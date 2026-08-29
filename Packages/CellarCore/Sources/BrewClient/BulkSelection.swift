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
    /// Selected ∧ still installed ∧ a formula ∧ **not** currently pinned.
    public let pinnable: [PackageID]
    /// Selected ∧ still installed ∧ a formula ∧ currently pinned.
    public let unpinnable: [PackageID]

    /// The verbs a selection can be acted on with.
    ///
    /// `CaseIterable` with exactly four cases, so the absence of a bulk snooze,
    /// favorite or note affordance is a **test assertion** rather than a
    /// convention — the same technique `ActivityItem.Control` uses
    /// (installed-inventory II13).
    ///
    /// Pin and unpin are **two independent verbs, not one toggle**. A toggle's
    /// meaning would depend on how homogeneous the selection happened to be, and
    /// a selection holding both pinned and unpinned packages has no single
    /// correct answer — which is exactly what II13's "a bulk control that cannot
    /// act on the current selection MUST be unavailable rather than inert"
    /// forbids guessing about. Two verbs, each with its own eligibility, is the
    /// only shape that never guesses.
    ///
    /// Snooze is deliberately **not** a case here. It produces no
    /// `MutationCommand`, so a fifth case would need a `case snooze: []` arm in
    /// `commands(for:over:)` — a silent no-op the type system cannot catch — and
    /// `MetadataStore` lives in `Persistence` while this type lives in
    /// `BrewClient`, which must not link SwiftData. It travels its own app-side
    /// path instead (design HD11).
    public enum Action: Sendable, Equatable, CaseIterable {
        case upgrade
        case uninstall
        case pin
        case unpin

        public var title: String {
            switch self {
            case .upgrade: "Upgrade"
            case .uninstall: "Uninstall"
            case .pin: "Pin"
            case .unpin: "Unpin"
            }
        }

        /// Whether confirming is required before anything is submitted. Only
        /// the destructive one (package-mutation PM3). Pin and unpin are
        /// reversible in one click and ask nothing.
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
        // Homebrew-only, by maintainer decision: an npm global is upgraded from
        // its own row, or from select-all under the Updates lens, rather than
        // from the multi-selection toolbar. Removal is **not** restricted the
        // same way — an npm identity is uninstallable in bulk like any other,
        // and `commands(for:over:)` builds it an `npm uninstall -g` (design D14,
        // `package-mutation`).
        upgradable = live.filter { id in
            guard id.kind.source == .homebrew else { return false }
            guard let installed = present[id]?.installed, installed.isOutdated else { return false }
            guard !installed.isPinned else { return false }
            return !PackageMetadata.isSnoozed(
                offering: installed.catalogVersion,
                snoozedVersion: metadata?(id)?.snoozedVersion
            )
        }

        // Formula-only, because `MutationCommand.pin(formula:)` takes a
        // `FormulaID` by construction — "pin a cask" is unrepresentable rather
        // than validated, so a cask in the selection produces no command at all
        // and must not be counted as though it would.
        //
        // Derived **independently** of each other: a mixed pinned/unpinned
        // selection offers both verbs with honest counts, and neither guesses
        // about the other's members (II13).
        let formulae = live.filter { id in
            id.kind == .formula && present[id]?.installed != nil
        }
        pinnable = formulae.filter { present[$0]?.installed?.isPinned == false }
        unpinnable = formulae.filter { present[$0]?.installed?.isPinned == true }
    }

    public var isEmpty: Bool { uninstallable.isEmpty && upgradable.isEmpty }

    /// The ids `action` would submit, in selection order.
    public func ids(for action: Action) -> [PackageID] {
        switch action {
        case .upgrade: upgradable
        case .uninstall: uninstallable
        case .pin: pinnable
        case .unpin: unpinnable
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
