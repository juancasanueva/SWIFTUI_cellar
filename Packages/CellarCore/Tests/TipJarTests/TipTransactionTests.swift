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
    // MARK: - Every transaction is finished, including the unverified one

    /// The rule requirement 3 argues hardest for, as a value.
    ///
    /// It used to live only inside the conformer's `switch`, where the
    /// unverified branch is unreachable from any test: `SKTestSession` cannot
    /// produce a transaction that fails verification, so the one clause the spec
    /// spends a paragraph on was proved by reading it. Moving the **decision**
    /// here — leaving only the `Transaction.finish()` call itself on the far side
    /// of StoreKit — makes both branches executable, which is what the rest of
    /// this capability's rules already are.
    @Test("An unverified transaction must still be finished, and must not be thanked")
    func anUnverifiedTransactionMustStillBeFinishedAndMustNotBeThanked() {
        let disposition = TipTransactionDisposition.forTransaction(isVerified: false)

        #expect(
            disposition.mustFinish,
            "an unverified consumable was left unfinished, so it replays at every launch forever"
        )
        #expect(disposition.outcome == .unverified)
        #expect(disposition.outcome.recordsGratitude == false)
        #expect(
            disposition.outcome.failureReason == nil,
            "a verification failure was collapsed into an accusation of failure"
        )
    }

    /// Triangulation, and the reason the property is named rather than implied:
    /// `mustFinish` has to be true for **both** inputs. A mapping that returned
    /// the verified branch's answer for everything would pass the test above.
    @Test("A verified transaction is finished too, and it is the one that is thanked")
    func aVerifiedTransactionIsFinishedTooAndItIsTheOneThatIsThanked() {
        let disposition = TipTransactionDisposition.forTransaction(isVerified: true)

        #expect(disposition.mustFinish)
        #expect(disposition.outcome == .completed)
        #expect(disposition.outcome.recordsGratitude)
    }

    /// Stated as one assertion over both inputs, so the invariant reads the way
    /// the spec states it: finishing is **not** conditional on verification.
    @Test("Finishing is unconditional; only the thank-you depends on verification")
    func finishingIsUnconditionalOnlyTheThankYouDependsOnVerification() {
        let dispositions = [true, false].map(TipTransactionDisposition.forTransaction(isVerified:))
        let finishes = dispositions.map(\.mustFinish)
        let outcomes = dispositions.map(\.outcome)
        let gratitude = outcomes.map(\.recordsGratitude)

        #expect(finishes == [true, true], "finishing became conditional on verification")
        #expect(
            outcomes == [.completed, .unverified],
            "verification stopped deciding the thank-you, or started deciding the finish"
        )
        #expect(gratitude == [true, false], "the thank-you stopped depending on verification")
    }

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
