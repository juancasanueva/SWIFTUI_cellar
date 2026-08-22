//
//  TipPurchaseTests.swift
//  TipJarTests
//

import Testing
import TipJar

/// Requirement 2 — "Six outcomes, and each one claims exactly what happened".
///
/// The six exist so that no outcome has to be described in prose to be acted on.
/// A consumer decides what to show by switching, never by reading a reason
/// string — which is what keeps "Ask to Buy is waiting" from being rendered as a
/// thank-you and "verification failed" from being rendered as an accusation.
@Suite("Tip purchase outcomes")
struct TipPurchaseTests {
    // MARK: - A verified purchase completes and thanks the user

    @Test("A completed purchase is the only outcome that earns a thank-you")
    func aCompletedPurchaseIsTheOnlyOutcomeThatEarnsAThankYou() async {
        let purchases = RecordingTipPurchases(outcome: .completed)
        let product = TipFixtures.product()

        let outcome = await TipPurchaseRunner(purchases: purchases).run(for: .available(product))

        #expect(outcome == .completed)
        #expect(outcome.recordsGratitude)
        #expect(outcome.claimsTipComplete)
        #expect(purchases.events == [.purchased(product)])
    }

    // MARK: - Cancelling says nothing

    @Test("Cancelling is silent: no thank-you, no reason, nothing to surface")
    func cancellingIsSilentNoThankYouNoReasonNothingToSurface() async {
        let purchases = RecordingTipPurchases(outcome: .cancelled)
        let product = TipFixtures.product()

        let outcome = await TipPurchaseRunner(purchases: purchases).run(for: .available(product))

        #expect(outcome == .cancelled)
        #expect(outcome.isSilent)
        #expect(outcome.recordsGratitude == false)
        #expect(outcome.failureReason == nil, "a dismissed sheet was reported as an error")
        #expect(purchases.purchaseCount == 1, "the seam was never reached, so nothing was cancelled")
    }

    // MARK: - Ask to Buy is honest that nothing has been paid

    @Test("A deferred approval says the tip is not complete")
    func aDeferredApprovalSaysTheTipIsNotComplete() async {
        let purchases = RecordingTipPurchases(outcome: .pending)
        let product = TipFixtures.product()

        let outcome = await TipPurchaseRunner(purchases: purchases).run(for: .available(product))

        #expect(outcome == .pending)
        #expect(outcome.claimsTipComplete == false, "a deferred approval was presented as paid")
        #expect(outcome.recordsGratitude == false)
        #expect(outcome != .completed)
        #expect(outcome.failureReason == nil, "waiting for a parent was reported as a failure")
    }

    // MARK: - An unverified transaction is finished but never thanked

    @Test("An unverified transaction is neither thanked nor called a failure")
    func anUnverifiedTransactionIsNeitherThankedNorCalledAFailure() async {
        let purchases = RecordingTipPurchases(outcome: .unverified)
        let product = TipFixtures.product()

        let outcome = await TipPurchaseRunner(purchases: purchases).run(for: .available(product))

        #expect(outcome == .unverified)
        #expect(outcome.recordsGratitude == false)
        #expect(outcome.failureReason == nil, "verification trouble was collapsed into failure")
        #expect(outcome.isSilent == false, "an unverified transaction was hidden entirely")
        #expect(purchases.purchaseCount == 1)
    }

    // MARK: - A thrown purchase is a typed failure

    @Test("A thrown purchase carries a typed reason and thanks nobody")
    func aThrownPurchaseCarriesATypedReasonAndThanksNobody() async {
        let purchases = RecordingTipPurchases(outcome: .failed(reason: "networkUnavailable"))
        let product = TipFixtures.product()

        let outcome = await TipPurchaseRunner(purchases: purchases).run(for: .available(product))

        #expect(outcome == .failed(reason: "networkUnavailable"))
        #expect(outcome.failureReason == "networkUnavailable")
        #expect(outcome.recordsGratitude == false)
        #expect(outcome.claimsTipComplete == false)
    }

    /// Triangulation: a second reason must survive intact, or `failureReason`
    /// could be answering with a constant.
    @Test("A different failure reason is carried through unchanged")
    func aDifferentFailureReasonIsCarriedThroughUnchanged() async {
        let purchases = RecordingTipPurchases(outcome: .failed(reason: "paymentDeclined"))
        let product = TipFixtures.product()

        let outcome = await TipPurchaseRunner(purchases: purchases).run(for: .available(product))

        #expect(outcome.failureReason == "paymentDeclined")
        #expect(outcome != .failed(reason: "networkUnavailable"))
    }

    /// A case StoreKit adds after this app was compiled becomes a stated
    /// failure, never silence. The conformer has exactly one place to send it.
    @Test("An unrecognized store answer becomes a typed failure, not silence")
    func anUnrecognizedStoreAnswerBecomesATypedFailureNotSilence() {
        let outcome = TipPurchaseOutcome.unrecognized("someFutureCase")

        #expect(outcome.failureReason?.contains("someFutureCase") == true)
        #expect(outcome.recordsGratitude == false)
        #expect(outcome.isSilent == false, "an unknown answer was swallowed")
    }

    // MARK: - Purchasing without a product attempts nothing

    @Test("A purchase with an empty catalog reaches the seam not at all")
    func aPurchaseWithAnEmptyCatalogReachesTheSeamNotAtAll() async {
        let purchases = RecordingTipPurchases(outcome: .completed)

        let outcome = await TipPurchaseRunner(purchases: purchases)
            .run(for: .unavailable(.emptyCatalog))

        #expect(outcome == .unavailable(reason: TipUnavailableReason.emptyCatalog.diagnostic))
        #expect(purchases.events.isEmpty, "a purchase was attempted with nothing to buy")
        #expect(outcome.recordsGratitude == false)
    }

    /// Triangulation on the refusal path: a failed load refuses too, and says so
    /// differently, so the guard is over the availability value rather than over
    /// one hardcoded case.
    @Test("A failed load also refuses, and carries its own reason")
    func aFailedLoadAlsoRefusesAndCarriesItsOwnReason() async {
        let purchases = RecordingTipPurchases(outcome: .completed)

        let outcome = await TipPurchaseRunner(purchases: purchases)
            .run(for: .unavailable(.loadFailed("transport")))

        #expect(outcome.recordsGratitude == false)
        #expect(purchases.events.isEmpty)
        #expect(
            outcome != .unavailable(reason: TipUnavailableReason.emptyCatalog.diagnostic),
            "a failed load was reported as a build that simply has nothing to sell"
        )
    }

    /// And the control: a still-loading catalog must not buy anything either,
    /// or the surface could resolve a tap into a purchase of a product nobody
    /// has seen a price for.
    @Test("A catalog that has not settled buys nothing")
    func aCatalogThatHasNotSettledBuysNothing() async {
        let purchases = RecordingTipPurchases(outcome: .completed)

        for availability in [TipAvailability.unknown, .loading] {
            let outcome = await TipPurchaseRunner(purchases: purchases).run(for: availability)
            #expect(outcome.recordsGratitude == false)
        }

        #expect(purchases.events.isEmpty, "an unsettled catalog was purchased from")
    }

    // MARK: - The state machine around one purchase

    @Test("Purchase state distinguishes idle, in flight, and settled")
    func purchaseStateDistinguishesIdleInFlightAndSettled() {
        #expect(TipPurchaseState.idle != .inFlight)
        #expect(TipPurchaseState.settled(.completed) != .settled(.cancelled))
        #expect(TipPurchaseState.inFlight != .settled(.completed))
    }
}
