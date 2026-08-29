import BrewProcess
import Catalog
import Foundation

/// The version transition Cellar **intended** when it submitted the mutation.
///
/// Captured at submission rather than observed afterwards (design D7). Diffing
/// an inventory snapshot either side of the operation would need a re-snapshot
/// to land before the write, would make the entry depend on watcher timing, and
/// is exactly the per-package attribution the settled `upgradeAll` decision
/// declines.
public struct VersionTransition: Sendable, Hashable {
    // swiftlint:disable identifier_name
    // `from`/`to` are the interface the design specifies and the pair a reader
    // expects; `toVersion` inside a type already called `VersionTransition`
    // would be noise.
    public let from: String
    public let to: String

    /// Fails unless both ends are known: half a transition is worse than none,
    /// because a row rendering "1.2.2 → " reads as data loss rather than as
    /// absence.
    public init?(from: String, to: String) {
        guard !from.isEmpty, !to.isEmpty else { return nil }
        self.from = from
        self.to = to
    }
    // swiftlint:enable identifier_name
}

/// One durable entry, as the terminal funnel hands it over.
public struct HistoryDraft: Sendable {
    /// The `ActivityItem`'s id. `#Unique` on it downstream means a replayed
    /// write cannot double-log.
    public let id: UUID
    public let date: Date
    /// `nil` for a grouped `upgradeAll`, which names no package.
    public let packageID: PackageID?
    public let verb: String
    public let versions: VersionTransition?
    public let outcome: MutationOutcome
    public let argv: [String]
    /// The newest log lines of a plain failure, verbatim — empty for every
    /// other outcome. Display-only, like the argv: nothing ever parses it.
    public let failureTail: [String]

    public init(
        id: UUID,
        date: Date,
        packageID: PackageID?,
        verb: String,
        versions: VersionTransition?,
        outcome: MutationOutcome,
        argv: [String],
        failureTail: [String] = []
    ) {
        self.id = id
        self.date = date
        self.packageID = packageID
        self.verb = verb
        self.versions = versions
        self.outcome = outcome
        self.argv = argv
        self.failureTail = failureTail
    }

    /// How many log lines a failure keeps in its durable record.
    public static let failureTailLimit = 20

    /// The tail a terminal outcome earns: the newest lines for `.failed` —
    /// the one outcome whose only explanation is the log — and nothing for
    /// every other, which already names its own cause. Verbatim on purpose:
    /// classification happened before this, so nothing brew wrote can change
    /// what the row says happened, only explain it.
    public static func failureTail(of log: [LogLine], for outcome: MutationOutcome) -> [String] {
        guard case .failed = outcome else { return [] }
        return log.suffix(failureTailLimit).map(\.text)
    }

    /// The argv as one string, for search and for the copy affordance.
    ///
    /// Rendered here so the stored form and the copied form are the same
    /// projection of the same vector — and, like `displayCommand`, it is
    /// **one-way**: nothing parses it back into a command.
    public var commandText: String { argv.joined(separator: " ") }
}

/// Where a terminal outcome's durable record goes.
///
/// **Synchronous, `@MainActor`, and non-throwing**, and all three are load-
/// bearing. `OperationCenter.finish(_:with:)` is already the single, idempotent
/// terminal funnel that pays the mutation gate exactly once; hanging the write
/// there makes "exactly one entry per terminal outcome" true by construction
/// rather than by discipline. Non-throwing because a failed *write* must never
/// change a *mutation's* reported outcome — the store surfaces its own
/// `lastError` instead (installation-history IH7).
@MainActor public protocol HistoryRecording {
    func record(_ draft: HistoryDraft)
}

/// The default: accepts every draft and stores nothing.
///
/// The seam's identity element, so an app with no store configured behaves
/// exactly as it did before history existed — and so reverting this feature is
/// one injection away (IH7 sc1).
public struct NoHistoryRecording: HistoryRecording {
    public init() {}

    @MainActor public func record(_: HistoryDraft) {}
}
