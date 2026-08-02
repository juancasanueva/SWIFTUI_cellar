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

    // MARK: - Catalog-only controls under installed-driven modes (D8d — II8 sc6–7)

    /// One formula and one cask, the formula deprecated and the cask disabled,
    /// both installed. Every catalog-only control has something to bite on.
    private static var mixedInventory: InstalledInventory {
        InstalledInventory(packages: [
            InstalledDeriveTests.formula(name: "wget", installed: "1.25.0"),
            InstalledDeriveTests.cask(
                name: "iterm2", installed: "3.5.0", published: "3.5.0",
                snapshotOutdated: false, declaresAutoUpdates: false
            )
        ])
    }

    private static let mixedCatalog: [PackageID: CatalogPackage] = [
        PackageID(kind: .formula, name: "wget"): catalogPackage(.formula, "wget", deprecated: true),
        PackageID(kind: .cask, name: "iterm2"): catalogPackage(.cask, "iterm2", disabled: true)
    ]

    private static func mixedLookup(_ id: PackageID) -> CatalogPackage? { mixedCatalog[id] }

    private func mixedRows(mode: InstalledFilterMode, filters: SearchFilters) -> [String] {
        browse(Self.mixedInventory).rows(
            mode: mode,
            query: "",
            filters: filters,
            catalogResults: [],
            catalogLookup: Self.mixedLookup
        ).map(\.id.name)
    }

    /// The M2-1 defect: under `installed` the kind picker rendered enabled and
    /// changed nothing. Every enabled control must be honoured — a control that
    /// cannot move the visible results is a control that lies (II8 sc6).
    @Test("The kind control narrows the installed mode, and the picker stays enabled")
    func kindNarrowsTheInstalledMode() {
        let composer = browse(Self.mixedInventory)
        #expect(composer.isFilterEnabled, "the control is offered, so it must be honoured")

        #expect(mixedRows(mode: .installed, filters: Self.noFilters) == ["iterm2", "wget"])
        #expect(mixedRows(mode: .installed, filters: SearchFilters(kinds: [.formula])) == ["wget"])
        #expect(mixedRows(mode: .installed, filters: SearchFilters(kinds: [.cask])) == ["iterm2"])
    }

    @Test("Deprecated and disabled both narrow the installed mode")
    func deprecatedAndDisabledNarrowTheInstalledMode() {
        #expect(
            mixedRows(mode: .installed, filters: SearchFilters(excludeDeprecated: true))
                == ["iterm2"],
            "the deprecated formula survived an excludeDeprecated filter"
        )
        #expect(
            mixedRows(mode: .installed, filters: SearchFilters(excludeDisabled: true))
                == ["wget"],
            "the disabled cask survived an excludeDisabled filter"
        )
    }

    /// The kind is read off the **inventory**, which is the authoritative record
    /// of what this machine has: an installed package has a kind even when the
    /// catalog has never heard of it.
    @Test("Kind is answered by the inventory, not by the catalog record")
    func kindComesFromTheInventory() {
        let rows = browse(Self.mixedInventory).rows(
            mode: .installed,
            query: "",
            filters: SearchFilters(kinds: [.cask]),
            catalogResults: [],
            catalogLookup: { _ in nil }
        )

        #expect(rows.map(\.id.name) == ["iterm2"])
    }

    /// The II3 principle, restated where it now matters: `deprecated` and
    /// `disabled` are *catalog* facts, and a package the catalog never published
    /// carries neither. Hiding a third-party-tap row behind a flag nothing
    /// published would make it unreachable in Cellar entirely.
    @Test("A row with no catalog record is never hidden by a catalog-only flag")
    func aRowWithNoCatalogRecordIsNeverHidden() {
        let inventory = InstalledInventory(packages: [
            InstalledDeriveTests.formula(name: "private-tool", installed: "0.4.1")
        ])

        for filters in [
            SearchFilters(excludeDeprecated: true),
            SearchFilters(excludeDisabled: true),
            SearchFilters(excludeDeprecated: true, excludeDisabled: true)
        ] {
            let rows = browse(inventory).rows(
                mode: .installed,
                query: "",
                filters: filters,
                catalogResults: [],
                catalogLookup: { _ in nil }
            )
            #expect(rows.map(\.id.name) == ["private-tool"])
        }
    }

    /// The outdated mode obeys the same rule (II8 sc7).
    @Test("The kind control applied to casks leaves only the cask under outdated")
    func kindNarrowsTheOutdatedMode() {
        let inventory = InstalledInventory(packages: [
            InstalledDeriveTests.formula(
                name: "git", installed: "2.48.1", published: "2.49.0", snapshotOutdated: true
            ),
            InstalledDeriveTests.cask(
                name: "iterm2", installed: "3.5.0", published: "3.5.1",
                snapshotOutdated: true, declaresAutoUpdates: false
            )
        ])
        let composer = browse(inventory)

        let unfiltered = composer.rows(
            mode: .outdated, query: "", filters: Self.noFilters,
            catalogResults: [], catalogLookup: { _ in nil }
        )
        let casksOnly = composer.rows(
            mode: .outdated, query: "", filters: SearchFilters(kinds: [.cask]),
            catalogResults: [], catalogLookup: { _ in nil }
        )

        #expect(unfiltered.map(\.id.name) == ["git", "iterm2"])
        #expect(casksOnly.map(\.id.name) == ["iterm2"])
    }

    /// The `all` and `notInstalled` modes read the catalog page, which the index
    /// has already filtered — applying the same predicates a second time here
    /// must not change what they show.
    @Test("The catalog-driven modes are unaffected by the same filters")
    func catalogDrivenModesAreUnchanged() {
        let composer = browse(Self.wgetOnly)
        let filters = SearchFilters(kinds: [.cask], excludeDeprecated: true)

        let all = composer.rows(
            mode: .all, query: "", filters: filters,
            catalogResults: Self.catalogResults, catalogLookup: Self.lookup
        )
        let notInstalled = composer.rows(
            mode: .notInstalled, query: "", filters: filters,
            catalogResults: Self.catalogResults, catalogLookup: Self.lookup
        )

        #expect(all.map(\.id) == Self.catalogResults.map(\.id))
        #expect(notInstalled.map(\.id.name) == ["curl"])
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
