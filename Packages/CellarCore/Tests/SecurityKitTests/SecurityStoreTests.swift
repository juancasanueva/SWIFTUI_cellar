import Catalog
import CellarTestSupport
import Foundation
import Testing

@testable import SecurityKit

/// The two guards `SecurityStore` adopts behind, and why they are two.
///
/// - a **generation** kills a superseded *task* — the answer to a question
///   nobody is asking any more;
/// - an **ordinal** kills a late-arriving older *snapshot* — an answer to the
///   right question that arrived after a better one.
///
/// Asserting them together would let either mask the other: a stale task whose
/// result also carries a stale ordinal is refused twice over and proves nothing
/// about which guard did the refusing. So the generation tests hold the ordinal
/// **fixed** at a value that would otherwise install, and the ordinal tests use
/// the live generation.
@Suite("Security store guards", .timeLimit(.minutes(1)))
@MainActor
struct SecurityStoreTests {
    typealias Arrange = SecurityStoreArrangement

    // MARK: - The generation guard (11.1)

    /// A task whose generation has been rotated cannot install its result, even
    /// though that result would install perfectly well from the live generation.
    ///
    /// The ordinal is held **fixed** across this test and its control, and the
    /// projection never runs for the refused adoption — so the ordinal guard is
    /// demonstrably not the thing doing the refusing.
    @Test("A superseded task is killed by its generation")
    func aSupersededTaskIsKilledByItsGeneration() async throws {
        let clock = TestClock()
        let source = RecordingAdvisorySource(clock: clock, discoveryDelay: .seconds(60))
        let store = Arrange.heldOpenStore(clock: clock, source: source)

        let superseded = store.startScan()
        await clock.waitForSleepers()
        store.cancelScan()

        await store.adopt(
            .completed(Arrange.result(ordinal: 7, entries: [Arrange.vulnerableEntry])),
            scope: .cveScan,
            generation: superseded
        )

        #expect(store.state(for: .cveScan).result == nil, "a superseded task installed its result")
        #expect(
            store.projectionCount == 0,
            "the refused adoption still cost a projection, so it reached the ordinal guard"
        )
        #expect(store.coverage(for: .cveScan).vulnerable == 0)
    }

    /// The control, differing from the test above in the generation and in
    /// nothing else: same store shape, same ordinal, same result.
    @Test("The live generation installs the very result the superseded one could not")
    func theLiveGenerationInstallsTheSameResult() async throws {
        let clock = TestClock()
        let source = RecordingAdvisorySource(clock: clock, discoveryDelay: .seconds(60))
        let store = Arrange.heldOpenStore(clock: clock, source: source)

        let live = store.startScan()
        await clock.waitForSleepers()

        await store.adopt(
            .completed(Arrange.result(ordinal: 7, entries: [Arrange.vulnerableEntry])),
            scope: .cveScan,
            generation: live
        )

        #expect(store.state(for: .cveScan).result?.revision == SecurityScanRevision(ordinal: 7))
        #expect(store.projectionCount == 1)
        #expect(store.coverage(for: .cveScan).vulnerable == 1)

        store.cancelScan()
    }

    /// Arrival order is not authority. An older snapshot landing after a newer
    /// one has installed is discarded rather than written on top of it.
    @Test("A late-arriving older snapshot is rejected by its ordinal")
    func aLateArrivingOlderSnapshotIsRejectedByItsOrdinal() async throws {
        let store = SecurityStore(engine: Arrange.engine(source: RecordingAdvisorySource()))

        await store.adopt(Arrange.result(ordinal: 7, entries: [Arrange.vulnerableEntry]), scope: .cveScan)
        await store.adopt(Arrange.result(ordinal: 3, entries: [Arrange.cleanEntry]), scope: .cveScan)

        #expect(store.state(for: .cveScan).result?.revision == SecurityScanRevision(ordinal: 7))
        #expect(store.coverage(for: .cveScan).vulnerable == 1, "the older snapshot installed")
        #expect(store.coverage(for: .cveScan).clean == 0)
        #expect(store.adoptionRequestCount == 2)
        #expect(store.projectionCount == 1, "the discarded snapshot still cost a projection")
    }

    // MARK: - Duplicate and older ordinals (11.2)

    /// One materialization reaches the store through more than one ingress — the
    /// settled event and a manual refresh both carry it. Whichever arrives second
    /// must come back with the result queryable rather than returning early with
    /// nothing, and it must not cost a second projection.
    @Test("A duplicate ordinal joins the in-flight adoption rather than returning")
    func aDuplicateOrdinalJoinsTheInFlightAdoptionRatherThanReturning() async throws {
        let store = SecurityStore(engine: Arrange.engine(source: RecordingAdvisorySource()))
        let snapshot = Arrange.result(ordinal: 4, entries: [Arrange.vulnerableEntry, Arrange.cleanEntry])

        let first = Task { await store.adopt(snapshot, scope: .cveScan) }
        // Let the first claim the revision and suspend on its projection, so the
        // second genuinely arrives *during* the adoption rather than after it.
        await Task.yield()

        // Read at the instant the duplicate's own call returns — not at the end
        // of the test, by which time the first adoption has finished regardless
        // and the two behaviours are indistinguishable. This is the whole
        // difference between joining and returning early: what the second caller
        // can see the moment it is handed control back.
        let observedByTheDuplicate = Task { @MainActor () -> CoverageTotals in
            await store.adopt(snapshot, scope: .cveScan)
            return store.coverage(for: .cveScan)
        }
        let observed = await observedByTheDuplicate.value
        await first.value

        #expect(observed.vulnerable == 1, "the duplicate returned before the snapshot was queryable")
        #expect(observed.clean == 1)
        #expect(store.adoptionRequestCount == 2, "one of the two ingresses never reached the store")
        #expect(store.projectionCount == 1, "one materialization cost two projections")
        #expect(store.coverage(for: .cveScan).vulnerable == 1)
        #expect(store.state(for: .cveScan).result?.revision == SecurityScanRevision(ordinal: 4))

        // A re-delivery after the adoption has settled takes the same door and
        // is equally free.
        await store.adopt(snapshot, scope: .cveScan)
        #expect(store.projectionCount == 1)
        #expect(store.coverage(for: .cveScan).total == 2)
    }

    /// The older ordinal leaves through the same door as the duplicate, and the
    /// adopted-revision record does not regress on its way out — otherwise the
    /// discarded snapshot would disarm the newer one's deduplication.
    @Test("An older ordinal returns without blanking anything")
    func anOlderOrdinalReturnsWithoutBlanking() async throws {
        let store = SecurityStore(engine: Arrange.engine(source: RecordingAdvisorySource()))
        let newer = Arrange.result(ordinal: 9, entries: [Arrange.vulnerableEntry])
        let older = Arrange.result(ordinal: 2, entries: [Arrange.cleanEntry])

        await store.adopt(newer, scope: .cveScan)
        await store.adopt(older, scope: .cveScan)
        await store.adopt(newer, scope: .cveScan)

        #expect(store.adoptionRequestCount == 3)
        #expect(store.projectionCount == 1, "the discarded snapshot disarmed the newer one's dedup")
        #expect(store.state(for: .cveScan).result?.revision == SecurityScanRevision(ordinal: 9))
        #expect(store.coverage(for: .cveScan).vulnerable == 1)
    }
}
