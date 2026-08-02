import Foundation
import Testing

@testable import Catalog

/// `.serialized` because several of these tests hold two ~15,000-record
/// snapshots and their indexes alive at once. Run in parallel they add tens of
/// megabytes of unrelated resident memory to whatever else is running, which
/// `CatalogMemoryTests` measures as process footprint.
@Suite("Catalog store", .serialized)
@MainActor
struct CatalogStoreTests {
    // MARK: - Start-up (CS8)

    @Test("start() adopts the cached snapshot before any network work")
    func startAdoptsTheCache() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()
        harness.source.script(.notModified, for: .formulae)
        harness.source.script(.notModified, for: .casks)

        let store = CatalogStore(engine: harness.engine)
        #expect(store.isReady == false)
        #expect(store.results.isEmpty)

        let running = Task { await store.start() }
        defer { running.cancel() }
        await poll { store.isReady }

        #expect(store.results.map(\.name).sorted() == ["iterm2", "wget"])
        #expect(store.package(PackageID(kind: .cask, name: "iterm2"))?.displayName == "Iterm2")
    }

    @Test("A second start() is a no-op while the first is running")
    func secondStartDoesNotDoubleConsume() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        let store = CatalogStore(engine: harness.engine)
        let first = Task { await store.start() }
        defer { first.cancel() }
        await poll { store.isReady }

        // A second window's `.task` calls start() again. The engine's event
        // stream has exactly one iterator, so this must return without starting
        // a second consumer or refresh loop — not trap.
        await store.start()

        #expect(store.isReady)
        // Only the first start's refresh loop ran: each payload was asked for
        // exactly once. Poll on the casks count — the LATER of the two
        // sequential fetches — so both requests have happened before asserting.
        await poll { harness.source.requests(for: .casks).count == 1 }
        #expect(harness.source.requests(for: .formulae).count == 1)
        #expect(harness.source.requests(for: .casks).count == 1)
    }

    @Test("A cold launch is ready immediately with zero results and a live status")
    func coldLaunchIsNonBlocking() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.onFetch { try? await Task.sleep(for: .milliseconds(40)) }

        let store = CatalogStore(engine: harness.engine)
        let running = Task { await store.start() }
        defer { running.cancel() }

        await poll { store.isReady }
        // Ready means "answering", not "populated": there is simply nothing yet.
        #expect(store.results.isEmpty)

        await poll { store.syncStatus != .idle }
        let duringSync = store.syncStatus
        #expect(
            duringSync == .downloading(fractionCompleted: nil) || duringSync == .decoding,
            "expected a live download/decode status, got \(duringSync)"
        )

        await poll { store.results.isEmpty == false }
        #expect(store.results.map(\.name).sorted() == ["iterm2", "wget"])
        // The engine yields `.snapshot` before `.succeeded`, and adoption is now
        // an `await` (defect #1), so results land one or more turns ahead of the
        // status. Same assertion, polled rather than read instantly.
        await poll { if case .succeeded = store.syncStatus { true } else { false } }
        guard case .succeeded = store.syncStatus else {
            Issue.record("expected succeeded, got \(store.syncStatus)")
            return
        }
    }

    @Test("A failed first sync publishes the failure and keeps answering")
    func failedFirstSyncIsPublished() async throws {
        let harness = try SyncHarness()
        harness.source.script(.failure(.offline), for: .formulae)

        let store = CatalogStore(engine: harness.engine)
        let running = Task { await store.start() }
        defer { running.cancel() }

        await poll { store.syncStatus == .failed(.offline) }

        #expect(store.results.isEmpty)
        #expect(store.isReady)
    }

    @Test("A sync that lands while the store is running replaces the results")
    func laterSyncReplacesResults() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()

        let store = CatalogStore(engine: harness.engine)
        let running = Task { await store.start() }
        defer { running.cancel() }
        await poll { store.results.count == 2 }

        harness.source.script(.payload(Payload.formulae(["wget", "curl"])), for: .formulae)
        harness.source.script(.notModified, for: .casks)
        await store.refreshNow()

        #expect(store.results.map(\.name).sorted() == ["curl", "iterm2", "wget"])
    }

    @Test("The store reports how many packages are indexed, not how many match")
    func packageCountIsTheWholeCatalog() async throws {
        let store = try await Self.populated()

        #expect(store.packageCount == 4)

        store.query = "wget"

        #expect(store.results.count == 1)
        #expect(store.packageCount == 4)
    }

    @Test("An empty store reports zero indexed packages")
    func emptyStoreReportsZero() async throws {
        let harness = try SyncHarness()
        let store = CatalogStore(engine: harness.engine)

        await store.loadCache()

        #expect(store.packageCount == 0)
        #expect(store.isReady)
    }

    // MARK: - Off-main, ordered, single adoption (CSA1)

    @Test("Adopting a 15,500-record snapshot leaves the main actor free")
    func adoptionDoesNotBlockTheMainActor() async throws {
        try await HeavyFixtureLock.exclusive {
            let harness = try SyncHarness()
            let store = CatalogStore(engine: harness.engine)
            let snapshot = Self.snapshot(of: SearchIndexTests.realisticRecordCount, prefix: "pkg")
            let finished = Flag()
            let turns = Counter()

            let ticker = Task { @MainActor in
                while !finished.isSet {
                    await Task.yield()
                    turns.increment()
                }
            }
            await Task.yield()

            let before = turns.value
            await store.adopt(snapshot)
            let during = turns.value - before
            finished.set()
            await ticker.value

            #expect(store.packageCount == SearchIndexTests.realisticRecordCount)
            // Zero under M1's synchronous main-actor build: it holds the actor from
            // the moment adoption starts. A regression test, not a timing one.
            #expect(during > 0, "no main-actor turn completed while the snapshot was adopted")
        }
    }

    @Test("Every query issued during an adoption is answered from the last good index")
    func queriesNeverBlankWhileASnapshotIsAdopted() async throws {
        try await HeavyFixtureLock.exclusive {
            let harness = try SyncHarness()
            let store = CatalogStore(engine: harness.engine)
            // Both snapshots share a name space, so "the results went empty" can
            // only mean the swap blanked them — never that the query stopped
            // matching.
            await store.adopt(Self.snapshot(of: 15_000, prefix: "pkg"))
            store.query = "pkg"
            #expect(store.results.isEmpty == false)

            let finished = Flag()
            let sawEmpty = Flag()
            let answered = Counter()

            // Keystrokes for the whole duration of the adoption below.
            let typist = Task { @MainActor in
                var toggle = false
                while !finished.isSet {
                    toggle.toggle()
                    store.query = toggle ? "pkg1" : "pkg2"
                    if store.results.isEmpty { sawEmpty.set() }
                    answered.increment()
                    await Task.yield()
                }
            }
            await Task.yield()

            let before = answered.value
            await store.adopt(Self.snapshot(of: 6_000, prefix: "pkg"))
            let during = answered.value - before
            finished.set()
            await typist.value

            #expect(during > 0, "no query was issued while the adoption was in progress")
            #expect(sawEmpty.isSet == false, "a query observed an empty result set caused by the swap")

            store.query = "pkg"
            #expect(store.results.isEmpty == false)
            #expect(store.packageCount == 6_000)
        }
    }

    @Test("A late adoption of an older snapshot is discarded, not installed")
    func lateOlderAdoptionIsDiscarded() async throws {
        try await HeavyFixtureLock.exclusive {
            let harness = try SyncHarness()
            let store = CatalogStore(engine: harness.engine)
            // `older` is 15,500 records and `newer` is 3, so the newer build lands
            // first and the older one arrives afterwards with a stale ordinal.
            let older = Self.snapshot(of: 8_000, prefix: "old")
            let newer = Self.snapshot(of: 3, prefix: "new")

            let first = Task { await store.adopt(older) }
            let second = Task { await store.adopt(newer) }
            await second.value
            await first.value

            #expect(store.packageCount == 3)
            store.query = "new"
            #expect(store.results.map(\.name).sorted() == ["new0", "new1", "new2"])
            store.query = "old"
            #expect(store.results.isEmpty, "the discarded older build was installed after all")
        }
    }

    @Test("A manual refresh with the event stream running builds one index for its snapshot")
    func refreshNowAdoptsItsSnapshotExactlyOnce() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        let store = CatalogStore(engine: harness.engine)
        let running = Task { await store.start() }
        defer { running.cancel() }
        await poll { store.isReady }
        // The refresh loop's own first sync has to land before its successor is
        // scripted, or `refreshNow()` joins it instead of running a new one.
        await poll { store.results.count == 2 }

        let buildsBefore = store.indexBuildCount
        let requestsBefore = store.adoptionRequestCount

        harness.source.script(.payload(Payload.formulae(["wget", "curl"])), for: .formulae)
        harness.source.script(.notModified, for: .casks)
        await store.refreshNow()
        // Let the `.snapshot` event reach the observer too.
        await Self.settle()

        // Both ingresses delivered the snapshot...
        #expect(store.adoptionRequestCount == requestsBefore + 2)
        // ...and exactly one of them built an index for it.
        #expect(store.indexBuildCount == buildsBefore + 1)
        #expect(store.packageCount == 3)
        #expect(store.results.map(\.name).sorted() == ["curl", "iterm2", "wget"])
    }

    // MARK: - Reranking (D4)

    @Test("Setting the query reranks synchronously, with no await in between")
    func queryReranksSynchronously() async throws {
        let store = try await Self.populated()

        store.query = "wget"

        // No `await` between the assignment and the assertion: if reranking
        // hopped off the main actor this would still show the old results.
        #expect(store.results.map(\.name) == ["wget"])

        store.query = "docker"
        #expect(store.results.map(\.name) == ["docker", "docker"])
    }

    @Test("Rapid successive queries leave the last one showing")
    func rapidQueriesDoNotArriveOutOfOrder() async throws {
        let store = try await Self.populated()

        store.query = "w"
        store.query = "wg"
        store.query = "wget"

        #expect(store.results.map(\.name) == ["wget"])
        #expect(store.query == "wget")
    }

    @Test("Setting the filters reranks synchronously")
    func filtersRerankSynchronously() async throws {
        let store = try await Self.populated()
        store.query = "docker"
        #expect(store.results.count == 2)

        store.filters.kinds = [.cask]

        #expect(store.results.map(\.kind) == [.cask])
    }

    @Test("Assigning an unchanged query does not disturb the results")
    func unchangedQueryIsANoOp() async throws {
        let store = try await Self.populated()
        store.query = "wget"
        let before = store.results

        store.query = "wget"

        #expect(store.results == before)
    }

    // MARK: - Manual refresh (CS7)

    @Test("A second refreshNow() joins the sync already in flight")
    func refreshNowIsSingleFlight() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()
        let before = harness.source.requests(for: .formulae).count
        harness.source.onFetch { try? await Task.sleep(for: .milliseconds(60)) }

        let store = CatalogStore(engine: harness.engine)
        let first = Task { await store.refreshNow() }
        await poll { harness.source.requests(for: .formulae).count == before + 1 }
        let second = Task { await store.refreshNow() }

        await first.value
        await second.value

        #expect(harness.source.requests(for: .formulae).count == before + 1)
    }

    // MARK: - Helpers

    /// Lets every pending main-actor continuation run.
    static func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    /// A snapshot of `count` distinctly named records.
    static func snapshot(of count: Int, prefix: String) -> CatalogSnapshot {
        CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            skippedRecordCount: 0,
            packages: (0..<count).map {
                CatalogPackage.stub(kind: .formula, name: "\(prefix)\($0)")
            }
        )
    }

    /// A started store holding a small, known catalog.
    static func populated() async throws -> CatalogStore {
        let harness = try SyncHarness()
        harness.source.script(
            .payload(Payload.formulae(["wget", "docker", "curl"])),
            for: .formulae
        )
        harness.source.script(.payload(Payload.casks(["docker"])), for: .casks)
        _ = await harness.engine.sync()

        let store = CatalogStore(engine: harness.engine)
        await store.loadCache()
        return store
    }

    /// Bounded polling that stays on the main actor, so the condition can read
    /// main-isolated state.
    func poll(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

extension CatalogStoreTests {
    static func poll(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
