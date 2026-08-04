import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

@Suite("Tap payload acquisition")
struct TapPayloadTests {
    @Test("The tap snapshot uses one exact read invocation")
    func exactReadInvocation() async throws {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: "[]\n", stderr: "", exit: BrewExit(status: 0, reason: .exited))
        ])
        let source = BrewTapPayloadSource(launcher: launcher)

        let payload = try await source.payload(using: TestInstallation.appleSilicon)

        #expect(String(decoding: payload, as: UTF8.self) == "[]")
        #expect(launcher.specs.map(\.arguments) == [["tap-info", "--installed", "--json"]])
        #expect(launcher.launchCount == 1)
    }

    @Test("Cancellation, non-zero and blank stdout remain distinct")
    func acquisitionFailuresRemainDistinct() {
        #expect(throws: TapInventoryError.cancelled) {
            try TapPayload.payload(from: [], exit: BrewExit(status: 130, reason: .cancelled(signal: 2)))
        }
        #expect {
            try TapPayload.payload(
                from: [LogLine(stream: .stderr, text: "failed", sequence: 0)],
                exit: BrewExit(status: 1, reason: .exited)
            )
        } throws: { error in
            (error as? TapInventoryError) == .commandFailed(status: 1, message: "failed")
        }
        #expect(throws: TapInventoryError.blankOutput) {
            try TapPayload.payload(
                from: [LogLine(stream: .stdout, text: "   ", sequence: 0)],
                exit: BrewExit(status: 0, reason: .exited)
            )
        }
    }
}
