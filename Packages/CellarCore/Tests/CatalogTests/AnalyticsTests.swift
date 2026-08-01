import Foundation
import Testing

@testable import Catalog

@Suite("Analytics join")
struct AnalyticsTests {
    // MARK: - Parsing (CS9)

    @Test(
        "Comma-grouped counts parse to the same integer whatever the locale",
        arguments: [
            ("2,808,879", 2_808_879),
            ("1,070,144", 1_070_144),
            ("1,234", 1_234),
            ("12", 12),
            ("0", 0)
        ]
    )
    func commaGroupedCountsParse(input: String, expected: Int) {
        #expect(AnalyticsIndex.parseCount(input) == expected)
    }

    @Test(
        "Anything the API does not emit is rejected rather than half-read",
        arguments: ["", "abc", "1.234", "1 234", "-5", "2,80x,879"]
    )
    func nonConformingCountsAreRejected(input: String) {
        // `1.234` is the trap a locale-sensitive parser falls into: under a
        // German locale `NumberFormatter` reads it as 1234, and under a US one
        // as 1.234 → 1. The API only ever emits comma grouping, so the honest
        // answer to a dot is "not a count I recognise".
        #expect(AnalyticsIndex.parseCount(input) == nil)
    }

    // MARK: - Namespacing (CS9, PD5)

    @Test("Formula and cask item keys land in their own namespace")
    func itemKeysAreNamespaced() throws {
        let index = try AnalyticsIndex.decode(
            Fixture.data("analytics-formula-365d"),
            kind: .formula
        )
        .merging(
            try AnalyticsIndex.decode(Fixture.data("analytics-cask-365d"), kind: .cask)
        )

        #expect(index.count(for: PackageID(kind: .formula, name: "gh")) == 2_809_017)
        #expect(index.count(for: PackageID(kind: .formula, name: "node")) == 2_543_320)
        #expect(index.count(for: PackageID(kind: .cask, name: "claude-code")) == 1_070_144)
        #expect(index.count(for: PackageID(kind: .cask, name: "visual-studio-code")) == 494_727)

        // `gh` is a formula, never a cask: the namespaces do not leak.
        #expect(index.count(for: PackageID(kind: .cask, name: "gh")) == nil)
        #expect(index.count(for: PackageID(kind: .formula, name: "claude-code")) == nil)
    }

    @Test("A package with no analytics entry has an absent count, not zero")
    func missingEntryIsAbsent() throws {
        let index = try AnalyticsIndex.decode(
            Fixture.data("analytics-formula-365d"),
            kind: .formula
        )

        #expect(index.count(for: PackageID(kind: .formula, name: "obscure")) == nil)

        let snapshot = CatalogDecoder.link(
            formulae: DecodedResource(
                packages: [
                    CatalogPackage.stub(kind: .formula, name: "gh"),
                    CatalogPackage.stub(kind: .formula, name: "obscure")
                ],
                skippedRecordCount: 0
            ),
            casks: .empty,
            analytics: index,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        let ghFormula = try #require(snapshot.packages.first { $0.name == "gh" })
        let obscure = try #require(snapshot.packages.first { $0.name == "obscure" })
        #expect(ghFormula.installCount365d == 2_809_017)
        #expect(obscure.installCount365d == nil)
        #expect(obscure.installCount == nil)
    }

    // MARK: - Degradation (CS9)

    @Test("A failed analytics fetch still produces a successful sync")
    func analyticsFailureIsNotFatal() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["gh", "node"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.script(.failure(.httpStatus(503)), for: .analyticsFormula)
        harness.source.script(.failure(.offline), for: .analyticsCask)

        let result = await harness.engine.sync()

        #expect(result.value != nil)
        #expect(await harness.engine.status == .succeeded(at: harness.time.now))
        let snapshot = try #require(try harness.store.loadSnapshot())
        #expect(snapshot.packages.count == 3)
        #expect(snapshot.packages.allSatisfy { $0.installCount365d == nil })
    }

    @Test("A successful analytics fetch joins counts onto the snapshot")
    func analyticsSuccessJoinsCounts() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["gh", "obscure"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        harness.source.script(
            .payload(try Fixture.data("analytics-formula-365d")),
            for: .analyticsFormula
        )
        harness.source.script(
            .payload(try Fixture.data("analytics-cask-365d")),
            for: .analyticsCask
        )

        let result = await harness.engine.sync()

        let snapshot = try #require(result.value)
        let ghFormula = try #require(snapshot.packages.first { $0.name == "gh" })
        let obscure = try #require(snapshot.packages.first { $0.name == "obscure" })
        #expect(ghFormula.installCount365d == 2_809_017)
        #expect(obscure.installCount365d == nil)
    }

    // MARK: - Honest presentation (PD5)

    @Test("A formula count is published as a 365-day installs-on-request lower bound")
    func formulaCountCarriesItsSemantics() throws {
        let ghFormula = CatalogPackage.stub(kind: .formula, name: "gh", installCount365d: 2_808_879)
        let count = try #require(ghFormula.installCount)

        #expect(count.value == 2_808_879)
        #expect(count.windowDays == 365)
        #expect(count.metric == .installsOnRequest)
        #expect(count.isLowerBound)
    }

    @Test("A cask count is published as a 365-day installs lower bound")
    func caskCountCarriesItsSemantics() throws {
        let code = CatalogPackage.stub(kind: .cask, name: "visual-studio-code", installCount365d: 494_727)
        let count = try #require(code.installCount)

        #expect(count.value == 494_727)
        #expect(count.windowDays == 365)
        #expect(count.metric == .installs)
        #expect(count.isLowerBound)
    }

    @Test("A recorded zero is a count, an absent entry is not")
    func zeroIsDistinctFromAbsent() throws {
        let quiet = CatalogPackage.stub(kind: .formula, name: "quiet", installCount365d: 0)
        let unknown = CatalogPackage.stub(kind: .formula, name: "unknown", installCount365d: nil)

        #expect(quiet.installCount?.value == 0)
        #expect(unknown.installCount == nil)
    }
}
