import Foundation
import SwiftData

// MARK: - Schema V3 (design D2)

/// Version 3 of the local metadata store's schema.
///
/// One column added to one model, nothing else: `HistoryEntry.failureTail`,
/// defaulted to `[]` so every row written before it existed decodes as "no
/// tail". The other three models are the same types V2 declared.
///
/// The changed model could not stay the same type: SwiftData locates a store's
/// current version by matching each declared schema's shape, so V1 and V2 must
/// keep describing the column-less `HistoryEntry` they actually stamped — the
/// archival `SchemaV1.HistoryEntry` — while this version declares the live
/// class that carries the new column.
public enum SchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [PackageMeta.self, Snooze.self, HistoryEntry.self, DismissedCVE.self]
    }
}
