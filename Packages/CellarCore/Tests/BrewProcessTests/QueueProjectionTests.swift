import CellarTestSupport
import Foundation
import Synchronization
import Testing

@testable import BrewProcess

/// The queue stops being a private detail and becomes a read-only projection
/// (brew-execution BE1, operation-activity OA1, OA3, OA4).
///
/// Everything here is derived from state the runner already keeps — `process`
/// (spawned yet?), `resolvedExit` (terminal?), `fault` — so there is no second
/// source of truth that can drift. Nothing spawns `brew` (design D12).
@Suite("Queue projection", .timeLimit(.minutes(1)))
struct QueueProjectionTests {
    private static func runner(_ launcher: FakeProcessLauncher) -> BrewRunner {
        BrewRunner(
            installation: BrewInstallation(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
                prefix: .appleSilicon,
                version: BrewVersion(major: 6, minor: 0, patch: 14)
            ),
            launcher: launcher
        )
    }

    private static func install(_ name: String) -> BrewCommand {
        .mutate(["install", "--formula", name])
    }

    private static func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    // MARK: - Enumeration, order and argv (BE1 sc4, sc6; OA1 sc1, sc3)

    @Test("Queued mutations are enumerable before they run, in FIFO order, with their argv")
    func queuedMutationsAreEnumerableInRunOrder() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        let first = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)
        let second = try await runner.start(Self.install("b"))
        let third = try await runner.start(Self.install("c"))
        await Self.settle()

        let snapshot = await runner.snapshot()

        #expect(snapshot.operations.map(\.id) == [first.id, second.id, third.id])
        #expect(snapshot.operations[0].phase == .running)
        #expect(snapshot.operations[1].phase == .pending)
        #expect(snapshot.operations[2].phase == .pending)

        // Each entry carries the argv its operation was submitted with.
        #expect(snapshot.operations.map(\.command.arguments) == [
            ["install", "--formula", "a"],
            ["install", "--formula", "b"],
            ["install", "--formula", "c"]
        ])

        // Only the running one has ever been spawned.
        #expect(launcher.launchCount == 1)

        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await first.exit()
        _ = await second.cancel()
        _ = await third.cancel()
    }

    /// Enumeration is read-only: it starts nothing, delays nothing, reorders
    /// nothing, and does not block on the operation in flight (BE1 sc6).
    @Test("Enumerating repeatedly while one runs spawns nothing and does not reorder")
    func enumeratingDoesNotPerturbScheduling() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        let first = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)
        let second = try await runner.start(Self.install("b"))
        let third = try await runner.start(Self.install("c"))
        await Self.settle()

        for _ in 0..<20 {
            let snapshot = await runner.snapshot()
            #expect(snapshot.operations.count == 3)
        }

        #expect(launcher.launchCount == 1, "enumerating spawned something")

        // And the start order after A completes is still B then C.
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await first.exit()
        await launcher.waitForLaunches(atLeast: 2)
        launcher.launchedProcesses[1].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await second.exit()
        await launcher.waitForLaunches(atLeast: 3)

        #expect(launcher.recordedSpecs.map(\.arguments) == [
            ["install", "--formula", "a"],
            ["install", "--formula", "b"],
            ["install", "--formula", "c"]
        ])

        launcher.launchedProcesses[2].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await third.exit()
    }

    // MARK: - Identity (BE1 sc5; OA1 sc2, sc4)

    @Test("The same command submitted twice yields two different, stable identities")
    func identitiesAreDistinctAndStable() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        let first = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)
        let second = try await runner.start(Self.install("a"))
        await Self.settle()

        #expect(first.id != second.id, "two submissions of one command shared an identity")

        // Pending → running → terminal, one identity throughout.
        func identity(of id: UUID) async throws -> OperationSnapshot {
            let snapshot = await runner.snapshot()
            return try #require(snapshot.operations.first { $0.id == id })
        }

        #expect(try await identity(of: second.id).phase == .pending)

        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await first.exit()
        await launcher.waitForLaunches(atLeast: 2)
        await Self.settle()

        #expect(try await identity(of: second.id).phase == .running)
        #expect(try await identity(of: first.id).phase.isTerminal)

        launcher.launchedProcesses[1].terminate(with: BrewExit(status: 3, reason: .exited))
        _ = await second.exit()

        let terminal = try await identity(of: second.id)
        #expect(terminal.id == second.id)
        #expect(terminal.phase == .terminal(BrewExit(status: 3, reason: .exited), fault: nil))
    }

    /// A terminal operation stays enumerable for the session, with its outcome,
    /// and enumerating it restarts nothing (OA1 sc4).
    @Test("A terminal operation stays enumerable with its outcome and restarts nothing")
    func terminalOperationsStayEnumerable() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        let operation = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await operation.exit()

        for _ in 0..<10 {
            let snapshot = await runner.snapshot()
            let entry = try #require(snapshot.operations.first { $0.id == operation.id })
            #expect(entry.phase == .terminal(BrewExit(status: 0, reason: .exited), fault: nil))
            #expect(entry.command.arguments == ["install", "--formula", "a"])
        }

        #expect(launcher.launchCount == 1, "enumerating a terminal operation restarted it")
    }

    // MARK: - Logs while running (OA3 sc1–2)

    @Test("Lines are readable while the operation is still running, tagged and in order")
    func linesAreReadableBeforeTheOperationExits() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        let operation = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)
        let process = launcher.launchedProcesses[0]

        process.emitStdout("a\n")
        process.emitStderr("b\n")
        process.emitStdout("c\n")

        var collected: [LogLine] = []
        for await line in operation.lines {
            collected.append(line)
            if collected.count == 3 { break }
        }

        // Still running: nothing has exited.
        let snapshot = await runner.snapshot()
        #expect(snapshot.operations.first?.phase == .running)

        #expect(collected.map(\.text) == ["a", "b", "c"])
        #expect(collected.map(\.stream) == [.stdout, .stderr, .stdout])

        process.terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await operation.exit()
    }

    // MARK: - The stream (D3)

    @Test("The queue stream publishes a snapshot at every phase change")
    func theQueueStreamPublishesPhaseChanges() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        let observed = Mutex<[QueueSnapshot]>([])
        let watcher = Task {
            for await snapshot in runner.queue {
                observed.withLock { $0.append(snapshot) }
            }
        }
        await Self.settle()

        let operation = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await operation.exit()
        await Self.settle()

        let snapshots = observed.withLock { $0 }
        #expect(snapshots.isEmpty == false, "the queue stream published nothing at all")

        let last = try #require(snapshots.last)
        #expect(last.operations.count == 1)
        #expect(last.operations[0].phase.isTerminal)
        watcher.cancel()
    }

    /// `.bufferingNewest(1)`: these are *state snapshots*, so dropping an
    /// intermediate one is lossless, and a slow consumer can never back-pressure
    /// the actor.
    @Test("A slow consumer sees the newest snapshot rather than a backlog")
    func aSlowConsumerSeesTheNewestSnapshot() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        var iterator = runner.queue.makeAsyncIterator()

        // Churn the queue hard while nobody is reading it.
        var operations: [BrewOperation] = []
        for index in 0..<12 {
            operations.append(try await runner.start(Self.install("package-\(index)")))
        }
        await launcher.waitForLaunches(atLeast: 1)
        await Self.settle()

        // The very next element the slow consumer gets already reflects all of
        // them — it is not handed the first of twelve stale snapshots.
        let snapshot = try #require(await iterator.next())
        #expect(snapshot.operations.count == 12)
        #expect(launcher.launchCount == 1, "the backlog spawned more than the head")

        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        for operation in operations { await operation.cancel() }
    }

    // MARK: - Cancellation through the projection (BE1 sc3; OA4 sc1–2)

    @Test("Cancelling a pending operation spawns nothing and resolves it cancelled")
    func cancellingAPendingOperationSpawnsNothing() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        let running = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)
        let pending = try await runner.start(Self.install("b"))
        await Self.settle()

        await pending.cancel()
        await Self.settle()

        #expect(launcher.launchCount == 1, "a cancelled pending operation was spawned")

        let snapshot = await runner.snapshot()
        let entry = try #require(snapshot.operations.first { $0.id == pending.id })
        #expect(entry.phase.isTerminal)
        #expect(entry.phase.exit?.isCancelled == true)

        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await running.exit()
    }

    @Test("Cancelling the running operation reports cancelled and lets the next start")
    func cancellingTheRunningOperationLetsTheQueueProceed() async throws {
        let launcher = FakeProcessLauncher(behavior: .exitOnInterrupt)
        let runner = Self.runner(launcher)

        let running = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)
        let next = try await runner.start(Self.install("b"))
        await Self.settle()

        await running.cancel()
        let exit = await running.exit()

        #expect(exit.isCancelled, "a cancelled run was reported as a plain failure")

        await launcher.waitForLaunches(atLeast: 2)
        #expect(launcher.launchCount == 2, "the queue stalled behind a cancelled operation")

        let snapshot = await runner.snapshot()
        #expect(try #require(snapshot.operations.first { $0.id == running.id }).phase.isTerminal)
        #expect(try #require(snapshot.operations.first { $0.id == next.id }).phase == .running)

        launcher.launchedProcesses[1].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await next.exit()
    }

    // MARK: - Phase is derived, never stored

    /// The whole point of D3: phase is computed from `process` and
    /// `resolvedExit`, so it cannot drift from them. A read-only query is never
    /// gated, so it is `.running` the instant it is submitted.
    @Test("A read-only query is running immediately and never pending")
    func readsAreNeverPending() async throws {
        let launcher = FakeProcessLauncher()
        let runner = Self.runner(launcher)

        let mutation = try await runner.start(Self.install("a"))
        await launcher.waitForLaunches(atLeast: 1)
        let read = try await runner.start(.read(["info", "--json=v2"]))
        await launcher.waitForLaunches(atLeast: 2)

        let snapshot = await runner.snapshot()
        let entry = try #require(snapshot.operations.first { $0.id == read.id })
        #expect(entry.phase == .running, "a read-only query was gated behind a mutation")

        launcher.launchedProcesses[1].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await read.exit()
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await mutation.exit()
    }

    @Test("A launch fault is carried into the terminal phase")
    func launchFaultsReachTheProjection() async throws {
        let launcher = FakeProcessLauncher()
        launcher.failLaunch(with: POSIXError(.ENOENT))
        let runner = Self.runner(launcher)

        let operation = try await runner.start(Self.install("a"))
        _ = await operation.exit()

        let snapshot = await runner.snapshot()
        let entry = try #require(snapshot.operations.first)
        #expect(entry.phase.isTerminal)
        #expect(entry.phase.fault != nil)
    }
}
