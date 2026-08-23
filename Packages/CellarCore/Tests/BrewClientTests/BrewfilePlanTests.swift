import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The plan (`brewfile-management` BF7, `package-mutation` PM1 and PM9,
/// design DD1).
///
/// Applying a selection expands into one **existing** typed command per selected
/// entry — a tap add or an install — and nothing else. This capability
/// introduces no mutating command family, no seventh case of
/// `MutationCommand`, and no new invalidation domain. It cannot fail and cannot
/// emit free text, because by the time it runs, every name it holds is an
/// already-constructed `TapName`, `FormulaID` or `CaskID`.
///
/// Tap ordering is load-bearing **twice**. A package from a newly added tap must
/// not be attempted before its tap exists — and the shared confirmation gate
/// derives the batch's disclosure from `commands.first`, so a tap-carrying batch
/// presents the tap-add warning only when a tap leads it. Both consequences are
/// asserted, not just the ordering.
@MainActor
@Suite("Brewfile plan", .timeLimit(.minutes(1)))
struct BrewfilePlanTests {

    static func parse(_ text: String) async throws -> BrewfileDocument {
        try await BrewfileParser.decode(Data(text.utf8))
    }

    static func diff(_ text: String) async throws -> BrewfileDiff {
        BrewfileDiff(document: try await parse(text), installed: .empty, taps: .empty)
    }

    // MARK: - BF7 — one existing command per selected entry

    @Test("A mixed selection fans out, taps first, one subject per argv")
    func aMixedSelectionFansOutTapsFirst() async throws {
        let diff = try await Self.diff(
            """
            tap "acme/tap"
            brew "wget"
            brew "git"
            """
        )
        let plan = BrewfilePlan(selecting: diff.selectedEntries)

        #expect(plan.commands.count == 3)
        #expect(
            plan.commands.map(\.arguments) == [
                ["tap", "acme/tap"],
                ["install", "--formula", "wget"],
                ["install", "--formula", "git"]
            ]
        )
        #expect(plan.commands.map(\.verb) == ["tapAdd", "install", "install"])

        // One subject per argv: exactly one non-flag token after the verb.
        for command in plan.commands {
            let subjects = command.arguments.dropFirst().filter { $0.hasPrefix("--") == false }
            #expect(subjects.count == 1, "\(command.displayCommand) names more than one subject")
        }
    }

    @Test("A cask entry becomes an install carrying the cask flag")
    func aCaskEntryBecomesAnInstallCarryingTheCaskFlag() async throws {
        let diff = try await Self.diff("cask \"iterm2\"\n")
        let plan = BrewfilePlan(selecting: diff.selectedEntries)

        #expect(plan.commands.map(\.arguments) == [["install", "--cask", "iterm2"]])
        #expect(plan.installs.count == 1)
        #expect(plan.taps.isEmpty)
    }

    @Test("Only selected entries are submitted")
    func onlySelectedEntriesAreSubmitted() async throws {
        let document = try await Self.parse(
            """
            brew "wget"
            brew "git"
            brew "ripgrep"
            mas "Xcode", id: 497799835
            vscode "ms-python.python"
            """
        )
        var diff = BrewfileDiff(
            document: document,
            installed: InstalledFixture.inventory(upToDate: [PackageID(kind: .formula, name: "ripgrep")]),
            taps: .empty
        )
        // Two missing entries; deselect one.
        let deselected = try #require(diff.missing.first { $0.displayName == "git" }?.id)
        diff.deselect(deselected)

        let plan = BrewfilePlan(selecting: diff.selectedEntries)

        #expect(plan.commands.count == 1)
        #expect(plan.commands.first?.arguments == ["install", "--formula", "wget"])
        for absent in ["git", "ripgrep", "Xcode", "ms-python.python"] {
            #expect(
                plan.commands.contains { $0.arguments.contains(absent) } == false,
                "\(absent) reached the plan"
            )
        }
    }

    @Test("An empty selection produces an empty plan, and submits nothing")
    func anEmptySelectionProducesAnEmptyPlan() async throws {
        var diff = try await Self.diff("brew \"wget\"\nbrew \"git\"\n")
        diff.deselectAll()

        let plan = BrewfilePlan(selecting: diff.selectedEntries)
        #expect(plan.commands.isEmpty)
        #expect(plan.isEmpty)

        let harness = CenterHarness()
        #expect(harness.center.request(plan.commands) == nil, "an empty batch raised a confirmation")
        #expect(harness.center.pendingConfirmation == nil)
        #expect(harness.launcher.launchCount == 0)
    }

    // MARK: - BF7, DD1 — taps lead, even when selected last

    @Test("A tap selected last still leads the batch, and still leads the confirmation")
    func aTapSelectedLastStillLeadsTheBatch() async throws {
        let diff = try await Self.diff(
            """
            brew "wget"
            brew "git"
            tap "acme/tap"
            """
        )
        // The tap is the last line of the file, so it is last in selection order.
        #expect(diff.selectedEntries.last?.tapName == TapName("acme/tap"))

        let plan = BrewfilePlan(selecting: diff.selectedEntries)

        // Consequence 1 — execution order: the tap exists before anything from
        // it is attempted.
        #expect(plan.commands.first?.arguments == ["tap", "acme/tap"])
        #expect(plan.commands.map(\.verb) == ["tapAdd", "install", "install"])

        // Consequence 2 — disclosure: the gate reads `commands.first`, so the
        // ordering is what makes the tap warning reachable at all.
        let harness = CenterHarness()
        let request = try #require(harness.center.request(plan.commands))
        #expect(request.disclosure == .tapAdd(TapName("acme/tap")!))
    }

    @Test("Relative order inside each group follows the file")
    func relativeOrderInsideEachGroupFollowsTheFile() async throws {
        let diff = try await Self.diff(
            """
            brew "wget"
            tap "beta/tap"
            cask "iterm2"
            tap "alpha/tap"
            brew "git"
            """
        )
        let plan = BrewfilePlan(selecting: diff.selectedEntries)

        #expect(
            plan.commands.map(\.arguments) == [
                ["tap", "beta/tap"],
                ["tap", "alpha/tap"],
                ["install", "--formula", "wget"],
                ["install", "--cask", "iterm2"],
                ["install", "--formula", "git"]
            ],
            "the plan re-sorted within a group instead of preserving file order"
        )
    }

    // MARK: - BF7, PM1, BF5 — one confirmation covers the batch

    @Test("One confirmation covers the batch, and declining submits nothing")
    func oneConfirmationCoversTheBatchAndDecliningSubmitsNothing() async throws {
        let diff = try await Self.diff(
            """
            brew "wget"
            brew "git"
            tap "acme/tap"
            """
        )
        let plan = BrewfilePlan(selecting: diff.selectedEntries)
        let harness = CenterHarness()

        let request = try #require(harness.center.request(plan.commands))
        #expect(request.commands.count == 3, "the confirmation covered less than the whole batch")
        #expect(request.disclosure == .tapAdd(TapName("acme/tap")!))
        #expect(harness.launcher.launchCount == 0, "something was enqueued before the yes")

        // Declining submits none of it, never a partial subset.
        harness.center.decline(request)
        #expect(harness.center.pendingConfirmation == nil)
        #expect(harness.launcher.launchCount == 0)
        #expect(harness.center.items.isEmpty)
    }

    @Test("Confirming submits every command the confirmation showed")
    func confirmingSubmitsEveryCommandTheConfirmationShowed() async throws {
        let diff = try await Self.diff(
            """
            tap "acme/tap"
            brew "wget"
            brew "git"
            """
        )
        let plan = BrewfilePlan(selecting: diff.selectedEntries)
        let harness = CenterHarness()

        let request = try #require(harness.center.request(plan.commands))
        let items = harness.center.confirm(request)

        #expect(items.count == 3)
        #expect(
            items.map(\.arguments) == [
                ["tap", "acme/tap"],
                ["install", "--formula", "wget"],
                ["install", "--formula", "git"]
            ]
        )
        for index in 0..<3 { try await harness.finish(call: index) }
        #expect(items.allSatisfy { $0.outcome == .succeeded })
    }

    /// BF5, proven end to end: a `trusted:` claim in the file changes nothing
    /// about the confirmation the user is shown.
    @Test("A trusted tap still raises the identical trust disclosure")
    func aTrustedTapStillRaisesTheIdenticalTrustDisclosure() async throws {
        let claimed = try await Self.diff("tap \"acme/tap\", trusted: { casks: [\"thing\"] }\n")
        let plain = try await Self.diff("tap \"acme/tap\"\n")

        // The claim really was parsed and retained — otherwise this proves
        // nothing about a claim conferring nothing.
        #expect(claimed.selectedEntries.first?.trustedClaim != nil)
        #expect(plain.selectedEntries.first?.trustedClaim == nil)

        let claimedRequest = try #require(
            CenterHarness().center.request(BrewfilePlan(selecting: claimed.selectedEntries).commands)
        )
        let plainRequest = try #require(
            CenterHarness().center.request(BrewfilePlan(selecting: plain.selectedEntries).commands)
        )

        #expect(claimedRequest.disclosure == plainRequest.disclosure)
        #expect(claimedRequest.warningText == plainRequest.warningText)
        #expect(claimedRequest.disclosure == .tapAdd(TapName("acme/tap")!))

        // And nothing derived from the option reaches argv.
        #expect(claimedRequest.commands.map(\.arguments) == [["tap", "acme/tap"]])
        #expect(
            claimedRequest.commands.flatMap(\.arguments).contains { $0.contains("trusted") } == false
        )
    }

    // MARK: - PM9, BF1 — every name came through the shipped gate

    @Test("A refused name reaches no plan, no argv and no process")
    func aRefusedNameReachesNoPlanNoArgvNoProcess() async throws {
        let hostile = try Data(
            contentsOf: BrewfileFixtureManifest.root.appendingPathComponent("hostile-ruby.brewfile")
        )
        let diff = BrewfileDiff(
            document: try await BrewfileParser.decode(hostile),
            installed: .empty,
            taps: .empty
        )
        let plan = BrewfilePlan(selecting: diff.selectedEntries)

        // Only the one ordinary line survived, and it survived as an install.
        #expect(plan.commands.map(\.arguments) == [["install", "--formula", "ripgrep"]])

        // Every refusal is counted and named — not dropped.
        #expect(diff.skips.count == 13)

        // And none of the refused strings exists anywhere on the argv path.
        let argv = plan.commands.flatMap(\.arguments)
        for refused in ["--force", "wget; rm -rf /", "`id`", "$(id)", "#{ENV['HOME']}/x", "curl"] {
            #expect(argv.contains(refused) == false, "\(refused) reached argv")
        }

        let harness = CenterHarness()
        #expect(harness.center.request(plan.commands) == nil, "an install-only batch asked to confirm")
        for command in plan.commands { harness.center.submit(command) }
        try await harness.finish(call: 0)
        let spawned = harness.launcher.recordedSpecs.flatMap(\.arguments)
        for refused in ["--force", "wget; rm -rf /", "`id`", "$(id)"] {
            #expect(spawned.contains(refused) == false, "\(refused) was spawned")
        }
    }

    /// The construction surface, enumerated. There is no file-sourced
    /// convenience constructor and no "already validated" bypass, because the
    /// plan takes `BrewfileEntry` values whose identities are already typed.
    @Test("The plan accepts only already-constructed identities")
    func thePlanAcceptsOnlyAlreadyConstructedIdentities() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let plan = try #require(sources.first { $0.name == "BrewfilePlan.swift" })

        #expect(plan.code.contains("public init(selecting entries: [BrewfileEntry])"))
        for bypass in [
            "init(names:", "String)", "unvalidated", "PackageID(kind:", "rawValue:"
        ] {
            #expect(
                plan.code.contains(bypass) == false,
                "BrewfilePlan.swift offers a path around the typed identity: \(bypass)"
            )
        }
        // It cannot fail: there is no failable initialiser and nothing to throw.
        #expect(plan.code.contains("init?") == false)
        #expect(plan.code.containsIdentifier("throws") == false)
    }

    // MARK: - BF7 — no new family, no new domain

    @Test("The capability adds no mutating command family and no invalidation domain")
    func theCapabilityAddsNoMutatingCommandFamilyAndNoInvalidationDomain() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)

        for source in sources where source.name.hasPrefix("Brewfile") {
            #expect(
                source.code.contains(": BrewMutating") == false,
                "\(source.name) declares a new BrewMutating conformer"
            )
            #expect(
                source.code.contains("InvalidationScope(rawValue:") == false,
                "\(source.name) declares a new invalidation domain"
            )
        }

        // The four shipped domains, unchanged.
        #expect(InvalidationScope.installedInventory.rawValue == 1)
        #expect(InvalidationScope.services.rawValue == 2)
        #expect(InvalidationScope.taps.rawValue == 4)
        #expect(InvalidationScope.diskUsage.rawValue == 8)

        // And the plan's commands really are the shipped types, projected.
        let tap = TapCommand.addTap(TapName("acme/tap")!)
        let install = MutationCommand.install(PackageTarget(kind: .formula, name: "wget")!)
        #expect(AnyBrewMutation(tap).invalidates == .taps)
        #expect(AnyBrewMutation(install).invalidates == [.installedInventory, .diskUsage])
    }

    // MARK: - BF5 :115 — a qualified entry installs the bare token

    /// **D3.** Homebrew 6 treats naming a qualified package on the command line
    /// as a **per-package grant**, so forwarding a file's `brew
    /// "acme/tap/thing"` as argv would let the file's author grant trust on the
    /// importing user's Mac — exactly the delegation BF5 refuses.
    ///
    /// The line still parses as an ordinary entry and is still counted; what
    /// runs is `install --formula thing`. If `acme/tap` is untrusted brew
    /// refuses, and PM10's typed outcome offers the grant as an explicit answer.
    @Test("A qualified entry installs the bare token")
    func aQualifiedEntryInstallsTheBareToken() throws {
        let formula = try #require(FormulaID(name: "acme/tap/thing"))
        let cask = try #require(CaskID(name: "acme/tap/app"))
        let plan = BrewfilePlan(selecting: [
            BrewfileEntry(kind: .formula(formula), lineNumber: 1),
            BrewfileEntry(kind: .cask(cask), lineNumber: 2)
        ])

        #expect(plan.installs.map(\.arguments) == [
            ["install", "--formula", "thing"],
            ["install", "--cask", "app"]
        ])

        // The entry itself is unchanged: it parses, it keeps its qualified
        // identity for display and diffing, and no skip is counted for it.
        #expect(formula.name == "acme/tap/thing")
        #expect(cask.name == "acme/tap/app")

        // A degenerate qualified name whose last component is empty produces
        // **no** command rather than installing the component before it — which
        // would be the wrong package, silently.
        let degenerate = try #require(FormulaID(name: "acme/tap/"))
        let degeneratePlan = BrewfilePlan(selecting: [
            BrewfileEntry(kind: .formula(degenerate), lineNumber: 1)
        ])
        #expect(degeneratePlan.installs.isEmpty)
        #expect(degeneratePlan.isEmpty)

        // Positively anchored: an ordinary bare entry is untouched by all of
        // this, so the strip is about the qualifier and nothing else.
        let bare = try #require(FormulaID(name: "wget"))
        let barePlan = BrewfilePlan(selecting: [
            BrewfileEntry(kind: .formula(bare), lineNumber: 1)
        ])
        #expect(barePlan.installs.map(\.arguments) == [["install", "--formula", "wget"]])
    }
}
