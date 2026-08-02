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
    /// The most recent snapshot. Survives a failed refresh.
    public private(set) var inventory: InstalledInventory = .empty
    public private(set) var state: InstalledLoadState = .idle

    /// Why the inventory is empty, when that is the reason it is.
    public var absence: InstalledAbsence? {
        guard case .brewAbsent(let absence) = state else { return nil }
        return absence
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
            inventory = snapshot
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
        inventory = .empty
        state = .brewAbsent(absence)
    }

    private func vacate(_ token: Int) {
        guard inFlight?.token == token else { return }
        inFlight = nil
    }
}
