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
}
