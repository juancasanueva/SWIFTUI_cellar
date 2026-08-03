import BrewClient
import BrewProcess
import Catalog
import Foundation
import SwiftData
import Testing

@testable import Persistence

/// Favorites, notes and snoozes as the app reads and writes them
/// (local-package-metadata LPM2, LPM3, LPM4, LPM6).
///
/// Every test runs against a real `ModelContainer`; none of them spawns
/// anything. The store is `@MainActor @Observable` over the container's
/// `mainContext`, on the shipped `InstalledStore` exemplar — no `@Query`, no
/// `.modelContainer(…)` modifier, no `@ModelActor` (design D3).
@MainActor
@Suite("Metadata store")
struct MetadataStoreTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let git = PackageID(kind: .formula, name: "git")
    private static let iterm = PackageID(kind: .cask, name: "iterm2")

    private static func store() throws -> MetadataStore {
        MetadataStore(container: try PersistenceContainer.inMemory())
    }

    // MARK: - LPM2 sc1, sc3 — the favorite flag

    @Test("The favorite flag round-trips and toggling it twice leaves one state")
    func theFavoriteFlagRoundTrips() throws {
        let store = try Self.store()

        #expect(store.isFavorite(Self.wget) == false)
        store.setFavorite(true, for: Self.wget)
        #expect(store.isFavorite(Self.wget))
        store.setFavorite(false, for: Self.wget)
        #expect(store.isFavorite(Self.wget) == false)

        // Idempotent: setting the same value twice stores one state, not two.
        store.setFavorite(true, for: Self.wget)
        store.setFavorite(true, for: Self.wget)
        #expect(store.isFavorite(Self.wget))
        #expect(store.favoriteIDs == [Self.wget])
    }

    @Test("A package with no stored metadata reports not favorite and throws nothing")
    func anUnknownPackageIsNotFavorite() throws {
        let store = try Self.store()
        store.setFavorite(true, for: Self.wget)

        #expect(store.isFavorite(Self.git) == false)
        #expect(store.note(for: Self.git) == nil)
        #expect(store.snoozedVersion(for: Self.git) == nil)
        #expect(store.metadata(for: Self.git) == PackageMetadata())
        #expect(store.lastError == nil)
    }

    // MARK: - LPM2 sc2 — toggling favorite spawns nothing

    @Test("Marking and unmarking favorite records no brew invocation and submits nothing")
    func togglingFavoriteSpawnsNothing() async throws {
        let launcher = SpyProcessLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: TestInstallation.appleSilicon)
        let store = try Self.store()

        store.setFavorite(true, for: Self.wget)
        store.setFavorite(false, for: Self.wget)
        store.setNote("a note", for: Self.iterm)
        store.snooze(Self.git, offering: "2.44.0")
        store.unsnooze(Self.git)
        for _ in 0..<100 { await Task.yield() }

        #expect(launcher.launchCount == 0, "a metadata write reached the process seam")
        #expect(center.items.isEmpty, "a metadata write submitted an operation")
        #expect(center.summary.isBusy == false)
    }

    // MARK: - LPM3 sc1–2 — a note is plain text, stored verbatim

    @Test("A multi-line note round-trips byte-identically with no markup interpreted")
    func aNoteRoundTripsVerbatim() throws {
        let store = try Self.store()
        let text = "line one\n\n  # not a heading  \nline two"

        store.setNote(text, for: Self.wget)

        let readBack = try #require(store.note(for: Self.wget))
        #expect(readBack == text)
        #expect(Array(readBack.utf8) == Array(text.utf8), "the note was not byte-identical")
        #expect(readBack.contains("  # not a heading  "), "markup was interpreted or stripped")
        #expect(readBack.contains("\n\n"), "internal blank lines were collapsed")
    }

    /// Threat: **user free text reaching a command vector.** Notes are the first
    /// user-authored persisted strings in the app. They are stored and returned
    /// verbatim and can reach **no** argv, because argv comes only from
    /// `MutationCommand`.
    @Test("A note containing shell metacharacters changes no ProcessSpec")
    func aHostileNoteReachesNoArgv() async throws {
        let launcher = SpyProcessLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: TestInstallation.appleSilicon)
        let store = try Self.store()
        let hostile = "; rm -rf / --force $(whoami) `id` && echo pwned"

        store.setNote(hostile, for: Self.wget)
        // A real mutation runs beside it, so "no argv" is asserted against argv
        // that actually exists rather than against an empty list.
        let target = try #require(PackageTarget(Self.wget))
        center.submit(.install(target))
        for _ in 0..<200 { await Task.yield() }

        #expect(store.note(for: Self.wget) == hostile)
        #expect(launcher.launchCount == 1)
        #expect(launcher.allArguments == ["install", "--formula", "wget"])
        // Fragments distinctive enough that a false positive is a real one:
        // "rm" alone would match "--formula".
        for fragment in ["rm -rf", "-rf", "--force", "$(whoami)", "`id`", "pwned", "&&"] {
            #expect(
                launcher.allArguments.contains { $0.contains(fragment) } == false,
                "the fragment \(fragment) reached argv"
            )
        }
    }

    @Test("No length cap is imposed on a note")
    func aNoteHasNoLengthCap() throws {
        let store = try Self.store()
        let long = String(repeating: "cellar ", count: 5_000)

        store.setNote(long, for: Self.wget)

        #expect(store.note(for: Self.wget)?.count == long.count)
        #expect(store.note(for: Self.wget) == long)
    }

    @Test("Setting a note to the empty string reports no note")
    func anEmptyNoteIsNoNote() throws {
        let store = try Self.store()
        store.setNote("some text", for: Self.wget)
        #expect(store.note(for: Self.wget) == "some text")

        store.setNote("", for: Self.wget)

        #expect(store.note(for: Self.wget) == nil)
        #expect(store.metadata(for: Self.wget).note.isEmpty)
    }

    // MARK: - LPM4 sc1–3 — a snooze is scoped to a version

    @Test("Snoozing records the exact offered version and nothing else")
    func snoozingRecordsTheOfferedVersion() throws {
        let container = try PersistenceContainer.inMemory()
        let store = MetadataStore(container: container)

        store.snooze(Self.wget, offering: "1.2.3")

        #expect(store.snoozedVersion(for: Self.wget) == "1.2.3")
        let rows = try container.mainContext.fetch(FetchDescriptor<Snooze>())
        let row = try #require(rows.first)
        #expect(row.snoozedVersion == "1.2.3")
        #expect(row.name == "wget")
        #expect(row.kindRaw == "formula")
    }

    /// The stored fields carry no duration, no expiry and no timestamp that
    /// governs when the snooze ends. `createdAt` is provenance, and the rule
    /// that reads a snooze never looks at it.
    @Test("A stored snooze carries no duration, expiry or governing timestamp")
    func aSnoozeCarriesNoTimeComponent() throws {
        let source = SchemaTests.code(in: try Self.source(of: "SchemaV1.swift"))
        let snoozeBlock = try #require(
            source.components(separatedBy: "public final class Snooze {").last?
                .components(separatedBy: "public var packageID").first
        )

        for forbidden in ["duration", "Duration", "expiry", "expires", "until", "deadline"] {
            #expect(
                snoozeBlock.contains(forbidden) == false,
                "the snooze model stores \(forbidden)"
            )
        }
        // Exactly one stored Date, and it is provenance rather than policy.
        let storedDates = snoozeBlock
            .split(separator: "\n")
            .filter { $0.contains("public var") && $0.contains(": Date") }
        #expect(storedDates.count == 1)
        #expect(storedDates.first?.contains("createdAt") == true)

        // And the reader never consults it.
        let store = SchemaTests.code(in: try Self.source(of: "MetadataStore.swift"))
        #expect(store.contains("createdAt <") == false)
        #expect(store.contains("Date.now >") == false)
    }

    @Test("Re-snoozing replaces the stored version rather than accumulating a second snooze")
    func reSnoozingReplaces() throws {
        let container = try PersistenceContainer.inMemory()
        let store = MetadataStore(container: container)

        store.snooze(Self.wget, offering: "1.2.3")
        store.snooze(Self.wget, offering: "1.3.0")

        let rows = try container.mainContext.fetch(FetchDescriptor<Snooze>())
        #expect(rows.count == 1, "re-snoozing accumulated a second snooze")
        #expect(rows.first?.snoozedVersion == "1.3.0")
        #expect(store.snoozedVersion(for: Self.wget) == "1.3.0")
    }

    @Test("Unsnoozing removes the snooze entirely and leaves the rest of the metadata")
    func unsnoozingRemovesTheSnooze() throws {
        let container = try PersistenceContainer.inMemory()
        let store = MetadataStore(container: container)
        store.setFavorite(true, for: Self.wget)
        store.setNote("keep me", for: Self.wget)
        store.snooze(Self.wget, offering: "1.2.3")

        store.unsnooze(Self.wget)

        #expect(try container.mainContext.fetch(FetchDescriptor<Snooze>()).isEmpty)
        #expect(store.snoozedVersion(for: Self.wget) == nil)
        #expect(store.isFavorite(Self.wget), "unsnoozing dropped the favorite")
        #expect(store.note(for: Self.wget) == "keep me", "unsnoozing dropped the note")
    }

    // MARK: - LPM6 sc2 — threat: filesystem write surface

    /// A corrupt or unwritable store costs local metadata and nothing else. A
    /// `try!` at launch would turn a recoverable disk problem into a boot loop
    /// (design D4).
    @Test("A container that fails to open degrades to an empty, no-op, explained store")
    func anUnopenableContainerDegrades() async throws {
        // A path whose parent is a *file*, so the directory can never be made.
        let blocker = FileManager.default.temporaryDirectory
            .appending(path: "cellar-blocker-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: blocker.path(percentEncoded: false), contents: Data())
        defer { try? FileManager.default.removeItem(at: blocker) }

        let store = MetadataStore(at: blocker.appending(path: "Metadata.store"))

        let reason = try #require(store.availability.reason)
        #expect(reason.isEmpty == false, "the failure was not explained")
        #expect(store.availability.isAvailable == false)
        #expect(store.snapshot.isEmpty)

        // Writes are no-ops that throw nothing, and reads stay answerable.
        store.setFavorite(true, for: Self.wget)
        store.setNote("anything", for: Self.wget)
        store.snooze(Self.wget, offering: "1.2.3")
        store.unsnooze(Self.wget)

        #expect(store.isFavorite(Self.wget) == false)
        #expect(store.note(for: Self.wget) == nil)
        #expect(store.snoozedVersion(for: Self.wget) == nil)
        #expect(store.snapshot.isEmpty)
        #expect(store.favoriteIDs.isEmpty)
    }

    @Test("An available store reports no reason and no error")
    func anAvailableStoreReportsNoReason() throws {
        let store = try Self.store()

        #expect(store.availability == .available)
        #expect(store.availability.reason == nil)
        #expect(store.lastError == nil)
    }

    // MARK: - The published snapshot

    @Test("The snapshot is republished from the store after every save")
    func theSnapshotIsRepublishedAfterEachSave() throws {
        let store = try Self.store()

        #expect(store.snapshot.isEmpty)
        store.setFavorite(true, for: Self.wget)
        #expect(store.snapshot[Self.wget] == PackageMetadata(isFavorite: true))

        store.setNote("mirror", for: Self.wget)
        store.snooze(Self.wget, offering: "1.2.3")
        #expect(
            store.snapshot[Self.wget]
                == PackageMetadata(isFavorite: true, note: "mirror", snoozedVersion: "1.2.3")
        )

        store.setFavorite(true, for: Self.iterm)
        #expect(Set(store.snapshot.keys) == [Self.wget, Self.iterm])
        #expect(store.snapshot[Self.iterm] == PackageMetadata(isFavorite: true))
    }

    // MARK: -

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Persistence/\(file)"),
            encoding: .utf8
        )
    }
}

/// Installations the suites point at. Nothing is ever spawned at these paths.
enum TestInstallation {
    static let appleSilicon = BrewInstallation(
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
        prefix: .appleSilicon,
        version: BrewVersion(major: 6, minor: 0, patch: 14)
    )
}
