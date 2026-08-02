import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// Cadence lives outside CoreServices so all of it is reachable through a fake
/// observer and a hand-advanced clock (design D9, D12).
@MainActor
@Suite("Installed refresh cadence", .timeLimit(.minutes(1)))
struct InstalledRefreshTests {
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
        withObserver: Bool = true
    ) -> Harness {
        let source = FakeInstalledPayloadSource(answers)
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

    // MARK: - External change (II10 sc1, sc2)

    @Test("An external install is reflected after the quiet window, with no user action")
    func externalChangeIsReflected() async {
        let harness = harness()
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        #expect(harness.store.inventory.packages.map(\.name) == ["wget"])

        harness.observer.emit()
        await harness.clock.waitForSleepers()
        await passQuietWindow(harness.clock)

        #expect(harness.store.inventory.packages.map(\.name) == ["curl", "wget"])
        #expect(harness.source.callCount == 2)
        loop.cancel()
    }

    @Test("Twenty signals inside the quiet window cost exactly one re-snapshot")
    func aBurstCostsOneReSnapshot() async {
        let harness = harness()
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount

        harness.observer.emit(20)
        await settle()
        await harness.clock.waitForSleepers()
        await passQuietWindow(harness.clock)

        #expect(harness.observer.emittedCount == 20)
        #expect(harness.source.callCount - baseline == 1)
        loop.cancel()
    }

    /// The window *extends*, it does not merely throttle. That is the whole
    /// point for a `brew upgrade` that writes for minutes: one refresh at the
    /// end, not one every two seconds while it works.
    @Test("A signal arriving inside the window pushes the refresh back")
    func aSignalInsideTheWindowExtendsIt() async {
        let harness = harness(answers: [.formulae(["wget"])])
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount

        harness.observer.emit()
        await harness.clock.waitForSleepers()
        // Still writing: another signal lands before the window closes.
        harness.observer.emit()
        await settle()

        await harness.clock.advance(by: .seconds(2))
        await settle()
        #expect(harness.source.callCount == baseline, "the window closed while writes continued")

        await harness.clock.advance(by: .seconds(2))
        await settle()
        #expect(harness.source.callCount - baseline == 1)
        loop.cancel()
    }

    /// The signal is an invalidation trigger, nothing more: the coordinator
    /// re-snapshots rather than trying to read what changed out of the event.
    @Test("The signal carries nothing, so a re-snapshot is always taken")
    func theSignalIsOnlyAnInvalidation() async {
        // Same payload twice: a coordinator that tried to "detect no change"
        // and skip would record one call, not two.
        let harness = harness(answers: [.formulae(["wget"])])
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)

        harness.observer.emit()
        await harness.clock.waitForSleepers()
        await passQuietWindow(harness.clock)

        #expect(harness.source.callCount == 2)
        loop.cancel()
    }

    /// The app attaches its watcher after launch, once detection has told it
    /// which prefix to watch, so it forwards signals through this entry point
    /// rather than through an observer handed to `run()`. Same debounce, same
    /// suppression — proven here rather than assumed.
    @Test("A directly reported change is debounced exactly like an observed one")
    func directlyReportedChangesAreDebouncedToo() async {
        let harness = harness(answers: [.formulae(["wget"])], withObserver: false)
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount

        for _ in 0..<20 { harness.coordinator.changeDetected() }
        await settle()
        await harness.clock.waitForSleepers()
        await passQuietWindow(harness.clock)

        #expect(harness.source.callCount - baseline == 1)
        loop.cancel()
    }

    @Test("A directly reported change during a mutation is suppressed too")
    func directlyReportedChangesAreSuppressedDuringAMutation() async {
        let harness = harness(answers: [.formulae(["wget"])], withObserver: false)
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount

        harness.mutations.begin()
        for _ in 0..<5 { harness.coordinator.changeDetected() }
        await settle()
        await passQuietWindow(harness.clock)

        #expect(harness.source.callCount == baseline)
        harness.mutations.end()
        await settle()
        await passQuietWindow(harness.clock)
        #expect(harness.source.callCount - baseline == 1)
        loop.cancel()
    }

    // MARK: - Suppression during a mutation (II10 sc3)

    @Test("Signals during a Cellar mutation are suppressed and settled exactly once")
    func signalsDuringAMutationAreSuppressed() async {
        let harness = harness(answers: [.formulae(["wget"])])
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount

        harness.mutations.begin()
        harness.observer.emit(10)
        await settle()
        await passQuietWindow(harness.clock)

        #expect(harness.source.callCount == baseline, "a re-snapshot ran while mutating")

        harness.mutations.end()
        await settle()
        await passQuietWindow(harness.clock)

        #expect(harness.source.callCount - baseline == 1)
        loop.cancel()
    }

    @Test("A mutation with no signals at all still settles with one re-snapshot")
    func aMutationAlwaysSettlesWithOneReSnapshot() async {
        let harness = harness(answers: [.formulae(["wget"])])
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount

        harness.mutations.begin()
        harness.mutations.end()
        await settle()
        await passQuietWindow(harness.clock)

        #expect(harness.source.callCount - baseline == 1)
        loop.cancel()
    }

    // MARK: - Baseline (the watcher is an optimisation, never the only path)

    @Test("The baseline refresh fires at launch and on activation with no observer at all")
    func baselineWorksWithoutAnyObserver() async {
        let harness = harness(
            answers: [.formulae(["wget"]), .formulae(["wget", "curl"])],
            withObserver: false
        )
        let loop = Task { await harness.coordinator.run() }

        // Launch.
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        #expect(harness.store.inventory.packages.map(\.name) == ["wget"])

        // Activation.
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)

        #expect(harness.source.callCount == 2)
        #expect(harness.store.inventory.packages.map(\.name) == ["curl", "wget"])
        loop.cancel()
    }

    @Test("The baseline remembers the installation the loop should refresh with")
    func baselineRecordsTheInstallation() async {
        let harness = harness()
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)

        harness.observer.emit()
        await harness.clock.waitForSleepers()
        await passQuietWindow(harness.clock)

        #expect(
            harness.source.installations.allSatisfy {
                $0.executableURL == TestInstallation.appleSilicon.executableURL
            }
        )
        loop.cancel()
    }

    @Test("With no brew, a signal re-snapshots nothing and spawns nothing")
    func signalsWithoutBrewSpawnNothing() async {
        let harness = harness()
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: nil)

        harness.observer.emit(5)
        await settle()
        await passQuietWindow(harness.clock)

        #expect(harness.source.callCount == 0)
        #expect(harness.store.inventory.isEmpty)
        loop.cancel()
    }
}
