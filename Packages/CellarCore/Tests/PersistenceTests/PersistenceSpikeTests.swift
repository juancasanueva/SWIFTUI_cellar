import Foundation
import SwiftData
import Testing

@testable import Persistence

// MARK: - Gate confirmations G2, G3, G4 (design "Open Gates")
//
// G1 was closed green by a live probe outside the repo (Engram `#7116`). This
// file re-lands that proof **on the real `Persistence` target** and answers the
// three gates that the probe could not: whether `#Unique` upserts rather than
// throws (G2), whether an on-disk container opens with no app bundle present
// (G3), and whether a `@MainActor` holder of a `ModelContainer` compiles and
// runs in a `nonisolated`-default target under `.swiftLanguageMode(.v6)` (G4).
//
// Verdicts are recorded here, in the file, rather than only in a report — a
// future reader who changes toolchains needs the assertion, not the anecdote.
//
// **G2 verdict: UPSERT.** Two inserts sharing the same `#Unique([\.kindRaw,
// \.name])` key leave exactly one row and throw nothing.
// **G3 verdict: OPEN.** A container created under a temporary directory with no
// app bundle present opens, writes, and reopens against the same URL.
// **G4 verdict: CLEAN.** A `@MainActor final class` holding the container
// compiles and runs here.

/// Builds the container exactly as `PersistenceContainer` will in Phase 4:
/// `Schema(versionedSchema:)` + `MetadataMigrationPlan`. Spelled here rather
/// than in production so Phase 0 adds no production surface beyond the schema
/// and the plan the gates actually exercise.
private func spikeContainer(url: URL? = nil) throws -> ModelContainer {
    let configuration = if let url {
        ModelConfiguration(url: url)
    } else {
        ModelConfiguration(isStoredInMemoryOnly: true)
    }
    return try ModelContainer(
        for: Schema(versionedSchema: SchemaV1.self),
        migrationPlan: MetadataMigrationPlan.self,
        configurations: configuration
    )
}

/// A `@MainActor` owner of a container, in a target whose default isolation is
/// `nonisolated` — the shape `MetadataStore` and `HistoryStore` take in Phase 4.
@MainActor
private final class SpikeContainerHolder {
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func insert(_ meta: PackageMeta) throws {
        container.mainContext.insert(meta)
        try container.mainContext.save()
    }

    func fetchAll() throws -> [PackageMeta] {
        try container.mainContext.fetch(FetchDescriptor<PackageMeta>())
    }

    func fetch(named name: String) throws -> [PackageMeta] {
        try container.mainContext.fetch(
            FetchDescriptor<PackageMeta>(predicate: #Predicate { $0.name == name })
        )
    }
}

@Suite("Persistence spike")
struct PersistenceSpikeTests {
    // MARK: - G1 confirmation / G4

    @Test("An in-memory container built from the versioned schema round-trips a #Predicate fetch")
    @MainActor
    func inMemoryRoundTrip() throws {
        let holder = SpikeContainerHolder(container: try spikeContainer())

        try holder.insert(PackageMeta(kindRaw: "formula", name: "wget", isFavorite: true))
        try holder.insert(PackageMeta(kindRaw: "cask", name: "iterm2", isFavorite: false))

        let matches = try holder.fetch(named: "wget")
        #expect(matches.count == 1)
        #expect(matches.first?.kindRaw == "formula")
        #expect(matches.first?.isFavorite == true)
        #expect(try holder.fetchAll().count == 2)
    }

    // MARK: - G2

    @Test("Two inserts on the same unique key upsert rather than throw")
    @MainActor
    func uniqueKeyUpserts() throws {
        let holder = SpikeContainerHolder(container: try spikeContainer())

        try holder.insert(PackageMeta(kindRaw: "formula", name: "wget", isFavorite: false))
        try holder.insert(PackageMeta(kindRaw: "formula", name: "wget", isFavorite: true))

        let rows = try holder.fetchAll()
        #expect(rows.count == 1)
        #expect(rows.first?.isFavorite == true)
    }

    @Test("The unique key is the pair, so the same name in the other namespace is a second row")
    @MainActor
    func uniqueKeyIsTheKindNamePair() throws {
        let holder = SpikeContainerHolder(container: try spikeContainer())

        try holder.insert(PackageMeta(kindRaw: "formula", name: "docker", isFavorite: true))
        try holder.insert(PackageMeta(kindRaw: "cask", name: "docker", isFavorite: false))

        let rows = try holder.fetchAll().sorted { $0.kindRaw < $1.kindRaw }
        #expect(rows.count == 2)
        #expect(rows.map(\.kindRaw) == ["cask", "formula"])
        #expect(rows.map(\.isFavorite) == [false, true])
    }

    // MARK: - G3

    @Test("An on-disk container with no app bundle present opens, writes and reopens")
    @MainActor
    func onDiskContainerReopens() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "cellar-spike-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appending(path: "Metadata.store")
        do {
            let holder = SpikeContainerHolder(container: try spikeContainer(url: url))
            try holder.insert(PackageMeta(kindRaw: "formula", name: "wget", isFavorite: true))
            #expect(try holder.fetchAll().count == 1)
        }

        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        let reopened = SpikeContainerHolder(container: try spikeContainer(url: url))
        let rows = try reopened.fetchAll()
        #expect(rows.count == 1)
        #expect(rows.first?.name == "wget")
        #expect(rows.first?.isFavorite == true)
    }
}
