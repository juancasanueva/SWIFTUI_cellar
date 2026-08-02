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
        declaresAutoUpdates: Bool?
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
        self.snapshotOutdated = snapshotOutdated
        self.isPinned = isPinned
        self.pinnedVersion = pinnedVersion
        self.declaresAutoUpdates = declaresAutoUpdates
    }

    /// The version currently in use.
    public var installedVersion: String { primaryKeg.version }

    /// When the primary keg was installed.
    public var installedAt: Date { primaryKeg.installedAt }
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

    private let positions: [PackageID: Int]

    public init(packages: [InstalledPackage], skippedRecordCount: Int = 0) {
        self.packages = packages
        self.skippedRecordCount = skippedRecordCount
        positions = Dictionary(
            packages.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// A snapshot of a machine with nothing installed — or of no machine at all.
    /// A valid value either way, never an error (installed-inventory II9).
    public static let empty = InstalledInventory(packages: [])

    public var isEmpty: Bool { packages.isEmpty }

    /// The record for an id, or `nil`. A miss is an ordinary answer.
    public func package(_ id: PackageID) -> InstalledPackage? {
        positions[id].map { packages[$0] }
    }
}
