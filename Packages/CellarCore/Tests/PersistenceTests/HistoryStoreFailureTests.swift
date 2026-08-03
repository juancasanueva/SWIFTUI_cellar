import Catalog
import Foundation
import SwiftData
import Testing

@testable import Persistence

/// A failed write stays reported, across every later reload.
///
/// Its own suite rather than more of `HistoryStoreTests`: the projection tests
/// and the write-failure tests share only a container, and folding these in
/// pushed that type past SwiftLint's body-length limit. Split, not suppressed.
@MainActor
@Suite("History store write failures")
struct HistoryStoreFailureTests {
    /// Stands in for whatever SwiftData raises: the store reacts to *a* thrown
    /// error, never to a particular one.
    private struct ClearFailure: Error {}

    private static func entry(
        named name: String,
        verb: String,
        at seconds: TimeInterval
    ) -> HistoryEntry {
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

    /// The clear failure survived the reload the *attempt* performs — that was
    /// M2-3's fix. It did not survive the **next** one.
    ///
    /// `search` reloads on every keystroke (`:83-88`) and `reload()` ended with
    /// an unconditional `availability = .available`, so the first character the
    /// user typed after a failed clear reported a healthy history. The window
    /// is one keystroke wide, which is why the original fix could look complete.
    @Test("A failed clear's reason survives a search-driven reload")
    func aFailedClearReasonSurvivesASearchDrivenReload() throws {
        let container = try PersistenceContainer.inMemory()
        container.mainContext.insert(Self.entry(named: "wget", verb: "install", at: 1_000))
        try container.mainContext.save()

        let store = HistoryStore(container: container, clearing: { _ in throw ClearFailure() })
        store.clearAll()
        let reason = try #require(store.availability.reason)
        #expect(store.lastError == reason)

        // One keystroke. The `didSet` reloads, and the reload used to reset the
        // availability to `.available` on its way out.
        store.search = "w"

        #expect(
            store.availability.isAvailable == false,
            "a keystroke reported the failed clear as a healthy history"
        )
        #expect(store.availability.reason == reason, "the reason changed under a reload")
        #expect(store.lastError == reason)
        // And the reload still did its own job: the search really filtered.
        #expect(store.records.map(\.name) == ["wget"])

        // Still true several reloads later — it is sticky, not merely delayed.
        store.search = "wg"
        store.search = ""
        #expect(store.availability.isAvailable == false)
        #expect(store.availability.reason == reason)
    }

    @Test("A successful append or clear leaves no stale failure reason")
    func aSuccessfulAppendOrClearLeavesNoStaleFailureReason() throws {
        let container = try PersistenceContainer.inMemory()
        container.mainContext.insert(Self.entry(named: "wget", verb: "install", at: 1_000))
        try container.mainContext.save()

        let store = HistoryStore(container: container, clearing: { _ in throw ClearFailure() })
        store.clearAll()
        #expect(store.availability.isAvailable == false)

        // A later write that lands clears the reason, and it stays cleared
        // across the reloads that follow.
        store.append(Self.entry(named: "git", verb: "uninstall", at: 2_000))

        #expect(store.availability.isAvailable, "a successful append left a stale failure reason")
        #expect(store.lastError == nil)
        store.search = "git"
        #expect(store.availability.isAvailable)
        store.search = ""
        #expect(store.records.count == 2)

        // Same for a clear that succeeds after one that did not.
        let healthy = HistoryStore(container: container, clearing: { _ in throw ClearFailure() })
        healthy.clearAll()
        #expect(healthy.availability.isAvailable == false)

        let recovered = HistoryStore(container: container)
        recovered.clearAll()
        #expect(recovered.availability.isAvailable)
        #expect(recovered.lastError == nil)
        #expect(recovered.records.isEmpty)
    }

    /// A store that cannot be opened at all is not a *failed clear*, and the
    /// sticky reason must not overwrite the reason it already has.
    @Test("An unopened store keeps its own reason rather than a clear's")
    func anUnopenedStoreKeepsItsOwnReason() {
        let store = HistoryStore(container: nil)
        let opening = store.availability.reason

        store.clearAll()
        store.search = "wget"

        #expect(store.availability.isAvailable == false)
        #expect(store.availability.reason == opening)
    }
}
