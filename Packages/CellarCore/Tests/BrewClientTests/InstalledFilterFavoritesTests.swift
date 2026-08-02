import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The favorites filter, composed on exactly the terms the installed-state
/// filters already use (installed-inventory II8, local-package-metadata LPM3).
///
/// Its own suite rather than more of `InstalledFilterTests`, which is already
/// long enough to be near SwiftLint's `type_body_length` limit.
@Suite("Installed favorites filter")
struct InstalledFilterFavoritesTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let curl = PackageID(kind: .formula, name: "curl")
    private static let git = PackageID(kind: .formula, name: "git")

    // MARK: - II8 sc8 — the favorites filter narrows the list

    @Test("The favorites filter narrows the list to the favorite")
    func theFavoritesFilterNarrows() {
        let browse = InstalledBrowse(
            inventory: InstalledFixture.inventory(upToDate: [Self.wget, Self.curl]),
            isAvailable: true
        )
        let metadata: MetadataSnapshot = [Self.wget: PackageMetadata(isFavorite: true)]

        let rows = browse.entries(
            includingDependencies: true,
            catalogLookup: { _ in nil },
            metadata: metadata.lookup,
            favoritesOnly: true
        )

        #expect(rows.map(\.id) == [Self.wget])
    }

    // MARK: - II8 sc9 — it composes rather than replacing

    @Test("The favorites filter composes with the outdated filter rather than replacing it")
    func theFavoritesFilterComposes() {
        // One outdated favorite, one up-to-date favorite, one outdated non-favorite.
        let browse = InstalledBrowse(
            inventory: InstalledFixture.inventory(
                outdated: [Self.wget: "1.2.3", Self.git: "2.44.0"],
                upToDate: [Self.curl]
            ),
            isAvailable: true
        )
        let metadata: MetadataSnapshot = [
            Self.wget: PackageMetadata(isFavorite: true),
            Self.curl: PackageMetadata(isFavorite: true)
        ]

        let rows = browse.rows(
            mode: .outdated,
            query: "",
            filters: SearchFilters(),
            catalogResults: [],
            catalogLookup: { _ in nil },
            metadata: metadata.lookup,
            favoritesOnly: true
        )

        #expect(rows.map(\.id) == [Self.wget], "the filters replaced each other instead of composing")
    }

    // MARK: - II8 sc10 — with no metadata it is disabled and changes nothing

    @Test("With no metadata the favorites filter is disabled and the results are unchanged")
    func withNoMetadataTheFilterIsDisabled() {
        let browse = InstalledBrowse(
            inventory: InstalledFixture.inventory(upToDate: [Self.wget, Self.curl]),
            isAvailable: true
        )

        #expect(browse.isFavoritesFilterEnabled(metadata: nil) == false)
        #expect(browse.isFavoritesFilterEnabled(metadata: MetadataSnapshot().lookup))
        #expect(browse.favoriteIDs(metadata: nil) == nil)

        let unfiltered = browse.entries(includingDependencies: true, catalogLookup: { _ in nil })
        let asked = browse.entries(
            includingDependencies: true,
            catalogLookup: { _ in nil },
            metadata: nil,
            favoritesOnly: true
        )

        #expect(asked.map(\.id) == unfiltered.map(\.id))
    }

    // MARK: - II8 sc5 — the catalog query declares no membership predicate

    @Test("The catalog query's declared filter set contains no installed or favorite predicate")
    func theCatalogFilterSetDeclaresNoMembershipPredicate() throws {
        let mirror = Mirror(reflecting: SearchFilters())
        let declared = mirror.children.compactMap(\.label)

        #expect(declared.sorted() == ["excludeDeprecated", "excludeDisabled", "kinds"])
        for forbidden in ["installed", "notInstalled", "outdated", "favorite", "favorites"] {
            #expect(
                declared.contains { $0.lowercased().contains(forbidden.lowercased()) } == false,
                "the catalog filter set declares a \(forbidden) predicate"
            )
        }
    }

    // MARK: - LPM3 sc3 — note text enters no search index

    @Test("Searching the Installed list for a word that appears only in a note returns nothing")
    func noteTextIsNeverSearched() {
        let browse = InstalledBrowse(
            inventory: InstalledFixture.inventory(upToDate: [Self.wget]),
            isAvailable: true
        )
        let metadata: MetadataSnapshot = [
            Self.wget: PackageMetadata(note: "reminds me of a zeppelin")
        ]

        let rows = browse.rows(
            mode: .installed,
            query: "zeppelin",
            filters: SearchFilters(),
            catalogResults: [],
            catalogLookup: { _ in nil },
            metadata: metadata.lookup
        )

        #expect(rows.isEmpty, "note text reached the Installed list's search")

        // And the same query against the package's own name still finds it, so
        // the emptiness above is a filtered result rather than a broken search.
        let byName = browse.rows(
            mode: .installed,
            query: "wget",
            filters: SearchFilters(),
            catalogResults: [],
            catalogLookup: { _ in nil },
            metadata: metadata.lookup
        )
        #expect(byName.map(\.id) == [Self.wget])
    }
}
