import Foundation
import Testing

@testable import BrewProcess

/// The real `brew` binary, when this machine has one.
private let realBrewPath = "/opt/homebrew/bin/brew"
private let hasRealBrew = FileManager.default.isExecutableFile(atPath: realBrewPath)

extension Tag {
    /// Spawns the real `brew`. Excluded from the fast inner loop with
    /// `swift test --skip tag:realBrew`.
    @Tag static var realBrew: Self
}

/// End-to-end coverage against a real Homebrew install.
///
/// Gated with `.enabled(if:)` so a machine without Homebrew skips these rather
/// than failing: they prove integration, not a requirement of the build.
@Suite(
    "Real Homebrew integration",
    .enabled(if: hasRealBrew),
    .tags(.realBrew),
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

    /// The honest form of `brew-execution`'s "no ANSI escape byte survives
    /// capture": a fake process cannot prove anything about brew's own colour
    /// decision, because the decision is made inside brew from the environment
    /// it was handed. Only a real invocation can.
    ///
    /// `brew info --formula <name>` is the probe because it is the shape that
    /// colours: brew paints its `==>` headers, its `Warning:` prefixes and its
    /// bottle table. It is also read-only and free.
    ///
    /// The formula is **discovered**, never hardcoded — a name this machine does
    /// not have installed would exit non-zero and print nothing worth
    /// inspecting, which is a test that passes because it observed nothing.
    @Test("No escape byte survives capture from a real brew invocation")
    func noEscapeByteSurvivesCaptureFromARealBrewInvocation() async throws {
        let installation = try #require(
            await DefaultBrewLocator().detect(configuredPath: nil).installation
        )
        let runner = BrewRunner(installation: installation)

        let listing = try await runner.start(.read(["list", "--formula"]))
        var installed: [String] = []
        for await line in listing.lines where line.stream == .stdout {
            installed.append(contentsOf: line.text.split(separator: " ").map(String.init))
        }
        _ = await listing.exit()
        let formula = try #require(
            installed.first { !$0.isEmpty },
            "this machine has no installed formula to inspect"
        )

        let info = try await runner.start(.read(["info", "--formula", formula]))
        var log: [LogLine] = []
        for await line in info.lines { log.append(line) }
        let exit = await info.exit()

        // A run that produced nothing would satisfy `allSatisfy` vacuously.
        #expect(exit.isSuccess)
        #expect(log.isEmpty == false, "brew info printed nothing, so nothing was inspected")
        #expect(log.contains { $0.text.contains(formula) })

        let coloured = log.filter { $0.text.utf8.contains(0x1B) }
        #expect(
            coloured.isEmpty,
            "\(coloured.count) captured line(s) carry an ESC byte: \(coloured.map(\.text).prefix(3))"
        )
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
