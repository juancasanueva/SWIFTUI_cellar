import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The containment claim behind design D4's most review-sensitive decision.
///
/// The service marker pass reads **stdout**, where `MutationOutcome`'s shipped
/// rule is stderr-only precisely so a package's build script cannot change what
/// the user is told. The mitigation is structural — the pass is family-owned, so
/// it cannot reach `install`/`upgrade` — and these are the tests that make that
/// claim falsifiable rather than merely stated.
///
/// Verified by mutation during apply: moving the marker pass onto the shared
/// `BrewMutating` default fails **both** tests below, on exactly the assertions
/// that name the leak.
///
/// Split out of `ServiceClassificationTests` at SwiftLint's `file_length` and
/// `type_body_length` bounds — split rather than suppressed (task 17.1) — and
/// the seam is honest: "what this family decides" and "what this family must
/// never be able to decide for another" are two subjects.
@Suite("Service classification containment")
struct ServiceClassificationContainmentTests {
    private static func target(_ name: String) throws -> ServiceTarget {
        try #require(ServiceTarget(name: name))
    }

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
        stdout: [String] = [],
        stderr: [String] = []
    ) -> MutationOutcome {
        command.classify(
            exit: BrewExit(status: status, reason: .exited),
            fault: nil,
            log: lines(stdout: stdout, stderr: stderr)
        )
    }

    /// Live probe, brew 6.0.14 — exit 0, on stdout.
    private static let alreadyStarted =
        "Service `atuin` already started, use `brew services restart atuin` to restart."
    /// Live probe — exit 0, on stderr.
    private static let notStarted = "Warning: Service `atuin` is not started."

    /// One synthesised run, named rather than a tuple so a failing row says
    /// which shape it was.
    struct Payload: Sendable {
        var status: Int32 = 1
        var reason: BrewExit.Reason = .exited
        var fault: BrewProcessError?
        var stdout: [String] = []
        var stderr: [String] = []
    }

    // MARK: - Threat: untrusted subprocess payload as classification input

    /// **The claim that makes widening to stdout acceptable.** The marker pass
    /// belongs to `ServiceCommand` alone; the protocol default — which every
    /// package command uses — is byte-identical to the shipped static
    /// classifier.
    ///
    /// A regression anchor over the same inputs `ClassificationTests` covers, so
    /// moving the marker pass onto the default would fail here rather than
    /// silently change what an `install` tells the user.
    @Test("Package classification is byte-identical to the shipped classifier")
    func packageClassificationIsByteIdentical() throws {
        let wget = try #require(PackageTarget(PackageID(kind: .formula, name: "wget")))
        let commands: [MutationCommand] = [
            .install(wget), .uninstall(wget), .reinstall(wget), .upgrade(wget), .upgradeAll
        ]

        let payloads: [Payload] = [
            Payload(status: 0, stdout: ["==> Pouring wget"]),
            Payload(stderr: ["Error: A `brew upgrade` process has already locked /opt/homebrew"]),
            Payload(stderr: ["Please wait for it to finish or terminate it to continue."]),
            Payload(stderr: ["sudo: a password is required"]),
            Payload(stderr: ["Error: No available formula with the name \"wgett\"."]),
            Payload(status: 130, reason: .cancelled(signal: SIGINT), stderr: ["Error: interrupted"]),
            Payload(status: 127, fault: .executableUnavailable(URL(fileURLWithPath: "/x"))),
            Payload(status: 0, stdout: ["Password: is in the README"]),
            Payload(status: -1, reason: .unknownOperation),
            // The service markers themselves, on both streams. Without these
            // rows the comparison would still pass if the marker pass were
            // moved onto the shared default, because no other payload here can
            // reach it — so these are the rows that make the anchor bite.
            Payload(status: 0, stdout: [Self.alreadyStarted]),
            Payload(status: 0, stderr: [Self.notStarted])
        ]

        var compared = 0
        for command in commands {
            for payload in payloads {
                let exit = BrewExit(status: payload.status, reason: payload.reason)
                let log = Self.lines(stdout: payload.stdout, stderr: payload.stderr)
                #expect(
                    command.classify(exit: exit, fault: payload.fault, log: log)
                        == MutationOutcome.classify(exit: exit, fault: payload.fault, log: log),
                    "\(command.verb) drifted from the shipped classifier on status \(payload.status)"
                )
                compared += 1
            }
        }
        #expect(compared == 55, "the regression anchor did not run over every pair")
    }

    /// **Adversarial.** A formula whose build script echoes brew's own service
    /// marker must not be able to tell the user their install "made no change".
    @Test("A payload containing a service marker cannot reclassify an install")
    func aPayloadContainingAServiceMarkerCannotReclassifyAnInstall() throws {
        let wget = try #require(PackageTarget(PackageID(kind: .formula, name: "wget")))
        let hostile = [Self.alreadyStarted, Self.notStarted, "already started, use"]

        // On stdout, where a build script writes.
        let onStdout = MutationCommand.install(wget).classify(
            exit: BrewExit(status: 0, reason: .exited),
            fault: nil,
            log: Self.lines(stdout: hostile)
        )
        #expect(onStdout == .succeeded, "a service marker reclassified an install")
        #expect(onStdout != .noChange)

        // And on stderr, where brew writes.
        let onStderr = MutationCommand.install(wget).classify(
            exit: BrewExit(status: 0, reason: .exited),
            fault: nil,
            log: Self.lines(stderr: hostile)
        )
        #expect(onStderr == .succeeded)
        #expect(onStderr != .noChange)

        // The same bytes, through the family that owns the marker, do classify —
        // so the difference is the *family*, not the payload.
        #expect(
            Self.classify(.start(try Self.target("atuin")), status: 0, stdout: hostile) == .noChange,
            "the marker never matched at all, so this proves nothing about scoping"
        )
    }

    // MARK: - SM6 sc5 — nothing parsed reaches an argv

    /// Classification is display-only. Traced two ways, because either alone
    /// would be weak: behaviourally, the argv is identical before and after
    /// classifying the most hostile payload available; structurally, the family
    /// contains no extraction construct that could have produced a token.
    @Test("Nothing parsed from brew's output reaches an argv")
    func nothingParsedFromBrewsOutputReachesAnArgv() throws {
        let command = ServiceCommand.stop(try Self.target("atuin"))
        let before = command.arguments

        let hostile = [
            "Service `--all` already started, use `brew services restart --all` to restart.",
            "Warning: Service `; rm -rf /` is not started.",
            "Error: run `brew services start everything` instead",
            "sudo: a password is required"
        ]
        let outcome = command.classify(
            exit: BrewExit(status: 0, reason: .exited),
            fault: nil,
            log: Self.lines(stdout: hostile, stderr: hostile)
        )

        // The argv is untouched, and still names exactly the service asked for.
        #expect(command.arguments == before)
        #expect(command.arguments == ["services", "stop", "atuin"])
        #expect(command.arguments.contains("--all") == false)
        #expect(command.arguments.contains("everything") == false)
        #expect(command.brewCommand.arguments == ["services", "stop", "atuin"])

        // Nor does the sentence shown echo anything from the payload.
        let message = outcome.message(for: command)
        for leaked in ["--all", "rm -rf", "everything", "sudo"] {
            #expect(message.contains(leaked) == false, "\(leaked) was echoed out of the payload")
        }

        // Structurally: nothing in the family extracts a substring at all.
        let source = try Self.source(of: "ServiceCommand.swift")
        for extraction in [
            "range(of:", "components(separatedBy:", "split(separator:", "firstMatch",
            "prefix(upTo", "dropFirst(", "capture", "replacingOccurrences"
        ] {
            #expect(
                source.contains(extraction) == false,
                "\(extraction) appeared — a value could be extracted from the payload"
            )
        }
        #expect(source.contains("func classify"), "the scan ran against a file with no classifier")
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
