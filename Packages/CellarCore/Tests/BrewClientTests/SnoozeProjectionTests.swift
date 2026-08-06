import Catalog
import Foundation
import Testing

@testable import BrewClient

/// The snooze badge rule, and the outdated set it composes into
/// (local-package-metadata LPM5, installed-inventory II12).
///
/// The whole rule is **string equality**: the badge is suppressed for exactly as
/// long as the offered version equals the one the snooze was taken against. Any
/// different value revives it, with no user action.
///
/// That was a ruling, not a default (Engram `#7117`). An ordering comparator
/// that misread `1.2.3_1`, `2023-10-01`, `r5` or `9e` would **silently suppress
/// a real update, forever** — the one outcome this feature must never produce.
/// Equality's failure mode is a badge that is honest: a package republished at
/// an older version shows one again. The tests below assert the accepted false
/// positive on purpose, so nobody "fixes" it into a comparator.
///
/// The structural guards behind the rule live in `SnoozeGuardTests`: the guard
/// grew in M4 and the behaviour did not, and keeping them in one file would
/// have made that impossible to see in a diff.
@Suite("Snooze projection")
struct SnoozeProjectionTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let git = PackageID(kind: .formula, name: "git")

    // MARK: - LPM5 sc1–2 — suppression while unchanged, revival when different

    @Test("The badge is suppressed while the offered version is exactly the snoozed one")
    func theBadgeIsSuppressedWhileUnchanged() {
        #expect(PackageMetadata.isSnoozed(offering: "1.2.3", snoozedVersion: "1.2.3"))
    }

    @Test("A newer offered version revives the badge with no user action")
    func aNewerOfferedVersionRevivesTheBadge() {
        #expect(PackageMetadata.isSnoozed(offering: "1.3.0", snoozedVersion: "1.2.3") == false)
    }

    // MARK: - LPM5 sc3 — the accepted, visible false positive (the G5 ruling)

    @Test(
        "A revision-suffixed or older offered version also revives the badge",
        arguments: ["1.2.3_1", "1.2.2", "1.2.3-1", "1.2", "1.2.30"]
    )
    func anyDifferentOfferedVersionRevivesTheBadge(offered: String) {
        #expect(PackageMetadata.isSnoozed(offering: offered, snoozedVersion: "1.2.3") == false)
    }

    @Test("A package with no snooze is never suppressed")
    func noSnoozeIsNeverSuppressed() {
        #expect(PackageMetadata.isSnoozed(offering: "1.2.3", snoozedVersion: nil) == false)
        #expect(PackageMetadata().isSnoozed(offering: "1.2.3") == false)
        #expect(PackageMetadata(snoozedVersion: "1.2.3").isSnoozed(offering: "1.2.3"))
    }

    // MARK: - LPM5 sc4 — unsnoozing restores the badge on the next read

    @Test("Removing the snooze shows the badge on the next read, with no inventory refresh")
    func unsnoozingRestoresTheBadgeImmediately() {
        let inventory = InstalledFixture.inventory(
            outdated: [Self.wget: "1.2.3", Self.git: "2.44.0"]
        )
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)
        let snoozed: MetadataSnapshot = [Self.wget: PackageMetadata(snoozedVersion: "1.2.3")]

        #expect(browse.outdatedIDs(metadata: snoozed.lookup) == [Self.git])

        // The very same inventory, read again with the snooze gone.
        #expect(browse.outdatedIDs(metadata: nil) == [Self.wget, Self.git])
        #expect(browse.outdatedIDs(metadata: MetadataSnapshot().lookup) == [Self.wget, Self.git])
    }

    // MARK: - LPM5 sc5 / II12 sc4 — a snooze never hides the package

    @Test("A snoozed, outdated package is still listed with its installed version")
    func aSnoozedPackageIsStillListed() {
        let inventory = InstalledFixture.inventory(outdated: [Self.wget: "1.2.3"])
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)
        let snoozed: MetadataSnapshot = [Self.wget: PackageMetadata(snoozedVersion: "1.2.3")]

        let listed = browse.entries(
            includingDependencies: true,
            catalogLookup: { _ in nil },
            metadata: snoozed.lookup
        )

        #expect(listed.map(\.id).contains(Self.wget))
        #expect(listed.first { $0.id == Self.wget }?.version == InstalledFixture.installedVersion)
    }

    // MARK: - II12 sc1–2 — the outdated set and the count

    @Test("A snoozed package is absent from the outdated set and the count is one lower")
    func aSnoozedPackageLeavesTheSetAndTheCount() {
        let inventory = InstalledFixture.inventory(
            outdated: [Self.wget: "1.2.3", Self.git: "2.44.0"]
        )
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)
        let snoozed: MetadataSnapshot = [Self.wget: PackageMetadata(snoozedVersion: "1.2.3")]

        #expect(browse.outdatedIDs(metadata: snoozed.lookup) == [Self.git])
        #expect(browse.outdatedCount(metadata: snoozed.lookup) == 1)
        #expect(browse.outdatedCount(metadata: nil) == 2)
    }

    @Test(
        "A changed offered version returns the package to the set and the count",
        arguments: ["1.3.0", "1.2.3_1"]
    )
    func aChangedOfferedVersionReturnsItToTheSet(offered: String) {
        let inventory = InstalledFixture.inventory(
            outdated: [Self.wget: offered, Self.git: "2.44.0"]
        )
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)
        // Snoozed at 1.2.3 while brew now offers something else.
        let snoozed: MetadataSnapshot = [Self.wget: PackageMetadata(snoozedVersion: "1.2.3")]

        #expect(browse.outdatedIDs(metadata: snoozed.lookup) == [Self.wget, Self.git])
        #expect(browse.outdatedCount(metadata: snoozed.lookup) == 2)
    }

    // MARK: - II12 sc3 — the browse filter agrees with the list, exactly

    @Test("The outdated browse filter shows exactly the outdated set")
    func theOutdatedFilterAgreesWithTheList() {
        let inventory = InstalledFixture.inventory(
            outdated: [Self.wget: "1.2.3", Self.git: "2.44.0"]
        )
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)
        let snoozed: MetadataSnapshot = [Self.wget: PackageMetadata(snoozedVersion: "1.2.3")]

        let filtered = browse.rows(
            mode: .outdated,
            query: "",
            filters: SearchFilters(),
            catalogResults: [],
            catalogLookup: { _ in nil },
            metadata: snoozed.lookup
        )

        #expect(Set(filtered.map(\.id)) == browse.outdatedIDs(metadata: snoozed.lookup))
        #expect(filtered.map(\.id).contains(Self.wget) == false, "a snoozed package survived the filter")
    }

    // MARK: - LPM6 sc1 — a cold or unavailable store changes nothing

    @Test("With no metadata every projection is identical to the pre-metadata behaviour")
    func anEmptyStoreChangesNothing() {
        let inventory = InstalledFixture.inventory(
            outdated: [Self.wget: "1.2.3", Self.git: "2.44.0"]
        )
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)

        for lookup in [nil, MetadataSnapshot().lookup] as [MetadataLookup?] {
            #expect(browse.outdatedIDs(metadata: lookup) == inventory.outdatedIDs)
            #expect(browse.outdatedCount(metadata: lookup) == inventory.outdatedCount)
            #expect(
                browse.entries(
                    includingDependencies: true,
                    catalogLookup: { _ in nil },
                    metadata: lookup
                ).map(\.id)
                    == browse.entries(includingDependencies: true, catalogLookup: { _ in nil })
                    .map(\.id)
            )
        }
    }
}
