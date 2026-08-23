import BrewClient
import Catalog
import Foundation

/// Where `OperationCenter`'s terminal funnel hands its drafts (design D1, D7).
///
/// This is the whole reason `Persistence` depends on `BrewClient` rather than on
/// `Catalog` alone: the draft carries a `MutationOutcome` and a package identity,
/// and the mapping from those to stored primitives belongs in CellarCore where
/// `swift test` can reach it — not in the app target.
///
/// **Non-throwing, synchronous and `@MainActor`**, because the protocol is. A
/// write that fails surfaces on the store's own `lastError` and never reaches
/// the operation that produced it: recording is a side effect of a terminal
/// outcome, never a precondition of one (installation-history IH7).
@MainActor
public final class SwiftDataHistoryRecorder: HistoryRecording {
    private let store: HistoryStore

    /// Takes the store rather than a container, so the projection the History
    /// view is reading refreshes with the row that was just written, and there
    /// is exactly one `availability`/`lastError` for the whole capability.
    public init(store: HistoryStore) {
        self.store = store
    }

    public func record(_ draft: HistoryDraft) {
        store.append(Self.row(from: draft))
    }

    // MARK: - Draft → row

    /// Pure, and deliberately so: every field of the mapping is checkable
    /// without a container, a context or a clock.
    ///
    /// Two V1 rules are applied here rather than assumed downstream. **Absence
    /// is the empty string**: a grouped `upgradeAll` names no package, and
    /// `name == ""` is what says so. And **`commandText` is a denormalisation**
    /// of the argv, written at the same moment as the argv so the two cannot
    /// disagree.
    static func row(from draft: HistoryDraft) -> HistoryEntry {
        let classified = classify(draft.outcome)
        return HistoryEntry(
            id: draft.id,
            date: draft.date,
            kindRaw: draft.packageID?.kind.rawValue ?? "",
            name: draft.packageID?.name ?? "",
            verb: draft.verb,
            versionFrom: draft.versions?.from ?? "",
            versionTo: draft.versions?.to ?? "",
            outcomeRaw: classified.raw,
            exitStatus: classified.exitStatus,
            argv: draft.argv,
            commandText: draft.commandText
        )
    }

    /// The outcome as two stored primitives, never as a `Codable` enum.
    ///
    /// The domain enum carries associated values and will grow; pinning the
    /// on-disk shape to it would make every future outcome a migration (D2). The
    /// name is taken from the **classified** outcome, so nothing brew wrote can
    /// decide what a row says happened.
    ///
    /// `exitStatus` is recorded only where it is actually known: `succeeded`
    /// means exit 0 by definition and `failed` carries its status, while a busy,
    /// privilege, cancelled, abandoned or launch failure has no status this
    /// layer observed. Inventing one would be a confident lie in a durable row.
    static func classify(_ outcome: MutationOutcome) -> (raw: String, exitStatus: Int?) {
        switch outcome {
        case .succeeded: ("succeeded", 0)
        // Exit 0 by definition — brew ran, reported that nothing needed doing,
        // and returned cleanly. The status is known here, unlike for the
        // failures below, so it is recorded rather than invented.
        case .noChange: ("noChange", 0)
        case .failed(let status): ("failed", Int(status))
        case .busy: ("busy", nil)
        case .needsPrivileges: ("needsPrivileges", nil)
        case .cancelled: ("cancelled", nil)
        case .abandoned: ("abandoned", nil)
        case .launchFailed: ("launchFailed", nil)
        case .authorizationDenied(.evidenceChanged):
            ("authorizationDeniedEvidenceChanged", nil)
        case .authorizationDenied(.evidenceUnavailable):
            ("authorizationDeniedEvidenceUnavailable", nil)
        // The command never ran, so brew reported no status this layer could
        // record — and the row says what happened without naming a tap, because
        // the outcome carries none (package-mutation PM10).
        case .refusedUntrustedTap: ("refusedUntrustedTap", nil)
        }
    }
}
