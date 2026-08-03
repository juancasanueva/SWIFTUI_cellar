import BrewProcess
import Foundation

/// Owns *when* the services list is refreshed.
///
/// `InstalledRefreshCoordinator`'s trust order with a visibility gate in front
/// of it:
///
/// 1. **Baseline** — launch, activation, and becoming visible. Always on.
/// 2. **Poll** — every 5 seconds, on an injected clock, and **only** while the
///    surface is visible.
/// 3. **Our own mutations** — suppressed while one is in flight, so a restart
///    in progress cannot flicker between statuses, and settled with exactly one
///    forced refresh at the terminal outcome.
///
/// **Trap, read from the code rather than assumed.** The poll must not be a
/// `LoopOwner` slot. `LoopOwner.start` guards on `loops[id] == nil` and a slot
/// "stays claimed for the rest of the launch even if its body returns"
/// (`LoopOwner.swift:20-23, 32`), so a poll registered there would run once and
/// never restart after the first hide. The poll task is owned **here**, created
/// by `setVisible(true)` and cancelled *and niled* by `setVisible(false)`.
/// `LoopOwner.start("services")` is reserved for the terminals consumer, which
/// genuinely is app-lifetime.
@MainActor
public final class ServicesRefreshCoordinator {
    /// How often the list is re-read while the surface is visible.
    ///
    /// Five seconds is the product ruling, and the cost is known: a
    /// `services list --json` measured 0.37 s at n = 1 service, which is why
    /// the poll reads the list rather than `info --all` (0.43 s and scaling
    /// with service count).
    public static let defaultInterval: Duration = .seconds(5)

    private let store: ServicesStore
    /// The gate for the **services** domain, not the installed one.
    ///
    /// It is a second instance of the shipped `InstalledMutationGate` type
    /// rather than a new type: that type is already a depth counter plus a
    /// `terminals` stream with nothing installed-specific in its body. The
    /// rename it now deserves is registered as debt rather than taken here
    /// (design D2).
    private let mutations: InstalledMutationGate?
    private let clock: any Clock<Duration>
    private let interval: Duration

    /// The installation the baseline last refreshed with. The poll reuses it,
    /// so a tick can never probe a `brew` the user has already moved away from.
    private var installation: BrewInstallation?

    /// The two reported halves of "the surface is visible".
    ///
    /// SM3 names two reasons it stops being so — the window was hidden, or the
    /// section was deselected — and they are observed in two different places:
    /// `scenePhase` in the app, `onAppear`/`onDisappear` in the view. Folding
    /// them into one setter would let whichever reported last overrule the
    /// other, so a hidden window with Services still selected would keep
    /// polling. The gate is their conjunction.
    private var isSectionVisible = false
    private var isAppActive = true

    private var isVisible: Bool { isSectionVisible && isAppActive }

    /// The one poll in flight, owned so hiding can end it.
    ///
    /// Niled as well as cancelled: a cancelled-but-resident task would make
    /// `isPolling` lie and would make the next show believe a loop was already
    /// running.
    private var pollTask: Task<Void, Never>?

    public init(
        store: ServicesStore,
        mutations: InstalledMutationGate? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        interval: Duration = ServicesRefreshCoordinator.defaultInterval
    ) {
        self.store = store
        self.mutations = mutations
        self.clock = clock
        self.interval = interval
    }

    // MARK: - The terminals consumer

    /// Consumes service-mutation terminals until cancelled.
    ///
    /// Owned by `LoopOwner.start("services")` for the app's lifetime, matching
    /// `loops.start("installed")`. **Only this** belongs in a `LoopOwner` slot:
    /// a slot stays claimed for the rest of the launch even after its body
    /// returns, which is right for an app-lifetime consumer and fatal for the
    /// poll — see the trap in this type's documentation.
    public func run() async {
        guard let mutations else { return }
        for await _ in mutations.terminals {
            await mutationSettled()
        }
    }

    /// One service mutation reached a terminal outcome: brew has just changed
    /// what launchd is running, so exactly one refresh is owed — success,
    /// failure and cancellation alike, and whether or not the surface is
    /// visible (SM8).
    ///
    /// `invalidate()` first, for the reason `InstalledRefreshCoordinator` does
    /// it: the store coalesces same-request refreshes, so without moving the
    /// mark this refresh could be answered by a poll acquisition that started
    /// *before* the mutation finished — a list from before the change, adopted
    /// after it.
    private func mutationSettled() async {
        store.invalidate()
        await performRefresh()
    }

    /// Whether a poll loop is running right now.
    ///
    /// Public because "no poll loop is running" is a claim SM11 makes about the
    /// brew-absent state, and a claim worth asserting directly rather than
    /// inferring from a probe count that would also be zero if the loop were
    /// running and merely failing.
    public var isPolling: Bool { pollTask != nil }

    // MARK: - Baseline

    /// Refreshes now and records the installation the poll should use.
    public func refresh(using installation: BrewInstallation?) async {
        self.installation = installation
        await store.refresh(using: installation)
        syncPolling()
    }

    /// The same, straight from detection, so the absence reason survives.
    public func refresh(for detection: BrewDetectionState) async {
        installation = detection.installation
        await store.refresh(for: detection)
        syncPolling()
    }

    // MARK: - Visibility

    /// Reports whether the services section is the one being shown.
    ///
    /// Visibility is **reported** by the UI, never decided by it: `onAppear`
    /// and `onDisappear` cover section deselection and window close. Both
    /// arrive more than once for one real transition, so this is idempotent —
    /// a repeated show must not run a second baseline or start a second loop.
    public func setVisible(_ visible: Bool) {
        guard visible != isSectionVisible else { return }
        isSectionVisible = visible
        applyVisibility()
    }

    /// Reports whether the app itself is in the foreground, from `scenePhase`.
    ///
    /// A window hidden with ⌘H while Services is still the selected section is
    /// not a visible surface, and must cost zero probes.
    public func setActive(_ active: Bool) {
        guard active != isAppActive else { return }
        isAppActive = active
        applyVisibility()
    }

    private func applyVisibility() {
        if isVisible {
            startPolling()
        } else {
            stopPolling()
        }
    }

    // MARK: - The poll

    /// Starts the loop when there is something to poll.
    ///
    /// With no installation there is no loop at all — not a loop that ticks and
    /// finds nothing. SM11 asks for exactly that: with brew absent, "no poll
    /// loop is running".
    private func startPolling() {
        guard pollTask == nil, installation != nil else { return }
        pollTask = Task { @MainActor [weak self] in
            await self?.poll()
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Keeps the loop's existence consistent with what detection now reports.
    ///
    /// Detection commonly resolves *after* the surface is already showing —
    /// that is the ordinary launch order, not an edge case — so brew appearing
    /// has to be able to start the loop, and brew disappearing has to stop it.
    private func syncPolling() {
        guard isVisible else { return }
        if installation == nil {
            stopPolling()
        } else {
            startPolling()
        }
    }

    private func poll() async {
        // Becoming visible is itself a refresh: a surface that appeared showing
        // a list from before the last hide would be showing the past.
        await performRefresh()

        while !Task.isCancelled {
            try? await clock.sleep(for: interval)
            // Re-checked after the sleep rather than only before it: the hide
            // that ends this loop lands while it is suspended here.
            guard !Task.isCancelled, isVisible else { return }

            // Our own writes. A restart is a stop and a start, so a tick landing
            // between them would show the user a status that is true for a
            // fraction of a second and reads as a flicker. The terminal owes
            // exactly one refresh anyway, so the tick is dropped rather than
            // deferred — `continue`, not `return`: the loop is suppressed for
            // the duration, not ended by it (SM3).
            guard mutations?.isMutating != true else { continue }
            await performRefresh()
        }
    }

    private func performRefresh() async {
        guard let installation else { return }
        await store.refresh(using: installation)
    }
}
