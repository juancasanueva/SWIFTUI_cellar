import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// Cancel stays effective when the executing backend is detached or replaced
/// (operation-activity OA4, design D10).
///
/// M2-2's `cancel(_:)` read the *centre's current* runner and, when there was
/// none, settled the item as cancelled outright. Two defects followed: a
/// repointed `brew` cancelled on the wrong runner, and a running operation was
/// reported cancelled — paying the mutation gate's `end()` early — while the
/// process carried on. Bulk multi-select multiplies the exposure, so it is
/// closed before that arrives.
///
/// The item now holds the `BrewOperation` its own runner produced, so cancel is
/// always delivered to the process that actually exists.
@MainActor
@Suite("Operation center cancel", .timeLimit(.minutes(1)))
struct OperationCenterCancelTests {
    private static func wget() throws -> PackageTarget {
        try #require(PackageTarget(CenterHarness.wget))
    }

    private static func git() throws -> PackageTarget {
        try #require(PackageTarget(CenterHarness.git))
    }

    // MARK: - OA4 sc4 — cancelling while detached still stops the process

    @Test("A detached cancel signals the process and settles only at the real terminal")
    func aDetachedCancelSignalsRatherThanSettles() async throws {
        let harness = CenterHarness(honoursInterrupt: false)
        let item = harness.center.submit(.install(try Self.wget()))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let process = try #require(harness.launcher.launchedProcesses.first)

        harness.center.attach(installation: nil)
        await harness.settle()
        #expect(harness.center.isAvailable == false)

        harness.center.cancel(item)
        await harness.poll { process.deliveredSignals.isEmpty == false }

        // Signalled through the ordinary escalation…
        #expect(process.deliveredSignals.contains(.interrupt))
        // …and *not* reported cancelled while it is still running.
        #expect(item.isTerminal == false, "a running operation was reported cancelled")
        #expect(item.outcome == nil)
        #expect(item.isCancelRequested)

        process.terminate(with: BrewExit(status: 130, reason: .signalled(SIGINT)))
        await harness.poll { item.isTerminal }

        #expect(item.outcome == .cancelled)
    }

    // MARK: - OA4 sc5 — the gate is paid exactly once, at the real terminal

    @Test("A detached cancel starts nothing and forces no re-snapshot before the terminal")
    func aDetachedCancelDoesNotReleaseTheGateEarly() async throws {
        let harness = CenterHarness(honoursInterrupt: false)
        let terminals = Counter()
        let watcher = Task { [stream = harness.gate.terminals] in
            for await _ in stream { terminals.increment() }
        }
        await harness.settle()

        let running = harness.center.submit(.install(try Self.wget()))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let pending = harness.center.submit(.install(try Self.git()))
        await harness.settle()

        let process = try #require(harness.launcher.launchedProcesses.first)
        harness.center.attach(installation: nil)
        await harness.settle()

        harness.center.cancel(running)
        await harness.poll { process.deliveredSignals.isEmpty == false }

        #expect(pending.isTerminal == false, "the pending mutation was settled by the cancel")
        #expect(harness.launcher.launchCount == 1, "the pending mutation started early")
        #expect(terminals.value == 0, "an inventory re-snapshot was forced before the terminal")
        #expect(harness.gate.isMutating, "the gate was released before the process stopped")

        process.terminate(with: BrewExit(status: 130, reason: .signalled(SIGINT)))
        await harness.poll { running.isTerminal }
        await harness.settle()

        // Exactly once, and only now.
        #expect(running.outcome == .cancelled)
        #expect(terminals.value == 1)
        #expect(harness.launcher.launchCount == 2, "the pending mutation never started")
        watcher.cancel()
    }

    // MARK: - Cancel reaches the runner that produced the operation

    @Test("Repointing brew mid-flight still cancels on the original runner")
    func cancelReachesTheOriginalRunner() async throws {
        let harness = CenterHarness(honoursInterrupt: false)
        let item = harness.center.submit(.install(try Self.wget()))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let original = try #require(harness.launcher.launchedProcesses.first)

        // A second runner, over the same launcher, with its own queue.
        harness.center.attach(installation: TestInstallation.intel)
        await harness.settle()
        #expect(harness.center.isAvailable)

        harness.center.cancel(item)
        await harness.poll { original.deliveredSignals.isEmpty == false }

        #expect(original.deliveredSignals.contains(.interrupt))
        #expect(harness.launcher.launchCount == 1, "cancelling spawned something on the new runner")
        #expect(item.isTerminal == false)

        original.terminate(with: BrewExit(status: 130, reason: .signalled(SIGINT)))
        await harness.poll { item.isTerminal }
        #expect(item.outcome == .cancelled)
    }

    /// The one case that is still terminal here: a submission that never had a
    /// runner at all, and no start in flight to replay the request.
    @Test("A submission that never had a runner is cancelled outright")
    func aSubmissionWithNoRunnerIsCancelledOutright() async throws {
        let harness = CenterHarness()
        let pendingBehind = harness.center.submit(.install(try Self.wget()))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let queued = harness.center.submit(.install(try Self.git()))
        await harness.settle()

        #expect(queued.isTerminal == false)
        harness.center.cancel(queued)
        await harness.poll { queued.isTerminal }

        #expect(queued.outcome == .cancelled)
        #expect(harness.launcher.launchCount == 1, "a cancelled pending mutation spawned")

        try await harness.finish(call: 0)
        #expect(pendingBehind.outcome == .succeeded)
    }

    /// A cancel that arrives before the item has reached a runner settles it
    /// **immediately**, and nothing is ever spawned.
    ///
    /// This is the cross-source chain's doing (design D13). Every submission now
    /// waits its turn at the centre before it is handed to a runner, so between
    /// `submit` returning and that hand-off the item holds nothing at all: no
    /// process, no operation id, no entry in any runner's queue. Settling it
    /// there is honest rather than optimistic, and it is what makes cancelling a
    /// queued mutation free instead of a promise redeemed whenever its
    /// predecessor happens to finish.
    ///
    /// The replay guard inside `run(_:for:on:)` is unchanged and still the
    /// answer for the narrower window after the hand-off; what changed is that
    /// this window is no longer the one a person's cancel usually lands in.
    @Test("A cancel racing the submission settles at once and spawns nothing")
    func aCancelRacingTheSubmissionSettlesAtOnce() async throws {
        let harness = CenterHarness(honoursInterrupt: false)
        let item = harness.center.submit(.install(try Self.wget()))

        // No settle: the chain gate has not run yet, so there is no handle and
        // nothing has been launched.
        #expect(item.operation == nil)
        #expect(item.isChainQueued)
        #expect(item.isStartInFlight == false)
        #expect(harness.launcher.launchCount == 0)

        harness.center.cancel(item)

        #expect(item.isTerminal, "a cancel before the hand-off left the item live")
        #expect(item.outcome == .cancelled, "the cancel was lost")

        await harness.settle()

        #expect(harness.launcher.launchCount == 0, "a cancelled submission was still spawned")
        #expect(item.isStartInFlight == false)
    }

    // MARK: - The harness stops trapping (design D11)

    /// `TestPoll.until` returns silently on timeout, so `finish(call:)` used to
    /// index a process that was never launched — trapping, and taking the entire
    /// suite down without naming a single test. It now fails one expectation,
    /// attributed here.
    @Test("Finishing a call that never launched fails this test instead of crashing the suite")
    func theHarnessReportsAMissingProcess() async {
        let harness = CenterHarness()

        await withKnownIssue("nothing was submitted, so call 0 never launches") {
            try await harness.finish(call: 0, timeout: .milliseconds(50))
        }

        // The suite is still alive and the harness is still usable.
        #expect(harness.launcher.launchCount == 0)
        #expect(harness.center.items.isEmpty)
    }
}
