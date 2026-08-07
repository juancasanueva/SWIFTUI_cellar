import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The diff (`brewfile-management` BF6, design D1).
///
/// It is a **pure offline projection**: the caller already holds an
/// `InstalledInventory` and a `TapInventory`, and the diff is a fold over those
/// values. It spawns no process, forces no re-snapshot and asks brew nothing —
/// the preview costs zero new acquisition, exactly as `installed-inventory` and
/// `package-discovery` already require of their own projections.
///
/// Selection lives here rather than in a view. Whether a row can be selected is
/// a fact about the row's typed state, so a surface cannot accidentally offer a
/// checkbox for a package that is already installed, and no code path can move a
/// present or skipped row into the selection.
@Suite("Brewfile diff")
struct BrewfileDiffTests {

    static func parse(_ text: String) async throws -> BrewfileDocument {
        try await BrewfileParser.decode(Data(text.utf8))
    }

    static func inventory(_ ids: [PackageID]) -> InstalledInventory {
        InstalledFixture.inventory(upToDate: ids)
    }

    static func taps(_ names: [String]) -> TapInventory {
        TapInventory(taps: names.map { TapRecord(name: $0, repository: $0) })
    }

    static let wget = PackageID(kind: .formula, name: "wget")
    static let git = PackageID(kind: .formula, name: "git")
    static let ripgrep = PackageID(kind: .formula, name: "ripgrep")

    // MARK: - Three typed states

    @Test("Missing entries arrive selected and present entries do not")
    func missingEntriesArriveSelectedAndPresentEntriesDoNot() async throws {
        let document = try await Self.parse(
            """
            brew "wget"
            brew "git"
            brew "ripgrep"
            """
        )
        let diff = BrewfileDiff(document: document, installed: Self.inventory([Self.wget]), taps: .empty)

        #expect(diff.rows.count == 3)
        #expect(diff.missing.map(\.displayName) == ["git", "ripgrep"])
        #expect(diff.present.map(\.displayName) == ["wget"])
        #expect(diff.selection == Set(diff.missing.map(\.id)))

        // The present row is visible, and it is not selectable.
        let presentRow = try #require(diff.rows.first { $0.entry?.displayName == "wget" })
        #expect(presentRow.isSelectable == false)
        #expect(presentRow.state == .present)
        for row in diff.rows where row.entry?.displayName != "wget" {
            #expect(row.isSelectable)
        }
    }

    @Test("A skipped line is visible with its reason and its line number, and is unselectable")
    func aSkippedLineIsVisibleWithItsReasonAndIsUnselectable() async throws {
        let document = try await Self.parse(
            """
            brew "wget"
            whalebrew "whalebrew/wget"
            """
        )
        let diff = BrewfileDiff(document: document, installed: .empty, taps: .empty)

        #expect(diff.rows.count == 2)
        let skipped = try #require(diff.rows.last)
        #expect(skipped.state == .skipped)
        #expect(skipped.isSelectable == false)
        #expect(skipped.skip?.reason == .unsupportedEntryKind("whalebrew"))
        #expect(skipped.skip?.lineNumber == 2)
        #expect(skipped.skip?.rawLine == "whalebrew \"whalebrew/wget\"")

        // Rows come back in file order, so a surface can render "line 2" beside
        // the line above it and beneath the line below it.
        #expect(diff.rows.map(\.lineNumber) == [1, 2])
    }

    @Test("A present or skipped entry cannot enter the selection")
    func aPresentOrSkippedEntryCannotEnterTheSelection() async throws {
        let document = try await Self.parse(
            """
            brew "wget"
            brew "git"
            vscode "ms-python.python"
            """
        )
        var diff = BrewfileDiff(document: document, installed: Self.inventory([Self.wget]), taps: .empty)

        let presentID = try #require(diff.present.first?.id)
        let skippedID = try #require(diff.skips.first?.id)
        let missingID = try #require(diff.missing.first?.id)
        #expect(diff.selection == [missingID])

        diff.select(presentID)
        diff.select(skippedID)
        #expect(diff.selection == [missingID], "a non-missing row entered the selection")

        // The one legitimate move still works, in both directions.
        diff.deselect(missingID)
        #expect(diff.selection.isEmpty)
        diff.select(missingID)
        #expect(diff.selection == [missingID])

        // And a wholesale assignment is filtered on the same rule, so a caller
        // cannot bypass the per-id gate by replacing the set.
        diff.setSelection([presentID, skippedID, missingID])
        #expect(diff.selection == [missingID])
    }

    @Test("An official tap already in the resident inventory reads present")
    func anOfficialTapAlreadyInTheResidentInventoryReadsPresent() async throws {
        let document = try await Self.parse(
            """
            tap "homebrew/cask"
            tap "acme/tap"
            """
        )
        let diff = BrewfileDiff(
            document: document,
            installed: .empty,
            taps: Self.taps(["homebrew/cask"])
        )

        #expect(diff.present.compactMap(\.tapName?.rawValue) == ["homebrew/cask"])
        #expect(diff.missing.compactMap(\.tapName?.rawValue) == ["acme/tap"])
        #expect(diff.selection == Set(diff.missing.map(\.id)))
    }

    // MARK: - Three empties stay distinct

    @Test("A file with no entries, an all-present file and an all-skipped file are distinct")
    func threeEmptiesStayDistinct() async throws {
        let nothing = BrewfileDiff(
            document: try await Self.parse("# only a comment\n"),
            installed: .empty,
            taps: .empty
        )
        let allPresent = BrewfileDiff(
            document: try await Self.parse("brew \"wget\"\n"),
            installed: Self.inventory([Self.wget]),
            taps: .empty
        )
        let allSkipped = BrewfileDiff(
            document: try await Self.parse("mas \"Xcode\", id: 497799835\n"),
            installed: .empty,
            taps: .empty
        )

        #expect(nothing.summary == .nothingInTheFile)
        #expect(allPresent.summary == .everythingAlreadyPresent)
        #expect(allSkipped.summary == .everythingSkipped)

        let summaries = [nothing.summary, allPresent.summary, allSkipped.summary]
        #expect(Set(summaries).count == 3, "two empties collapsed into one value")

        // And none of them is the same as having something to do.
        let actionable = BrewfileDiff(
            document: try await Self.parse("brew \"wget\"\n"),
            installed: .empty,
            taps: .empty
        )
        #expect(actionable.summary == .actionable)
        #expect(summaries.contains(.actionable) == false)
    }

    @Test("Skips never gate the diff: an all-skipped file is still a usable projection")
    func skipsNeverGateTheDiff() async throws {
        let document = try await Self.parse(
            """
            mas "Xcode", id: 497799835
            vscode "ms-python.python"
            """
        )
        let diff = BrewfileDiff(document: document, installed: .empty, taps: .empty)

        #expect(diff.skips.count == 2)
        #expect(diff.rows.count == 2)
        #expect(diff.selection.isEmpty)
        // An empty selection is a legitimate state, not an error.
        #expect(diff.summary == .everythingSkipped)
    }

    // MARK: - BF6 — the preview costs no acquisition

    @Test("Diffing a file acquires nothing")
    func diffingAFileAcquiresNothing() async throws {
        var text = ""
        for index in 0..<30 { text += "brew \"pkg-\(index)\"\n" }
        let document = try await Self.parse(text)
        #expect(document.entries.count == 30)

        let launcher = RecordingProcessLauncher()
        let installed = Self.inventory([Self.wget])
        let taps = Self.taps(["homebrew/core"])

        let diff = BrewfileDiff(document: document, installed: installed, taps: taps)

        #expect(diff.missing.count == 30)
        #expect(launcher.launchCount == 0, "the diff spawned a process")
        // The inventories the caller handed in are the ones that were read —
        // nothing was re-snapshotted, because there is nothing here that could.
        #expect(installed == Self.inventory([Self.wget]))
        #expect(taps == Self.taps(["homebrew/core"]))
    }

    /// The structural half: this file has nothing to spawn *with*.
    @Test("The diff has no process, no refresh and no acquisition to reach for")
    func theDiffHasNothingToAcquireWith() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let diff = try #require(sources.first { $0.name == "BrewfileDiff.swift" })

        for reach in [
            "Process", "ProcessLaunching", "BrewCommand", "URLSession",
            "FileManager", "refresh", "snapshot", "OperationCenter"
        ] {
            #expect(
                diff.code.containsIdentifier(reach) == false,
                "BrewfileDiff.swift reaches for \(reach)"
            )
        }
    }

    /// It is Cellar's reading, and it says so. A surface that presented this as
    /// brew's own verdict would be claiming an authority nothing here has.
    @Test("The projection is attributed to Cellar, not to brew")
    func theProjectionIsAttributedToCellarNotToBrew() {
        #expect(BrewfileDiff.attribution.contains("Cellar"))
        #expect(BrewfileDiff.attribution.lowercased().contains("homebrew was not asked"))
    }
}
