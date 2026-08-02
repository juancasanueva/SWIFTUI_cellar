import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// Threat row — **untrusted subprocess payload**.
///
/// `brew`'s stdout is arbitrary bytes of arbitrary size written by a program
/// Cellar does not control. Everything that decides what those bytes *mean*
/// lives in one pure function, so every hostile shape is reachable here with no
/// process, no fake launcher, and no timing (design D2).
@Suite("Installed payload acquisition")
struct InstalledPayloadTests {
    private func stdout(_ text: String, _ sequence: Int) -> LogLine {
        LogLine(stream: .stdout, text: text, sequence: sequence)
    }

    private func stderr(_ text: String, _ sequence: Int) -> LogLine {
        LogLine(stream: .stderr, text: text, sequence: sequence)
    }

    private let ok = BrewExit(status: 0, reason: .exited)

    @Test("A well-formed run yields exactly the stdout bytes")
    func successYieldsStdoutBytes() throws {
        let lines = [stdout("{\"formulae\":[],", 0), stdout("\"casks\":[]}", 1)]

        let payload = try InstalledPayload.payload(from: lines, exit: ok)

        #expect(String(decoding: payload, as: UTF8.self) == "{\"formulae\":[],\n\"casks\":[]}")
    }

    @Test("A non-zero exit is an error carrying the stderr tail, never an empty inventory")
    func nonZeroExitIsAnErrorNotAnEmptyInventory() {
        // A plausible hostile shape: brew fails *and* prints a valid-looking
        // empty envelope. Reading that as "nothing is installed" would wipe the
        // user's list on a transient lock failure.
        let lines = [
            stdout("{\"formulae\":[],\"casks\":[]}", 0),
            stderr("Warning: some earlier noise", 1),
            stderr("Error: Another active Homebrew process is already running.", 2)
        ]

        let failure = BrewExit(status: 1, reason: .exited)

        #expect(throws: InstalledInventoryError.self) {
            try InstalledPayload.payload(from: lines, exit: failure)
        }

        guard
            let error = capture({ try InstalledPayload.payload(from: lines, exit: failure) }),
            case .commandFailed(let status, let message) = error
        else {
            Issue.record("expected `.commandFailed`")
            return
        }
        #expect(status == 1)
        #expect(message.contains("Another active Homebrew process is already running."))
    }

    /// Triangulation: a *different* status must survive into the error rather
    /// than being flattened to a constant.
    @Test("The reported status is the one the process actually returned")
    func reportedStatusIsTheProcessStatus() {
        let failure = BrewExit(status: 77, reason: .exited)

        guard
            let error = capture({
                try InstalledPayload.payload(from: [stderr("boom", 0)], exit: failure)
            }),
            case .commandFailed(let status, let message) = error
        else {
            Issue.record("expected `.commandFailed`")
            return
        }
        #expect(status == 77)
        #expect(message == "boom")
    }

    @Test("A long stderr is reported as its tail, where the reason usually is")
    func stderrIsReportedAsATail() {
        let noise = (0..<40).map { stderr("noise line \($0)", $0) }
        let lines = noise + [stderr("Error: the actual reason", 40)]

        guard
            let error = capture({
                try InstalledPayload.payload(from: lines, exit: BrewExit(status: 1, reason: .exited))
            }),
            case .commandFailed(_, let message) = error
        else {
            Issue.record("expected `.commandFailed`")
            return
        }
        #expect(message.contains("Error: the actual reason"))
        #expect(message.contains("noise line 0") == false)
    }

    @Test("Empty stdout is malformed, not an empty inventory")
    func emptyStdoutIsMalformed() {
        let lines = [stderr("brew said nothing useful", 0)]

        #expect(throws: InstalledInventoryError.malformedPayload) {
            try InstalledPayload.payload(from: lines, exit: ok)
        }
        // Whitespace-only stdout is the same fact written differently.
        #expect(throws: InstalledInventoryError.malformedPayload) {
            try InstalledPayload.payload(from: [stdout("   ", 0)], exit: ok)
        }
    }

    @Test("Interleaved stderr never enters the joined JSON")
    func interleavedStderrNeverEntersTheJSON() throws {
        let lines = [
            stdout("{\"formulae\":[],", 0),
            stderr("Warning: you are using a deprecated tap", 1),
            stdout("\"casks\":[]}", 2)
        ]

        let payload = try InstalledPayload.payload(from: lines, exit: ok)
        let text = String(decoding: payload, as: UTF8.self)

        #expect(text.contains("Warning") == false)
        // Proof the payload is still the parseable document, not merely
        // "something without the warning in it".
        let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        #expect(object?.keys.sorted() == ["casks", "formulae"])
    }

    @Test("A cancelled run is reported as cancelled, not as a failure")
    func cancelledRunIsReportedAsCancelled() {
        let cancelled = BrewExit(status: 130, reason: .cancelled(signal: SIGINT))

        #expect(throws: InstalledInventoryError.cancelled) {
            try InstalledPayload.payload(from: [stdout("{}", 0)], exit: cancelled)
        }
    }

    /// `#expect(throws:)` reports a mismatch but hands nothing back, and these
    /// assertions are about the error's *contents*.
    private func capture(
        _ body: () throws -> Data
    ) -> InstalledInventoryError? {
        do {
            _ = try body()
            return nil
        } catch let error as InstalledInventoryError {
            return error
        } catch {
            return nil
        }
    }
}
