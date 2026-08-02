import Foundation
import SwiftData

/// Version 1 of the local metadata store's schema (design D2).
///
/// V1 is genesis: there is nothing to migrate *from*. The versioned schema and
/// its migration plan exist from day one anyway, so M4's `DismissedCVE` and M6's
/// `Settings` arrive as `.lightweight` stages rather than as a rewrite.
///
/// Phase 0 lands the schema with the single model the gate confirmations need.
/// The remaining models (`Snooze`, `HistoryEntry`) and the remaining
/// `PackageMeta` fields land in Phase 4, still inside V1 — nothing has shipped,
/// so this is not a migration.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] { [PackageMeta.self] }
}

/// Per-package local metadata, keyed by the `(kind, name)` identity the catalog
/// and the inventory already use (local-package-metadata LPM1).
///
/// `PackageKind` persists as its `rawValue` rather than as a `Codable` enum, so
/// `#Predicate` stays a string comparison and a future kind cannot break the
/// decoding of existing rows.
@Model
public final class PackageMeta {
    public var kindRaw: String
    public var name: String
    public var isFavorite: Bool = false

    #Unique<PackageMeta>([\.kindRaw, \.name])

    public init(kindRaw: String, name: String, isFavorite: Bool = false) {
        self.kindRaw = kindRaw
        self.name = name
        self.isFavorite = isFavorite
    }
}
