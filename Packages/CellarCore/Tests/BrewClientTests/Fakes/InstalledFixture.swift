import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The hand-trimmed `brew info --installed --json=v2` excerpt.
///
/// See `Fixtures/README.md` for what each record is there to prove.
enum InstalledFixture {
    static func data() throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: "installed-info",
                withExtension: "json",
                subdirectory: "Fixtures"
            ),
            "missing Fixtures/installed-info.json"
        )
        return try Data(contentsOf: url)
    }

    static func inventory() throws -> InstalledInventory {
        try InstalledDecoder.inventory(from: data())
    }

    /// One record from the fixture inventory, by identity.
    static func package(_ kind: PackageKind, _ name: String) throws -> InstalledPackage {
        let inventory = try inventory()
        return try #require(
            inventory.package(PackageID(kind: kind, name: name)),
            "no \(kind) named \(name) in the fixture"
        )
    }

    static func date(_ epochSeconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: epochSeconds)
    }

    // MARK: - Synthetic inventories, for the composition rules

    /// The version every synthetic package reports as installed.
    ///
    /// One constant rather than a literal per test, so "the row still shows the
    /// version it has installed" is asserted against the same value the builder
    /// wrote (installed-inventory II12 sc4).
    static let installedVersion = "1.0.0"

    /// An inventory assembled from identities rather than decoded from JSON.
    ///
    /// The fixture is the right tool for decoding; it is the wrong tool for a
    /// rule that needs *this* package outdated toward *that* exact published
    /// version. `outdated` maps an identity to the version brew is currently
    /// offering for it, which is precisely what a snooze is taken against.
    static func inventory(
        outdated: [PackageID: String] = [:],
        upToDate: [PackageID] = [],
        pinned: Set<PackageID> = [],
        dependencies: Set<PackageID> = []
    ) -> InstalledInventory {
        let ordered = outdated.keys.sorted { $0.name < $1.name }.map { id in
            package(
                id,
                catalogVersion: outdated[id] ?? installedVersion,
                isPinned: pinned.contains(id),
                onRequest: !dependencies.contains(id)
            )
        } + upToDate.map { id in
            package(
                id,
                catalogVersion: installedVersion,
                isPinned: pinned.contains(id),
                onRequest: !dependencies.contains(id)
            )
        }
        return InstalledInventory(packages: ordered)
    }

    static func package(
        _ id: PackageID,
        catalogVersion: String,
        isPinned: Bool = false,
        onRequest: Bool = true
    ) -> InstalledPackage {
        let keg = InstalledKeg(
            version: installedVersion,
            installedAt: date(1_000),
            installedOnRequest: onRequest
        )
        return InstalledPackage(
            kind: id.kind,
            name: id.name,
            displayName: id.name,
            desc: nil,
            homepage: nil,
            tap: "homebrew/core",
            catalogVersion: catalogVersion,
            kegs: [keg],
            primaryKeg: keg,
            snapshotOutdated: catalogVersion != installedVersion,
            isPinned: isPinned,
            pinnedVersion: isPinned ? installedVersion : nil,
            declaresAutoUpdates: nil
        )
    }
}
