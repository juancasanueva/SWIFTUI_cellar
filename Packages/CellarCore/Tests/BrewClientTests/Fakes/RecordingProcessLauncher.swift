import CellarTestSupport
import Foundation
import Synchronization

@testable import BrewProcess

/// One canned `brew` run.
///
/// The default is the smallest *well-formed* snapshot, so a test that cares only
/// about argv does not have to restate a document to avoid tripping the
/// malformed-payload guard.
struct ScriptedRun: Sendable {
    var stdout = "{\"formulae\":[],\"casks\":[]}\n"
    var stderr = ""
    var exit = BrewExit(status: 0, reason: .exited)
}

/// A launcher that records every `ProcessSpec` it is handed and answers with a
/// canned run.
///
/// Deliberately far smaller than `BrewProcessTests`' `FakeProcessLauncher`: the
/// acquisition *semantics* are already covered by the pure
/// `InstalledPayload.payload(from:exit:)`, so all this has to prove is the argv
/// vector and the twenty lines of glue around it (design D2, D12).
final class RecordingProcessLauncher: ProcessLaunching, Sendable {
    private struct State {
        var runs: [ScriptedRun]
        var specs: [ProcessSpec] = []
        var launchError: (any Error)?
    }

    private let state: Mutex<State>

    init(_ runs: [ScriptedRun] = [ScriptedRun()]) {
        state = Mutex(State(runs: runs))
    }

    init(failingWith error: any Error) {
        state = Mutex(State(runs: [ScriptedRun()], launchError: error))
    }

    /// Every spec handed to `launch`, in order.
    var specs: [ProcessSpec] { state.withLock { $0.specs } }
    var launchCount: Int { state.withLock { $0.specs.count } }

    func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
        let (run, error) = state.withLock { state -> (ScriptedRun, (any Error)?) in
            state.specs.append(spec)
            let index = min(state.specs.count - 1, state.runs.count - 1)
            return (state.runs[index], state.launchError)
        }
        if let error { throw error }
        return ScriptedProcess(run)
    }
}

/// A process whose whole life is already decided when it is created.
final class ScriptedProcess: LaunchedProcess, Sendable {
    let output: AsyncStream<OutputChunk>
    private let result: BrewExit

    init(_ run: ScriptedRun) {
        let (stream, continuation) = AsyncStream<OutputChunk>.makeStream()
        if !run.stdout.isEmpty { continuation.yield(.stdout(Data(run.stdout.utf8))) }
        if !run.stderr.isEmpty { continuation.yield(.stderr(Data(run.stderr.utf8))) }
        continuation.finish()
        output = stream
        result = run.exit
    }

    func send(_ signal: ProcessSignal) throws {}

    func waitForTermination() async -> BrewExit { result }
}

/// A launcher whose processes the test drives by hand.
///
/// `RecordingProcessLauncher` above is enough for acquisition, where the whole
/// run is decided up front. The activity surfaces need the opposite: a process
/// that emits while it is still running and terminates when the test says so.
///
/// It duplicates `BrewProcessTests`' `FakeProcessLauncher` rather than sharing
/// it, and that is the boundary M2-1 D2 and design D9 both document: the fake
/// conforms to a `BrewProcess` protocol, so moving it into the dependency-free
/// `CellarTestSupport` would give that target a dependency and defeat its whole
/// reason for existing.
final class ControllableProcessLauncher: ProcessLaunching, Sendable {
    private struct State {
        var specs: [ProcessSpec] = []
        var launched: [ControllableProcess] = []
        var launchError: (any Error)?
    }

    private let state = Mutex(State())

    /// Every spec passed to `launch(_:)`, in order.
    var recordedSpecs: [ProcessSpec] { state.withLock { $0.specs } }
    /// Every process handed out, in launch order.
    var launchedProcesses: [ControllableProcess] { state.withLock { $0.launched } }
    var launchCount: Int { state.withLock { $0.launched.count } }

    /// Makes the next `launch(_:)` throw instead of returning a process.
    func failLaunch(with error: any Error) {
        state.withLock { $0.launchError = error }
    }

    func waitForLaunches(atLeast count: Int) async {
        await TestPoll.until(self.launchCount >= count)
    }

    func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
        let outcome = state.withLock { state -> Result<ControllableProcess, any Error> in
            state.specs.append(spec)
            if let error = state.launchError { return .failure(error) }
            let process = ControllableProcess()
            state.launched.append(process)
            return .success(process)
        }
        return try outcome.get()
    }
}

/// A process that stays alive until the test terminates it.
final class ControllableProcess: LaunchedProcess, Sendable {
    private struct State {
        var exit: BrewExit?
        var signals: [ProcessSignal] = []
        var waiters: [CheckedContinuation<BrewExit, Never>] = []
    }

    private let state = Mutex(State())
    private let continuation: AsyncStream<OutputChunk>.Continuation

    let output: AsyncStream<OutputChunk>

    init() {
        (output, continuation) = AsyncStream<OutputChunk>.makeStream()
    }

    var deliveredSignals: [ProcessSignal] { state.withLock { $0.signals } }
    var hasTerminated: Bool { state.withLock { $0.exit != nil } }

    func emitStdout(_ text: String) { continuation.yield(.stdout(Data(text.utf8))) }
    func emitStderr(_ text: String) { continuation.yield(.stderr(Data(text.utf8))) }

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

    func send(_ signal: ProcessSignal) throws {
        state.withLock { $0.signals.append(signal) }
        // Honours SIGINT, like a well-behaved `brew`.
        if signal == .interrupt {
            terminate(with: BrewExit(status: 128 + SIGINT, reason: .signalled(SIGINT)))
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

/// Installations the suites point at. Nothing is ever spawned at these paths.
enum TestInstallation {
    static func at(_ path: String) -> BrewInstallation {
        BrewInstallation(
            executableURL: URL(fileURLWithPath: path),
            prefix: .appleSilicon,
            version: BrewVersion(major: 6, minor: 0, patch: 14)
        )
    }

    static let appleSilicon = at("/opt/homebrew/bin/brew")
    static let intel = at("/usr/local/bin/brew")
}
