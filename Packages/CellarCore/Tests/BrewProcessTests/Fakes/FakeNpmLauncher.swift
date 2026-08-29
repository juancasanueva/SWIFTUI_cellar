import Foundation
import Synchronization

@testable import BrewProcess

/// A launcher scripted by **executable path and argument vector**.
///
/// `FakeVersionLauncher` keys on the path alone, which is enough for brew:
/// validating a `brew` runs exactly one command. Validating an npm runs two
/// against the same binary — `--version`, then `prefix -g` — so a path-keyed
/// script cannot express "this npm answers its version but its prefix probe
/// fails", which is a state detection has to have a defined answer for.
///
/// `FakeProcessLauncher`'s ordered queue could express it, but only positionally:
/// a priority test that adds one candidate in front silently re-points every
/// scripted response after it. Keying on the pair keeps each expectation
/// attached to the invocation it describes.
final class FakeNpmLauncher: ProcessLaunching, Sendable {
    struct Key: Hashable, Sendable {
        let path: String
        let arguments: [String]
    }

    struct Response: Sendable {
        var stdout: String = ""
        var stderr: String = ""
        var status: Int32 = 0

        static func out(_ text: String, status: Int32 = 0) -> Response {
            Response(stdout: text + "\n", status: status)
        }
    }

    private struct State {
        var responses: [Key: Response]
        var specs: [ProcessSpec] = []
        var launchError: (any Error)?
    }

    private let state: Mutex<State>

    init(responses: [Key: Response] = [:]) {
        self.state = Mutex(State(responses: responses))
    }

    /// Scripts one npm that answers both validation probes.
    static func valid(
        _ path: String,
        version: String = "10.9.2",
        prefix: String = "/opt/homebrew"
    ) -> [Key: Response] {
        [
            Key(path: path, arguments: ["--version"]): .out(version),
            Key(path: path, arguments: ["prefix", "-g"]): .out(prefix),
        ]
    }

    var recordedSpecs: [ProcessSpec] { state.withLock { $0.specs } }
    var recordedArguments: [[String]] { recordedSpecs.map(\.arguments) }
    /// Every invocation as `(executable path, argv)`, in order.
    var recordedInvocations: [(path: String, arguments: [String])] {
        recordedSpecs.map { ($0.executableURL.path, $0.arguments) }
    }

    var launchedPaths: [String] { recordedSpecs.map(\.executableURL.path) }

    func failLaunch(with error: any Error) {
        state.withLock { $0.launchError = error }
    }

    func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
        let outcome = state.withLock { state -> Result<Response, any Error> in
            state.specs.append(spec)
            if let error = state.launchError { return .failure(error) }
            let key = Key(path: spec.executableURL.path, arguments: spec.arguments)
            // An unscripted invocation exits non-zero with nothing on stdout,
            // which is what an npm that is not really an npm looks like. It is
            // never silently successful.
            return .success(state.responses[key] ?? Response(status: 1))
        }
        let response = try outcome.get()

        let process = FakeProcess()
        if !response.stdout.isEmpty { process.emitStdout(response.stdout) }
        if !response.stderr.isEmpty { process.emitStderr(response.stderr) }
        process.terminate(with: BrewExit(status: response.status, reason: .exited))
        return process
    }
}

/// A scripted directory listing, so nvm's and mise's "newest installed Node"
/// rule is reachable without a real `~/.nvm` tree.
final class FakeDirectoryEnumerator: DirectoryEnumerating, Sendable {
    private struct State {
        var children: [String: [String]]
        var enumerated: [String] = []
    }

    private let state: Mutex<State>

    /// - Parameter children: directory path to the bare names it contains.
    init(children: [String: [String]] = [:]) {
        self.state = Mutex(State(children: children))
    }

    /// Directories whose contents were listed, in order.
    var enumeratedPaths: [String] { state.withLock { $0.enumerated } }

    func subdirectories(of url: URL) -> [URL] {
        state.withLock { state in
            state.enumerated.append(url.path)
            return (state.children[url.path] ?? []).map(url.appendingPathComponent)
        }
    }
}
