import CellarTestSupport
import Foundation
import Testing

@testable import BrewProcess

// MARK: - Runner-record retention (brew-execution BE1, design D6)
//
// Three rules, in order:
//
//   R1  A record that is not terminal is never touched.
//   R2  On terminal ∧ drained the record is *compacted*: process, pump,
//       completion, continuation and lines are released; `id`, `command`,
//       `ordinal`, `resolvedExit` and `fault` survive, so `exit(of:)` and
//       `fault(of:)` still answer exactly.
//   R3  A compacted record is *removed* only once its `BrewOperation` handle has
//       been released. Released-and-compacted records are additionally capped,
//       oldest ordinal first, so the true bound is `live handles + the cap`.
//
// Release is by **ownership**, not by timing: the handle's `deinit` hands its id
// back. That is what makes "a record can only be removed when no caller can
// still ask about it" structural rather than probabilistic — which is exactly
// the property BE1's "an operation still being awaited must remain answerable"
// needs.
//
// The cap is injected here rather than hard-coded at 200, on the `policy:` and
// `clock:` precedent: a retention rule whose only test is "run 260 operations"
// is a rule nobody re-tests after they change it. The shipped default is still
// 200.

@Suite("Runner record retention", .timeLimit(.minutes(1)))
struct RetentionTests {
    private static let cap = 3

    private static func runner(_ launcher: FakeProcessLauncher) -> BrewRunner {
        BrewRunner(installation: .fixture, launcher: launcher, retainedTerminalRecords: cap)
    }

    /// `TestPoll.until` takes a synchronous autoclosure; every condition here
    /// has to hop onto the runner's actor first. Release is driven by `deinit`,
    /// which schedules its hand-back rather than performing it inline, so the
    /// assertions poll instead of assuming the next yield is enough.
    private static func poll(
        timeout: Duration = .seconds(5),
        until condition: @Sendable () async -> Bool
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while await !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    /// Runs one read operation to a terminal outcome and drains it.
    ///
    /// Returns the handle so the caller decides when it dies — which is the
    /// whole point of R3.
    @discardableResult
    private static func runDrainedRead(
        on runner: BrewRunner,
        launcher: FakeProcessLauncher,
        index: Int,
        status: Int32 = 0
    ) async throws -> BrewOperation {
        let operation = try await runner.start(.read(["list", "--versions"]))
        await launcher.waitForLaunches(atLeast: index + 1)
        launcher.launchedProcesses[index].terminate(with: BrewExit(status: status, reason: .exited))
        for await _ in operation.lines {}
        _ = await operation.exit()
        return operation
    }

    // MARK: - R2 / BE1 sc7 — records stop accumulating

    @Test("Drained terminal records stop accumulating once their handles die")
    func drainedRecordsAreBounded() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)
        let total = Self.cap * 4

        for index in 0..<total {
            // The handle dies at the end of each iteration, so every record is
            // released as well as compacted.
            _ = try await Self.runDrainedRead(on: runner, launcher: launcher, index: index)
        }
        await Self.poll { await runner.activeOperationCount <= Self.cap }

        let held = await runner.activeOperationCount
        #expect(held == Self.cap)
        #expect(held < total, "records grew with the number of operations run")
    }

    // MARK: - R1 / BE1 sc9 — retirement never touches pending or running work

    @Test("Retirement leaves the running and pending operations enumerated in order")
    func retirementNeverTouchesLiveWork() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        // Three drained terminal reads first, each released immediately.
        for index in 0..<3 {
            _ = try await Self.runDrainedRead(on: runner, launcher: launcher, index: index)
        }

        // Then a running mutation with another queued behind it.
        let running = try await runner.start(.mutate(["upgrade", "--formula", "wget"]))
        await launcher.waitForLaunches(atLeast: 4)
        let pending = try await runner.start(.mutate(["upgrade", "--formula", "git"]))
        await Self.poll { await runner.snapshot().running.count == 1 }
        let launchesBefore = launcher.launchCount

        // Force several retirement passes by releasing more handles.
        for offset in 0..<4 {
            // Launch 3 is the running mutation; the pending one has not spawned.
            _ = try await Self.runDrainedRead(on: runner, launcher: launcher, index: 4 + offset)
        }
        await launcher.settle()

        let snapshot = await runner.snapshot()
        #expect(snapshot.running.map(\.id) == [running.id])
        #expect(snapshot.pending.map(\.id) == [pending.id])
        #expect(snapshot.pending.first?.command.arguments == ["upgrade", "--formula", "git"])
        #expect(await runner.holdsExecutionResources(running.id), "a running record was compacted")
        // Nothing was spawned, cancelled or restarted on their behalf: the only
        // new launches are the four reads this block deliberately ran.
        #expect(launcher.launchCount == launchesBefore + 4)

        launcher.launchedProcesses[3].terminate(with: BrewExit(status: 0, reason: .exited))
        for await _ in running.lines {}
        _ = await running.exit()
    }

    // MARK: - R2 / BE1 sc8 — a compacted record still answers exactly

    @Test("A terminal record answers exit(of:) after its execution resources are released")
    func compactedRecordStillAnswersExit() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        let operation = try await runner.start(.read(["list"]))
        await launcher.waitForLaunches(atLeast: 1)
        launcher.launchedProcesses[0].emitStdout("wget 1.21.4\n")
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 3, reason: .exited))

        // Drain the output but never await the result before compaction.
        for await _ in operation.lines {}
        await Self.poll { await runner.isCompacted(operation.id) }

        #expect(await runner.holdsExecutionResources(operation.id) == false)
        let exit = await operation.exit()
        #expect(exit.status == 3)
        #expect(exit.reason == .exited)

        let entry = await runner.snapshot().operations.first { $0.id == operation.id }
        #expect(entry?.command.arguments == ["list"])
        #expect(entry?.phase.isTerminal == true)
    }

    @Test("A compacted record still answers fault(of:) with its out-of-band fault")
    func compactedRecordStillAnswersFault() async throws {
        let launcher = FakeProcessLauncher()
        launcher.failLaunch(with: POSIXError(.ENOENT))
        let runner = Self.runner(launcher)

        let operation = try await runner.start(.mutate(["upgrade", "--formula", "wget"]))
        await Self.poll { await runner.isCompacted(operation.id) }

        #expect(await runner.holdsExecutionResources(operation.id) == false)
        let executable = BrewInstallation.fixture.executableURL
        #expect(await operation.fault() == .executableUnavailable(executable))
        #expect(await operation.exit().status == 127)
    }

    // MARK: - R3 — removal is owned by the handle, not timed

    @Test("A record survives while its handle is alive and is removed only after release")
    func recordSurvivesWhileItsHandleIsAlive() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        // The oldest operation of all — and the one whose handle stays alive.
        var held: BrewOperation? = try await Self.runDrainedRead(
            on: runner,
            launcher: launcher,
            index: 0,
            status: 7
        )
        let heldID = try #require(held).id

        for index in 1...(Self.cap + 3) {
            _ = try await Self.runDrainedRead(on: runner, launcher: launcher, index: index)
        }
        await Self.poll { await runner.activeOperationCount <= Self.cap + 1 }

        // Oldest ordinal first — except the held one, which is not evictable at
        // any age, because its handle can still ask about it.
        #expect(await runner.activeOperationCount == Self.cap + 1)
        let entry = await runner.snapshot().operations.first { $0.id == heldID }
        #expect(entry?.phase.exit?.status == 7)

        held = nil
        await Self.poll { await runner.activeOperationCount == Self.cap }
        #expect(await runner.activeOperationCount == Self.cap)
        #expect(await runner.snapshot().operations.contains { $0.id == heldID } == false)
    }

    @Test("A retired operation is never reported pending or running and is never respawned")
    func retiredOperationIsNeverResurrected() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        var firstID: UUID?
        for index in 0...(Self.cap + 2) {
            let operation = try await Self.runDrainedRead(
                on: runner,
                launcher: launcher,
                index: index
            )
            if index == 0 { firstID = operation.id }
        }
        let retiredID = try #require(firstID)
        await Self.poll { await runner.activeOperationCount <= Self.cap }
        let launchesAfterRetirement = launcher.launchCount

        let snapshot = await runner.snapshot()
        #expect(snapshot.operations.contains { $0.id == retiredID } == false)
        #expect(snapshot.pending.isEmpty)
        #expect(snapshot.running.isEmpty)

        // Asking about a retired operation neither resurrects nor respawns it.
        await runner.cancel(retiredID)
        await launcher.settle()
        #expect(launcher.launchCount == launchesAfterRetirement)
        #expect(await runner.snapshot().operations.contains { $0.id == retiredID } == false)
        #expect(await runner.activeOperationCount == Self.cap)
    }
}
