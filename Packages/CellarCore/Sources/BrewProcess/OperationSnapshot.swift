import Foundation

/// One operation as an observer sees it.
///
/// Every field is **derived** from state the runner already keeps for its own
/// purposes. In particular the phase is computed from `process` and
/// `resolvedExit` rather than stored beside them, because a stored phase is a
/// second source of truth and a second source of truth eventually disagrees
/// with the first (design D3).
public struct OperationSnapshot: Sendable, Identifiable, Equatable {
    /// Assigned at submission, stable for the operation's whole lifetime, and
    /// distinct for two otherwise identical submissions (brew-execution BE1).
    public let id: UUID

    /// The argv this operation was submitted with, verbatim. "Copy command"
    /// reads this, and it is the same vector that reached the process seam.
    public let command: BrewCommand

    /// Where the operation is in its life.
    public enum Phase: Sendable, Equatable {
        /// Gated behind an earlier mutation. Nothing has been spawned, so
        /// cancelling costs nothing and changes nothing on disk.
        case pending
        /// Spawned and not yet terminal.
        case running
        /// Finished, however it finished. A cancelled run is a `BrewExit`
        /// reason, not a failure (M1 D3).
        case terminal(BrewExit, fault: BrewProcessError?)
        /// Authorization refused the mutation before a process was launched.
        case authorizationDenied(MutationLaunchDenial)

        public var isTerminal: Bool {
            switch self {
            case .terminal, .authorizationDenied: true
            case .pending, .running: false
            }
        }

        /// The terminal exit, when there is one.
        public var exit: BrewExit? {
            guard case .terminal(let exit, _) = self else { return nil }
            return exit
        }

        /// The out-of-band fault, when there was one. `nil` for every normal
        /// run, including a cancelled one.
        public var fault: BrewProcessError? {
            guard case .terminal(_, let fault) = self else { return nil }
            return fault
        }
    }

    public let phase: Phase

    public init(id: UUID, command: BrewCommand, phase: Phase) {
        self.id = id
        self.command = command
        self.phase = phase
    }
}

/// Every operation the runner is tracking, in submission order.
///
/// Ordered by the submission ordinal rather than by the dictionary that holds
/// the records, so "the order brew will actually run them" is answerable
/// (operation-activity OA1).
public struct QueueSnapshot: Sendable, Equatable {
    public let operations: [OperationSnapshot]

    public init(operations: [OperationSnapshot]) {
        self.operations = operations
    }

    /// The one operation currently spawned, if any. At most one *mutation* runs
    /// at a time; a read-only query may run beside it.
    public var running: [OperationSnapshot] {
        operations.filter { $0.phase == .running }
    }

    public var pending: [OperationSnapshot] {
        operations.filter { $0.phase == .pending }
    }

    /// Whether any work is in flight — pending or running.
    public var isBusy: Bool {
        operations.contains { !$0.phase.isTerminal }
    }
}
