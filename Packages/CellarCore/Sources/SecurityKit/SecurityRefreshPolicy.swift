import Foundation

/// The wall clock, behind a seam.
///
/// Separate from the `Clock` the refresh loop sleeps on, and the separation is
/// the point: sleeping is monotonic, staleness is a wall-clock question, and the
/// two diverge every time a laptop closes its lid.
///
/// Declared here rather than borrowed from `Catalog`. The two protocols are the
/// same shape today and answer to different owners: `CatalogTimeSource` belongs
/// to catalog sync and may change for catalog reasons. Mirroring a discipline is
/// not the same as sharing a type.
public protocol SecurityTimeSource: Sendable {
    var now: Date { get }
}

/// `Date()`.
public struct SystemSecurityTimeSource: SecurityTimeSource {
    public init() {}

    public var now: Date { Date() }
}

/// Every number the scan schedule depends on, in one place.
///
/// Mirrors `CatalogRefreshPolicy`, including the split that looks redundant and
/// is not.
public struct SecurityRefreshPolicy: Sendable, Equatable {
    /// A scan older than this is refreshed in the background.
    ///
    /// Deliberately equal to `AdvisoryCacheEntry.timeToLive`: a shorter TTL makes
    /// every scheduled scan a full re-query with no cache benefit, a longer one
    /// lets a scheduled scan read its own cache and never actually refresh.
    public var staleAfter: TimeInterval

    /// How often the loop wakes to compare wall-clock time against the cache.
    ///
    /// **Not** a single twenty-four hour sleep. A monotonic sleep does not
    /// advance while the machine is asleep, so a laptop closed overnight would
    /// wake with a two-day-old scan and nothing pending — the exact defect
    /// `CatalogSyncEngine.swift:149` exists to avoid, restated here rather than
    /// rediscovered.
    public var pollGranularity: Duration

    /// Total attempts per scan, including the first.
    public var maximumAttempts: Int
    /// Delay before the first retry; doubled for each subsequent one.
    public var backoff: Duration
    /// Ceiling on a response body, matching `AdvisorySession.payloadByteLimit`.
    public var payloadByteLimit: Int

    public init(
        staleAfter: TimeInterval = 24 * 60 * 60,
        pollGranularity: Duration = .seconds(15 * 60),
        maximumAttempts: Int = 3,
        backoff: Duration = .milliseconds(500),
        payloadByteLimit: Int = AdvisorySession.payloadByteLimit
    ) {
        self.staleAfter = staleAfter
        self.pollGranularity = pollGranularity
        self.maximumAttempts = maximumAttempts
        self.backoff = backoff
        self.payloadByteLimit = payloadByteLimit
    }

    /// Whether a scan is due.
    ///
    /// Never having scanned is stale, or the first launch after consent would
    /// wait a day before asking anything. A `fetchedAt` in the future is stale
    /// too: the clock moved, the age is unusable, and pretending the scan is
    /// fresh would hide the problem for as long as the skew lasts.
    public func isStale(lastFetchedAt: Date?, now: Date) -> Bool {
        guard let lastFetchedAt else { return true }
        let age = now.timeIntervalSince(lastFetchedAt)
        guard age >= 0 else { return true }
        return age > staleAfter
    }

    /// The delay before attempt number `attempt` (1-based), exponential.
    public func backoff(beforeAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return .zero }
        return backoff * Int(pow(2.0, Double(attempt - 2)))
    }

    /// Whether repeating a failed request could plausibly help.
    ///
    /// Retrying a rate limit immediately is the one thing guaranteed to make a
    /// rate limit worse; re-sending an oversized or undecodable payload sends
    /// exactly the same bytes again; and consent does not change because it was
    /// asked twice. Only the two failures that are genuinely about the transport
    /// are worth another attempt.
    public func isWorthRetrying(_ error: AdvisoryError) -> Bool {
        switch error {
        case .offline, .transportFailed: true
        case .rateLimited, .payloadTooLarge, .malformedPayload, .malformedRecord,
             .blockedPendingConsent: false
        }
    }
}
