import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

@Suite("Tap commands", .timeLimit(.minutes(1)))
struct TapCommandTests {
    @Test("A canonical target builds exact typed argv and trust disclosure")
    func canonicalAddBuildsExactArgv() throws {
        let command = try #require(TapCommand.add("acme/tools"))

        #expect(command.arguments == ["tap", "acme/tools"])
        #expect(command.verb == "tapAdd")
        #expect(command.requiresConfirmation)
        #expect(command.invalidates == .taps)
        #expect(command.disclosure == .tapTrust(TapName("acme/tools")!))
        #expect(command.displayCommand == "brew tap acme/tools")
    }

    @Test(
        "Hostile and unsupported targets are rejected before command construction",
        arguments: [
            "", " acme/tools", "acme /tools", "-acme/tools", "acme/-tools",
            "acme/tools/extra", "https://example.com/a.git", "git@example.com:a.git"
        ]
    )
    func hostileTargetsAreRejected(raw: String) {
        #expect(TapCommand.add(raw) == nil)
        #expect(TapCommand.untap(raw) == nil)
    }

    @Test("Plain untap is unconfirmed and never gains a force flag")
    func plainUntapIsPrimary() throws {
        let command = try #require(TapCommand.untap("acme/tools"))

        #expect(command.arguments == ["untap", "acme/tools"])
        #expect(command.verb == "tapUntap")
        #expect(command.requiresConfirmation == false)
        #expect(command.invalidates == .taps)
        #expect(command.arguments.contains("--force") == false)
    }

    @Test("Force is available only for a complete current non-empty exact-tap set")
    func forceAvailabilityIsFailClosed() throws {
        let tap = try #require(TapName("acme/tools"))
        let affected: Set<PackageID> = [
            PackageID(kind: .formula, name: "widget"),
            PackageID(kind: .cask, name: "desk")
        ]
        let evidence = ForceUntapEvidence(tap: tap, affected: affected, isComplete: true)

        let request = try #require(TapCommand.forceUntap(evidence: evidence))
        #expect(request.arguments == ["untap", "--force", "acme/tools"])
        #expect(request.verb == "tapForceUntap")
        #expect(request.requiresConfirmation)
        #expect(request.invalidates == [.taps, .installedInventory])
        #expect(request.disclosure == .forceUntap(tap: tap, affected: affected))

        #expect(TapCommand.forceUntap(evidence: ForceUntapEvidence(
            tap: tap,
            affected: [],
            isComplete: true
        )) == nil)
        #expect(TapCommand.forceUntap(evidence: ForceUntapEvidence(
            tap: tap,
            affected: affected,
            isComplete: false
        )) == nil)
    }

    @Test("Queue-front authorization ignores ordering but denies additions removals and kind changes")
    func queueFrontAuthorizationComparesTypedSets() async throws {
        let tap = try #require(TapName("acme/tools"))
        let formula = PackageID(kind: .formula, name: "widget")
        let cask = PackageID(kind: .cask, name: "desk")
        let expected: Set<PackageID> = [formula, cask]

        let reordered = ForceUntapLaunchAuthorizer(tap: tap, expected: expected) {
            ForceUntapEvidence(tap: tap, affected: [cask, formula], isComplete: true)
        }
        #expect(await reordered.authorizeLaunch() == .allow)

        let changed = ForceUntapLaunchAuthorizer(tap: tap, expected: expected) {
            ForceUntapEvidence(
                tap: tap,
                affected: [formula, PackageID(kind: .formula, name: "new")],
                isComplete: true
            )
        }
        #expect(await changed.authorizeLaunch() == .deny(MutationLaunchDenial(code: .evidenceChanged)))

        let unavailable = ForceUntapLaunchAuthorizer(tap: tap, expected: expected) { nil }
        #expect(
            await unavailable.authorizeLaunch()
                == .deny(MutationLaunchDenial(code: .evidenceUnavailable))
        )
    }

    @Test("Disclosure prose cannot rewrite the typed execution vector")
    func disclosureCannotRewriteArgv() throws {
        let command = try #require(TapCommand.add("acme/tools"))
        let request = OperationCenter.ConfirmationRequest(
            id: UUID(),
            command: AnyBrewMutation(command),
            additional: [],
            disclosure: .tapTrust(TapName("acme/tools")!)
        )

        #expect(request.warningText.contains("formulae and casks"))
        #expect(request.command.arguments == ["tap", "acme/tools"])
        #expect(request.displayCommand == "brew tap acme/tools")
    }
}
