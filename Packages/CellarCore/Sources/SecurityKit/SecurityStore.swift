import Foundation
import Observation

// MARK: - Scopes

/// The two things this store holds state for.
///
/// They are separate scopes rather than one blended status because they fail
/// independently: advisory scanning can be rate-limited while artifact
/// inspection is perfectly healthy, and a single spinner covering both would
/// have to lie about one of them.
public enum SecurityScope: String, Sendable, Hashable, CaseIterable {
    case cveScan
    case integrity
}

// MARK: - State

/// What one scope currently has to show.
///
/// `CleanupPreviewState`'s shape, including the part that carries the weight:
/// every non-answer case carries the last good result alongside it. A transient
/// failure must not empty the user's findings, and a surface that can still
/// reach them can say "this is what we knew at 09:14" instead of nothing.
public enum SecurityScanState: Sendable, Hashable {
    case idle
    case loading(stale: SecurityScanResult?)
    case content(SecurityScanResult)
    /// A scan that finished while still missing something it set out to learn.
    ///
    /// Its own case rather than a flag on `.content`, so a caller cannot render
    /// a partial scan as a complete one by forgetting to read the flag.
    case partial(SecurityScanResult)
    case failed(AdvisoryError, stale: SecurityScanResult?)
    case cancelled(stale: SecurityScanResult?)

    /// The result this state is currently presenting, if it is presenting one.
    public var result: SecurityScanResult? {
        switch self {
        case .content(let result), .partial(let result): result
        case .idle, .loading, .failed, .cancelled: nil
        }
    }

    /// The last good result held behind a non-answer.
    public var staleResult: SecurityScanResult? {
        switch self {
        case .loading(let stale), .failed(_, let stale), .cancelled(let stale): stale
        case .idle, .content, .partial: nil
        }
    }

    public var failure: AdvisoryError? {
        guard case .failed(let error, _) = self else { return nil }
        return error
    }
}

// MARK: - The store

/// The security surface's state, and the single main-isolated crossing point of
/// this target.
///
/// ## Two guards, two questions
///
/// A **generation** kills a superseded *task*: the user navigated away, revoked
/// consent, or asked again, and the answer now arriving is to a question nobody
/// is asking. An **ordinal** kills a late-arriving older *snapshot*: the answer
/// is to the right question, but a better answer already landed. They are not
/// interchangeable, and neither one can do the other's job — a cache read that
/// started first and finished second carries a live generation and a stale
/// ordinal, while a cancelled scan carries a stale generation and an ordinal
/// nobody has seen yet.
///
/// `CleanupStore` supplies the per-scope task map, generation map and `lastGood`
/// survival; `CatalogStore.adopt` supplies the strictly-greater ordinal rule,
/// including its two edges — a duplicate **joins** the adoption already in
/// flight rather than returning empty-handed, and an older one returns without
/// disarming the newer snapshot's deduplication.
@MainActor
@Observable
public final class SecurityStore {
    /// Per-scope state. Absent means `.idle`, which is what a store that has
    /// never been asked anything honestly has.
    public private(set) var states: [SecurityScope: SecurityScanState] = [:]
    /// Per-scope coverage, projected off the main actor during adoption.
    public private(set) var coverages: [SecurityScope: CoverageTotals] = [:]
    /// The engine's most recent published status, including the one that is not
    /// a failure: nothing was sent because consent was never granted.
    public private(set) var scanStatus: SecurityScanStatus = .idle
    /// Whether the store has consulted the cache at all.
    ///
    /// "Ready" means answering, not populated — the catalog's distinction. A
    /// cold launch with no cache is ready and empty, and the surface shows an
    /// empty state rather than a spinner that never resolves.
    public private(set) var isReady = false

    @ObservationIgnored private let engine: SecurityScanEngine
    @ObservationIgnored private var tasks: [SecurityScope: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [SecurityScope: UUID] = [:]
    @ObservationIgnored private var lastGood: [SecurityScope: SecurityScanResult] = [:]
    /// The newest snapshot identity each scope has taken responsibility for, and
    /// the adoption a duplicate delivery of it should wait on.
    @ObservationIgnored private var adoptedRevisions: [SecurityScope: SecurityScanRevision] = [:]
    @ObservationIgnored private var adoptionsInFlight: [SecurityScope: Task<Void, Never>] = [:]
    @ObservationIgnored private var isRunning = false

    /// How many adoptions were requested, and how many actually projected.
    ///
    /// Internal instrumentation, exactly as `CatalogStore` carries: "one
    /// snapshot, one projection" is not observable from the published state,
    /// and it is the whole content of the duplicate and older-ordinal rules.
    @ObservationIgnored private(set) var adoptionRequestCount = 0
    @ObservationIgnored private(set) var projectionCount = 0

    public init(engine: SecurityScanEngine) {
        self.engine = engine
    }

    // MARK: - Reading

    public func state(for scope: SecurityScope) -> SecurityScanState { states[scope] ?? .idle }

    public func coverage(for scope: SecurityScope) -> CoverageTotals {
        coverages[scope] ?? CoverageTotals(of: [])
    }

    // MARK: - Lifecycle

    /// Loads the cache, then observes the engine for as long as the scene lives.
    ///
    /// SwiftUI's structured cancellation tears down both the event observer and
    /// the refresh loop when the scene goes away. The event stream supports one
    /// iterator, so a second window's `.task` must not start a second one.
    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        await loadCache()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [engine] in
                for await event in engine.events {
                    await self.handle(event)
                }
            }
            group.addTask { [engine] in
                await engine.runRefreshLoop()
            }
        }
    }

    /// Reads whatever is on disk and starts answering.
    ///
    /// **Before any network work, and consulting no consent.** Reading a file
    /// this app wrote is not egress, and the result is adopted at the file's own
    /// persisted ordinal — so the floor a live scan has to clear survives the
    /// relaunch instead of resetting to zero and letting a stale snapshot win.
    public func loadCache() async {
        if let file = await engine.loadCache() {
            await adopt(file.scanResult, scope: .cveScan)
        }
        // After the adoption, so a cold launch with a usable cache shows results
        // rather than flashing an empty state and repopulating.
        isReady = true
    }

    /// Starts a scan for `scope`, superseding whatever was running for it.
    ///
    /// Returns the generation, which is the only thing that can authorise the
    /// resulting adoption.
    @discardableResult
    public func startScan(_ scope: SecurityScope = .cveScan) -> UUID {
        tasks[scope]?.cancel()
        let generation = UUID()
        generations[scope] = generation
        states[scope] = .loading(stale: lastGood[scope])

        tasks[scope] = Task { [weak self, engine] in
            let outcome = await engine.scan()
            await self?.adopt(outcome, scope: scope, generation: generation)
        }
        return generation
    }

    /// Starts a scan and waits for it to be adopted.
    ///
    /// The manual-refresh ingress: a caller that pressed a button wants to know
    /// when there is something to look at.
    public func scanNow(_ scope: SecurityScope = .cveScan) async {
        startScan(scope)
        await tasks[scope]?.value
    }

    /// Cancels the scan in flight for `scope`, rotating its generation so its
    /// answer cannot install afterwards.
    public func cancelScan(_ scope: SecurityScope = .cveScan) {
        tasks[scope]?.cancel()
        tasks[scope] = nil
        generations[scope] = UUID()
        states[scope] = .cancelled(stale: lastGood[scope])
        Task { [engine] in await engine.cancel() }
    }

    // MARK: - Adoption

    private func handle(_ event: SecurityScanEvent) async {
        switch event {
        case .status(let status): scanStatus = status
        case .settled(let result): await adopt(result, scope: .cveScan)
        }
    }

    /// Installs a task's outcome, if that task is still the one being awaited.
    ///
    /// Internal rather than private because the guarantee worth testing here —
    /// a superseded task cannot install a result that the live generation would
    /// have installed happily — is a statement about this method and nothing
    /// else. The generation is checked *before* the ordinal, so a refused task
    /// never reaches the ordinal guard and the two cannot mask each other.
    func adopt(
        _ outcome: SecurityScanOutcome,
        scope: SecurityScope,
        generation: UUID
    ) async {
        guard generations[scope] == generation else { return }
        tasks[scope] = nil

        switch outcome {
        case .completed(let result):
            await adopt(result, scope: scope)
        case .cancelled:
            states[scope] = .cancelled(stale: lastGood[scope])
        case .failed(let error):
            // The last good result stays resident: a rate limit or a dropped
            // connection must not empty the user's findings.
            states[scope] = .failed(error, stale: lastGood[scope])
        }
    }

    /// Installs a snapshot, if it is strictly newer than the one already adopted.
    ///
    /// Internal for the same reason: the duplicate-joins and older-returns edges
    /// are statements about this method.
    func adopt(_ result: SecurityScanResult, scope: SecurityScope) async {
        adoptionRequestCount += 1

        // Only a strictly greater ordinal may install. "Newer" is the result's
        // own minted revision, never the order adoption happened to be called
        // in — a cache read that started first can finish second.
        //
        // A duplicate *joins* rather than returns: one materialization reaches
        // this store through the settled event and through a manual refresh, and
        // whichever arrives second must come back with the result queryable.
        // Claimed before any suspension, so a concurrent duplicate cannot slip
        // past, and an older one leaves through the same door without regressing
        // the adopted record — which is what stops it disarming the newer
        // snapshot's deduplication. Ordinals start at 1, so a missing record
        // stands for "nothing adopted yet".
        guard result.revision.supersedes(adoptedRevisions[scope]) else {
            await adoptionsInFlight[scope]?.value
            return
        }
        adoptedRevisions[scope] = result.revision

        projectionCount += 1
        lastGood[scope] = result

        let adoption = Task { [weak self] in
            let totals = await Self.project(result)
            guard let self else { return }
            // One main-actor assignment pair, after the projection: there is no
            // window in which the store is between results.
            coverages[scope] = totals
            // Partial is its own state and never `.content`: "we could not get
            // severities" is a different claim from "these findings are unrated".
            states[scope] = result.isPartial ? .partial(result) : .content(result)
        }
        adoptionsInFlight[scope] = adoption

        await adoption.value

        if adoptionsInFlight[scope] == adoption { adoptionsInFlight[scope] = nil }
    }

    /// Counts the four coverage states off the main actor.
    ///
    /// Small work today — an inventory is hundreds of entries, not the catalog's
    /// fifteen thousand records — and off-main anyway, because it scales with
    /// the inventory and the main actor's job is the window. It is also what a
    /// duplicate adoption joins, which is the only way "one materialization,
    /// one projection" can be a fact rather than an intention.
    private nonisolated static func project(_ result: SecurityScanResult) async -> CoverageTotals {
        CoverageTotals(of: result.entries.map(\.outcome))
    }
}
