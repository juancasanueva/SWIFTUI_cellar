import Foundation
import Testing

@testable import BrewClient

@MainActor
@Suite("Confirmation recovery backlog")
struct ConfirmationBacklogTests {
    @Test("An occupied slot keeps unrelated UI visible and promotes recovery on vacancy")
    func occupiedSlotPromotesAfterVacancy() {
        let box = ConfirmationBox()
        let unrelated = request("uninstall", "--formula", "wget")
        let recovery = request("untap", "--force", "acme/tools")
        let token = MutationOperationToken()
        box.present(unrelated)

        box.enqueueRecovery(
            request: recovery,
            token: token,
            supersessionKey: "acme/tools",
            isEligible: { true },
            onCancel: {}
        )
        #expect(box.pending == unrelated)
        #expect(box.backloggedToken == token)

        box.consume(unrelated)
        #expect(box.pending == recovery)
        #expect(box.visibleRecoveryToken == token)
    }

    @Test("The newest recovery replaces the backlog and cancels the old candidate")
    func backlogIsLatestWins() {
        let box = ConfirmationBox()
        box.present(request("uninstall", "--formula", "wget"))
        var cancelled: [String] = []
        let first = MutationOperationToken()
        let second = MutationOperationToken()

        box.enqueueRecovery(
            request: request("untap", "--force", "old/tools"),
            token: first,
            supersessionKey: "old/tools",
            isEligible: { true },
            onCancel: { cancelled.append("old") }
        )
        box.enqueueRecovery(
            request: request("untap", "--force", "new/tools"),
            token: second,
            supersessionKey: "new/tools",
            isEligible: { true },
            onCancel: { cancelled.append("new") }
        )

        #expect(cancelled == ["old"])
        #expect(box.backloggedToken == second)
    }

    @Test("Duplicate tokens are ignored and ineligible recovery is cancelled at vacancy")
    func duplicateAndIneligibleRecoveryDoNotPresent() {
        let box = ConfirmationBox()
        let visible = request("uninstall", "--formula", "wget")
        let token = MutationOperationToken()
        var cancellations = 0
        box.present(visible)
        box.enqueueRecovery(
            request: request("untap", "--force", "acme/tools"),
            token: token,
            supersessionKey: "acme/tools",
            isEligible: { false },
            onCancel: { cancellations += 1 }
        )
        box.enqueueRecovery(
            request: request("untap", "--force", "duplicate/tools"),
            token: token,
            supersessionKey: "duplicate/tools",
            isEligible: { true },
            onCancel: { cancellations += 100 }
        )

        box.consume(visible)

        #expect(box.pending == nil)
        #expect(cancellations == 1)
    }

    @Test("A newer force supersedes visible recovery and shutdown cancels all recovery")
    func supersessionAndShutdownCancelRecovery() {
        let box = ConfirmationBox()
        var cancellations = 0
        let first = MutationOperationToken()
        box.enqueueRecovery(
            request: request("untap", "--force", "acme/tools"),
            token: first,
            supersessionKey: "acme/tools",
            isEligible: { true },
            onCancel: { cancellations += 1 }
        )
        #expect(box.visibleRecoveryToken == first)

        box.supersedeRecovery(for: "acme/tools")
        #expect(box.pending == nil)
        #expect(cancellations == 1)

        box.enqueueRecovery(
            request: request("untap", "--force", "other/tools"),
            token: MutationOperationToken(),
            supersessionKey: "other/tools",
            isEligible: { true },
            onCancel: { cancellations += 1 }
        )
        box.shutdown()
        #expect(box.pending == nil)
        #expect(cancellations == 2)
    }

    private func request(_ arguments: String...) -> OperationCenter.ConfirmationRequest {
        OperationCenter.ConfirmationRequest(
            id: UUID(),
            command: AnyBrewMutation(ProbeMutation(arguments: arguments)),
            additional: []
        )
    }
}
