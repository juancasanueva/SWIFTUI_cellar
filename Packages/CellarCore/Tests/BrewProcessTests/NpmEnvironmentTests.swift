import Foundation
import Testing

@testable import BrewProcess

/// npm's environment is composed under the same allow-list discipline as brew's,
/// with different pins and one extra obligation: `PATH` must be *prepended* with
/// the selected npm's bin directory. `npm` is a `#!/usr/bin/env node` script, and
/// a GUI process's inherited `PATH` frequently has no `node` in it at all.
@Suite("Normalized npm environment")
struct NpmEnvironmentTests {
    private static let hostileParent = [
        "PATH": "/usr/bin:/bin",
        "HOME": "/Users/tester",
        "SHELL": "/bin/zsh",
        "HOMEBREW_NO_AUTO_UPDATE": "0",
        "HOMEBREW_GITHUB_API_TOKEN": "secret",
        "NODE_OPTIONS": "--inspect",
        "npm_config_registry": "https://evil.example/",
        "NPM_TOKEN": "secret",
        "NO_COLOR": "0",
    ]

    private static func environment(
        at path: String = "/Users/tester/.volta/bin/npm"
    ) -> NpmEnvironment {
        NpmEnvironment(
            executableURL: URL(fileURLWithPath: path),
            version: "10.9.2",
            prefix: URL(fileURLWithPath: "/Users/tester/.volta"),
            origin: .volta
        )
    }

    @Test("The selected npm's bin directory is prepended to the inherited PATH")
    func pathIsPrependedWithTheBinDirectory() {
        let composed = Self.environment().processEnvironment(inheriting: Self.hostileParent)

        #expect(composed["PATH"] == "/Users/tester/.volta/bin:/usr/bin:/bin")
    }

    /// Asserted on `path` rather than on the `URL`. `URL(fileURLWithPath:)`
    /// consults the file system to decide whether to append a trailing slash, so
    /// a `URL` comparison here would pass or fail depending on whether the
    /// machine running the tests happens to have that directory — which is
    /// exactly the kind of test that goes green locally and red in CI.
    @Test("The bin directory is derived from the executable, not supplied separately")
    func binDirectoryFollowsTheExecutable() {
        #expect(
            Self.environment(at: "/opt/homebrew/bin/npm").binDirectory.path
                == "/opt/homebrew/bin"
        )
        #expect(
            Self.environment(at: "/Users/tester/.nvm/versions/node/v22.3.0/bin/npm")
                .binDirectory.path == "/Users/tester/.nvm/versions/node/v22.3.0/bin"
        )
    }

    @Test("HOME is inherited so the user's npmrc still applies")
    func homeIsInherited() {
        let composed = Self.environment().processEnvironment(inheriting: Self.hostileParent)

        #expect(composed["HOME"] == "/Users/tester")
    }

    @Test("The composed keys are exactly PATH, HOME and the seven pins")
    func nothingElseSurvivesComposition() {
        let composed = Self.environment().processEnvironment(inheriting: Self.hostileParent)

        #expect(
            Set(composed.keys) == [
                "PATH",
                "HOME",
                "NO_COLOR",
                "npm_config_color",
                "npm_config_progress",
                "npm_config_update_notifier",
                "npm_config_fund",
                "npm_config_audit",
                "npm_config_loglevel",
            ]
        )
        // Named individually as well, because a set comparison that starts
        // failing gets "fixed" by widening the expected set.
        #expect(composed["SHELL"] == nil)
        #expect(composed["NODE_OPTIONS"] == nil)
        #expect(composed["npm_config_registry"] == nil)
        #expect(composed["NPM_TOKEN"] == nil)
    }

    @Test("The seven pins carry exactly these values, and a hostile parent cannot move them")
    func pinsWinOverTheParent() {
        let composed = Self.environment().processEnvironment(inheriting: Self.hostileParent)

        #expect(composed["NO_COLOR"] == "1")
        #expect(composed["npm_config_color"] == "false")
        #expect(composed["npm_config_progress"] == "false")
        #expect(composed["npm_config_update_notifier"] == "false")
        #expect(composed["npm_config_fund"] == "false")
        #expect(composed["npm_config_audit"] == "false")
        #expect(composed["npm_config_loglevel"] == "warn")
    }

    @Test("No Homebrew key is ever set for an npm invocation")
    func noHomebrewKeyLeaksIn() {
        let composed = Self.environment().processEnvironment(inheriting: Self.hostileParent)

        #expect(composed.keys.contains { $0.hasPrefix("HOMEBREW_") } == false)
        #expect(composed["HOMEBREW_NO_AUTO_UPDATE"] == nil)
        #expect(composed["HOMEBREW_GITHUB_API_TOKEN"] == nil)
    }

    @Test("A parent with no PATH still gets the bin directory")
    func absentParentPathStillYieldsTheBinDirectory() {
        let composed = Self.environment().processEnvironment(inheriting: ["HOME": "/Users/tester"])

        #expect(composed["PATH"] == "/Users/tester/.volta/bin")
        #expect(composed["HOME"] == "/Users/tester")
    }

    @Test("A parent with no HOME composes without one rather than inventing it")
    func absentParentHomeIsNotInvented() {
        let composed = Self.environment().processEnvironment(inheriting: ["PATH": "/usr/bin"])

        #expect(composed["HOME"] == nil)
        #expect(composed["PATH"] == "/Users/tester/.volta/bin:/usr/bin")
    }

    @Test("Two environments describing the same npm are equal")
    func equalityIsByValue() {
        #expect(Self.environment() == Self.environment())
        #expect(Self.environment() != Self.environment(at: "/usr/local/bin/npm"))
    }
}
