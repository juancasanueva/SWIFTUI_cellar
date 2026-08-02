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
