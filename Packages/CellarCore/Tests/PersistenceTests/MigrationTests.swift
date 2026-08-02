import Catalog
import Foundation
import SwiftData
import Testing

@testable import Persistence

/// Metadata is machine-local and survives a schema upgrade
/// (local-package-metadata LPM7).
///
/// V1 is genesis, so there is nothing to migrate *from* yet. The migration plan
/// exists anyway, and this suite is what makes that claim testable rather than
/// aspirational: a throwaway V2 that adds one optional property is migrated
/// `.lightweight`, with every previously stored value intact.
@MainActor
@Suite("Metadata migration")
struct MigrationTests {
    private static let wget = PackageID(kind: .formula, name: "wget")

    // MARK: - LPM7 sc1 — no sync or network surface exists

    @Test("Neither the stored configuration nor the public surface declares a remote destination")
    func noSyncOrNetworkSurfaceExists() throws {
        for file in [
            "PersistenceContainer.swift", "SchemaV1.swift", "MetadataStore.swift",
            "HistoryStore.swift", "MetadataMigrationPlan.swift"
        ] {
            let source = SchemaTests.code(in: try Self.source(of: file))
            for remote in [
                "cloudKitDatabase", "CloudKit", "groupContainer", "allowsCloudEncryption",
                "URLSession", "URLRequest", "https://", "http://"
            ] {
                #expect(source.contains(remote) == false, "\(file) declares \(remote)")
            }
        }
    }

    @Test("Persistence links no networking framework at all")
    func persistenceImportsNoNetworking() throws {
        for file in [
            "PersistenceContainer.swift", "SchemaV1.swift", "MetadataStore.swift",
            "HistoryStore.swift", "MetadataMigrationPlan.swift"
        ] {
            let imports = SchemaTests.code(in: try Self.source(of: file))
                .split(separator: "\n")
                .filter { $0.hasPrefix("import ") }
                .map { String($0.dropFirst("import ".count)) }

            #expect(imports.isEmpty == false, "\(file) parsed to no imports at all")
            #expect(Set(imports).isSubset(of: ["Foundation", "SwiftData", "Observation", "Catalog", "BrewClient"]),
                    "\(file) imports something outside the local-storage surface: \(imports)")
        }
    }

    /// The behavioural half: reading and writing metadata makes no request. A
    /// URL protocol that fails every request loudly would be the only way one
    /// could be missed, so one is installed for the duration.
    @Test("Reading and writing metadata issues no network request")
    func metadataWritesIssueNoRequest() throws {
        RequestSpy.reset()
        URLProtocol.registerClass(RequestSpy.self)
        defer { URLProtocol.unregisterClass(RequestSpy.self) }

        try withTemporaryStore { url in
            let store = MetadataStore(at: url)
            store.setFavorite(true, for: Self.wget)
            store.setNote("nothing leaves this machine", for: Self.wget)
            store.snooze(Self.wget, offering: "1.2.3")
            store.reload()

            #expect(store.isFavorite(Self.wget))
            #expect(RequestSpy.observedCount == 0, "a metadata write issued a network request")
        }
    }

    // MARK: - LPM7 sc2 — an earlier schema version migrates without data loss

    /// Writes at V1, then reopens the same file through a plan whose second
    /// version adds one optional property. If the stage were anything other
    /// than `.lightweight`, or if the plan were missing, this throws rather
    /// than migrating.
    @Test("A store written at V1 is still readable when a later version adds a field")
    func aV1StoreMigratesToAVersionThatAddsAField() throws {
        try withTemporaryStore { url in
            do {
                let store = try MetadataStore(container: PersistenceContainer.onDisk(at: url))
                store.setFavorite(true, for: Self.wget)
                store.setNote("survives the upgrade", for: Self.wget)
                store.snooze(Self.wget, offering: "1.2.3")
            }

            let upgraded = try ModelContainer(
                for: Schema(versionedSchema: ThrowawaySchemaV2.self),
                migrationPlan: ThrowawayMigrationPlan.self,
                configurations: ModelConfiguration(url: url)
            )

            let metas = try upgraded.mainContext.fetch(FetchDescriptor<ThrowawaySchemaV2.PackageMeta>())
            let meta = try #require(metas.first)
            #expect(meta.name == "wget")
            #expect(meta.isFavorite)
            #expect(meta.note == "survives the upgrade")
            // The added property is present and defaulted, not a decode failure.
            #expect(meta.colorTag == nil)

            let snoozes = try upgraded.mainContext.fetch(FetchDescriptor<ThrowawaySchemaV2.Snooze>())
            #expect(snoozes.first?.snoozedVersion == "1.2.3")
        }
    }

    @Test("The shipped plan declares V1 and no stages, so V1 is genesis")
    func theShippedPlanIsGenesis() {
        #expect(MetadataMigrationPlan.schemas.count == 1)
        #expect(MetadataMigrationPlan.stages.isEmpty)
        #expect(ThrowawayMigrationPlan.stages.count == 1)
    }

    // MARK: -

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Persistence/\(file)"),
            encoding: .utf8
        )
    }
}

/// Fails every request it sees, and counts it. Registered only for the duration
/// of the test that installs it.
final class RequestSpy: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var count = 0

    static var observedCount: Int { count }
    static func reset() { count = 0 }

    // swiftlint:disable static_over_final_class
    // `URLProtocol` declares these as overridable class methods; `static` in a
    // final class cannot override one.
    override class func canInit(with request: URLRequest) -> Bool {
        count += 1
        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class
    override func startLoading() {}
    override func stopLoading() {}
}

// MARK: - A throwaway V2, for the migration proof only

/// Adds one optional property to `PackageMeta`. Exists purely so
/// "`MetadataMigrationPlan` really is a plan, and adding a field really is
/// `.lightweight`" is proven rather than asserted. Nothing ships it.
enum ThrowawaySchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [PackageMeta.self, Snooze.self, HistoryEntry.self]
    }

    @Model
    final class PackageMeta {
        var kindRaw: String = ""
        var name: String = ""
        var isFavorite: Bool = false
        var note: String = ""
        var updatedAt: Date = Date.distantPast
        /// The added field.
        var colorTag: String?

        init(kindRaw: String, name: String) {
            self.kindRaw = kindRaw
            self.name = name
        }
    }

    @Model
    final class Snooze {
        var kindRaw: String = ""
        var name: String = ""
        var snoozedVersion: String = ""
        var createdAt: Date = Date.distantPast

        init(kindRaw: String, name: String, snoozedVersion: String) {
            self.kindRaw = kindRaw
            self.name = name
            self.snoozedVersion = snoozedVersion
        }
    }

    @Model
    final class HistoryEntry {
        var id: UUID = UUID()
        var date: Date = Date.distantPast
        var kindRaw: String = ""
        var name: String = ""
        var verb: String = ""
        var versionFrom: String = ""
        var versionTo: String = ""
        var outcomeRaw: String = ""
        var exitStatus: Int?
        var argv: [String] = []
        var commandText: String = ""

        init(id: UUID) { self.id = id }
    }
}

enum ThrowawayMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, ThrowawaySchemaV2.self] }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: ThrowawaySchemaV2.self)]
    }
}
