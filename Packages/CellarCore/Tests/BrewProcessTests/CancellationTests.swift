import Foundation
import Synchronization
import Testing

@testable import BrewProcess

@Suite("Cancellation escalates SIGINT then SIGTERM")
struct CancellationTests {
    /// Wires a runner to a scripted process on a manually advanced clock, so no
    /// grace period ever costs wall-clock time.
    private func makeRunner(
        behavior: FakeProcess.SignalBehavior
    ) -> (BrewRunner, FakeProcess, TestClock) {
        let clock = TestClock()
        let launcher = FakeProcessLauncher(clock: clock)
        let process = FakeProcess(behavior: behavior, clock: clock)
        launcher.enqueue(process)
        let runner = BrewRunner(
            installation: .fixture,
            launcher: launcher,
            policy: .default,
            clock: clock
        )
        return (runner, process, clock)
    }

    @Test("A cooperative process stops at SIGINT and reports cancelled")
    func cooperativeProcessStopsAtInterrupt() async throws {
        let (runner, process, _) = makeRunner(behavior: .exitOnInterrupt)
        let operation = try await runner.start(.mutate(["upgrade", "ripgrep"]))

        await operation.cancel()
        let exit = await operation.exit()

        #expect(process.deliveredSignals == [.interrupt])
        #expect(exit.reason == .cancelled(signal: SIGINT))
        #expect(exit.isCancelled)
        #expect(await operation.fault() == nil)
    }

    @Test("A process that ignores SIGINT is escalated to SIGTERM after the grace")
    func unresponsiveProcessIsEscalated() async throws {
        let (runner, process, clock) = makeRunner(behavior: .exitOnTerminate)
        let operation = try await runner.start(.mutate(["upgrade", "ripgrep"]))

        let cancellation = Task { await operation.cancel() }
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(3))
        await cancellation.value

        let exit = await operation.exit()

        #expect(process.deliveredSignals == [.interrupt, .terminate])
        #expect(exit.reason == .cancelled(signal: SIGTERM))
        #expect(await operation.fault() == nil)
    }

    @Test("SIGTERM is only sent after the interrupt grace has actually elapsed")
    func terminateWaitsForTheInterruptGrace() async throws {
        let (runner, process, clock) = makeRunner(behavior: .exitOnTerminate)
        let operation = try await runner.start(.mutate(["upgrade", "ripgrep"]))

        let cancellation = Task { await operation.cancel() }
        await clock.waitForSleepers()

        // Time has not moved yet: the interrupt is out, the escalation is not.
        #expect(process.deliveredSignals == [.interrupt])

        await clock.advance(by: .seconds(3))
        await cancellation.value

        #expect(process.deliveredSignals == [.interrupt, .terminate])
    }

    @Test("A process ignoring both signals is reported unresponsive, never killed")
    func unresponsiveProcessIsNeverKilled() async throws {
        let (runner, process, clock) = makeRunner(behavior: .ignoreAll)
        let operation = try await runner.start(.mutate(["upgrade", "ripgrep"]))

        let cancellation = Task { await operation.cancel() }
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(3))
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(2))
        await cancellation.value

        // SIGINT then SIGTERM, and nothing after: escalation stops at SIGTERM
        // because SIGKILL would leave a stale lock and a half-linked keg (D4).
        #expect(process.deliveredSignals == [.interrupt, .terminate])
        #expect(process.hasTerminated == false)
        #expect(await operation.fault() == .cancelledUnresponsive(after: .seconds(5)))
    }

    @Test("Delivered signals are timestamped in escalation order on the injected clock")
    func signalsAreOrderedInTime() async throws {
        let (runner, process, clock) = makeRunner(behavior: .exitOnTerminate)
        let operation = try await runner.start(.mutate(["upgrade", "ripgrep"]))

        let cancellation = Task { await operation.cancel() }
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(3))
        await cancellation.value

        let records = process.recordedSignals
        #expect(records.count == 2)
        #expect(records.first?.instant == TestClock.Instant(offset: .zero))
        #expect(records.last?.instant == TestClock.Instant(offset: .seconds(3)))
    }

    @Test("Cancelling the consuming Swift task escalates the same way")
    func cancellingTheConsumerCancelsTheProcess() async throws {
        let (runner, process, _) = makeRunner(behavior: .exitOnInterrupt)
        let operation = try await runner.start(.mutate(["upgrade", "ripgrep"]))

        let consuming = Mutex(false)
        let consumer = Task {
            for await _ in operation.lines { consuming.withLock { $0 = true } }
        }
        process.emitStdout("==> Upgrading\n")
        await TestPoll.until(consuming.withLock { $0 })
        consumer.cancel()

        await process.waitForSignals(atLeast: 1)
        let exit = await operation.exit()

        #expect(process.deliveredSignals == [.interrupt])
        #expect(exit.reason == .cancelled(signal: SIGINT))
    }

    @Test("Cancelling an already-finished operation changes nothing")
    func cancellingAfterCompletionIsANoOp() async throws {
        let (runner, process, _) = makeRunner(behavior: .exitOnInterrupt)
        let operation = try await runner.start(.mutate(["list"]))
        process.terminate(with: BrewExit(status: 0, reason: .exited))
        let exit = await operation.exit()

        await operation.cancel()

        #expect(exit.isSuccess)
        #expect(process.deliveredSignals.isEmpty)
        #expect(await operation.exit() == exit)
    }
}
