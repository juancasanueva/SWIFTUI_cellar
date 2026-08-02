import CellarTestSupport
import Foundation
import Synchronization

@testable import BrewProcess

/// A scripted stand-in for a spawned process.
///
/// Tests drive it explicitly: emit chunks, decide which signals it honours, and
/// terminate it when the scenario calls for it.
final class FakeProcess: LaunchedProcess, Sendable {
    /// What the fake does when a signal arrives.
    enum SignalBehavior: Sendable {
        /// Terminate as soon as `SIGINT` is delivered.
        case exitOnInterrupt
        /// Ignore `SIGINT`, terminate on `SIGTERM`.
        case exitOnTerminate
        /// Ignore every signal — the unresponsive case.
        case ignoreAll
        /// Stay alive; the test terminates the process by hand.
        case manual
    }

    /// One delivered signal plus the clock reading at delivery time.
    struct SignalRecord: Sendable, Equatable {
        let signal: ProcessSignal
        let instant: TestClock.Instant?
    }

    private struct State {
        var chunks: [OutputChunk] = []
        var signals: [SignalRecord] = []
        var exit: BrewExit?
        var waiters: [CheckedContinuation<BrewExit, Never>] = []
        var sendError: (any Error)?
    }

    private let state = Mutex(State())
    private let behavior: SignalBehavior
    private let clock: TestClock?
    private let continuation: AsyncStream<OutputChunk>.Continuation

    let output: AsyncStream<OutputChunk>

    init(behavior: SignalBehavior = .manual, clock: TestClock? = nil) {
        self.behavior = behavior
        self.clock = clock
        let (stream, continuation) = AsyncStream<OutputChunk>.makeStream()
        self.output = stream
        self.continuation = continuation
    }

    // MARK: - Test driving

    /// Pushes one raw chunk onto the output stream.
    func emit(_ chunk: OutputChunk) {
        state.withLock { $0.chunks.append(chunk) }
        continuation.yield(chunk)
    }

    /// Pushes UTF-8 bytes onto stdout.
    func emitStdout(_ text: String) {
        emit(.stdout(Data(text.utf8)))
    }

    /// Pushes UTF-8 bytes onto stderr.
    func emitStderr(_ text: String) {
        emit(.stderr(Data(text.utf8)))
    }

    /// Ends the output stream and resolves everyone awaiting termination.
    func terminate(with exit: BrewExit) {
        let waiters = state.withLock { state -> [CheckedContinuation<BrewExit, Never>] in
            guard state.exit == nil else { return [] }
            state.exit = exit
            defer { state.waiters.removeAll() }
            return state.waiters
        }
        continuation.finish()
        for waiter in waiters { waiter.resume(returning: exit) }
    }

    /// Makes `send(_:)` throw, simulating a process that vanished before the
    /// signal could be delivered.
    func failSignals(with error: any Error) {
        state.withLock { $0.sendError = error }
    }

    /// Signals delivered so far, oldest first.
    var recordedSignals: [SignalRecord] { state.withLock { $0.signals } }

    /// Just the signal kinds, for order assertions.
    var deliveredSignals: [ProcessSignal] { recordedSignals.map(\.signal) }

    /// Whether the process has terminated.
    var hasTerminated: Bool { state.withLock { $0.exit != nil } }

    /// Suspends until at least `count` signals have been delivered.
    func waitForSignals(atLeast count: Int) async {
        await TestPoll.until(self.recordedSignals.count >= count)
    }

    // MARK: - LaunchedProcess

    func send(_ signal: ProcessSignal) throws {
        let error = state.withLock { state -> (any Error)? in
            state.signals.append(SignalRecord(signal: signal, instant: clock?.now))
            return state.sendError
        }
        if let error { throw error }

        switch (behavior, signal) {
        case (.exitOnInterrupt, .interrupt), (.exitOnTerminate, .terminate):
            terminate(with: BrewExit(status: 128 + signal.posixValue, reason: .signalled(signal.posixValue)))
        default:
            break
        }
    }

    func waitForTermination() async -> BrewExit {
        await withCheckedContinuation { continuation in
            let resolved = state.withLock { state -> BrewExit? in
                if let exit = state.exit { return exit }
                state.waiters.append(continuation)
                return nil
            }
            if let resolved { continuation.resume(returning: resolved) }
        }
    }
}
