import Foundation

/// Builds `CaskBrowseContent` from what the catalog already holds, porting
/// CaskHub's `CatalogProjector` rules verbatim.
///
/// Pure and `nonisolated`, like `DiscoverProjection`: a snapshot already in
/// memory and two resources already decoded. No request, no subprocess, no
/// sync triggered by a page being rendered.
public enum CaskBrowseProjection {
    /// How many casks a section shows before its destination takes over.
    public static let sectionSize = 8
    /// How many casks the Featured page shows, CaskHub's cap verbatim.
    public static let featuredSize = 100
    /// How far back "recently added" reaches, in days.
    public static let defaultRecentWindowDays = 30

    /// `content(...)` off the caller's actor.
    ///
    /// `@concurrent` rather than a plain `nonisolated func`, mirroring
    /// `DiscoverProjection.build`: a synchronous nonisolated call from the main
    /// actor still runs *on* it, and sorting ~4k casks per adoption is exactly
    /// the kind of work that path keeps off the main actor.
    @concurrent
    public static func build(
        snapshot: CatalogSnapshot?,
        catalog: CaskCategoryCatalog?,
        addedDates: CaskAddedDates?,
        now: Date,
        recentWindowDays: Int = defaultRecentWindowDays
    ) async -> CaskBrowseContent {
        content(
            snapshot: snapshot,
            catalog: catalog,
            addedDates: addedDates,
            now: now,
            recentWindowDays: recentWindowDays
        )
    }

    public nonisolated static func content(
        snapshot: CatalogSnapshot?,
        catalog: CaskCategoryCatalog?,
        addedDates: CaskAddedDates?,
        now: Date,
        recentWindowDays: Int = defaultRecentWindowDays
    ) -> CaskBrowseContent {
        // No usable snapshot: nothing has been measured yet.
        guard let snapshot else { return .empty }

        // Eligibility, CaskHub's filter verbatim: live casks only, and neither
        // versioned aliases ("@") nor fonts belong on a browse shelf.
        let casks = snapshot.packages.filter { package in
            package.kind == .cask
                && !package.deprecated
                && !package.disabled
                && !package.name.contains("@")
                && !package.name.hasPrefix("font-")
        }
        guard !casks.isEmpty else { return .empty }

        // Absent counts flatten to zero for this sort **only** — the packages
        // keep their `nil`, because "not reported" is not "zero installs".
        let popularityOrder = casks.sorted {
            ($0.installCount365d ?? 0) > ($1.installCount365d ?? 0)
        }

        let dates = addedDates?.tokenAddedDates ?? [:]

        // One pass over popularity order fills every category page, uncapped,
        // so each page inherits popularity order for free. The counts fall out
        // of the same fill, and the shelves take their eight off the top: the
        // shelf is a display rule, the page and the number are facts.
        var casksByCategory: [String: [CatalogPackage]] = [:]
        if let catalog {
            for cask in popularityOrder {
                for categoryID in catalog.uniqueCategoryIDs(for: cask.name) {
                    casksByCategory[categoryID, default: []].append(cask)
                }
            }
        }
        let categoryCounts = casksByCategory.mapValues(\.count)

        var sections = [
            CaskBrowseSection(
                destination: .topCharts,
                title: "Most Popular",
                casks: Array(popularityOrder.prefix(sectionSize))
            ),
            CaskBrowseSection(
                destination: .recentlyAdded,
                title: "Recently Added",
                casks: Array(
                    sortedByNewest(
                        recentCasks(
                            in: casks,
                            addedDates: dates,
                            now: now,
                            windowDays: recentWindowDays
                        ),
                        addedDates: dates
                    )
                    .prefix(sectionSize)
                )
            )
        ]
        for category in catalog?.orderedCategories ?? [] where category.id != "other" {
            sections.append(
                CaskBrowseSection(
                    destination: .category(category.id),
                    title: category.definition.displayName,
                    casks: Array((casksByCategory[category.id] ?? []).prefix(sectionSize))
                )
            )
        }

        return CaskBrowseContent(
            housePick: popularityOrder.first,
            sections: sections.filter { !$0.casks.isEmpty },
            featured: Array(popularityOrder.prefix(featuredSize)),
            allByPopularity: popularityOrder,
            caskCount: casks.count,
            categoryCounts: categoryCounts,
            categories: (catalog?.orderedCategories ?? []).map {
                CaskCategorySummary(
                    id: $0.id,
                    displayName: $0.definition.displayName,
                    icon: $0.definition.icon
                )
            },
            casksByCategory: casksByCategory,
            addedDates: dates
        )
    }

    // MARK: - Charts

    /// The Top Charts ordering: the eligible universe re-ranked by one
    /// window's counts, or handed back untouched when the window is the annual
    /// one the incoming order already encodes.
    ///
    /// The sort is stable and absent tokens flatten to zero for the sort
    /// **only** — so a window that never measured a cask leaves it exactly
    /// where the 365d popularity order put it, and ties break deterministically.
    public nonisolated static func chart(
        _ casks: [CatalogPackage],
        counts: [String: Int]?
    ) -> [CatalogPackage] {
        guard let counts else { return casks }
        return casks.sorted { (counts[$0.name] ?? 0) > (counts[$1.name] ?? 0) }
    }

    // MARK: - Recency

    /// The casks the window calls recent, in the order they came in — the
    /// browse shelf's rule and the Recently Added page's, one function.
    ///
    /// A filter, never a ranking: the universe arrives popularity-ordered and
    /// the page applies its own sort separately, so "Most Popular" is free.
    public nonisolated static func recentCasks(
        in casks: [CatalogPackage],
        addedDates: [String: String],
        now: Date,
        windowDays: Int
    ) -> [CatalogPackage] {
        let recentTokens = recentTokens(in: addedDates, now: now, windowDays: windowDays)
        return casks.filter { isRecent($0.name, in: recentTokens, addedDates: addedDates) }
    }

    /// Tokens whose date string reaches the window cutoff.
    ///
    /// The cutoff is a **date string** and the comparison is lexicographic,
    /// exactly as CaskHub does it: ISO8601 makes string order chronological
    /// order, so nothing here ever parses a date.
    private static func recentTokens(
        in addedDates: [String: String],
        now: Date,
        windowDays: Int
    ) -> Set<String> {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -windowDays, to: now) ?? now
        let cutoff = cutoffDate.formatted(.iso8601.year().month().day())
        return Set(addedDates.filter { $0.value >= cutoff }.keys)
    }

    /// Catalog tokens absent from the mined dates postdate the last mine, so
    /// they are the newest casks; an empty dictionary means the data never
    /// loaded, so nothing is new.
    private static func isRecent(
        _ token: String,
        in recentTokens: Set<String>,
        addedDates: [String: String]
    ) -> Bool {
        recentTokens.contains(token)
            || (!addedDates.isEmpty && addedDates[token] == nil)
    }

    /// Newest first by string compare; an undated token falls back to "9999",
    /// which outranks every ISO year — absent from the mine means newest.
    public nonisolated static func sortedByNewest(
        _ casks: [CatalogPackage],
        addedDates: [String: String]
    ) -> [CatalogPackage] {
        casks.sorted {
            (addedDates[$0.name] ?? "9999") > (addedDates[$1.name] ?? "9999")
        }
    }

    /// The same compare ascending: oldest first, with the "9999"-defaulted
    /// undated tokens — the mine's newest — bringing up the rear.
    public nonisolated static func sortedByOldest(
        _ casks: [CatalogPackage],
        addedDates: [String: String]
    ) -> [CatalogPackage] {
        casks.sorted {
            (addedDates[$0.name] ?? "9999") < (addedDates[$1.name] ?? "9999")
        }
    }
}
