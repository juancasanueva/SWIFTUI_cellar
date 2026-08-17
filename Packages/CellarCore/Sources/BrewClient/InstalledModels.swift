import Catalog
import Foundation

/// One installed version of a package.
///
/// A formula can have several; a cask has exactly one, synthesised from its
/// plain-string installed version. Keeping kegs as a list is what makes a
/// multi-version formula *representable* rather than truncated (design D3).
public struct InstalledKeg: Sendable, Hashable {
    public let version: String
    /// From the record's install timestamp, interpreted as Unix epoch seconds.
    public let installedAt: Date
    /// Whether this keg was installed because the user asked for it.
    public let installedOnRequest: Bool

    public init(version: String, installedAt: Date, installedOnRequest: Bool) {
        self.version = version
        self.installedAt = installedAt
        self.installedOnRequest = installedOnRequest
    }
}

/// One installed package, projected from the single `brew info --installed`
/// snapshot.
///
/// Self-sufficient on purpose: the payload already carries `desc`, `homepage`,
/// the published version and every status flag, so the Installed list renders
/// with no catalog at all. The catalog decorates, it does not supply (design D5).
public struct InstalledPackage: Sendable, Hashable, Identifiable {
    public var id: PackageID { PackageID(kind: kind, name: name) }

    public let kind: PackageKind
    /// The token brew installs by.
    public let name: String
    /// What a human calls it. Equals `name` for formulae.
    public let displayName: String
    public let desc: String?
    public let homepage: URL?
    public let tap: String
    /// The version the published record currently offers.
    public let catalogVersion: String
    /// Every installed keg, newest last. Never empty.
    public let kegs: [InstalledKeg]
    /// The keg brew linked, or the newest one when nothing is linked.
    public let primaryKeg: InstalledKeg
    /// Exact payload state. `nil` means Homebrew reports the formula as unlinked.
    public let linkedKeg: String?
    /// The snapshot's own outdated flag, verbatim.
    ///
    /// Kept separate from `isOutdated` because the cask rule narrows it
    /// (design D4) and a reviewer has to be able to see both.
    public let snapshotOutdated: Bool
    public let isPinned: Bool
    public let pinnedVersion: String?
    /// Casks only. `nil` means the payload did not declare it, which is not the
    /// same fact as declaring `false` (installed-inventory II2).
    public let declaresAutoUpdates: Bool?

    public init(
        kind: PackageKind,
        name: String,
        displayName: String,
        desc: String?,
        homepage: URL?,
        tap: String,
        catalogVersion: String,
        kegs: [InstalledKeg],
        primaryKeg: InstalledKeg,
        snapshotOutdated: Bool,
        isPinned: Bool,
        pinnedVersion: String?,
        declaresAutoUpdates: Bool?,
        linkedKeg: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.displayName = displayName
        self.desc = desc
        self.homepage = homepage
        self.tap = tap
        self.catalogVersion = catalogVersion
        self.kegs = kegs
        self.primaryKeg = primaryKeg
        self.linkedKeg = linkedKeg
        self.snapshotOutdated = snapshotOutdated
        self.isPinned = isPinned
        self.pinnedVersion = pinnedVersion
        self.declaresAutoUpdates = declaresAutoUpdates
    }

    /// The version currently in use.
    public var installedVersion: String { primaryKeg.version }

    /// When the primary keg was installed.
    public var installedAt: Date { primaryKeg.installedAt }

    // MARK: - Derived state (design D4)

    /// Whether the app keeps itself up to date.
    ///
    /// `nil` folds to `false` here and only here: "not declared" is a fact worth
    /// preserving through decode, but at the point of decision the question is
    /// binary (installed-inventory II2, II4).
    public var isSelfUpdating: Bool { declaresAutoUpdates == true }

    /// Whether Cellar should report this package as outdated.
    ///
    /// For a formula this is the snapshot's flag verbatim — it matches
    /// `brew outdated` exactly. For a cask the flag is *conjoined* with the
    /// auto-updates exclusion, which brew's own snapshot already applies: the
    /// duplication is deliberate, so a future brew change cannot make Cellar
    /// start nagging about apps that update themselves (installed-inventory
    /// II4).
    public var isOutdated: Bool {
        switch kind {
        case .formula: snapshotOutdated
        case .cask: snapshotOutdated && !isSelfUpdating
        }
    }

    /// Whether a self-updating cask is behind the version its record publishes.
    ///
    /// The greedy signal without the greedy probe: the same record carries both
    /// numbers, so `brew outdated --greedy` is never spawned. Informational
    /// only — it feeds a separate section and the detail's neutral "Updates
    /// itself" wording, never the outdated set, the count or the update badge
    /// (installed-inventory II5).
    public var hasNewerVersion: Bool {
        isSelfUpdating && installedVersion != catalogVersion
    }

    /// Whether the user asked for this package, rather than getting it as
    /// somebody else's dependency.
    ///
    /// The payload carries no `installed_as_dependency` the projection trusts,
    /// so this is the *presence of an on-request marker*, not the absence of a
    /// dependency one. Any keg counts: pulled in first and asked for later is
    /// still asked for. A record with no marker at all reads as on request, so
    /// nothing deliberate can be hidden by the default view (II3).
    public var isOnRequest: Bool {
        kegs.contains(where: \.installedOnRequest)
    }
}

/// An immutable snapshot of what this machine has installed.
///
/// `Sendable` by composition, so a freshly decoded inventory crosses back to the
/// main actor with no lock and no `@unchecked`.
public struct InstalledInventory: Sendable, Hashable {
    /// Every installed package, sorted by name.
    public let packages: [InstalledPackage]
    /// Records the payload carried but this build could not read.
    public let skippedRecordCount: Int

    /// Everything installed, as a membership set Browse can intersect against.
    public let installedIDs: Set<PackageID>
    /// Everything Cellar reports as outdated. Self-updating casks are excluded,
    /// so the Browse filter and the Installed list agree by construction
    /// (installed-inventory II8).
    public let outdatedIDs: Set<PackageID>

    private let positions: [PackageID: Int]

    /// Both membership sets are built here — once, in the same off-main pass
    /// that produced the projection — rather than recomputed per query
    /// (design D5).
    public init(packages: [InstalledPackage], skippedRecordCount: Int = 0) {
        let ordered = packages.sorted(by: Self.precedes)
        self.packages = ordered
        self.skippedRecordCount = skippedRecordCount
        positions = Dictionary(
            ordered.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        installedIDs = Set(ordered.map(\.id))
        outdatedIDs = Set(ordered.lazy.filter(\.isOutdated).map(\.id))
    }

    /// Name first, then namespace. Total by construction — `(name, kind)` is
    /// unique — so two adjacent rows can never swap between refreshes.
    private static func precedes(_ lhs: InstalledPackage, _ rhs: InstalledPackage) -> Bool {
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.kind == .formula && rhs.kind == .cask
    }

    /// The badge count. Counts `isOutdated` only, so a self-updating cask with a
    /// newer version is visible in its own section and invisible here.
    public var outdatedCount: Int { outdatedIDs.count }

    /// A snapshot of a machine with nothing installed — or of no machine at all.
    /// A valid value either way, never an error (installed-inventory II9).
    public static let empty = InstalledInventory(packages: [])

    public var isEmpty: Bool { packages.isEmpty }

    /// The record for an id, or `nil`. A miss is an ordinary answer.
    public func package(_ id: PackageID) -> InstalledPackage? {
        positions[id].map { packages[$0] }
    }

    /// The Installed list, under the dependency toggle.
    ///
    /// The default is on-request only, because a machine with 160 packages
    /// installed usually has ~40 the user chose and 120 that came along for the
    /// ride (installed-inventory II3).
    public func packages(includingDependencies: Bool) -> [InstalledPackage] {
        includingDependencies ? packages : packages.filter(\.isOnRequest)
    }
}
