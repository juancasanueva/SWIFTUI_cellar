//
//  TipTransactionTests.swift
//  TipJarTests
//

import CellarTestSupport
import Testing
import TipJar

/// Requirement 3 — "Every transaction is finished, including the unverified one".
///
/// A consumable that is never finished replays at every launch, forever. That is
/// the failure this suite exists to make unreachable, and it has an ordering to
/// it as much as a set of cases: the leftover queue is drained **before** the
/// update stream is observed, so a transaction sitting there from a previous
/// launch is dealt with rather than raced.
@Suite("Tip transactions")
@MainActor
struct TipTransactionTests {
    // MARK: - The unfinished queue is drained at launch

    @Test("Launch drains the unfinished queue before it starts observing")
    func launchDrainsTheUnfinishedQueueBeforeItStartsObserving() async {
        let purchases = RecordingTipPurchases()
        let store = TipStore(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: RecordingTipGratitude()
        )

        let running = Task { @MainActor in await store.start() }
        defer { running.cancel() }
        await TestPoll.until(purchases.observationCount == 1)

        #expect(
            purchases.events == [.drained, .observed],
            "observation started before the leftover queue was drained"
        )
    }

    @Test("Two drained transactions are both consumed, and only the verified one is thanked")
    func twoDrainedTransactionsAreBothConsumedAndOnlyTheVerifiedOneIsThanked() async {
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases(drainYields: [.completed, .unverified])
        let store = TipStore(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: gratitude
        )

        let running = Task { @MainActor in await store.start() }
        defer { running.cancel() }
        await TestPoll.until(gratitude.writeCount == 1)

        #expect(purchases.events == [.drained, .observed])
        #expect(store.hasTipped, "the verified leftover was finished without a thank-you")
        #expect(
            gratitude.writeCount == 1,
            "the unverified leftover was thanked as if it had been verified"
        )
    }

    /// Triangulation on the drain: a queue holding **only** an unverified
    /// leftover must still be drained and still write nothing, or the assertion
    /// above would pass against an implementation that thanks the first outcome
    /// it sees whatever it is.
    @Test("An unverified leftover alone is drained and thanks nobody")
    func anUnverifiedLeftoverAloneIsDrainedAndThanksNobody() async {
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases(drainYields: [.unverified])
        let store = TipStore(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: gratitude
        )

        let running = Task { @MainActor in await store.start() }
        defer { running.cancel() }
        await TestPoll.until(purchases.observationCount == 1)
        await Task.yield()

        #expect(purchases.events == [.drained, .observed])
        #expect(gratitude.writeCount == 0)
        #expect(store.hasTipped == false)
    }

    // MARK: - A later Ask-to-Buy approval is caught after the app was quit

    @Test("An approval arriving on the stream records the thank-you")
    func anApprovalArrivingOnTheStreamRecordsTheThankYou() async {
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases()
        let store = TipStore(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: gratitude
        )

        let running = Task { @MainActor in await store.start() }
        defer { running.cancel() }
        await TestPoll.until(purchases.observationCount == 1)
        #expect(store.hasTipped == false, "the arrangement started from an already-thanked state")

        purchases.deliver(.completed)
        await TestPoll.until(gratitude.writeCount == 1)

        #expect(store.hasTipped)
        #expect(gratitude.writeCount == 1)
    }

    /// The other half: an unverified transaction arriving on the same stream is
    /// consumed and finished, and writes nothing.
    @Test("An unverified transaction on the stream writes nothing")
    func anUnverifiedTransactionOnTheStreamWritesNothing() async {
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases()
        let store = TipStore(
            catalog: FakeTipCatalog(.loaded([TipFixtures.product()])),
            purchases: purchases,
            gratitude: gratitude
        )

        let running = Task { @MainActor in await store.start() }
        defer { running.cancel() }
        await TestPoll.until(purchases.observationCount == 1)

        purchases.deliver(.unverified)
        purchases.deliver(.completed)
        await TestPoll.until(gratitude.writeCount == 1)

        // The completed one behind it is the control: the stream really was
        // being read, so the unverified one's silence is an observation rather
        // than a listener that never ran.
        #expect(gratitude.writeCount == 1)
        #expect(store.hasTipped)
    }

    // MARK: - A second window joins the one observation

    @Test("Starting twice yields one observation, and the first is never restarted")
    func startingTwiceYieldsOneObservationAndTheFirstIsNeverRestarted() async {
        let gratitude = RecordingTipGratitude()
        let purchases = RecordingTipPurchases()
        let catalog = FakeTipCatalog(.loaded([TipFixtures.product()]))
        let store = TipStore(catalog: catalog, purchases: purchases, gratitude: gratitude)

        let first = Task { @MainActor in await store.start() }
        defer { first.cancel() }
        await TestPoll.until(purchases.observationCount == 1)

        // The second window, joining an app that is already observing.
        await store.start()

        #expect(purchases.observationCount == 1, "a second window started a second listener")
        #expect(catalog.callCount == 1, "the catalog was fetched again for a second window")
        #expect(gratitude.readCount == 1)

        // And the first observation is still live: an approval delivered after
        // the second `start()` still lands. Without this, "exactly one" would
        // also be satisfied by an implementation that cancelled the original.
        purchases.deliver(.completed)
        await TestPoll.until(gratitude.writeCount == 1)

        #expect(store.hasTipped, "the second start cancelled the observation the first one owned")
        #expect(purchases.events == [.drained, .observed])
    }
}
