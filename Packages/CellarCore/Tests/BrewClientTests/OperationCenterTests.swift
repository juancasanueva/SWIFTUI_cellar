import CellarTestSupport
import Foundation
import Synchronization
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// The store that turns a typed command into a queue item, drives the mutation
/// gate, and projects both the always-visible summary and the detail list.
///
/// Built on the `InstalledStore` exemplar — one `@MainActor @Observable` class,
/// acquisition below it — and covering the rules the SwiftUI views read, so the
/// app target owns no rule at all (design D4, D10). Nothing spawns `brew` and
/// nothing mutates a real Homebrew (D12).
@MainActor
@Suite("Operation center", .timeLimit(.minutes(1)))
struct OperationCenterTests {
    // MARK: - Fixtures

    private static let wget = PackageID(kind: .formula, name: "wget")
    private static let git = PackageID(kind: .formula, name: "git")
    private static let iterm = PackageID(kind: .cask, name: "iterm2")

    private struct Harness {
        let launcher: ControllableProcessLauncher
        let gate: InstalledMutationGate
        let center: OperationCenter
    }

    private func harness(attached: Bool = true) -> Harness {
        let launcher = ControllableProcessLauncher()
        let gate = InstalledMutationGate()
        let center = OperationCenter(gate: gate, launcherFactory: { _ in launcher })
        if attached {
            center.attach(installation: TestInstallation.appleSilicon)
        }
        return Harness(launcher: launcher, gate: gate, center: center)
    }

    private func settle() async {
        for _ in 0..<200 { await Task.yield() }
    }

    /// Main-actor polling, for the places a fixed number of yields is not
    /// enough — draining two thousand lines crosses a stream and an actor hop.
    ///
    /// `TestPoll` cannot serve here: its condition is `@Sendable`, so it would
    /// have to be evaluated off the main actor.
    private func poll(until condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
    }

    /// Terminates the `index`-th spawned process and lets the center observe it.
    private func finish(
        _ harness: Harness,
        call index: Int,
        status: Int32 = 0
    ) async {
        await harness.launcher.waitForLaunches(atLeast: index + 1)
        harness.launcher.launchedProcesses[index]
            .terminate(with: BrewExit(status: status, reason: .exited))
        await settle()
    }

    // MARK: - One submission, one item (OA2 sc1–2)

    @Test("A submission produces one item whose identity and copy text never change")
    func aSubmissionProducesOneStableItem() async throws {
        let harness = harness()
        let command = MutationCommand.install(Self.iterm)

        let item = harness.center.submit(command)
        await settle()

        let id = item.id
        let pendingCopy = item.copyText
        #expect(harness.center.items.count == 1)
        #expect(item.displayCommand == "brew install --cask iterm2")
        #expect(pendingCopy == "brew install --cask iterm2")

        await finish(harness, call: 0)

        #expect(item.id == id, "the identity changed between states")
        #expect(item.copyText == pendingCopy, "copy text differed once terminal")
        #expect(item.displayCommand == "brew install --cask iterm2")
        #expect(item.outcome == .succeeded)
        #expect(item.isTerminal)
    }

    @Test("The item carries the exact argv in every state")
    func theItemCarriesTheExactArgv() async throws {
        let harness = harness()
        let item = harness.center.submit(.install(Self.iterm))
        await settle()

        #expect(item.arguments == ["install", "--cask", "iterm2"])
        await finish(harness, call: 0)
        #expect(item.arguments == ["install", "--cask", "iterm2"])

        // And that is the vector that reached the process seam.
        #expect(harness.launcher.recordedSpecs.map(\.arguments) == [item.arguments])
    }

    // MARK: - The bounded log ring (OA3 sc3)

    @Test("The log drains verbatim, tagged, in emission order")
    func theLogDrainsVerbatim() async throws {
        let harness = harness()
        let item = harness.center.submit(.install(Self.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let process = harness.launcher.launchedProcesses[0]

        process.emitStdout("==> Downloading\n")
        process.emitStderr("Warning: something\n")
        process.emitStdout("==> Pouring\n")
        await settle()

        #expect(item.log.map(\.text) == ["==> Downloading", "Warning: something", "==> Pouring"])
        #expect(item.log.map(\.stream) == [.stdout, .stderr, .stdout])
        #expect(item.isLogTruncated == false)

        // Readable while still running, which is the point of streaming.
        #expect(item.isTerminal == false)
        await finish(harness, call: 0)
        #expect(item.log.count == 3, "the terminal outcome dropped the log")
    }

    @Test("The 2,001st line evicts the oldest and raises the truncation marker")
    func theLogRingEvictsTheOldest() async throws {
        let harness = harness()
        let item = harness.center.submit(.install(Self.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let process = harness.launcher.launchedProcesses[0]

        for index in 0..<ActivityItem.logCapacity {
            process.emitStdout("line \(index)\n")
        }
        // 2,000 lines cross a stream and a main-actor hop, so wait for the
        // drain to catch up rather than for a fixed number of yields.
        await poll { item.log.count >= ActivityItem.logCapacity }

        #expect(item.log.count == ActivityItem.logCapacity)
        #expect(item.isLogTruncated == false)
        #expect(item.log.first?.text == "line 0")

        process.emitStdout("line 2000\n")
        await poll { item.isLogTruncated }

        #expect(item.log.count == ActivityItem.logCapacity, "the ring grew past its capacity")
        #expect(item.isLogTruncated, "no truncation marker after eviction")
        #expect(item.log.first?.text == "line 1", "the oldest line was not the one evicted")
        #expect(item.log.last?.text == "line 2000")
        // Still verbatim and still tagged.
        #expect(item.log.allSatisfy { $0.stream == .stdout })

        await finish(harness, call: 0)
    }

    // MARK: - Per-package fan-out (PM2 sc2 — the settled shape)

    /// The user ruling: a selected upgrade is N ordinary `.upgrade(id)`
    /// submissions, not one grouped invocation. There is no `upgradeSelected`
    /// case anywhere in the API.
    @Test("A selection fans out into exactly one operation per package, in order")
    func aSelectionFansOutPerPackage() async throws {
        let harness = harness()

        let items = harness.center.submitUpgrades(for: [Self.wget, Self.git, Self.iterm])
        await settle()

        #expect(items.count == 3)
        #expect(harness.center.items.count == 3)
        #expect(items.map(\.arguments) == [
            ["upgrade", "--formula", "wget"],
            ["upgrade", "--formula", "git"],
            ["upgrade", "--cask", "iterm2"]
        ])

        // No argv names more than one package.
        for item in items {
            let names = item.arguments.filter { !$0.hasPrefix("-") && $0 != "upgrade" }
            #expect(names.count == 1, "an argv named \(names.count) packages")
        }

        for index in 0..<3 { await finish(harness, call: index) }
    }

    /// The reason the fan-out was chosen over kind-grouped argv: attribution.
    @Test("A mid-batch failure attributes to exactly one package")
    func aMidBatchFailureAttributesToOnePackage() async throws {
        let harness = harness()
        let items = harness.center.submitUpgrades(for: [Self.wget, Self.git, Self.iterm])
        await settle()

        await finish(harness, call: 0, status: 0)
        await finish(harness, call: 1, status: 1)
        await finish(harness, call: 2, status: 0)

        #expect(items[0].outcome == .succeeded)
        #expect(items[1].outcome == .failed(status: 1))
        #expect(items[2].outcome == .succeeded, "a sibling was poisoned by the failing item")

        #expect(items[1].packageID == Self.git)
        #expect(items.count(where: { $0.outcome?.isFailure == true }) == 1)
    }

    /// A pinned formula is not named in the selected-upgrade expansion over the
    /// outdated set, and no unpin is submitted on its behalf (PM2 sc4).
    @Test("A pinned formula is never named and never unpinned to upgrade it")
    func pinnedFormulaeAreNeverForceUpgraded() async throws {
        let harness = harness()
        let inventory = InstalledInventory(packages: [
            InstalledDeriveTests.formula(
                name: "wget", installed: "1.25.0", published: "1.26.0", snapshotOutdated: true
            ),
            InstalledDeriveTests.formula(
                name: "pinned-tool", installed: "1.0", published: "2.0",
                snapshotOutdated: false, isPinned: true, pinnedVersion: "1.0"
            )
        ])

        let items = harness.center.submitUpgradesForOutdated(in: inventory)
        await settle()

        #expect(items.map(\.arguments) == [["upgrade", "--formula", "wget"]])
        let everyArgument = items.flatMap(\.arguments)
        #expect(everyArgument.contains("pinned-tool") == false)
        #expect(everyArgument.contains("unpin") == false)

        // And upgrade-all names nothing at all, so it cannot name it either.
        let all = harness.center.submit(.upgradeAll)
        #expect(all.arguments == ["upgrade"])

        await finish(harness, call: 0)
        await finish(harness, call: 1)
    }

    // MARK: - The depth-counted gate (PM6 sc1–2; II10 sc3)

    /// N terminals produce exactly N re-snapshots — never N−1 (the shipped
    /// `guard isMutating` swallowed the extras) and never 2N (design D7).
    @Test("N terminals produce exactly N re-snapshots and the gate covers the batch")
    func nTerminalsProduceNReSnapshots() async throws {
        let harness = harness()
        let terminals = Mutex(0)
        let watcher = Task { [stream = harness.gate.terminals] in
            for await _ in stream { terminals.withLock { $0 += 1 } }
        }
        await settle()

        _ = harness.center.submitUpgrades(for: [Self.wget, Self.git, Self.iterm])
        await settle()

        #expect(harness.gate.isMutating, "the gate did not open for the batch")

        await finish(harness, call: 0)
        #expect(
            harness.gate.isMutating,
            "the gate closed after the first item while two were still queued"
        )

        await finish(harness, call: 1)
        await finish(harness, call: 2)

        #expect(harness.gate.isMutating == false, "the gate stayed open after the last terminal")
        #expect(terminals.withLock { $0 } == 3, "N terminals did not produce N re-snapshots")
        watcher.cancel()
    }

    /// Every terminal outcome owes one, including the two typed failures and a
    /// cancellation.
    @Test(
        "Success, failure, busy, needs-privileges and cancellation each force exactly one",
        arguments: [0, 1, 2] as [Int32]
    )
    func everyTerminalOutcomeForcesExactlyOne(status: Int32) async throws {
        let harness = harness()
        let terminals = Mutex(0)
        let watcher = Task { [stream = harness.gate.terminals] in
            for await _ in stream { terminals.withLock { $0 += 1 } }
        }
        await settle()

        _ = harness.center.submit(.install(Self.wget))
        await finish(harness, call: 0, status: status)

        #expect(terminals.withLock { $0 } == 1)
        watcher.cancel()
    }

    @Test("A cancelled item forces its re-snapshot too")
    func aCancelledItemForcesItsReSnapshot() async throws {
        let harness = harness()
        let terminals = Mutex(0)
        let watcher = Task { [stream = harness.gate.terminals] in
            for await _ in stream { terminals.withLock { $0 += 1 } }
        }
        await settle()

        let running = harness.center.submit(.install(Self.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let pending = harness.center.submit(.install(Self.git))
        await settle()

        harness.center.cancel(pending)
        await settle()

        #expect(harness.launcher.launchCount == 1, "cancelling a pending item spawned it")
        #expect(pending.outcome == .cancelled)
        #expect(terminals.withLock { $0 } == 1)

        await finish(harness, call: 0)
        #expect(terminals.withLock { $0 } == 2)
        #expect(running.outcome == .succeeded)
        watcher.cancel()
    }

    // MARK: - Cancel, confirmation and queue control (OA4 sc1, sc3; PM3 sc2)

    @Test("Cancelling a pending item spawns nothing and shows the generic sentence")
    func cancellingAPendingItemSpawnsNothing() async throws {
        let harness = harness()
        _ = harness.center.submit(.install(Self.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let pending = harness.center.submit(.uninstall(Self.git))
        await settle()

        #expect(pending.isCancellable)
        harness.center.cancel(pending)
        await settle()

        #expect(harness.launcher.launchCount == 1)
        #expect(pending.outcome == .cancelled)
        #expect(pending.message.lowercased().contains("partial"))
        #expect(pending.message == MutationOutcome.cancelled.message(for: .uninstall(Self.git)))

        await finish(harness, call: 0)
    }

    /// Queue control is cancel-only: I2 stays immutable and no surface reorders
    /// or removes (product Q6).
    @Test("The controls offered for a pending item are cancel and nothing else")
    func queueControlIsCancelOnly() async throws {
        let harness = harness()
        _ = harness.center.submit(.install(Self.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let pending = harness.center.submit(.install(Self.git))
        await settle()

        #expect(pending.controls == [.cancel, .copyCommand])
        #expect(pending.controls.contains(.cancel))
        for absent in [ActivityItem.Control.moveUp, .moveDown, .remove] {
            #expect(pending.controls.contains(absent) == false)
        }

        await finish(harness, call: 0)
        await finish(harness, call: 1)
    }

    @Test("A terminal item offers no cancel, only copy")
    func aTerminalItemOffersNoCancel() async throws {
        let harness = harness()
        let item = harness.center.submit(.install(Self.wget))
        await finish(harness, call: 0)

        #expect(item.isCancellable == false)
        #expect(item.controls.contains(.cancel) == false)
    }

    /// Declining a confirmation submits nothing and spawns nothing (PM3 sc2).
    @Test("Declining a confirmation submits nothing and spawns nothing")
    func decliningAConfirmationSubmitsNothing() async throws {
        let harness = harness()
        let command = MutationCommand.uninstall(Self.wget)

        #expect(command.requiresConfirmation)
        let request = try #require(harness.center.request(command))
        #expect(request.displayCommand == "brew uninstall --formula wget")

        harness.center.decline(request)
        await settle()

        #expect(harness.center.items.isEmpty, "a declined confirmation enqueued an item")
        #expect(harness.launcher.launchCount == 0)
        #expect(harness.center.pendingConfirmation == nil)
    }

    @Test("Confirming submits exactly the command that was shown")
    func confirmingSubmitsTheShownCommand() async throws {
        let harness = harness()
        let request = try #require(harness.center.request(.uninstall(Self.wget)))

        let item = try #require(harness.center.confirm(request))
        await settle()

        #expect(item.displayCommand == request.displayCommand)
        #expect(item.arguments == ["uninstall", "--formula", "wget"])
        await finish(harness, call: 0)
    }

    @Test("A non-destructive command needs no confirmation and submits directly")
    func nonDestructiveCommandsSubmitDirectly() async throws {
        let harness = harness()

        #expect(harness.center.request(.install(Self.wget)) == nil)
        let item = harness.center.submit(.install(Self.wget))
        await settle()

        #expect(item.arguments == ["install", "--formula", "wget"])
        #expect(harness.center.pendingConfirmation == nil)
        await finish(harness, call: 0)
    }

    // MARK: - Summary and detail agree (OA5 sc1–3)

    @Test("The summary reports the running operation and the pending count")
    func theSummaryReportsRunningAndPending() async throws {
        let harness = harness()
        let first = harness.center.submit(.install(Self.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        _ = harness.center.submit(.install(Self.git))
        _ = harness.center.submit(.install(Self.iterm))
        await settle()

        let summary = harness.center.summary
        #expect(summary.isBusy)
        #expect(summary.running?.id == first.id)
        #expect(summary.runningCommand == "brew install --formula wget")
        #expect(summary.pendingCount == 2)

        for index in 0..<3 { await finish(harness, call: index) }
    }

    @Test("An empty centre and an all-terminal centre both report idle")
    func anEmptyAndAnAllTerminalCentreBothReportIdle() async throws {
        let harness = harness()

        #expect(harness.center.summary.isBusy == false)
        #expect(harness.center.summary.pendingCount == 0)
        #expect(harness.center.summary.running == nil)

        _ = harness.center.submit(.install(Self.wget))
        await finish(harness, call: 0)

        #expect(harness.center.summary.isBusy == false, "an all-terminal centre claimed work")
        #expect(harness.center.summary.pendingCount == 0)
        #expect(harness.center.summary.running == nil)
        #expect(harness.center.items.count == 1, "the terminal item stopped being enumerable")
    }

    /// Both projections derive from the one `QueueSnapshot`, so they cannot
    /// disagree — asserted across a sequence of submissions, a cancellation and
    /// terminals rather than at one convenient moment.
    @Test("Summary and detail never disagree across a whole sequence")
    func summaryAndDetailNeverDisagree() async throws {
        let harness = harness()

        func check(_ label: String) {
            let summary = harness.center.summary
            let detail = harness.center.items
            #expect(
                summary.running?.id == detail.first(where: { $0.isRunning })?.id,
                "summary and detail disagreed on the running operation at \(label)"
            )
            #expect(
                summary.pendingCount == detail.count(where: \.isPending),
                "summary and detail disagreed on the pending count at \(label)"
            )
            #expect(summary.isBusy == detail.contains { !$0.isTerminal })
        }

        check("empty")
        _ = harness.center.submit(.install(Self.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        check("one running")

        let pending = harness.center.submit(.install(Self.git))
        _ = harness.center.submit(.install(Self.iterm))
        await settle()
        check("two pending")

        harness.center.cancel(pending)
        await settle()
        check("one cancelled")

        await finish(harness, call: 0)
        check("head terminal")
        await finish(harness, call: 1)
        check("all terminal")
    }

    // MARK: - No runner (PM7 sc1–3)

    @Test("With no runner a submission becomes a terminal item reporting unavailable")
    func withNoRunnerASubmissionIsTerminalAndUnavailable() async throws {
        let harness = harness(attached: false)

        #expect(harness.center.isAvailable == false)
        let item = harness.center.submit(.install(Self.wget))
        await settle()

        #expect(item.isTerminal, "an unavailable submission was left hanging")
        #expect(item.outcome == .launchFailed)
        #expect(harness.launcher.launchCount == 0, "a submission spawned with no runner attached")
        #expect(harness.center.items.count == 1)
    }

    @Test("The rejection reason is available as read-only guidance")
    func theRejectionReasonIsReadOnlyGuidance() async throws {
        let harness = harness(attached: false)
        let item = harness.center.submit(.install(Self.wget))
        await settle()

        #expect(item.message.isEmpty == false)
        #expect(harness.center.unavailableGuidance?.isEmpty == false)
        #expect(item.isCancellable == false)
    }

    @Test("Mutations become available when brew appears, with no restart")
    func mutationsBecomeAvailableWhenBrewAppears() async throws {
        let harness = harness(attached: false)

        _ = harness.center.submit(.install(Self.wget))
        await settle()
        #expect(harness.launcher.launchCount == 0)

        harness.center.attach(installation: TestInstallation.appleSilicon)
        #expect(harness.center.isAvailable)

        let item = harness.center.submit(.install(Self.git))
        await finish(harness, call: 0)

        #expect(item.outcome == .succeeded)
        #expect(harness.launcher.launchCount == 1)
    }

    /// Repointing `brew` builds a new runner while in-flight items keep the old
    /// one alive until they settle.
    @Test("Repointing brew leaves in-flight items running on the old runner")
    func repointingBrewKeepsInFlightItemsAlive() async throws {
        let harness = harness()
        let inFlight = harness.center.submit(.install(Self.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)

        harness.center.attach(installation: TestInstallation.intel)
        await settle()

        #expect(inFlight.isTerminal == false, "repointing brew abandoned an in-flight item")

        await finish(harness, call: 0)
        #expect(inFlight.outcome == .succeeded)

        // And the next submission goes to the new installation.
        _ = harness.center.submit(.install(Self.git))
        await harness.launcher.waitForLaunches(atLeast: 2)
        #expect(
            harness.launcher.recordedSpecs.last?.executableURL
                == TestInstallation.intel.executableURL
        )
        await finish(harness, call: 1)
    }
}
