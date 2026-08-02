import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// Installed-state filters are *composed* above the search index, never pushed
/// into it (installed-inventory II8), and the catalog decorates the Installed
/// list rather than supplying it (II7).
@Suite("Installed filter composition")
struct InstalledFilterTests {
    // MARK: - Fixtures

    static func catalogPackage(
        _ kind: PackageKind,
        _ name: String,
        desc: String? = nil,
        version: String = "1.0.0",
        installCount: Int? = nil,
        deprecated: Bool = false,
        disabled: Bool = false
    ) -> CatalogPackage {
        CatalogPackage(
            kind: kind, name: name, displayName: name, desc: desc, homepage: nil,
            license: nil, version: version, tap: "homebrew/core", dependencies: [],
            buildDependencies: [], dependents: [], caveats: nil, deprecated: deprecated,
            deprecationReason: nil, deprecationDate: nil, disabled: disabled,
            disableReason: nil, disableDate: nil, autoUpdates: false,
            installCount365d: installCount
        )
    }

    /// Every predicate on, which is what "no filtering" spells.
    static let noFilters = SearchFilters()

    static let wgetCatalog = catalogPackage(
        .formula, "wget", desc: "Internet file retriever", installCount: 1_234
    )
    static let curlCatalog = catalogPackage(.formula, "curl", desc: "Transfer data with URLs")

    static let catalogResults = [wgetCatalog, curlCatalog]

    static func lookup(_ id: PackageID) -> CatalogPackage? {
        catalogResults.first { $0.id == id }
    }

    /// An inventory holding only `wget`.
    static var wgetOnly: InstalledInventory {
        InstalledInventory(packages: [
            InstalledDeriveTests.formula(name: "wget", installed: "1.25.0")
        ])
    }

    private func browse(
        _ inventory: InstalledInventory,
        isAvailable: Bool = true
    ) -> InstalledBrowse {
        InstalledBrowse(inventory: inventory, isAvailable: isAvailable)
    }

    // MARK: - The four modes (II8 sc1–sc3)

    @Test("The installed filter narrows browse results")
    func installedFilterNarrowsResults() {
        let rows = browse(Self.wgetOnly).rows(
            mode: .installed,
            query: "",
            filters: Self.noFilters,
            catalogResults: Self.catalogResults,
            catalogLookup: Self.lookup
        )

        #expect(rows.map(\.id.name) == ["wget"])
    }

    @Test("The not-installed filter is the complement")
    func notInstalledFilterIsTheComplement() {
        let rows = browse(Self.wgetOnly).rows(
            mode: .notInstalled,
            query: "",
            filters: Self.noFilters,
            catalogResults: Self.catalogResults,
            catalogLookup: Self.lookup
        )

        #expect(rows.map(\.id.name) == ["curl"])
    }

    @Test("The all mode leaves the catalog results exactly as they were")
    func allModeLeavesResultsUnchanged() {
        let rows = browse(Self.wgetOnly).rows(
            mode: .all,
            query: "",
            filters: Self.noFilters,
            catalogResults: Self.catalogResults,
            catalogLookup: Self.lookup
        )

        #expect(rows.map(\.id) == Self.catalogResults.map(\.id))
    }

    @Test("The outdated filter excludes self-updating casks")
    func outdatedFilterExcludesSelfUpdatingCasks() {
        let inventory = InstalledInventory(packages: [
            InstalledDeriveTests.formula(
                name: "git", installed: "2.48.1", published: "2.49.0", snapshotOutdated: true
            ),
            InstalledDeriveTests.cask(
                name: "ghostty", installed: "1.2.3", published: "1.3.1",
                snapshotOutdated: false, declaresAutoUpdates: true
            )
        ])

        let rows = browse(inventory).rows(
            mode: .outdated,
            query: "",
            filters: Self.noFilters,
            catalogResults: [],
            catalogLookup: { _ in nil }
        )

        #expect(rows.map(\.id.name) == ["git"])
    }

    /// The reason `installed` is sourced from the inventory rather than
    /// intersected with the page: `catalog.results` is capped at 200, and
    /// intersecting an empty-query page with ~160 installed ids renders ~0 rows.
    @Test("Installed rows come from the inventory, not from the capped page")
    func installedRowsAreNotLimitedByTheCatalogPage() {
        let inventory = InstalledInventory(packages: (0..<300).map {
            InstalledDeriveTests.formula(name: "package-\(String(format: "%03d", $0))", installed: "1.0")
        })

        let rows = browse(inventory).rows(
            mode: .installed,
            query: "",
            filters: Self.noFilters,
            // A page that happens to contain none of them, as it would after
            // ranking by install count.
            catalogResults: Self.catalogResults,
            catalogLookup: Self.lookup
        )

        #expect(rows.count == 300)
        #expect(rows.map(\.id.name) == rows.map(\.id.name).sorted())
    }

    @Test("Installed rows honour the live query against name and description")
    func installedRowsHonourTheQuery() {
        let inventory = InstalledInventory(packages: [
            InstalledDeriveTests.formula(name: "wget", installed: "1.25.0"),
            InstalledDeriveTests.formula(name: "ripgrep", installed: "14.1.1")
        ])

        let matches = browse(inventory).rows(
            mode: .installed,
            query: "rip",
            filters: Self.noFilters,
            catalogResults: [],
            catalogLookup: { _ in nil }
        )

        #expect(matches.map(\.id.name) == ["ripgrep"])
    }

    // MARK: - No inventory (II8 sc4)

    @Test("With no inventory the mode is forced to all and the picker is disabled")
    func withNoInventoryTheFilterIsDisabledAndInert() {
        let composer = browse(.empty, isAvailable: false)

        #expect(composer.isFilterEnabled == false)
        #expect(composer.effectiveMode(.installed) == .all)
        #expect(composer.effectiveMode(.outdated) == .all)
        #expect(composer.effectiveMode(.notInstalled) == .all)

        // And the rows are identical to the same query with no installed-state
        // filtering at all.
        let filtered = composer.rows(
            mode: composer.effectiveMode(.installed),
            query: "doc",
            filters: Self.noFilters,
            catalogResults: Self.catalogResults,
            catalogLookup: Self.lookup
        )
        let unfiltered = composer.rows(
            mode: .all,
            query: "doc",
            filters: Self.noFilters,
            catalogResults: Self.catalogResults,
            catalogLookup: Self.lookup
        )

        #expect(filtered.map(\.id) == unfiltered.map(\.id))
        #expect(filtered.map(\.id) == Self.catalogResults.map(\.id))
    }

    @Test("With an inventory present the picker is enabled and the mode is honoured")
    func withAnInventoryTheFilterIsEnabled() {
        let composer = browse(Self.wgetOnly)

        #expect(composer.isFilterEnabled)
        #expect(composer.effectiveMode(.installed) == .installed)
    }

    // MARK: - Catalog decoration (II7)

    @Test("A matched installed package carries its version and the catalog description")
    func matchedPackageCarriesCatalogMetadata() throws {
        let entries = browse(Self.wgetOnly).entries(
            includingDependencies: false,
            catalogLookup: Self.lookup
        )

        let wget = try #require(entries.first)
        #expect(wget.installed?.installedVersion == "1.25.0")
        #expect(wget.desc == "Internet file retriever")
        #expect(wget.catalog?.installCount365d == 1_234)
    }

    @Test("An unmatched installed package is still listed, with its snapshot data")
    func unmatchedPackageIsStillListed() throws {
        let inventory = try InstalledFixture.inventory()

        let entries = browse(inventory).entries(
            includingDependencies: true,
            catalogLookup: Self.lookup
        )
        let tool = try #require(entries.first { $0.id.name == "private-tool" })

        #expect(tool.catalog == nil)
        #expect(tool.installed?.installedVersion == "0.4.1")
        // The snapshot is self-sufficient: the description came with it.
        #expect(tool.desc == "An internal tool published by a third-party tap")
    }

    /// A cold, empty or poisoned catalog costs decoration, never a row.
    @Test("With no catalog at all every installed package is still listed")
    func anEmptyCatalogCostsDecorationNotRows() throws {
        let inventory = try InstalledFixture.inventory()

        let entries = browse(inventory).entries(
            includingDependencies: true,
            catalogLookup: { _ in nil }
        )

        #expect(entries.count == inventory.packages.count)
        #expect(entries.allSatisfy { $0.catalog == nil })
        #expect(entries.allSatisfy { $0.installed != nil })
    }

    @Test("The default entry list honours the dependency toggle")
    func entriesHonourTheDependencyToggle() throws {
        let inventory = try InstalledFixture.inventory()
        let composer = browse(inventory)

        let onRequest = composer.entries(includingDependencies: false, catalogLookup: Self.lookup)
        let everything = composer.entries(includingDependencies: true, catalogLookup: Self.lookup)

        #expect(onRequest.count < everything.count)
        #expect(onRequest.map(\.id.name).contains("libunistring") == false)
        #expect(everything.map(\.id.name).contains("libunistring"))
    }
}
