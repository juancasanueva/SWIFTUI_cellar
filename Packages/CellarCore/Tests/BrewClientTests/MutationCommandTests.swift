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
        ArgvCase(command: .install(PackageTarget(wget)!), argv: ["install", "--formula", "wget"]),
        ArgvCase(command: .install(PackageTarget(iterm)!), argv: ["install", "--cask", "iterm2"]),
        ArgvCase(command: .uninstall(PackageTarget(iterm)!), argv: ["uninstall", "--cask", "iterm2"]),
        ArgvCase(command: .uninstall(PackageTarget(wget)!), argv: ["uninstall", "--formula", "wget"]),
        ArgvCase(command: .reinstall(PackageTarget(git)!), argv: ["reinstall", "--formula", "git"]),
        ArgvCase(command: .upgrade(PackageTarget(wget)!), argv: ["upgrade", "--formula", "wget"]),
        ArgvCase(command: .upgrade(PackageTarget(iterm)!), argv: ["upgrade", "--cask", "iterm2"]),
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
        let cask = MutationCommand.install(PackageTarget(PackageID(kind: .cask, name: "docker"))!)
        let formula = MutationCommand.install(PackageTarget(PackageID(kind: .formula, name: "docker"))!)

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
        let command = MutationCommand.uninstall(PackageTarget(Self.iterm)!)
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
            .install(PackageTarget(Self.wget)!),
            .reinstall(PackageTarget(Self.git)!),
            .upgrade(PackageTarget(Self.iterm)!),
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
            MutationCommand.uninstall(PackageTarget(Self.wget)!).displayCommand
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

    // MARK: - The rule every command family inherits (design D1, threat matrix)

    /// The structural rule the shared spine rests on:
    ///
    /// > A conformer's `arguments` may contain only literal verb/flag enum raw
    /// > values plus tokens taken from a validated wrapper.
    ///
    /// Scanned over **every** `*Command.swift` in `BrewClient`, not just this
    /// one, so a family added later is covered the day its file lands rather
    /// than the day somebody remembers to widen a list.
    ///
    /// **Anchored positively first** (the M3-0 task 8.1 lesson): a glob that
    /// silently matched nothing would make every forbidden-token expectation
    /// below pass vacuously, which is the exact failure mode this idiom exists
    /// to avoid. So the file set is asserted to be non-empty, to contain the
    /// file we know is there, and each member is asserted to actually declare
    /// the property being scanned.
    @Test("Every command family builds argv from literals and validated wrappers only")
    func everyCommandFamilyBuildsArgvStructurally() throws {
        let files = try Self.commandFiles()

        #expect(files.isEmpty == false, "the *Command.swift scan matched no files at all")
        #expect(
            files.keys.contains("MutationCommand.swift"),
            "the scan did not find the file it is known to cover — the glob is wrong"
        )

        for (name, source) in files {
            // Positive anchor, per file: it really does lower to an argv vector.
            let body = try #require(
                Self.argumentsBody(of: source),
                "\(name) declares no `var arguments: [String]` to scan"
            )
            #expect(body.contains("["), "\(name)'s arguments body builds no vector")

            // The rule, as forbidden constructs. Each one is a way a token
            // could enter argv without passing the validated wrapper.
            for construct in ["\\(", "joined(", "components(separatedBy:", "split(", "+ \" \""] {
                #expect(
                    body.contains(construct) == false,
                    "\(name) composes argv with \(construct) — a token may bypass the name gate"
                )
            }

            // And the names it does place in argv come through the single gate.
            guard Self.namesNothing.contains(name) else {
                #expect(
                    source.contains("MutationName.isSafe"),
                    "\(name) does not route its names through the one `isSafe` gate"
                )
                continue
            }

            // A family that names **nothing** has no name to gate, and
            // demanding `isSafe` of it would be theatre. The exemption is
            // therefore paid for with a *stronger* claim, not a weaker one: the
            // file must be structurally incapable of putting a name in argv at
            // all. Adding a file to `namesNothing` is a deliberate act that
            // must satisfy every expectation below.
            #expect(
                source.contains("MutationName.isSafe") == false,
                "\(name) is listed as naming nothing but reaches for the name gate"
            )
            for naming in ["PackageID", "PackageTarget", "FormulaID", "CaskID", "TapName"] {
                #expect(
                    source.contains(naming) == false,
                    "\(name) is listed as naming nothing but carries a \(naming)"
                )
            }
            // Nothing free-text can get in: the only initialiser takes a `URL`,
            // and the only `String` in the file is a literal enum raw value.
            let initialisers = source
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.contains("init(") }
            #expect(
                initialisers == ["public init(fileURL: URL) {"],
                "\(name) is listed as naming nothing but offers \(initialisers)"
            )
            let storedStrings = source
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { ($0.hasPrefix("public let ") || $0.hasPrefix("let ")) && $0.contains("String") }
            #expect(
                storedStrings.isEmpty,
                "\(name) is listed as naming nothing but stores \(storedStrings)"
            )
        }
    }

    /// Command families whose argv contains no package name at any position.
    ///
    /// `BundleDumpCommand` is the only member: its vector is literal verb and
    /// flag tokens plus **one path this capability itself created** under a
    /// Cellar-owned temporary location. There is no name in it to validate, and
    /// there is no way to put one in — the initialiser takes a `URL`, not a
    /// `String` (`brewfile-management` BF1).
    private static let namesNothing: Set<String> = ["BundleDumpCommand.swift"]

    /// Every `*Command.swift` in `BrewClient`, keyed by file name.
    private static func commandFiles() throws -> [String: String] {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrewClient")
        let names = try FileManager.default
            .contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix("Command.swift") }

        return try names.reduce(into: [:]) { files, name in
            files[name] = try String(
                contentsOf: sources.appendingPathComponent(name),
                encoding: .utf8
            )
        }
    }

    /// The body of `var arguments: [String]`, up to its closing brace.
    ///
    /// Textual because the claim is textual: what matters is which *constructs*
    /// appear between the braces, and a parser would buy nothing a reader of
    /// this file could not already check by eye.
    private static func argumentsBody(of source: String) -> String? {
        guard let start = source.range(of: "var arguments: [String]") else { return nil }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: "\n    }") else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }

    /// And the structural claim, checked behaviourally: round-tripping a display
    /// string is impossible because the only way to build a command is from a
    /// typed `PackageID`, which a string cannot become without a parser.
    @Test("Argv is only ever produced from typed cases")
    func argvIsOnlyProducedFromTypedCases() {
        let rendered = MutationCommand.uninstall(PackageTarget(Self.iterm)!).displayCommand
        #expect(rendered == "brew uninstall --cask iterm2")

        // The rendered form carries the kind as a flag, and the only way back to
        // a command is to name the kind again in the type system.
        let rebuilt = MutationCommand.uninstall(PackageTarget(PackageID(kind: .cask, name: "iterm2"))!)
        #expect(rebuilt.displayCommand == rendered)
        #expect(rebuilt.arguments == ["uninstall", "--cask", "iterm2"])
    }
}
