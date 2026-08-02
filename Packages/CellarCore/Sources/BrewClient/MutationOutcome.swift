import BrewProcess
import Foundation

// MARK: - Threat response: untrusted subprocess payload as classification input
//
// `classify` reads brew's own prose to decide which sentence the user is shown.
// That is only acceptable because of two properties, and both are pinned by
// tests rather than argued (design D5):
//
// 1. **Classification changes only the message.** It never triggers a retry,
//    never escalates a privilege, never composes an argv, and never suppresses
//    the forced re-snapshot a terminal outcome owes. So a false positive is a
//    wrong sentence next to the real log, and a false negative degrades to
//    `.failed` with that same log verbatim and untruncated on screen.
// 2. **Nothing is parsed *out of* the payload.** brew's lock message names the
//    invocation that was blocked, not the process holding the lock (live probe,
//    brew 6.0.14), so presenting a holder parsed from it would be a confident
//    lie. Every message this type renders is built from Cellar's own typed
//    command, never from bytes the subprocess wrote.
//
// Matching is confined to the last 20 `.stderr` lines: brew writes diagnostics
// there, so a package echoing prose on stdout cannot change what the user is
// told, and a multi-megabyte log costs a bounded scan.

/// How one mutation ended, as the user needs to understand it.
public enum MutationOutcome: Sendable, Equatable {
    /// Exit 0.
    case succeeded
    /// A non-zero exit matching no known signature. The log is the explanation.
    case failed(status: Int32)
    /// Homebrew is locked by something outside Cellar (live-probed).
    case busy
    /// The command needs privileges Cellar will not acquire.
    case needsPrivileges
    /// Cellar cancelled it, and it stopped.
    case cancelled
    /// Cellar cancelled it, brew ignored both signals, and it is still running
    /// outside Cellar. Mapped from `BrewProcessError.cancelledUnresponsive`;
    /// SIGKILL is never an option (M1 D4).
    case abandoned(after: Duration)
    /// The process never started.
    case launchFailed

    // MARK: - Classification

    /// How many trailing stderr lines are scanned for a signature.
    ///
    /// brew puts its diagnosis in the last few lines; twenty is generous for
    /// that and bounded for a log measured in megabytes.
    static let tailLength = 20

    /// Decides the outcome from the terminal facts and the output tail.
    ///
    /// Pure, total, and ordered so the cheap structural facts win over prose:
    /// a fault, a cancellation and a zero exit are all decided before a single
    /// byte of subprocess output is examined.
    public static func classify(
        exit: BrewExit,
        fault: BrewProcessError?,
        log: [LogLine]
    ) -> MutationOutcome {
        if let fault {
            switch fault {
            case .cancelledUnresponsive(let grace):
                return .abandoned(after: grace)
            case .executableUnavailable, .launchFailed:
                return .launchFailed
            }
        }

        if exit.isCancelled { return .cancelled }
        if exit.isSuccess { return .succeeded }

        // Only now, and only on stderr.
        let tail = log
            .filter { $0.stream == .stderr }
            .suffix(tailLength)
            .map(\.text)

        if tail.contains(where: Signature.isLock) { return .busy }
        if tail.contains(where: Signature.isPrivilege) { return .needsPrivileges }

        return .failed(status: exit.status)
    }

    /// The phrases brew emits, and the only bytes of the payload this module
    /// ever looks at. Nothing is captured, extracted or echoed from them.
    private enum Signature {
        /// Live-probed on brew 6.0.14 (exit 1). Either phrase alone suffices:
        /// the wording differs between the lock a formula takes and the one a
        /// cask takes, and a partial match must not become a plain failure.
        static let lock = [
            "has already locked",
            "Please wait for it to finish or terminate it to continue"
        ]

        /// Heuristic and deliberately unprobed — no live sudo-requiring cask was
        /// exercised. Safe to widen without a design change, because a miss
        /// degrades to `.failed` with the log visible.
        static let privilege = [
            "sudo: no tty present",
            "sudo: a password is required",
            "Password:"
        ]

        static func isLock(_ line: String) -> Bool {
            lock.contains { line.contains($0) }
        }

        static func isPrivilege(_ line: String) -> Bool {
            privilege.contains { line.contains($0) }
        }
    }

    // MARK: - Reading the outcome

    public var isSuccess: Bool { self == .succeeded }

    /// Cancellation and abandonment are **not** failures: the user asked for
    /// them, and reporting them as errors would be a lie about their own action.
    public var isFailure: Bool {
        switch self {
        case .failed, .busy, .needsPrivileges, .launchFailed: true
        case .succeeded, .cancelled, .abandoned: false
        }
    }

    /// Every terminal outcome owes exactly one inventory re-snapshot — success,
    /// both typed failures, a plain failure and a cancellation alike. A
    /// cancelled or failed mutation may have changed the world just as much as a
    /// successful one (package-mutation PM6).
    public var forcesReSnapshot: Bool { true }

    /// The one sentence shown for this outcome.
    ///
    /// Built entirely from Cellar's own typed `command` — never from the
    /// subprocess's bytes — which is what makes the "brew's guessed command
    /// name is never presented" property structural rather than careful.
    public func message(for command: MutationCommand) -> String {
        switch self {
        case .succeeded:
            "Done."
        case .failed(let status):
            "Homebrew exited with status \(status). The full output is below."
        case .busy:
            """
            Homebrew is busy with another operation, probably in a Terminal \
            window. Wait for it to finish and try again.
            """
        case .needsPrivileges:
            """
            This needs an administrator password, which Cellar does not ask for. \
            Run \(command.displayCommand) in Terminal instead.
            """
        case .cancelled:
            """
            Cancelled. Homebrew may have left a partial change; refreshing now.
            """
        case .abandoned:
            """
            Cancelled, but Homebrew ignored the request and is still running \
            outside Cellar. It may leave a partial change; refreshing now.
            """
        case .launchFailed:
            "Homebrew could not be started. Check the brew location in Settings."
        }
    }

    /// A short label for the activity list, where the full sentence does not fit.
    public var summaryLabel: String {
        switch self {
        case .succeeded: "Done"
        case .failed: "Failed"
        case .busy: "Homebrew busy"
        case .needsPrivileges: "Needs Terminal"
        case .cancelled: "Cancelled"
        case .abandoned: "Cancelled, still running"
        case .launchFailed: "Could not start"
        }
    }
}
