import Foundation
import Synchronization

@testable import BrewProcess

/// A launcher that answers `--version` probes with scripted output and exits
/// immediately, so detection tests never block on a live process.
final class FakeVersionLauncher: ProcessLaunching, Sendable {
    struct Response: Sendable {
        var stdout: String = ""
        var stderr: String = ""
        var status: Int32 = 0

        static func version(_ text: String) -> Response {
            Response(stdout: text + "\n")
        }
    }

    private struct State {
        var responses: [String: Response]
        var specs: [ProcessSpec] = []
        var launchError: (any Error)?
    }

    private let state: Mutex<State>

    /// - Parameter responses: keyed by executable path.
    init(responses: [String: Response] = [:]) {
        self.state = Mutex(State(responses: responses))
    }

    /// Every spec passed to `launch(_:)`, in order.
    var recordedSpecs: [ProcessSpec] { state.withLock { $0.specs } }

    /// The argument vectors detection actually ran.
    var recordedArguments: [[String]] { recordedSpecs.map(\.arguments) }

    func failLaunch(with error: any Error) {
        state.withLock { $0.launchError = error }
    }

    func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
        let outcome = state.withLock { state -> Result<Response, any Error> in
            state.specs.append(spec)
            if let error = state.launchError { return .failure(error) }
            return .success(state.responses[spec.executableURL.path] ?? Response())
        }
        let response = try outcome.get()

        let process = FakeProcess()
        if !response.stdout.isEmpty { process.emitStdout(response.stdout) }
        if !response.stderr.isEmpty { process.emitStderr(response.stderr) }
        process.terminate(with: BrewExit(status: response.status, reason: .exited))
        return process
    }
}
