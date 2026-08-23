//
//  TapCompositionTests.swift
//  cellarTests
//

import BrewClient
import BrewProcess
import Catalog
import Foundation
import Testing

@testable import cellar

/// Trust is a capability grant: it lets Homebrew load and run a third party's
/// code as this user, with this user's permissions. The one property that makes
/// the whole feature safe is therefore an **absence** — that no path anywhere in
/// the app produces a `trust` argv except an explicitly confirmed answer to a
/// Trust request (tap-management TM13 :517-523, TM6 :199-205).
///
/// An absence is only worth asserting when the ledger it is asserted over is
/// real, so every action below runs through a real `OperationCenter` over a
/// recording launcher rather than through a mock of one.
@MainActor
@Suite("Tap trust composition", .timeLimit(.minutes(1)))
struct TapCompositionTests {
    @Test("No path grants trust without an explicit answer")
    func noPathGrantsTrustWithoutAnExplicitAnswer() async throws {
        let tap = try #require(TapName("acme/tools"))
        let launcher = CompositionLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: AppTestFixtures.installation)

        // Add Tap — exactly one confirmation, and it discloses the add.
        let addCommand = try #require(TapCommand.add("acme/tools"))
        let add = try #require(center.request(addCommand), "Add Tap raised no confirmation")
        #expect(add.disclosure == .tapAdd(tap))
        #expect(add.commands.count == 1)
        _ = center.confirm(add)

        // Untap — no confirmation at all; removal is the primary action.
        let untapCommand = try #require(TapCommand.untap("acme/tools"))
        #expect(center.request(untapCommand) == nil)
        _ = center.submit(untapCommand)

        // Untrust — no confirmation either; a revocation only reduces authority.
        let untrustCommand = try #require(TapCommand.untrust("acme/tools"))
        #expect(center.request(untrustCommand) == nil)
        _ = center.submit(untrustCommand)

        // Force Untap — one confirmation, and it discloses the affected set,
        // never the grant.
        let force = try #require(TapCommand.forceUntap(evidence: ForceUntapEvidence(
            tap: tap,
            affected: [PackageID(kind: .formula, name: "widget")],
            isComplete: true
        )))
        let forceRequest = try #require(center.request(force), "Force Untap raised no confirmation")
        #expect(forceRequest.disclosure == .forceUntap(
            tap: tap,
            affected: [PackageID(kind: .formula, name: "widget")]
        ))
        _ = center.confirm(forceRequest)

        await settle(center)

        // The absence, over a real ledger: four actions, and not one of them
        // spawned a grant.
        #expect(launcher.spawned.isEmpty == false, "nothing ran at all — the ledger is vacuous")
        #expect(
            launcher.spawned.contains { $0.first == "trust" } == false,
            "a path other than an explicit Trust answer spawned a grant: \(launcher.spawned)"
        )
        #expect(launcher.spawned.contains(["tap", "acme/tools"]))
        #expect(launcher.spawned.contains(["untap", "acme/tools"]))
        #expect(launcher.spawned.contains(["untrust", "acme/tools"]))
        #expect(launcher.spawned.contains(["untap", "--force", "acme/tools"]))

        // And the control: an explicit Trust answer *does* raise exactly one
        // confirmation, carrying the grant disclosure, and only then does a
        // `trust` argv exist.
        let trustCommand = try #require(TapCommand.trust("acme/tools"))
        let grant = try #require(center.request(trustCommand), "Trust raised no confirmation")
        #expect(grant.disclosure == .tapTrustGrant(tap))
        #expect(grant.commands.count == 1)
        #expect(grant.warningText.contains("third-party code running as you"))
        _ = center.confirm(grant)
        await settle(center)

        #expect(launcher.spawned.filter { $0.first == "trust" } == [["trust", "acme/tools"]])
    }

    /// Declining is the other half of "explicit": a grant the user did not agree
    /// to must leave nothing behind at all (TM13 :514).
    @Test("Declining a trust grant spawns nothing and enqueues nothing")
    func decliningATrustGrantSpawnsNothing() async throws {
        let launcher = CompositionLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: AppTestFixtures.installation)

        let trustCommand = try #require(TapCommand.trust("acme/tools"))
        let grant = try #require(center.request(trustCommand))
        center.decline(grant)
        await settle(center)

        #expect(center.pendingConfirmation == nil)
        #expect(launcher.spawned.isEmpty, "a declined grant spawned: \(launcher.spawned)")

        // Positively anchored: the same centre does spawn when the answer is yes.
        let agreed = try #require(center.request(trustCommand))
        _ = center.confirm(agreed)
        await settle(center)
        #expect(launcher.spawned == [["trust", "acme/tools"]])
    }

    /// PM10 :348-357 and TM13 :517-523. The refusal carries nothing, so the
    /// recovery's tap comes from Cellar's own snapshot — and it is offered only
    /// when exactly one untrusted tap publishes that exact `(kind, name)`.
    ///
    /// Pressing it opens the **ordinary confirmed** Trust request. It re-runs
    /// nothing: a requalified retry is the one thing that would turn a refusal
    /// into silent execution of code nobody consented to (design R2).
    @Test("The refusal recovery offers Trust only for a unique publisher")
    func theRefusalRecoveryOffersTrustOnlyForAUniquePublisher() async throws {
        let widget = PackageID(kind: .cask, name: "widget")
        let publisher = TapRecord(
            name: "acme/tools",
            repository: "tools",
            caskTokens: ["acme/tools/widget"],
            trust: .untrusted
        )
        let rival = TapRecord(
            name: "other/tools",
            repository: "tools",
            caskTokens: ["other/tools/widget"],
            trust: .untrusted
        )

        // Zero publishers — no button.
        #expect(
            UntrustedTapRecovery.trustableTap(forRefused: widget, in: .empty) == nil
        )
        // Two publishers — no button, because Cellar does not know which tap
        // brew meant and guessing grants the wrong capability.
        #expect(
            UntrustedTapRecovery.trustableTap(
                forRefused: widget,
                in: TapInventory(taps: [publisher, rival])
            ) == nil
        )
        // Exactly one — the button, naming that tap.
        let tap = try #require(
            UntrustedTapRecovery.trustableTap(
                forRefused: widget,
                in: TapInventory(taps: [publisher])
            )
        )

        // Pressing it: the ordinary confirmed grant, and nothing else.
        let launcher = CompositionLauncher()
        let center = OperationCenter(launcherFactory: { _ in launcher })
        center.attach(installation: AppTestFixtures.installation)

        let request = try #require(
            center.request(TapCommand.trustTap(tap)),
            "the recovery submitted a grant without a confirmation"
        )
        #expect(request.disclosure == .tapTrustGrant(tap))
        #expect(request.commands.count == 1, "the recovery bundled a retry with the grant")
        _ = center.confirm(request)
        await settle(center)

        // One spawn, and it is the grant — the refused mutation was not re-run,
        // requalified or otherwise.
        #expect(launcher.spawned == [["trust", "acme/tools"]])
        #expect(launcher.spawned.allSatisfy { argv in argv.allSatisfy { !$0.contains("/widget") } })
    }

    private func settle(_ center: OperationCenter) async {
        for _ in 0..<200 { await Task.yield() }
    }
}
