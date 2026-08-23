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
    /// It exited 0, and said so in words: nothing changed, because the thing
    /// was already in the state that was asked for.
    ///
    /// `brew services` exits 0 both for a state change and for a no-op, so the
    /// exit code cannot separate them and something has to read the prose
    /// (live probe, brew 6.0.14 — gate U8). This is the `.cancelled` shape:
    /// neither a success nor a failure, because nothing happened and nothing
    /// went wrong.
    ///
    /// Rejected, and recorded so the decision is not silently reopened: an
    /// associated value on `.succeeded` (it breaks `==` across many shipped
    /// tests), and a display-only note (it would leave the durable history
    /// saying "Done" about a no-op, which is a lie).
    case noChange
    /// Cellar cancelled it, and it stopped.
    case cancelled
    /// Cellar cancelled it, brew ignored both signals, and it is still running
    /// outside Cellar. Mapped from `BrewProcessError.cancelledUnresponsive`;
    /// SIGKILL is never an option (M1 D4).
    case abandoned(after: Duration)
    /// The process never started.
    case launchFailed
    /// Queue-front evidence rejected the mutation before process launch.
    case authorizationDenied(MutationLaunchDenial.Code)
    /// Homebrew refused to load the package because the tap publishing it is
    /// not trusted. Nothing ran.
    ///
    /// **No associated value, deliberately.** Not one byte of the refusal is
    /// parsed, captured or echoed — no tap name, package name, qualified token
    /// or suggested command (package-mutation PM10 :293-295). The recovery
    /// finds its tap in Cellar's own snapshot instead
    /// (`UntrustedTapRecovery`), so the only thing brew's message does here is
    /// answer "was this a trust refusal?".
    ///
    /// A parsed-then-validated tap name was rejected as "strictly stronger": it
    /// is not, it is an extraction, and PM10 asserts its absence.
    case refusedUntrustedTap

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

        // An identity the execution layer does not know never had a process, so
        // it is the same fact `.launchFailed` already names — "the process never
        // started". No new outcome case, no new sentence, and decided here so
        // subprocess prose can never reclassify it (brew-execution, design D8).
        if exit.reason == .unknownOperation { return .launchFailed }

        if exit.isCancelled { return .cancelled }
        if exit.isSuccess { return .succeeded }

        // Only now, and only on stderr.
        let tail = log
            .filter { $0.stream == .stderr }
            .suffix(tailLength)
            .map(\.text)

        if tail.contains(where: Signature.isLock) { return .busy }
        if tail.contains(where: Signature.isPrivilege) { return .needsPrivileges }
        if tail.contains(where: Signature.isUntrustedTap) { return .refusedUntrustedTap }

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

        /// One phrase, not two (design DD-6). `"untrusted tap"` is the
        /// substring of the measured Homebrew 6.0.18 cask refusal (obs #7721)
        /// and of any plausible formula wording, and it cannot collide with the
        /// lock or privilege phrases above.
        ///
        /// `"Refusing to load"` alone was rejected: brew refuses to load things
        /// for reasons a trust grant would not fix, and a false positive here
        /// does not merely show a wrong sentence — it offers a **Trust button**
        /// for one of them. A miss degrades to `.failed` with the verbatim log,
        /// and widening later needs no structural change.
        static let untrustedTap = "untrusted tap"

        static func isPrivilege(_ line: String) -> Bool {
            privilege.contains { line.contains($0) }
        }

        static func isUntrustedTap(_ line: String) -> Bool {
            line.contains(untrustedTap)
        }
    }

    // MARK: - Reading the outcome

    public var isSuccess: Bool { self == .succeeded }

    /// Cancellation and abandonment are **not** failures: the user asked for
    /// them, and reporting them as errors would be a lie about their own action.
    public var isFailure: Bool {
        switch self {
        // The command did not run, so the refusal is a failure.
        case .failed, .busy, .needsPrivileges, .launchFailed, .refusedUntrustedTap: true
        case .succeeded, .noChange, .cancelled, .abandoned, .authorizationDenied: false
        }
    }

    // There is deliberately **no** re-snapshot flag on this type any more.
    //
    // It was an unconditional `true` on every outcome, which made "what does
    // this invalidate?" a property of *how the operation ended*. It is a
    // property of *what ran*: a services toggle changes nothing in the installed
    // set whether it succeeds, fails or is cancelled. The declaration moved to
    // `BrewMutating.invalidates`, and PM6's real invariant is preserved intact —
    // every terminal outcome still owes exactly one refresh of each domain its
    // command declared (design D2).

    /// The one sentence shown for this outcome.
    ///
    /// Built entirely from Cellar's own typed `command` — never from the
    /// subprocess's bytes — which is what makes the "brew's guessed command
    /// name is never presented" property structural rather than careful.
    public func message(for command: some BrewMutating) -> String {
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
        case .noChange:
            """
            No change: it was already in that state. Homebrew reported this \
            rather than doing anything.
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
        case .authorizationDenied(.evidenceChanged):
            "The affected packages changed. Review them and confirm again."
        case .authorizationDenied(.evidenceUnavailable):
            "Cellar could not verify the current affected packages. Refresh and try again."
        // Tap-scoped and tap-agnostic: it names no tap, because nothing was read
        // out of the refusal to name one with, and it says nothing about the
        // *package* being untrusted, because a per-package grant is independent
        // of a tap grant (PM10 :309-314).
        case .refusedUntrustedTap:
            """
            Homebrew refused to load this package because its tap is not \
            trusted. Trust the tap in Taps, then try again.
            """
        }
    }

    /// A short label for the activity list, where the full sentence does not fit.
    public var summaryLabel: String {
        switch self {
        case .succeeded: "Done"
        case .noChange: "No change"
        case .failed: "Failed"
        case .busy: "Homebrew busy"
        case .needsPrivileges: "Needs Terminal"
        case .cancelled: "Cancelled"
        case .abandoned: "Cancelled, still running"
        case .launchFailed: "Could not start"
        case .authorizationDenied(.evidenceChanged): "Needs fresh confirmation"
        case .authorizationDenied(.evidenceUnavailable): "Could not verify current packages"
        case .refusedUntrustedTap: "Tap not trusted"
        }
    }
}
