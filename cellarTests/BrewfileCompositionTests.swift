//
//  BrewfileCompositionTests.swift
//  cellarTests
//

import AppKit
import BrewClient
import BrewProcess
import Catalog
import Foundation
import Synchronization
import Testing

@testable import cellar

/// Every `brew` spawn one `CompositionLauncher` saw, keyed by that launcher's
/// own tag.
///
/// The keying is the point. `SecurityCompositionSupport`'s
/// `CompositionRequestSpy` counts into a single `static` and registers globally,
/// which is fine for the question that suite asks and wrong for this one: Swift
/// Testing runs suites concurrently, so a test that *makes* a spawn to prove the
/// counter works would clobber a concurrent test asserting the counter is zero —
/// a false zero, which is exactly the failure slice 3 shipped and had to
/// re-diagnose. A tag per instance makes "this launcher saw nothing" a claim
/// about this test alone.
enum BrewfileCompositionLedger {
    static let spawns = Mutex<[String: [[String]]]>([:])
}

/// A launcher that records every argv it is handed, for one test.
struct CompositionLauncher: ProcessLaunching {
    let tag: String

    init() {
        let tag = UUID().uuidString
        self.tag = tag
        BrewfileCompositionLedger.spawns.withLock { $0[tag] = [] }
    }

    /// Every argv vector spawned through this launcher, in order.
    var spawned: [[String]] {
        BrewfileCompositionLedger.spawns.withLock { $0[tag] ?? [] }
    }

    func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess {
        BrewfileCompositionLedger.spawns.withLock { $0[tag, default: []].append(spec.arguments) }
        return CompositionProcess()
    }
}

/// A process that succeeds immediately and says nothing.
private final class CompositionProcess: LaunchedProcess, Sendable {
    let output: AsyncStream<OutputChunk>

    init() {
        output = AsyncStream { $0.finish() }
    }

    func send(_ signal: ProcessSignal) throws {}

    func waitForTermination() async -> BrewExit { BrewExit(status: 0, reason: .exited) }
}

/// The app half of Brewfile import and export (design DD4, D3).
///
/// Three kinds of claim live here, and each is tested the way it can actually be
/// proven:
///
/// - **The panels** carry configuration, and configuration is readable off a
///   real `NSOpenPanel` / `NSSavePanel` without ever running one modally. The
///   tests therefore call the shipped `configure(_:)` and read the panel back,
///   rather than asserting that a struct exists.
/// - **The wiring** is proven end to end through a real `OperationCenter` over a
///   **per-instance** recording launcher, so "exactly one confirmation, carrying
///   the tapTrust disclosure" is a count over a real ledger.
/// - **The absences** — no remembered destination, no security-scoped bookmark,
///   no `brew bundle` subcommand other than `dump` — are claims about what the
///   app target does *not* contain, and a source scan is the only thing that can
///   make them.
@Suite("Brewfile composition", .timeLimit(.minutes(1)))
struct BrewfileCompositionTests {

    // MARK: - Arrangement

    /// The app target's own sources, raw and comment-stripped.
    ///
    /// Both, deliberately. A prohibition must be checked against **stripped**
    /// code so a doc comment describing it is never mistaken for a violation;
    /// a recorded trap must be checked against the **raw** text, because
    /// recording it is precisely what a comment is for.
    static func appSource(_ name: String) throws -> (raw: String, stripped: String) {
        let url = AppSecuritySources.directory
            .appendingPathComponent("Taps")
            .appendingPathComponent(name)
        let raw = try String(contentsOf: url, encoding: .utf8)
        return (raw, AppSecuritySources.stripComments(from: raw))
    }

    // MARK: - 9.1 The AppKit seams

    @MainActor
    @Test("The source panel takes one file and refuses a directory")
    func theSourcePanelTakesOneFileAndRefusesADirectory() {
        let panel = NSOpenPanel()
        BrewfileSourcePanel.configure(panel)

        #expect(panel.canChooseFiles, "the open panel could not choose a file at all")
        #expect(panel.canChooseDirectories == false, "a directory is not a Brewfile")
        #expect(panel.allowsMultipleSelection == false, "an import reads exactly one file")
        // A Brewfile has no extension, so a content-type filter would grey out
        // the very file the user came to pick.
        #expect(panel.allowedContentTypes.isEmpty)
        #expect(panel.prompt == BrewfileSourcePanel.prompt)
    }

    @MainActor
    @Test("The destination panel offers the name Brewfile and no extension filter")
    func theDestinationPanelOffersTheNameBrewfile() {
        let panel = NSSavePanel()
        BrewfileDestinationPanel.configure(panel)

        #expect(panel.nameFieldStringValue == "Brewfile")
        #expect(panel.allowedContentTypes.isEmpty, "a Brewfile has no extension to enforce")
        #expect(panel.canCreateDirectories, "the user may export into a new folder")
        #expect(panel.isExtensionHidden == false)
        #expect(panel.prompt == BrewfileDestinationPanel.prompt)
    }

    /// The two prompts are different words, which is the whole reason they are
    /// two constants rather than one shared "OK".
    @Test("The two panels ask for two different things")
    func theTwoPanelsAskForTwoDifferentThings() {
        #expect(BrewfileSourcePanel.prompt.isEmpty == false)
        #expect(BrewfileDestinationPanel.prompt.isEmpty == false)
        #expect(BrewfileSourcePanel.prompt != BrewfileDestinationPanel.prompt)
        #expect(BrewfileSourcePanel.message.isEmpty == false)
        #expect(BrewfileDestinationPanel.message.isEmpty == false)
    }

    /// `BrewfilePublicationTests` makes this claim over `CellarCore`. It has to
    /// be made again here, because the app target is where a panel could quietly
    /// acquire a memory (`brewfile-management` BF9).
    @Test("The panels remember nothing and hold no bookmark")
    func thePanelsRememberNothingAndHoldNoBookmark() throws {
        let source = try Self.appSource("BrewfilePanels.swift")

        for forbidden in [
            "UserDefaults",
            "AppStorage",
            "bookmarkData",
            "startAccessingSecurityScopedResource",
            "stopAccessingSecurityScopedResource",
            "NSDocumentController",
            "noteNewRecentDocumentURL"
        ] {
            #expect(
                source.stripped.contains(forbidden) == false,
                "BrewfilePanels.swift reaches for \(forbidden)"
            )
        }

        // Nor may it seed a well-known Brewfile location as the default
        // destination: the user chooses the path, or nothing is written.
        for wellKnown in [".Brewfile", ".homebrew/Brewfile", "HOMEBREW_BUNDLE_FILE_GLOBAL", "XDG_CONFIG"] {
            #expect(
                source.stripped.contains(wellKnown) == false,
                "BrewfilePanels.swift names the well-known location \(wellKnown)"
            )
        }
    }

    /// The latent trap, recorded where the code it would break lives.
    ///
    /// `ENABLE_USER_SELECTED_FILES = readonly` is inert today because
    /// `ENABLE_APP_SANDBOX = NO`. If the sandbox is ever switched on, that value
    /// permits the import's **read** and blocks the export's **write** — a
    /// half-broken feature rather than an obviously broken one, which is exactly
    /// the kind of thing that gets rediscovered from a bug report. This test
    /// fails if the note is ever deleted.
    @Test("The sandbox trap is recorded beside the code it would break")
    func theSandboxTrapIsRecordedBesideTheCodeItWouldBreak() throws {
        let source = try Self.appSource("BrewfilePanels.swift")

        #expect(source.raw.contains("ENABLE_USER_SELECTED_FILES"))
        #expect(source.raw.contains("ENABLE_APP_SANDBOX"))
        #expect(
            source.raw.contains("readonly"),
            "the recorded trap does not say which value is set"
        )
    }

    /// AppKit is reached from this one file and from nowhere else on the
    /// Brewfile path, which is what keeps `CellarCore` testable without a window
    /// server (design DD4).
    @Test("Only the panels file imports AppKit on the Brewfile path")
    func onlyThePanelsFileImportsAppKitOnTheBrewfilePath() throws {
        for name in ["BrewfileImportSheet.swift", "BrewfileExportSheet.swift"] {
            let source = try Self.appSource(name)
            #expect(
                source.stripped.contains("import AppKit") == false,
                "\(name) imports AppKit; the panels file is the seam"
            )
            #expect(source.stripped.contains("NSOpenPanel") == false)
            #expect(source.stripped.contains("NSSavePanel") == false)
        }

        let panels = try Self.appSource("BrewfilePanels.swift")
        #expect(panels.stripped.contains("import AppKit"))
        #expect(panels.stripped.contains("NSOpenPanel"))
        #expect(panels.stripped.contains("NSSavePanel"))
    }

    // MARK: - 9.2 The wiring, through a real centre

    /// A Brewfile written to a real temporary file, because the store reads
    /// through `DefaultCatalogFileSystem` and stubbing that here would test the
    /// stub rather than the composition.
    static func temporaryBrewfile(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-composition-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Brewfile")
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// The tap is written **last** on purpose. `OperationCenterBulk.request(_:)`
    /// reads `commands.first`, so a plan that preserved file order would present
    /// "This removes installed software." for a batch that adds a third-party
    /// tap. That is the DD1 defect, and this is where the app-level wiring is
    /// asked about it.
    static let tapLastBrewfile = """
        brew "wget"
        brew "git"
        tap "acme/tap", trusted: true
        """

    @MainActor
    static func importedStore(_ contents: String) async throws -> BrewfileStore {
        let store = BrewfileStore()
        let url = try temporaryBrewfile(contents)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await store.importFile(at: url, installed: .empty, taps: .empty)
        return store
    }

    @MainActor
    @Test("A tap-carrying import raises exactly one confirmation, and it is the trust one")
    func aTapCarryingImportRaisesExactlyOneTrustConfirmation() async throws {
        let launcher = CompositionLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: AppTestFixtures.installation)
        let store = try await Self.importedStore(Self.tapLastBrewfile)

        let request = try #require(
            BrewfileImportAction.apply(store, through: center),
            "a tap-carrying import asked for no confirmation at all"
        )

        #expect(center.pendingConfirmation == request, "the request never reached the gate")
        #expect(request.disclosure == .tapAdd(try #require(TapName("acme/tap"))))
        #expect(request.warningText == """
        Adding acme/tap clones a third-party repository. Homebrew will not load \
        its formulae or casks until you trust it, and Cellar does not trust it \
        for you.
        """)
        #expect(
            request.warningText != "This removes installed software.",
            "the erased batch presented the package-removal disclosure — DD1 has regressed"
        )
        // One yes, covering all three, with the tap at the head of it.
        #expect(request.commands.count == 3)
        #expect(request.command.displayCommand.contains("tap acme/tap"))
        #expect(request.displayCommands.contains { $0.contains("wget") })
        // Nothing has spawned yet: a confirmation is asked before anything runs.
        #expect(launcher.spawned.isEmpty)
    }

    @MainActor
    @Test("Declining a tap-carrying import spawns nothing at all")
    func decliningATapCarryingImportSpawnsNothing() async throws {
        let launcher = CompositionLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: AppTestFixtures.installation)
        let store = try await Self.importedStore(Self.tapLastBrewfile)

        let request = try #require(BrewfileImportAction.apply(store, through: center))
        center.decline(request)

        // Given time to spawn if it were going to.
        try? await Task.sleep(for: .milliseconds(300))

        #expect(center.pendingConfirmation == nil)
        #expect(center.items.isEmpty, "declining enqueued an operation")
        #expect(launcher.spawned.isEmpty, "declining spawned \(launcher.spawned)")
    }

    /// The positive that gives the two zeros above their meaning: this launcher
    /// does count, so an empty ledger is a refusal rather than a broken recorder.
    @MainActor
    @Test("Confirming submits all three, tap first, and never a bundle subcommand")
    func confirmingSubmitsAllThreeTapFirst() async throws {
        let launcher = CompositionLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: AppTestFixtures.installation)
        let store = try await Self.importedStore(Self.tapLastBrewfile)

        let request = try #require(BrewfileImportAction.apply(store, through: center))
        let items = center.confirm(request)
        #expect(items.count == 3)

        await Self.untilSpawned(atLeast: 3, launcher)

        let spawned = launcher.spawned
        #expect(spawned.count == 3, "expected three spawns, saw \(spawned)")
        #expect(spawned.first?.first == "tap", "the tap did not lead: \(spawned)")
        #expect(spawned.first?.contains("acme/tap") == true)
        // A file-sourced name never becomes anything but its own subject, and no
        // `brew bundle` argv exists on the import path at all.
        for argv in spawned {
            #expect(argv.contains("bundle") == false, "an import constructed \(argv)")
            #expect(argv.contains("trusted") == false, "the trusted: claim reached argv")
            #expect(argv.contains("--file") == false)
        }
        #expect(spawned.contains { $0.contains("wget") })
        #expect(spawned.contains { $0.contains("git") })
    }

    /// Triangulation: with no tap there is no confirmation, and the installs
    /// must still be submitted rather than silently dropped on the `nil`.
    @MainActor
    @Test("An install-only import asks nothing and still submits every install")
    func anInstallOnlyImportAsksNothingAndStillSubmits() async throws {
        let launcher = CompositionLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: AppTestFixtures.installation)
        let store = try await Self.importedStore("brew \"wget\"\ncask \"ghostty\"\n")

        #expect(BrewfileImportAction.apply(store, through: center) == nil)
        #expect(center.pendingConfirmation == nil)

        await Self.untilSpawned(atLeast: 2, launcher)

        let spawned = launcher.spawned
        #expect(spawned.count == 2, "install-only import spawned \(spawned)")
        #expect(spawned.allSatisfy { $0.first == "install" })
        #expect(spawned.contains { $0.contains("--formula") && $0.contains("wget") })
        #expect(spawned.contains { $0.contains("--cask") && $0.contains("ghostty") })
    }

    /// Nothing is submitted without a selection, at the app level too.
    @MainActor
    @Test("Deselecting everything makes the apply a no-op")
    func deselectingEverythingMakesTheApplyANoOp() async throws {
        let launcher = CompositionLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: AppTestFixtures.installation)
        let store = try await Self.importedStore(Self.tapLastBrewfile)
        store.deselectAll()

        #expect(store.canImport == false)
        #expect(BrewfileImportAction.apply(store, through: center) == nil)

        try? await Task.sleep(for: .milliseconds(300))

        #expect(center.items.isEmpty)
        #expect(launcher.spawned.isEmpty, "an empty selection spawned \(launcher.spawned)")
    }

    static func untilSpawned(atLeast count: Int, _ launcher: CompositionLauncher) async {
        for _ in 0..<200 {
            if launcher.spawned.count >= count { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
    }

    // MARK: - 9.3 The import sheet's presentation

    /// A `mixed-kinds` shaped file: three states at once, plus four skip
    /// categories, so one document exercises the whole projection.
    static let mixedBrewfile = """
        tap "acme/tap"
        brew "wget"
        brew "git"
        mas "Xcode", id: 497799835
        vscode "ms-python.python"
        cargo "ripgrep"
        brew "dotnet@9", link: true
        brew "gnupg" if OS.mac?
        brew "wget; rm -rf /"
        """

    @MainActor
    @Test("Missing rows arrive selected, present rows are visible and unselectable")
    func missingRowsArriveSelectedAndPresentRowsAreNot() async throws {
        let store = BrewfileStore()
        let url = try Self.temporaryBrewfile(Self.mixedBrewfile)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await store.importFile(
            at: url,
            installed: InstalledFixture.holding(PackageID(kind: .formula, name: "wget")),
            taps: .empty
        )

        let diff = try #require(store.diff)
        let rows = BrewfileImportRow.rows(for: diff)

        let wget = try #require(rows.first { $0.title == "wget" })
        #expect(wget.state == .present)
        #expect(wget.isSelectable == false, "an installed package was offered as selectable")
        #expect(wget.detail == "Formula · already installed")

        let git = try #require(rows.first { $0.title == "git" })
        #expect(git.state == .missing)
        #expect(git.isSelectable)
        #expect(git.detail == "Formula · not installed")
        #expect(diff.selection.contains(git.id), "a missing entry did not arrive selected")

        let tap = try #require(rows.first { $0.title == "acme/tap" })
        #expect(tap.detail == "Tap · not added")

        // Every skipped line is still a row: skips are shown in place, not
        // dropped and reported only as a total.
        #expect(rows.filter { $0.state == .skipped }.count == 6)
        #expect(rows.allSatisfy { $0.state != .skipped || $0.isSelectable == false })
        // File order, so a line number in the sheet matches the file.
        #expect(rows.map(\.id) == rows.map(\.id).sorted())
    }

    @MainActor
    @Test("A skipped row names its line number and says why, without free text")
    func aSkippedRowNamesItsLineAndSaysWhy() async throws {
        let store = BrewfileStore()
        let url = try Self.temporaryBrewfile(Self.mixedBrewfile)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await store.importFile(at: url, installed: .empty, taps: .empty)

        let diff = try #require(store.diff)
        let rows = BrewfileImportRow.rows(for: diff)
        let conditional = try #require(rows.first { $0.id == 8 })

        #expect(conditional.state == .skipped)
        #expect(conditional.title == "brew \"gnupg\" if OS.mac?", "the raw line was not preserved")
        #expect(conditional.detail.hasPrefix("Line 8 · "))
        #expect(conditional.detail.contains(BrewfileSkipCopy.reason(for: .rubyConditional)))
        #expect(conditional.detail.contains("never runs it"))
    }

    /// The counted summary a user reads instead of the file. Every category is
    /// named, counted, and expanded with what it refused.
    @MainActor
    @Test("Skips are grouped, counted and named")
    func skipsAreGroupedCountedAndNamed() async throws {
        let store = BrewfileStore()
        let url = try Self.temporaryBrewfile(Self.mixedBrewfile)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await store.importFile(at: url, installed: .empty, taps: .empty)

        let diff = try #require(store.diff)
        let groups = BrewfileSkipGroup.groups(for: diff)

        #expect(groups.map(\.category) == [
            .unsupportedEntryKind, .unsupportedOption, .rubyConditional, .unrepresentableName
        ])

        let kinds = try #require(groups.first { $0.category == .unsupportedEntryKind })
        #expect(kinds.count == 3)
        #expect(kinds.headline == "3 lines skipped")
        #expect(kinds.reason == BrewfileSkipCopy.reason(for: .unsupportedEntryKind))
        #expect(kinds.detail == "cargo, mas, vscode", "the refused kinds were not named")
        #expect(kinds.lines == "Lines 4, 5, 6")

        let option = try #require(groups.first { $0.category == .unsupportedOption })
        #expect(option.count == 1)
        #expect(option.headline == "1 line skipped")
        #expect(option.detail == "link")
        #expect(option.lines == "Line 7")

        // Every category carries copy: a user reading "3 lines skipped" can tell
        // why without opening the file.
        for category in BrewfileSkipReason.Category.allCases {
            #expect(BrewfileSkipCopy.reason(for: category).isEmpty == false)
            #expect(BrewfileSkipCopy.reason(for: category).hasSuffix("."))
        }
    }

    @MainActor
    @Test("A file that is only skips still imports nothing but is not an error")
    func aFileThatIsOnlySkipsIsStillAValidImport() async throws {
        let store = BrewfileStore()
        let url = try Self.temporaryBrewfile("mas \"Xcode\", id: 1\nvscode \"ms-python.python\"\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await store.importFile(at: url, installed: .empty, taps: .empty)

        let diff = try #require(store.diff)
        #expect(diff.summary == .everythingSkipped)
        #expect(BrewfileSkipGroup.groups(for: diff).first?.count == 2)
        // The sheet's headline distinguishes it from "the file said nothing".
        #expect(
            BrewfileImportSummaryCopy.sentence(for: .everythingSkipped)
                != BrewfileImportSummaryCopy.sentence(for: .nothingInTheFile)
        )
        for summary in [
            BrewfileDiff.Summary.nothingInTheFile,
            .everythingAlreadyPresent,
            .everythingSkipped,
            .actionable
        ] {
            #expect(BrewfileImportSummaryCopy.sentence(for: summary).isEmpty == false)
        }
    }

    /// A `trusted:` claim is shown, attributed to the file's author, and confers
    /// nothing (`brewfile-management` BF5).
    @MainActor
    @Test("A trusted: claim is surfaced and attributed to the file")
    func aTrustedClaimIsSurfacedAndAttributed() async throws {
        let store = BrewfileStore()
        let url = try Self.temporaryBrewfile("tap \"acme/tap\", trusted: true\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        await store.importFile(at: url, installed: .empty, taps: .empty)

        let diff = try #require(store.diff)
        let row = try #require(BrewfileImportRow.rows(for: diff).first)

        #expect(row.trustClaim == BrewfileTrustClaim.attribution)
        #expect(row.trustClaim?.contains("Cellar grants no trust") == true)
    }

    /// The attribution above the list: this is Cellar's reading, not brew's.
    @MainActor
    @Test("The sheet reuses the attribution constant rather than inventing one")
    func theSheetReusesTheAttributionConstant() throws {
        let source = try Self.appSource("BrewfileImportSheet.swift")
        #expect(source.stripped.contains("BrewfileDiff.attribution"))
        #expect(source.stripped.contains("BrewfileTrustClaim.attribution"))
        // No brew invocation is constructible from the sheet at all.
        for forbidden in ["bundle", "Process", "/bin/sh", "BrewCommand"] {
            #expect(source.stripped.contains(forbidden) == false, "the sheet names \(forbidden)")
        }
    }
}

// MARK: - 9.5 Placement

/// Where the Brewfile affordances live.
///
/// **Rewritten, never deleted**, when the design document promoted the Brewfile
/// to a sidebar section of its own (`Cellar.dc.html`, 2026-08-07). D3's original
/// ruling — sheets inside Taps, no destination — was made before that document
/// existed; the design supersedes the placement half while everything the sheets
/// guarantee (dump-then-preview-then-panel, panel-chooses-Cellar-writes) is
/// untouched, because the new section presents the **same** sheets over the same
/// `BrewfileStore`. The Taps toolbar affordances remain beside it.
@Suite("Brewfile placement")
struct BrewfilePlacementTests {

    /// The whole-vocabulary assertion, corrected rather than loosened: *any*
    /// new section still fails it, which is exactly what it is for. The design
    /// added four — favorites, updates, brewfile, settings — and the CaskHub
    /// port added four more cask-discovery pages; each is named explicitly so
    /// a nineteenth section fails here too. The nineteenth then arrived on
    /// purpose — `caskCategory`, the one case behind every data-driven
    /// category page — followed by the three formula-discovery pages that
    /// mirror the cask ones (2026-08-17), and minus the original Discover
    /// section the same day; each remaining case is named explicitly like the
    /// rest, so a twenty-second still fails.
    @Test("The sidebar vocabulary is the design document's twenty-one sections")
    func theSidebarVocabularyIsTheDesignDocumentsSections() {
        #expect(
            AppSection.allCases.map(\.rawValue) == [
                "home", "browse",
                "caskBrowse", "caskFeatured", "caskTopCharts", "caskRecentlyAdded",
                "caskCategory",
                "formulaBrowse", "formulaFeatured", "formulaTopCharts",
                "installed", "favorites", "updates",
                "taps", "services", "cleanup", "health", "security", "brewfile",
                "history", "settings"
            ]
        )
        #expect(AppSection.allCases.count == 21)
    }

    @Test("Both affordances live in the Brewfile section, and the sheets are presented nowhere else")
    func bothAffordancesLiveInTheBrewfileSection() throws {
        let sources = try AppSecuritySources.load()
        let section = try #require(
            sources.first { $0.name == "BrewfileSectionView.swift" },
            "the Brewfile section view is missing from the app target"
        )

        #expect(section.code.contains("BrewfileImportSheet"))
        #expect(section.code.contains("BrewfileExportSheet"))
        #expect(section.code.contains("BrewfileSourcePanel"))
        #expect(section.code.contains("brewfile-section-import"))
        #expect(section.code.contains("brewfile-section-export"))
        // Not a destination. A sheet, over the section the user is already in.
        #expect(
            section.code.contains("navigationDestination") == false,
            "the Brewfile affordances added a navigation destination"
        )

        // The design port moved both flows out of the Taps list and into the
        // Brewfile section. This seals the move: a chip drifting back into Taps
        // would revive the two-surface split the section was created to end.
        let taps = try BrewfileCompositionTests.appSource("TapsListView.swift")
        #expect(
            taps.stripped.contains("Brewfile") == false,
            "the Taps list grew a Brewfile affordance back"
        )

        // The sheets are presented from the Brewfile section and from no other
        // view — both flows stay on the one store that owns the DD3/DD4
        // ordering guarantees.
        for other in sources where other.name != "BrewfileSectionView.swift" {
            #expect(
                other.code.contains("BrewfileImportSheet(") == false,
                "\(other.name) also presents the import sheet"
            )
            #expect(
                other.code.contains("BrewfileExportSheet(") == false,
                "\(other.name) also presents the export sheet"
            )
        }
    }
}

// MARK: - 9.4 The export sheet

/// A dump that answers with whatever the test decided, and counts its runs.
struct StubDumpSource: BundleDumpSourcing {
    let outcome: Result<BundleDumpResult, BundleDumpError>
    let tag: String

    init(_ outcome: Result<BundleDumpResult, BundleDumpError>) {
        self.outcome = outcome
        tag = UUID().uuidString
        BrewfileCompositionLedger.spawns.withLock { $0[tag] = [] }
    }

    var runCount: Int { BrewfileCompositionLedger.spawns.withLock { $0[tag]?.count ?? 0 } }

    func dump(for detection: BrewDetectionState) async throws(BundleDumpError) -> BundleDumpResult {
        BrewfileCompositionLedger.spawns.withLock { $0[tag, default: []].append(["dump"]) }
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}

/// A destination chooser that records whether it was ever asked.
///
/// Per instance, like everything else here: "the panel never opened" is an
/// absence, and an absence needs a recorder that would have counted a presence.
struct RecordingDestinationChooser: BrewfileDestinationChoosing {
    let destination: URL?
    let tag: String

    init(destination: URL?) {
        self.destination = destination
        tag = UUID().uuidString
        BrewfileCompositionLedger.spawns.withLock { $0[tag] = [] }
    }

    var askedCount: Int { BrewfileCompositionLedger.spawns.withLock { $0[tag]?.count ?? 0 } }

    func chooseDestination() async -> URL? {
        BrewfileCompositionLedger.spawns.withLock { $0[tag, default: []].append(["choose"]) }
        return destination
    }
}

@MainActor
@Suite("Brewfile export composition", .timeLimit(.minutes(1)))
struct BrewfileExportCompositionTests {

    static let document = Data("tap \"homebrew/core\"\nbrew \"wget\"\n".utf8)

    static func exported(_ outcome: Result<BundleDumpResult, BundleDumpError>) async -> BrewfileStore {
        let store = BrewfileStore()
        await store.export(using: StubDumpSource(outcome), detection: .absent)
        return store
    }

    /// The whole of design DD3, at the level a user meets it: the panel is
    /// offered only when there are bytes to write.
    @Test("The save panel is offered only after a successful preview")
    func theSavePanelIsOfferedOnlyAfterASuccessfulPreview() async {
        let idle = BrewfileStore()
        #expect(BrewfileExportPresentation(state: idle.exportState).canPublish == false)

        let failed = await Self.exported(.failure(.documentUnreadable))
        #expect(BrewfileExportPresentation(state: failed.exportState).canPublish == false)

        let previewed = await Self.exported(
            .success(BundleDumpResult(document: Self.document, rawStderr: Data()))
        )
        #expect(BrewfileExportPresentation(state: previewed.exportState).canPublish)
    }

    @Test("A failed dump never opens a panel and never writes")
    func aFailedDumpNeverOpensAPanelAndNeverWrites() async {
        let store = await Self.exported(
            .failure(.commandFailed(status: 1, rawStdout: Data(), rawStderr: Data("locked\n".utf8)))
        )
        let chooser = RecordingDestinationChooser(destination: URL(fileURLWithPath: "/tmp/nope"))

        let presentation = BrewfileExportPresentation(state: store.exportState)
        #expect(presentation.canPublish == false)
        #expect(presentation.detail.contains("1"), "the exit status was not reported")

        // Even if something called it anyway, the store refuses: there is no
        // preview to publish.
        await store.publish(to: chooser)
        #expect(chooser.askedCount == 0, "a failed dump reached the save panel")
    }

    /// The bytes shown are the dump's bytes. No provenance header, no reordering,
    /// no re-encoding (`brewfile-management` BF9).
    @Test("The preview shows the document verbatim")
    func thePreviewShowsTheDocumentVerbatim() async {
        let store = await Self.exported(
            .success(BundleDumpResult(document: Self.document, rawStderr: Data("warning\n".utf8)))
        )
        let presentation = BrewfileExportPresentation(state: store.exportState)

        #expect(presentation.canPublish)
        #expect(presentation.documentText == "tap \"homebrew/core\"\nbrew \"wget\"\n")
        #expect(
            presentation.documentText?.contains("warning") == false,
            "stderr leaked into the previewed document"
        )
        // An exit-zero run with a non-empty stderr is still a success.
        #expect(presentation.isFailure == false)
    }

    @Test("Publishing writes exactly the previewed bytes to the chosen path")
    func publishingWritesExactlyThePreviewedBytes() async throws {
        let store = await Self.exported(
            .success(BundleDumpResult(document: Self.document, rawStderr: Data()))
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Brewfile")
        let chooser = RecordingDestinationChooser(destination: destination)

        await store.publish(to: chooser)

        #expect(chooser.askedCount == 1)
        #expect(store.exportState == .published(destination))
        #expect(try Data(contentsOf: destination) == Self.document)
        #expect(BrewfileExportPresentation(state: store.exportState).isPublished)
    }

    @Test("Cancelling the destination publishes nothing and keeps the preview")
    func cancellingTheDestinationPublishesNothing() async {
        let store = await Self.exported(
            .success(BundleDumpResult(document: Self.document, rawStderr: Data()))
        )
        let chooser = RecordingDestinationChooser(destination: nil)

        await store.publish(to: chooser)

        #expect(chooser.askedCount == 1)
        #expect(store.exportState == .preview(Self.document), "cancelling lost the preview")
        #expect(BrewfileExportPresentation(state: store.exportState).canPublish)
    }

    @Test("Every export state has a headline, and no two settled ones match")
    func everyExportStateHasAHeadline() async {
        let idle = BrewfileExportPresentation(state: .idle)
        let dumping = BrewfileExportPresentation(state: .dumping)
        let preview = BrewfileExportPresentation(state: .preview(Self.document))
        let published = BrewfileExportPresentation(
            state: .published(URL(fileURLWithPath: "/tmp/Brewfile"))
        )
        let failed = BrewfileExportPresentation(state: .failed(.dumpFailed(.documentUnreadable)))

        let headlines = [idle, dumping, preview, published, failed].map(\.headline)
        #expect(headlines.allSatisfy { $0.isEmpty == false })
        #expect(Set(headlines).count == headlines.count, "two export states read the same")
        #expect(published.detail.contains("Brewfile"), "the published path was not named")
        #expect(failed.isFailure)
    }

    /// The export sheet is a surface over the store, and constructs no argv.
    @Test("The export sheet builds no brew invocation of its own")
    func theExportSheetBuildsNoBrewInvocationOfItsOwn() throws {
        let source = try BrewfileCompositionTests.appSource("BrewfileExportSheet.swift")
        // `import BrewProcess` is how `BrewDetectionState` is named, so the scan
        // is over the things that *spawn* rather than over the substring
        // "Process" — the whole-identifier discipline amendment A6 established.
        for forbidden in [
            "bundle", "BrewCommand", "ProcessSpec", "ProcessLaunching",
            "SystemProcessLauncher", "/bin/sh", "--file", "--force"
        ] {
            #expect(source.stripped.contains(forbidden) == false, "the sheet names \(forbidden)")
        }
        for forbidden in ["UserDefaults", "AppStorage", "bookmarkData"] {
            #expect(source.stripped.contains(forbidden) == false, "the sheet remembers \(forbidden)")
        }
    }
}

/// Inventories for the composition suite.
///
/// Built through the shipped initialiser rather than through a decoded payload,
/// because only membership matters here — the diff asks `installedIDs.contains`
/// and nothing else.
enum InstalledFixture {
    static func holding(_ ids: PackageID...) -> InstalledInventory {
        let keg = InstalledKeg(version: "1.0", installedAt: .distantPast, installedOnRequest: true)
        return InstalledInventory(
            packages: ids.map { id in
                InstalledPackage(
                    kind: id.kind,
                    name: id.name,
                    displayName: id.name,
                    desc: nil,
                    homepage: nil,
                    tap: "homebrew/core",
                    catalogVersion: "1.0",
                    kegs: [keg],
                    primaryKeg: keg,
                    snapshotOutdated: false,
                    isPinned: false,
                    pinnedVersion: nil,
                    declaresAutoUpdates: nil
                )
            }
        )
    }
}
