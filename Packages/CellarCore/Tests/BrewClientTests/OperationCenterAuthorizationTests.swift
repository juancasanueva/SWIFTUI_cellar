import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

@MainActor
@Suite("Operation center authorization", .timeLimit(.minutes(1)))
struct OperationCenterAuthorizationTests {
    @Test("A denied mutation settles once without spawn and records typed history")
    func denialSettlesOnceWithoutSpawn() async throws {
        let harness = CenterHarness()
        let item = harness.center.submit(
            ProbeMutation(arguments: ["untap", "--force", "acme/tools"], verb: "tapForceUntap"),
            authorizer: DenyingAuthorizer(code: .evidenceChanged)
        )

        await harness.poll { item.isTerminal }

        #expect(harness.launcher.launchCount == 0)
        #expect(item.outcome == .authorizationDenied(.evidenceChanged))
        #expect(item.queuePhase == .authorizationDenied(
            MutationLaunchDenial(code: .evidenceChanged)
        ))
        #expect(item.log.isEmpty)
        #expect(harness.recorder.drafts.count == 1)
        let draft = try #require(harness.recorder.drafts.first)
        #expect(draft.packageID == nil)
        #expect(draft.verb == "tapForceUntap")
        #expect(draft.argv == ["untap", "--force", "acme/tools"])
        #expect(draft.outcome == .authorizationDenied(.evidenceChanged))

        await harness.settle()
        #expect(harness.recorder.drafts.count == 1, "denial finished or recorded more than once")
    }

    @Test("Evidence-unavailable denial uses its distinct typed outcome")
    func unavailableEvidenceHasDistinctOutcome() async {
        let harness = CenterHarness()
        let item = harness.center.submit(
            ProbeMutation(arguments: ["untap", "--force", "acme/tools"], verb: "tapForceUntap"),
            authorizer: DenyingAuthorizer(code: .evidenceUnavailable)
        )

        await harness.poll { item.isTerminal }

        #expect(item.outcome == .authorizationDenied(.evidenceUnavailable))
        #expect(item.statusLabel == "Could not verify current packages")
        #expect(harness.launcher.launchCount == 0)
    }
}

private struct DenyingAuthorizer: MutationLaunchAuthorizing {
    let code: MutationLaunchDenial.Code

    func authorizeLaunch() async -> MutationLaunchDecision {
        .deny(MutationLaunchDenial(code: code))
    }
}
