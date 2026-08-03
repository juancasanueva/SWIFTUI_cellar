import BrewProcess
import Foundation
import Observation

/// What the store is currently able to say about the services list.
public enum ServicesLoadState: Sendable, Equatable {
    /// Nothing has been asked yet.
    case idle
    /// An acquisition is in flight. The resident list stays readable.
    case loading
    /// The resident list is a real snapshot.
    case loaded
    /// There is no brew to ask. Not a failure.
    case brewAbsent(InstalledAbsence)
    /// The last acquisition failed. The previous list is still resident.
    case failed(ServicesError)
}

/// The services list as the UI sees it.
///
/// `InstalledStore`'s shape over a different projection, and deliberately so:
/// the three properties M2-0 paid for hold here for the same reasons, and one
/// of them matters *more* here because this store is polled every five seconds.
///
/// - the single-flight slot is keyed by the **request** plus an invalidation
///   mark, so a poll tick cannot start a second probe of the same thing and a
///   refresh owed after a mutation cannot be answered by a probe that ran
///   before it;
/// - adoption is **ordinal-guarded**, so a slow answer overtaken by a fast one
///   is discarded rather than installed on top of fresher data;
/// - a failed refresh keeps the last good list. A transient brew lock must not
///   empty the services list — at a 5-second cadence the user would watch it
///   blink.
///
/// **It opens no `ModelContainer` and persists nothing.** Service state is
/// launchd's truth, re-read every poll; there is no offline copy worth keeping
/// and nothing a user could lose. W3's "no second container is ever opened"
/// invariant therefore holds *a fortiori*, and
/// `LocalStoresTests > oneContainerServesBothStores` remains its assertion.
/// This is a deliberate, recorded deviation from the proposal's "`ServicesStore`
/// joins `LocalStores`".
@MainActor
@Observable
public final class ServicesStore {
    /// The most recent list. Survives a failed refresh.
    public private(set) var services: [ServiceRecord] = []
    public private(set) var state: ServicesLoadState = .idle

    /// The selected service's detail, when one is selected and its probe
    /// answered. Fetched lazily and keyed on selection — never on a poll tick.
    public private(set) var detail: ServiceDetail?
    /// The selected service's name, whether or not its detail has arrived.
    public private(set) var selected: String?

    /// Why the list is empty, when that is the reason it is.
    ///
    /// `InstalledAbsence` rather than a services-specific twin: the reason brew
    /// is unusable is a property of brew, not of what was being asked, and
    /// reusing it is what makes SM11's "the same read-only guidance the rest of
    /// the app surfaces" literally true rather than merely similar.
    public var absence: InstalledAbsence? {
        guard case .brewAbsent(let absence) = state else { return nil }
        return absence
    }

    @ObservationIgnored private let source: any ServicesPayloadSourcing
    @ObservationIgnored private let detailSource: any ServiceDetailPayloadSourcing

    /// The one acquisition that may be joined, the token that owns it, the
    /// request it was started for, and the freshness mark it started at.
    private struct InFlightRefresh {
        let token: Int
        let request: URL
        let mark: Int
        let task: Task<Result<[ServiceRecord], ServicesError>, Never>
    }

    @ObservationIgnored private var inFlight: InFlightRefresh?
    @ObservationIgnored private var nextToken = 0
    /// The newest ordinal that actually reached `services`.
    @ObservationIgnored private var installedSequence = 0
    /// Monotonic count of "what launchd is running changed since you looked".
    @ObservationIgnored private var invalidationCount = 0
    /// The installation the last refresh ran against, so a selection can probe
    /// detail without being handed one again.
    @ObservationIgnored private var installation: BrewInstallation?

    public init(
        source: any ServicesPayloadSourcing = ServicesListPayloadSource(),
        detailSource: any ServiceDetailPayloadSourcing = ServiceInfoPayloadSource()
    ) {
        self.source = source
        self.detailSource = detailSource
    }

    // MARK: - Freshness

    /// Records that the resident list — and anything currently in flight — may
    /// already be stale. Spawns nothing.
    public func invalidate() {
        invalidationCount += 1
    }

    // MARK: - Refreshing

    /// Refreshes from whatever detection currently reports.
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

    /// Takes a fresh list, or clears when there is no brew to ask.
    ///
    /// Never throws and never blocks: the caller is a poll tick, and a tick
    /// that could throw would have to be wrapped at every site.
    public func refresh(using installation: BrewInstallation?) async {
        guard let installation else {
            clear(to: .notInstalled(.standard))
            return
        }
        self.installation = installation

        let request = installation.executableURL
        let outcome: Result<[ServiceRecord], ServicesError>
        let token: Int

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
                // joiner resumes.
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
        from source: any ServicesPayloadSourcing,
        using installation: BrewInstallation
    ) async -> Result<[ServiceRecord], ServicesError> {
        do {
            let payload = try await source.payload(using: installation)
            return .success(try await ServicesDecoder.decode(payload))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Adoption

    private func adopt(
        _ outcome: Result<[ServiceRecord], ServicesError>,
        token: Int
    ) {
        guard token > installedSequence else { return }
        installedSequence = token

        switch outcome {
        case .success(let snapshot):
            // One main-actor assignment, so there is no window in which a row
            // shows a status from the previous list beside one from this
            // (SM9: a stale status is never retained).
            services = snapshot
            state = .loaded
        case .failure(let error):
            state = .failed(error)
        }
    }

    /// Clears to an empty list with guidance, spawning nothing.
    ///
    /// The slot is vacated **before** the ordinal is bumped, for the reason
    /// `InstalledStore` documents: leaving it resident strands the store, since
    /// a later refresh joins the pre-clear acquisition whose answer the ordinal
    /// guard then discards.
    private func clear(to absence: InstalledAbsence) {
        inFlight?.task.cancel()
        inFlight = nil

        nextToken += 1
        installedSequence = nextToken
        services = []
        detail = nil
        state = .brewAbsent(absence)
    }

    private func vacate(_ token: Int) {
        guard inFlight?.token == token else { return }
        inFlight = nil
    }

    // MARK: - Detail (SM2)

    /// Selects a service and fetches its detail, or clears the selection.
    ///
    /// The probe runs **here and nowhere else**, which is what makes "a poll
    /// tick fetches no detail" a property of the design rather than of the
    /// current call sites: `refresh` has no path to `detailSource`.
    public func select(_ name: String?) async {
        selected = name
        detail = nil

        guard let name,
              let installation,
              // The same argv gate the mutating commands use. A name that could
              // not survive composition is never probed.
              let target = ServiceTarget(name: name)
        else { return }

        do {
            let payload = try await detailSource.payload(using: installation, naming: target)
            let details = try await ServicesDecoder.decodeDetails(payload)
            // Still the selection this probe was started for. A user clicking
            // through the list faster than brew answers must not be shown the
            // previous service's log paths.
            guard selected == name else { return }
            detail = details.first { $0.name == name } ?? details.first
        } catch {
            // A detail probe that fails costs the detail pane and nothing else:
            // the list is not a failure because one service would not describe
            // itself.
            detail = nil
        }
    }
}
