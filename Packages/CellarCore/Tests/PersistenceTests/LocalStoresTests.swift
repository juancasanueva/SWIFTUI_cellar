import Catalog
import Foundation
import SwiftData
import Testing

@testable import Persistence

/// The composition root's one rule about local storage: **one** `ModelContainer`
/// is opened over the store file and injected into both stores.
///
/// Two containers over one file is a data-integrity hazard rather than a visible
/// bug, so it needs a test that states the invariant directly. The rule lives in
/// the package that owns the fold from an open error to a reason, which is what
/// makes it provable here at all — `cellarApp` is not visible to `swift test`
/// (design D6).
@MainActor
@Suite("Local stores composition")
struct LocalStoresTests {
    private static let wget = PackageID(kind: .formula, name: "wget")

    @Test("One container serves both stores")
    func oneContainerServesBothStores() throws {
        let url = try Self.temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let stores = LocalStores(at: url)

        #expect(stores.metadata.availability.isAvailable)
        #expect(stores.history.availability.isAvailable)
        // The invariant itself: not two containers that happen to agree, one
        // container held by both.
        let container = try #require(stores.container)
        #expect(stores.metadata.container === container, "the metadata store opened its own container")
        #expect(stores.history.container === container, "the history store opened its own container")

        // And it behaves like one store: a write through each is readable
        // through each, and clearing the history leaves the metadata alone.
        stores.metadata.setFavorite(true, for: Self.wget)
        stores.history.append(Self.entry(named: "wget", verb: "install", at: 1_000))

        #expect(stores.metadata.isFavorite(Self.wget))
        #expect(stores.history.records.map(\.name) == ["wget"])
        #expect(try container.mainContext.fetch(FetchDescriptor<HistoryEntry>()).count == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<PackageMeta>()).count == 1)

        stores.history.clearAll()
        stores.metadata.reload()

        #expect(stores.history.records.isEmpty)
        #expect(stores.metadata.isFavorite(Self.wget), "clearing the history reached the metadata")
    }

    @Test("A store that cannot be opened gives both stores the same reason")
    func aStoreThatCannotBeOpenedGivesBothStoresTheSameReason() throws {
        // A regular file exactly where the enclosing directory must go, so
        // `createDirectory` fails before SwiftData is ever reached.
        let blocked = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-blocked-\(UUID().uuidString)", isDirectory: false)
        try Data().write(to: blocked)
        defer { try? FileManager.default.removeItem(at: blocked) }

        let stores = LocalStores(at: blocked.appendingPathComponent("Metadata.store"))

        #expect(stores.container == nil)
        #expect(stores.metadata.availability.isAvailable == false)
        #expect(stores.history.availability.isAvailable == false)

        let reason = try #require(stores.metadata.availability.reason)
        #expect(reason.isEmpty == false)
        #expect(
            stores.history.availability.reason == reason,
            "one open failure produced two different reasons"
        )

        // Degraded, never thrown: both stores still answer.
        #expect(stores.metadata.isFavorite(Self.wget) == false)
        #expect(stores.history.records.isEmpty)
    }

    private static func temporaryStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-stores-\(UUID().uuidString)", isDirectory: true)
        return directory.appendingPathComponent("Metadata.store", isDirectory: false)
    }

    private static func entry(named name: String, verb: String, at seconds: TimeInterval) -> HistoryEntry {
        let argv = [verb, "--formula", name]
        return HistoryEntry(
            id: UUID(),
            date: Date(timeIntervalSince1970: seconds),
            kindRaw: PackageKind.formula.rawValue,
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
}
