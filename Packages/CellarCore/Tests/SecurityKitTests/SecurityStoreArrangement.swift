import Catalog
import CellarTestSupport
import Foundation

@testable import SecurityKit

/// Everything the two `SecurityStore` suites arrange with.
///
/// Shared rather than duplicated because the guard suite and the cache suite
/// assert about the *same* store over the *same* results: two copies of these
/// values would let one suite drift into testing a store the other never sees.
/// An `enum` with no cases, so it carries no isolation of its own and the
/// engine's `@Sendable` query provider can read it.
enum SecurityStoreArrangement {
    static let epoch = Date(timeIntervalSince1970: 1_780_000_000)

    static let query = AdvisoryQuery(
        packageID: PackageID(kind: .formula, name: "bat"),
        installedVersion: "0.18.1",
        queryVersion: "0.18.1",
        ecosystem: "crates.io",
        ecosystemPackageName: "bat"
    )

    static func engine(
        source: RecordingAdvisorySource,
        clock: TestClock = TestClock(),
        cache: InMemoryAdvisoryCache = InMemoryAdvisoryCache(),
        consent: any ScanConsentProviding = FixedScanConsent(.granted(at: epoch))
    ) -> SecurityScanEngine {
        SecurityScanEngine(
            discovery: source,
            enrichment: source,
            cache: cache,
            consent: consent,
            queries: { [query] },
            clock: clock,
            timeSource: MutableTimeSource(epoch)
        )
    }

    /// A store whose engine will never settle on its own, so the only thing that
    /// changes its state is the adoption the test performs by hand.
    @MainActor
    static func heldOpenStore(
        clock: TestClock,
        source: RecordingAdvisorySource
    ) -> SecurityStore {
        SecurityStore(engine: engine(source: source, clock: clock))
    }

    static func finding(_ advisoryID: String) -> VulnerabilityFinding {
        VulnerabilityFinding(
            advisoryID: advisoryID,
            cveID: nil,
            aliases: [],
            summary: "A real advisory shape, minus the prose.",
            severity: .high,
            ecosystem: "crates.io",
            ecosystemPackageName: "bat",
            declaredFixVersion: "0.18.2",
            fix: .stillAffected,
            answeredBy: .osv,
            isDismissed: false
        )
    }

    static func entry(
        name: String,
        outcome: CVEScanOutcome,
        fetchedAt: Date = epoch
    ) -> AdvisoryCacheEntry {
        AdvisoryCacheEntry(
            key: AdvisoryCacheKey(
                sourceID: .osv,
                packageID: PackageID(kind: .formula, name: name),
                version: "0.18.1"
            ),
            outcome: outcome,
            fetchedAt: fetchedAt,
            advisoryModified: nil,
            mappingRevision: EcosystemMapping.revision,
            matcherVersion: CVEMatcher.version
        )
    }

    static let vulnerableEntry = entry(
        name: "bat",
        outcome: .covered(.findings([finding("GHSA-p24j-h477-76q3")]))
    )

    static let cleanEntry = entry(
        name: "eza",
        outcome: .covered(.clean(CleanCoverage(answeredBy: .osv, queriedVersion: "0.18.1")))
    )

    static func provenance(enrichmentSucceeded: Bool = true) -> ScanProvenance {
        ScanProvenance(
            scannedAt: epoch,
            matcherVersion: CVEMatcher.version,
            mappingRevision: EcosystemMapping.revision,
            skippedRecordCounts: [.osv: 0, .nvd: 0],
            enrichmentAttempted: true,
            enrichmentSucceeded: enrichmentSucceeded
        )
    }

    static func result(
        ordinal: Int,
        entries: [AdvisoryCacheEntry],
        isPartial: Bool = false
    ) -> SecurityScanResult {
        SecurityScanResult(
            revision: SecurityScanRevision(ordinal: ordinal),
            entries: entries,
            provenance: provenance(enrichmentSucceeded: !isPartial),
            isPartial: isPartial
        )
    }

    /// Bounded polling that stays on the main actor, so the condition can read
    /// main-isolated state.
    @MainActor
    static func poll(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
