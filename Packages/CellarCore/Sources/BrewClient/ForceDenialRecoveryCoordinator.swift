import Foundation

/// Orders denial recovery after terminal settlement and every keyed refresh.
@MainActor
final class ForceDenialRecoveryCoordinator {
    struct Expectation {
        let token: MutationOperationToken
        let supersessionKey: String
        let isEligible: @MainActor () -> Bool
        let waiter: Task<RefreshReceipt?, Never>
    }

    private let registry: MutationRefreshRegistry
    private let confirmations: ConfirmationBox
    private var recoveryTasks: [MutationOperationToken: Task<Void, Never>] = [:]

    init(registry: MutationRefreshRegistry, confirmations: ConfirmationBox) {
        self.registry = registry
        self.confirmations = confirmations
    }

    func begin(
        supersessionKey: String,
        isEligible: @escaping @MainActor () -> Bool
    ) async -> Expectation {
        let token = MutationOperationToken()
        await registry.register(token, domains: [.taps, .installedInventory])
        let waiter = Task { await registry.wait(for: token) }
        return Expectation(
            token: token,
            supersessionKey: supersessionKey,
            isEligible: isEligible,
            waiter: waiter
        )
    }

    func authorizationDenied(
        _ expectation: Expectation,
        buildReplacement: @escaping @MainActor () async -> OperationCenter.ConfirmationRequest?
    ) {
        guard recoveryTasks[expectation.token] == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self, let receipt = await expectation.waiter.value else { return }
            defer { recoveryTasks[expectation.token] = nil }
            guard receipt.results[.taps] == .refreshed,
                  receipt.results[.installedInventory] == .refreshed,
                  expectation.isEligible(),
                  let request = await buildReplacement(),
                  expectation.isEligible()
            else { return }

            confirmations.enqueueRecovery(
                request: request,
                token: expectation.token,
                supersessionKey: expectation.supersessionKey,
                isEligible: expectation.isEligible,
                onCancel: { [weak self] in self?.cancel(expectation) }
            )
        }
        recoveryTasks[expectation.token] = task
    }

    /// Every non-denial terminal cancels the expectation immediately.
    func finish(_ expectation: Expectation) {
        cancel(expectation)
    }

    func shutdown() async {
        for task in recoveryTasks.values { task.cancel() }
        recoveryTasks.removeAll()
        confirmations.shutdown()
        await registry.shutdown()
    }

    private func cancel(_ expectation: Expectation) {
        expectation.waiter.cancel()
        recoveryTasks.removeValue(forKey: expectation.token)?.cancel()
    }
}

@MainActor
struct ForceRecoveryContext {
    let expectation: ForceDenialRecoveryCoordinator.Expectation
    let currentEvidence: @MainActor @Sendable () -> ForceUntapEvidence?
}

extension OperationCenter {
    /// Confirms a force untap with a queue-front evidence check and keyed refresh recovery.
    ///
    /// The confirmation carries the exact set the user reviewed. The closure is
    /// consulted only at the queue front and again after both invalidated domains
    /// have refreshed; UI prose can therefore never become execution input.
    @discardableResult
    public func confirmForceUntap(
        _ request: ConfirmationRequest,
        currentEvidence: @escaping @MainActor @Sendable () -> ForceUntapEvidence?
    ) async -> ActivityItem? {
        guard pendingConfirmation == request,
              let recovery = forceRecovery,
              case .forceUntap(let tap, let affected) = request.disclosure
        else { return nil }

        let reviewedEvidence = ForceUntapEvidence(
            tap: tap,
            affected: affected,
            isComplete: true
        )
        guard let command = TapCommand.forceUntap(evidence: reviewedEvidence) else { return nil }

        let expectation = await recovery.begin(
            supersessionKey: tap.rawValue,
            isEligible: {
                guard let evidence = currentEvidence() else { return false }
                return evidence.tap == tap && evidence.isComplete && !evidence.affected.isEmpty
            }
        )
        confirmations.consume(request)

        let authorizer = ForceUntapLaunchAuthorizer(
            tap: tap,
            expected: affected,
            currentEvidence: { await currentEvidence() }
        )
        let item = submit(
            command,
            authorizer: authorizer,
            refreshToken: expectation.token
        )
        forceRecoveryContexts[item.id] = ForceRecoveryContext(
            expectation: expectation,
            currentEvidence: currentEvidence
        )
        return item
    }

    func settleForceRecovery(for item: ActivityItem, outcome: MutationOutcome) {
        guard let recovery = forceRecovery,
              let context = forceRecoveryContexts.removeValue(forKey: item.id)
        else { return }

        guard case .authorizationDenied = outcome else {
            recovery.finish(context.expectation)
            return
        }

        recovery.authorizationDenied(context.expectation) {
            guard let evidence = context.currentEvidence(),
                  let command = TapCommand.forceUntap(evidence: evidence)
            else { return nil }
            return ConfirmationRequest(
                id: UUID(),
                command: AnyBrewMutation(command),
                additional: [],
                disclosure: command.disclosure
            )
        }
    }
}
