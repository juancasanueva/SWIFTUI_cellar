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
        ArgvCase(command: .upgradeAll, argv: ["upgrade"]),
        ArgvCase(command: .update, argv: ["update"])
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

    /// `update` refreshes what brew knows, never what is installed, so its
    /// vector is the bare verb: no `--force`, no `--auto-update`, and no name —
    /// there is nothing it could correctly name.
    @Test("Update is a bare brew update with nothing added")
    func updateIsBare() {
        let argv = MutationCommand.update.arguments

        #expect(argv == ["update"])
        for forbidden in ["--force", "--auto-update", "--merge", "wget", "iterm2"] {
            #expect(argv.contains(forbidden) == false, "update carried \(forbidden)")
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

    @Test("Install, reinstall, upgrade, upgrade-all, update, pin and unpin never confirm")
    func nonDestructiveCommandsNeverConfirm() {
        let safe: [MutationCommand] = [
            .install(PackageTarget(Self.wget)!),
            .reinstall(PackageTarget(Self.git)!),
            .upgrade(PackageTarget(Self.iterm)!),
            .upgradeAll, .update, .pin(FormulaID(Self.git)!), .unpin(FormulaID(Self.git)!)
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
            guard Self.namesNothing.keys.contains(name) else {
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
                initialisers == Self.namesNothing[name],
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

    /// Command families whose argv contains no package name at any position,
    /// each mapped to the **exact** set of initialisers it may offer.
    ///
    /// Exact per file rather than a shared rule, because the exemption is paid
    /// for with a stronger claim than the one it replaces: a member here must be
    /// structurally incapable of putting a name in argv, and "which initialisers
    /// exist" is the sharpest way to say that. Adding a member is a deliberate
    /// act that must satisfy every expectation above.
    ///
    /// - `BundleDumpCommand`: literal verb and flag tokens plus **one path this
    ///   capability itself created** under a Cellar-owned temporary location.
    ///   There is no name in it to validate and no way to put one in — the
    ///   initialiser takes a `URL`, not a `String` (`brewfile-management` BF1).
    /// - `DoctorCommand`: the strictest member possible. Its vector is the single
    ///   literal `doctor`, and it offers **no initialiser at all**, so there is
    ///   no parameter through which anything could reach argv (`system-health`).
    private static let namesNothing: [String: [String]] = [
        "BundleDumpCommand.swift": ["public init(fileURL: URL) {"],
        "DoctorCommand.swift": []
    ]

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

    // MARK: - PM10 :367-373 — an untrusted tap never pre-blocks a mutation

    /// **R7 / obs #7724.** With the tap withheld the inventory cannot prove a
    /// package's origin, and a **per-package** grant can make brew allow exactly
    /// what a tap-state gate would refuse. Only brew sees both grant kinds, so
    /// only brew decides — a pre-launch gate here would block what the user is
    /// entitled to run and would call a loadable package untrusted.
    @Test("An untrusted tap never pre-blocks a mutation")
    func anUntrustedTapNeverPreBlocksAMutation() throws {
        // A package whose tap brew is withholding, published by an untrusted tap.
        let widget = PackageID(kind: .cask, name: "widget")
        let target = try #require(PackageTarget(widget))
        let untrusted = TapRecord(
            name: "acme/tools",
            repository: "tools",
            caskTokens: ["acme/tools/widget"],
            trust: .untrusted
        )
        #expect(TapProjection.publishes(widget, in: untrusted))

        // Every mutation for it is built normally, and its argv names the bare
        // token — the same argv the same command builds for any other package.
        for command in [
            MutationCommand.install(target),
            .uninstall(target),
            .upgrade(target),
            .reinstall(target)
        ] {
            #expect(command.arguments.contains("widget"))
            #expect(command.arguments.contains { $0.contains("/") } == false)
            #expect(command.arguments.first != nil)
        }

        // And no build path consults a trust state at all. Asserted
        // structurally, because "the gate is not there yet" is exactly the kind
        // of absence a later change reintroduces while fixing something else.
        let files = try Self.commandFiles()
        #expect(files.isEmpty == false, "the *Command.swift scan matched no files at all")
        let mutation = try #require(files["MutationCommand.swift"])
        // The trust *machinery*, not the English word: a shipped comment at
        // `MutationCommand.swift:104` says "a future reader would trust it",
        // and banning the bare word would make this guard about prose.
        //
        // Extended for **per-package** grants (PM10 :152-158): a store that did
        // not exist when this list was written is exactly how a pre-launch gate
        // comes back. One prefix token covers every type the per-package wire,
        // source and store introduce, because they all share it.
        let gates = [
            "TapTrustState", ".untrusted", ".trusted", ".trust", "TapRecord",
            "TapInventory", "TapProjection", "trustableTap", "UntrustedTapRecovery",
            "TrustGrant", "grantsIndividually"
        ]
        for gate in gates {
            #expect(
                mutation.contains(gate) == false,
                "the package mutation surface consults tap trust: \(gate)"
            )
        }

        // …and the list **covers** the per-package vocabulary, asserted as
        // coverage rather than as prose: each name is either on the list or
        // shares a prefix with something on it.
        let perPackageNames = [
            "TrustGrantState", "TrustGrantLedger", "TrustGrantError", "TrustGrantDecoder",
            "TrustGrantSourcing", "BrewTrustGrantPayloadSource", "TrustGrantPayload",
            "TrustGrantStore", "TrustGrantLoadState", "TrustGrantSection",
            "grantsIndividually"
        ]
        for name in perPackageNames {
            #expect(
                gates.contains { name.contains($0) },
                "the per-package trust type \(name) is not covered by the ban list"
            )
        }
        // The two projection values the list does not name are unreachable
        // without one that it does: `TapGrantPresentation` is nested in
        // `TapProjection`, and the only producer of `UnattributedGrants` is
        // `TapProjection.accounting`. Both spellings carry a banned token.
        for reachedThroughTheProjection in ["TapGrantPresentation", "UnattributedGrants"] {
            #expect(mutation.contains(reachedThroughTheProjection) == false)
        }
        #expect(gates.contains("TapProjection"))

        // Positively anchored: the list is not vacuous — the names really do
        // exist, and they really are absent from this one file.
        let projection = try Self.brewClientSource("TapProjection.swift")
        #expect(projection.contains("grantsIndividually"))
        #expect(projection.contains("UnattributedGrants"))
        #expect(try Self.brewClientSource("TrustGrantStore.swift").contains("TrustGrantStore"))
    }

    // MARK: - PM10 :144-150 — a per-package grant state never pre-blocks either

    /// **The same defect in a new place.** A `noGrantRecorded` state is not a
    /// prediction of refusal: a package under a trusted tap needs no individual
    /// grant, and an `unreported` report is not evidence of anything at all.
    /// Gating on either would refuse exactly what brew allows.
    @Test("A per-package grant state never pre-blocks a mutation")
    func aPerPackageGrantStateNeverPreBlocksAMutation() throws {
        let widget = PackageID(kind: .cask, name: "widget")
        let target = try #require(PackageTarget(widget))
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            caskTokens: ["acme/tools/widget"],
            trust: .untrusted
        )
        // `granted`, `noGrantRecorded` and `unreported` in turn, plus a machine
        // whose report failed to load — which is `unreported` reached the other
        // way, and is listed separately because it is a different history.
        let states: [(name: String, state: TrustGrantState)] = [
            ("granted", .reported(TrustGrantLedger(casks: ["acme/tools/widget"]))),
            ("noGrantRecorded", .reported(TrustGrantLedger(casks: ["other/tools/desk"]))),
            ("reported empty", .reported(TrustGrantLedger(declaredNamespaces: ["casks"]))),
            ("unreported", .unreported),
            ("failed to load", TrustGrantState.settled(
                .failure(.commandFailed(status: 1, message: "Error: Unknown command: trust")),
                keeping: .unreported
            ))
        ]

        // Positively anchored: the states really are different, and the first
        // really does record a grant for this exact package.
        #expect(states.count == 5)
        #expect(TapProjection.grantsIndividually(widget, publishedBy: tap.name, in: states[0].state))
        #expect(TapProjection.grantsIndividually(widget, publishedBy: tap.name, in: states[1].state) == false)

        let expected: [MutationCommand] = [
            .install(target), .uninstall(target), .upgrade(target), .reinstall(target)
        ]
        for entry in states {
            for command in expected {
                // Built and submitted normally in every case: same argv, same
                // confirmation, same declared domains, same disclosure. Nothing
                // is disabled, refused, or warned about on the strength of a
                // grant state.
                #expect(command.arguments.contains("widget"), "\(entry.name) changed the argv")
                #expect(command.arguments.contains { $0.contains("/") } == false)
                #expect(command.requiresConfirmation == (command.verb == "uninstall"))
                #expect(command.invalidates == [.installedInventory, .diskUsage])
                #expect(command.packageID == widget, "\(entry.name) changed the target")
            }
        }
    }

    // MARK: - PM10 :160-167 — the read is not a command on the spine

    @Test("The per-package read is not a command on the mutation spine")
    func thePerPackageReadIsNotACommandOnTheMutationSpine() throws {
        // It is a `read`, and a `BrewCommand` — not a `BrewMutating` conformer,
        // so it cannot be enqueued, cannot produce an activity item, and has no
        // `invalidates` to declare.
        let read = BrewTrustGrantPayloadSource.command
        #expect(read.kind == .read)
        #expect((read as Any) is (any BrewMutating) == false)
        #expect(read.arguments == ["trust", "--json", "v1"])

        // The spine's families are exactly the ones it covered before: every
        // `*Command.swift` that declares `invalidates`, and no more.
        let declaring = try Self.commandFiles()
            .filter { $0.value.contains("var invalidates: InvalidationScope") }
            .keys
            .sorted()
        // `NpmCommand.swift` joined this census deliberately: npm enters through
        // the shared abstraction exactly as services and taps did, which is what
        // keeps PM1's "exactly six" package commands literally true while a
        // second source exists (`package-mutation`, design D14).
        #expect(declaring == [
            "CleanupCommand.swift", "NpmCommand.swift", "ServiceCommand.swift", "TapCommand.swift"
        ], "the spine's command families changed: \(declaring)")
        // `MutationCommand`'s own declaration lives in `BrewMutating.swift`,
        // which is why it is not in the list above and is asserted here instead.
        #expect(try Self.brewClientSource("BrewMutating.swift")
            .contains("extension MutationCommand: BrewMutating"))

        // No `TrustGrant…` file is a command family at all.
        #expect(try Self.commandFiles().keys.contains { $0.hasPrefix("TrustGrant") } == false)
        for name in ["TrustGrantPayloadSource.swift", "TrustGrantStore.swift", "TrustGrantWire.swift"] {
            let source = try Self.brewClientSource(name)
            #expect(source.contains("BrewMutating") == false, "\(name) reaches for the mutation spine")
            #expect(source.contains("InvalidationScope") == false, "\(name) declares an invalidation domain")
            #expect(source.contains("ActivityItem") == false, "\(name) produces an activity item")
            #expect(source.contains("OperationCenter") == false, "\(name) enqueues on the spine")
        }
    }

    private static func brewClientSource(_ name: String) throws -> String {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/BrewClient")
        return try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
    }

    // MARK: - PM10 :359-365 — the argv prohibition, as an absence over the surface

    /// **The central threat (D1, D3, design R2).** Homebrew 6 treats *naming* a
    /// `owner/tap/token` on the command line as a **per-package trust grant**
    /// (`trust.rb#explicitly_allowed?`). So a qualified token reaching argv — a
    /// "helpful" retry, or a Brewfile line the importing user never wrote —
    /// would silently execute code nobody consented to run, while looking
    /// exactly like a bug fix.
    ///
    /// The shipped name gate deliberately permits `/`: `TapName.init?` is
    /// expressed over the same gate and a tap name *is* `owner/repo`, so
    /// narrowing it would make every tap unconstructible. The prohibition is
    /// therefore an **absence over the whole argv surface**, asserted here.
    ///
    /// **Positively anchored**, because a vacuous version of this test is worse
    /// than none: the fixture set is asserted non-empty, `addTap` really does
    /// produce exactly one `/`, and the qualified Brewfile entry really does
    /// produce `install --formula thing`.
    @Test("No package position anywhere ever carries a qualified token")
    func noPackagePositionEverCarriesAQualifiedToken() throws {
        // 1. Every `MutationCommand` factory, over both kinds.
        let formula = try #require(PackageTarget(PackageID(kind: .formula, name: "wget")))
        let cask = try #require(PackageTarget(PackageID(kind: .cask, name: "iterm2")))
        var mutations: [MutationCommand] = [.update, .upgradeAll]
        for target in [formula, cask] {
            mutations.append(contentsOf: [
                .install(target), .uninstall(target), .upgrade(target), .reinstall(target)
            ])
        }
        mutations.append(.zap(try #require(CaskID(cask.id))))
        mutations.append(.pin(try #require(FormulaID(formula.id))))
        mutations.append(.unpin(try #require(FormulaID(formula.id))))
        // …and the `naming(_:_:)` build, over the identities Cellar actually
        // types: catalog and installed identities, which are bare tokens.
        //
        // A synthetic qualified `PackageID` is deliberately **not** fed in here.
        // `naming` is a lift over `PackageTarget.init?`, and **DD-8** forbids
        // narrowing that gate — `TapName.init?` is expressed over it and a tap
        // name *is* `owner/repo`, so a `/` ban there makes every tap
        // unconstructible and every qualified Brewfile line an unrepresentable
        // entry. The one place a qualified name can enter is a Brewfile, and
        // that is where **D3** strips it — asserted by the plan fixture below.
        for id in [formula.id, cask.id] {
            let builds: [(PackageTarget) -> MutationCommand] = [
                { MutationCommand.install($0) },
                { MutationCommand.uninstall($0) },
                { MutationCommand.upgrade($0) },
                { MutationCommand.reinstall($0) }
            ]
            for build in builds {
                if let built = MutationCommand.naming(id, build) { mutations.append(built) }
            }
        }

        // 2. Every `TapCommand` case.
        let tap = try #require(TapName("acme/tap"))
        let tapCommands: [TapCommand] = [
            .addTap(tap), .trustTap(tap), .untrustTap(tap), .removeTap(tap),
            .forceRemoveTap(ForceUntapEvidence(
                tap: tap,
                affected: [PackageID(kind: .formula, name: "thing")],
                isComplete: true
            ))
        ]

        // 3. Every command a plan built from a **qualified** fixture emits.
        let qualified = BrewfilePlan(selecting: [
            BrewfileEntry(
                kind: .formula(try #require(FormulaID(name: "acme/tap/thing"))),
                lineNumber: 1
            ),
            BrewfileEntry(
                kind: .cask(try #require(CaskID(name: "acme/tap/app"))),
                lineNumber: 2
            ),
            BrewfileEntry(kind: .tap(tap, url: nil), lineNumber: 3)
        ])

        // 4. Every `ServiceCommand` verb and every `CleanupCommand` scope (W1):
        // both carry a package position built from the same `PackageTarget`
        // gate, so the enumeration has to walk them too.
        let service = try #require(ServiceTarget(name: "thing"))
        let serviceCommands = ServiceCommand.allVerbs(for: service)
        let cleanupCommands: [CleanupCommand] = [
            CleanupCommand(scope: .global),
            CleanupCommand(scope: .autoremove),
            try #require(CleanupCommand.package(kind: .formula, name: "thing")),
            try #require(CleanupCommand.package(kind: .cask, name: "app"))
        ]

        // Positive anchors first — a scan that matched nothing would make every
        // expectation below pass for the wrong reason.
        #expect(mutations.count >= 11, "the mutation fixture set collapsed")
        #expect(tapCommands.count == 5)
        #expect(serviceCommands.count == 4, "the service verb set collapsed")
        #expect(cleanupCommands.count == 4)
        #expect(qualified.installs.isEmpty == false, "the qualified plan produced no install")
        #expect(qualified.taps.map(\.arguments) == [["tap", "acme/tap"]])
        #expect(
            TapCommand.addTap(tap).arguments.filter { $0.contains("/") } == ["acme/tap"],
            "the tap add stopped producing the one legitimate slash"
        )
        #expect(qualified.installs.first?.arguments == ["install", "--formula", "thing"])

        // **No `MutationCommand` argv element contains a slash at all** — the
        // package families have no legitimate use for one.
        for command in mutations + qualified.installs {
            for element in command.arguments {
                #expect(
                    element.contains("/") == false,
                    "\(command.verb) carries a slash in argv: \(element)"
                )
            }
        }
        for arguments in serviceCommands.map(\.arguments) + cleanupCommands.map(\.arguments) {
            for element in arguments {
                #expect(element.contains("/") == false, "a service or cleanup argv carries a slash: \(element)")
            }
        }

        // And **no argv element of any family carries two or more** — one is a
        // tap name, two is a qualified package token and therefore a grant.
        for arguments in (mutations + qualified.installs).map(\.arguments)
            + tapCommands.map(\.arguments) {
            for element in arguments {
                #expect(
                    element.filter { $0 == "/" }.count <= 1,
                    "a qualified token reached argv: \(element)"
                )
            }
        }
    }
}
