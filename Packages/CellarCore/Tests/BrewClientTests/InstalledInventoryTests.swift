import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The inventory value itself: what it guarantees regardless of where its
/// records came from.
@Suite("Installed inventory")
struct InstalledInventoryTests {
    private func build(_ packages: [InstalledPackage]) -> InstalledInventory {
        InstalledInventory(packages: packages)
    }

    /// Sorting belongs to the value, not to the decoder that happens to build
    /// it: a hand-built inventory in a preview or a test must order the same way
    /// the real one does, or the list diffs differently between the two.
    @Test("Records are ordered by name whoever built the inventory")
    func recordsAreOrderedByName() {
        let inventory = build([
            InstalledDeriveTests.formula(name: "zulu", installed: "1.0"),
            InstalledDeriveTests.formula(name: "alpha", installed: "1.0"),
            InstalledDeriveTests.formula(name: "mike", installed: "1.0")
        ])

        #expect(inventory.packages.map(\.name) == ["alpha", "mike", "zulu"])
    }

    /// The same token exists in both namespaces, so the order has to be total
    /// or two adjacent rows can swap between refreshes.
    @Test("A name collision is broken by namespace, formula first")
    func nameCollisionIsBrokenByNamespace() {
        let inventory = build([
            InstalledDeriveTests.cask(
                name: "docker", installed: "1.0", published: "1.0",
                snapshotOutdated: false, declaresAutoUpdates: nil
            ),
            InstalledDeriveTests.formula(name: "docker", installed: "1.0")
        ])

        #expect(inventory.packages.map(\.kind) == [.formula, .cask])
    }

    @Test("Membership is answered over the catalog's identity, not over names")
    func membershipIsAnsweredOverPackageID() {
        let inventory = build([
            InstalledDeriveTests.formula(name: "docker", installed: "1.0")
        ])

        #expect(inventory.installedIDs.contains(PackageID(kind: .formula, name: "docker")))
        // Same token, other namespace: not installed.
        #expect(inventory.installedIDs.contains(PackageID(kind: .cask, name: "docker")) == false)
        #expect(inventory.installedIDs.count == 1)
    }

    @Test("The outdated set is a subset of the installed set, minus self-updating casks")
    func outdatedIsASubsetExcludingSelfUpdatingCasks() {
        let inventory = build([
            InstalledDeriveTests.formula(
                name: "git", installed: "2.48.1", published: "2.49.0", snapshotOutdated: true
            ),
            InstalledDeriveTests.cask(
                name: "ghostty", installed: "1.2.3", published: "1.3.1",
                snapshotOutdated: false, declaresAutoUpdates: true
            ),
            InstalledDeriveTests.formula(name: "wget", installed: "1.25.0")
        ])

        #expect(inventory.outdatedIDs.isSubset(of: inventory.installedIDs))
        #expect(inventory.outdatedIDs.map(\.name) == ["git"])
        #expect(inventory.installedIDs.count == 3)
    }

    @Test("An empty inventory is a value, not an error")
    func emptyInventoryIsAValue() {
        let inventory = InstalledInventory.empty

        #expect(inventory.isEmpty)
        #expect(inventory.packages.isEmpty)
        #expect(inventory.installedIDs.isEmpty)
        #expect(inventory.outdatedIDs.isEmpty)
        #expect(inventory.outdatedCount == 0)
        #expect(inventory.skippedRecordCount == 0)
        #expect(inventory.package(PackageID(kind: .formula, name: "wget")) == nil)
        #expect(inventory.packages(includingDependencies: true).isEmpty)
    }

    @Test("A decoded inventory carries the same ordering guarantee")
    func decodedInventoryIsOrderedToo() throws {
        let inventory = try InstalledFixture.inventory()

        #expect(inventory.packages.map(\.name) == inventory.packages.map(\.name).sorted())
        #expect(inventory.installedIDs.count == inventory.packages.count)
    }
}
