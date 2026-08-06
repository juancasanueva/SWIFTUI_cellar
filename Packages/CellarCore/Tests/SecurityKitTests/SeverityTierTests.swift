import Foundation
import Testing

@testable import SecurityKit

/// Severity is *read*, never *inferred*.
///
/// The spec's rule has one sharp edge: when nobody published a score, the answer
/// is `unrated` — a sixth tier that renders and sorts on its own — and not
/// `medium`, not `none`, and not "probably fine". Every test here exists to make
/// the absence of that default an asserted fact.
@Suite("Severity tiering")
struct SeverityTierTests {
    // MARK: - Preference

    /// The preference order, over the real capture.
    ///
    /// Two of these rows are load-bearing rather than decorative, because the
    /// preferred metric and the runner-up **disagree about the tier**:
    ///
    /// - `CVE-2020-25575` — v3.1 9.8 (critical) beside v2 7.5 (high)
    /// - `CVE-2021-36753` — v3.1 7.8 (high) beside v2 4.6 (medium)
    ///
    /// A decoder that picked the last metric it saw, or the first, would pass a
    /// tier-only assertion on the other rows and fail on these two. The selected
    /// score is asserted as well as the tier, because `CVE-2026-0994`'s v4.0 8.2
    /// and v3.1 7.5 both land in `high` — there the tier alone proves nothing.
    @Test(
        "The tier prefers CVSS v4.0, then v3.1, then v3.0, then v2",
        arguments: [
            ("CVE-2026-0994", CVSSVersion.v40, 8.2, SeverityTier.high),
            ("CVE-2020-25575", .v31, 9.8, .critical),
            ("CVE-2019-25010", .v31, 9.8, .critical),
            ("CVE-2021-3013", .v31, 9.8, .critical),
            ("CVE-2021-36753", .v31, 7.8, .high),
            ("CVE-2022-32213", .v31, 6.5, .medium),
            ("CVE-2022-1941", .v31, 7.5, .high)
        ]
    )
    func theTierPrefersCVSSv4ThenV31ThenV30ThenV2(
        cveID: String,
        version: CVSSVersion,
        baseScore: Double,
        tier: SeverityTier
    ) throws {
        let response = try NVDWire.enrichment(from: Fixture.data("NVD/cveids-response.json"))
        let record = try #require(response.records.first { $0.cveID == cveID })

        let selected = try #require(SeverityTier.preferredScore(among: record.scores))
        #expect(selected.version == version)
        #expect(selected.baseScore == baseScore)
        #expect(SeverityTier.tiered(from: record.scores, advertised: nil) == tier)
    }

    /// CVSS v3.0 has no record in the captured corpus — NVD had already
    /// re-scored every one of these CVEs under v3.1 — so its position in the
    /// preference order is asserted directly on the ordering function. Stated
    /// here rather than left untested, because a missing rung is exactly the
    /// kind of gap that stays invisible until the day a v3.0-only advisory
    /// arrives.
    @Test("The full preference order holds, including the rung the corpus has no capture for")
    func theFullPreferenceOrderHoldsIncludingVersionThreeZero() throws {
        let all = [
            CVSSScore(version: .v2, baseScore: 1.0, vectorString: "v2", publishedSeverity: nil),
            CVSSScore(version: .v30, baseScore: 2.0, vectorString: "v30", publishedSeverity: nil),
            CVSSScore(version: .v31, baseScore: 3.0, vectorString: "v31", publishedSeverity: nil),
            CVSSScore(version: .v40, baseScore: 4.0, vectorString: "v40", publishedSeverity: nil)
        ]

        // Peeling the preferred metric off the front, one rung at a time.
        var remaining = all
        var order: [CVSSVersion] = []
        while let preferred = SeverityTier.preferredScore(among: remaining) {
            order.append(preferred.version)
            remaining.removeAll { $0.version == preferred.version }
        }

        #expect(order == [.v40, .v31, .v30, .v2])
        #expect(SeverityTier.preferredScore(among: []) == nil)
    }

    // MARK: - Bands

    /// The band boundaries, including the ones nobody writes a test for until a
    /// 6.9 renders as high. `none` exists in v3 and above and does not exist in
    /// v2, where 0.0 is the bottom of `low`.
    @Test(
        "Scores tier by their own version's bands",
        arguments: [
            (CVSSVersion.v31, 0.0, SeverityTier.none),
            (.v31, 0.1, .low),
            (.v31, 3.9, .low),
            (.v31, 4.0, .medium),
            (.v31, 6.9, .medium),
            (.v31, 7.0, .high),
            (.v31, 8.9, .high),
            (.v31, 9.0, .critical),
            (.v31, 10.0, .critical),
            (.v40, 9.0, .critical),
            (.v30, 4.0, .medium),
            // CVSS v2 has no `critical` and no `none`: 10.0 is high and 0.0 is
            // low. Tiering a v2 score with v3 bands would invent a critical
            // that its own specification does not define.
            (.v2, 0.0, .low),
            (.v2, 3.9, .low),
            (.v2, 4.0, .medium),
            (.v2, 6.9, .medium),
            (.v2, 7.0, .high),
            (.v2, 10.0, .high)
        ]
    )
    func scoresTierByTheirOwnVersionsBands(
        version: CVSSVersion,
        baseScore: Double,
        tier: SeverityTier
    ) {
        let score = CVSSScore(
            version: version,
            baseScore: baseScore,
            vectorString: "",
            publishedSeverity: nil
        )

        #expect(SeverityTier.tiered(from: [score], advertised: nil) == tier)
    }

    // MARK: - Advertised severity

    /// The fallback the spec allows: a database that publishes a word but no
    /// number. `vulns-GHSA-4gg8-gxpx-9rph.json` is the real record — no
    /// `severity` array at all, `database_specific.severity: "MODERATE"`.
    @Test("An advertised severity is used when no score exists")
    func anAdvertisedSeverityIsUsedWhenNoScoreExists() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-GHSA-4gg8-gxpx-9rph.json")
        )

        #expect(advisory.severityVectors.isEmpty, "the fixture is meant to carry no score")
        #expect(advisory.advertisedSeverity == "MODERATE")
        #expect(
            SeverityTier.tiered(from: [], advertised: advisory.advertisedSeverity) == .medium
        )
    }

    /// The vocabularies the two databases actually use, plus the one that must
    /// not be guessed at.
    @Test(
        "Advertised words map to tiers, and an unknown word does not",
        arguments: [
            ("CRITICAL", SeverityTier.critical),
            ("critical", .critical),
            ("HIGH", .high),
            ("MODERATE", .medium),
            ("MEDIUM", .medium),
            ("LOW", .low),
            ("NONE", SeverityTier.none),
            ("IMPORTANT", .unrated),
            ("", .unrated)
        ]
    )
    func advertisedWordsMapToTiers(word: String, tier: SeverityTier) {
        #expect(SeverityTier.tiered(from: [], advertised: word) == tier)
    }

    /// A published score outranks a published word. They disagree here on
    /// purpose: 9.8 is critical and the word says low, and the number wins,
    /// because the spec's preference order puts the advertised severity *after*
    /// every score.
    @Test("A score outranks an advertised word")
    func aScoreOutranksAnAdvertisedWord() {
        let score = CVSSScore(
            version: .v31,
            baseScore: 9.8,
            vectorString: "",
            publishedSeverity: "CRITICAL"
        )

        #expect(SeverityTier.tiered(from: [score], advertised: "LOW") == .critical)
    }

    // MARK: - Unrated

    /// The rule the whole type exists for.
    @Test("An unscored advisory stays unrated and sorts in its own bucket")
    func anUnscoredAdvisoryStaysUnratedAndSortsInItsOwnBucket() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-RUSTSEC-2021-0139.json")
        )

        // The real record: no `severity` array, and a `database_specific` that
        // carries only a licence — present, but not a severity.
        #expect(advisory.severityVectors.isEmpty)
        #expect(advisory.advertisedSeverity == nil)

        let tier = SeverityTier.tiered(from: [], advertised: advisory.advertisedSeverity)
        #expect(tier == .unrated)
        #expect(tier != .medium, "an unscored advisory must never default to medium")
        #expect(tier != SeverityTier.none, "unrated is not the same claim as a 0.0 score")
        #expect(tier.isScored == false)

        // Its own bucket: no scored tier shares its position, and sorting a
        // mixed list leaves it alone at the end rather than interleaved.
        let scored = SeverityTier.allCases.filter(\.isScored)
        #expect(scored.count == 5)
        #expect(scored.contains { $0.displayOrder == tier.displayOrder } == false)

        let mixed: [SeverityTier] = [.unrated, .low, .critical, SeverityTier.none, .high]
        #expect(
            mixed.sorted { $0.displayOrder < $1.displayOrder }
                == [.critical, .high, .low, SeverityTier.none, .unrated]
        )
    }

    /// Triangulation for the one above: a second unscored record, and the
    /// *positive* half — an advisory that does carry a score must not come back
    /// unrated, or "everything is unrated" would pass every assertion here.
    @Test("The unrated verdict is about the payload, not about the function")
    func theUnratedVerdictIsAboutThePayload() throws {
        let unscored = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-RUSTSEC-2020-0163.json")
        )
        #expect(
            SeverityTier.tiered(from: [], advertised: unscored.advertisedSeverity) == .unrated
        )

        let response = try NVDWire.enrichment(from: Fixture.data("NVD/cveids-response.json"))
        let scored = try #require(response.records.first { $0.cveID == "CVE-2026-0994" })
        #expect(SeverityTier.tiered(from: scored.scores, advertised: nil) != .unrated)
    }
}
