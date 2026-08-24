import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// `package-trust` PT1 :52-61 — how the report is acquired, and the two things
/// that acquisition must never do: name a package, or read Homebrew's state
/// files off the disk.
@Suite("Per-package trust acquisition")
struct TrustGrantSourceTests {
    // MARK: - PT1 :75-81 — the argv is a constant that names nothing

    /// **D-f, DD-11.** Homebrew 6 treats *naming* a `/`-qualified package to its
    /// trust machinery as **the grant** (`trust.rb#explicitly_allowed?`). This
    /// read therefore has to be incapable of naming one, not merely careful not
    /// to: three literal elements, no interpolation, no parameter.
    @Test("The grant read is a constant argv with no qualified token")
    func theGrantReadIsAConstantArgvWithNoQualifiedToken() async throws {
        let command = BrewTrustGrantPayloadSource.command

        #expect(command.arguments == ["trust", "--json", "v1"])
        #expect(command.kind == .read)
        for element in command.arguments {
            #expect(element.contains("/") == false, "the grant read argv carries a slash: \(element)")
            #expect(
                ["--formula", "--cask", "--tap", "--casks", "--formulae"].contains(element) == false,
                "the grant read argv carries a kind flag: \(element)"
            )
        }

        // Positively anchored: that constant really is what gets spawned, and it
        // is spawned exactly once for one read.
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: "{\"formulae\":[],\"casks\":[]}\n")
        ])
        let payload = try await BrewTrustGrantPayloadSource(launcher: launcher)
            .payload(using: TestInstallation.appleSilicon)

        #expect(String(decoding: payload, as: UTF8.self) == "{\"formulae\":[],\"casks\":[]}")
        #expect(launcher.specs.map(\.arguments) == [["trust", "--json", "v1"]])
        #expect(launcher.launchCount == 1)

        // …and the literal is a `static let`, so there is no parameter through
        // which a token could reach it. Asserted over the source, because "no
        // caller passes one today" is exactly the guarantee a later change ends.
        let source = try Self.trustGrantSources()["TrustGrantPayloadSource.swift"]
        let declaration = try #require(source)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.contains("BrewCommand.read(") }
        #expect(
            declaration == "static let command = BrewCommand.read([\"trust\", \"--json\", \"v1\"])",
            "the grant read's argv stopped being a constant declaration: \(declaration ?? "absent")"
        )
        #expect(try #require(declaration).contains("\\(") == false)
    }

    // MARK: - PT1 :99-105 — no path reads a trust file from disk

    /// `rules.apply`: *never manipulate the Cellar/Caskroom directly; always
    /// shell out to `brew`*. `trust.json`'s location varies by configuration and
    /// its format is Homebrew's private business, so the only honest acquisition
    /// is asking `brew` — on the failure paths as much as on the happy one.
    @Test("No path reads a trust file from disk")
    func noPathReadsATrustFileFromDisk() async throws {
        let sources = try Self.trustGrantSources()

        // Positively anchored: the scan really did find the files it covers. It
        // is a glob rather than a fixed list so a `TrustGrant…` file added later
        // is covered the day it lands, not the day somebody widens a list.
        #expect(sources.isEmpty == false, "the TrustGrant*.swift scan matched no files at all")
        #expect(
            Set(sources.keys).isSuperset(of: Self.coveredFiles),
            "the scan lost a file it is known to cover: \(sources.keys.sorted())"
        )

        for (name, code) in sources {
            for access in [
                "FileManager", "trust.json", ".homebrew", "XDG_CONFIG_HOME",
                "URL(fileURLWithPath:", "contentsOf:", "Data(contentsOf"
            ] {
                #expect(
                    code.contains(access) == false,
                    "\(name) reaches for Homebrew state on disk: \(access)"
                )
            }
        }

        // And the one acquisition there is really is the spawned read — on the
        // failure path too, where a "fallback" file read would be most tempting.
        let launcher = RecordingProcessLauncher([
            ScriptedRun(stdout: "", stderr: "Error: Unknown command: trust",
                        exit: BrewExit(status: 1, reason: .exited))
        ])
        let failing = BrewTrustGrantPayloadSource(launcher: launcher)
        await #expect {
            _ = try await failing.payload(using: TestInstallation.appleSilicon)
        } throws: { error in
            (error as? TrustGrantError)
                == .commandFailed(status: 1, message: "Error: Unknown command: trust")
        }
        #expect(launcher.specs.map(\.arguments) == [["trust", "--json", "v1"]])
    }

    /// The `TrustGrant…` sources this capability owns, keyed by file name.
    private static func trustGrantSources() throws -> [String: String] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrewClient")
        let names = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("TrustGrant") && $0.hasSuffix(".swift") }

        return try names.reduce(into: [:]) { files, name in
            files[name] = try String(
                contentsOf: directory.appendingPathComponent(name),
                encoding: .utf8
            )
        }
    }

    /// The files the scan is known to cover, so a glob that quietly stopped
    /// matching cannot make every expectation above pass vacuously.
    private static let coveredFiles: Set<String> = [
        "TrustGrantWire.swift",
        "TrustGrantPayloadSource.swift"
    ]
}
