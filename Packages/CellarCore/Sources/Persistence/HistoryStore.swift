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

    /// The search term. Empty returns every entry (IH5 sc1).
    public var search: String = "" {
        didSet {
            guard search != oldValue else { return }
            reload()
        }
    }

    @ObservationIgnored private let container: ModelContainer?

    private var context: ModelContext? { container?.mainContext }

    public init(container: ModelContainer?) {
        self.container = container
        availability = container == nil
            ? .unavailable(reason: "The local history store could not be opened.")
            : .available
        reload()
    }

    /// Opens the store at `url`, folding a failure into `.unavailable(reason:)`
    /// exactly as `MetadataStore` does (design D4).
    public convenience init(at url: URL = PersistenceContainer.defaultURL()) {
        do {
            self.init(container: try PersistenceContainer.onDisk(at: url))
        } catch {
            self.init(container: nil)
            availability = .unavailable(reason: MetadataStore.describe(error))
        }
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

    // MARK: - Clearing

    /// Removes every entry and **nothing else** (IH6).
    ///
    /// One statement, over one model: favorites, notes and snoozes live in
    /// different models with no relationship to this one, so there is no
    /// cascade that could reach them. The confirmation itself belongs to the
    /// view — this is the action it confirms, and it is all-or-nothing because
    /// no selective deletion exists to offer instead.
    public func clearAll() {
        guard let context else { return }
        do {
            try context.delete(model: HistoryEntry.self)
            try context.save()
        } catch {
            context.rollback()
            availability = .unavailable(reason: MetadataStore.describe(error))
        }
        reload()
    }
}
