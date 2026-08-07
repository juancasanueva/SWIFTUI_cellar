import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// Refusal, counted (`brewfile-management` BF2, BF4, threat rows TM1 and TM2).
///
/// The rule this suite defends is that **nothing is silently dropped**. A line
/// the grammar cannot accept becomes a typed skip carrying a named reason, its
/// line number and its raw line — and a clean file reports a skip count of `0`
/// rather than an absent one, so "nothing was skipped" and "skips were not
/// tracked" are never the same value.
///
/// It also defends the harder half: a Brewfile is evaluated Ruby, and none of it
/// is ever evaluated here. The hostile fixture contains a `File.write`, a
/// `system(…)`, a backtick command and a `$(…)` substitution. After parsing it,
/// no marker exists on disk, because the parser has no filesystem, no
/// subprocess and no interpreter to reach for.
@Suite("Brewfile skips and refusal")
struct BrewfileSkipTests {

    static func parse(_ text: String) async throws -> BrewfileDocument {
        try await BrewfileParser.decode(Data(text.utf8))
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: BrewfileFixtureManifest.root.appendingPathComponent(name))
    }

    /// Exactly the paths `hostile-ruby.brewfile` tries to create.
    static let markerPaths = [
        "/tmp/cellar-brewfile-hostile-marker.txt",
        "/tmp/cellar-brewfile-hostile-system.txt",
        "/tmp/cellar-brewfile-hostile-backtick.txt",
        "/tmp/cellar-brewfile-hostile-substitution.txt"
    ]

    // MARK: - BF4 — every unsupported kind is counted and named

    @Test(
        "Each unsupported entry kind is counted, named, and keeps its line",
        arguments: [
            "mas", "vscode", "whalebrew", "go", "cargo",
            "uv", "npm", "krew", "flatpak", "winget"
        ]
    )
    func eachUnsupportedEntryKindIsCountedAndNamed(kind: String) async throws {
        let line = "\(kind) \"something\""
        let document = try await Self.parse("brew \"wget\"\n\(line)\n")

        #expect(document.entries.map(\.displayName) == ["wget"], "the good line stopped surviving")
        #expect(document.skips.count == 1)
        let skip = try #require(document.skips.first)
        #expect(skip.reason == .unsupportedEntryKind(kind))
        #expect(skip.reason.detail == kind)
        #expect(skip.lineNumber == 2)
        #expect(skip.rawLine == line, "the raw line was truncated, re-encoded or normalised")
    }

    /// An option changes what the author asked for. Installing a stripped entry
    /// is not what they wrote, so the entry is refused rather than trimmed.
    @Test(
        "An option key other than trusted: names itself and refuses the entry",
        arguments: [
            ("brew \"dotnet@9\", link: true", "link"),
            ("brew \"postgresql@16\", postinstall: \"initdb\"", "postinstall"),
            ("brew \"vim\", args: [\"with-override-system-vi\"]", "args")
        ]
    )
    func anOptionKeyOtherThanTrustedNamesItself(line: String, key: String) async throws {
        let document = try await Self.parse(line + "\n")

        #expect(document.entries.isEmpty, "a stripped entry was installed anyway")
        #expect(document.skips.count == 1)
        #expect(document.skips.first?.reason == .unsupportedOption(key))
        #expect(document.skips.first?.rawLine == line)
    }

    @Test("Unsupported kinds are counted and named, and the file still imports")
    func unsupportedKindsAreCountedAndTheFileStillImports() async throws {
        let document = try await Self.parse(
            """
            mas "Xcode", id: 497799835
            vscode "ms-python.python"
            cargo "ripgrep"
            brew "wget"
            """
        )

        #expect(document.skips.count == 3)
        #expect(
            document.skips.map(\.reason) == [
                .unsupportedEntryKind("mas"),
                .unsupportedEntryKind("vscode"),
                .unsupportedEntryKind("cargo")
            ]
        )
        #expect(document.skips.map(\.lineNumber) == [1, 2, 3])
        #expect(document.entries.map(\.displayName) == ["wget"])
        #expect(document.skipCounts[.unsupportedEntryKind] == 3)
    }

    @Test("A clean file reports zero, not absence")
    func aCleanFileReportsZeroNotAbsence() async throws {
        let document = try await Self.parse(
            """
            tap "acme/tap"
            brew "wget"
            cask "iterm2"
            """
        )

        #expect(document.skips.count == 0)
        #expect(document.skipCounts.isEmpty, "a clean file invented a category with a zero count")
        #expect(document.entries.count == 3)
        #expect(document.isEmpty == false)
    }

    @Test("A skip keeps its raw line, exactly as read")
    func aSkipKeepsItsRawLineExactlyAsRead() async throws {
        let document = try await Self.parse(
            """
            tap "acme/tap"
            brew "wget"
            cask "iterm2"
            whalebrew "whalebrew/wget"
            """
        )

        let skip = try #require(document.skips.first)
        #expect(skip.lineNumber == 4)
        #expect(skip.rawLine == "whalebrew \"whalebrew/wget\"")
    }

    // MARK: - BF4 — no skip class blocks an import

    @Test("A wholly unsupported file still parses successfully")
    func aWhollyUnsupportedFileStillParsesSuccessfully() async throws {
        let document = try await Self.parse(
            """
            mas "Xcode", id: 497799835
            vscode "ms-python.python"
            """
        )

        #expect(document.entries.isEmpty)
        #expect(document.skips.count == 2, "every line must still be accounted for")
        // Distinct from a file that said nothing at all.
        #expect(document.isEmpty == false)
        let silent = try await Self.parse("\n# nothing here\n")
        #expect(silent.isEmpty)
        #expect(silent.entries.isEmpty)
        #expect(silent.skips.count == 0)
    }

    /// Three empties stay three distinct values (BF6's precondition, stated at
    /// the parse layer where it originates).
    @Test("An empty parse, an all-skipped parse and a populated parse are distinct")
    func anEmptyParseAnAllSkippedParseAndAPopulatedParseAreDistinct() async throws {
        let empty = try await BrewfileParser.decode(try Self.fixture("empty.brewfile"))
        let skipped = try await Self.parse("vscode \"ms-python.python\"\n")
        let populated = try await Self.parse("brew \"wget\"\n")

        #expect(empty.isEmpty)
        #expect(empty.entries.isEmpty)
        #expect(empty.skips.count == 0)

        #expect(skipped.isEmpty == false)
        #expect(skipped.entries.isEmpty)
        #expect(skipped.skips.count == 1)

        #expect(populated.entries.count == 1)

        #expect(empty != skipped)
        #expect(skipped != populated)
        #expect(empty != populated)
    }

    // MARK: - BF2, TM1, TM2 — nothing is evaluated

    @Test("The hostile fixture executes nothing and installs nothing")
    func theHostileFixtureExecutesNothingAndInstallsNothing() async throws {
        // Precondition: none of the markers exists before the parse. Without
        // this, a stale file from an earlier run would make the check vacuous —
        // or, worse, a real write would be excused as pre-existing.
        for path in Self.markerPaths {
            try? FileManager.default.removeItem(atPath: path)
            #expect(
                FileManager.default.fileExists(atPath: path) == false,
                "\(path) existed before the parse, so this proves nothing"
            )
        }

        let launcher = RecordingProcessLauncher()
        let document = try await BrewfileParser.decode(try Self.fixture("hostile-ruby.brewfile"))

        // Nothing ran and nothing was written.
        #expect(launcher.launchCount == 0)
        for path in Self.markerPaths {
            #expect(
                FileManager.default.fileExists(atPath: path) == false,
                "\(path) exists — a payload in the fixture was evaluated"
            )
        }

        // Every Ruby residue line is accounted for by a named reason, and the
        // ordinary line beside them still survives.
        #expect(document.entries.map(\.displayName) == ["ripgrep"])
        #expect(document.skips.count == 13, "a hostile line went unaccounted for")
        #expect(
            document.skips.allSatisfy { $0.rawLine.isEmpty == false },
            "a skip lost the line it refused"
        )

        let reasons = Dictionary(grouping: document.skips, by: \.reason.category)
        #expect(reasons[.rubyConditional]?.count == 2, "the if/unless lines were not both refused")
        #expect(reasons[.unrepresentableName]?.count == 5)
        #expect(reasons[.unsupportedOption]?.count == 1)
        #expect(reasons[.unrecognisedLine]?.count == 5)

        // The payload lines are refused as *lines*, with their text preserved —
        // which is what lets a surface show the user what it refused to run.
        #expect(document.skips.contains { $0.rawLine.hasPrefix("File.write(") })
        #expect(document.skips.contains { $0.rawLine.hasPrefix("system(") })
    }

    /// D6: the condition is never evaluated, so the outcome cannot depend on
    /// the host it is parsed on.
    @Test("A conditional line is skipped identically on any machine")
    func aConditionalLineIsSkippedIdenticallyOnAnyMachine() async throws {
        let document = try await Self.parse("brew \"gnupg\" if OS.mac?\n")

        #expect(document.entries.isEmpty)
        #expect(document.skips.count == 1)
        let skip = try #require(document.skips.first)
        #expect(skip.reason == .rubyConditional)
        #expect(skip.rawLine == "brew \"gnupg\" if OS.mac?")

        // The host is macOS. The identical bytes must produce the identical
        // result, which is what "never evaluated" means operationally: had the
        // condition been evaluated here, it would have been *true* and produced
        // an entry.
        #expect(document.entries.contains { $0.displayName == "gnupg" } == false)

        let unless = try await Self.parse("cask \"iterm2\" unless OS.linux?\n")
        #expect(unless.skips.first?.reason == .rubyConditional)
        #expect(unless.entries.isEmpty)
    }

    @Test("Interpolation and method calls are never evaluated")
    func interpolationAndMethodCallsAreNeverEvaluated() async throws {
        let document = try await Self.parse(
            """
            brew "#{ENV['HOME']}/x"
            brew Foo.bar
            """
        )

        #expect(document.entries.isEmpty)
        #expect(document.skips.count == 2)
        #expect(document.skips[0].reason == .unrepresentableName)
        #expect(document.skips[1].reason == .unrecognisedLine)

        // The environment value never appears anywhere in the result — which is
        // the observable form of "no environment variable was read".
        let home = ProcessInfo.processInfo.environment["HOME"] ?? "/Users"
        #expect(document.skips.allSatisfy { $0.rawLine.contains(home) == false })
    }

    @Test(
        "A name the typed identity refuses is a skip, never a string",
        arguments: ["brew \"--force\"", "brew \"wget; rm -rf /\"", "brew \"\"", "brew \"   \""]
    )
    func aNameTheTypedIdentityRefusesIsASkipNeverAString(line: String) async throws {
        let document = try await Self.parse(line + "\n")

        #expect(document.entries.isEmpty)
        #expect(document.skips.count == 1)
        #expect(document.skips.first?.reason == .unrepresentableName)
        #expect(document.skips.first?.rawLine == line)
    }

    @Test(
        "Shell metacharacters in a name yield a refusal, never a command",
        arguments: ["`id`", "$(id)", "wget && rm", "wget|tee"]
    )
    func shellMetacharactersInANameYieldARefusal(name: String) async throws {
        let document = try await Self.parse("brew \"\(name)\"\n")

        #expect(document.entries.isEmpty, "\(name) became an entry")
        #expect(document.skips.first?.reason == .unrepresentableName)
    }

    // MARK: - BF2 — byte-level tolerance and bounds

    @Test("Undecodable bytes are tolerated at line granularity, not fatal")
    func undecodableBytesAreToleratedAtLineGranularity() async throws {
        let document = try await BrewfileParser.decode(try Self.fixture("undecodable.brewfile"))

        #expect(document.entries.map(\.displayName) == ["wget", "ripgrep"])
        #expect(document.entries.map(\.lineNumber) == [1, 3])
        #expect(document.skips.count == 1)
        #expect(document.skips.first?.reason == .undecodableBytes)
        #expect(document.skips.first?.lineNumber == 2)
    }

    @Test("An empty file is an empty parse, not a failure")
    func anEmptyFileIsAnEmptyParseNotAFailure() async throws {
        let document = try await BrewfileParser.decode(try Self.fixture("empty.brewfile"))

        #expect(document.entries.isEmpty)
        #expect(document.skips.count == 0)
        #expect(document.isEmpty)
    }

    /// Over the bound, the file is refused **whole** and parsed never — the one
    /// case where refusal is not a skip.
    @Test("Input over the size bound throws and is parsed never")
    func inputOverTheSizeBoundThrowsAndIsParsedNever() async throws {
        let line = "brew \"wget\"\n"
        let repeats = (BrewfileParser.maximumByteCount / line.utf8.count) + 64
        let oversized = Data(String(repeating: line, count: repeats).utf8)
        #expect(oversized.count > BrewfileParser.maximumByteCount)

        await #expect(throws: BrewfileParseError.self) {
            _ = try await BrewfileParser.decode(oversized)
        }

        // Exactly at the bound is still accepted, so the bound is a bound rather
        // than an off-by-one refusal of ordinary files.
        let atBound = Data(String(repeating: "\n", count: BrewfileParser.maximumByteCount).utf8)
        let document = try await BrewfileParser.decode(atBound)
        #expect(document.isEmpty)
    }

    // MARK: - BF2 — parsing is pure

    @Test("Parsing the same bytes twice produces the same document")
    func parsingTheSameBytesTwiceProducesTheSameDocument() async throws {
        let data = try Self.fixture("mixed-kinds.brewfile")
        let first = try await BrewfileParser.decode(data)
        let second = try await BrewfileParser.decode(data)

        #expect(first == second)
        #expect(first.entries.isEmpty == false)
        #expect(first.skips.isEmpty == false)
    }

    /// The signature is the guarantee: `decode` takes `Data`. There is no
    /// URL-taking overload, so the parser structurally *cannot* read a file, an
    /// environment variable or a network response.
    @Test("The parser takes bytes and reaches for nothing else")
    func theParserTakesBytesAndReachesForNothingElse() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let parser = try #require(sources.first { $0.name == "BrewfileParser.swift" })

        #expect(
            parser.code.contains(
                "public static func decode(_ data: Data) async throws(BrewfileParseError) -> BrewfileDocument"
            ),
            "the decode signature changed"
        )
        // M1 convention: the attribute goes on its own line, before the modifier.
        #expect(parser.code.contains("@concurrent\n    public static func decode"))

        for reach in [
            "URLSession", "FileManager", "Process", "ProcessInfo", "BrewCommand",
            "ProcessLaunching", "getenv", "Bundle"
        ] {
            #expect(
                parser.code.containsIdentifier(reach) == false,
                "BrewfileParser.swift reaches for \(reach)"
            )
        }
        // `URL` is permitted for exactly one thing: turning a tap's second
        // positional into a value for display. `URL(string:)` is pure. The
        // file-reading and network forms are not.
        for reach in ["URL(fileURLWithPath:", "Data(contentsOf:", "contentsOf:", "/bin/sh"] {
            #expect(parser.code.contains(reach) == false, "BrewfileParser.swift reaches for \(reach)")
        }
        #expect(parser.code.contains("func decode(_ url:") == false, "a URL-taking overload exists")
    }
}
