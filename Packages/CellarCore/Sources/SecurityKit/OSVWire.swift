import Foundation

// MARK: - Values

/// One advisory as `querybatch` names it: an identifier and when it last changed.
///
/// `modified` is not decoration. It is the second, independent cache
/// invalidation the spec requires — an advisory edited today must be re-hydrated
/// today, even if the entry that holds it is still inside its TTL.
public struct OSVAdvisoryReference: Sendable, Hashable {
    public let id: String
    public let modified: Date

    public init(id: String, modified: Date) {
        self.id = id
        self.modified = modified
    }
}

/// OSV's answer to one query in a batch.
///
/// `answered([])` and `unreadable` are deliberately different values. The first
/// means "we asked and there is nothing"; the second means "we asked and cannot
/// tell". Collapsing them is the exact failure `CVEScanOutcome` exists to
/// prevent, and it would be reintroduced here if this were an array that could
/// simply be empty.
public enum OSVQueryResult: Sendable, Hashable {
    case answered([OSVAdvisoryReference])
    case unreadable
}

/// A decoded `querybatch` response.
///
/// `results` is **positional**: entry *i* answers query *i*, and nothing inside
/// an entry names the package it belongs to. That is why a bad entry keeps its
/// slot instead of being dropped — see `OSVWire.querybatch(from:)`.
public struct OSVQuerybatchResponse: Sendable, Hashable {
    public let results: [OSVQueryResult]
    public let skippedRecordCount: Int

    public init(results: [OSVQueryResult], skippedRecordCount: Int) {
        self.results = results
        self.skippedRecordCount = skippedRecordCount
    }
}

/// One declared affected range.
///
/// The three event lists are kept apart rather than reduced to a single "fixed
/// version", because the spec requires "no fix published" to stay distinct from
/// "fix unknown". A range with an `introduced` event and no `fixed` event — the
/// shape RustSec uses for an unmaintained crate — is a real statement that no
/// fix exists, and it must not read as a missing field.
public struct OSVRange: Sendable, Hashable {
    public let type: String
    public let introduced: [String]
    public let fixed: [String]
    public let lastAffected: [String]

    public init(type: String, introduced: [String], fixed: [String], lastAffected: [String]) {
        self.type = type
        self.introduced = introduced
        self.fixed = fixed
        self.lastAffected = lastAffected
    }
}

/// One package an advisory applies to, in that package's own ecosystem.
public struct OSVAffected: Sendable, Hashable {
    public let ecosystem: String
    public let packageName: String
    public let ranges: [OSVRange]

    public init(ecosystem: String, packageName: String, ranges: [OSVRange]) {
        self.ecosystem = ecosystem
        self.packageName = packageName
        self.ranges = ranges
    }
}

/// A hydrated advisory record.
public struct OSVAdvisory: Sendable, Hashable {
    public let id: String
    public let modified: Date
    public let summary: String
    public let details: String
    /// Other identifiers for the same vulnerability. The `CVE-…` alias is what
    /// enrichment is keyed by; nothing else in a request ever names a package.
    public let aliases: [String]
    /// The database's own published severity word, when it has one.
    ///
    /// Read from the `severity` **key** rather than inferred from an empty
    /// `database_specific` object: RustSec records carry a present-but-irrelevant
    /// `database_specific` holding only a licence.
    public let advertisedSeverity: String?
    /// The published CVSS vectors. OSV publishes vectors without base scores, so
    /// these identify *which* metric exists; the numeric score that tiers a
    /// finding comes from NVD enrichment.
    public let severityVectors: [OSVSeverityVector]
    public let affected: [OSVAffected]

    public init(
        id: String,
        modified: Date,
        summary: String,
        details: String,
        aliases: [String],
        advertisedSeverity: String?,
        severityVectors: [OSVSeverityVector],
        affected: [OSVAffected]
    ) {
        self.id = id
        self.modified = modified
        self.summary = summary
        self.details = details
        self.aliases = aliases
        self.advertisedSeverity = advertisedSeverity
        self.severityVectors = severityVectors
        self.affected = affected
    }

    /// The first `CVE-…` alias, which is the only identifier enrichment uses.
    public var cveID: String? {
        aliases.first { $0.hasPrefix("CVE-") }
    }
}

/// One published CVSS vector: its metric family and the vector string itself.
public struct OSVSeverityVector: Sendable, Hashable {
    public let type: String
    public let vectorString: String

    public init(type: String, vectorString: String) {
        self.type = type
        self.vectorString = vectorString
    }
}

// MARK: - Decode

/// Turns OSV payloads into values.
///
/// Follows the `InstalledDecoder` rule, which has two halves pulling in opposite
/// directions. An unreadable **envelope** fails the request, because nothing in
/// it is recoverable. An unreadable **record** costs that record and is counted,
/// because one advisory whose shape drifted must not delete every other answer
/// in the batch.
///
/// A third rule is specific to this payload and is the dangerous one. OSV's
/// `results` array is positional, so dropping a bad entry the way a lossy array
/// drops a bad formula would re-attribute every later answer to the wrong
/// package: a whole inventory of confident, wrong findings, with nothing left in
/// the payload to catch it. A bad entry therefore keeps its slot and reports
/// `.unreadable`.
public enum OSVWire {
    public static func querybatch(from data: Data) throws(AdvisoryError) -> OSVQuerybatchResponse {
        let envelope: QuerybatchEnvelopeWire
        do {
            envelope = try JSONDecoder().decode(QuerybatchEnvelopeWire.self, from: data)
        } catch {
            throw .malformedPayload
        }
        return OSVQuerybatchResponse(
            results: envelope.results,
            skippedRecordCount: envelope.skippedCount
        )
    }

    public static func advisory(from data: Data) throws(AdvisoryError) -> OSVAdvisory {
        let wire: AdvisoryWire
        do {
            wire = try JSONDecoder().decode(AdvisoryWire.self, from: data)
        } catch {
            throw .malformedPayload
        }
        // A single hydration *is* its own envelope: an unparseable timestamp
        // leaves nothing recoverable, rather than costing one record of many.
        guard let modified = timestamp(wire.modified) else { throw .malformedPayload }

        return OSVAdvisory(
            id: wire.id,
            modified: modified,
            summary: wire.summary ?? "",
            details: wire.details ?? "",
            aliases: wire.aliases ?? [],
            advertisedSeverity: wire.databaseSpecific?.severity,
            severityVectors: (wire.severity ?? []).map {
                OSVSeverityVector(type: $0.type, vectorString: $0.score)
            },
            affected: (wire.affected ?? []).map(project(affected:))
        )
    }

    // MARK: - Timestamps

    /// Both spellings the captured corpus actually contains.
    ///
    /// GitHub-sourced records carry nanosecond fractions
    /// (`2026-07-07T17:56:36.712428283Z`); RustSec records carry none at all
    /// (`2022-08-02T14:03:23Z`). Two facts decided this implementation, and both
    /// were measured rather than assumed:
    ///
    /// - `ISO8601DateFormatter` parses exactly *one* of the two per option set
    ///   and returns `nil` for the other, so it would need two instances — and
    ///   it is a non-`Sendable` class, which this target's language mode will not
    ///   let a `static let` hold.
    /// - `Date.ISO8601FormatStyle` is a `Sendable` value and parses **both**
    ///   spellings with one strategy.
    ///
    /// So there is one strategy, and `bothCapturedTimestampSpellingsParse` keeps
    /// that leniency an asserted fact rather than a hope.
    public static func timestamp(_ string: String) -> Date? {
        try? Date(string, strategy: strategy)
    }

    private static let strategy = Date.ISO8601FormatStyle(
        includingFractionalSeconds: true,
        timeZone: TimeZone(identifier: "UTC") ?? .gmt
    )

    // MARK: - Projection

    private static func project(affected wire: AffectedWire) -> OSVAffected {
        OSVAffected(
            ecosystem: wire.package.ecosystem,
            packageName: wire.package.name,
            ranges: (wire.ranges ?? []).map { range in
                let events = range.events ?? []
                return OSVRange(
                    type: range.type,
                    introduced: events.compactMap(\.introduced),
                    fixed: events.compactMap(\.fixed),
                    lastAffected: events.compactMap(\.lastAffected)
                )
            }
        )
    }
}

// MARK: - Wire shapes

/// Consumes exactly one JSON value of any shape and keeps nothing, so a lossy
/// container can advance past an element it could not read.
private struct SkipWire: Decodable {
    init(from decoder: any Decoder) throws {
        _ = try decoder.singleValueContainer()
    }
}

private struct QuerybatchEnvelopeWire: Decodable {
    let results: [OSVQueryResult]
    let skippedCount: Int

    enum CodingKeys: String, CodingKey { case results }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var array = try container.nestedUnkeyedContainer(forKey: .results)
        var results: [OSVQueryResult] = []
        var skipped = 0

        while !array.isAtEnd {
            do {
                let result = try array.decode(QueryResultWire.self)
                results.append(.answered(result.references))
                skipped += result.skippedCount
            } catch {
                // The slot survives. Dropping it would shift every later answer
                // onto the wrong package.
                _ = try? array.decode(SkipWire.self)
                results.append(.unreadable)
                skipped += 1
            }
        }

        self.results = results
        skippedCount = skipped
    }
}

private struct QueryResultWire: Decodable {
    let references: [OSVAdvisoryReference]
    let skippedCount: Int

    enum CodingKeys: String, CodingKey { case vulns }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `{}` is OSV's answer for a package with no advisories at all. That is
        // an answer, not an omission, and it is the shape a real inventory
        // produces for almost every package.
        guard container.contains(.vulns) else {
            references = []
            skippedCount = 0
            return
        }

        var array = try container.nestedUnkeyedContainer(forKey: .vulns)
        var references: [OSVAdvisoryReference] = []
        var skipped = 0

        while !array.isAtEnd {
            guard let wire = try? array.decode(AdvisoryReferenceWire.self),
                  let modified = OSVWire.timestamp(wire.modified)
            else {
                _ = try? array.decode(SkipWire.self)
                skipped += 1
                continue
            }
            references.append(OSVAdvisoryReference(id: wire.id, modified: modified))
        }

        self.references = references
        skippedCount = skipped
    }
}

private struct AdvisoryReferenceWire: Decodable {
    let id: String
    let modified: String
}

private struct AdvisoryWire: Decodable {
    let id: String
    let modified: String
    let summary: String?
    let details: String?
    let aliases: [String]?
    let severity: [SeverityWire]?
    let databaseSpecific: DatabaseSpecificWire?
    let affected: [AffectedWire]?

    enum CodingKeys: String, CodingKey {
        case id, modified, summary, details, aliases, severity, affected
        case databaseSpecific = "database_specific"
    }
}

private struct SeverityWire: Decodable {
    let type: String
    let score: String
}

private struct DatabaseSpecificWire: Decodable {
    let severity: String?
}

private struct AffectedWire: Decodable {
    let package: AffectedPackageWire
    let ranges: [RangeWire]?
}

private struct AffectedPackageWire: Decodable {
    let name: String
    let ecosystem: String
}

private struct RangeWire: Decodable {
    let type: String
    let events: [EventWire]?
}

private struct EventWire: Decodable {
    let introduced: String?
    let fixed: String?
    let lastAffected: String?

    enum CodingKeys: String, CodingKey {
        case introduced, fixed
        case lastAffected = "last_affected"
    }
}
