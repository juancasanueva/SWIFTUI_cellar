import Foundation
import Synchronization

/// The production `ProcessLaunching` seam: spawns a real `Foundation.Process`.
public struct SystemProcessLauncher: ProcessLaunching {
    public init() {}

    public func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
        try SystemProcess(spec: spec)
    }
}

/// A `Foundation.Process` made safe to use from Swift concurrency.
///
/// Design decision D1: `Process`, its `Pipe`s, and every scrap of mutable
/// bookkeeping live inside one `Mutex`, which is the sanctioned way to confine
/// a non-`Sendable` Foundation object. The class is `Sendable` with **zero**
/// `@unchecked` conformances.
///
/// Invariant I1: both readability handlers feed exactly **one**
/// `AsyncStream<OutputChunk>` continuation, and `finish()` is called exactly
/// once — after both pipes reach EOF *and* the process has been reaped. Anything
/// less truncates output; anything more traps.
final class SystemProcess: LaunchedProcess, Sendable {
    private struct State {
        var process: Process
        var stdoutAtEOF = false
        var stderrAtEOF = false
        var reaped: BrewExit?
        var completed = false
        var waiters: [CheckedContinuation<BrewExit, Never>] = []
    }

    private let state: Mutex<State>
    private let continuation: AsyncStream<OutputChunk>.Continuation

    let output: AsyncStream<OutputChunk>

    init(spec: ProcessSpec) throws {
        let process = Process()
        process.executableURL = spec.executableURL
        process.arguments = spec.arguments
        process.environment = spec.environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // brew must never be able to block waiting for input Cellar cannot give.
        process.standardInput = FileHandle.nullDevice

        let (stream, continuation) = AsyncStream<OutputChunk>.makeStream()
        self.output = stream
        self.continuation = continuation
        self.state = Mutex(State(process: process))

        stdoutPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            read(from: handle, tagging: OutputChunk.stdout, isStdout: true)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            read(from: handle, tagging: OutputChunk.stderr, isStdout: false)
        }
        process.terminationHandler = { [self] terminated in
            markReaped(exit: Self.exit(of: terminated))
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            continuation.finish()
            throw error
        }
    }

    // MARK: - LaunchedProcess

    func send(_ signal: ProcessSignal) throws {
        let identifier = state.withLock { state -> pid_t? in
            state.reaped == nil ? state.process.processIdentifier : nil
        }
        guard let identifier, identifier > 0 else { return }

        if kill(identifier, signal.posixValue) != 0, errno != ESRCH {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }
    }

    func waitForTermination() async -> BrewExit {
        await withCheckedContinuation { continuation in
            let resolved = state.withLock { state -> BrewExit? in
                if state.completed { return state.reaped }
                state.waiters.append(continuation)
                return nil
            }
            if let resolved { continuation.resume(returning: resolved) }
        }
    }

    // MARK: - Pipe plumbing

    /// Called on Foundation's reader queue for each readable event. An empty
    /// read means EOF for that pipe.
    private func read(
        from handle: FileHandle,
        tagging wrap: (Data) -> OutputChunk,
        isStdout: Bool
    ) {
        let data = handle.availableData
        guard data.isEmpty else {
            continuation.yield(wrap(data))
            return
        }

        handle.readabilityHandler = nil
        state.withLock { state in
            if isStdout { state.stdoutAtEOF = true } else { state.stderrAtEOF = true }
        }
        completeIfDone()
    }

    private func markReaped(exit: BrewExit) {
        state.withLock { $0.reaped = exit }
        completeIfDone()
    }

    /// Finishes the stream and resolves waiters exactly once (I1).
    private func completeIfDone() {
        let completion = state.withLock { state -> (BrewExit, [CheckedContinuation<BrewExit, Never>])? in
            guard !state.completed,
                  state.stdoutAtEOF,
                  state.stderrAtEOF,
                  let exit = state.reaped
            else { return nil }

            state.completed = true
            defer { state.waiters.removeAll() }
            return (exit, state.waiters)
        }
        guard let (exit, waiters) = completion else { return }

        continuation.finish()
        for waiter in waiters { waiter.resume(returning: exit) }
    }

    private static func exit(of process: Process) -> BrewExit {
        switch process.terminationReason {
        case .uncaughtSignal:
            let signal = process.terminationStatus
            return BrewExit(status: 128 + signal, reason: .signalled(signal))
        default:
            return BrewExit(status: process.terminationStatus, reason: .exited)
        }
    }
}
