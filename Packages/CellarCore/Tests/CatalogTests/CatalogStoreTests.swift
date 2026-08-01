import Foundation
import Testing

@testable import Catalog

@Suite("Catalog store")
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
