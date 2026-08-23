import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// Outcome classification, as a pure function over untrusted subprocess output.
///
/// This suite is the threat response for **untrusted subprocess payload as
/// classification input** and for the **privilege boundary** (design D5).
/// Two properties make matching on brew's prose acceptable at all, and both are
/// asserted here rather than merely argued:
///
/// - classification changes **only the sentence shown** — never a retry, never
///   an escalation, never an argv — so a false positive is a wrong message and a
///   false negative degrades to `.failed` with the full log on screen;
/// - brew names the *blocked* invocation in its lock message, not the process
///   actually holding the lock (live probe, Engram `.../lock-probe`), so nothing
///   is ever parsed out of it and presented as the holder.
@Suite("Mutation outcome classification")
struct ClassificationTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let hello = PackageID(kind: .formula, name: "hello")

    /// Synthesised output. No test spawns `brew` and no test mutates anything
    /// (D12); the lock and sudo surfaces are covered by the *strings* the live
    /// probe captured, not by re-creating the conditions.
    private static func lines(
        stdout: [String] = [],
        stderr: [String] = []
    ) -> [LogLine] {
        var sequence = 0
        var out: [LogLine] = []
        for text in stdout {
            out.append(LogLine(stream: .stdout, text: text, sequence: sequence))
            sequence += 1
        }
        for text in stderr {
            out.append(LogLine(stream: .stderr, text: text, sequence: sequence))
            sequence += 1
        }
        return out
    }

    private static func classify(
        status: Int32 = 1,
        reason: BrewExit.Reason = .exited,
        fault: BrewProcessError? = nil,
        stdout: [String] = [],
        stderr: [String] = []
    ) -> MutationOutcome {
        MutationOutcome.classify(
            exit: BrewExit(status: status, reason: reason),
            fault: fault,
            log: lines(stdout: stdout, stderr: stderr)
        )
    }

    // MARK: - The lock surface (PM5 sc1–sc3) — live-probed, brew 6.0.14

    /// The exact two lines the probe captured, byte for byte.
    private static let lockStderr = [
        "Error: A `brew uninstall hello` process has already locked "
            + "/opt/homebrew/Cellar/hello.",
        "Please wait for it to finish or terminate it to continue."
    ]

    @Test("The probed lock output classifies as busy")
    func probedLockOutputIsBusy() {
        let outcome = Self.classify(status: 1, stderr: Self.lockStderr)

        #expect(outcome == .busy)
        #expect(outcome.isFailure)
        #expect(outcome.isSuccess == false)
    }

    @Test("The busy message tells the user Homebrew is busy in another terminal")
    func theBusyMessageNamesTheRealCause() {
        let message = MutationOutcome.busy.message(for: MutationCommand.uninstall(PackageTarget(Self.hello)!))

        #expect(message.lowercased().contains("homebrew"))
        #expect(message.lowercased().contains("terminal"))
        #expect(message.lowercased().contains("busy"))
    }

    /// Either phrase alone is enough: the probe emitted both, but brew's
    /// wording differs between the lock a formula takes and the one a cask
    /// takes, and a partial match must not silently become `.failed`.
    @Test(
        "Either lock phrase on its own is enough",
        arguments: [
            "Error: A `brew upgrade` process has already locked /opt/homebrew/Cellar/git.",
            "Please wait for it to finish or terminate it to continue."
        ]
    )
    func eitherLockPhraseSuffices(line: String) {
        #expect(Self.classify(status: 1, stderr: [line]) == .busy)
    }

    /// **Threat: untrusted subprocess payload.** brew names its *own*
    /// invocation in that message, not the process holding the lock, so parsing
    /// a holder out of it would print a confident lie. The classification must
    /// still be busy, and the command name must not survive into the text.
    @Test("A busy message naming an unrelated command still classifies busy, silently")
    func aBusyMessageNamingAnotherCommandIsStillBusy() {
        let hostile = [
            "Error: A `brew install some-other-package` process has already locked "
                + "/opt/homebrew/Cellar/wget.",
            "Please wait for it to finish or terminate it to continue."
        ]

        let outcome = Self.classify(status: 1, stderr: hostile)
        #expect(outcome == .busy)

        let message = outcome.message(for: MutationCommand.uninstall(PackageTarget(Self.wget)!))
        #expect(
            message.contains("some-other-package") == false,
            "brew's guessed command name was parsed out and presented as the lock holder"
        )
        #expect(message.contains("install some-other-package") == false)
        // Nor is any path from the message echoed.
        #expect(message.contains("/opt/homebrew/Cellar") == false)
    }

    @Test("A non-zero exit without either lock phrase is a plain failure")
    func aNonZeroExitWithoutTheSignatureIsNotBusy() {
        let outcome = Self.classify(
            status: 1,
            stderr: ["Error: No available formula with the name \"wgett\"."]
        )

        #expect(outcome == .failed(status: 1))
        #expect(outcome != .busy)
    }

    // MARK: - The privilege boundary (PM4 sc1, sc3)

    /// **Threat: privilege boundary.** Standard input is `/dev/null`, so brew
    /// can never block on a prompt Cellar cannot answer; what it can do is fail
    /// with a signature. The response is a sentence, and only a sentence.
    @Test(
        "Every sudo signature with a non-zero exit is the typed privilege failure",
        arguments: [
            "sudo: no tty present and no askpass program specified",
            "sudo: a password is required",
            "Password:"
        ]
    )
    func sudoSignaturesAreTyped(line: String) {
        #expect(Self.classify(status: 1, stderr: [line]) == .needsPrivileges)
    }

    @Test("The privilege guidance echoes the exact command and names the package")
    func privilegeGuidanceEchoesTheCommand() {
        let command = MutationCommand.install(PackageTarget(PackageID(kind: .cask, name: "docker"))!)
        let message = MutationOutcome.needsPrivileges.message(for: command)

        #expect(message.contains(command.displayCommand))
        #expect(message.contains("brew install --cask docker"))
        #expect(message.contains("docker"))
        #expect(message.lowercased().contains("terminal"))
    }

    /// There is no in-app credential surface anywhere in the outcome's API: no
    /// password, no askpass, no retry, no escalation. Asserted structurally
    /// because the safest possible implementation of this requirement is the
    /// *absence* of a member, which a behavioural test cannot see.
    @Test("The outcome offers no credential surface, no retry and no escalation")
    func noCredentialSurfaceExists() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/BrewClient/MutationOutcome.swift"),
            encoding: .utf8
        )

        for forbidden in [
            "func retry", "var retry", "askpass", "SUDO_ASKPASS", "AuthorizationRef",
            "SMJobBless", "keychain", "Keychain", "func escalate", "password:"
        ] {
            #expect(
                source.contains(forbidden) == false,
                "\(forbidden) appeared in the outcome — a privilege path may have leaked in"
            )
        }
    }

    /// **Threat: untrusted payload, adversarial.** A package whose *successful*
    /// output happens to contain `Password:` is not a privilege failure. The
    /// exit status is checked before any prose is.
    @Test("A successful run whose output contains a prompt signature is not a failure")
    func aSuccessfulRunIsNeverReclassifiedByItsOutput() {
        let outcome = Self.classify(
            status: 0,
            reason: .exited,
            stdout: [
                "==> Installing hello",
                "Password: is stored in ~/.config/hello/secrets",
                "sudo: a password is required (this line is part of the README we print)"
            ]
        )

        #expect(outcome == .succeeded)
        #expect(outcome.isFailure == false)
    }

    /// Signatures are matched on **stderr only**: brew writes its own diagnostics
    /// there, and a package echoing prose on stdout must not be able to change
    /// what the user is told.
    @Test("A signature appearing only on stdout does not classify")
    func stdoutIsNeverASignatureSource() {
        #expect(
            Self.classify(status: 1, stdout: Self.lockStderr) == .failed(status: 1),
            "a lock phrase on stdout classified as busy"
        )
        #expect(
            Self.classify(status: 1, stdout: ["sudo: a password is required"])
                == .failed(status: 1)
        )
    }

    @Test("An unrecognised failure degrades to the plain failure, keeping its status")
    func unrecognisedFailuresDegradeToFailed() {
        #expect(Self.classify(status: 1, stderr: ["Error: something new"]) == .failed(status: 1))
        #expect(Self.classify(status: 2, stderr: []) == .failed(status: 2))
        #expect(Self.classify(status: 127, stderr: ["nope"]) == .failed(status: 127))
    }

    /// The full log is the property that makes a false negative survivable, so
    /// the outcome must not be carrying — or truncating — a copy of it.
    @Test("Classification is decided from the tail but preserves nothing itself")
    func classificationCarriesNoLogCopy() {
        let noisy = (0..<5_000).map { "line \($0)" }
        let outcome = Self.classify(status: 1, stderr: noisy)

        #expect(outcome == .failed(status: 1))
        // The log lives on the activity item, verbatim and untruncated; the
        // outcome is a small enumerated value that could not hold it.
        #expect(MemoryLayout<MutationOutcome>.size < 128)
    }

    /// Only the last 20 stderr lines are scanned, so a multi-megabyte log costs
    /// a bounded amount of work — and a signature buried far above the tail is
    /// deliberately out of scope rather than accidentally in it.
    @Test("Only the stderr tail is scanned, so a huge log classifies in bounded time")
    func onlyTheTailIsScanned() {
        let buried = Self.lockStderr + (0..<50_000).map { "progress \($0)" }
        let inTail = (0..<50_000).map { "progress \($0)" } + Self.lockStderr

        let start = ContinuousClock.now
        #expect(Self.classify(status: 1, stderr: buried) == .failed(status: 1))
        #expect(Self.classify(status: 1, stderr: inTail) == .busy)
        #expect(ContinuousClock.now - start < .seconds(2))
    }

    // MARK: - Faults, cancellation and abandonment (PM6)

    @Test("A launch fault is reported as launch failure, never as a brew failure")
    func launchFaultsAreTheirOwnOutcome() {
        let url = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        let outcome = Self.classify(
            status: 127,
            fault: .executableUnavailable(url),
            stderr: Self.lockStderr
        )

        #expect(outcome == .launchFailed)
        #expect(outcome != .busy, "a fault was overtaken by prose matching")
    }

    /// `.abandoned` is mapped from the existing `.cancelledUnresponsive` fault:
    /// brew ignored SIGINT *and* SIGTERM and is still running outside Cellar,
    /// which is a materially different fact from an ordinary cancellation.
    @Test("An unresponsive cancellation is abandonment, with its own sentence")
    func unresponsiveCancellationIsAbandonment() {
        let outcome = Self.classify(
            status: 128 + SIGTERM,
            reason: .cancelled(signal: SIGTERM),
            fault: .cancelledUnresponsive(after: .seconds(7))
        )

        #expect(outcome == .abandoned(after: .seconds(7)))
        #expect(outcome != .cancelled)

        let message = outcome.message(for: MutationCommand.install(PackageTarget(Self.wget)!))
        #expect(message != MutationOutcome.cancelled.message(for: MutationCommand.install(PackageTarget(Self.wget)!)))
        #expect(message.lowercased().contains("still running"))
    }

    @Test("A cancelled run is cancelled, never a failure")
    func cancelledRunsAreNeverFailures() {
        let outcome = Self.classify(
            status: 128 + SIGINT,
            reason: .cancelled(signal: SIGINT),
            stderr: ["Error: interrupted"]
        )

        #expect(outcome == .cancelled)
        #expect(outcome.isFailure == false)
        #expect(outcome != .failed(status: 130))
    }

    /// One generic sentence for every command (product Q5): it must not claim
    /// the change was undone, must not claim nothing happened, and must admit
    /// possible partial state (PM6 sc3).
    @Test("The cancelled message is one generic sentence for every command")
    func theCancelledMessageIsGeneric() throws {
        let commands: [MutationCommand] = [
            .install(PackageTarget(Self.wget)!),
            .uninstall(PackageTarget(Self.hello)!),
            .upgradeAll,
            .zap(CaskID(PackageID(kind: .cask, name: "iterm2"))!)
        ]

        let messages = Set(commands.map { MutationOutcome.cancelled.message(for: $0) })
        #expect(messages.count == 1, "the cancelled message was tailored per command")

        let message = try #require(messages.first)
        #expect(message.lowercased().contains("partial"))
        for claim in ["undone", "rolled back", "nothing happened", "no changes were made"] {
            #expect(
                message.lowercased().contains(claim) == false,
                "the cancelled message claimed \(claim)"
            )
        }
    }

    @Test("Success reports success and nothing else")
    func successIsSuccess() {
        let outcome = Self.classify(status: 0, reason: .exited, stdout: ["==> Pouring wget"])

        #expect(outcome == .succeeded)
        #expect(outcome.isSuccess)
        #expect(outcome.isFailure == false)
    }

    /// Every outcome is terminal — including the two typed failures — and what a
    /// terminal outcome refreshes is decided by the **command**, never by the
    /// outcome (PM6, as amended by design D2).
    ///
    /// The shipped re-snapshot flag was an unconditional `true` on every case,
    /// so it could only ever say "everything, always". Its replacement is
    /// asserted where it now lives; this test keeps the half that is still a
    /// property of the outcome — that each of them really is an ending — and
    /// pins the absence of the old member so it cannot quietly return.
    @Test("Every outcome is terminal, and what it refreshes is not its business")
    func everyOutcomeIsTerminalAndDeclaresNoScope() {
        let outcomes: [MutationOutcome] = [
            .succeeded, .failed(status: 1), .busy, .needsPrivileges,
            .cancelled, .abandoned(after: .seconds(7)), .launchFailed
        ]

        // Total: every outcome is exactly one of success, failure, or a
        // user-asked-for ending. None is "still going".
        for outcome in outcomes {
            #expect(outcome.isSuccess || outcome.isFailure || !outcome.summaryLabel.isEmpty)
            #expect(!(outcome.isSuccess && outcome.isFailure), "\(outcome) is both")
        }
        #expect(outcomes.count(where: \.isSuccess) == 1)
        #expect(outcomes.count(where: \.isFailure) == 4)
    }

    // MARK: - PM10 — the untrusted-tap refusal

    /// The measured Homebrew 6.0.18 **cask** refusal, byte for byte (obs #7721).
    private static let refusalStderr = [
        "Error: Refusing to load cask acme/tools/widget from untrusted tap acme/tools. "
            + "Run `brew trust --cask acme/tools/widget` or `brew trust acme/tools` to trust it."
    ]

    /// PM10 :328-341. Bound by exactly the discipline the sudo and busy
    /// signatures already are: stderr only, non-zero exit only, the shipped tail
    /// window, structural facts first.
    ///
    /// **DD-6.** One phrase, and a specific one. `"Refusing to load"` alone was
    /// rejected: brew refuses to load things for reasons a trust grant would not
    /// fix, and a false positive there does not merely show a wrong sentence —
    /// it offers a **Trust button** for one of them, which is a security-relevant
    /// misdirection.
    @Test("An untrusted-tap refusal is its own outcome")
    func anUntrustedTapRefusalIsItsOwnOutcome() {
        #expect(Self.classify(status: 1, stderr: Self.refusalStderr) == .refusedUntrustedTap)

        // The same prose on stdout does not classify: a package echoing brew's
        // words cannot steer the UI.
        #expect(Self.classify(status: 1, stdout: Self.refusalStderr) == .failed(status: 1))

        // Nor does a success, however it reads.
        #expect(Self.classify(status: 0, stderr: Self.refusalStderr) == .succeeded)

        // And a refusal to load that names no untrusted tap stays a plain
        // failure with its verbatim log — the DD-6 rule, stated as a test.
        #expect(
            Self.classify(status: 1, stderr: [
                "Error: Refusing to load cask acme/tools/widget from a directory that is not a tap."
            ]) == .failed(status: 1)
        )

        // The structural facts still win over the prose: a cancellation and a
        // launch fault are decided before a byte of output is examined.
        #expect(
            Self.classify(status: 1, reason: .cancelled(signal: 2), stderr: Self.refusalStderr)
                == .cancelled
        )
        #expect(
            Self.classify(
                status: 1,
                fault: .launchFailed(URL(fileURLWithPath: "/opt/homebrew/bin/brew"), code: 2),
                stderr: Self.refusalStderr
            ) == .launchFailed
        )
    }

    /// PM10 :293-295 is literal: "**nothing extracted from the payload**. No tap
    /// name, package name, qualified token or suggested command MUST be parsed
    /// out of the message."
    ///
    /// Asserted by **value equality across two refusals naming different taps**,
    /// which is the only assertion a payload-carrying case could not pass.
    @Test("Nothing is extracted from the refusal")
    func nothingIsExtractedFromTheRefusal() {
        let first = Self.classify(status: 1, stderr: Self.refusalStderr)
        let second = Self.classify(status: 1, stderr: [
            "Error: Refusing to load cask stranger/other/gadget from untrusted tap stranger/other. "
                + "Run `brew trust --cask stranger/other/gadget` or `brew trust stranger/other` to trust it."
        ])

        #expect(first == .refusedUntrustedTap)
        #expect(first == second, "the outcome carries something it read out of the payload")

        // The message is the spec's exact sentence, and it names nothing the
        // payload said (PM10 :351-357).
        let command = TapCommand.addTap(TapName("acme/tools")!)
        let message = first.message(for: command)
        #expect(message == """
        Homebrew refused to load this package because its tap is not trusted. \
        Trust the tap in Taps, then try again.
        """)
        for extracted in ["acme/tools", "widget", "stranger", "brew trust", "--cask"] {
            #expect(
                message.contains(extracted) == false,
                "the message echoes something parsed out of the refusal: \(extracted)"
            )
        }
        #expect(first.summaryLabel == "Tap not trusted")
        // The command did not run, so it is a failure.
        #expect(first.isFailure)
        #expect(first.isSuccess == false)

        // Classification read no more than the shipped tail window: a refusal
        // pushed past it stops classifying, which is what proves the bound.
        let padding = (0..<MutationOutcome.tailLength).map { "noise \($0)" }
        #expect(
            Self.classify(status: 1, stderr: Self.refusalStderr + padding) == .failed(status: 1)
        )
        #expect(MutationOutcome.tailLength == 20)
    }
}
