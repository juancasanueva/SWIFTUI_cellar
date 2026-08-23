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
        #expect(command.disclosure == .tapAdd(TapName("acme/tools")!))
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
        #expect(request.invalidates == [.taps, .installedInventory, .diskUsage])
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
            disclosure: .tapAdd(TapName("acme/tools")!)
        )

        #expect(request.warningText.contains("clones a third-party repository"))
        #expect(request.command.arguments == ["tap", "acme/tools"])
        #expect(request.displayCommand == "brew tap acme/tools")
    }

    // MARK: - TM13 — trust is granted and revoked only by an explicit answer

    /// TM13 :500-506. Two literal verbs plus the validated tap identity, and
    /// nothing else: no kind flag, no package position, no interpolation. Trust
    /// is a property of a **tap**, so `packageID` is `nil` for both — which is
    /// also what keeps a qualified package token out of these argvs by
    /// construction rather than by review.
    @Test("Trust and untrust lower to literal argv and carry no package identity")
    func trustAndUntrustLowerToLiteralArgv() throws {
        let trust = try #require(TapCommand.trust("acme/tools"))
        let untrust = try #require(TapCommand.untrust("acme/tools"))

        #expect(trust.arguments == ["trust", "acme/tools"])
        #expect(untrust.arguments == ["untrust", "acme/tools"])
        #expect(trust.verb == "tapTrust")
        #expect(untrust.verb == "tapUntrust")
        #expect(trust.packageID == nil)
        #expect(untrust.packageID == nil)
        #expect(trust.displayCommand == "brew trust acme/tools")
        #expect(untrust.displayCommand == "brew untrust acme/tools")

        // No kind flag and no extra token, in either direction.
        for command in [trust, untrust] {
            #expect(command.arguments.count == 2)
            #expect(command.arguments.contains("--formula") == false)
            #expect(command.arguments.contains("--cask") == false)
            #expect(command.arguments.dropFirst() == ["acme/tools"])
        }

        // The same gate every tap target passes; a hostile target builds nothing.
        for hostile in ["", " acme/tools", "acme/tools/extra", "https://example.com/a.git"] {
            #expect(TapCommand.trust(hostile) == nil)
            #expect(TapCommand.untrust(hostile) == nil)
        }
    }

    /// TM13 :482-494, PM3 :253-268. A grant lets Homebrew load and run
    /// third-party code as the user, so it is confirmed. A revocation only
    /// *reduces* authority, so it is not — and presenting it as destructive
    /// would teach the user to dismiss the sheet that matters.
    ///
    /// Both invalidate installed inventory as well as taps, because a trust
    /// change is exactly what makes `brew info --installed` start or stop
    /// reporting a package's `tap` (obs #7724).
    @Test("Only the grant is confirmed, and both invalidate installed inventory")
    func onlyTheGrantIsConfirmedAndBothInvalidateInstalledInventory() throws {
        let tap = try #require(TapName("acme/tools"))
        let trust = try #require(TapCommand.trust("acme/tools"))
        let untrust = try #require(TapCommand.untrust("acme/tools"))

        #expect(trust.requiresConfirmation)
        #expect(untrust.requiresConfirmation == false)
        // PM3 :253 — the grant carries the typed grant disclosure, not the add's.
        #expect(trust.disclosure == .tapTrustGrant(tap))
        #expect(trust.disclosure != .tapAdd(tap))
        // PM3 :262 — the revocation passes the gate without a confirmation, so
        // whatever it would have shown is never presented. WU5's `unit 8` pins
        // that it declares nothing of its own.

        #expect(trust.invalidates == [.taps, .installedInventory])
        #expect(untrust.invalidates == [.taps, .installedInventory])
        // Neither touches a keg or a caskroom, so neither remeasures disk.
        #expect(trust.diskAreas.isEmpty)
        #expect(untrust.diskAreas.isEmpty)

        // The control: the two commands that do *not* refresh the inventory
        // still do not, so this is a statement about trust rather than about
        // every tap command.
        #expect(try #require(TapCommand.add("acme/tools")).invalidates == .taps)
        #expect(try #require(TapCommand.untap("acme/tools")).invalidates == .taps)
    }
}
