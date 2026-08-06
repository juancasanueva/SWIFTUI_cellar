import Foundation
import Testing

@testable import Catalog

/// How `CatalogStore` takes a snapshot on: off the main actor, in order, and
/// exactly once however many ingresses deliver it.
///
/// `.serialized` because these tests hold two catalog-sized snapshots and their
/// indexes alive at once; split from `CatalogStoreTests` so neither file
/// outgrows the project's limits.
///
/// `.timeLimit` because three tests here poll or spin a watcher against a
/// condition another task must satisfy: a regression that stops satisfying it
/// should fail the run, not hang it. `TimeLimitTrait` only accepts whole
/// minutes — `.seconds(30)` traps at runtime.
@Suite("Catalog adoption", .serialized, .timeLimit(.minutes(1)))
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

    @Test("An older snapshot arriving after a newer one has installed is discarded")
    func anOlderSnapshotArrivingAfterANewerOneIsDiscarded() async throws {
        let harness = try SyncHarness()
        let store = CatalogStore(engine: harness.engine)
        // Materialization order is what mints the revision, so `older` is built
        // first and carries the lower ordinal. Nothing about this test is a race:
        // `newer` is fully installed before `older` is even offered, which is the
        // case arrival order alone cannot tell from a legitimate update.
        let older = Self.snapshot(of: 2, prefix: "old")
        let newer = Self.snapshot(of: 3, prefix: "new")

        await store.adopt(newer)
        #expect(store.packageCount == 3)

        await store.adopt(older)

        #expect(store.packageCount == 3, "the older snapshot was installed over the newer one")
        #expect(store.indexBuildCount == 1, "the discarded snapshot still cost an index build")
        store.query = "new"
        #expect(store.results.map(\.name).sorted() == ["new0", "new1", "new2"])
        store.query = "old"
        #expect(store.results.isEmpty, "the older snapshot's records are being served")
    }

    @Test("The adopted revision does not regress after discarding an older snapshot")
    func theAdoptedRevisionDoesNotRegressAfterDiscardingAnOlderSnapshot() async throws {
        let harness = try SyncHarness()
        let store = CatalogStore(engine: harness.engine)
        let older = Self.snapshot(of: 2, prefix: "old")
        let newer = Self.snapshot(of: 3, prefix: "new")

        await store.adopt(newer)
        await store.adopt(older)
        // The re-delivery every ingress produces: if the discarded snapshot had
        // overwritten the adopted-revision record, this would look like new
        // content and rebuild.
        await store.adopt(newer)

        #expect(store.adoptionRequestCount == 3)
        #expect(store.indexBuildCount == 1, "the discarded snapshot disarmed the newer one's dedup")
        #expect(store.packageCount == 3)
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

    // MARK: - Discover lands with the index (PD-R6)

    @Test("Discover content is installed in the same assignment as the index")
    func discoverIsInstalledAlongsideTheIndex() async throws {
        let harness = try SyncHarness()
        let store = CatalogStore(engine: harness.engine)

        // Before any adoption: awaiting the catalog, and explicitly not a
        // failure or a pending spinner.
        #expect(store.discover == .empty)
        #expect(store.discover.topFormulae.isAwaitingCatalog)

        let watcher = Task { @MainActor in
            // Every observed moment must agree: an index of N records beside a
            // Discover projection built from a *different* snapshot is the state
            // this assertion exists to exclude.
            var straddled = false
            for _ in 0..<400 {
                let count = store.packageCount
                let ranked = store.discover.topFormulae.count
                if count > 0, ranked == 0 { straddled = true }
                await Task.yield()
            }
            return straddled
        }
        await Task.yield()

        await store.adopt(Self.rankedSnapshot(of: 60))
        let straddled = await watcher.value

        #expect(store.packageCount == 60)
        // Fifty rungs from sixty eligible records: the projection really ran.
        #expect(store.discover.topFormulae.count == 50)
        #expect(
            straddled == false,
            "an observer saw a fresh index beside a stale Discover projection"
        )
    }

    @Test("A duplicate or older revision costs no second Discover projection")
    func duplicateRevisionDoesNotReproject() async throws {
        let harness = try SyncHarness()
        let store = CatalogStore(engine: harness.engine)
        let snapshot = Self.rankedSnapshot(of: 10)

        await store.adopt(snapshot)
        let afterFirst = store.discover
        let buildsAfterFirst = store.indexBuildCount

        // The same materialization, delivered twice — a manual refresh and the
        // event stream both claim it. One materialization, one projection.
        await store.adopt(snapshot)

        #expect(store.indexBuildCount == buildsAfterFirst)
        #expect(store.discover == afterFirst)
        #expect(store.discover.topFormulae.count == 10)
    }

    /// A snapshot whose records are all eligible for the formula ladder.
    static func rankedSnapshot(of count: Int) -> CatalogSnapshot {
        CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            skippedRecordCount: 0,
            packages: (0..<count).map {
                CatalogPackage.stub(
                    kind: .formula,
                    name: String(format: "pkg%03d", $0),
                    installCount365d: $0 * 10
                )
            }
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
