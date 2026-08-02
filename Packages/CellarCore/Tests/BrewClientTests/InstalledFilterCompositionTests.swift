import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The catalog-only controls (kind, deprecated, disabled) under Browse's two
/// inventory-driven modes — the fourth M2-1 defect this change absorbs
/// (design D8d, installed-inventory II8 sc6-7).
@Suite("Installed filter controls")
struct InstalledFilterCompositionTests {
    private static let noFilters = SearchFilters()

    private static func catalogPackage(
        _ kind: PackageKind,
        _ name: String,
        deprecated: Bool = false,
        disabled: Bool = false
    ) -> CatalogPackage {
        InstalledFilterTests.catalogPackage(
            kind, name, deprecated: deprecated, disabled: disabled
        )
    }

    private func browse(_ inventory: InstalledInventory) -> InstalledBrowse {
        InstalledBrowse(inventory: inventory, isAvailable: true)
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
        let composer = browse(InstalledFilterTests.wgetOnly)
        let filters = SearchFilters(kinds: [.cask], excludeDeprecated: true)

        let all = composer.rows(
            mode: .all, query: "", filters: filters,
            catalogResults: InstalledFilterTests.catalogResults, catalogLookup: InstalledFilterTests.lookup
        )
        let notInstalled = composer.rows(
            mode: .notInstalled, query: "", filters: filters,
            catalogResults: InstalledFilterTests.catalogResults, catalogLookup: InstalledFilterTests.lookup
        )

        #expect(all.map(\.id) == InstalledFilterTests.catalogResults.map(\.id))
        #expect(notInstalled.map(\.id.name) == ["curl"])
    }
}
