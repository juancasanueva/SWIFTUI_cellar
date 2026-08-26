import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The half of the poll that answers to mutations rather than to visibility
/// (design D3 — service-management SM3 sc4, SM8).
///
/// Two obligations that pull against each other, which is why they are asserted
/// together: while a service mutation is in flight the poll must run **not at
/// all**, so a restart in progress cannot flicker between statuses; and at that
/// mutation's terminal outcome exactly **one** refresh is owed — never zero, and
/// never two because the poll woke up at the same moment.
///
/// Split from `ServicesRefreshTests` at SwiftLint's length bounds (task 17.1),
/// and the seam is real: that suite needs no `OperationCenter` at all.
@MainActor
@Suite("Services refresh control", .timeLimit(.minutes(1)))
struct ServicesRefreshControlTests {
    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    private struct Harness {
        let source: FakeServicesPayloadSource
        let store: ServicesStore
        let clock: TestClock
        let coordinator: ServicesRefreshCoordinator
        let servicesGate: InstalledMutationGate
        let installedGate: InstalledMutationGate
        let launcher: ControllableProcessLauncher
        let center: OperationCenter
        /// One tick per inventory terminal. Must stay at zero throughout.
        let inventoryTerminals: Counter
        let loop: Task<Void, Never>
        let watcher: Task<Void, Never>

        func stop() {
            loop.cancel()
            watcher.cancel()
        }
    }

    private func harness() -> Harness {
        let source = FakeServicesPayloadSource([.services(["atuin"])])
        let store = ServicesStore(source: source)
        let clock = TestClock()
        let servicesGate = InstalledMutationGate()
        let installedGate = InstalledMutationGate()
        let coordinator = ServicesRefreshCoordinator(
            store: store,
            mutations: servicesGate,
            clock: clock
        )
        let launcher = ControllableProcessLauncher()
        let center = OperationCenter(
            gates: MutationGates([
                (.installedInventory, installedGate),
                (.services, servicesGate)
            ]),
            launcherFactory: { _ in launcher }
        )
        center.attach(installation: TestInstallation.appleSilicon)

        let inventoryTerminals = Counter()
        let watcher = Task { [stream = installedGate.terminals] in
            for await _ in stream { inventoryTerminals.increment() }
        }
        return Harness(
            source: source,
            store: store,
            clock: clock,
            coordinator: coordinator,
            servicesGate: servicesGate,
            installedGate: installedGate,
            launcher: launcher,
            center: center,
            inventoryTerminals: inventoryTerminals,
            loop: Task { await coordinator.run() },
            watcher: watcher
        )
    }

    private func target(_ name: String) throws -> ServiceTarget {
        try #require(ServiceTarget(name: name))
    }

    // MARK: - SM3 sc4 — suppressed in flight, exactly one at the terminal

    @Test("Polling is suppressed while a service mutation is in flight")
    func pollingIsSuppressedWhileAServiceMutationIsInFlight() async throws {
        let harness = harness()
        defer { harness.stop() }

        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        harness.coordinator.setVisible(true)
        await harness.source.waitForCalls(atLeast: 2)
        let beforeMutating = harness.source.callCount

        // Prove the poll is genuinely alive first — otherwise "no refresh ran"
        // below would be true for the wrong reason.
        await harness.clock.waitForSleepers(atLeast: 1)
        await harness.clock.advance(by: .seconds(5))
        await settle()
        #expect(harness.source.callCount == beforeMutating + 1, "the poll was not running to begin with")
        let baseline = harness.source.callCount

        // A service restart begins and stays in flight.
        let item = harness.center.submit(service: .restart(try target("atuin")))
        await harness.launcher.waitForLaunches(atLeast: 1)
        await settle()
        #expect(harness.servicesGate.isMutating, "the services gate never opened")
        #expect(item.isTerminal == false)

        // Several intervals pass while it runs.
        for _ in 0..<4 {
            await harness.clock.waitForSleepers(atLeast: 1)
            await harness.clock.advance(by: .seconds(5))
            await settle()
        }

        #expect(
            harness.source.callCount == baseline,
            "\(harness.source.callCount - baseline) poll refresh(es) ran during a mutation"
        )

        // The terminal outcome: exactly one refresh, and not two.
        harness.launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        await harness.source.waitForCalls(atLeast: baseline + 1)
        await settle()

        #expect(item.isTerminal)
        #expect(
            harness.source.callCount - baseline == 1,
            "the terminal owed one refresh and got \(harness.source.callCount - baseline)"
        )

        // And the poll resumes afterwards.
        await harness.clock.waitForSleepers(atLeast: 1)
        await harness.clock.advance(by: .seconds(5))
        await settle()
        #expect(harness.source.callCount - baseline == 2, "the poll did not resume after the terminal")
        harness.coordinator.setVisible(false)
    }

    // MARK: - SM8 sc2 — failure and cancellation owe the same one refresh

    @Test(
        "A failed or cancelled service verb still forces exactly one services refresh",
        arguments: [Ending.failed, .cancelled]
    )
    func aFailedOrCancelledServiceVerbStillForcesExactlyOneServicesRefresh(
        ending: Ending
    ) async throws {
        let harness = harness()
        defer { harness.stop() }

        // Deliberately **not** visible: the refresh owed at a terminal is owed
        // whatever the surface is doing, so the count cannot be confused with a
        // poll tick.
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount
        #expect(harness.coordinator.isPolling == false)

        let item = harness.center.submit(service: .restart(try target("atuin")))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let process = harness.launcher.launchedProcesses[0]

        switch ending {
        case .failed:
            process.terminate(with: BrewExit(status: 1, reason: .exited))
        case .cancelled:
            harness.center.cancel(item)
            await TestPoll.until(process.deliveredSignals.isEmpty == false)
            process.terminate(with: BrewExit(status: 130, reason: .cancelled(signal: SIGINT)))
        }

        await harness.source.waitForCalls(atLeast: baseline + 1)
        await settle()

        #expect(item.isTerminal)
        #expect(item.outcome == ending.outcome)
        #expect(
            harness.source.callCount - baseline == 1,
            "\(ending) forced \(harness.source.callCount - baseline) services refreshes rather than one"
        )
        // And no inventory re-snapshot in either case (SM8, II10 sc8).
        #expect(
            harness.inventoryTerminals.value == 0,
            "a service verb forced \(harness.inventoryTerminals.value) inventory re-snapshot(s)"
        )
        #expect(harness.installedGate.isMutating == false)
        #expect(harness.servicesGate.isMutating == false)
    }

    enum Ending: Sendable, CustomStringConvertible {
        case failed
        case cancelled

        var outcome: MutationOutcome {
            switch self {
            case .failed: .failed(status: 1)
            case .cancelled: .cancelled
            }
        }

        var description: String {
            switch self {
            case .failed: "a failed restart"
            case .cancelled: "a cancelled restart"
            }
        }
    }

    /// A successful verb owes exactly one too — the same rule, stated for the
    /// case a reader would otherwise assume was covered by the poll.
    @Test("A successful service verb refreshes services once, with no poll running")
    func aSuccessfulServiceVerbRefreshesOnce() async throws {
        let harness = harness()
        defer { harness.stop() }

        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount

        let item = harness.center.submit(service: .start(try target("atuin")))
        await harness.launcher.waitForLaunches(atLeast: 1)
        harness.launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        await harness.source.waitForCalls(atLeast: baseline + 1)
        await settle()

        #expect(item.outcome == .succeeded)
        #expect(harness.source.callCount - baseline == 1)
        #expect(harness.inventoryTerminals.value == 0)
    }

    // MARK: - SM3's secondary read-only surface (menu-bar D3)

    /// A surface that shows services state **without being** the services
    /// section may freshen it once. It may not join the visibility conjunction
    /// that gates the poll.
    ///
    /// The conjunction has exactly two halves on purpose, reported from two
    /// places, and folding a third in is the class of bug it exists to prevent:
    /// a secondary surface that reported visibility would leave the poll running
    /// after the section itself closed. This asserts it cannot, because it never
    /// reaches either half.
    @Test("A baseline refresh starts no poll and reports no visibility")
    func aBaselineRefreshStartsNoPollAndReportsNoVisibility() async throws {
        let harness = harness()
        defer { harness.stop() }

        // Deliberately not visible, and never made visible before the baseline.
        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount
        #expect(harness.coordinator.isPolling == false)

        await harness.coordinator.refreshBaseline()
        await settle()

        #expect(
            harness.source.callCount - baseline == 1,
            "the baseline performed \(harness.source.callCount - baseline) refreshes rather than one"
        )
        #expect(harness.coordinator.isPolling == false, "a secondary refresh started a poll")

        // Sixty seconds is twelve poll intervals. Nothing was scheduled on the
        // clock, so nothing ticks.
        await harness.clock.advance(by: .seconds(60))
        await settle()
        #expect(
            harness.source.callCount - baseline == 1,
            "advancing the clock produced \(harness.source.callCount - baseline - 1) further invocation(s)"
        )
        #expect(harness.coordinator.isPolling == false)

        // Neither half of the conjunction was consumed: the section becoming
        // visible still starts the poll normally, with its own baseline.
        harness.coordinator.setVisible(true)
        await harness.source.waitForCalls(atLeast: baseline + 2)
        await settle()
        #expect(harness.coordinator.isPolling, "the section could no longer start the poll")
        #expect(harness.source.callCount - baseline == 2)

        await harness.clock.waitForSleepers(atLeast: 1)
        await harness.clock.advance(by: .seconds(5))
        await settle()
        #expect(harness.source.callCount - baseline == 3, "the poll did not tick after the section appeared")
        harness.coordinator.setVisible(false)
    }

    /// The one refresh is **skipped**, not deferred: the mutation's terminal
    /// already owes its own, and queueing a second would make a restart refresh
    /// twice at the moment it settles.
    @Test("A baseline refresh is skipped entirely while a mutation is in flight")
    func aBaselineRefreshIsSkippedEntirelyWhileAMutationIsInFlight() async throws {
        let harness = harness()
        defer { harness.stop() }

        await harness.coordinator.refresh(using: TestInstallation.appleSilicon)
        let baseline = harness.source.callCount

        let item = harness.center.submit(service: .restart(try target("atuin")))
        await harness.launcher.waitForLaunches(atLeast: 1)
        await settle()
        #expect(harness.servicesGate.isMutating, "the services gate never opened")

        await harness.coordinator.refreshBaseline()
        await settle()
        #expect(
            harness.source.callCount == baseline,
            "\(harness.source.callCount - baseline) refresh(es) ran during a mutation"
        )

        // The terminal owes exactly one — not two, so nothing was queued behind
        // the skip.
        harness.launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        await harness.source.waitForCalls(atLeast: baseline + 1)
        await settle()

        #expect(item.isTerminal)
        #expect(
            harness.source.callCount - baseline == 1,
            "the terminal produced \(harness.source.callCount - baseline) refreshes rather than one"
        )
        #expect(harness.servicesGate.isMutating == false)

        // Released, the next call refreshes once again — the skip suppressed it
        // for the duration, it did not disable it.
        await harness.coordinator.refreshBaseline()
        await settle()
        #expect(harness.source.callCount - baseline == 2)
        #expect(harness.coordinator.isPolling == false, "none of this started a poll")
    }
}
