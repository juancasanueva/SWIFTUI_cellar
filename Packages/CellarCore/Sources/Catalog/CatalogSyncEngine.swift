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

    /// The one sync that may be joined, together with the token that owns it.
    ///
    /// Keyed by a token so a settling task can only ever vacate *its own* entry:
    /// without it, a slow unwind could clear a slot a newer sync already took.
    private struct InFlightSync {
        let token: Int
        let task: Task<Result<CatalogSnapshot, CatalogSyncError>, Never>
        /// A cancelled slot is drainable but never joinable.
        var isCancelled = false
    }

    private var inFlight: InFlightSync?
    private var nextSyncToken = 0

    /// The identity of the snapshot currently on disk, if it is known.
    private var diskRevision: CatalogSnapshotRevision?

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
    ///
    /// Every read is re-stamped with `diskRevision`, so the same file always
    /// answers under the same identity and the consumer can tell a re-read from
    /// genuinely new content (design D2).
    public func cachedSnapshot() -> CatalogSnapshot? {
        guard let snapshot = (try? store.loadSnapshot()) ?? nil else { return nil }
        guard let diskRevision else {
            self.diskRevision = snapshot.revision
            return snapshot
        }
        return snapshot.carrying(diskRevision)
    }

    /// The wall-clock instant this engine reckons by.
    ///
    /// Exposed so a consumer projecting Discover prunes against the *same*
    /// clock the sync dated the arrivals with, rather than reaching for
    /// `Date()` and introducing a second, untestable notion of now.
    public var now: Date { timeSource.now }

    /// The dated arrivals log, already pruned to the retention window.
    ///
    /// Mirrors `cachedSnapshot()`: never blocks on the network, and a missing,
    /// corrupt or version-mismatched file is the ordinary answer "no arrivals"
    /// rather than an error. Pruned on the way out, so the thirty-day rule holds
    /// even on a machine that has not synced in six weeks — write-time pruning
    /// alone would only bound the file (catalog-sync CS-A2).
    public func arrivals() -> PackageArrivalsLog? {
        store.loadArrivals()?.pruned(now: timeSource.now)
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
    /// downloads help nobody. Only work *genuinely in flight* may be joined: the
    /// task vacates its own slot from inside its body, so the slot is empty
    /// before any joiner resumes and nobody is handed a settled result as if it
    /// were fresh (design D3).
    @discardableResult
    public func sync() async -> Result<CatalogSnapshot, CatalogSyncError> {
        while let current = inFlight {
            guard current.isCancelled else { return await current.task.value }
            // A cancelled run is not joinable, and it is still unwinding: its
            // `defer { store.purgeStaging() }` would delete a successor's
            // download. Drain it, then start fresh work on an empty staging dir.
            _ = await current.task.value
        }

        nextSyncToken += 1
        let token = nextSyncToken
        // Creation and assignment are one actor turn with no suspension between
        // them, so the body cannot settle before the slot exists.
        let task = Task {
            defer { self.vacate(token) }
            return await self.performSync()
        }
        inFlight = InFlightSync(token: token, task: task)
        return await task.value
    }

    private func vacate(_ token: Int) {
        guard inFlight?.token == token else { return }
        inFlight = nil
    }

    /// Syncs only when the persisted catalog is past `staleAfter`.
    @discardableResult
    public func syncIfStale() async -> Result<CatalogSnapshot, CatalogSyncError>? {
        guard isStale() else { return nil }
        return await sync()
    }

    /// Cancels the sync in flight, if any.
    ///
    /// Marks the slot rather than emptying it. Emptying immediately would let a
    /// fresh sync start while the cancelled one is still unwinding, and the old
    /// task's `defer { store.purgeStaging() }` would then delete the new run's
    /// in-flight download. The mark keeps the invariant — nobody is satisfied by
    /// cancelled work — without opening that race (design D3).
    public func cancel() {
        inFlight?.isCancelled = true
        inFlight?.task.cancel()
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

            let acquired = try await acquirePayloads(
                previousState: previousState,
                // Validators certify the payload behind `previousSnapshot`. If that
                // snapshot cannot be read, a 304 would leave nothing to rebuild
                // from, so the fetch must be unconditional (catalog-sync CS6).
                revalidatable: previousSnapshot != nil,
                into: staging
            )
            let sources = acquired.sources
            let now = timeSource.now

            // Nothing moved. Writing the snapshot again would be 4 MB of
            // pointless I/O; the sidecar still has to record the new
            // `downloadedAt` or the next launch re-checks immediately. Bound to a
            // *readable* previous snapshot: "unchanged" with nothing to rebuild
            // from is not a success, and the old `previousSnapshot ??
            // CatalogSnapshot(packages: [])` fallback could only ever have
            // published an empty catalog. Without a cache the sync falls through
            // and fails, which is what forces the next fetch to be unconditional
            // (design D4).
            if !acquired.changed, let previousSnapshot {
                try store.persistState(
                    CatalogState(
                        sources: sources,
                        lastSuccessAt: now,
                        skippedRecordCount: previousState?.skippedRecordCount ?? 0
                    )
                )
                return succeed(with: previousSnapshot, at: now)
            }

            let analytics = await fetchAnalytics(into: staging, carryingOver: previousSnapshot)
            try checkCancellation()

            let snapshot = CatalogDecoder.link(
                formulae: acquired.decoded[.formula] ?? carriedOver(.formula, from: previousSnapshot),
                casks: acquired.decoded[.cask] ?? carriedOver(.cask, from: previousSnapshot),
                analytics: analytics,
                generatedAt: now
            )
            try persist(
                snapshot,
                state: CatalogState(
                    sources: sources,
                    lastSuccessAt: now,
                    skippedRecordCount: acquired.skippedRecordCount
                )
            )
            // Only on the path that materialized a *new* snapshot. On a fully
            // revalidated sync the packages are identical, so diffing would be a
            // guaranteed no-op costing a roster read and a 16k set compare.
            recordArrivals(in: snapshot, at: now)
            return succeed(with: snapshot, at: now)
        } catch {
            let failure = CatalogSyncError.from(error)
            publish(.failed(failure))
            return .failure(failure)
        }
    }

    /// Publishes a snapshot and re-pins the identity of the bytes on disk.
    ///
    /// A publish that failed part-way could have left either file behind, so the
    /// pin is forgotten rather than left certifying bytes nobody checked.
    private func persist(_ snapshot: CatalogSnapshot, state: CatalogState) throws {
        do {
            try store.persist(snapshot, state: state)
            diskRevision = snapshot.revision
        } catch {
            diskRevision = nil
            throw error
        }
    }

    /// Advances the seen-set and the arrivals log against a freshly published
    /// snapshot.
    ///
    /// **Non-throwing by signature, and that is the point.** This runs inside
    /// `performSync`'s `do` block, whose `catch` turns anything reaching it into
    /// a failed sync — so a roster that cannot be written would otherwise
    /// discard a 47 MB catalog that arrived perfectly. Newness is decoration: a
    /// write failure here costs newness for one sync and nothing else, and the
    /// signature is what makes the alternative unreachable rather than merely
    /// unintended (catalog-sync CS-A1).
    ///
    /// An absent or rejected roster is the *seeding* pass, which by construction
    /// records zero arrivals — so a corrupt file degrades to "empty and
    /// explained", never to "the whole catalog is new".
    private func recordArrivals(in snapshot: CatalogSnapshot, at instant: Date) {
        let advanced = DiscoveryRosterDiff.advance(
            roster: store.loadRoster(),
            arrivals: store.loadArrivals(),
            observing: snapshot.packages,
            now: instant
        )
        try? store.persistDiscovery(roster: advanced.roster, arrivals: advanced.arrivals)
    }

    /// What one pass over the two payload resources produced.
    private struct AcquiredPayloads {
        var sources: [CatalogResource: SourceState]
        var decoded: [PackageKind: DecodedResource] = [:]
        var skippedRecordCount = 0
        /// False when every resource revalidated as unchanged.
        var changed = false
    }

    /// Fetches and decodes each payload resource in turn.
    ///
    /// Sequential on purpose: two mapped 30 MB payloads alive at once would
    /// double the decode peak for no benefit (design D8).
    private func acquirePayloads(
        previousState: CatalogState?,
        revalidatable: Bool,
        into staging: URL
    ) async throws -> AcquiredPayloads {
        var acquired = AcquiredPayloads(sources: previousState?.sources ?? [:])

        for resource in CatalogResource.payloadResources {
            let stored = revalidatable ? previousState?.sources[resource]?.validators : nil
            let outcome = try await fetch(
                resource,
                validators: stored.flatMap { $0.isEmpty ? nil : $0 },
                into: staging
            )

            switch outcome {
            case .notModified:
                // Revalidated, not re-downloaded: the payload stands, only its
                // freshness moves (catalog-sync CS2).
                acquired.sources[resource]?.downloadedAt = timeSource.now

            case .downloaded(let payload):
                acquired.changed = true
                publish(.decoding)
                let projected = try await CatalogDecoder.decode(resource, at: payload.fileURL)
                acquired.decoded[resource.kind] = projected
                acquired.skippedRecordCount += projected.skippedRecordCount
                acquired.sources[resource] = SourceState(
                    validators: payload.validators,
                    downloadedAt: timeSource.now,
                    recordCount: projected.packages.count,
                    byteCount: payload.byteCount
                )
            }
            try checkCancellation()
        }

        return acquired
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
                    index = index.merging(AnalyticsIndex(carriedOverFor: resource.kind, in: previous))
                    continue
                }
                index = index.merging(
                    try await CatalogDecoder.decodeAnalytics(at: payload.fileURL, kind: resource.kind)
                )
            } catch {
                index = index.merging(AnalyticsIndex(carriedOverFor: resource.kind, in: previous))
            }
        }
        return index
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
