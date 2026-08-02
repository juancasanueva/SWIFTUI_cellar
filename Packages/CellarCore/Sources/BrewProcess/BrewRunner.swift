import Foundation

/// Runs `brew` commands and publishes their output as it arrives.
///
/// The runner owns process lifetime, serialization, and stream plumbing; it
/// deliberately owns no parsing or presentation. Every subprocess reaches the
/// outside world through the injected `ProcessLaunching` seam, so the whole
/// actor is testable without spawning anything, and every grace period runs on
/// the injected `Clock`, so cancellation is testable without waiting.
public actor BrewRunner {
    private let installation: BrewInstallation
    private let launcher: any ProcessLaunching
    private let policy: CancellationPolicy
    private let clock: any Clock<Duration>
    private var operations: [UUID: OperationRecord] = [:]
    private var nextOrdinal = 0
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

    public init(
        installation: BrewInstallation,
        launcher: any ProcessLaunching = SystemProcessLauncher(),
        policy: CancellationPolicy = .default,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.installation = installation
        self.launcher = launcher
        self.policy = policy
        self.clock = clock
        (queue, queueContinuation) = AsyncStream<QueueSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    /// How many operations the runner is tracking. Test-facing.
    var activeOperationCount: Int { operations.count }

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
    private func publish() {
        queueContinuation.yield(snapshot())
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
            executableURL: installation.executableURL,
            arguments: command.arguments,
            environment: BrewEnvironment.current()
        )

        nextOrdinal += 1
        let (lines, continuation) = AsyncStream<LogLine>.makeStream()
        let submission = Submission(
            id: UUID(),
            command: command,
            ordinal: nextOrdinal,
            lines: lines,
            continuation: continuation
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
                throw Self.mapLaunchFailure(error, executableURL: installation.executableURL)
            }
            install(submission, process: process)

        case .mutate:
            enqueueMutation(submission, spec: spec)
        }

        return BrewOperation(id: id, lines: lines, runner: self)
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
        guard let record = operations[id], record.resolvedExit == nil else {
            // Cancelled while queued: never spawn anything.
            return
        }

        let process: any LaunchedProcess
        do {
            process = try launcher.launch(spec)
        } catch {
            operations[id]?.fault = Self.mapLaunchFailure(
                error,
                executableURL: installation.executableURL
            )
            operations[id]?.resolvedExit = BrewExit(status: 127, reason: .exited)
            record.continuation.finish()
            publish()
            return
        }

        let pump = Self.startPump(reading: process, into: record.continuation)
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
        guard operations[id]?.resolvedExit == nil else { return }

        let exit = await process.waitForTermination()
        // Computed before the assignment: writing through `operations[id]` while
        // the right-hand side also reads it would overlap exclusive access.
        let result = terminalResult(exit, for: id)
        operations[id]?.resolvedExit = result
        publish()
    }

    // MARK: - Results

    /// The terminal result of `id`, once every line it produced is observable.
    ///
    /// Never throws: a cancelled run is a `BrewExit.Reason`, not a failure (D3).
    func exit(of id: UUID) async -> BrewExit {
        guard let record = operations[id] else {
            return BrewExit(status: 0, reason: .exited)
        }
        if let resolved = record.resolvedExit { return resolved }

        await record.completion?.value
        return operations[id]?.resolvedExit ?? BrewExit(status: 0, reason: .exited)
    }

    /// An out-of-band fault, if the operation hit one. `nil` for every normal
    /// run, including a cancelled one.
    func fault(of id: UUID) -> BrewProcessError? {
        operations[id]?.fault
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
              record.resolvedExit == nil,
              record.isCancelling == false
        else { return }
        operations[id]?.isCancelling = true

        guard let process = record.process, let pump = record.pump else {
            // Still queued behind another mutation: resolve it here so it never
            // spawns, and let the gate hand over to whoever is next.
            operations[id]?.resolvedExit = BrewExit(
                status: 128 + SIGINT,
                reason: .cancelled(signal: SIGINT)
            )
            record.continuation.finish()
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
        operations[id]?.fault = .cancelledUnresponsive(after: policy.totalGrace)
        operations[id]?.resolvedExit = BrewExit(
            status: 128 + SIGTERM,
            reason: .cancelled(signal: SIGTERM)
        )
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
        return await completes(pump, within: grace)
    }

    /// Races the output pump against the grace period on the injected clock.
    ///
    /// The pump finishing is the signal that the process is gone: both the real
    /// and the fake process end their output stream exactly at termination.
    private func completes(_ pump: Task<Void, Never>, within grace: Duration) async -> Bool {
        let (outcomes, continuation) = AsyncStream<Bool>.makeStream()
        let clock = self.clock

        let watcher = Task.detached {
            await pump.value
            continuation.yield(true)
            continuation.finish()
        }
        let timer = Task.detached {
            try? await clock.sleep(for: grace)
            continuation.yield(false)
            continuation.finish()
        }
        defer {
            watcher.cancel()
            timer.cancel()
        }

        for await outcome in outcomes { return outcome }
        return false
    }

    // MARK: - Plumbing

    /// Drains raw chunks into whole, tagged, sequenced lines (design D2).
    private static func startPump(
        reading process: any LaunchedProcess,
        into continuation: AsyncStream<LogLine>.Continuation
    ) -> Task<Void, Never> {
        Task {
            var splitter = LineSplitter()
            for await chunk in process.output {
                for line in splitter.consume(chunk) {
                    continuation.yield(line)
                }
            }
            for line in splitter.flush() {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}
