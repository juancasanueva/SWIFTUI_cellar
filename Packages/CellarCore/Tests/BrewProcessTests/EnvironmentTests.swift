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
        #expect(environment["HOMEBREW_COLOR"] == "0")
        #expect(environment["HOMEBREW_NO_EMOJI"] == "1")
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
        #expect(environment["HOMEBREW_COLOR"] == "0")
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
            #expect(spec.environment["HOMEBREW_COLOR"] == "0")
            #expect(spec.environment["HOMEBREW_NO_EMOJI"] == "1")
            #expect(spec.environment["HOMEBREW_NO_INSTALL_FROM_API"] == nil)
        }
    }
}
