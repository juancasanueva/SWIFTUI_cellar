import Foundation
import Synchronization
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog
@testable import DiskUsage

@MainActor
@Suite("Cleanup operation spine", .timeLimit(.minutes(1)))
struct CleanupOperationTests {
    @Test("Every cleanup scope records exact identity and refreshes only declared domains")
    func scopeMatrixRecordsAndInvalidatesExactlyOnce() async throws {
        let harness = Harness()
        defer { harness.stop() }
        let cases: [(CleanupScope, String, PackageID?, Set<DiskArea>)] = [
            (.global, "cleanupGlobal", nil, [.cellar, .caskroom, .cache]),
            (.package(PackageTarget(kind: .formula, name: "wget")!), "cleanupPackage",
             PackageID(kind: .formula, name: "wget"), [.cellar, .cache]),
            (.package(PackageTarget(kind: .cask, name: "iterm2")!), "cleanupPackage",
             PackageID(kind: .cask, name: "iterm2"), [.caskroom, .cache]),
            (.full, "cleanupFull", nil, [.cellar, .caskroom, .cache]),
            (.autoremove, "cleanupAutoremove", nil, [.cellar]),
        ]

        for (index, testCase) in cases.enumerated() {
            let preview = Self.preview(scope: testCase.0)
            let source = ScriptedCleanupPreviewSource([.success(preview)])
            let request = try #require(harness.center.requestCleanup(preview: .content(preview)))
            let item = try #require(harness.center.confirmCleanup(
                request,
                source: source,
                detection: .detected(TestInstallation.appleSilicon)
            ))
            await harness.launcher.waitForLaunches(atLeast: index + 1)
            harness.launcher.launchedProcesses[index].terminate(with: BrewExit(status: 0, reason: .exited))
            await harness.poll { item.isTerminal && harness.recorder.drafts.count == index + 1 }

            let draft = harness.recorder.drafts[index]
            #expect(draft.verb == testCase.1)
            #expect(draft.packageID == testCase.2)
            #expect(draft.versions == nil)
            #expect(draft.argv == CleanupCommand(scope: testCase.0).arguments)
            await harness.diskEvents.waitForCount(index + 1)
            #expect(await harness.diskEvents.values[index]?.diskAreas == testCase.3)
        }

        #expect(harness.installedCount.value == cases.count)
        #expect(harness.diskCount.value == cases.count)
        #expect(harness.servicesCount.value == 0)
        #expect(harness.tapsCount.value == 0)
        #expect(harness.recorder.drafts.count == cases.count)
    }

    @Test("All modeled terminals pay history and declared refreshes exactly once")
    func everyTerminalUsesTheSingleFinishFunnel() async throws {
        let harness = Harness(honoursInterrupt: false)
        defer { harness.stop() }
        let processOutcomes: [MutationOutcome] = [
            .succeeded, .failed(status: 7), .busy, .needsPrivileges, .noChange,
            .cancelled, .abandoned(after: .seconds(2)),
        ]

        for (index, outcome) in processOutcomes.enumerated() {
            let item = harness.center.submit(TerminalCleanupProbe(outcome: outcome))
            await harness.launcher.waitForLaunches(atLeast: index + 1)
            harness.launcher.launchedProcesses[index].terminate(with: BrewExit(status: 0, reason: .exited))
            await harness.poll { item.isTerminal }
            #expect(item.outcome == outcome)
        }

        let changed = harness.center.submit(
            TerminalCleanupProbe(outcome: .succeeded),
            authorizer: DenyingCleanupAuthorizer(code: .evidenceChanged)
        )
        let unavailable = harness.center.submit(
            TerminalCleanupProbe(outcome: .succeeded),
            authorizer: DenyingCleanupAuthorizer(code: .evidenceUnavailable)
        )
        await harness.poll { changed.isTerminal && unavailable.isTerminal }
        #expect(changed.outcome == .authorizationDenied(.evidenceChanged))
        #expect(unavailable.outcome == .authorizationDenied(.evidenceUnavailable))

        harness.center.attach(installation: nil)
        let launchFailed = harness.center.submit(TerminalCleanupProbe(outcome: .succeeded))
        #expect(launchFailed.outcome == .launchFailed)
        await harness.settle()

        let expected = processOutcomes.count + 3
        await harness.poll {
            harness.installedCount.value == expected && harness.diskCount.value == expected
        }
        #expect(harness.recorder.drafts.count == expected)
        let recordedOutcomes = harness.recorder.drafts.map(\.outcome)
        for outcome in processOutcomes + [
            .authorizationDenied(.evidenceChanged),
            .authorizationDenied(.evidenceUnavailable),
            .launchFailed,
        ] {
            #expect(recordedOutcomes.count(where: { $0 == outcome }) == 1)
        }
        #expect(harness.installedCount.value == expected)
        #expect(harness.diskCount.value == expected)
        #expect(harness.servicesCount.value == 0)
        #expect(harness.tapsCount.value == 0)
        #expect(harness.launcher.launchCount == processOutcomes.count)
    }

    @Test("Cleanup mutation keeps command-local environment on the authorized spine")
    func operationCenterPreservesCleanupEnvironmentOverrides() async throws {
        let harness = Harness()
        defer { harness.stop() }
        let preview = Self.preview(scope: .full)
        let request = try #require(harness.center.requestCleanup(preview: .content(preview)))
        let item = try #require(harness.center.confirmCleanup(
            request,
            source: ScriptedCleanupPreviewSource([.success(preview)]),
            detection: .detected(TestInstallation.appleSilicon)
        ))
        await harness.launcher.waitForLaunches(atLeast: 1)

        let spec = try #require(harness.launcher.recordedSpecs.first)
        #expect(spec.arguments == ["cleanup", "--prune=all"])
        #expect(spec.environment["HOMEBREW_NO_AUTOREMOVE"] == "1")
        #expect(spec.executableURL == TestInstallation.appleSilicon.executableURL)
        harness.launcher.launchedProcesses[0].terminate(with: BrewExit(status: 0, reason: .exited))
        await harness.poll { item.isTerminal }
    }

    private static func preview(scope: CleanupScope) -> CleanupPreviewResult {
        let request = CleanupPreviewRequest(id: UUID(), scope: scope)
        let stdout = switch scope {
        case .autoremove: "==> Would autoremove 1 unneeded formula:\nwget\n"
        case .global, .package, .full: "Would remove: /cache/a (1B)\n"
        }
        return CleanupParser.parse(request, rawStdout: Data(stdout.utf8), rawStderr: Data())
    }
}

private extension CleanupOperationTests {
    @MainActor
    struct Harness {
        let launcher: ControllableProcessLauncher
        let center: OperationCenter
        let recorder = RecordingHistoryRecorder()
        let installedCount = Counter()
        let diskCount = Counter()
        let servicesCount = Counter()
        let tapsCount = Counter()
        let diskEvents = OptionalEventRecorder()
        let watchers: [Task<Void, Never>]

        init(honoursInterrupt: Bool = true) {
            launcher = ControllableProcessLauncher(honoursInterrupt: honoursInterrupt)
            let installed = InstalledMutationGate()
            let disk = InstalledMutationGate()
            let services = InstalledMutationGate()
            let taps = InstalledMutationGate()
            center = OperationCenter(
                gates: MutationGates([
                    (.installedInventory, installed), (.diskUsage, disk),
                    (.services, services), (.taps, taps),
                ]),
                history: recorder,
                launcherFactory: { [launcher] _ in launcher }
            )
            center.attach(installation: TestInstallation.appleSilicon)
            let installedCount = self.installedCount
            let diskCount = self.diskCount
            let servicesCount = self.servicesCount
            let tapsCount = self.tapsCount
            let diskEvents = self.diskEvents
            watchers = [
                Task { for await _ in installed.terminals { installedCount.increment() } },
                Task { for await event in disk.settlements {
                    diskCount.increment(); await diskEvents.append(event)
                } },
                Task { for await _ in services.terminals { servicesCount.increment() } },
                Task { for await _ in taps.terminals { tapsCount.increment() } },
            ]
        }

        func settle() async { for _ in 0..<200 { await Task.yield() } }
        func poll(until condition: () -> Bool) async {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        }
        func stop() { watchers.forEach { $0.cancel() } }
    }
}

private actor OptionalEventRecorder {
    private(set) var values: [MutationTerminalEvent?] = []
    func append(_ event: MutationTerminalEvent?) { values.append(event) }
    func waitForCount(_ count: Int) async {
        while values.count < count { await Task.yield() }
    }
}

private struct TerminalCleanupProbe: BrewMutating {
    let outcome: MutationOutcome
    private let command = CleanupCommand(scope: .global)
    var arguments: [String] { command.arguments }
    var verb: String { command.verb }
    var packageID: PackageID? { command.packageID }
    var requiresConfirmation: Bool { command.requiresConfirmation }
    var invalidates: InvalidationScope { command.invalidates }
    var diskAreas: Set<DiskArea> { command.diskAreas }
    var environmentOverrides: Set<BrewEnvironment.CommandOverride> { command.environmentOverrides }
    func classify(exit _: BrewExit, fault _: BrewProcessError?, log _: [LogLine]) -> MutationOutcome { outcome }
}

private struct DenyingCleanupAuthorizer: MutationLaunchAuthorizing {
    let code: MutationLaunchDenial.Code
    func authorizeLaunch() async -> MutationLaunchDecision { .deny(.init(code: code)) }
}
