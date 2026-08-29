import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// Threat row — **subprocess argument composition**, for npm's read path.
///
/// This change adds exactly two npm invocations for reading. Both vectors are
/// compile-time constants: no interpolation, no joining, no shell, and no
/// parameter through which a package name from a hostile `ls` payload could
/// reach argv. Mirrors `InstalledArgvTests` deliberately — the same claim, made
/// the same way, for the other source.
@Suite("npm read argument composition")
struct NpmArgvTests {
    static let listVector = ["ls", "-g", "--json", "--depth=0"]
    static let outdatedVector = ["outdated", "-g", "--json"]

    private static let environment = NpmEnvironment(
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/npm"),
        version: "10.9.2",
        prefix: URL(fileURLWithPath: "/opt/homebrew"),
        origin: .homebrew
    )

    private static func launcher(stdout: String) -> RecordingProcessLauncher {
        RecordingProcessLauncher([ScriptedRun(stdout: stdout)])
    }

    @Test("The two read commands are the fixed vectors")
    func commandsAreTheFixedVectors() {
        #expect(NpmPayloadSource.listArguments == Self.listVector)
        #expect(NpmPayloadSource.outdatedArguments == Self.outdatedVector)
    }

    @Test("A listing refresh spawns exactly one process with exactly that vector")
    func listingSpawnsOnceWithTheExactVector() async throws {
        let launcher = Self.launcher(stdout: #"{"name":"lib","dependencies":{}}"#)
        let source = NpmPayloadSource(launcher: launcher)

        _ = try await source.installed(using: Self.environment)

        #expect(launcher.launchCount == 1)
        let spec = try #require(launcher.specs.first)
        #expect(spec.arguments == Self.listVector)
        #expect(spec.executableURL == Self.environment.executableURL)
    }

    @Test("An outdated refresh spawns exactly one process with exactly that vector")
    func outdatedSpawnsOnceWithTheExactVector() async throws {
        let launcher = Self.launcher(stdout: "{}")
        let source = NpmPayloadSource(launcher: launcher)

        _ = try await source.outdated(using: Self.environment)

        #expect(launcher.launchCount == 1)
        let spec = try #require(launcher.specs.first)
        #expect(spec.arguments == Self.outdatedVector)
    }

    /// Triangulation, and the actual point: the *only* input that reaches the
    /// spawn is which npm to run. Two different environments produce two
    /// different executables and byte-identical argv.
    @Test("A different npm changes the executable and nothing else")
    func argvIsIndependentOfTheEnvironment() async throws {
        let other = NpmEnvironment(
            executableURL: URL(fileURLWithPath: "/Users/tester/.volta/bin/npm"),
            version: "9.0.0",
            prefix: URL(fileURLWithPath: "/Users/tester/.volta"),
            origin: .volta
        )
        let launcher = Self.launcher(stdout: #"{"name":"lib","dependencies":{}}"#)

        _ = try await NpmPayloadSource(launcher: launcher).installed(using: other)

        let spec = try #require(launcher.specs.first)
        #expect(spec.arguments == Self.listVector)
        #expect(spec.executableURL == other.executableURL)
        // No shell anywhere: the executable is npm itself.
        #expect(spec.executableURL.lastPathComponent == "npm")
    }

    @Test("Neither vector carries a package name, a registry or an extra flag")
    func vectorsCarryNothingElse() {
        for vector in [Self.listVector, Self.outdatedVector] {
            #expect(vector.contains { $0.contains("registry") } == false)
            #expect(vector.contains("--force") == false)
            #expect(vector.contains { $0.hasPrefix("@") } == false)
        }
        // Exact, not merely "contains what it should": an extra flag would pass
        // a containment check and change what npm does.
        #expect(Self.listVector.count == 4)
        #expect(Self.outdatedVector.count == 3)
    }

    @Test("The npm exit rule does not reach the three brew JSON payload sources")
    func brewJsonTrioIsUntouched() {
        // Their vectors are unchanged, and — the part that matters — their
        // acceptance rule still refuses every non-zero exit.
        #expect(BrewInfoPayloadSource.command.arguments == ["info", "--installed", "--json=v2"])

        let lines = [LogLine(stream: .stdout, text: #"{"formulae":[],"casks":[]}"#, sequence: 0)]
        #expect(throws: InstalledInventoryError.self) {
            try InstalledPayload.payload(
                from: lines, exit: BrewExit(status: 1, reason: .exited)
            )
        }
        // The same input, under npm's rule, is accepted. Two rules, both alive.
        #expect(throws: Never.self) {
            try NpmPayload.installed(from: lines, exit: BrewExit(status: 1, reason: .exited))
        }
    }
}
