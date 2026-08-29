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
    ///
    /// A **computed getter with no setter at all** — strictly stronger than the
    /// `private(set)` it restores, because there is no setter left to widen a
    /// second time. The value lives in a nested `@Observable` box, and
    /// observation propagates through this read, so the sheet still updates
    /// (design D6 — register item VS2).
    public var pendingConfirmation: ConfirmationRequest? { confirmations.pending }

    /// The one writable position, reachable only from inside this type.
    ///
    /// `@ObservationIgnored` because the box publishes its own changes;
    /// observing the reference as well would wake every observer twice.
    @ObservationIgnored let confirmations = ConfirmationBox()

    /// The only writer, and deliberately a method rather than a property setter.
    ///
    /// The confirmation surface lives one file over, which is exactly why the
    /// property was widened to `internal(set)` in the first place. A
    /// module-internal *method* gives that file what it needs without giving the
    /// rest of the module the ability to answer a confirmation on the user's
    /// behalf.
    func setPendingConfirmation(_ request: ConfirmationRequest?) {
        if let request {
            confirmations.present(request)
        } else if let pending = confirmations.pending {
            confirmations.consume(pending)
        }
    }

    /// The services-scoped duplicate-submit guard.
    ///
    /// Internal rather than private because the services submit path lives in
    /// `OperationCenterServices.swift`. Unlike the confirmation box, nothing
    /// about this is a security position — it holds the most recent item per
    /// service name and answers "is that one still in flight?", which any file
    /// in the module could compute from `items` anyway.
    @ObservationIgnored let serviceSubmissions = ServiceSubmissionGuard()

    /// The state domains this centre can invalidate, and the gate for each.
    ///
    /// A command opens only the ones its own `invalidates` scope names, so a
    /// family that cannot change the installed set neither suppresses external
    /// change signals nor forces an inventory re-snapshot (design D2).
    @ObservationIgnored private let gates: MutationGates?
    /// Where a terminal outcome's durable record goes.
    ///
    /// Defaulted to the no-op so an app with no store configured behaves exactly
    /// as it did before history existed — and so reverting the feature is one
    /// injection away (installation-history IH7 sc1).
    @ObservationIgnored private let history: any HistoryRecording
    /// How a runner for one executable gets its process seam.
    ///
    /// Keyed on the **executable URL** rather than on a `BrewInstallation`,
    /// because the centre now builds runners for two sources and npm has no
    /// installation to hand over. Every shipped call site passes `{ _ in … }`
    /// and is unaffected.
    @ObservationIgnored private let launcherFactory: (URL) -> any ProcessLaunching
    /// One runner per source, built as each source becomes available.
    ///
    /// Two runners rather than one runner told which executable to spawn: the
    /// runner's FIFO, cancel escalation and retention are per-instance, and a
    /// single instance spawning both would make an npm mutation wait behind a
    /// ten-minute `brew upgrade` for reasons brew's queue knows nothing about.
    /// Serialisation *across* sources is a separate, deliberate rule, imposed at
    /// this level rather than inside either runner (design D13).
    @ObservationIgnored private var runners: [PackageSource: BrewRunner] = [:]
    /// What each attached runner spawns, so an item can record the executable
    /// its refresh receipt belongs to.
    @ObservationIgnored private var executables: [PackageSource: URL] = [:]
    @ObservationIgnored private var installation: BrewInstallation?
    @ObservationIgnored private let refreshRegistry: MutationRefreshRegistry?
    @ObservationIgnored lazy var forceRecovery: ForceDenialRecoveryCoordinator? = refreshRegistry.map {
        ForceDenialRecoveryCoordinator(registry: $0, confirmations: confirmations)
    }
    @ObservationIgnored var forceRecoveryContexts: [UUID: ForceRecoveryContext] = [:]

    /// The chain gate of the most recently submitted mutation.
    ///
    /// One mutation at a time **across sources** (`package-mutation`). Each
    /// runner already serialises its own, but two runners know nothing about
    /// each other, so the rule has to be imposed where both are visible — here.
    ///
    /// Invariant, and the reason this is read and written with no `await`
    /// between: the tail is captured and replaced synchronously inside `perform`,
    /// so however submissions interleave, the order they were submitted in is
    /// the order they run in. It is the same invariant `BrewRunner`'s own gate
    /// holds, one level up (design D13).
    @ObservationIgnored private var mutationTail: Task<Void, Never>?

    public init(
        gates: MutationGates,
        history: any HistoryRecording = NoHistoryRecording(),
        refreshRegistry: MutationRefreshRegistry? = nil,
        launcherFactory: @escaping (URL) -> any ProcessLaunching = { _ in
            SystemProcessLauncher()
        }
    ) {
        self.gates = gates
        self.history = history
        self.refreshRegistry = refreshRegistry
        self.launcherFactory = launcherFactory
    }

    /// The single-domain form, kept so every shipped test and the app's
    /// composition root compile unchanged.
    ///
    /// It is exactly `MutationGates([(.installedInventory, gate)])`, which is
    /// what the centre did unconditionally before there was more than one
    /// domain. `gates` has no default here precisely so this initialiser stays
    /// the one an argument-free `OperationCenter()` resolves to.
    public init(
        gate: InstalledMutationGate? = nil,
        history: any HistoryRecording = NoHistoryRecording(),
        refreshRegistry: MutationRefreshRegistry? = nil,
        launcherFactory: @escaping (URL) -> any ProcessLaunching = { _ in
            SystemProcessLauncher()
        }
    ) {
        gates = gate.map { MutationGates(installed: $0) }
        self.history = history
        self.refreshRegistry = refreshRegistry
        self.launcherFactory = launcherFactory
    }

    // MARK: - Attachment

    /// Whether Homebrew mutations can run at all right now.
    ///
    /// Kept source-free so every shipped call site reads exactly what it read
    /// before. Homebrew is what it always meant, and stating that here is what
    /// keeps "a Homebrew command MUST NOT be made unavailable because npm is
    /// absent" true by construction (package-mutation PM7 as modified).
    public var isAvailable: Bool { isAvailable(for: .homebrew) }

    /// Whether `source`'s mutations can run right now.
    public func isAvailable(for source: PackageSource) -> Bool {
        runners[source] != nil
    }

    /// Why they cannot, when they cannot. Read-only guidance, never an error:
    /// affordances go unavailable rather than failing at spawn time
    /// (package-mutation PM7).
    public var unavailableGuidance: String? { unavailableGuidance(for: .homebrew) }

    /// The same guidance, per source, naming the source the user would have to
    /// fix — never the other one.
    public func unavailableGuidance(for source: PackageSource) -> String? {
        guard !isAvailable(for: source) else { return nil }
        return switch source {
        case .homebrew:
            "Homebrew is not available, so package changes are turned off. "
                + "Check the brew location in Settings."
        case .npm:
            "npm is not available, so npm package changes are turned off. "
                + "Turn the npm source on in Settings and check its location there."
        }
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
            runners[.homebrew] = nil
            executables[.homebrew] = nil
            self.installation = nil
            return
        }
        guard installation.executableURL != self.installation?.executableURL else { return }

        self.installation = installation
        executables[.homebrew] = installation.executableURL
        let runner = BrewRunner(
            installation: installation,
            launcher: launcherFactory(installation.executableURL)
        )
        runners[.homebrew] = runner
        watchQueue(of: runner)
    }

    /// Points the centre at a detected npm, on exactly the terms brew is
    /// attached: mutations become available the moment detection resolves, with
    /// no relaunch, and detaching removes only this source's runner.
    ///
    /// The npm runner is the **generalised** `BrewRunner` — same FIFO, same
    /// SIGINT→SIGTERM escalation, same retention — handed npm's executable and
    /// npm's environment composer rather than brew's (`brew-execution`,
    /// design D4).
    public func attach(npm environment: NpmEnvironment?) {
        guard let environment else {
            runners[.npm] = nil
            executables[.npm] = nil
            return
        }
        guard environment.executableURL != executables[.npm] else { return }

        executables[.npm] = environment.executableURL
        let runner = BrewRunner(
            executableURL: environment.executableURL,
            environment: { _ in environment.processEnvironment() },
            launcher: launcherFactory(environment.executableURL)
        )
        runners[.npm] = runner
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
    ///
    /// `versions` is the transition Cellar **intends**, captured here rather
    /// than observed at the terminal: the durable record then says what was
    /// attempted, and its outcome says whether it happened (design D7).
    /// The concrete overload exists so a leading-dot literal still resolves.
    ///
    /// `operations.submit(.upgradeAll)` cannot infer a contextual base against a
    /// generic parameter, so without this the app target would have to spell the
    /// type at every call site. It forwards immediately; there is one submission
    /// path, not two (design D1).
    @discardableResult
    public func submit(
        _ command: MutationCommand,
        versions: VersionTransition? = nil
    ) -> ActivityItem {
        perform(command, versions: versions, authorizer: AllowMutationLaunch(), refreshToken: nil)
    }

    @discardableResult
    public func submit(
        _ command: some BrewMutating,
        versions: VersionTransition? = nil
    ) -> ActivityItem {
        perform(command, versions: versions, authorizer: AllowMutationLaunch(), refreshToken: nil)
    }

    @discardableResult
    public func submit(
        _ command: some BrewMutating,
        versions: VersionTransition? = nil,
        authorizer: any MutationLaunchAuthorizing,
        refreshToken: MutationOperationToken? = nil
    ) -> ActivityItem {
        perform(
            command,
            versions: versions,
            authorizer: authorizer,
            refreshToken: refreshToken
        )
    }

    /// The one submission path. Both overloads above forward here unchanged, so
    /// "exactly one `begin()` per submit and one `end()` per finish" stays an
    /// invariant of *submission* rather than of whichever spelling was used.
    @discardableResult
    private func perform(
        _ command: some BrewMutating,
        versions: VersionTransition?,
        authorizer: any MutationLaunchAuthorizing,
        refreshToken: MutationOperationToken?
    ) -> ActivityItem {
        let item = ActivityItem(
            id: UUID(),
            command: command,
            versions: versions,
            refreshToken: refreshToken,
            installationURL: executables[command.source]
        )
        items.append(item)

        // The gate opens per submission, not per batch, so `isMutating` stays
        // true for the whole of a fan-out — a quiet window between two queued
        // mutations wastes no refresh — while N terminals still produce exactly
        // N re-snapshots (design D7).
        //
        // Hoisted above the runner guard so that one `begin()` per submit and
        // one `end()` per finish is an invariant of *submission* rather than of
        // the happy path: every exit from this method below here goes through
        // `finish`, which is the only settle site (design D3).
        //
        // Scoped to what this command invalidates, so a family that cannot
        // change the installed set never opens that gate at all — which is the
        // whole of the scoping, and why the change observer needs no edit.
        gates?.begin(command.invalidates)

        guard let runner = runners[command.source] else {
            item.queuePhase = .terminal(BrewExit(status: 127, reason: .exited), fault: nil)
            // Through the funnel, never beside it. Settling inline here is what
            // made a terminal outcome with no history entry possible at all: the
            // entry is written by construction now, not by a second call site
            // remembering to write one (operation-activity OA6).
            finish(item, with: .launchFailed)
            return item
        }

        // Marked before the task is created, so a cancel arriving while this
        // item waits its turn settles it here and now rather than reaching a
        // runner that has never heard of it (design D13).
        item.isChainQueued = true
        let predecessor = mutationTail
        let gate = Task { [weak self] in
            await predecessor?.value
            await self?.runChained(command, for: item, on: runner, authorizer: authorizer)
        }
        mutationTail = gate
        return item
    }

    /// Waits for the previous submission's terminal outcome, then runs this one.
    ///
    /// Every line between the `await` above and the `await run(...)` below is
    /// synchronous and main-isolated, so the hand-off from "queued at the
    /// centre" to "about to have a handle" cannot be observed half-done: a
    /// cancel either arrived before it and already settled the item, or arrives
    /// after it and is replayed by `run(_:for:on:)`.
    private func runChained(
        _ command: some BrewMutating,
        for item: ActivityItem,
        on runner: BrewRunner,
        authorizer: any MutationLaunchAuthorizing
    ) async {
        item.isChainQueued = false
        // Cancelled while it waited: it is already terminal, and nothing may be
        // spawned for it (design D13).
        guard item.outcome == nil else { return }
        item.isStartInFlight = true
        await run(command, for: item, on: runner, authorizer: authorizer)
    }

    // MARK: - One operation, start to finish

    /// Generic, so `classify` dispatches to the **concrete** command's own
    /// implementation. That is what makes "a family may read its own markers
    /// without any other family paying for it" a property of the spine rather
    /// than of a switch somebody has to keep exhaustive (design D4).
    private func run(
        _ command: some BrewMutating,
        for item: ActivityItem,
        on runner: BrewRunner,
        authorizer: any MutationLaunchAuthorizing
    ) async {
        // Cancelled between `submit` and here: never spawn it.
        guard !item.isCancelRequested else {
            item.isStartInFlight = false
            finish(item, with: .cancelled)
            return
        }

        let operation: AuthorizedMutationOperation
        do {
            operation = try await runner.start(
                BrewMutation(arguments: command.arguments),
                authorizer: authorizer,
                environmentOverrides: command.environmentOverrides
            )
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

        switch await operation.terminal() {
        case .process(let exit, let fault):
            // Through the concrete command, preserving family-specific classification.
            finish(item, with: command.classify(exit: exit, fault: fault, log: item.log))
        case .authorizationDenied(let denial):
            item.queuePhase = .authorizationDenied(denial)
            finish(item, with: .authorizationDenied(denial.code))
        }
    }

    /// Settles an item exactly once, pays the re-snapshot it owes, and records
    /// the one durable entry that outcome earns.
    ///
    /// Idempotent on purpose: a cancel and a terminal exit can race, and paying
    /// the gate twice for one operation would produce 2N re-snapshots for a
    /// batch of N. That same idempotence is what makes "exactly one history
    /// entry per terminal outcome" true **by construction** rather than by
    /// discipline (operation-activity OA6, design D7).
    private func finish(_ item: ActivityItem, with outcome: MutationOutcome) {
        guard item.outcome == nil else { return }
        item.settle(outcome)
        // Recording is a side effect of the outcome,
        // never a precondition of it. The protocol is synchronous and
        // non-throwing, so an absent or failing recorder cannot change what this
        // operation reported or delay the re-snapshot it already paid (IH7).
        history.record(
            HistoryDraft(
                id: item.id,
                date: Date(),
                packageID: item.packageID,
                verb: item.command.verb,
                versions: item.versions,
                outcome: outcome,
                argv: item.arguments,
                failureTail: HistoryDraft.failureTail(of: item.log, for: outcome)
            )
        )
        // Emit refresh work only after the terminal and its durable history draft
        // are settled. Receipt consumers can therefore never reconfirm early.
        gates?.end(
            item.command.invalidates,
            token: item.refreshToken,
            installationURL: item.installationURL,
            diskAreas: item.command.diskAreas
        )
        settleForceRecovery(for: item, outcome: outcome)
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
        // No handle. An item still waiting its turn in the centre's chain has
        // nothing spawned and nothing to signal, so it settles here — which is
        // what makes cancelling a queued mutation free rather than a promise
        // redeemed whenever its predecessor happens to finish.
        //
        // If a start is in flight instead, `run(_:for:on:)` replays the request
        // — it guards at entry and again after start. Only a submission that
        // never had a runner at all is terminal here for the third reason.
        if item.isChainQueued || !item.isStartInFlight {
            finish(item, with: .cancelled)
        }
    }
}
