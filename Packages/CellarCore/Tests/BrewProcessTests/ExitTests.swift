import Foundation
import Testing

@testable import BrewProcess

@Suite("Terminal result and exit handling")
struct ExitTests {
    @Test("A non-zero exit is a result carrying its code, not a thrown error")
    func nonZeroExitIsReportedAsAResult() async throws {
        let launcher = FakeProcessLauncher()
        let process = FakeProcess()
        launcher.enqueue(process)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        let operation = try await runner.start(.read(["outdated"]))
        process.emitStdout("Error: No available formula\n")
        process.terminate(with: BrewExit(status: 1, reason: .exited))

        let exit = await operation.exit()

        #expect(exit == BrewExit(status: 1, reason: .exited))
        #expect(exit.isSuccess == false)
    }

    @Test("Every emitted line is observable before the exit resolves")
    func linesAreObservableBeforeTheResult() async throws {
        let launcher = FakeProcessLauncher()
        let process = FakeProcess()
        launcher.enqueue(process)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        let operation = try await runner.start(.read(["outdated"]))
        process.emitStdout("first\nsecond\n")
        process.terminate(with: BrewExit(status: 1, reason: .exited))

        let exit = await operation.exit()

        // The stream has already finished by the time the exit resolves, so
        // draining it now returns everything the process produced.
        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }

        #expect(lines.map(\.text) == ["first", "second"])
        #expect(exit.status == 1)
    }

    @Test("A successful run reports exit 0")
    func successfulExit() async throws {
        let launcher = FakeProcessLauncher()
        let process = FakeProcess()
        launcher.enqueue(process)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        let operation = try await runner.start(.read(["list"]))
        process.terminate(with: BrewExit(status: 0, reason: .exited))

        let exit = await operation.exit()

        #expect(exit.isSuccess)
    }

    @Test("Asking for the exit twice returns the same terminal result")
    func exitIsIdempotent() async throws {
        let launcher = FakeProcessLauncher()
        let process = FakeProcess()
        launcher.enqueue(process)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        let operation = try await runner.start(.read(["list"]))
        process.terminate(with: BrewExit(status: 42, reason: .exited))

        let first = await operation.exit()
        let second = await operation.exit()

        #expect(first == second)
        #expect(second.status == 42)
    }

    @Test("A missing executable is reported as executableUnavailable")
    func missingExecutableIsDistinct() async {
        let launcher = FakeProcessLauncher()
        launcher.failLaunch(with: CocoaError(.fileNoSuchFile))
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        await #expect(throws: BrewProcessError.executableUnavailable(BrewInstallation.fixture.executableURL)) {
            _ = try await runner.start(.read(["list"]))
        }
    }

    @Test("A permission failure is also executableUnavailable")
    func permissionDeniedIsUnavailable() async {
        let launcher = FakeProcessLauncher()
        launcher.failLaunch(with: POSIXError(.EACCES))
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        await #expect(throws: BrewProcessError.executableUnavailable(BrewInstallation.fixture.executableURL)) {
            _ = try await runner.start(.read(["list"]))
        }
    }

    @Test("Any other spawn fault is reported as launchFailed with its code")
    func otherSpawnFaultsCarryTheirCode() async {
        let launcher = FakeProcessLauncher()
        launcher.failLaunch(with: POSIXError(.ENOMEM))
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        await #expect(
            throws: BrewProcessError.launchFailed(
                BrewInstallation.fixture.executableURL,
                code: ENOMEM
            )
        ) {
            _ = try await runner.start(.read(["list"]))
        }
    }

    @Test("A failed spawn leaves no operation behind")
    func failedSpawnLeaksNoOperation() async throws {
        let launcher = FakeProcessLauncher()
        launcher.failLaunch(with: CocoaError(.fileNoSuchFile))
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try? await runner.start(.read(["list"]))

        let active = await runner.activeOperationCount
        #expect(active == 0)
        #expect(launcher.launchCount == 0)
    }
}
