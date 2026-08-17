import Foundation
import Testing

@testable import Catalog

/// The formula storefront's projection: the cask browse rules re-applied to
/// the other kind, minus everything whose data is cask-mined — no categories,
/// no added dates. What remains is eligibility, popularity, the house pick,
/// the Most Popular shelf, and the Featured cap.
@Suite("Formula browse projection")
struct FormulaBrowseProjectionTests {
    /// The cask suite's fixed clock, kept for symmetry.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Eligibility

    @Test("Only live unversioned formulae are eligible: no casks, deprecated, disabled or @-versioned tokens")
    func eligibilityFilterExcludesTheKnownShapes() {
        let content = Self.project(packages: [
            CatalogPackage.stub(kind: .cask, name: "iterm2", installCount365d: 9_000),
            Self.formula("olddeprecated", installs: 8_000, deprecated: true),
            Self.formula("olddisabled", installs: 7_000, disabled: true),
            Self.formula("python@3.12", installs: 6_000),
            Self.formula("wget", installs: 100)
        ])

        #expect(content.formulaCount == 1)
        #expect(content.mostPopular.map(\.name) == ["wget"])
        #expect(content.housePick?.name == "wget")
    }

    @Test("An empty or absent snapshot projects the empty content")
    func absentSnapshotProjectsEmpty() {
        #expect(FormulaBrowseProjection.content(snapshot: nil) == .empty)
        #expect(Self.project(packages: []) == .empty)
    }

    // MARK: - Popularity and the house pick

    @Test("Popularity sorts by annual installs descending, flattening absent counts to zero")
    func popularityOrderFlattensAbsentCountsToZero() {
        let content = Self.project(packages: [
            Self.formula("middling", installs: 5),
            Self.formula("unreported", installs: nil),
            Self.formula("top", installs: 10)
        ])

        // Absent is *sorted* as zero — the packages still carry `nil`, because
        // "not reported" is a different fact from "zero installs".
        #expect(content.mostPopular.map(\.name) == ["top", "middling", "unreported"])
        #expect(content.mostPopular.last?.installCount365d == nil)
    }

    @Test("The house pick is the most popular eligible formula")
    func housePickIsTheMostPopular() {
        let content = Self.project(packages: [
            Self.formula("ffmpeg", installs: 500),
            Self.formula("wget", installs: 900),
            Self.formula("jq", installs: 700)
        ])

        #expect(content.housePick?.name == "wget")
    }

    // MARK: - Caps

    @Test("The Most Popular shelf caps at twenty-four while allByPopularity stays uncapped")
    func mostPopularShelfCapsAtTwentyFour() {
        let formulae = (1...30).map { Self.formula("formula-\($0)", installs: 100 - $0) }
        let content = Self.project(packages: formulae)

        // Deeper than the cask shelves' eight on purpose: the cask Browse
        // fills its page with many shelves, the formula Browse has this one.
        #expect(content.mostPopular.count == 24)
        #expect(content.mostPopular.first?.name == "formula-1")
        #expect(content.allByPopularity.count == 30)
        #expect(content.formulaCount == 30)
    }

    @Test("Featured caps at one hundred, in popularity order")
    func featuredCapsAtOneHundred() {
        let formulae = (1...120).map { Self.formula("formula-\($0)", installs: 1_000 - $0) }
        let content = Self.project(packages: formulae)

        #expect(content.featured.count == 100)
        #expect(content.featured.first?.name == "formula-1")
        #expect(content.featured.last?.name == "formula-100")
    }

    // MARK: - Store integration

    @Test("Formula browse content lands with the adopted snapshot, beside the cask browse")
    @MainActor
    func formulaBrowseIsInstalledWithTheSnapshot() async throws {
        let harness = try SyncHarness()
        let store = CatalogStore(engine: harness.engine)

        #expect(store.formulaBrowse == .empty)

        await store.adopt(
            CatalogSnapshot(
                generatedAt: Self.now,
                skippedRecordCount: 0,
                packages: [
                    Self.formula("wget", installs: 900),
                    Self.formula("jq", installs: 500),
                    CatalogPackage.stub(kind: .cask, name: "iterm2", installCount365d: 9_000)
                ]
            )
        )

        #expect(store.formulaBrowse.formulaCount == 2)
        #expect(store.formulaBrowse.housePick?.name == "wget")
    }

    // MARK: - Helpers

    static func project(packages: [CatalogPackage]) -> FormulaBrowseContent {
        FormulaBrowseProjection.content(
            snapshot: CatalogSnapshot(
                generatedAt: now,
                skippedRecordCount: 0,
                packages: packages
            )
        )
    }

    static func formula(
        _ name: String,
        installs: Int?,
        deprecated: Bool = false,
        disabled: Bool = false
    ) -> CatalogPackage {
        CatalogPackage.stub(
            kind: .formula,
            name: name,
            deprecated: deprecated,
            disabled: disabled,
            installCount365d: installs
        )
    }
}
