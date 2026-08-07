//
//  HealthRemediationTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import Testing

@testable import cellar

/// What a health row actually submits, and whose confirmation it travels under
/// (system-health SH11).
///
/// `HealthComposition.command(for:)` is the whole app-side remediation seam and it
/// lived with no test: correct by construction is a different thing from held
/// there, and the `Catalog` suites cannot reach it because the command types are
/// in `BrewClient` and the routing is in the app target. Two halves, for SH11's
/// two claims — each row pinned to its exact shipped command, then the
/// `SnoozeGuardTests` idiom (anchor, sweep, violation control) over
/// `cellar/Health/`.
@Suite("Health remediation", .timeLimit(.minutes(1)))
struct HealthRemediationTests {
    // MARK: - SH11 sc1 — each remediation submits the verb its owner already ships

    @Test("Every remediation maps to the exact command its owner already ships")
    func everyRemediationMapsToItsOwnersShippedCommand() throws {
        // The anchor: five remediations exist and every one is decided below, so a
        // sixth added without a decision fails here rather than reaching the UI as
        // a silently inert control.
        #expect(HealthRemediation.allCases.count == 5)

        let expected: [HealthRemediation: HealthComposition.Command?] = [
            .upgradeAll: .mutation(.upgradeAll),
            .autoremove: .cleanup(CleanupCommand(scope: .autoremove)),
            .cleanupCache: .cleanup(CleanupCommand(scope: .global)),
            .runDoctor: .runDoctor,
            HealthRemediation.none: nil
        ]

        for remediation in HealthRemediation.allCases {
            let want = try #require(expected[remediation], "\(remediation) has no expected command")
            #expect(
                HealthComposition.command(for: remediation) == want,
                "\(remediation) no longer offers the verb its owning capability ships"
            )
        }
    }

    // MARK: - SH11 sc3 — a remediation keeps its owner's confirmation

    /// The confirmation is the owner's because Health does not build one: it hands
    /// the owner's own command value back to the owner's spine, and the gate reads
    /// that value's own `requiresConfirmation` and `disclosure`.
    @Test("A cleanup remediation keeps Cleanup's confirmation and its disclosure")
    func aCleanupRemediationKeepsItsOwnersConfirmation() throws {
        for (remediation, scope) in [
            (HealthRemediation.autoremove, CleanupScope.autoremove),
            (HealthRemediation.cleanupCache, CleanupScope.global)
        ] {
            let owner = CleanupCommand(scope: scope)
            guard case .cleanup(let offered)? = HealthComposition.command(for: remediation) else {
                Issue.record("\(remediation) no longer offers Cleanup's own command")
                continue
            }

            #expect(offered == owner, "a health row constructed its own \(scope) command")
            #expect(offered.requiresConfirmation, "a health row would run \(scope) with no confirmation")
            #expect(offered.requiresConfirmation == owner.requiresConfirmation)
            // The same disclosure, not merely *a* disclosure: a weaker one is the
            // failure SH11 names, and it is invisible from the argv alone.
            #expect(offered.disclosure == owner.disclosure)
            #expect(offered.disclosure.warningText == owner.disclosure.warningText)
            #expect(offered.arguments == owner.arguments)
        }
    }

    /// Upgrade-all is submitted exactly as the Installed list submits it — which
    /// means Health neither drops a gate nor invents one it has no standing to add.
    @Test("Upgrade-all is Installed's own command, with Installed's own gate")
    func upgradeAllIsInstalledsOwnCommandWithItsOwnGate() throws {
        guard case .mutation(let offered)? = HealthComposition.command(for: .upgradeAll) else {
            Issue.record("the outdated row no longer offers Installed's own upgrade-all")
            return
        }

        #expect(offered == MutationCommand.upgradeAll)
        #expect(offered.arguments == ["upgrade"])
        #expect(offered.verb == "upgradeAll")
        #expect(offered.requiresConfirmation == MutationCommand.upgradeAll.requiresConfirmation)
        // Absolutely as well as relatively: upgrade-all destroys nothing, and
        // inventing a gate here would deviate as much as dropping one.
        #expect(offered.requiresConfirmation == false)
    }

    // MARK: - The structural half — nothing leaves the spine

    @Test("Nothing in cellar/Health submits, spawns or confirms outside the spine")
    func nothingInHealthSubmitsOutsideTheShippedSpine() throws {
        let group = try HealthSources.load()
        #expect(group.count >= 5, "the Health group read as \(group.map(\.name))")

        let view = try #require(group.first { $0.name == "HealthView.swift" }?.code)
        // The anchor: the routing must be present for its absence to mean
        // anything, or the sweep below is equally green over a group that submits
        // nothing.
        #expect(view.contains("HealthComposition.command(for:"))
        #expect(view.contains("operations.submit("))
        #expect(view.contains("operations.requestCleanup("))

        for source in group {
            let found = HealthRemediationScan.bypasses(in: source.code)
            #expect(found.isEmpty, "\(source.name) reaches \(found), which is off the shipped spine")
        }
    }

    /// The violation control. Without it the sweep above is equally green against
    /// a detector that recognises nothing.
    @Test("The bypass detector sees a bypass when there is one")
    func theBypassDetectorSeesAbypassWhenThereIsOne() {
        let offender = """
        private func remediate(_ command: HealthComposition.Command) {
            if command.requiresConfirmation { return }
            Process().launch()
        }
        """
        #expect(HealthRemediationScan.bypasses(in: offender) == ["Process(", "requiresConfirmation"])
        #expect(HealthRemediationScan.bypasses(in: "operations.submit(mutation)").isEmpty)
    }
}

// MARK: - The detector

/// The names a remediation would have to reach for to leave the shipped spine:
/// spawning directly, assembling a raw brew command, re-issuing an erased
/// mutation, authoring a disclosure, reading the owner's gate, or bypassing the
/// operation centre. `request(` deliberately does not match `requestCleanup(`,
/// which *is* the spine.
///
/// Read over comment-stripped source (`HealthSources.load()`), so a rule
/// *described* in a doc comment — `HealthView` explains the confirmation it does
/// not build — is never mistaken for one violated in code.
nonisolated enum HealthRemediationScan {
    static let forbidden = [
        "AnyBrewMutation", "BrewCommand", "ConfirmationDisclosure", "Process(",
        "ProcessLaunching", "request(", "requiresConfirmation", ".mutate("
    ]

    static func bypasses(in code: String) -> [String] {
        forbidden.filter(code.contains).sorted()
    }
}
