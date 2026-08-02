import Foundation
import Testing

@testable import Catalog

/// How `CatalogStore` takes a snapshot on: off the main actor, in order, and
/// exactly once however many ingresses deliver it.
///
/// `.serialized` because these tests hold two catalog-sized snapshots and their
/// indexes alive at once; split from `CatalogStoreTests` so neither file
/// outgrows the project's limits.
@Suite("Catalog adoption", .serialized)
@MainActor
struct CatalogAdoptionTests {
    // MARK: - Off-main, ordered, single adoption (CSA1)

    @Test("Adopting a 15,500-record snapshot leaves the main actor free", .heavyFixture)
    func adoptionDoesNotBlockTheMainActor() async throws {
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

    @Test("Every query issued during an adoption is answered from the last good index", .heavyFixture)
    func queriesNeverBlankWhileASnapshotIsAdopted() async throws {
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

    @Test("A late adoption of an older snapshot is discarded, not installed", .heavyFixture)
    func lateOlderAdoptionIsDiscarded() async throws {
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

    @Test("A poisoned snapshot on disk launches as an ordinary cold start")
    func poisonedSnapshotLaunchesAsAColdStart() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()
        try harness.poisonSnapshot()
        harness.source.script(.payload(Payload.formulae(["wget", "curl"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        // Past the shelf life, so the launch actually refreshes.
        harness.time.advance(by: 90_000)

        // Each engine is a fresh one over the same directory: this is a *launch*,
        // so it must not inherit the buffered events of the sync that set the
        // fixture up.
        //
        // The load is exercised on its own first, with no refresh loop racing
        // it, so "the poisoned snapshot was not served" is an observation rather
        // than a coin flip.
        let loading = CatalogStore(engine: harness.freshEngine())
        await loading.loadCache()
        #expect(loading.isReady)
        #expect(loading.packageCount == 0)
        #expect(loading.results.isEmpty)
        #expect(loading.syncStatus == .idle, "the discarded snapshot was reported")

        let store = CatalogStore(engine: harness.freshEngine())
        let statuses = Recorder()
        let running = Task { await store.start() }
        defer { running.cancel() }
        let watcher = Task { @MainActor in
            var last = store.syncStatus
            statuses.record("\(last)")
            while store.results.isEmpty {
                if store.syncStatus != last {
                    last = store.syncStatus
                    statuses.record("\(last)")
                }
                await Task.yield()
            }
        }

        await poll { store.results.count == 3 }
        await watcher.value

        #expect(store.results.map(\.name).sorted() == ["curl", "iterm2", "wget"])
        // Silent, per Q1: the ordinary progression, never a failure raised for
        // the snapshot that was thrown away.
        #expect(
            statuses.labels.contains { $0.hasPrefix("failed") } == false,
            "cold launch over a poisoned snapshot reported \(statuses.labels)"
        )
    }

    /// Bounded polling that stays on the main actor, so the condition can read
    /// main-isolated state.
    func poll(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

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
}
