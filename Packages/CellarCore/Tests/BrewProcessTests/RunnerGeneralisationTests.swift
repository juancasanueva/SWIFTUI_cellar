import CellarTestSupport
import Foundation
import Synchronization
import Testing

@testable import BrewProcess

/// The runner, generalised over an executable and an environment composer
/// (`brew-execution` — "The runner is generalised over an executable and an
/// environment composer"; design D4).
///
/// The whole point of the generalisation is that a second source can reuse the
/// FIFO, the SIGINT→SIGTERM escalation, the pump and the retention rules without
/// a second actor being written — and that the brew half is provably unchanged
/// while it happens.
@Suite("Runner generalisation")
struct RunnerGeneralisationTests {
    private static let npm = URL(fileURLWithPath: "/opt/homebrew/bin/npm")
    private static let npmEnvironment = [
        "PATH": "/opt/homebrew/bin:/usr/bin",
        "HOME": "/Users/tester",
        "npm_config_progress": "false",
    ]

    // MARK: - The generalised form

    @Test("A generalised read spawns the injected executable under the injected composer")
    func generalisedReadSpawnsItsOwnExecutable() async throws {
        let launcher = FakeProcessLauncher()
        let runner = BrewRunner(
            executableURL: Self.npm,
            environment: { _ in Self.npmEnvironment },
            launcher: launcher
        )

        _ = try await runner.start(.read(["ls", "-g", "--json", "--depth=0"]))

        let spec = try #require(launcher.recordedSpecs.first)
        #expect(spec.executableURL == Self.npm)
        #expect(spec.arguments == ["ls", "-g", "--json", "--depth=0"])
        #expect(spec.environment["npm_config_progress"] == "false")
        #expect(spec.environment.keys.contains { $0.hasPrefix("HOMEBREW_") } == false)
    }

    /// Triangulation: the mutation path composes its spec at a different site,
    /// so a fix applied only to the read path would leave npm mutations
    /// spawning `brew`.
    @Test("A generalised mutation spawns the injected executable under the injected composer")
    func generalisedMutationSpawnsItsOwnExecutable() async throws {
        let launcher = FakeProcessLauncher()
        let runner = BrewRunner(
            executableURL: Self.npm,
            environment: { _ in Self.npmEnvironment },
            launcher: launcher
        )

        _ = try await runner.start(BrewMutation(arguments: ["install", "-g", "typescript@latest"]))
        await launcher.waitForLaunches(atLeast: 1)

        let spec = try #require(launcher.recordedSpecs.first)
        #expect(spec.executableURL == Self.npm)
        #expect(spec.arguments == ["install", "-g", "typescript@latest"])
        #expect(spec.environment == Self.npmEnvironment)
    }

    /// The composer is handed the command's own typed overrides rather than a
    /// fixed set, which is what keeps `brew cleanup`'s `noAutoremove` working
    /// through the generalised path.
    @Test("The composer receives the command's own environment overrides")
    func composerReceivesCommandOverrides() async throws {
        let launcher = FakeProcessLauncher()
        let seen = Mutex<[Set<BrewEnvironment.CommandOverride>]>([])
        let runner = BrewRunner(
            executableURL: Self.npm,
            environment: { overrides in
                seen.withLock { $0.append(overrides) }
                return Self.npmEnvironment
            },
            launcher: launcher
        )

        _ = try await runner.start(
            BrewMutation(arguments: ["cleanup"]),
            environmentOverrides: [.noAutoremove]
        )
        await launcher.waitForLaunches(atLeast: 1)

        #expect(seen.withLock { $0 } == [[.noAutoremove]])
    }

    // MARK: - The brew convenience form, unchanged

    @Test("The brew convenience initializer spawns brew under the pinned brew environment")
    func brewConvenienceInitializerIsUnchanged() async throws {
        let launcher = FakeProcessLauncher()
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.mutate(["upgrade", "--formula", "wget"]))
        await launcher.waitForLaunches(atLeast: 1)

        let spec = try #require(launcher.recordedSpecs.first)
        #expect(spec.executableURL == BrewInstallation.fixture.executableURL)
        #expect(spec.environment == BrewEnvironment.current(commandOverrides: []))
        #expect(spec.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
    }

    /// A brew runner and an npm runner are distinct instances that cannot spawn
    /// each other's executable, which is what "source-keyed runners MUST be
    /// distinct instances" means at the execution layer.
    @Test("A brew runner and an npm runner never spawn each other's executable")
    func runnersNeverSpawnEachOthersExecutable() async throws {
        let brewLauncher = FakeProcessLauncher()
        let npmLauncher = FakeProcessLauncher()
        let brew = BrewRunner(installation: .fixture, launcher: brewLauncher)
        let npm = BrewRunner(
            executableURL: Self.npm,
            environment: { _ in Self.npmEnvironment },
            launcher: npmLauncher
        )

        _ = try await brew.start(.read(["info", "--installed"]))
        _ = try await npm.start(.read(["ls", "-g"]))

        #expect(brewLauncher.recordedSpecs.map(\.executableURL) == [BrewInstallation.fixture.executableURL])
        #expect(npmLauncher.recordedSpecs.map(\.executableURL) == [Self.npm])
    }

    // MARK: - The structural half of the same rule

    /// `brew-execution`: "the runner reaches no brew environment type directly …
    /// none exists outside the brew convenience initializer".
    ///
    /// Textual because the claim is textual — an absence in a target's source
    /// cannot be proved by importing it — and anchored positively first, so a
    /// wrong path cannot make the prohibition pass vacuously.
    @Test("The runner reaches the brew environment composer only in its convenience initializer")
    func runnerReachesTheBrewComposerOnlyOnce() throws {
        let code = try Self.runnerCode()

        #expect(code.contains("public actor BrewRunner"), "the scan did not read the runner's source")
        #expect(code.contains("executableURL"), "the scan read a runner with no executable of its own")

        let composerReferences = code.components(separatedBy: "BrewEnvironment.current(").count - 1
        #expect(
            composerReferences == 1,
            "only the brew convenience initializer may reach the composer, but \(composerReferences) sites do"
        )
        #expect(
            code.contains("BrewEnvironment.compose(") == false,
            "the runner composes a brew environment directly"
        )
    }

    /// `Sources/BrewProcess/BrewRunner.swift` with its `//` comments removed, so
    /// a prohibition *described* in a doc comment is never mistaken for one
    /// *violated* in code.
    private static func runnerCode() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // BrewProcessTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // CellarCore
            .appendingPathComponent("Sources/BrewProcess/BrewRunner.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") == false }
            .joined(separator: "\n")
    }
}
