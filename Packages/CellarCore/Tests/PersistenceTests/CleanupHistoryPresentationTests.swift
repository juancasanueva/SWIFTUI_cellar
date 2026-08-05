import BrewClient
import Catalog
import Foundation
import SwiftData
import Testing

@testable import Persistence

@MainActor
@Suite("Cleanup history presentation")
struct CleanupHistoryPresentationTests {
    private struct ExpectedCleanup {
        let verb: String
        let label: String
        let packageID: PackageID?
        let argv: [String]
    }

    private static let package = PackageID(kind: .formula, name: "ripgrep")

    private static let cleanups = [
        ExpectedCleanup(
            verb: "cleanupGlobal",
            label: "Cleanup",
            packageID: nil,
            argv: ["cleanup"]
        ),
        ExpectedCleanup(
            verb: "cleanupPackage",
            label: "Package cleanup",
            packageID: package,
            argv: ["cleanup", "ripgrep"]
        ),
        ExpectedCleanup(
            verb: "cleanupFull",
            label: "Full cleanup",
            packageID: nil,
            argv: ["cleanup", "--prune=all"]
        ),
        ExpectedCleanup(
            verb: "cleanupAutoremove",
            label: "Autoremove",
            packageID: nil,
            argv: ["autoremove"]
        )
    ]

    @Test("Cleanup drafts retain exact verbs, identities, labels, and operation scopes")
    func cleanupDraftsRetainTheirPresentationContract() throws {
        let container = try PersistenceContainer.inMemory()
        let store = HistoryStore(container: container)
        Self.recordCleanups(in: store)

        #expect(store.records.count == 4)
        let records = Dictionary(uniqueKeysWithValues: store.records.map { ($0.verb, $0) })

        for expected in Self.cleanups {
            let record = try #require(records[expected.verb])
            #expect(record.actionLabel == expected.label)
            #expect(record.packageID == expected.packageID)
            #expect(record.argv == expected.argv)
            #expect(record.commandText == expected.argv.joined(separator: " "))
            #expect(record.versions == nil)

            if let packageID = expected.packageID {
                #expect(record.subject == .package(packageID.name))
            } else {
                #expect(record.name.isEmpty)
                #expect(record.subject == .operationScope(expected.label))
                #expect(record.subject.label == expected.label)
            }
        }
    }

    @Test("Cleanup search matches labels, verbs, scope terms, package names, and argv")
    func cleanupSearchMatchesEveryPresentationTerm() throws {
        let container = try PersistenceContainer.inMemory()
        let store = HistoryStore(container: container)
        Self.recordCleanups(in: store)

        let cases: [(query: String, verbs: Set<String>)] = [
            ("Package cleanup", ["cleanupPackage"]),
            ("FULL CLEANUP", ["cleanupFull"]),
            ("Autoremove", ["cleanupAutoremove"]),
            ("cleanupGlobal", ["cleanupGlobal"]),
            ("cleanup", Set(Self.cleanups.map(\.verb))),
            ("FULL", ["cleanupFull"]),
            ("ripGREP", ["cleanupPackage"]),
            ("--prune=all", ["cleanupFull"])
        ]

        for searchCase in cases {
            store.search = searchCase.query
            #expect(Set(store.records.map(\.verb)) == searchCase.verbs)
        }
    }

    @Test("Schema V1 round trips cleanup rows and unknown presentation remains readable")
    func schemaV1RoundTripAndFallbackRemainReadable() throws {
        try withTemporaryStore { url in
            do {
                let container = try PersistenceContainer.onDisk(at: url)
                let store = HistoryStore(container: container)
                Self.recordCleanups(in: store)
                let recorder = SwiftDataHistoryRecorder(store: store)
                recorder.record(
                    HistoryDraft(
                        id: UUID(),
                        date: Date(timeIntervalSince1970: 2_000),
                        packageID: nil,
                        verb: "cleanupFromOlderBuild",
                        versions: nil,
                        outcome: .succeeded,
                        argv: ["cleanup", "--future-option"]
                    )
                )
                recorder.record(
                    HistoryDraft(
                        id: UUID(),
                        date: Date(timeIntervalSince1970: 2_001),
                        packageID: PackageID(kind: .cask, name: "legacy-tool"),
                        verb: "cleanupLegacyPackage",
                        versions: nil,
                        outcome: .succeeded,
                        argv: ["cleanup", "legacy-tool"]
                    )
                )
            }

            let container = try PersistenceContainer.onDisk(at: url)
            let store = HistoryStore(container: container)
            #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
            #expect(store.records.count == 6)

            let fallback = try #require(
                store.records.first { $0.verb == "cleanupFromOlderBuild" }
            )
            #expect(fallback.actionLabel == "cleanupFromOlderBuild")
            #expect(fallback.subject == .noPackage)
            #expect(fallback.commandText == "cleanup --future-option")
            #expect(fallback.argv == ["cleanup", "--future-option"])
            #expect(fallback.controls == [.copyCommand])

            let packageFallback = try #require(
                store.records.first { $0.verb == "cleanupLegacyPackage" }
            )
            #expect(packageFallback.actionLabel == "cleanupLegacyPackage")
            #expect(packageFallback.subject == .package("legacy-tool"))
            #expect(packageFallback.commandText == "cleanup legacy-tool")
            #expect(packageFallback.controls == [.copyCommand])

            let rows = try container.mainContext.fetch(FetchDescriptor<HistoryEntry>())
            let global = try #require(rows.first { $0.verb == "cleanupGlobal" })
            #expect(global.kindRaw.isEmpty)
            #expect(global.name.isEmpty)
            #expect(global.versionFrom.isEmpty)
            #expect(global.versionTo.isEmpty)

            let package = try #require(rows.first { $0.verb == "cleanupPackage" })
            #expect(package.kindRaw == PackageKind.formula.rawValue)
            #expect(package.name == "ripgrep")
            #expect(package.versionFrom.isEmpty)
            #expect(package.versionTo.isEmpty)
        }
    }

    private static func recordCleanups(in store: HistoryStore) {
        let recorder = SwiftDataHistoryRecorder(store: store)
        for (offset, cleanup) in cleanups.enumerated() {
            recorder.record(
                HistoryDraft(
                    id: UUID(),
                    date: Date(timeIntervalSince1970: TimeInterval(1_000 + offset)),
                    packageID: cleanup.packageID,
                    verb: cleanup.verb,
                    versions: nil,
                    outcome: .succeeded,
                    argv: cleanup.argv
                )
            )
        }
    }
}
