import BrewClient
import Catalog
import Foundation
import SwiftData
import Testing

@testable import BrewProcess
@testable import Persistence

/// The `HistoryRecording` conformance: one draft in, one durable row out
/// (installation-history IH1, IH3, IH4; design D1, D7).
///
/// Two threat rows are answered here. **Untrusted payload as classification
/// input**: `outcomeRaw` is derived from the pure classifier, never from the
/// bytes brew wrote. **Persisted argv is display-only**: nothing anywhere
/// reconstructs a runnable command from a stored row.
@MainActor
@Suite("History recorder")
struct HistoryRecorderTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let iterm = PackageID(kind: .cask, name: "iterm2")

    private static func draft(
        id: UUID = UUID(),
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        packageID: PackageID? = wget,
        verb: String = "upgrade",
        versions: VersionTransition? = VersionTransition(from: "1.2.2", to: "1.2.3"),
        outcome: MutationOutcome = .succeeded,
        argv: [String] = ["upgrade", "--formula", "wget"]
    ) -> HistoryDraft {
        HistoryDraft(
            id: id,
            date: date,
            packageID: packageID,
            verb: verb,
            versions: versions,
            outcome: outcome,
            argv: argv
        )
    }

    private static func recorder(
        _ container: ModelContainer
    ) -> (SwiftDataHistoryRecorder, HistoryStore) {
        let store = HistoryStore(container: container)
        return (SwiftDataHistoryRecorder(store: store), store)
    }

    // MARK: - IH1 sc1 — every field survives the mapping

    @Test("A draft maps to a row with every field preserved")
    func aDraftMapsToACompleteRow() throws {
        let container = try PersistenceContainer.inMemory()
        let (recorder, store) = Self.recorder(container)

        let id = UUID()
        recorder.record(Self.draft(id: id, outcome: .failed(status: 2)))

        #expect(store.records.count == 1)
        let record = try #require(store.records.first)
        #expect(record.id == id)
        #expect(record.date == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(record.packageID == Self.wget)
        #expect(record.name == "wget")
        #expect(record.verb == "upgrade")
        #expect(record.versionFrom == "1.2.2")
        #expect(record.versionTo == "1.2.3")
        #expect(record.outcomeRaw == "failed")
        #expect(record.exitStatus == 2)
        #expect(record.argv == ["upgrade", "--formula", "wget"])
        #expect(record.commandText == "upgrade --formula wget")
        #expect(store.lastError == nil)
    }

    /// A grouped `upgradeAll` names no package, and "no package" is the empty
    /// string rather than an `Optional` — the rule every model in V1 shares.
    @Test("A draft naming no package persists as the empty identity, not as null")
    func aGroupedDraftPersistsAsAnEmptyIdentity() throws {
        let container = try PersistenceContainer.inMemory()
        let (recorder, store) = Self.recorder(container)

        recorder.record(
            Self.draft(packageID: nil, verb: "upgradeAll", versions: nil, argv: ["upgrade"])
        )

        let record = try #require(store.records.first)
        #expect(record.name.isEmpty)
        #expect(record.packageID == nil)
        #expect(record.verb == "upgradeAll")
        #expect(record.versionFrom.isEmpty)
        #expect(record.versionTo.isEmpty)
        #expect(record.versions == nil)
        #expect(record.commandText == "upgrade")
    }

    // MARK: - IH1 sc4 — the rows survive a close and reopen

    @Test("Three recorded entries survive a close and reopen against the same location")
    func recordedEntriesSurviveAReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("Metadata.store", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        let ids = [UUID(), UUID(), UUID()]
        do {
            let (recorder, _) = Self.recorder(try PersistenceContainer.onDisk(at: url))
            recorder.record(Self.draft(id: ids[0], packageID: Self.wget, verb: "install"))
            recorder.record(Self.draft(
                id: ids[1],
                date: Date(timeIntervalSince1970: 1_700_000_100),
                packageID: Self.iterm,
                verb: "uninstall",
                versions: nil,
                argv: ["uninstall", "--cask", "iterm2"]
            ))
            recorder.record(Self.draft(
                id: ids[2],
                date: Date(timeIntervalSince1970: 1_700_000_200),
                outcome: .cancelled
            ))
        }

        let reopened = HistoryStore(container: try PersistenceContainer.onDisk(at: url))

        #expect(reopened.records.count == 3)
        #expect(Set(reopened.records.map(\.id)) == Set(ids))
        // Newest first, with their original fields.
        #expect(reopened.records.map(\.verb) == ["upgrade", "uninstall", "install"])
        #expect(reopened.records.first?.outcomeRaw == "cancelled")
        let cask = try #require(reopened.records.first(where: { $0.name == "iterm2" }))
        #expect(cask.packageID == Self.iterm)
        #expect(cask.commandText == "uninstall --cask iterm2")
    }

    // MARK: - 7.2 — a replayed write cannot double-log

    @Test("Recording the same draft id twice leaves exactly one row")
    func aReplayedWriteCannotDoubleLog() throws {
        let container = try PersistenceContainer.inMemory()
        let (recorder, store) = Self.recorder(container)
        let id = UUID()

        recorder.record(Self.draft(id: id, outcome: .succeeded))
        recorder.record(Self.draft(id: id, outcome: .succeeded))

        #expect(store.records.count == 1, "a replayed terminal double-logged")

        // And two genuinely different operations are two rows, so the
        // deduplication is keyed on identity rather than on content.
        recorder.record(Self.draft(id: UUID(), outcome: .succeeded))
        #expect(store.records.count == 2)
    }

    // MARK: - 7.3 — threat: untrusted payload as classification input

    /// The classifier decides on the structural facts before it reads a byte of
    /// output: exit 0 is success, whatever the package printed. `outcomeRaw` is
    /// derived from that classification, never from the raw log — so a package
    /// echoing `Password:` cannot rewrite its own history row.
    @Test("A successful run whose output says Password: persists as succeeded")
    func hostileOutputCannotRewriteThePersistedOutcome() throws {
        let container = try PersistenceContainer.inMemory()
        let (recorder, store) = Self.recorder(container)

        let hostile = [
            LogLine(stream: .stderr, text: "sudo: a password is required", sequence: 0),
            LogLine(stream: .stderr, text: "Password:", sequence: 1)
        ]
        let outcome = MutationOutcome.classify(
            exit: BrewExit(status: 0, reason: .exited),
            fault: nil,
            log: hostile
        )
        #expect(outcome == .succeeded, "M2-2's own classification changed")

        recorder.record(Self.draft(outcome: outcome))

        let record = try #require(store.records.first)
        #expect(record.outcomeRaw == "succeeded")
        #expect(record.outcomeRaw != "needsPrivileges")
        // And none of the payload was persisted at all.
        #expect(record.commandText.contains("Password") == false)
        #expect(record.argv.contains { $0.contains("password") } == false)
    }

    /// The same run, exiting non-zero, is where the signature is allowed to
    /// speak — and it still persists a classified outcome rather than the text.
    @Test("The same output on a non-zero exit persists the classified typed failure")
    func aClassifiedFailurePersistsItsOwnName() throws {
        let container = try PersistenceContainer.inMemory()
        let (recorder, store) = Self.recorder(container)

        let outcome = MutationOutcome.classify(
            exit: BrewExit(status: 1, reason: .exited),
            fault: nil,
            log: [LogLine(stream: .stderr, text: "Password:", sequence: 0)]
        )
        #expect(outcome == .needsPrivileges)

        recorder.record(Self.draft(outcome: outcome))

        let record = try #require(store.records.first)
        #expect(record.outcomeRaw == "needsPrivileges")
        #expect(record.exitStatus == nil, "an unprobed status was invented")
    }

    // MARK: - 7.4 — threat: persisted argv is display-only

    /// One-way, exactly like `displayCommand`. Enumerated on the source rather
    /// than argued, so an overload added later fails this instead of shipping.
    @Test("No API turns a stored row back into a runnable command")
    func aStoredRowCannotBecomeACommand() throws {
        for file in ["SwiftDataHistoryRecorder.swift", "HistoryStore.swift", "SchemaV1.swift"] {
            let source = try Self.declarations(of: file)
            #expect(
                source.contains("-> MutationCommand") == false,
                "\(file) reconstructs a command from a stored row"
            )
            #expect(source.contains("MutationCommand(") == false)
            #expect(source.contains("brewCommand") == false)
            #expect(source.contains("PackageTarget(") == false)
        }
    }

    @Test("The only per-entry control is copy, and it copies commandText exactly")
    func theOnlyControlIsCopy() throws {
        let container = try PersistenceContainer.inMemory()
        let (recorder, store) = Self.recorder(container)
        recorder.record(Self.draft(argv: ["uninstall", "--cask", "iterm2"]))

        let record = try #require(store.records.first)
        #expect(record.controls == [.copyCommand])
        #expect(record.controls.contains(.delete) == false)
        #expect(record.controls.contains(.remove) == false)
        // Character for character, and identical to the joined argv.
        #expect(record.commandText == "uninstall --cask iterm2")
        #expect(record.commandText == record.argv.joined(separator: " "))
    }

    // MARK: - IH4 sc3 — durability is independent of runner retention

    /// The execution layer bounds its own in-memory records by handle ownership
    /// (design D6 R3). This store is the durable one, and the two must not be
    /// the same thing: retiring the record must leave every field of the entry
    /// exactly where it was.
    @Test("An entry whose execution record has been retired is still complete")
    func retiringAnExecutionRecordLeavesTheEntryIntact() async throws {
        let container = try PersistenceContainer.inMemory()
        let (recorder, store) = Self.recorder(container)

        let launcher = SpyProcessLauncher()
        let runner = BrewRunner(
            installation: BrewInstallation(
                executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
                prefix: .appleSilicon,
                version: BrewVersion(major: 6, minor: 0, patch: 14)
            ),
            launcher: launcher,
            retainedTerminalRecords: 0
        )

        var operation: BrewOperation? = try await runner.start(
            .mutate(["uninstall", "--formula", "wget"])
        )
        let operationID = try #require(operation?.id)
        for await _ in operation!.lines {}
        let exit = await operation!.exit()
        #expect(exit.isSuccess)

        recorder.record(
            Self.draft(verb: "uninstall", argv: ["uninstall", "--formula", "wget"])
        )
        #expect(store.records.count == 1)

        // Drop the last handle: R3 now permits the runner to retire the record.
        // `deinit` hands the id back from a task, so yield until it has run
        // rather than sleeping on a wall clock.
        operation = nil
        for _ in 0..<500 where await runner.activeOperationCount > 0 {
            await Task.yield()
        }

        #expect(await runner.activeOperationCount == 0, "the execution record was never retired")
        #expect(await runner.holdsExecutionResources(operationID) == false)

        // The durable entry is untouched, with all of its fields.
        store.reload()
        let record = try #require(store.records.first)
        #expect(store.records.count == 1)
        #expect(record.verb == "uninstall")
        #expect(record.name == "wget")
        #expect(record.argv == ["uninstall", "--formula", "wget"])
        #expect(record.commandText == "uninstall --formula wget")
        #expect(record.outcomeRaw == "succeeded")
    }

    // MARK: -

    private static func declarations(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Persistence/\(file)"),
            encoding: .utf8
        )
        return source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
