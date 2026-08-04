import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Foundation

/// Deterministic, process-free app dependencies used only by the XCUITest launch mode.
enum AppTestFixtures {
    nonisolated enum Mode: Sendable {
        case standard
        case empty
        case error
        case absent
        case large
        case warning
    }

    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--ui-testing-m3-taps")
            || arguments.contains("--ui-testing-m3-disk-usage")
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
        if arguments.contains("--ui-testing-m3-disk-usage-absent") { return .absent }
        if arguments.contains("--ui-testing-m3-disk-usage-warning") { return .warning }
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
        case .standard, .absent, .warning:
            return Data(
                #"[{"name":"homebrew/core","repo":"homebrew-core","formula_names":[],"cask_tokens":[]},{"name":"homebrew/cask","repo":"homebrew-cask","formula_names":[],"cask_tokens":[]},{"name":"acme/tools","user":"acme","repo":"tools","remote":"https://example.com/acme/tools","formula_names":["acme/tools/widget"],"cask_tokens":["widget-app"],"last_commit":"2026-08-04"}]"#.utf8
            )
        }
    }
}

extension AppTestFixtures {
    nonisolated static var diskSnapshot: DiskUsageSnapshot {
        let roots = DiskRootsIdentity(
            cellar: "/tmp/cellar-ui-tests/Cellar",
            caskroom: "/tmp/cellar-ui-tests/Caskroom",
            cache: "/tmp/cellar-ui-tests/Cache"
        )
        let warning = mode == .warning
            ? [DiskUsageWarning(area: .caskroom, path: roots.caskroom, message: "permission denied")]
            : []
        let wget = diskPackage(.formula, "wget", "1.25.0", 20_000, .linked("1.25.0"))
        let ghostty = diskPackage(.cask, "ghostty", "1.0", 10_000, .notApplicable)
        return DiskUsageSnapshot(
            roots: roots,
            generatedAt: Date(timeIntervalSince1970: 1_775_000_000),
            rootStates: [
                .cellar: .present,
                .caskroom: warning.isEmpty ? .present : .failed("permission denied"),
                .cache: .present
            ],
            packages: [ghostty, wget],
            cache: .init(allocatedBytes: 5_000, logicalBytes: 4_000),
            warnings: warning
        )
    }

    nonisolated private static func diskPackage(
        _ kind: PackageKind,
        _ name: String,
        _ version: String,
        _ bytes: Int64,
        _ linkState: FormulaLinkState
    ) -> DiskPackageUsage {
        let id = PackageID(kind: kind, name: name)
        return DiskPackageUsage(
            id: id,
            versions: [DiskVersionUsage(
                id: .init(package: id, rawVersion: version),
                observation: .init(allocatedBytes: bytes, logicalBytes: bytes),
                linkState: linkState
            )]
        )
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
