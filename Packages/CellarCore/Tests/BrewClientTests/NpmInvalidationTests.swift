import CellarTestSupport
import Catalog
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// The fifth invalidation domain: what an npm terminal outcome refreshes, and
/// what it must leave alone (`npm-source` — an npm mutation's terminal outcome
/// forces exactly one npm refresh; design D11).
///
/// The npm reads are driven through a **real** `NpmPayloadSource` over a
/// recording launcher, so "exactly one `ls -g` and one `outdated -g`, and no
/// `brew info --installed --json=v2`" is a claim about literal argv rather than
/// about a counter standing in for one — the same discipline
/// `MutationGatesTests` uses for brew.
@MainActor
@Suite("npm invalidation", .timeLimit(.minutes(1)))
struct NpmInvalidationTests {
    private static let typescript = PackageID(kind: .npm, name: "typescript")

    private static func npmUpgrade() throws -> NpmCommand {
        .upgrade(try #require(NpmPackageTarget(typescript)))
    }

    // MARK: - The domain itself

    @Test("The npm domain is its own bit, disjoint from every brew domain")
    func npmDomainIsItsOwnBit() {
        #expect(InvalidationScope.npmInventory.rawValue == 1 << 4)

        let brew: InvalidationScope = [.installedInventory, .services, .taps, .diskUsage]
        #expect(brew.rawValue == 0b1111)
        #expect(InvalidationScope.npmInventory.isDisjoint(with: brew))
    }

    /// The scope has to reach a `RefreshDomain`, or the gate would settle with a
    /// `nil` event and no receipt consumer could ever be told which domain ran.
    @Test("The npm scope maps to the npm refresh domain")
    func npmScopeMapsToItsDomain() async throws {
        let npmGate = InstalledMutationGate()
        let installedGate = InstalledMutationGate()
        let gates = MutationGates([
            (.installedInventory, installedGate),
            (.npmInventory, npmGate),
        ])
        let token = MutationOperationToken()
        var iterator = npmGate.settlements.makeAsyncIterator()

        gates.begin(.npmInventory)
        gates.end(
            .npmInventory,
            token: token,
            installationURL: NpmEnvironmentFixture.detected.executableURL
        )
        let event = try #require(await iterator.next())

        #expect(event?.domain == .npmInventory)
        #expect(event?.token == token)
        #expect(event?.diskAreas.isEmpty == true)
        #expect(installedGate.isMutating == false)
    }

    // MARK: - One open, one end, per npm terminal

    @Test("An npm terminal opens and closes the npm gate exactly once")
    func npmTerminalSettlesItsGateOnce() async throws {
        let harness = Harness()
        defer { harness.stop() }

        harness.center.submit(try Self.npmUpgrade())
        await harness.settle()
        #expect(harness.npmGate.isMutating, "the npm gate never opened")
        #expect(harness.installedGate.isMutating == false, "an npm command opened the brew gate")

        try await harness.finishMutation(status: 0)

        #expect(harness.npmGate.isMutating == false)
        #expect(harness.npmTerminals.value == 1)
        #expect(harness.installedTerminals.value == 0)
    }

    /// Triangulation: the obligation is a property of *what ran*, not of how it
    /// ended, so a failure and a cancellation each owe exactly one too.
    @Test(
        "Every terminal an npm mutation can reach owes exactly one npm refresh",
        arguments: [
            (Int32(0), BrewExit.Reason.exited),
            (Int32(1), BrewExit.Reason.exited),
            (Int32(130), BrewExit.Reason.cancelled(signal: SIGINT)),
        ]
    )
    func everyNpmTerminalOwesOneRefresh(status: Int32, reason: BrewExit.Reason) async throws {
        let harness = Harness()
        defer { harness.stop() }

        harness.center.submit(try Self.npmUpgrade())
        try await harness.finishMutation(status: status, reason: reason)

        #expect(harness.npmTerminals.value == 1)
        #expect(harness.installedTerminals.value == 0)
    }

    // MARK: - What the refresh actually spawns

    @Test("An npm terminal produces one ls and one outdated, and no brew probe")
    func npmTerminalRefreshesOnlyNpm() async throws {
        let harness = Harness()
        defer { harness.stop() }

        #expect(harness.npmProbes.isEmpty, "something refreshed npm before any mutation ran")

        harness.center.submit(try Self.npmUpgrade())
        try await harness.finishMutation(status: 0)
        await harness.settle()

        #expect(harness.npmProbes == [
            ["ls", "-g", "--json", "--depth=0"],
            ["outdated", "-g", "--json"],
        ])
        #expect(harness.brewProbes.isEmpty, "an npm terminal forced a brew re-snapshot")
    }

    /// And the mirror image: a brew terminal refreshes brew and never reaches
    /// npm, so the two domains are independent in both directions.
    @Test("A brew terminal never spawns an npm read")
    func brewTerminalNeverRefreshesNpm() async throws {
        let harness = Harness()
        defer { harness.stop() }

        harness.center.submit(try #require(MutationCommand.upgrade(formula: "wget")))
        try await harness.finishMutation(status: 0)
        await harness.settle()

        #expect(harness.installedTerminals.value == 1)
        #expect(harness.npmTerminals.value == 0)
        #expect(harness.npmProbes.isEmpty)
    }

    // MARK: - Harness

    /// The spine wired the way the app wires it, with the npm domain added as a
    /// fifth gate whose terminals drive npm's two reads.
    @MainActor
    private struct Harness {
        let mutations = ControllableProcessLauncher()
        /// Everything npm's reads spawn. Its specs are the evidence.
        let npmLauncher = RecordingProcessLauncher([
            ScriptedRun(stdout: "{\"dependencies\":{}}\n"),
            ScriptedRun(stdout: "{}\n"),
        ])
        /// Everything brew's inventory refresh spawns.
        let brewLauncher = RecordingProcessLauncher()
        let installedGate = InstalledMutationGate()
        let npmGate = InstalledMutationGate()
        let npmStore: NpmStore
        let center: OperationCenter
        let installedTerminals = Counter()
        let npmTerminals = Counter()
        private let watchers: [Task<Void, Never>]

        var npmProbes: [[String]] { npmLauncher.specs.map(\.arguments) }
        var brewProbes: [[String]] { brewLauncher.specs.map(\.arguments) }

        init() {
            let installed = InstalledStore(source: BrewInfoPayloadSource(launcher: brewLauncher))
            npmStore = NpmStore(installed: installed, source: NpmPayloadSource(launcher: npmLauncher))
            let mutations = mutations
            center = OperationCenter(
                gates: MutationGates([
                    (.installedInventory, installedGate),
                    (.npmInventory, npmGate),
                ]),
                launcherFactory: { _ in mutations }
            )
            center.attach(installation: TestInstallation.appleSilicon)
            center.attach(npm: NpmEnvironmentFixture.detected)

            let installedTerminals = installedTerminals
            let npmTerminals = npmTerminals
            let npmStore = npmStore
            watchers = [
                Task { [stream = installedGate.terminals] in
                    for await _ in stream { installedTerminals.increment() }
                },
                // The stand-in for `NpmRefreshCoordinator`, which unit 3 owns:
                // one listing and one outdated check per npm terminal, which is
                // exactly the obligation this suite is counting.
                Task { [stream = npmGate.terminals] in
                    for await _ in stream {
                        npmTerminals.increment()
                        await npmStore.refreshListing(using: NpmEnvironmentFixture.detected)
                        await npmStore.refreshOutdated(using: NpmEnvironmentFixture.detected)
                    }
                },
            ]
        }

        func stop() {
            for watcher in watchers { watcher.cancel() }
        }

        func settle() async {
            for _ in 0..<300 { await Task.yield() }
        }

        func finishMutation(
            status: Int32,
            reason: BrewExit.Reason = .exited
        ) async throws {
            await TestPoll.until(self.mutations.launchCount >= 1)
            let process = try #require(mutations.launchedProcesses.first, "no mutation was spawned")
            process.terminate(with: BrewExit(status: status, reason: reason))
            await settle()
        }
    }
}
