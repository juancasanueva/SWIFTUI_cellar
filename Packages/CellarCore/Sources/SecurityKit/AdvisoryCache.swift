import Catalog
import Foundation

// MARK: - Identity

/// What one cached answer is an answer *about*.
///
/// The version is part of the key, not a field beside it. An upgrade therefore
/// produces a cache **miss** rather than a stale hit, which is the same mechanic
/// that makes a dismissal re-surface after an upgrade: the key simply stops
/// matching, and nothing has to be invalidated by hand.
public struct AdvisoryCacheKey: Sendable, Hashable, Codable {
    public let sourceID: AdvisorySourceID
    public let packageID: PackageID
    /// The installed version this answer was computed for.
    public let version: String

    public init(sourceID: AdvisorySourceID, packageID: PackageID, version: String) {
        self.sourceID = sourceID
        self.packageID = packageID
        self.version = version
    }
}

/// The build that is asking.
///
/// Named rather than passed as two loose integers, because the question these
/// two numbers answer together — *is this entry still the work of the code
/// running now* — is one question, and a call site that passed them in the wrong
/// order would otherwise compile.
public struct AdvisoryCacheContext: Sendable, Hashable, Codable {
    public let mappingRevision: Int
    public let matcherVersion: Int

    public init(mappingRevision: Int, matcherVersion: Int) {
        self.mappingRevision = mappingRevision
        self.matcherVersion = matcherVersion
    }

    /// The running build's own numbers.
    public static let current = AdvisoryCacheContext(
        mappingRevision: EcosystemMapping.revision,
        matcherVersion: CVEMatcher.version
    )
}

// MARK: - Entries

/// One package's cached answer, and everything needed to decide whether it is
/// still worth serving.
public struct AdvisoryCacheEntry: Sendable, Hashable, Codable {
    /// Twenty-four hours, chosen to **equal** `staleAfter` and the approved daily
    /// cadence.
    ///
    /// Shorter and every scheduled scan becomes a full re-query with no cache
    /// benefit at all; longer and a consented daily scan reads its own cache and
    /// never actually refreshes. At exactly one day the TTL serves the
    /// within-day repeats — relaunch, manual refresh, post-mutation re-scan —
    /// and never suppresses the scheduled one.
    public static let timeToLive: TimeInterval = 24 * 60 * 60

    public let key: AdvisoryCacheKey
    public let outcome: CVEScanOutcome
    public let fetchedAt: Date
    /// The newest `modified` across the advisories behind this outcome, or `nil`
    /// when there were none.
    public let advisoryModified: Date?
    public let mappingRevision: Int
    public let matcherVersion: Int

    public init(
        key: AdvisoryCacheKey,
        outcome: CVEScanOutcome,
        fetchedAt: Date,
        advisoryModified: Date?,
        mappingRevision: Int,
        matcherVersion: Int
    ) {
        self.key = key
        self.outcome = outcome
        self.fetchedAt = fetchedAt
        self.advisoryModified = advisoryModified
        self.mappingRevision = mappingRevision
        self.matcherVersion = matcherVersion
    }

    /// Always `.cached`, and never `.live`.
    ///
    /// There is no branch here and that is the point: a value read from disk
    /// cannot be published as fresh, because the type that says so is computed
    /// from the entry rather than passed in by whoever is doing the publishing.
    public var freshness: ResultFreshness { .cached(fetchedAt: fetchedAt) }

    public func age(at now: Date) -> TimeInterval { now.timeIntervalSince(fetchedAt) }

    /// Whether this entry may still be served.
    ///
    /// Two independent invalidations, and they answer different questions.
    ///
    /// **(a) Is this still the code that produced the entry?** A mismatched
    /// `mappingRevision` or `matcherVersion` invalidates regardless of age, so a
    /// corrected table or a fixed matcher can never be masked by a fresh-looking
    /// entry. Age is judged the same way, with one asymmetry worth stating: an
    /// entry stamped in the *future* is rejected outright rather than treated as
    /// arbitrarily fresh, because a clock that moved backwards makes every age
    /// meaningless and a negative age is not an age.
    ///
    /// **(b) Is this still the world the entry described?** `querybatch` is cheap
    /// and returns each advisory's `modified`. If any of them is newer than what
    /// this entry recorded, the entry is re-hydrated even well inside the TTL —
    /// and an advisory appearing at all for a package that cached *clean* is the
    /// same signal, which is why a `nil` `advisoryModified` cannot survive a
    /// non-`nil` observation.
    public func isValid(
        at now: Date,
        against context: AdvisoryCacheContext,
        newestAdvisoryModified: Date? = nil
    ) -> Bool {
        guard mappingRevision == context.mappingRevision,
              matcherVersion == context.matcherVersion
        else { return false }

        let age = age(at: now)
        guard age >= 0, age <= Self.timeToLive else { return false }

        guard let newest = newestAdvisoryModified else { return true }
        guard let recorded = advisoryModified else { return false }
        return newest <= recorded
    }
}

// MARK: - The revision ordinal

/// The identity of one published scan result.
///
/// Monotonic and persisted, so it survives a relaunch. Two guards use it for two
/// different jobs and they must not be confused: a *generation* kills a
/// superseded task, this ordinal kills a late-arriving older snapshot. Cache
/// reads are slow and a live scan sometimes is not, so without this a cache read
/// that started first and finished second would blank fresher results.
public struct SecurityScanRevision: Sendable, Hashable, Codable, Comparable {
    public let ordinal: Int

    public init(ordinal: Int) {
        self.ordinal = ordinal
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.ordinal < rhs.ordinal }

    /// The revision a live scan mints from this one.
    public func next() -> SecurityScanRevision { SecurityScanRevision(ordinal: ordinal + 1) }

    /// Whether a snapshot at this revision may replace one already adopted.
    ///
    /// **Strictly** greater. A duplicate joins the adoption already in flight
    /// rather than replacing it, and an older one returns without blanking
    /// anything — the `CatalogStore.adopt` contract.
    public func supersedes(_ adopted: SecurityScanRevision?) -> Bool {
        guard let adopted else { return true }
        return self > adopted
    }
}

// MARK: - The file

/// Everything the cache persists, in one file.
public struct AdvisoryCacheFile: Sendable, Hashable, Codable {
    /// Bumped whenever this file's shape changes. A file from another schema is
    /// treated exactly like a corrupt one: discarded, silently, because it is
    /// derived data.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    /// The ordinal the last published scan was minted at.
    ///
    /// Persisted **inside the file** rather than derived at launch, so
    /// monotonicity survives the process rather than restarting at zero every
    /// time the app opens.
    public let revisionOrdinal: Int
    public let entries: [AdvisoryCacheEntry]

    public init(
        schemaVersion: Int = AdvisoryCacheFile.currentSchemaVersion,
        revisionOrdinal: Int,
        entries: [AdvisoryCacheEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.revisionOrdinal = revisionOrdinal
        self.entries = entries
    }

    public var revision: SecurityScanRevision { SecurityScanRevision(ordinal: revisionOrdinal) }
}

// MARK: - Storage

public protocol AdvisoryCaching: Sendable {
    func load() async throws -> AdvisoryCacheFile?
    func save(_ file: AdvisoryCacheFile) async throws
}

/// One JSON file in `~/Library/Caches/`, behind an actor.
///
/// The `DiskUsageCache` shape verbatim, including the part that looks like
/// sloppiness and is not: `load()` never surfaces a failure. This file is
/// derived, re-fetchable data, so "the cache could not be read" and "there is no
/// cache" are the same situation and both degrade to a full scan. Giving callers
/// an error to handle would only invite one of them to handle it by showing the
/// user a scary message about a file they do not own.
///
/// The URL is injected rather than computed here, exactly as `diskCacheURL` is:
/// the app owns where its caches live.
public actor AdvisoryCache: AdvisoryCaching {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() async throws -> AdvisoryCacheFile? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(AdvisoryCacheFile.self, from: data),
              file.schemaVersion == AdvisoryCacheFile.currentSchemaVersion
        else { return nil }
        return file
    }

    public func save(_ file: AdvisoryCacheFile) async throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Atomic, so a crash mid-write leaves the previous cache intact rather
        // than a truncated file that `load()` would discard.
        try encoder.encode(file).write(to: fileURL, options: .atomic)
    }
}
