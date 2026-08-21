import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// The four service verbs and the argv they lower to (design D9 —
/// service-management SM4, SM5).
///
/// This is the threat response for **subprocess argument composition** on the
/// second command family. Every guarantee `MutationCommandTests` makes for
/// packages is remade here for services, because a family that entered the spine
/// without them would have made the spine's promise false rather than shared.
///
/// The strongest of them is structural: **`--all` is unrepresentable**. No case
/// omits a target, so there is no value of this type whose argv acts on more
/// than one service — which is the answer to the `upgradeAll` trap rather than a
/// rule somebody has to remember not to break.
@Suite("Service command argv")
struct ServiceCommandTests {
    private static func target(_ name: String) throws -> ServiceTarget {
        try #require(ServiceTarget(name: name))
    }

    // MARK: - Construction (threat matrix — subprocess argument composition)

    /// Rejected **at construction**, so no argv is ever built from a hostile
    /// name — not built and then filtered, which would leave a window in which
    /// the vector existed.
    ///
    /// `--all` is in this list deliberately: a service literally named `--all`
    /// would otherwise widen a single-service verb into every service, which is
    /// the one composition mistake that could destroy state the user did not ask
    /// about. It is refused for the ordinary reason — it begins with `-`.
    @Test(
        "An unsafe service name is rejected at construction and builds no argv",
        arguments: ["", "-", "-rf", "--all", "--json", " ", "\t", "atuin redis", "atuin\nrm", "a;rm -rf /"]
    )
    func anUnsafeServiceNameIsRejectedAtConstructionAndBuildsNoArgv(name: String) {
        #expect(ServiceTarget(name: name) == nil, "\(name) survived the gate")
        #expect(ServiceCommand.start(service: name) == nil)
        #expect(ServiceCommand.run(service: name) == nil)
        #expect(ServiceCommand.stop(service: name) == nil)
        #expect(ServiceCommand.restart(service: name) == nil)
    }

    /// Shell metacharacters are **not** rejected, and that is the correct
    /// behaviour rather than a gap.
    ///
    /// The tasks list expected `$(…)` and `;` to be refused at construction.
    /// They are not, because `MutationName.isSafe` refuses exactly "empty,
    /// leading `-`, or containing whitespace" and `package-mutation` PM9 is
    /// explicitly untouched by this slice — widening the shared gate would
    /// change package construction rules the delta says stay where they are.
    ///
    /// The guarantee that actually matters is the one the threat matrix names:
    /// **argv is a vector, never a string**. A name containing `$(…)` reaches
    /// `Process.arguments` as one literal element, no shell is ever involved, and
    /// brew answers "no such service". So this asserts the real property — the
    /// hostile text survives *intact and alone* through the process seam — rather
    /// than asserting a rejection that would be security theatre.
    @Test(
        "A name carrying shell metacharacters reaches the process seam as one literal element",
        arguments: ["$(whoami)", "atuin;rm", "`id`", "a|b", "a&b", "a>b"]
    )
    func shellMetacharactersSurviveAsOneLiteralArgument(name: String) async throws {
        let command = try #require(ServiceCommand.stop(service: name))

        // One element, not two, and not expanded.
        #expect(command.arguments == ["services", "stop", name])
        #expect(command.arguments.count == 3)

        // And that is exactly what the process seam is handed.
        let launcher = RecordingProcessLauncher()
        let runner = BrewRunner(installation: TestInstallation.appleSilicon, launcher: launcher)
        let operation = try await runner.start(command.brewCommand)
        _ = await operation.exit()

        let spec = try #require(launcher.specs.first)
        #expect(spec.arguments == ["services", "stop", name])
        #expect(spec.arguments.last == name, "the name was split, quoted or expanded on the way")
    }

    /// The names brew actually publishes are not refused. Without this the test
    /// above would pass just as well against a gate that rejected everything.
    @Test(
        "Legitimate service names are accepted and lower normally",
        arguments: ["atuin", "postgresql@16", "redis", "unbound", "php@8.3", "mysql-client"]
    )
    func legitimateServiceNamesAreAccepted(name: String) throws {
        let command = try #require(ServiceCommand.start(service: name))
        #expect(command.arguments == ["services", "start", name])
    }

    // MARK: - SM4 sc1–sc3 — the exact vectors

    @Test("Each verb produces its exact argv")
    func eachVerbProducesItsExactArgv() throws {
        let atuin = try Self.target("atuin")

        #expect(ServiceCommand.start(atuin).arguments == ["services", "start", "atuin"])
        #expect(ServiceCommand.stop(atuin).arguments == ["services", "stop", "atuin"])
        #expect(ServiceCommand.restart(atuin).arguments == ["services", "restart", "atuin"])
        #expect(ServiceCommand.run(atuin).arguments == ["services", "run", "atuin"])

        // The name is the last element, and its own element — never interpolated
        // into one of the literals ahead of it.
        for command in ServiceCommand.allVerbs(for: atuin) {
            #expect(command.arguments.count == 3)
            #expect(command.arguments.last == "atuin")
            #expect(command.arguments.first == "services")
        }
    }

    @Test("No service argv ever contains --all")
    func noServiceArgvEverContainsAll() throws {
        let names = ["atuin", "postgresql", "redis"]
        let commands = try names.flatMap { ServiceCommand.allVerbs(for: try Self.target($0)) }

        #expect(commands.count == 12, "the enumeration did not cover four verbs over three services")
        for command in commands {
            #expect(command.arguments.contains("--all") == false)
            // And none names more than one service: exactly one of the three
            // names appears in each vector.
            #expect(command.arguments.count(where: names.contains) == 1)
        }
    }

    /// `kill` and `stop --keep` are out, with the reason recorded: both mean
    /// "stop but stay registered", which has no PRD surface and would make the
    /// start-vs-run login-item distinction incoherent to explain.
    ///
    /// Asserted over the whole enumerable surface rather than as an unwritten
    /// omission — `allCases` is what makes "exactly four" a claim about the type.
    @Test("kill and stop --keep are not offered")
    func killAndStopKeepAreNotOffered() throws {
        let atuin = try Self.target("atuin")
        let verbs = ServiceCommand.allVerbs(for: atuin)

        #expect(Set(verbs.map { $0.arguments[1] }) == ["start", "stop", "restart", "run"])
        #expect(verbs.count == 4)
        for command in verbs {
            #expect(command.arguments.contains("kill") == false)
            #expect(command.arguments.contains("--keep") == false)
        }
    }

    // MARK: - SM5 sc2 — the row surface is enumerable, so no default can hide

    /// "Neither action is a hidden default" is a claim about the **whole**
    /// surface, so it is asserted over an `allCases` list rather than by the
    /// absence of some other control nobody wrote. The `ActivityItem.Control` /
    /// `HistoryRecord.Control` idiom (ruling #7182-3).
    @Test("The row control surface is exactly the five enumerated controls")
    func theRowControlSurfaceIsExactlyTheFiveEnumeratedControls() {
        #expect(
            ServiceRowControl.allCases == [.start, .run, .stop, .restart, .copyCommand]
        )

        // Start and run are separately invocable, and neither is derived from
        // the other by adding or removing an argument (SM5 sc1).
        #expect(ServiceRowControl.start != ServiceRowControl.run)
        #expect(ServiceRowControl.allCases.count(where: { $0.isLoginRegistering }) == 1)
        #expect(ServiceRowControl.start.isLoginRegistering)
        #expect(ServiceRowControl.run.isLoginRegistering == false)

        // Every label states which of the two it does, in words, so the
        // difference is legible without a tooltip.
        #expect(ServiceRowControl.start.label.lowercased().contains("login"))
        #expect(ServiceRowControl.run.label.lowercased().contains("once"))
        #expect(Set(ServiceRowControl.allCases.map(\.label)).count == 5, "two controls share a label")
    }

    @Test("The two actions submit different commands, neither derived from the other")
    func theTwoActionsSubmitDifferentCommands() throws {
        let atuin = try Self.target("atuin")
        let start = try #require(ServiceRowControl.start.command(for: atuin))
        let run = try #require(ServiceRowControl.run.command(for: atuin))

        #expect(start.arguments == ["services", "start", "atuin"])
        #expect(run.arguments == ["services", "run", "atuin"])
        // Not one verb with a flag: the vectors are the same length and differ
        // in exactly the verb token.
        #expect(start.arguments.count == run.arguments.count)
        #expect(zip(start.arguments, run.arguments).count { $0 != $1 } == 1)

        // Copy-command is not a submission at all.
        #expect(ServiceRowControl.copyCommand.command(for: atuin) == nil)
    }

    // MARK: - The spine's projections (D9)

    @Test("Every verb declares services only, needs no confirmation and names no package")
    func everyVerbDeclaresItsProjections() throws {
        for command in ServiceCommand.allVerbs(for: try Self.target("atuin")) {
            #expect(command.invalidates == .services)
            #expect(command.invalidates.contains(.installedInventory) == false)
            #expect(command.packageID == nil, "a service was modelled as a package (SM12)")
            #expect(
                command.requiresConfirmation == false,
                "\(command.verb) asked for confirmation — none of the four destroys anything"
            )
            #expect(command.brewCommand.kind == .mutate)
            #expect(command.displayCommand == "brew " + command.arguments.joined(separator: " "))
        }
    }

    /// The verbs are namespaced, so a history search for a package verb cannot
    /// collide with a service one (design D9, installation-history IH5).
    @Test("Each verb records under its own namespaced name")
    func eachVerbRecordsUnderItsOwnName() throws {
        let atuin = try Self.target("atuin")
        let verbs = ServiceCommand.allVerbs(for: atuin).map(\.verb)

        #expect(verbs == ["serviceStart", "serviceRun", "serviceStop", "serviceRestart"])
        #expect(Set(verbs).count == 4, "two verbs record under the same name")
        // And none collides with a package verb.
        let packageVerbs = [
            "install", "uninstall", "reinstall", "upgrade",
            "zap", "upgradeAll", "update", "pin", "unpin"
        ]
        #expect(Set(verbs).isDisjoint(with: packageVerbs))
    }
}
