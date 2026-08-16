import Foundation
import Testing

@testable import Catalog

/// The vendored CaskHub data files: category catalog and added dates.
///
/// Both are gated by an exact schema version in both directions — a mismatch
/// is "no data", never an error — following the same idiom as
/// `DiscoverySchema`: the file this build cannot read simply does not exist
/// for it.
@Suite("Cask browse data")
struct CaskBrowseDataTests {
    // MARK: - Category catalog decoding

    @Test("A well-formed category file decodes with every declared table")
    func categoryCatalogDecodes() async throws {
        let catalog = try #require(await CaskCategoryCatalog.decode(Self.categoriesJSON()))

        #expect(catalog.version == CaskCategoryCatalog.schemaVersion)
        #expect(catalog.generatedDate == "2026-08-13")
        #expect(catalog.releaseTag == "caskflow-v1")
        #expect(catalog.categories["browsers"]?.displayName == "Browsers")
        #expect(catalog.categories["browsers"]?.icon == "globe")
        #expect(catalog.tokenToCategory["arc"]?.primary == "browsers")
        #expect(catalog.tokenToCategory["arc"]?.secondary == ["productivity"])
        #expect(catalog.iconTokens == ["arc", "iterm2"])
    }

    @Test("A category file with any other schema version yields no data")
    func categoryCatalogRejectsOtherVersions() async {
        // Exact in both directions: older *and* newer are equally unreadable.
        for version in [1, 3] {
            let decoded = await CaskCategoryCatalog.decode(
                Self.categoriesJSON(version: version)
            )
            #expect(decoded == nil, "version \(version) must read as no data")
        }
    }

    @Test("Malformed category bytes yield no data, never an error")
    func categoryCatalogRejectsMalformedBytes() async {
        #expect(await CaskCategoryCatalog.decode(Data("not json".utf8)) == nil)
    }

    // MARK: - Category ordering and mapping

    @Test("Categories are ordered by display name with other forced last")
    func orderedCategoriesForceOtherLast() {
        let catalog = Self.catalog(
            categories: [
                "other": CaskCategoryDefinition(displayName: "Other", icon: "square.grid.2x2"),
                "utilities": CaskCategoryDefinition(displayName: "Utilities", icon: "wrench"),
                "browsers": CaskCategoryDefinition(displayName: "Browsers", icon: "globe"),
                "ai": CaskCategoryDefinition(displayName: "AI", icon: "sparkles")
            ],
            mappings: [:]
        )

        // "Other" would sort between "Browsers" and "Utilities" alphabetically;
        // the CaskHub rule pins it to the end regardless.
        #expect(catalog.orderedCategories.map(\.id) == ["ai", "browsers", "utilities", "other"])
    }

    @Test("A token's category ids are primary first, then secondary, de-duplicated")
    func uniqueCategoryIDsDeduplicatePreservingOrder() {
        let catalog = Self.catalog(
            categories: [:],
            mappings: [
                "arc": CaskCategoryMapping(
                    primary: "browsers",
                    secondary: ["browsers", "productivity", "productivity", "utilities"]
                )
            ]
        )

        #expect(catalog.uniqueCategoryIDs(for: "arc") == ["browsers", "productivity", "utilities"])
        // An unmapped token has no categories rather than a default.
        #expect(catalog.uniqueCategoryIDs(for: "unmapped") == [])
    }

    // MARK: - Added dates decoding

    @Test("A well-formed added-dates file decodes and keeps its timestamps as strings")
    func addedDatesDecode() async throws {
        let dates = try #require(await CaskAddedDates.decode(Self.addedDatesJSON()))

        #expect(dates.version == CaskAddedDates.schemaVersion)
        #expect(dates.generatedDate == "2026-08-13T15:44:15Z")
        // ISO8601 strings compare lexicographically; parsing them would be
        // work the projection never needs.
        #expect(dates.tokenAddedDates["arc"] == "2027-01-10T00:00:00Z")
    }

    @Test("An added-dates file with any other schema version yields no data")
    func addedDatesRejectOtherVersions() async {
        for version in [0, 2] {
            let decoded = await CaskAddedDates.decode(Self.addedDatesJSON(version: version))
            #expect(decoded == nil, "version \(version) must read as no data")
        }
    }

    // MARK: - Shipped resources

    @Test("The shipped category catalog loads from the module bundle")
    func shippedCategoryCatalogLoads() async throws {
        let catalog = try #require(await CaskCategoryCatalog.shipped())

        #expect(catalog.version == CaskCategoryCatalog.schemaVersion)
        #expect(catalog.categories.isEmpty == false)
        #expect(catalog.categories["other"] != nil)
        #expect(catalog.tokenToCategory.isEmpty == false)
        #expect(catalog.iconTokens.isEmpty == false)
    }

    @Test("The shipped added dates load from the module bundle")
    func shippedAddedDatesLoad() async throws {
        let dates = try #require(await CaskAddedDates.shipped())

        #expect(dates.version == CaskAddedDates.schemaVersion)
        #expect(dates.tokenAddedDates.isEmpty == false)
    }

    @Test("A bundle without the resources yields no data, never an error")
    func missingResourceYieldsNoData() async {
        #expect(await CaskCategoryCatalog.shipped(from: Bundle(for: BundleAnchor.self)) == nil)
        #expect(await CaskAddedDates.shipped(from: Bundle(for: BundleAnchor.self)) == nil)
    }

    // MARK: - Helpers

    /// An anchor class whose bundle is the test bundle — which carries neither
    /// resource under the names the loaders ask for.
    private final class BundleAnchor {}

    static func catalog(
        categories: [String: CaskCategoryDefinition],
        mappings: [String: CaskCategoryMapping]
    ) -> CaskCategoryCatalog {
        CaskCategoryCatalog(
            version: CaskCategoryCatalog.schemaVersion,
            generatedDate: "2026-08-13",
            releaseTag: nil,
            categories: categories,
            tokenToCategory: mappings,
            iconTokens: []
        )
    }

    static func categoriesJSON(version: Int = CaskCategoryCatalog.schemaVersion) -> Data {
        Data("""
        {
            "version": \(version),
            "generatedDate": "2026-08-13",
            "totalCasks": 2,
            "releaseTag": "caskflow-v1",
            "categories": {
                "browsers": { "displayName": "Browsers", "icon": "globe" },
                "other": { "displayName": "Other", "icon": "square.grid.2x2" }
            },
            "tokenToCategory": {
                "arc": { "primary": "browsers", "secondary": ["productivity"] }
            },
            "iconTokens": ["arc", "iterm2"]
        }
        """.utf8)
    }

    static func addedDatesJSON(version: Int = CaskAddedDates.schemaVersion) -> Data {
        Data("""
        {
            "version": \(version),
            "generatedDate": "2026-08-13T15:44:15Z",
            "totalCasks": 1,
            "tokenAddedDates": { "arc": "2027-01-10T00:00:00Z" }
        }
        """.utf8)
    }
}
