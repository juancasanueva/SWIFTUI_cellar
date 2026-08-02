import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The typed mutation vocabulary and the argv it lowers to.
///
/// This suite is the threat response for **subprocess argument composition**
/// (design D1, D2). Every assertion is about the exact vector, because a
/// mutation is the one place in Cellar where getting an argument wrong destroys
/// something. Nothing here spawns `brew` (D12): the one test that proves argv
/// survives the process seam records the `ProcessSpec` instead.
@Suite("Mutation command argv")
struct MutationCommandTests {
    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let git = PackageID(kind: .formula, name: "git")
    private static let iterm = PackageID(kind: .cask, name: "iterm2")

    // MARK: - Exact vectors (PM1 sc1–sc4, PM2 sc1, sc3)

    /// One case per shipped scenario, asserted as a whole vector rather than as
    /// "contains": a spurious extra argument is exactly the failure mode that
    /// matters, and `contains` would not see it.
    struct ArgvCase: Sendable, CustomTestStringConvertible {
        let command: MutationCommand
        let argv: [String]

        var testDescription: String { argv.joined(separator: " ") }
    }

    static let argvCases: [ArgvCase] = [
        ArgvCase(command: .install(wget), argv: ["install", "--formula", "wget"]),
        ArgvCase(command: .install(iterm), argv: ["install", "--cask", "iterm2"]),
        ArgvCase(command: .uninstall(iterm), argv: ["uninstall", "--cask", "iterm2"]),
        ArgvCase(command: .uninstall(wget), argv: ["uninstall", "--formula", "wget"]),
        ArgvCase(command: .reinstall(git), argv: ["reinstall", "--formula", "git"]),
        ArgvCase(command: .upgrade(wget), argv: ["upgrade", "--formula", "wget"]),
        ArgvCase(command: .upgrade(iterm), argv: ["upgrade", "--cask", "iterm2"]),
        ArgvCase(
            command: .zap(CaskID(iterm)!),
            argv: ["uninstall", "--cask", "--zap", "iterm2"]
        ),
        ArgvCase(command: .pin(FormulaID(git)!), argv: ["pin", "--formula", "git"]),
        ArgvCase(command: .unpin(FormulaID(git)!), argv: ["unpin", "--formula", "git"]),
        ArgvCase(command: .upgradeAll, argv: ["upgrade"])
    ]

    @Test("Every command lowers to exactly its documented vector", arguments: argvCases)
    func everyCommandLowersToItsVector(testCase: ArgvCase) {
        #expect(testCase.command.arguments == testCase.argv)
    }

    @Test("Every mutation is serialized as a mutation", arguments: argvCases)
    func everyCommandIsAMutation(testCase: ArgvCase) {
        #expect(testCase.command.brewCommand.kind == .mutate)
        #expect(testCase.command.brewCommand.arguments == testCase.argv)
    }

    /// A token existing in both namespaces resolves by flag, never by brew's own
    /// disambiguation (PM1 sc5). `docker` is the live example.
    @Test("A token in both namespaces is disambiguated by the flag, never by brew")
    func bothNamespaceTokensAreDisambiguatedByFlag() {
        let cask = MutationCommand.install(PackageID(kind: .cask, name: "docker"))
        let formula = MutationCommand.install(PackageID(kind: .formula, name: "docker"))

        #expect(cask.arguments == ["install", "--cask", "docker"])
        #expect(formula.arguments == ["install", "--formula", "docker"])
        #expect(cask.arguments.contains("--formula") == false)
        #expect(formula.arguments.contains("--cask") == false)
    }

    @Test("No invocation ever carries both kind flags", arguments: argvCases)
    func noInvocationCarriesBothKindFlags(testCase: ArgvCase) {
        let argv = testCase.command.arguments
        #expect(!(argv.contains("--formula") && argv.contains("--cask")))
    }

    /// `upgradeAll` is the deliberate exception, and the only one: product Q3
    /// defines it as literally `brew upgrade` with brew's own defaults, so
    /// anything that defeats those defaults must be absent (PM2 sc3).
    @Test("Upgrade all is a bare brew upgrade with nothing added")
    func upgradeAllIsBare() {
        let argv = MutationCommand.upgradeAll.arguments

        #expect(argv == ["upgrade"])
        for forbidden in [
            "--formula", "--cask", "--greedy", "--greedy-latest",
            "--greedy-auto-updates", "--force", "wget", "iterm2"
        ] {
            #expect(argv.contains(forbidden) == false, "upgradeAll carried \(forbidden)")
        }
    }

    /// Every command that *names* a package carries its kind flag. Stated as a
    /// property over the whole vocabulary rather than per case, so a seventh
    /// verb added later cannot quietly skip it.
    @Test("Every package-naming command carries exactly one kind flag", arguments: argvCases)
    func everyPackageNamingCommandCarriesAKindFlag(testCase: ArgvCase) {
        let argv = testCase.command.arguments
        let flags = argv.count { $0 == "--formula" || $0 == "--cask" }

        if testCase.command.packageID == nil {
            #expect(flags == 0, "a command naming no package carried a kind flag")
        } else {
            #expect(flags == 1, "a package-naming command did not carry exactly one kind flag")
        }
    }

    /// The argv inspected before submission is the argv spawned (PM1). Proven
    /// through the process seam rather than asserted twice off the same array.
    @Test("The argv that reaches the process seam is the argv that was inspected")
    func spawnedArgvMatchesTheInspectedArgv() async throws {
        let command = MutationCommand.uninstall(Self.iterm)
        let launcher = RecordingProcessLauncher()
        let runner = BrewRunner(installation: TestInstallation.appleSilicon, launcher: launcher)

        let operation = try await runner.start(command.brewCommand)
        _ = await operation.exit()

        let spec = try #require(launcher.specs.first)
        #expect(spec.arguments == command.arguments)
        #expect(spec.arguments == ["uninstall", "--cask", "iterm2"])
        #expect(spec.executableURL == TestInstallation.appleSilicon.executableURL)
    }

    // MARK: - Argv hardening (D2 — threat: option injection)

    /// The one place option injection could enter, so it is refused at the type
    /// boundary and no argv is ever built from it.
    @Test(
        "A name that is empty or option-looking is refused at construction",
        arguments: ["", "-rf", "--prefix", "-", " ", "\t", "wget curl", "wget\nrm"]
    )
    func hostileNamesAreRefusedAtConstruction(name: String) {
        #expect(MutationCommand.install(formula: name) == nil)
        #expect(MutationCommand.install(cask: name) == nil)
        #expect(MutationCommand.uninstall(formula: name) == nil)
        #expect(MutationCommand.upgrade(formula: name) == nil)
        #expect(FormulaID(name: name) == nil)
        #expect(CaskID(name: name) == nil)
    }

    @Test("An ordinary name is accepted and lowers normally")
    func ordinaryNamesAreAccepted() throws {
        let install = try #require(MutationCommand.install(formula: "wget"))
        let zap = try #require(MutationCommand.zap(cask: "iterm2"))

        #expect(install.arguments == ["install", "--formula", "wget"])
        #expect(zap.arguments == ["uninstall", "--cask", "--zap", "iterm2"])
    }

    /// Names brew itself publishes that look unusual but are legitimate. The
    /// rejection rule is "empty or leading `-`", not "alphanumeric only".
    @Test(
        "Legitimate but unusual brew names are not refused",
        arguments: ["gcc@11", "python@3.12", "libpq", "font-fira-code", "ruby-build", "openssl@3"]
    )
    func legitimateNamesAreAccepted(name: String) {
        #expect(MutationCommand.install(formula: name)?.arguments
            == ["install", "--formula", name])
    }

    /// `zap` for a formula and `pin` for a cask are **unrepresentable**, not
    /// rejected at runtime: the failable wrapper is the proof (threat:
    /// irreversible mutation scope).
    @Test("Zap is unrepresentable for a formula and pin for a cask")
    func wrongKindWrappersAreUnrepresentable() {
        #expect(CaskID(Self.wget) == nil, "a formula produced a CaskID")
        #expect(FormulaID(Self.iterm) == nil, "a cask produced a FormulaID")

        #expect(CaskID(Self.iterm) != nil)
        #expect(FormulaID(Self.git) != nil)

        #expect(MutationCommand.zap(cask: "wget") != nil, "the wrapper is about kind, not name")
        #expect(MutationCommand.pin(formula: "iterm2") != nil)
    }

    // MARK: - Confirmation and display (D6 — PM3 sc1, sc3, sc4; OA2 sc1)

    @Test("Exactly uninstall and zap require confirmation", arguments: argvCases)
    func onlyDestructiveCommandsRequireConfirmation(testCase: ArgvCase) {
        let isDestructive = switch testCase.command {
        case .uninstall, .zap: true
        default: false
        }

        #expect(testCase.command.requiresConfirmation == isDestructive)
    }

    @Test("Install, reinstall, upgrade, upgrade-all, pin and unpin never confirm")
    func nonDestructiveCommandsNeverConfirm() {
        let safe: [MutationCommand] = [
            .install(Self.wget), .reinstall(Self.git), .upgrade(Self.iterm),
            .upgradeAll, .pin(FormulaID(Self.git)!), .unpin(FormulaID(Self.git)!)
        ]

        #expect(safe.allSatisfy { $0.requiresConfirmation == false })
    }

    /// The display string is the argv, character for character, prefixed by the
    /// executable's own name. Nothing is added, reordered or dropped.
    @Test("The display command matches the argv character for character", arguments: argvCases)
    func displayCommandMatchesTheArgv(testCase: ArgvCase) {
        #expect(
            testCase.command.displayCommand
                == "brew " + testCase.command.arguments.joined(separator: " ")
        )
    }

    @Test("The display command is stable and pasteable for the destructive cases")
    func displayCommandForTheDestructiveCases() {
        #expect(
            MutationCommand.uninstall(Self.wget).displayCommand
                == "brew uninstall --formula wget"
        )
        #expect(
            MutationCommand.zap(CaskID(Self.iterm)!).displayCommand
                == "brew uninstall --cask --zap iterm2"
        )
    }

    // MARK: - The display string is never a source of argv (threat matrix)

    /// `displayCommand` is one-way. There is no factory, initialiser or parser
    /// anywhere in the vocabulary that takes a command *string* and produces
    /// argv — the only producer is `arguments` over the typed cases, so a
    /// rendered string can never change what runs.
    @Test("No public API turns a command string back into argv")
    func noStringIsEverParsedBackIntoArgv() throws {
        // …/Tests/BrewClientTests/MutationCommandTests.swift → …/CellarCore.
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot
                .appendingPathComponent("Sources/BrewClient/MutationCommand.swift"),
            encoding: .utf8
        )

        // The rendered string is produced here and consumed nowhere.
        #expect(source.contains("displayCommand"))
        for parser in [
            "components(separatedBy:", "split(separator:", "hasPrefix(\"brew",
            "init(displayCommand", "init(command:", "parse("
        ] {
            #expect(
                source.contains(parser) == false,
                "\(parser) appeared in the vocabulary — a string→argv path may have leaked in"
            )
        }
    }

    /// And the structural claim, checked behaviourally: round-tripping a display
    /// string is impossible because the only way to build a command is from a
    /// typed `PackageID`, which a string cannot become without a parser.
    @Test("Argv is only ever produced from typed cases")
    func argvIsOnlyProducedFromTypedCases() {
        let rendered = MutationCommand.uninstall(Self.iterm).displayCommand
        #expect(rendered == "brew uninstall --cask iterm2")

        // The rendered form carries the kind as a flag, and the only way back to
        // a command is to name the kind again in the type system.
        let rebuilt = MutationCommand.uninstall(PackageID(kind: .cask, name: "iterm2"))
        #expect(rebuilt.displayCommand == rendered)
        #expect(rebuilt.arguments == ["uninstall", "--cask", "iterm2"])
    }
}
