import Catalog
import Foundation
import SwiftData
import Testing

@testable import Persistence

/// Metadata is machine-local and survives a schema upgrade
/// (local-package-metadata LPM7).
///
/// Two claims, and they are different. The **real** one is V1 → V2: a store
/// written by the code that shipped V1 opens under V2 with every field intact,
/// which is the first migration this app has ever performed. The **forward**
/// one is V2 → a throwaway that adds a property, which keeps the original
/// promise honest — the version after the one we ship still costs a stage
/// rather than a rewrite.
@MainActor
@Suite("Metadata migration")
struct MigrationTests {
    private static let wget = PackageID(kind: .formula, name: "wget")

    // MARK: - LPM7 sc1 — no sync or network surface exists

    @Test("Neither the stored configuration nor the public surface declares a remote destination")
    func noSyncOrNetworkSurfaceExists() throws {
        for file in [
            "PersistenceContainer.swift", "SchemaV1.swift", "SchemaV2.swift", "SchemaV3.swift",
            "MetadataStore.swift", "HistoryStore.swift", "MetadataMigrationPlan.swift",
            "DismissalStore.swift"
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
            "PersistenceContainer.swift", "SchemaV1.swift", "SchemaV2.swift", "SchemaV3.swift",
            "MetadataStore.swift", "HistoryStore.swift", "MetadataMigrationPlan.swift"
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

    /// Writes at the shipped schema, then reopens the same file through a plan
    /// whose *next* version adds one optional property. If that stage were
    /// anything other than `.lightweight`, or if the plan were missing, this
    /// throws rather than migrating.
    ///
    /// Retargeted from V1→throwaway to V2→throwaway when V2 shipped: the claim
    /// has always been "the version after the one we ship costs a stage, not a
    /// rewrite", and pinning it to V1 forever would have quietly turned it into
    /// a test of a migration that now has a real one beside it.
    @Test("A store written at the shipped schema is still readable when a later version adds a field")
    func theShippedStoreMigratesToAVersionThatAddsAField() throws {
        try withTemporaryStore { url in
            do {
                let store = try MetadataStore(container: PersistenceContainer.onDisk(at: url))
                store.setFavorite(true, for: Self.wget)
                store.setNote("survives the upgrade", for: Self.wget)
                store.snooze(Self.wget, offering: "1.2.3")
            }

            let upgraded = try ModelContainer(
                for: Schema(versionedSchema: ThrowawaySchemaV4.self),
                migrationPlan: ThrowawayMigrationPlan.self,
                configurations: ModelConfiguration(url: url)
            )

            let metas = try upgraded.mainContext.fetch(FetchDescriptor<ThrowawaySchemaV4.PackageMeta>())
            let meta = try #require(metas.first)
            #expect(meta.name == "wget")
            #expect(meta.isFavorite)
            #expect(meta.note == "survives the upgrade")
            // The added property is present and defaulted, not a decode failure.
            #expect(meta.colorTag == nil)

            let snoozes = try upgraded.mainContext.fetch(FetchDescriptor<ThrowawaySchemaV4.Snooze>())
            #expect(snoozes.first?.snoozedVersion == "1.2.3")
        }
    }

    @Test("The shipped plan declares every version and one lightweight stage per step")
    func theShippedPlanDeclaresEveryStage() {
        // V1 was genesis and the plan was wired from the first commit precisely
        // so that each later milestone is a stage rather than a rewrite.
        #expect(MetadataMigrationPlan.schemas.count == 3)
        #expect(MetadataMigrationPlan.stages.count == 2)
        #expect(ThrowawayMigrationPlan.stages.count == 3, "the throwaway plan lost a stage")

        // Counting the stages says only that stages exist. `MigrationStage` is
        // a pattern-matchable enum, so the claim worth making is which stages
        // they are: lightweight, and each bridging the right adjacent pair.
        // SwiftData performs implicit lightweight migration anyway — so this
        // test is the only thing standing between the plan and a stage that is
        // silently decorative.
        let pairs: [(any VersionedSchema.Type, any VersionedSchema.Type)] = [
            (SchemaV1.self, SchemaV2.self),
            (SchemaV2.self, SchemaV3.self)
        ]
        for (index, expected) in pairs.enumerated() {
            guard index < MetadataMigrationPlan.stages.count,
                  case .lightweight(let fromVersion, let toVersion) = MetadataMigrationPlan.stages[index]
            else {
                Issue.record("stage \(index) is missing or not lightweight")
                continue
            }
            #expect(ObjectIdentifier(fromVersion) == ObjectIdentifier(expected.0))
            #expect(ObjectIdentifier(toVersion) == ObjectIdentifier(expected.1))
            #expect(fromVersion.versionIdentifier == expected.0.versionIdentifier)
            #expect(toVersion.versionIdentifier == expected.1.versionIdentifier)
        }
    }

    // MARK: - The second real migration: V2 → V3

    /// A store written by the code that shipped V2 — the archival `HistoryEntry`
    /// shape, no `failureTail` column — opened by the shipped V3 container.
    ///
    /// This is the exact store every user of the previous release has on disk,
    /// and the exact open that threw `SwiftDataError` when the field was first
    /// added to the shared class in place instead of behind a version bump.
    @Test("A store written under V2 opens under V3 with the failure tail defaulted")
    func aStoreWrittenUnderV2OpensUnderV3WithTheTailDefaulted() throws {
        let stamp = Date(timeIntervalSince1970: 1_770_000_000)
        let entryID = UUID()

        try withTemporaryStore { url in
            do {
                let written = try ModelContainer(
                    for: Schema(versionedSchema: SchemaV2.self),
                    migrationPlan: ShippedV2Plan.self,
                    configurations: ModelConfiguration(url: url)
                )
                written.mainContext.insert(
                    SchemaV1.HistoryEntry(
                        id: entryID,
                        date: stamp,
                        kindRaw: "cask",
                        name: "google-chrome",
                        verb: "install",
                        versionFrom: "",
                        versionTo: "",
                        outcomeRaw: "failed",
                        exitStatus: 1,
                        argv: ["install", "--cask", "google-chrome"],
                        commandText: "install --cask google-chrome"
                    )
                )
                try written.mainContext.save()
            }

            let upgraded = try PersistenceContainer.onDisk(at: url)
            let entry = try #require(
                try upgraded.mainContext.fetch(FetchDescriptor<HistoryEntry>()).first
            )
            #expect(entry.id == entryID)
            #expect(entry.name == "google-chrome")
            #expect(entry.outcomeRaw == "failed")
            #expect(entry.exitStatus == 1)
            #expect(entry.argv == ["install", "--cask", "google-chrome"])
            // Present and defaulted, not a decode failure — and not invented.
            #expect(entry.failureTail.isEmpty)
        }
    }

    // MARK: - The first real migration: V1 → V2

    /// A store written by the code that shipped V1, opened by the code that
    /// ships V2.
    ///
    /// The V1 side is built through a V1-only plan — the plan V1 actually had —
    /// rather than by asking today's plan for an older schema, because "today's
    /// code can produce something it can also read" is not the claim. Every
    /// stored value is asserted field by field: a migration that silently
    /// defaulted a column would keep the row count and lose the row.
    @Test("A store written under V1 opens under V2 with every row intact")
    func aStoreWrittenUnderV1OpensUnderV2WithEveryRowIntact() throws {
        let stamp = Date(timeIntervalSince1970: 1_770_000_000)
        let entryID = UUID()

        try withTemporaryStore { url in
            try Self.writeV1Fixture(at: url, stamp: stamp, entryID: entryID)

            let upgraded = try PersistenceContainer.onDisk(at: url)
            let context = upgraded.mainContext

            let meta = try #require(try context.fetch(FetchDescriptor<PackageMeta>()).first)
            #expect(meta.kindRaw == "formula")
            #expect(meta.name == "wget")
            #expect(meta.isFavorite)
            #expect(meta.note == "written under V1")
            #expect(meta.updatedAt == stamp)

            let snooze = try #require(try context.fetch(FetchDescriptor<Snooze>()).first)
            #expect(snooze.kindRaw == "cask")
            #expect(snooze.name == "iterm2")
            #expect(snooze.snoozedVersion == "3.5.0")
            #expect(snooze.createdAt == stamp)

            try Self.expectHistoryIntact(in: context, stamp: stamp, entryID: entryID)

            // The new model arrives empty rather than absent: a V1 store has no
            // dismissals, and asking for them is not an error.
            #expect(try context.fetch(FetchDescriptor<DismissedCVE>()).isEmpty)
        }
    }

    /// Field level, not count level.
    ///
    /// "The three V1 models are unchanged" is a claim about every property of
    /// every one of them, and a test that compared entity *counts* would pass
    /// while a renamed column quietly turned a lightweight stage into data loss.
    @Test("The three V1 models are unchanged in V2, property for property")
    func theThreeV1ModelsAreUnchangedInV2() throws {
        let versionOne = Schema(versionedSchema: SchemaV1.self)
        let versionTwo = Schema(versionedSchema: SchemaV2.self)

        for name in ["PackageMeta", "Snooze", "HistoryEntry"] {
            let before = try Self.propertyNames(of: name, in: versionOne)
            let after = try Self.propertyNames(of: name, in: versionTwo)
            // The positive anchor: without it, two entities that both parsed to
            // nothing would compare equal and this test would guard nothing.
            #expect(before.isEmpty == false, "\(name) parsed to no properties at all in V1")
            #expect(before == after, "\(name) changed between V1 and V2: \(before) → \(after)")
        }

        let before = Set(versionOne.entities.map(\.name))
        let after = Set(versionTwo.entities.map(\.name))
        #expect(before == ["PackageMeta", "Snooze", "HistoryEntry"])
        #expect(after == before.union(["DismissedCVE"]), "V2 changed more than one model")
    }

    /// `DismissedCVE` is primitives only, and the four-part key is on the
    /// identity that actually identifies an advisory.
    @Test("DismissedCVE is primitives only, uniqued on its four-part key")
    func dismissedCVEIsPrimitivesOnly() throws {
        let entity = try #require(
            Schema(versionedSchema: SchemaV2.self).entities.first { $0.name == "DismissedCVE" }
        )
        #expect(entity.relationships.isEmpty, "DismissedCVE declared a relationship")
        #expect(
            Set(entity.attributes.map(\.name)) == [
                "advisoryID", "cveID", "kindRaw", "name", "version", "dismissedAt", "note"
            ]
        )
        #expect(
            entity.uniquenessConstraints == [["advisoryID", "kindRaw", "name", "version"]],
            "the unique key is \(entity.uniquenessConstraints)"
        )
    }

    /// Writes the fixture with the plan V1 actually had.
    private static func writeV1Fixture(at url: URL, stamp: Date, entryID: UUID) throws {
        let written = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: ShippedV1Plan.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = written.mainContext
        context.insert(
            PackageMeta(
                kindRaw: "formula",
                name: "wget",
                isFavorite: true,
                note: "written under V1",
                updatedAt: stamp
            )
        )
        context.insert(
            Snooze(kindRaw: "cask", name: "iterm2", snoozedVersion: "3.5.0", createdAt: stamp)
        )
        context.insert(
            SchemaV1.HistoryEntry(
                id: entryID,
                date: stamp,
                kindRaw: "formula",
                name: "wget",
                verb: "install",
                versionFrom: "",
                versionTo: "1.21.4",
                outcomeRaw: "succeeded",
                exitStatus: 0,
                argv: ["brew", "install", "wget"],
                commandText: "brew install wget"
            )
        )
        try context.save()
    }

    /// The widest of the three models, asserted field by field — including the
    /// `[String]` and the optional `Int`, which are the two columns a careless
    /// stage would be most likely to drop.
    private static func expectHistoryIntact(
        in context: ModelContext,
        stamp: Date,
        entryID: UUID
    ) throws {
        let entry = try #require(try context.fetch(FetchDescriptor<HistoryEntry>()).first)
        #expect(entry.id == entryID)
        #expect(entry.date == stamp)
        #expect(entry.verb == "install")
        #expect(entry.versionFrom == "")
        #expect(entry.versionTo == "1.21.4")
        #expect(entry.outcomeRaw == "succeeded")
        #expect(entry.exitStatus == 0)
        #expect(entry.argv == ["brew", "install", "wget"])
        #expect(entry.commandText == "brew install wget")
        // The V3 column, present and defaulted on a row written two versions
        // before it existed.
        #expect(entry.failureTail.isEmpty)
    }

    private static func propertyNames(of entity: String, in schema: Schema) throws -> [String] {
        let match = try #require(
            schema.entities.first { $0.name == entity },
            "\(entity) is absent from the schema"
        )
        return match.properties.map(\.name).sorted()
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
