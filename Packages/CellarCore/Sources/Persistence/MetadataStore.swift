import BrewClient
import Catalog
import Foundation
import Observation
import SwiftData

/// Favorites, notes and snoozes, as the app reads and writes them
/// (local-package-metadata LPM2, LPM3, LPM4, LPM6).
///
/// `@MainActor @Observable` over the container's `mainContext`, on the shipped
/// `InstalledStore`/`OperationCenter` exemplar (design D3). Three consequences
/// are deliberate:
///
/// - **It publishes values, never models.** `snapshot` is a
///   `[PackageID: PackageMetadata]`, so no `@Model` instance leaves this module
///   and every composition rule can be proven over values in `BrewClient`.
/// - **Writes `save()` explicitly** rather than relying on autosave, so a test
///   can assert durability without waiting for a run-loop turn — and the
///   snapshot is republished from the store *after* the save, so what the UI
///   reads is what the disk holds.
/// - **A failure is a state.** Nothing here throws at a caller: an unavailable
///   store reads empty and writes nothing (D4).
///
/// No `@Query`, no `.modelContainer(…)` scene modifier, no `@ModelActor`: every
/// write in this milestone is one user-initiated row on the main context.
@MainActor
@Observable
public final class MetadataStore {
    /// Whether metadata can be read and written at all right now.
    public private(set) var availability: StoreAvailability

    /// Every package with anything stored for it. Loaded whole — favorites,
    /// notes and snoozes are a few hundred tiny rows — and republished after
    /// each save.
    public private(set) var snapshot: MetadataSnapshot = [:]

    /// The last write failure, for surfacing beside the affordance that failed.
    /// Never thrown, and never allowed to reach an unrelated path.
    public private(set) var lastError: String?

    /// Internal rather than private so "one container, both stores" is an
    /// invariant a test can state directly rather than infer (design D6).
    @ObservationIgnored let container: ModelContainer?

    private var context: ModelContext? { container?.mainContext }

    public init(container: ModelContainer?) {
        self.container = container
        availability = container == nil
            ? .unavailable(reason: "The local metadata store could not be opened.")
            : .available
        reload()
    }

    /// Opens the store at `url`, folding a failure into `.unavailable(reason:)`.
    ///
    /// `ModelContainer(for:migrationPlan:configurations:)` throws, and a `try!`
    /// at launch would turn a recoverable disk problem into a boot loop (D4).
    public convenience init(at url: URL = PersistenceContainer.defaultURL()) {
        do {
            self.init(container: try PersistenceContainer.onDisk(at: url))
        } catch {
            self.init(unavailable: error)
        }
    }

    /// One open failure, folded into a reason. Internal rather than private so
    /// `LocalStores` can give both stores the *same* reason when the single
    /// container it opens for them fails (design D6).
    convenience init(unavailable error: any Error) {
        self.init(container: nil)
        availability = .unavailable(reason: Self.describe(error))
    }

    // MARK: - Reading

    /// What is stored for `id`. A package with nothing stored reports
    /// `PackageMetadata.none` — not an absent value, and never an error
    /// (LPM2 sc3).
    public func metadata(for id: PackageID) -> PackageMetadata {
        snapshot[id] ?? .none
    }

    public func isFavorite(_ id: PackageID) -> Bool { metadata(for: id).isFavorite }

    /// The note, or `nil` when there is none. Storing an empty note **is**
    /// having no note (LPM3).
    public func note(for id: PackageID) -> String? {
        let note = metadata(for: id).note
        return note.isEmpty ? nil : note
    }

    public func snoozedVersion(for id: PackageID) -> String? { metadata(for: id).snoozedVersion }

    /// The favorite membership set, in the shape the installed-state filters
    /// already intersect against (installed-inventory II8).
    public var favoriteIDs: Set<PackageID> {
        Set(snapshot.filter(\.value.isFavorite).keys)
    }

    // MARK: - Writing

    /// Spawns no process, submits no operation, and changes no installed state:
    /// it writes one row (LPM2 sc2).
    public func setFavorite(_ isFavorite: Bool, for id: PackageID) {
        write { context in
            let meta = try Self.meta(for: id, in: context)
            meta.isFavorite = isFavorite
            meta.updatedAt = .now
        }
    }

    public func toggleFavorite(_ id: PackageID) {
        setFavorite(!isFavorite(id), for: id)
    }

    /// Stores `text` verbatim: no length cap, no markup interpretation, no
    /// normalisation of whitespace or newlines (LPM3 sc1).
    public func setNote(_ text: String, for id: PackageID) {
        write { context in
            let meta = try Self.meta(for: id, in: context)
            meta.note = text
            meta.updatedAt = .now
        }
    }

    /// Records the exact version currently offered for `id`, and nothing else —
    /// no duration, no expiry, no reading of the clock that governs when the
    /// snooze ends (LPM4 sc1–2). Re-snoozing replaces (sc3).
    public func snooze(_ id: PackageID, offering version: String) {
        write { context in
            if let existing = try Self.snooze(for: id, in: context) {
                existing.snoozedVersion = version
            } else {
                context.insert(
                    Snooze(kindRaw: id.kind.rawValue, name: id.name, snoozedVersion: version)
                )
            }
        }
    }

    /// Removes the snooze entirely, leaving the favorite and the note alone.
    public func unsnooze(_ id: PackageID) {
        write { context in
            if let existing = try Self.snooze(for: id, in: context) {
                context.delete(existing)
            }
        }
    }

    // MARK: - The one write path

    /// Performs one mutation, saves it explicitly, and republishes the snapshot
    /// from the store.
    ///
    /// The single place a write can fail, so a degraded store is one branch
    /// rather than one per affordance.
    private func write(_ mutate: (ModelContext) throws -> Void) {
        guard let context else { return }
        do {
            try mutate(context)
            try context.save()
            lastError = nil
        } catch {
            context.rollback()
            lastError = Self.describe(error)
        }
        reload()
    }

    /// Rebuilds the published snapshot from what is actually stored.
    public func reload() {
        guard let context else {
            snapshot = [:]
            return
        }
        do {
            var rebuilt: MetadataSnapshot = [:]
            for meta in try context.fetch(FetchDescriptor<PackageMeta>()) {
                guard let id = meta.packageID else { continue }
                rebuilt[id] = PackageMetadata(isFavorite: meta.isFavorite, note: meta.note)
            }
            for snooze in try context.fetch(FetchDescriptor<Snooze>()) {
                guard let id = snooze.packageID else { continue }
                let existing = rebuilt[id] ?? .none
                rebuilt[id] = PackageMetadata(
                    isFavorite: existing.isFavorite,
                    note: existing.note,
                    snoozedVersion: snooze.snoozedVersion
                )
            }
            snapshot = rebuilt
            availability = .available
        } catch {
            snapshot = [:]
            availability = .unavailable(reason: Self.describe(error))
        }
    }

    // MARK: - Fetch-or-create on the joint key

    /// `#Unique([\.kindRaw, \.name])` upserts on this toolchain (gate G2,
    /// confirmed in `PersistenceSpikeTests`), but fetch-or-create is what keeps
    /// a *partial* write — setting a note on a package that is already a
    /// favorite — from replacing the row it should have amended.
    private static func meta(for id: PackageID, in context: ModelContext) throws -> PackageMeta {
        let kindRaw = id.kind.rawValue
        let name = id.name
        let existing = try context.fetch(
            FetchDescriptor<PackageMeta>(
                predicate: #Predicate { $0.kindRaw == kindRaw && $0.name == name }
            )
        )
        if let found = existing.first { return found }

        let created = PackageMeta(kindRaw: kindRaw, name: name)
        context.insert(created)
        return created
    }

    private static func snooze(for id: PackageID, in context: ModelContext) throws -> Snooze? {
        let kindRaw = id.kind.rawValue
        let name = id.name
        return try context.fetch(
            FetchDescriptor<Snooze>(
                predicate: #Predicate { $0.kindRaw == kindRaw && $0.name == name }
            )
        ).first
    }

    /// One rendering of a failure, so every reason string reads the same way.
    static func describe(_ error: any Error) -> String {
        let described = (error as NSError).localizedDescription
        return described.isEmpty ? String(describing: error) : described
    }
}
