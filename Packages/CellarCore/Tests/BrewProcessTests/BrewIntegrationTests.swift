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

/// The real `npm` binary, when this machine has one.
private let realNpmPath = "/opt/homebrew/bin/npm"
private let hasRealNpm = FileManager.default.isExecutableFile(atPath: realNpmPath)

extension Tag {
    /// Spawns the real `npm`. Excluded from the fast inner loop alongside
    /// `realBrew`, and skipped outright on a machine with no npm.
    @Tag static var realNpm: Self
}

/// End-to-end coverage against a real npm install.
///
/// **Read-only, and deliberately so.** Every invocation below is one the app
/// makes on its read path — `--version`, `prefix -g`, `ls -g --json --depth=0` —
/// so running this suite installs nothing, removes nothing and reaches no
/// registry. `outdated -g` is left out for that last reason: it is the one read
/// that needs the network, and a test suite that fails on a train is a test
/// suite people learn to ignore.
///
/// Gated with `.enabled(if:)` like its Homebrew sibling: a machine without npm
/// skips these rather than failing, because they prove integration and not a
/// requirement of the build.
@Suite(
    "Real npm integration",
    .enabled(if: hasRealNpm),
    .tags(.realNpm),
    .timeLimit(.minutes(1))
)
struct NpmIntegrationTests {
    /// Detection answers the real triple, and answers it from the real binary.
    @Test("Detection finds the real npm and reports its version, prefix and origin")
    func detectsRealNpm() async throws {
        let environment = try #require(
            await DefaultNpmLocator().detect(configuredPath: nil).environment,
            "npm is on this machine but detection did not find it"
        )

        // The *resolved* target, not the symlink: the locator follows symlinks
        // deliberately, and on a Homebrew `node` install `/opt/homebrew/bin/npm`
        // resolves two hops to `lib/node_modules/npm/bin/npm-cli.js`. Asserting
        // the file name would pin the shape of one machine's install rather than
        // the fact under test, which is that detection landed on npm's own
        // entry point.
        //
        // **Finding, recorded rather than absorbed.** That resolution has a
        // consequence this suite cannot assert without failing on a defect it
        // does not own: `binDirectory` becomes the directory of `npm-cli.js`,
        // which contains no `node`, so the `PATH` prepend that exists precisely
        // so a Finder-launched Cellar can resolve `node` prepends a directory
        // that cannot. It works here only because a `swift test` process
        // inherits a shell `PATH`. See the unit-3 apply report.
        #expect(environment.executableURL.path.contains("npm"))
        #expect(FileManager.default.isExecutableFile(atPath: environment.executableURL.path))
        // A version npm really printed, not a placeholder: at least a major and
        // a minor, both numeric.
        let parts = environment.version.split(separator: ".")
        #expect(parts.count >= 2, "npm reported \(environment.version)")
        #expect(parts.prefix(2).allSatisfy { Int($0) != nil }, "npm reported \(environment.version)")
        // The global prefix is a directory that exists — it is where `-g`
        // packages live, so a path nothing is at would mean detection invented
        // one.
        var isDirectory: ObjCBool = false
        #expect(
            FileManager.default.fileExists(atPath: environment.prefix.path, isDirectory: &isDirectory),
            "the reported global prefix \(environment.prefix.path) does not exist"
        )
        #expect(isDirectory.boolValue)
    }

    /// The listing the Installed list is built from, from the real binary, with
    /// no ANSI byte anywhere in it.
    @Test("npm ls -g --json --depth=0 returns a decodable document with no escape byte")
    func realGlobalListingIsDecodable() async throws {
        let environment = try #require(
            await DefaultNpmLocator().detect(configuredPath: nil).environment
        )
        let process = try SystemProcessLauncher().launch(
            ProcessSpec(
                executableURL: environment.executableURL,
                arguments: ["ls", "-g", "--json", "--depth=0"],
                environment: environment.processEnvironment()
            )
        )
        let (lines, exit) = await ProcessOutputCollector.drain(process)

        // Exit 1 is npm's ordinary answer when a global has an unsatisfied peer
        // dependency, and it still carries the whole document — which is the
        // rule this suite exists to prove against a real npm rather than a
        // fixture.
        #expect(exit.reason == .exited)
        #expect(exit.status == 0 || exit.status == 1, "npm ls exited \(exit.status)")

        let stdout = lines
            .filter { $0.stream == .stdout }
            .map(\.text)
            .joined(separator: "\n")
        #expect(stdout.isEmpty == false, "npm ls printed nothing, so nothing was read")

        let document = try #require(
            try JSONSerialization.jsonObject(with: Data(stdout.utf8)) as? [String: Any],
            "npm ls did not print a JSON object"
        )
        // `dependencies` is the key the decoder reads. An empty global prefix is
        // legitimate, so its *presence* is what is asserted, not its size.
        #expect(document["dependencies"] != nil || document["problems"] != nil)

        let coloured = lines.filter { $0.text.utf8.contains(0x1B) }
        #expect(
            coloured.isEmpty,
            "\(coloured.count) captured line(s) carry an ESC byte: \(coloured.map(\.text).prefix(3))"
        )
    }

    @Test("A configured path pointing at a non-npm binary is rejected")
    func realNonNpmBinaryIsRejected() async {
        let state = await DefaultNpmLocator().detect(
            configuredPath: URL(fileURLWithPath: "/bin/echo")
        )

        guard case .invalid(let url, let reason) = state else {
            Issue.record("expected .invalid for /bin/echo, got \(state)")
            return
        }
        #expect(url == URL(fileURLWithPath: "/bin/echo"))
        #expect(reason != .notExecutable, "/bin/echo is executable; it is simply not npm")
    }
}
