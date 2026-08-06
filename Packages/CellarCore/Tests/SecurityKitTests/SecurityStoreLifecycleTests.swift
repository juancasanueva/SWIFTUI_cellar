import Catalog
import CellarTestSupport
import Foundation
import Testing

@testable import SecurityKit

/// What `SecurityStore` shows when a scan degrades, what it reads back from the
/// cache, and how a settled engine event reaches it.
///
/// Split from `SecurityStoreTests` so neither file outgrows the project's
/// limits; both arrange through `SecurityStoreArrangement`, so they are talking
/// about the same store.
///
/// `.timeLimit` because one test polls against a condition another task must
/// satisfy: a regression that stops satisfying it should fail the run, not hang
/// it. `TimeLimitTrait` only accepts whole minutes.
@Suite("Security store lifecycle", .timeLimit(.minutes(1)))
@MainActor
struct SecurityStoreLifecycleTests {
    typealias Arrange = SecurityStoreArrangement

    // MARK: - Degradation (11.3)

    /// A failed scan reports the failure and keeps the last good result resident.
    /// A transient failure must not empty the user's findings.
    @Test("The last good result survives a failed scan")
    func lastGoodSurvivesAFailedScan() async throws {
        let clock = TestClock()
        let source = RecordingAdvisorySource(clock: clock)
        // Not retryable, so the failure is the answer rather than the first of
        // several attempts on a clock nobody is advancing.
        source.answerDiscovery(with: .failure(.malformedPayload))
        let store = SecurityStore(engine: Arrange.engine(source: source, clock: clock))

        await store.adopt(Arrange.result(ordinal: 5, entries: [Arrange.vulnerableEntry]), scope: .cveScan)
        #expect(store.state(for: .cveScan).result?.revision == SecurityScanRevision(ordinal: 5))

        await store.scanNow()

        #expect(store.state(for: .cveScan).failure == .malformedPayload)
        let stale = try #require(store.state(for: .cveScan).staleResult)
        #expect(stale.revision == SecurityScanRevision(ordinal: 5))
        #expect(stale.entries == [Arrange.vulnerableEntry], "the last good findings were dropped")
        #expect(store.coverage(for: .cveScan).vulnerable == 1, "a failed scan blanked the coverage")
    }

    /// "We could not get severities" is a different claim from "these findings
    /// are unrated", and the store must not launder the first into the second.
    @Test("A partial scan is adopted as partial and never as complete")
    func aPartialScanIsAdoptedAsPartialAndNeverAsComplete() async throws {
        let store = SecurityStore(engine: Arrange.engine(source: RecordingAdvisorySource()))

        await store.adopt(
            Arrange.result(ordinal: 1, entries: [Arrange.vulnerableEntry], isPartial: true),
            scope: .cveScan
        )

        guard case .partial(let adopted) = store.state(for: .cveScan) else {
            Issue.record("a partial scan was adopted as \(store.state(for: .cveScan))")
            return
        }
        #expect(adopted.isPartial)
        #expect(store.state(for: .cveScan).result?.entries == [Arrange.vulnerableEntry])
        #expect(adopted.provenance.enrichmentAttempted)
        #expect(adopted.provenance.enrichmentSucceeded == false)
    }

    /// The control: the same entries, the same store, complete this time.
    @Test("A complete scan is adopted as content")
    func aCompleteScanIsAdoptedAsContent() async throws {
        let store = SecurityStore(engine: Arrange.engine(source: RecordingAdvisorySource()))

        await store.adopt(
            Arrange.result(ordinal: 1, entries: [Arrange.vulnerableEntry], isPartial: false),
            scope: .cveScan
        )

        guard case .content = store.state(for: .cveScan) else {
            Issue.record("a complete scan was adopted as \(store.state(for: .cveScan))")
            return
        }
    }

    /// The whole path, through the engine: a refused enrichment produces a
    /// partial result and the store shows it as partial.
    @Test("A refused enrichment reaches the store as partial rather than as content")
    func aRefusedEnrichmentReachesTheStoreAsPartial() async throws {
        let advisory = try OSVWire.advisory(from: Fixture.data("OSV/vulns-PYSEC-2026-899.json"))
        let source = RecordingAdvisorySource()
        source.answerDiscovery(
            with: .success(
                AdvisoryDiscovery(
                    answers: [
                        DiscoveredAnswer(
                            answer: .answered([advisory]),
                            newestModified: advisory.modified
                        )
                    ],
                    skippedRecordCount: 0
                )
            )
        )
        source.answerEnrichment(with: .failure(.rateLimited))
        let store = SecurityStore(engine: Arrange.engine(source: source))

        await store.scanNow()

        guard case .partial(let adopted) = store.state(for: .cveScan) else {
            Issue.record("a refused enrichment was adopted as \(store.state(for: .cveScan))")
            return
        }
        #expect(adopted.provenance.enrichmentSucceeded == false)
    }

    // MARK: - The cache load (11.4)

    /// The persisted scan is read and adopted before anything is transmitted,
    /// and it is adopted **at its own ordinal** rather than at zero — so the
    /// ordinal keeps climbing across a relaunch instead of restarting and
    /// letting a stale snapshot win.
    @Test("Load cache runs before any network work and adopts at the persisted ordinal")
    func loadCacheRunsBeforeAnyNetworkWorkAndAdoptsAtThePersistedOrdinal() async throws {
        let source = RecordingAdvisorySource()
        let cache = InMemoryAdvisoryCache(
            AdvisoryCacheFile(
                revisionOrdinal: 12,
                entries: [Arrange.vulnerableEntry, Arrange.cleanEntry],
                provenance: Arrange.provenance(),
                isPartial: false
            )
        )
        let store = SecurityStore(engine: Arrange.engine(source: source, cache: cache))

        await store.loadCache()

        #expect(source.discoverCallCount == 0, "the cache load transmitted something")
        #expect(source.enrichCallCount == 0, "the cache load transmitted something")
        #expect(store.isReady, "the store never became ready over a usable cache")
        #expect(store.state(for: .cveScan).result?.revision == SecurityScanRevision(ordinal: 12))
        #expect(store.coverage(for: .cveScan).vulnerable == 1)
        #expect(store.coverage(for: .cveScan).clean == 1)

        // Everything the cache published is cached, with its age, and never live.
        let entries = try #require(store.state(for: .cveScan).result?.entries)
        #expect(entries.allSatisfy { $0.freshness == .cached(fetchedAt: Arrange.epoch) })

        // And the ordinal the load adopted at is the floor the next live scan
        // has to clear: a snapshot minted before the relaunch cannot install.
        await store.adopt(Arrange.result(ordinal: 11, entries: []), scope: .cveScan)
        #expect(store.state(for: .cveScan).result?.revision == SecurityScanRevision(ordinal: 12))
        #expect(store.coverage(for: .cveScan).total == 2)
    }

    /// A cold launch over an empty cache is ready and empty, not stuck.
    @Test("Load cache over an absent file leaves the store ready and empty")
    func loadCacheOverAnAbsentFileLeavesTheStoreReadyAndEmpty() async throws {
        let source = RecordingAdvisorySource()
        let store = SecurityStore(engine: Arrange.engine(source: source))

        await store.loadCache()

        #expect(store.isReady)
        #expect(store.state(for: .cveScan).result == nil)
        #expect(store.coverage(for: .cveScan).total == 0)
        #expect(source.discoverCallCount == 0)
    }

    /// The cached result carries the provenance and the partiality of the scan
    /// that produced it, read from the file rather than invented at load time.
    ///
    /// Without this, an offline reader is told a scan whose enrichment was
    /// refused was complete — which is exactly the fabrication the whole change
    /// exists to prevent. The cache is the only place that fact can come from.
    @Test("A cached load carries the scan's own provenance and partiality")
    func aCachedLoadCarriesTheScansOwnProvenanceAndPartiality() async throws {
        let cache = InMemoryAdvisoryCache(
            AdvisoryCacheFile(
                revisionOrdinal: 3,
                entries: [Arrange.vulnerableEntry],
                provenance: Arrange.provenance(enrichmentSucceeded: false),
                isPartial: true
            )
        )
        let store = SecurityStore(engine: Arrange.engine(source: RecordingAdvisorySource(), cache: cache))

        await store.loadCache()

        guard case .partial(let adopted) = store.state(for: .cveScan) else {
            Issue.record("a partial scan came back from the cache as \(store.state(for: .cveScan))")
            return
        }
        #expect(adopted.provenance.enrichmentAttempted)
        #expect(adopted.provenance.enrichmentSucceeded == false)
        #expect(adopted.provenance.scannedAt == Arrange.epoch)
        #expect(adopted.provenance.matcherVersion == CVEMatcher.version)
    }

    /// The round trip that makes the test above more than a statement about a
    /// hand-built file: a real scan's provenance survives the disk.
    @Test("A live scan's provenance and partiality survive the cache round trip")
    func provenanceSurvivesTheCacheRoundTrip() async throws {
        let advisory = try OSVWire.advisory(from: Fixture.data("OSV/vulns-PYSEC-2026-899.json"))
        let source = RecordingAdvisorySource()
        source.answerDiscovery(
            with: .success(
                AdvisoryDiscovery(
                    answers: [
                        DiscoveredAnswer(
                            answer: .answered([advisory]),
                            newestModified: advisory.modified
                        )
                    ],
                    skippedRecordCount: 0
                )
            )
        )
        source.answerEnrichment(with: .failure(.rateLimited))
        let cache = InMemoryAdvisoryCache()
        let scanning = SecurityStore(engine: Arrange.engine(source: source, cache: cache))

        await scanning.scanNow()

        // A second launch over the file the first one wrote.
        let relaunched = SecurityStore(
            engine: Arrange.engine(source: RecordingAdvisorySource(), cache: cache)
        )
        await relaunched.loadCache()

        guard case .partial(let adopted) = relaunched.state(for: .cveScan) else {
            Issue.record("the relaunch read the partial scan as \(relaunched.state(for: .cveScan))")
            return
        }
        #expect(adopted.provenance.enrichmentAttempted)
        #expect(adopted.provenance.enrichmentSucceeded == false)
        #expect(adopted.revision == SecurityScanRevision(ordinal: 1))
    }

    // MARK: - The event stream

    /// The store's ordinary ingress: the engine settles, the event arrives, and
    /// the same guarded adoption installs it.
    @Test("A settled event from the engine is adopted through the same guards")
    func aSettledEventFromTheEngineIsAdoptedThroughTheSameGuards() async throws {
        let clock = TestClock()
        let source = RecordingAdvisorySource(clock: clock)
        let store = SecurityStore(engine: Arrange.engine(source: source, clock: clock))

        // Never awaited: `TestClock.sleep` resumes only on `advance`, so a
        // cancelled refresh loop would otherwise hang the test forever.
        let running = Task { await store.start() }
        defer { running.cancel() }

        await Arrange.poll { store.state(for: .cveScan).result != nil }

        #expect(store.isReady)
        #expect(store.state(for: .cveScan).result?.revision == SecurityScanRevision(ordinal: 1))
        #expect(store.scanStatus == .settled(SecurityScanRevision(ordinal: 1)))
        #expect(source.discoverCallCount == 1)
    }
}
