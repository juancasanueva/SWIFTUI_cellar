import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Foundation
import ReleaseNotes
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
            || arguments.contains("--ui-testing-m5-release-notes")
            || arguments.contains("--ui-testing-m5-brewfile")
    }

    // MARK: - M5 Brewfile

    nonisolated static var isBrewfileEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-m5-brewfile")
    }

    /// Where an import reads from, for this launch.
    ///
    /// The ordinary `NSOpenPanel`, except under `--ui-testing-m5-brewfile`,
    /// where it is a stub returning a Brewfile this launch wrote to a temporary
    /// file. That is the only way a UI test can exercise import at all: a modal
    /// `NSOpenPanel` cannot be driven by identifier, and picking a file by
    /// coordinates would test the panel rather than the import.
    ///
    /// Deliberately narrow: it swaps one seam and changes no behaviour. The
    /// bytes still travel the shipped path — `CatalogFileSystem` reads them,
    /// `BrewfileParser` decodes them, and nothing is evaluated.
    nonisolated static var brewfileSourceChooser: any BrewfileSourceChoosing {
        isBrewfileEnabled ? AppTestBrewfileSourceChooser() : BrewfileSourcePanel()
    }

    /// A mixed-kinds document, in the shape of the `Fixtures/Bundle` fixture of
    /// the same name.
    ///
    /// Inline rather than read from `Tests/BrewClientTests/Fixtures/Bundle/`,
    /// because reaching that resource from the app target would mean adding a
    /// bundle resource — and this change is bound to a zero-line
    /// `project.pbxproj` diff. Every construct the UI test asserts about is
    /// present: three unsupported kinds, one unsupported option, one Ruby
    /// conditional, a tap the fixture inventory does not already carry, and one
    /// package that inventory *does* carry, so the present-and-unselectable row
    /// is reachable too.
    nonisolated static let brewfileDocument = """
        tap "gentleman-programming/tap"
        brew "widget"
        brew "wget"
        cask "ghostty"
        mas "Xcode", id: 497799835
        vscode "ms-python.python"
        cargo "ripgrep"
        brew "dotnet@9", link: true
        brew "gnupg" if OS.mac?

        """

    // MARK: - M5 release notes

    nonisolated static var isReleaseNotesEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-m5-release-notes")
    }

    /// Whether the launch pretends a grant is already recorded.
    ///
    /// A launch argument rather than a written default, so a UI test never has to
    /// mutate the developer's real preferences to reach the granted path — and so
    /// the ungranted path is genuinely ungranted rather than "whatever was left
    /// over from the last run".
    nonisolated static var isReleaseNotesGranted: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-m5-release-notes-granted")
    }

    /// What the stubbed GitHub transport answers with.
    nonisolated enum ReleaseNotesMode: Sendable {
        /// A page carrying a release tagged for the outdated version.
        case matched
        /// `403` with an exhausted budget and a reset time.
        case rateLimited
    }

    nonisolated static var releaseNotesMode: ReleaseNotesMode {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-m5-release-notes-rate-limited")
            ? .rateLimited
            : .matched
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

/// The `NSOpenPanel` stand-in for `--ui-testing-m5-brewfile`.
///
/// Writes the document once per launch and answers with its URL, so the store
/// reads a real file through the real file-system seam.
struct AppTestBrewfileSourceChooser: BrewfileSourceChoosing {
    func chooseSource() async -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-ui-brewfile", isDirectory: true)
        let url = directory.appendingPathComponent("Brewfile")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(AppTestFixtures.brewfileDocument.utf8).write(to: url)
        } catch {
            return nil
        }
        return url
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
        guard AppTestFixtures.isReleaseNotesEnabled else {
            return Data(
                #"{"formulae":[{"name":"widget","tap":"acme/tools","versions":{"stable":"1.0"},"installed":[{"version":"1.0","time":0,"installed_on_request":true}]}],"casks":[]}"#.utf8
            )
        }
        // One outdated formula whose published homepage is a real GitHub
        // repository, so the row's affordance resolves without a catalog record.
        // The second is outdated too and resolves to nothing, which is what makes
        // "the button appears only where it can work" observable rather than
        // vacuous.
        return Data(
            #"""
            {"formulae":[
              {"name":"hyperfine","tap":"homebrew/core","desc":"Command-line benchmarking tool",
               "homepage":"https://github.com/sharkdp/hyperfine",
               "versions":{"stable":"1.20.0"},"outdated":true,
               "installed":[{"version":"1.18.0","time":0,"installed_on_request":true}]},
              {"name":"widget","tap":"acme/tools","desc":"No repository anywhere",
               "homepage":"https://gnu.org/software/widget",
               "versions":{"stable":"2.0"},"outdated":true,
               "installed":[{"version":"1.0","time":0,"installed_on_request":true}]}
            ],"casks":[]}
            """#.utf8
        )
    }
}

/// The stubbed GitHub transport for `--ui-testing-m5-release-notes`.
///
/// Registered on this launch's release-notes session only — never globally — so
/// nothing else in the app changes and no real request is ever issued from a UI
/// test. It exists so the E2E cases are deterministic: the rate-limited case in
/// particular cannot be reached by asking GitHub nicely.
nonisolated final class AppTestReleaseNotesProtocol: URLProtocol {
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let status: Int
        let headers: [String: String]
        let body: Data

        switch AppTestFixtures.releaseNotesMode {
        case .matched:
            status = 200
            headers = [
                "Content-Type": "application/json",
                "x-ratelimit-limit": "60",
                "x-ratelimit-remaining": "57",
                "x-ratelimit-reset": "1786055400"
            ]
            body = Data(Self.matchedPage.utf8)
        case .rateLimited:
            status = 403
            headers = [
                "Content-Type": "application/json",
                "x-ratelimit-limit": "60",
                "x-ratelimit-remaining": "0",
                "x-ratelimit-reset": "1786055400"
            ]
            body = Data(#"{"message":"API rate limit exceeded"}"#.utf8)
        }

        guard let response = HTTPURLResponse(
            url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// Tagged `v1.20.0`, which is the `catalogVersion` the payload above offers,
    /// so the matcher's `v`-prefix rule is what makes this land.
    private static let matchedPage = """
        [{"tag_name":"v1.20.0","name":"v1.20.0",
          "body":"## What's Changed\\n\\nFaster warmup runs and a new `--sort` option.",
          "draft":false,"prerelease":false,
          "published_at":"2024-11-16T09:32:35Z",
          "html_url":"https://github.com/sharkdp/hyperfine/releases/tag/v1.20.0"}]
        """

    /// A session that answers only from this stub.
    static func session() -> URLSession {
        let configuration = ReleaseNotesSession.configuration()
        configuration.protocolClasses = [AppTestReleaseNotesProtocol.self]
        return URLSession(configuration: configuration)
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
