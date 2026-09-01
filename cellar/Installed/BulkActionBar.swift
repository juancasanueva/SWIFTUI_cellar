//
//  BulkActionBar.swift
//  cellar
//

import BrewClient
import Catalog
import Persistence
import SwiftUI

/// The words the snooze control says.
///
/// Named constants because this is the one verb in the app whose ordinary English
/// meaning is a **duration** and whose implementation deliberately is not. A
/// snooze here lasts until a different version is offered — not an hour, not a
/// week, not "remind me later" — and `local-package-metadata` makes that a
/// requirement rather than a preference, precisely because the honest wording is
/// the unnatural one.
nonisolated enum BulkSnoozeCopy {
    static func label(count: Int) -> String { "Snooze \(count)" }

    static let explanation =
        "Hides the update badge for the selected packages until a different version is offered."
}

/// What a multi-selection can be snoozed toward.
///
/// One snooze per package, each naming **that package's own** offered version.
/// N outdated packages are outdated toward N different versions, so a batch that
/// shared one version would mis-scope N−1 of them and suppress badges for
/// versions those packages were never outdated toward (LPM4).
///
/// Eligibility is outdated ∧ not already snoozed at the offered version ∧ having
/// an offered version to name at all. A package with nothing to snooze toward is
/// left out of both the count and the write, so the number announced and the rows
/// written are the same set (II14).
///
/// **Nothing here compares, orders or ranks a version.** `PackageMetadata.isSnoozed`
/// is exact string equality, and that is the whole rule; `SnoozeGuardTests` scans
/// this file for every comparator token it forbids elsewhere in the capability.
nonisolated struct BulkSnoozeSelection: Sendable, Hashable {
    /// Eligible ids, in selection order.
    let snoozable: [PackageID]
    private let offers: [PackageID: String]

    init(selection: [PackageID], entries: [PackageEntry], metadata: MetadataLookup?) {
        let present = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var eligible: [PackageID] = []
        var offered: [PackageID: String] = [:]
        for id in selection {
            guard let installed = present[id]?.installed, installed.isOutdated else { continue }
            // Nothing to snooze toward is not a placeholder, an empty string or a
            // neighbour's version — it is simply not eligible.
            let version = installed.catalogVersion
            guard version.isEmpty == false else { continue }
            guard PackageMetadata.isSnoozed(
                offering: version,
                snoozedVersion: metadata?(id)?.snoozedVersion
            ) == false else { continue }

            eligible.append(id)
            offered[id] = version
        }
        snoozable = eligible
        offers = offered
    }

    var count: Int { snoozable.count }

    /// **Unavailable rather than inert** on an empty eligible set (II13 sc5).
    var isAvailable: Bool { snoozable.isEmpty == false }

    /// The version this package would be snoozed toward — its own, or `nil`.
    func offeredVersion(for id: PackageID) -> String? { offers[id] }

    /// Records one snooze per eligible package, in selection order.
    ///
    /// The result is indistinguishable from having snoozed each one individually,
    /// in any order: no shared version, no batch identity, no group record.
    func apply(_ record: (PackageID, String) -> Void) {
        for id in snoozable {
            guard let version = offers[id] else { continue }
            record(id, version)
        }
    }
}

/// Every bulk control's label, count, role and enablement — as a value.
///
/// Extracted so all four are provable **without rendering** (the
/// `PackageInspectionRow` idiom). The bar shipped with no covering tests at all,
/// and it is now the surface that announces five different numbers over one
/// selection; "the label counts exactly the set it submits" (II14) is not a claim
/// a view body can be asked to make.
///
/// Each count comes from the same projection its own action submits:
/// `BulkSelection.ids(for:)` for the four mutation verbs, `BulkSnoozeSelection`
/// for snooze. There is no second count anywhere to drift from the first.
nonisolated struct BulkActionBarPresentation: Sendable, Hashable {
    struct Control: Sendable, Hashable {
        let label: String
        let count: Int
        let isEnabled: Bool
        let isDestructive: Bool
    }

    struct Entry: Sendable, Hashable {
        let action: BulkSelection.Action
        let control: Control
    }

    /// One per `BulkSelection.Action`, in `allCases` order.
    let mutations: [Entry]
    /// Beside them, never among them (HD11).
    let snooze: Control

    init(selection: BulkSelection, snooze snoozeSelection: BulkSnoozeSelection, isOperationAvailable: Bool) {
        mutations = BulkSelection.Action.allCases.map { action in
            Entry(
                action: action,
                control: Control(
                    label: selection.label(for: action),
                    count: selection.ids(for: action).count,
                    isEnabled: selection.isAvailable(action) && isOperationAvailable,
                    isDestructive: action == .uninstall
                )
            )
        }
        snooze = Control(
            label: BulkSnoozeCopy.label(count: snoozeSelection.count),
            count: snoozeSelection.count,
            // Snooze spawns nothing and submits nothing, so a missing brew is no
            // reason to withhold it.
            isEnabled: snoozeSelection.isAvailable,
            isDestructive: false
        )
    }

    var controls: [Control] { mutations.map(\.control) + [snooze] }

    func control(for action: BulkSelection.Action) -> Control? {
        mutations.first { $0.action == action }?.control
    }
}

/// What a multi-selection can be acted on with (installed-inventory II13,
/// package-mutation PM8).
///
/// Four mutation verbs — upgrade, uninstall, pin and unpin — and nothing else,
/// not because this view omits the rest but because `BulkSelection.Action` is
/// `CaseIterable` with exactly four cases and this bar iterates it. A bulk
/// favorite or note cannot be added here without adding a case, which a test
/// would fail.
///
/// **Snooze is the deliberate exception, and it sits beside the loop rather than
/// inside it.** It produces no `MutationCommand`, so a fifth case would need a
/// `case snooze: []` arm in `commands(for:over:)` — a silent no-op the type system
/// cannot catch — and `MetadataStore` lives in `Persistence` while `BulkSelection`
/// lives in `BrewClient`, which must not link SwiftData. So it writes one row per
/// package through the shipped store API and submits nothing (design HD11).
///
/// Every control is **unavailable rather than inert**: a button that is enabled
/// and does nothing when pressed is the failure mode II13 sc5 forbids, so each
/// label counts exactly what would be submitted, and a verb whose eligible set
/// is empty does not render at all.
struct BulkActionBar: View {
    let selection: BulkSelection
    let operations: OperationCenter
    let inventory: InstalledInventory
    let snooze: BulkSnoozeSelection
    /// The shipped store API, handed in rather than reached for, so this view
    /// records snoozes only through `MetadataStore` (LPM5).
    let metadata: MetadataStore

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BulkSelection.Action.allCases, id: \.self) { action in
                // A verb with nothing to act on does not render at all: a
                // zero-count control adds a number and no information, and a
                // dimmed one makes the whole row read like a summary line.
                if let control = presentation.control(for: action), control.count > 0 {
                    Button(control.label, role: action == .uninstall ? .destructive : nil) {
                        // Confirming is decided by the centre, not here — every
                        // bulk batch asks first (bulk-confirmation ruling
                        // 2026-09-01), and a `nil` request means there was
                        // nothing to submit.
                        operations.submitBulk(
                            action,
                            over: selection.ids(for: action),
                            in: inventory
                        )
                    }
                    .buttonStyle(ActionPillStyle(isDestructive: control.isDestructive))
                    .disabled(!control.isEnabled)
                }
            }
            if presentation.snooze.count > 0 {
                Button(presentation.snooze.label, action: applySnooze)
                    .buttonStyle(ActionPillStyle())
                    .disabled(!presentation.snooze.isEnabled)
                    .help(BulkSnoozeCopy.explanation)
                    .accessibilityIdentifier("bulk-snooze")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .help(operations.unavailableGuidance ?? "Act on the selected packages")
    }

    private var presentation: BulkActionBarPresentation {
        BulkActionBarPresentation(
            selection: selection,
            snooze: snooze,
            isOperationAvailable: operations.isAvailable
        )
    }

    /// One write per package, each naming that package's own offered version.
    private func applySnooze() {
        snooze.apply { id, version in
            metadata.snooze(id, offering: version)
        }
    }
}
