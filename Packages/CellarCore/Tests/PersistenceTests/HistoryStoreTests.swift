import Catalog
import Foundation
import SwiftData
import Testing

@testable import Persistence

/// The history projection: ordered newest first, searchable, keep-all, and
/// clearable only as a whole (installation-history IH4, IH5, IH6).
@MainActor
@Suite("History store")
struct HistoryStoreTests {
    private static let wget = PackageID(kind: .formula, name: "wget")

    /// Three entries in a known order, oldest first as written.
    private static func seeded() throws -> (ModelContainer, HistoryStore) {
        let container = try PersistenceContainer.inMemory()
        let context = container.mainContext
        context.insert(entry(named: "wget", verb: "install", at: 1_000))
        context.insert(entry(named: "git", verb: "uninstall", at: 2_000))
        context.insert(entry(named: "iterm2", verb: "upgrade", kind: .cask, at: 3_000))
        try context.save()
        return (container, HistoryStore(container: container))
    }

    private static func entry(
        named name: String,
        verb: String,
        kind: PackageKind = .formula,
        at seconds: TimeInterval
    ) -> HistoryEntry {
        let argv = [verb, "--\(kind.rawValue)", name]
        return HistoryEntry(
            id: UUID(),
            date: Date(timeIntervalSince1970: seconds),
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

    // MARK: - IH5 sc1 — newest first

    @Test("An empty search returns every entry, most recent first")
    func anEmptySearchReturnsEverythingNewestFirst() throws {
        let (_, store) = try Self.seeded()

        #expect(store.records.count == 3)
        #expect(store.records.map(\.name) == ["iterm2", "git", "wget"])
        #expect(store.records.map(\.date) == store.records.map(\.date).sorted(by: >))
    }

    // MARK: - IH5 sc2–3 — searching narrows the list

    @Test("Searching by package name is case-insensitive and narrows to one entry")
    func searchingByNameNarrows() throws {
        let (_, store) = try Self.seeded()

        store.search = "WGET"

        #expect(store.records.count == 1)
        #expect(store.records.first?.name == "wget")
        #expect(store.records.first?.packageID == Self.wget)
    }

    @Test("Searching by verb narrows to the entry with that verb")
    func searchingByVerbNarrows() throws {
        let (_, store) = try Self.seeded()

        store.search = "uninstall"

        #expect(store.records.count == 1)
        #expect(store.records.first?.verb == "uninstall")
        #expect(store.records.first?.name == "git")
    }

    @Test("Searching by an argv fragment reaches the command text")
    func searchingByArgvFragmentReachesTheCommand() throws {
        let (_, store) = try Self.seeded()

        store.search = "--cask"

        #expect(store.records.count == 1)
        #expect(store.records.first?.commandText == "upgrade --cask iterm2")
    }

    // MARK: - IH5 sc4 — an empty result is non-destructive

    @Test("A search matching nothing is empty, and the next empty search returns everything")
    func aSearchMatchingNothingIsNonDestructive() throws {
        let (container, store) = try Self.seeded()

        store.search = "zeppelin"
        #expect(store.records.isEmpty)
        // The rows are still there — the search filtered, it did not delete.
        #expect(try container.mainContext.fetch(FetchDescriptor<HistoryEntry>()).count == 3)

        store.search = ""
        #expect(store.records.count == 3)
        #expect(store.records.map(\.name) == ["iterm2", "git", "wget"])
    }

    // MARK: - IH4 sc1 — nothing is evicted as entries accumulate

    /// Keep-all retention, and the reason `HistoryStore` sets **no**
    /// `fetchLimit`: truncating the view would quietly contradict the retention
    /// promise while looking exactly like it was honoured.
    @Test("A large number of entries across several sessions are all still present")
    func nothingIsEvictedAsEntriesAccumulate() throws {
        let container = try PersistenceContainer.inMemory()
        let context = container.mainContext

        // Three "sessions", each opening its own store over the same container.
        for session in 0..<3 {
            for index in 0..<250 {
                context.insert(
                    Self.entry(
                        named: "package-\(session)-\(index)",
                        verb: "install",
                        at: TimeInterval(session * 1_000 + index)
                    )
                )
            }
            try context.save()
            _ = HistoryStore(container: container)
        }

        let store = HistoryStore(container: container)
        #expect(store.records.count == 750, "entries were evicted by age or by count")
        #expect(store.records.first?.name == "package-2-249", "the newest entry is not first")
        #expect(store.records.last?.name == "package-0-0", "the oldest entry was dropped")

        // Comments stripped: the file *documents* why there is no limit.
        let source = SchemaTests.code(in: try Self.storeSource())
        #expect(source.contains("fetchLimit") == false, "the history query gained a fetchLimit")
    }

    // MARK: - IH4 sc2 — a later mutation appends rather than amends

    @Test("Uninstalling a package already installed appends a second entry, unchanged")
    func aLaterMutationAppends() throws {
        let container = try PersistenceContainer.inMemory()
        let install = Self.entry(named: "wget", verb: "install", at: 1_000)
        container.mainContext.insert(install)
        try container.mainContext.save()
        let originalID = install.id

        container.mainContext.insert(Self.entry(named: "wget", verb: "uninstall", at: 2_000))
        try container.mainContext.save()

        let store = HistoryStore(container: container)
        let forWget = store.records.filter { $0.name == "wget" }
        #expect(forWget.count == 2)
        #expect(forWget.map(\.verb) == ["uninstall", "install"])

        let first = try #require(forWget.last)
        #expect(first.id == originalID, "the earlier entry was rewritten rather than appended to")
        #expect(first.commandText == "install --formula wget")
        #expect(first.date == Date(timeIntervalSince1970: 1_000))
    }

    // MARK: - IH6 sc1, sc3 — clear is all-or-nothing and touches nothing else

    @Test("A confirmed clear empties the history and leaves every favorite, note and snooze")
    func clearingEmptiesOnlyTheHistory() throws {
        let container = try PersistenceContainer.inMemory()
        let metadata = MetadataStore(container: container)
        metadata.setFavorite(true, for: Self.wget)
        metadata.setNote("line one\nline two", for: Self.wget)
        metadata.snooze(Self.wget, offering: "1.2.3")

        container.mainContext.insert(Self.entry(named: "wget", verb: "install", at: 1_000))
        container.mainContext.insert(Self.entry(named: "git", verb: "uninstall", at: 2_000))
        try container.mainContext.save()

        let store = HistoryStore(container: container)
        #expect(store.records.count == 2)

        store.clearAll()

        #expect(store.records.isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<HistoryEntry>()).isEmpty)

        metadata.reload()
        #expect(metadata.isFavorite(Self.wget))
        #expect(metadata.note(for: Self.wget) == "line one\nline two")
        #expect(metadata.snoozedVersion(for: Self.wget) == "1.2.3")
        #expect(try container.mainContext.fetch(FetchDescriptor<PackageMeta>()).count == 1)
        #expect(try container.mainContext.fetch(FetchDescriptor<Snooze>()).count == 1)
    }

    // MARK: - IH6 — a clear that fails stays observable

    /// A clear that fails was indistinguishable from a healthy empty history:
    /// the `catch` set the availability and the unconditional `reload()` below
    /// it immediately overwrote that with `.available`, and `lastError` was
    /// never touched at all.
    ///
    /// The failure is injected through the clear seam rather than by making a
    /// real SwiftData delete fail: a read-only directory or a corrupted file is
    /// flaky in the `swift test` loop, and what is under test is the store's
    /// reaction, not SwiftData's (design D5).
    @Test("A failed clear keeps every entry and reports the reason")
    func aFailedClearKeepsEveryEntryAndReportsTheReason() throws {
        let container = try PersistenceContainer.inMemory()
        let context = container.mainContext
        context.insert(Self.entry(named: "wget", verb: "install", at: 1_000))
        context.insert(Self.entry(named: "git", verb: "uninstall", at: 2_000))
        context.insert(Self.entry(named: "iterm2", verb: "upgrade", kind: .cask, at: 3_000))
        try context.save()

        let store = HistoryStore(container: container, clearing: { _ in throw ClearFailure() })
        #expect(store.records.count == 3)

        store.clearAll()

        // Every entry, with its original fields — read back after the reload the
        // attempt performs, so this is the rebuilt projection, not a stale one.
        #expect(store.records.count == 3, "a failed clear deleted \(3 - store.records.count) entries")
        #expect(store.records.map(\.name) == ["iterm2", "git", "wget"])
        #expect(store.records.map(\.verb) == ["upgrade", "uninstall", "install"])
        #expect(store.records.map(\.commandText) == [
            "upgrade --cask iterm2",
            "uninstall --formula git",
            "install --formula wget"
        ])
        #expect(try context.fetch(FetchDescriptor<HistoryEntry>()).count == 3)

        // And the failure survived that reload rather than being overwritten by
        // it: not an empty history, and not a healthy one.
        #expect(store.availability.isAvailable == false, "a failed clear reported a healthy history")
        #expect(store.availability.reason?.isEmpty == false)
        #expect(store.lastError?.isEmpty == false, "a failed clear reported no reason")
    }

    @Test("A successful clear leaves no stale failure reason")
    func aSuccessfulClearLeavesNoStaleFailureReason() throws {
        let (container, store) = try Self.seeded()
        #expect(store.records.count == 3)

        store.clearAll()

        #expect(store.records.isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<HistoryEntry>()).isEmpty)
        #expect(store.availability.isAvailable, "a successful clear reported an unavailable store")
        #expect(store.lastError == nil, "a successful clear left a failure reason behind")
    }

    /// Stands in for whatever SwiftData raises: the store reacts to *a* thrown
    /// error, never to a particular one.
    private struct ClearFailure: Error {}

    // MARK: - IH6 sc4 — no per-entry delete affordance exists

    /// The `ActivityItem.Control` technique: the candidate controls are
    /// enumerable, so "no delete or remove control is present" is an assertion
    /// about the whole surface rather than about what happens to be unwritten.
    @Test("The controls a single entry exposes are copy and nothing else")
    func noPerEntryDeleteControlExists() throws {
        let (_, store) = try Self.seeded()
        let record = try #require(store.records.first)

        #expect(record.controls == [.copyCommand])
        for absent in [HistoryRecord.Control.delete, .remove] {
            #expect(record.controls.contains(absent) == false, "a per-entry \(absent) control exists")
        }
        // And no API on the store deletes one entry.
        let source = SchemaTests.code(in: try Self.storeSource())
        #expect(source.contains("func delete(") == false)
        #expect(source.contains("func remove(") == false)
    }

    // MARK: - Degradation

    @Test("An unavailable history store reads empty and clears nothing, throwing nothing")
    func anUnavailableStoreDegrades() throws {
        let store = HistoryStore(container: nil)

        #expect(store.availability.isAvailable == false)
        #expect(store.availability.reason?.isEmpty == false)
        #expect(store.records.isEmpty)

        store.search = "wget"
        store.clearAll()

        #expect(store.records.isEmpty)
    }

    // MARK: -

    private static func storeSource() throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Persistence/HistoryStore.swift"),
            encoding: .utf8
        )
    }
}
