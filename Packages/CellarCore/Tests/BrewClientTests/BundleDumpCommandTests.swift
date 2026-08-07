import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// The one `brew bundle` argv this capability can construct
/// (`brewfile-management` BF1, BF8; probe U6).
///
/// The headline invariant of this whole change is that **brew is never pointed
/// at a file Cellar did not write**. Probe U8 is why: `brew bundle check --file
/// <path>` evaluates the Brewfile's Ruby, and a marker written by a `File.write`
/// payload was on disk afterwards. A "read-only preview" implemented that way
/// runs a stranger's code.
///
/// So the rule is enforced by **enumeration**, not by convention: `dump` is the
/// only subcommand that can be spelled, and every other `bundle` subcommand is
/// unrepresentable rather than merely unused.
@Suite("Bundle dump command")
struct BundleDumpCommandTests {

    static let temp = URL(fileURLWithPath: "/var/folders/xx/cellar-brewfile/ABC/Brewfile")

    // MARK: - BF8 — the argv is pinned

    @Test("The dump argv is pinned exactly")
    func theDumpArgvIsPinnedExactly() {
        let command = BundleDumpCommand(fileURL: Self.temp)

        #expect(
            command.arguments == [
                "bundle", "dump",
                "--file", Self.temp.path,
                "--force", "--formula", "--cask", "--tap"
            ]
        )
        #expect(command.displayCommand == "brew " + command.arguments.joined(separator: " "))
    }

    /// A **read**, not a mutation: an export changes nothing installed, so it
    /// must not be serialised behind the mutation queue or counted as one.
    @Test("The dump is a read, and it carries no environment override")
    func theDumpIsAReadAndCarriesNoEnvironmentOverride() {
        let command = BundleDumpCommand(fileURL: Self.temp)

        #expect(command.brewCommand.kind == .read)
        #expect(command.brewCommand.arguments == command.arguments)
        #expect(command.brewCommand.environmentOverrides.isEmpty)
    }

    /// The positive type filters are what exclude `mas` and `vscode` entries
    /// from the exported file — they are not decoration.
    @Test("The three type filters are all present, and --global is not")
    func theThreeTypeFiltersAreAllPresent() {
        let arguments = BundleDumpCommand(fileURL: Self.temp).arguments

        #expect(arguments.contains("--formula"))
        #expect(arguments.contains("--cask"))
        #expect(arguments.contains("--tap"))
        #expect(arguments.contains("--global") == false)
        #expect(arguments.contains("--describe") == false)
    }

    // MARK: - BF1 — dump is the only subcommand, by enumeration

    /// The enumeration itself: `BundleDumpCommand.Subcommand` is `CaseIterable`
    /// with exactly one case, so "no other subcommand exists" is a fact the
    /// compiler keeps rather than a list somebody has to remember to check.
    @Test("Dump is the only bundle subcommand that can be constructed")
    func dumpIsTheOnlyBundleSubcommandThatCanBeConstructed() {
        #expect(BundleDumpCommand.Subcommand.allCases.count == 1)
        #expect(BundleDumpCommand.Subcommand.allCases == [.dump])
        #expect(BundleDumpCommand.Subcommand.dump.rawValue == "dump")

        // And the constructed argv agrees with the enumeration.
        let subcommands = BundleDumpCommand(fileURL: Self.temp).arguments
            .drop { $0 != "bundle" }
            .dropFirst()
            .prefix(1)
        #expect(Array(subcommands) == ["dump"])
    }

    /// U8 is why `check` is on this list. The others are here because a
    /// `bundle` subcommand that installs, removes or edits must not become
    /// reachable by a future one-line convenience.
    @Test(
        "Every other bundle subcommand is unrepresentable, not merely unused",
        arguments: [
            "install", "upgrade", "check", "cleanup", "list",
            "exec", "sh", "env", "add", "remove", "edit"
        ]
    )
    func everyOtherBundleSubcommandIsUnrepresentable(subcommand: String) throws {
        // Not constructible: the type has no case for it.
        #expect(BundleDumpCommand.Subcommand(rawValue: subcommand) == nil)

        // And not spellable: no source on this path contains the literal.
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        for source in sources where source.name.hasPrefix("BundleDump") {
            #expect(
                source.code.contains("\"\(subcommand)\"") == false,
                "\(source.name) can spell the bundle \(subcommand) subcommand"
            )
        }
    }

    @Test("No bundle argv can carry --global or a user-chosen path")
    func noBundleArgvCanCarryGlobalOrAUserChosenPath() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)

        for source in sources where source.name.hasPrefix("BundleDump") {
            #expect(source.code.contains("\"--global\"") == false)
            #expect(source.code.contains("HOMEBREW_BUNDLE_FILE") == false)
        }

        // The `--file` value is the one the caller constructed, and the
        // constructor takes a `URL` this capability made — there is no
        // string-taking overload a user path could arrive through.
        let command = try #require(sources.first { $0.name == "BundleDumpCommand.swift" })
        #expect(command.code.contains("public init(fileURL: URL)"))
        #expect(command.code.contains("init(path: String") == false)
    }
}
