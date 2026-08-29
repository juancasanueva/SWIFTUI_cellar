import BrewClient
import Catalog
import Foundation
import SwiftData
import Testing

@testable import Persistence

/// npm's durable rows: the identity and verbs they store, the presentation they
/// derive from them, and the way a build without the npm kind reads them
/// (`installation-history` — "npm entries store the npm identity, namespaced
/// verbs and a source-aware presentation"; design D12).
@MainActor
@Suite("npm history")
struct NpmHistoryTests {
    private static let typescript = PackageID(kind: .npm, name: "typescript")
    private static let corepack = PackageID(kind: .npm, name: "corepack")
    private static let wget = PackageID(kind: .formula, name: "wget")

    private static func draft(
        packageID: PackageID?,
        verb: String,
        versions: VersionTransition? = nil,
        outcome: MutationOutcome = .succeeded,
        argv: [String]
    ) -> HistoryDraft {
        HistoryDraft(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            packageID: packageID,
            verb: verb,
            versions: versions,
            outcome: outcome,
            argv: argv
        )
    }

    // MARK: - What one npm operation stores

    @Test("Each npm verb writes one identity-bearing row through the existing columns")
    func eachNpmVerbWritesOneRow() throws {
        let container = try PersistenceContainer.inMemory()
        let store = HistoryStore(container: container)
        let recorder = SwiftDataHistoryRecorder(store: store)

        recorder.record(Self.draft(
            packageID: Self.typescript,
            verb: "npmUpgrade",
            versions: VersionTransition(from: "5.6.2", to: "5.7.0"),
            argv: ["install", "-g", "typescript@latest"]
        ))
        recorder.record(Self.draft(
            packageID: Self.corepack,
            verb: "npmUninstall",
            argv: ["uninstall", "-g", "corepack"]
        ))

        #expect(store.records.count == 2)
        let byVerb = Dictionary(uniqueKeysWithValues: store.records.map { ($0.verb, $0) })

        let upgrade = try #require(byVerb["npmUpgrade"])
        #expect(upgrade.packageID == Self.typescript)
        #expect(upgrade.packageID?.kind == .npm)
        #expect(upgrade.name == "typescript")
        #expect(upgrade.versionFrom == "5.6.2")
        #expect(upgrade.versionTo == "5.7.0")
        #expect(upgrade.argv == ["install", "-g", "typescript@latest"])
        #expect(upgrade.outcomeRaw == "succeeded")

        let uninstall = try #require(byVerb["npmUninstall"])
        #expect(uninstall.packageID == Self.corepack)
        #expect(uninstall.versions == nil)
        #expect(uninstall.argv == ["uninstall", "-g", "corepack"])
    }

    /// No schema migration: the npm kind travels through the shipped `kindRaw`
    /// string column exactly as `formula` and `cask` do.
    @Test("The npm kind travels through the existing kindRaw column")
    func npmKindUsesTheExistingColumn() {
        let row = SwiftDataHistoryRecorder.row(from: Self.draft(
            packageID: Self.typescript,
            verb: "npmUpgrade",
            argv: ["install", "-g", "typescript@latest"]
        ))

        #expect(row.kindRaw == "npm")
        #expect(row.name == "typescript")
        #expect(row.packageID == Self.typescript)
        #expect(row.commandText == "install -g typescript@latest")
    }

    // MARK: - Presentation

    @Test("Presentation is source-aware")
    func presentationIsSourceAware() throws {
        let container = try PersistenceContainer.inMemory()
        let store = HistoryStore(container: container)
        SwiftDataHistoryRecorder(store: store).record(Self.draft(
            packageID: Self.typescript,
            verb: "npmUpgrade",
            outcome: .needsPrivileges,
            argv: ["install", "-g", "typescript@latest"]
        ))

        let record = try #require(store.records.first)

        #expect(record.source == .npm)
        #expect(record.sourceLabel == "npm")
        #expect(record.displayCommand == "npm install -g typescript@latest")
        #expect(record.outcomeLabel.localizedCaseInsensitiveContains("npm"))
        #expect(record.outcomeLabel.contains("Homebrew") == false)
        #expect(record.subject == .package("typescript"))
    }

    /// Triangulation, and the containment claim: a brew row's presentation is
    /// byte-identical to what it shipped as.
    @Test("A Homebrew row's presentation is unchanged")
    func homebrewPresentationIsUnchanged() throws {
        let container = try PersistenceContainer.inMemory()
        let store = HistoryStore(container: container)
        let recorder = SwiftDataHistoryRecorder(store: store)
        recorder.record(Self.draft(
            packageID: Self.wget,
            verb: "upgrade",
            outcome: .failed(status: 243),
            argv: ["upgrade", "--formula", "wget"]
        ))

        let record = try #require(store.records.first)

        #expect(record.source == .homebrew)
        #expect(record.sourceLabel == "Homebrew")
        #expect(record.displayCommand == "brew upgrade --formula wget")
        #expect(record.outcomeLabel == "Failed (243)")
    }

    @Test("An npm exit status is worded for npm rather than for Homebrew")
    func npmExitStatusIsWordedForNpm() throws {
        let container = try PersistenceContainer.inMemory()
        let store = HistoryStore(container: container)
        SwiftDataHistoryRecorder(store: store).record(Self.draft(
            packageID: Self.typescript,
            verb: "npmUpgrade",
            outcome: .failed(status: 243),
            argv: ["install", "-g", "typescript@latest"]
        ))

        let record = try #require(store.records.first)

        #expect(record.outcomeLabel.contains("243"))
        #expect(record.outcomeLabel.localizedCaseInsensitiveContains("npm"))
        #expect(record.outcomeLabel != "Failed (243)")
    }

    /// The argv stays **display-only**: the rendered command is a prefix plus
    /// the stored vector joined, and nothing anywhere turns it back into one.
    @Test("The stored argv is display-only and the rendering is one-way")
    func argvStaysDisplayOnly() throws {
        let container = try PersistenceContainer.inMemory()
        let store = HistoryStore(container: container)
        SwiftDataHistoryRecorder(store: store).record(Self.draft(
            packageID: Self.typescript,
            verb: "npmUpgrade",
            argv: ["install", "-g", "typescript@latest"]
        ))

        let record = try #require(store.records.first)

        #expect(record.commandText == record.argv.joined(separator: " "))
        #expect(record.displayCommand == "npm " + record.commandText)
        #expect(record.controls == [.copyCommand])

        let source = try Self.persistenceSource("HistoryPresentation.swift")
        for parser in ["components(separatedBy:", "split(separator:", "MutationCommand("] {
            #expect(source.contains(parser) == false, "presentation parses a command back: \(parser)")
        }
    }

    // MARK: - Search

    @Test("npm entries are searchable by source, verb, name and argv")
    func npmEntriesAreSearchable() throws {
        let container = try PersistenceContainer.inMemory()
        let store = HistoryStore(container: container)
        let recorder = SwiftDataHistoryRecorder(store: store)
        recorder.record(Self.draft(
            packageID: Self.typescript,
            verb: "npmUpgrade",
            argv: ["install", "-g", "typescript@latest"]
        ))
        recorder.record(Self.draft(
            packageID: Self.wget,
            verb: "upgrade",
            argv: ["upgrade", "--formula", "wget"]
        ))

        #expect(store.records.count == 2)

        store.search = "NPM"
        #expect(store.records.map(\.verb) == ["npmUpgrade"])

        store.search = "typescript"
        #expect(store.records.map(\.name) == ["typescript"])

        store.search = "upgrade"
        #expect(Set(store.records.map(\.verb)) == ["npmUpgrade", "upgrade"])

        store.search = "uninstall"
        #expect(store.records.isEmpty)

        store.search = "-g"
        #expect(store.records.map(\.verb) == ["npmUpgrade"])
    }

    // MARK: - A build that does not know the kind

    /// `installation-history`: "A build without the npm kind MUST decode such
    /// rows as absent rather than fail or misattribute them."
    ///
    /// Exercised with a kind string **this** build does not know, which is the
    /// only honest way to stand in for a decoder that predates `npm`: the rule
    /// under test is `PackageIdentity`'s, and it cannot tell the two cases
    /// apart.
    @Test("A row whose kind this build does not know decodes as absent")
    func anUnknownKindDecodesAsAbsent() throws {
        let container = try PersistenceContainer.inMemory()
        let context = container.mainContext
        context.insert(HistoryEntry(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_700_000_000),
            kindRaw: "pnpm",
            name: "typescript",
            verb: "pnpmUpgrade",
            versionFrom: "",
            versionTo: "",
            outcomeRaw: "succeeded",
            exitStatus: 0,
            argv: ["add", "-g", "typescript"],
            commandText: "add -g typescript"
        ))
        try context.save()
        let store = HistoryStore(container: container)

        let record = try #require(store.records.first)

        #expect(record.packageID == nil, "an unknown kind was misattributed")
        #expect(record.name == "typescript")
        // Nothing was inferred: with no identity there is no source to claim,
        // and the row falls back to the vocabulary every unattributed row uses.
        #expect(record.source == .homebrew)
        #expect(record.outcomeLabel == "Done")
    }

    // MARK: - Source scanning

    private static func persistenceSource(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Persistence/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
