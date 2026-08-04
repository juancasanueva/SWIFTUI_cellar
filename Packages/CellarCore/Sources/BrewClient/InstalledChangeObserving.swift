import BrewProcess
import DiskUsage
import Foundation
import Observation

/// A source of "something under the watched roots changed".
///
/// The signal is deliberately `Void`. Its contents are never parsed: a
/// re-snapshot is always taken instead, because the only thing an event can
/// honestly tell us is that the last snapshot is stale (installed-inventory
/// II10). That also means the watcher can be wrong, late or missing without
/// making the inventory wrong — the baseline refresh still covers it.
public protocol InstalledChangeObserving: Sendable {
    /// Coalesced change signals. Never parsed.
    func changes() -> AsyncStream<Void>
}

/// Consumes one root-change stream and fans the signal out without starting a
/// second FSEvents observer. Path details are intentionally not interpreted;
/// the production watcher covers Cellar and Caskroom as one explicit boundary.
@MainActor
public final class HomebrewChangeFanout {
    private let observer: any InstalledChangeObserving
    private let installedChanged: @MainActor @Sendable () async -> Void
    private let diskChanged: @MainActor @Sendable (Set<DiskArea>) async -> Void

    public init(
        observer: any InstalledChangeObserving,
        installedChanged: @escaping @MainActor @Sendable () async -> Void,
        diskChanged: @escaping @MainActor @Sendable (Set<DiskArea>) async -> Void
    ) {
        self.observer = observer
        self.installedChanged = installedChanged
        self.diskChanged = diskChanged
    }

    public func run() async {
        for await _ in observer.changes() {
            await installedChanged()
            await diskChanged([.cellar, .caskroom])
        }
    }
}

/// Whether Cellar itself is currently changing what is installed.
///
/// M2-2 owns mutations; this is the seam it will drive. Signals emitted while a
/// mutation runs are noise from our own work — brew writes continuously through
/// an install — so they are suppressed and settled once at the end.
@MainActor
@Observable
public final class InstalledMutationGate {
    /// How many mutations are currently in flight.
    ///
    /// A depth rather than a flag, because M2-2 submits batches: a selected
    /// upgrade over three packages is three operations, and a flag would report
    /// "not mutating" the moment the first of them settled — re-opening the
    /// suppression window while brew was still writing (design D7).
    @ObservationIgnored private var depth = 0

    public private(set) var isMutating = false

    /// One element per mutation that reached a terminal outcome.
    @ObservationIgnored public let terminals: AsyncStream<Void>
    @ObservationIgnored private let continuation: AsyncStream<Void>.Continuation
    /// Every terminal, with identity when a receipt was registered for it.
    @ObservationIgnored public let settlements: AsyncStream<MutationTerminalEvent?>
    @ObservationIgnored private let settlementContinuation:
        AsyncStream<MutationTerminalEvent?>.Continuation

    public init() {
        (terminals, continuation) = AsyncStream<Void>.makeStream()
        (settlements, settlementContinuation) = AsyncStream<MutationTerminalEvent?>.makeStream()
    }

    public func begin() {
        depth += 1
        isMutating = true
    }

    /// Ends one mutation, whatever its outcome. Success and failure both
    /// invalidate the snapshot.
    ///
    /// The terminal is yielded **unconditionally**, even when the depth is
    /// already zero. That asymmetry is deliberate: the previous
    /// `guard isMutating` swallowed every end past the first, so a batch of N
    /// produced N−1 re-snapshots and the last mutation's effect could stay
    /// invisible until something else happened to invalidate the inventory. One
    /// wasted refresh is a far cheaper mistake than a stale list.
    public func end() {
        end(event: nil)
    }

    public func end(event: MutationTerminalEvent?) {
        depth = max(0, depth - 1)
        isMutating = depth > 0
        continuation.yield()
        settlementContinuation.yield(event)
    }

    public func shutdown() {
        continuation.finish()
        settlementContinuation.finish()
    }
}

/// Owns *when* the inventory is refreshed. The observer owns nothing but the
/// signal.
///
/// Three inputs, in order of trust:
///
/// 1. **Baseline** — launch and app activation. Always on, watcher or not. This
///    is the path that has to be correct; everything else is latency.
/// 2. **External change** — debounced on an injected clock, so a `brew upgrade`
///    writing for minutes produces one refresh at the end rather than hundreds
///    during.
/// 3. **Our own mutations** — suppressed while in flight, settled exactly once
///    at the terminal outcome.
@MainActor
public final class InstalledRefreshCoordinator {
    /// How long the watched roots must be quiet before a re-snapshot is taken.
    public static let defaultQuietWindow: Duration = .seconds(2)

    private let store: InstalledStore
    private let observer: (any InstalledChangeObserving)?
    private let mutations: InstalledMutationGate?
    private let clock: any Clock<Duration>
    private let quietWindow: Duration
    private let refreshRegistry: MutationRefreshRegistry?

    /// The installation the baseline last refreshed with. The debounced path
    /// reuses it, so a change signal can never refresh against a `brew` the user
    /// has already moved away from.
    private var installation: BrewInstallation?
    private var isDebouncing = false
    private var windowExtended = false

    /// The one debounce in flight, owned so `run()` can cancel it.
    ///
    /// It used to be a detached `Task` nobody held, which made the
    /// `Task.isCancelled` guards below unreachable — nothing ever cancelled it,
    /// so a torn-down coordinator could still refresh minutes later (design D8a).
    private var debounceTask: Task<Void, Never>?

    public init(
        store: InstalledStore,
        observer: (any InstalledChangeObserving)? = nil,
        mutations: InstalledMutationGate? = nil,
        refreshRegistry: MutationRefreshRegistry? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        quietWindow: Duration = InstalledRefreshCoordinator.defaultQuietWindow
    ) {
        self.store = store
        self.observer = observer
        self.mutations = mutations
        self.refreshRegistry = refreshRegistry
        self.clock = clock
        self.quietWindow = quietWindow
    }

    // MARK: - Baseline

    /// Refreshes now and records the installation the loop should use.
    ///
    /// Driven from launch and `NSApplication.didBecomeActiveNotification`,
    /// mirroring the existing `brewDetection.refresh()` wiring.
    public func refresh(using installation: BrewInstallation?) async {
        self.installation = installation
        await store.refresh(using: installation)
    }

    /// The same, straight from detection, so the absence reason survives.
    public func refresh(for detection: BrewDetectionState) async {
        installation = detection.installation
        await store.refresh(for: detection)
    }

    // MARK: - The loop

    /// Consumes change signals and mutation outcomes until cancelled.
    ///
    /// Owned by `LoopOwner` for the app's lifetime rather than by a scene, so
    /// closing the window that started the app does not stop it (design D10).
    public func run() async {
        // Strong `self` on purpose: the group is structured, so both children
        // end when `run()` does. A weak capture here trips the region-based
        // isolation checker and buys nothing — the coordinator outlives the
        // loop by construction.
        await withTaskGroup(of: Void.self) { group in
            if let observer {
                group.addTask {
                    for await _ in observer.changes() {
                        await self.changeSignalled()
                    }
                }
            }
            if let mutations {
                group.addTask { [settlements = mutations.settlements] in
                    for await event in settlements {
                        await self.mutationSettled(event)
                    }
                }
            }
        }

        // The group is structured, so both children are done here — but the
        // debounce is not one of them. Cancelling it is what stops a window
        // opened before teardown from refreshing after it.
        debounceTask?.cancel()
        debounceTask = nil
    }

    // MARK: - Debounce

    /// Reports an external change from a source attached after `run()` started.
    ///
    /// The app cannot build its watcher until detection has told it which prefix
    /// to watch, which is after this coordinator exists, so the watcher forwards
    /// its signals here instead of being handed to `run()`. Identical treatment:
    /// same quiet window, same suppression.
    public func changeDetected() {
        changeSignalled()
    }

    private func changeSignalled() {
        // Whatever is resident — and whatever is currently in flight — was
        // observed before this signal, so it can no longer answer for the world
        // after it. Marking is unconditional and spawns nothing; suppression
        // below only decides *when* the re-snapshot runs (design D8b).
        store.invalidate()

        // Our own writes. brew is mid-install; every one of these is noise, and
        // the terminal outcome will settle it once.
        if mutations?.isMutating == true { return }

        // Already waiting: extend the window instead of starting a second one.
        // That is what turns a multi-minute `brew upgrade` into one refresh.
        guard !isDebouncing else {
            windowExtended = true
            return
        }
        isDebouncing = true

        debounceTask = Task { @MainActor in
            await self.waitOutTheQuietWindow()
        }
    }

    private func waitOutTheQuietWindow() async {
        repeat {
            windowExtended = false
            try? await clock.sleep(for: quietWindow)
        } while windowExtended && !Task.isCancelled

        isDebouncing = false
        debounceTask = nil
        guard !Task.isCancelled else { return }

        // Suppression is re-checked *here*, where the re-snapshot would actually
        // start, and not only when the signal arrived and when the window
        // opened. A mutation that began inside an already-open window would
        // otherwise be re-snapshotted mid-install (design D8a — II10 sc5).
        // Dropping the refresh loses nothing: the mutation's terminal outcome
        // owes exactly one anyway.
        guard mutations?.isMutating != true else { return }

        await performRefresh()
    }

    /// One mutation reached a terminal outcome: brew has just changed what is
    /// installed, so the mark moves for the same reason a watcher signal moves
    /// it, and exactly one re-snapshot is owed.
    private func mutationSettled(_ event: MutationTerminalEvent?) async {
        store.invalidate()
        let result = await performRefresh(for: event)
        if let event, let refreshRegistry {
            await refreshRegistry.complete(event, with: result)
        }
    }

    @discardableResult
    private func performRefresh(for event: MutationTerminalEvent? = nil) async -> RefreshResult {
        guard let installation else { return .brewUnavailable }
        if let event, event.installationURL != installation.executableURL {
            return .installationChanged
        }
        await store.refresh(using: installation)
        if Task.isCancelled { return .cancelled }
        switch store.state {
        case .loaded: return .refreshed
        case .failed: return .failed
        case .brewAbsent: return .brewUnavailable
        case .idle, .loading: return .failed
        }
    }
}
