import Foundation
import SwiftData

/// Every locally persisted store, over **one** `ModelContainer`.
///
/// The composition root used to build a `MetadataStore` and a `HistoryStore`
/// separately, and each opened its own container over the same store file. Two
/// containers over one file is not a visible bug — it is a data-integrity
/// hazard: two independent stacks, two coordinators, two sets of pending
/// changes, all writing the same SQLite file.
///
/// Opening the container here rather than inline in the app target keeps the
/// error→reason fold inside the package that owns it, makes the one-container
/// rule provable by `swift test`, and gives M3-1's services store somewhere to
/// join instead of opening a third (design D6). Both stores keep their
/// `init(at:)` convenience initialisers, which tests still use.
///
/// A struct rather than a class: it holds no state of its own beyond the two
/// stores, and both of those are reference types the caller keeps.
@MainActor
public struct LocalStores {
    public let metadata: MetadataStore
    public let history: HistoryStore

    /// The one container both stores were given, or `nil` when it could not be
    /// opened. Internal: the invariant is worth asserting, not exporting.
    let container: ModelContainer?

    /// Opens the store at `url` once and injects it into both stores.
    ///
    /// Never throws. An open failure folds into **both** stores'
    /// `.unavailable(reason:)` carrying the same reason, because it is one
    /// failure — the alternative is an app whose two halves disagree about why
    /// local storage is off. A `try!` here would turn a recoverable disk problem
    /// into a boot loop (design D4).
    public init(at url: URL = PersistenceContainer.defaultURL()) {
        do {
            let container = try PersistenceContainer.onDisk(at: url)
            self.container = container
            metadata = MetadataStore(container: container)
            history = HistoryStore(container: container)
        } catch {
            container = nil
            metadata = MetadataStore(unavailable: error)
            history = HistoryStore(unavailable: error)
        }
    }
}
