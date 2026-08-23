import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The shared mutation spine, and the promise that a second family may enter it
/// without any package rule being loosened (design D1, package-mutation PM1).
///
/// PM1's "exactly six" is the load-bearing sentence: a non-package verb added as
/// a seventh case of `MutationCommand` would inherit a type whose identity, verb
/// and argv are package-shaped by construction. So this suite proves two things
/// at once — that a foreign command really does reach the queue, the log, the
/// outcome and the record, **and** that `MutationCommand` did not grow to let it.
@MainActor
@Suite("Brew mutating spine", .timeLimit(.minutes(1)))
struct BrewMutatingTests {

    // MARK: - PM1 sc6 — another family enters without becoming a case

    /// Every shipped case, mapped by a switch the **compiler** keeps exhaustive.
    ///
    /// This is the assertion PM1 actually needs. A ninth case — `serviceStart`,
    /// say — does not fail this test at runtime; it stops the suite compiling,
    /// which is the only guard that cannot be forgotten. The runtime half below
    /// then pins the vocabulary itself.
    private static func declaredVerb(of command: MutationCommand) -> String {
        switch command {
        case .install: "install"
        case .uninstall: "uninstall"
        case .reinstall: "reinstall"
        case .upgrade: "upgrade"
        case .zap: "zap"
        case .upgradeAll: "upgradeAll"
        case .update: "update"
        case .pin: "pin"
        case .unpin: "unpin"
        }
    }

    private static let everyShippedCommand: [MutationCommand] = [
        .install(PackageTarget(PackageID(kind: .formula, name: "wget"))!),
        .uninstall(PackageTarget(PackageID(kind: .formula, name: "wget"))!),
        .reinstall(PackageTarget(PackageID(kind: .formula, name: "git"))!),
        .upgrade(PackageTarget(PackageID(kind: .cask, name: "iterm2"))!),
        .zap(CaskID(PackageID(kind: .cask, name: "iterm2"))!),
        .upgradeAll,
        .update,
        .pin(FormulaID(PackageID(kind: .formula, name: "git"))!),
        .unpin(FormulaID(PackageID(kind: .formula, name: "git"))!)
    ]

    @Test("Another family enters the spine without becoming a case of the mutation command type")
    func anotherFamilyEntersTheSpineWithoutBecomingACaseOfTheMutationCommandType() async throws {
        let harness = CenterHarness()
        let probe = ProbeMutation()

        // It goes through the *same* submit as a package mutation — not through
        // a parallel entry point built for it.
        let item = harness.center.submit(probe)
        try await harness.finish(call: 0)

        // Projected: argv, verb, terminal outcome, and the record they earn.
        #expect(item.arguments == ["services", "start", "atuin"])
        #expect(item.displayCommand == "brew services start atuin")
        #expect(item.outcome == .succeeded)
        #expect(item.packageID == nil, "a non-package family was given a package identity")
        let draft = try #require(harness.recorder.drafts.first)
        #expect(draft.verb == "probeStart")
        #expect(draft.argv == ["services", "start", "atuin"])
        #expect(harness.launcher.recordedSpecs.first?.arguments == ["services", "start", "atuin"])

        // And `MutationCommand` still carries exactly the package vocabulary.
        let verbs = Self.everyShippedCommand.map(Self.declaredVerb)
        #expect(
            Set(verbs) == [
                "install", "uninstall", "reinstall", "upgrade",
                "zap", "upgradeAll", "update", "pin", "unpin"
            ]
        )
        #expect(verbs.count == 9, "the package vocabulary changed size")
        #expect(Self.everyShippedCommand.map(\.verb) == verbs, "a case's verb drifted from its name")
        #expect(
            verbs.contains(probe.verb) == false,
            "the foreign command was absorbed as a case of the package command type"
        )
    }

    /// Every package command declares the installed set and disk usage —
    /// so the scope is a real per-command declaration rather than a constant
    /// wearing a new name (PM6).
    @Test("Every package command declares installed inventory and disk usage")
    func everyPackageCommandDeclaresTheInstalledSet() {
        for command in Self.everyShippedCommand where command != .update {
            #expect(
                command.invalidates == [.installedInventory, .diskUsage],
                "\(command.verb) declared \(command.invalidates)"
            )
            #expect(command.diskAreas.isEmpty == false)
        }
        #expect(ProbeMutation().invalidates == .services)
        #expect(InvalidationScope.services != InvalidationScope.installedInventory)
    }

    /// `brew update` changes what brew *knows*, not what is installed on disk:
    /// the outdated set can move (which is the whole point of offering it), and
    /// tap revisions advance, but no keg or cask is touched. Declaring disk
    /// usage would force a remeasure that provably cannot observe a change.
    @Test("Update declares the installed inventory and taps, and no disk area")
    func updateDeclaresInventoryAndTapsOnly() {
        #expect(MutationCommand.update.invalidates == [.installedInventory, .taps])
        #expect(MutationCommand.update.diskAreas.isEmpty)
        #expect(MutationCommand.update.packageID == nil)
    }

    // MARK: - The erased value (D1)

    @Test("An erased mutation carries only projections and compares by value")
    func anErasedMutationCarriesOnlyProjectionsAndCompareByValue() throws {
        let install = MutationCommand.install(PackageTarget(PackageID(kind: .formula, name: "wget"))!)
        let sameInstall = MutationCommand.install(PackageTarget(PackageID(kind: .formula, name: "wget"))!)
        let otherInstall = MutationCommand.install(PackageTarget(PackageID(kind: .cask, name: "iterm2"))!)

        let erased = AnyBrewMutation(install)
        let equal = AnyBrewMutation(sameInstall)
        let different = AnyBrewMutation(otherInstall)
        let foreign = AnyBrewMutation(ProbeMutation())

        // Equality is restored, and it is equality of what will run.
        #expect(erased == equal)
        #expect(erased != different)
        #expect(erased != foreign)

        // Every projection survives erasure, verbatim.
        #expect(erased.arguments == ["install", "--formula", "wget"])
        #expect(erased.verb == "install")
        #expect(erased.packageID == PackageID(kind: .formula, name: "wget"))
        #expect(erased.requiresConfirmation == false)
        #expect(erased.invalidates == [.installedInventory, .diskUsage])
        #expect(erased.diskAreas == [.cellar])
        #expect(erased.displayCommand == "brew install --formula wget")
        let destructive = MutationCommand.uninstall(PackageTarget(PackageID(kind: .cask, name: "iterm2"))!)
        #expect(AnyBrewMutation(destructive).requiresConfirmation)

        // And **nothing** can be parsed back out of it: there is no case
        // payload to recover, so the erased value cannot be widened into a
        // command that runs something other than the argv it carries. This
        // strengthens the shipped "nothing is parsed back out of a command"
        // property rather than weakening it.
        let source = try Self.source(of: "BrewMutating.swift")
        for recovery in [
            "as? MutationCommand", "as! MutationCommand", "func unwrap", "var wrapped",
            "var base", "init(displayCommand", "components(separatedBy:", "split(separator:"
        ] {
            #expect(
                source.contains(recovery) == false,
                "\(recovery) appeared in the erased value — a path back to a concrete command leaked in"
            )
        }
        #expect(source.contains("public struct AnyBrewMutation"), "the scan ran against the wrong file")
    }

    /// Round-tripping is impossible behaviourally too: two different commands
    /// that would run the same argv erase to the same value, so the erasure
    /// cannot be a hidden channel back to a specific case.
    @Test("Erasure keeps what runs and forgets which type produced it")
    func erasureForgetsTheProducingType() {
        let package = MutationCommand.upgradeAll
        let impostor = ProbeMutation(
            arguments: ["upgrade"],
            verb: "upgradeAll",
            packageID: nil,
            requiresConfirmation: false,
            invalidates: [.installedInventory, .diskUsage],
            diskAreas: package.diskAreas
        )

        #expect(AnyBrewMutation(package) == AnyBrewMutation(impostor))
        #expect(AnyBrewMutation(package).arguments == ["upgrade"])
    }

    // MARK: - DD1 guard — the equality contract the spine change moves (PM1)

    /// Characterisation, written **before** `AnyBrewMutation` gains an eighth
    /// projection, so the blast radius of adding one is measured rather than
    /// discovered.
    ///
    /// The erased value is `Equatable` and `Hashable`, and three shipped rules
    /// rest on that and on nothing else:
    ///
    /// 1. Two erased values are equal **iff** every projection matches — which
    ///    is why adding a projection is a semantic change to equality, not a
    ///    field addition.
    /// 2. `ConfirmationRequest ==` is what gates `confirm` and `decline`
    ///    (`OperationCenterBulk.swift:151,158`), and that equality is structural
    ///    over the erased commands the request carries.
    /// 3. `ActivityItem.command.verb` — a projection, read through the erasure —
    ///    is what drives the app's zap retitle
    ///    (`cellar/Activity/MutationConfirmation.swift:230`).
    ///
    /// After DD1 lands, this suite extends rather than moves: two commands
    /// differing **only** in `disclosure` must be unequal and must hash apart.
    /// Stating it here is the point — the alternative is discovering it as an
    /// unexplained `ConfirmationBacklogTests` failure four phases later.
    @Test("Erased equality is projection-by-projection, and hashing agrees with it")
    func erasedEqualityIsProjectionByProjectionAndHashingAgreesWithIt() {
        let base = ProbeMutation()

        // Identical projections, produced independently: equal, and hashed alike.
        #expect(AnyBrewMutation(base) == AnyBrewMutation(ProbeMutation()))
        #expect(AnyBrewMutation(base).hashValue == AnyBrewMutation(ProbeMutation()).hashValue)

        // One projection at a time. Every one of them separates the values,
        // which is what "equality of what will run" means concretely.
        var byArguments = base
        byArguments.arguments = ["services", "stop", "atuin"]
        var byVerb = base
        byVerb.verb = "probeStop"
        var byPackage = base
        byPackage.packageID = PackageID(kind: .formula, name: "wget")
        var byConfirmation = base
        byConfirmation.requiresConfirmation = true
        var byScope = base
        byScope.invalidates = .installedInventory
        var byDiskAreas = base
        byDiskAreas.diskAreas = [.cellar]
        var byOverrides = base
        byOverrides.environmentOverrides = [.noAutoremove]

        let divergent: [(String, ProbeMutation)] = [
            ("arguments", byArguments),
            ("verb", byVerb),
            ("packageID", byPackage),
            ("requiresConfirmation", byConfirmation),
            ("invalidates", byScope),
            ("diskAreas", byDiskAreas),
            ("environmentOverrides", byOverrides)
        ]
        #expect(divergent.count == 7, "the projection count changed — DD1's blast radius moved")

        for (name, variant) in divergent {
            #expect(
                AnyBrewMutation(base) != AnyBrewMutation(variant),
                "\(name) stopped separating two erased values"
            )
            #expect(
                AnyBrewMutation(base).hashValue != AnyBrewMutation(variant).hashValue,
                "\(name) is not hashed, so equality and hashing disagree"
            )
        }
    }

    /// A conformer that declares a disclosure of its own, so the projection can
    /// be varied **alone**. `ProbeMutation` deliberately declares none — its job
    /// is to prove the protocol default is real — so it cannot serve here.
    private struct DisclosingProbe: BrewMutating {
        var arguments = ["tap", "acme/tap"]
        var verb = "tapAdd"
        var packageID: PackageID?
        var requiresConfirmation = true
        var invalidates: InvalidationScope = .taps
        /// The **declaration**, not the presentation. A probe that varied
        /// `disclosure` directly could no longer tell "declares nothing" from
        /// "shows the ordinary removal text", which is the distinction the batch
        /// rule rests on (design DD-3).
        var declaredDisclosure: ConfirmationDisclosure? = .packageRemoval
    }

    /// The guard above, extended deliberately once DD1 landed.
    ///
    /// Adding an eighth projection widened equality: two commands that run the
    /// identical argv and differ **only** in what they warn about are no longer
    /// the same erased value. That is a consequence worth stating out loud —
    /// the alternative was meeting it as an unexplained failure in
    /// `ConfirmationBacklogTests`, four phases from here, with nothing pointing
    /// back at this change.
    @Test("Two commands differing only in disclosure are unequal and hash apart")
    func twoCommandsDifferingOnlyInDisclosureAreUnequalAndHashApart() throws {
        let tap = try #require(TapName("acme/tap"))
        let plain = DisclosingProbe()
        var warning = plain
        warning.declaredDisclosure = .tapAdd(tap)

        // Same argv, same verb, same scope, same everything else.
        #expect(plain.arguments == warning.arguments)
        #expect(plain.verb == warning.verb)
        #expect(plain.invalidates == warning.invalidates)

        #expect(AnyBrewMutation(plain) != AnyBrewMutation(warning))
        #expect(AnyBrewMutation(plain).hashValue != AnyBrewMutation(warning).hashValue)
        #expect(Set([AnyBrewMutation(plain), AnyBrewMutation(warning)]).count == 2)

        // And it is still equality *of what will run plus what it warns about*:
        // two independently built values that agree on both are the same value.
        #expect(AnyBrewMutation(warning) == AnyBrewMutation(DisclosingProbe(declaredDisclosure: .tapAdd(tap))))
    }

    /// `confirm` and `decline` are gated by `pendingConfirmation == request`,
    /// so a request that is *value-equal* is accepted and one that is not is
    /// silently refused. Erased-command equality is therefore load-bearing for
    /// the destructive gate itself, not only for presentation.
    @Test("Confirmation identity is what gates confirm and decline")
    func confirmationIdentityIsWhatGatesConfirmAndDecline() async throws {
        let harness = CenterHarness()
        let tap = try #require(TapName("acme/tap"))
        let pending = try #require(harness.center.request(TapCommand.addTap(tap)))

        // A request carrying the same command but a different identity is not
        // the pending one: both gates refuse it and nothing is spawned.
        let impostor = OperationCenter.ConfirmationRequest(
            id: UUID(),
            command: pending.command,
            additional: pending.additional,
            disclosure: pending.disclosure
        )
        #expect(impostor != pending)
        #expect(harness.center.confirm(impostor).isEmpty)
        harness.center.decline(impostor)
        #expect(harness.center.pendingConfirmation == pending, "an impostor consumed the gate")
        #expect(harness.launcher.launchCount == 0)

        // The pending one, by value, submits every command it listed.
        let items = harness.center.confirm(pending)
        #expect(items.count == 1)
        #expect(items.first?.arguments == ["tap", "acme/tap"])
        #expect(harness.center.pendingConfirmation == nil)
        try await harness.finish(call: 0)
    }

    /// The zap retitle reads `command.verb` through the erasure. That is a
    /// *presentation* read of a verb, explicitly permitted, and it is not a
    /// disclosure path — which is the distinction DD1's structural test relies
    /// on.
    @Test("The zap retitle reads a verb through the erasure, and only zap carries it")
    func theZapRetitleReadsAVerbThroughTheErasure() throws {
        let harness = CenterHarness()
        let cask = try #require(CaskID(PackageID(kind: .cask, name: "iterm2")))
        let request = try #require(harness.center.request(MutationCommand.zap(cask)))

        #expect(request.command.verb == "zap", "the projection the app's isZap reads changed")
        #expect(request.commands.map(\.verb) == ["zap"])
        #expect(
            Self.everyShippedCommand.filter { $0.verb == "zap" }.count == 1,
            "a second command started answering to the zap verb"
        )
        #expect(request.disclosure == .packageRemoval)
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
