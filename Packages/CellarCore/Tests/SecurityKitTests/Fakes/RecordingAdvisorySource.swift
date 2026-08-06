import CellarTestSupport
import Foundation
import SecurityKit
import Synchronization

/// Both acquisition seams, recorded.
///
/// The counters are the point. Most of what the consent and scheduling rules
/// promise is an **absence** — no request before consent, no request after
/// revocation, no request while the cache is fresh — and an absence is only
/// provable by counting the calls that did happen against zero, with a control
/// somewhere else proving the counter moves at all.
final class RecordingAdvisorySource: AdvisoryDiscovering, AdvisoryEnriching, Sendable {
    struct State {
        var discoverCalls = 0
        var enrichCalls = 0
        var lastQueries: [AdvisoryQuery] = []
        var lastIdentifiers: [String] = []
        /// Consumed in order; once empty, `discovery` answers.
        var queuedDiscoveries: [Result<AdvisoryDiscovery, AdvisoryError>] = []
        /// `nil` means "echo one clean answer per query", which is both the
        /// realistic result on a real inventory and the only default that keeps
        /// answers aligned with questions whatever the test asks about.
        var discovery: Result<AdvisoryDiscovery, AdvisoryError>?
        var enrichment: Result<AdvisoryEnrichment, AdvisoryError> =
            .success(AdvisoryEnrichment(severities: [:], skippedRecordCount: 0))
    }

    private let state = Mutex(State())
    /// Lets a test hold discovery open, which is the only way to have two scans
    /// genuinely overlap rather than merely follow one another.
    private let clock: TestClock?
    private let discoveryDelay: Duration

    init(clock: TestClock? = nil, discoveryDelay: Duration = .zero) {
        self.clock = clock
        self.discoveryDelay = discoveryDelay
    }

    // MARK: - Reading

    var discoverCallCount: Int { state.withLock(\.discoverCalls) }
    var enrichCallCount: Int { state.withLock(\.enrichCalls) }
    var lastQueries: [AdvisoryQuery] { state.withLock(\.lastQueries) }
    var lastIdentifiers: [String] { state.withLock(\.lastIdentifiers) }

    // MARK: - Arranging

    func answerDiscovery(with result: Result<AdvisoryDiscovery, AdvisoryError>) {
        state.withLock { $0.discovery = result }
    }

    func queueDiscoveries(_ results: [Result<AdvisoryDiscovery, AdvisoryError>]) {
        state.withLock { $0.queuedDiscoveries = results }
    }

    func answerEnrichment(with result: Result<AdvisoryEnrichment, AdvisoryError>) {
        state.withLock { $0.enrichment = result }
    }

    // MARK: - The seams

    func discover(_ queries: [AdvisoryQuery]) async throws(AdvisoryError) -> AdvisoryDiscovery {
        let result = state.withLock { state -> Result<AdvisoryDiscovery, AdvisoryError>? in
            state.discoverCalls += 1
            state.lastQueries = queries
            guard state.queuedDiscoveries.isEmpty else {
                return state.queuedDiscoveries.removeFirst()
            }
            return state.discovery
        }

        if let clock, discoveryDelay > .zero {
            try? await clock.sleep(for: discoveryDelay)
        }

        switch result {
        case .none:
            return AdvisoryDiscovery(
                answers: queries.map { _ in
                    DiscoveredAnswer(answer: .answered([]), newestModified: nil)
                },
                skippedRecordCount: 0
            )
        case .success(let discovery): return discovery
        case .failure(let error): throw error
        }
    }

    func enrich(_ cveIDs: [String]) async throws(AdvisoryError) -> AdvisoryEnrichment {
        let result = state.withLock { state -> Result<AdvisoryEnrichment, AdvisoryError> in
            state.enrichCalls += 1
            state.lastIdentifiers = cveIDs
            return state.enrichment
        }
        switch result {
        case .success(let enrichment): return enrichment
        case .failure(let error): throw error
        }
    }
}

/// Consent that can be withdrawn mid-test, which is the only way to state *off
/// means fully off* as a test rather than as two separate engines.
final class MutableScanConsent: ScanConsentProviding, Sendable {
    private let consent: Mutex<ScanConsent>

    init(_ consent: ScanConsent) {
        self.consent = Mutex(consent)
    }

    func currentConsent() async -> ScanConsent { consent.withLock { $0 } }

    func revoke() { consent.withLock { $0 = $0.revoked() } }

    func grant(at date: Date) { consent.withLock { $0 = .granted(at: date) } }
}

/// A wall clock a test can move, kept deliberately separate from `TestClock`.
///
/// Sleeping is monotonic and staleness is a wall-clock question, and the whole
/// reason `SecurityRefreshPolicy` splits `staleAfter` from `pollGranularity` is
/// that those two diverge every time a laptop closes its lid. A test that used
/// one seam for both could not tell the split apart from its absence.
final class MutableTimeSource: SecurityTimeSource, Sendable {
    private let instant: Mutex<Date>

    init(_ now: Date) {
        instant = Mutex(now)
    }

    var now: Date { instant.withLock { $0 } }

    func advance(by interval: TimeInterval) {
        instant.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

/// An in-memory `AdvisoryCaching`, so scheduling tests never touch a disk.
final class InMemoryAdvisoryCache: AdvisoryCaching, Sendable {
    private let file: Mutex<AdvisoryCacheFile?>

    init(_ file: AdvisoryCacheFile? = nil) {
        self.file = Mutex(file)
    }

    func load() async throws -> AdvisoryCacheFile? { file.withLock { $0 } }

    func save(_ file: AdvisoryCacheFile) async throws {
        self.file.withLock { $0 = file }
    }

    var stored: AdvisoryCacheFile? { file.withLock { $0 } }
}
