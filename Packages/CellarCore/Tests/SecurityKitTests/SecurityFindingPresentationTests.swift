import Foundation
import Testing

@testable import SecurityKit

/// How one finding introduces itself, offers an upgrade, and links its records.
///
/// Split from `SecurityPresentationTests`, which is about the whole inventory.
/// The split is the point rather than housekeeping: these are per-finding claims
/// and they grow with the detail pane, while the section projection does not.
@Suite("Security finding presentation")
struct SecurityFindingPresentationTests {
    private typealias Arranged = SecurityPresentationArrangement

    // MARK: - Row identity

    /// The design writes `security-finding-{cveID}`. Most advisories this app
    /// receives publish **no** CVE alias — `GHSA-`, `RUSTSEC-` and `PYSEC-`
    /// routinely do not — so a literal reading collapses every unaliased finding
    /// onto `security-finding-`, the same identifier for all of them. Batch 4's
    /// Deviation 39 made `advisoryID` the identity for dismissal for exactly this
    /// reason; the row identifier follows it.
    @Test("A finding identifier falls back to the advisory ID when there is no CVE")
    func theFindingIdentifierFallsBackToTheAdvisoryID() {
        let aliased = Arranged.finding("GHSA-4gg8-gxpx-9rph", cveID: "CVE-2026-0994")
        let unaliased = Arranged.finding("RUSTSEC-2021-0139", cveID: nil)

        #expect(SecurityPresentation.findingIdentifier(aliased) == "security-finding-CVE-2026-0994")
        #expect(SecurityPresentation.dismissIdentifier(aliased) == "security-dismiss-CVE-2026-0994")
        #expect(
            SecurityPresentation.findingIdentifier(unaliased) == "security-finding-RUSTSEC-2021-0139"
        )
        #expect(
            SecurityPresentation.dismissIdentifier(unaliased) == "security-dismiss-RUSTSEC-2021-0139"
        )
    }

    /// Two different unaliased advisories must not share one identifier.
    @Test("Two CVE-less advisories get two distinct identifiers")
    func twoCVELessAdvisoriesGetTwoDistinctIdentifiers() {
        let first = Arranged.finding("GHSA-7gcm-g887-7qv7", cveID: nil)
        let second = Arranged.finding("PYSEC-2026-899", cveID: nil)

        #expect(
            SecurityPresentation.findingIdentifier(first)
                != SecurityPresentation.findingIdentifier(second)
        )
    }

    // MARK: - Framing

    /// A finding is a statement about an **ecosystem package**, not about the
    /// Homebrew formula. `protobuf` the Homebrew formula and `protobuf` on PyPI
    /// are different things that share a name, and a detail pane that said
    /// "protobuf is vulnerable" would be asserting something OSV never said.
    @Test("Every finding is framed as reported for its ecosystem package")
    func everyFindingIsFramedAsReportedForItsEcosystemPackage() {
        let finding = Arranged.finding("GHSA-A")

        #expect(
            SecurityPresentation.reportedFor(finding, queriedVersion: "0.24.0")
                == "Reported for crates.io/bat 0.24.0"
        )
    }

    // MARK: - The upgrade offer

    /// The spec's own scenario: fixed upstream in `2.5.0` while Homebrew offers
    /// `2.6.1`. The offer must target Homebrew's version *and* say so.
    @Test("The upgrade offer names Homebrew's version and states the difference")
    func theUpgradeOfferNamesHomebrewsVersion() {
        let offer = SecurityPresentation.upgradeOffer(
            for: Arranged.finding("GHSA-A", declaredFixVersion: "2.5.0"),
            catalogVersion: "2.6.1"
        )

        #expect(offer == .differs(homebrew: "2.6.1", advisory: "2.5.0"))
        #expect(offer.actionTitle == "Upgrade to 2.6.1")
        #expect(offer.note?.contains("2.6.1") == true)
        #expect(offer.note?.contains("2.5.0") == true)
    }

    @Test("A matching Homebrew version needs no difference note")
    func aMatchingHomebrewVersionNeedsNoDifferenceNote() {
        let offer = SecurityPresentation.upgradeOffer(
            for: Arranged.finding("GHSA-A", declaredFixVersion: "2.5.0"),
            catalogVersion: "2.5.0"
        )

        #expect(offer == .matches(version: "2.5.0"))
        #expect(offer.actionTitle == "Upgrade to 2.5.0")
        #expect(offer.note == nil)
    }

    /// Homebrew behind the advisory's fix is the case a naive offer gets wrong:
    /// the button still upgrades, and the note must not imply the upgrade fixes
    /// the advisory when Homebrew does not yet carry the fix.
    @Test("Homebrew behind the advisory fix is stated rather than implied to be a fix")
    func homebrewBehindTheAdvisoryFixIsStated() {
        let offer = SecurityPresentation.upgradeOffer(
            for: Arranged.finding("GHSA-A", declaredFixVersion: "2.5.0"),
            catalogVersion: "2.4.0"
        )

        #expect(offer == .differs(homebrew: "2.4.0", advisory: "2.5.0"))
        #expect(offer.note?.contains("2.4.0") == true)
        #expect(offer.note?.contains("2.5.0") == true)
    }

    @Test("With no catalog version there is no upgrade offer at all")
    func withNoCatalogVersionThereIsNoUpgradeOffer() {
        let offer = SecurityPresentation.upgradeOffer(
            for: Arranged.finding("GHSA-A", declaredFixVersion: "2.5.0"),
            catalogVersion: nil
        )

        #expect(offer == .unavailable)
        #expect(offer.actionTitle == nil)
    }

    // MARK: - The fix sentence

    /// The spec's `1.2.3_1` / `1.2.4` scenario, as a sentence. It must state that
    /// a fix is published and that comparison is not possible, and must assert no
    /// ordering verdict in either direction.
    @Test("A non-comparable pair states the gap and asserts no ordering")
    func aNonComparablePairStatesTheGapAndAssertsNoOrdering() {
        let sentence = SecurityPresentation.fixDescription(
            .notComparable(scheme: .homebrewRevision),
            declaredFixVersion: "1.2.4"
        )

        #expect(sentence.localizedCaseInsensitiveContains("fix published"))
        #expect(sentence.localizedCaseInsensitiveContains("comparison not possible"))
        #expect(sentence.localizedCaseInsensitiveContains("1.2.4"))
        for verdict in ["still affected", "no longer affected", "not affected", "already fixed"] {
            #expect(
                sentence.localizedCaseInsensitiveContains(verdict) == false,
                "the sentence asserted an ordering verdict: \(verdict)"
            )
        }
    }

    @Test(
        "Every fix verdict has its own distinct sentence",
        arguments: [
            FixVersionComparison.fixedAtOrBefore,
            .stillAffected,
            .noFixPublished,
            .fixUnknown,
            .notComparable(scheme: .homebrewRevision),
            .notComparable(scheme: .other)
        ]
    )
    func everyFixVerdictHasItsOwnSentence(verdict: FixVersionComparison) {
        let sentence = SecurityPresentation.fixDescription(verdict, declaredFixVersion: "1.2.4")

        #expect(sentence.isEmpty == false)
        let others: [FixVersionComparison] = [
            .fixedAtOrBefore, .stillAffected, .noFixPublished, .fixUnknown
        ]
        for other in others where other != verdict {
            #expect(
                sentence != SecurityPresentation.fixDescription(other, declaredFixVersion: "1.2.4"),
                "\(verdict) reads identically to \(other)"
            )
        }
    }

    // MARK: - Record locations

    /// Built from constant hosts and the advisory's own identifiers — never from
    /// a name this app guessed.
    @Test("A finding locates its OSV record, and its NVD record only when it has a CVE")
    func aFindingLocatesItsOSVRecordAndItsNVDRecordOnlyWithACVE() {
        let aliased = Arranged.finding("GHSA-4gg8-gxpx-9rph")

        #expect(
            SecurityPresentation.advisoryRecordLocation(aliased)
                == "osv.dev/vulnerability/GHSA-4gg8-gxpx-9rph"
        )
        #expect(
            SecurityPresentation.cveRecordLocation(aliased)
                == "nvd.nist.gov/vuln/detail/CVE-2026-0001"
        )
        #expect(
            SecurityPresentation.cveRecordLocation(Arranged.finding("GHSA-A", cveID: nil)) == nil
        )
    }

    /// The locations carry **no scheme**, which is what keeps the target's exact
    /// two-host egress guard an equality rather than an allow-list. A string that
    /// is not a URL cannot become a request by accident.
    @Test("Record locations carry no scheme")
    func recordLocationsCarryNoScheme() throws {
        let finding = Arranged.finding("GHSA-A")
        let locations = [
            try #require(SecurityPresentation.advisoryRecordLocation(finding)),
            try #require(SecurityPresentation.cveRecordLocation(finding)),
            SecurityPresentation.osvRecordHost,
            SecurityPresentation.nvdRecordHost
        ]

        for location in locations {
            #expect(location.contains("://") == false, "\(location) is a URL, not a location")
        }
    }
}
