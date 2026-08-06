import Foundation

// MARK: - Schema

/// This store's own schema version.
///
/// **Deliberately not `CatalogSnapshot.currentSchemaVersion`.** The *gate idiom*
/// is what the requirement asks for — a file whose recorded version does not
/// match is discarded whole — and sharing the catalog's constant would satisfy
/// the letter of that while breaking its intent: an unrelated field added to a
/// catalog package would move the catalog's version and silently wipe every
/// release note the user has cached, for a change that has nothing to do with
/// them. Two independent bodies of derived data, two independent versions.
public enum ReleaseNotesSchema {
    public static let currentVersion = 1
}

// MARK: - Identity

/// What one cached answer is an answer *about*.
///
/// The version is part of the key, not a field beside it, so an upgrade produces
/// a **miss** rather than a stale hit — the same mechanic that makes a dismissed
/// finding re-surface after an upgrade. Nothing has to be invalidated by hand;
/// the key simply stops matching.
public struct ReleaseNotesCacheKey: Sendable, Hashable, Codable {
    public let repository: GitHubRepository
    public let version: String

    public init(repository: GitHubRepository, version: String) {
        self.repository = repository
        self.version = version
    }

    /// A stable ordering, so a written file is byte-reproducible and a diff of
    /// two writes shows what changed rather than a reshuffled dictionary.
    var sortKey: String { "\(repository.owner)/\(repository.name)@\(version)" }
}

// MARK: - Entries

/// One cached answer and everything needed to decide whether it is still worth
/// serving.
public struct ReleaseNotesCacheEntry: Sendable, Hashable, Codable {
    /// Seven days for a matched release body.
    ///
    /// A published release note does not change after the fact, so re-asking
    /// sooner spends one of sixty requests an hour to learn nothing. Seven days
    /// is also comfortably longer than the interval between noticing a package is
    /// outdated and upgrading it, which is the whole window this cache serves.
    public static let matchedTTL: TimeInterval = 7 * 86_400

    /// Twenty-four hours for every negative answer.
    ///
    /// Shorter than the matched tier because a negative answer is a claim about
    /// the *present*: a repository that published nothing yesterday may publish
    /// today, and a user who looks again tomorrow deserves a real answer rather
    /// than last week's absence.
    public static let negativeTTL: TimeInterval = 24 * 3_600

    public let outcome: ReleaseNotesOutcome
    public let storedAt: Date
    /// The validator the answer was served with, so a stale entry can be
    /// revalidated with `If-None-Match` instead of refetched.
    public let etag: String?

    public init(outcome: ReleaseNotesOutcome, storedAt: Date, etag: String?) {
        self.outcome = outcome
        self.storedAt = storedAt
        self.etag = etag
    }

    /// The tier this entry ages at, chosen by the outcome case rather than
    /// stored, so the two can never disagree.
    public var timeToLive: TimeInterval {
        if case .notes = outcome { Self.matchedTTL } else { Self.negativeTTL }
    }

    /// Whether this entry may still be served without asking again.
    ///
    /// An entry stamped in the **future** is rejected outright rather than
    /// treated as arbitrarily fresh: a clock that moved backwards makes every age
    /// meaningless, and a negative age is not an age. The `AdvisoryCacheEntry`
    /// asymmetry, restated because it is the kind of thing that gets lost.
    public func isFresh(now: Date) -> Bool {
        let age = now.timeIntervalSince(storedAt)
        return age >= 0 && age <= timeToLive
    }
}

// MARK: - The file

/// Everything the cache persists, in one file.
public struct ReleaseNotesCacheFile: Sendable, Hashable, Codable {
    /// Two hundred entries. A user with a large inventory who looks at release
    /// notes constantly still fits; a file that grew without bound would be
    /// derived data nobody ever cleaned up.
    public static let entryLimit = 200

    public let schemaVersion: Int
    public let entries: [ReleaseNotesCacheKey: ReleaseNotesCacheEntry]

    public init(
        schemaVersion: Int = ReleaseNotesSchema.currentVersion,
        entries: [ReleaseNotesCacheKey: ReleaseNotesCacheEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    /// Expiry first, then the cap, oldest first.
    ///
    /// That order matters: capping first could drop a fresh entry to make room
    /// for a stale one that expiry was about to remove anyway. Idempotent by
    /// construction — running it twice on the same `now` removes nothing the
    /// first pass left.
    public func pruned(now: Date) -> Self {
        let fresh = entries.filter { $0.value.isFresh(now: now) }
        guard fresh.count > Self.entryLimit else {
            return ReleaseNotesCacheFile(schemaVersion: schemaVersion, entries: fresh)
        }

        let kept = fresh
            .sorted { lhs, rhs in
                // Newest first, with the key as a tie-break so two entries
                // stamped in the same instant drop deterministically.
                if lhs.value.storedAt != rhs.value.storedAt {
                    return lhs.value.storedAt > rhs.value.storedAt
                }
                return lhs.key.sortKey < rhs.key.sortKey
            }
            .prefix(Self.entryLimit)

        return ReleaseNotesCacheFile(
            schemaVersion: schemaVersion,
            entries: Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        )
    }

    // MARK: - Codable

    /// Encoded as a **sorted array of records**, not as a Swift dictionary.
    ///
    /// `Codable` writes a dictionary with a non-`String` key as an unkeyed array
    /// in iteration order, which is not stable between runs — so two saves of the
    /// same content would produce different bytes and the atomic-write discipline
    /// below would be replacing a file with a shuffled copy of itself.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case entries
    }

    private struct Record: Sendable, Hashable, Codable {
        let key: ReleaseNotesCacheKey
        let entry: ReleaseNotesCacheEntry
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let records = try container.decode([Record].self, forKey: .entries)
        entries = Dictionary(records.map { ($0.key, $0.entry) }, uniquingKeysWith: { _, last in last })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(
            entries
                .map { Record(key: $0.key, entry: $0.value) }
                .sorted { $0.key.sortKey < $1.key.sortKey },
            forKey: .entries
        )
    }
}

// MARK: - The filesystem seam

/// Every filesystem operation this store performs, behind one named seam.
///
/// A seam because the interesting claims are *absences* — a rejecting read wrote
/// nothing, a save touched this file and no catalog file — and an absence is only
/// provable if something counted the presences.
public protocol ReleaseNotesFileAccess: Sendable {
    func contents(at url: URL) async -> Data?
    func write(_ data: Data, to url: URL) async throws
    func remove(at url: URL) async throws
}

/// The real filesystem.
public struct SystemReleaseNotesFileAccess: ReleaseNotesFileAccess {
    public init() {}

    public func contents(at url: URL) async -> Data? {
        try? Data(contentsOf: url)
    }

    public func write(_ data: Data, to url: URL) async throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Atomic, so a crash mid-write leaves the previous cache intact rather
        // than a truncated file the next load would discard.
        try data.write(to: url, options: .atomic)
    }

    public func remove(at url: URL) async throws {
        try FileManager.default.removeItem(at: url)
    }
}

// MARK: - Storage

/// One JSON file, behind an actor.
///
/// The `AdvisoryCache` shape, including the part that looks like sloppiness and
/// is not: `load()` never surfaces a failure. This file is derived, re-fetchable
/// data, so "the cache could not be read" and "there is no cache" are the same
/// situation and both cost exactly one request. Handing callers an error would
/// only invite one of them to show the user a frightening message about a file
/// they do not own.
///
/// It is also the reason a corrupt file is **left on disk** rather than deleted:
/// a version of this app that cannot read a file is not evidence the file is
/// worthless, and deleting it forecloses on a reader that could.
///
/// The URL is injected. The app owns where its caches live.
public actor ReleaseNotesCache {
    private let fileURL: URL
    private let access: any ReleaseNotesFileAccess

    public init(fileURL: URL, access: any ReleaseNotesFileAccess = SystemReleaseNotesFileAccess()) {
        self.fileURL = fileURL
        self.access = access
    }

    /// The stored file, or `nil` for every reason there could be not to have one:
    /// missing, unreadable, byte-corrupt, or written by another schema.
    ///
    /// No partial adoption anywhere on this path. A file that decodes to three
    /// good entries and one broken one is discarded whole, because a cache that
    /// silently drops entries is a cache that silently changes answers.
    public func load() async -> ReleaseNotesCacheFile? {
        guard let data = await access.contents(at: fileURL),
              let file = try? Self.decoder.decode(ReleaseNotesCacheFile.self, from: data),
              file.schemaVersion == ReleaseNotesSchema.currentVersion
        else { return nil }
        return file
    }

    public func save(_ file: ReleaseNotesCacheFile) async throws {
        try await access.write(Self.encoder.encode(file), to: fileURL)
    }

    /// The freshest entry for a key, or `nil` when there is none worth serving.
    public func entry(
        for key: ReleaseNotesCacheKey,
        now: Date
    ) async -> ReleaseNotesCacheEntry? {
        guard let entry = await load()?.entries[key] else { return nil }
        return entry.isFresh(now: now) ? entry : nil
    }

    /// The entry for a key **whatever its age**, so a stale one can still lend its
    /// validator to a conditional request.
    public func staleEntry(for key: ReleaseNotesCacheKey) async -> ReleaseNotesCacheEntry? {
        await load()?.entries[key]
    }

    /// Writes one answer, if it is an answer worth keeping.
    ///
    /// An `.unavailable` outcome is dropped here rather than at the call site
    /// (D3). A cached refusal outlives the window it describes: a rate-limit wall
    /// that lifts at 21:15 would keep being reported for the next day, turning a
    /// transient condition into a persistent lie with no way for the user to
    /// clear it. Putting the rule in the store means no future caller can forget
    /// it.
    public func record(
        _ outcome: ReleaseNotesOutcome,
        for key: ReleaseNotesCacheKey,
        etag: String?,
        now: Date
    ) async throws {
        guard outcome.isCacheable else { return }

        var entries = await load()?.entries ?? [:]
        entries[key] = ReleaseNotesCacheEntry(outcome: outcome, storedAt: now, etag: etag)
        try await save(ReleaseNotesCacheFile(entries: entries).pruned(now: now))
    }

    /// Refreshes a still-valid entry's timestamp after a `304`, without paying
    /// for a body nobody sent.
    public func refresh(_ key: ReleaseNotesCacheKey, etag: String?, now: Date) async throws {
        guard let existing = await staleEntry(for: key) else { return }
        try await record(existing.outcome, for: key, etag: etag ?? existing.etag, now: now)
    }

    // MARK: - Coders

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
