import Foundation

/// Runs `brew` commands and publishes their output as it arrives.
///
/// The runner owns process lifetime, serialization, and stream plumbing; it
/// deliberately owns no parsing or presentation. Every subprocess reaches the
/// outside world through the injected `ProcessLaunching` seam, so the whole
/// actor is testable without spawning anything, and every grace period runs on
/// the injected `Clock`, so cancellation is testable without waiting.
///
/// Records are retained under the three ordered rules documented on
/// `OperationRecord` (design D6, brew-execution BE1): `compact(_:)`,
/// `release(_:)` and `evictRetiredRecords()`.
public actor BrewRunner {
    /// Compacted-and-released records kept for enumeration; the true bound is
    /// `live handles + this` (see `OperationRecord`'s retention notes).
    public static let defaultRetainedTerminalRecords = 200

    /// The binary every submission of this runner spawns.
    ///
    /// Stored instead of a `BrewInstallation` because the FIFO, the cancel
    /// escalation, the pump and the retention rules never needed a brew
    /// installation — they needed a path to spawn. Narrowing the dependency to
    /// exactly that is what lets a second source reuse this actor rather than
    /// grow a second one (design D4, `brew-execution`).
    private let executableURL: URL
    /// How this runner composes the environment its subprocesses run under.
    ///
    /// Injected rather than reached for, so the runner holds no opinion about
    /// *which* environment is correct: a brew runner is handed brew's composer
    /// by the convenience initializer below, and an npm runner is handed npm's.
    /// A runner that reached `BrewEnvironment` directly could only ever spawn
    /// brew, whatever executable it was pointed at.
    private let environment: @Sendable (Set<BrewEnvironment.CommandOverride>) -> [String: String]
    private let launcher: any ProcessLaunching
    private let policy: CancellationPolicy
    private let clock: any Clock<Duration>
    private let retainedTerminalRecords: Int
    private var operations: [UUID: OperationRecord] = [:]
    private var nextOrdinal = 0
    /// The last snapshot handed to `queue`, so an unchanged phase is not
    /// republished (BE1 sc10, design D6 follow-up 4b).
    private var lastPublished: QueueSnapshot?
    /// The gate task of the most recently submitted mutation (design D5).
    private var mutationTail: Task<Void, Never>?

    /// Queue state, republished whenever a phase changes.
    ///
    /// `.bufferingNewest(1)` is correct rather than merely cheap: these are
    /// *state snapshots*, so dropping an intermediate one is lossless, and a
    /// slow UI can never back-pressure the actor. `queue` is a `nonisolated let`
    /// of `Sendable` elements, so reading it crosses no isolation (design D3).
    public nonisolated let queue: AsyncStream<QueueSnapshot>
    private nonisolated let queueContinuation: AsyncStream<QueueSnapshot>.Continuation

    /// The general form: an executable, a composer for the environment it runs
    /// under, and the seams every runner already took.
    public init(
        executableURL: URL,
        environment: @escaping @Sendable (Set<BrewEnvironment.CommandOverride>) -> [String: String],
        launcher: any ProcessLaunching = SystemProcessLauncher(),
        policy: CancellationPolicy = .default,
        clock: any Clock<Duration> = ContinuousClock(),
        retainedTerminalRecords: Int = BrewRunner.defaultRetainedTerminalRecords
    ) {
        self.executableURL = executableURL
        self.environment = environment
        self.launcher = launcher
        self.policy = policy
        self.clock = clock
        self.retainedTerminalRecords = max(0, retainedTerminalRecords)
        (queue, queueContinuation) = AsyncStream<QueueSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    /// The brew form, preserved exactly as it shipped.
    ///
    /// The **one** place in this file that names a brew-specific environment,
    /// which is what makes "a runner composed for brew behaves byte-identically
    /// to the shipped runner" a property a reader can check by looking at a
    /// single initializer rather than at every spawn site.
    ///
    /// Delegating rather than `convenience`: an actor's initializers are never
    /// spelled with that keyword, and `self.init(...)` is how one forwards.
    public init(
        installation: BrewInstallation,
        launcher: any ProcessLaunching = SystemProcessLauncher(),
        policy: CancellationPolicy = .default,
        clock: any Clock<Duration> = ContinuousClock(),
        retainedTerminalRecords: Int = BrewRunner.defaultRetainedTerminalRecords
    ) {
        self.init(
            executableURL: installation.executableURL,
            environment: { BrewEnvironment.current(commandOverrides: $0) },
            launcher: launcher,
            policy: policy,
            clock: clock,
            retainedTerminalRecords: retainedTerminalRecords
        )
    }

    /// How many operations the runner is tracking. Test-facing.
    var activeOperationCount: Int { operations.count }

    /// Whether R2 has already released `id`'s execution resources. Test-facing.
    func isCompacted(_ id: UUID) -> Bool { operations[id]?.isCompacted ?? false }

    /// Whether `id` still pins a process, a task or a stream. Test-facing.
    func holdsExecutionResources(_ id: UUID) -> Bool {
        operations[id]?.holdsExecutionResources ?? false
    }

    /// Yields the current queue again, so BE1 sc10's "the same phase produced
    /// repeatedly" is something a test can actually produce. Test-facing.
    func republish() { publish() }

    // MARK: - Projection

    /// Every operation the runner is tracking, in submission order.
    ///
    /// Strictly read-only: it starts nothing, cancels nothing, and never awaits
    /// the operation in flight, so enumerating cannot perturb scheduling
    /// (brew-execution BE1).
    public func snapshot() -> QueueSnapshot {
        QueueSnapshot(
            operations: operations
                .values
                .sorted { $0.ordinal < $1.ordinal }
                .map(\.projection)
        )
    }

    /// Republishes the queue. Called at the five sites where a phase already
    /// changes: enqueue, install, spawn, terminal, cancel.
    ///
    /// Guarded by equality so an observer sees one change per real transition
    /// rather than one per yield (BE1 sc10). `.bufferingNewest(1)` collapses a
    /// *backlog*, which is a different thing: it cannot tell a repeat from a
    /// transition, so without this guard a repeat is delivered as a change.
    private func publish() {
        let snapshot = snapshot()
        guard snapshot != lastPublished else { return }
        lastPublished = snapshot
        queueContinuation.yield(snapshot)
    }

    // MARK: - Retention (design D6, brew-execution BE1)

    /// R2 — releases everything a terminal, drained operation no longer needs.
    /// R1 is the guard on the first line: a live record is never touched.
    private func compact(_ id: UUID) {
        guard var record = operations[id], record.terminal != nil, !record.isCompacted else {
            return
        }
        record.process = nil
        record.pump = nil
        record.completion = nil
        record.continuation = nil
        record.lines = nil
        record.isCompacted = true
        operations[id] = record
        evictRetiredRecords()
    }

    /// R3 — the handle is gone, so nobody can ask about this operation any more.
    /// Called from `BrewOperation.deinit`; advisory, never imperative.
    func release(_ id: UUID) {
        guard operations[id] != nil else { return }
        operations[id]?.isReleased = true
        compact(id)
        evictRetiredRecords()
    }

    /// Removes the oldest compacted-and-released records beyond the window.
    private func evictRetiredRecords() {
        let retired = operations.values
            .filter { $0.isCompacted && $0.isReleased }
            .sorted { $0.ordinal < $1.ordinal }
        guard retired.count > retainedTerminalRecords else { return }
        for record in retired.prefix(retired.count - retainedTerminalRecords) {
            operations[record.id] = nil
        }
    }

    // MARK: - Starting work

    /// Starts `command` and returns a handle to its output.
    ///
    /// A `.read` spawns immediately, so an unusable executable is reported to
    /// the caller straight away. A `.mutate` joins the FIFO gate and spawns when
    /// its turn comes, which is what makes a queued mutation cancellable before
    /// it ever touches Homebrew.
    public func start(_ command: BrewCommand) async throws(BrewProcessError) -> BrewOperation {
        let spec = ProcessSpec(
            executableURL: executableURL,
            arguments: command.arguments,
            environment: environment(command.environmentOverrides)
        )

        nextOrdinal += 1
        let (lines, continuation) = AsyncStream<LogLine>.makeStream()
        let submission = Submission(
            id: UUID(),
            command: command,
            ordinal: nextOrdinal,
            lines: lines,
            continuation: continuation,
            authorizer: command.kind == .mutate ? AllowMutationLaunch() : nil
        )
        let id = submission.id

        switch command.kind {
        case .read:
            let process: any LaunchedProcess
            do {
                process = try launcher.launch(spec)
            } catch {
                // Nothing is recorded before the launch attempt, so a failed
                // spawn leaves no half-built operation behind.
                throw Self.mapLaunchFailure(error, executableURL: executableURL)
            }
            install(submission, process: process)

        case .mutate:
            enqueueMutation(submission, spec: spec)
        }

        return BrewOperation(id: id, lines: lines, runner: self)
    }

    /// Enqueues an authorized mutation. Reads cannot enter this API.
    public func start(
        _ mutation: BrewMutation,
        authorizer: any MutationLaunchAuthorizing = AllowMutationLaunch()
    ) async throws(BrewProcessError) -> AuthorizedMutationOperation {
        try await start(
            mutation,
            authorizer: authorizer,
            environmentOverrides: []
        )
    }

    /// Enqueues an authorized mutation with typed command-local policy.
    public func start(
        _ mutation: BrewMutation,
        authorizer: any MutationLaunchAuthorizing = AllowMutationLaunch(),
        environmentOverrides: Set<BrewEnvironment.CommandOverride>
    ) async throws(BrewProcessError) -> AuthorizedMutationOperation {
        let command = BrewCommand.mutate(
            mutation.arguments,
            environmentOverrides: environmentOverrides
        )
        let spec = ProcessSpec(
            executableURL: executableURL,
            arguments: mutation.arguments,
            environment: environment(environmentOverrides)
        )
        nextOrdinal += 1
        let (lines, continuation) = AsyncStream<LogLine>.makeStream()
        let submission = Submission(
            id: UUID(),
            command: command,
            ordinal: nextOrdinal,
            lines: lines,
            continuation: continuation,
            authorizer: authorizer
        )
        enqueueMutation(submission, spec: spec)
        return AuthorizedMutationOperation(id: submission.id, lines: lines, runner: self)
    }

    /// Puts a mutation at the end of the FIFO gate.
    ///
    /// Invariant I2: the tail is read **and** replaced synchronously, before
    /// this method's first `await` — in fact it never suspends at all — so actor
    /// reentrancy cannot reorder the queue no matter how the callers interleave.
    private func enqueueMutation(_ submission: Submission, spec: ProcessSpec) {
        let id = submission.id
        let predecessor = mutationTail
        operations[id] = submission.record()

        let gate = Task { [self] in
            await predecessor?.value
            await runQueuedMutation(id: id, spec: spec)
        }
        mutationTail = gate
        operations[id]?.completion = gate

        installConsumerCancellation(for: id, on: submission.continuation)
        publish()
    }

    /// Runs one gated mutation and holds the gate until it is terminal.
    private func runQueuedMutation(id: UUID, spec: ProcessSpec) async {
        guard let record = operations[id], record.terminal == nil else {
            // Cancelled while queued: never spawn anything.
            return
        }

        let decision = await record.authorizer?.authorizeLaunch() ?? .allow
        guard operations[id]?.terminal == nil else { return }
        if case .deny(let denial) = decision {
            operations[id]?.terminal = .authorizationDenied(denial)
            record.continuation?.finish()
            compact(id)
            publish()
            return
        }

        // Cancellation can settle the queued record while authorization awaits.
        guard operations[id]?.terminal == nil else { return }

        let process: any LaunchedProcess
        do {
            process = try launcher.launch(spec)
        } catch {
            let fault = Self.mapLaunchFailure(error, executableURL: executableURL)
            operations[id]?.terminal = .process(
                BrewExit(status: 127, reason: .exited),
                fault: fault
            )
            record.continuation?.finish()
            compact(id)
            publish()
            return
        }

        guard let continuation = record.continuation else { return }
        let pump = Self.startPump(reading: process, into: continuation)
        operations[id]?.process = process
        operations[id]?.pump = pump
        publish()
        await drive(id)
    }

    /// Records a launched process and starts pumping its output.
    private func install(_ submission: Submission, process: any LaunchedProcess) {
        let id = submission.id
        let pump = Self.startPump(reading: process, into: submission.continuation)
        operations[id] = submission.record(process: process, pump: pump)
        // Safe to assign after the fact: this method never suspends, so the
        // task body cannot observe the record before the assignment lands.
        operations[id]?.completion = Task { await self.drive(id) }

        installConsumerCancellation(for: id, on: submission.continuation)
        publish()
    }

    /// Cancelling the task consuming `lines` cancels the operation itself.
    private func installConsumerCancellation(
        for id: UUID,
        on continuation: AsyncStream<LogLine>.Continuation
    ) {
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination, let self else { return }
            Task { await self.cancel(id) }
        }
    }

    /// Waits for the operation to finish and stores its terminal result.
    private func drive(_ id: UUID) async {
        guard let pump = operations[id]?.pump, let process = operations[id]?.process else { return }

        // Awaiting the pump first is what guarantees the ordering contract: the
        // result is never delivered before the output is observable.
        await pump.value
        guard operations[id]?.terminal == nil else { return }

        let exit = await process.waitForTermination()
        // Computed before the assignment: writing through `operations[id]` while
        // the right-hand side also reads it would overlap exclusive access.
        let result = terminalResult(exit, for: id)
        let fault = operations[id]?.pendingFault
        operations[id]?.terminal = .process(result, fault: fault)
        compact(id)
        publish()
    }

    // MARK: - Results

    /// The terminal result of `id`, once every line it produced is observable.
    ///
    /// Never throws: a cancelled run is a `BrewExit.Reason`, not a failure (D3),
    /// and an identity with no record is a value too — `.unknownOperation`,
    /// never a fabricated `status: 0` success (brew-execution, design D8).
    func exit(of id: UUID) async -> BrewExit {
        guard let record = operations[id] else {
            return .unknownOperation
        }
        if case .process(let exit, _) = record.terminal { return exit }

        await record.completion?.value
        if case .process(let exit, _) = operations[id]?.terminal { return exit }
        return .unknownOperation
    }

    /// An out-of-band fault, if the operation hit one. `nil` for every normal
    /// run, including a cancelled one.
    func fault(of id: UUID) -> BrewProcessError? {
        if case .process(_, let fault) = operations[id]?.terminal { return fault }
        return operations[id]?.pendingFault
    }

    func authorizedTerminal(of id: UUID) async -> AuthorizedMutationTerminal {
        guard let record = operations[id] else {
            return .process(.unknownOperation, fault: nil)
        }
        if let terminal = record.terminal { return terminal.authorized }

        await record.completion?.value
        return operations[id]?.terminal?.authorized
            ?? .process(.unknownOperation, fault: nil)
    }

    /// Reports a run Cellar cancelled as cancelled, whatever the OS said.
    private func terminalResult(_ exit: BrewExit, for id: UUID) -> BrewExit {
        guard let signal = operations[id]?.cancellationSignal else { return exit }
        return BrewExit(status: exit.status, reason: .cancelled(signal: signal))
    }

    // MARK: - Cancellation

    /// Stops `id`, escalating `SIGINT` → `SIGTERM` and never further (D4).
    public func cancel(_ id: BrewOperation.ID) async {
        guard let record = operations[id],
               record.terminal == nil,
              record.isCancelling == false
        else { return }
        operations[id]?.isCancelling = true

        guard let process = record.process, let pump = record.pump else {
            // Still queued behind another mutation: resolve it here so it never
            // spawns, and let the gate hand over to whoever is next.
            operations[id]?.terminal = .process(
                BrewExit(status: 128 + SIGINT, reason: .cancelled(signal: SIGINT)),
                fault: nil
            )
            record.continuation?.finish()
            compact(id)
            publish()
            return
        }

        if await escalate(.interrupt, to: process, id: id, pump: pump, grace: policy.interruptGrace) {
            return
        }
        if await escalate(.terminate, to: process, id: id, pump: pump, grace: policy.terminateGrace) {
            return
        }

        // The process ignored both signals. Stop consuming it, report the fault,
        // and leave it alone: SIGKILL is not an option (D4).
        pump.cancel()
        operations[id]?.terminal = .process(
            BrewExit(status: 128 + SIGTERM, reason: .cancelled(signal: SIGTERM)),
            fault: .cancelledUnresponsive(after: policy.totalGrace)
        )
        // The pump was cancelled rather than drained — the closest to drained
        // that D4's "never SIGKILL" allows — so this record is compactable too.
        compact(id)
        publish()
    }

    /// Delivers one signal and reports whether the process stopped within
    /// `grace`.
    private func escalate(
        _ signal: ProcessSignal,
        to process: any LaunchedProcess,
        id: UUID,
        pump: Task<Void, Never>,
        grace: Duration
    ) async -> Bool {
        operations[id]?.cancellationSignal = signal.posixValue
        try? process.send(signal)
        return await Self.completes(pump, within: grace, on: clock)
    }
}

private extension OperationTerminal {
    var authorized: AuthorizedMutationTerminal {
        switch self {
        case .process(let exit, let fault): .process(exit, fault: fault)
        case .authorizationDenied(let denial): .authorizationDenied(denial)
        }
    }
}
