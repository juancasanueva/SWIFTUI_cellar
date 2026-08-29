import CellarTestSupport
import Foundation
import Synchronization
import Testing

@testable import BrewClient
@testable import BrewProcess

/// When npm is read, and — far more importantly — when it is *not*.
///
/// The whole point of a separate coordinator is that `npm outdated -g --json`
/// needs the network and can be slow, so it must not ride on the trigger that
/// re-reads Homebrew's inventory. brew refreshes on every activation; npm must
/// not, because a user who ⌘-tabs twenty times an hour would otherwise make
/// twenty registry round-trips (`npm-source`: the npm outdated cadence is
/// independent of brew's activation-driven refresh; design D10).
///
/// Every claim here counts what the payload source was actually asked, on a
/// manually advanced clock, so "once per hour" is a fact about the code rather
/// than about how long the test happened to take.
@MainActor
@Suite("npm refresh cadence", .timeLimit(.minutes(1)))
struct NpmRefreshCoordinatorTests {
    private static let environment = NpmEnvironmentFixture.detected

    private struct Harness {
        let source: FakeNpmPayloadSource
        let store: NpmStore
        let clock: TestClock
        let coordinator: NpmRefreshCoordinator
    }

    private func harness(
        listings: [FakeNpmPayloadSource.Answer] = [.globals([("typescript", "5.6.0")])],
        reports: [FakeNpmPayloadSource.Answer] = [.payload("{}")],
        mutations: InstalledMutationGate? = nil
    ) -> Harness {
        let source = FakeNpmPayloadSource(listings: listings, reports: reports)
        let store = NpmStore(installed: InstalledStore(), source: source)
        let clock = TestClock()
        return Harness(
            source: source,
            store: store,
            clock: clock,
            coordinator: NpmRefreshCoordinator(
                store: store,
                mutations: mutations,
                clock: clock
            )
        )
    }

    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    /// One period, waited for rather than raced with: the periodic task has to
    /// have reached its `sleep` before time may move, or the tick this asserts
    /// is silently skipped.
    private func advanceOnePeriod(_ harness: Harness) async {
        await harness.clock.waitForSleepers(atLeast: 1)
        await harness.clock.advance(by: NpmRefreshCoordinator.defaultOutdatedInterval)
        await settle()
    }

    // MARK: - Becoming detected

    @Test("A source that becomes detected is listed and checked exactly once")
    func detectionListsAndChecksOnce() async {
        let harness = harness()
        defer { harness.coordinator.stop() }

        await harness.coordinator.apply(.detected(Self.environment))
        await settle()

        #expect(harness.source.listingCount == 1)
        #expect(harness.source.reportCount == 1)
        #expect(harness.store.inventory.packages.map(\.name) == ["typescript"])
        #expect(harness.store.inventory.outdated.isUpToDate)
    }

    /// Triangulation over the other half of the toggle: turning the source off
    /// withdraws the rows *and* ends the cadence, so a disabled npm costs
    /// nothing on every subsequent tick.
    @Test("Turning the source off withdraws its rows and stops the cadence")
    func disablingStopsTheCadence() async {
        let harness = harness()
        defer { harness.coordinator.stop() }

        await harness.coordinator.apply(.detected(Self.environment))
        await settle()
        await harness.coordinator.apply(.disabled)
        await settle()

        #expect(harness.store.inventory.packages.isEmpty)
        #expect(harness.store.isContributing == false)

        let listings = harness.source.listingCount
        let reports = harness.source.reportCount
        await harness.clock.advance(by: NpmRefreshCoordinator.defaultOutdatedInterval * 3)
        await settle()

        #expect(harness.source.listingCount == listings, "a disabled source was still listed")
        #expect(harness.source.reportCount == reports, "a disabled source was still checked")
    }

    // MARK: - Activation (`npm-source`: activation does not trigger the check)

    @Test("Five activations re-list npm and never check it; one period later, exactly one check")
    func activationNeverChecksButThePeriodDoes() async {
        let harness = harness()
        defer { harness.coordinator.stop() }

        await harness.coordinator.apply(.detected(Self.environment))
        await settle()
        let checksAfterDetection = harness.source.reportCount

        for _ in 0..<5 {
            await harness.coordinator.activate()
        }
        await settle()

        #expect(harness.source.listingCount == 6, "activation stopped re-reading the local listing")
        #expect(
            harness.source.reportCount == checksAfterDetection,
            "app activation reached the registry"
        )

        await advanceOnePeriod(harness)
        #expect(harness.source.reportCount == checksAfterDetection + 1)
    }

    // MARK: - Terminals

    @Test("Each npm terminal outcome forces exactly one listing and one check")
    func eachTerminalForcesOneRefresh() async throws {
        let gate = InstalledMutationGate()
        let harness = harness(mutations: gate)
        defer { harness.coordinator.stop() }

        await harness.coordinator.apply(.detected(Self.environment))
        await settle()
        let listings = harness.source.listingCount
        let reports = harness.source.reportCount

        let consumer = Task { await harness.coordinator.run() }
        defer { consumer.cancel() }

        gate.begin()
        gate.end(
            event: MutationTerminalEvent(
                token: MutationOperationToken(),
                domain: .npmInventory,
                installationURL: Self.environment.executableURL
            )
        )
        await settle()

        #expect(harness.source.listingCount == listings + 1)
        #expect(harness.source.reportCount == reports + 1)
    }

    // MARK: - Explicit refresh and coalescing

    @Test("An explicit refresh reads both, and overlapping ones coalesce into one check")
    func overlappingChecksCoalesceAndLaterOnesRunFresh() async {
        let source = GatedNpmPayloadSource()
        let store = NpmStore(installed: InstalledStore(), source: source)
        let coordinator = NpmRefreshCoordinator(store: store, clock: TestClock())
        defer { coordinator.stop() }

        // Detection's own check is still held open by the gate, so the two
        // explicit refreshes below really do overlap an in-flight one.
        await coordinator.apply(.detected(Self.environment))
        await TestPoll.until(source.reportCount >= 1)

        async let first: Void = coordinator.refresh()
        async let second: Void = coordinator.refresh()
        await TestPoll.until(source.listingCount >= 3)

        #expect(source.listingCount == 3, "an explicit refresh stopped re-reading the listing")
        #expect(source.reportCount == 1, "overlapping requests reached the registry more than once")

        source.open()
        _ = await (first, second)

        // A request raised *after* the first settled is a new question, so it
        // runs rather than joining an answer that is already history.
        await coordinator.refresh()
        #expect(source.reportCount == 2)
        #expect(source.listingCount == 4)
    }

    // MARK: - Failure

    /// A failed check must not spin: nothing retries it until the next tick,
    /// which is the difference between one offline machine and a machine
    /// hammering an unreachable registry.
    @Test("A failed check is left failed until the next period, never retried in a loop")
    func aFailedCheckWaitsForTheNextPeriod() async {
        let harness = harness(reports: [.failure(.networkUnavailable), .payload("{}")])
        defer { harness.coordinator.stop() }

        await harness.coordinator.apply(.detected(Self.environment))
        await settle()

        #expect(harness.store.inventory.outdated == .failed(.networkUnavailable))
        #expect(harness.store.inventory.outdated.isUpToDate == false)
        #expect(harness.source.reportCount == 1, "the failure was retried without waiting")

        await advanceOnePeriod(harness)
        #expect(harness.source.reportCount == 2)
        #expect(harness.store.inventory.outdated.isUpToDate)
    }

    @Test("The minimum interval between registry checks is one hour")
    func theIntervalIsOneHour() {
        #expect(NpmRefreshCoordinator.defaultOutdatedInterval == .seconds(3_600))
    }
}

/// A payload source whose *outdated* answer suspends until the test releases
/// it, so two requests can genuinely be in flight at the same moment.
///
/// The listing stays instantaneous: only the registry round-trip is the one
/// worth holding open, and holding both would make the coalescing claim about
/// the wrong call.
private final class GatedNpmPayloadSource: NpmPayloadSourcing, Sendable {
    private struct State {
        var listingCalls = 0
        var reportCalls = 0
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    var listingCount: Int { state.withLock { $0.listingCalls } }
    var reportCount: Int { state.withLock { $0.reportCalls } }

    /// Lets every held check — and every later one — complete.
    func open() {
        let waiting = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            let waiters = state.waiters
            state.waiters = []
            return waiters
        }
        for waiter in waiting { waiter.resume() }
    }

    func installed(using environment: NpmEnvironment) async throws(NpmInventoryError) -> Data {
        state.withLock { $0.listingCalls += 1 }
        return Data(#"{"name":"lib","dependencies":{}}"#.utf8)
    }

    func outdated(using environment: NpmEnvironment) async throws(NpmInventoryError) -> Data {
        state.withLock { $0.reportCalls += 1 }
        await held()
        return Data("{}".utf8)
    }

    private func held() async {
        await withCheckedContinuation { continuation in
            let alreadyOpen = state.withLock { state -> Bool in
                if state.isOpen { return true }
                state.waiters.append(continuation)
                return false
            }
            if alreadyOpen { continuation.resume() }
        }
    }
}
