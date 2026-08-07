//
//  BulkSnoozeTests.swift
//  cellarTests
//

import BrewClient
import BrewProcess
import Catalog
import Foundation
import Persistence
import Testing

@testable import cellar

/// Snoozing several packages in one action (`local-package-metadata` LPM4,
/// `installed-inventory` II13, design HD11).
///
/// The whole rule is that a bulk snooze is **N individual snoozes**, not one
/// batch. N packages are outdated toward N *different* versions, so a batch that
/// shared one version would silently mis-scope N−1 of them — and, worse, suppress
/// badges for versions those packages were never outdated toward.
///
/// It also travels its own path. Snooze produces no `MutationCommand`, so a fifth
/// `BulkSelection.Action` case would need a `case snooze: []` arm in
/// `commands(for:over:)` — a silent no-op the type system cannot catch — and
/// `MetadataStore` lives in `Persistence` while `BulkSelection` lives in
/// `BrewClient`, which must not link SwiftData.
@Suite("Bulk snooze", .timeLimit(.minutes(1)))
struct BulkSnoozeTests {

    // MARK: - 11.1 — one snooze per package, each naming its own version

    @Test("Snoozing three packages records three versions, each the package's own")
    func snoozingThreePackagesRecordsThreeOwnVersions() throws {
        let packages = [
            HealthFixtures.package("git", installed: "1.0.0", offering: "1.2.3", outdated: true),
            HealthFixtures.package("hugo", installed: "2025-01-01", offering: "2026-08-01", outdated: true),
            HealthFixtures.package("jq", installed: "3.0.0", offering: "4.0.0_1", outdated: true)
        ]
        let selection = BulkSnoozeSelection(
            selection: packages.map(\.id),
            entries: HealthFixtures.entries(packages),
            metadata: nil
        )
        #expect(selection.count == 3)

        let sink = RecordingSnoozeSink()
        selection.apply(sink.snooze)

        #expect(sink.writes.map(\.version) == ["1.2.3", "2026-08-01", "4.0.0_1"])
        #expect(sink.writes.map(\.id) == packages.map(\.id))
        // No shared version, and no version reused across two packages.
        #expect(Set(sink.writes.map(\.version)).count == 3)
    }

    /// Indistinguishable from having snoozed each one individually, in any order.
    ///
    /// Proven against a real `MetadataStore` on an in-memory container rather than
    /// against the recording sink, because the claim is about **stored** rows: a
    /// ledger cannot show that re-snoozing replaced rather than accumulated, and
    /// that is exactly the difference a batch identity would introduce.
    @MainActor
    @Test("A bulk snooze is indistinguishable from individual snoozes in any order")
    func aBulkSnoozeIsIndistinguishableFromIndividualSnoozes() throws {
        let packages = [
            HealthFixtures.package("git", offering: "1.2.3", outdated: true),
            HealthFixtures.package("hugo", offering: "2026-08-01", outdated: true),
            HealthFixtures.package("jq", offering: "4.0.0_1", outdated: true)
        ]

        let bulkStore = MetadataStore(container: try PersistenceContainer.inMemory())
        BulkSnoozeSelection(
            selection: packages.map(\.id),
            entries: HealthFixtures.entries(packages),
            metadata: nil
        ).apply { bulkStore.snooze($0, offering: $1) }

        // The same three, one at a time, in a different order.
        let individualStore = MetadataStore(container: try PersistenceContainer.inMemory())
        for package in packages.reversed() {
            individualStore.snooze(package.id, offering: package.catalogVersion)
        }

        for package in packages {
            let bulk = bulkStore.snoozedVersion(for: package.id)
            #expect(bulk == package.catalogVersion)
            #expect(bulk == individualStore.snoozedVersion(for: package.id))
        }
    }

    // MARK: - 11.2 — nothing to snooze toward records nothing

    @Test("A package with no offered version records nothing at all")
    func aPackageWithNoOfferedVersionRecordsNothing() throws {
        let outdated = HealthFixtures.package("git", offering: "1.2.3", outdated: true)
        let nothingOffered = HealthFixtures.package("wget", offering: "", outdated: true)
        let selection = BulkSnoozeSelection(
            selection: [outdated.id, nothingOffered.id],
            entries: HealthFixtures.entries([outdated, nothingOffered]),
            metadata: nil
        )

        let sink = RecordingSnoozeSink()
        selection.apply(sink.snooze)

        #expect(sink.writes.count == 1)
        #expect(sink.writes.first?.id == outdated.id)
        #expect(sink.writes.first?.version == "1.2.3")
        // Announced and recorded are the same set, so nothing was counted that
        // could not be written (II14).
        #expect(selection.count == sink.writes.count)
        #expect(selection.snoozable.contains(nothingOffered.id) == false)
    }

    /// A snooze already at the offered version is not offered again, and one at a
    /// *different* version is.
    ///
    /// Equality is the whole rule. There is no ordering here, no comparator, and
    /// no notion of "newer": `1.2.3_1` is simply not `1.2.3`.
    @Test("Eligibility is outdated and not already snoozed at the offered version")
    func eligibilityIsOutdatedAndNotAlreadySnoozed() throws {
        let current = HealthFixtures.package("git", offering: "1.2.3", outdated: true)
        let stale = HealthFixtures.package("hugo", offering: "2026-08-01", outdated: true)
        let upToDate = HealthFixtures.package("jq", offering: "1.0.0", outdated: false)

        let metadata: MetadataLookup = { id in
            switch id.name {
            case "git": PackageMetadata(isFavorite: false, note: "", snoozedVersion: "1.2.3")
            case "hugo": PackageMetadata(isFavorite: false, note: "", snoozedVersion: "2026-07-01")
            default: nil
            }
        }
        let selection = BulkSnoozeSelection(
            selection: [current.id, stale.id, upToDate.id],
            entries: HealthFixtures.entries([current, stale, upToDate]),
            metadata: metadata
        )

        #expect(selection.snoozable == [stale.id], "eligibility was \(selection.snoozable)")
        #expect(selection.isAvailable)

        // …and an empty eligible set is unavailable rather than an inert control.
        let nothing = BulkSnoozeSelection(
            selection: [current.id, upToDate.id],
            entries: HealthFixtures.entries([current, upToDate]),
            metadata: metadata
        )
        #expect(nothing.count == 0)
        #expect(nothing.isAvailable == false)
    }

    @Test("The action compares, orders and ranks nothing")
    func theActionComparesOrdersAndRanksNothing() throws {
        let source = try BulkActionBarSources.barSource()
        for comparator in [
            "compare(", ".numeric", "NumericSearch", "versionCompare", "isNewer",
            "isOlder", "precedes", "sorted", "SemVer", "Comparator"
        ] {
            #expect(source.contains(comparator) == false, "the bulk snooze surface reaches for \(comparator)")
        }
        // The anchor: the file really was read, and it really is the one that
        // records snoozes.
        #expect(source.contains("BulkSnoozeSelection"))
        #expect(source.contains("isSnoozed"))
    }

    // MARK: - 11.3 — it never enters the mutation spine

    @Test("Bulk snooze is not a bulk mutation verb")
    func bulkSnoozeIsNotAbulkMutationVerb() {
        #expect(BulkSelection.Action.allCases == [.upgrade, .uninstall, .pin, .unpin])
        #expect(
            BulkSelection.Action.allCases.contains { $0.title.lowercased().contains("snooze") } == false
        )
    }

    /// Nothing spawned, nothing submitted, nothing written to history.
    @MainActor
    @Test("Submitting a bulk snooze spawns nothing and submits nothing")
    func submittingAbulkSnoozeSpawnsNothingAndSubmitsNothing() throws {
        let launcher = CompositionLauncher()
        let operations = OperationCenter(launcherFactory: { _ in launcher })
        operations.attach(installation: HealthFixtures.installation)

        let packages = [
            HealthFixtures.package("git", offering: "1.2.3", outdated: true),
            HealthFixtures.package("hugo", offering: "2026-08-01", outdated: true)
        ]
        let store = MetadataStore(container: try PersistenceContainer.inMemory())
        BulkSnoozeSelection(
            selection: packages.map(\.id),
            entries: HealthFixtures.entries(packages),
            metadata: nil
        ).apply { store.snooze($0, offering: $1) }

        #expect(launcher.spawned.isEmpty, "bulk snooze spawned \(launcher.spawned)")
        #expect(operations.items.isEmpty, "bulk snooze submitted \(operations.items.count) operations")
        // …and the rows really were written, so the three absences above are not
        // the absence of the action itself.
        #expect(store.snoozedVersion(for: packages[0].id) == "1.2.3")
        #expect(store.snoozedVersion(for: packages[1].id) == "2026-08-01")
    }

    /// Structural: `OperationCenter` never learns the word, and `BrewClient`
    /// still does not link SwiftData.
    @Test("Neither the bulk vocabulary nor the operation centre names snooze")
    func neitherTheBulkVocabularyNorTheOperationCentreNamesSnooze() throws {
        for path in [
            "Sources/BrewClient/BulkSelection.swift",
            "Sources/BrewClient/OperationCenterBulk.swift",
            "Sources/BrewClient/OperationCenter.swift"
        ] {
            let code = try BulkActionBarSources.packageSource(at: path)
            #expect(code.isEmpty == false, "\(path) read as empty")
            // `isSnoozed` is deliberately allowed and deliberately not searched
            // for: `BulkSelection` *reads* the snooze state to keep a snoozed
            // package out of the upgrade set, which is II12 working correctly.
            // What may not exist is snooze as a **verb** on the mutation spine.
            // Tokens that cannot collide with `snoozedVersion`, which is the
            // read `BulkSelection` legitimately performs.
            for verb in ["case snooze", "func snooze", "submitSnooze", "snoozeBulk", "Snooze("] {
                #expect(
                    code.contains(verb) == false,
                    "\(path) names \(verb); HD11 keeps snooze off the mutation spine"
                )
            }
            #expect(code.contains("MetadataStore") == false, "\(path) reaches the metadata store directly")
            #expect(code.contains("SwiftData") == false, "\(path) links SwiftData")
        }
        // The anchor: those files really are the bulk spine.
        #expect(try BulkActionBarSources.packageSource(at: "Sources/BrewClient/BulkSelection.swift")
            .contains("case unpin"))
    }

    /// `createdAt` is provenance, never policy.
    @Test("No snooze timestamp reaches the suppression projection")
    func noSnoozeTimestampReachesTheSuppressionProjection() throws {
        let rule = try BulkActionBarSources.packageSource(at: "Sources/BrewClient/PackageMetadata.swift")
        #expect(rule.contains("snoozedVersion == candidate"))
        for clockword in ["createdAt", "Date(", ".now", "expires", "duration"] {
            #expect(rule.contains(clockword) == false, "the snooze rule reads \(clockword)")
        }
    }
}
