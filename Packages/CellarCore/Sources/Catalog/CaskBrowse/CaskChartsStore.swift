import Foundation
import Observation

// MARK: - Schema

/// This cache's own schema version.
///
/// Deliberately not the catalog's constant — the `ReleaseNotesSchema` rule,
/// restated: a file whose recorded version does not match is discarded whole,
/// and sharing the catalog's version would wipe every cached ranking for a
/// package-field change that has nothing to do with them.
public enum CaskChartsSchema {
    public static let currentVersion = 1
}

// MARK: - The file

/// One cached window: the counts and when they were fetched.
struct CaskChartsCacheEntry: Codable, Sendable, Hashable {
    let counts: [String: Int]
    let fetchedAt: Date
}

/// Everything the store persists: `cask-charts-v1.json`.
///
/// Entries are keyed by `CaskChartsPeriod.rawValue` — string keys, so `Codable`
/// writes a real JSON object — and adopted tolerantly: a key this build does
/// not recognise is skipped, not an error.
struct CaskChartsCacheFile: Codable, Sendable, Hashable {
    let schemaVersion: Int
    let entries: [String: CaskChartsCacheEntry]
}

// MARK: - The store

/// Per-period Top Charts rankings, fetched lazily and cached twice: in memory
/// for the session, on disk for an hour.
///
/// The CaskHub port's exact selection logic: an already-cached period commits
/// immediately; 365d commits with no fetch at all, because the catalog carries
/// every annual count on the packages; a failed fetch commits a fallback the
/// user already has data for; and a request-ID guard drops a stale response
/// whole when the user switches periods faster than the network answers.
@MainActor
@Observable
public final class CaskChartsStore {
    /// One hour. A ranking is a fast-moving aggregate the origin re-publishes
    /// continuously, so a day-old chart would be a stale answer served as a
    /// fresh one — and an hour still makes a relaunch free.
    public static let timeToLive: TimeInterval = 3_600
    public static let cacheFileName = "cask-charts-v1.json"

    /// The fetched windows only — `days365` never appears here, because it
    /// lives on the packages themselves.
    public private(set) var countsByPeriod: [CaskChartsPeriod: [String: Int]] = [:]
    /// The committed selection. Only ever moved to a period that can actually
    /// be rendered: one with counts behind it, or the annual window.
    public private(set) var period: CaskChartsPeriod = .days365
    public private(set) var isLoading = false

    private let source: any CaskChartsSource
    private let directory: URL
    /// This instance's cache file. Parameterized so the formula charts store
    /// keeps its windows beside — never on top of — the cask ones.
    private let cacheFileName: String
    private let now: @Sendable () -> Date
    private var fetchedAt: [CaskChartsPeriod: Date] = [:]
    private var hasLoadedCache = false
    /// The one selection allowed to commit. A newer `select` overwrites it, so
    /// an older response finds itself unrecognised and drops.
    private var activeRequest: UUID?

    /// The directory is injected — the app owns where its caches live, and a
    /// test owns a temporary one. So is the clock, because TTL claims are
    /// claims about time.
    public init(
        source: any CaskChartsSource,
        directory: URL,
        cacheFileName: String = CaskChartsStore.cacheFileName,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.directory = directory
        self.cacheFileName = cacheFileName
        self.now = now
    }

    public func select(_ requested: CaskChartsPeriod) async {
        loadCacheIfNeeded()

        // The annual window ships on every package; committing it is a rename,
        // not a fetch. An in-flight fetch for another period is superseded.
        if requested == .days365 {
            commit(requested)
            return
        }
        if countsByPeriod[requested] != nil {
            commit(requested)
            return
        }

        let request = UUID()
        activeRequest = request
        isLoading = true
        do {
            let counts = try await source.fetchCounts(period: requested)
            // A newer selection owns the page now: a stale response is dropped
            // whole — neither stored nor committed — rather than raced in.
            guard activeRequest == request else { return }
            countsByPeriod[requested] = counts
            fetchedAt[requested] = now()
            commit(requested)
            persist()
        } catch {
            guard activeRequest == request else { return }
            // The current period if it still has data behind it, else the one
            // window that never needs a fetch.
            commit(period == .days365 || countsByPeriod[period] != nil ? period : .days365)
        }
    }

    private func commit(_ committed: CaskChartsPeriod) {
        period = committed
        activeRequest = nil
        isLoading = false
    }

    // MARK: - Disk cache

    private var fileURL: URL { directory.appendingPathComponent(cacheFileName) }

    /// Loaded lazily on the first selection, so a launch that never opens Top
    /// Charts never reads the file.
    ///
    /// `nil` for every reason there could be not to have a cache — missing,
    /// unreadable, byte-corrupt, or written by another schema — and never an
    /// error: this is derived, re-fetchable data (the `ReleaseNotesCache`
    /// contract). A stale entry is a **miss**: adopting it and refreshing
    /// later would render an hour-old chart as the selected one.
    private func loadCacheIfNeeded() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? Self.decoder.decode(CaskChartsCacheFile.self, from: data),
              file.schemaVersion == CaskChartsSchema.currentVersion
        else { return }

        let loadedAt = now()
        for (rawPeriod, entry) in file.entries {
            guard let cached = CaskChartsPeriod(rawValue: rawPeriod), cached != .days365 else {
                continue
            }
            // An entry stamped in the future is rejected outright — a clock
            // that moved backwards makes every age meaningless.
            let age = loadedAt.timeIntervalSince(entry.fetchedAt)
            guard age >= 0, age <= Self.timeToLive else { continue }
            countsByPeriod[cached] = entry.counts
            fetchedAt[cached] = entry.fetchedAt
        }
    }

    /// Atomic, and `try?` throughout: a cache that fails to write costs one
    /// refetch next launch, which is not worth a user-facing error.
    private func persist() {
        var entries: [String: CaskChartsCacheEntry] = [:]
        for (cached, counts) in countsByPeriod {
            guard let stamp = fetchedAt[cached] else { continue }
            entries[cached.rawValue] = CaskChartsCacheEntry(counts: counts, fetchedAt: stamp)
        }
        guard let data = try? Self.encoder.encode(
            CaskChartsCacheFile(schemaVersion: CaskChartsSchema.currentVersion, entries: entries)
        ) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
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
