import Foundation

/// The services submit path, and the one guard in front of it (design D6 —
/// service-management SM4, SM10).
///
/// Split out of `OperationCenter.swift` for the reason `OperationCenterBulk`
/// already was: "how a service verb reaches the queue, and what stops a
/// double-click queueing two contradictory operations" is its own story, and the
/// centre's declaration is at this package's 400-line bound.
///
/// Everything else a service verb needs it inherits: the FIFO queue, the log
/// ring, cancel, the copy-command, the terminal funnel, the one history entry
/// and the scoped invalidation. That inheritance is the whole point of the
/// shared spine — this file adds a guard and a fan-out, and nothing else.
extension OperationCenter {

    // MARK: - One service (SM10)

    /// Submits one service verb, unless that service already has an operation
    /// in flight.
    ///
    /// Returns the **existing** item in that case rather than `nil`, so a caller
    /// gets something to show either way and a refused click is not silent. The
    /// user's second click on a row that is already working is answered by the
    /// work that is already happening.
    ///
    /// Deliberately **not** a general deduplication. `brew-execution` permits
    /// duplicate submissions of the same command and distinguishes them by
    /// identity, and the general rule (M2-2 follow-up 7) stays deferred. What is
    /// closed here is one specific harm: a double-invoked control queueing a
    /// stop behind a start for one service.
    @discardableResult
    public func submit(service command: ServiceCommand) -> ActivityItem {
        if let inFlight = serviceSubmissions.inFlight(for: command.target) { return inFlight }

        let item = submit(command)
        serviceSubmissions.record(item, for: command.target)
        return item
    }

    // MARK: - Several services (SM4 sc4)

    /// One operation per service, in the order they were chosen.
    ///
    /// The fan-out happens here, at the call site, exactly as it does for a
    /// package selection — there is no `--all` and no batched service command,
    /// so every service gets its own queue item, log, copy-command, cancel and
    /// terminal outcome, and a mid-batch failure attributes to exactly one
    /// service (M2 fan-out ruling, package-mutation PM2 sc2).
    @discardableResult
    public func submit(services commands: [ServiceCommand]) -> [ActivityItem] {
        commands.map { submit(service: $0) }
    }
}

/// Which service currently has an operation that has not settled.
///
/// **It holds items rather than a flag, and that is what releases it.** The
/// stored item's own `isTerminal` is the answer, so "the guard is released at
/// the terminal outcome — succeeded, failed or cancelled alike" falls out of the
/// item settling rather than out of a second place remembering to clear a
/// bit. There is no hook in `finish` to forget.
///
/// Keyed on the validated service name, so it cannot be confused by two commands
/// whose argv happens to look alike.
@MainActor
final class ServiceSubmissionGuard {
    private var submissions: [String: ActivityItem] = [:]

    init() {}

    /// The unsettled operation for this service, if there is one.
    func inFlight(for target: ServiceTarget) -> ActivityItem? {
        guard let item = submissions[target.name], !item.isTerminal else { return nil }
        return item
    }

    /// Remembers the operation just submitted for this service.
    ///
    /// A terminal item — the shape a submission with no runner produces — is
    /// deliberately still recorded: it answers `inFlight` with `nil` on the very
    /// next call, so a brew-absent affordance is never accidentally latched.
    func record(_ item: ActivityItem, for target: ServiceTarget) {
        submissions[target.name] = item
    }
}
