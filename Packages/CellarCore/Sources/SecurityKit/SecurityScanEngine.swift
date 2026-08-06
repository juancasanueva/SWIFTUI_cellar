import Foundation

// MARK: - The engine

/// Runs advisory scans, one at a time, behind recorded consent.
///
/// `CatalogSyncEngine`'s shipped lifecycle guarantees, restated for a different
/// payload rather than reinvented: single-flight keyed by a token so a settling
/// run can only vacate its own slot, drain-then-restart on cancellation so a
/// cancelled run is never joined, and a one-observer event stream.
///
/// ## Consent is checked on every egress path
///
/// Not once at construction, and not once when the loop starts. `scan()` reads
/// the current consent every time it runs, which is what makes revocation take
/// effect on the very next scheduled pass rather than at the next launch. Off is
/// fully off, and the cache stays readable — `loadCache()` deliberately does not
/// consult consent, because reading a file this app already wrote is not egress.
public actor SecurityScanEngine {
    /// Where the queries come from.
    ///
    /// A closure because building them needs `InstalledPackage.primaryKeg`, which
    /// lives in `BrewClient` — a target this one deliberately cannot see. The app
    /// composes the two; this engine only asks.
    public typealias QueryProvider = @Sendable () async -> [AdvisoryQuery]
    /// The whole of what one scan must account for: the packages to ask about,
    /// **and** the ones already decided without asking.
    public typealias RequestProvider = @Sendable () async -> AdvisoryScanRequest

    let discovery: any AdvisoryDiscovering
    let enrichment: any AdvisoryEnriching
    let cache: any AdvisoryCaching
    let consent: any ScanConsentProviding
    let request: RequestProvider
    let matcher: CVEMatcher
    let clock: any Clock<Duration>
    let timeSource: any SecurityTimeSource
    let policy: SecurityRefreshPolicy

    public internal(set) var status: SecurityScanStatus = .idle

    /// The one scan that may be joined, together with the token that owns it.
    ///
    /// Keyed by token so a settling run can only ever vacate *its own* entry:
    /// without it, a slow unwind could clear a slot a newer scan already took.
    private struct InFlightScan {
        let token: Int
        let task: Task<SecurityScanOutcome, Never>
        /// A cancelled slot is drainable but never joinable.
        var isCancelled = false
    }

    private var inFlight: InFlightScan?
    private var nextScanToken = 0

    public nonisolated let events: AsyncStream<SecurityScanEvent>
    nonisolated let continuation: AsyncStream<SecurityScanEvent>.Continuation

    public init(
        discovery: any AdvisoryDiscovering,
        enrichment: any AdvisoryEnriching,
        cache: any AdvisoryCaching,
        consent: any ScanConsentProviding,
        request: @escaping RequestProvider,
        matcher: CVEMatcher = CVEMatcher(),
        clock: any Clock<Duration> = ContinuousClock(),
        timeSource: any SecurityTimeSource = SystemSecurityTimeSource(),
        policy: SecurityRefreshPolicy = SecurityRefreshPolicy()
    ) {
        self.discovery = discovery
        self.enrichment = enrichment
        self.cache = cache
        self.consent = consent
        self.request = request
        self.matcher = matcher
        self.clock = clock
        self.timeSource = timeSource
        self.policy = policy

        (events, continuation) = AsyncStream.makeStream(
            of: SecurityScanEvent.self,
            bufferingPolicy: .unbounded
        )
    }

    /// For callers with nothing pre-decided.
    ///
    /// Every real composition root has something pre-decided — most of an
    /// inventory is unmapped — so this exists for the tests that are asking about
    /// the *acquisition* half and would otherwise have to say "and nothing else"
    /// at every call site.
    public init(
        discovery: any AdvisoryDiscovering,
        enrichment: any AdvisoryEnriching,
        cache: any AdvisoryCaching,
        consent: any ScanConsentProviding,
        queries: @escaping QueryProvider,
        matcher: CVEMatcher = CVEMatcher(),
        clock: any Clock<Duration> = ContinuousClock(),
        timeSource: any SecurityTimeSource = SystemSecurityTimeSource(),
        policy: SecurityRefreshPolicy = SecurityRefreshPolicy()
    ) {
        self.init(
            discovery: discovery,
            enrichment: enrichment,
            cache: cache,
            consent: consent,
            request: { AdvisoryScanRequest(queries: await queries()) },
            matcher: matcher,
            clock: clock,
            timeSource: timeSource,
            policy: policy
        )
    }

    // MARK: - Reading what is already known

    /// The persisted scan, read from disk.
    ///
    /// **Runs before any network work and consults no consent.** Reading a file
    /// this app wrote is not egress, and refusing to read it after revocation
    /// would delete the user's findings rather than stop transmitting them.
    public func loadCache() async -> AdvisoryCacheFile? {
        (try? await cache.load()) ?? nil
    }

    // MARK: - Scanning

    /// Runs a scan, or joins the one already running.
    ///
    /// The task vacates its own slot from inside its body, so the slot is empty
    /// before any joiner resumes and nobody is handed a settled result as if it
    /// were fresh.
    @discardableResult
    public func scan() async -> SecurityScanOutcome {
        while let current = inFlight {
            guard current.isCancelled else { return await current.task.value }
            // A cancelled run is not joinable and is still unwinding. Drain it,
            // then start fresh — the same rule catalog sync learned.
            _ = await current.task.value
        }

        nextScanToken += 1
        let token = nextScanToken
        // Creation and assignment are one actor turn with no suspension between
        // them, so the body cannot settle before the slot exists.
        let task = Task {
            defer { self.vacate(token) }
            return await self.performScan()
        }
        inFlight = InFlightScan(token: token, task: task)
        return await task.value
    }

    private func vacate(_ token: Int) {
        guard inFlight?.token == token else { return }
        inFlight = nil
    }

    /// Scans only when the persisted result is past `staleAfter`.
    ///
    /// `nil` means there was nothing to do — which is a different answer from a
    /// scan that ran and found nothing.
    @discardableResult
    public func scanIfStale() async -> SecurityScanOutcome? {
        let lastFetchedAt = await loadCache()?.entries.map(\.fetchedAt).max()
        guard policy.isStale(lastFetchedAt: lastFetchedAt, now: timeSource.now) else { return nil }
        return await scan()
    }

    /// Cancels the scan in flight, if any.
    ///
    /// Marks the slot rather than emptying it, so a fresh scan cannot start
    /// while the cancelled one is still unwinding.
    public func cancel() {
        inFlight?.isCancelled = true
        inFlight?.task.cancel()
    }

    /// Wakes every `pollGranularity` and scans when the wall clock says the last
    /// scan went stale.
    ///
    /// A single twenty-four hour sleep would be simpler and wrong: monotonic
    /// sleeps do not advance while the machine is asleep, so a laptop closed
    /// overnight would wake with nothing pending.
    public func runRefreshLoop() async {
        while !Task.isCancelled {
            await scanIfStale()
            do {
                try await clock.sleep(for: policy.pollGranularity)
            } catch {
                return
            }
        }
    }

    // MARK: - The scan itself

    private func performScan() async -> SecurityScanOutcome {
        // Every egress path checks consent first, every time. Not at
        // construction, not once per loop — here, so revocation takes effect on
        // the next pass rather than the next launch.
        do {
            try await consent.currentConsent().authorise()
        } catch {
            publish(.blockedPendingConsent)
            return .failed(.blockedPendingConsent)
        }

        let scanRequest = await request()
        let queries = scanRequest.queries
        guard Task.isCancelled == false else { return .cancelled }

        publish(.discovering)
        let discovered: AdvisoryDiscovery
        switch await discoverWithRetries(queries) {
        case .success(let value): discovered = value
        case .failure(let error):
            guard Task.isCancelled == false else { return .cancelled }
            publish(.failed(error))
            return .failed(error)
        }
        guard Task.isCancelled == false else { return .cancelled }

        // A positional payload whose length disagrees with the question list
        // cannot be attributed to anything.
        guard discovered.answers.count == queries.count else {
            publish(.failed(.malformedPayload))
            return .failed(.malformedPayload)
        }

        let enriched = await enrichIfNeeded(discovered)
        guard Task.isCancelled == false else { return .cancelled }

        return await settle(
            request: scanRequest,
            discovered: discovered,
            enriched: enriched
        )
    }
}
