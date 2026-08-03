/// How a `brew` invocation ended.
///
/// A non-zero status is **not** an error (design decision D3): brew uses exit
/// codes semantically, and a cancelled operation must report *cancelled* rather
/// than failure. Only launch faults and an unresponsive cancellation throw.
public struct BrewExit: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        /// The process ran to completion and returned `status`.
        case exited
        /// The process stopped because Cellar cancelled it with `signal`.
        case cancelled(signal: Int32)
        /// The process was terminated by a signal Cellar did not send.
        case signalled(Int32)
        /// No process ever existed for the identity that was asked about: it was
        /// never submitted, or its record has already been retired. Declared
        /// here rather than in an extension because Swift has no way to add an
        /// enum case from outside its declaration.
        case unknownOperation
    }

    /// The process exit status, or `128 + signal` when it was signalled.
    public let status: Int32

    /// Why the process stopped.
    public let reason: Reason

    public init(status: Int32, reason: Reason) {
        self.status = status
        self.reason = reason
    }

    /// True only for a normal termination with status 0.
    public var isSuccess: Bool {
        reason == .exited && status == 0
    }

    /// True when Cellar cancelled the operation.
    public var isCancelled: Bool {
        if case .cancelled = reason { return true }
        return false
    }
}

extension BrewExit {
    /// The answer for an identity the execution layer does not know.
    ///
    /// `-1` cannot collide with a real terminal status: a wait status is 0–255
    /// and a signalled one is `128 + n`. Paired with a reason of
    /// `.unknownOperation`, `isSuccess` — which requires `.exited` *and* a zero
    /// status — makes the fabricated success unrepresentable rather than merely
    /// unobserved (brew-execution, design D8).
    public static let unknownOperation = BrewExit(status: -1, reason: .unknownOperation)
}
