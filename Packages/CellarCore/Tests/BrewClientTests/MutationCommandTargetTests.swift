import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// Command construction is validated at the type boundary, with **no bypass**
/// (package-mutation PM9, design D9).
///
/// M2-2 claimed "an unvalidated command is unrepresentable" while two app-target
/// call sites built package-naming cases straight from a raw `PackageID`. Fixing
/// those two sites would have left the third one to come, so the four bare cases
/// take a `PackageTarget` instead: the guard is now enforced by the type rather
/// than by remembering to use it.
///
/// Its own suite rather than more of `MutationCommandTests`, which is already
/// near SwiftLint's `type_body_length` limit.
@Suite("Mutation command target")
struct MutationCommandTargetTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let git = PackageID(kind: .formula, name: "git")
    private static let iterm = PackageID(kind: .cask, name: "iterm2")

    // MARK: - PM9 sc1–2 — threat: subprocess argument composition

    /// Empty, whitespace-only, and anything brew would read as an option.
    @Test(
        "An unsafe name yields no target at all",
        arguments: ["", " ", "\t", "   ", "-", "-rf", "--force", "--prefix", "wget curl", "a\nb"]
    )
    func unsafeNamesYieldNoTarget(name: String) {
        #expect(PackageTarget(PackageID(kind: .formula, name: name)) == nil)
        #expect(PackageTarget(PackageID(kind: .cask, name: name)) == nil)
        #expect(PackageTarget(kind: .formula, name: name) == nil)
    }

    /// The consequence that matters: with no target there is no command, so no
    /// argv containing the name is produced, nothing is enqueued, and nothing is
    /// spawned.
    @Test("An unsafe name produces no argv, enqueues nothing and spawns nothing")
    @MainActor
    func unsafeNamesReachNoQueue() async throws {
        let harness = CenterHarness()
        let hostile = PackageID(kind: .formula, name: "--force")

        #expect(PackageTarget(hostile) == nil)
        #expect(MutationCommand.naming(hostile, MutationCommand.install) == nil)
        #expect(MutationCommand.naming(hostile, MutationCommand.uninstall) == nil)
        #expect(MutationCommand.naming(hostile, MutationCommand.upgrade) == nil)
        #expect(MutationCommand.install(formula: "--force") == nil)

        // Nothing could be built, so nothing could be submitted.
        _ = harness.center.submitUpgrades(for: [hostile])
        await harness.settle()

        #expect(harness.center.items.isEmpty, "an unvalidated identity reached the queue")
        #expect(harness.launcher.launchCount == 0)
        #expect(harness.launcher.recordedSpecs.isEmpty)
    }

    @Test("A safe name yields a target that carries the identity unchanged")
    func safeNamesYieldATarget() throws {
        let target = try #require(PackageTarget(Self.wget))

        #expect(target.id == Self.wget)
        #expect(target.name == "wget")
        #expect(target.kind == .formula)
        #expect(PackageTarget(kind: .cask, name: "iterm2")?.id == Self.iterm)
        // Names brew genuinely publishes are not collateral damage.
        #expect(PackageTarget(kind: .formula, name: "gcc@11")?.name == "gcc@11")
        #expect(PackageTarget(kind: .formula, name: "font-fira-code") != nil)
    }

    // MARK: - PM9 sc3 — no construction path skips validation

    /// The structural half: every case that names a package names a *proven*
    /// one. A future verb added as `case something(PackageID)` fails here.
    @Test("No enum case in the vocabulary takes a bare PackageID")
    func noCaseTakesABarePackageID() throws {
        let source = try Self.vocabularySource()
        let cases = source
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("case ") }

        #expect(cases.isEmpty == false, "the vocabulary parsed to no cases at all")
        for declaration in cases {
            #expect(
                declaration.contains("(PackageID)") == false,
                "\(declaration) takes an unvalidated identity"
            )
        }
    }

    /// And the behavioural half: every public way to obtain a command applies
    /// the same rule, so there is no alternate constructor or convenience
    /// overload that skips it.
    @Test(
        "Every public construction path refuses the same unsafe name",
        arguments: ["", " ", "--force"]
    )
    func everyConstructionPathValidates(name: String) {
        let formula = PackageID(kind: .formula, name: name)
        let cask = PackageID(kind: .cask, name: name)

        #expect(PackageTarget(formula) == nil)
        #expect(FormulaID(formula) == nil)
        #expect(CaskID(cask) == nil)
        #expect(FormulaID(name: name) == nil)
        #expect(CaskID(name: name) == nil)
        #expect(MutationCommand.install(formula: name) == nil)
        #expect(MutationCommand.install(cask: name) == nil)
        #expect(MutationCommand.uninstall(formula: name) == nil)
        #expect(MutationCommand.uninstall(cask: name) == nil)
        #expect(MutationCommand.reinstall(formula: name) == nil)
        #expect(MutationCommand.upgrade(formula: name) == nil)
        #expect(MutationCommand.upgrade(cask: name) == nil)
        #expect(MutationCommand.zap(cask: name) == nil)
        #expect(MutationCommand.pin(formula: name) == nil)
        #expect(MutationCommand.unpin(formula: name) == nil)
        #expect(MutationCommand.naming(formula, MutationCommand.install) == nil)
        #expect(MutationCommand.naming(cask, MutationCommand.uninstall) == nil)
    }

    /// `isSafe` has exactly one definition, so the wrappers cannot drift apart.
    @Test("The safety rule is defined once and the wrappers are expressed over it")
    func theSafetyRuleIsDefinedOnce() throws {
        let source = try Self.vocabularySource()
        let definitions = source.components(separatedBy: "static func isSafe").count - 1

        #expect(definitions == 1, "the name-safety rule has \(definitions) definitions")
        // `FormulaID`/`CaskID` are kind wrappers over the same proven target.
        #expect(FormulaID(Self.wget)?.target == PackageTarget(Self.wget))
        #expect(CaskID(Self.iterm)?.target == PackageTarget(Self.iterm))
        #expect(FormulaID(Self.iterm) == nil, "a cask produced a FormulaID")
        #expect(CaskID(Self.wget) == nil, "a formula produced a CaskID")
    }

    // MARK: - Retyping has zero argv consequence

    /// The whole point of D9: this is a compile-time change. The four retyped
    /// cases lower to exactly the vectors M2-2 shipped.
    @Test("The four retyped cases keep their exact argv")
    func retypedCasesKeepTheirArgv() throws {
        let wget = try #require(PackageTarget(Self.wget))
        let git = try #require(PackageTarget(Self.git))
        let iterm = try #require(PackageTarget(Self.iterm))

        #expect(MutationCommand.install(wget).arguments == ["install", "--formula", "wget"])
        #expect(MutationCommand.uninstall(iterm).arguments == ["uninstall", "--cask", "iterm2"])
        #expect(MutationCommand.reinstall(git).arguments == ["reinstall", "--formula", "git"])
        #expect(MutationCommand.upgrade(wget).arguments == ["upgrade", "--formula", "wget"])
    }

    @Test("A retyped command still projects its package identity and display form")
    func retypedCasesKeepTheirProjections() throws {
        let iterm = try #require(PackageTarget(Self.iterm))
        let command = MutationCommand.uninstall(iterm)

        #expect(command.packageID == Self.iterm)
        #expect(command.displayCommand == "brew uninstall --cask iterm2")
        #expect(command.requiresConfirmation)
        #expect(command.brewCommand.kind == .mutate)
    }

    // MARK: -

    /// …/Tests/BrewClientTests/… → …/CellarCore/Sources/BrewClient/…
    private static func vocabularySource() throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/BrewClient/MutationCommand.swift"),
            encoding: .utf8
        )
    }
}
