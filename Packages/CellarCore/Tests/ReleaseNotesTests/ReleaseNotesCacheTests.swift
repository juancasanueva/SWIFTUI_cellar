import Foundation
import ReleaseNotes
import Testing

/// The cache is derived data on a path any local process can write, and it holds
/// two kinds of answer with two different shelf lives.
///
/// Three rules run through everything below.
///
/// 1. **A corrupt or mismatched store means cached nothing.** Not a partial
///    adoption, not a throw the caller has to handle, and above all not a wrong
///    answer. Reading nothing costs one request; adopting half a file costs
///    correctness.
/// 2. **The clock is injected.** Every freshness predicate is a pure function of
///    a `now` the test supplies, so a TTL boundary is asserted synchronously
///    rather than by sleeping.
/// 3. **A rate-limit refusal is never written.** A cached wall outlives the hour
///    it describes.
@Suite("Release-notes cache")
struct ReleaseNotesCacheTests {
    // MARK: - Arrangement

    private var repository: GitHubRepository { GitHubRepository(owner: "acme", name: "foo")! }
    private var other: GitHubRepository { GitHubRepository(owner: "acme", name: "bar")! }

    private var resolved: ResolvedRepository {
        ResolvedRepository(repository: repository, source: .homepage, agreeingSourceCount: 1)
    }

    private func matched(_ tag: String = "v2.44.0") -> ReleaseNotesOutcome {
        .notes(resolved, GitHubRelease(tagName: tag, name: tag, body: "notes for \(tag)"))
    }

    private var negative: ReleaseNotesOutcome {
        .noReleaseMatchesVersion(resolved, version: "2.44.0", inspected: 26, pageWasFull: false)
    }

    private func entry(
        _ outcome: ReleaseNotesOutcome,
        storedAt: Date,
        etag: String? = nil
    ) -> ReleaseNotesCacheEntry {
        ReleaseNotesCacheEntry(outcome: outcome, storedAt: storedAt, etag: etag)
    }

    private func key(_ repository: GitHubRepository, _ version: String) -> ReleaseNotesCacheKey {
        ReleaseNotesCacheKey(repository: repository, version: version)
    }

    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-release-notes-tests-\(UUID().uuidString)")
            .appendingPathComponent("release-notes-v1.json")
    }

    // MARK: - Untrusted on-disk input

    @Test("A missing file reads as cached nothing, throws nothing, and writes nothing")
    func aMissingFileReadsAsCachedNothing() async throws {
        let url = temporaryFile()
        let recorder = RecordingFileAccess()

        let cache = ReleaseNotesCache(fileURL: url, access: recorder)
        let file = await cache.load()

        let writes = await recorder.writes
        let removals = await recorder.removals
        let reads = await recorder.reads

        #expect(file == nil)
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
        #expect(writes.isEmpty, "a read wrote \(writes)")
        #expect(removals.isEmpty, "a read removed \(removals)")
        // Anchored: the read really did look at the path it was given.
        #expect(reads.contains(url.path))
    }

    @Test(
        "A byte-corrupt or mismatched file reads as cached nothing and adopts no partial entries",
        arguments: [
            "not json at all",
            "{",
            "[]",
            #"{"schemaVersion": 99, "entries": []}"#,
            #"{"schemaVersion": 0, "entries": []}"#
        ]
    )
    func aCorruptOrMismatchedFileReadsAsCachedNothing(contents: String) async throws {
        let url = temporaryFile()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let recorder = RecordingFileAccess()
        let file = await ReleaseNotesCache(fileURL: url, access: recorder).load()

        let writes = await recorder.writes
        let removals = await recorder.removals

        #expect(file == nil, "\(contents) was adopted as \(String(describing: file))")
        #expect(writes.isEmpty, "a rejecting read wrote to disk")
        #expect(removals.isEmpty, "a rejecting read removed the file")
        // The bytes are still there. A read that cannot understand a file must
        // not delete it — the next version of this app might understand it.
        #expect(try Data(contentsOf: url) == Data(contents.utf8))
    }

    /// A file carrying **this** schema version is adopted, so the refusals above
    /// are about the mismatch and not about a loader that never adopts anything.
    @Test("A file at the current schema version round-trips through the store")
    func aFileAtTheCurrentSchemaVersionRoundTrips() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_786_000_000)

        let cache = ReleaseNotesCache(fileURL: url)
        try await cache.save(
            ReleaseNotesCacheFile(entries: [key(repository, "2.44.0"): entry(matched(), storedAt: now)])
        )

        let read = try #require(await cache.load())
        #expect(read.schemaVersion == ReleaseNotesSchema.currentVersion)
        #expect(read.entries.count == 1)
        #expect(read.entries[key(repository, "2.44.0")]?.outcome == matched())
        #expect(read.entries[key(repository, "2.44.0")]?.storedAt == now)
    }

    /// The schema version is this capability's **own**, and deliberately not the
    /// catalog's. Sharing the constant would mean an unrelated catalog field
    /// change silently wiped the user's notes cache.
    @Test("The schema version is a constant this capability owns")
    func theSchemaVersionIsAConstantThisCapabilityOwns() {
        #expect(ReleaseNotesSchema.currentVersion == 1)
    }

    // MARK: - The two tiers, over an injected clock

    /// Seven days for a matched body. A published release note does not change
    /// after the fact, so re-asking sooner spends a request against a 60-per-hour
    /// budget to learn nothing.
    @Test(
        "A matched body is fresh at 6d23h and stale at 7d1h",
        arguments: [
            (6 * 86_400 + 23 * 3_600, true),
            (7 * 86_400 - 1, true),
            (7 * 86_400 + 3_600, false),
            (8 * 86_400, false)
        ]
    )
    func aMatchedBodyIsFreshForSevenDays(age: Int, fresh: Bool) {
        let storedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let entry = entry(matched(), storedAt: storedAt)

        #expect(
            entry.isFresh(now: storedAt.addingTimeInterval(TimeInterval(age))) == fresh,
            "a matched entry aged \(age)s reported fresh=\(!fresh)"
        )
    }

    /// Twenty-four hours for every negative answer. A repository that published
    /// nothing yesterday may have published something today, and a day is short
    /// enough that a user who upgrades and looks again tomorrow gets a real
    /// answer.
    @Test(
        "A negative answer is fresh at 23h and stale at 25h",
        arguments: [
            (23 * 3_600, true),
            (24 * 3_600 - 1, true),
            (25 * 3_600, false),
            (7 * 86_400, false)
        ]
    )
    func aNegativeAnswerIsFreshForTwentyFourHours(age: Int, fresh: Bool) {
        let storedAt = Date(timeIntervalSince1970: 1_786_000_000)

        for outcome in [
            negative,
            .repositoryPublishesNoReleases(resolved),
            .unresolvableRepository(triedSources: Set(RepositorySource.allCases))
        ] as [ReleaseNotesOutcome] {
            #expect(
                entry(outcome, storedAt: storedAt)
                    .isFresh(now: storedAt.addingTimeInterval(TimeInterval(age))) == fresh,
                "\(outcome) aged \(age)s reported fresh=\(!fresh)"
            )
        }
    }

    @Test("The two tiers really are different: a matched entry outlives a negative one")
    func theTwoTiersReallyAreDifferent() {
        let storedAt = Date(timeIntervalSince1970: 1_786_000_000)
        let threeDays = storedAt.addingTimeInterval(3 * 86_400)

        #expect(entry(matched(), storedAt: storedAt).isFresh(now: threeDays))
        #expect(entry(negative, storedAt: storedAt).isFresh(now: threeDays) == false)
        #expect(ReleaseNotesCacheEntry.matchedTTL == 7 * 86_400)
        #expect(ReleaseNotesCacheEntry.negativeTTL == 24 * 3_600)
    }

    /// An entry stamped in the **future** is rejected rather than treated as
    /// arbitrarily fresh: a clock that moved backwards makes every age
    /// meaningless, and a negative age is not an age. The `AdvisoryCacheEntry`
    /// asymmetry, restated because it is easy to lose.
    @Test("An entry stamped in the future is not fresh")
    func anEntryStampedInTheFutureIsNotFresh() {
        let storedAt = Date(timeIntervalSince1970: 1_786_000_000)

        #expect(
            entry(matched(), storedAt: storedAt)
                .isFresh(now: storedAt.addingTimeInterval(-3_600)) == false
        )
    }

    // MARK: - The key

    @Test("The key is repository and version, so two versions of one repository are two entries")
    func theKeyIsRepositoryAndVersion() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_786_000_000)

        let cache = ReleaseNotesCache(fileURL: url)
        try await cache.save(ReleaseNotesCacheFile(entries: [
            key(repository, "2.44.0"): entry(matched("v2.44.0"), storedAt: now),
            key(repository, "2.43.0"): entry(matched("v2.43.0"), storedAt: now),
            key(other, "2.44.0"): entry(matched("v2.44.0"), storedAt: now)
        ]))

        let read = try #require(await cache.load())
        #expect(read.entries.count == 3)
        #expect(read.entries[key(repository, "2.44.0")]?.outcome.release?.tagName == "v2.44.0")
        #expect(read.entries[key(repository, "2.43.0")]?.outcome.release?.tagName == "v2.43.0")
        // An upgrade is therefore a cache **miss** rather than a stale hit, with
        // nothing to invalidate by hand.
        #expect(read.entries[key(repository, "2.45.0")] == nil)
    }

    // MARK: - A refusal is never cached

    @Test("A rate-limit refusal leaves no entry for that repository and version")
    func aRateLimitRefusalLeavesNoEntry() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let cache = ReleaseNotesCache(fileURL: url)

        let refusal = ReleaseNotesOutcome.unavailable(
            .rateLimited(RateLimitStatus(limit: 60, remaining: 0, resetAt: now))
        )

        try await cache.record(
            refusal, for: key(repository, "2.44.0"), etag: nil, now: now
        )

        // Read back: nothing at all, not even an empty-bodied placeholder.
        let read = await cache.load()
        #expect(read?.entries[key(repository, "2.44.0")] == nil)

        // The control, so "nothing was written" is a decision about the refusal
        // and not a `record` that never works.
        try await cache.record(matched(), for: key(repository, "2.44.0"), etag: nil, now: now)
        let recorded = await cache.load()?.entries[key(repository, "2.44.0")]?.outcome
        #expect(recorded == matched())
    }

    @Test("No failure reason at all is written to the store")
    func noFailureReasonAtAllIsWritten() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let cache = ReleaseNotesCache(fileURL: url)

        for failure in ReleaseNotesFailure.allTestCases {
            try await cache.record(
                .unavailable(failure), for: key(repository, "2.44.0"), etag: nil, now: now
            )
        }

        let stored = await cache.load()?.entries
        #expect(stored?.isEmpty != false, "a failure reached the store")
    }

    // MARK: - Bounds and pruning

    @Test("The entry cap drops the oldest first")
    func theEntryCapDropsTheOldestFirst() {
        let base = Date(timeIntervalSince1970: 1_786_000_000)
        var entries: [ReleaseNotesCacheKey: ReleaseNotesCacheEntry] = [:]

        // 210 entries, each one minute newer than the last, all inside the
        // matched TTL so the cap is what does the dropping rather than expiry.
        for index in 0..<210 {
            entries[key(repository, "1.\(index).0")] = entry(
                matched(), storedAt: base.addingTimeInterval(TimeInterval(index * 60))
            )
        }

        let pruned = ReleaseNotesCacheFile(entries: entries)
            .pruned(now: base.addingTimeInterval(3 * 86_400))

        #expect(ReleaseNotesCacheFile.entryLimit == 200)
        #expect(pruned.entries.count == 200)
        // The ten oldest are gone and the newest survived.
        #expect(pruned.entries[key(repository, "1.0.0")] == nil)
        #expect(pruned.entries[key(repository, "1.9.0")] == nil)
        #expect(pruned.entries[key(repository, "1.10.0")] != nil)
        #expect(pruned.entries[key(repository, "1.209.0")] != nil)
    }

    @Test("Pruning drops expired entries and keeps fresh ones")
    func pruningDropsExpiredEntries() {
        let base = Date(timeIntervalSince1970: 1_786_000_000)
        let file = ReleaseNotesCacheFile(entries: [
            key(repository, "fresh-matched"): entry(matched(), storedAt: base),
            key(repository, "stale-matched"): entry(
                matched(), storedAt: base.addingTimeInterval(-8 * 86_400)
            ),
            key(repository, "fresh-negative"): entry(negative, storedAt: base),
            key(repository, "stale-negative"): entry(
                negative, storedAt: base.addingTimeInterval(-25 * 3_600)
            )
        ])

        let pruned = file.pruned(now: base)

        #expect(pruned.entries.count == 2)
        #expect(pruned.entries[key(repository, "fresh-matched")] != nil)
        #expect(pruned.entries[key(repository, "fresh-negative")] != nil)
        #expect(pruned.entries[key(repository, "stale-matched")] == nil)
        #expect(pruned.entries[key(repository, "stale-negative")] == nil)
    }

    @Test("Pruning is idempotent")
    func pruningIsIdempotent() {
        let base = Date(timeIntervalSince1970: 1_786_000_000)
        var entries: [ReleaseNotesCacheKey: ReleaseNotesCacheEntry] = [:]
        for index in 0..<250 {
            entries[key(repository, "1.\(index).0")] = entry(
                index.isMultiple(of: 3) ? negative : matched(),
                storedAt: base.addingTimeInterval(TimeInterval(index * 60) - 30 * 3_600)
            )
        }

        let once = ReleaseNotesCacheFile(entries: entries).pruned(now: base)
        let twice = once.pruned(now: base)

        #expect(once == twice, "a second prune changed the file")
        #expect(once.entries.isEmpty == false, "the prune removed everything, proving nothing")
    }

    // MARK: - The catalog is untouched

    /// The final clause of the cache requirement, and the whole of RN-R9's cache
    /// half: this store reads and writes its own file and nothing else. Asserted
    /// with a recording seam over a directory that also contains a catalog
    /// snapshot, so "it did not touch the catalog" is a checked list of paths
    /// rather than a hope.
    @Test("Loading and saving touches this store's file and no catalog file")
    func loadingAndSavingTouchesNoCatalogFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-release-notes-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A catalog snapshot sitting beside the notes cache, exactly as it does
        // in `~/Library/Caches/Cellar/`.
        let snapshot = directory.appendingPathComponent("catalog-snapshot.json")
        let snapshotBytes = Data(#"{"schemaVersion":2,"packages":[]}"#.utf8)
        try snapshotBytes.write(to: snapshot)

        let url = directory.appendingPathComponent("release-notes-v1.json")
        let recorder = RecordingFileAccess()
        let cache = ReleaseNotesCache(fileURL: url, access: recorder)
        let now = Date(timeIntervalSince1970: 1_786_000_000)

        _ = await cache.load()
        try await cache.record(matched(), for: key(repository, "2.44.0"), etag: "\"e\"", now: now)
        _ = await cache.load()

        let touched = await recorder.allPaths
        #expect(touched.isEmpty == false, "the recorder saw nothing, so it proves nothing")
        #expect(
            touched.allSatisfy { $0 == url.path },
            "the store touched \(touched.filter { $0 != url.path })"
        )
        // And the snapshot on disk is byte-identical.
        #expect(try Data(contentsOf: snapshot) == snapshotBytes)
    }

    // MARK: - Durability

    @Test("A save replaces the previous file atomically and keeps its keys sorted")
    func aSaveReplacesThePreviousFileAtomically() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let cache = ReleaseNotesCache(fileURL: url)

        try await cache.save(ReleaseNotesCacheFile(entries: [
            key(repository, "2.44.0"): entry(matched(), storedAt: now)
        ]))
        let first = try Data(contentsOf: url)

        try await cache.save(ReleaseNotesCacheFile(entries: [
            key(repository, "2.45.0"): entry(matched("v2.45.0"), storedAt: now)
        ]))
        let second = try Data(contentsOf: url)

        let reloaded = try #require(await cache.load())

        #expect(first != second)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries[key(repository, "2.45.0")] != nil)

        // Sorted keys, so a byte-diff of two writes shows what changed rather
        // than a reshuffled dictionary.
        let text = try #require(String(data: second, encoding: .utf8))
        let entriesAt = try #require(text.range(of: "\"entries\""))
        let versionAt = try #require(text.range(of: "\"schemaVersion\""))
        #expect(entriesAt.lowerBound < versionAt.lowerBound, "the encoder did not sort its keys")
    }

    @Test("A recorded entry carries the ETag it was answered with")
    func aRecordedEntryCarriesItsEtag() async throws {
        let url = temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let cache = ReleaseNotesCache(fileURL: url)

        try await cache.record(
            matched(), for: key(repository, "2.44.0"), etag: "\"deadbeef\"", now: now
        )

        let stored = await cache.load()?.entries[key(repository, "2.44.0")]
        #expect(stored?.etag == "\"deadbeef\"")
    }
}

// MARK: - The file seam

/// Every filesystem operation the cache performs, recorded.
///
/// The claims here are absences — "a rejecting read wrote nothing", "the catalog
/// snapshot was never opened" — and an absence is only provable if something
/// counted the presences.
actor RecordingFileAccess: ReleaseNotesFileAccess {
    private(set) var reads: [String] = []
    private(set) var writes: [String] = []
    private(set) var removals: [String] = []

    var allPaths: [String] { reads + writes + removals }

    func contents(at url: URL) -> Data? {
        reads.append(url.path)
        return try? Data(contentsOf: url)
    }

    func write(_ data: Data, to url: URL) throws {
        writes.append(url.path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    func remove(at url: URL) throws {
        removals.append(url.path)
        try FileManager.default.removeItem(at: url)
    }
}
