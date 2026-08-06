import Catalog
import CellarTestSupport
import Foundation
import SecurityKit
import Testing

/// Consent, as a value.
///
/// Everything about this feature that could embarrass a user turns on one
/// question — *did they say yes* — and the whole point of making it a value with
/// one constructor is that "yes" cannot be arrived at by accident. There is no
/// mutable boolean, no default-true, and no way to build a granted consent
/// without a date on it.
@Suite("Scan consent")
struct ScanConsentTests {
    // MARK: - The default

    /// First launch is not consent, and the absence of a stored preference is
    /// not consent either.
    @Test("Consent is absent until it is given")
    func consentIsAbsentUntilItIsGiven() {
        #expect(ScanConsent.notGranted.isGranted == false)
        #expect(ScanConsent.notGranted.grantedAt == nil)
    }

    // MARK: - The gate

    /// The `vulnerability-scanning` requirement: nothing egresses before
    /// consent — and when something tries, it says so.
    ///
    /// A typed refusal rather than silence. "You have not opted in" and "we
    /// tried and could not reach anyone" are different sentences, and a surface
    /// showing the second for the first would be lying about what the app did.
    /// Parking silently is the failure this test exists to prevent: a scan that
    /// simply returns nothing leaves the user staring at an empty security
    /// surface with no idea why.
    @Test("A blocked egress emits blockedPendingConsent rather than parking silently")
    func aBlockedEgressEmitsBlockedPendingConsentRatherThanParkingSilently() {
        #expect(throws: AdvisoryError.blockedPendingConsent) {
            try ScanConsent.notGranted.authorise()
        }

        // The control: a granted consent authorises without throwing, so the
        // refusal above is consent's doing rather than a gate that refuses
        // everyone.
        let granted = ScanConsent.granted(at: Date(timeIntervalSince1970: 1_780_000_000))
        #expect(throws: Never.self) { try granted.authorise() }
        #expect(granted.isGranted)
        #expect(granted.grantedAt == Date(timeIntervalSince1970: 1_780_000_000))
    }

    // MARK: - Reversibility

    /// Off is fully off, and it leaves no residue that could be misread as a
    /// lapsed grant.
    @Test("Revocation clears the grant and its date, and is idempotent")
    func revocationClearsTheGrantAndItsDate() {
        let granted = ScanConsent.granted(at: Date(timeIntervalSince1970: 1_780_000_000))
        let revoked = granted.revoked()

        #expect(revoked.isGranted == false)
        #expect(revoked.grantedAt == nil)
        #expect(revoked == ScanConsent.notGranted)
        #expect(revoked.revoked() == revoked)

        #expect(throws: AdvisoryError.blockedPendingConsent) { try revoked.authorise() }
    }

    /// Consent is stored by the app in its preferences, so it has to survive
    /// that round trip intact — a decode that lost `grantedAt` would leave a
    /// grant nobody can date.
    @Test("Consent survives the preference round trip")
    func consentSurvivesThePreferenceRoundTrip() throws {
        let granted = ScanConsent.granted(at: Date(timeIntervalSince1970: 1_780_000_000))

        let encoded = try JSONEncoder().encode(granted)
        let decoded = try JSONDecoder().decode(ScanConsent.self, from: encoded)

        #expect(decoded == granted)
        #expect(decoded.grantedAt == granted.grantedAt)

        let revoked = try JSONDecoder().decode(
            ScanConsent.self,
            from: try JSONEncoder().encode(ScanConsent.notGranted)
        )
        #expect(revoked.isGranted == false)
    }

    // MARK: - Through the engine

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
        consent: any ScanConsentProviding,
        cache: InMemoryAdvisoryCache = InMemoryAdvisoryCache(),
        clock: TestClock = TestClock(),
        timeSource: MutableTimeSource = MutableTimeSource(epoch)
    ) -> SecurityScanEngine {
        SecurityScanEngine(
            discovery: source,
            enrichment: source,
            cache: cache,
            consent: consent,
            queries: { [query] },
            clock: clock,
            timeSource: timeSource
        )
    }

    static func cache(scannedAt fetchedAt: Date) -> InMemoryAdvisoryCache {
        InMemoryAdvisoryCache(
            AdvisoryCacheFile.arranged(
                revisionOrdinal: 3,
                entries: [
                    AdvisoryCacheEntry(
                        key: AdvisoryCacheKey(
                            sourceID: .osv,
                            packageID: query.packageID,
                            version: query.installedVersion
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

    /// The `vulnerability-scanning` scenario: *nothing is transmitted before
    /// consent*.
    ///
    /// The whole first-launch sequence — construct the engine, open the surface,
    /// read the cache, ask for a scan, ask for a scheduled scan — against a
    /// recording seam that counts every request. The count must be zero, and the
    /// refusal must be visible rather than silent.
    @Test("Nothing is transmitted before consent")
    func nothingIsTransmittedBeforeConsent() async throws {
        let source = RecordingAdvisorySource()
        let engine = Self.engine(
            source: source,
            consent: FixedScanConsent(.notGranted),
            cache: Self.cache(scannedAt: Self.epoch.addingTimeInterval(-100 * 3_600))
        )

        // Opening the surface reads the cache. That is a disk read, not egress.
        let cached = await engine.loadCache()
        #expect(cached?.entries.count == 1, "the surface could not read its own cache")

        let scan = await engine.scan()
        // Stale by four days, so consent is the only thing standing in the way.
        let scheduled = await engine.scanIfStale()

        #expect(source.discoverCallCount == 0, "a request was issued before consent")
        #expect(source.enrichCallCount == 0, "a request was issued before consent")
        #expect(scan == .failed(.blockedPendingConsent))
        #expect(scheduled == .failed(.blockedPendingConsent))
        #expect(await engine.status == .blockedPendingConsent)

        // The control: the same engine with consent recorded does reach the
        // network, so the zeros above are consent's doing.
        let consented = Self.engine(
            source: source,
            consent: FixedScanConsent(.granted(at: Self.epoch))
        )
        _ = await consented.scan()
        #expect(source.discoverCallCount == 1)
    }

    /// The `vulnerability-scanning` scenario: *off means fully off*.
    ///
    /// Not merely "no new manual scan": the scheduled loop keeps running and
    /// must issue nothing either. So time is advanced past several poll
    /// granularities *and* past `staleAfter`, which is precisely when a loop that
    /// only checked consent at start-up would fire.
    @Test("Turning scanning off stops every request and every scheduled run")
    func turningScanningOffStopsEveryRequestAndEveryScheduledRun() async throws {
        let source = RecordingAdvisorySource()
        let clock = TestClock()
        let timeSource = MutableTimeSource(Self.epoch)
        let consent = MutableScanConsent(.granted(at: Self.epoch))
        let cache = Self.cache(scannedAt: Self.epoch)
        let engine = Self.engine(
            source: source,
            consent: consent,
            cache: cache,
            clock: clock,
            timeSource: timeSource
        )

        let loop = Task { await engine.runRefreshLoop() }
        // See `SecurityRefreshPolicyTests`: cancelled, never awaited.
        defer { loop.cancel() }
        await clock.waitForSleepers()

        // A day passes with consent in place: the scheduled scan fires.
        timeSource.advance(by: 25 * 3_600)
        await clock.advance(by: .seconds(15 * 60))
        await clock.waitForSleepers()
        #expect(source.discoverCallCount == 1, "a consented, stale scan did not run")

        consent.revoke()
        let afterRevocation = source.discoverCallCount

        // Several poll granularities and another two days of wall clock.
        for _ in 1...6 {
            timeSource.advance(by: 8 * 3_600)
            await clock.advance(by: .seconds(15 * 60))
            await clock.waitForSleepers()
        }

        #expect(
            source.discoverCallCount == afterRevocation,
            "\(source.discoverCallCount - afterRevocation) requests were issued after revocation"
        )
        #expect(source.enrichCallCount == 0)
        #expect(await engine.status == .blockedPendingConsent)
    }

    /// Off stops the requests, not the reading. Findings already on disk stay
    /// visible, and stay labelled with their age rather than presented as fresh.
    @Test("The cache stays readable with its age after revocation")
    func theCacheStaysReadableWithItsAgeAfterRevocation() async throws {
        let source = RecordingAdvisorySource()
        let consent = MutableScanConsent(.granted(at: Self.epoch))
        let engine = Self.engine(
            source: source,
            consent: consent,
            cache: Self.cache(scannedAt: Self.epoch)
        )

        consent.revoke()

        let cached = try #require(await engine.loadCache())
        let entry = try #require(cached.entries.first)

        #expect(entry.freshness == .cached(fetchedAt: Self.epoch))
        #expect(entry.freshness != .live)
        #expect(entry.age(at: Self.epoch.addingTimeInterval(7_200)) == 7_200)
        #expect(cached.revision == SecurityScanRevision(ordinal: 3))
        #expect(source.discoverCallCount == 0, "reading the cache reached the network")
    }
}
