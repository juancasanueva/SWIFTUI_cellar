import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The order the installed list displays its packages in, as one projection.
///
/// The sections were three private computeds in the view while `reconcileOrder`
/// appended in flat inventory order, so a select-all entered the selection — and
/// therefore submitted its operations — in an order the user never saw. One
/// projection read twice is the `upgradableIDs` precedent (II14, design D9).
@MainActor
@Suite("Installed sections")
struct InstalledSectionsTests {
    @Test("The displayed order is outdated, then self-updating, then the rest")
    func theDisplayedOrderIsOutdatedThenSelfUpdatingThenTheRest() {
        // Inventory order deliberately interleaves all three sections.
        let entries = [Self.git, Self.ghostty, Self.iterm, Self.pcre2]

        let sections = InstalledSections(entries: entries, outdatedIDs: [Self.iterm.id])

        #expect(sections.outdated.map(\.id.name) == ["iterm2"])
        #expect(sections.selfUpdating.map(\.id.name) == ["ghostty"])
        #expect(sections.rest.map(\.id.name) == ["git", "pcre2"])
        #expect(sections.displayed.map(\.id.name) == ["iterm2", "ghostty", "git", "pcre2"])
        // Every package lands in exactly one section, so the rendered rows and
        // `displayed` cannot disagree about how many there are.
        #expect(sections.displayed.count == entries.count)
        #expect(Set(sections.displayed.map(\.id)) == Set(entries.map(\.id)))
    }

    @Test("A bulk add enters the selection in displayed order, not inventory order")
    func bulkAddEntersTheSelectionInDisplayedOrderNotInventoryOrder() async throws {
        let entries = [Self.git, Self.pcre2, Self.iterm]
        let sections = InstalledSections(entries: entries, outdatedIDs: [Self.iterm.id])

        #expect(entries.map(\.id.name) == ["git", "pcre2", "iterm2"], "inventory order")
        #expect(sections.displayed.map(\.id.name) == ["iterm2", "git", "pcre2"], "displayed order")

        // One bulk add: every id arrives at once, out of a `Set` whose iteration
        // order carries no information at all.
        let addedAtOnce = Set(entries.map(\.id))
        var order: [PackageID] = []
        order.append(contentsOf: sections.displayed.map(\.id).filter { addedAtOnce.contains($0) })

        #expect(order.map(\.name) == ["iterm2", "git", "pcre2"])

        // And because selection order *is* submission order, the operations come
        // out in the order the user saw the rows.
        let harness = CenterHarness()
        let inventory = InstalledInventory(packages: [Self.gitPackage, Self.pcre2Package, Self.itermPackage])
        let items = harness.center.submitUpgrades(for: order, in: inventory)
        await harness.settle()

        #expect(items.map(\.arguments) == [
            ["upgrade", "--cask", "iterm2"],
            ["upgrade", "--formula", "git"],
            ["upgrade", "--formula", "pcre2"]
        ])
        for index in 0..<items.count { try await harness.finish(call: index) }
    }

    // MARK: - Fixtures

    private static let gitPackage = InstalledDeriveTests.formula(name: "git", installed: "2.51.0")
    private static let pcre2Package = InstalledDeriveTests.formula(
        name: "pcre2", installed: "10.46", onRequest: false
    )
    private static let itermPackage = InstalledDeriveTests.cask(
        name: "iterm2", installed: "3.5.0", published: "3.6.0",
        snapshotOutdated: true, declaresAutoUpdates: nil
    )
    private static let ghosttyPackage = InstalledDeriveTests.cask(
        name: "ghostty", installed: "1.2.3", published: "1.3.1",
        snapshotOutdated: false, declaresAutoUpdates: true
    )

    private static let git = entry(gitPackage)
    private static let pcre2 = entry(pcre2Package)
    private static let iterm = entry(itermPackage)
    private static let ghostty = entry(ghosttyPackage)

    private static func entry(_ package: InstalledPackage) -> PackageEntry {
        PackageEntry(installed: package, catalog: nil, id: package.id)
    }
}
