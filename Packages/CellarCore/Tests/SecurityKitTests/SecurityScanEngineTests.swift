import Catalog
import CellarTestSupport
import Foundation
import SecurityKit
import Testing

/// The scan engine's lifecycle guarantees.
///
/// These are `CatalogSyncEngine`'s shipped guarantees, restated for a different
/// payload rather than reinvented: overlapping work coalesces onto the one run
/// in flight, a cancelled run is drained before a successor starts, and the
/// event stream has one observer. All three were paid for once already; the cost
/// of not restating them is paying again.
@Suite("Security scan engine")
struct SecurityScanEngineTests {
    static let epoch = Date(timeIntervalSince1970: 1_780_000_000)

    static let query = AdvisoryQuery(
        packageID: PackageID(kind: .formula, name: "bat"),
        installedVersion: "0.15.0",
        queryVersion: "0.15.0",
        ecosystem: "crates.io",
        ecosystemPackageName: "bat"
    )

    static func engine(
        source: RecordingAdvisorySource,
        clock: TestClock = TestClock(),
        cache: InMemoryAdvisoryCache = InMemoryAdvisoryCache(),
        consent: any ScanConsentProviding = FixedScanConsent(.granted(at: epoch))
    ) -> SecurityScanEngine {
        SecurityScanEngine(
            discovery: source,
            enrichment: source,
            cache: cache,
            consent: consent,
            queries: { [query] },
            clock: clock,
            timeSource: MutableTimeSource(epoch)
        )
    }

    /// The engine the two enrichment tests share, wired to a real PyPI query so
    /// the advisory the fixture names actually matches.
    static func protobufEngine(source: RecordingAdvisorySource) -> SecurityScanEngine {
        SecurityScanEngine(
            discovery: source,
            enrichment: source,
            cache: InMemoryAdvisoryCache(),
            consent: FixedScanConsent(.granted(at: epoch)),
            queries: {
                [
                    AdvisoryQuery(
                        packageID: PackageID(kind: .formula, name: "protobuf"),
                        installedVersion: "3.20.1",
                        queryVersion: "3.20.1",
                        ecosystem: "PyPI",
                        ecosystemPackageName: "protobuf"
                    )
                ]
            },
            clock: TestClock(),
            timeSource: MutableTimeSource(epoch)
        )
    }

    /// One discovery answer carrying one advisory, aligned with the one query
    /// `protobufEngine` asks.
    static func discovered(_ advisory: OSVAdvisory) -> AdvisoryDiscovery {
        AdvisoryDiscovery(
            answers: [
                DiscoveredAnswer(answer: .answered([advisory]), newestModified: advisory.modified)
            ],
            skippedRecordCount: 0
        )
    }

    // MARK: - Single flight

    /// Two callers, one run. The second joins rather than starting a second set
    /// of requests against the same two hosts.
    @Test("Overlapping scans coalesce onto the one in flight, keyed by its token")
    func overlappingScansCoalesceOntoTheOneInFlightKeyedByToken() async throws {
        let clock = TestClock()
        let source = RecordingAdvisorySource(clock: clock, discoveryDelay: .seconds(1))
        let engine = Self.engine(source: source, clock: clock)

        let first = Task { await engine.scan() }
        await clock.waitForSleepers()

        let second = Task { await engine.scan() }
        // Let the joiner reach the actor and find the slot occupied.
        await Task.yield()

        await clock.advance(by: .seconds(1))
        let firstOutcome = await first.value
        let secondOutcome = await second.value

        #expect(source.discoverCallCount == 1, "the second caller started its own scan")
        #expect(firstOutcome == secondOutcome, "the joiner got a different answer")

        // The slot is vacated by the run that owned it, so a later scan is a
        // genuinely new one rather than a permanent join to a settled result.
        await clock.advance(by: .seconds(1))
        let third = Task { await engine.scan() }
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(1))
        _ = await third.value
        #expect(source.discoverCallCount == 2, "a later scan joined a settled run")
    }

    /// A cancelled run is not joinable and is not abandoned either: the
    /// successor waits for it to unwind, then starts clean.
    @Test("Cancellation drains then restarts rather than leaving a half scan")
    func cancellationDrainsThenRestartsRatherThanLeavingAHalfScan() async throws {
        let clock = TestClock()
        let source = RecordingAdvisorySource(clock: clock, discoveryDelay: .seconds(1))
        let cache = InMemoryAdvisoryCache()
        let engine = Self.engine(source: source, clock: clock, cache: cache)

        let cancelled = Task { await engine.scan() }
        await clock.waitForSleepers()
        await engine.cancel()

        let successor = Task { await engine.scan() }
        // Release the cancelled run so it can unwind, then the successor's own
        // discovery.
        await clock.advance(by: .seconds(1))
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(1))

        #expect(await cancelled.value == .cancelled, "a cancelled run reported a result")
        let outcome = await successor.value
        guard case .completed = outcome else {
            Issue.record("the successor did not complete: \(outcome)")
            return
        }
        #expect(source.discoverCallCount == 2, "the successor joined the cancelled run")

        // A cancelled run publishes nothing, so nothing half-finished reached
        // the cache before the successor's result did.
        let stored = try #require(cache.stored)
        #expect(stored.revisionOrdinal == 1)
    }

    // MARK: - The event stream

    @Test("The event stream delivers status then settlement, in order, to its one observer")
    func theEventStreamSupportsExactlyOneObserver() async throws {
        let source = RecordingAdvisorySource()
        let engine = Self.engine(source: source)

        let observer = Task { () -> [SecurityScanEvent] in
            var seen: [SecurityScanEvent] = []
            for await event in engine.events {
                seen.append(event)
                if case .settled = event { break }
            }
            return seen
        }

        _ = await engine.scan()
        let seen = await observer.value

        #expect(seen.first == .status(.discovering))
        #expect(seen.contains(.status(.enriching)) == false, "nothing was found, yet NVD was asked")
        guard case .settled(let result) = try #require(seen.last) else {
            Issue.record("the stream never settled: \(seen)")
            return
        }
        #expect(result.revision == SecurityScanRevision(ordinal: 1))
        #expect(result.entries.count == 1)
    }

    /// Enrichment runs only when discovery found something to enrich, so a clean
    /// inventory costs one request rather than two.
    @Test("Enrichment is skipped entirely when discovery found no identifiers")
    func enrichmentIsSkippedWhenDiscoveryFoundNoIdentifiers() async throws {
        let source = RecordingAdvisorySource()
        let engine = Self.engine(source: source)

        _ = await engine.scan()

        #expect(source.discoverCallCount == 1)
        #expect(source.enrichCallCount == 0, "a clean inventory still asked NVD")
    }

    /// The control for the test above, and the enrichment path end to end: a
    /// real advisory with a CVE alias is discovered, its identifier is what
    /// enrichment is asked about, and the returned tier reaches the finding.
    @Test("A discovered advisory is enriched by its CVE identifier and the tier reaches the finding")
    func aDiscoveredAdvisoryIsEnrichedByItsIdentifier() async throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-PYSEC-2026-899.json")
        )
        let cveID = try #require(advisory.cveID)

        let source = RecordingAdvisorySource()
        source.answerDiscovery(with: .success(Self.discovered(advisory)))
        source.answerEnrichment(
            with: .success(
                AdvisoryEnrichment(severities: [cveID: .critical], skippedRecordCount: 0)
            )
        )

        let outcome = await Self.protobufEngine(source: source).scan()

        #expect(source.enrichCallCount == 1)
        #expect(source.lastIdentifiers == [cveID], "enrichment asked about \(source.lastIdentifiers)")

        guard case .completed(let result) = outcome,
              case .covered(.findings(let findings)) = try #require(result.entries.first).outcome
        else {
            Issue.record("the discovered advisory did not become a finding: \(outcome)")
            return
        }
        #expect(findings.first?.severity == .critical)
        #expect(result.entries.first?.advisoryModified == advisory.modified)
        #expect(result.provenance.enrichmentAttempted)
        #expect(result.provenance.enrichmentSucceeded)
    }

    /// A failed enrichment is recorded, not fatal. Discovery's answers stand and
    /// the findings simply arrive unrated.
    @Test("A failed enrichment leaves the scan complete, unrated, and honest about it")
    func aFailedEnrichmentLeavesTheScanCompleteAndHonest() async throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-PYSEC-2026-899.json")
        )

        let source = RecordingAdvisorySource()
        source.answerDiscovery(with: .success(Self.discovered(advisory)))
        source.answerEnrichment(with: .failure(.rateLimited))

        let outcome = await Self.protobufEngine(source: source).scan()

        guard case .completed(let result) = outcome else {
            Issue.record("a rate-limited enrichment failed the whole scan: \(outcome)")
            return
        }
        guard case .covered(.findings(let findings)) = try #require(result.entries.first).outcome
        else {
            Issue.record("the finding was lost when enrichment failed")
            return
        }
        #expect(findings.allSatisfy { $0.severity == .unrated })
        #expect(result.provenance.enrichmentAttempted)
        #expect(result.provenance.enrichmentSucceeded == false)
        #expect(result.isPartial, "a scan missing its severities reported itself complete")
    }

    // MARK: - The revision ordinal

    /// A live scan mints `persisted + 1` and persists it, so the ordinal keeps
    /// climbing across relaunches rather than restarting.
    @Test("A live scan mints the next ordinal from the persisted one and saves it")
    func aLiveScanMintsTheNextOrdinalFromThePersistedOne() async throws {
        let source = RecordingAdvisorySource()
        let cache = InMemoryAdvisoryCache(
            AdvisoryCacheFile.arranged(revisionOrdinal: 12, entries: [])
        )
        let engine = Self.engine(source: source, cache: cache)

        let outcome = await engine.scan()

        guard case .completed(let result) = outcome else {
            Issue.record("the scan did not complete: \(outcome)")
            return
        }
        #expect(result.revision == SecurityScanRevision(ordinal: 13))
        #expect(cache.stored?.revisionOrdinal == 13)
    }
}
