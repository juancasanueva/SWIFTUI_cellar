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
/// confirmation carrying the `tapTrust` disclosure" — against shipped source and
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

        #expect(request.disclosure == .tapTrust(Self.acme))
        #expect(request.tapIdentity == Self.acme)
        #expect(request.commands.count == 3, "the batch lost commands on the way to the gate")
        #expect(harness.launcher.launchCount == 0, "the gate spawned before it was answered")

        // Identical to the disclosure the same tap add presents unerased — the
        // whole point of the requirement is that erasure changes nothing.
        let reference = CenterHarness()
        let unerased = try #require(reference.center.request(TapCommand.addTap(Self.acme)))
        #expect(request.disclosure == unerased.disclosure)
        #expect(request.warningText == unerased.warningText)
        #expect(
            request.warningText
                == "Adding acme/tap trusts third-party formulae and casks that can distribute code."
        )
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
        #expect(tapRequest.disclosure == .tapTrust(Self.acme))

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
        #expect(TapCommand.addTap(Self.acme).disclosure == .tapTrust(Self.acme))
        #expect(AnyBrewMutation(TapCommand.addTap(Self.acme)).disclosure == .tapTrust(Self.acme))
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
            bulk.code.contains("disclosure: first.disclosure"),
            "the confirmation gate does not read the disclosure through the abstraction"
        )

        // And the abstraction really does declare it, so the read above is a
        // protocol requirement rather than a lucky concrete member.
        let spine = try #require(sources.first { $0.name == "BrewMutating.swift" })
        #expect(spine.code.contains("var disclosure: ConfirmationDisclosure { get }"))
        #expect(
            spine.code.contains("public let disclosure: ConfirmationDisclosure"),
            "the erased value does not store the disclosure, so erasure still discards it"
        )
    }
}
