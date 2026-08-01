import Foundation
import Testing

@testable import Catalog

@Suite("Catalog persistence")
struct FileStoreTests {
    static let root = URL(fileURLWithPath: "/tmp/cellar-fake/Catalog", isDirectory: true)

    // MARK: - Atomic swap (CS3)

    @Test("A write that fails midway leaves the previous snapshot readable")
    func failedWriteKeepsThePreviousSnapshot() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        let previous = Self.snapshot(names: ["wget", "git"])
        try store.persist(previous, state: Self.state(recordCount: 2))

        fileSystem.failReplacements(of: store.snapshotURL)

        #expect(throws: CatalogSyncError.persistence) {
            try store.persist(Self.snapshot(names: ["curl"]), state: Self.state(recordCount: 1))
        }

        let reloaded = try #require(try store.loadSnapshot())
        #expect(reloaded.packages.map(\.name) == ["wget", "git"])
    }

    @Test("A sidecar write failure is reported as a persistence failure")
    func failedSidecarWriteIsAPersistenceFailure() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        fileSystem.failReplacements(of: store.stateURL)

        #expect(throws: CatalogSyncError.persistence) {
            try store.persist(Self.snapshot(names: ["wget"]), state: Self.state(recordCount: 1))
        }
    }

    @Test("The snapshot is published before the sidecar that advertises it")
    func snapshotIsPublishedBeforeItsSidecar() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)

        try store.persist(Self.snapshot(names: ["wget"]), state: Self.state(recordCount: 1))

        // The reverse order would advertise a stale snapshot as fresh — the one
        // failure mode that serves wrong data (design D3).
        #expect(fileSystem.publishedPaths == ["catalog.json", "catalog-state.json"])
    }

    // MARK: - State sidecar (CS6)

    @Test("The state sidecar round-trips validators, downloadedAt and per-source counts")
    func sidecarRoundTrips() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        let downloadedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let state = CatalogState(
            sources: [
                .formulae: SourceState(
                    validators: ConditionalValidators(
                        etag: "\"6a6e2a26-1d95bbf\"",
                        lastModified: "Sat, 01 Aug 2026 17:17:26 GMT"
                    ),
                    downloadedAt: downloadedAt,
                    recordCount: 7_000,
                    byteCount: 31_022_015
                ),
                .casks: SourceState(
                    validators: ConditionalValidators(etag: "\"6a6e2a26-fff2a7\""),
                    downloadedAt: downloadedAt,
                    recordCount: 8_500,
                    byteCount: 16_773_799
                )
            ],
            lastSuccessAt: downloadedAt,
            skippedRecordCount: 0
        )
        try store.persist(Self.snapshot(names: ["wget"]), state: state)

        let reloaded = try #require(try store.loadState())
        #expect(reloaded.schemaVersion == CatalogSnapshot.currentSchemaVersion)
        #expect(reloaded.sources[.formulae]?.recordCount == 7_000)
        #expect(reloaded.sources[.casks]?.recordCount == 8_500)
        #expect(reloaded.sources[.formulae]?.downloadedAt == downloadedAt)
        #expect(reloaded.sources[.formulae]?.validators.etag == "\"6a6e2a26-1d95bbf\"")
        #expect(
            reloaded.sources[.formulae]?.validators.lastModified
                == "Sat, 01 Aug 2026 17:17:26 GMT"
        )
        #expect(reloaded.sources[.casks]?.validators.lastModified == nil)
    }

    @Test("A sidecar from a newer build reads as no cache, not as an error")
    func newerSchemaVersionIsNoCache() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        let future = """
        {"schemaVersion":\(CatalogSnapshot.currentSchemaVersion + 1),
         "sources":{},"lastSuccessAt":0,"skippedRecordCount":0,
         "fieldFromTheFuture":{"nested":true}}
        """
        fileSystem.seed(Data(future.utf8), at: store.stateURL)
        fileSystem.seed(Data("{\"schemaVersion\":99}".utf8), at: store.snapshotURL)

        #expect(try store.loadState() == nil)
        #expect(try store.loadSnapshot() == nil)
        #expect(store.hasUsableCache == false)
    }

    @Test("A corrupt snapshot reads as no cache rather than crashing the launch")
    func corruptSnapshotIsNoCache() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        fileSystem.seed(Data("{ this is not json".utf8), at: store.snapshotURL)

        #expect(try store.loadSnapshot() == nil)
    }

    // MARK: - Full replace (CS3)

    @Test("A package absent from the new payload disappears entirely")
    func absentPackageDisappears() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        try store.persist(
            Self.snapshot(names: ["wget", "oldpkg"]),
            state: Self.state(recordCount: 2)
        )

        try store.persist(Self.snapshot(names: ["wget"]), state: Self.state(recordCount: 1))

        let reloaded = try #require(try store.loadSnapshot())
        // No tombstone, no merge: the new dump *is* the catalog.
        #expect(reloaded.packages.map(\.name) == ["wget"])
        #expect(reloaded.packages.contains { $0.name == "oldpkg" } == false)
    }

    @Test("Staging is created on demand and purged wholesale")
    func stagingIsCreatedAndPurged() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)

        let staging = try store.prepareStaging()
        #expect(fileSystem.fileExists(at: staging))
        fileSystem.seed(Data("payload".utf8), at: staging.appendingPathComponent("formula.json"))

        store.purgeStaging()

        #expect(fileSystem.fileExists(at: staging) == false)
        #expect(fileSystem.contents(at: staging.appendingPathComponent("formula.json")) == nil)
    }

    // MARK: - Helpers

    static func snapshot(names: [String]) -> CatalogSnapshot {
        CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            skippedRecordCount: 0,
            packages: names.map { CatalogPackage.stub(kind: .formula, name: $0) }
        )
    }

    static func state(recordCount: Int) -> CatalogState {
        CatalogState(
            sources: [
                .formulae: SourceState(
                    validators: ConditionalValidators(),
                    downloadedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    recordCount: recordCount,
                    byteCount: 0
                )
            ],
            lastSuccessAt: Date(timeIntervalSince1970: 1_800_000_000),
            skippedRecordCount: 0
        )
    }
}
