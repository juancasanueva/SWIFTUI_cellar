import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// Acquisition for the export (`brewfile-management` BF8, threat row TM3,
/// design DD3).
///
/// `brew` writes to a path **Cellar created for this export and nothing else**.
/// That is what makes `--force` safe to pass: there is no user file at the other
/// end of it. The save panel opens only after a successful preview, so a dump
/// failure never reaches the user's disk at all.
///
/// The temporary directory is removed on success, on failure and on
/// cancellation. All three are asserted, because the failure paths are exactly
/// the ones a `defer` is easy to forget on.
@Suite("Bundle dump source", .timeLimit(.minutes(1)))
struct BundleDumpSourceTests {

    static let temporaryRoot = URL(fileURLWithPath: "/var/folders/xx/T")
    static let document = "tap \"acme/tap\"\nbrew \"wget\"\n"

    static func source(
        launcher: any ProcessLaunching,
        fileSystem: RecordingFileSystem
    ) -> BundleDumpSource {
        BundleDumpSource(
            launcher: launcher,
            fileSystem: fileSystem,
            temporaryRoot: Self.temporaryRoot
        )
    }

    static func succeedingLauncher(stderr: String = "") -> RecordingProcessLauncher {
        RecordingProcessLauncher([ScriptedRun(stdout: "", stderr: stderr)])
    }

    // MARK: - TM3 — the file is always Cellar's

    @Test("Every export names a fresh Cellar-owned temporary path")
    func everyExportNamesAFreshCellarOwnedTemporaryPath() async throws {
        let launcher = Self.succeedingLauncher()
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: Data(Self.document.utf8))
        let source = Self.source(launcher: launcher, fileSystem: fileSystem)

        _ = try await source.dump(for: .detected(TestInstallation.appleSilicon))
        _ = try await source.dump(for: .detected(TestInstallation.appleSilicon))

        #expect(launcher.launchCount == 2)
        let paths = launcher.specs.map { spec -> String in
            let index = spec.arguments.firstIndex(of: "--file")!
            return spec.arguments[index + 1]
        }
        #expect(paths.count == 2)
        #expect(paths[0] != paths[1], "two exports reused the same temporary path")
        for path in paths {
            #expect(path.hasPrefix(Self.temporaryRoot.path + "/cellar-brewfile/"))
            #expect(path.hasSuffix("/Brewfile"))
        }

        // The directory was created by Cellar before brew was asked for
        // anything, which is what makes `--force` unable to reach a user file.
        let created = fileSystem.calls.compactMap { call -> URL? in
            guard case .createDirectory(let url) = call else { return nil }
            return url
        }
        #expect(created.count == 2)
        #expect(created.allSatisfy { $0.path.contains("/cellar-brewfile/") })
    }

    @Test("A user-obtained path appears in no brew argv at any stage")
    func aUserObtainedPathAppearsInNoBrewArgv() async throws {
        let chosen = URL(fileURLWithPath: "/Users/someone/Documents/Brewfile")
        let launcher = Self.succeedingLauncher()
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: Data(Self.document.utf8))
        let source = Self.source(launcher: launcher, fileSystem: fileSystem)

        let result = try await source.dump(for: .detected(TestInstallation.appleSilicon))

        // Publication is a separate step, and it is Cellar's own write through
        // the shipped file-system seam — never an argument to a subprocess.
        try fileSystem.write(result.document, to: chosen)

        let everyArgument = launcher.specs.flatMap(\.arguments)
        #expect(everyArgument.contains(chosen.path) == false)
        #expect(everyArgument.contains { $0.contains("/Users/someone") } == false)
        #expect(fileSystem.bytes(at: chosen) == Data(Self.document.utf8))
    }

    // MARK: - BF8 — exit zero, and the stream split

    @Test("Exit zero reads the document from the temporary file")
    func exitZeroReadsTheDocumentFromTheTemporaryFile() async throws {
        let launcher = Self.succeedingLauncher()
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: Data(Self.document.utf8))

        let result = try await Self.source(launcher: launcher, fileSystem: fileSystem)
            .dump(for: .detected(TestInstallation.appleSilicon))

        #expect(result.document == Data(Self.document.utf8))

        // Read from the file brew was pointed at, not from stdout.
        let read = fileSystem.calls.compactMap { call -> URL? in
            guard case .read(let url) = call else { return nil }
            return url
        }
        #expect(read.count == 1)
        #expect(read.first?.lastPathComponent == "Brewfile")
    }

    /// U6 observed an unrelated `libtiff`/`webp` warning on stderr at exit `0`.
    /// A source that treated a non-empty stderr as failure would report a
    /// perfectly good export as an error; one that concatenated the streams
    /// would put the warning inside the published Brewfile.
    @Test("A warning on stderr at exit zero is still a success")
    func aWarningOnStderrAtExitZeroIsStillASuccess() async throws {
        let stderr = try String(
            contentsOf: BrewfileFixtureManifest.root.appendingPathComponent("dump-stderr.txt"),
            encoding: .utf8
        )
        #expect(stderr.isEmpty == false, "the replayed capture is empty, so this proves nothing")

        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: Data(Self.document.utf8))
        let result = try await Self.source(
            launcher: Self.succeedingLauncher(stderr: stderr),
            fileSystem: fileSystem
        ).dump(for: .detected(TestInstallation.appleSilicon))

        #expect(result.document == Data(Self.document.utf8))
        #expect(result.rawStderr == Data(stderr.utf8))
        // No byte of stderr appears anywhere in the document.
        #expect(String(decoding: result.document, as: UTF8.self).contains("circular dependency") == false)
        #expect(String(decoding: result.document, as: UTF8.self) == Self.document)
    }

    // MARK: - BF8 — a non-zero exit keeps both streams

    @Test("A non-zero exit is a typed failure that keeps both raw streams")
    func aNonZeroExitIsATypedFailureThatKeepsBothRawStreams() async throws {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(
                stdout: "partial\n",
                stderr: "Error: something went wrong\n",
                exit: BrewExit(status: 1, reason: .exited)
            )
        ])
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: Data(Self.document.utf8))

        await #expect(throws: BundleDumpError.self) {
            _ = try await Self.source(launcher: launcher, fileSystem: fileSystem)
                .dump(for: .detected(TestInstallation.appleSilicon))
        }

        do {
            _ = try await Self.source(launcher: launcher, fileSystem: fileSystem)
                .dump(for: .detected(TestInstallation.appleSilicon))
            Issue.record("a non-zero exit was reported as a success")
        } catch {
            guard case .commandFailed(let status, let stdout, let stderr) = error else {
                Issue.record("a non-zero exit produced \(error) rather than a command failure")
                return
            }
            #expect(status == 1)
            #expect(stdout == Data("partial\n".utf8))
            #expect(stderr == Data("Error: something went wrong\n".utf8))
        }
    }

    @Test("An undetected brew is a typed unavailability, not an empty document")
    func anUndetectedBrewIsATypedUnavailability() async throws {
        let fileSystem = RecordingFileSystem()
        let source = Self.source(launcher: Self.succeedingLauncher(), fileSystem: fileSystem)

        do {
            _ = try await source.dump(for: .absent)
            Issue.record("an absent brew produced a document")
        } catch {
            guard case .unavailable = error else {
                Issue.record("an absent brew produced \(error)")
                return
            }
        }
        #expect(fileSystem.calls.isEmpty, "a temporary directory was created for a run that never ran")
    }

    // MARK: - BF8 — the temporary file never survives the attempt

    @Test("The temporary directory is removed after a successful export")
    func theTemporaryDirectoryIsRemovedAfterASuccessfulExport() async throws {
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: Data(Self.document.utf8))

        _ = try await Self.source(launcher: Self.succeedingLauncher(), fileSystem: fileSystem)
            .dump(for: .detected(TestInstallation.appleSilicon))

        let removed = fileSystem.calls.compactMap { call -> URL? in
            guard case .removeItem(let url) = call else { return nil }
            return url
        }
        #expect(removed.count == 1)
        #expect(removed.first?.path.contains("/cellar-brewfile/") == true)
        #expect(fileSystem.containsAnything(under: Self.temporaryRoot) == false)
    }

    @Test("The temporary directory is removed after a failed export")
    func theTemporaryDirectoryIsRemovedAfterAFailedExport() async throws {
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: "", stderr: "boom\n", exit: BrewExit(status: 2, reason: .exited))
        ])
        let fileSystem = RecordingFileSystem()

        _ = try? await Self.source(launcher: launcher, fileSystem: fileSystem)
            .dump(for: .detected(TestInstallation.appleSilicon))

        #expect(fileSystem.calls.contains { call in
            if case .removeItem = call { return true } else { return false }
        })
        #expect(fileSystem.containsAnything(under: Self.temporaryRoot) == false)
    }

    @Test("The temporary directory is removed after a cancelled export")
    func theTemporaryDirectoryIsRemovedAfterACancelledExport() async throws {
        let launcher = ControllableProcessLauncher(honoursInterrupt: true)
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: Data(Self.document.utf8))
        let source = Self.source(launcher: launcher, fileSystem: fileSystem)

        let task = Task {
            try await source.dump(for: .detected(TestInstallation.appleSilicon))
        }
        await launcher.waitForLaunches(atLeast: 1)
        task.cancel()

        let outcome = await task.result
        #expect(throws: BundleDumpError.self) { _ = try outcome.get() }

        // The interrupt reached the process, and the directory is gone.
        #expect(launcher.launchedProcesses.first?.deliveredSignals.contains(.interrupt) == true)
        #expect(fileSystem.calls.contains { call in
            if case .removeItem = call { return true } else { return false }
        })
        #expect(fileSystem.containsAnything(under: Self.temporaryRoot) == false)
    }

    // MARK: - BF8 — an export acquires nothing else and records nothing

    @Test("An export acquires nothing else and writes no history entry")
    func anExportAcquiresNothingElseAndWritesNoHistoryEntry() async throws {
        let launcher = Self.succeedingLauncher()
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: Data(Self.document.utf8))

        _ = try await Self.source(launcher: launcher, fileSystem: fileSystem)
            .dump(for: .detected(TestInstallation.appleSilicon))

        #expect(launcher.launchCount == 1, "the export spawned more than the dump")
        let everyArgument = launcher.specs.flatMap(\.arguments)
        #expect(everyArgument.contains("info") == false, "an inventory probe was forced")
        #expect(everyArgument.contains("--json=v2") == false)

        // No history entry can exist, because nothing here holds a recorder:
        // the only file-system calls are the ones the temp lifecycle makes.
        let unexpected = fileSystem.calls.filter { call in
            switch call {
            case .createDirectory, .read, .removeItem: false
            default: true
            }
        }
        #expect(unexpected.isEmpty, "the export touched the disk outside its own temporary directory")
    }

    /// The structural half: this source has no queue, no gate and no recorder to
    /// reach for, so "submits no mutation" is the shape of the file rather than
    /// a promise about it.
    @Test("The dump source has no mutation spine to reach for")
    func theDumpSourceHasNoMutationSpineToReachFor() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let dump = try #require(sources.first { $0.name == "BundleDumpSource.swift" })

        for reach in [
            "OperationCenter", "HistoryRecording", "MutationGates", "AnyBrewMutation",
            "HistoryDraft", "InstalledPayloadSource", "AppKit"
        ] {
            #expect(
                dump.code.containsIdentifier(reach) == false,
                "BundleDumpSource.swift reaches for \(reach)"
            )
        }
        // The temp removal is on both paths, by `defer` rather than by two call
        // sites that could drift.
        #expect(dump.code.contains("defer"))
    }
}
