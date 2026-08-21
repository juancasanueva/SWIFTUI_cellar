import Foundation

/// What an always-visible indicator needs, and nothing more
/// (operation-activity OA5).
///
/// Split out of `OperationCenter.swift` for the reason `OperationCenterBulk`
/// already was, and for the reason task 17.1 names: the centre's declaration
/// reached this package's 400-line bound, and the answer is a split rather than
/// a `swiftlint:disable`. The seam is honest — "what is running, and how much is
/// queued" is a projection *over* the centre, not part of running an operation.
extension OperationCenter {
    /// What an always-visible indicator needs, and nothing more.
    ///
    /// `@MainActor` rather than `Sendable`: it holds the live `ActivityItem`, so
    /// the bar and the drawer are looking at one object rather than at a copy
    /// that can fall behind it.
    @MainActor
    public struct Summary {
        public let isBusy: Bool
        public let running: ActivityItem?
        public let pendingCount: Int

        /// The running operation's command, for the collapsed bar.
        public var runningCommand: String? { running?.displayCommand }
    }

    /// The summary, derived from the very same items the detail listing shows,
    /// so the two cannot disagree about what is running or how much is queued.
    public var summary: Summary {
        Summary(
            isBusy: items.contains { !$0.isTerminal },
            running: items.first(where: \.isRunning),
            pendingCount: items.count(where: \.isPending)
        )
    }

    /// Whether a `brew update` is pending or running, for the chip that submits
    /// one. Read off the same items the listing shows, so the chip cannot offer
    /// a second update while the first is still deciding what is outdated —
    /// and comes back the moment the first one settles.
    ///
    /// Matched by erased-command equality — equality of *what will run* —
    /// rather than by inspecting a verb string, which the mutation spine's own
    /// structural scan forbids.
    public var isHomebrewUpdateInFlight: Bool {
        let update = AnyBrewMutation(MutationCommand.update)
        return items.contains { $0.command == update && !$0.isTerminal }
    }
}
