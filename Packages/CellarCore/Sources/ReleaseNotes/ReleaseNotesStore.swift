import Catalog
import Foundation
import Observation

// MARK: - State

/// What one package's release-notes surface is showing.
///
/// `lastGood` is carried by the state rather than kept beside it, because
/// "loading" and "failed" both need it and neither is a state a view should have
/// to cross-reference something else to render. It is what makes a failed reload
/// leave a note the user is reading on screen instead of blanking it.
public enum ReleaseNotesState: Sendable, Hashable {
    case idle
    case loading(lastGood: ReleaseNotesOutcome?)
    case loaded(ReleaseNotesOutcome)
    case failed(ReleaseNotesFailure, lastGood: ReleaseNotesOutcome?)

    /// The settled answer, and `nil` while there is not one.
    public var outcome: ReleaseNotesOutcome? {
        switch self {
        case .loaded(let outcome): outcome
        case .failed(let failure, _): .unavailable(failure)
        case .idle, .loading: nil
        }
    }

    /// The last answer worth showing, whatever has happened since.
    public var lastGood: ReleaseNotesOutcome? {
        switch self {
        case .loaded(let outcome): outcome
        case .loading(let lastGood), .failed(_, let lastGood): lastGood
        case .idle: nil
        }
    }

    public var failure: ReleaseNotesFailure? {
        switch self {
        case .failed(let failure, _): failure
        case .loaded(let outcome): outcome.failure
        case .idle, .loading: nil
        }
    }

    public var isLoading: Bool {
        if case .loading = self { true } else { false }
    }
}

// MARK: - The store

/// Owns release-notes work for the whole app: one package at a time, one request
/// per click, and nothing that could be started by anything but a click.
///
/// ## The shape is the guard
///
/// `load` takes a **single** `PackageID`. There is no array form, no
/// `loadAll`, no prefetch, and no method a `.task` modifier would find natural to
/// call. That is not tidiness: a plural entry point is all it would take for a
/// list render to become thirty requests, and the surest way to prevent that is
/// for the call not to exist. `OperationCenterBulk` cannot see this type at all —
/// it lives in `BrewClient`, which this target does not depend on and which does
/// not depend on this target.
///
/// ## Why the clock is injected
///
/// Every TTL decision is made against a `now` this store is handed, so cache
/// boundaries are testable synchronously and a test never sleeps to cross one.
/// The `SecurityConsentPreference` shape, not a new date-provider protocol.
@MainActor
@Observable
public final class ReleaseNotesStore {
    public private(set) var states: [PackageID: ReleaseNotesState] = [:]
    /// What GitHub last said about the request budget, from a success as well as
    /// from a refusal — so a surface can warn before the wall rather than only
    /// after it.
    public private(set) var rateLimit: RateLimitStatus?

    @ObservationIgnored private let source: any ReleaseNotesSource
    @ObservationIgnored private let cache: ReleaseNotesCache
    @ObservationIgnored private let consent: any ReleaseNotesConsentProviding
    @ObservationIgnored private let credentials: (any ReleaseNotesCredentialStoring)?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let pageSize: Int

    @ObservationIgnored private var tasks: [PackageID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [PackageID: UUID] = [:]

    public init(
        source: any ReleaseNotesSource,
        cache: ReleaseNotesCache,
        consent: any ReleaseNotesConsentProviding,
        credentials: (any ReleaseNotesCredentialStoring)? = nil,
        pageSize: Int = GitHubReleaseNotesSource.defaultPageSize,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.source = source
        self.cache = cache
        self.consent = consent
        self.credentials = credentials
        self.pageSize = pageSize
        self.now = now
    }

    public func state(for id: PackageID) -> ReleaseNotesState { states[id] ?? .idle }

    // MARK: - One package, one click

    /// Starts release-notes work for one package at one version.
    ///
    /// Called only from an explicit user action. A second call for the same
    /// package cancels the first and mints a new generation, so a result that
    /// arrives from superseded work is dropped rather than overwriting a fresher
    /// one.
    public func load(_ id: PackageID, version: String, candidates: RepositoryCandidates) {
        tasks[id]?.cancel()
        let generation = UUID()
        generations[id] = generation
        states[id] = .loading(lastGood: state(for: id).lastGood)

        tasks[id] = Task { [weak self] in
            guard let self else { return }
            let settlement = await self.settle(version: version, candidates: candidates)
            self.adopt(settlement, for: id, generation: generation)
        }
    }

    /// Stops in-flight work and leaves the surface at the last good value.
    ///
    /// The generation is rotated as well as the task cancelled, so a result
    /// already past its cancellation check still cannot land.
    public func cancel(_ id: PackageID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        generations[id] = UUID()
        let lastGood = state(for: id).lastGood
        states[id] = lastGood.map { .loaded($0) } ?? .idle
    }

    /// Joins the in-flight load for one package, if there is one.
    ///
    /// Exposed for tests, which must be able to await a settlement without
    /// sleeping on a wall clock. It grants no ability a caller does not already
    /// have: the work is already running and its result is already published.
    public func waitForLoad(_ id: PackageID) async {
        await tasks[id]?.value
    }

    // MARK: - Settling

    private struct Settlement: Sendable {
        let outcome: ReleaseNotesOutcome
        let rateLimit: RateLimitStatus?
    }

    /// The whole flow, off the main actor's decision-making but on its actor:
    /// resolve, read the cache, authorise, fetch, match, write back.
    ///
    /// Resolution comes **first** and costs nothing, so a package whose
    /// repository cannot be worked out never reaches consent, the Keychain or the
    /// network.
    private func settle(
        version: String,
        candidates: RepositoryCandidates
    ) async -> Settlement {
        guard let resolved = GitHubRepositoryResolver.resolve(candidates) else {
            return Settlement(
                outcome: .unresolvableRepository(triedSources: candidates.triedSources),
                rateLimit: nil
            )
        }

        let key = ReleaseNotesCacheKey(repository: resolved.repository, version: version)
        let moment = now()

        if let fresh = await cache.entry(for: key, now: moment) {
            return Settlement(outcome: fresh.outcome, rateLimit: nil)
        }

        // The gate. Nothing above this line left the machine; nothing below it
        // runs without a dated grant.
        let grant: ReleaseNotesGrant
        do {
            grant = try await consent.currentConsent().authorise()
        } catch {
            return Settlement(outcome: .unavailable(.blockedPendingConsent), rateLimit: nil)
        }

        // A token that cannot be read is a *missing* token: the request goes
        // unauthenticated rather than failing over a credential the feature works
        // without.
        let token = (try? await credentials?.personalAccessToken()) ?? nil
        let stale = await cache.staleEntry(for: key)

        do {
            let fetched = try await source.releases(
                for: resolved.repository,
                validators: stale?.etag.map { ConditionalValidators(etag: $0) },
                token: token,
                grant: grant
            )
            return await adopt(fetched, resolved: resolved, version: version, key: key, stale: stale, now: moment)
        } catch {
            return Settlement(
                outcome: .unavailable(error),
                rateLimit: error.rateLimit
            )
        }
    }

    private func adopt(
        _ fetched: ReleaseFetchOutcome,
        resolved: ResolvedRepository,
        version: String,
        key: ReleaseNotesCacheKey,
        stale: ReleaseNotesCacheEntry?,
        now moment: Date
    ) async -> Settlement {
        switch fetched {
        case .notModified(let rateLimit):
            // The validator still matches, so the cached answer is still the
            // answer. Its timestamp is refreshed; its body was never resent.
            guard let stale else {
                return Settlement(outcome: .unavailable(.malformedPayload), rateLimit: rateLimit)
            }
            try? await cache.refresh(key, etag: stale.etag, now: moment)
            return Settlement(outcome: stale.outcome, rateLimit: rateLimit)

        case .fetched(let releases, let etag, let rateLimit):
            let outcome = Self.outcome(
                from: releases,
                resolved: resolved,
                version: version,
                packageName: key.repository.name,
                pageSize: pageSize
            )
            try? await cache.record(outcome, for: key, etag: etag, now: moment)
            return Settlement(outcome: outcome, rateLimit: rateLimit)
        }
    }

    /// The three answers one response can carry.
    ///
    /// An empty list is "publishes no releases"; a non-empty list with no
    /// matching tag is "no release matches this version", **qualified** by whether
    /// the page filled its bound. That last distinction is why the list endpoint
    /// is used at all: the per-tag endpoint answers 404 for both.
    private nonisolated static func outcome(
        from releases: [GitHubRelease],
        resolved: ResolvedRepository,
        version: String,
        packageName: String,
        pageSize: Int
    ) -> ReleaseNotesOutcome {
        guard releases.isEmpty == false else {
            return .repositoryPublishesNoReleases(resolved)
        }
        if let matched = ReleaseTagMatcher.match(
            version: version, packageName: packageName, in: releases
        ) {
            return .notes(resolved, matched)
        }
        return .noReleaseMatchesVersion(
            resolved,
            version: version,
            inspected: releases.count,
            pageWasFull: releases.count >= pageSize
        )
    }

    // MARK: - Publishing

    private func adopt(_ settlement: Settlement, for id: PackageID, generation: UUID) {
        // A result from superseded work is dropped, not published.
        guard generations[id] == generation else { return }
        tasks[id] = nil

        if let rateLimit = settlement.rateLimit, rateLimit.isEmpty == false {
            self.rateLimit = rateLimit
        }

        if case .unavailable(let failure) = settlement.outcome {
            // Last-good survival: a failed reload never blanks a note the user is
            // already reading.
            states[id] = .failed(failure, lastGood: state(for: id).lastGood)
        } else {
            states[id] = .loaded(settlement.outcome)
        }
    }
}
