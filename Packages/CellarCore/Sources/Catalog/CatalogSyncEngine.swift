import Foundation

/// What the engine tells its observer about.
public enum CatalogSyncEvent: Sendable {
    case status(CatalogSyncStatus)
    case snapshot(CatalogSnapshot)
}

/// Coordinates acquisition, decoding and persistence for the whole catalog.
///
/// An `actor` because sync has real coordination state — an in-flight task, the
/// current phase — that several callers touch at once. It holds **only** that
/// state: every multi-second CPU burst happens in a `@concurrent` function off
/// the actor, so `status`, `cancel()` and a manual-refresh join are never stuck
/// behind a decode (design D2).
public actor CatalogSyncEngine {
    private let store: CatalogFileStore
    private let source: any CatalogSource
    private let clock: any Clock<Duration>
    private let timeSource: any CatalogTimeSource
    private let policy: CatalogRefreshPolicy

    public private(set) var status: CatalogSyncStatus = .idle
    private var inFlight: Task<Result<CatalogSnapshot, CatalogSyncError>, Never>?

    /// Status transitions and new snapshots, in order, for a single observer.
    public nonisolated let events: AsyncStream<CatalogSyncEvent>
    private nonisolated let continuation: AsyncStream<CatalogSyncEvent>.Continuation

    public init(
        store: CatalogFileStore,
        source: any CatalogSource,
        clock: any Clock<Duration> = ContinuousClock(),
        timeSource: any CatalogTimeSource = SystemTimeSource(),
        policy: CatalogRefreshPolicy = CatalogRefreshPolicy()
    ) {
        self.store = store
        self.source = source
        self.clock = clock
        self.timeSource = timeSource
        self.policy = policy
        (events, continuation) = AsyncStream<CatalogSyncEvent>.makeStream(
            bufferingPolicy: .unbounded
        )
    }

    // MARK: - Cache

    /// The persisted snapshot, or `nil`. Never blocks on the network.
    public func cachedSnapshot() -> CatalogSnapshot? {
        (try? store.loadSnapshot()) ?? nil
    }

    /// Whether the oldest payload source is past its shelf life.
    ///
    /// No cache at all counts as stale — that is what makes a cold launch sync.
    public func isStale() -> Bool {
        guard
            let state = (try? store.loadState()) ?? nil,
            let downloadedAt = state.oldestPayloadDownloadedAt
        else { return true }
        return timeSource.now.timeIntervalSince(downloadedAt) >= policy.staleAfter
    }

    // MARK: - Syncing

    /// Runs a sync, or joins the one already running.
    ///
    /// Single-flight for the same reason `BrewDetectionStore.refresh()` is: a
    /// window regaining focus can fire in bursts, and two concurrent 47 MB
    /// downloads help nobody.
    @discardableResult
    public func sync() async -> Result<CatalogSnapshot, CatalogSyncError> {
        if let inFlight { return await inFlight.value }

        let task = Task { await self.performSync() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    /// Syncs only when the persisted catalog is past `staleAfter`.
    @discardableResult
    public func syncIfStale() async -> Result<CatalogSnapshot, CatalogSyncError>? {
        guard isStale() else { return nil }
        return await sync()
    }

    /// Cancels the sync in flight, if any.
    public func cancel() {
        inFlight?.cancel()
    }

    /// Wakes every `pollGranularity` and syncs when the wall clock says the
    /// catalog went stale.
    ///
    /// A single 24 h sleep would be simpler and wrong: monotonic sleeps do not
    /// advance while the machine is asleep, so a laptop closed overnight would
    /// wake with a two-day-old catalog and no pending refresh (design D5).
    public func runRefreshLoop() async {
        while !Task.isCancelled {
            await syncIfStale()
            do {
                try await clock.sleep(for: policy.pollGranularity)
            } catch {
                return
            }
        }
    }

    // MARK: - The sync itself

    private func performSync() async -> Result<CatalogSnapshot, CatalogSyncError> {
        let previousState = (try? store.loadState()) ?? nil
        let previousSnapshot = cachedSnapshot()

        do {
            publish(.downloading(fractionCompleted: nil))
            let staging = try store.prepareStaging()
            defer { store.purgeStaging() }

            var sources = previousState?.sources ?? [:]
            var decoded: [PackageKind: DecodedResource] = [:]
            var skipped = 0
            var changed = false

            for resource in CatalogResource.payloadResources {
                let stored = previousState?.sources[resource]?.validators
                let outcome = try await fetch(
                    resource,
                    validators: stored.flatMap { $0.isEmpty ? nil : $0 },
                    into: staging
                )

                switch outcome {
                case .notModified:
                    // Revalidated, not re-downloaded: the payload stands, only
                    // its freshness moves (catalog-sync CS2).
                    sources[resource]?.downloadedAt = timeSource.now

                case .downloaded(let payload):
                    changed = true
                    publish(.decoding)
                    let resource$ = try await CatalogDecoder.decode(resource, at: payload.fileURL)
                    decoded[resource.kind] = resource$
                    skipped += resource$.skippedRecordCount
                    sources[resource] = SourceState(
                        validators: payload.validators,
                        downloadedAt: timeSource.now,
                        recordCount: resource$.packages.count,
                        byteCount: payload.byteCount
                    )
                }
                try checkCancellation()
            }

            let now = timeSource.now

            guard changed || previousSnapshot == nil else {
                // Nothing moved. Writing the snapshot again would be 4 MB of
                // pointless I/O; the sidecar still has to record the new
                // `downloadedAt` or the next launch re-checks immediately.
                try store.persistState(
                    CatalogState(
                        sources: sources,
                        lastSuccessAt: now,
                        skippedRecordCount: previousState?.skippedRecordCount ?? 0
                    )
                )
                let snapshot = previousSnapshot ?? CatalogSnapshot(
                    generatedAt: now, skippedRecordCount: 0, packages: []
                )
                return succeed(with: snapshot, at: now)
            }

            let analytics = await fetchAnalytics(into: staging, carryingOver: previousSnapshot)
            try checkCancellation()

            let snapshot = CatalogDecoder.link(
                formulae: decoded[.formula] ?? carriedOver(.formula, from: previousSnapshot),
                casks: decoded[.cask] ?? carriedOver(.cask, from: previousSnapshot),
                analytics: analytics,
                generatedAt: now
            )
            try store.persist(
                snapshot,
                state: CatalogState(
                    sources: sources,
                    lastSuccessAt: now,
                    skippedRecordCount: skipped
                )
            )
            return succeed(with: snapshot, at: now)
        } catch {
            let failure = CatalogSyncError.from(error)
            publish(.failed(failure))
            return .failure(failure)
        }
    }

    /// A resource the origin says is unchanged still has to appear in the new
    /// snapshot, and the previous projection is exactly those records.
    private func carriedOver(
        _ kind: PackageKind,
        from snapshot: CatalogSnapshot?
    ) -> DecodedResource {
        guard let snapshot else { return .empty }
        return DecodedResource(
            packages: snapshot.packages.filter { $0.kind == kind },
            skippedRecordCount: 0
        )
    }

    /// Acquires the two analytics endpoints, never fatally.
    ///
    /// Analytics is decoration: a catalog with no install counts is still a
    /// complete, searchable catalog, so a failure here must not cost the user
    /// the 47 MB of payload that already arrived (catalog-sync CS9). A namespace
    /// that fails keeps whatever count the previous snapshot held, because a
    /// slightly stale number beats blanking the column.
    ///
    /// No retry: this data is optional, and a backoff storm for it would delay
    /// the snapshot that is not.
    private func fetchAnalytics(
        into directory: URL,
        carryingOver previous: CatalogSnapshot?
    ) async -> AnalyticsIndex {
        var index = AnalyticsIndex()
        for resource in CatalogResource.analyticsResources {
            do {
                let outcome = try await source.fetch(resource, validators: nil, into: directory)
                guard case .downloaded(let payload) = outcome else {
                    index = index.merging(Self.counts(of: resource.kind, in: previous))
                    continue
                }
                index = index.merging(
                    try await CatalogDecoder.decodeAnalytics(at: payload.fileURL, kind: resource.kind)
                )
            } catch {
                index = index.merging(Self.counts(of: resource.kind, in: previous))
            }
        }
        return index
    }

    private static func counts(of kind: PackageKind, in snapshot: CatalogSnapshot?) -> AnalyticsIndex {
        guard let snapshot else { return AnalyticsIndex() }
        var counts: [PackageID: Int] = [:]
        for package in snapshot.packages where package.kind == kind {
            if let count = package.installCount365d { counts[package.id] = count }
        }
        return AnalyticsIndex(counts: counts)
    }

    private func succeed(
        with snapshot: CatalogSnapshot,
        at instant: Date
    ) -> Result<CatalogSnapshot, CatalogSyncError> {
        continuation.yield(.snapshot(snapshot))
        publish(.succeeded(at: instant))
        return .success(snapshot)
    }

    private func fetch(
        _ resource: CatalogResource,
        validators: ConditionalValidators?,
        into directory: URL
    ) async throws -> CatalogFetchOutcome {
        var attempt = 1
        while true {
            do {
                return try await source.fetch(resource, validators: validators, into: directory)
            } catch {
                let failure = CatalogSyncError.from(error)
                guard failure.isRetryable, attempt < policy.maximumAttempts else { throw failure }
                attempt += 1
                try await clock.sleep(for: policy.backoff(beforeAttempt: attempt))
            }
        }
    }

    private func checkCancellation() throws {
        if Task.isCancelled { throw CatalogSyncError.cancelled }
    }

    private func publish(_ status: CatalogSyncStatus) {
        self.status = status
        continuation.yield(.status(status))
    }
}

extension CatalogResource {
    /// The two resources that carry packages. Analytics is a separate, optional
    /// join.
    public static let payloadResources: [CatalogResource] = [.formulae, .casks]

    /// The two optional install-count endpoints.
    public static let analyticsResources: [CatalogResource] = [.analyticsFormula, .analyticsCask]

    var kind: PackageKind {
        switch self {
        case .formulae, .analyticsFormula: .formula
        case .casks, .analyticsCask: .cask
        }
    }
}

extension CatalogSyncError {
    /// Normalises anything thrown inside a sync into the closed taxonomy.
    static func from(_ error: any Error) -> CatalogSyncError {
        switch error {
        case let known as CatalogSyncError: known
        case is CancellationError: .cancelled
        default: .malformedPayload
        }
    }
}

extension CatalogDecoder {
    /// Decodes a staged payload off the caller's executor.
    ///
    /// `@concurrent` rather than a plain `nonisolated func`: a synchronous
    /// nonisolated call from an actor still runs *on* that actor, which is the
    /// head-of-line block this whole design avoids (design D2).
    @concurrent
    public static func decode(
        _ resource: CatalogResource,
        at url: URL
    ) async throws -> DecodedResource {
        switch resource {
        case .formulae:
            try decodeFormulae(contentsOf: url, deletingAfterwards: true)
        case .casks:
            try decodeCasks(contentsOf: url, deletingAfterwards: true)
        case .analyticsFormula, .analyticsCask:
            throw CatalogSyncError.malformedPayload
        }
    }

    /// Decodes a staged analytics payload off the caller's executor.
    @concurrent
    public static func decodeAnalytics(at url: URL, kind: PackageKind) async throws -> AnalyticsIndex {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw CatalogSyncError.malformedPayload
        }
        return try AnalyticsIndex.decode(data, kind: kind)
    }
}
