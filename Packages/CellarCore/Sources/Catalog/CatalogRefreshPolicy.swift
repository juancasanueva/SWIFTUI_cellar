import Foundation

/// The wall clock, behind a seam.
///
/// Separate from the `Clock` the refresh loop sleeps on: sleeping is monotonic,
/// staleness is a wall-clock question, and the two diverge every time a laptop
/// closes its lid (design D5).
public protocol CatalogTimeSource: Sendable {
    var now: Date { get }
}

/// `Date()`.
public struct SystemTimeSource: CatalogTimeSource {
    public init() {}
    public var now: Date { Date() }
}

/// Every number the refresh schedule depends on, in one place.
public struct CatalogRefreshPolicy: Sendable, Equatable {
    /// A catalog older than this is refreshed in the background.
    public var staleAfter: TimeInterval
    /// How often the loop wakes to compare wall-clock time against the sidecar.
    ///
    /// A single 24 h sleep would drift across system sleep; a short poll that
    /// re-reads the wall clock does not (design D5).
    public var pollGranularity: Duration
    /// Total attempts per resource, including the first.
    public var maximumAttempts: Int
    /// Delay before the first retry; doubled for each subsequent one.
    public var backoff: Duration
    /// Per-resource ceiling on a downloaded body.
    public var payloadByteLimit: Int

    public init(
        staleAfter: TimeInterval = 24 * 60 * 60,
        pollGranularity: Duration = .seconds(15 * 60),
        maximumAttempts: Int = 3,
        backoff: Duration = .milliseconds(500),
        payloadByteLimit: Int = 128 * 1_048_576
    ) {
        self.staleAfter = staleAfter
        self.pollGranularity = pollGranularity
        self.maximumAttempts = maximumAttempts
        self.backoff = backoff
        self.payloadByteLimit = payloadByteLimit
    }

    /// The delay before attempt number `attempt` (1-based), exponential.
    func backoff(beforeAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return .zero }
        return backoff * Int(pow(2.0, Double(attempt - 2)))
    }
}
