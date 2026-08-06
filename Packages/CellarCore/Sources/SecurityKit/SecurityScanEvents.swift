import Foundation

// MARK: - What a scan produces

/// One completed scan.
///
/// `entries` is exactly what the cache persists, rather than a second parallel
/// shape: an outcome the surface can render and an outcome the cache can store
/// are the same value, so there is no projection between them to get wrong.
public struct SecurityScanResult: Sendable, Hashable {
    public let revision: SecurityScanRevision
    public let entries: [AdvisoryCacheEntry]
    public let provenance: ScanProvenance
    /// Whether anything the scan set out to learn is missing.
    ///
    /// A scan whose enrichment was refused still has every finding, so it is a
    /// **partial** result rather than a failed one — and it must not be adopted
    /// as complete, because "we could not get severities" is a different claim
    /// from "these findings are unrated".
    public let isPartial: Bool

    public init(
        revision: SecurityScanRevision,
        entries: [AdvisoryCacheEntry],
        provenance: ScanProvenance,
        isPartial: Bool
    ) {
        self.revision = revision
        self.entries = entries
        self.provenance = provenance
        self.isPartial = isPartial
    }
}

/// How a scan ended.
///
/// Three cases, and cancellation is its own. Folding it into a failure would tell
/// the surface that something went wrong when the user simply navigated away, and
/// folding it into a result would present a half-finished scan as an answer.
public enum SecurityScanOutcome: Sendable, Hashable {
    case completed(SecurityScanResult)
    case cancelled
    case failed(AdvisoryError)
}

public enum SecurityScanStatus: Sendable, Hashable {
    case idle
    /// Nothing was sent, and the reason is consent rather than the network.
    case blockedPendingConsent
    case discovering
    case enriching
    case settled(SecurityScanRevision)
    case failed(AdvisoryError)
}

public enum SecurityScanEvent: Sendable, Hashable {
    case status(SecurityScanStatus)
    case settled(SecurityScanResult)
}
