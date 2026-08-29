import BrewProcess
import Foundation

/// Owns *when* npm is read.
///
/// The fifth coordinator, and the first whose two reads are on **two different
/// cadences**. That split is the whole reason it exists rather than npm joining
/// `InstalledRefreshCoordinator`:
///
/// - `npm ls -g --json --depth=0` is a local directory read. It is cheap, so it
///   runs on detection, on every npm terminal outcome and on app activation —
///   the same baseline brew's inventory gets.
/// - `npm outdated -g --json` opens a connection to the registry for every
///   global package. It runs when the source becomes detected, on every npm
///   terminal outcome, on an explicit user refresh, and then on a timer with a
///   one-hour floor. **Never on activation.** A user who ⌘-tabs twenty times an
///   hour would otherwise make twenty rounds of registry requests, which is the
///   exact cost `npm-source` names ("It MUST NOT be coupled to window focus,
///   app activation or the brew inventory refresh, because it needs the network
///   and can be slow"; design D10).
///
/// Two further rules the timer alone cannot express:
///
/// - **Coalescing.** A check already in flight absorbs every request that
///   arrives while it runs, so a terminal outcome landing during the periodic
///   tick costs one round-trip rather than two. A request raised after
///   settlement is a new question and runs fresh.
/// - **No tight retry.** A failed check is left failed. Nothing here reschedules
///   it; the next tick retries it, which is what keeps one offline machine from
///   hammering an unreachable registry.
@MainActor
public final class NpmRefreshCoordinator {
    /// The floor between two registry checks.
    ///
    /// One hour, and a floor rather than a schedule: a terminal outcome or an
    /// explicit refresh may check sooner, because both are moments where the
    /// answer is known to have changed or the user asked for it.
    public static let defaultOutdatedInterval: Duration = .seconds(3_600)

    private let store: NpmStore
    /// The **npm** gate, not the installed one. A brew terminal reaches this
    /// coordinator through no path at all.
    private let mutations: InstalledMutationGate?
    private let refreshRegistry: MutationRefreshRegistry?
    private let clock: any Clock<Duration>
    private let outdatedInterval: Duration

    /// The npm the cadence currently reads. `nil` whenever the source is off,
    /// absent or invalid — four different things to say and one thing to do.
    private var environment: NpmEnvironment?

    /// The one registry check in flight, held so overlapping requests can join
    /// it rather than open a second connection.
    ///
    /// Niled on settlement, so the *next* request is genuinely a new one.
    private var outdatedCheck: Task<Void, Never>?

    /// The periodic loop, owned here rather than in a `LoopOwner` slot for the
    /// reason `ServicesRefreshCoordinator` documents: a slot stays claimed for
    /// the rest of the launch, so a loop registered there could never restart
    /// after the source was switched off and on again.
    private var periodicTask: Task<Void, Never>?

    public init(
        store: NpmStore,
        mutations: InstalledMutationGate? = nil,
        refreshRegistry: MutationRefreshRegistry? = nil,
        clock: any Clock<Duration> = ContinuousClock(),
        outdatedInterval: Duration = NpmRefreshCoordinator.defaultOutdatedInterval
    ) {
        self.store = store
        self.mutations = mutations
        self.refreshRegistry = refreshRegistry
        self.clock = clock
        self.outdatedInterval = outdatedInterval
    }

    // MARK: - Detection

    /// Reacts to a detection change, including the toggle being turned on or off.
    ///
    /// Detection is the only trigger that can *start* or *stop* the cadence, so
    /// enabling the source begins reading without a relaunch and disabling it
    /// stops every future tick — `npm-source`'s "turning it off MUST clear npm
    /// inventory state and stop the npm refresh cadence without a relaunch".
    public func apply(_ detection: NpmDetectionState) async {
        guard let environment = detection.environment else {
            self.environment = nil
            stopPeriodicCheck()
            store.withdraw()
            return
        }

        let isNewNpm = self.environment != environment
        self.environment = environment
        await store.refreshListing(using: environment)
        // A different npm is a different set of globals *and* a different
        // registry answer, so the schedule restarts rather than waiting out the
        // previous npm's remaining hour.
        if isNewNpm { stopPeriodicCheck() }
        startPeriodicCheck()
    }

    // MARK: - Activation

    /// The app came to the front.
    ///
    /// Re-reads the local listing and **nothing else**. This is the method the
    /// independence requirement is really about: it must never reach the
    /// registry, however often it is called.
    public func activate() async {
        guard let environment else { return }
        await store.refreshListing(using: environment)
    }

    // MARK: - Explicit refresh

    /// The user asked. Both reads, and the check is allowed to run ahead of the
    /// timer because a person is waiting for it.
    public func refresh() async {
        guard let environment else { return }
        await store.refreshListing(using: environment)
        await checkOutdated()
    }

    // MARK: - Terminals

    /// Consumes npm terminal outcomes until cancelled.
    ///
    /// Success, failure and cancellation alike: what an npm mutation *attempted*
    /// is what makes the previous answer untrustworthy, not whether it worked.
    public func run() async {
        guard let mutations else { return }
        for await event in mutations.settlements {
            await terminalSettled(event)
        }
    }

    private func terminalSettled(_ event: MutationTerminalEvent?) async {
        let result = await performTerminalRefresh(for: event)
        if let event, let refreshRegistry {
            await refreshRegistry.complete(event, with: result)
        }
    }

    private func performTerminalRefresh(for event: MutationTerminalEvent?) async -> RefreshResult {
        guard let environment else { return .brewUnavailable }
        // The npm the mutation ran against is the npm whose globals it changed.
        // A user who switched npm mid-flight gets no refresh rather than a
        // refresh of the wrong prefix.
        if let event, event.installationURL != environment.executableURL {
            return .installationChanged
        }
        await store.refreshListing(using: environment)
        await checkOutdated()
        return .refreshed
    }

    // MARK: - The periodic check

    private func startPeriodicCheck() {
        guard periodicTask == nil, environment != nil else { return }
        periodicTask = Task { @MainActor [weak self] in
            await self?.periodicCheck()
        }
    }

    private func stopPeriodicCheck() {
        periodicTask?.cancel()
        periodicTask = nil
    }

    /// Becoming detected owes the first check; every interval after that owes
    /// another.
    private func periodicCheck() async {
        await checkOutdated()

        while !Task.isCancelled {
            try? await clock.sleep(for: outdatedInterval)
            // Re-checked after the sleep as well as before it: the toggle that
            // ends this loop lands while it is suspended here.
            guard !Task.isCancelled, environment != nil else { return }
            await checkOutdated()
        }
    }

    // MARK: - The one registry call

    /// Runs the outdated check, or joins the one already running.
    ///
    /// Every path that may reach the registry goes through here, which is what
    /// makes coalescing a property of the type rather than of each caller
    /// remembering to ask.
    private func checkOutdated() async {
        if let outdatedCheck {
            await outdatedCheck.value
            return
        }
        guard let environment else { return }

        let task = Task { @MainActor [store] in
            await store.refreshOutdated(using: environment)
        }
        outdatedCheck = task
        await task.value
        outdatedCheck = nil
    }

    // MARK: - Teardown

    /// Ends the cadence. Nothing is read after this until detection reports
    /// again.
    public func stop() {
        stopPeriodicCheck()
        outdatedCheck?.cancel()
        outdatedCheck = nil
    }
}
