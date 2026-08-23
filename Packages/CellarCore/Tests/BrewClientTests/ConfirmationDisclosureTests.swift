import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The confirmation **disclosure**, read through the shared abstraction rather
/// than recovered from a concrete command type (package-mutation PM1, design
/// DD1).
///
/// Design verified the proposal's claim — "a mixed batch raises exactly one
/// confirmation carrying the `tapAdd` disclosure" — against shipped source and
/// found it false. `OperationCenterBulk.request(_:)` resolved the disclosure by
/// downcasting, `(first as? TapCommand)?.disclosure ?? .packageRemoval`, and
/// `AnyBrewMutation` carried seven projections with `disclosure` not among them.
/// Every shipped call site happens to submit an **unerased** `TapCommand`, so the
/// gap never fired; a Brewfile batch is the first mixed tap+install submission
/// and must be erased before it reaches the gate, at which point the downcast
/// fails and the sheet shows "This removes installed software." instead of the
/// tap-trust warning.
///
/// That is a security-relevant downgrade of a typed warning another capability
/// owns, so it is proven here as a requirement rather than left as an
/// implementation detail.
@MainActor
@Suite("Confirmation disclosure survives erasure", .timeLimit(.minutes(1)))
struct ConfirmationDisclosureTests {

    private static let acme = TapName("acme/tap")!
    private static let wget = PackageTarget(PackageID(kind: .formula, name: "wget"))!
    private static let git = PackageTarget(PackageID(kind: .formula, name: "git"))!
    private static let iterm = PackageTarget(PackageID(kind: .cask, name: "iterm2"))!

    // MARK: - II13 — bulk pin and bulk unpin raise no confirmation

    /// `request(_:)` already returned `nil` for pin and unpin before they had a
    /// bulk form, because neither destroys anything and both are reversible in
    /// one click. So `submitBulk` submits them directly, and DD1's
    /// `first.disclosure` fix — which is what makes an erased mixed batch
    /// disclose the *right* warning — is untouched by the widening.
    @Test("Bulk pin and bulk unpin present no confirmation at all")
    func bulkPinAndUnpinRaiseNoConfirmation() {
        let harness = CenterHarness()

        for command in [MutationCommand.pin(FormulaID(Self.wget.id)!), .unpin(FormulaID(Self.git.id)!)] {
            #expect(harness.center.request(command) == nil, "\(command.verb) asked for a confirmation")
            #expect(command.requiresConfirmation == false)
        }

        // And as a batch, which is the shape `submitBulk` actually hands it.
        let batch: [MutationCommand] = [
            .pin(FormulaID(Self.wget.id)!),
            .pin(FormulaID(Self.git.id)!)
        ]
        #expect(harness.center.request(batch) == nil, "a bulk pin batch asked for a confirmation")
        #expect(harness.center.pendingConfirmation == nil)

        // The control: the destructive verb still does ask, so "no confirmation"
        // is about pinning rather than about a gate that stopped working.
        #expect(harness.center.request(MutationCommand.uninstall(Self.wget)) != nil)
    }

    // MARK: - PM1 — an erased mixed batch still discloses tap trust

    @Test("An erased mixed batch still discloses tap trust")
    func anErasedMixedBatchStillDisclosesTapTrust() throws {
        let harness = CenterHarness()
        let erased: [AnyBrewMutation] = [
            AnyBrewMutation(TapCommand.addTap(Self.acme)),
            AnyBrewMutation(MutationCommand.install(Self.wget)),
            AnyBrewMutation(MutationCommand.install(Self.git))
        ]

        let request = try #require(
            harness.center.request(erased),
            "an erased batch containing a tap add raised no confirmation at all"
        )

        #expect(request.disclosure == .tapAdd(Self.acme))
        #expect(request.tapIdentity == Self.acme)
        #expect(request.commands.count == 3, "the batch lost commands on the way to the gate")
        #expect(harness.launcher.launchCount == 0, "the gate spawned before it was answered")

        // Identical to the disclosure the same tap add presents unerased — the
        // whole point of the requirement is that erasure changes nothing.
        let reference = CenterHarness()
        let unerased = try #require(reference.center.request(TapCommand.addTap(Self.acme)))
        #expect(request.disclosure == unerased.disclosure)
        #expect(request.warningText == unerased.warningText)
        #expect(request.warningText == """
        Adding acme/tap clones a third-party repository. Homebrew will not load \
        its formulae or casks until you trust it, and Cellar does not trust it \
        for you.
        """)
    }

    // MARK: - PM1 — an erased install-only batch still discloses package removal

    @Test("An erased install-only batch still discloses package removal")
    func anErasedInstallOnlyBatchStillDisclosesPackageRemoval() throws {
        let harness = CenterHarness()
        let erased: [AnyBrewMutation] = [
            AnyBrewMutation(MutationCommand.uninstall(Self.wget)),
            AnyBrewMutation(MutationCommand.uninstall(Self.iterm))
        ]

        let request = try #require(harness.center.request(erased))
        #expect(request.disclosure == .packageRemoval)
        #expect(request.warningText == "This removes installed software.")
        #expect(request.tapIdentity == nil, "a package-only batch claimed a tap identity")
        #expect(request.affectedPackages.isEmpty)
    }

    /// Every shipped call site's disclosure, unchanged by DD1.
    @Test("Every shipped call site keeps the disclosure it already presented")
    func everyShippedCallSiteKeepsTheDisclosureItAlreadyPresented() throws {
        // `submitBulk(.uninstall, …)` — concrete `MutationCommand`s, package removal.
        let bulk = CenterHarness()
        let bulkRequest = try #require(
            bulk.center.submitBulk(.uninstall, over: [CenterHarness.wget, CenterHarness.git])
        )
        #expect(bulkRequest.disclosure == .packageRemoval)
        #expect(bulkRequest.commands.count == 2)
        #expect(bulk.launcher.launchCount == 0)

        // A single unerased `TapCommand` — tap trust, exactly as before.
        let single = CenterHarness()
        let tapRequest = try #require(single.center.request(TapCommand.addTap(Self.acme)))
        #expect(tapRequest.disclosure == .tapAdd(Self.acme))

        // A force-untap still carries its own evidence-bearing disclosure.
        let affected: Set<PackageID> = [PackageID(kind: .formula, name: "wget")]
        let evidence = ForceUntapEvidence(tap: Self.acme, affected: affected, isComplete: true)
        let force = try #require(TapCommand.forceUntap(evidence: evidence))
        let forceHarness = CenterHarness()
        let forceRequest = try #require(forceHarness.center.request(force))
        #expect(forceRequest.disclosure == .forceUntap(tap: Self.acme, affected: affected))
        #expect(forceRequest.affectedPackages == [PackageID(kind: .formula, name: "wget")])

        // `requestCleanup` builds its request directly and never consults the
        // batch head, so DD1 cannot reach it. Asserted structurally, because
        // the alternative is standing up a whole cleanup preview to observe an
        // absence.
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let cleanup = try #require(sources.first { $0.name == "OperationCenterCleanup.swift" })
        #expect(
            cleanup.code.contains("cleanupDisclosure: CleanupConfirmationDisclosure(result: result)"),
            "the cleanup request stopped carrying its own typed evidence"
        )
        #expect(
            cleanup.code.contains("disclosure:") == false || cleanup.code.contains("cleanupDisclosure:"),
            "the cleanup request started resolving an ordinary disclosure"
        )
    }

    /// A command that declares no disclosure of its own supplies the ordinary
    /// package-removal disclosure **by protocol default**, not by a caller's
    /// `??` fallback. The distinction is the whole requirement: a fallback in
    /// the caller is exactly what silently downgraded the tap warning.
    @Test("A command declaring no disclosure defaults through the protocol, not the caller")
    func aCommandDeclaringNoDisclosureDefaultsThroughTheProtocol() throws {
        var probe = ProbeMutation()
        probe.requiresConfirmation = true

        // The default is readable on the command itself, with no gate involved.
        #expect(probe.disclosure == .packageRemoval)
        // And it survives erasure, which is what makes the gate's read total.
        #expect(AnyBrewMutation(probe).disclosure == .packageRemoval)

        let harness = CenterHarness()
        let request = try #require(harness.center.request([AnyBrewMutation(probe)]))
        #expect(request.disclosure == .packageRemoval)

        // A conformer that *does* declare one is taken at its word, erased or not.
        #expect(TapCommand.addTap(Self.acme).disclosure == .tapAdd(Self.acme))
        #expect(AnyBrewMutation(TapCommand.addTap(Self.acme)).disclosure == .tapAdd(Self.acme))
    }

    // MARK: - TM6 / TM13 / PM3 — the add says what add does, the grant says what a grant does

    /// **D2.** `brew tap` on Homebrew 6 grants nothing: the tap it clones is
    /// inert until a separate `brew trust` runs. The shipped copy — "Adding
    /// acme/tap trusts third-party formulae and casks that can distribute
    /// code." — asserted a capability grant the command never made, which is
    /// the one kind of wrong sentence a security disclosure may not contain.
    ///
    /// Two cases now, because two different things happen and a user answering
    /// them must be able to tell which one they answered (TM6 :191-197,
    /// TM13 :508-515, PM3 :245-260).
    @Test("The add disclosure claims no grant and the grant disclosure claims one")
    func theAddDisclosureClaimsNoGrantAndTheGrantDisclosureClaimsOne() throws {
        let tap = try #require(TapName("acme/tools"))

        #expect(ConfirmationDisclosure.tapAdd(tap).warningText == """
        Adding acme/tools clones a third-party repository. Homebrew will not \
        load its formulae or casks until you trust it, and Cellar does not \
        trust it for you.
        """)
        #expect(ConfirmationDisclosure.tapTrustGrant(tap).warningText == """
        Trusting acme/tools lets Homebrew load and run its formulae and casks. \
        That is third-party code running as you, with your permissions.
        """)

        // The add text must not claim a grant, and the grant text must not
        // pretend to be an add — the two are separate answers to separate
        // questions (TM6 :164-169).
        #expect(ConfirmationDisclosure.tapAdd(tap).warningText.contains("does not trust it for you"))
        #expect(ConfirmationDisclosure.tapTrustGrant(tap).warningText.contains("clones") == false)

        // TM12 :467-473 / R7 — both sentences are about the **tap**. A
        // per-package grant can make a package loadable while its tap is not
        // trusted, so neither may call a package untrusted.
        for text in [
            ConfirmationDisclosure.tapAdd(tap).warningText,
            ConfirmationDisclosure.tapTrustGrant(tap).warningText
        ] {
            #expect(text.contains(tap.rawValue), "the disclosure does not name the tap: \(text)")
            #expect(
                text.localizedCaseInsensitiveContains("untrusted") == false,
                "the disclosure calls something untrusted: \(text)"
            )
        }

        // The two disclosures this change does not touch stay byte-identical.
        #expect(ConfirmationDisclosure.packageRemoval.warningText == "This removes installed software.")
        let affected: Set<PackageID> = [
            PackageID(kind: .formula, name: "widget"),
            PackageID(kind: .cask, name: "widget")
        ]
        #expect(
            ConfirmationDisclosure.forceUntap(tap: tap, affected: affected).warningText
                == "Force-removing acme/tools affects 2 installed packages."
        )
    }

    // MARK: - PM1 / TM8 — a batch takes the disclosure of its first *declaring* command

    /// **The defect this exists to prevent.** TM7 and TM8 prepend a revocation
    /// to every removal. Under the shipped rule — `first.disclosure` — the batch
    /// head became a command with nothing of its own to say, whose protocol
    /// default is "This removes installed software.", and the force-untap
    /// affected-package disclosure was silently downgraded to it. That is the
    /// exact defect PM1 was written to fix, reintroduced by an unrelated change.
    ///
    /// The fix is a *skip*, not a re-rank: a command that declares nothing is
    /// passed over, and the first command that declares something wins
    /// (TM8 :308-314, PM1 :128-152).
    @Test("A batch led by a command that discloses nothing still discloses the force untap")
    func aBatchLedByACommandThatDisclosesNothingStillDisclosesTheForceUntap() throws {
        let widget = PackageID(kind: .formula, name: "widget")
        let evidence = ForceUntapEvidence(tap: Self.acme, affected: [widget], isComplete: true)
        let forced = try #require(TapCommand.forcedRemoval(evidence: evidence))
        let harness = CenterHarness()

        let request = try #require(
            harness.center.request(forced),
            "a revoke-first force untap raised no confirmation at all"
        )
        #expect(request.disclosure == .forceUntap(tap: Self.acme, affected: [widget]))
        #expect(request.warningText != "This removes installed software.")
        #expect(request.commands.map(\.arguments) == [
            ["untrust", "acme/tap"],
            ["untap", "--force", "acme/tap"]
        ])

        // TM8 :313 — identical to the disclosure the same force untap presents
        // when submitted **without** the revocation in front of it.
        let reference = CenterHarness()
        let alone = try #require(TapCommand.forceUntap(evidence: evidence))
        let unprefixed = try #require(reference.center.request(alone))
        #expect(request.disclosure == unprefixed.disclosure)
        #expect(request.warningText == unprefixed.warningText)

        // TM7 :219-220 — the plain removal still raises nothing, because neither
        // of its members requires a confirmation.
        let plain = try #require(TapCommand.removal(of: "acme/tap"))
        #expect(CenterHarness().center.request(plain) == nil)

        // PM1 :137 — an erased install-only batch still discloses the ordinary
        // package removal, through the protocol default and not through a caller.
        let installOnly = [
            AnyBrewMutation(MutationCommand.uninstall(Self.wget)),
            AnyBrewMutation(MutationCommand.uninstall(Self.git))
        ]
        let removalRequest = try #require(CenterHarness().center.request(installOnly))
        #expect(removalRequest.disclosure == .packageRemoval)

        // PM1 :128 — and an erased mixed tap+install batch discloses the tap add.
        let mixed = [
            AnyBrewMutation(TapCommand.addTap(Self.acme)),
            AnyBrewMutation(MutationCommand.uninstall(Self.wget))
        ]
        let mixedRequest = try #require(CenterHarness().center.request(mixed))
        #expect(mixedRequest.disclosure == .tapAdd(Self.acme))
    }

    /// PM1 :154-161. Submission order, never severity. A rule that picked the
    /// "strongest" disclosure would be a ranking Cellar has no basis for, and it
    /// would show the user a warning about a command other than the one the
    /// batch leads with.
    @Test("Skipping picks the first declaring command, not the strongest")
    func skippingPicksTheFirstDeclaringCommandNotTheStrongest() throws {
        let widget = PackageID(kind: .formula, name: "widget")
        let evidence = ForceUntapEvidence(tap: Self.acme, affected: [widget], isComplete: true)
        let batch = [
            AnyBrewMutation(TapCommand.untrustTap(Self.acme)),
            AnyBrewMutation(TapCommand.addTap(Self.acme)),
            AnyBrewMutation(TapCommand.forceRemoveTap(evidence))
        ]

        let request = try #require(CenterHarness().center.request(batch))

        // The add is second and the force untap third; the add wins because it
        // declares first, not because it is milder.
        #expect(request.disclosure == .tapAdd(Self.acme))
        #expect(request.disclosure != .forceUntap(tap: Self.acme, affected: [widget]))
        #expect(batch.map(\.declaredDisclosure) == [
            nil,
            .tapAdd(Self.acme),
            .forceUntap(tap: Self.acme, affected: [widget])
        ])

        // And the rule itself, read directly: skip the non-declaring head, then
        // stop at the first declaration.
        #expect(batch.leadDisclosure == .tapAdd(Self.acme))
        #expect([AnyBrewMutation(TapCommand.untrustTap(Self.acme))].leadDisclosure == .packageRemoval)
        #expect(([] as [AnyBrewMutation]).leadDisclosure == .packageRemoval)
    }

    // MARK: - PM1 — no disclosure is recovered by a type test

    /// Structural, over the whole of `Sources/BrewClient/`.
    ///
    /// The permitted exception is stated rather than implied: reading a command's
    /// **verb** for a presentation concern that is not the disclosure — the
    /// shipped zap retitle in `cellar/Activity/MutationConfirmation.swift` — is
    /// explicitly allowed by the requirement. This scan therefore bans the
    /// downcast family outright and bans a verb read only where a disclosure is
    /// produced.
    @Test("No disclosure is recovered by a downcast, a type test or a verb string")
    func noDisclosureIsRecoveredByADowncastATypeTestOrAVerbString() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)

        for source in sources {
            for recovery in ["as? TapCommand", "as! TapCommand", "is TapCommand"] {
                #expect(
                    source.code.contains(recovery) == false,
                    "\(source.name) recovers a concrete command type: \(recovery)"
                )
            }
            #expect(
                source.code.contains("?.disclosure ??") == false,
                "\(source.name) still resolves a disclosure by a caller-side fallback"
            )
            #expect(
                source.code.contains("verb ==") == false,
                "\(source.name) inspects a verb string inside the mutation spine"
            )
        }

        // The positive half: the gate reads the disclosure straight off the
        // command, through the shared abstraction and nothing else.
        let bulk = try #require(sources.first { $0.name == "OperationCenterBulk.swift" })
        #expect(
            bulk.code.contains("disclosure: commands.leadDisclosure"),
            "the confirmation gate does not read the disclosure through the abstraction"
        )

        // And the abstraction really does declare **both** facts, so the read
        // above is a protocol requirement rather than a lucky concrete member.
        // Two members, because "declares nothing of its own" and "shows the
        // ordinary removal text" must stay distinguishable — the batch rule
        // exists only because they are (design DD-3).
        let spine = try #require(sources.first { $0.name == "BrewMutating.swift" })
        #expect(spine.code.contains("var disclosure: ConfirmationDisclosure { get }"))
        #expect(spine.code.contains("var declaredDisclosure: ConfirmationDisclosure? { get }"))
        #expect(
            spine.code.contains("public let disclosure: ConfirmationDisclosure"),
            "the erased value does not store the disclosure, so erasure still discards it"
        )
        #expect(
            spine.code.contains("public let declaredDisclosure: ConfirmationDisclosure?"),
            "the erased value discards the declaration, so a batch head loses its skip predicate"
        )
    }
}
