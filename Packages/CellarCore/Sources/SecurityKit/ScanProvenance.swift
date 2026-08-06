import Foundation

/// What produced a scan result, recorded alongside the result itself.
///
/// Mirrors `CleanupParserProvenance`: the version of the code that produced an
/// answer travels with the answer, so a corrected mapping table or a fixed
/// matcher can be told apart from a stale cache entry rather than guessed at.
/// The cache invalidates on both version fields for exactly that reason.
public struct ScanProvenance: Sendable, Hashable {
    public let scannedAt: Date
    /// The matcher that produced this result.
    public let matcherVersion: Int
    /// The curated ecosystem table that produced this result.
    public let mappingRevision: Int
    /// How many records each source published that could not be read.
    ///
    /// Per source, because "OSV dropped one record" and "NVD dropped one record"
    /// are different facts with different consequences: the first costs coverage,
    /// the second costs only severity.
    public let skippedRecordCounts: [AdvisorySourceID: Int]
    /// Whether enrichment was attempted at all, and whether it worked.
    ///
    /// Two flags rather than one, because "we never asked NVD" and "we asked and
    /// were rate-limited" both leave findings unrated and must not be reported
    /// as the same thing.
    public let enrichmentAttempted: Bool
    public let enrichmentSucceeded: Bool

    public init(
        scannedAt: Date,
        matcherVersion: Int,
        mappingRevision: Int,
        skippedRecordCounts: [AdvisorySourceID: Int] = [:],
        enrichmentAttempted: Bool = false,
        enrichmentSucceeded: Bool = false
    ) {
        self.scannedAt = scannedAt
        self.matcherVersion = matcherVersion
        self.mappingRevision = mappingRevision
        self.skippedRecordCounts = skippedRecordCounts
        self.enrichmentAttempted = enrichmentAttempted
        self.enrichmentSucceeded = enrichmentSucceeded
    }

    /// The total across every source, for the one place a single number is
    /// meaningful: telling a user that something was dropped at all.
    public var totalSkippedRecordCount: Int {
        skippedRecordCounts.values.reduce(0, +)
    }
}
