import Catalog
import Foundation

@testable import SecurityKit

/// Shared arrangement for the two presentation suites.
///
/// One factory rather than two, so the section projection and the finding
/// projection cannot drift into testing differently-shaped inputs — the
/// `SecurityStoreArrangement` discipline.
enum SecurityPresentationArrangement {
    static let stamp = Date(timeIntervalSince1970: 1_770_000_000)

    static func entry(
        _ name: String,
        _ outcome: CVEScanOutcome,
        version: String = "1.0.0",
        fetchedAt: Date = SecurityPresentationArrangement.stamp
    ) -> AdvisoryCacheEntry {
        AdvisoryCacheEntry(
            key: AdvisoryCacheKey(
                sourceID: .osv,
                packageID: PackageID(kind: .formula, name: name),
                version: version
            ),
            outcome: outcome,
            fetchedAt: fetchedAt,
            advisoryModified: nil,
            mappingRevision: EcosystemMapping.revision,
            matcherVersion: CVEMatcher.version
        )
    }

    static func clean(_ version: String = "1.0.0") -> CVEScanOutcome {
        .covered(.clean(CleanCoverage(answeredBy: .osv, queriedVersion: version)))
    }

    static func finding(
        _ id: String,
        severity: SeverityTier = .high,
        isDismissed: Bool = false,
        cveID: String? = "CVE-2026-0001",
        declaredFixVersion: String? = "1.2.0"
    ) -> VulnerabilityFinding {
        VulnerabilityFinding(
            advisoryID: id,
            cveID: cveID,
            aliases: [],
            summary: "A summary.",
            severity: severity,
            ecosystem: "crates.io",
            ecosystemPackageName: "bat",
            declaredFixVersion: declaredFixVersion,
            fix: .stillAffected,
            answeredBy: .osv,
            isDismissed: isDismissed
        )
    }

    /// One of each state, so every ordering assertion runs against a scan that
    /// actually reached all four.
    static var mixedEntries: [AdvisoryCacheEntry] {
        [
            entry("bat", .covered(.findings([finding("GHSA-A")]))),
            entry("ripgrep", clean()),
            entry("curl", .notCovered(.unmapped)),
            entry("firefox", .unavailable(.rateLimited))
        ]
    }

    /// One arrangement of the four counts.
    ///
    /// A named type rather than a four-member tuple: the parameterized honesty
    /// test reads its rows by name, and a tuple of four `Int`s is exactly the
    /// shape in which two of them get silently transposed.
    struct CountRow: Sendable {
        let vulnerable: Int
        let clean: Int
        let notCovered: Int
        let unavailable: Int

        init(vulnerable: Int, clean: Int, notCovered: Int, unavailable: Int) {
            self.vulnerable = vulnerable
            self.clean = clean
            self.notCovered = notCovered
            self.unavailable = unavailable
        }

        var unanswered: Int { notCovered + unavailable }
    }

    static func outcomes(_ row: CountRow) -> [CVEScanOutcome] {
        var outcomes: [CVEScanOutcome] = []
        outcomes.append(contentsOf: (0..<row.vulnerable).map { .covered(.findings([finding("GHSA-\($0)")])) })
        outcomes.append(contentsOf: (0..<row.clean).map { _ in clean() })
        outcomes.append(contentsOf: (0..<row.notCovered).map { _ in .notCovered(.unmapped) })
        outcomes.append(contentsOf: (0..<row.unavailable).map { _ in .unavailable(.offline) })
        return outcomes
    }

    static func totals(_ row: CountRow) -> CoverageTotals { CoverageTotals(of: outcomes(row)) }
}
