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
@Suite("Operation center projections", .timeLimit(.minutes(1)))
struct OperationCenterProjectionTests {
    // MARK: - The depth-counted gate (PM6 sc1–2; II10 sc3)

    /// N terminals produce exactly N re-snapshots — never N−1 (the shipped
    /// `guard isMutating` swallowed the extras) and never 2N (design D7).
    @Test("N terminals produce exactly N re-snapshots and the gate covers the batch")
    func nTerminalsProduceNReSnapshots() async throws {
        let harness = CenterHarness()
        let terminals = Mutex(0)
        let watcher = Task { [stream = harness.gate.terminals] in
            for await _ in stream { terminals.withLock { $0 += 1 } }
        }
        await harness.settle()

        _ = harness.center.submitUpgrades(for: [CenterHarness.wget, CenterHarness.git, CenterHarness.iterm])
        await harness.settle()

        #expect(harness.gate.isMutating, "the gate did not open for the batch")

        await harness.finish(call: 0)
        #expect(
            harness.gate.isMutating,
            "the gate closed after the first item while two were still queued"
        )

        await harness.finish(call: 1)
        await harness.finish(call: 2)

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
        let harness = CenterHarness()
        let terminals = Mutex(0)
        let watcher = Task { [stream = harness.gate.terminals] in
            for await _ in stream { terminals.withLock { $0 += 1 } }
        }
        await harness.settle()

        _ = harness.center.submit(.install(CenterHarness.wget))
        await harness.finish(call: 0, status: status)

        #expect(terminals.withLock { $0 } == 1)
        watcher.cancel()
    }

    @Test("A cancelled item forces its re-snapshot too")
    func aCancelledItemForcesItsReSnapshot() async throws {
        let harness = CenterHarness()
        let terminals = Mutex(0)
        let watcher = Task { [stream = harness.gate.terminals] in
            for await _ in stream { terminals.withLock { $0 += 1 } }
        }
        await harness.settle()

        let running = harness.center.submit(.install(CenterHarness.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let pending = harness.center.submit(.install(CenterHarness.git))
        await harness.settle()

        harness.center.cancel(pending)
        await harness.settle()

        #expect(harness.launcher.launchCount == 1, "cancelling a pending item spawned it")
        #expect(pending.outcome == .cancelled)
        #expect(terminals.withLock { $0 } == 1)

        await harness.finish(call: 0)
        #expect(terminals.withLock { $0 } == 2)
        #expect(running.outcome == .succeeded)
        watcher.cancel()
    }

    // MARK: - Cancel, confirmation and queue control (OA4 sc1, sc3; PM3 sc2)

    @Test("Cancelling a pending item spawns nothing and shows the generic sentence")
    func cancellingAPendingItemSpawnsNothing() async throws {
        let harness = CenterHarness()
        _ = harness.center.submit(.install(CenterHarness.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let pending = harness.center.submit(.uninstall(CenterHarness.git))
        await harness.settle()

        #expect(pending.isCancellable)
        harness.center.cancel(pending)
        await harness.settle()

        #expect(harness.launcher.launchCount == 1)
        #expect(pending.outcome == .cancelled)
        #expect(pending.message.lowercased().contains("partial"))
        #expect(pending.message == MutationOutcome.cancelled.message(for: .uninstall(CenterHarness.git)))

        await harness.finish(call: 0)
    }

    /// Queue control is cancel-only: I2 stays immutable and no surface reorders
    /// or removes (product Q6).
    @Test("The controls offered for a pending item are cancel and nothing else")
    func queueControlIsCancelOnly() async throws {
        let harness = CenterHarness()
        _ = harness.center.submit(.install(CenterHarness.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        let pending = harness.center.submit(.install(CenterHarness.git))
        await harness.settle()

        #expect(pending.controls == [.cancel, .copyCommand])
        #expect(pending.controls.contains(.cancel))
        for absent in [ActivityItem.Control.moveUp, .moveDown, .remove] {
            #expect(pending.controls.contains(absent) == false)
        }

        await harness.finish(call: 0)
        await harness.finish(call: 1)
    }

    @Test("A terminal item offers no cancel, only copy")
    func aTerminalItemOffersNoCancel() async throws {
        let harness = CenterHarness()
        let item = harness.center.submit(.install(CenterHarness.wget))
        await harness.finish(call: 0)

        #expect(item.isCancellable == false)
        #expect(item.controls.contains(.cancel) == false)
    }

    /// Declining a confirmation submits nothing and spawns nothing (PM3 sc2).
    @Test("Declining a confirmation submits nothing and spawns nothing")
    func decliningAConfirmationSubmitsNothing() async throws {
        let harness = CenterHarness()
        let command = MutationCommand.uninstall(CenterHarness.wget)

        #expect(command.requiresConfirmation)
        let request = try #require(harness.center.request(command))
        #expect(request.displayCommand == "brew uninstall --formula wget")

        harness.center.decline(request)
        await harness.settle()

        #expect(harness.center.items.isEmpty, "a declined confirmation enqueued an item")
        #expect(harness.launcher.launchCount == 0)
        #expect(harness.center.pendingConfirmation == nil)
    }

    @Test("Confirming submits exactly the command that was shown")
    func confirmingSubmitsTheShownCommand() async throws {
        let harness = CenterHarness()
        let request = try #require(harness.center.request(.uninstall(CenterHarness.wget)))

        let item = try #require(harness.center.confirm(request))
        await harness.settle()

        #expect(item.displayCommand == request.displayCommand)
        #expect(item.arguments == ["uninstall", "--formula", "wget"])
        await harness.finish(call: 0)
    }

    @Test("A non-destructive command needs no confirmation and submits directly")
    func nonDestructiveCommandsSubmitDirectly() async throws {
        let harness = CenterHarness()

        #expect(harness.center.request(.install(CenterHarness.wget)) == nil)
        let item = harness.center.submit(.install(CenterHarness.wget))
        await harness.settle()

        #expect(item.arguments == ["install", "--formula", "wget"])
        #expect(harness.center.pendingConfirmation == nil)
        await harness.finish(call: 0)
    }

    // MARK: - Summary and detail agree (OA5 sc1–3)

    @Test("The summary reports the running operation and the pending count")
    func theSummaryReportsRunningAndPending() async throws {
        let harness = CenterHarness()
        let first = harness.center.submit(.install(CenterHarness.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        _ = harness.center.submit(.install(CenterHarness.git))
        _ = harness.center.submit(.install(CenterHarness.iterm))
        await harness.settle()

        let summary = harness.center.summary
        #expect(summary.isBusy)
        #expect(summary.running?.id == first.id)
        #expect(summary.runningCommand == "brew install --formula wget")
        #expect(summary.pendingCount == 2)

        for index in 0..<3 { await harness.finish(call: index) }
    }

    @Test("An empty centre and an all-terminal centre both report idle")
    func anEmptyAndAnAllTerminalCentreBothReportIdle() async throws {
        let harness = CenterHarness()

        #expect(harness.center.summary.isBusy == false)
        #expect(harness.center.summary.pendingCount == 0)
        #expect(harness.center.summary.running == nil)

        _ = harness.center.submit(.install(CenterHarness.wget))
        await harness.finish(call: 0)

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
        let harness = CenterHarness()

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
        _ = harness.center.submit(.install(CenterHarness.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)
        check("one running")

        let pending = harness.center.submit(.install(CenterHarness.git))
        _ = harness.center.submit(.install(CenterHarness.iterm))
        await harness.settle()
        check("two pending")

        harness.center.cancel(pending)
        await harness.settle()
        check("one cancelled")

        await harness.finish(call: 0)
        check("head terminal")
        await harness.finish(call: 1)
        check("all terminal")
    }

    // MARK: - No runner (PM7 sc1–3)

    @Test("With no runner a submission becomes a terminal item reporting unavailable")
    func withNoRunnerASubmissionIsTerminalAndUnavailable() async throws {
        let harness = CenterHarness(attached: false)

        #expect(harness.center.isAvailable == false)
        let item = harness.center.submit(.install(CenterHarness.wget))
        await harness.settle()

        #expect(item.isTerminal, "an unavailable submission was left hanging")
        #expect(item.outcome == .launchFailed)
        #expect(harness.launcher.launchCount == 0, "a submission spawned with no runner attached")
        #expect(harness.center.items.count == 1)
    }

    @Test("The rejection reason is available as read-only guidance")
    func theRejectionReasonIsReadOnlyGuidance() async throws {
        let harness = CenterHarness(attached: false)
        let item = harness.center.submit(.install(CenterHarness.wget))
        await harness.settle()

        #expect(item.message.isEmpty == false)
        #expect(harness.center.unavailableGuidance?.isEmpty == false)
        #expect(item.isCancellable == false)
    }

    @Test("Mutations become available when brew appears, with no restart")
    func mutationsBecomeAvailableWhenBrewAppears() async throws {
        let harness = CenterHarness(attached: false)

        _ = harness.center.submit(.install(CenterHarness.wget))
        await harness.settle()
        #expect(harness.launcher.launchCount == 0)

        harness.center.attach(installation: TestInstallation.appleSilicon)
        #expect(harness.center.isAvailable)

        let item = harness.center.submit(.install(CenterHarness.git))
        await harness.finish(call: 0)

        #expect(item.outcome == .succeeded)
        #expect(harness.launcher.launchCount == 1)
    }

    /// Repointing `brew` builds a new runner while in-flight items keep the old
    /// one alive until they settle.
    @Test("Repointing brew leaves in-flight items running on the old runner")
    func repointingBrewKeepsInFlightItemsAlive() async throws {
        let harness = CenterHarness()
        let inFlight = harness.center.submit(.install(CenterHarness.wget))
        await harness.launcher.waitForLaunches(atLeast: 1)

        harness.center.attach(installation: TestInstallation.intel)
        await harness.settle()

        #expect(inFlight.isTerminal == false, "repointing brew abandoned an in-flight item")

        await harness.finish(call: 0)
        #expect(inFlight.outcome == .succeeded)

        // And the next submission goes to the new installation.
        _ = harness.center.submit(.install(CenterHarness.git))
        await harness.launcher.waitForLaunches(atLeast: 2)
        #expect(
            harness.launcher.recordedSpecs.last?.executableURL
                == TestInstallation.intel.executableURL
        )
        await harness.finish(call: 1)
    }
}
