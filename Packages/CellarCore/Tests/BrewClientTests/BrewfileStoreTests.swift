import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The store (design DD5, DD6; `brewfile-management` BF6, BF9).
///
/// Both state machines are **closed enums**, the `ServicesLoadState` /
/// `InstalledLoadState` idiom: every state a surface can be in is a case, all
/// state is `private(set)`, and no state is an empty value, a `nil`, or a
/// never-settling pending case. That is what makes "the file said nothing",
/// "you already have all of it" and "we could not read it" three different
/// screens rather than one blank list.
@MainActor
@Suite("Brewfile store", .timeLimit(.minutes(1)))
struct BrewfileStoreTests {

    static let sourceURL = URL(fileURLWithPath: "/Users/someone/Documents/Brewfile")
    static let destination = URL(fileURLWithPath: "/Users/someone/Desktop/Exported")
    static let temporaryRoot = URL(fileURLWithPath: "/var/folders/xx/T")

    static func store(
        fileSystem: RecordingFileSystem = RecordingFileSystem()
    ) -> BrewfileStore {
        BrewfileStore(fileSystem: fileSystem)
    }

    static func fixtureBytes(_ name: String) throws -> Data {
        try Data(contentsOf: BrewfileFixtureManifest.root.appendingPathComponent(name))
    }

    // MARK: - DD5 — closed state machines

    @Test("Both state machines start idle, and idle is a real state")
    func bothStateMachinesStartIdle() {
        let store = Self.store()

        #expect(store.importState == .idle)
        #expect(store.exportState == .idle)
        #expect(store.diff == nil, "an idle store invented an empty diff")
        #expect(store.plan == nil)
        #expect(store.advisories.isEmpty)
    }

    @Test("Reading a file settles on a parsed diff, never on an empty list")
    func readingAFileSettlesOnAParsedDiff() async throws {
        let fileSystem = RecordingFileSystem(
            contents: [Self.sourceURL: Data("brew \"wget\"\nbrew \"git\"\n".utf8)]
        )
        let store = Self.store(fileSystem: fileSystem)

        await store.importFile(
            from: StubSourceChooser(source: Self.sourceURL),
            installed: InstalledFixture.inventory(upToDate: [PackageID(kind: .formula, name: "wget")]),
            taps: .empty
        )

        guard case .parsed(let diff) = store.importState else {
            Issue.record("the import settled on \(store.importState)")
            return
        }
        #expect(diff.missing.map(\.displayName) == ["git"])
        #expect(diff.present.map(\.displayName) == ["wget"])
        #expect(store.diff?.selection == diff.selection)
    }

    @Test("A cancelled source choice leaves the store idle rather than failed")
    func aCancelledSourceChoiceLeavesTheStoreIdle() async {
        let store = Self.store()

        await store.importFile(from: StubSourceChooser(source: nil), installed: .empty, taps: .empty)

        #expect(store.importState == .idle, "cancelling was reported as a failure")
        #expect(store.diff == nil)
    }

    @Test("An unreadable file is a typed failure, not an empty parse")
    func anUnreadableFileIsATypedFailure() async {
        let fileSystem = RecordingFileSystem()
        fileSystem.failReads(with: CocoaError(.fileReadNoPermission))
        let store = Self.store(fileSystem: fileSystem)

        await store.importFile(
            from: StubSourceChooser(source: Self.sourceURL),
            installed: .empty,
            taps: .empty
        )

        #expect(store.importState == .failed(.unreadable(Self.sourceURL)))
        #expect(store.diff == nil, "a failed read left a diff behind")
    }

    @Test("An oversized file is refused whole, with the bound named")
    func anOversizedFileIsRefusedWhole() async throws {
        let line = "brew \"wget\"\n"
        let repeats = (BrewfileParser.maximumByteCount / line.utf8.count) + 64
        let oversized = Data(String(repeating: line, count: repeats).utf8)
        let fileSystem = RecordingFileSystem(contents: [Self.sourceURL: oversized])
        let store = Self.store(fileSystem: fileSystem)

        await store.importFile(
            from: StubSourceChooser(source: Self.sourceURL),
            installed: .empty,
            taps: .empty
        )

        #expect(
            store.importState
                == .failed(.tooLarge(bytes: oversized.count, limit: BrewfileParser.maximumByteCount))
        )
    }

    /// The three empties, at the level a surface actually reads them.
    @Test(
        "The store distinguishes the three empties",
        arguments: [
            ("# nothing\n", BrewfileDiff.Summary.nothingInTheFile),
            ("mas \"Xcode\", id: 1\n", BrewfileDiff.Summary.everythingSkipped),
            ("brew \"wget\"\n", BrewfileDiff.Summary.actionable)
        ]
    )
    func theStoreDistinguishesTheThreeEmpties(
        text: String,
        expected: BrewfileDiff.Summary
    ) async throws {
        let fileSystem = RecordingFileSystem(contents: [Self.sourceURL: Data(text.utf8)])
        let store = Self.store(fileSystem: fileSystem)

        await store.importFile(
            from: StubSourceChooser(source: Self.sourceURL),
            installed: .empty,
            taps: .empty
        )

        #expect(store.diff?.summary == expected)
    }

    // MARK: - Selection, at the level the UI reads it

    @Test("Selection initialises to the missing set and refuses everything else")
    func selectionInitialisesToTheMissingSet() async throws {
        let text = """
            brew "wget"
            brew "git"
            mas "Xcode", id: 497799835
            """
        let fileSystem = RecordingFileSystem(contents: [Self.sourceURL: Data(text.utf8)])
        let store = Self.store(fileSystem: fileSystem)

        await store.importFile(
            from: StubSourceChooser(source: Self.sourceURL),
            installed: InstalledFixture.inventory(upToDate: [PackageID(kind: .formula, name: "wget")]),
            taps: .empty
        )

        let diff = try #require(store.diff)
        #expect(diff.selection == Set(diff.missing.map(\.id)))
        #expect(diff.missing.map(\.displayName) == ["git"])

        // A present row and a skipped row cannot be selected, through the store.
        let presentID = try #require(diff.present.first?.id)
        let skippedID = try #require(diff.skips.first?.id)
        store.select(presentID)
        store.select(skippedID)
        #expect(store.diff?.selection == diff.selection, "the store let a non-missing row in")

        // The missing one toggles, both ways.
        let missingID = try #require(diff.missing.first?.id)
        store.toggle(missingID)
        #expect(store.diff?.selection.isEmpty == true)
        store.toggle(missingID)
        #expect(store.diff?.selection == [missingID])
    }

    /// Confirmed decision 3, restated where the UI actually reads it: skips do
    /// not gate the import button.
    @Test("Skips never gate the import, even when the file is entirely skips")
    func skipsNeverGateTheImport() async throws {
        let text = """
            mas "Xcode", id: 497799835
            vscode "ms-python.python"
            brew "wget"
            """
        let fileSystem = RecordingFileSystem(contents: [Self.sourceURL: Data(text.utf8)])
        let store = Self.store(fileSystem: fileSystem)

        await store.importFile(
            from: StubSourceChooser(source: Self.sourceURL),
            installed: .empty,
            taps: .empty
        )

        #expect(store.diff?.skips.count == 2)
        #expect(store.canImport, "counted skips disabled the import")
        #expect(store.plan?.commands.map(\.arguments) == [["install", "--formula", "wget"]])

        // An all-skipped file leaves the import unavailable because there is
        // nothing selected — not because skips blocked it.
        let onlySkips = RecordingFileSystem(
            contents: [Self.sourceURL: Data("mas \"Xcode\", id: 1\n".utf8)]
        )
        let second = Self.store(fileSystem: onlySkips)
        await second.importFile(
            from: StubSourceChooser(source: Self.sourceURL),
            installed: .empty,
            taps: .empty
        )
        #expect(second.diff?.skips.count == 1)
        #expect(second.canImport == false)
        #expect(second.plan?.isEmpty == true)
        #expect(second.importState != .idle, "an all-skipped file was treated as no import at all")
    }

    // MARK: - Export

    @Test("An export moves idle to preview, and publishing settles on the destination")
    func anExportMovesIdleToPreviewAndPublishes() async throws {
        let document = try Self.fixtureBytes("dump-file.brewfile")
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: document)
        let store = Self.store(fileSystem: fileSystem)
        let source = BundleDumpSource(
            launcher: RecordingProcessLauncher([ScriptedRun(stdout: "", stderr: "")]),
            fileSystem: fileSystem,
            temporaryRoot: Self.temporaryRoot
        )

        await store.export(using: source, detection: .detected(TestInstallation.appleSilicon))

        guard case .preview(let previewed) = store.exportState else {
            Issue.record("the export settled on \(store.exportState)")
            return
        }
        #expect(previewed == document, "the preview is not the dump's bytes")

        await store.publish(to: StubDestinationChooser(destination: Self.destination))

        #expect(store.exportState == .published(Self.destination))
        #expect(fileSystem.bytes(at: Self.destination) == document, "the published bytes drifted")
    }

    /// The panel opens only after a successful preview, so a dump failure never
    /// reaches the user's disk.
    @Test("A failed dump never reaches publication")
    func aFailedDumpNeverReachesPublication() async throws {
        let fileSystem = RecordingFileSystem()
        let store = Self.store(fileSystem: fileSystem)
        let source = BundleDumpSource(
            launcher: RecordingProcessLauncher([
                ScriptedRun(stdout: "", stderr: "boom\n", exit: BrewExit(status: 1, reason: .exited))
            ]),
            fileSystem: fileSystem,
            temporaryRoot: Self.temporaryRoot
        )

        await store.export(using: source, detection: .detected(TestInstallation.appleSilicon))

        guard case .failed(let error) = store.exportState else {
            Issue.record("a non-zero dump settled on \(store.exportState)")
            return
        }
        #expect(error == .dumpFailed(.commandFailed(
            status: 1,
            rawStdout: Data(),
            rawStderr: Data("boom\n".utf8)
        )))

        // Publishing from a failed export writes nothing at all.
        await store.publish(to: StubDestinationChooser(destination: Self.destination))
        #expect(fileSystem.bytes(at: Self.destination) == nil)
        #expect(fileSystem.calls.contains { call in
            if case .write = call { return true } else { return false }
        } == false)
    }

    @Test("Cancelling the destination choice keeps the preview and publishes nothing")
    func cancellingTheDestinationChoiceKeepsThePreview() async throws {
        let document = try Self.fixtureBytes("dump-file.brewfile")
        let fileSystem = RecordingFileSystem()
        fileSystem.answerSubprocessWrite(with: document)
        let store = Self.store(fileSystem: fileSystem)
        let source = BundleDumpSource(
            launcher: RecordingProcessLauncher([ScriptedRun(stdout: "", stderr: "")]),
            fileSystem: fileSystem,
            temporaryRoot: Self.temporaryRoot
        )

        await store.export(using: source, detection: .detected(TestInstallation.appleSilicon))
        await store.publish(to: StubDestinationChooser(destination: nil))

        #expect(store.exportState == .preview(document), "cancelling lost the preview")
        #expect(fileSystem.containsAnything(under: Self.temporaryRoot) == false)
    }

    @Test("A failed publication is typed, and the preview survives it")
    func aFailedPublicationIsTypedAndThePreviewSurvives() async throws {
        let document = try Self.fixtureBytes("dump-file.brewfile")
        let existing = Data("brew \"already-here\"\n".utf8)
        let fileSystem = RecordingFileSystem(contents: [Self.destination: existing])
        fileSystem.answerSubprocessWrite(with: document)
        let store = Self.store(fileSystem: fileSystem)
        let source = BundleDumpSource(
            launcher: RecordingProcessLauncher([ScriptedRun(stdout: "", stderr: "")]),
            fileSystem: fileSystem,
            temporaryRoot: Self.temporaryRoot
        )

        await store.export(using: source, detection: .detected(TestInstallation.appleSilicon))
        fileSystem.failWrites(with: CocoaError(.fileWriteNoPermission))
        await store.publish(to: StubDestinationChooser(destination: Self.destination))

        guard case .failed(let error) = store.exportState else {
            Issue.record("a failed publication settled on \(store.exportState)")
            return
        }
        guard case .publicationFailed(let destination, _) = error else {
            Issue.record("a failed publication produced \(error)")
            return
        }
        #expect(destination == Self.destination)
        #expect(fileSystem.bytes(at: Self.destination) == existing, "the existing file changed")
        // The state is the failure — but the bytes survive it, so a retry to
        // another location does not have to pay for a second dump.
        #expect(store.previewDocument == nil, "a failed publication still reads as a preview")
        #expect(store.retryableDocument == document, "the dump's bytes were lost on a failed write")
    }

    // MARK: - DD6 — the sudo-password advisory

    /// `SystemProcess` sets `standardInput = .nullDevice`, so a cask needing an
    /// administrator password fails opaquely. The advisory is **Brewfile-scoped**
    /// and derived from the terminal item — `classify`'s outcome vocabulary is
    /// untouched, because widening it would change every install path.
    @Test("A cask that needed a password yields a Brewfile-scoped advisory")
    func aCaskThatNeededAPasswordYieldsABrewfileScopedAdvisory() async throws {
        let harness = CenterHarness()
        let cask = try #require(PackageTarget(kind: .cask, name: "docker"))
        let item = harness.center.submit(MutationCommand.install(cask))
        await harness.settle()
        // The shipped privilege signature, verbatim from `MutationOutcome`.
        try #require(harness.launcher.launchedProcesses.first).emitStderr(
            "sudo: a password is required\n"
        )
        try await harness.finish(call: 0, status: 1)

        #expect(item.outcome == .needsPrivileges, "the shipped classification changed")

        let store = Self.store()
        store.noteTerminal(item)

        let advisory = try #require(store.advisories.first)
        #expect(advisory.packageID == PackageID(kind: .cask, name: "docker"))
        #expect(advisory.message.contains("docker"))
        #expect(advisory.message.lowercased().contains("administrator password"))
        #expect(advisory.message.lowercased().contains("terminal"))
        #expect(advisory.message.lowercased().contains("cellar cannot"))
    }

    @Test("An ordinary failure produces no advisory, and a success produces none either")
    func anOrdinaryFailureProducesNoAdvisory() async throws {
        let harness = CenterHarness()
        let store = Self.store()

        let failing = harness.center.submit(
            MutationCommand.install(PackageTarget(kind: .formula, name: "wget")!)
        )
        try await harness.finish(call: 0, status: 1)
        store.noteTerminal(failing)
        #expect(failing.outcome == .failed(status: 1))
        #expect(store.advisories.isEmpty, "an ordinary failure produced a password advisory")

        let succeeding = harness.center.submit(
            MutationCommand.install(PackageTarget(kind: .cask, name: "iterm2")!)
        )
        try await harness.finish(call: 1)
        store.noteTerminal(succeeding)
        #expect(succeeding.outcome == .succeeded)
        #expect(store.advisories.isEmpty)
    }

    /// The vocabulary this decision refused to widen, asserted rather than
    /// assumed: nothing here adds a `MutationOutcome` case, and nothing leaks
    /// into `package-mutation` or the durable history.
    @Test("The advisory adds no MutationOutcome case and touches no history")
    func theAdvisoryAddsNoMutationOutcomeCase() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let store = try #require(sources.first { $0.name == "BrewfileStore.swift" })

        for reach in ["MutationOutcome(", "HistoryDraft", "HistoryRecording", "classify"] {
            #expect(
                store.code.contains(reach) == false,
                "BrewfileStore.swift reaches for \(reach)"
            )
        }

        // The shipped vocabulary, unchanged and unwidened.
        let outcome = try #require(sources.first { $0.name == "MutationOutcome.swift" })
        for declared in [
            "case succeeded", "case failed(status: Int32)", "case busy", "case needsPrivileges",
            "case noChange", "case cancelled", "case abandoned(after: Duration)",
            "case launchFailed", "case authorizationDenied(MutationLaunchDenial.Code)"
        ] {
            #expect(outcome.code.contains(declared), "\(declared) left the outcome vocabulary")
        }
        for invented in ["Brewfile", "brewfile", "passwordRequired", "advisory"] {
            #expect(
                outcome.code.contains(invented) == false,
                "a Brewfile concept leaked into the outcome vocabulary: \(invented)"
            )
        }
    }

    // MARK: - DD5 — the shape of the type

    @Test("All state is private(set), with no actor, no unsafe and no availability branch")
    func allStateIsPrivateSet() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let store = try #require(sources.first { $0.name == "BrewfileStore.swift" })

        #expect(store.code.contains("@MainActor"))
        #expect(store.code.contains("@Observable"))
        #expect(store.code.contains("public final class BrewfileStore"))
        #expect(store.code.contains("public private(set) var importState"))
        #expect(store.code.contains("public private(set) var exportState"))

        for forbidden in ["nonisolated(unsafe)", "#available", "actor ", "@unchecked"] {
            #expect(store.code.contains(forbidden) == false, "BrewfileStore.swift uses \(forbidden)")
        }
        // No **stored** `public var` — every state change goes through a
        // method, so a surface cannot assign a state directly. A computed
        // `public var` is a projection and carries no storage, so it is not the
        // thing this rule is about.
        let assignable = store.code
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("public var ") && $0.contains("{") == false }
        #expect(assignable.isEmpty, "a state is publicly assignable: \(assignable)")
    }
}
