import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// A selection expands to one invocation per package, behind one confirmation
/// (package-mutation PM3 sc5–6, PM8; installation-history IH2 sc2; design D8).
///
/// Two threat rows meet here. **Subprocess argument composition**: no generated
/// argv may name more than one package, so kind mixing is structurally
/// impossible rather than merely avoided. **Irreversible mutation scope**: one
/// destructive action gets exactly one confirmation, it names every package it
/// will remove, and declining it submits none of them — never a partial subset.
@MainActor
@Suite("Bulk fan-out", .timeLimit(.minutes(1)))
struct BulkFanOutTests {
    /// Two formulae and a cask, deliberately mixed: a single grouped argv would
    /// have to pick one kind flag, and this ordering makes that impossible to
    /// hide.
    private static let selection = [CenterHarness.wget, CenterHarness.git, CenterHarness.iterm]

    // MARK: - PM8 sc1, IH2 sc2 — one invocation, and one entry, per package

    @Test("A confirmed bulk uninstall enqueues one single-package invocation per selection, in order")
    func aBulkUninstallFansOutInSelectionOrder() async throws {
        let harness = CenterHarness()

        let request = try #require(
            harness.center.submitBulk(.uninstall, over: Self.selection),
            "a bulk uninstall submitted without asking"
        )
        #expect(harness.center.items.isEmpty, "an operation was enqueued before the confirmation")

        let items = harness.center.confirm(request)
        await harness.settle()

        #expect(items.count == 3)
        #expect(items.map(\.arguments) == [
            ["uninstall", "--formula", "wget"],
            ["uninstall", "--formula", "git"],
            ["uninstall", "--cask", "iterm2"]
        ])

        // No argv names more than one package.
        for item in items {
            let names = item.arguments.filter { !$0.hasPrefix("-") && $0 != "uninstall" }
            #expect(names.count == 1, "an argv named \(names.count) packages")
        }
        #expect(harness.launcher.recordedSpecs.first?.arguments == items[0].arguments)

        for index in 0..<3 { try await harness.finish(call: index) }

        // Exactly three entries, one naming each package, in the same order.
        #expect(harness.recorder.drafts.count == 3)
        #expect(harness.recorder.drafts.map(\.packageID) == Self.selection)
        #expect(harness.recorder.drafts.allSatisfy { $0.verb == "uninstall" })
    }

    // MARK: - PM8 sc2 — a mid-batch failure attributes to one package

    @Test("A mid-batch non-zero exit attributes to the second package and the third still runs")
    func aMidBatchFailureStopsNothingElse() async throws {
        let harness = CenterHarness()
        let request = try #require(harness.center.submitBulk(.uninstall, over: Self.selection))
        let items = harness.center.confirm(request)
        await harness.settle()

        try await harness.finish(call: 0, status: 0)
        try await harness.finish(call: 1, status: 1)
        try await harness.finish(call: 2, status: 0)

        #expect(items[0].outcome == .succeeded)
        #expect(items[1].outcome == .failed(status: 1))
        #expect(items[2].outcome == .succeeded, "a sibling was poisoned by the failing operation")
        #expect(items[1].packageID == CenterHarness.git)
        #expect(items.count(where: { $0.outcome?.isFailure == true }) == 1)
        #expect(harness.launcher.launchCount == 3, "the third operation never ran")
    }

    // MARK: - PM8 sc3 — cancelling one leaves the rest of the batch alone

    @Test("Cancelling the second of three leaves the first running and the third queued")
    func cancellingOneLeavesTheRestQueued() async throws {
        let harness = CenterHarness()
        let request = try #require(harness.center.submitBulk(.uninstall, over: Self.selection))
        let items = harness.center.confirm(request)
        await harness.launcher.waitForLaunches(atLeast: 1)
        await harness.settle()

        // Mutations are serialized, so only the first has spawned.
        #expect(harness.launcher.launchCount == 1)

        harness.center.cancel(items[1])
        await harness.poll { items[1].isTerminal }

        #expect(items[1].outcome == .cancelled)
        #expect(harness.launcher.launchCount == 1, "the cancelled operation spawned a process")
        #expect(items[0].isTerminal == false, "cancelling one settled the running operation")
        #expect(items[2].isTerminal == false, "cancelling one settled the operation behind it")

        try await harness.finish(call: 0)
        try await harness.finish(call: 1)

        #expect(items[0].outcome == .succeeded)
        #expect(items[2].outcome == .succeeded, "the third operation never ran after the cancel")
        // Three terminals, three entries: a cancellation is recorded like any
        // other outcome.
        #expect(harness.recorder.drafts.count == 3)
    }

    // MARK: - PM8 sc4, II13 — no verb without a selection form accepts a selection

    /// **Rewritten, not deleted** (m5-health, II13). This test also pinned the
    /// two-case vocabulary, in both of its halves: the exhaustive `allCases`
    /// assertion, and a source scan asserting `.pin` and `.unpin` appear nowhere
    /// in the bulk surface. Pin and unpin were deliberately narrowed out on
    /// 2026-08-02 and the maintainer has reversed that ruling.
    ///
    /// Its intent survives exactly and is what the rewrite keeps: **no verb that
    /// has no selection form may appear in the bulk surface**. `reinstall` and
    /// `zap` still have none, so they are still scanned for. Pin and unpin now
    /// do, so they moved from the prohibited list into the exhaustive one — and
    /// each is asserted to produce only its own verb, which is the half that
    /// makes the widening honest rather than merely permitted.
    @Test("Only the four mutation verbs expand over a selection, and each produces only its own")
    func noOtherVerbAcceptsASelection() throws {
        let harness = CenterHarness()

        // Exhaustive over the whole bulk surface.
        #expect(BulkSelection.Action.allCases == [.upgrade, .uninstall, .pin, .unpin])

        let expectedVerb: [BulkSelection.Action: String] = [
            .upgrade: "upgrade", .uninstall: "uninstall", .pin: "pin", .unpin: "unpin"
        ]
        for action in BulkSelection.Action.allCases {
            let commands = harness.center.commands(for: action, over: Self.selection)
            let verbs = Set(commands.map(\.verb))
            #expect(verbs == [expectedVerb[action]], "\(action) produced \(verbs)")
        }

        // Pin and unpin are formula-only **by construction**, so the cask in the
        // selection produces no command rather than an invalid one. That is the
        // fan-out half of "a cask never enters a pin or unpin set".
        #expect(harness.center.commands(for: .upgrade, over: Self.selection).count == 3)
        #expect(harness.center.commands(for: .uninstall, over: Self.selection).count == 3)
        #expect(harness.center.commands(for: .pin, over: Self.selection).count == 2)
        #expect(harness.center.commands(for: .unpin, over: Self.selection).count == 2)

        // And nothing in the bulk surface names a verb that still has no
        // selection form — asserted on the source, so a future overload cannot
        // slip one in without this failing.
        let source = try Self.declarations(of: "OperationCenterBulk.swift")
        for absent in [".reinstall", ".zap"] {
            #expect(source.contains(absent) == false, "a bulk \(absent) mutation exists")
        }
    }

    // MARK: - II13 — the two new verbs fan out over exactly their eligible set

    @Test("Bulk pin and bulk unpin fan out one command per eligible formula, in selection order")
    func pinAndUnpinFanOutOverTheirEligibleSet() {
        let harness = CenterHarness()
        let formulae = [CenterHarness.wget, CenterHarness.git]

        let pins = harness.center.commands(for: .pin, over: formulae)
        let unpins = harness.center.commands(for: .unpin, over: formulae)

        #expect(pins.map(\.arguments) == [
            ["pin", "--formula", "wget"],
            ["pin", "--formula", "git"]
        ])
        #expect(unpins.map(\.arguments) == [
            ["unpin", "--formula", "wget"],
            ["unpin", "--formula", "git"]
        ])
        // One package per argv, like every other fan-out.
        for command in pins + unpins {
            let names = command.arguments.filter { !$0.hasPrefix("-") }
            #expect(names.count == 2, "an argv named \(names.count - 1) packages")
        }
    }

    /// It acts on exactly the set it is handed, and never on an ineligible
    /// member: a cask cannot become a pin command, because `FormulaID` refuses
    /// it at construction.
    @Test("A cask never produces a pin or unpin command")
    func aCaskNeverProducesAPinCommand() {
        let harness = CenterHarness()

        #expect(harness.center.commands(for: .pin, over: [CenterHarness.iterm]).isEmpty)
        #expect(harness.center.commands(for: .unpin, over: [CenterHarness.iterm]).isEmpty)
        // The control: the same cask does produce an uninstall.
        #expect(harness.center.commands(for: .uninstall, over: [CenterHarness.iterm]).count == 1)
    }

    /// Bulk pin and bulk unpin are reversible, so neither raises a confirmation
    /// and `submitBulk` submits directly — the same rule the single-command path
    /// applies, not a bulk-specific exception.
    @Test("Bulk pin and bulk unpin submit directly, asking nothing")
    func pinAndUnpinAskNothing() async throws {
        let harness = CenterHarness()
        let formulae = [CenterHarness.wget, CenterHarness.git]

        #expect(harness.center.submitBulk(.pin, over: formulae) == nil, "bulk pin raised a confirmation")
        await harness.settle()
        #expect(harness.center.pendingConfirmation == nil)
        #expect(harness.center.items.map(\.arguments) == [
            ["pin", "--formula", "wget"],
            ["pin", "--formula", "git"]
        ])
        for index in 0..<2 { try await harness.finish(call: index) }
    }

    // MARK: - PM3 sc5 — threat: irreversible mutation scope

    @Test("One bulk uninstall asks once, and the confirmation names every selected package")
    func oneConfirmationNamesEveryPackage() throws {
        let harness = CenterHarness()

        let request = try #require(harness.center.submitBulk(.uninstall, over: Self.selection))

        #expect(harness.center.pendingConfirmation == request, "more than one confirmation is pending")
        #expect(request.commands.count == 3)
        #expect(request.isBulk)
        #expect(request.displayCommands == [
            "brew uninstall --formula wget",
            "brew uninstall --formula git",
            "brew uninstall --cask iterm2"
        ])

        // Every package, named — not a count and not an elided subset.
        let text = request.displayCommand
        for id in Self.selection {
            #expect(text.contains(id.name), "\(id.name) was not disclosed by the confirmation")
        }
        #expect(harness.center.items.isEmpty)
        #expect(harness.launcher.launchCount == 0)
    }

    // MARK: - PM3 sc6 — declining submits none of it, never a subset

    @Test("Declining a bulk uninstall submits none of it and spawns nothing")
    func decliningSubmitsNoneOfIt() async throws {
        let harness = CenterHarness()
        let request = try #require(harness.center.submitBulk(.uninstall, over: Self.selection))

        harness.center.decline(request)
        await harness.settle()

        #expect(harness.center.items.isEmpty, "a declined bulk uninstall enqueued a partial subset")
        #expect(harness.launcher.launchCount == 0)
        #expect(harness.center.pendingConfirmation == nil)
        #expect(harness.recorder.drafts.isEmpty)
    }

    /// A bulk upgrade is not destructive, so it is submitted directly — the same
    /// rule the single-command path applies, not a bulk-specific exception.
    @Test("A bulk upgrade needs no confirmation and submits directly, in selection order")
    func aBulkUpgradeSubmitsDirectly() async throws {
        let harness = CenterHarness()

        #expect(harness.center.submitBulk(.upgrade, over: Self.selection) == nil)
        await harness.settle()

        #expect(harness.center.items.map(\.arguments) == [
            ["upgrade", "--formula", "wget"],
            ["upgrade", "--formula", "git"],
            ["upgrade", "--cask", "iterm2"]
        ])
        for index in 0..<3 { try await harness.finish(call: index) }
    }

    // MARK: - II14 — the announced count and the submitted set are one projection

    /// The M2-2 defect this closes: the button counted the dependency-filtered
    /// entries while the submission filtered the whole inventory. Asserted over
    /// **every** combination of the two things that can move them apart, so
    /// agreement is structural rather than two filters happening to concur.
    @Test(
        "The announced upgradable count equals the operations submitted, in every combination",
        arguments: [true, false], [true, false]
    )
    func theCountEqualsTheSubmission(includingDependencies: Bool, snoozed: Bool) async throws {
        let harness = CenterHarness()
        let inventory = InstalledFixture.inventory(
            outdated: [
                CenterHarness.wget: "1.2.3",
                CenterHarness.git: "2.44.0",
                CenterHarness.iterm: "3.5.0",
                Self.curl: "8.7.1"
            ],
            pinned: [Self.curl],
            dependencies: [CenterHarness.git]
        )
        let browse = InstalledBrowse(inventory: inventory, isAvailable: true)
        let snapshot: MetadataSnapshot = [CenterHarness.wget: PackageMetadata(snoozedVersion: "1.2.3")]
        let metadata: MetadataLookup? = snoozed ? snapshot.lookup : nil

        let ids = browse.upgradableIDs(
            includingDependencies: includingDependencies,
            metadata: metadata
        )
        let announced = browse.upgradableCount(
            includingDependencies: includingDependencies,
            metadata: metadata
        )
        let items = harness.center.submitUpgrades(for: ids, in: inventory)
        await harness.settle()

        // Non-trivial in every case: `iterm2` is outdated, on request, unpinned
        // and never snoozed, so at least one package is always submitted.
        #expect(ids.contains(CenterHarness.iterm))
        #expect(ids.contains(Self.curl) == false, "a pinned package was submitted")
        #expect(items.count == announced, "the label announced \(announced) and submitted \(items.count)")
        #expect(items.compactMap(\.packageID) == ids)
        #expect(ids.contains(CenterHarness.wget) == !snoozed)
        #expect(ids.contains(CenterHarness.git) == includingDependencies)

        for index in 0..<items.count { try await harness.finish(call: index) }
    }

    /// The other half of II14: there must be **no second derivation** to
    /// disagree with. `submitUpgradesForOutdated(in:)` filtered the whole
    /// inventory while the label counted the dependency-filtered entries, which
    /// is exactly the pair of sets this closes — so its absence is asserted,
    /// not merely intended.
    @Test("No parallel outdated-set submission exists to disagree with the announced count")
    func noSecondDerivationOfTheUpgradableSetExists() throws {
        for file in ["OperationCenter.swift", "OperationCenterBulk.swift"] {
            // Declarations, not prose: the rejected alternative is still worth
            // recording in a comment, and a comment cannot submit anything.
            let source = try Self.declarations(of: file)
            #expect(
                source.contains("submitUpgradesForOutdated") == false,
                "\(file) still derives the upgradable set a second way"
            )
        }
        // The one derivation everything reads.
        #expect(try Self.source(of: "InstalledFilterMode.swift").contains("func upgradableIDs("))
    }

    private static let curl = PackageID(kind: .formula, name: "curl")

    /// The file with every comment line removed, so a structural claim is made
    /// about what the module *declares* rather than about what it explains.
    private static func declarations(of file: String) throws -> String {
        try source(of: file)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private static func source(of file: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/BrewClient/\(file)"),
            encoding: .utf8
        )
    }
}
