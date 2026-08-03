import Foundation
import Testing

@testable import BrewProcess

@Suite("Normalized brew environment")
struct EnvironmentTests {
    private let hostileParent = [
        "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
        "HOME": "/Users/tester",
        "HOMEBREW_NO_AUTO_UPDATE": "0",
        "HOMEBREW_COLOR": "1",
        "HOMEBREW_NO_EMOJI": "0",
        "HOMEBREW_NO_INSTALL_FROM_API": "1",
        "HOMEBREW_GITHUB_API_TOKEN": "secret",
    ]

    @Test("Pinned values win over a parent environment that sets them differently")
    func pinnedValuesOverrideTheParentEnvironment() {
        let environment = BrewEnvironment.compose(inheriting: hostileParent)

        #expect(environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
        #expect(environment["HOMEBREW_NO_COLOR"] == "1")
        #expect(environment["HOMEBREW_NO_EMOJI"] == "1")
    }

    /// `HOMEBREW_COLOR` is a **force**-colour boolean in brew
    /// (`env_config.rb:249-252`, declared `disabled_by: :HOMEBREW_NO_COLOR`):
    /// any value counts as set, `"0"` included. Pinning it to `"0"` therefore
    /// produced the exact opposite of the stated intent, verified by an `od -c`
    /// probe with stdout redirected to a file (defect #7179).
    ///
    /// The assertion is `== nil` rather than `!= "0"` on purpose: "not that one
    /// wrong value" would still pass with `"false"`, `"no"` or `""` pinned, and
    /// every one of those forces colour on.
    @Test("The force-colour key is never set at any value")
    func theForceColourKeyIsNeverSetAtAnyValue() {
        #expect(BrewEnvironment.pinned["HOMEBREW_COLOR"] == nil)
        #expect(BrewEnvironment.pinned["HOMEBREW_NO_COLOR"] == "1")

        // And composition cannot reintroduce it from a parent that sets it.
        let environment = BrewEnvironment.compose(inheriting: hostileParent)
        #expect(environment["HOMEBREW_COLOR"] == nil)
        #expect(environment["HOMEBREW_NO_COLOR"] == "1")
    }

    @Test("HOMEBREW_NO_INSTALL_FROM_API is never set, even if the parent sets it")
    func apiModeStaysAtItsDefault() {
        let environment = BrewEnvironment.compose(inheriting: hostileParent)

        #expect(environment["HOMEBREW_NO_INSTALL_FROM_API"] == nil)
        #expect(environment.keys.contains("HOMEBREW_GITHUB_API_TOKEN") == false)
    }

    @Test("PATH and HOME are inherited from the parent environment")
    func pathAndHomeAreInherited() {
        let environment = BrewEnvironment.compose(inheriting: hostileParent)

        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/bin:/bin")
        #expect(environment["HOME"] == "/Users/tester")
    }

    @Test("A parent without PATH or HOME yields an environment without them")
    func missingInheritedKeysAreNotInvented() {
        let environment = BrewEnvironment.compose(inheriting: [:])

        #expect(environment["PATH"] == nil)
        #expect(environment["HOME"] == nil)
        #expect(environment["HOMEBREW_NO_COLOR"] == "1")
    }

    @Test("Every launched command carries the normalized environment")
    func environmentIsAppliedToEveryInvocation() async throws {
        let launcher = FakeProcessLauncher()
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.read(["list"]))
        _ = try await runner.start(.read(["outdated"]))

        #expect(launcher.recordedSpecs.count == 2)
        for spec in launcher.recordedSpecs {
            #expect(spec.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1")
            #expect(spec.environment["HOMEBREW_NO_COLOR"] == "1")
            #expect(spec.environment["HOMEBREW_NO_EMOJI"] == "1")
            #expect(spec.environment["HOMEBREW_NO_INSTALL_FROM_API"] == nil)
        }
    }

    /// Asserting `pinned` alone would leave the key reintroducible anywhere
    /// between `BrewEnvironment` and `SystemProcess` — a later `spec.environment`
    /// merge, a runner default, a plumbing convenience. This drives a real spawn
    /// through the launcher seam and reads back what the *process* would have
    /// received, for a mutation as well as a read.
    @Test("The spawned process receives the suppression key and not the force key")
    func theSpawnedProcessReceivesTheSuppressionKeyAndNotTheForceKey() async throws {
        let launcher = FakeProcessLauncher()
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.read(["services", "list", "--json"]))
        _ = try await runner.start(.mutate(["services", "start", "atuin"]))
        // A mutation is launched by the gate, not by `start`, so both specs are
        // only recorded once the queue has actually spawned them.
        await launcher.waitForLaunches(atLeast: 2)

        #expect(launcher.recordedSpecs.count == 2)
        for spec in launcher.recordedSpecs {
            #expect(
                spec.environment["HOMEBREW_COLOR"] == nil,
                "the force-colour key reached the spawned process"
            )
            #expect(spec.environment["HOMEBREW_NO_COLOR"] == "1")
        }
    }
}
