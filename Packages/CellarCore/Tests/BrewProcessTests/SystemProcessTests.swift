import Foundation
import Testing

@testable import BrewProcess

/// Integration coverage for the real `Foundation.Process` bridge. These use
/// system binaries that exist on every macOS install, so they never skip.
@Suite("SystemProcess bridges Foundation.Process")
struct SystemProcessTests {
    private func installation(at path: String) -> BrewInstallation {
        BrewInstallation(
            executableURL: URL(fileURLWithPath: path),
            prefix: .custom(URL(fileURLWithPath: path)),
            version: BrewVersion(major: 4, minor: 0, patch: 0)
        )
    }

    @Test("A real /bin/echo run streams its line and exits 0")
    func echoStreamsOneLineAndExitsZero() async throws {
        let runner = BrewRunner(
            installation: installation(at: "/bin/echo"),
            launcher: SystemProcessLauncher()
        )

        let operation = try await runner.start(.read(["hello from cellar"]))

        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        let exit = await operation.exit()

        #expect(lines.map(\.text) == ["hello from cellar"])
        #expect(lines.first?.stream == .stdout)
        #expect(lines.first?.sequence == 0)
        #expect(exit == BrewExit(status: 0, reason: .exited))
    }

    @Test("Multi-line real output keeps its order and sequence")
    func multiLineOutputIsOrdered() async throws {
        let runner = BrewRunner(
            installation: installation(at: "/bin/echo"),
            launcher: SystemProcessLauncher()
        )

        let operation = try await runner.start(.read(["one\ntwo\nthree"]))

        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        _ = await operation.exit()

        #expect(lines.map(\.text) == ["one", "two", "three"])
        #expect(lines.map(\.sequence) == [0, 1, 2])
    }

    @Test("A real non-zero exit is reported as a result, not an error")
    func nonZeroExitFromRealBinary() async throws {
        let runner = BrewRunner(
            installation: installation(at: "/usr/bin/false"),
            launcher: SystemProcessLauncher()
        )

        let operation = try await runner.start(.read([]))
        for await _ in operation.lines {}
        let exit = await operation.exit()

        #expect(exit == BrewExit(status: 1, reason: .exited))
    }

    @Test("Spawning a path that does not exist reports executableUnavailable")
    func missingBinaryReportsUnavailable() async {
        let missing = "/opt/homebrew/bin/definitely-not-a-real-binary"
        let runner = BrewRunner(
            installation: installation(at: missing),
            launcher: SystemProcessLauncher()
        )

        await #expect(throws: BrewProcessError.executableUnavailable(URL(fileURLWithPath: missing))) {
            _ = try await runner.start(.read([]))
        }
    }
}
