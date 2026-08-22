//
//  TipFakes.swift
//  TipJarTests
//

import CellarTestSupport
import Synchronization
import TipJar

/// The product every suite arranges around.
///
/// Its `displayPrice` is a **sentinel, not a price**: the spec forbids a literal
/// price string in shipped source *and* in any test assertion, so the fixture
/// carries a value no locale could ever produce. That keeps "the price is read
/// from the loaded product" provable — the assertion compares against this
/// sentinel, which can only be there if the product's own field was used — while
/// leaving the structural sweep nothing to trip over.
enum TipFixtures {
    static let sentinelPrice = "PRICE-FROM-PRODUCT"
    static let otherSentinelPrice = "PRICE-FROM-A-DIFFERENT-PRODUCT"

    static func product(
        id: String = TipProductIDs.tip,
        displayName: String = "Tip",
        description: String = "A thank-you to the developer.",
        displayPrice: String = sentinelPrice
    ) -> TipProduct {
        TipProduct(
            id: id,
            displayName: displayName,
            description: description,
            displayPrice: displayPrice
        )
    }
}

/// A catalog seam that can be **held open**.
///
/// Holding it open is the whole point of the type: "loading is observable while
/// it is in progress" is a claim about a state that exists only between the call
/// and the answer, and a seam that answers instantly makes that window
/// unobservable — the test would pass against an implementation that never
/// published `loading` at all.
///
/// `Mutex`-backed rather than an actor so the seam stays a plain `Sendable`
/// value the way a shipped conformer is (the `RecordingAdvisorySource` idiom).
final class FakeTipCatalog: TipCatalogLoading, Sendable {
    private struct State {
        var calls = 0
        var isWaiting = false
        var isReleased = false
    }

    private let state = Mutex(State())
    private let result: TipCatalogLoad
    private let isGated: Bool

    init(_ result: TipCatalogLoad, heldOpen: Bool = false) {
        self.result = result
        isGated = heldOpen
    }

    /// How many times the catalog was actually asked. A settle-once claim is a
    /// count, not an impression.
    var callCount: Int { state.withLock(\.calls) }

    /// True once the seam has been called and is still holding its answer back.
    var isWaiting: Bool { state.withLock(\.isWaiting) }

    /// Lets the held-open answer through.
    func release() {
        state.withLock { $0.isReleased = true }
    }

    func loadTips() async -> TipCatalogLoad {
        state.withLock {
            $0.calls += 1
            $0.isWaiting = isGated
        }
        if isGated {
            await TestPoll.until(self.state.withLock(\.isReleased))
            state.withLock { $0.isWaiting = false }
        }
        return result
    }
}

/// A purchasing seam that records **what happened and in what order**.
///
/// Two of this capability's rules are orderings rather than values — the
/// unfinished queue is drained *before* observation starts, and a purchase
/// requested with no product must reach this seam *not at all* — and neither is
/// provable without a list of the calls that did happen.
final class RecordingTipPurchases: TipPurchasing, Sendable {
    /// The seam calls, in the order they arrived.
    enum Event: Equatable, Sendable {
        case purchased(TipProduct)
        case drained
        case observed
    }

    private struct State {
        var events: [Event] = []
        /// Consumed in order; once empty, `outcome` answers.
        var queued: [TipPurchaseOutcome] = []
        var outcome: TipPurchaseOutcome = .completed
        /// Yielded onto the stream when `drainUnfinished()` runs.
        var drainYields: [TipPurchaseOutcome] = []
    }

    private let state = Mutex(State())
    private let stream: AsyncStream<TipPurchaseOutcome>
    private let continuation: AsyncStream<TipPurchaseOutcome>.Continuation

    init(
        outcome: TipPurchaseOutcome = .completed,
        queued: [TipPurchaseOutcome] = [],
        drainYields: [TipPurchaseOutcome] = []
    ) {
        (stream, continuation) = AsyncStream.makeStream()
        state.withLock {
            $0.outcome = outcome
            $0.queued = queued
            $0.drainYields = drainYields
        }
    }

    // MARK: - Reading

    var events: [Event] { state.withLock(\.events) }

    var purchaseCount: Int {
        state.withLock { state in
            state.events.filter { event in
                if case .purchased = event { return true }
                return false
            }
            .count
        }
    }

    var observationCount: Int {
        state.withLock { state in state.events.filter { $0 == .observed }.count }
    }

    // MARK: - Arranging

    /// Pushes an outcome onto the update stream, the way a later Ask-to-Buy
    /// approval arrives at the next launch.
    func deliver(_ outcome: TipPurchaseOutcome) {
        continuation.yield(outcome)
    }

    // MARK: - The seam

    func purchase(_ product: TipProduct) async -> TipPurchaseOutcome {
        state.withLock { state -> TipPurchaseOutcome in
            state.events.append(.purchased(product))
            guard state.queued.isEmpty else { return state.queued.removeFirst() }
            return state.outcome
        }
    }

    func drainUnfinished() async {
        let yields = state.withLock { state -> [TipPurchaseOutcome] in
            state.events.append(.drained)
            return state.drainYields
        }
        for outcome in yields { continuation.yield(outcome) }
    }

    func transactionOutcomes() -> AsyncStream<TipPurchaseOutcome> {
        state.withLock { $0.events.append(.observed) }
        return stream
    }
}

/// The thank-you flag, recorded rather than stored.
///
/// Every non-completing outcome must write **nothing**, and nothing is only
/// provable by counting the writes that did happen against zero — with the
/// completing case somewhere else proving the counter moves at all.
final class RecordingTipGratitude: TipGratitudeRecording, Sendable {
    private struct State {
        var hasTipped = false
        var writes = 0
        var reads = 0
    }

    private let state = Mutex(State())

    init(hasTipped: Bool = false) {
        state.withLock { $0.hasTipped = hasTipped }
    }

    var writeCount: Int { state.withLock(\.writes) }
    var readCount: Int { state.withLock(\.reads) }
    var storedValue: Bool { state.withLock(\.hasTipped) }

    func hasTipped() async -> Bool {
        state.withLock {
            $0.reads += 1
            return $0.hasTipped
        }
    }

    func recordTip() async {
        state.withLock {
            $0.writes += 1
            $0.hasTipped = true
        }
    }
}

/// A main-actor log of the states a store or loader published, in order.
///
/// "Settles exactly once" is an assertion about a *sequence*, so the sequence has
/// to be kept.
@MainActor
final class TipStateLog {
    private(set) var states: [TipAvailability] = []

    func record(_ state: TipAvailability) { states.append(state) }
}
