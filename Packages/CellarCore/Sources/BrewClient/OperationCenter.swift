import BrewProcess
import Catalog
import Foundation
import Observation

/// The store that turns a typed command into a queue item and drives everything
/// downstream of it.
///
/// Built on the `InstalledStore` exemplar: one `@MainActor @Observable` class,
/// with process work happening below it in SwiftPM's default `nonisolated`
/// world. Per submission it holds an `ActivityItem`, starts one task draining
/// `operation.lines` into that item's bounded ring, awaits `exit()`, classifies
/// (design D5) and settles the mutation gate (D7).
///
/// The runner arrives *after* detection, so `attach(installation:)` builds it. A
/// submission with no runner is a terminal item reporting unavailable rather
/// than a silent no-op, and repointing `brew` builds a new runner while
/// in-flight items keep the old one alive until they settle (D4,
/// package-mutation PM7).
@MainActor
@Observable
public final class OperationCenter {
    /// Every item this session, oldest first. Terminal items stay enumerable
    /// for the rest of the session (operation-activity OA1); persistence across
    /// launches is M2-3.
    public private(set) var items: [ActivityItem] = []

    /// The confirmation currently awaiting an answer, if any.
    public private(set) var pendingConfirmation: ConfirmationRequest?

    @ObservationIgnored private let gate: InstalledMutationGate?
    @ObservationIgnored private let launcherFactory: (BrewInstallation) -> any ProcessLaunching
    @ObservationIgnored private var runner: BrewRunner?
    @ObservationIgnored private var installation: BrewInstallation?

    public init(
        gate: InstalledMutationGate? = nil,
        launcherFactory: @escaping (BrewInstallation) -> any ProcessLaunching = { _ in
            SystemProcessLauncher()
        }
    ) {
        self.gate = gate
        self.launcherFactory = launcherFactory
    }

    // MARK: - Attachment

    /// Whether mutations can run at all right now.
    public var isAvailable: Bool { runner != nil }

    /// Why they cannot, when they cannot. Read-only guidance, never an error:
    /// affordances go unavailable rather than failing at spawn time
    /// (package-mutation PM7).
    public var unavailableGuidance: String? {
        isAvailable
            ? nil
            : "Homebrew is not available, so package changes are turned off. "
                + "Check the brew location in Settings."
    }

    /// Points the centre at an installation, building the runner it needs.
    ///
    /// Called from the detection wiring, so mutations become available the
    /// moment brew does — with no restart. Repointing builds a **new** runner
    /// and leaves the previous one alive: each in-flight item's drain task holds
    /// its own `BrewOperation`, which holds the runner that spawned it, so the
    /// old queue finishes on its own terms.
    public func attach(installation: BrewInstallation?) {
        guard let installation else {
            runner = nil
            self.installation = nil
            return
        }
        guard installation.executableURL != self.installation?.executableURL else { return }

        self.installation = installation
        let runner = BrewRunner(
            installation: installation,
            launcher: launcherFactory(installation)
        )
        self.runner = runner
        watchQueue(of: runner)
    }

    /// Merges one runner's queue snapshots into the items it owns.
    ///
    /// One watcher per attached runner, all writing into the same items, so a
    /// `brew` repointed mid-flight does not strand the operations still running
    /// on the previous runner. The watcher ends when the centre does.
    private func watchQueue(of runner: BrewRunner) {
        Task { [weak self] in
            for await snapshot in runner.queue {
                guard let self else { break }
                self.apply(snapshot)
            }
        }
    }

    /// The one place a queue phase is written onto an item, so the summary and
    /// the detail listing are reading the same projection (OA5).
    ///
    /// Two guards, both load-bearing since M2-3:
    ///
    /// - A phase is written only for an id the snapshot actually carries, so an
    ///   operation whose execution-layer record has been **retired** (D6 R3)
    ///   simply stops receiving updates rather than being reset. Its `isTerminal`
    ///   is decided by its `outcome`, which the centre owns, so the item stays
    ///   enumerable for the session with its identity, argv and outcome intact
    ///   (operation-activity OA1).
    /// - A phase is written only when it **differs**. `queuePhase` is observed,
    ///   and the runner yields a snapshot per real transition; without this the
    ///   centre would still wake every observer of every item on every yield
    ///   (brew-execution BE1 sc10).
    private func apply(_ snapshot: QueueSnapshot) {
        let phases = Dictionary(
            snapshot.operations.map { ($0.id, $0.phase) },
            uniquingKeysWith: { _, newest in newest }
        )
        for item in items {
            guard let operationID = item.operationID,
                  let phase = phases[operationID],
                  item.queuePhase != phase
            else { continue }
            item.queuePhase = phase
        }
    }

    // MARK: - Submitting

    /// Submits one command and returns the item tracking it.
    ///
    /// Never throws and never blocks. With no runner attached the item comes
    /// back already terminal and already explained, because a silent no-op
    /// would leave the user watching for something that will never happen.
    @discardableResult
    public func submit(_ command: MutationCommand) -> ActivityItem {
        let item = ActivityItem(id: UUID(), command: command)
        items.append(item)

        guard let runner else {
            item.queuePhase = .terminal(BrewExit(status: 127, reason: .exited), fault: nil)
            item.settle(.launchFailed)
            return item
        }

        // The gate opens per submission, not per batch, so `isMutating` stays
        // true for the whole of a fan-out — a quiet window between two queued
        // mutations wastes no refresh — while N terminals still produce exactly
        // N re-snapshots (design D7).
        gate?.begin()

        // Marked before the task is created, so a cancel arriving between here
        // and `run(_:for:on:)` is replayed rather than settling an operation
        // that is about to exist (design D10).
        item.isStartInFlight = true
        Task { [weak self] in
            await self?.run(command, for: item, on: runner)
        }
        return item
    }

    /// Expands a selection into one ordinary upgrade per package.
    ///
    /// There is no `upgradeSelected` command: the fan-out happens here, at the
    /// call site, so every selected package gets its own queue item, log,
    /// copy-command, cancel and terminal outcome — and a mid-batch failure
    /// attributes to exactly one package (design D1, user ruling 2026-08-02).
    @discardableResult
    public func submitUpgrades(for ids: [PackageID]) -> [ActivityItem] {
        ids.compactMap { id in
            MutationCommand.naming(id, MutationCommand.upgrade).map { submit($0) }
        }
    }

    /// The same, over everything the inventory reports as outdated.
    ///
    /// The outdated set comes from `InstalledInventory` rather than being
    /// re-derived, so the exclusion of self-updating casks agrees with the
    /// inventory's own derivation (M2-1 II4/II5). Pinned packages are excluded
    /// too and **no unpin is submitted on their behalf**: brew's own defaults
    /// skip them, and defeating that would upgrade something the user
    /// explicitly held back (package-mutation PM2).
    @discardableResult
    public func submitUpgradesForOutdated(in inventory: InstalledInventory) -> [ActivityItem] {
        submitUpgrades(
            for: inventory.packages
                .filter { $0.isOutdated && !$0.isPinned }
                .map(\.id)
        )
    }

    // MARK: - One operation, start to finish

    private func run(
        _ command: MutationCommand,
        for item: ActivityItem,
        on runner: BrewRunner
    ) async {
        // Cancelled between `submit` and here: never spawn it.
        guard !item.isCancelRequested else {
            item.isStartInFlight = false
            finish(item, with: .cancelled)
            return
        }

        let operation: BrewOperation
        do {
            operation = try await runner.start(command.brewCommand)
        } catch {
            item.isStartInFlight = false
            finish(item, with: .launchFailed)
            return
        }
        item.operationID = operation.id
        // The item owns the handle from here until it settles: cancel reaches
        // the runner that produced it, and the execution layer's record cannot
        // be retired underneath a caller that can still ask about it (D6, D10).
        item.operation = operation
        item.isStartInFlight = false

        // A cancel that arrived while the submission was in flight has nothing
        // to act on yet, so it is replayed here rather than lost.
        if item.isCancelRequested {
            await operation.cancel()
        }

        // One drain task per submission. Reading lines to exhaustion before
        // asking for the exit preserves the runner's ordering contract: the
        // result is never delivered before its output is observable.
        for await line in operation.lines {
            item.append(line)
        }

        let exit = await operation.exit()
        let fault = await operation.fault()
        finish(item, with: .classify(exit: exit, fault: fault, log: item.log))
    }

    /// Settles an item exactly once and pays the re-snapshot it owes.
    ///
    /// Idempotent on purpose: a cancel and a terminal exit can race, and paying
    /// the gate twice for one operation would produce 2N re-snapshots for a
    /// batch of N.
    private func finish(_ item: ActivityItem, with outcome: MutationOutcome) {
        guard item.outcome == nil else { return }
        item.settle(outcome)
        // Every terminal outcome owes exactly one re-snapshot — success, both
        // typed failures, a plain failure and a cancellation alike (PM6).
        gate?.end()
    }

    // MARK: - Cancel

    /// Cancels an item, whether it is pending or running.
    ///
    /// A pending item resolves without ever spawning; a running one gets
    /// SIGINT → SIGTERM and never SIGKILL. Both guarantees are the runner's
    /// (M1 D4) and this only exposes them. Queue control is cancel-only: there
    /// is deliberately no reorder and no remove (product Q6, and the FIFO
    /// invariant stays immutable).
    ///
    /// Delivery goes through the item's **own** handle rather than through the
    /// centre's current runner (design D10). A `brew` that has been detached or
    /// repointed since submission therefore changes nothing: the operation is
    /// signalled on the runner that spawned it, and the item settles as
    /// cancelled only when that process actually stops — so the gate is paid,
    /// and the re-snapshot forced, exactly once and only at the real terminal
    /// outcome (operation-activity OA4).
    public func cancel(_ item: ActivityItem) {
        guard item.isCancellable else { return }
        item.isCancelRequested = true

        if let operation = item.operation {
            Task { await operation.cancel() }
            return
        }
        // No handle. If a start is in flight, `run(_:for:on:)` replays the
        // request — it guards at entry and again after start. Only a submission
        // that never had a runner is terminal here.
        if !item.isStartInFlight {
            finish(item, with: .cancelled)
        }
    }

    // MARK: - Confirmation (design D6)

    /// A destructive command waiting for an explicit yes.
    ///
    /// It carries the **typed** command, so confirming submits exactly what was
    /// shown: there is no path from the rendered string back to argv.
    public struct ConfirmationRequest: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let command: MutationCommand

        /// The exact command that will run, character for character.
        public var displayCommand: String { command.displayCommand }
    }

    /// Asks for confirmation, when this command needs one.
    ///
    /// Returns `nil` for everything that does not — install, reinstall,
    /// upgrade, upgrade-all, pin and unpin — so a caller can treat "no request"
    /// as "submit directly" without restating the rule (product Q2).
    public func request(_ command: MutationCommand) -> ConfirmationRequest? {
        guard command.requiresConfirmation else { return nil }
        let request = ConfirmationRequest(id: UUID(), command: command)
        pendingConfirmation = request
        return request
    }

    /// Submits the confirmed command. Nothing was enqueued before this point.
    @discardableResult
    public func confirm(_ request: ConfirmationRequest) -> ActivityItem? {
        guard pendingConfirmation == request else { return nil }
        pendingConfirmation = nil
        return submit(request.command)
    }

    /// Spawns nothing, enqueues nothing, leaves the inventory untouched.
    public func decline(_ request: ConfirmationRequest) {
        guard pendingConfirmation == request else { return }
        pendingConfirmation = nil
    }

    // MARK: - Summary (operation-activity OA5)

    /// What an always-visible indicator needs, and nothing more.
    ///
    /// `@MainActor` rather than `Sendable`: it holds the live `ActivityItem`, so
    /// the bar and the drawer are looking at one object rather than at a copy
    /// that can fall behind it.
    @MainActor
    public struct Summary {
        public let isBusy: Bool
        public let running: ActivityItem?
        public let pendingCount: Int

        /// The running operation's command, for the collapsed bar.
        public var runningCommand: String? { running?.displayCommand }
    }

    /// The summary, derived from the very same items the detail listing shows,
    /// so the two cannot disagree about what is running or how much is queued.
    public var summary: Summary {
        Summary(
            isBusy: items.contains { !$0.isTerminal },
            running: items.first(where: \.isRunning),
            pendingCount: items.count(where: \.isPending)
        )
    }
}
