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

    private let discovery: any AdvisoryDiscovering
    private let enrichment: any AdvisoryEnriching
    private let cache: any AdvisoryCaching
    private let consent: any ScanConsentProviding
    private let queries: QueryProvider
    private let matcher: CVEMatcher
    private let clock: any Clock<Duration>
    private let timeSource: any SecurityTimeSource
    private let policy: SecurityRefreshPolicy

    public private(set) var status: SecurityScanStatus = .idle

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
    private nonisolated let continuation: AsyncStream<SecurityScanEvent>.Continuation

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
        self.discovery = discovery
        self.enrichment = enrichment
        self.cache = cache
        self.consent = consent
        self.queries = queries
        self.matcher = matcher
        self.clock = clock
        self.timeSource = timeSource
        self.policy = policy

        (events, continuation) = AsyncStream.makeStream(
            of: SecurityScanEvent.self,
            bufferingPolicy: .unbounded
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

        let queries = await queries()
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

        return await settle(queries: queries, discovered: discovered, enriched: enriched)
    }

    /// Composes the answers into outcomes, mints the next revision, persists,
    /// and publishes — in that order, so nothing is published that was not first
    /// written down.
    private func settle(
        queries: [AdvisoryQuery],
        discovered: AdvisoryDiscovery,
        enriched: EnrichmentStep
    ) async -> SecurityScanOutcome {
        let now = timeSource.now
        let entries = entries(
            for: queries,
            answers: discovered.answers,
            severities: enriched.severities,
            at: now
        )

        let revision = (await loadCache()?.revision ?? SecurityScanRevision(ordinal: 0)).next()
        let result = SecurityScanResult(
            revision: revision,
            entries: entries,
            provenance: ScanProvenance(
                scannedAt: now,
                matcherVersion: CVEMatcher.version,
                mappingRevision: EcosystemMapping.revision,
                skippedRecordCounts: [
                    .osv: discovered.skippedRecordCount,
                    .nvd: enriched.skippedRecordCount
                ],
                enrichmentAttempted: enriched.attempted,
                enrichmentSucceeded: enriched.succeeded
            ),
            isPartial: (enriched.attempted && enriched.succeeded == false)
                || discovered.skippedRecordCount > 0
        )

        // Provenance and partiality are persisted with the entries, so a
        // relaunch reads back the scan that happened rather than a scan-shaped
        // guess assembled from what survived.
        try? await cache.save(
            AdvisoryCacheFile(
                revisionOrdinal: revision.ordinal,
                entries: entries,
                provenance: result.provenance,
                isPartial: result.isPartial
            )
        )

        status = .settled(revision)
        continuation.yield(.status(status))
        continuation.yield(.settled(result))
        return .completed(result)
    }

    /// What enrichment produced, and whether it was even asked.
    ///
    /// Two flags rather than one, because "we never asked NVD" and "we asked and
    /// were refused" both leave findings unrated and are different facts.
    private struct EnrichmentStep {
        var severities: [String: SeverityTier] = [:]
        var attempted = false
        var succeeded = false
        var skippedRecordCount = 0
    }

    private func enrichIfNeeded(_ discovered: AdvisoryDiscovery) async -> EnrichmentStep {
        let identifiers = Self.identifiers(in: discovered)
        // No findings, no enrichment. A clean inventory costs one request.
        guard identifiers.isEmpty == false else { return EnrichmentStep() }

        var step = EnrichmentStep(attempted: true)
        publish(.enriching)
        do {
            let enriched = try await enrichment.enrich(identifiers)
            step.severities = enriched.severities
            step.skippedRecordCount = enriched.skippedRecordCount
            step.succeeded = true
        } catch {
            // Recorded, never fatal: discovery's answers stand and the findings
            // simply arrive unrated.
            step.succeeded = false
        }
        return step
    }

    private func entries(
        for queries: [AdvisoryQuery],
        answers: [DiscoveredAnswer],
        severities: [String: SeverityTier],
        at now: Date
    ) -> [AdvisoryCacheEntry] {
        zip(queries, answers).map { query, discoveredAnswer in
            AdvisoryCacheEntry(
                key: AdvisoryCacheKey(
                    sourceID: .osv,
                    packageID: query.packageID,
                    version: query.installedVersion
                ),
                outcome: matcher.match(
                    query: query,
                    answer: discoveredAnswer.answer,
                    severities: severities
                ),
                fetchedAt: now,
                advisoryModified: discoveredAnswer.newestModified,
                mappingRevision: EcosystemMapping.revision,
                matcherVersion: CVEMatcher.version
            )
        }
    }

    /// Retries only the failures another attempt could plausibly fix.
    private func discoverWithRetries(
        _ queries: [AdvisoryQuery]
    ) async -> Result<AdvisoryDiscovery, AdvisoryError> {
        var lastError = AdvisoryError.transportFailed

        for attempt in 1...max(1, policy.maximumAttempts) {
            if attempt > 1 {
                do {
                    try await clock.sleep(for: policy.backoff(beforeAttempt: attempt))
                } catch {
                    return .failure(lastError)
                }
            }
            do {
                return .success(try await discovery.discover(queries))
            } catch {
                lastError = error
                guard policy.isWorthRetrying(error) else { return .failure(error) }
            }
        }
        return .failure(lastError)
    }

    /// The CVE identifiers discovery found, deduplicated and ordered.
    ///
    /// Ordered so a request is reproducible, deduplicated because one advisory
    /// routinely applies to several installed packages and enrichment must not
    /// scale with inventory.
    private static func identifiers(in discovery: AdvisoryDiscovery) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        for discoveredAnswer in discovery.answers {
            guard case .answered(let advisories) = discoveredAnswer.answer else { continue }
            for advisory in advisories {
                guard let cveID = advisory.cveID, seen.insert(cveID).inserted else { continue }
                ordered.append(cveID)
            }
        }
        return ordered
    }

    private func publish(_ status: SecurityScanStatus) {
        self.status = status
        continuation.yield(.status(status))
    }
}
