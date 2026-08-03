import Catalog
import Foundation
import Testing

@testable import BrewClient

/// What a multi-selection is eligible for, and in what order
/// (installed-inventory II13, II14, design D8).
@Suite("Bulk selection")
struct BulkSelectionTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let git = PackageID(kind: .formula, name: "git")
    private static let iterm = PackageID(kind: .cask, name: "iterm2")
    private static let curl = PackageID(kind: .formula, name: "curl")

    private static func entries(
        outdated: [PackageID: String] = [:],
        upToDate: [PackageID] = [],
        pinned: Set<PackageID> = []
    ) -> [PackageEntry] {
        let inventory = InstalledFixture.inventory(
            outdated: outdated,
            upToDate: upToDate,
            pinned: pinned
        )
        return InstalledBrowse(inventory: inventory, isAvailable: true)
            .entries(includingDependencies: true, catalogLookup: { _ in nil })
    }

    // MARK: - II13 sc1–2 — the selection preserves order

    @Test("The selection is reported in the order the packages were selected")
    func theSelectionPreservesOrder() {
        let entries = Self.entries(upToDate: [Self.git, Self.wget, Self.iterm])
        let selection = BulkSelection(
            selection: [Self.wget, Self.iterm, Self.git],
            entries: entries
        )

        #expect(selection.uninstallable == [Self.wget, Self.iterm, Self.git])
    }

    @Test("Deselecting one package leaves the others in their original relative order")
    func deselectingPreservesRelativeOrder() {
        let entries = Self.entries(upToDate: [Self.git, Self.wget, Self.iterm])
        let selection = BulkSelection(selection: [Self.wget, Self.git], entries: entries)

        #expect(selection.uninstallable == [Self.wget, Self.git])
    }

    // MARK: - II13 sc3 — a package that leaves the inventory leaves the selection

    @Test("A package no longer in the inventory is not eligible for anything")
    func aDepartedPackageLeavesTheSelection() {
        // `wget` was selected, then uninstalled outside the app.
        let entries = Self.entries(upToDate: [Self.git])
        let selection = BulkSelection(selection: [Self.wget, Self.git], entries: entries)

        #expect(selection.uninstallable == [Self.git])
        #expect(selection.upgradable.isEmpty)
        #expect(selection.reconciled(against: entries) == [Self.git])
    }

    // MARK: - II13 sc4 — threat: irreversible mutation scope

    /// `Action` is `CaseIterable` with exactly two cases, so the absence of a
    /// bulk pin, unpin, snooze, favorite or note affordance is an **assertion**
    /// rather than a convention — the same technique `ActivityItem.Control`
    /// uses.
    @Test("Exactly upgrade and uninstall are bulk-eligible, and nothing else is")
    func onlyUpgradeAndUninstallAreBulkEligible() {
        #expect(BulkSelection.Action.allCases == [.upgrade, .uninstall])
        #expect(BulkSelection.Action.allCases.count == 2)

        let titles = BulkSelection.Action.allCases.map(\.title).joined(separator: " ").lowercased()
        for absent in ["pin", "unpin", "snooze", "favorite", "note"] {
            #expect(titles.contains(absent) == false, "a bulk \(absent) affordance exists")
        }
    }

    // MARK: - II13 sc5 — an empty selection offers no enabled control

    @Test("An empty selection reports every bulk control unavailable rather than inert")
    func anEmptySelectionOffersNothing() {
        let entries = Self.entries(upToDate: [Self.wget])
        let selection = BulkSelection(selection: [], entries: entries)

        #expect(selection.isEmpty)
        for action in BulkSelection.Action.allCases {
            #expect(selection.isAvailable(action) == false, "\(action) was offered for an empty selection")
            #expect(selection.ids(for: action).isEmpty)
        }
    }

    @Test("A control that cannot act on the current selection is unavailable")
    func anIneligibleControlIsUnavailable() {
        // Selected, installed, but nothing is outdated: uninstall yes, upgrade no.
        let entries = Self.entries(upToDate: [Self.wget, Self.git])
        let selection = BulkSelection(selection: [Self.wget, Self.git], entries: entries)

        #expect(selection.isAvailable(.uninstall))
        #expect(selection.isAvailable(.upgrade) == false)
        #expect(selection.ids(for: .uninstall) == [Self.wget, Self.git])
        #expect(selection.ids(for: .upgrade).isEmpty)
    }

    // MARK: - Eligibility — outdated, not pinned, not snoozed

    @Test("Upgradable is selected, outdated, unpinned and unsnoozed, in selection order")
    func upgradableIsTheIntersection() {
        let entries = Self.entries(
            outdated: [Self.wget: "1.2.3", Self.git: "2.44.0", Self.curl: "8.7.1"],
            upToDate: [Self.iterm],
            pinned: [Self.curl]
        )
        let metadata: MetadataSnapshot = [Self.git: PackageMetadata(snoozedVersion: "2.44.0")]

        let selection = BulkSelection(
            selection: [Self.iterm, Self.curl, Self.git, Self.wget],
            entries: entries,
            metadata: metadata.lookup
        )

        // `iterm2` is not outdated, `curl` is pinned, `git` is snoozed.
        #expect(selection.upgradable == [Self.wget])
        // Uninstall is unaffected by any of those three.
        #expect(selection.uninstallable == [Self.iterm, Self.curl, Self.git, Self.wget])
    }

    // MARK: - II14 sc1–3 — the label counts exactly the set it submits

    @Test("The announced count equals the ids submitted under the default filters")
    func theAnnouncedCountEqualsTheSubmittedSet() {
        let inventory = InstalledFixture.inventory(outdated: [Self.wget: "1.2.3", Self.git: "2.44.0"])
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)

        let ids = browse.upgradableIDs(includingDependencies: false)
        #expect(browse.upgradableCount(includingDependencies: false) == ids.count)
        #expect(ids.count == 2)
    }

    @Test("Toggling the dependency filter moves the count and the submitted set together")
    func theDependencyToggleMovesBothTogether() {
        let inventory = InstalledFixture.inventory(
            outdated: [Self.wget: "1.2.3", Self.git: "2.44.0"],
            dependencies: [Self.git]
        )
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)

        let onRequestOnly = browse.upgradableIDs(includingDependencies: false)
        let withDependencies = browse.upgradableIDs(includingDependencies: true)

        #expect(onRequestOnly == [Self.wget])
        #expect(Set(withDependencies) == [Self.wget, Self.git])
        #expect(browse.upgradableCount(includingDependencies: false) == onRequestOnly.count)
        #expect(browse.upgradableCount(includingDependencies: true) == withDependencies.count)
        #expect(browse.upgradableCount(includingDependencies: true)
            != browse.upgradableCount(includingDependencies: false))
    }

    @Test("With three outdated packages, one snoozed, the announced count is two")
    func aSnoozedPackageLeavesBothTheCountAndTheSubmission() {
        let inventory = InstalledFixture.inventory(
            outdated: [Self.wget: "1.2.3", Self.git: "2.44.0", Self.curl: "8.7.1"]
        )
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)
        let metadata: MetadataSnapshot = [Self.git: PackageMetadata(snoozedVersion: "2.44.0")]

        let ids = browse.upgradableIDs(includingDependencies: true, metadata: metadata.lookup)

        #expect(browse.upgradableCount(includingDependencies: true, metadata: metadata.lookup) == 2)
        #expect(ids.count == 2)
        #expect(ids.contains(Self.git) == false, "the snoozed package would still have been submitted")
        #expect(Set(ids) == [Self.wget, Self.curl])
    }

    /// The pinned exclusion lives in the derivation, once — and no unpin is
    /// submitted on their behalf (package-mutation PM2).
    @Test("A pinned outdated package is excluded from the count and the submission alike")
    func pinnedPackagesAreExcludedFromBoth() {
        let inventory = InstalledFixture.inventory(
            outdated: [Self.wget: "1.2.3", Self.curl: "8.7.1"],
            pinned: [Self.curl]
        )
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)

        #expect(browse.upgradableIDs(includingDependencies: true) == [Self.wget])
        #expect(browse.upgradableCount(includingDependencies: true) == 1)
    }
}
