import Foundation
import Testing

@testable import Catalog

/// The CaskHub-style browse projection: eligibility, popularity, recency and
/// the single-pass category fill, ported rule for rule from CaskHub's
/// `CatalogProjector`.
@Suite("Cask browse projection")
struct CaskBrowseProjectionTests {
    /// 2027-01-15T08:00:00Z — the same fixed clock the Discover suite uses.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Eligibility

    @Test("Only live casks are eligible: no formulae, deprecated, disabled, versioned or font tokens")
    func eligibilityFilterExcludesTheKnownShapes() {
        let content = Self.project(packages: [
            CatalogPackage.stub(kind: .formula, name: "wget", installCount365d: 9_000),
            Self.cask("olddeprecated", installs: 8_000, deprecated: true),
            Self.cask("olddisabled", installs: 7_000, disabled: true),
            Self.cask("app@beta", installs: 6_000),
            Self.cask("font-fira-code", installs: 5_000),
            Self.cask("iterm2", installs: 100)
        ])

        #expect(content.caskCount == 1)
        let popular = Self.section(.topCharts, in: content)
        #expect(popular?.casks.map(\.name) == ["iterm2"])
        #expect(content.housePick?.name == "iterm2")
    }

    @Test("An empty or absent snapshot projects the empty content")
    func absentSnapshotProjectsEmpty() {
        #expect(
            CaskBrowseProjection.content(
                snapshot: nil, catalog: nil, addedDates: nil, now: Self.now
            ) == .empty
        )
        #expect(Self.project(packages: []) == .empty)
    }

    // MARK: - Popularity and the house pick

    @Test("Popularity sorts by annual installs descending, flattening absent counts to zero")
    func popularityOrderFlattensAbsentCountsToZero() {
        let content = Self.project(packages: [
            Self.cask("middling", installs: 5),
            Self.cask("unreported", installs: nil),
            Self.cask("top", installs: 10)
        ])

        // Absent is *sorted* as zero — the packages still carry `nil`, because
        // "not reported" is a different fact from "zero installs".
        let popular = try? #require(Self.section(.topCharts, in: content))
        #expect(popular?.casks.map(\.name) == ["top", "middling", "unreported"])
        #expect(popular?.casks.last?.installCount365d == nil)
    }

    @Test("The house pick is the most popular eligible cask")
    func housePickIsTheMostPopularCask() {
        let content = Self.project(packages: [
            Self.cask("runnerup", installs: 50),
            Self.cask("winner", installs: 900)
        ])

        #expect(content.housePick?.name == "winner")
    }

    @Test("With every count absent the house pick is the first eligible cask, stably")
    func housePickIsStableWhenNothingIsCounted() {
        let content = Self.project(packages: [
            Self.cask("first", installs: nil),
            Self.cask("second", installs: nil)
        ])

        #expect(content.housePick?.name == "first")
    }

    // MARK: - Section size

    @Test("Every section shows at most eight casks")
    func sectionsCapAtEight() {
        let packages = (0..<12).map {
            Self.cask(String(format: "cask%02d", $0), installs: (12 - $0) * 10)
        }
        let catalog = Self.catalog(
            categories: ["utilities": CaskCategoryDefinition(displayName: "Utilities", icon: "wrench")],
            mappings: Dictionary(
                uniqueKeysWithValues: packages.map {
                    ($0.name, CaskCategoryMapping(primary: "utilities", secondary: []))
                }
            )
        )

        let content = Self.project(packages: packages, catalog: catalog)

        #expect(Self.section(.topCharts, in: content)?.casks.count == 8)
        #expect(Self.section(.category("utilities"), in: content)?.casks.count == 8)
        // The cap is a display rule; the totals stay honest.
        #expect(content.caskCount == 12)
        #expect(content.categoryCounts["utilities"] == 12)
    }

    // MARK: - Category fill

    @Test("Category sections are filled in one pass, so each keeps popularity order")
    func categoryFillPreservesPopularityOrder() throws {
        let catalog = Self.catalog(
            categories: [
                "browsers": CaskCategoryDefinition(displayName: "Browsers", icon: "globe"),
                "utilities": CaskCategoryDefinition(displayName: "Utilities", icon: "wrench")
            ],
            mappings: [
                "arc": CaskCategoryMapping(primary: "browsers", secondary: ["utilities"]),
                "firefox": CaskCategoryMapping(primary: "browsers", secondary: []),
                "raycast": CaskCategoryMapping(primary: "utilities", secondary: [])
            ]
        )

        let content = Self.project(
            packages: [
                Self.cask("firefox", installs: 300),
                Self.cask("raycast", installs: 900),
                Self.cask("arc", installs: 500)
            ],
            catalog: catalog
        )

        let browsers = try #require(Self.section(.category("browsers"), in: content))
        let utilities = try #require(Self.section(.category("utilities"), in: content))
        #expect(browsers.casks.map(\.name) == ["arc", "firefox"])
        // The secondary mapping lands `arc` in utilities too, after the more
        // popular `raycast`.
        #expect(utilities.casks.map(\.name) == ["raycast", "arc"])
        #expect(browsers.title == "Browsers")
    }

    @Test("A cask counts into every unique category of its mapping")
    func categoryCountsCoverEveryUniqueCategory() {
        let catalog = Self.catalog(
            categories: [
                "browsers": CaskCategoryDefinition(displayName: "Browsers", icon: "globe"),
                "utilities": CaskCategoryDefinition(displayName: "Utilities", icon: "wrench")
            ],
            mappings: [
                // The duplicated secondary must not double-count.
                "arc": CaskCategoryMapping(primary: "browsers", secondary: ["utilities", "browsers", "utilities"])
            ]
        )

        let content = Self.project(packages: [Self.cask("arc", installs: 1)], catalog: catalog)

        #expect(content.categoryCounts == ["browsers": 1, "utilities": 1])
    }

    @Test("Category sections follow the ordered catalog, and other never becomes a section")
    func categorySectionsFollowCatalogOrderWithoutOther() {
        let catalog = Self.catalog(
            categories: [
                "other": CaskCategoryDefinition(displayName: "Other", icon: "square.grid.2x2"),
                "utilities": CaskCategoryDefinition(displayName: "Utilities", icon: "wrench"),
                "browsers": CaskCategoryDefinition(displayName: "Browsers", icon: "globe")
            ],
            mappings: [
                "arc": CaskCategoryMapping(primary: "browsers", secondary: []),
                "raycast": CaskCategoryMapping(primary: "utilities", secondary: []),
                "misc": CaskCategoryMapping(primary: "other", secondary: [])
            ]
        )

        let content = Self.project(
            packages: [
                Self.cask("arc", installs: 3),
                Self.cask("raycast", installs: 2),
                Self.cask("misc", installs: 1)
            ],
            catalog: catalog
        )

        // "Other" is still *counted* — the sidebar wants the number — it just
        // never renders as a browse section.
        #expect(content.categoryCounts["other"] == 1)
        #expect(
            content.sections.map(\.destination) == [
                .topCharts, .category("browsers"), .category("utilities")
            ]
        )
    }

    @Test("A section with nothing in it is dropped rather than rendered empty")
    func emptySectionsAreDropped() {
        let catalog = Self.catalog(
            categories: [
                "browsers": CaskCategoryDefinition(displayName: "Browsers", icon: "globe"),
                "games": CaskCategoryDefinition(displayName: "Games", icon: "gamecontroller")
            ],
            mappings: ["arc": CaskCategoryMapping(primary: "browsers", secondary: [])]
        )

        let content = Self.project(packages: [Self.cask("arc", installs: 1)], catalog: catalog)

        // No cask maps to games, nothing is recent: neither section exists.
        #expect(Self.section(.category("games"), in: content) == nil)
        #expect(Self.section(.recentlyAdded, in: content) == nil)
    }

    // MARK: - The category pages

    @Test("Content carries the ordered category summaries: id, display name and icon, other last")
    func contentCarriesOrderedCategorySummaries() {
        let catalog = Self.catalog(
            categories: [
                "other": CaskCategoryDefinition(displayName: "Other", icon: "square.grid.2x2"),
                "utilities": CaskCategoryDefinition(displayName: "Utilities", icon: "wrench"),
                "browsers": CaskCategoryDefinition(displayName: "Browsers", icon: "globe")
            ],
            mappings: ["arc": CaskCategoryMapping(primary: "browsers", secondary: [])]
        )

        let content = Self.project(packages: [Self.cask("arc", installs: 1)], catalog: catalog)

        // Unlike the browse sections, "other" *is* a page — it just still
        // closes the list, exactly as `orderedCategories` puts it.
        #expect(content.categories.map(\.id) == ["browsers", "utilities", "other"])
        #expect(
            content.categories.first
                == CaskCategorySummary(id: "browsers", displayName: "Browsers", icon: "globe")
        )
    }

    @Test("casksByCategory is uncapped, popularity-ordered, and covers every unique category")
    func casksByCategoryIsTheUncappedFill() throws {
        let extras = (0..<10).map {
            Self.cask(String(format: "util%02d", $0), installs: (10 - $0) * 10)
        }
        var mappings = Dictionary(
            uniqueKeysWithValues: extras.map {
                ($0.name, CaskCategoryMapping(primary: "utilities", secondary: []))
            }
        )
        mappings["arc"] = CaskCategoryMapping(primary: "browsers", secondary: ["utilities"])
        let catalog = Self.catalog(
            categories: [
                "browsers": CaskCategoryDefinition(displayName: "Browsers", icon: "globe"),
                "utilities": CaskCategoryDefinition(displayName: "Utilities", icon: "wrench")
            ],
            mappings: mappings
        )

        let content = Self.project(
            packages: extras + [Self.cask("arc", installs: 55), Self.cask("unmapped", installs: 9_000)],
            catalog: catalog
        )

        // Eleven utilities: past the shelf's cap of eight, because the page
        // shows everything the shelf merely samples.
        let utilities = try #require(content.casksByCategory["utilities"])
        #expect(utilities.count == 11)
        #expect(utilities.map(\.name) == [
            "util00", "util01", "util02", "util03", "util04",
            "arc", "util05", "util06", "util07", "util08", "util09"
        ])
        // The secondary mapping lands `arc` on both pages.
        #expect(content.casksByCategory["browsers"]?.map(\.name) == ["arc"])
        // An unmapped token belongs to no page at all, popular or not.
        #expect(content.casksByCategory.values.allSatisfy { casks in
            !casks.contains { $0.name == "unmapped" }
        })
    }

    @Test("Without a category catalog the summaries and the fill are empty")
    func categoriesAreEmptyWithoutACatalog() {
        let content = Self.project(packages: [Self.cask("arc", installs: 1)])

        #expect(content.categories.isEmpty)
        #expect(content.casksByCategory.isEmpty)
        #expect(CaskBrowseContent.empty.categories.isEmpty)
        #expect(CaskBrowseContent.empty.casksByCategory.isEmpty)
    }

    // MARK: - Recently added

    @Test("A token dated inside the window is recent; one dated before it is not")
    func recencyComparesDateStringsAgainstTheWindowCutoff() throws {
        let content = Self.project(
            packages: [
                Self.cask("fresh", installs: 1),
                Self.cask("stale", installs: 2)
            ],
            addedDates: Self.dates([
                "fresh": "2027-01-10T00:00:00Z",
                "stale": "2026-11-01T00:00:00Z"
            ])
        )

        let recent = try #require(Self.section(.recentlyAdded, in: content))
        #expect(recent.casks.map(\.name) == ["fresh"])
        #expect(recent.title == "Recently Added")
    }

    @Test("A token absent from a non-empty dates file postdates the mine, so it is new")
    func absentTokenIsNewWhenDatesExist() throws {
        let content = Self.project(
            packages: [Self.cask("postdates-the-mine", installs: 1)],
            addedDates: Self.dates(["someothertoken": "2020-01-01T00:00:00Z"])
        )

        let recent = try #require(Self.section(.recentlyAdded, in: content))
        #expect(recent.casks.map(\.name) == ["postdates-the-mine"])
    }

    @Test("An empty dates dictionary means the data never loaded, so nothing is new")
    func nothingIsNewWhenDatesNeverLoaded() {
        let content = Self.project(
            packages: [Self.cask("anything", installs: 1)],
            addedDates: Self.dates([:])
        )

        #expect(Self.section(.recentlyAdded, in: content) == nil)
    }

    @Test("Recently added sorts by date string descending, undated tokens first")
    func newestSortIsAStringCompareWithUndatedFirst() throws {
        let content = Self.project(
            packages: [
                Self.cask("older", installs: 900),
                Self.cask("undated", installs: 1),
                Self.cask("newer", installs: 500)
            ],
            addedDates: Self.dates([
                "older": "2027-01-08T00:00:00Z",
                "newer": "2027-01-12T00:00:00Z",
                "anchor": "2020-01-01T00:00:00Z"
            ])
        )

        // The undated token falls back to "9999", which outranks any ISO year:
        // newest-first puts it ahead of every dated cask, popularity be damned.
        let recent = try #require(Self.section(.recentlyAdded, in: content))
        #expect(recent.casks.map(\.name) == ["undated", "newer", "older"])
    }

    // MARK: - The Recently Added page

    @Test("Content carries the dates map the projection loaded, empty when it never did")
    func contentCarriesTheAddedDatesMap() {
        let map = ["fresh": "2027-01-10T00:00:00Z"]

        let content = Self.project(
            packages: [Self.cask("fresh", installs: 1)],
            addedDates: Self.dates(map)
        )

        #expect(content.addedDates == map)
        // No dates resource at all: the page gets the empty map, not a crash.
        #expect(Self.project(packages: [Self.cask("fresh", installs: 1)]).addedDates == [:])
        #expect(CaskBrowseContent.empty.addedDates == [:])
    }

    @Test("A cask dated exactly at the cutoff is recent, and drops out as the window shrinks")
    func recentCasksIncludeTheCutoffDayAndShrinkWithTheWindow() {
        // `now` is 2027-01-15T08:00:00Z, so the cutoffs land on 2026-12-16,
        // 2026-11-16 and 2026-10-17. Each cask sits exactly *on* one cutoff:
        // `>=` keeps it in, and the next narrower window drops it.
        let casks = [
            Self.cask("at30", installs: 3),
            Self.cask("at60", installs: 2),
            Self.cask("at90", installs: 1),
            Self.cask("ancient", installs: 900)
        ]
        let dates = [
            "at30": "2026-12-16T00:00:00Z",
            "at60": "2026-11-16T00:00:00Z",
            "at90": "2026-10-17T00:00:00Z",
            "ancient": "2020-01-01T00:00:00Z"
        ]

        #expect(
            CaskBrowseProjection.recentCasks(
                in: casks, addedDates: dates, now: Self.now, windowDays: 90
            ).map(\.name) == ["at30", "at60", "at90"]
        )
        #expect(
            CaskBrowseProjection.recentCasks(
                in: casks, addedDates: dates, now: Self.now, windowDays: 60
            ).map(\.name) == ["at30", "at60"]
        )
        #expect(
            CaskBrowseProjection.recentCasks(
                in: casks, addedDates: dates, now: Self.now, windowDays: 30
            ).map(\.name) == ["at30"]
        )
    }

    @Test("recentCasks treats a token absent from a non-empty dates map as new")
    func recentCasksTreatAbsentTokensAsNew() {
        let recent = CaskBrowseProjection.recentCasks(
            in: [Self.cask("postdates-the-mine", installs: 1)],
            addedDates: ["someothertoken": "2020-01-01T00:00:00Z"],
            now: Self.now,
            windowDays: 30
        )

        #expect(recent.map(\.name) == ["postdates-the-mine"])
    }

    @Test("recentCasks finds nothing when the dates map never loaded")
    func recentCasksAreEmptyWhenDatesNeverLoaded() {
        let recent = CaskBrowseProjection.recentCasks(
            in: [Self.cask("anything", installs: 1)],
            addedDates: [:],
            now: Self.now,
            windowDays: 90
        )

        #expect(recent.isEmpty)
    }

    @Test("recentCasks preserves the input order — the page sorts separately")
    func recentCasksPreserveInputOrder() {
        // Popularity order in, popularity order out, however the dates fall:
        // the filter is a filter, not a ranking.
        let casks = [
            Self.cask("older-but-popular", installs: 900),
            Self.cask("newest", installs: 5),
            Self.cask("middling", installs: 50)
        ]
        let dates = [
            "older-but-popular": "2027-01-01T00:00:00Z",
            "newest": "2027-01-14T00:00:00Z",
            "middling": "2027-01-08T00:00:00Z"
        ]

        let recent = CaskBrowseProjection.recentCasks(
            in: casks, addedDates: dates, now: Self.now, windowDays: 30
        )

        #expect(recent.map(\.name) == ["older-but-popular", "newest", "middling"])
    }

    @Test("sortedByNewest is a descending string compare with undated tokens first")
    func sortedByNewestPutsUndatedTokensFirst() {
        let sorted = CaskBrowseProjection.sortedByNewest(
            [
                Self.cask("older", installs: 900),
                Self.cask("undated", installs: 1),
                Self.cask("newer", installs: 500)
            ],
            addedDates: [
                "older": "2027-01-08T00:00:00Z",
                "newer": "2027-01-12T00:00:00Z"
            ]
        )

        // The undated token falls back to "9999", which outranks any ISO year.
        #expect(sorted.map(\.name) == ["undated", "newer", "older"])
    }

    @Test("sortedByOldest is the ascending compare, so undated tokens land last")
    func sortedByOldestPutsUndatedTokensLast() {
        let sorted = CaskBrowseProjection.sortedByOldest(
            [
                Self.cask("undated", installs: 1),
                Self.cask("newer", installs: 500),
                Self.cask("older", installs: 900)
            ],
            addedDates: [
                "older": "2027-01-08T00:00:00Z",
                "newer": "2027-01-12T00:00:00Z"
            ]
        )

        // The same "9999" fallback, mirrored: absent-from-the-mine means
        // newest, so an oldest-first list ends with it.
        #expect(sorted.map(\.name) == ["older", "newer", "undated"])
    }

    // MARK: - Featured

    @Test("Featured lists casks in popularity order, flattening absent counts to zero")
    func featuredIsPopularityOrdered() {
        let content = Self.project(packages: [
            Self.cask("middling", installs: 5),
            Self.cask("unreported", installs: nil),
            Self.cask("top", installs: 10)
        ])

        #expect(content.featured.map(\.name) == ["top", "middling", "unreported"])
        // Absent is *sorted* as zero — the package still carries `nil`.
        #expect(content.featured.last?.installCount365d == nil)
    }

    @Test("Featured caps at featuredSize while the totals stay honest")
    func featuredCapsAtFeaturedSize() {
        let packages = (0..<(CaskBrowseProjection.featuredSize + 3)).map {
            Self.cask(
                String(format: "cask%03d", $0),
                installs: CaskBrowseProjection.featuredSize + 3 - $0
            )
        }

        let content = Self.project(packages: packages)

        #expect(content.featured.count == CaskBrowseProjection.featuredSize)
        #expect(content.featured.first?.name == "cask000")
        #expect(content.featured.last?.name == String(
            format: "cask%03d", CaskBrowseProjection.featuredSize - 1
        ))
        // The cap is a display rule; the total stays honest.
        #expect(content.caskCount == packages.count)
    }

    @Test("Featured applies the same eligibility filter as the shelves")
    func featuredExcludesTheIneligibleShapes() {
        let content = Self.project(packages: [
            CatalogPackage.stub(kind: .formula, name: "wget", installCount365d: 9_000),
            Self.cask("olddeprecated", installs: 8_000, deprecated: true),
            Self.cask("olddisabled", installs: 7_000, disabled: true),
            Self.cask("app@beta", installs: 6_000),
            Self.cask("font-fira-code", installs: 5_000),
            Self.cask("iterm2", installs: 100)
        ])

        #expect(content.featured.map(\.name) == ["iterm2"])
    }

    @Test("An absent snapshot features nothing")
    func featuredIsEmptyForAbsentSnapshot() {
        let content = CaskBrowseProjection.content(
            snapshot: nil, catalog: nil, addedDates: nil, now: Self.now
        )

        #expect(content.featured.isEmpty)
    }

    // MARK: - The whole universe

    @Test("allByPopularity is the whole eligible set, uncapped, in popularity order")
    func allByPopularityIsTheWholeEligibleUniverse() {
        let packages = (0..<(CaskBrowseProjection.featuredSize + 3)).map {
            Self.cask(
                String(format: "cask%03d", $0),
                installs: CaskBrowseProjection.featuredSize + 3 - $0
            )
        }

        let content = Self.project(packages: packages.shuffled())

        // Featured caps; the universe does not — it is the "N casks" set itself.
        #expect(content.allByPopularity.count == packages.count)
        #expect(content.allByPopularity.map(\.name) == packages.map(\.name))
        #expect(content.allByPopularity.count == content.caskCount)
    }

    @Test("allByPopularity applies the same eligibility filter as the shelves")
    func allByPopularityExcludesTheIneligibleShapes() {
        let content = Self.project(packages: [
            CatalogPackage.stub(kind: .formula, name: "wget", installCount365d: 9_000),
            Self.cask("olddeprecated", installs: 8_000, deprecated: true),
            Self.cask("olddisabled", installs: 7_000, disabled: true),
            Self.cask("app@beta", installs: 6_000),
            Self.cask("font-fira-code", installs: 5_000),
            Self.cask("iterm2", installs: 100)
        ])

        #expect(content.allByPopularity.map(\.name) == ["iterm2"])
    }

    @Test("The empty content carries an empty universe")
    func emptyContentCarriesAnEmptyUniverse() {
        #expect(CaskBrowseContent.empty.allByPopularity.isEmpty)
    }

    // MARK: - Chart ordering

    @Test("chart with nil counts hands the input back untouched")
    func chartWithNilCountsIsAPassthrough() {
        let casks = [
            Self.cask("second", installs: 5),
            Self.cask("first", installs: 900)
        ]

        // The 365d case: the incoming order *is* the ranking.
        #expect(CaskBrowseProjection.chart(casks, counts: nil) == casks)
    }

    @Test("chart sorts by the window's counts descending, treating absent tokens as zero")
    func chartSortsByTheWindowsCountsDescending() {
        let casks = [
            Self.cask("annualtop", installs: 9_000),
            Self.cask("unranked", installs: 8_000),
            Self.cask("monthlytop", installs: 100)
        ]

        let ranked = CaskBrowseProjection.chart(
            casks,
            counts: ["monthlytop": 500, "annualtop": 40]
        )

        // The selected window's numbers decide, not the annual ones the
        // packages carry; a token the window never measured sorts as zero.
        #expect(ranked.map(\.name) == ["monthlytop", "annualtop", "unranked"])
    }

    @Test("chart is stable: tied counts keep the incoming order")
    func chartKeepsTheIncomingOrderForTies() {
        let casks = [
            Self.cask("kept-first", installs: 1),
            Self.cask("kept-second", installs: 2),
            Self.cask("kept-third", installs: 3)
        ]

        let ranked = CaskBrowseProjection.chart(casks, counts: ["elsewhere": 9])

        // All three flatten to zero, so the incoming (365d popularity) order
        // is the tie-break — by guarantee, not by luck.
        #expect(ranked.map(\.name) == ["kept-first", "kept-second", "kept-third"])
    }

    // MARK: - Store integration

    @Test("Cask browse content lands with the adopted snapshot, beside Discover")
    @MainActor
    func caskBrowseIsInstalledWithTheSnapshot() async throws {
        let harness = try SyncHarness()
        let store = CatalogStore(engine: harness.engine)

        #expect(store.caskBrowse == .empty)

        await store.adopt(
            CatalogSnapshot(
                generatedAt: Self.now,
                skippedRecordCount: 0,
                packages: [
                    Self.cask("iterm2", installs: 900),
                    Self.cask("arc", installs: 500),
                    CatalogPackage.stub(kind: .formula, name: "wget", installCount365d: 9_000)
                ]
            )
        )

        #expect(store.caskBrowse.caskCount == 2)
        #expect(store.caskBrowse.housePick?.name == "iterm2")
        // The shipped category catalog resolved real sections for real tokens.
        #expect(store.caskBrowse.sections.isEmpty == false)
    }

    // MARK: - Helpers

    static func project(
        packages: [CatalogPackage],
        catalog: CaskCategoryCatalog? = nil,
        addedDates: CaskAddedDates? = nil
    ) -> CaskBrowseContent {
        CaskBrowseProjection.content(
            snapshot: CatalogSnapshot(
                generatedAt: now,
                skippedRecordCount: 0,
                packages: packages
            ),
            catalog: catalog,
            addedDates: addedDates,
            now: now
        )
    }

    static func section(
        _ destination: CaskBrowseDestination,
        in content: CaskBrowseContent
    ) -> CaskBrowseSection? {
        content.sections.first { $0.destination == destination }
    }

    static func cask(
        _ name: String,
        installs: Int?,
        deprecated: Bool = false,
        disabled: Bool = false
    ) -> CatalogPackage {
        CatalogPackage.stub(
            kind: .cask,
            name: name,
            deprecated: deprecated,
            disabled: disabled,
            installCount365d: installs
        )
    }

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

    static func dates(_ tokenAddedDates: [String: String]) -> CaskAddedDates {
        CaskAddedDates(
            version: CaskAddedDates.schemaVersion,
            generatedDate: "2026-08-13T15:44:15Z",
            tokenAddedDates: tokenAddedDates
        )
    }
}
