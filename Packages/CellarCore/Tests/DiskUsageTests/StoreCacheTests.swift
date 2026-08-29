import Catalog
import BrewProcess
import Foundation
import Synchronization
import Testing

@testable import DiskUsage

@MainActor
@Suite("Disk usage cache and store")
struct StoreCacheTests {
    @Test("A complete matching cache is adopted stale and mismatched roots are ignored")
    func cacheAdoptionMatchesRoots() async throws {
        let cache = MemoryDiskUsageCache()
        let roots = identity("a")
        let cached = snapshot(roots: roots, bytes: 10)
        try await cache.save(cached)
        let store = DiskUsageStore(cache: cache)

        await store.loadCached(for: roots)
        #expect(store.visibleSnapshot == cached)
        #expect(store.isStale)

        await store.loadCached(for: identity("other"))
        #expect(store.visibleSnapshot == nil)
    }

    @Test("Only current warning-free completion replaces and persists the accepted snapshot")
    func currentCompleteGenerationReplacesAtomically() async throws {
        let cache = MemoryDiskUsageCache()
        let store = DiskUsageStore(cache: cache)
        let staleGeneration = store.beginScan()
        let currentGeneration = store.beginScan()

        await store.accept(.completed(snapshot(roots: identity("a"), bytes: 1)), generation: staleGeneration)
        #expect(store.visibleSnapshot == nil)

        let partial = snapshot(roots: identity("a"), bytes: 2, warning: true)
        await store.accept(.completed(partial), generation: currentGeneration)
        #expect(store.visiblePackages.first?.observation.allocatedBytes == 2)
        #expect(store.visibleSnapshot == nil)
        #expect(store.warnings.isEmpty == false)

        let recoveryGeneration = store.beginScan()
        let recovered = snapshot(roots: identity("a"), bytes: 3)
        await store.accept(.completed(recovered), generation: recoveryGeneration)
        #expect(store.visibleSnapshot == recovered)
        #expect(store.warnings.isEmpty)
        #expect(try await cache.load()?.packages.first?.observation.allocatedBytes == 3)
    }

    @Test("Entry scans are needed only without a fresh snapshot and never mid-scan")
    func entryScanNeededOnlyWithoutFreshSnapshot() async {
        let store = DiskUsageStore(cache: MemoryDiskUsageCache())
        #expect(store.needsEntryScan)

        let generation = store.beginScan()
        #expect(store.needsEntryScan == false)

        await store.accept(.completed(snapshot(roots: identity("a"), bytes: 1)), generation: generation)
        #expect(store.needsEntryScan == false)

        store.invalidate([.cache])
        #expect(store.needsEntryScan)
    }

    @Test("Progress is monotonic and cancellation keeps the accepted snapshot")
    func progressAndCancellationPreserveAcceptedData() async {
        let cache = MemoryDiskUsageCache(initial: snapshot(roots: identity("a"), bytes: 5))
        let store = DiskUsageStore(cache: cache)
        await store.loadCached(for: identity("a"))
        let generation = store.beginScan()

        await store.accept(.progress(.init(completedUnits: 2, discoveredUnits: 5)), generation: generation)
        await store.accept(.progress(.init(completedUnits: 1, discoveredUnits: 6)), generation: generation)
        #expect(store.progress?.completedUnits == 2)

        store.cancel()
        await store.accept(.completed(snapshot(roots: identity("a"), bytes: 99)), generation: generation)
        #expect(store.visibleSnapshot?.packages.first?.observation.allocatedBytes == 5)
        #expect(store.isScanning == false)
    }

    @Test("Store-owned scan publishes live events and cancellation stops its producer")
    func ownedScanPublishesAndCancels() async {
        let cache = MemoryDiskUsageCache(initial: snapshot(roots: identity("a"), bytes: 5))
        let store = DiskUsageStore(cache: cache)
        await store.loadCached(for: identity("a"))
        let scanner = ControlledDiskUsageScanner()
        let roots = roots("a")

        store.startScan(roots: roots, scanner: scanner)
        await eventually { scanner.isConnected }

        let version = snapshot(roots: roots.identity, bytes: 12).packages[0].versions[0]
        scanner.yield(.version(version))
        await eventually { store.visiblePackages.first?.observation.allocatedBytes == 12 }

        store.cancel()
        await eventually { scanner.wasCancelled }
        #expect(store.visibleSnapshot?.packages.first?.observation.allocatedBytes == 5)
        #expect(store.isScanning == false)
    }

    @Test("Incremental arrivals keep selected expansion identity and deterministic order")
    func incrementalOrderingPreservesIdentity() async throws {
        let store = DiskUsageStore(cache: MemoryDiskUsageCache())
        let selected = package(.formula, "zulu", version: "1", bytes: 10)
        let selectedID = selected.id
        let expandedID = selected.id
        let initialGeneration = store.beginScan()
        await store.accept(
            .completed(snapshot(roots: identity("a"), packages: [selected])),
            generation: initialGeneration
        )

        let generation = store.beginScan()
        await store.accept(.version(selected.versions[0]), generation: generation)
        let tied = package(.formula, "alpha", version: "1", bytes: 10)
        await store.accept(.version(tied.versions[0]), generation: generation)
        #expect(store.visiblePackages.map(\.id) == [tied.id, selectedID])

        let earlier = package(.cask, "heavy", version: "1", bytes: 20)
        await store.accept(.version(earlier.versions[0]), generation: generation)
        #expect(store.visiblePackages.map(\.id) == [earlier.id, tied.id, selectedID])

        let secondVersion = package(.formula, "zulu", version: "2", bytes: 5).versions[0]
        await store.accept(.version(secondVersion), generation: generation)
        let firstRead = store.visiblePackages
        let selectedAfterArrivals = try #require(firstRead.first { $0.id == selectedID })

        #expect(firstRead.map(\.id) == [earlier.id, selectedID, tied.id])
        #expect(store.visiblePackages.map(\.id) == firstRead.map(\.id))
        #expect(selectedAfterArrivals.id == expandedID)
        #expect(selectedAfterArrivals.versions.map(\.id.rawVersion) == ["1", "2"])
    }

    private func identity(_ suffix: String) -> DiskRootsIdentity {
        .init(cellar: "/\(suffix)/Cellar", caskroom: "/\(suffix)/Caskroom", cache: "/\(suffix)/Cache")
    }

    private func roots(_ suffix: String) -> HomebrewRoots {
        let prefix = URL(fileURLWithPath: "/\(suffix)")
        let installation = BrewInstallation(
            executableURL: prefix.appendingPathComponent("bin/brew"),
            prefix: .custom(prefix),
            version: BrewVersion(major: 6, minor: 0, patch: 0)
        )
        return HomebrewRoots(
            installation: installation,
            userCacheDirectory: URL(fileURLWithPath: "/\(suffix)")
        )
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
        #expect(condition())
    }

    private func snapshot(
        roots: DiskRootsIdentity,
        bytes: Int64,
        warning: Bool = false
    ) -> DiskUsageSnapshot {
        let id = PackageID(kind: .formula, name: "wget")
        let version = DiskVersionUsage(
            id: .init(package: id, rawVersion: "1"),
            observation: .init(allocatedBytes: bytes, logicalBytes: bytes),
            linkState: .linked("1")
        )
        return DiskUsageSnapshot(
            roots: roots,
            generatedAt: Date(timeIntervalSince1970: TimeInterval(bytes)),
            rootStates: warning ? [.cellar: .failed("denied")] : [.cellar: .present, .caskroom: .absent, .cache: .absent],
            packages: [.init(id: id, versions: [version])],
            cache: .zero,
            warnings: warning ? [.init(area: .cellar, path: roots.cellar, message: "denied")] : []
        )
    }

    private func snapshot(
        roots: DiskRootsIdentity,
        packages: [DiskPackageUsage]
    ) -> DiskUsageSnapshot {
        DiskUsageSnapshot(
            roots: roots,
            generatedAt: Date(timeIntervalSince1970: 1),
            rootStates: [.cellar: .present, .caskroom: .present, .cache: .absent],
            packages: packages,
            cache: .zero
        )
    }

    private func package(
        _ kind: PackageKind,
        _ name: String,
        version: String,
        bytes: Int64
    ) -> DiskPackageUsage {
        let id = PackageID(kind: kind, name: name)
        return DiskPackageUsage(
            id: id,
            versions: [DiskVersionUsage(
                id: .init(package: id, rawVersion: version),
                observation: .init(allocatedBytes: bytes, logicalBytes: bytes),
                linkState: kind == .formula ? .unlinked : .notApplicable
            )]
        )
    }
}

private final class ControlledDiskUsageScanner: DiskUsageScanning, @unchecked Sendable {
    private struct State: Sendable {
        var continuation: DiskUsageEventStream.Continuation?
        var wasCancelled = false
    }

    private let state = Mutex(State())

    var isConnected: Bool { state.withLock { $0.continuation != nil } }
    var wasCancelled: Bool { state.withLock { $0.wasCancelled } }

    func scan(
        roots: HomebrewRoots,
        formulaLinks: [PackageID: FormulaLinkState]
    ) async -> DiskUsageEventStream {
        AsyncThrowingStream { continuation in
            state.withLock { $0.continuation = continuation }
            continuation.onTermination = { [weak self] _ in
                self?.state.withLock { $0.wasCancelled = true }
            }
        }
    }

    func yield(_ event: DiskUsageEvent) {
        state.withLock { $0.continuation }?.yield(event)
    }
}

private actor MemoryDiskUsageCache: DiskUsageCaching {
    private var snapshot: DiskUsageSnapshot?

    init(initial: DiskUsageSnapshot? = nil) { snapshot = initial }

    func load() throws -> DiskUsageSnapshot? { snapshot }
    func save(_ snapshot: DiskUsageSnapshot) throws { self.snapshot = snapshot }
}
