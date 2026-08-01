import Foundation
import Testing

@testable import BrewProcess

@Suite("Argument composition never reaches a shell")
struct ArgumentCompositionTests {
    @Test("A hostile argument arrives as one literal argv element")
    func hostileArgumentStaysOneElement() async throws {
        let hostile = "my formula; rm -rf / $(id) `whoami`"
        let launcher = FakeProcessLauncher()
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.read(["info", hostile]))

        let spec = try #require(launcher.recordedSpecs.first)
        #expect(spec.arguments == ["info", hostile])
        #expect(spec.arguments.count == 2)
    }

    @Test("The spawned executable is brew itself, never a shell")
    func executableIsBrewNotAShell() async throws {
        let launcher = FakeProcessLauncher()
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.mutate(["upgrade", "ripgrep"]))

        let spec = try #require(launcher.recordedSpecs.first)
        #expect(spec.executableURL == BrewInstallation.fixture.executableURL)
        #expect(spec.arguments.contains("-c") == false)
        #expect(spec.executableURL.path.contains("sh") == false)
    }

    @Test("Arguments are not reordered, deduplicated, or dropped")
    func argumentVectorIsPassedThroughUnchanged() async throws {
        let arguments = ["install", "--formula", "ripgrep", "--formula", "fd", ""]
        let launcher = FakeProcessLauncher()
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        _ = try await runner.start(.mutate(arguments))

        #expect(launcher.recordedSpecs.first?.arguments == arguments)
    }
}
