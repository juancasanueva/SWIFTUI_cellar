import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The headline invariant, proven rather than assumed
/// (`brewfile-management` BF1; threat rows TM1, TM2, TM3).
///
/// > **brew is never pointed at a file Cellar did not write.**
///
/// Every other test in this change asserts a behaviour. This one asserts the
/// property the whole change exists for: across the entire Brewfile surface, no
/// element of any `brew` argv derives from a path the user chose or from a raw
/// line of the file they supplied, and every `--file` value is a path this
/// capability created under a Cellar-owned temporary location.
///
/// Probe U8 is why that matters and is not paranoia: `brew bundle check --file
/// <path>` **evaluates** the Brewfile's Ruby, and a `File.write` payload left
/// its marker on disk. Handing brew a stranger's file runs a stranger's code.
@MainActor
@Suite("Brewfile argv structure", .timeLimit(.minutes(1)))
struct BrewfileArgvStructureTests {

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: BrewfileFixtureManifest.root.appendingPathComponent(name))
    }

    /// Every `bundle` subcommand that is forbidden, and why the list exists.
    static let forbiddenBundleSubcommands = [
        "install", "upgrade", "check", "cleanup", "list",
        "exec", "sh", "env", "add", "remove", "edit"
    ]

    // MARK: - BF1 — nothing user-chosen reaches argv

    /// The whole surface, driven end to end: a user-chosen source path, a
    /// hostile file, a real captured dump, a selection, a submission, and an
    /// export with a user-chosen destination.
    @Test("No brew argv element derives from a user path or a raw file line")
    func noBrewArgvElementDerivesFromAUserPathOrARawFileLine() async throws {
        let chosenSource = URL(fileURLWithPath: "/Users/someone/Downloads/Untrusted Brewfile")
        let chosenDestination = URL(fileURLWithPath: "/Users/someone/Desktop/My Brewfile")
        let hostile = try Self.fixture("hostile-ruby.brewfile")

        let fileSystem = RecordingFileSystem(contents: [chosenSource: hostile])
        let store = BrewfileStore(fileSystem: fileSystem)

        // Import: read the user's file, project it, plan it, submit it.
        await store.importFile(at: chosenSource, installed: .empty, taps: .empty)
        let plan = try #require(store.plan)
        let harness = CenterHarness()
        for command in plan.commands { harness.center.submit(command) }
        await harness.settle()

        // Export: dump to a Cellar temp, then publish to the user's choice.
        fileSystem.answerSubprocessWrite(with: try Self.fixture("dump-file.brewfile"))
        let exportLauncher = RecordingProcessLauncher([ScriptedRun(stdout: "", stderr: "")])
        let source = BundleDumpSource(
            launcher: exportLauncher,
            fileSystem: fileSystem,
            temporaryRoot: URL(fileURLWithPath: "/var/folders/xx/T")
        )
        await store.export(using: source, detection: .detected(TestInstallation.appleSilicon))
        await store.publish(to: StubDestinationChooser(destination: chosenDestination))

        // Positive anchor: something really did run, and something really was
        // written — otherwise every absence below is vacuous.
        #expect(harness.launcher.launchCount == 1, "the import submitted nothing")
        #expect(exportLauncher.launchCount == 1, "the export ran nothing")
        #expect(fileSystem.bytes(at: chosenDestination) != nil, "nothing was published")

        // Now the absences, over **every** argument of **every** spawn.
        let everyArgument = harness.launcher.recordedSpecs.flatMap(\.arguments)
            + exportLauncher.specs.flatMap(\.arguments)
        #expect(everyArgument.isEmpty == false)

        for path in [chosenSource.path, chosenDestination.path, "/Users/someone"] {
            #expect(
                everyArgument.contains { $0.contains(path) } == false,
                "a user-chosen path reached argv: \(path)"
            )
        }

        // And no raw line of the hostile file, either — including the payloads
        // that would have been the interesting ones to smuggle through.
        for raw in [
            "File.write", "system(", "`touch", "$(touch", "OS.mac?", "unless",
            "#{ENV['HOME']}/x", "wget; rm -rf /", "--force\"", "postinstall"
        ] {
            #expect(
                everyArgument.contains { $0.contains(raw) } == false,
                "a raw file line reached argv: \(raw)"
            )
        }

        // The one thing that did survive is the one ordinary entry, admitted
        // through the shipped typed identity.
        #expect(harness.launcher.recordedSpecs.first?.arguments == ["install", "--formula", "ripgrep"])
    }

    @Test("Every --file value is a Cellar-created temporary path")
    func everyFileValueIsACellarCreatedTemporaryPath() async throws {
        let temporaryRoot = URL(fileURLWithPath: "/var/folders/xx/T")
        let launcher = RecordingProcessLauncher([ScriptedRun(stdout: "", stderr: "")])
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: try Self.fixture("dump-file.brewfile"))

        _ = try await BundleDumpSource(
            launcher: launcher,
            fileSystem: fileSystem,
            temporaryRoot: temporaryRoot
        ).dump(for: .detected(TestInstallation.appleSilicon))

        let arguments = try #require(launcher.specs.first?.arguments)
        let index = try #require(arguments.firstIndex(of: "--file"))
        let value = arguments[index + 1]

        #expect(value.hasPrefix(temporaryRoot.path + "/cellar-brewfile/"))
        #expect(value.hasSuffix("/Brewfile"))
        // Cellar made the directory before brew was asked for anything.
        #expect(fileSystem.calls.contains { call in
            if case .createDirectory(let url) = call {
                return value.hasPrefix(url.path)
            }
            return false
        })
    }

    /// The submission path carries no `--file` at all: an import is not a
    /// `bundle` invocation, it is N ordinary installs.
    @Test("An import spawns no bundle invocation of any kind")
    func anImportSpawnsNoBundleInvocationOfAnyKind() async throws {
        let url = URL(fileURLWithPath: "/Users/someone/Brewfile")
        let fileSystem = RecordingFileSystem(
            contents: [url: try Self.fixture("mixed-kinds.brewfile")]
        )
        let store = BrewfileStore(fileSystem: fileSystem)
        await store.importFile(at: url, installed: .empty, taps: .empty)

        let harness = CenterHarness()
        let plan = try #require(store.plan)
        #expect(plan.commands.isEmpty == false, "the fixture produced nothing to submit")
        for command in plan.commands { harness.center.submit(command) }
        await harness.settle()

        let everyArgument = harness.launcher.recordedSpecs.flatMap(\.arguments)
        #expect(everyArgument.contains("bundle") == false, "an import reached brew bundle")
        #expect(everyArgument.contains("--file") == false)
        for subcommand in Self.forbiddenBundleSubcommands {
            #expect(
                harness.launcher.recordedSpecs.contains { $0.arguments.first == "bundle" } == false,
                "an import reached bundle \(subcommand)"
            )
        }
    }

    // MARK: - Source scan (task 8.2)

    /// Comments are stripped first, so a prohibition *described* in a doc
    /// comment — and these files describe theirs at length — is never mistaken
    /// for one *violated* in code.
    @Test("No Brewfile source can spawn, shell out, import AppKit or evaluate Ruby")
    func noBrewfileSourceCanSpawnShellOutOrEvaluateRuby() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)

        let surface = sources.filter {
            $0.name.hasPrefix("Brewfile") || $0.name.hasPrefix("BundleDump")
        }
        #expect(surface.count == 8, "the Brewfile surface changed size: \(surface.map(\.name))")

        for source in surface {
            for forbidden in ["/bin/sh", "/bin/bash", "/usr/bin/env", "eval(", "NSTask"] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) contains \(forbidden)"
                )
            }
            // Whole-identifier, so `BrewfileSkipReason.rubyConditional` — a
            // *name for a refusal* — is not mistaken for an interpreter.
            for identifier in ["Process", "NSAppleScript", "dlopen", "system", "ruby", "Ruby"] {
                #expect(
                    source.code.containsIdentifier(identifier) == false,
                    "\(source.name) reaches for \(identifier)"
                )
            }
            #expect(source.code.contains("import AppKit") == false)
            #expect(source.code.contains("import SwiftUI") == false)
        }

        // `BundleDumpSource` is the only file on this surface that may hold a
        // launcher at all, and it holds the **seam**, never a concrete process.
        let dump = try #require(surface.first { $0.name == "BundleDumpSource.swift" })
        #expect(dump.code.contains("any ProcessLaunching"))
        for other in surface where other.name != "BundleDumpSource.swift" {
            #expect(
                other.code.containsIdentifier("ProcessLaunching") == false,
                "\(other.name) can launch a process"
            )
        }
    }

    @Test(
        "No forbidden bundle subcommand string exists anywhere on the surface",
        arguments: [
            "install", "upgrade", "check", "cleanup", "list",
            "exec", "sh", "env", "add", "remove", "edit"
        ]
    )
    func noForbiddenBundleSubcommandStringExists(subcommand: String) throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)

        for source in sources
        where source.name.hasPrefix("Brewfile") || source.name.hasPrefix("BundleDump") {
            // As a *bundle argument*: the literal beside the `bundle` token.
            #expect(
                source.code.contains("\"bundle\", \"\(subcommand)\"") == false,
                "\(source.name) can spell bundle \(subcommand)"
            )
        }

        let command = try #require(sources.first { $0.name == "BundleDumpCommand.swift" })
        #expect(command.code.contains("\"bundle\", Subcommand.dump.rawValue"))
        #expect(BundleDumpCommand.Subcommand(rawValue: subcommand) == nil)
    }

    // MARK: - U10 divergence (task 8.4) — a check, never a gate

    /// Cellar's reading of a **real** dump, compared against the file byte for
    /// byte. Every line must land as a typed entry or a **named** skip, with
    /// zero `unrecognisedLine`.
    ///
    /// Recorded as a divergence check rather than a gate: if the real world
    /// disagrees with the grammar, that becomes a row in `design.md` →
    /// *Apply-Time Amendments*, never a silent parser tweak.
    @Test("Every line of the captured dump lands as a typed entry or a named skip")
    func everyLineOfTheCapturedDumpLandsAsATypedEntryOrANamedSkip() async throws {
        let data = try Self.fixture("dump-file.brewfile")
        let document = try await BrewfileParser.decode(data)

        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.trimmingCharacters(in: .whitespaces).isEmpty == false }
        let meaningful = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") == false }

        #expect(meaningful.count == 79, "the capture's line count changed")
        #expect(
            document.entries.count + document.skips.count == meaningful.count,
            "\(meaningful.count - document.entries.count - document.skips.count) lines went unaccounted for"
        )

        // The divergence itself: not one line fell through to the generic
        // reason. Every refusal has something to say about *why*.
        let unrecognised = document.skips
            .filter { $0.reason.category == .unrecognisedLine }
            .map(\.rawLine)
        #expect(unrecognised.isEmpty, "a real dump line was unrecognised: \(unrecognised)")
        #expect(document.skips.map(\.reason) == [.unsupportedOption("link")])
        #expect(document.skips.allSatisfy { $0.reason.detail != nil || $0.reason.category != .unsupportedOption })

        // And every comment line really was ignored rather than counted, which
        // is what keeps a real round-trip from looking lossy.
        #expect(lines.count - meaningful.count == 69)
    }
}
