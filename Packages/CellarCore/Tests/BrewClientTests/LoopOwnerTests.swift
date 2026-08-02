import Foundation
import Testing

@testable import BrewClient

/// Background refresh loops belong to the application, not to whichever window
/// happened to start them (installed-inventory II11, design D10).
@MainActor
@Suite("Loop ownership", .timeLimit(.minutes(1)))
struct LoopOwnerTests {
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    /// A loop that runs until told to stop and counts how far it got.
    private func ticking(
        starts: Counter,
        ticks: Counter,
        stop: Flag
    ) -> @MainActor () async -> Void {
        {
            starts.increment()
            while !stop.isSet {
                await Task.yield()
                ticks.increment()
            }
        }
    }

    @Test("Starting the same id twice runs exactly one loop")
    func startIsIdempotentPerID() async {
        let owner = LoopOwner()
        let starts = Counter()
        let ticks = Counter()
        let stop = Flag()

        owner.start("catalog", ticking(starts: starts, ticks: ticks, stop: stop))
        owner.start("catalog", ticking(starts: starts, ticks: ticks, stop: stop))
        await settle()

        #expect(starts.value == 1)
        #expect(owner.isRunning("catalog"))
        stop.set()
    }

    @Test("Different ids run their own loops")
    func differentIDsRunSeparateLoops() async {
        let owner = LoopOwner()
        let starts = Counter()
        let stop = Flag()

        owner.start("catalog", ticking(starts: starts, ticks: Counter(), stop: stop))
        owner.start("installed", ticking(starts: starts, ticks: Counter(), stop: stop))
        await settle()

        #expect(starts.value == 2)
        #expect(owner.isRunning("catalog"))
        #expect(owner.isRunning("installed"))
        stop.set()
    }

    @Test("An id that was never started is not running")
    func unknownIDIsNotRunning() {
        let owner = LoopOwner()

        #expect(owner.isRunning("catalog") == false)
    }

    /// Open → close → open. The reopened window re-enters `start`, finds the
    /// loop already running, and returns without starting a second one.
    @Test("Reopening a window after all were closed does not start another loop")
    func reopeningAWindowDoesNotDoubleStart() async {
        let owner = LoopOwner()
        let starts = Counter()
        let stop = Flag()

        // First window.
        owner.start("installed", ticking(starts: starts, ticks: Counter(), stop: stop))
        await settle()
        // Second window opens, then every window closes, then one reopens.
        owner.start("installed", ticking(starts: starts, ticks: Counter(), stop: stop))
        owner.start("installed", ticking(starts: starts, ticks: Counter(), stop: stop))
        await settle()

        #expect(starts.value == 1)
        #expect(owner.isRunning("installed"))
        stop.set()
    }

    /// The loop is owned by the object, not by the scene's task tree, so tearing
    /// the scene down leaves it running.
    @Test("Closing the scene that started a loop does not cancel it")
    func closingTheStartingSceneDoesNotCancelTheLoop() async {
        let owner = LoopOwner()
        let starts = Counter()
        let ticks = Counter()
        let stop = Flag()

        let scene = Task { @MainActor in
            owner.start("installed", ticking(starts: starts, ticks: ticks, stop: stop))
            // The scene lives on until its window closes.
            while !Task.isCancelled { await Task.yield() }
        }
        await TestPoll.until(starts.value == 1)

        scene.cancel()
        await scene.value
        await settle()

        let before = ticks.value
        await settle()

        #expect(ticks.value > before, "the loop stopped when its scene did")
        #expect(owner.isRunning("installed"))
        stop.set()
    }

    /// …and the work it drives still lands: a refresh after the window closed
    /// updates the store as before.
    @Test("A refresh after the starting window closed still updates the inventory")
    func refreshAfterTheWindowClosedStillUpdates() async {
        let owner = LoopOwner()
        let source = FakeInstalledPayloadSource([
            .formulae(["wget"]),
            .formulae(["wget", "curl"])
        ])
        let store = InstalledStore(source: source)
        let ready = Flag()

        let scene = Task { @MainActor in
            owner.start("installed") {
                await store.refresh(using: TestInstallation.appleSilicon)
                ready.set()
            }
            while !Task.isCancelled { await Task.yield() }
        }
        await TestPoll.until(ready.isSet)
        scene.cancel()
        await scene.value

        await store.refresh(using: TestInstallation.appleSilicon)

        #expect(store.inventory.packages.map(\.name) == ["curl", "wget"])
        #expect(source.callCount == 2)
    }
}
