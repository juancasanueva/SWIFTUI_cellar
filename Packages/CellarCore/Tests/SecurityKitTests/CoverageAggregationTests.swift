import Catalog
import Foundation
import Testing

@testable import SecurityKit

/// Aggregation is where honesty is usually lost.
///
/// Every individual outcome can be perfectly typed and the summary can still say
/// "0 vulnerabilities" over an inventory nobody could answer for. Four states go
/// in; four counts must come out; and the clean count must contain only packages
/// that were actually asked about and actually came back empty.
@Suite("Coverage aggregation")
struct CoverageAggregationTests {
    private static func clean(_ version: String) -> CVEScanOutcome {
        .covered(.clean(CleanCoverage(answeredBy: .osv, queriedVersion: version)))
    }

    private static func finding(_ id: String) -> VulnerabilityFinding {
        VulnerabilityFinding(
            advisoryID: id,
            cveID: nil,
            aliases: [],
            summary: "",
            severity: .unrated,
            ecosystem: "crates.io",
            ecosystemPackageName: "bat",
            declaredFixVersion: nil,
            fix: .fixUnknown,
            answeredBy: .osv,
            isDismissed: false
        )
    }

    // MARK: - The four counts

    @Test("Four distinct counts survive aggregation")
    func fourDistinctCountsSurviveAggregation() {
        let mixed: [CVEScanOutcome] = [
            .covered(.findings([Self.finding("A")])),
            .covered(.findings([Self.finding("B"), Self.finding("C")])),
            Self.clean("1.0.0"),
            Self.clean("2.0.0"),
            Self.clean("3.0.0"),
            .notCovered(.unmapped),
            .notCovered(.kindUnsupported),
            .notCovered(.unsupportedVersionScheme),
            .notCovered(.unmapped),
            .unavailable(.rateLimited)
        ]

        let totals = CoverageTotals(of: mixed)

        #expect(totals.vulnerable == 2)
        #expect(totals.clean == 3)
        #expect(totals.notCovered == 4)
        #expect(totals.unavailable == 1)
        #expect(totals.total == 10, "a package fell out of the summary entirely")
    }

    /// The rule the spec states twice, because it is the one that matters.
    @Test("The clean count includes only covered-clean")
    func theCleanCountIncludesOnlyCoveredClean() {
        let unanswerable: [CVEScanOutcome] = [
            .notCovered(.unmapped),
            .notCovered(.kindUnsupported),
            .notCovered(.unsupportedVersionScheme),
            .unavailable(.offline),
            .unavailable(.rateLimited),
            .unavailable(.transportFailed),
            .unavailable(.malformedRecord)
        ]

        let totals = CoverageTotals(of: unanswerable)

        // Set up so that a clean result would be *wrong*: nothing here was
        // answered, so nothing here may be counted clean.
        #expect(totals.clean == 0)
        #expect(totals.vulnerable == 0)
        #expect(totals.notCovered == 3)
        #expect(totals.unavailable == 4)
        #expect(totals.total == 7)
    }

    /// The realistic inventory, which U1 says is the common case: nothing is in
    /// the table, so nothing is covered. A summary that reads "no
    /// vulnerabilities" here would be the single worst thing this feature could
    /// do, and `hasUnansweredPackages` is what a badge or empty state must
    /// consult before claiming anything.
    @Test("An all-unmapped inventory is not clean and knows it is not")
    func anAllUnmappedInventoryIsNotClean() {
        let inventory = Array(repeating: CVEScanOutcome.notCovered(.unmapped), count: 159)

        let totals = CoverageTotals(of: inventory)

        #expect(totals.notCovered == 159)
        #expect(totals.clean == 0)
        #expect(totals.vulnerable == 0)
        #expect(totals.hasUnansweredPackages)
        #expect(totals.isEntirelyAnswered == false)
    }

    /// Triangulation: an inventory that *is* entirely answered and entirely
    /// clean must say so, or the two flags above would just be "always
    /// pessimistic".
    @Test("A fully answered clean inventory is allowed to say so")
    func aFullyAnsweredCleanInventorySaysSo() {
        let totals = CoverageTotals(of: [Self.clean("1.0.0"), Self.clean("2.0.0")])

        #expect(totals.clean == 2)
        #expect(totals.hasUnansweredPackages == false)
        #expect(totals.isEntirelyAnswered)
    }

    @Test("An empty inventory claims nothing")
    func anEmptyInventoryClaimsNothing() {
        let totals = CoverageTotals(of: [])

        #expect(totals.total == 0)
        #expect(totals.clean == 0)
        // Nothing was asked, so nothing is unanswered -- but nothing is clean
        // either, and the summary has no inventory to describe.
        #expect(totals.hasUnansweredPackages == false)
    }

    // MARK: - Dismissal

    /// Task 6.7's rule, and the reason dismissal cannot be implemented by
    /// deleting findings.
    ///
    /// A dismissal answers **one** finding at **one** installed version. It must
    /// not touch the package's other findings, and it must not change the
    /// coverage state — which means a package whose every finding is dismissed
    /// stays `covered(findings:)` and never becomes `covered(clean:)`. Removing
    /// findings from the array would make that impossible to guarantee, so the
    /// finding stays and carries `isDismissed`.
    @Test("A dismissal suppresses exactly one finding and changes no coverage state")
    func aDismissalSuppressesExactlyOneFindingAndChangesNoCoverageState() throws {
        let advisories = try [
            "OSV/vulns-PYSEC-2026-899.json",
            "OSV/vulns-PYSEC-2026-1805.json"
        ].map { try OSVWire.advisory(from: Fixture.data($0)) }
        let query = AdvisoryQuery(
            packageID: PackageID(kind: .formula, name: "protobuf"),
            installedVersion: "3.20.1",
            queryVersion: "3.20.1",
            ecosystem: "PyPI",
            ecosystemPackageName: "protobuf"
        )
        let dismissed = "PYSEC-2026-899"

        let undismissed = CVEMatcher().match(query: query, answer: .answered(advisories))
        guard case .covered(.findings(let before)) = undismissed else {
            Issue.record("the control produced no findings")
            return
        }
        #expect(before.count == 2)
        #expect(before.allSatisfy { $0.isDismissed == false })

        let outcome = CVEMatcher().match(
            query: query,
            answer: .answered(advisories),
            isDismissed: { key in key.advisoryID == dismissed }
        )

        guard case .covered(.findings(let after)) = outcome else {
            Issue.record("a dismissal changed the coverage state")
            return
        }
        // Same coverage state, same findings, one of them answered.
        #expect(after.count == 2)
        #expect(after.filter(\.isDismissed).map(\.advisoryID) == [dismissed])
        #expect(after.filter { $0.isDismissed == false }.count == 1)
        #expect(after.map(\.advisoryID).sorted() == before.map(\.advisoryID).sorted())
        #expect(CoverageTotals(of: [outcome]).vulnerable == 1)
        #expect(CoverageTotals(of: [outcome]).clean == 0)
    }

    /// The version scoping. A dismissal is keyed by the exact installed version,
    /// so an upgrade re-surfaces the finding with no user action — the key
    /// simply stops matching.
    @Test("A dismissal is keyed by the exact installed version")
    func aDismissalIsKeyedByTheExactInstalledVersion() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-PYSEC-2026-899.json")
        )
        let dismissalAtOldVersion: DismissalLookup = { key in
            key.advisoryID == "PYSEC-2026-899" && key.installedVersion == "3.20.1"
        }

        func findings(installed: String) throws -> [VulnerabilityFinding] {
            let query = AdvisoryQuery(
                packageID: PackageID(kind: .formula, name: "protobuf"),
                installedVersion: installed,
                queryVersion: installed,
                ecosystem: "PyPI",
                ecosystemPackageName: "protobuf"
            )
            let outcome = CVEMatcher().match(
                query: query,
                answer: .answered([advisory]),
                isDismissed: dismissalAtOldVersion
            )
            guard case .covered(.findings(let findings)) = outcome else { return [] }
            return findings
        }

        #expect(try findings(installed: "3.20.1").first?.isDismissed == true)
        // Upgraded. Nothing was deleted and the user did nothing; the key just
        // no longer matches.
        #expect(try findings(installed: "3.20.2").first?.isDismissed == false)
    }

    /// The key carries the package identity too, so two formulae that share an
    /// advisory are answered independently.
    @Test("A dismissal does not suppress the same advisory for another package")
    func aDismissalIsScopedToItsPackage() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-PYSEC-2026-899.json")
        )
        let scoped: DismissalLookup = { key in
            key.packageID == PackageID(kind: .formula, name: "protobuf")
        }

        let otherPackage = AdvisoryQuery(
            packageID: PackageID(kind: .formula, name: "protobuf-c"),
            installedVersion: "3.20.1",
            queryVersion: "3.20.1",
            ecosystem: "PyPI",
            ecosystemPackageName: "protobuf"
        )
        let outcome = CVEMatcher().match(
            query: otherPackage,
            answer: .answered([advisory]),
            isDismissed: scoped
        )

        guard case .covered(.findings(let findings)) = outcome else {
            Issue.record("the other package produced no finding")
            return
        }
        #expect(findings[0].isDismissed == false)
    }
}
