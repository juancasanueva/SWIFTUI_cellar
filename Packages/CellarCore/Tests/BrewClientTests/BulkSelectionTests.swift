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

    /// `Action` is `CaseIterable` with exactly four cases, so the absence of a
    /// bulk snooze, favorite or note affordance is an **assertion** rather than a
    /// convention — the same technique `ActivityItem.Control` uses.
    ///
    /// **Rewritten, not deleted** (m5-health, II13). This test previously
    /// asserted a two-case vocabulary and scanned the titles for
    /// `pin`/`unpin`/`snooze`/`favorite`/`note`. Pin and unpin were deliberately
    /// narrowed out on 2026-08-02 and the maintainer has reversed that ruling, so
    /// PRD §3.2's full bulk vocabulary ships. The title scan is the sharp edge
    /// and it survives: it still fails on any of the three verbs that remain
    /// prohibited, and `pin` had to be removed from it explicitly rather than
    /// left to be silently satisfied by a count change.
    ///
    /// Note that scanning for `"pin"` would now match `"Unpin"` as a substring
    /// anyway, which is exactly the kind of accident that makes a scan pass for
    /// the wrong reason — so the prohibited list is the three verbs and nothing
    /// that collides with a shipped one.
    @Test("Exactly upgrade, uninstall, pin and unpin are bulk-eligible, and nothing else is")
    func onlyTheFourMutationVerbsAreBulkEligible() {
        #expect(BulkSelection.Action.allCases == [.upgrade, .uninstall, .pin, .unpin])
        #expect(BulkSelection.Action.allCases.count == 4)

        let titles = BulkSelection.Action.allCases.map(\.title).joined(separator: " ").lowercased()
        for absent in ["snooze", "favorite", "note"] {
            #expect(titles.contains(absent) == false, "a bulk \(absent) affordance exists")
        }
        // And the two new ones really are there, by title as well as by case, so
        // the count above cannot be satisfied by two unrelated additions.
        #expect(titles.contains("pin"))
        #expect(titles.contains("unpin"))
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

    // MARK: - II13 — pin and unpin are two independent verbs

    /// The clause that makes them two verbs rather than one toggle: a selection
    /// holding both pinned and unpinned packages has **no single correct answer**,
    /// and "unavailable rather than inert" forbids guessing. So both are offered,
    /// each over its own subset, and neither guesses about the other's.
    @Test("A mixed pinned selection offers both verbs, each over exactly its own subset")
    func aMixedPinnedSelectionOffersBothVerbs() {
        let entries = Self.entries(
            upToDate: [Self.wget, Self.git, Self.curl],
            pinned: [Self.curl]
        )
        let selection = BulkSelection(
            selection: [Self.wget, Self.git, Self.curl],
            entries: entries
        )

        #expect(selection.isAvailable(.pin))
        #expect(selection.isAvailable(.unpin))
        #expect(selection.ids(for: .pin) == [Self.wget, Self.git])
        #expect(selection.ids(for: .unpin) == [Self.curl])
        // Honest counts: each announces exactly what it would submit.
        #expect(selection.label(for: .pin) == "Pin 2")
        #expect(selection.label(for: .unpin) == "Unpin 1")
    }

    /// Derived independently, so one being empty says nothing about the other.
    @Test("An all-unpinned selection leaves unpin unavailable, and the reverse")
    func eachVerbIsDerivedIndependently() {
        let entries = Self.entries(upToDate: [Self.wget, Self.git], pinned: [Self.git])

        let unpinned = BulkSelection(selection: [Self.wget], entries: entries)
        #expect(unpinned.isAvailable(.pin))
        #expect(unpinned.isAvailable(.unpin) == false)
        #expect(unpinned.ids(for: .unpin).isEmpty)

        let pinned = BulkSelection(selection: [Self.git], entries: entries)
        #expect(pinned.isAvailable(.unpin))
        #expect(pinned.isAvailable(.pin) == false)
        #expect(pinned.ids(for: .pin).isEmpty)
    }

    /// Pinning is formula-only in brew, and `MutationCommand.pin(formula:)` takes
    /// a `FormulaID` by construction. A cask must therefore never enter either
    /// set — and the resulting control is **unavailable rather than present and
    /// inert**.
    @Test("A selection containing only casks leaves both pin and unpin unavailable, not inert")
    func casksNeverEnterEitherSet() {
        let iterm2 = Self.iterm
        let entries = Self.entries(upToDate: [iterm2])
        let selection = BulkSelection(selection: [iterm2], entries: entries)

        #expect(selection.ids(for: .pin).isEmpty)
        #expect(selection.ids(for: .unpin).isEmpty)
        #expect(selection.isAvailable(.pin) == false, "a cask selection offered pin")
        #expect(selection.isAvailable(.unpin) == false, "a cask selection offered unpin")
        // The control: the same selection *is* uninstallable, so "unavailable"
        // is about pinning rather than about an empty selection.
        #expect(selection.isAvailable(.uninstall))
    }

    @Test("A cask never enters either set even when formulae are selected beside it")
    func aCaskIsFilteredOutOfAMixedKindSelection() {
        let entries = Self.entries(
            upToDate: [Self.wget, Self.iterm, Self.curl],
            pinned: [Self.curl]
        )
        let selection = BulkSelection(
            selection: [Self.wget, Self.iterm, Self.curl],
            entries: entries
        )

        #expect(selection.ids(for: .pin) == [Self.wget])
        #expect(selection.ids(for: .unpin) == [Self.curl])
        #expect(selection.ids(for: .pin).contains(Self.iterm) == false)
        #expect(selection.ids(for: .unpin).contains(Self.iterm) == false)
        // Uninstall still covers all three, so the filter is pinning-specific.
        #expect(selection.ids(for: .uninstall).count == 3)
    }

    /// A package that has left the inventory cannot be pinned either — the
    /// reconciliation happens once, before any verb's eligibility is derived.
    @Test("A departed package enters neither the pinnable nor the unpinnable set")
    func aDepartedPackageEntersNeitherPinSet() {
        let entries = Self.entries(upToDate: [Self.git])
        let selection = BulkSelection(selection: [Self.wget, Self.git], entries: entries)

        #expect(selection.ids(for: .pin) == [Self.git])
        #expect(selection.ids(for: .pin).contains(Self.wget) == false)
        #expect(selection.ids(for: .unpin).isEmpty)
    }

    /// Selection order is preserved through the new verbs too, because it
    /// determines submission order.
    @Test("Both new verbs report their sets in selection order")
    func bothNewVerbsPreserveSelectionOrder() {
        let entries = Self.entries(
            upToDate: [Self.wget, Self.git, Self.curl],
            pinned: [Self.git, Self.curl]
        )
        let selection = BulkSelection(
            selection: [Self.curl, Self.wget, Self.git],
            entries: entries
        )

        #expect(selection.ids(for: .unpin) == [Self.curl, Self.git])
        #expect(selection.ids(for: .pin) == [Self.wget])
    }

    // MARK: - II13 — the bulk mutation vocabulary, by case and by title

    /// The scenario both rewritten tests answer to: the vocabulary of bulk verbs
    /// that produce mutation commands is exactly these four, enumerated
    /// exhaustively **by case and by displayed title**.
    @Test("The bulk mutation vocabulary is exactly upgrade, uninstall, pin and unpin")
    func theBulkMutationVocabularyIsExactlyFour() {
        #expect(BulkSelection.Action.allCases == [.upgrade, .uninstall, .pin, .unpin])
        #expect(BulkSelection.Action.allCases.map(\.title) == ["Upgrade", "Uninstall", "Pin", "Unpin"])

        // By title, so a case renamed to dodge the enumeration above is caught.
        let titles = Set(BulkSelection.Action.allCases.map { $0.title.lowercased() })
        #expect(titles == ["upgrade", "uninstall", "pin", "unpin"])

        // No snooze, favorite, note or service verb — by case or by title.
        // Snooze travels its own app-side path precisely so it cannot be
        // represented here as a case that produces no command.
        for absent in ["snooze", "favorite", "note", "start", "stop", "restart"] {
            #expect(titles.contains(absent) == false, "\(absent) entered the bulk vocabulary by title")
        }
        for action in BulkSelection.Action.allCases {
            #expect(["snooze", "favorite", "note"].contains("\(action)") == false)
        }
    }

    /// Only the destructive one asks. Pin and unpin are reversible, so they
    /// require no confirmation.
    @Test("Only uninstall requires a confirmation")
    func onlyUninstallRequiresConfirmation() {
        #expect(BulkSelection.Action.uninstall.requiresConfirmation)
        #expect(BulkSelection.Action.upgrade.requiresConfirmation == false)
        #expect(BulkSelection.Action.pin.requiresConfirmation == false)
        #expect(BulkSelection.Action.unpin.requiresConfirmation == false)
        #expect(BulkSelection.Action.allCases.count { $0.requiresConfirmation } == 1)
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
