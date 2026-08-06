import Foundation

// MARK: - Values

/// A CVSS metric family, most preferred first.
///
/// The order is the spec's, and it is an order of *authority*, not of numbers:
/// a v4.0 8.2 outranks a v3.1 9.8 because v4.0 is the newer analysis of the same
/// vulnerability, not because 8.2 is larger.
public enum CVSSVersion: String, Sendable, Hashable, Codable, CaseIterable {
    // swiftlint:disable identifier_name
    // `v2` is two characters and is the name CVSS itself uses. The alternative
    // is `v20`, which reads as "version twenty" beside `v40`, or `version2`,
    // which breaks the shape of the other three. The raw values carry the
    // unambiguous form.
    case v40 = "4.0"
    case v31 = "3.1"
    case v30 = "3.0"
    case v2 = "2.0"
    // swiftlint:enable identifier_name

    /// Lower is preferred.
    var preference: Int {
        switch self {
        case .v40: 0
        case .v31: 1
        case .v30: 2
        case .v2: 3
        }
    }
}

/// One published base score.
public struct CVSSScore: Sendable, Hashable {
    public let version: CVSSVersion
    public let baseScore: Double
    public let vectorString: String
    /// The scoring authority's own severity word, where it published one.
    ///
    /// Kept alongside the number rather than instead of it, because the tier is
    /// computed from the number: this field is what lets
    /// `theComputedBandAgreesWithNvdsOwnWord` check that arithmetic against NVD
    /// rather than against the author's memory of the CVSS specification.
    ///
    /// It is read from **two** places, because NVD writes it in two. v3.x and
    /// v4.0 put it inside `cvssData`; v2 puts it beside `cvssData`, as a sibling
    /// of the metric entry.
    public let publishedSeverity: String?

    public init(
        version: CVSSVersion,
        baseScore: Double,
        vectorString: String,
        publishedSeverity: String?
    ) {
        self.version = version
        self.baseScore = baseScore
        self.vectorString = vectorString
        self.publishedSeverity = publishedSeverity
    }
}

/// One enriched CVE.
public struct NVDRecord: Sendable, Hashable {
    public let cveID: String
    /// NVD's own analysis state. `"Received"` means the record exists and has
    /// not been scored yet — the honest route to `unrated`.
    public let vulnStatus: String
    public let description: String
    /// Every **CVSS** metric on the record. Entries of other kinds are absent
    /// rather than represented, because there is nothing this feature can do
    /// with them and a half-decoded one is a trap.
    public let scores: [CVSSScore]

    public init(cveID: String, vulnStatus: String, description: String, scores: [CVSSScore]) {
        self.cveID = cveID
        self.vulnStatus = vulnStatus
        self.description = description
        self.scores = scores
    }
}

/// A decoded enrichment response.
public struct NVDEnrichmentResponse: Sendable, Hashable {
    public let records: [NVDRecord]
    /// The server's own count, left untouched by a local decode failure. The gap
    /// between this and `records.count` is the evidence that something was
    /// dropped.
    public let totalResults: Int
    public let skippedRecordCount: Int

    public init(records: [NVDRecord], totalResults: Int, skippedRecordCount: Int) {
        self.records = records
        self.totalResults = totalResults
        self.skippedRecordCount = skippedRecordCount
    }
}

// MARK: - Decode

/// Turns NVD enrichment payloads into values.
///
/// Same envelope/record rule as `OSVWire`, with one deliberate difference:
/// NVD's `vulnerabilities` array is **not positional**. Every record names its
/// own CVE, so an unreadable one costs exactly itself and is dropped, where an
/// unreadable OSV result has to keep its slot. The two decoders look
/// inconsistent side by side; they are the same rule applied to two payloads
/// that carry identity differently.
public enum NVDWire {
    public static func enrichment(from data: Data) throws(AdvisoryError) -> NVDEnrichmentResponse {
        let envelope: EnrichmentEnvelopeWire
        do {
            envelope = try JSONDecoder().decode(EnrichmentEnvelopeWire.self, from: data)
        } catch {
            throw .malformedPayload
        }
        return NVDEnrichmentResponse(
            records: envelope.records,
            totalResults: envelope.totalResults,
            skippedRecordCount: envelope.skippedCount
        )
    }
}

// MARK: - Tiering

extension SeverityTier {
    /// The tier for one advisory: the best published score, else the published
    /// word, else nothing.
    ///
    /// "Else nothing" is the whole rule. There is no arithmetic here that turns
    /// an absent score into a middling one, and `unrated` is returned rather
    /// than any scored tier when neither source said anything.
    public static func tiered(from scores: [CVSSScore], advertised: String?) -> SeverityTier {
        if let preferred = preferredScore(among: scores) { return preferred.tier }
        guard let advertised, let word = tier(advertised: advertised) else { return .unrated }
        return word
    }

    /// The most authoritative score present, by metric family.
    ///
    /// Exposed rather than folded into `tiered(from:advertised:)` because two
    /// metrics can disagree about the score while agreeing about the tier —
    /// `CVE-2026-0994` carries v4.0 8.2 beside v3.1 7.5, both `high` — and a
    /// preference test that could only see the tier would pass against a
    /// decoder that picked either one.
    public static func preferredScore(among scores: [CVSSScore]) -> CVSSScore? {
        scores.min { $0.version.preference < $1.version.preference }
    }

    /// The severity words the two databases actually publish.
    ///
    /// Returns `nil` for anything else, which becomes `unrated`. A word this
    /// table does not know is not a hint to be interpreted: guessing that
    /// `IMPORTANT` means `high` is the same failure as defaulting an unscored
    /// advisory to medium, one synonym further along.
    static func tier(advertised word: String) -> SeverityTier? {
        switch word.uppercased() {
        case "CRITICAL": .critical
        case "HIGH": .high
        case "MODERATE", "MEDIUM": .medium
        case "LOW": .low
        case "NONE": SeverityTier.none
        default: nil
        }
    }
}

extension CVSSScore {
    /// The band this score falls in, under **its own version's** specification.
    ///
    /// The bands are not shared. CVSS v2 defines no `critical` and no `none`:
    /// its scale is low / medium / high, with 10.0 at the top of `high` and 0.0
    /// at the bottom of `low`. Tiering a v2 score with v3 bands would invent a
    /// critical rating that the standard which produced the number does not
    /// define — and the captured corpus has three records where exactly that
    /// mistake changes the answer.
    var tier: SeverityTier {
        switch version {
        case .v2:
            if baseScore >= 7.0 { return .high }
            if baseScore >= 4.0 { return .medium }
            return .low
        case .v30, .v31, .v40:
            if baseScore >= 9.0 { return .critical }
            if baseScore >= 7.0 { return .high }
            if baseScore >= 4.0 { return .medium }
            if baseScore >= 0.1 { return .low }
            return SeverityTier.none
        }
    }
}

// MARK: - Wire shapes

private struct SkipWire: Decodable {
    init(from decoder: any Decoder) throws {
        _ = try decoder.singleValueContainer()
    }
}

private struct EnrichmentEnvelopeWire: Decodable {
    let records: [NVDRecord]
    let totalResults: Int
    let skippedCount: Int

    enum CodingKeys: String, CodingKey {
        case totalResults, vulnerabilities
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalResults = try container.decode(Int.self, forKey: .totalResults)

        var array = try container.nestedUnkeyedContainer(forKey: .vulnerabilities)
        var records: [NVDRecord] = []
        var skipped = 0

        while !array.isAtEnd {
            guard let wire = try? array.decode(VulnerabilityWire.self) else {
                _ = try? array.decode(SkipWire.self)
                skipped += 1
                continue
            }
            records.append(wire.cve.record)
        }

        self.records = records
        skippedCount = skipped
    }
}

private struct VulnerabilityWire: Decodable {
    let cve: CVEWire
}

private struct CVEWire: Decodable {
    let id: String
    let vulnStatus: String?
    let descriptions: [DescriptionWire]?
    /// Keyed by metric family (`cvssMetricV40`, `cvssMetricV31`, `ssvcV203`, …).
    ///
    /// Decoded as a plain dictionary rather than as a fixed set of keys, because
    /// NVD adds families over time and an unknown one must be *ignored*, not a
    /// decode failure. The family name is never trusted for the version either —
    /// that comes from `cvssData.version`.
    let metrics: [String: [MetricEntryWire]]?

    var record: NVDRecord {
        NVDRecord(
            cveID: id,
            vulnStatus: vulnStatus ?? "",
            description: descriptions?.first { $0.lang == "en" }?.value ?? "",
            scores: (metrics ?? [:])
                .sorted { $0.key < $1.key }
                .flatMap(\.value)
                .compactMap(\.score)
                .sorted { $0.version.preference < $1.version.preference }
        )
    }
}

private struct DescriptionWire: Decodable {
    let lang: String
    let value: String
}

private struct MetricEntryWire: Decodable {
    let cvssData: CVSSDataWire?
    /// CVSS v2's severity word, published as a sibling of `cvssData` rather than
    /// inside it.
    let baseSeverity: String?

    /// `nil` for any entry that is not a CVSS score.
    ///
    /// `ssvcV203` is the live example: it sits inside `metrics` beside genuine
    /// v3.1 scores and carries no `cvssData` member at all. Assuming every
    /// entry in `metrics` is a score reports a properly scored 7.5 record as
    /// unrated — the exact hazard the U2 capture found.
    var score: CVSSScore? {
        guard let cvssData, let version = CVSSVersion(rawValue: cvssData.version) else {
            return nil
        }
        return CVSSScore(
            version: version,
            baseScore: cvssData.baseScore,
            vectorString: cvssData.vectorString,
            publishedSeverity: cvssData.baseSeverity ?? baseSeverity
        )
    }
}

private struct CVSSDataWire: Decodable {
    let version: String
    let baseScore: Double
    let vectorString: String
    let baseSeverity: String?
}
