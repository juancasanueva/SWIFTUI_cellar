import BrewProcess
import Foundation
import Testing

@testable import BrewClient

/// npm's exit codes do not mean what brew's mean, and this is the adapter that
/// says so. `npm outdated -g --json` exits `1` on its ordinary success path —
/// "something is outdated" — and `npm ls -g --json` exits `1` while printing a
/// complete document when a global package has an unsatisfied dependency
/// (`ELSPROBLEMS`). Both are captured in `Fixtures/Npm/`, from the real binary.
///
/// The rule this suite protects most carefully is the one whose failure is
/// silent: a non-zero exit with no readable document must be a **failure**, not
/// an empty inventory. An empty inventory presented as healthy reads as "you
/// have no global packages", which is indistinguishable from the truth for a
/// user who cannot see the exit code.
@Suite("npm payload exit matrix")
struct NpmPayloadTests {
    private static func lines(stdout: String = "", stderr: String = "") -> [LogLine] {
        var lines: [LogLine] = []
        if stdout.isEmpty == false {
            lines.append(contentsOf: NpmFixture.lines(stdout, stream: .stdout))
        }
        if stderr.isEmpty == false {
            lines.append(contentsOf: NpmFixture.lines(stderr, stream: .stderr))
        }
        return lines.enumerated().map {
            LogLine(stream: $0.element.stream, text: $0.element.text, sequence: $0.offset)
        }
    }

    private static func exited(_ status: Int32) -> BrewExit {
        BrewExit(status: status, reason: .exited)
    }

    private static let document = #"{"name":"lib","dependencies":{"pnpm":{"version":"10.13.1"}}}"#

    // MARK: - `ls -g`

    @Test("Exit 0 with a document is accepted")
    func listingExitZeroIsAccepted() throws {
        let data = try NpmPayload.installed(
            from: Self.lines(stdout: Self.document), exit: Self.exited(0)
        )

        #expect(String(decoding: data, as: UTF8.self) == Self.document)
    }

    @Test("Exit 1 with a parseable document is accepted — npm's ELSPROBLEMS case")
    func listingExitOneWithDocumentIsAccepted() throws {
        let data = try NpmPayload.installed(
            from: Self.lines(
                stdout: Self.document,
                stderr: "npm error code ELSPROBLEMS\nnpm error missing: left-pad@^1.3.0"
            ),
            exit: Self.exited(1)
        )

        #expect(String(decoding: data, as: UTF8.self) == Self.document)
    }

    @Test("Exit 1 with unparseable stdout is a failure, never an empty inventory")
    func listingExitOneWithGarbageIsAFailure() {
        #expect(throws: NpmInventoryError.commandFailed(status: 1, message: "npm error code EJSONPARSE")) {
            try NpmPayload.installed(
                from: Self.lines(stdout: "not json at all", stderr: "npm error code EJSONPARSE"),
                exit: Self.exited(1)
            )
        }
    }

    @Test("Exit 1 with empty stdout is a failure")
    func listingExitOneWithNoStdoutIsAFailure() {
        #expect(throws: NpmInventoryError.self) {
            try NpmPayload.installed(
                from: Self.lines(stderr: "npm error code ELSPROBLEMS"), exit: Self.exited(1)
            )
        }
    }

    @Test("Any exit above 1 is a failure even with a perfect document on stdout")
    func listingExitTwoIsAlwaysAFailure() {
        #expect(throws: NpmInventoryError.self) {
            try NpmPayload.installed(
                from: Self.lines(stdout: Self.document, stderr: "npm error code EACCES"),
                exit: Self.exited(2)
            )
        }
    }

    @Test("A document on stderr only is a failure, not an inventory")
    func listingDocumentOnStderrIsAFailure() {
        #expect(throws: NpmInventoryError.self) {
            try NpmPayload.installed(from: Self.lines(stderr: Self.document), exit: Self.exited(0))
        }
    }

    @Test("Only stdout enters the document, whatever stderr interleaves")
    func stderrNeverEntersTheDocument() throws {
        let interleaved = [
            LogLine(stream: .stderr, text: "npm warn deprecated foo@1.0.0", sequence: 0),
            LogLine(stream: .stdout, text: Self.document, sequence: 1),
            LogLine(stream: .stderr, text: "npm notice something", sequence: 2),
        ]

        let data = try NpmPayload.installed(from: interleaved, exit: Self.exited(0))

        #expect(String(decoding: data, as: UTF8.self) == Self.document)
    }

    @Test("Exit 0 with blank stdout is malformed, not an empty inventory")
    func listingBlankStdoutIsMalformed() {
        #expect(throws: NpmInventoryError.malformedPayload) {
            try NpmPayload.installed(from: Self.lines(stdout: "   \n  "), exit: Self.exited(0))
        }
    }

    @Test("A cancelled run is cancelled, never a failure and never empty")
    func cancellationIsItsOwnOutcome() {
        #expect(throws: NpmInventoryError.cancelled) {
            try NpmPayload.installed(
                from: Self.lines(stdout: Self.document),
                exit: BrewExit(status: 130, reason: .cancelled(signal: SIGINT))
            )
        }
    }

    // MARK: - `outdated -g`

    @Test("Outdated accepts exit 0 and exit 1 alike")
    func outdatedAcceptsZeroAndOne() throws {
        let report = #"{"pnpm":{"current":"10.13.1","wanted":"11.0.0","latest":"11.0.0"}}"#

        let clean = try NpmPayload.outdated(from: Self.lines(stdout: "{}"), exit: Self.exited(0))
        let dirty = try NpmPayload.outdated(from: Self.lines(stdout: report), exit: Self.exited(1))

        #expect(String(decoding: clean, as: UTF8.self) == "{}")
        #expect(String(decoding: dirty, as: UTF8.self) == report)
    }

    @Test("Outdated with blank stdout at exit 0 is the empty report, not a failure")
    func outdatedBlankAtExitZeroIsEmpty() throws {
        // Real behaviour: `npm outdated -g --json` for a package that is current
        // prints `{}`, but a run that matches nothing at all prints nothing.
        // Blank at exit 0 means "nothing is outdated", which is a fact, not a
        // missing answer — the one place blankness is legitimate.
        let data = try NpmPayload.outdated(from: [], exit: Self.exited(0))

        #expect(String(decoding: data, as: UTF8.self) == "{}")
    }

    @Test("Outdated with blank stdout at exit 1 is a failure")
    func outdatedBlankAtExitOneIsAFailure() {
        #expect(throws: NpmInventoryError.self) {
            try NpmPayload.outdated(
                from: Self.lines(stderr: "npm error code ENOTFOUND"), exit: Self.exited(1)
            )
        }
    }

    @Test("An offline run is a network failure rather than a generic one")
    func offlineStderrIsClassifiedAsNetwork() throws {
        let stderr = try NpmFixture.text("outdated-g-offline.stderr")

        #expect(throws: NpmInventoryError.networkUnavailable) {
            try NpmPayload.outdated(from: Self.lines(stderr: stderr), exit: Self.exited(1))
        }
    }

    @Test("Every npm network signature is recognised, and none of brew's are borrowed")
    func networkSignaturesAreNpmsOwn() {
        for code in ["ENOTFOUND", "ETIMEDOUT", "ECONNREFUSED", "EAI_AGAIN"] {
            #expect(throws: NpmInventoryError.networkUnavailable) {
                try NpmPayload.outdated(
                    from: Self.lines(stderr: "npm error code \(code)"), exit: Self.exited(1)
                )
            }
        }
        // Homebrew's own vocabulary must classify nothing here.
        #expect(throws: NpmInventoryError.self) {
            try NpmPayload.outdated(
                from: Self.lines(stderr: "Another active Homebrew process is already in progress"),
                exit: Self.exited(1)
            )
        }
        let brewShaped = #expect(throws: NpmInventoryError.self) {
            try NpmPayload.outdated(
                from: Self.lines(stderr: "Error: Permission denied @ rb_sysopen"),
                exit: Self.exited(1)
            )
        }
        #expect(brewShaped != .networkUnavailable)
    }

    @Test("A network failure on the listing path is classified too")
    func listingAlsoClassifiesNetworkFailures() {
        #expect(throws: NpmInventoryError.networkUnavailable) {
            try NpmPayload.installed(
                from: Self.lines(stderr: "npm error code ETIMEDOUT"), exit: Self.exited(1)
            )
        }
    }

    @Test("The failure message carries the stderr tail so the log is not lost")
    func failureCarriesTheStderrTail() {
        let error = #expect(throws: NpmInventoryError.self) {
            try NpmPayload.installed(
                from: Self.lines(stderr: "npm error code EUNKNOWN\nnpm error something broke"),
                exit: Self.exited(9)
            )
        }

        guard case .commandFailed(let status, let message) = error else {
            Issue.record("expected commandFailed, got \(String(describing: error))")
            return
        }
        #expect(status == 9)
        #expect(message.contains("npm error something broke"))
        #expect(message.contains("Homebrew") == false)
    }
}
