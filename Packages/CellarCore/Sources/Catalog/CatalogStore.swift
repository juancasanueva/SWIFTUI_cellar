import Foundation
import Observation

/// The catalog as the UI sees it: a searchable result list and a sync status.
///
/// The single main-isolated crossing point in this module. Everything below it —
/// acquisition, decoding, index building — runs in SwiftPM's default
/// `nonisolated` world, so the isolation boundary is explicit and one file wide
/// (design D1).
@MainActor
@Observable
public final class CatalogStore {
    /// The current result list for `query` under `filters`.
    public private(set) var results: [CatalogPackage] = []
    /// The most recent sync status.
    ///
    /// Named for its type: the design draft called it `syncState`, but the spec
    /// settled the enumeration's name as `CatalogSyncStatus` and one vocabulary
    /// is worth more than two.
    public private(set) var syncStatus: CatalogSyncStatus = .idle
    /// How many packages the loaded snapshot holds, regardless of the query.
    public private(set) var packageCount = 0
    /// Whether the store can answer queries at all.
    ///
    /// Becomes true as soon as the cache has been consulted — with or without a
    /// hit. "Ready" means answering, not populated (catalog-sync CS8).
    public private(set) var isReady = false

    /// The as-you-type query. Reranks on assignment.
    public var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            rerank()
        }
    }

    /// The active filters. Rerank on assignment.
    public var filters: SearchFilters = SearchFilters() {
        didSet {
            guard filters != oldValue else { return }
            rerank()
        }
    }

    @ObservationIgnored private let engine: CatalogSyncEngine
    @ObservationIgnored private let resultLimit: Int
    @ObservationIgnored private var index = PackageSearchIndex()
    @ObservationIgnored private var isRunning = false

    public init(engine: CatalogSyncEngine, resultLimit: Int = 200) {
        self.engine = engine
        self.resultLimit = resultLimit
    }

    /// The store wired to the app's on-disk catalog directory and the live API.
    public convenience init(
        directory: URL,
        source: any CatalogSource = HTTPCatalogSource(),
        policy: CatalogRefreshPolicy = CatalogRefreshPolicy()
    ) {
        self.init(
            engine: CatalogSyncEngine(
                store: CatalogFileStore(directory: directory),
                source: source,
                policy: policy
            )
        )
    }

    /// The default on-disk location: `Application Support/<bundle id>/Catalog`.
    public static func defaultDirectory(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.juancasanueva.cellar"
    ) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Catalog", isDirectory: true)
    }

    // MARK: - Lifecycle

    /// Adopts the cached snapshot, then runs the refresh schedule until
    /// cancelled.
    ///
    /// Long-lived on purpose: driven from `.task { await catalog.start() }`, so
    /// SwiftUI's structured cancellation tears down both the event observer and
    /// the refresh loop when the scene goes away — no `deinit` bookkeeping, no
    /// detached task outliving its window.
    public func start() async {
        // The engine's event stream supports exactly one iterator; a second
        // window's `.task` must not start a second one (or a second refresh
        // loop). The first caller owns both until its scene is torn down.
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        await loadCache()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [engine] in
                for await event in engine.events {
                    await self.handle(event)
                }
            }
            group.addTask { [engine] in
                await engine.runRefreshLoop()
            }
        }
    }

    /// Reads whatever is on disk and starts answering queries.
    public func loadCache() async {
        if let snapshot = await engine.cachedSnapshot() {
            adopt(snapshot)
        }
        isReady = true
    }

    /// Runs a sync now, joining one already in flight.
    ///
    /// Single-flight all the way down, mirroring `BrewDetectionStore.refresh()`:
    /// a toolbar button and a window activation can fire together, and the user
    /// wants one refresh, not two (catalog-sync CS7).
    public func refreshNow() async {
        let result = await engine.sync()
        if case .success(let snapshot) = result {
            adopt(snapshot)
        }
        syncStatus = await engine.status
    }

    // MARK: - Queries

    public func package(_ id: PackageID) -> CatalogPackage? {
        index.package(id)
    }

    private func handle(_ event: CatalogSyncEvent) {
        switch event {
        case .status(let status): syncStatus = status
        case .snapshot(let snapshot): adopt(snapshot)
        }
    }

    private func adopt(_ snapshot: CatalogSnapshot) {
        index = PackageSearchIndex(snapshot: snapshot)
        packageCount = index.recordCount
        rerank()
    }

    /// Recomputes the result list on the main actor, synchronously.
    ///
    /// The measured p95 (1.02 ms against an 8 ms ceiling) is what licenses this:
    /// an async hop would cost more than the search does, and it would introduce
    /// out-of-order as-you-type results and per-keystroke cancellation logic to
    /// solve a problem that does not exist (design D4).
    private func rerank() {
        let hits = index.search(query, filters: filters, limit: resultLimit)
        results = hits.compactMap { index.package($0.id) }
    }
}
