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
                "zap", "upgradeAll", "pin", "unpin"
            ]
        )
        #expect(verbs.count == 8, "the package vocabulary changed size")
        #expect(Self.everyShippedCommand.map(\.verb) == verbs, "a case's verb drifted from its name")
        #expect(
            verbs.contains(probe.verb) == false,
            "the foreign command was absorbed as a case of the package command type"
        )
    }

    /// Every package command declares the installed set, and nothing else —
    /// so the scope is a real per-command declaration rather than a constant
    /// wearing a new name (PM6).
    @Test("Every package command declares the installed set and only that")
    func everyPackageCommandDeclaresTheInstalledSet() {
        for command in Self.everyShippedCommand {
            #expect(command.invalidates == .installedInventory, "\(command.verb) declared \(command.invalidates)")
        }
        #expect(ProbeMutation().invalidates == .services)
        #expect(InvalidationScope.services != InvalidationScope.installedInventory)
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
        #expect(erased.invalidates == .installedInventory)
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
            invalidates: .installedInventory
        )

        #expect(AnyBrewMutation(package) == AnyBrewMutation(impostor))
        #expect(AnyBrewMutation(package).arguments == ["upgrade"])
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
