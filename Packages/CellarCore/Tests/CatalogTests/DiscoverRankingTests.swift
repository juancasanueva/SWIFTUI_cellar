import Foundation
import Testing

@testable import Catalog

/// The two ranked ladders (package-discovery PD-R1, proposal D3).
///
/// The rule this suite exists to hold is *absent is not zero*: a package the
/// analytics endpoint never listed is **unmeasured**, and an unmeasured package
/// has no business on a most-installed ladder at any position. `installCount365d`
/// is `Int?` for exactly that reason, and the ladder is where flattening it to
/// `0` would be most tempting and most wrong.
@Suite("Discover ranked ladders")
struct DiscoverRankingTests {
    // MARK: - Two separate ladders (sc1)

    @Test("Formulae and casks rank on separate ladders, each on its own metric")
    func formulaeAndCasksRankSeparately() {
        // The highest-counted record in the whole snapshot is a cask, so a merged
        // ladder would put it above every formula — which is exactly the
        // incomparable-numbers mistake D3 rejected.
        let packages = [
            CatalogPackage.stub(kind: .cask, name: "topcask", installCount365d: 900_000),
            CatalogPackage.stub(kind: .cask, name: "midcask", installCount365d: 400_000),
            CatalogPackage.stub(kind: .formula, name: "topformula", installCount365d: 300_000),
            CatalogPackage.stub(kind: .formula, name: "midformula", installCount365d: 100_000)
        ]

        let formulae = DiscoverRanking.ladder(.formula, in: packages)
        let casks = DiscoverRanking.ladder(.cask, in: packages)

        #expect(formulae.map(\.package.name) == ["topformula", "midformula"])
        #expect(casks.map(\.package.name) == ["topcask", "midcask"])

        // No entry appears in both.
        let formulaIDs = Set(formulae.map(\.id))
        let caskIDs = Set(casks.map(\.id))
        #expect(formulaIDs.isDisjoint(with: caskIDs))

        // Each row reports the metric matching its kind: the two counts measure
        // different quantities and must never be presented as one.
        #expect(formulae.allSatisfy { $0.installs.metric == .installsOnRequest })
        #expect(casks.allSatisfy { $0.installs.metric == .installs })

        // Ranks are 1-based and within their own ladder, so both start at 1.
        #expect(formulae.map(\.rank) == [1, 2])
        #expect(casks.map(\.rank) == [1, 2])
        #expect(formulae[0].installs.value == 300_000)
        #expect(casks[0].installs.value == 900_000)
    }

    // MARK: - Absent is not zero (sc2)

    @Test("A package with no analytics entry is absent from the ladder, not last")
    func absentInstallCountIsAbsentFromTheLadder() {
        let packages = [
            CatalogPackage.stub(kind: .formula, name: "measured", installCount365d: 500),
            CatalogPackage.stub(kind: .formula, name: "alsomeasured", installCount365d: 4),
            // No analytics entry at all. Not "zero installs" — unmeasured.
            CatalogPackage.stub(kind: .formula, name: "obscure", installCount365d: nil)
        ]

        let ladder = DiscoverRanking.ladder(.formula, in: packages)

        #expect(ladder.map(\.package.name) == ["measured", "alsomeasured"])
        #expect(ladder.contains { $0.package.name == "obscure" } == false)
        // And nothing arrived carrying a `0` invented from an absent count. The
        // genuinely-low record is still there with its real `4`, which is what
        // makes this assertion about coercion rather than about filtering.
        #expect(ladder.contains { $0.installs.value == 0 } == false)
        #expect(ladder.map(\.installs.value) == [500, 4])
    }

    @Test("A zero published count is a measurement and still ranks")
    func publishedZeroIsAMeasurementNotAnAbsence() {
        // The mirror image of the test above, and the reason "absent is not zero"
        // needs both halves: a published `0` is a real analytics answer and must
        // appear, while an absent count must not — so a ladder cannot satisfy
        // both by simply dropping every zero.
        let packages = [
            CatalogPackage.stub(kind: .formula, name: "popular", installCount365d: 10),
            CatalogPackage.stub(kind: .formula, name: "measuredzero", installCount365d: 0),
            CatalogPackage.stub(kind: .formula, name: "unmeasured", installCount365d: nil)
        ]

        let ladder = DiscoverRanking.ladder(.formula, in: packages)

        #expect(ladder.map(\.package.name) == ["popular", "measuredzero"])
        #expect(ladder.map(\.installs.value) == [10, 0])
    }

    // MARK: - Deprecated and disabled are ineligible (sc3)

    @Test("Deprecated and disabled packages are ineligible for either ladder")
    func deprecatedAndDisabledAreIneligible() {
        let packages = [
            CatalogPackage.stub(
                kind: .formula, name: "abandoned", deprecated: true, installCount365d: 999_999
            ),
            CatalogPackage.stub(
                kind: .formula, name: "removed", disabled: true, installCount365d: 888_888
            ),
            CatalogPackage.stub(kind: .formula, name: "healthy", installCount365d: 100),
            CatalogPackage.stub(kind: .formula, name: "alsohealthy", installCount365d: 50)
        ]

        let ladder = DiscoverRanking.ladder(.formula, in: packages)

        // Recommending an abandoned package is worse than showing a shorter list
        // (D3), so the two highest-counted records in the snapshot are gone and
        // the ladder starts at the highest-counted record that is neither.
        #expect(ladder.map(\.package.name) == ["healthy", "alsohealthy"])
        #expect(ladder.first?.rank == 1)
        #expect(ladder.contains { $0.package.deprecated || $0.package.disabled } == false)
    }

    // MARK: - Depth (sc4)

    @Test("A short catalog yields a short ladder rather than a padded one")
    func shortCatalogYieldsShortLadder() {
        let packages = (1...7).map {
            CatalogPackage.stub(kind: .cask, name: "cask\($0)", installCount365d: $0 * 10)
        }

        let ladder = DiscoverRanking.ladder(.cask, in: packages)

        #expect(ladder.count == 7)
        // Descending by count, so the highest-numbered stub leads.
        #expect(ladder.first?.package.name == "cask7")
        #expect(ladder.last?.package.name == "cask1")
        #expect(ladder.map(\.rank) == Array(1...7))
    }

    @Test("The ladder stops at fifty and the fifty-first eligible package is absent")
    func ladderStopsAtFifty() {
        // 51 eligible formulae, counts descending with the name so the ordering
        // is unambiguous: `formula51` is the highest and `formula01` the lowest.
        let packages = (1...51).map { index in
            CatalogPackage.stub(
                kind: .formula,
                name: String(format: "formula%02d", index),
                installCount365d: index * 100
            )
        }

        let ladder = DiscoverRanking.ladder(.formula, in: packages)

        #expect(DiscoverRanking.ladderDepth == 50)
        #expect(ladder.count == 50)
        #expect(ladder.first?.package.name == "formula51")
        // The 51st-ranked record — the lowest count — is the one that falls off.
        #expect(ladder.contains { $0.package.name == "formula01" } == false)
        #expect(ladder.last?.package.name == "formula02")
        #expect(ladder.last?.rank == 50)
    }

    // MARK: - Deterministic total order (sc5)

    @Test("Equal counts order deterministically across runs")
    func equalCountsOrderDeterministically() {
        // Declared in an order that is neither alphabetical nor reversed, so a
        // ranking that leaked input order would produce `charlie, alpha, bravo`.
        let packages = [
            CatalogPackage.stub(kind: .formula, name: "charlie", installCount365d: 42),
            CatalogPackage.stub(kind: .formula, name: "alpha", installCount365d: 42),
            CatalogPackage.stub(kind: .formula, name: "bravo", installCount365d: 42)
        ]

        let first = DiscoverRanking.ladder(.formula, in: packages)
        let second = DiscoverRanking.ladder(.formula, in: packages)

        #expect(first.map(\.package.name) == ["alpha", "bravo", "charlie"])
        #expect(first.map(\.package.name) == second.map(\.package.name))
        #expect(first.map(\.rank) == second.map(\.rank))
    }

    // MARK: - Carried-forward counts (sc6)

    @Test("Counts carried forward by a revalidated sync still rank")
    func carriedForwardCountsStillRank() throws {
        // A 304 sync republishes the previous snapshot's records, analytics
        // included. Ranking reads only the snapshot it is given, so a
        // carried-forward count is an ordinary count.
        let previous = CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            skippedRecordCount: 0,
            packages: [
                CatalogPackage.stub(kind: .formula, name: "git", installCount365d: 7_000),
                CatalogPackage.stub(kind: .cask, name: "iterm2", installCount365d: 3_000)
            ]
        )
        let carried = previous.packages.filter { $0.kind == .formula }
            + previous.packages.filter { $0.kind == .cask }

        let formulae = DiscoverRanking.ladder(.formula, in: carried)
        let casks = DiscoverRanking.ladder(.cask, in: carried)

        #expect(formulae.isEmpty == false)
        #expect(casks.isEmpty == false)
        #expect(formulae.map(\.package.name) == ["git"])
        #expect(formulae.first?.installs.value == 7_000)
        #expect(casks.first?.installs.value == 3_000)
    }

    // MARK: - Structural guard (task 2.4)

    @Test("The ranking never reuses the search order and never coerces an absent count")
    func rankingDoesNotReuseTheSearchOrder() throws {
        let code = try CatalogSources.code(of: "DiscoverRanking.swift")
        CatalogSources.assertAnchored(code, expecting: "ladder")

        // `PackageSearchIndex.defaultOrder` sorts absent counts **last**, which
        // is right for an empty search query and wrong here: on a most-installed
        // ladder, unmeasured must not appear at all. Reusing it would satisfy
        // every ordering assertion above while quietly ranking `obscure` fiftieth.
        #expect(code.contains("defaultOrder") == false)
        // And nothing coerces an absent count into a number.
        #expect(code.contains("?? 0") == false)
    }
}
