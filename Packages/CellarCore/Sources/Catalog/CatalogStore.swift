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
    /// What Discover renders for the adopted snapshot.
    ///
    /// One `private(set)` property rather than a second store: the engine's
    /// event stream supports exactly one iterator, so a second `@Observable`
    /// could not observe snapshots, and one fed by this store would be
    /// indirection with no boundary. All the logic stays in nonisolated pure
    /// `Catalog` types — this class gains a value, not behaviour.
    public private(set) var discover: DiscoverContent = .empty
    /// What the cask browse page renders for the adopted snapshot.
    ///
    /// Built beside `discover` in the same adoption, installed in the same
    /// main-actor turn: an observer must never see a fresh index next to a
    /// stale browse page, for exactly the reason `discover` states.
    public private(set) var caskBrowse: CaskBrowseContent = .empty
    /// What the formula browse pages render — the same contract as
    /// `caskBrowse`, for the other kind.
    public private(set) var formulaBrowse: FormulaBrowseContent = .empty

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
    /// The shipped curated resource, decoded at most once per launch.
    @ObservationIgnored private var loadedCuratedList: CuratedDiscoveryList?
    /// The vendored CaskHub resources, decoded at most once per launch.
    ///
    /// ~920 KB of JSON between them, so they load lazily on the first
    /// adoption's `@concurrent` build path — never on the launch path — and
    /// then stay cached: the bundle cannot change while the app is running.
    @ObservationIgnored private var loadedCaskCategoryCatalog: CaskCategoryCatalog?
    @ObservationIgnored private var loadedCaskAddedDates: CaskAddedDates?
    @ObservationIgnored private var isRunning = false
    /// Stamped before each adoption's build; only an ordinal still ahead of
    /// `installedSequence` may install.
    @ObservationIgnored private var adoptionSequence = 0
    @ObservationIgnored private var installedSequence = 0
    /// The newest snapshot identity this store has taken responsibility for, and
    /// the adoption a duplicate delivery of it should wait on.
    @ObservationIgnored private var adoptedRevision: CatalogSnapshotRevision?
    @ObservationIgnored private var adoptionInFlight: Task<Void, Never>?

    /// How many adoptions were requested, and how many actually built an index.
    ///
    /// Internal instrumentation: "one snapshot, one index" is not observable
    /// from the outside — a duplicate build produces exactly the same results,
    /// just after another 30 ms of CPU.
    @ObservationIgnored private(set) var adoptionRequestCount = 0
    @ObservationIgnored private(set) var indexBuildCount = 0

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
            await adopt(snapshot)
        }
        // Still after the adoption: a cold launch with a usable cache shows
        // results rather than flashing an empty state and repopulating.
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
            await adopt(snapshot)
        }
        syncStatus = await engine.status
    }

    // MARK: - Queries

    public func package(_ id: PackageID) -> CatalogPackage? {
        index.package(id)
    }

    private func handle(_ event: CatalogSyncEvent) async {
        switch event {
        case .status(let status): syncStatus = status
        case .snapshot(let snapshot): await adopt(snapshot)
        }
    }

    /// Installs a snapshot's index, building it off the main actor.
    ///
    /// Internal rather than private because the guarantees worth testing here —
    /// the main actor stays free, queries never blank, a late older build is
    /// discarded — are all statements about `adopt` itself.
    func adopt(_ snapshot: CatalogSnapshot) async {
        adoptionRequestCount += 1

        // Only a strictly newer materialization may install. "Newer" is the
        // snapshot's own revision ordinal, minted when it was materialized —
        // never the order `adopt` happened to be called, which would let an
        // older snapshot entering after a newer one has installed win
        // (catalog-sync, design D1).
        //
        // Equal ordinal is the duplicate case and keeps its existing contract:
        // the same snapshot arrives through `refreshNow()` and through the sync
        // event stream, and a 304 poll re-emits the file already on disk. All of
        // those are one materialization and must cost one index, not two. The
        // duplicate *joins* rather than returns: a manual refresh has to come
        // back with its snapshot queryable, whichever ingress claimed it.
        //
        // Claimed before any suspension, so a concurrent duplicate cannot slip
        // past. An older snapshot leaves through the same door, which is what
        // makes the assignment below unreachable for it — the adopted-revision
        // record cannot regress and disarm the newer snapshot's deduplication.
        // Ordinals start at 1, so `0` stands for "nothing adopted yet".
        guard snapshot.revision.ordinal > (adoptedRevision?.ordinal ?? 0) else {
            await adoptionInFlight?.value
            return
        }
        adoptedRevision = snapshot.revision

        adoptionSequence += 1
        let ordinal = adoptionSequence
        indexBuildCount += 1

        let adoption = Task { [weak self] in
            let built = await PackageSearchIndex.build(from: snapshot)
            guard let self else { return }
            // Every await happens *before* the ordinal guard, so installing is a
            // single uninterrupted main-actor turn. Awaiting between the guard
            // and the assignments would reopen exactly the window this design
            // closes: an observer seeing a fresh index beside a stale Discover.
            let curated = await curatedList()
            let arrivals = await engine.arrivals()
            let projected = await DiscoverProjection.build(
                snapshot: snapshot,
                curated: curated,
                arrivals: arrivals,
                now: await engine.now
            )
            let browse = await CaskBrowseProjection.build(
                snapshot: snapshot,
                catalog: await caskCategoryCatalog(),
                addedDates: await caskAddedDates(),
                now: await engine.now
            )
            let formulaContent = await FormulaBrowseProjection.build(snapshot: snapshot)
            // Builds can finish out of order — a 16k snapshot overtaken by a
            // small one. The newer catalog wins, so a stale ordinal is discarded
            // here rather than installed on top of fresher data (design D1).
            guard ordinal > installedSequence else { return }
            installedSequence = ordinal
            // One main-actor assignment, after the build: there is no window in
            // which the store is between indexes.
            index = built
            packageCount = built.recordCount
            discover = projected
            caskBrowse = browse
            formulaBrowse = formulaContent
            rerank()
        }
        adoptionInFlight = adoption

        await adoption.value

        if adoptionInFlight == adoption { adoptionInFlight = nil }
    }

    /// The shipped curated list, decoded once per launch.
    ///
    /// Cached because the resource cannot change while the app is running, and
    /// a re-decode per adoption would be pure waste. A resource that fails to
    /// load is `nil` and stays `nil` for this launch: the curated section then
    /// reports its own named empty state, which is a designed outcome rather
    /// than a crash.
    private func curatedList() async -> CuratedDiscoveryList? {
        if let loadedCuratedList { return loadedCuratedList }
        let loaded = try? await CuratedDiscoveryList.shipped()
        loadedCuratedList = loaded
        return loaded
    }

    /// The vendored category catalog, decoded once per launch — same contract
    /// as `curatedList()`: a resource that fails to load leaves the browse
    /// page without category shelves, which is a designed outcome.
    private func caskCategoryCatalog() async -> CaskCategoryCatalog? {
        if let loadedCaskCategoryCatalog { return loadedCaskCategoryCatalog }
        let loaded = await CaskCategoryCatalog.shipped()
        loadedCaskCategoryCatalog = loaded
        return loaded
    }

    /// The vendored added dates, decoded once per launch. Absent data means
    /// "nothing is recent", never an error — the projection's own rule.
    private func caskAddedDates() async -> CaskAddedDates? {
        if let loadedCaskAddedDates { return loadedCaskAddedDates }
        let loaded = await CaskAddedDates.shipped()
        loadedCaskAddedDates = loaded
        return loaded
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
