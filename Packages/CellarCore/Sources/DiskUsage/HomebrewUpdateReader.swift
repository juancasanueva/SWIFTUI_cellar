import Foundation

/// How old the local Homebrew checkout is.
///
/// Four typed cases, and **no invented date anywhere**. A placeholder, a
/// `Date.distantPast`, a zero date or a negative age would each let a non-answer
/// travel as if it were a measurement — and the one that matters most is
/// `futureDated`, which is deliberately *not* clamped to zero. Clamping would
/// render a wrong clock as a perfectly fresh installation, which is the most
/// flattering lie this reading could tell.
///
/// Absent, unreadable and future-dated reach every consumer as themselves,
/// including the health score, which treats each as **unanswered** rather than
/// as fresh or as stale.
public enum HomebrewLastUpdate: Sendable, Hashable {
    case read(Date)
    /// No checkout, or no fetch marker in it. Covers both "never fetched" and
    /// "not a git checkout".
    case absent
    /// The marker exists and its metadata could not be read.
    case unreadable
    /// The marker's date is later than the moment the reading was taken. Carries
    /// the offending date rather than a negative age.
    case futureDated(Date)

    /// The date an age may be derived from. `nil` for every non-answer —
    /// including `futureDated`, whose date is evidence of a problem rather than
    /// a measurement of freshness.
    public var date: Date? {
        if case .read(let date) = self { return date }
        return nil
    }

    /// The date a `futureDated` reading is complaining about.
    public var offendingDate: Date? {
        if case .futureDated(let date) = self { return date }
        return nil
    }

    /// Whether this reading answers the question at all.
    public var isAnswered: Bool { date != nil }

    /// How long ago the checkout last fetched. `nil` unless this is a `read`, so
    /// an age can never be derived from a non-answer.
    public func age(at now: Date) -> TimeInterval? {
        guard let date else { return nil }
        return now.timeIntervalSince(date)
    }
}

/// Finds the local Homebrew git checkout by **probing the filesystem**.
///
/// Never by invoking brew. `brew --repository` would answer correctly and would
/// also give Homebrew a chance to auto-update on the way, moving the very marker
/// this reading is about — so asking how old Homebrew is would be what made it
/// new (`system-health`, "The last-update reading costs no brew invocation").
///
/// Threat response — **filesystem path resolution**: the candidate list is a
/// closed two-element list, both entries derived from `HomebrewRoots.prefix`.
/// There is no user-supplied path, no environment read, and no symlink following
/// into an unknown root. A probe that does not resolve is not an error — it is
/// how the other installation shape is discovered.
///
/// Probe order, validated by U11 on both supported shapes:
///
/// 1. `<prefix>/Homebrew/.git` — the `/usr/local` shape PRD §3.9 supports, where
///    the repository is nested under the prefix;
/// 2. `<prefix>/.git` — the Apple Silicon shape, where `brew --repository`
///    equals the prefix.
///
/// The first probe that resolves wins, and the second is not read.
public enum HomebrewRepositoryLocator {
    /// The file Homebrew's own `auto-update.sh` stats to decide whether it is
    /// due for a fetch. U12 watched it move with a real auto-update in the same
    /// session as the API cache, which is what makes it the authoritative
    /// last-update artefact rather than a heuristic Cellar invented.
    public static let fetchMarkerName = "FETCH_HEAD"

    /// The two candidates, in probe order. Deliberately a function of the roots
    /// alone, so the closed list is readable in one place.
    static func candidates(for roots: HomebrewRoots) -> [URL] {
        [
            roots.prefix.appendingPathComponent("Homebrew", isDirectory: true)
                .appendingPathComponent(".git", isDirectory: true),
            roots.prefix.appendingPathComponent(".git", isDirectory: true)
        ]
    }

    /// The resolved checkout, or `nil` when neither shape is present.
    ///
    /// Resolution is by the marker: a `.git` directory with no `FETCH_HEAD` in
    /// it answers nothing this capability wants, so it is not a resolution.
    public static func repository(
        for roots: HomebrewRoots,
        access: any FileMetadataAccess
    ) -> URL? {
        for candidate in candidates(for: roots) {
            let marker = candidate.appendingPathComponent(fetchMarkerName)
            if case .absent = access.modificationDate(at: marker) { continue }
            return candidate
        }
        return nil
    }
}

/// Reads the fetch marker's modification date, and nothing else.
///
/// **It composes `HomebrewRoots` and widens nothing** (design HD4). Adding the
/// repository to `DiskRootsIdentity` was the obvious move and is the wrong one,
/// verified rather than assumed:
///
/// - `DiskRootsIdentity` is `Codable` with four non-optional stored properties
///   and is persisted verbatim as `DiskUsageSnapshot.roots`. A new non-optional
///   key makes every previously written cache file throw `keyNotFound` on load
///   rather than degrade to `nil`, because `DiskUsageCache.load()` throws on a
///   decode failure and returns `nil` only for a missing file or a schema
///   mismatch.
/// - Even on a successful decode, `CleanupParser.currentlyOnDiskBytes` gates on
///   `snapshot.roots == expectedRoots`. Widening the identity changes that `==`,
///   and the orphan byte attribution silently becomes `nil`.
///
/// So `HomebrewRoots`, `DiskRootsIdentity`, `DiskUsageSnapshot` and the cache are
/// all untouched, and this value reads what it needs from the roots it is handed.
public enum HomebrewUpdateReader {
    /// The reading. Never throws; every failure is one of the four cases.
    public static func lastUpdate(
        roots: HomebrewRoots,
        now: Date,
        access: any FileMetadataAccess
    ) -> HomebrewLastUpdate {
        guard let repository = HomebrewRepositoryLocator.repository(for: roots, access: access) else {
            return .absent
        }
        let marker = repository.appendingPathComponent(HomebrewRepositoryLocator.fetchMarkerName)

        switch access.modificationDate(at: marker) {
        case .absent:
            return .absent
        case .unreadable:
            return .unreadable
        case .read(let date):
            // Strictly later than `now`, so a marker written in the same instant
            // the reading was taken is an ordinary answer rather than a fault.
            return date > now ? .futureDated(date) : .read(date)
        }
    }
}
