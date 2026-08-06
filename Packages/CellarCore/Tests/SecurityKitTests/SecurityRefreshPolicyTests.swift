import CellarTestSupport
import Catalog
import Foundation
import SecurityKit
import Testing

/// The refresh schedule, and the deliberate split at the heart of it.
///
/// `staleAfter` is a **wall-clock** interval compared against the cache's
/// `fetchedAt`. `pollGranularity` is a **monotonic** sleep. They are separate
/// numbers because a single twenty-four hour sleep does not advance while the
/// machine is asleep, so a laptop closed overnight would wake with a two-day-old
/// scan and nothing pending — `CatalogSyncEngine.swift:149`, learned once
/// already.
@Suite("Security refresh policy")
struct SecurityRefreshPolicyTests {
    static let epoch = Date(timeIntervalSince1970: 1_780_000_000)

    static let sampleQuery = AdvisoryQuery(
        packageID: PackageID(kind: .formula, name: "bat"),
        installedVersion: "0.15.0",
        queryVersion: "0.15.0",
        ecosystem: "crates.io",
        ecosystemPackageName: "bat"
    )

    /// A cache whose newest entry was fetched at `fetchedAt` — which is exactly
    /// what staleness is measured against, so seeding it is how a test says
    /// "a scan happened then".
    static func cache(scannedAt fetchedAt: Date) -> InMemoryAdvisoryCache {
        InMemoryAdvisoryCache(
            AdvisoryCacheFile.arranged(
                revisionOrdinal: 1,
                entries: [
                    AdvisoryCacheEntry(
                        key: AdvisoryCacheKey(
                            sourceID: .osv,
                            packageID: sampleQuery.packageID,
                            version: sampleQuery.installedVersion
                        ),
                        outcome: .covered(
                            .clean(CleanCoverage(answeredBy: .osv, queriedVersion: "0.15.0"))
                        ),
                        fetchedAt: fetchedAt,
                        advisoryModified: nil,
                        mappingRevision: EcosystemMapping.revision,
                        matcherVersion: CVEMatcher.version
                    )
                ]
            )
        )
    }

    static func engine(
        source: RecordingAdvisorySource,
        clock: TestClock,
        timeSource: MutableTimeSource,
        cache: InMemoryAdvisoryCache = InMemoryAdvisoryCache(),
        policy: SecurityRefreshPolicy = SecurityRefreshPolicy()
    ) -> SecurityScanEngine {
        SecurityScanEngine(
            discovery: source,
            enrichment: source,
            cache: cache,
            consent: FixedScanConsent(.granted(at: epoch)),
            queries: { [sampleQuery] },
            clock: clock,
            timeSource: timeSource,
            policy: policy
        )
    }

    // MARK: - The numbers

    @Test("The policy's defaults are a day of staleness and a quarter hour of polling")
    func thePolicyDefaultsAreADayAndAQuarterHour() {
        let policy = SecurityRefreshPolicy()

        #expect(policy.staleAfter == 24 * 60 * 60)
        #expect(policy.pollGranularity == .seconds(15 * 60))
        #expect(policy.maximumAttempts == 3)
        #expect(policy.payloadByteLimit == 8 * 1_048_576)
        // The TTL and the staleness window are the same number on purpose: a
        // shorter TTL makes every scheduled scan a full re-query, a longer one
        // lets a scheduled scan read its own cache and never refresh.
        #expect(policy.staleAfter == AdvisoryCacheEntry.timeToLive)
    }

    // MARK: - Staleness is wall clock

    /// The overnight case, which is the whole reason the two numbers are apart.
    ///
    /// The `TestClock` advances by **one poll granularity** — fifteen monotonic
    /// minutes, all the sleep a closed laptop would have accrued — while the
    /// wall clock moves thirty hours. A single twenty-four hour monotonic sleep
    /// would still be sleeping here; the loop wakes, re-reads the wall clock, and
    /// finds a pending re-scan.
    @Test("Staleness is wall clock against fetchedAt while the loop sleeps on poll granularity")
    func stalenessIsWallClockAgainstFetchedAtWhileTheLoopSleepsOnPollGranularity() async throws {
        let source = RecordingAdvisorySource()
        let clock = TestClock()
        let timeSource = MutableTimeSource(Self.epoch)
        let engine = Self.engine(
            source: source,
            clock: clock,
            timeSource: timeSource,
            cache: Self.cache(scannedAt: Self.epoch)
        )

        let loop = Task { await engine.runRefreshLoop() }
        // Cancelled but never awaited: `TestClock.sleep` resumes only when the
        // clock advances, so awaiting a loop suspended in it would hang. The
        // `SchedulerTests` precedent.
        defer { loop.cancel() }
        await clock.waitForSleepers()
        #expect(source.discoverCallCount == 0, "a fresh cache triggered a scan")

        // The lid closes. Wall time moves thirty hours; monotonic time moves the
        // fifteen minutes a sleeping machine actually accrues.
        timeSource.advance(by: 30 * 3_600)
        await clock.advance(by: .seconds(15 * 60))
        await clock.waitForSleepers()

        #expect(source.discoverCallCount == 1, "the loop woke and found nothing pending")
    }

    @Test("Scan-if-stale does nothing while the cache is fresh")
    func scanIfStaleDoesNothingWhenTheCacheIsFresh() async throws {
        let source = RecordingAdvisorySource()
        let timeSource = MutableTimeSource(Self.epoch)
        let engine = Self.engine(
            source: source,
            clock: TestClock(),
            timeSource: timeSource,
            cache: Self.cache(scannedAt: Self.epoch)
        )

        #expect(await engine.scanIfStale() == nil)
        #expect(source.discoverCallCount == 0)

        // One second inside the window: still nothing.
        timeSource.advance(by: 24 * 3_600 - 1)
        #expect(await engine.scanIfStale() == nil)
        #expect(source.discoverCallCount == 0)

        // The control: past the window, it scans. Without this the two `nil`s
        // above would be satisfied by a method that never scans at all.
        timeSource.advance(by: 2)
        #expect(await engine.scanIfStale() != nil)
        #expect(source.discoverCallCount == 1)
    }

    /// Never scanned is stale. Otherwise the very first launch after consent
    /// would wait a day before asking anything.
    @Test("A machine that has never scanned is stale")
    func aMachineThatHasNeverScannedIsStale() {
        let policy = SecurityRefreshPolicy()

        #expect(policy.isStale(lastFetchedAt: nil, now: Self.epoch))
        #expect(policy.isStale(lastFetchedAt: Self.epoch, now: Self.epoch) == false)
        #expect(
            policy.isStale(
                lastFetchedAt: Self.epoch,
                now: Self.epoch.addingTimeInterval(24 * 3_600)
            ) == false
        )
        #expect(
            policy.isStale(
                lastFetchedAt: Self.epoch,
                now: Self.epoch.addingTimeInterval(24 * 3_600 + 1)
            )
        )
        // A clock that moved backwards makes the last scan look like it is in
        // the future. That is not freshness — it is an unusable age.
        #expect(
            policy.isStale(
                lastFetchedAt: Self.epoch.addingTimeInterval(3_600),
                now: Self.epoch
            )
        )
    }

    // MARK: - Retry

    @Test("Maximum attempts and backoff are honoured on repeated transport failure")
    func maximumAttemptsAndBackoffAreHonouredOnRepeatedTransportFailure() async throws {
        let policy = SecurityRefreshPolicy(maximumAttempts: 3, backoff: .milliseconds(500))

        // Exponential from the second attempt, and no delay before the first.
        #expect(policy.backoff(beforeAttempt: 1) == .zero)
        #expect(policy.backoff(beforeAttempt: 2) == .milliseconds(500))
        #expect(policy.backoff(beforeAttempt: 3) == .seconds(1))

        let source = RecordingAdvisorySource()
        source.answerDiscovery(with: .failure(.transportFailed))
        let clock = TestClock()
        let engine = Self.engine(
            source: source,
            clock: clock,
            timeSource: MutableTimeSource(Self.epoch),
            policy: policy
        )

        let scan = Task { await engine.scan() }

        // Two backoff sleeps for three attempts.
        for _ in 1...2 {
            await clock.waitForSleepers()
            await clock.advance(by: .seconds(1))
        }

        let outcome = await scan.value
        #expect(source.discoverCallCount == 3, "the scan made \(source.discoverCallCount) attempts")
        guard case .failed(let error) = outcome else {
            Issue.record("three transport failures still produced a result")
            return
        }
        #expect(error == .transportFailed)
    }

    /// A failure that will not improve by being repeated is not repeated.
    ///
    /// Retrying a rate limit immediately is the one thing guaranteed to make a
    /// rate limit worse, and re-sending a payload that was too large sends the
    /// same payload again.
    @Test("A rate limit and an oversized payload are not retried")
    func aRateLimitAndAnOversizedPayloadAreNotRetried() async throws {
        for error in [AdvisoryError.rateLimited, .payloadTooLarge, .malformedPayload] {
            let source = RecordingAdvisorySource()
            source.answerDiscovery(with: .failure(error))
            let engine = Self.engine(
                source: source,
                clock: TestClock(),
                timeSource: MutableTimeSource(Self.epoch)
            )

            _ = await engine.scan()

            #expect(source.discoverCallCount == 1, "\(error) was retried")
        }
    }
}
