import Catalog
import Foundation
import SecurityKit
import Testing

/// The advisory cache: what it serves, what it refuses to serve, and what
/// survives a relaunch.
///
/// Two independent invalidations live here and they answer different questions.
/// The first — TTL, mapping revision, matcher version — asks *is this code still
/// the code that produced the entry*. The second — an advisory's own `modified`
/// — asks *is the world still the world the entry described*. Either one alone
/// leaves a real failure open: without the first, a corrected mapping table is
/// masked by a fresh-looking entry for a day; without the second, an advisory
/// published this morning is invisible until tomorrow.
@Suite("Advisory cache")
struct AdvisoryCacheTests {
    // MARK: - Fixtures for the values under test

    static let epoch = Date(timeIntervalSince1970: 1_780_000_000)

    static func key(_ name: String = "bat", version: String = "0.15.0") -> AdvisoryCacheKey {
        AdvisoryCacheKey(
            sourceID: .osv,
            packageID: PackageID(kind: .formula, name: name),
            version: version
        )
    }

    /// A real outcome, matched from a captured advisory, so the round-trip below
    /// is exercising the shape the app actually stores rather than a stub.
    static func realFindings() throws -> CVEScanOutcome {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-GHSA-p24j-h477-76q3.json")
        )
        let query = try #require(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "bat"),
                installedVersion: "0.15.0"
            ).query
        )
        return CVEMatcher().match(query: query, answer: .answered([advisory]))
    }

    static func entry(
        outcome: CVEScanOutcome = .covered(
            .clean(CleanCoverage(answeredBy: .osv, queriedVersion: "0.15.0"))
        ),
        fetchedAt: Date = epoch,
        advisoryModified: Date? = nil,
        mappingRevision: Int = EcosystemMapping.revision,
        matcherVersion: Int = CVEMatcher.version
    ) -> AdvisoryCacheEntry {
        AdvisoryCacheEntry(
            key: key(),
            outcome: outcome,
            fetchedAt: fetchedAt,
            advisoryModified: advisoryModified,
            mappingRevision: mappingRevision,
            matcherVersion: matcherVersion
        )
    }

    static func directory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-advisory-cache-tests")
            .appendingPathComponent(UUID().uuidString)
    }

    // MARK: - Invalidation (a): time

    @Test("An entry inside the twenty-four hour window is served")
    func anEntryInsideTheTtlIsServed() {
        let entry = Self.entry()

        #expect(AdvisoryCacheEntry.timeToLive == 24 * 60 * 60)
        #expect(entry.isValid(at: Self.epoch.addingTimeInterval(60), against: .current))
        #expect(
            entry.isValid(at: Self.epoch.addingTimeInterval(23 * 3_600 + 3_540), against: .current)
        )
        // The boundary itself: exactly twenty-four hours is not *older than*
        // twenty-four hours.
        #expect(entry.isValid(at: Self.epoch.addingTimeInterval(24 * 3_600), against: .current))
    }

    @Test("An entry older than twenty-four hours is invalid")
    func anEntryOlderThanTwentyFourHoursIsInvalid() {
        let entry = Self.entry()

        #expect(
            entry.isValid(at: Self.epoch.addingTimeInterval(24 * 3_600 + 1), against: .current)
                == false
        )
        #expect(entry.isValid(at: Self.epoch.addingTimeInterval(72 * 3_600), against: .current) == false)
    }

    /// A clock that moved backwards makes an entry look arbitrarily fresh, so an
    /// entry stamped in the future is not trusted at all. Age is the only thing
    /// the freshness label can honestly report, and a negative age is not an age.
    @Test("An entry stamped in the future is invalid rather than eternally fresh")
    func anEntryStampedInTheFutureIsInvalid() {
        let entry = Self.entry(fetchedAt: Self.epoch.addingTimeInterval(3_600))

        #expect(entry.isValid(at: Self.epoch, against: .current) == false)
    }

    // MARK: - Invalidation (a): the code that produced it

    /// A corrected table or a fixed matcher can never be masked by a
    /// fresh-looking entry — which is the whole reason both numbers are stored
    /// beside the outcome rather than assumed.
    @Test("A mapping revision or matcher version mismatch invalidates regardless of the TTL")
    func aMappingRevisionOrMatcherVersionMismatchInvalidatesRegardlessOfTtl() {
        let oneMinuteOld = Self.epoch.addingTimeInterval(60)

        let staleTable = Self.entry(mappingRevision: EcosystemMapping.revision - 1)
        #expect(staleTable.isValid(at: oneMinuteOld, against: .current) == false)

        let staleMatcher = Self.entry(matcherVersion: CVEMatcher.version - 1)
        #expect(staleMatcher.isValid(at: oneMinuteOld, against: .current) == false)

        // A *newer* recorded version is just as much a mismatch: it means the
        // entry was written by a build this one is not.
        let futureTable = Self.entry(mappingRevision: EcosystemMapping.revision + 1)
        #expect(futureTable.isValid(at: oneMinuteOld, against: .current) == false)

        // The control: the same entry with both numbers matching is served, so
        // the three refusals above are the mismatch's doing.
        #expect(Self.entry().isValid(at: oneMinuteOld, against: .current))
    }

    // MARK: - Invalidation (b): the world

    @Test("An advisory modified more recently than the entry forces re-hydration inside the TTL")
    func anAdvisoryModifiedNewerThanTheEntryForcesReHydrationInsideTheTtl() {
        let modified = Self.epoch.addingTimeInterval(-86_400)
        let entry = Self.entry(advisoryModified: modified)
        let insideTheWindow = Self.epoch.addingTimeInterval(60)

        // Untouched since the entry was written: the entry stands.
        #expect(
            entry.isValid(
                at: insideTheWindow,
                against: .current,
                newestAdvisoryModified: modified
            )
        )
        #expect(
            entry.isValid(
                at: insideTheWindow,
                against: .current,
                newestAdvisoryModified: modified.addingTimeInterval(-1)
            )
        )
        // Edited by one second: re-hydrate, TTL or no TTL.
        #expect(
            entry.isValid(
                at: insideTheWindow,
                against: .current,
                newestAdvisoryModified: modified.addingTimeInterval(1)
            ) == false
        )
    }

    /// A clean entry recorded no advisory timestamp because there was no
    /// advisory. The moment `querybatch` names one, the entry is describing a
    /// world that no longer exists.
    @Test("An advisory appearing for a previously clean package invalidates its entry")
    func anAdvisoryAppearingForACleanPackageInvalidatesItsEntry() {
        let entry = Self.entry(advisoryModified: nil)
        let insideTheWindow = Self.epoch.addingTimeInterval(60)

        #expect(entry.isValid(at: insideTheWindow, against: .current))
        #expect(
            entry.isValid(
                at: insideTheWindow,
                against: .current,
                newestAdvisoryModified: Self.epoch
            ) == false
        )
    }

    // MARK: - Freshness

    /// The `vulnerability-scanning` scenario: *findings are readable offline*,
    /// and they are labelled with their age rather than presented as fresh.
    @Test("Cached outcomes are published as cached with their age, never as live")
    func cachedOutcomesArePublishedAsCachedWithTheirAge() async throws {
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AdvisoryCache(
            fileURL: directory.appendingPathComponent(SecurityKit.advisoryCacheFileName)
        )

        let findings = try Self.realFindings()
        try await cache.save(
            AdvisoryCacheFile(
                revisionOrdinal: 1,
                entries: [Self.entry(outcome: findings, advisoryModified: Self.epoch)]
            )
        )

        let reloaded = try #require(await cache.load())
        #expect(reloaded.entries.count == 1)
        let entry = try #require(reloaded.entries.first)

        #expect(entry.freshness == .cached(fetchedAt: Self.epoch))
        #expect(entry.freshness != .live)
        #expect(entry.age(at: Self.epoch.addingTimeInterval(3_600)) == 3_600)

        // Readable offline means the findings themselves survived the disk, not
        // merely that a file was written.
        guard case .covered(.findings(let stored)) = entry.outcome else {
            Issue.record("the cached outcome came back as \(entry.outcome), not as findings")
            return
        }
        #expect(stored.count == 1)
        #expect(stored.first?.advisoryID == "GHSA-p24j-h477-76q3")
        #expect(stored.first?.cveID == "CVE-2021-36753")
        #expect(stored.first?.severity == .high)
        #expect(stored.first?.declaredFixVersion == "0.18.2")
        #expect(entry.outcome == findings, "the round trip changed the outcome")
    }

    // MARK: - Degradation

    /// The `DiskUsageCache` rule: derived data in `~/Library/Caches/` degrades to
    /// a full scan. There is no error path here to handle, because there is no
    /// error — an unreadable cache is simply no cache.
    @Test("A corrupt or unreadable file yields no entries and no error path")
    func aCorruptOrUnreadableFileYieldsNoEntriesAndNoErrorPath() async throws {
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(SecurityKit.advisoryCacheFileName)
        let cache = AdvisoryCache(fileURL: fileURL)

        // Nothing there at all.
        var loaded = try await cache.load()
        #expect(loaded == nil, "an absent cache file produced \(String(describing: loaded))")

        // There, and not JSON.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json at all".utf8).write(to: fileURL, options: .atomic)
        loaded = try await cache.load()
        #expect(loaded == nil, "a corrupt cache file produced \(String(describing: loaded))")

        // There, JSON, and not this schema.
        try Data(#"{"schemaVersion":99,"revisionOrdinal":1,"entries":[]}"#.utf8)
            .write(to: fileURL, options: .atomic)
        loaded = try await cache.load()
        #expect(loaded == nil, "a foreign schema produced \(String(describing: loaded))")

        // The control: a file this cache did write comes back. Without it, the
        // three `nil`s above would be satisfied by a `load()` that always
        // returns `nil`.
        try await cache.save(AdvisoryCacheFile(revisionOrdinal: 4, entries: [Self.entry()]))
        let reloaded = try #require(await cache.load())
        #expect(reloaded.revisionOrdinal == 4)
        #expect(reloaded.entries.count == 1)
    }

    // MARK: - The revision ordinal

    /// Monotonicity has to survive the process, or every relaunch restarts the
    /// ordinal at zero and the guard below stops guarding anything.
    @Test("The revision ordinal survives a simulated relaunch")
    func theRevisionOrdinalSurvivesASimulatedRelaunch() async throws {
        let directory = Self.directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(SecurityKit.advisoryCacheFileName)

        let beforeRelaunch = AdvisoryCache(fileURL: fileURL)
        try await beforeRelaunch.save(
            AdvisoryCacheFile(revisionOrdinal: 7, entries: [Self.entry()])
        )

        // A different actor instance on the same URL is what a relaunch looks
        // like from this layer.
        let afterRelaunch = AdvisoryCache(fileURL: fileURL)
        let reloaded = try #require(await afterRelaunch.load())

        #expect(reloaded.revisionOrdinal == 7)
        #expect(reloaded.revision == SecurityScanRevision(ordinal: 7))
        // A live scan mints the next one from the persisted value, not from zero.
        #expect(reloaded.revision.next() == SecurityScanRevision(ordinal: 8))
    }

    /// The `CatalogStore.loadCache()` → `adopt` precedent, stated as a test.
    ///
    /// Cache reads are slow and network scans are sometimes not. When the two
    /// race, the ordinal decides — never arrival order — so fresh results are
    /// not blanked by a cache read that started first and finished second.
    @Test("A slow cache load landing after a fast live scan is rejected by the ordinal guard")
    func aSlowCacheLoadLandingAfterAFastLiveScanIsRejectedByTheOrdinalGuard() {
        let persisted = SecurityScanRevision(ordinal: 3)
        var adopted: SecurityScanRevision?

        // The live scan mints `persisted + 1` and lands first.
        let live = persisted.next()
        #expect(live.supersedes(adopted))
        adopted = live

        // The cache read finally lands, carrying the *older* persisted ordinal.
        #expect(persisted.supersedes(adopted) == false)
        #expect(adopted == live, "a late cache read blanked a fresher live scan")

        // A duplicate does not supersede either — it joins, it does not replace.
        #expect(live.supersedes(adopted) == false)

        // The control: the next live scan does supersede, so `supersedes` is not
        // simply always false.
        #expect(live.next().supersedes(adopted))
    }
}
