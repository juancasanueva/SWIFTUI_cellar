import Foundation

/// Everything the formula storefront pages render, projected once per
/// snapshot adoption — the `CaskBrowseContent` idea applied to the other
/// kind, minus every field whose data is cask-mined: no categories, no
/// added dates, no recency. What formulae have is what CaskHub's rules can
/// honestly compute from the catalog and its analytics alone.
public struct FormulaBrowseContent: Sendable, Hashable {
    /// The single most popular eligible formula — the hero card's subject.
    public let housePick: CatalogPackage?
    /// The Most Popular shelf: the popularity order's first eight.
    public let mostPopular: [CatalogPackage]
    /// The Featured page's hundred, in popularity order.
    public let featured: [CatalogPackage]
    /// The whole eligible universe in popularity order — Top Charts re-ranks
    /// it per window, search matches rank by it.
    public let allByPopularity: [CatalogPackage]
    /// Every eligible formula, uncapped — the count the top bar states.
    public let formulaCount: Int

    public init(
        housePick: CatalogPackage?,
        mostPopular: [CatalogPackage],
        featured: [CatalogPackage],
        allByPopularity: [CatalogPackage],
        formulaCount: Int
    ) {
        self.housePick = housePick
        self.mostPopular = mostPopular
        self.featured = featured
        self.allByPopularity = allByPopularity
        self.formulaCount = formulaCount
    }

    /// No snapshot has produced any content yet.
    public static let empty = FormulaBrowseContent(
        housePick: nil,
        mostPopular: [],
        featured: [],
        allByPopularity: [],
        formulaCount: 0
    )
}
