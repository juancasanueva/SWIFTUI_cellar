import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// The absorbed M2-1 cadence defects: a quiet window that opened before a
/// mutation began, a signal answered by a pre-signal acquisition, and a
/// debounce nobody owned (design D8a, D8b — installed-inventory II10).
@MainActor
@Suite("Installed refresh defects", .timeLimit(.minutes(1)))
struct InstalledRefreshDefectTests {
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    /// A store whose next snapshot gains a package, plus the pieces around it.
    private struct Harness {
        let source: FakeInstalledPayloadSource
        let store: InstalledStore
        let observer: FakeInstalledChangeObserver
        let mutations: InstalledMutationGate
        let clock: TestClock
        let coordinator: InstalledRefreshCoordinator
    }

    @MainActor
    private func harness(
        answers: [FakeInstalledPayloadSource.Answer] = [
            .formulae(["wget"]),
            .formulae(["wget", "curl"])
        ],
        withObserver: Bool = true,
        gated: Bool = false
    ) -> Harness {
        let source = FakeInstalledPayloadSource(answers, gated: gated)
        let store = InstalledStore(source: source)
        let observer = FakeInstalledChangeObserver()
        let mutations = InstalledMutationGate()
        let clock = TestClock()
        let coordinator = InstalledRefreshCoordinator(
            store: store,
            observer: withObserver ? observer : nil,
            mutations: mutations,
            clock: clock
        )
        return Harness(
            source: source,
            store: store,
            observer: observer,
            mutations: mutations,
            clock: clock,
            coordinator: coordinator
        )
    }

    /// Advances past the quiet window until the coordinator stops extending it.
    private func passQuietWindow(_ clock: TestClock, rounds: Int = 4) async {
        for _ in 0..<rounds {
            await clock.advance(by: .seconds(2))
            for _ in 0..<20 { await Task.yield() }
        }
    }

    // MARK: - The absorbed defects

    /// The coordinator is what tells the store its freshness mark moved
    /// (design D8b — II10 sc6). Without that call the debounced refresh joins
    /// the acquisition that was already running when the signal arrived, and
    /// the inventory settles on state observed before the change.
    @Test("A signal during an acquisition is not answered by that acquisition")
    func aSignalDuringAnAcquisitionIsNotAnsweredByIt() async {
        let harness = harness(
            answers: [.formulae(["wget"]), .formulae(["wget", "curl"])],
            gated: true
        )
        let loop = Task { await harness.coordinator.run() }

        let baseline = Task {
            await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        }
        await harness.source.waitForCalls(atLeast: 1)

        // The change lands while that first acquisition is still open.
        harness.observer.emit()
        await harness.clock.waitForSleepers()
        await passQuietWindow(harness.clock)

        #expect(
            harness.source.callCount == 2,
            "the debounced refresh joined a pre-signal acquisition"
        )

        harness.source.release()
        await baseline.value
        await settle()

        #expect(harness.store.inventory.packages.map(\.name) == ["curl", "wget"])
        loop.cancel()
    }

    /// A mutation terminal is an invalidation for the same reason a watcher
    /// signal is: brew has just changed what is installed.
    @Test("A mutation terminal invalidates the inventory before re-snapshotting")
    func aMutationTerminalInvalidatesTheInventory() async {
        let harness = harness(
            answers: [.formulae(["wget"]), .formulae(["wget", "curl"])],
            gated: true
        )
        let loop = Task { await harness.coordinator.run() }

        let baseline = Task {
            await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        }
        await harness.source.waitForCalls(atLeast: 1)

        harness.mutations.begin()
        harness.mutations.end()
        await harness.source.waitForCalls(atLeast: 2)

        #expect(
            harness.source.callCount == 2,
            "the terminal re-snapshot joined an acquisition that predates the mutation"
        )

        harness.source.release()
        await baseline.value
        await settle()

        #expect(harness.store.inventory.packages.map(\.name) == ["curl", "wget"])
        loop.cancel()
    }

    /// The debounce task was unstructured and unowned, which made the
    /// `Task.isCancelled` guards inside it unreachable: nothing ever cancelled
    /// it. Owning it is what turns those guards from dead code into the reason a
    /// torn-down coordinator cannot refresh after the fact (design D8a).
    @Test("Cancelling the loop cancels the pending debounce, so no refresh escapes it")
    func cancellingTheLoopCancelsThePendingDebounce() async {
        let harness = harness(answers: [.formulae(["wget"])])
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount

        harness.observer.emit()
        await harness.clock.waitForSleepers()

        loop.cancel()
        harness.observer.finish()
        await loop.value
        await settle()
        await passQuietWindow(harness.clock)

        #expect(
            harness.source.callCount == baseline,
            "a debounced refresh survived the loop that owned it"
        )
    }
}
