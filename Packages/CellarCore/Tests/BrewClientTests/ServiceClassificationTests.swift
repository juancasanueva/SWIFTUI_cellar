import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// Outcome classification for the four service verbs (design D4 —
/// service-management SM6, SM7, package-mutation PM4).
///
/// **Why this family needs its own classifier at all**, live-probed on brew
/// 6.0.14 (Engram `#7178`, gate U8): `brew services start` on an already-running
/// service exits **0**, and `brew services stop` on an already-stopped one exits
/// **0** as well. The exit code cannot separate "it happened" from "it was
/// already like that", so something has to read the prose.
///
/// **The decision in this slice most deserving adversarial review** is that the
/// marker pass reads **stdout**, where `MutationOutcome`'s shipped rule is
/// stderr-only precisely so a package's build script cannot change what the user
/// is told. Two things make that acceptable, and both are asserted here rather
/// than argued:
///
/// - the pass is **family-owned** — `ServiceCommand` overrides `classify`, the
///   protocol default is untouched — so it cannot reach `install`/`upgrade`;
/// - classification changes only the **message**: never a retry, never a
///   privilege, never an argv.
///
/// `brew services` runs no third-party build script; its stdout is brew's own
/// prose plus launchctl's.
@Suite("Service outcome classification")
struct ServiceClassificationTests {
    private static func target(_ name: String) throws -> ServiceTarget {
        try #require(ServiceTarget(name: name))
    }

    /// Synthesised output. Nothing here spawns `brew` and nothing mutates a
    /// service; the marker strings are the ones the live probe captured.
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
        _ command: ServiceCommand,
        status: Int32 = 0,
        reason: BrewExit.Reason = .exited,
        fault: BrewProcessError? = nil,
        stdout: [String] = [],
        stderr: [String] = []
    ) -> MutationOutcome {
        command.classify(
            exit: BrewExit(status: status, reason: reason),
            fault: fault,
            log: lines(stdout: stdout, stderr: stderr)
        )
    }

    // MARK: - The probed strings, byte for byte

    /// Live probe, brew 6.0.14 — a cold start.
    private static let coldStart = "==> Successfully started `atuin` (label: homebrew.mxcl.atuin)"
    /// Live probe — a start on a service that is already running. Exit **0**,
    /// on **stdout**, with no `Successfully` line and no `Error:`.
    private static let alreadyStarted =
        "Service `atuin` already started, use `brew services restart atuin` to restart."
    /// Live probe — a stop on a service that is already stopped. Exit **0**, on
    /// **stderr**.
    private static let notStarted = "Warning: Service `atuin` is not started."
    /// Live probe, gate U5 — the non-fatal root-domain warning.
    private static let rootWarning =
        "Warning: `atuin` must be run as root to start at system startup!"

    // MARK: - SM6 sc1–sc4

    @Test("A cold start is classified as started")
    func aColdStartIsClassifiedAsStarted() throws {
        let outcome = Self.classify(
            .start(try Self.target("atuin")),
            status: 0,
            stdout: [Self.coldStart]
        )

        #expect(outcome == .succeeded)
        #expect(outcome.isSuccess)
        #expect(outcome.isFailure == false)
    }

    /// Exit 0 **and** a marker that says nothing happened. The classification
    /// must come from the marker; the exit code says the opposite.
    @Test("A start on an already-running service is classified from the marker, not the exit code")
    func aStartOnAnAlreadyRunningServiceIsClassifiedFromTheMarkerNotTheExitCode() throws {
        let outcome = Self.classify(
            .start(try Self.target("atuin")),
            status: 0,
            stdout: [Self.alreadyStarted]
        )

        #expect(outcome == .noChange)
        #expect(outcome != .succeeded, "a no-op was reported as a fresh start")
        #expect(outcome.isFailure == false, "a no-op was reported as a failure")
        #expect(outcome.isSuccess == false)
        #expect(outcome.summaryLabel == "No change")

        // The exit status alone would have said "succeeded", which is the whole
        // point: a classifier that read only the exit code cannot tell these
        // apart, and the shipped default does exactly that.
        #expect(
            MutationOutcome.classify(
                exit: BrewExit(status: 0, reason: .exited),
                fault: nil,
                log: Self.lines(stdout: [Self.alreadyStarted])
            ) == .succeeded
        )
    }

    @Test("A stop on an already-stopped service is classified from its stderr warning")
    func aStopOnAnAlreadyStoppedServiceIsClassifiedFromItsStderrWarning() throws {
        let outcome = Self.classify(
            .stop(try Self.target("atuin")),
            status: 0,
            stderr: [Self.notStarted]
        )

        #expect(outcome == .noChange)
        #expect(outcome.isFailure == false)
        #expect(outcome.isSuccess == false)
    }

    /// The marker is matched on an **interior invariant**, never anchored and
    /// never whole-sentence, because brew interpolates the service name into
    /// every one of them.
    @Test(
        "The marker matches whichever service name brew interpolated",
        arguments: ["atuin", "postgresql@16", "unbound"]
    )
    func markersMatchAnyInterpolatedName(name: String) throws {
        let started = "Service `\(name)` already started, use `brew services restart \(name)` to restart."
        let stopped = "Warning: Service `\(name)` is not started."

        #expect(Self.classify(.start(try Self.target(name)), stdout: [started]) == .noChange)
        #expect(Self.classify(.stop(try Self.target(name)), stderr: [stopped]) == .noChange)
    }

    /// Two separate claims, and the parenthetical in task 11.5 is what separates
    /// them:
    ///
    /// - a **non-zero** exit matching no marker is a generic failure, with its
    ///   log preserved verbatim;
    /// - an **exit 0** matching no marker is not reported as a state change that
    ///   did not happen — brew exited 0 and never said "already started", so it
    ///   did the thing. What it must never be is `.noChange`.
    @Test("An unmatched outcome is never a success it did not earn")
    func anUnmatchedOutcomeIsNeverASuccess() throws {
        let restart = ServiceCommand.restart(try Self.target("atuin"))
        let noise = ["Error: something brew has never said before"]

        let failed = Self.classify(restart, status: 1, stderr: noise)
        #expect(failed == .failed(status: 1))
        #expect(failed.isFailure)
        #expect(failed != .noChange, "an unmatched failure was reported as a no-op")
        #expect(failed != .succeeded)

        // The log is the explanation, and the outcome carries no copy of it —
        // so a false negative degrades to the full output on screen.
        #expect(MemoryLayout<MutationOutcome>.size < 128)

        let zero = Self.classify(restart, status: 0, stdout: ["some unfamiliar line"])
        #expect(zero == .succeeded)
        #expect(
            zero != .noChange,
            "exit 0 with no marker was reported as a state change that did not happen"
        )
    }

    /// `Successfully started` / `Successfully stopped` are **corroboration
    /// only**, never the sole success test: an exit 0 with neither marker is
    /// still a success, and an exit 0 carrying both the success line and the
    /// no-change marker is a no-op, because brew only prints the latter when
    /// nothing happened.
    @Test("The success line corroborates but never decides")
    func theSuccessLineCorroboratesButNeverDecides() throws {
        let start = ServiceCommand.start(try Self.target("atuin"))

        #expect(Self.classify(start, status: 0, stdout: []) == .succeeded)
        #expect(
            Self.classify(start, status: 0, stdout: [Self.coldStart, Self.alreadyStarted])
                == .noChange
        )
        // And a success line on a **failed** run does not rescue it.
        #expect(Self.classify(start, status: 1, stdout: [Self.coldStart]) == .failed(status: 1))
    }

    // MARK: - SM7 sc1–sc2, PM4 — the privilege boundary

    /// Cellar never escalates. brew emits this warning and then installs into
    /// the *user* domain, so a run that then exits 0 is a success — reporting it
    /// as a sudo-required failure would send the user to Terminal for nothing.
    @Test("A root-domain warning on a zero exit is a success, not a privilege failure")
    func aRootDomainWarningOnAZeroExitIsASuccessNotAPrivilegeFailure() throws {
        let outcome = Self.classify(
            .start(try Self.target("atuin")),
            status: 0,
            stdout: [Self.coldStart],
            stderr: [Self.rootWarning]
        )

        #expect(outcome == .succeeded)
        #expect(outcome != .needsPrivileges, "a non-fatal warning became a sudo failure")
        #expect(outcome.isFailure == false)
    }

    /// The exact stderr/exit signature of a rejected `launchctl bootstrap` is
    /// **unprobed** (U5 residual), so the classifier must degrade safely: a
    /// generic failure with the output on screen, never a success, never a
    /// no-op, and never an automatic retry.
    @Test("A rejected bootstrap is a generic failure with its log intact and no retry")
    func aRejectedBootstrapIsAGenericFailureWithItsLogIntactAndNoRetry() throws {
        let command = ServiceCommand.start(try Self.target("atuin"))
        let log = Self.lines(
            stdout: [],
            stderr: [Self.rootWarning, "Bootstrap failed: 5: Input/output error"]
        )
        let outcome = command.classify(
            exit: BrewExit(status: 1, reason: .exited),
            fault: nil,
            log: log
        )

        #expect(outcome == .failed(status: 1))
        #expect(outcome != .succeeded)
        #expect(outcome != .noChange)
        #expect(outcome != .needsPrivileges, "an unprobed signature was guessed at")

        // Its output is readable verbatim — the classifier consumed nothing.
        #expect(log.map(\.text).contains(Self.rootWarning))
        #expect(log.count == 2)

        // And nothing retries: the surface offers no such affordance at all.
        let source = try Self.source(of: "ServiceCommand.swift")
        for forbidden in ["func retry", "retryCount", "sudo", "AuthorizationRef", "askpass"] {
            #expect(source.contains(forbidden) == false, "\(forbidden) leaked into the service family")
        }
        #expect(source.contains("public enum ServiceCommand"), "the scan ran against the wrong file")
    }

    /// A **non-zero** exit carrying a real sudo signature is still the typed
    /// privilege failure — the family override falls through to the default, it
    /// does not replace it.
    @Test("A genuine sudo signature on a failed run still reaches the typed failure")
    func aGenuineSudoSignatureStillReachesTheTypedFailure() throws {
        let outcome = Self.classify(
            .start(try Self.target("atuin")),
            status: 1,
            stderr: ["sudo: a password is required"]
        )

        #expect(outcome == .needsPrivileges)
    }

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/BrewClient/\(file)"),
            encoding: .utf8
        )
    }
}
