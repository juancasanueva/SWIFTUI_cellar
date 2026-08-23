import CellarTestSupport
import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// A sequence whose followers are earned, not queued (maintainer decision D4,
/// 2026-08-23).
///
/// `submitSequence` fans every command into its own queue item at once and never
/// looks back: a mid-sequence failure changes nothing about what runs behind it.
/// That is right for a fan-out over N independent packages and wrong for an
/// action whose second command is only meaningful if the first one happened —
/// which is exactly the untap sequence, because `brew` refuses to untap a tap
/// that still owns installed packages and a revocation submitted anyway would
/// strand the user on an untrusted tap whose Force Untap is hidden.
///
/// Both surfaces stay: the confirmation shape is identical (one request for the
/// whole sequence, declining submits none of it — PM3), and only the execution
/// differs.
@MainActor
@Suite("Dependent sequences", .timeLimit(.minutes(1)))
struct OperationCenterDependentSequenceTests {
    private static let acme = TapName("acme/tools")!

    private static func removal() throws -> [TapCommand] {
        try #require(TapCommand.removal(of: "acme/tools"))
    }

    private static func forcedRemoval() throws -> [TapCommand] {
        try #require(TapCommand.forcedRemoval(evidence: ForceUntapEvidence(
            tap: acme,
            affected: [PackageID(kind: .formula, name: "widget")],
            isComplete: true
        )))
    }

    // MARK: - The lead decides

    /// The defect, stated as a test: a refused lead submits nothing behind it.
    ///
    /// Not "submits it later" and not "submits it and marks it failed" — the
    /// follower never becomes a queue item at all, so there is no phantom entry
    /// in Activity for a command that was never run.
    @Test("A failed lead never submits its follower")
    func aFailedLeadNeverSubmitsItsFollower() async throws {
        let harness = CenterHarness()

        #expect(harness.center.submitDependentSequence(try Self.removal()) == nil)
        try await harness.finish(call: 0, status: 1)
        await harness.settle()

        #expect(harness.center.items.count == 1, "a refused removal enqueued a phantom follower")
        #expect(harness.center.items.map(\.arguments) == [["untap", "acme/tools"]])
        #expect(harness.center.items.map(\.outcome) == [.failed(status: 1)])

        // The strongest form of the same fact: no `untrust` argv ever reached
        // the launcher, so nothing was spawned and nothing was cancelled either.
        #expect(harness.launcher.launchCount == 1)
        #expect(
            harness.launcher.recordedSpecs.contains { $0.arguments.contains("untrust") } == false,
            "a revocation was spawned behind a refused removal"
        )
    }

    /// The other half. A follower is submitted **after** the lead settles, in
    /// order — never beside it, which is what makes the ordering a fact about
    /// the queue rather than about how fast the first process happened to exit.
    @Test("A successful lead submits its follower, and only once it has settled")
    func aSuccessfulLeadSubmitsItsFollowerOnlyOnceItHasSettled() async throws {
        let harness = CenterHarness()

        #expect(harness.center.submitDependentSequence(try Self.removal()) == nil)
        await harness.launcher.waitForLaunches(atLeast: 1)
        await harness.settle()

        // While the lead is still running there is exactly one item and one
        // spawned process: the follower is not queued behind it.
        #expect(harness.center.items.count == 1)
        #expect(harness.launcher.launchCount == 1)

        try await harness.finish(call: 0)
        #expect(harness.center.items.count == 2, "a settled lead did not submit its follower")
        #expect(harness.center.items[0].isTerminal)

        try await harness.finish(call: 1)
        #expect(harness.launcher.recordedSpecs.map(\.arguments) == [
            ["untap", "acme/tools"],
            ["untrust", "acme/tools"]
        ])
        #expect(harness.center.items.map(\.outcome) == [.succeeded, .succeeded])
    }

    /// A cancelled lead is not a successful one. The distinction matters because
    /// cancel and a terminal exit race, and a follower submitted off anything
    /// but `succeeded` would run against a tap that is still there.
    @Test("A cancelled lead never submits its follower")
    func aCancelledLeadNeverSubmitsItsFollower() async throws {
        let harness = CenterHarness()

        #expect(harness.center.submitDependentSequence(try Self.removal()) == nil)
        await harness.launcher.waitForLaunches(atLeast: 1)
        await harness.settle()

        let lead = try #require(harness.center.items.first)
        harness.center.cancel(lead)
        await harness.poll(until: { lead.isTerminal })
        await harness.settle()

        #expect(lead.outcome == .cancelled)
        #expect(harness.center.items.count == 1)
        #expect(harness.launcher.launchCount == 1)
        #expect(
            harness.launcher.recordedSpecs.contains { $0.arguments.contains("untrust") } == false
        )
    }

    // MARK: - PM3 — the confirmation shape is unchanged

    /// One request for the whole sequence, and declining submits **none** of it
    /// — never a partial subset. Identical to `submitSequence`; the dependency
    /// lives entirely behind the yes.
    @Test("Declining a dependent sequence submits nothing at all")
    func decliningADependentSequenceSubmitsNothingAtAll() async throws {
        let harness = CenterHarness()
        let forced = try Self.forcedRemoval()

        let request = try #require(
            harness.center.submitDependentSequence(forced),
            "a force untap submitted without asking"
        )
        #expect(request.dependsOnLead)
        #expect(request.commands.map(\.arguments) == [
            ["untap", "--force", "acme/tools"],
            ["untrust", "acme/tools"]
        ])
        // The removal leads, so the sheet leads with the force-untap disclosure.
        #expect(request.disclosure == .forceUntap(
            tap: Self.acme,
            affected: [PackageID(kind: .formula, name: "widget")]
        ))
        #expect(harness.center.items.isEmpty, "an operation was enqueued before the confirmation")

        harness.center.decline(request)
        await harness.settle()

        #expect(harness.center.items.isEmpty)
        #expect(harness.launcher.launchCount == 0)
        #expect(harness.center.pendingConfirmation == nil)
    }

    /// Confirming runs the dependent path, not the fan-out one: the yes covers
    /// both commands, and the second is still earned by the first.
    @Test("Confirming a dependent sequence runs the dependent path")
    func confirmingADependentSequenceRunsTheDependentPath() async throws {
        let harness = CenterHarness()

        let request = try #require(harness.center.submitDependentSequence(try Self.forcedRemoval()))
        let submitted = harness.center.confirm(request)
        await harness.settle()

        // Only the lead exists yet, even though the yes covered two commands.
        #expect(submitted.map(\.arguments) == [["untap", "--force", "acme/tools"]])
        #expect(harness.center.items.count == 1)

        try await harness.finish(call: 0)
        #expect(harness.center.items.count == 2)
        try await harness.finish(call: 1)

        #expect(harness.launcher.recordedSpecs.map(\.arguments) == [
            ["untap", "--force", "acme/tools"],
            ["untrust", "acme/tools"]
        ])
        #expect(harness.center.items.map(\.outcome) == [.succeeded, .succeeded])
    }

    /// …and a confirmed dependent sequence whose lead is refused submits no
    /// follower either. The confirmation agreed to an *action*, not to two
    /// commands running whatever happens.
    @Test("A confirmed dependent sequence still stops at a refused lead")
    func aConfirmedDependentSequenceStillStopsAtARefusedLead() async throws {
        let harness = CenterHarness()

        let request = try #require(harness.center.submitDependentSequence(try Self.forcedRemoval()))
        _ = harness.center.confirm(request)
        try await harness.finish(call: 0, status: 1)
        await harness.settle()

        #expect(harness.center.items.count == 1)
        #expect(harness.launcher.launchCount == 1)
    }

    // MARK: - The unconditional fan-out is untouched

    /// `submitSequence` keeps its own meaning for every other caller: both
    /// commands become queue items at submission time, and a failed first one
    /// changes nothing about the second.
    @Test("submitSequence still fans out unconditionally")
    func submitSequenceStillFansOutUnconditionally() async throws {
        let harness = CenterHarness()

        #expect(harness.center.submitSequence(try Self.removal()) == nil)
        await harness.settle()

        #expect(harness.center.items.count == 2, "the independent fan-out lost a queue item")
        try await harness.finish(call: 0, status: 1)
        try await harness.finish(call: 1)

        #expect(harness.launcher.recordedSpecs.map(\.arguments) == [
            ["untap", "acme/tools"],
            ["untrust", "acme/tools"]
        ])
        #expect(harness.center.items.map(\.outcome) == [.failed(status: 1), .succeeded])
    }
}
