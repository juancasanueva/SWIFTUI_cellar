import CellarTestSupport
import Catalog
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// One mutation at a time, across both sources (`package-mutation` —
/// "Mutations are serialized across sources through one FIFO"; design D13).
///
/// The serialisation is imposed at the **centre**, not inside either runner:
/// each runner keeps its own per-instance FIFO, and the chain here is what makes
/// a brew mutation submitted after an npm one wait for it. That is also why the
/// queue-phase question below is worth a test of its own — a chain-queued item
/// is deliberately absent from its runner's snapshot until its turn comes.
@MainActor
@Suite("Cross-source FIFO", .timeLimit(.minutes(1)))
struct CrossSourceFIFOTests {
    private static let typescript = PackageID(kind: .npm, name: "typescript")
    private static let corepack = PackageID(kind: .npm, name: "corepack")

    private static func npmUpgrade(_ id: PackageID = typescript) throws -> NpmCommand {
        .upgrade(try #require(NpmPackageTarget(id)))
    }

    private static func attached() -> CenterHarness {
        let harness = CenterHarness(attached: true)
        harness.center.attach(npm: NpmEnvironmentFixture.detected)
        return harness
    }

    // MARK: - Submission order, whatever the source

    @Test("A brew mutation waits for an in-flight npm mutation")
    func brewWaitsForNpm() async throws {
        let harness = Self.attached()

        let npm = harness.center.submit(try Self.npmUpgrade())
        let brew = harness.center.submit(try #require(MutationCommand.upgrade(formula: "wget")))
        await TestPoll.until(harness.launcher.launchCount >= 1)
        await harness.settle()

        // Exactly one process exists, and it is npm's.
        #expect(harness.launcher.launchCount == 1)
        #expect(
            harness.launcher.recordedSpecs.first?.executableURL
                == NpmEnvironmentFixture.detected.executableURL
        )
        #expect(npm.isTerminal == false)
        #expect(brew.isTerminal == false)
        #expect(brew.queuePhase == .pending)

        try await harness.finish(call: 0, status: 0)

        // Only once npm reached its terminal outcome does brew spawn.
        await TestPoll.until(harness.launcher.launchCount >= 2)
        #expect(npm.outcome == .succeeded)
        #expect(
            harness.launcher.recordedSpecs.last?.executableURL
                == TestInstallation.appleSilicon.executableURL
        )

        try await harness.finish(call: 1, status: 0)
        #expect(brew.outcome == .succeeded)
    }

    /// Triangulation, in the other direction: the rule is about submission
    /// order, not about which source happens to be first.
    @Test("An npm mutation waits for an in-flight brew mutation")
    func npmWaitsForBrew() async throws {
        let harness = Self.attached()

        let brew = harness.center.submit(try #require(MutationCommand.upgrade(formula: "wget")))
        let npm = harness.center.submit(try Self.npmUpgrade())
        await TestPoll.until(harness.launcher.launchCount >= 1)
        await harness.settle()

        #expect(harness.launcher.launchCount == 1)
        #expect(
            harness.launcher.recordedSpecs.first?.executableURL
                == TestInstallation.appleSilicon.executableURL
        )
        #expect(npm.queuePhase == .pending)

        try await harness.finish(call: 0, status: 0)
        await TestPoll.until(harness.launcher.launchCount >= 2)
        #expect(brew.outcome == .succeeded)
        #expect(
            harness.launcher.recordedSpecs.last?.executableURL
                == NpmEnvironmentFixture.detected.executableURL
        )
    }

    @Test("Three mixed submissions spawn strictly in submission order")
    func threeMixedSubmissionsKeepTheirOrder() async throws {
        let harness = Self.attached()

        harness.center.submit(try #require(MutationCommand.upgrade(formula: "wget")))
        harness.center.submit(try Self.npmUpgrade())
        harness.center.submit(try #require(MutationCommand.upgrade(cask: "iterm2")))

        for index in 0..<3 {
            await TestPoll.until(harness.launcher.launchCount >= index + 1)
            #expect(harness.launcher.launchCount == index + 1, "call \(index) overlapped its predecessor")
            try await harness.finish(call: index, status: 0)
        }

        #expect(harness.launcher.recordedSpecs.map(\.arguments) == [
            ["upgrade", "--formula", "wget"],
            ["install", "-g", "typescript@latest"],
            ["upgrade", "--cask", "iterm2"],
        ])
    }

    // MARK: - The enumeration a person reads

    /// The D13 open question, answered by test: a chain-queued brew item has no
    /// runner snapshot to take a phase from, so it must still *read* as queued.
    @Test("A chained item reads as queued before its turn")
    func chainedItemReadsAsQueued() async throws {
        let harness = Self.attached()

        let npm = harness.center.submit(try Self.npmUpgrade())
        let brew = harness.center.submit(try #require(MutationCommand.upgrade(formula: "wget")))
        await TestPoll.until(harness.launcher.launchCount >= 1)
        await harness.settle()

        #expect(npm.isRunning, "the in-flight item is not reported running")
        #expect(brew.isPending, "the chained item is not reported pending")
        #expect(brew.queuePhase == .pending)
        #expect(brew.statusLabel == "Queued")
        #expect(brew.isCancellable)
        #expect(harness.center.summary.pendingCount == 1)
        #expect(harness.center.summary.running === npm)

        try await harness.finish(call: 0, status: 0)
        try await harness.finish(call: 1, status: 0)
    }

    // MARK: - Cancelling before a turn

    @Test("Cancelling a chain-queued item settles it immediately and never spawns it")
    func cancellingAChainQueuedItemNeverSpawnsIt() async throws {
        let harness = Self.attached()

        let npm = harness.center.submit(try Self.npmUpgrade())
        let brew = harness.center.submit(try #require(MutationCommand.upgrade(formula: "wget")))
        await TestPoll.until(harness.launcher.launchCount >= 1)
        await harness.settle()

        harness.center.cancel(brew)

        // Immediately: not after the predecessor settles.
        #expect(brew.outcome == .cancelled)
        #expect(brew.isTerminal)
        #expect(harness.launcher.launchCount == 1)

        try await harness.finish(call: 0, status: 0)
        await harness.settle()

        #expect(npm.outcome == .succeeded)
        #expect(harness.launcher.launchCount == 1, "the cancelled item spawned when its turn came")
        #expect(harness.recorder.drafts.count == 2)
        #expect(harness.recorder.drafts.map(\.outcome).contains(.cancelled))
    }

    /// And the successor of a cancelled item still runs: cancelling one member
    /// must not strand the chain behind it.
    @Test("The item behind a cancelled one still takes its turn")
    func theChainSurvivesACancellation() async throws {
        let harness = Self.attached()

        harness.center.submit(try Self.npmUpgrade())
        let cancelled = harness.center.submit(try #require(MutationCommand.upgrade(formula: "wget")))
        let last = harness.center.submit(try Self.npmUpgrade(Self.corepack))
        await TestPoll.until(harness.launcher.launchCount >= 1)
        await harness.settle()

        harness.center.cancel(cancelled)
        try await harness.finish(call: 0, status: 0)
        await TestPoll.until(harness.launcher.launchCount >= 2)
        try await harness.finish(call: 1, status: 0)

        #expect(last.outcome == .succeeded)
        #expect(harness.launcher.recordedSpecs.map(\.arguments) == [
            ["install", "-g", "typescript@latest"],
            ["install", "-g", "corepack@latest"],
        ])
    }

    // MARK: - Reads are never blocked by a mutation of either source

    @Test("A read of either source proceeds during an npm mutation")
    func readsAreNotBlockedByAMutation() async throws {
        let harness = Self.attached()
        let npmReads = RecordingProcessLauncher([ScriptedRun(stdout: "{\"dependencies\":{}}\n")])
        let brewReads = RecordingProcessLauncher()

        harness.center.submit(try Self.npmUpgrade())
        await TestPoll.until(harness.launcher.launchCount >= 1)

        // The mutation is still in flight: nothing has terminated it.
        #expect(harness.launcher.launchedProcesses.first?.hasTerminated == false)

        let globals = try await NpmPayloadSource(launcher: npmReads)
            .installed(using: NpmEnvironmentFixture.detected)
        let brewRunner = BrewRunner(
            installation: TestInstallation.appleSilicon,
            launcher: brewReads
        )
        let read = try await brewRunner.start(.read(["info", "--installed", "--json=v2"]))
        _ = await read.exit()

        #expect(globals.isEmpty == false)
        #expect(npmReads.specs.map(\.arguments) == [["ls", "-g", "--json", "--depth=0"]])
        #expect(brewReads.specs.map(\.arguments) == [["info", "--installed", "--json=v2"]])
        #expect(harness.launcher.launchedProcesses.first?.hasTerminated == false)

        try await harness.finish(call: 0, status: 0)
    }
}
