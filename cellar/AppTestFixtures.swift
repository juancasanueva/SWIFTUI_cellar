import BrewClient
import BrewProcess
import Foundation

/// Deterministic, process-free app dependencies used only by the XCUITest launch mode.
enum AppTestFixtures {
    nonisolated enum Mode: Sendable {
        case standard
        case empty
        case error
        case absent
        case large
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-m3-taps")
    }

    nonisolated static let installation = BrewInstallation(
        executableURL: URL(fileURLWithPath: "/usr/bin/true"),
        prefix: .custom(URL(fileURLWithPath: "/tmp/cellar-ui-tests")),
        version: BrewVersion(major: 6, minor: 0, patch: 0)
    )

    nonisolated static var mode: Mode {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-m3-taps-empty") { return .empty }
        if arguments.contains("--ui-testing-m3-taps-error") { return .error }
        if arguments.contains("--ui-testing-m3-taps-absent") { return .absent }
        if arguments.contains("--ui-testing-m3-taps-large") { return .large }
        return .standard
    }
}

struct AppTestBrewLocator: BrewLocating {
    func detect(configuredPath: URL?) async -> BrewDetectionState {
        switch AppTestFixtures.mode {
        case .absent:
            return .absent
        default:
            return .detected(AppTestFixtures.installation)
        }
    }
}

struct AppTestTapPayloadSource: TapPayloadSourcing {
    func payload(using installation: BrewInstallation) async throws(TapInventoryError) -> Data {
        switch AppTestFixtures.mode {
        case .empty:
            return Data("[]".utf8)
        case .error:
            throw .malformedJSON
        case .large:
            let formulae = (0..<5_000).map { index in
                index == 4_999 ? "acme/large/needle-4999" : "acme/large/package-\(index)"
            }
            do {
                return try JSONSerialization.data(withJSONObject: [[
                    "name": "acme/large",
                    "repo": "large",
                    "formula_names": formulae,
                    "cask_tokens": []
                ]])
            } catch {
                throw .malformedJSON
            }
        case .standard, .absent:
            return Data(
                #"[{"name":"homebrew/core","repo":"homebrew-core","formula_names":[],"cask_tokens":[]},{"name":"homebrew/cask","repo":"homebrew-cask","formula_names":[],"cask_tokens":[]},{"name":"acme/tools","user":"acme","repo":"tools","remote":"https://example.com/acme/tools","formula_names":["acme/tools/widget"],"cask_tokens":["widget-app"],"last_commit":"2026-08-04"}]"#.utf8
            )
        }
    }
}

struct AppTestInstalledPayloadSource: InstalledPayloadSourcing {
    func payload(using installation: BrewInstallation) async throws(InstalledInventoryError) -> Data {
        Data(
            #"{"formulae":[{"name":"widget","tap":"acme/tools","versions":{"stable":"1.0"},"installed":[{"version":"1.0","time":0,"installed_on_request":true}]}],"casks":[]}"#.utf8
        )
    }
}

struct AppTestProcessLauncher: ProcessLaunching {
    func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
        AppTestLaunchedProcess()
    }
}

private final class AppTestLaunchedProcess: LaunchedProcess {
    let output: AsyncStream<OutputChunk>

    init() {
        output = AsyncStream { $0.finish() }
    }

    func send(_ signal: ProcessSignal) throws {}

    func waitForTermination() async -> BrewExit {
        BrewExit(status: 0, reason: .exited)
    }
}
