import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// The services poll: on while the surface is visible, off — entirely — while
/// it is not.
///
/// `.timeLimit(.minutes(1))` in **whole minutes**: `.seconds(30)` traps at
/// runtime, which cost M3-0 an apply cycle. Nothing here sleeps on the wall
/// clock; every interval is hand-advanced.
@MainActor
@Suite("Services refresh cadence", .timeLimit(.minutes(1)))
struct ServicesRefreshTests {
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private struct Harness {
        let source: FakeServicesPayloadSource
        let store: ServicesStore
        let clock: TestClock
        let coordinator: ServicesRefreshCoordinator
    }

    private func harness(
        answers: [FakeServicesPayloadSource.Answer] = [.services(["atuin"])]
    ) -> Harness {
        let source = FakeServicesPayloadSource(answers)
        let store = ServicesStore(source: source)
        let clock = TestClock()
        return Harness(
            source: source,
            store: store,
            clock: clock,
            coordinator: ServicesRefreshCoordinator(store: store, clock: clock)
        )
    }

    /// One poll interval, waited for rather than raced with.
    ///
    /// `sleepers` is the number of tasks that must be suspended on the clock
    /// before time is allowed to move. It is normally the one live loop, but a
    /// loop cancelled *while suspended* stays registered with `TestClock` until
    /// the next advance resumes it — so after a hide the count is one higher
    /// than the number of loops that will actually refresh. Advancing before
    /// the live loop has reached its `sleep` is the difference between "one
    /// tick per interval" and a silently skipped tick.
    private func advanceOneInterval(_ harness: Harness, sleepers: Int = 1) async {
        await harness.clock.waitForSleepers(atLeast: sleepers)
        await harness.clock.advance(by: .seconds(5))
        await settle()
    }

    // MARK: - SM3 sc1 — the cadence

    @Test("The list refreshes on the five-second cadence while visible")
    func theListRefreshesOnTheFiveSecondCadenceWhileVisible() async {
        let harness = harness()
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let launchBaseline = harness.source.callCount
        #expect(launchBaseline == 1)

        harness.coordinator.setVisible(true)
        await harness.source.waitForCalls(atLeast: 2)
        // Becoming visible is itself a baseline refresh (SM3).
        #expect(harness.source.callCount == 2)

        for expected in 3...5 {
            await advanceOneInterval(harness)
            #expect(harness.source.callCount == expected)
        }

        // One baseline on becoming visible plus exactly three ticks.
        #expect(harness.source.callCount - launchBaseline == 4)
        harness.coordinator.setVisible(false)
    }

    /// A shorter wait must not tick: "every 5 seconds" is a cadence, not "at
    /// least once in a while".
    @Test("Four seconds of simulated time buys no refresh")
    func aShortWaitBuysNoRefresh() async {
        let harness = harness()
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        harness.coordinator.setVisible(true)
        await harness.source.waitForCalls(atLeast: 2)
        let baseline = harness.source.callCount

        await harness.clock.waitForSleepers()
        await harness.clock.advance(by: .seconds(4))
        await settle()

        #expect(harness.source.callCount == baseline, "the poll ticked early")

        await harness.clock.advance(by: .seconds(1))
        await settle()
        #expect(harness.source.callCount - baseline == 1)
        harness.coordinator.setVisible(false)
    }

    // MARK: - SM3 sc2 — hiding stops polling entirely

    /// Also the threat-matrix **Process integration** row: no spawn after hide
    /// across sixty seconds of simulated time. "Entirely" is the word the spec
    /// uses, so a slowed-down poll would fail this.
    @Test("Hiding the surface stops polling entirely")
    func hidingTheSurfaceStopsPollingEntirely() async {
        let harness = harness()
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        harness.coordinator.setVisible(true)
        await harness.source.waitForCalls(atLeast: 2)
        await advanceOneInterval(harness)
        let beforeHiding = harness.source.callCount
        #expect(beforeHiding >= 3, "the poll never ran, so stopping it proves nothing")

        harness.coordinator.setVisible(false)
        await settle()

        // Twelve intervals' worth.
        for _ in 0..<12 {
            await harness.clock.advance(by: .seconds(5))
            await settle()
        }

        #expect(
            harness.source.callCount == beforeHiding,
            "\(harness.source.callCount - beforeHiding) probe(s) ran while the surface was hidden"
        )
        #expect(harness.coordinator.isPolling == false)

        // And it resumes with a baseline refresh, not silently.
        harness.coordinator.setVisible(true)
        await harness.source.waitForCalls(atLeast: beforeHiding + 1)
        #expect(harness.source.callCount == beforeHiding + 1)
        harness.coordinator.setVisible(false)
    }

    @Test("No process is spawned at all while the surface is hidden")
    func noProcessIsSpawnedWhileHidden() async {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: ServicesFixture.withNullUserAndExitCode)
        ])
        let store = ServicesStore(source: ServicesListPayloadSource(launcher: launcher))
        let clock = TestClock()
        let coordinator = ServicesRefreshCoordinator(store: store, clock: clock)

        await coordinator.refresh(using: TestInstallation.appleSilicon)
        coordinator.setVisible(true)
        await TestPoll.until(launcher.launchCount >= 2)
        let beforeHiding = launcher.launchCount

        coordinator.setVisible(false)
        await settle()
        for _ in 0..<12 {
            await clock.advance(by: .seconds(5))
            await settle()
        }

        #expect(launcher.launchCount == beforeHiding)
    }

    // MARK: - SM3 sc3 — at most one loop

    /// Reported visibility arrives from `onAppear`, `onDisappear` and
    /// `scenePhase` at once, so "become visible" is delivered more than once
    /// per actual transition.
    ///
    /// **Counted through the clock, not through the probe count.** Two poll
    /// loops refreshing together are indistinguishable by probe count, because
    /// `ServicesStore` coalesces same-request refreshes onto one acquisition —
    /// so a probe-count assertion here passes with the loop guard deleted and
    /// proves nothing. A running loop is a sleeper on the injected clock, and
    /// N loops are N sleepers, so that is what is counted. Verified by
    /// mutation: removing the guard makes this fail.
    @Test("Only one poll loop runs per launch")
    func onlyOnePollLoopRunsPerLaunch() async {
        let harness = harness()
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)

        for _ in 0..<3 { harness.coordinator.setVisible(true) }
        await harness.source.waitForCalls(atLeast: 2)
        await harness.clock.waitForSleepers(atLeast: 1)
        await settle()

        #expect(
            harness.clock.sleeperCount == 1,
            "\(harness.clock.sleeperCount) poll loops are running after three shows"
        )

        var expected = harness.source.callCount
        for _ in 0..<2 {
            await advanceOneInterval(harness)
            expected += 1
            #expect(harness.source.callCount == expected, "a tick was served by two loops")
            await harness.clock.waitForSleepers(atLeast: 1)
            await settle()
            #expect(harness.clock.sleeperCount == 1)
        }

        // Hide, show, hide, show. Each hide leaves the loop it cancelled
        // suspended on the clock until the next advance resumes it, so two
        // sleepers must be present before time may move — and exactly one must
        // remain once it has.
        for _ in 0..<2 {
            harness.coordinator.setVisible(false)
            await settle()
            harness.coordinator.setVisible(true)
            expected += 1
            await harness.source.waitForCalls(atLeast: expected)

            await advanceOneInterval(harness, sleepers: 2)
            expected += 1
            #expect(
                harness.source.callCount == expected,
                "a hidden-then-shown surface is being polled by two loops"
            )
            await harness.clock.waitForSleepers(atLeast: 1)
            await settle()
            #expect(
                harness.clock.sleeperCount == 1,
                "\(harness.clock.sleeperCount) loops survived a hide and a show"
            )
        }

        harness.coordinator.setVisible(false)
    }

    // MARK: - SM2 sc2 — a poll tick fetches no detail

    @Test("A poll tick fetches no detail")
    func aPollTickFetchesNoDetail() async {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: ServicesFixture.withNullUserAndExitCode)
        ])
        let store = ServicesStore(
            source: ServicesListPayloadSource(launcher: launcher),
            detailSource: ServiceInfoPayloadSource(launcher: launcher)
        )
        let clock = TestClock()
        let coordinator = ServicesRefreshCoordinator(store: store, clock: clock)

        await coordinator.refresh(using: TestInstallation.appleSilicon)
        coordinator.setVisible(true)
        await TestPoll.until(launcher.launchCount >= 2)

        for _ in 0..<3 {
            await clock.waitForSleepers()
            await clock.advance(by: .seconds(5))
            await settle()
        }

        #expect(launcher.launchCount >= 4, "the poll never ticked")
        for spec in launcher.specs {
            #expect(spec.arguments == ["services", "list", "--json"])
        }
        #expect(
            launcher.specs.contains { $0.arguments.contains("info") } == false,
            "a poll tick fetched detail"
        )
        coordinator.setVisible(false)
    }

    // MARK: - SM11 — nothing runs with no brew

    @Test("With brew absent, becoming visible starts no poll loop and spawns nothing")
    func absentBrewStartsNoPollLoop() async {
        let harness = harness()
        await harness.coordinator.refresh(for: .absent)

        harness.coordinator.setVisible(true)
        await settle()
        for _ in 0..<4 {
            await harness.clock.advance(by: .seconds(5))
            await settle()
        }

        #expect(harness.source.callCount == 0)
        #expect(harness.coordinator.isPolling == false, "a poll loop is running with no brew")
        #expect(harness.store.services.isEmpty)
    }

    /// Detection can resolve after the surface is already showing, which is the
    /// ordinary launch sequence rather than an edge case.
    @Test("Polling begins when brew appears while the surface is already visible")
    func pollingBeginsWhenBrewAppears() async {
        let harness = harness()
        await harness.coordinator.refresh(for: .absent)
        harness.coordinator.setVisible(true)
        await settle()
        #expect(harness.coordinator.isPolling == false)

        await harness.coordinator.refresh(for: .detected(TestInstallation.appleSilicon))
        await harness.source.waitForCalls(atLeast: 1)

        #expect(harness.coordinator.isPolling)
        await advanceOneInterval(harness)
        #expect(harness.source.callCount >= 2)
        harness.coordinator.setVisible(false)
    }
}
