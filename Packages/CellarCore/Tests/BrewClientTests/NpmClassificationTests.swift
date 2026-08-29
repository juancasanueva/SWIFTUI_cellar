import BrewProcess
import Catalog
import Foundation
import Testing

@testable import BrewClient

/// npm outcomes, classified by npm's own signatures and never by brew's
/// (`npm-source` — "npm outcomes are classified by npm's own signatures, never
/// brew's"; design D14).
///
/// The same two properties `ClassificationTests` rests on hold here: matching on
/// npm's prose changes **only the sentence shown**, and nothing is ever parsed
/// *out of* the payload into that sentence — every message is built from
/// Cellar's own typed command.
@Suite("npm outcome classification")
struct NpmClassificationTests {
    private static let typescript = PackageID(kind: .npm, name: "typescript")

    private static func upgrade() throws -> NpmCommand {
        .upgrade(try #require(NpmPackageTarget(typescript)))
    }

    private static func classify(
        _ command: NpmCommand,
        status: Int32 = 1,
        reason: BrewExit.Reason = .exited,
        fault: BrewProcessError? = nil,
        stdout: [String] = [],
        stderr: [String] = []
    ) -> MutationOutcome {
        var sequence = 0
        var log: [LogLine] = []
        for text in stdout {
            log.append(LogLine(stream: .stdout, text: text, sequence: sequence))
            sequence += 1
        }
        for text in stderr {
            log.append(LogLine(stream: .stderr, text: text, sequence: sequence))
            sequence += 1
        }
        return command.classify(
            exit: BrewExit(status: status, reason: reason),
            fault: fault,
            log: log
        )
    }

    // MARK: - Exit 0 wins over any prose

    @Test("Exit 0 is a success whatever npm printed")
    func exitZeroIsSuccess() throws {
        let command = try Self.upgrade()

        #expect(Self.classify(command, status: 0) == .succeeded)
        #expect(
            Self.classify(
                command,
                status: 0,
                stderr: ["npm WARN deprecated request@2.88.2", "npm error code EACCES"]
            ) == .succeeded
        )
    }

    // MARK: - The privilege surface (live-probed fixture)

    @Test("EACCES on a non-zero exit is the typed needs-privileges failure")
    func eaccesIsNeedsPrivileges() throws {
        let command = try Self.upgrade()
        let stderr = try NpmFixture.text("install-g-eacces.stderr")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let outcome = Self.classify(command, status: 243, stderr: stderr)

        #expect(outcome == .needsPrivileges)
        #expect(outcome.message(for: command).contains("npm install -g typescript@latest"))
        #expect(outcome.message(for: command).contains("Homebrew") == false)
    }

    /// Triangulation: `EPERM` is the other permission code npm emits, and it
    /// must reach the same typed outcome rather than degrading to a generic
    /// failure.
    @Test("EPERM reaches the same typed needs-privileges failure")
    func epermIsNeedsPrivileges() throws {
        let command = try Self.upgrade()

        let outcome = Self.classify(
            command,
            status: 1,
            stderr: ["npm error code EPERM", "npm error syscall unlink"]
        )
        #expect(outcome == .needsPrivileges)
    }

    // MARK: - The network surface

    @Test(
        "Every npm network code is a failure that names the network",
        arguments: ["ENOTFOUND", "ETIMEDOUT", "ECONNREFUSED", "EAI_AGAIN"]
    )
    func networkCodesNameTheNetwork(code: String) throws {
        let command = try Self.upgrade()

        let outcome = Self.classify(command, status: 1, stderr: ["npm error code \(code)"])

        #expect(outcome == .networkUnavailable)
        #expect(outcome.isFailure)
        let message = outcome.message(for: command)
        #expect(message.localizedCaseInsensitiveContains("network"))
        #expect(message.contains("Homebrew") == false)
    }

    @Test("The captured offline report classifies as a network failure")
    func capturedOfflineReportIsNetwork() throws {
        let command = try Self.upgrade()
        let stderr = try NpmFixture.text("outdated-g-offline.stderr")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        #expect(Self.classify(command, status: 1, stderr: stderr) == .networkUnavailable)
    }

    // MARK: - Everything else is a generic failure with its log

    @Test("An unrecognised non-zero exit is a generic failure naming npm")
    func unrecognisedFailureNamesNpm() throws {
        let command = try Self.upgrade()

        let outcome = Self.classify(
            command,
            status: 7,
            stderr: ["npm error something nobody has seen before"]
        )

        #expect(outcome == .failed(status: 7))
        let message = outcome.message(for: command)
        #expect(message.contains("npm exited with status 7"))
        #expect(message.contains("Homebrew") == false)
    }

    // MARK: - Brew's signatures never classify an npm run

    /// Brew's lock, sudo-prompt and untrusted-tap phrases are brew's vocabulary.
    /// A package's own output echoing one of them must not make an npm run
    /// report "Homebrew is busy" or offer a Trust button for a tap npm has never
    /// heard of.
    @Test(
        "Brew's own signatures never classify an npm run",
        arguments: [
            "Another active Homebrew process has already locked",
            "Please wait for it to finish or terminate it to continue",
            "sudo: a password is required",
            "Refusing to load formula from untrusted tap",
        ]
    )
    func brewSignaturesNeverApply(line: String) throws {
        let command = try Self.upgrade()

        let outcome = Self.classify(command, status: 1, stderr: ["npm error", line])

        #expect(outcome == .failed(status: 1))
        #expect(outcome != .busy)
        #expect(outcome != .refusedUntrustedTap)
    }

    /// And the reverse containment: adding npm's codes to the shared classifier
    /// must not have taught a **brew** command to answer to them.
    @Test("npm's codes never classify a brew run")
    func npmCodesNeverClassifyBrew() throws {
        let brew = try #require(MutationCommand.upgrade(formula: "wget"))

        let outcome = brew.classify(
            exit: BrewExit(status: 1, reason: .exited),
            fault: nil,
            log: [LogLine(stream: .stderr, text: "Error: ENOTFOUND registry", sequence: 0)]
        )

        #expect(outcome == .failed(status: 1))
        #expect(outcome.message(for: brew).contains("Homebrew exited with status 1"))
    }

    // MARK: - The structural facts the ordering rests on

    @Test("A fault and a cancellation are decided before any npm prose is read")
    func faultsAndCancellationsWinOverProse() throws {
        let command = try Self.upgrade()

        #expect(
            Self.classify(
                command,
                status: 127,
                fault: .launchFailed(URL(fileURLWithPath: "/opt/homebrew/bin/npm"), code: 2),
                stderr: ["npm error code EACCES"]
            ) == .launchFailed
        )
        #expect(
            Self.classify(
                command,
                status: 130,
                reason: .cancelled(signal: SIGINT),
                stderr: ["npm error code ENOTFOUND"]
            ) == .cancelled
        )
    }
}
