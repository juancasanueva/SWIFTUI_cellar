import BrewProcess
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

/// Whether Cellar itself is currently changing what is installed.
///
/// M2-2 owns mutations; this is the seam it will drive. Signals emitted while a
/// mutation runs are noise from our own work — brew writes continuously through
/// an install — so they are suppressed and settled once at the end.
@MainActor
@Observable
public final class InstalledMutationGate {
    public private(set) var isMutating = false

    /// One element per mutation that reached a terminal outcome.
    @ObservationIgnored public let terminals: AsyncStream<Void>
    @ObservationIgnored private let continuation: AsyncStream<Void>.Continuation

    public init() {
        (terminals, continuation) = AsyncStream<Void>.makeStream()
    }

    public func begin() {
        isMutating = true
    }

    /// Ends the mutation, whatever its outcome. Success and failure both
    /// invalidate the snapshot.
    public func end() {
        guard isMutating else { return }
        isMutating = false
        continuation.yield()
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

    /// The installation the baseline last refreshed with. The debounced path
    /// reuses it, so a change signal can never refresh against a `brew` the user
    /// has already moved away from.
    private var installation: BrewInstallation?
    private var isDebouncing = false
    private var windowExtended = false

    public init(
        store: InstalledStore,
        observer: (any InstalledChangeObserving)? = nil,
        mutations: InstalledMutationGate? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        quietWindow: Duration = InstalledRefreshCoordinator.defaultQuietWindow
    ) {
        self.store = store
        self.observer = observer
        self.mutations = mutations
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
                group.addTask { [terminals = mutations.terminals] in
                    for await _ in terminals {
                        await self.performRefresh()
                    }
                }
            }
        }
    }

    // MARK: - Debounce

    private func changeSignalled() {
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

        Task { @MainActor in
            await self.waitOutTheQuietWindow()
        }
    }

    private func waitOutTheQuietWindow() async {
        repeat {
            windowExtended = false
            try? await clock.sleep(for: quietWindow)
        } while windowExtended && !Task.isCancelled

        isDebouncing = false
        guard !Task.isCancelled else { return }
        await performRefresh()
    }

    private func performRefresh() async {
        guard let installation else { return }
        await store.refresh(using: installation)
    }
}
