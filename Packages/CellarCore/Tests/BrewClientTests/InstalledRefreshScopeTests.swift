import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// Suppression and the owed re-snapshot, scoped to the commands that declare the
/// installed set (installed-inventory II10 as amended, design D2).
///
/// Split out of `InstalledRefreshTests` rather than added to it: that suite is
/// already at SwiftLint's `type_body_length` bound, and task 17.1 asks for a
/// split rather than a suppression. The seam is a real one — everything here
/// needs a live `OperationCenter` and two gates, which nothing else in that
/// suite does.
@MainActor
@Suite("Installed refresh scoping", .timeLimit(.minutes(1)))
struct InstalledRefreshScopeTests {
    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private struct Harness {
        let source: FakeInstalledPayloadSource
        let store: InstalledStore
        let observer: FakeInstalledChangeObserver
        let mutations: InstalledMutationGate
        let clock: TestClock
        let coordinator: InstalledRefreshCoordinator
    }

    private func harness() -> Harness {
        let source = FakeInstalledPayloadSource([
            .formulae(["wget"]),
            .formulae(["wget", "curl"])
        ])
        let store = InstalledStore(source: source)
        let observer = FakeInstalledChangeObserver()
        let mutations = InstalledMutationGate()
        let clock = TestClock()
        return Harness(
            source: source,
            store: store,
            observer: observer,
            mutations: mutations,
            clock: clock,
            coordinator: InstalledRefreshCoordinator(
                store: store,
                observer: observer,
                mutations: mutations,
                clock: clock
            )
        )
    }

    /// Advances past the quiet window until the coordinator stops extending it.
    private func passQuietWindow(_ clock: TestClock, rounds: Int = 4) async {
        for _ in 0..<rounds {
            await clock.advance(by: .seconds(2))
            for _ in 0..<20 { await Task.yield() }
        }
    }

    /// Suppression is scoped to commands that **declare** the installed set.
    ///
    /// The pair matters more than either half. `signalsDuringAMutationAreSuppressed`
    /// above proves an inventory-invalidating mutation still silences the
    /// watcher; this proves an operation that cannot change the installed set
    /// does **not** — so a genuine external install landing while a service
    /// restarts is answered on the ordinary quiet window rather than being held
    /// hostage by an unrelated operation.
    @Test("External signals are not suppressed by a non-invalidating operation")
    func externalSignalsAreNotSuppressedByANonInvalidatingOperation() async {
        let harness = harness()
        let servicesGate = InstalledMutationGate()
        let launcher = ControllableProcessLauncher()
        let center = OperationCenter(
            gates: MutationGates([
                (.installedInventory, harness.mutations),
                (.services, servicesGate)
            ]),
            launcherFactory: { _ in launcher }
        )
        center.attach(installation: TestInstallation.appleSilicon)
        let loop = Task { await harness.coordinator.run() }
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount
        #expect(harness.store.inventory.packages.map(\.name) == ["wget"])

        // A non-inventory operation starts, and is still running throughout.
        let item = center.submit(ProbeMutation())
        await launcher.waitForLaunches(atLeast: 1)
        await settle()
        #expect(item.isTerminal == false, "the operation ended before the signal, proving nothing")
        #expect(servicesGate.isMutating, "the declared domain's gate never opened")
        #expect(harness.mutations.isMutating == false, "a services command suppressed the inventory")

        // An external change lands while it runs.
        harness.observer.emit()
        await harness.clock.waitForSleepers()
        await passQuietWindow(harness.clock)

        // Answered on the ordinary quiet window, without waiting for it.
        #expect(
            harness.source.callCount - baseline == 1,
            "the external signal was suppressed by an operation that cannot change the installed set"
        )
        #expect(harness.store.inventory.packages.map(\.name) == ["curl", "wget"])
        #expect(item.isTerminal == false, "the refresh waited for the unrelated operation to finish")

        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        await settle()
        loop.cancel()
    }

}
