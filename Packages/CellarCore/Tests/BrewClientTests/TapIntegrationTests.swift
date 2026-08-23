import CellarTestSupport
import Foundation
import Synchronization
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

@MainActor
@Suite("Tap integration containment", .timeLimit(.minutes(1)))
struct TapIntegrationTests {
    @Test("Tap mutations serialize on the existing FIFO with package mutations")
    func tapMutationsUseSharedFIFO() async throws {
        let harness = CenterHarness()
        let package = harness.center.submit(.install(try #require(PackageTarget(CenterHarness.wget))))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let add = harness.center.submit(try #require(TapCommand.add("acme/tools")))
        let untap = harness.center.submit(try #require(TapCommand.untap("acme/tools")))
        await harness.settle()

        #expect(harness.launcher.launchCount == 1)
        try await harness.finish(call: 0)
        try await harness.finish(call: 1)
        try await harness.finish(call: 2)

        #expect(harness.launcher.recordedSpecs.map(\.arguments) == [
            ["install", "--formula", "wget"],
            ["tap", "acme/tools"],
            ["untap", "acme/tools"]
        ])
        #expect([package, add, untap].allSatisfy { $0.isTerminal })
    }

    @Test("Tap terminals refresh only declared domains exactly once")
    func tapInvalidationIsExactlyScoped() async throws {
        let launcher = ControllableProcessLauncher()
        let tapsGate = InstalledMutationGate()
        let installedGate = InstalledMutationGate()
        let servicesGate = InstalledMutationGate()
        let center = OperationCenter(
            gates: MutationGates([
                (.taps, tapsGate),
                (.installedInventory, installedGate),
                (.services, servicesGate)
            ]),
            launcherFactory: { _ in launcher }
        )
        center.attach(installation: TestInstallation.appleSilicon)
        let taps = Counter()
        let installed = Counter()
        let services = Counter()
        let tapWatcher = Task { for await _ in tapsGate.terminals { taps.increment() } }
        let installedWatcher = Task { for await _ in installedGate.terminals { installed.increment() } }
        let servicesWatcher = Task { for await _ in servicesGate.terminals { services.increment() } }
        let tap = try #require(TapName("acme/tools"))
        let force = try #require(TapCommand.forceUntap(evidence: ForceUntapEvidence(
            tap: tap,
            affected: [PackageID(kind: .formula, name: "widget")],
            isComplete: true
        )))

        _ = center.submit(try #require(TapCommand.add("acme/tools")))
        _ = center.submit(try #require(TapCommand.untap("acme/tools")))
        _ = center.submit(force)
        for index in 0..<3 {
            await launcher.waitForLaunches(atLeast: index + 1)
            launcher.launchedProcesses[index].terminate(with: BrewExit(status: 0, reason: .exited))
            for _ in 0..<100 { await Task.yield() }
        }

        #expect(taps.value == 3)
        #expect(installed.value == 1)
        #expect(services.value == 0)
        tapWatcher.cancel()
        installedWatcher.cancel()
        servicesWatcher.cancel()
    }

    @Test("Denied force emits keyed gates and both coordinators complete one receipt")
    func deniedForceCompletesPostHistoryRefreshReceipt() async throws {
        let registry = MutationRefreshRegistry()
        let tapsGate = InstalledMutationGate()
        let installedGate = InstalledMutationGate()
        let tapSource = IntegrationTapSource()
        let installedSource = FakeInstalledPayloadSource([.formulae(["widget"])])
        let tapStore = TapStore(source: tapSource)
        let installedStore = InstalledStore(source: installedSource)
        let tapCoordinator = TapRefreshCoordinator(
            store: tapStore,
            mutations: tapsGate,
            refreshRegistry: registry
        )
        let installedCoordinator = InstalledRefreshCoordinator(
            store: installedStore,
            mutations: installedGate,
            refreshRegistry: registry
        )
        await tapCoordinator.refresh(using: TestInstallation.appleSilicon)
        await installedCoordinator.refresh(using: TestInstallation.appleSilicon)
        let tapLoop = Task { await tapCoordinator.run() }
        let installedLoop = Task { await installedCoordinator.run() }

        let recorder = RecordingHistoryRecorder()
        let center = OperationCenter(
            gates: MutationGates([(.taps, tapsGate), (.installedInventory, installedGate)]),
            history: recorder,
            launcherFactory: { _ in ControllableProcessLauncher() }
        )
        center.attach(installation: TestInstallation.appleSilicon)
        let token = MutationOperationToken()
        await registry.register(token, domains: [.taps, .installedInventory])
        let waiter = Task { await registry.wait(for: token) }
        let tap = try #require(TapName("acme/tools"))
        let command = try #require(TapCommand.forceUntap(evidence: ForceUntapEvidence(
            tap: tap,
            affected: [PackageID(kind: .formula, name: "widget")],
            isComplete: true
        )))

        let item = center.submit(
            command,
            authorizer: IntegrationDenyingAuthorizer(),
            refreshToken: token
        )
        while !item.isTerminal { await Task.yield() }
        let receipt = try #require(await waiter.value)

        #expect(item.outcome == .authorizationDenied(.evidenceChanged))
        #expect(recorder.drafts.count == 1)
        #expect(receipt.results == [.taps: .refreshed, .installedInventory: .refreshed])
        #expect(tapSource.callCount == 2, "baseline plus one terminal refresh expected")
        #expect(installedSource.callCount == 2, "baseline plus one terminal refresh expected")
        tapLoop.cancel()
        installedLoop.cancel()
    }

    @Test("Tap implementation remains contained from catalog persistence and RDD")
    func structuralContainmentGuards() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let package = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        let tapWire = try source("TapWire.swift", root: root)
        let tapPayload = try source("TapPayloadSource.swift", root: root)
        let tapCommand = try source("TapCommand.swift", root: root)

        #expect(package.contains("name: \"BrewClient\",\n            dependencies: [\"BrewProcess\", \"Catalog\", \"DiskUsage\"]"))
        #expect(tapWire.contains("import Persistence") == false)
        #expect(tapPayload.contains("write(") == false)
        #expect(tapCommand.contains("displayCommand.split") == false)
        #expect(tapCommand.contains("warningText.split") == false)
        #expect(tapCommand.contains("gentle-ai review") == false)
        #expect(tapCommand.contains("receipt") == false)
    }

    private func source(_ file: String, root: URL) throws -> String {
        try String(
            contentsOf: root.appendingPathComponent("Sources/BrewClient/\(file)"),
            encoding: .utf8
        )
    }

    // MARK: - TM7 :257-263 / TM13 :525-531

    /// **DD-5, amended by D4 (2026-08-23).** `brew` refuses to untap a tap that
    /// still owns installed packages — `Refusing to untap acme/tools because it
    /// contains the following installed casks: …`, exit 1. The revocation must
    /// therefore not run in front of it: revoking first and then being refused
    /// leaves the grant gone, the tap still present, and Force Untap hidden
    /// because it is only offered for a *trusted* tap (DD-14) — a loop with no
    /// exit.
    ///
    /// So a refused removal submits **no** revocation at all. No phantom queue
    /// item appears for a command that was never run, and the one failed item
    /// carries brew's own reason.
    @Test("A refused removal submits no revocation")
    func aRefusedRemovalSubmitsNoRevocation() async throws {
        let removal = try #require(TapCommand.removal(of: "acme/tools"))
        let launcher = ControllableProcessLauncher()
        let center = OperationCenter(
            gates: MutationGates(installed: InstalledMutationGate()),
            launcherFactory: { _ in launcher }
        )
        center.attach(installation: TestInstallation.appleSilicon)

        _ = center.submitDependentSequence(removal)

        // The removal leads, and brew refuses it.
        await launcher.waitForLaunches(atLeast: 1)
        launcher.launchedProcesses[0].emitStderr(
            "Error: Refusing to untap acme/tools because it contains the following "
                + "installed casks:\nacme/tools/desk\n"
        )
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 1, reason: .exited))
        await settle()
        await settle()

        // Nothing followed it. Not "eventually", and not "not yet": there is one
        // spawned process, and no `untrust` argv ever reached the launcher.
        #expect(launcher.recordedSpecs.map(\.arguments) == [["untap", "acme/tools"]])
        #expect(launcher.recordedSpecs.contains { $0.arguments.contains("untrust") } == false)

        // One visible operation, carrying brew's own reason.
        let items = center.items
        #expect(items.count == 1)
        #expect(items.map(\.command.verb) == ["tapUntap"])
        #expect(items.map(\.outcome) == [.failed(status: 1)])
        #expect(
            items.first?.log.contains { $0.text.contains("Refusing to untap") } == true,
            "the refused removal did not surface brew's reason"
        )
    }

    /// **D4, the other half.** The grant still never outlives a removal brew
    /// *accepted* (TM13.6): the revocation follows, unconditionally, the moment
    /// the removal settles as succeeded — and `brew untrust` on a never-trusted
    /// tap exits 0 (obs #7722), so there is nothing to check before submitting
    /// it.
    @Test("A successful removal is followed by the revocation")
    func aSuccessfulRemovalIsFollowedByTheRevocation() async throws {
        let removal = try #require(TapCommand.removal(of: "acme/tools"))
        let launcher = ControllableProcessLauncher()
        let center = OperationCenter(
            gates: MutationGates(installed: InstalledMutationGate()),
            launcherFactory: { _ in launcher }
        )
        center.attach(installation: TestInstallation.appleSilicon)

        _ = center.submitDependentSequence(removal)

        // Only the removal is enqueued up front: the revocation is not a queued
        // command waiting its turn, it does not exist yet.
        await launcher.waitForLaunches(atLeast: 1)
        #expect(center.items.count == 1)
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))

        // …and now it does.
        await launcher.waitForLaunches(atLeast: 2)
        launcher.launchedProcesses[1].terminate(with: BrewExit(status: 0, reason: .exited))
        await settle()

        #expect(launcher.recordedSpecs.map(\.arguments) == [
            ["untap", "acme/tools"],
            ["untrust", "acme/tools"]
        ])
        let items = center.items
        #expect(items.count == 2)
        #expect(items.map(\.command.verb) == ["tapUntap", "tapUntrust"])
        #expect(items.map(\.outcome) == [.succeeded, .succeeded])
    }

    /// TM13 :525-531 and obs #7722. `brew trust` on an already-trusted tap and
    /// `brew untrust` on a never-trusted one both exit 0. Reporting either as a
    /// failure — or worse, as a Cellar defect — would train the user to ignore a
    /// failed trust operation, which is the one they must never ignore.
    @Test("An idempotent grant or revocation is an ordinary success")
    func anIdempotentGrantOrRevocationIsAnOrdinarySuccess() async throws {
        let launcher = ControllableProcessLauncher()
        let center = OperationCenter(
            gates: MutationGates(installed: InstalledMutationGate()),
            launcherFactory: { _ in launcher }
        )
        center.attach(installation: TestInstallation.appleSilicon)

        let regrant = center.submit(try #require(TapCommand.trust("acme/tools")))
        await launcher.waitForLaunches(atLeast: 1)
        launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        await settle()

        let neverTrusted = center.submit(try #require(TapCommand.untrust("other/home")))
        await launcher.waitForLaunches(atLeast: 2)
        launcher.launchedProcesses[1].terminate(with: BrewExit(status: 0, reason: .exited))
        await settle()

        #expect(regrant.outcome == .succeeded)
        #expect(neverTrusted.outcome == .succeeded)
        #expect(regrant.outcome?.isFailure == false)
        #expect(neverTrusted.outcome?.isFailure == false)
        #expect(regrant.isTerminal)
        #expect(neverTrusted.isTerminal)
        #expect(launcher.recordedSpecs.map(\.arguments) == [
            ["trust", "acme/tools"],
            ["untrust", "other/home"]
        ])
    }

    private func settle() async {
        for _ in 0..<500 { await Task.yield() }
    }
}

private struct IntegrationDenyingAuthorizer: MutationLaunchAuthorizing {
    func authorizeLaunch() async -> MutationLaunchDecision {
        .deny(MutationLaunchDenial(code: .evidenceChanged))
    }
}

private final class IntegrationTapSource: TapPayloadSourcing, Sendable {
    private let calls = Mutex(0)
    var callCount: Int { calls.withLock { $0 } }

    func payload(using _: BrewInstallation) async throws(TapInventoryError) -> Data {
        calls.withLock { $0 += 1 }
        return Data("[{\"name\":\"acme/tools\",\"repo\":\"tools\"}]".utf8)
    }
}
