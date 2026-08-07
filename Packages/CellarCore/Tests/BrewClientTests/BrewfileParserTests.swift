import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// The accepted grammar (`brewfile-management` BF3, BF5, design DD2).
///
/// A Brewfile is evaluated Ruby, and probe U8 proved that pointing
/// `brew bundle check` at one runs it. Cellar therefore reads the file as
/// **bytes** and accepts a deliberately small grammar out of them: `tap`,
/// `brew`, `cask`, with the serialisations a real dump actually emits. Anything
/// else is a counted skip, never an interpretation and never an evaluation.
///
/// The shapes pinned here are not invented — they were read off
/// `Fixtures/Bundle/dump-file.brewfile`, captured from the real binary at
/// Homebrew `6.0.15-125-g7372067`, and the fixture manifest keeps them honest.
@Suite("Brewfile parser grammar")
struct BrewfileParserTests {

    static func parse(_ text: String) async throws -> BrewfileDocument {
        try await BrewfileParser.decode(Data(text.utf8))
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: BrewfileFixtureManifest.root.appendingPathComponent(name))
    }

    // MARK: - BF3 — tap, brew, cask, and their pinned serialisations

    @Test("A bare tap line is one tap entry")
    func aBareTapLineIsOneTapEntry() async throws {
        let document = try await Self.parse("tap \"agavra/tap\"\n")

        #expect(document.skips.isEmpty)
        let entry = try #require(document.entries.first)
        #expect(entry.lineNumber == 1)
        #expect(entry.tapName == TapName("agavra/tap"))
        guard case .tap(_, let url) = entry.kind else {
            Issue.record("the line did not parse as a tap")
            return
        }
        #expect(url == nil)
    }

    /// U9's URL second positional, verbatim from the real dump.
    @Test("A tap line with a URL positional keeps both, and counts no skip")
    func aTapLineWithAURLPositionalKeepsBoth() async throws {
        let document = try await Self.parse(
            "tap \"cloudmanic/spice-edit\", \"https://github.com/cloudmanic/spice-edit\"\n"
        )

        #expect(document.skips.count == 0)
        let entry = try #require(document.entries.first)
        guard case .tap(let name, let url) = entry.kind else {
            Issue.record("the line did not parse as a tap")
            return
        }
        #expect(name == TapName("cloudmanic/spice-edit"))
        #expect(url == URL(string: "https://github.com/cloudmanic/spice-edit"))
    }

    @Test("Quoting variants, whitespace and a trailing comma all parse to the same entry")
    func quotingVariantsParseToTheSameEntry() async throws {
        let document = try await Self.parse(
            """
            brew "wget"
            brew 'wget'
              brew "wget"
            brew "wget",
            """
        )

        #expect(document.skips.count == 0, "a quoting variant was counted as a skip")
        #expect(document.entries.count == 4)
        #expect(document.entries.map(\.displayName) == ["wget", "wget", "wget", "wget"])
        #expect(document.entries.map(\.lineNumber) == [1, 2, 3, 4])
        for entry in document.entries {
            guard case .formula(let formula) = entry.kind else {
                Issue.record("line \(entry.lineNumber) did not parse as a formula")
                return
            }
            #expect(formula.id == PackageID(kind: .formula, name: "wget"))
        }
    }

    @Test("A cask line is a cask entry, with its kind carried explicitly")
    func aCaskLineIsACaskEntry() async throws {
        let document = try await Self.parse("cask \"iterm2\"\n")

        #expect(document.skips.count == 0)
        let entry = try #require(document.entries.first)
        #expect(entry.packageID == PackageID(kind: .cask, name: "iterm2"))
    }

    /// U6: this Homebrew version emits `#` description comments in a dump
    /// **without** `--describe`. Counting them would make every real round-trip
    /// look lossy, so they are ignored rather than skipped.
    @Test("Description comments and blank lines are ignored, not counted as skips")
    func descriptionCommentsAndBlankLinesAreIgnored() async throws {
        let document = try await Self.parse(
            """
            # Improved shell history for zsh, bash, fish and nushell
            brew "atuin"

            # Clone of cat(1) with syntax highlighting and Git integration
            brew "bat"

            """
        )

        #expect(document.entries.map(\.displayName) == ["atuin", "bat"])
        #expect(document.skips.count == 0, "a comment or blank line was counted as a skip")
        #expect(document.entries.map(\.lineNumber) == [2, 5])
    }

    @Test("A trailing comment is stripped without disturbing the entry")
    func aTrailingCommentIsStrippedWithoutDisturbingTheEntry() async throws {
        let document = try await Self.parse("brew \"wget\" # the description\n")

        #expect(document.skips.count == 0)
        #expect(document.entries.first?.displayName == "wget")
    }

    // MARK: - BF3, revision-2 amendment — a tap-prefixed name is an entry

    /// `MutationName.isSafe` accepts `/`, so degrading these lines would
    /// silently drop **every third-party package** of a real dump. The captured
    /// fixture contains ten of them.
    @Test("A tap-prefixed package name is an ordinary entry, not a skip")
    func aTapPrefixedPackageNameIsAnOrdinaryEntry() async throws {
        let document = try await Self.parse(
            """
            brew "acme/tap/thing"
            cask "acme/tap/app"
            """
        )

        #expect(document.skips.count == 0, "a tap-prefixed token degraded into a skip")
        #expect(document.entries.count == 2)
        #expect(document.entries[0].packageID == PackageID(kind: .formula, name: "acme/tap/thing"))
        #expect(document.entries[1].packageID == PackageID(kind: .cask, name: "acme/tap/app"))
    }

    @Test("The real dump's tap-prefixed formulae all survive")
    func theRealDumpsTapPrefixedFormulaeAllSurvive() async throws {
        let document = try await BrewfileParser.decode(try Self.fixture("dump-file.brewfile"))
        let prefixed = document.entries.filter { $0.displayName.contains("/") && $0.tapName == nil }

        #expect(prefixed.count == 10, "the captured dump's tap-prefixed formulae changed count")
        #expect(prefixed.allSatisfy { $0.packageID?.kind == .formula })
        #expect(
            prefixed.contains { $0.displayName == "gentleman-programming/tap/engram" },
            "a known tap-prefixed formula from the capture is missing"
        )
    }

    // MARK: - BF5 — `trusted:` is parsed, surfaced, and confers nothing

    @Test("A trusted tap with a URL positional parses as one tap entry")
    func aTrustedTapWithAURLPositionalParsesAsOneTapEntry() async throws {
        let line = "tap \"gentleman-programming/tap\", "
            + "\"https://github.com/Gentleman-Programming/homebrew-tap\", "
            + "trusted: { casks: [\"engram\"] }"
        let document = try await Self.parse(line + "\n")

        #expect(document.skips.count == 0, "a trusted: option corrupted the line it appeared on")
        #expect(document.entries.count == 1)
        let entry = try #require(document.entries.first)
        guard case .tap(let name, let url) = entry.kind else {
            Issue.record("the line did not parse as a tap")
            return
        }
        #expect(name == TapName("gentleman-programming/tap"))
        #expect(url == URL(string: "https://github.com/Gentleman-Programming/homebrew-tap"))

        let claim = try #require(entry.trustedClaim, "the trusted: claim was discarded")
        #expect(claim.scope == .named(formulae: [], casks: ["engram"], commands: []))
        #expect(claim.rawOption.contains("engram"))
    }

    @Test("trusted: true is retained as a whole-tap claim")
    func trustedTrueIsRetainedAsAWholeTapClaim() async throws {
        let document = try await Self.parse("tap \"acme/tap\", trusted: true\n")

        #expect(document.skips.count == 0)
        let claim = try #require(document.entries.first?.trustedClaim)
        #expect(claim.scope == .everything)
        #expect(claim.rawOption == "trusted: true")
    }

    /// The real dump puts `trusted: true` on `brew` lines too. Each is an
    /// ordinary package entry, with no skip and no trust grant.
    @Test("trusted: on a brew or cask line parses and confers nothing")
    func trustedOnABrewOrCaskLineParsesAndConfersNothing() async throws {
        let document = try await Self.parse(
            """
            brew "acme/tap/thing", trusted: true
            cask "acme/tap/app", trusted: true
            """
        )

        #expect(document.skips.count == 0)
        #expect(document.entries.count == 2)
        #expect(document.entries[0].packageID == PackageID(kind: .formula, name: "acme/tap/thing"))
        #expect(document.entries[1].packageID == PackageID(kind: .cask, name: "acme/tap/app"))
        #expect(document.entries.allSatisfy { $0.trustedClaim?.scope == .everything })
    }

    /// The claim is retained for display and attributed to the file's author.
    /// It records nothing: there is no trust store, no grant, no allow-list.
    @Test("A retained claim is attributed to the file and grants nothing")
    func aRetainedClaimIsAttributedToTheFileAndGrantsNothing() async throws {
        let document = try await BrewfileParser.decode(try Self.fixture("trusted-taps.brewfile"))

        #expect(document.skips.count == 0, "U9's captured lines produced a skip")
        #expect(document.trustClaims.count == 4, "a claim was dropped from the projection")

        // Attribution is a named constant, and it names nobody but the author.
        #expect(BrewfileTrustClaim.attribution.contains("author"))
        #expect(BrewfileTrustClaim.attribution.lowercased().contains("cellar grants no trust"))

        // Structurally: nothing derived from the option can reach argv, because
        // no source on this path spells the token at all.
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        for source in sources where source.name.hasPrefix("Brewfile") {
            #expect(
                source.code.contains("\"--trusted\"") == false,
                "\(source.name) can spell a --trusted flag"
            )
        }
    }

    // MARK: - The captured dump, end to end

    /// The whole real capture, replayed offline. Every line lands as a typed
    /// entry or a **named** skip; the counts are the ones the README records.
    @Test("The captured dump parses into the shape the capture record documents")
    func theCapturedDumpParsesIntoTheShapeTheCaptureRecordDocuments() async throws {
        let document = try await BrewfileParser.decode(try Self.fixture("dump-file.brewfile"))

        let taps = document.entries.filter { $0.tapName != nil }
        let formulae = document.entries.filter { $0.packageID?.kind == .formula }
        let casks = document.entries.filter { $0.packageID?.kind == .cask }

        #expect(taps.count == 9)
        #expect(formulae.count == 58, "58 of the 59 brew lines are entries; dotnet@9 carries link:")
        #expect(casks.count == 11)

        // The one option hash in the capture, named rather than silently stripped.
        #expect(document.skips.count == 1)
        let skip = try #require(document.skips.first)
        #expect(skip.reason == .unsupportedOption("link"))
        #expect(skip.rawLine == "brew \"dotnet@9\", link: true")
    }
}
