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

    @Test("An unknown operation identity yields a typed unknown result rather than success")
    func anUnknownOperationYieldsATypedUnknownResultRatherThanSuccess() async throws {
        let launcher = FakeProcessLauncher()
        let process = FakeProcess()
        launcher.enqueue(process)
        // Zero retained terminal records, so a released operation is retired
        // immediately: the spec's second unknown identity — "one whose record
        // has already been retired" — is reachable without waiting on a cap.
        let runner = BrewRunner(installation: .fixture, launcher: launcher, retainedTerminalRecords: 0)

        // An identity the runner was never asked to run.
        let neverSubmitted = await runner.exit(of: UUID())

        #expect(neverSubmitted.reason == .unknownOperation)
        #expect(neverSubmitted.isSuccess == false, "an unknown identity was answered with a success")
        #expect(neverSubmitted != BrewExit(status: 0, reason: .exited))
        #expect(launcher.launchCount == 0, "asking about an unknown identity spawned a process")

        // The same entry point still answers a known identity with its real
        // exit — the unknown branch narrows nothing.
        let operation = try await runner.start(.read(["list"]))
        process.terminate(with: BrewExit(status: 0, reason: .exited))
        let known = await operation.exit()
        #expect(known == BrewExit(status: 0, reason: .exited))

        // And an identity whose record has been retired is unknown too, without
        // the released flag being what keeps the fabricated success unobserved.
        await runner.release(operation.id)
        let retired = await runner.exit(of: operation.id)

        #expect(retired.reason == .unknownOperation)
        #expect(retired.isSuccess == false)
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
