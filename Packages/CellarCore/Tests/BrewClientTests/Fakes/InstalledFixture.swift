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
}
