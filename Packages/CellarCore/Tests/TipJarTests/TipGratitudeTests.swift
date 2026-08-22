//
//  TipGratitudeTests.swift
//  TipJarTests
//

import CellarTestSupport
import Testing
import TipJar

/// Requirement 6 — "The thank-you is one local boolean, and that is the whole
/// record", and requirement 4's half of it: the flag remembers, and grants
/// nothing.
///
/// Cellar's no-telemetry claim is what a payment feature is most likely to be
/// suspected of breaking, so almost every assertion here is an **absence** — no
/// write on five of the six outcomes, no request, no process. Each one is
/// counted against zero, with a control somewhere proving the counter moves.
@Suite("Tip gratitude")
@MainActor
struct TipGratitudeTests {
    // MARK: - Arrangement

    /// Builds a store and runs `start()` to the point where it is observing.
    ///
    /// `start()` never returns by design, so it is held in a task and the test
    /// waits on the **seam's** own counter rather than on the store's
    /// main-actor state: by the time observation has begun, hydration and the
    /// catalog load are both behind it.
    private static func started(
        catalog: FakeTipCatalog,
        purchases: RecordingTipPurchases,
        gratitude: RecordingTipGratitude
    ) async -> (store: TipStore, running: Task<Void, Never>) {
        let store = TipStore(catalog: catalog, purchases: purchases, gratitude: gratitude)
        let running = Task { @MainActor in await store.start() }
        await TestPoll.until(purchases.observationCount == 1)
        return (store, running)
    }

    // MARK: - The thank-you survives a relaunch

    @Test("Launch reads the stored flag back, and writes nothing doing it")
    func launchReadsTheStoredFlagBackAndWritesNothingDoingIt() async {
        let gratitude = RecordingTipGratitude(hasTipped: true)
        let purchases = RecordingTipPurchases()
        let (store, running) = await Self.started(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: gratitude
        )
        defer { running.cancel() }

        #expect(store.hasTipped, "a user who already gave would be asked as if they had not")
        #expect(gratitude.readCount == 1)
        #expect(gratitude.writeCount == 0, "hydration wrote to the record it was only reading")
    }

    /// Triangulation: a store with nothing recorded must come up unset, or
    /// hydration could be answering `true` regardless.
    @Test("A launch with nothing recorded comes up unset")
    func aLaunchWithNothingRecordedComesUpUnset() async {
        let gratitude = RecordingTipGratitude(hasTipped: false)
        let purchases = RecordingTipPurchases()
        let (store, running) = await Self.started(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: gratitude
        )
        defer { running.cancel() }

        #expect(store.hasTipped == false)
        #expect(gratitude.readCount == 1)
    }

    // MARK: - A completed tip is the one thing that writes

    @Test("A completed tip records the thank-you exactly once")
    func aCompletedTipRecordsTheThankYouExactlyOnce() async {
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases(outcome: .completed)
        let (store, running) = await Self.started(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: gratitude
        )
        defer { running.cancel() }

        await store.tip()

        #expect(store.purchase == .settled(.completed))
        #expect(store.hasTipped)
        #expect(gratitude.writeCount == 1)
        #expect(gratitude.storedValue)
    }

    // MARK: - A non-completing outcome writes nothing

    @Test(
        "Every outcome other than completed leaves the record untouched",
        arguments: [
            TipPurchaseOutcome.cancelled,
            .pending,
            .unverified,
            .failed(reason: "networkUnavailable")
        ]
    )
    func everyOutcomeOtherThanCompletedLeavesTheRecordUntouched(
        outcome: TipPurchaseOutcome
    ) async {
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases(outcome: outcome)
        let (store, running) = await Self.started(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: gratitude
        )
        defer { running.cancel() }

        await store.tip()

        #expect(store.purchase == .settled(outcome))
        #expect(store.hasTipped == false)
        #expect(gratitude.writeCount == 0, "\(outcome) wrote the thank-you")
        #expect(gratitude.storedValue == false)
    }

    /// The sixth case, which cannot be arranged through the seam because it
    /// never reaches the seam at all.
    @Test("An unavailable catalog writes nothing and attempts nothing")
    func anUnavailableCatalogWritesNothingAndAttemptsNothing() async {
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases(outcome: .completed)
        let (store, running) = await Self.started(
            catalog: FakeTipCatalog(.loaded([])),
            purchases: purchases,
            gratitude: gratitude
        )
        defer { running.cancel() }

        await store.tip()

        #expect(store.availability == .unavailable(.emptyCatalog))
        #expect(store.hasTipped == false)
        #expect(gratitude.writeCount == 0)
        #expect(purchases.purchaseCount == 0, "a purchase was attempted with nothing to buy")
    }

    // MARK: - The surface follows availability, and nothing else

    @Test("The surface shows only for an available catalog")
    func theSurfaceShowsOnlyForAnAvailableCatalog() async {
        let stockedPurchases = RecordingTipPurchases()
        let emptyPurchases = RecordingTipPurchases()
        let stocked = TipStore(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: stockedPurchases,
            gratitude: RecordingTipGratitude()
        )
        let empty = TipStore(
            catalog: FakeTipCatalog(.loaded([])),
            purchases: emptyPurchases,
            gratitude: RecordingTipGratitude()
        )

        #expect(stocked.showsTipSurface == false, "the surface appeared before anything was loaded")

        let first = Task { @MainActor in await stocked.start() }
        let second = Task { @MainActor in await empty.start() }
        defer {
            first.cancel()
            second.cancel()
        }
        await TestPoll.until(
            stockedPurchases.observationCount == 1 && emptyPurchases.observationCount == 1
        )

        #expect(stocked.showsTipSurface)
        #expect(empty.showsTipSurface == false, "an empty catalog offered a control that can buy nothing")
        #expect(empty.availability == .unavailable(.emptyCatalog))
        #expect(empty.availability.product == nil)
    }

    /// Requirement 4's half: the record remembers, and gates nothing. A user who
    /// already gave still sees the same surface, at the same price, and may give
    /// again.
    @Test("A recorded thank-you neither hides the surface nor refuses a second tip")
    func aRecordedThankYouNeitherHidesTheSurfaceNorRefusesASecondTip() async {
        let gratitude = RecordingTipGratitude(hasTipped: true)
        let purchases = RecordingTipPurchases(outcome: .completed)
        let product = TipFixtures.product()
        let (store, running) = await Self.started(
            catalog: FakeTipCatalog(.loaded([product])),
            purchases: purchases,
            gratitude: gratitude
        )
        defer { running.cancel() }

        #expect(store.hasTipped, "the arrangement never took")
        #expect(store.showsTipSurface, "an earlier tip removed the surface")
        #expect(store.availability.product?.displayPrice == TipFixtures.sentinelPrice)

        await store.tip()

        #expect(store.purchase == .settled(.completed), "a second tip was refused")
        #expect(purchases.events == [.drained, .observed, .purchased(product)])
        #expect(store.showsTipSurface, "tipping again removed the surface")
        #expect(store.availability.product?.displayPrice == TipFixtures.sentinelPrice)
    }

    // MARK: - A tip in flight is not a tip twice

    @Test("A second tip while one is in flight is a no-op")
    func aSecondTipWhileOneIsInFlightIsANoOp() async {
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases(outcome: .completed)
        let store = TipStore(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: gratitude
        )
        let running = Task { @MainActor in await store.start() }
        defer { running.cancel() }
        await TestPoll.until(purchases.observationCount == 1)

        // Both taps are issued before either settles, which is what a
        // double-click on the button actually does.
        async let first: Void = store.tip()
        async let second: Void = store.tip()
        _ = await (first, second)

        #expect(purchases.purchaseCount == 1, "one tap became two payments")
        #expect(gratitude.writeCount == 1)
    }

    // MARK: - The tip path costs no egress and no brew process

    /// A complete ledger of every seam interaction one whole tip cycle produces.
    ///
    /// This test used to hand a recording network/process spy to **nothing** and
    /// then assert its counters were zero — two assertions that could not fail
    /// whatever the tip path did. The spy is gone: `TipJar` declares no network
    /// or process seam and, having zero dependencies, could not reach one if it
    /// wanted to, so there was never anything for a spy to observe.
    ///
    /// What can fail, and does the work the old assertions pretended to, is the
    /// **exhaustive** count below. Every call the cycle makes is enumerated
    /// exactly, so a fourth interaction, a second catalog fetch or an extra read
    /// breaks this test — which is the observable shape of "the tip path does
    /// only these three things". The claim that those three are the *only* seams
    /// reachable at all is a build-graph fact, asserted in the manifest by
    /// `TipCompositionTests.theTipJarTargetDeclaresAnEmptyDependencyList…`.
    @Test("A whole tip cycle touches the three declared seams, exactly this many times")
    func aWholeTipCycleTouchesTheThreeDeclaredSeamsExactlyThisManyTimes() async {
        let product = TipFixtures.product()
        let catalog = FakeTipCatalog(.loaded([product]))
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases(outcome: .completed)
        let (store, running) = await Self.started(
            catalog: catalog,
            purchases: purchases,
            gratitude: gratitude
        )
        defer { running.cancel() }

        await store.tip()

        #expect(store.hasTipped, "the cycle under measurement never actually ran")
        #expect(catalog.callCount == 1, "the catalog was fetched more than once for one launch")
        #expect(purchases.events == [.drained, .observed, .purchased(product)])
        #expect(gratitude.readCount == 1, "the flag was re-read outside hydration")
        #expect(gratitude.writeCount == 1)
    }
}
