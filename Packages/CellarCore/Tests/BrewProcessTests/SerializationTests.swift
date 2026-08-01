import Foundation
import Testing

@testable import BrewProcess

/// Time-limited: a broken gate deadlocks rather than failing an expectation.
@Suite("Serialized mutations with concurrent reads", .timeLimit(.minutes(1)))
struct SerializationTests {
    private func formulae(of launcher: FakeProcessLauncher) -> [String] {
        launcher.recordedSpecs.compactMap(\.arguments.last)
    }

    @Test("Three mutations run one at a time, in submission order")
    func mutationsNeverOverlapAndKeepSubmissionOrder() async throws {
        let launcher = FakeProcessLauncher()
        let first = FakeProcess()
        let second = FakeProcess()
        let third = FakeProcess()
        launcher.enqueue(first)
        launcher.enqueue(second)
        launcher.enqueue(third)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.mutate(["upgrade", "first"]))
        _ = try await runner.start(.mutate(["upgrade", "second"]))
        _ = try await runner.start(.mutate(["upgrade", "third"]))

        await launcher.waitForLaunches(atLeast: 1)
        await launcher.settle()
        #expect(launcher.launchCount == 1)
        #expect(formulae(of: launcher) == ["first"])

        first.terminate(with: BrewExit(status: 0, reason: .exited))
        await launcher.waitForLaunches(atLeast: 2)
        await launcher.settle()
        #expect(launcher.launchCount == 2)
        #expect(second.hasTerminated == false)

        second.terminate(with: BrewExit(status: 0, reason: .exited))
        await launcher.waitForLaunches(atLeast: 3)
        third.terminate(with: BrewExit(status: 0, reason: .exited))

        #expect(formulae(of: launcher) == ["first", "second", "third"])
    }

    @Test("A read starts and completes while a mutation is still running")
    func readsAreNotBlockedByAnInFlightMutation() async throws {
        let launcher = FakeProcessLauncher()
        let mutation = FakeProcess()
        let read = FakeProcess()
        launcher.enqueue(mutation)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.mutate(["upgrade", "ripgrep"]))
        await launcher.waitForLaunches(atLeast: 1)

        launcher.enqueue(read)
        let readOperation = try await runner.start(.read(["list"]))
        read.emitStdout("ripgrep\n")
        read.terminate(with: BrewExit(status: 0, reason: .exited))

        var lines: [LogLine] = []
        for await line in readOperation.lines { lines.append(line) }
        let readExit = await readOperation.exit()

        #expect(lines.map(\.text) == ["ripgrep"])
        #expect(readExit.isSuccess)
        // The mutation is untouched and still in flight.
        #expect(mutation.hasTerminated == false)
        #expect(launcher.launchCount == 2)

        mutation.terminate(with: BrewExit(status: 0, reason: .exited))
    }

    @Test("Cancelling a queued mutation spawns nothing and reports cancelled")
    func cancellingAQueuedMutationSpawnsNothing() async throws {
        let launcher = FakeProcessLauncher()
        let running = FakeProcess()
        launcher.enqueue(running)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.mutate(["upgrade", "running"]))
        let queued = try await runner.start(.mutate(["upgrade", "queued"]))
        await launcher.waitForLaunches(atLeast: 1)

        await queued.cancel()
        let queuedExit = await queued.exit()

        #expect(queuedExit.isCancelled)
        #expect(queuedExit.reason == .cancelled(signal: SIGINT))
        #expect(launcher.launchCount == 1)

        // Releasing the gate must not resurrect the cancelled mutation.
        running.terminate(with: BrewExit(status: 0, reason: .exited))
        await launcher.settle()
        #expect(launcher.launchCount == 1)
        #expect(formulae(of: launcher) == ["running"])
    }

    @Test("A cancelled mutation releases the gate for the one behind it")
    func cancellingAQueuedMutationLetsTheNextOneThrough() async throws {
        let launcher = FakeProcessLauncher()
        let running = FakeProcess()
        let last = FakeProcess()
        launcher.enqueue(running)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.mutate(["upgrade", "running"]))
        let queued = try await runner.start(.mutate(["upgrade", "queued"]))
        _ = try await runner.start(.mutate(["upgrade", "last"]))
        await launcher.waitForLaunches(atLeast: 1)

        await queued.cancel()
        launcher.enqueue(last)
        running.terminate(with: BrewExit(status: 0, reason: .exited))
        await launcher.waitForLaunches(atLeast: 2)

        #expect(formulae(of: launcher) == ["running", "last"])
        last.terminate(with: BrewExit(status: 0, reason: .exited))
    }

    @Test("A queued mutation whose spawn fails reports the fault and frees the gate")
    func deferredSpawnFailureIsReportedAndReleasesTheGate() async throws {
        let launcher = FakeProcessLauncher()
        let running = FakeProcess()
        launcher.enqueue(running)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.mutate(["upgrade", "running"]))
        let doomed = try await runner.start(.mutate(["upgrade", "doomed"]))
        await launcher.waitForLaunches(atLeast: 1)

        launcher.failLaunch(with: CocoaError(.fileNoSuchFile))
        running.terminate(with: BrewExit(status: 0, reason: .exited))

        let fault = await withTimeoutFault(doomed)
        #expect(fault == .executableUnavailable(BrewInstallation.fixture.executableURL))

        var lines: [LogLine] = []
        for await line in doomed.lines { lines.append(line) }
        #expect(lines.isEmpty)
    }

    /// Waits for the operation to reach its terminal state, then reads its fault.
    private func withTimeoutFault(_ operation: BrewOperation) async -> BrewProcessError? {
        _ = await operation.exit()
        return await operation.fault()
    }
}
