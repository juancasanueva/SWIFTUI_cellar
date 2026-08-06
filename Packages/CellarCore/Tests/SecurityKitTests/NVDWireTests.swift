import Foundation
import Testing

@testable import SecurityKit

/// Enrichment's payload, decoded under the same envelope/record rule as OSV —
/// with one deliberate difference.
///
/// NVD's `vulnerabilities` array is **not positional**: every record names its
/// own CVE, so a record that cannot be read costs exactly itself and the
/// survivors keep their identities. OSV's `results` array carries no such name,
/// which is why `OSVWire` keeps a bad slot and this decoder drops one. The two
/// rules look inconsistent side by side; they are the same rule applied to two
/// different payloads.
@Suite("NVD wire decode")
struct NVDWireTests {
    // MARK: - The positive anchor

    @Test("The captured enrichment response decodes every record")
    func theRealCaptureDecodesCompletely() throws {
        let response = try NVDWire.enrichment(from: Fixture.data("NVD/cveids-response.json"))

        #expect(response.totalResults == 7)
        #expect(response.records.count == 7)
        #expect(response.skippedRecordCount == 0)
        #expect(response.records.map(\.cveID).contains("CVE-2026-0994"))
    }

    // MARK: - The envelope

    /// The rate limit is the real reason this matters. The captured `429` body is
    /// 17 bytes of `text/plain`, so a client that decodes before it classifies
    /// the status reports a JSON failure for what is actually a rate limit — and
    /// then has to guess which one it was.
    @Test("A body that is not JSON fails the whole request")
    func aNonJsonEnvelopeFailsTheRequest() throws {
        let rateLimitBody = try Fixture.data("NVD/ratelimited-response.body")

        #expect(throws: AdvisoryError.malformedPayload) {
            try NVDWire.enrichment(from: rateLimitBody)
        }
    }

    // MARK: - The record

    @Test("A malformed record is dropped and counted while its neighbours survive")
    func aMalformedRecordIsSkippedAndCounted() throws {
        let response = try NVDWire.enrichment(
            from: Fixture.data("NVD/cveids-badrecord-response.json")
        )

        // Seven records in; the fourth lost its `id`.
        #expect(response.records.count == 6)
        #expect(response.skippedRecordCount == 1)
        #expect(response.records.map(\.cveID) == [
            "CVE-2020-25575", "CVE-2019-25010", "CVE-2021-3013",
            "CVE-2022-32213", "CVE-2022-1941", "CVE-2026-0994"
        ])
        // `totalResults` is the server's count and is untouched by a local decode
        // failure — the gap between it and `records.count` is the evidence.
        #expect(response.totalResults == 7)
    }

    // MARK: - Metric shapes

    /// The live decode hazard the U2 gate found (task 2.2).
    ///
    /// `ssvcV203` sits inside `metrics` beside genuine CVSS entries and carries
    /// **no `cvssData` member at all**. A decoder that iterates `metrics` and
    /// assumes every entry is a score either crashes or, worse, treats the
    /// scored record as unscored and reports a real 7.5 as `unrated`.
    @Test("A non-CVSS metric entry is ignored rather than tiered")
    func aNonCvssMetricEntryIsIgnoredRatherThanTiered() throws {
        let response = try NVDWire.enrichment(from: Fixture.data("NVD/cveids-response.json"))
        let record = try #require(response.records.first { $0.cveID == "CVE-2022-1941" })

        // The record's `metrics` object holds three entries, two of which are
        // CVSS v3.1 and one of which is `ssvcV203`.
        #expect(record.scores.count == 2)
        #expect(record.scores.allSatisfy { $0.version == .v31 })
        #expect(record.scores.allSatisfy { $0.baseScore == 7.5 })

        // The consequence, stated as the thing that would actually go wrong.
        #expect(SeverityTier.tiered(from: record.scores, advertised: nil) == .high)
        #expect(SeverityTier.tiered(from: record.scores, advertised: nil) != .unrated)
    }

    /// The other real route to `unrated`, also from the U2 gate: `metrics` is an
    /// empty object on a CVE that NVD has received but not yet analysed.
    @Test("A record with no CVSS metric at all stays unrated")
    func aRecordWithNoCvssMetricStaysUnrated() throws {
        let response = try NVDWire.enrichment(
            from: Fixture.data("NVD/cveids-unrated-response.json")
        )

        #expect(response.records.count == 2)
        #expect(response.skippedRecordCount == 0, "an empty `metrics` is a shape, not a failure")

        for record in response.records {
            #expect(record.vulnStatus == "Received")
            #expect(record.scores.isEmpty)
            #expect(SeverityTier.tiered(from: record.scores, advertised: nil) == .unrated)
        }
    }

    /// CVSS v2 writes `baseSeverity` as a **sibling** of `cvssData`, while v3.1
    /// and v4.0 write it **inside** `cvssData`. Both spellings occur in the same
    /// captured response, on the same record.
    @Test("Both places NVD writes a published severity word are read")
    func bothPublishedSeverityPositionsAreRead() throws {
        let response = try NVDWire.enrichment(from: Fixture.data("NVD/cveids-response.json"))
        let record = try #require(response.records.first { $0.cveID == "CVE-2020-25575" })

        let modern = try #require(record.scores.first { $0.version == .v31 })
        let legacy = try #require(record.scores.first { $0.version == .v2 })

        #expect(modern.publishedSeverity == "CRITICAL")
        #expect(legacy.publishedSeverity == "HIGH")
    }

    /// The band arithmetic, checked against NVD's own word for every scored
    /// entry in the capture rather than against the author's memory of the CVSS
    /// specification.
    @Test("Every published severity word in the capture agrees with the computed band")
    func theComputedBandAgreesWithNvdsOwnWord() throws {
        let response = try NVDWire.enrichment(from: Fixture.data("NVD/cveids-response.json"))
        let scores = response.records.flatMap(\.scores).filter { $0.publishedSeverity != nil }

        #expect(scores.count == 15, "the cross-check ran against no scores")

        for score in scores {
            #expect(
                SeverityTier.tiered(from: [score], advertised: nil).rawValue.uppercased()
                    == score.publishedSeverity,
                "\(score.version.rawValue) \(score.baseScore) disagreed with NVD"
            )
        }
    }
}
