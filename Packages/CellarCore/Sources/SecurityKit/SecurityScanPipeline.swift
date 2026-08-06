import Foundation

/// The scan pipeline: settling a run into a result, building its entries, and the
/// two retry policies.
///
/// Split out of `SecurityScanEngine.swift`, which crossed the 400-line rule when
/// pre-decided outcomes landed. The seam is real rather than arbitrary: nothing
/// here touches the single-flight slot, the event stream or the consent gate —
/// those are lifecycle, and this is the work the lifecycle schedules.
extension SecurityScanEngine {

    /// Composes the answers into outcomes, mints the next revision, persists,
    /// and publishes — in that order, so nothing is published that was not first
    /// written down.
    func settle(
        request: AdvisoryScanRequest,
        discovered: AdvisoryDiscovery,
        enriched: EnrichmentStep
    ) async -> SecurityScanOutcome {
        let now = timeSource.now
        let entries = entries(
            predecided: request.predecided,
            for: request.queries,
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
    struct EnrichmentStep {
        var severities: [String: SeverityTier] = [:]
        var attempted = false
        var succeeded = false
        var skippedRecordCount = 0
    }

    func enrichIfNeeded(_ discovered: AdvisoryDiscovery) async -> EnrichmentStep {
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

    func entries(
        predecided: [PredecidedOutcome],
        for queries: [AdvisoryQuery],
        answers: [DiscoveredAnswer],
        severities: [String: SeverityTier],
        at now: Date
    ) -> [AdvisoryCacheEntry] {
        let answered = zip(queries, answers).map { query, discoveredAnswer in
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

        // Appended rather than merged: a pre-decided package was never queried,
        // so there is no answer for it to disagree with, and the two sets are
        // disjoint by construction.
        return answered + predecided.map { decided in
            AdvisoryCacheEntry(
                key: AdvisoryCacheKey(
                    sourceID: .osv,
                    packageID: decided.packageID,
                    version: decided.installedVersion
                ),
                outcome: decided.outcome,
                fetchedAt: now,
                advisoryModified: nil,
                mappingRevision: EcosystemMapping.revision,
                matcherVersion: CVEMatcher.version
            )
        }
    }

    /// Retries only the failures another attempt could plausibly fix.
    func discoverWithRetries(
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

    func publish(_ status: SecurityScanStatus) {
        self.status = status
        continuation.yield(.status(status))
    }
}
