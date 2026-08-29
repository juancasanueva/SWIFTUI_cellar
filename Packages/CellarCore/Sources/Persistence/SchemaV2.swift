import Catalog
import Foundation
import SwiftData

// MARK: - Schema V2 (design D2)
//
// One model added, three models untouched. Every V1 rule holds here unchanged —
// primitives only, `PackageKind` as its `rawValue`, absence as the empty string,
// no `@Relationship`, no `@Transient` — and `DismissedCVE` was shaped to obey
// them rather than to be convenient:
//
// 1. **No relationship to `PackageMeta`.** A dismissal must survive an uninstall
//    and a metadata delete, exactly as history does. A cascade rule would be
//    wrong and a nullify rule would buy nothing the joint key does not give.
// 2. **The version is part of the key, not a field beside it.** That is the
//    whole mechanic behind "an upgrade re-surfaces a dismissed finding": nothing
//    is invalidated by hand, the key simply stops matching.
// 3. **No `Bool` anywhere.** A dismissal is the *presence* of a row. There is no
//    `isDismissed` column to get out of step with the row's existence.

/// Version 2 of the local metadata store's schema.
///
/// The three V1 models are the same types, not copies: SwiftData compares the
/// stored shape, and re-declaring identical models here would invite exactly the
/// silent drift `MigrationTests.theThreeV1ModelsAreUnchangedInV2` exists to
/// catch. The migration is therefore one added entity and nothing else, which is
/// what makes `.lightweight` correct rather than merely convenient.
///
/// `HistoryEntry` is the archival `SchemaV1` shape, shared with V1: V3 grew the
/// live class a column, and this version must keep describing the store its
/// stamp actually wrote.
public enum SchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [PackageMeta.self, Snooze.self, SchemaV1.HistoryEntry.self, DismissedCVE.self]
    }
}

/// One finding the user has answered, scoped to the exact advisory, package and
/// installed version (vulnerability-scanning: dismissal is scoped to the exact
/// finding and installed version).
///
/// ## Why the key names the advisory rather than the CVE
///
/// The obvious key is `(cveID, kind, name, version)`, and it is wrong for the
/// data this app actually receives. Many OSV records carry **no CVE alias at
/// all** — `GHSA-…`, `RUSTSEC-…` and `PYSEC-…` records routinely do not — so a
/// CVE-keyed row would store them all under the empty string, and dismissing one
/// of them would silently dismiss every other unaliased finding for the same
/// package at the same version. `advisoryID` is present on every record and
/// identifies exactly one of them.
///
/// `cveID` is still stored, because it is what the user sees, what NVD
/// enrichment is keyed by, and what a support conversation quotes. It is
/// metadata on the row, not the row's identity — which also means an alias
/// appearing on an advisory *after* it was dismissed cannot revoke the dismissal.
@Model
public final class DismissedCVE {
    /// The advisory's own identifier in the database that published it.
    public var advisoryID: String
    /// The CVE alias, or `""` when the advisory has none.
    public var cveID: String
    public var kindRaw: String
    public var name: String
    /// The exact installed version the dismissal was taken against. An upgrade
    /// changes it, the key stops matching, and the finding re-surfaces with no
    /// user action and no row deleted.
    public var version: String
    public var dismissedAt: Date
    /// Why, in the user's words. `""` means no note.
    public var note: String = ""

    #Unique<DismissedCVE>([\.advisoryID, \.kindRaw, \.name, \.version])

    public init(
        advisoryID: String,
        cveID: String = "",
        kindRaw: String,
        name: String,
        version: String,
        dismissedAt: Date = .now,
        note: String = ""
    ) {
        self.advisoryID = advisoryID
        self.cveID = cveID
        self.kindRaw = kindRaw
        self.name = name
        self.version = version
        self.dismissedAt = dismissedAt
        self.note = note
    }

    public var packageID: PackageID? { PackageIdentity.id(kindRaw: kindRaw, name: name) }
}
