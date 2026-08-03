import Catalog
import Foundation

/// What a multi-selection is eligible for, derived once (design D8,
/// installed-inventory II13).
///
/// Built from the **ordered** selection, so both arrays come out in selection
/// order and stay there through submission — which is what
/// `installed-inventory` requires and what a `Set<PackageID>` cannot carry.
///
/// Pure and value-typed, like every other rule in this module: the views own no
/// part of it.
public struct BulkSelection: Sendable {
    /// Selected ∧ outdated ∧ not pinned ∧ not snoozed, in selection order.
    public let upgradable: [PackageID]
    /// Selected ∧ still installed, in selection order.
    public let uninstallable: [PackageID]

    /// The verbs a selection can be acted on with.
    ///
    /// `CaseIterable` with exactly two cases, so the absence of a bulk pin,
    /// unpin, snooze, favorite or note affordance is a **test assertion** rather
    /// than a convention — the same technique `ActivityItem.Control` uses
    /// (installed-inventory II13 sc4).
    public enum Action: Sendable, Equatable, CaseIterable {
        case upgrade
        case uninstall

        public var title: String {
            switch self {
            case .upgrade: "Upgrade"
            case .uninstall: "Uninstall"
            }
        }

        /// Whether confirming is required before anything is submitted. Only
        /// the destructive one (package-mutation PM3).
        public var requiresConfirmation: Bool { self == .uninstall }
    }

    public init(
        selection: [PackageID],
        entries: [PackageEntry],
        metadata: MetadataLookup? = nil
    ) {
        let present = Dictionary(
            entries.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Reconciled against the inventory first: a package that has left it
        // cannot be acted on, so it leaves the selection rather than producing
        // an operation for something the app no longer lists (II13 sc3).
        let live = selection.filter { present[$0] != nil }

        uninstallable = live
        upgradable = live.filter { id in
            guard let installed = present[id]?.installed, installed.isOutdated else { return false }
            guard !installed.isPinned else { return false }
            return !PackageMetadata.isSnoozed(
                offering: installed.catalogVersion,
                snoozedVersion: metadata?(id)?.snoozedVersion
            )
        }
    }

    public var isEmpty: Bool { uninstallable.isEmpty && upgradable.isEmpty }

    /// The ids `action` would submit, in selection order.
    public func ids(for action: Action) -> [PackageID] {
        switch action {
        case .upgrade: upgradable
        case .uninstall: uninstallable
        }
    }

    /// Whether the control should be offered at all.
    ///
    /// **Unavailable rather than inert**: a control that is enabled and does
    /// nothing when pressed is the failure mode II13 sc5 forbids.
    public func isAvailable(_ action: Action) -> Bool {
        !ids(for: action).isEmpty
    }

    /// The label a control announces, counting exactly what it would submit.
    public func label(for action: Action) -> String {
        "\(action.title) \(ids(for: action).count)"
    }

    /// The selection with departed packages removed, for writing back to the
    /// list's own state at the next refresh.
    public func reconciled(against entries: [PackageEntry]) -> [PackageID] {
        let present = Set(entries.map(\.id))
        return uninstallable.filter { present.contains($0) }
    }
}

extension InstalledBrowse {
    /// How many packages a bulk upgrade would submit.
    ///
    /// Derived from `upgradableIDs` rather than counted separately, so it is
    /// **impossible** for the control to announce one number and submit a
    /// different set (installed-inventory II14).
    public func upgradableCount(
        includingDependencies: Bool,
        metadata: MetadataLookup? = nil
    ) -> Int {
        upgradableIDs(includingDependencies: includingDependencies, metadata: metadata).count
    }
}
