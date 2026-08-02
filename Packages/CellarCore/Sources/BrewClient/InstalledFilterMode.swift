import Catalog
import Foundation

/// The installed-state filters Browse offers.
///
/// They live here, not in `SearchFilters`: the persisted catalog has no idea
/// what this machine has installed, and offering the predicate down there would
/// be a promise the data cannot keep (package-search PS4). Composition happens
/// above the index instead, and PS4 stays byte-identical.
public enum InstalledFilterMode: String, CaseIterable, Sendable, Hashable, Identifiable {
    case all
    case installed
    case notInstalled
    case outdated

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "All"
        case .installed: "Installed"
        case .notInstalled: "Not installed"
        case .outdated: "Outdated"
        }
    }
}

/// One row of a package list: what the catalog publishes, what this machine has
/// installed, or both.
///
/// Either side may be absent, and neither absence hides the row. A package from
/// a third-party tap has no catalog record; a package in the catalog that is not
/// installed has no snapshot record.
public struct PackageEntry: Sendable, Hashable, Identifiable {
    public let id: PackageID
    public let displayName: String
    /// The version worth showing: the installed one when there is one.
    public let version: String
    public let installed: InstalledPackage?
    public let catalog: CatalogPackage?

    public init(installed: InstalledPackage?, catalog: CatalogPackage?, id: PackageID) {
        self.id = id
        self.installed = installed
        self.catalog = catalog
        displayName = installed?.displayName ?? catalog?.displayName ?? id.name
        version = installed?.installedVersion ?? catalog?.version ?? ""
    }

    /// The snapshot's description first: it is the one that exists even with a
    /// cold, empty or poisoned catalog.
    public var desc: String? { installed?.desc ?? catalog?.desc }

    public var isInstalled: Bool { installed != nil }
}

/// Composes installed state into a package list.
///
/// Pure and value-typed on purpose: the *rule* is testable in the `swift test`
/// inner loop, and only the picker that drives it lives in the app target. That
/// refines design D7, which put the whole resolution in the app.
public struct InstalledBrowse: Sendable {
    public let inventory: InstalledInventory
    /// Whether the inventory means anything yet — false when brew is absent.
    public let isAvailable: Bool

    public init(inventory: InstalledInventory, isAvailable: Bool) {
        self.inventory = inventory
        self.isAvailable = isAvailable
    }

    /// Whether the picker should be interactive.
    public var isFilterEnabled: Bool { isAvailable }

    /// The mode actually in effect.
    ///
    /// With no inventory every mode collapses to `all`, so the results a user
    /// sees are exactly the results they would see with no installed-state
    /// filtering at all (installed-inventory II8).
    public func effectiveMode(_ requested: InstalledFilterMode) -> InstalledFilterMode {
        isAvailable ? requested : .all
    }

    /// The rows Browse should show.
    ///
    /// `installed` and `outdated` are sourced from the **inventory**, not by
    /// intersecting the catalog page: `catalog.results` is capped at 200 and
    /// ranked by install count, so intersecting an empty-query page with ~160
    /// installed ids would render almost nothing. At a few hundred records a
    /// direct scan needs no index. `notInstalled` is a subtraction from the
    /// page, where the cap interaction is negligible (design D7).
    public func rows(
        mode: InstalledFilterMode,
        query: String,
        catalogResults: [CatalogPackage],
        catalogLookup: (PackageID) -> CatalogPackage?
    ) -> [PackageEntry] {
        switch effectiveMode(mode) {
        case .all:
            catalogResults.map { entry(catalog: $0) }
        case .notInstalled:
            catalogResults
                .filter { !inventory.installedIDs.contains($0.id) }
                .map { entry(catalog: $0) }
        case .installed:
            entries(from: inventory.packages, query: query, catalogLookup: catalogLookup)
        case .outdated:
            entries(
                from: inventory.packages.filter(\.isOutdated),
                query: query,
                catalogLookup: catalogLookup
            )
        }
    }

    /// The Installed list itself, under the dependency toggle.
    public func entries(
        includingDependencies: Bool,
        catalogLookup: (PackageID) -> CatalogPackage?
    ) -> [PackageEntry] {
        inventory
            .packages(includingDependencies: includingDependencies)
            .map { entry(installed: $0, catalogLookup: catalogLookup) }
    }

    // MARK: - Building rows

    private func entries(
        from packages: [InstalledPackage],
        query: String,
        catalogLookup: (PackageID) -> CatalogPackage?
    ) -> [PackageEntry] {
        packages
            .filter { Self.matches($0, query: query) }
            .map { entry(installed: $0, catalogLookup: catalogLookup) }
    }

    /// Decoration is resolved per rendered row — one dictionary hit each, over
    /// the rows actually on screen — so the 16,000-record catalog is never
    /// walked and a missing record costs metadata, never the row (design D5).
    private func entry(
        installed: InstalledPackage,
        catalogLookup: (PackageID) -> CatalogPackage?
    ) -> PackageEntry {
        PackageEntry(installed: installed, catalog: catalogLookup(installed.id), id: installed.id)
    }

    private func entry(catalog: CatalogPackage) -> PackageEntry {
        PackageEntry(installed: inventory.package(catalog.id), catalog: catalog, id: catalog.id)
    }

    /// Name and description matching, case-insensitive.
    ///
    /// Deliberately simpler than `PackageSearchIndex`: that index exists because
    /// 16,000 records need a byte-scan budget. A few hundred installed records
    /// do not, and building a second index for them would cost more than the
    /// scan it saves.
    private static func matches(_ package: InstalledPackage, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        if package.name.lowercased().contains(needle) { return true }
        if package.displayName.lowercased().contains(needle) { return true }
        return package.desc?.lowercased().contains(needle) ?? false
    }
}
