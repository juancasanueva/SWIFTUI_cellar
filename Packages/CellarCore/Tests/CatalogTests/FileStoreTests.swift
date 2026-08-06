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

    // MARK: - The schema 1 -> 2 transition (P3, P4, P5, TM5)

    @Test("A snapshot written by the previous schema is a cold start, not a failure")
    func previousSchemaSnapshotIsAColdStart() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        // A perfectly readable v1 snapshot: every record decodes, and it is
        // still no cache, because the *shape* is what changed.
        let previous = """
        {"schemaVersion":1,"generatedAt":1800000000,"skippedRecordCount":0,
         "packages":[{"kind":"formula","name":"wget","displayName":"wget",
                      "version":"1.25.0","tap":"homebrew/core","dependencies":[],
                      "buildDependencies":[],"dependents":[],"deprecated":false,
                      "disabled":false,"autoUpdates":false}]}
        """
        fileSystem.seed(Data(previous.utf8), at: store.snapshotURL)
        fileSystem.seed(
            Data(#"{"schemaVersion":1,"sources":{},"lastSuccessAt":0,"skippedRecordCount":0}"#.utf8),
            at: store.stateURL
        )

        #expect(try store.loadSnapshot() == nil)
        #expect(store.hasUsableCache == false)
        // No validator survives either, so the next sync re-downloads both
        // payloads instead of revalidating into the rejected snapshot.
        #expect(try store.loadState() == nil)
        // TM5: classification is a read. It rewrote, replaced and removed nothing.
        #expect(fileSystem.operations.isEmpty)
        #expect(fileSystem.contents(at: store.snapshotURL) == Data(previous.utf8))
    }

    @Test("A previous-schema sidecar is rejected independently of the snapshot")
    func previousSchemaSidecarIsRejectedIndependently() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        try store.persist(Self.snapshot(names: ["wget"]), state: Self.state(recordCount: 1))
        // The snapshot the store just wrote is current; only the sidecar is old.
        fileSystem.seed(
            Data(
                #"{"schemaVersion":1,"sources":{"casks":{"validators":{"etag":"\"old\""},"downloadedAt":0,"recordCount":1}},"lastSuccessAt":0,"skippedRecordCount":0}"#
                    .utf8
            ),
            at: store.stateURL
        )
        let operationsBeforeTheRead = fileSystem.operations

        // Neither file is adopted on the strength of the other's version.
        #expect(try store.loadState() == nil)
        #expect(try store.loadSnapshot()?.packages.map(\CatalogPackage.name) == ["wget"])
        // No validator from the rejected sidecar is replayed.
        #expect(fileSystem.operations == operationsBeforeTheRead)
    }

    @Test("Rollback is symmetric: a newer file is no cache for an older build")
    func rollbackIsSymmetric() throws {
        let fileSystem = FakeCatalogFileSystem()
        // Driven by injecting the expected version rather than by editing the
        // constant: this is what a *reverted* build sees, and the claim that
        // `git revert` is a complete rollback rests on it.
        let currentBuild = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        try currentBuild.persist(
            Self.snapshot(names: ["wget"]), state: Self.state(recordCount: 1)
        )
        #expect(try currentBuild.loadSnapshot() != nil)

        let revertedBuild = CatalogFileStore(
            directory: Self.root,
            fileSystem: fileSystem,
            expectedSchemaVersion: CatalogSnapshot.currentSchemaVersion - 1
        )
        let operationsBeforeTheRead = fileSystem.operations

        #expect(try revertedBuild.loadSnapshot() == nil)
        #expect(try revertedBuild.loadState() == nil)
        #expect(revertedBuild.hasUsableCache == false)
        // Nothing thrown, and neither file rewritten or deleted by the read.
        #expect(fileSystem.operations == operationsBeforeTheRead)
        #expect(fileSystem.contents(at: currentBuild.snapshotURL) != nil)
        #expect(fileSystem.contents(at: currentBuild.stateURL) != nil)
        // One full sync restores service for the reverted build. It mints its
        // own version, which is the other half of the symmetry: the older build
        // writes older files and reads them back without ceremony.
        try revertedBuild.persist(
            Self.snapshot(
                names: ["wget"],
                schemaVersion: CatalogSnapshot.currentSchemaVersion - 1
            ),
            state: Self.state(recordCount: 1)
        )
        #expect(try revertedBuild.loadSnapshot()?.packages.map(\CatalogPackage.name) == ["wget"])
    }

    // MARK: - The newness sidecars gate independently (CS-M1)

    @Test("A snapshot schema bump does not invalidate an independently versioned sidecar")
    func snapshotSchemaBumpDoesNotDiscardTheNewnessSidecars() throws {
        let fileSystem = FakeCatalogFileSystem()
        // The build's expectation for the *snapshot* has moved on; the two
        // newness sidecars were written at the version their own schema
        // declares and have not moved at all.
        let store = CatalogFileStore(
            directory: Self.root,
            fileSystem: fileSystem,
            expectedSchemaVersion: CatalogSnapshot.currentSchemaVersion + 1
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        fileSystem.seed(
            try encoder.encode(Self.snapshot(names: ["wget"])),
            at: store.snapshotURL
        )
        fileSystem.seed(try encoder.encode(Self.state(recordCount: 1)), at: store.stateURL)
        fileSystem.seed(
            try encoder.encode(KnownPackageRoster(formulae: ["wget"], casks: [])),
            at: store.rosterURL
        )
        fileSystem.seed(
            try encoder.encode(
                PackageArrivalsLog(arrivals: [
                    PackageArrival(
                        kind: .formula,
                        name: "wget",
                        firstSeenAt: Date(timeIntervalSince1970: 1_800_000_000)
                    )
                ])
            ),
            at: store.arrivalsURL
        )

        // The snapshot and its state sidecar are a cold start...
        #expect(try store.loadSnapshot() == nil)
        #expect(try store.loadState() == nil)
        // ...and the user's 30-day history survives it untouched. Sharing the
        // snapshot's constant would have erased it here, for a change that has
        // nothing to do with newness.
        let roster = try #require(store.loadRoster())
        #expect(roster.contains(PackageID(kind: .formula, name: "wget")))
        #expect(store.loadArrivals()?.arrivals.map(\.name) == ["wget"])
    }

    @Test("A sidecar whose own version differs, either way, is absent without costing the snapshot")
    func sidecarVersionMismatchDoesNotRejectTheSnapshot() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)
        try store.persist(Self.snapshot(names: ["wget"]), state: Self.state(recordCount: 1))

        // Both directions, because "exact in both directions" is the rule: a
        // version older than this build's and one newer are the same answer.
        for version in [DiscoverySchema.currentVersion - 1, DiscoverySchema.currentVersion + 1] {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            fileSystem.seed(
                try encoder.encode(
                    KnownPackageRoster(schemaVersion: version, formulae: ["wget"], casks: [])
                ),
                at: store.rosterURL
            )
            fileSystem.seed(
                try encoder.encode(PackageArrivalsLog(schemaVersion: version, arrivals: [])),
                at: store.arrivalsURL
            )
            let operationsBeforeTheRead = fileSystem.operations

            #expect(store.loadRoster() == nil, "version \(version) roster was adopted")
            #expect(store.loadArrivals() == nil, "version \(version) arrivals log was adopted")
            // The snapshot is unaffected: no file is rejected on the strength of
            // another's version.
            #expect(try store.loadSnapshot()?.packages.map(\CatalogPackage.name) == ["wget"])
            // Nothing thrown, and neither file rewritten or deleted by the read.
            #expect(fileSystem.operations == operationsBeforeTheRead)
        }
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

    // MARK: - Degenerate snapshots (CSA4, CSA3)

    @Test("A zero-package catalog.json on disk reads as no cache, and throws nothing")
    func zeroPackageSnapshotReadsAsNoCache() throws {
        let directory = try Self.temporaryDirectory()
        let store = CatalogFileStore(directory: directory)
        // Written past the guard, the way a build without it would have.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(Self.snapshot(names: [])).write(to: store.snapshotURL)

        #expect(try store.loadSnapshot() == nil)
        #expect(store.hasUsableCache == false)
        // Left in place: a read path must not mutate the store, and the next
        // successful sync overwrites it anyway.
        #expect(FileManager.default.fileExists(atPath: store.snapshotURL.path))
    }

    @Test("A one-package catalog.json is still a usable cache")
    func onePackageSnapshotIsAUsableCache() throws {
        let directory = try Self.temporaryDirectory()
        let store = CatalogFileStore(directory: directory)
        try store.persist(Self.snapshot(names: ["wget"]), state: Self.state(recordCount: 1))

        let loaded = try #require(try store.loadSnapshot())

        #expect(loaded.packages.map(\.name) == ["wget"])
        #expect(store.hasUsableCache)
    }

    @Test("Persisting a zero-package snapshot is malformed, not a persistence failure")
    func zeroPackagePersistIsRefused() throws {
        let fileSystem = FakeCatalogFileSystem()
        let store = CatalogFileStore(directory: Self.root, fileSystem: fileSystem)

        // `.persistence` would be the answer if the guard sat inside the `do`,
        // which rewrites every throw. This is a semantic refusal, not I/O.
        #expect(throws: CatalogSyncError.malformedPayload) {
            try store.persist(Self.snapshot(names: []), state: Self.state(recordCount: 0))
        }

        #expect(fileSystem.contents(at: store.snapshotURL) == nil)
        #expect(fileSystem.contents(at: store.stateURL) == nil)
        #expect(fileSystem.operations.isEmpty, "a refused snapshot touched the file system")
    }

    // MARK: - Helpers

    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func snapshot(
        names: [String],
        schemaVersion: Int = CatalogSnapshot.currentSchemaVersion
    ) -> CatalogSnapshot {
        CatalogSnapshot(
            schemaVersion: schemaVersion,
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
