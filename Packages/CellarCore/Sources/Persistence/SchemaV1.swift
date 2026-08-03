import Catalog
import Foundation
import SwiftData

// MARK: - Schema V1 (design D2)
//
// Three independent models, primitives only. Four rules hold across all of them,
// and each one is a decision rather than a default:
//
// 1. **`PackageKind` persists as its `rawValue`, not as a `Codable` enum.**
//    `#Predicate` stays a string comparison, and a kind added in a later
//    milestone cannot break the decoding of rows written today.
// 2. **Absence is the empty string, never `Optional`.** A package name can never
//    be empty — `MutationName.isSafe` refuses it — so `name == ""` unambiguously
//    means "this row names no package" (an `upgradeAll` entry). Every
//    `#Predicate` therefore stays non-optional, which is the shape the macro
//    handles best.
// 3. **`MutationOutcome` persists as `outcomeRaw` + `exitStatus`, not as a
//    `Codable` enum.** The domain enum carries associated values
//    (`.failed(status:)`, `.abandoned(after:)`) and will grow; pinning the
//    on-disk shape to it would make every future outcome a migration.
// 4. **`commandText` is a deliberate denormalisation** of
//    `argv.joined(separator: " ")`. `#Predicate` cannot express substring
//    matching across a `[String]`, and history search must reach the argv.
//
// **No `@Relationship` anywhere in V1**, and that is load-bearing rather than an
// omission: history must survive both an uninstall *and* a metadata delete. A
// cascade rule from `PackageMeta` would be exactly wrong, and a nullify rule
// would buy nothing the joint key does not already give. `@Transient` is unused
// too, so its default-value trap cannot bite.

/// Version 1 of the local metadata store's schema.
///
/// V1 is genesis: there is nothing to migrate *from*. The versioned schema and
/// its migration plan exist from day one anyway, so a later milestone's model
/// arrives as a `.lightweight` stage rather than as a rewrite.
public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [PackageMeta.self, Snooze.self, HistoryEntry.self]
    }
}

/// Per-package local metadata, keyed by the `(kind, name)` identity the catalog
/// and the inventory already use (local-package-metadata LPM1).
@Model
public final class PackageMeta {
    public var kindRaw: String
    public var name: String
    public var isFavorite: Bool = false
    /// Plain text, verbatim. No length cap, no markup, no normalisation
    /// (LPM3). Empty means "no note".
    public var note: String = ""
    public var updatedAt: Date

    #Unique<PackageMeta>([\.kindRaw, \.name])

    public init(
        kindRaw: String,
        name: String,
        isFavorite: Bool = false,
        note: String = "",
        updatedAt: Date = .now
    ) {
        self.kindRaw = kindRaw
        self.name = name
        self.isFavorite = isFavorite
        self.note = note
        self.updatedAt = updatedAt
    }

    public var packageID: PackageID? { PackageIdentity.id(kindRaw: kindRaw, name: name) }
}

/// One snooze, scoped to a version and to nothing else (LPM4).
///
/// There is deliberately **no duration, no expiry and no timestamp that governs
/// when the snooze ends**: `createdAt` is provenance, never policy. That is what
/// makes snooze behaviour reproducible with no clock seam at all.
@Model
public final class Snooze {
    public var kindRaw: String
    public var name: String
    /// The exact version string the snooze was taken against.
    public var snoozedVersion: String
    public var createdAt: Date

    #Unique<Snooze>([\.kindRaw, \.name])

    public init(kindRaw: String, name: String, snoozedVersion: String, createdAt: Date = .now) {
        self.kindRaw = kindRaw
        self.name = name
        self.snoozedVersion = snoozedVersion
        self.createdAt = createdAt
    }

    public var packageID: PackageID? { PackageIdentity.id(kindRaw: kindRaw, name: name) }
}

/// One durable record of a mutation Cellar itself performed
/// (installation-history IH1).
///
/// `id` is the `ActivityItem`'s id, and `#Unique` on it means a replayed write
/// cannot double-log.
@Model
public final class HistoryEntry {
    public var id: UUID
    public var date: Date
    /// `""` when the entry names no package — an `upgradeAll`.
    public var kindRaw: String
    public var name: String
    public var verb: String
    /// `""` when the transition was not known at submission.
    public var versionFrom: String
    public var versionTo: String
    public var outcomeRaw: String
    public var exitStatus: Int?
    public var argv: [String]
    /// `argv.joined(separator: " ")`, denormalised so search can reach it.
    public var commandText: String

    #Unique<HistoryEntry>([\.id])

    public init(
        id: UUID,
        date: Date,
        kindRaw: String,
        name: String,
        verb: String,
        versionFrom: String,
        versionTo: String,
        outcomeRaw: String,
        exitStatus: Int?,
        argv: [String],
        commandText: String
    ) {
        self.id = id
        self.date = date
        self.kindRaw = kindRaw
        self.name = name
        self.verb = verb
        self.versionFrom = versionFrom
        self.versionTo = versionTo
        self.outcomeRaw = outcomeRaw
        self.exitStatus = exitStatus
        self.argv = argv
        self.commandText = commandText
    }

    public var packageID: PackageID? { PackageIdentity.id(kindRaw: kindRaw, name: name) }
}

/// The one place a stored `(kindRaw, name)` pair becomes a `PackageID` again.
///
/// Spelled once so "absence is the empty string" is decoded identically by all
/// three models, and so a row written with an unknown kind degrades to "names no
/// package" rather than trapping.
enum PackageIdentity {
    static func id(kindRaw: String, name: String) -> PackageID? {
        guard !name.isEmpty, let kind = PackageKind(rawValue: kindRaw) else { return nil }
        return PackageID(kind: kind, name: name)
    }
}
