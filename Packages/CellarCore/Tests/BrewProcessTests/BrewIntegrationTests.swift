import Foundation
import Testing

@testable import BrewProcess

/// The real `brew` binary, when this machine has one.
private let realBrewPath = "/opt/homebrew/bin/brew"
private let hasRealBrew = FileManager.default.isExecutableFile(atPath: realBrewPath)

/// End-to-end coverage against a real Homebrew install.
///
/// Gated with `.enabled(if:)` so a machine without Homebrew skips these rather
/// than failing: they prove integration, not a requirement of the build.
@Suite(
    "Real Homebrew integration",
    .enabled(if: hasRealBrew),
    .timeLimit(.minutes(1))
)
struct BrewIntegrationTests {
    private var realBrewURL: URL { URL(fileURLWithPath: realBrewPath) }

    @Test("Detection finds the real installation and validates its version")
    func detectsRealInstallation() async throws {
        let locator = DefaultBrewLocator()

        let state = await locator.detect(configuredPath: nil)
        let installation = try #require(state.installation)

        #expect(installation.executableURL.path.hasSuffix("/bin/brew"))
        #expect(installation.version >= DefaultBrewLocator.minimumVersion)
        #expect(state.installGuidance == nil)
    }

    @Test("brew --version streams ordered lines and exits 0")
    func realVersionStreamsLines() async throws {
        let installation = try #require(
            await DefaultBrewLocator().detect(configuredPath: nil).installation
        )
        let runner = BrewRunner(installation: installation)

        let operation = try await runner.start(.read(["--version"]))
        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        let exit = await operation.exit()

        #expect(exit == BrewExit(status: 0, reason: .exited))
        #expect(lines.isEmpty == false)
        #expect(lines.first?.text.hasPrefix("Homebrew") == true)
        #expect(lines.map(\.sequence) == Array(0..<lines.count))
        #expect(BrewVersion.parse(lines.map(\.text).joined(separator: "\n")) != nil)
    }

    @Test("An unknown subcommand exits non-zero and explains itself on stderr")
    func unknownSubcommandFailsWithStderr() async throws {
        let installation = try #require(
            await DefaultBrewLocator().detect(configuredPath: nil).installation
        )
        let runner = BrewRunner(installation: installation)

        let operation = try await runner.start(.read(["definitely-not-a-brew-command"]))
        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        let exit = await operation.exit()

        #expect(exit.isSuccess == false)
        #expect(exit.status != 0)
        #expect(exit.reason == .exited)

        let stderr = lines.filter { $0.stream == .stderr }
        #expect(stderr.isEmpty == false)
        #expect(stderr.contains { $0.text.contains("definitely-not-a-brew-command") })
    }

    @Test("A configured path pointing at a non-Homebrew binary is rejected")
    func realNonBrewBinaryIsRejected() async {
        let locator = DefaultBrewLocator()

        let state = await locator.detect(configuredPath: URL(fileURLWithPath: "/bin/echo"))

        guard case .invalid(let url, .notHomebrew) = state else {
            Issue.record("expected .invalid(.notHomebrew) for /bin/echo, got \(state)")
            return
        }
        #expect(url == URL(fileURLWithPath: "/bin/echo"))
    }
}
