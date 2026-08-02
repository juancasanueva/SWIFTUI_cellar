import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// Threat row — **subprocess argument composition**.
///
/// This change adds exactly one new `brew` invocation. The vector it runs is a
/// compile-time constant: there is no interpolation, no joining, no shell, and
/// no parameter through which a package name, a search query or a catalog record
/// could reach argv.
@Suite("Installed snapshot argument composition")
struct InstalledArgvTests {
    static let expectedVector = ["info", "--installed", "--json=v2"]

    @Test("The snapshot command is the fixed read-only vector")
    func commandIsTheFixedReadVector() {
        #expect(BrewInfoPayloadSource.command == BrewCommand.read(Self.expectedVector))
        #expect(BrewInfoPayloadSource.command.arguments == Self.expectedVector)
    }

    /// `.read` is what keeps a re-snapshot out of M2-2's mutation gate — and,
    /// more importantly, out of the class of commands that may change state.
    @Test("The snapshot command is a read, so it can never enter the mutation gate")
    func commandKindIsRead() {
        #expect(BrewInfoPayloadSource.command.kind == .read)
        #expect(BrewInfoPayloadSource.command.kind != .mutate)
    }

    @Test("The launched process is handed that exact vector, once")
    func launchedSpecCarriesTheExactVector() async throws {
        let launcher = RecordingProcessLauncher()
        let source = BrewInfoPayloadSource(launcher: launcher)

        _ = try await source.payload(using: TestInstallation.appleSilicon)

        #expect(launcher.launchCount == 1)
        let spec = try #require(launcher.specs.first)
        #expect(spec.arguments == Self.expectedVector)
        #expect(spec.executableURL == TestInstallation.appleSilicon.executableURL)
    }

    /// Triangulation, and the actual point: the *only* input that reaches the
    /// spawn is which `brew` to run. Two different installations produce two
    /// different executables and byte-identical argv.
    @Test(
        "A different installation changes the executable and nothing else",
        arguments: [TestInstallation.appleSilicon, TestInstallation.intel]
    )
    func argvIsIndependentOfTheInstallation(installation: BrewInstallation) async throws {
        let launcher = RecordingProcessLauncher()
        let source = BrewInfoPayloadSource(launcher: launcher)

        _ = try await source.payload(using: installation)

        let spec = try #require(launcher.specs.first)
        #expect(spec.arguments == Self.expectedVector)
        #expect(spec.executableURL == installation.executableURL)
        // No shell anywhere: the executable is `brew` itself and nothing in the
        // vector is a shell command word.
        #expect(spec.executableURL.lastPathComponent == "brew")
        #expect(spec.arguments.contains("-c") == false)
    }

    // MARK: - The glue around the pure function

    @Test("The adapter drains stdout and hands the whole document back")
    func adapterDrainsStdout() async throws {
        let document = "{\"formulae\":[],\"casks\":[]}"
        let launcher = RecordingProcessLauncher([ScriptedRun(stdout: document + "\n")])
        let source = BrewInfoPayloadSource(launcher: launcher)

        let payload = try await source.payload(using: TestInstallation.appleSilicon)

        #expect(String(decoding: payload, as: UTF8.self) == document)
    }

    @Test("A failing run surfaces the command failure rather than an empty document")
    func adapterSurfacesCommandFailure() async {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(
                stdout: "{\"formulae\":[],\"casks\":[]}\n",
                stderr: "Error: Another active Homebrew process is already running.\n",
                exit: BrewExit(status: 1, reason: .exited)
            )
        ])
        let source = BrewInfoPayloadSource(launcher: launcher)

        await #expect(throws: InstalledInventoryError.self) {
            try await source.payload(using: TestInstallation.appleSilicon)
        }
    }

    @Test("An unusable brew binary is reported as brew being unavailable")
    func unusableExecutableIsBrewUnavailable() async {
        let launcher = RecordingProcessLauncher(failingWith: POSIXError(.ENOENT))
        let source = BrewInfoPayloadSource(launcher: launcher)

        await #expect(throws: InstalledInventoryError.brewUnavailable) {
            try await source.payload(using: TestInstallation.appleSilicon)
        }
    }
}
