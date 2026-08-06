import Catalog
import Foundation
import Testing

@testable import SecurityKit

/// The presentation rules, decided where `swift test` can reach them.
///
/// The project's `InstalledPresentation` / `ServicesPresentation` precedent: a
/// rule that lives in a view body is a rule nobody can assert. Section order,
/// the four counts, and — above all — *which sentence the surface is entitled to
/// say* are values here, so the app target owns symbols and layout and owns no
/// rule about what is true.
///
/// Split from `SecurityFindingPresentationTests`, which covers one finding's own
/// framing. This suite is about the whole inventory.
@Suite("Security presentation")
struct SecurityPresentationTests {
    private typealias Arranged = SecurityPresentationArrangement
    typealias Row = SecurityPresentationArrangement.CountRow

    // MARK: - 16.1 Section order

    @Test("Sections are ordered vulnerable, then not covered, then clean, then unavailable")
    func sectionsAreOrderedVulnerableThenNotCoveredThenCleanThenUnavailable() {
        let sections = SecurityPresentation.sections(of: Arranged.mixedEntries)

        #expect(
            sections.map(\.state) == [.vulnerable, .notCovered, .clean, .unavailable],
            "not-covered must sit directly under vulnerable, above clean"
        )
        #expect(sections.map(\.count) == [1, 1, 1, 1])
        #expect(
            sections.map(\.identifier) == [
                "security-coverage-vulnerable",
                "security-coverage-notCovered",
                "security-coverage-clean",
                "security-coverage-unavailable"
            ]
        )
    }

    /// The order is a property of the *state*, not of the order entries happened
    /// to arrive in. Feeding them backwards must not reorder the surface.
    @Test("Section order does not follow entry order")
    func sectionOrderDoesNotFollowEntryOrder() {
        let sections = SecurityPresentation.sections(of: Arranged.mixedEntries.reversed())

        #expect(sections.map(\.state) == [.vulnerable, .notCovered, .clean, .unavailable])
        #expect(sections.map(\.count) == [1, 1, 1, 1])
    }

    @Test("The not-covered section renders with its count even at zero findings")
    func theNotCoveredSectionRendersWithItsCountEvenAtZeroFindings() {
        // A scan with no vulnerable package at all — the realistic case on this
        // machine, where U1 measured ~3-5% curated coverage.
        let entries = [
            Arranged.entry("ripgrep", Arranged.clean()),
            Arranged.entry("curl", .notCovered(.unmapped)),
            Arranged.entry("coreutils", .notCovered(.unmapped)),
            Arranged.entry("zsh", .notCovered(.kindUnsupported))
        ]

        let sections = SecurityPresentation.sections(of: entries)
        let notCovered = sections.first { $0.state == .notCovered }

        #expect(notCovered?.count == 3)
        #expect(notCovered?.items.count == 3)
        #expect(
            sections.map(\.state) == [.vulnerable, .notCovered, .clean, .unavailable],
            "an empty vulnerable section must not delete the sections under it"
        )
        #expect(
            sections.first { $0.state == .vulnerable }?.count == 0,
            "a zero count is a fact worth rendering, not a section to hide"
        )
    }

    /// The one case where there are no sections at all: nothing has been scanned.
    @Test("An unscanned inventory produces no sections rather than four empty ones")
    func anUnscannedInventoryProducesNoSections() {
        #expect(SecurityPresentation.sections(of: []).isEmpty)
    }

    @Test("Each item carries its package, its queried version and its typed reason")
    func eachItemCarriesItsPackageVersionAndTypedReason() throws {
        let sections = SecurityPresentation.sections(of: Arranged.mixedEntries)

        let notCovered = try #require(sections.first { $0.state == .notCovered })
        let item = try #require(notCovered.items.first)
        #expect(item.packageID == PackageID(kind: .formula, name: "curl"))
        #expect(item.queriedVersion == "1.0.0")
        #expect(item.notCoveredReason == .unmapped)
        #expect(item.failure == nil)

        let unavailable = try #require(sections.first { $0.state == .unavailable })
        #expect(unavailable.items.first?.failure == .rateLimited)
        #expect(unavailable.items.first?.notCoveredReason == nil)

        let vulnerable = try #require(sections.first { $0.state == .vulnerable })
        #expect(vulnerable.items.first?.findings.map(\.advisoryID) == ["GHSA-A"])
        #expect(
            vulnerable.items.first?.freshness == .cached(fetchedAt: Arranged.stamp)
        )
    }

    /// `unrated` "sorts and renders distinctly from every scored tier" — it sorts
    /// into its own bucket at the end rather than being ranked as mild.
    @Test("Findings sort by severity with unrated in its own bucket last")
    func findingsSortBySeverityWithUnratedLast() throws {
        let entries = [
            Arranged.entry(
                "bat",
                .covered(
                    .findings([
                        Arranged.finding("GHSA-unrated", severity: .unrated),
                        Arranged.finding("GHSA-low", severity: .low),
                        Arranged.finding("GHSA-critical", severity: .critical),
                        Arranged.finding("GHSA-none", severity: .none),
                        Arranged.finding("GHSA-medium", severity: .medium)
                    ])
                )
            )
        ]

        let sections = SecurityPresentation.sections(of: entries)
        let item = try #require(sections.first { $0.state == .vulnerable }?.items.first)

        #expect(
            item.findings.map(\.advisoryID) == [
                "GHSA-critical", "GHSA-medium", "GHSA-low", "GHSA-none", "GHSA-unrated"
            ]
        )
    }

    /// Dismissal suppresses a row; it never changes a coverage state. A package
    /// whose every finding is dismissed is still counted vulnerable, because the
    /// user answered a *finding*, not a question about the package's health.
    @Test("A fully dismissed package stays vulnerable and its findings are separated")
    func aFullyDismissedPackageStaysVulnerable() throws {
        let entries = [
            Arranged.entry(
                "bat",
                .covered(
                    .findings([
                        Arranged.finding("GHSA-A", isDismissed: true),
                        Arranged.finding("GHSA-B", isDismissed: false)
                    ])
                )
            )
        ]

        let sections = SecurityPresentation.sections(of: entries)
        let item = try #require(sections.first { $0.state == .vulnerable }?.items.first)

        #expect(item.activeFindings.map(\.advisoryID) == ["GHSA-B"])
        #expect(item.dismissedFindings.map(\.advisoryID) == ["GHSA-A"])
        #expect(sections.first { $0.state == .vulnerable }?.count == 1)
    }

    // MARK: - 16.2 No sentence claims the inventory is clean while anything is unanswered

    /// Exhaustive over the four states: the claim "no vulnerabilities" is
    /// available to exactly one arrangement of counts, and that arrangement
    /// requires every package to have been answered.
    @Test(
        "No empty state or badge claims the inventory has no vulnerabilities when anything is not covered",
        arguments: [
            Row(vulnerable: 0, clean: 0, notCovered: 1, unavailable: 0),
            Row(vulnerable: 0, clean: 0, notCovered: 0, unavailable: 1),
            Row(vulnerable: 0, clean: 5, notCovered: 1, unavailable: 0),
            Row(vulnerable: 0, clean: 5, notCovered: 0, unavailable: 1),
            Row(vulnerable: 0, clean: 0, notCovered: 159, unavailable: 0),
            Row(vulnerable: 1, clean: 0, notCovered: 1, unavailable: 0),
            Row(vulnerable: 1, clean: 5, notCovered: 0, unavailable: 1),
            Row(vulnerable: 2, clean: 3, notCovered: 4, unavailable: 5)
        ]
    )
    func noSummaryClaimsNoVulnerabilitiesWhenAnythingIsNotCovered(row: Row) {
        let totals = Arranged.totals(row)
        let headline = SecurityPresentation.headline(for: totals)

        #expect(totals.hasUnansweredPackages, "arrangement error: this row must be unanswered somewhere")
        #expect(
            headline.claimsNoVulnerabilities == false,
            "\(headline) claims the inventory is clean while \(row.unanswered) packages went unanswered"
        )
        #expect(
            headline.message.localizedCaseInsensitiveContains("unanswered")
                || headline.message.localizedCaseInsensitiveContains("not covered"),
            "the unanswered packages must be named in the sentence, not only in a count elsewhere"
        )
    }

    /// The positive anchor. Without it the assertion above passes for a headline
    /// that can *never* say the inventory is clean, which proves nothing.
    @Test("A fully answered inventory with no findings is the one case entitled to say so")
    func aFullyAnsweredInventoryIsTheOneCaseEntitledToSaySo() {
        let totals = Arranged.totals(Row(vulnerable: 0, clean: 7, notCovered: 0, unavailable: 0))
        let headline = SecurityPresentation.headline(for: totals)

        #expect(headline == .fullyAnsweredNoVulnerabilities)
        #expect(headline.claimsNoVulnerabilities)
        #expect(headline.title.isEmpty == false)
    }

    @Test("An inventory nothing has been asked about reports that, not cleanliness")
    func anUnscannedInventoryReportsThatRatherThanCleanliness() {
        let headline = SecurityPresentation.headline(for: CoverageTotals(of: []))

        #expect(headline == .notScanned)
        #expect(headline.claimsNoVulnerabilities == false)
    }

    /// "Not-covered must be at least as prominent as vulnerable in every summary."
    /// A headline that names findings and silently drops the gap fails that.
    @Test("The vulnerable headline names the unanswered count alongside the findings")
    func theVulnerableHeadlineNamesTheUnansweredCountToo() {
        let totals = Arranged.totals(Row(vulnerable: 2, clean: 1, notCovered: 40, unavailable: 3))
        let headline = SecurityPresentation.headline(for: totals)

        #expect(headline == .vulnerable(count: 2, unanswered: 43))
        #expect(headline.message.contains("43"))
        #expect(headline.message.contains("2"))
    }

    @Test("Findings with no gaps report the findings alone")
    func findingsWithNoGapsReportTheFindingsAlone() {
        let totals = Arranged.totals(Row(vulnerable: 3, clean: 4, notCovered: 0, unavailable: 0))

        #expect(SecurityPresentation.headline(for: totals) == .vulnerable(count: 3, unanswered: 0))
    }

    @Test("No findings but gaps is its own sentence, distinct from clean")
    func noFindingsButGapsIsItsOwnSentence() {
        let totals = Arranged.totals(Row(vulnerable: 0, clean: 4, notCovered: 150, unavailable: 5))
        let headline = SecurityPresentation.headline(for: totals)

        #expect(headline == .noFindingsWithGaps(unanswered: 155))
        #expect(headline != .fullyAnsweredNoVulnerabilities)
        #expect(headline.message.contains("155"))
    }
}
