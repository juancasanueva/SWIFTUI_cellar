import Catalog
import Foundation
import SwiftData
import Testing

@testable import Persistence

/// Schema V1: three independent models, primitives only, no relationships
/// (design D2, local-package-metadata LPM1).
///
/// The claims under test are the ones a later schema change could quietly
/// break: metadata is keyed by the `(kind, name)` identity the rest of the app
/// already uses, it survives a close and reopen, and it is not deleted because
/// its package stopped being installed.
@MainActor
@Suite("Persistence schema")
struct SchemaTests {
    private static let wget = PackageID(kind: .formula, name: "wget")

    // MARK: - LPM1 sc1 — metadata survives a relaunch

    @Test("A favorite, a note and a snooze survive closing and reopening the store")
    func metadataSurvivesAReopen() throws {
        try withTemporaryStore { url in
            do {
                let store = try MetadataStore(container: PersistenceContainer.onDisk(at: url))
                store.setFavorite(true, for: Self.wget)
                store.setNote("keeps my downloads honest", for: Self.wget)
                store.snooze(Self.wget, offering: "1.21.4")
            }

            let reopened = try MetadataStore(container: PersistenceContainer.onDisk(at: url))
            #expect(reopened.isFavorite(Self.wget))
            #expect(reopened.note(for: Self.wget) == "keeps my downloads honest")
            #expect(reopened.snoozedVersion(for: Self.wget) == "1.21.4")
        }
    }

    // MARK: - LPM1 sc2 — kind is part of the key

    @Test("The same name in the other namespace is a different package")
    func kindIsPartOfTheKey() throws {
        let store = try MetadataStore(container: PersistenceContainer.inMemory())
        let formula = PackageID(kind: .formula, name: "docker")
        let cask = PackageID(kind: .cask, name: "docker")

        store.setFavorite(true, for: formula)
        store.setNote("the daemon", for: formula)

        #expect(store.isFavorite(formula))
        #expect(store.isFavorite(cask) == false, "the cask inherited the formula's favorite")
        #expect(store.note(for: cask) == nil)

        // And the other direction: writing the cask leaves the formula alone.
        store.snooze(cask, offering: "4.30.0")
        #expect(store.snoozedVersion(for: cask) == "4.30.0")
        #expect(store.snoozedVersion(for: formula) == nil)
        #expect(store.isFavorite(formula))
    }

    // MARK: - LPM1 sc3 — metadata outlives an uninstall

    /// Storage knows nothing about the inventory, and that is the point: there
    /// is no path by which "no longer installed" could reach a stored row.
    @Test("A note for a package absent from the inventory is unchanged and still readable")
    func metadataOutlivesAnUninstall() throws {
        let store = try MetadataStore(container: PersistenceContainer.inMemory())
        store.setNote("reinstall me later", for: Self.wget)

        // Nothing in the store's surface accepts an inventory, so an uninstall
        // is simply not an event it can observe.
        #expect(store.note(for: Self.wget) == "reinstall me later")
        #expect(store.snapshot[Self.wget]?.note == "reinstall me later")

        // Re-reading after any number of unrelated writes leaves it untouched.
        store.setFavorite(true, for: PackageID(kind: .cask, name: "iterm2"))
        store.setNote("", for: PackageID(kind: .formula, name: "git"))
        #expect(store.note(for: Self.wget) == "reinstall me later")
    }

    // MARK: - D2 — the stored shapes

    @Test("PackageKind persists as its raw value, never as an encoded enum")
    func kindPersistsAsARawString() throws {
        let container = try PersistenceContainer.inMemory()
        let store = MetadataStore(container: container)
        store.setFavorite(true, for: Self.wget)

        let rows = try container.mainContext.fetch(FetchDescriptor<PackageMeta>())
        let row = try #require(rows.first)
        #expect(row.kindRaw == "formula")
        #expect(row.kindRaw == PackageKind.formula.rawValue)
        #expect(row.name == "wget")
    }

    /// Absence is the empty string, never `Optional`: a package name can never
    /// be empty, so `name == ""` unambiguously means "this row names no
    /// package". That keeps every `#Predicate` non-optional.
    @Test("A history entry naming no package stores the empty string, not nil")
    func absenceIsTheEmptyString() throws {
        let container = try PersistenceContainer.inMemory()
        let entry = HistoryEntry(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_000),
            kindRaw: "",
            name: "",
            verb: "upgradeAll",
            versionFrom: "",
            versionTo: "",
            outcomeRaw: "succeeded",
            exitStatus: 0,
            argv: ["upgrade"],
            commandText: "upgrade"
        )
        container.mainContext.insert(entry)
        try container.mainContext.save()

        let rows = try container.mainContext.fetch(FetchDescriptor<HistoryEntry>())
        let row = try #require(rows.first)
        #expect(row.name == "")
        #expect(row.kindRaw == "")
        #expect(row.packageID == nil, "an empty name projected to a package identity")
        #expect(row.commandText == "upgrade")
    }

    @Test("The three models are independent — V1 declares no relationships")
    func theModelsAreIndependent() throws {
        // Comments stripped: the file *documents* why these two are absent, and
        // a test that read the prose would fail on the explanation.
        let source = Self.code(in: try Self.schemaSource())

        #expect(source.contains("@Relationship") == false, "V1 gained a relationship")
        #expect(source.contains("@Transient") == false, "V1 gained a transient property")
        #expect(SchemaV1.models.count == 3)
        #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    }

    /// Deleting metadata must not take history with it, and vice versa — the
    /// reason there is no relationship to begin with.
    @Test("Clearing every metadata row leaves history untouched")
    func metadataAndHistoryAreUnlinked() throws {
        let container = try PersistenceContainer.inMemory()
        let store = MetadataStore(container: container)
        store.setFavorite(true, for: Self.wget)
        container.mainContext.insert(Self.entry(named: "wget", verb: "install"))
        try container.mainContext.save()

        try container.mainContext.delete(model: PackageMeta.self)
        try container.mainContext.save()

        let history = try container.mainContext.fetch(FetchDescriptor<HistoryEntry>())
        #expect(history.count == 1)
        #expect(history.first?.name == "wget")
    }

    // MARK: -

    static func entry(
        named name: String,
        verb: String,
        kind: PackageKind = .formula,
        at date: Date = Date(timeIntervalSince1970: 1_000)
    ) -> HistoryEntry {
        let argv = [verb, "--\(kind.rawValue)", name]
        return HistoryEntry(
            id: UUID(),
            date: date,
            kindRaw: kind.rawValue,
            name: name,
            verb: verb,
            versionFrom: "",
            versionTo: "",
            outcomeRaw: "succeeded",
            exitStatus: 0,
            argv: argv,
            commandText: argv.joined(separator: " ")
        )
    }

    /// Declarations only — every `//` comment line and trailing comment gone.
    static func code(in source: String) -> String {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> Substring in
                guard let marker = line.range(of: "//") else { return line }
                return line[line.startIndex..<marker.lowerBound]
            }
            .joined(separator: "\n")
    }

    private static func schemaSource() throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Persistence/SchemaV1.swift"),
            encoding: .utf8
        )
    }
}

/// Runs `body` against a fresh on-disk location that is deleted afterwards.
///
/// On-disk rather than in-memory wherever durability is the claim: an in-memory
/// container cannot fail a "close it and open it again" test, so using one there
/// would assert nothing (G3, confirmed open in `PersistenceSpikeTests`).
func withTemporaryStore(_ body: (URL) throws -> Void) rethrows {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "cellar-metadata-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory.appending(path: "Metadata.store"))
}
