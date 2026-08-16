import Foundation

/// Where tapping a browse section header leads.
public enum CaskBrowseDestination: Hashable, Sendable {
    case topCharts
    case recentlyAdded
    case category(String)
}

/// One shelf of the browse page: a title, a destination, and at most a
/// section's worth of casks in the order the projection decided.
public struct CaskBrowseSection: Sendable, Hashable, Identifiable {
    public let destination: CaskBrowseDestination
    public let title: String
    public let casks: [CatalogPackage]

    public var id: CaskBrowseDestination { destination }

    public init(destination: CaskBrowseDestination, title: String, casks: [CatalogPackage]) {
        self.destination = destination
        self.title = title
        self.casks = casks
    }
}

/// Everything the cask browse page renders. No SwiftUI in sight, mirroring
/// `DiscoverContent`.
public struct CaskBrowseContent: Sendable, Hashable {
    /// The most popular eligible cask — the hero card.
    public let housePick: CatalogPackage?
    /// Non-empty sections only, in presentation order.
    public let sections: [CaskBrowseSection]
    /// The Featured page: the top eligible casks by annual installs, capped at
    /// `CaskBrowseProjection.featuredSize`, in popularity order.
    public let featured: [CatalogPackage]
    /// The whole eligible universe, uncapped, in the same annual popularity
    /// order the shelves inherit — the Top Charts page's input and the browse
    /// search's haystack.
    public let allByPopularity: [CatalogPackage]
    /// Every eligible cask, uncapped — the "N casks" label.
    public let caskCount: Int
    /// How many eligible casks each category holds, uncapped; a cask counts
    /// into **every** unique category of its mapping. The sidebar's numbers.
    public let categoryCounts: [String: Int]
    /// Token → ISO date string, exactly as the mined dates resource decoded —
    /// the Recently Added page's raw material. Empty when the resource never
    /// loaded, which the recency rule already reads as "nothing is new".
    public let addedDates: [String: String]

    public init(
        housePick: CatalogPackage?,
        sections: [CaskBrowseSection],
        featured: [CatalogPackage],
        allByPopularity: [CatalogPackage],
        caskCount: Int,
        categoryCounts: [String: Int],
        addedDates: [String: String]
    ) {
        self.housePick = housePick
        self.sections = sections
        self.featured = featured
        self.allByPopularity = allByPopularity
        self.caskCount = caskCount
        self.categoryCounts = categoryCounts
        self.addedDates = addedDates
    }

    /// Before any snapshot has been adopted, and after one with nothing
    /// eligible: the page has nothing to say.
    public static let empty = CaskBrowseContent(
        housePick: nil,
        sections: [],
        featured: [],
        allByPopularity: [],
        caskCount: 0,
        categoryCounts: [:],
        addedDates: [:]
    )
}
