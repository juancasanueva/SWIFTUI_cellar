import BrewProcess
import Catalog
import Foundation
import Observation

/// Why the inventory is empty, and what the user can do about it.
///
/// Absence is guidance, never an error: catalog browse and search are unaffected
/// by it, and there is nothing here a user can "retry" (installed-inventory II9).
public enum InstalledAbsence: Sendable, Equatable {
    /// No Homebrew anywhere.
    case notInstalled(BrewInstallGuidance)
    /// A configured path that exists but failed validation, and exactly why.
    case configuredPathRejected(URL, BrewValidationError)
    /// A configured path that is no longer on disk.
    case configuredPathMissing(URL)

    /// The install one-liner, present exactly when there is nothing to fix.
    public var installGuidance: BrewInstallGuidance? {
        guard case .notInstalled(let guidance) = self else { return nil }
        return guidance
    }

    /// Why the configured path was rejected, when one was.
    public var rejectionReason: BrewValidationError? {
        guard case .configuredPathRejected(_, let reason) = self else { return nil }
        return reason
    }
}

/// What the store is currently able to say about the inventory.
public enum InstalledLoadState: Sendable, Equatable {
    /// Nothing has been asked yet.
    case idle
    /// An acquisition is in flight. The resident inventory stays readable.
    case loading
    /// The resident inventory is a real snapshot.
    case loaded
    /// There is no brew to ask. Not a failure.
    case brewAbsent(InstalledAbsence)
    /// The last acquisition failed. The previous inventory is still resident.
    case failed(InstalledInventoryError)
}

/// The installed inventory as the UI sees it.
///
/// The single main-isolated crossing point in this module: acquisition and
/// decoding both run below it, in SwiftPM's default `nonisolated` world.
///
/// Two properties are worth stating explicitly, because both are corrections
/// M2-0 paid for:
///
/// - the single-flight slot is keyed by the **request** — the `brew` this
///   refresh was started for — so repointing the executable cannot be answered
///   with a snapshot of the previous installation (design D6);
/// - adoption is **ordinal-guarded**, so a slow large snapshot overtaken by a
///   fast one is discarded rather than installed on top of fresher data
///   (M2-0 D1).
@MainActor
@Observable
public final class InstalledStore {
    /// The most recent snapshot, merged across every contributing source.
    ///
    /// Recomposed rather than assigned: `brewInventory` and `contributions` are
    /// each replaced only by their own source, and this is what they add up to.
    public private(set) var inventory: InstalledInventory = .empty
    public private(set) var state: InstalledLoadState = .idle

    /// The Homebrew half, kept apart from the merged view.
    ///
    /// `state`, `absence` and every refresh rule below describe **Homebrew**, and
    /// they stay exactly as accurate as they were: a brew failure or absence is
    /// still a fact about brew alone. Splitting the storage is what lets that
    /// remain true while `inventory` answers for both.
    @ObservationIgnored private var brewInventory: InstalledInventory = .empty

    /// Rows contributed by every source other than Homebrew.
    ///
    /// Keyed by source, so each one's rows are replaced only by that source's own
    /// next successful acquisition (installed-inventory: one source's failure
    /// does not evict the other). A brew acquisition that failed must not empty
    /// the npm rows, and a `clear` for a missing Homebrew must not either — the
    /// npm packages are still installed, and saying otherwise would report a mass
    /// uninstall that did not happen.
    @ObservationIgnored private var contributions: [PackageSource: [InstalledPackage]] = [:]

    /// Why the inventory is empty, when that is the reason it is.
    public var absence: InstalledAbsence? {
        guard case .brewAbsent(let absence) = state else { return nil }
        return absence
    }

    /// Whether the merged inventory means anything yet.
    ///
    /// Used to be "Homebrew is not absent", read directly at the call site. With
    /// a second source that is wrong in a way nothing would catch: an npm-only
    /// machine has a real inventory, and reporting it unavailable collapses
    /// every installed-state filter to `all` over rows that are genuinely there.
    ///
    /// It lives here rather than as an expression in the view so it is one rule
    /// with one test, and so the next source does not have to find every place
    /// the old expression was written out.
    public var hasAnyInventory: Bool {
        absence == nil || contributions.values.contains { $0.isEmpty == false }
    }

    @ObservationIgnored private let source: any InstalledPayloadSourcing

    /// The one acquisition that may be joined, the token that owns it, the
    /// request it was started for, and the freshness mark it started at.
    private struct InFlightRefresh {
        let token: Int
        let request: URL
        /// The value of `invalidationCount` when this acquisition started.
        let mark: Int
        let task: Task<Result<InstalledInventory, InstalledInventoryError>, Never>
    }

    @ObservationIgnored private var inFlight: InFlightRefresh?
    @ObservationIgnored private var nextToken = 0
    /// The newest ordinal that actually reached `inventory`.
    @ObservationIgnored private var installedSequence = 0
    /// Monotonic count of "what is installed changed since you last looked".
    @ObservationIgnored private var invalidationCount = 0

    // MARK: - Freshness

    /// Records that the resident inventory — and anything currently in flight —
    /// may already be stale.
    ///
    /// Called on every external change signal and at every mutation terminal.
    /// It spawns nothing: it only moves the mark that decides whether the next
    /// refresh is entitled to join the acquisition already running (design D8b).
    public func invalidate() {
        invalidationCount += 1
    }

    public init(source: any InstalledPayloadSourcing = BrewInfoPayloadSource()) {
        self.source = source
    }

    // MARK: - Refreshing

    /// Refreshes from whatever detection currently reports.
    ///
    /// The overload exists so the *reason* an installation is missing survives
    /// into the guidance: `refresh(using: nil)` cannot tell "never installed"
    /// from "the path you configured is not executable", and II9 requires that
    /// distinction to be readable.
    public func refresh(for detection: BrewDetectionState) async {
        switch detection {
        case .detected(let installation):
            await refresh(using: installation)
        case .absent:
            clear(to: .notInstalled(.standard))
        case .invalid(let url, let reason):
            clear(to: .configuredPathRejected(url, reason))
        case .configuredPathMissing(let url):
            clear(to: .configuredPathMissing(url))
        }
    }

    /// Takes a fresh snapshot of `installation`, or clears when there is none.
    ///
    /// Never throws and never blocks: a caller that cannot act on a failure
    /// should not have to catch one.
    public func refresh(using installation: BrewInstallation?) async {
        guard let installation else {
            clear(to: .notInstalled(.standard))
            return
        }

        let request = installation.executableURL
        let outcome: Result<InstalledInventory, InstalledInventoryError>
        let token: Int

        // Joining requires both conditions. The request key is M2-1 D6's and is
        // kept, not replaced: it stops a snapshot of the previous `brew` from
        // answering a refresh of the new one. The mark is the addition: an
        // acquisition that started before the newest invalidation observed the
        // world before the change it is being asked about (design D8b).
        if let current = inFlight,
           current.request == request,
           current.mark >= invalidationCount {
            token = current.token
            outcome = await current.task.value
        } else {
            nextToken += 1
            token = nextToken
            state = .loading

            let acquisition = Task { [source, weak self] in
                // Vacated from inside the body, so the slot is empty before any
                // joiner resumes: a settled acquisition can never be handed back
                // as a fresh answer (M2-0 D3).
                defer { self?.vacate(token) }
                return await Self.snapshot(from: source, using: installation)
            }
            inFlight = InFlightRefresh(
                token: token,
                request: request,
                mark: invalidationCount,
                task: acquisition
            )
            outcome = await acquisition.value
        }

        adopt(outcome, token: token)
    }

    /// One acquisition, decoded off the main actor.
    private static func snapshot(
        from source: any InstalledPayloadSourcing,
        using installation: BrewInstallation
    ) async -> Result<InstalledInventory, InstalledInventoryError> {
        do {
            let payload = try await source.payload(using: installation)
            return .success(try await InstalledDecoder.decode(payload))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Adoption

    /// Installs an outcome, if it is still the newest one asked for.
    private func adopt(
        _ outcome: Result<InstalledInventory, InstalledInventoryError>,
        token: Int
    ) {
        // Tokens are handed out in request order, so a token that no longer
        // leads has been overtaken. Discarding it here is what stops a slow
        // snapshot from landing on top of a fresher one.
        guard token > installedSequence else { return }
        installedSequence = token

        switch outcome {
        case .success(let snapshot):
            // One main-actor assignment: there is no window in which the store
            // is between inventories.
            brewInventory = snapshot
            recompose()
            state = .loaded
        case .failure(let error):
            // The last good inventory stays resident — the catalog's discipline.
            // A transient brew lock must not empty the user's list.
            state = .failed(error)
        }
    }

    /// Clears to an empty inventory with guidance, spawning nothing.
    ///
    /// The slot is vacated **before** the ordinal is bumped. Leaving it resident
    /// stranded the store: a refresh requested afterwards joined the pre-clear
    /// acquisition, whose answer the ordinal guard then discarded, so the
    /// inventory stayed empty even after a valid refresh (design D8c). The
    /// cancellation is belt-and-braces — the ordinal guard still discards any
    /// late answer — but the vacating is load-bearing.
    private func clear(to absence: InstalledAbsence) {
        inFlight?.task.cancel()
        inFlight = nil

        nextToken += 1
        installedSequence = nextToken
        // Homebrew's rows go; every other source's stay. There is no Homebrew to
        // ask, which says nothing at all about what npm has installed.
        brewInventory = .empty
        recompose()
        state = .brewAbsent(absence)
    }

    private func vacate(_ token: Int) {
        guard inFlight?.token == token else { return }
        inFlight = nil
    }

    // MARK: - Other sources

    /// Installs one source's rows, replacing whatever it contributed before.
    ///
    /// Deliberately synchronous and unguarded by the ordinal: the brew ordinal
    /// exists because two `brew info` acquisitions can overlap and land out of
    /// order, and a caller here is handing over an already-decoded result rather
    /// than starting a race. The npm store owns its own ordering, on its own
    /// cadence, and giving the two sources one shared sequence would let a slow
    /// brew snapshot discard a fresh npm adoption for no reason.
    ///
    /// An empty array is a legitimate result — a machine with no globals — and
    /// means exactly that. It is not the same act as `clearContributions(from:)`,
    /// which says the source is gone.
    public func adopt(_ packages: [InstalledPackage], from source: PackageSource) {
        precondition(
            source != .homebrew,
            "Homebrew's rows come from its own acquisition, not from a contribution"
        )
        contributions[source] = packages
        recompose()
    }

    /// Removes a source's rows entirely, because the source is off or gone.
    public func clearContributions(from source: PackageSource) {
        guard contributions.removeValue(forKey: source) != nil else { return }
        recompose()
    }

    /// The one merged inventory, rebuilt from its parts.
    ///
    /// `InstalledInventory.init` sorts and builds both membership sets, so
    /// ordering and `outdatedIDs` are decided in exactly one place for both
    /// sources — which is why the six existing readers of `outdatedIDs` need no
    /// change at all.
    ///
    /// The skipped-record count stays Homebrew's: it counts records *brew's
    /// payload* carried and this build could not read, and folding another
    /// source into it would make a number that names one payload describe two.
    private func recompose() {
        guard contributions.isEmpty == false else {
            inventory = brewInventory
            return
        }

        // Sorted by source so the input order is stable; the inventory sorts the
        // rows itself, but a stable input keeps two equal rows from swapping.
        let contributed = contributions
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .flatMap(\.value)

        inventory = InstalledInventory(
            packages: brewInventory.packages + contributed,
            skippedRecordCount: brewInventory.skippedRecordCount
        )
    }
}
