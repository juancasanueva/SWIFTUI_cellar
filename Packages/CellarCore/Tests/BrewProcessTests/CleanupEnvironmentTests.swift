import Testing

@testable import BrewProcess

@Suite("Cleanup command environment")
struct CleanupEnvironmentTests {
    private let hostileParent = [
        "PATH": "/custom/bin:/usr/bin:/bin",
        "HOME": "/Users/tester",
        "HOMEBREW_NO_AUTO_UPDATE": "0",
        "HOMEBREW_NO_COLOR": "0",
        "HOMEBREW_NO_EMOJI": "0",
        "HOMEBREW_NO_AUTOREMOVE": "0",
        "HOMEBREW_GITHUB_API_TOKEN": "secret",
    ]

    @Test("A cleanup override composes after inherited and pinned values")
    func cleanupOverrideComposesLast() {
        let environment = BrewEnvironment.compose(
            inheriting: hostileParent,
            commandOverrides: [.noAutoremove]
        )

        #expect(environment == [
            "PATH": "/custom/bin:/usr/bin:/bin",
            "HOME": "/Users/tester",
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_COLOR": "1",
            "HOMEBREW_NO_EMOJI": "1",
            "HOMEBREW_NO_AUTOREMOVE": "1",
        ])
    }

    @Test("A command without cleanup overrides cannot inherit autoremove policy")
    func absentOverrideStaysAbsent() {
        let environment = BrewEnvironment.compose(
            inheriting: hostileParent,
            commandOverrides: []
        )

        #expect(environment["HOMEBREW_NO_AUTOREMOVE"] == nil)
        #expect(environment["HOMEBREW_GITHUB_API_TOKEN"] == nil)
        #expect(environment["PATH"] == hostileParent["PATH"])
        #expect(environment["HOME"] == hostileParent["HOME"])
    }

    @Test("BrewRunner carries typed command overrides to the process seam")
    func runnerCarriesCommandOverrides() async throws {
        let launcher = FakeProcessLauncher()
        let runner = BrewRunner(installation: .fixture, launcher: launcher)
        let command = BrewCommand.read(
            ["cleanup", "--dry-run"],
            environmentOverrides: [.noAutoremove]
        )

        _ = try await runner.start(command)

        let spec = try #require(launcher.recordedSpecs.first)
        #expect(spec.arguments == ["cleanup", "--dry-run"])
        #expect(spec.environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
        #expect(spec.executableURL == BrewInstallation.fixture.executableURL)
    }

    @Test("Authorized FIFO mutations retain command-local overrides")
    func authorizedMutationCarriesCommandOverrides() async throws {
        let launcher = FakeProcessLauncher()
        let process = FakeProcess()
        launcher.enqueue(process)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        let operation = try await runner.start(
            BrewMutation(arguments: ["cleanup", "--prune=all"]),
            environmentOverrides: [.noAutoremove]
        )
        await launcher.waitForLaunches(atLeast: 1)
        process.terminate(with: BrewExit(status: 0, reason: .exited))
        _ = await operation.terminal()

        let spec = try #require(launcher.recordedSpecs.first)
        #expect(spec.arguments == ["cleanup", "--prune=all"])
        #expect(spec.environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
    }
}
