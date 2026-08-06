import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Foundation
import SecurityKit

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
            || arguments.contains("--ui-testing-m3-cleanup")
            || arguments.contains("--ui-testing-m4-security")
    }

    // MARK: - M5 discover

    nonisolated static var isDiscoverEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-m5-discover")
    }

    /// Where the catalog lives for this launch.
    ///
    /// The ordinary location, except under `--ui-testing-m5-discover`, where it
    /// is an empty per-launch temporary directory. That is the only way a UI
    /// test can reach a genuine **first run** — with no snapshot, no roster and
    /// no arrivals log — on a developer machine whose real catalog directory is
    /// already populated. Deliberately narrow: it moves a path and changes no
    /// behaviour.
    ///
    /// Main-actor isolated because `CatalogStore.defaultDirectory()` is, and it
    /// is only ever read from the composition root, which is on that actor.
    static var catalogDirectory: URL {
        guard isDiscoverEnabled else { return CatalogStore.defaultDirectory() }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-ui-discover-\(UUID().uuidString)", isDirectory: true)
    }

    nonisolated enum CleanupMode: Sendable {
        case content, empty, unknownTotal, partial, error, cancelled
        case brewAbsence, confirmation, staleChanged, denialRefresh, postTerminalRefresh
    }

    // MARK: - M4 security

    nonisolated static var isSecurityEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-m4-security")
    }

    /// Two integrity reports, fixed, so the identity disclosure can be exercised
    /// without a real sweep over a real machine.
    ///
    /// The signed one carries **the real values this machine reports for
    /// Ghostty**, verified against `codesign -dv --verbose=4`. Using real values
    /// rather than invented ones means the UI test fails if the projection ever
    /// stops matching what MV-7 compares against.
    nonisolated static var integrityReports: [ArtifactIntegrityReport] {
        let signed = ArtifactLocation(
            packageID: PackageID(kind: .cask, name: "ghostty"),
            url: URL(fileURLWithPath: "/Applications/Ghostty.app"),
            kind: .bundle
        )
        let adHoc = ArtifactLocation(
            packageID: PackageID(kind: .formula, name: "ripgrep"),
            url: URL(fileURLWithPath: "/opt/homebrew/Cellar/ripgrep/15.2.0/bin/rg"),
            kind: .machO
        )
        return [
            ArtifactIntegrityReport(
                signature: ArtifactSignatureAssessment(
                    location: signed,
                    signing: .signed(
                        ArtifactSigningIdentity(
                            identifier: "com.mitchellh.ghostty",
                            teamIdentifier: "24VZTF6M5V",
                            authorities: [
                                "Developer ID Application: Mitchell Hashimoto (24VZTF6M5V)",
                                "Developer ID Certification Authority",
                                "Apple Root CA"
                            ]
                        )
                    ),
                    notarization: .notarized
                ),
                quarantine: nil
            ),
            ArtifactIntegrityReport(
                signature: ArtifactSignatureAssessment(
                    location: adHoc,
                    signing: .adHoc(identifier: "rg-555549448f89ec4d458733e9aff65b2c3b7acce2"),
                    notarization: .notNotarized
                ),
                quarantine: nil
            )
        ]
    }

    nonisolated static var isCleanupEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-m3-cleanup")
    }

    nonisolated static var cleanupMode: CleanupMode {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing-m3-cleanup-empty") { return .empty }
        if arguments.contains("--ui-testing-m3-cleanup-unknown-total") { return .unknownTotal }
        if arguments.contains("--ui-testing-m3-cleanup-partial") { return .partial }
        if arguments.contains("--ui-testing-m3-cleanup-error") { return .error }
        if arguments.contains("--ui-testing-m3-cleanup-cancelled") { return .cancelled }
        if arguments.contains("--ui-testing-m3-cleanup-brew-absence") { return .brewAbsence }
        if arguments.contains("--ui-testing-m3-cleanup-confirmation") { return .confirmation }
        if arguments.contains("--ui-testing-m3-cleanup-stale-changed") { return .staleChanged }
        if arguments.contains("--ui-testing-m3-cleanup-denial-refresh") { return .denialRefresh }
        if arguments.contains("--ui-testing-m3-cleanup-post-terminal-refresh") { return .postTerminalRefresh }
        return .content
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
        if AppTestFixtures.isCleanupEnabled, AppTestFixtures.cleanupMode == .brewAbsence {
            return .absent
        }
        return AppTestFixtures.mode == .absent ? .absent : .detected(AppTestFixtures.installation)
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

actor AppTestCleanupPreviewSource: CleanupPreviewSourcing {
    private let mode: AppTestFixtures.CleanupMode
    private var calls: [CleanupScope: Int] = [:]

    init(mode: AppTestFixtures.CleanupMode) {
        self.mode = mode
    }

    func preview(
        _ request: CleanupPreviewRequest,
        for detection: BrewDetectionState,
        diskUsage: CleanupDiskUsageContext?
    ) async throws(CleanupPreviewError) -> CleanupPreviewResult {
        guard detection.installation != nil else {
            throw .unavailable(.notInstalled(.standard))
        }
        if mode == .cancelled {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                throw .cancelled(rawStdout: Data(), rawStderr: Data())
            }
        }
        if mode == .error {
            throw .commandFailed(
                status: 1,
                rawStdout: Data(),
                rawStderr: Data("cleanup locked\n".utf8)
            )
        }

        let call = calls[request.scope, default: 0]
        calls[request.scope] = call + 1
        let stdout: String
        if request.scope == .autoremove {
            stdout = "==> Would autoremove 1 unneeded formula:\nwget\n"
        } else {
            stdout = switch mode {
            case .empty: ""
            case .unknownTotal: "Would remove: /tmp/archive (22B)\n"
            case .partial: "future Homebrew cleanup prose\n"
            case .staleChanged, .denialRefresh where call > 0:
                "Would remove: /tmp/changed (11B)\n"
                    + "==> This operation would free approximately 11B of disk space.\n"
            default:
                "Would remove: /tmp/archive (22B)\n"
                    + "==> This operation would free approximately 22B of disk space.\n"
            }
        }
        return CleanupParser.parse(
            request,
            rawStdout: Data(stdout.utf8),
            rawStderr: Data(),
            diskUsage: diskUsage
        )
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
