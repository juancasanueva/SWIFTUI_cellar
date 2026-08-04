import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

@MainActor
@Suite("Force denial recovery", .timeLimit(.minutes(1)))
struct ForceDenialRecoveryTests {
    @Test("Operation center reconfirms force untap from freshly refreshed evidence")
    func operationCenterReconfirmsFromFreshEvidence() async throws {
        let registry = MutationRefreshRegistry()
        let installedGate = InstalledMutationGate()
        let tapGate = InstalledMutationGate()
        let launcher = ControllableProcessLauncher()
        let center = OperationCenter(
            gates: MutationGates([
                (.installedInventory, installedGate),
                (.taps, tapGate)
            ]),
            refreshRegistry: registry,
            launcherFactory: { [launcher] _ in launcher }
        )
        center.attach(installation: TestInstallation.appleSilicon)

        _ = center.submit(ProbeMutation(arguments: ["hold"]))
        await launcher.waitForLaunches(atLeast: 1)

        let tap = try #require(TapName("acme/tools"))
        let evidence = EvidenceBox(ForceUntapEvidence(
            tap: tap,
            affected: [PackageID(kind: .formula, name: "widget")],
            isComplete: true
        ))
        let command = try #require(TapCommand.forceUntap(evidence: evidence.value))
        let request = try #require(center.request(command))
        let forceItem = try #require(await center.confirmForceUntap(request) { evidence.value })

        evidence.value = ForceUntapEvidence(
            tap: tap,
            affected: [
                PackageID(kind: .formula, name: "widget"),
                PackageID(kind: .cask, name: "widget-app")
            ],
            isComplete: true
        )
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        await settle()

        #expect(forceItem.outcome == .authorizationDenied(.evidenceChanged))
        #expect(launcher.launchCount == 1)
        let token = try #require(forceItem.refreshToken)
        let url = TestInstallation.appleSilicon.executableURL
        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .taps, installationURL: url),
            with: .refreshed
        ))
        await settle()
        #expect(center.pendingConfirmation == nil)

        #expect(await registry.complete(
            MutationTerminalEvent(token: token, domain: .installedInventory, installationURL: url),
            with: .refreshed
        ))
        await settle()

        #expect(center.pendingConfirmation?.displayCommand == "brew untap --force acme/tools")
        #expect(Set(center.pendingConfirmation?.affectedPackages.map(\.name) ?? []) == ["widget", "widget-app"])
    }

    @Test("Denial waits for both successful refresh receipts before rebuilding evidence")
    func denialWaitsForBothRefreshes() async throws {
        let registry = MutationRefreshRegistry()
        let box = ConfirmationBox()
        let coordinator = ForceDenialRecoveryCoordinator(registry: registry, confirmations: box)
        let installationURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        let expectation = await coordinator.begin(
            supersessionKey: "acme/tools",
            isEligible: { true }
        )
        var evidenceBuilds = 0

        coordinator.authorizationDenied(expectation) {
            evidenceBuilds += 1
            return self.request("untap", "--force", "acme/tools")
        }
        #expect(await registry.complete(
            MutationTerminalEvent(
                token: expectation.token,
                domain: .taps,
                installationURL: installationURL
            ),
            with: .refreshed
        ))
        await settle()
        #expect(evidenceBuilds == 0)
        #expect(box.pending == nil)

        #expect(await registry.complete(
            MutationTerminalEvent(
                token: expectation.token,
                domain: .installedInventory,
                installationURL: installationURL
            ),
            with: .refreshed
        ))
        await settle()

        #expect(evidenceBuilds == 1)
        #expect(box.pending?.displayCommand == "brew untap --force acme/tools")
    }

    @Test("Failure, absence, installation change, cancellation and teardown never reconfirm")
    func nonRefreshedReceiptNeverReconfirms() async {
        for result in [
            RefreshResult.failed,
            .brewUnavailable,
            .installationChanged,
            .cancelled,
            .teardown
        ] {
            let registry = MutationRefreshRegistry()
            let box = ConfirmationBox()
            let coordinator = ForceDenialRecoveryCoordinator(registry: registry, confirmations: box)
            let expectation = await coordinator.begin(
                supersessionKey: "acme/tools",
                isEligible: { true }
            )
            var evidenceBuilds = 0
            coordinator.authorizationDenied(expectation) {
                evidenceBuilds += 1
                return self.request("untap", "--force", "acme/tools")
            }
            let url = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
            _ = await registry.complete(
                MutationTerminalEvent(token: expectation.token, domain: .taps, installationURL: url),
                with: result
            )
            _ = await registry.complete(
                MutationTerminalEvent(
                    token: expectation.token,
                    domain: .installedInventory,
                    installationURL: url
                ),
                with: .refreshed
            )
            await settle()
            #expect(evidenceBuilds == 0, "\(result) rebuilt stale evidence")
            #expect(box.pending == nil)
        }
    }

    @Test("A non-denial terminal cancels the expectation and can never promote")
    func nonDenialCancelsExpectation() async {
        let registry = MutationRefreshRegistry()
        let box = ConfirmationBox()
        let coordinator = ForceDenialRecoveryCoordinator(registry: registry, confirmations: box)
        let expectation = await coordinator.begin(
            supersessionKey: "acme/tools",
            isEligible: { true }
        )

        coordinator.finish(expectation)
        await settle()

        #expect(await registry.isRegistered(expectation.token) == false)
        #expect(box.pending == nil)
    }

    private func request(_ arguments: String...) -> OperationCenter.ConfirmationRequest {
        OperationCenter.ConfirmationRequest(
            id: UUID(),
            command: AnyBrewMutation(ProbeMutation(arguments: arguments)),
            additional: []
        )
    }

    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }
}

@MainActor
private final class EvidenceBox {
    var value: ForceUntapEvidence

    init(_ value: ForceUntapEvidence) {
        self.value = value
    }
}
