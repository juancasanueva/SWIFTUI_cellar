import Catalog
import Foundation
import Observation
import SwiftData

/// One history entry as the UI reads it — a plain value, never a `@Model`
/// instance (design D3).
public struct HistoryRecord: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let date: Date
    /// `nil` for a grouped `upgradeAll`, which names no package.
    public let packageID: PackageID?
    public let name: String
    public let verb: String
    public let versionFrom: String
    public let versionTo: String
    public let outcomeRaw: String
    public let exitStatus: Int?
    public let argv: [String]
    /// What the copy affordance produces, character for character.
    public let commandText: String

    /// The version transition Cellar intended at submission, when both ends
    /// were known.
    public var versions: (from: String, to: String)? {
        guard !versionFrom.isEmpty, !versionTo.isEmpty else { return nil }
        return (versionFrom, versionTo)
    }

    /// Every control the history projection exposes for one entry.
    ///
    /// Enumerable rather than a set of booleans, and deliberately listing the
    /// two that are never produced, so "no delete or remove control is present"
    /// is a claim a test can make about the whole surface — the same technique
    /// `ActivityItem.Control` uses (installation-history IH6 sc4).
    public enum Control: Sendable, Equatable, CaseIterable {
        case copyCommand
        /// Never produced. Clearing is all-or-nothing behind a confirmation;
        /// selective deletion is out of scope by decision, not by omission.
        case delete
        case remove
    }

    public var controls: [Control] { [.copyCommand] }

    init(_ entry: HistoryEntry) {
        id = entry.id
        date = entry.date
        packageID = entry.packageID
        name = entry.name
        verb = entry.verb
        versionFrom = entry.versionFrom
        versionTo = entry.versionTo
        outcomeRaw = entry.outcomeRaw
        exitStatus = entry.exitStatus
        argv = entry.argv
        commandText = entry.commandText
    }
}

/// The durable record of every mutation Cellar performed, as a searchable,
/// newest-first projection (installation-history IH4, IH5, IH6).
///
/// `@MainActor @Observable` over the container's `mainContext`, like
/// `MetadataStore`. It publishes `HistoryRecord` values, so no `@Model` instance
/// leaves this module.
@MainActor
@Observable
public final class HistoryStore {
    public private(set) var availability: StoreAvailability

    /// The current projection: newest first, filtered by `search`.
    public private(set) var records: [HistoryRecord] = []

    /// Why the last write did not land, if it did not.
    ///
    /// Surfaced here rather than thrown, because the caller is a mutation's
    /// terminal path and a failed *record* must never change a *mutation's*
    /// reported outcome (IH7).
    public private(set) var lastError: String?

    /// The search term. Empty returns every entry (IH5 sc1).
    public var search: String = "" {
        didSet {
            guard search != oldValue else { return }
            reload()
        }
    }

    /// How `clearAll()` performs the deletion.
    ///
    /// A seam rather than a hard-coded statement, so the *failure* branch is
    /// provable in the `swift test` loop. Forcing a real SwiftData delete to
    /// throw needs a read-only directory or a corrupted file, both of which are
    /// flaky and test SwiftData rather than this store's reaction to it — the
    /// same reasoning behind `ProcessLaunching` and `CatalogSource` (design D5).
    typealias Clearing = @MainActor (ModelContext) throws -> Void

    /// The real deletion: one statement over one model, then one save.
    static let deleteEveryEntry: Clearing = { context in
        try context.delete(model: HistoryEntry.self)
        try context.save()
    }

    @ObservationIgnored private let container: ModelContainer?
    @ObservationIgnored private let clearing: Clearing

    private var context: ModelContext? { container?.mainContext }

    init(container: ModelContainer?, clearing: @escaping Clearing) {
        self.container = container
        self.clearing = clearing
        availability = container == nil
            ? .unavailable(reason: "The local history store could not be opened.")
            : .available
        reload()
    }

    public convenience init(container: ModelContainer?) {
        self.init(container: container, clearing: HistoryStore.deleteEveryEntry)
    }

    /// Opens the store at `url`, folding a failure into `.unavailable(reason:)`
    /// exactly as `MetadataStore` does (design D4).
    public convenience init(at url: URL = PersistenceContainer.defaultURL()) {
        do {
            self.init(container: try PersistenceContainer.onDisk(at: url))
        } catch {
            self.init(unavailable: error)
        }
    }

    /// One open failure, folded into a reason. Internal so `LocalStores` can
    /// give both stores the *same* reason when the one container it opens for
    /// them fails (design D6).
    convenience init(unavailable error: any Error) {
        self.init(container: nil)
        availability = .unavailable(reason: MetadataStore.describe(error))
    }

    // MARK: - Reading

    /// Rebuilds the projection from the store.
    ///
    /// **No `fetchLimit`.** Keep-all retention (IH4) means an empty search MUST
    /// return every entry, and truncating the view would quietly contradict the
    /// retention promise while looking exactly like it was honoured. Volume is
    /// bounded by what the user did *through Cellar*, which is small; if it ever
    /// measures slow, pagination is an additive change to this query rather than
    /// to the schema.
    public func reload() {
        guard let context else {
            records = []
            return
        }
        do {
            let term = search
            let descriptor = FetchDescriptor<HistoryEntry>(
                predicate: #Predicate { entry in
                    term.isEmpty
                        || entry.name.localizedStandardContains(term)
                        || entry.verb.localizedStandardContains(term)
                        || entry.commandText.localizedStandardContains(term)
                },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            records = try context.fetch(descriptor).map(HistoryRecord.init)
            availability = .available
        } catch {
            records = []
            availability = .unavailable(reason: MetadataStore.describe(error))
        }
    }

    // MARK: - Appending (IH1, IH4)

    /// Appends one row, then republishes the projection.
    ///
    /// Append-only: no entry is ever rewritten or amended, so a later operation
    /// on the same package produces a new row rather than updating the previous
    /// one. `#Unique` on `id` means a **replayed** write of the same terminal
    /// outcome upserts instead of double-logging, which is a different thing
    /// from amending — the row it lands on is the one it already wrote.
    ///
    /// Non-throwing on purpose: the caller is `OperationCenter.finish(_:with:)`,
    /// and a failure here must cost the history entry and nothing else (IH7).
    func append(_ entry: HistoryEntry) {
        guard let context else { return }
        do {
            context.insert(entry)
            try context.save()
            lastError = nil
        } catch {
            context.rollback()
            lastError = MetadataStore.describe(error)
        }
        reload()
    }

    // MARK: - Clearing

    /// Removes every entry and **nothing else** (IH6).
    ///
    /// One statement, over one model: favorites, notes and snoozes live in
    /// different models with no relationship to this one, so there is no
    /// cascade that could reach them. The confirmation itself belongs to the
    /// view — this is the action it confirms, and it is all-or-nothing because
    /// no selective deletion exists to offer instead.
    ///
    /// A clear that fails is **observable**: it rolls back, rebuilds the
    /// projection so every surviving entry is readable again, and only then
    /// applies the reason. That order is the whole fix — `reload()` sets
    /// `.available` on a successful fetch, so applying the failure first (what
    /// this did) meant the reload erased it and a failed clear was reported as a
    /// healthy history. Inline surface only: `availability` and `lastError`, set
    /// exactly as `append` sets them — no alert and no retry affordance
    /// (installation-history IH6, design D4).
    public func clearAll() {
        guard let context else { return }
        do {
            try clearing(context)
            reload()
            lastError = nil
        } catch {
            context.rollback()
            let reason = MetadataStore.describe(error)
            reload()
            availability = .unavailable(reason: reason)
            lastError = reason
        }
    }
}
