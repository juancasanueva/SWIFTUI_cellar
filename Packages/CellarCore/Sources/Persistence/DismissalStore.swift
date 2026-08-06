import Catalog
import Foundation
import Observation
import SecurityKit
import SwiftData

// MARK: - The value boundary

/// What a dismissal is stored under.
///
/// `cveID` is deliberately **not** part of it, and `DismissalKey`'s is therefore
/// ignored on lookup. OSV adds CVE aliases to advisories over time; a dismissal
/// that stopped applying the day an alias appeared would look exactly like the
/// re-surfacing an upgrade is supposed to cause, and the user would have no way
/// to tell the two apart.
public struct DismissalIdentity: Sendable, Hashable {
    public let advisoryID: String
    public let packageID: PackageID
    public let version: String

    public init(advisoryID: String, packageID: PackageID, version: String) {
        self.advisoryID = advisoryID
        self.packageID = packageID
        self.version = version
    }

    public init(_ key: DismissalKey) {
        self.init(
            advisoryID: key.advisoryID,
            packageID: key.packageID,
            version: key.installedVersion
        )
    }
}

/// One stored dismissal, as a value.
///
/// `MetadataStore`'s rule, restated: no `@Model` instance leaves this module, so
/// every consumer — a `@MainActor` view, a `@Sendable` matcher closure — holds
/// something that outlives the context it was read from.
public struct DismissalRecord: Sendable, Hashable {
    public let advisoryID: String
    /// `nil` when the advisory publishes no CVE alias, rather than the empty
    /// string the column stores. Absence-is-empty-string is a storage rule; it
    /// is not a fact about advisories, and letting it leak would make `""` a
    /// CVE identifier everywhere downstream.
    public let cveID: String?
    public let packageID: PackageID
    public let version: String
    public let dismissedAt: Date
    /// `""` when the user wrote none.
    public let note: String

    public init(
        advisoryID: String,
        cveID: String?,
        packageID: PackageID,
        version: String,
        dismissedAt: Date,
        note: String
    ) {
        self.advisoryID = advisoryID
        self.cveID = cveID
        self.packageID = packageID
        self.version = version
        self.dismissedAt = dismissedAt
        self.note = note
    }

    public var identity: DismissalIdentity {
        DismissalIdentity(advisoryID: advisoryID, packageID: packageID, version: version)
    }
}

/// Every dismissal, keyed by the identity it was taken under.
public typealias DismissalSnapshot = [DismissalIdentity: DismissalRecord]

// MARK: - The store

/// Dismissed findings, as the app reads and writes them.
///
/// The `MetadataStore` shape verbatim — `@MainActor @Observable` over the shared
/// container's `mainContext`, explicit `save()`, snapshot republished after each
/// write, and a failure that is a *state* rather than a thrown error. Three
/// things are specific to this store:
///
/// - **A dismissal is the presence of a row.** There is no `isDismissed` column
///   to fall out of step with the row's existence, and `restore` deletes rather
///   than clearing a flag.
/// - **The installed version is part of the key.** An upgrade is a key miss, so
///   a finding re-surfaces with no user action and nothing swept.
/// - **It changes no coverage state.** This store answers one question — has the
///   user already answered *this* finding — and the matcher carries the answer
///   as a flag on the finding, never by removing it.
///
/// This is the **only** file in `Sources/Persistence/` that imports
/// `SecurityKit`, and `SnoozeProjectionTests` asserts that exhaustively over the
/// whole directory. The import buys exactly two types — `DismissalKey` and
/// `DismissalLookup` — so the matcher and this store agree on what identifies a
/// finding without either one owning the other's vocabulary.
@MainActor
@Observable
public final class DismissalStore {
    public private(set) var availability: StoreAvailability

    /// Every dismissal on the machine. Loaded whole: this is a handful of rows
    /// a user typed by hand, not an inventory.
    public private(set) var snapshot: DismissalSnapshot = [:]

    /// The last write failure, for surfacing beside the affordance that failed.
    public private(set) var lastError: String?

    /// Internal rather than private so "one container, every store" stays an
    /// invariant a test can state directly (design D6).
    @ObservationIgnored let container: ModelContainer?

    private var context: ModelContext? { container?.mainContext }

    public init(container: ModelContainer?) {
        self.container = container
        availability = container == nil
            ? .unavailable(reason: "The local metadata store could not be opened.")
            : .available
        reload()
    }

    public convenience init(at url: URL = PersistenceContainer.defaultURL()) {
        do {
            self.init(container: try PersistenceContainer.onDisk(at: url))
        } catch {
            self.init(unavailable: error)
        }
    }

    /// One open failure, folded into a reason, so `LocalStores` can give every
    /// store the *same* reason when the single container fails.
    convenience init(unavailable error: any Error) {
        self.init(container: nil)
        availability = .unavailable(reason: Self.describe(error))
    }

    // MARK: - Reading

    /// Every dismissal, newest first.
    public var records: [DismissalRecord] {
        snapshot.values.sorted { $0.dismissedAt > $1.dismissedAt }
    }

    public func isDismissed(_ key: DismissalKey) -> Bool {
        snapshot[DismissalIdentity(key)] != nil
    }

    /// The seam the matcher consults.
    ///
    /// A closure over the snapshot rather than a reference to this store, so the
    /// matcher stays pure and nothing main-isolated crosses into it.
    public var lookup: DismissalLookup {
        let dismissed = Set(snapshot.keys)
        return { dismissed.contains(DismissalIdentity($0)) }
    }

    // MARK: - Writing

    /// Records that the user has answered this finding at this exact version.
    ///
    /// Idempotent: dismissing an already-dismissed finding updates its note and
    /// its timestamp rather than writing a second row the unique key would
    /// reject.
    public func dismiss(_ key: DismissalKey, note: String = "", at date: Date = .now) {
        guard let context else { return }
        let identity = DismissalIdentity(key)

        do {
            if let existing = try row(for: identity, in: context) {
                existing.cveID = key.cveID ?? ""
                existing.note = note
                existing.dismissedAt = date
            } else {
                context.insert(
                    DismissedCVE(
                        advisoryID: key.advisoryID,
                        cveID: key.cveID ?? "",
                        kindRaw: key.packageID.kind.rawValue,
                        name: key.packageID.name,
                        version: key.installedVersion,
                        dismissedAt: date,
                        note: note
                    )
                )
            }
            try context.save()
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
        reload()
    }

    /// Undoes a dismissal by deleting its row.
    ///
    /// Reversibility is a delete rather than a flag, so a restored finding is
    /// indistinguishable from one that was never dismissed — including to the
    /// next `reload`.
    public func restore(_ key: DismissalKey) {
        guard let context else { return }
        do {
            if let existing = try row(for: DismissalIdentity(key), in: context) {
                context.delete(existing)
                try context.save()
            }
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
        reload()
    }

    /// Rebuilds the published snapshot from the store.
    ///
    /// An unreadable store reads empty and writes nothing: local metadata is
    /// the only thing lost, and the app still browses, installs and scans (D4).
    public func reload() {
        guard let context else {
            snapshot = [:]
            return
        }
        do {
            var rebuilt: DismissalSnapshot = [:]
            for row in try context.fetch(FetchDescriptor<DismissedCVE>()) {
                guard let packageID = row.packageID else { continue }
                let record = DismissalRecord(
                    advisoryID: row.advisoryID,
                    cveID: row.cveID.isEmpty ? nil : row.cveID,
                    packageID: packageID,
                    version: row.version,
                    dismissedAt: row.dismissedAt,
                    note: row.note
                )
                rebuilt[record.identity] = record
            }
            snapshot = rebuilt
        } catch {
            snapshot = [:]
            lastError = Self.describe(error)
        }
    }

    // MARK: -

    private func row(
        for identity: DismissalIdentity,
        in context: ModelContext
    ) throws -> DismissedCVE? {
        let advisoryID = identity.advisoryID
        let kindRaw = identity.packageID.kind.rawValue
        let name = identity.packageID.name
        let version = identity.version

        return try context.fetch(
            FetchDescriptor<DismissedCVE>(
                predicate: #Predicate {
                    $0.advisoryID == advisoryID
                        && $0.kindRaw == kindRaw
                        && $0.name == name
                        && $0.version == version
                }
            )
        ).first
    }

    private static func describe(_ error: any Error) -> String {
        (error as NSError).localizedDescription
    }
}
