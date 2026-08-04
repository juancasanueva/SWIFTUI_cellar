import BrewProcess
import Catalog
import Foundation
import Observation

/// One submitted mutation, as the activity surfaces read it.
///
/// Every rule the SwiftUI views need is a computed property **here**, not in the
/// app target: which sentence to show, whether cancel is offered, what the copy
/// button copies, whether the log is truncated. That is what makes the views
/// presentational over rules proven in the `swift test` inner loop, and the
/// untested-by-design part layout only (design D4, D10).
@MainActor
@Observable
public final class ActivityItem: Identifiable {
    /// How many lines the log ring keeps.
    ///
    /// A `brew upgrade` over a large machine emits far more than this. The tail
    /// is the part that explains a failure, so the ring keeps the newest lines
    /// and says so rather than pretending it kept everything.
    public nonisolated static let logCapacity = 2_000

    /// Assigned at submission and never reassigned, so an observer can follow
    /// one operation across its whole lifetime (operation-activity OA1).
    public let id: UUID

    /// The runner's own id for this operation, once it has one.
    ///
    /// Separate from `id` because the item exists from the moment `submit`
    /// returns, which is strictly before the runner has been asked anything.
    /// Making `id` wait for it would mean handing back an item with no identity
    /// — or reassigning one, which is what OA1 forbids.
    internal var operationID: UUID?

    /// Set the moment a cancel is asked for, even if there is nothing to cancel
    /// yet, so a cancel racing the submission cannot be lost.
    internal var isCancelRequested = false

    /// The handle produced by **this item's own runner**, held for exactly as
    /// long as the item is cancellable and dropped in `settle(_:)`.
    ///
    /// Two things depend on that lifetime. Cancel is delivered to the process
    /// that actually exists, even after `brew` has been repointed or detached
    /// (design D10). And the execution layer's retention rule is expressed as
    /// ownership rather than as a timer: the runner may drop a terminal record
    /// only once no handle survives, and this is the last one (D6 R3). Holding
    /// it past `settle(_:)` would pin a record forever; dropping it earlier
    /// would make a live operation uncancellable.
    ///
    /// `@ObservationIgnored` because it is plumbing: no view reads it, and
    /// publishing it would wake every observer twice per operation.
    @ObservationIgnored internal var operation: AuthorizedMutationOperation?

    /// True between `submit` handing the command to `run(_:for:on:)` and that
    /// method obtaining — or failing to obtain — a handle.
    ///
    /// It is the difference between "there is nothing to cancel yet" and "there
    /// will never be anything to cancel". A cancel during the window is replayed
    /// by `run(_:for:on:)`, which guards at entry and again after start; a cancel
    /// outside it, with no handle, means no runner ever existed (design D10).
    @ObservationIgnored internal var isStartInFlight = false

    /// The typed command, erased to its projections. Everything displayed is
    /// rendered from this, never from bytes the subprocess wrote.
    ///
    /// Erased rather than generic because the item is *stored*, in an array the
    /// activity surfaces enumerate; a generic item would make that array
    /// impossible. `AnyBrewMutation` carries argv, verb, package identity,
    /// confirmation and invalidation scope — everything the surfaces and the
    /// terminal funnel read — and carries no path back to a concrete command
    /// (design D1).
    public let command: AnyBrewMutation

    /// The version move Cellar **intended** when it submitted this command.
    ///
    /// Captured here at submission rather than observed at the terminal, so the
    /// durable record cannot depend on whether a re-snapshot happened to land
    /// first (design D7). `nil` whenever either end is unknown: half a
    /// transition reads as data loss rather than as absence.
    @ObservationIgnored let versions: VersionTransition?
    @ObservationIgnored let refreshToken: MutationOperationToken?
    @ObservationIgnored let installationURL: URL?

    /// Where the queue says this operation is. Set by `OperationCenter` from
    /// the one `QueueSnapshot`, so the summary and the detail listing cannot
    /// disagree (OA5).
    public internal(set) var queuePhase: OperationSnapshot.Phase = .pending

    public private(set) var log: [LogLine] = []
    /// True once the ring has evicted at least one line.
    public private(set) var isLogTruncated = false

    /// The classified terminal outcome. `nil` until the operation settles;
    /// its presence *is* what "terminal" means for this item.
    public private(set) var outcome: MutationOutcome?

    init(
        id: UUID,
        command: some BrewMutating,
        versions: VersionTransition? = nil,
        refreshToken: MutationOperationToken? = nil,
        installationURL: URL? = nil
    ) {
        self.id = id
        self.command = AnyBrewMutation(command)
        self.versions = versions
        self.refreshToken = refreshToken
        self.installationURL = installationURL
    }

    // MARK: - What the views render

    /// The argv, verbatim, in every state.
    public var arguments: [String] { command.arguments }

    /// The command as a human reads it.
    public var displayCommand: String { command.displayCommand }

    /// What the copy affordance produces. Identical in every state, because it
    /// is the same pure projection of the same typed command (OA2).
    public var copyText: String { command.displayCommand }

    /// The package this operation acts on, when it acts on one. `upgradeAll`
    /// names none and no non-package family ever does, which is why this is
    /// optional rather than defaulted.
    public var packageID: PackageID? { command.packageID }

    /// The one sentence to show for the current state.
    public var message: String {
        outcome?.message(for: command) ?? inFlightMessage
    }

    /// A short label for the collapsed bar.
    public var statusLabel: String {
        outcome?.summaryLabel ?? (isRunning ? "Running" : "Queued")
    }

    private var inFlightMessage: String {
        isRunning ? "Running \(displayCommand)" : "Queued behind another operation."
    }

    // MARK: - Phase

    /// Terminal is decided by the **outcome**, not by the queue: the operation
    /// is only finished once its exit has been classified, so a view can never
    /// see "terminal with no outcome" for even one frame.
    public var isTerminal: Bool { outcome != nil }

    public var isRunning: Bool { outcome == nil && queuePhase == .running }

    public var isPending: Bool { outcome == nil && queuePhase == .pending }

    /// Cancel is offered from pending and running, and nowhere else
    /// (operation-activity OA4).
    public var isCancellable: Bool { !isTerminal }

    /// Whether this command must be confirmed before it is submitted at all.
    public var requiresConfirmation: Bool { command.requiresConfirmation }

    /// Every control the queue exposes for this item.
    ///
    /// Deliberately an enumerable list rather than a set of booleans, so
    /// "cancel is present and no reorder, move or remove control is" is a claim
    /// a test can make about the whole surface (product Q6; I2 stays immutable).
    public enum Control: Sendable, Equatable, CaseIterable {
        case cancel
        case copyCommand
        /// Never produced. Present so the absence is assertable rather than
        /// merely unwritten.
        case moveUp
        case moveDown
        case remove
    }

    public var controls: [Control] {
        isCancellable ? [.cancel, .copyCommand] : [.copyCommand]
    }

    // MARK: - Mutation, from the centre only

    /// Appends one line, evicting the oldest when the ring is full.
    func append(_ line: LogLine) {
        if log.count == Self.logCapacity {
            log.removeFirst()
            isLogTruncated = true
        }
        log.append(line)
    }

    func settle(_ outcome: MutationOutcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        // Terminal, so nothing can be cancelled and nothing can still ask the
        // runner about it: releasing here is what makes the execution layer's
        // record removable at all (design D6 R3).
        operation = nil
    }
}
