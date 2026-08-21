//
//  TipAvailabilityTests.swift
//  TipJarTests
//

import CellarTestSupport
import Testing
import TipJar

/// Requirement 1 — "The tip catalog has three states, and empty is one of them".
///
/// The rule that costs the most to get wrong is the cheapest one to state: an
/// empty product list is a **settled** answer, not a spinner and not an error.
/// A Developer ID build, an App Store Connect record that does not exist yet and
/// a fetch that came back with nothing all arrive here, and every one of them
/// must produce a state the surface can act on rather than a load that never
/// finishes.
@Suite("Tip availability")
struct TipAvailabilityTests {
    // MARK: - A catalog with one product loads

    @Test("A catalog carrying one product resolves to that product")
    func aCatalogCarryingOneProductResolvesToThatProduct() {
        let product = TipFixtures.product()

        let availability = TipAvailability.resolved(from: .loaded([product]))

        #expect(availability == .available(product))
        #expect(availability.product?.id == TipProductIDs.tip)
        #expect(availability.product?.displayPrice == TipFixtures.sentinelPrice)
        #expect(availability.product?.displayPrice.isEmpty == false)
    }

    /// The id has one home: the constant, and nothing in the target repeats it.
    @Test("The product id is a single declared constant")
    func theProductIDIsASingleDeclaredConstant() {
        #expect(TipProductIDs.tip == "com.juancasanueva.cellar.tip")
        #expect(TipProductIDs.all == [TipProductIDs.tip])
    }

    /// Triangulation on the *value* rather than the shape: a second product with
    /// different fields must produce a different answer, or `resolved` could be
    /// returning a hardcoded one.
    @Test("A different product resolves to that different product")
    func aDifferentProductResolvesToThatDifferentProduct() {
        let other = TipFixtures.product(
            id: "com.juancasanueva.cellar.tip.other",
            displayName: "Another tip",
            description: "A second thank-you.",
            displayPrice: TipFixtures.otherSentinelPrice
        )

        let availability = TipAvailability.resolved(from: .loaded([other]))

        #expect(availability == .available(other))
        #expect(availability.product?.displayPrice == TipFixtures.otherSentinelPrice)
        #expect(availability.product?.description == "A second thank-you.")
    }

    /// More than one product is still one tip: the first is the one offered, and
    /// the surface never has to choose.
    @Test("The first product of a longer list is the one offered")
    func theFirstProductOfALongerListIsTheOneOffered() {
        let first = TipFixtures.product()
        let second = TipFixtures.product(
            id: "com.juancasanueva.cellar.tip.second",
            displayPrice: TipFixtures.otherSentinelPrice
        )

        let availability = TipAvailability.resolved(from: .loaded([first, second]))

        #expect(availability == .available(first))
    }

    // MARK: - An empty product list is a settled state, not a spinner

    @Test("An empty product list settles as unavailable")
    func anEmptyProductListSettlesAsUnavailable() {
        let availability = TipAvailability.resolved(from: .loaded([]))

        #expect(availability == .unavailable(.emptyCatalog))
        #expect(availability != .loading)
        #expect(availability != .unknown)
        #expect(availability.product == nil)
        #expect(availability.isSettled, "an empty catalog left the surface waiting forever")
    }

    // MARK: - A failure is not an empty catalog

    @Test("A failed load is unavailable for a typed reason, not for emptiness")
    func aFailedLoadIsUnavailableForATypedReasonNotForEmptiness() {
        let availability = TipAvailability.resolved(from: .failed(reason: "transport"))

        #expect(availability == .unavailable(.loadFailed("transport")))
        #expect(
            availability != .unavailable(.emptyCatalog),
            "a failure was reported as a build that cannot transact"
        )
        #expect(availability.isSettled)
        #expect(availability.product == nil)
    }

    /// The discriminant, not the text. A consumer must be able to tell the two
    /// apart without reading the reason string — otherwise "this build cannot
    /// transact" and "something went wrong" become the same answer to a user.
    @Test("Empty and failed are distinguishable without reading the reason text")
    func emptyAndFailedAreDistinguishableWithoutReadingTheReasonText() {
        let empty = TipAvailability.resolved(from: .loaded([]))
        let failed = TipAvailability.resolved(from: .failed(reason: "transport"))

        #expect(empty.unavailableReason == .emptyCatalog)
        #expect(failed.unavailableReason == .loadFailed("transport"))
        #expect(empty.unavailableReason != failed.unavailableReason)
    }

    /// Two different failures stay two different failures, so a diagnostic is
    /// worth reading.
    @Test("A second failure reason survives resolution")
    func aSecondFailureReasonSurvivesResolution() {
        let availability = TipAvailability.resolved(from: .failed(reason: "storefrontUnavailable"))

        #expect(availability == .unavailable(.loadFailed("storefrontUnavailable")))
        #expect(availability != .unavailable(.loadFailed("transport")))
    }

    // MARK: - Loading is observable while it is in progress

    @Test("Neither the unloaded nor the loading state counts as settled")
    func neitherTheUnloadedNorTheLoadingStateCountsAsSettled() {
        #expect(TipAvailability.unknown.isSettled == false)
        #expect(TipAvailability.loading.isSettled == false)
        #expect(TipAvailability.unknown != .loading, "not-yet-asked was collapsed into asking")
    }

    @MainActor
    @Test("Loading is published while the seam holds its answer, then settles exactly once")
    func loadingIsPublishedWhileTheSeamHoldsItsAnswerThenSettlesExactlyOnce() async {
        let product = TipFixtures.product()
        let catalog = FakeTipCatalog(.loaded([product]), heldOpen: true)
        let log = TipStateLog()
        let loader = TipCatalogLoader(catalog: catalog)

        let running = Task { @MainActor in
            await loader.load { log.record($0) }
        }

        await TestPoll.until(catalog.isWaiting)
        #expect(log.states == [.loading], "the in-progress state was never published")

        catalog.release()
        await running.value

        #expect(log.states == [.loading, .available(product)])
        #expect(catalog.callCount == 1, "the catalog was asked more than once for one load")
    }

    /// The other side of the same cycle: an empty catalog settles once too, so
    /// the sequence above is not a description of the loaded path alone.
    @MainActor
    @Test("An empty catalog also publishes loading and then settles once")
    func anEmptyCatalogAlsoPublishesLoadingAndThenSettlesOnce() async {
        let catalog = FakeTipCatalog(.loaded([]))
        let log = TipStateLog()

        await TipCatalogLoader(catalog: catalog).load { log.record($0) }

        #expect(log.states == [.loading, .unavailable(.emptyCatalog)])
        #expect(log.states.filter(\.isSettled).count == 1, "the load settled more than once")
    }
}
