//
//  BulkActionBar.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// What a multi-selection can be acted on with (installed-inventory II13,
/// package-mutation PM8).
///
/// Upgrade and uninstall, and nothing else — not because this view omits the
/// rest, but because `BulkSelection.Action` is `CaseIterable` with exactly two
/// cases and this bar iterates it. A bulk pin, unpin, snooze, favorite or note
/// cannot be added here without adding a case, which a test would fail.
///
/// Every control is **unavailable rather than inert**: a button that is enabled
/// and does nothing when pressed is the failure mode II13 sc5 forbids, so the
/// label counts exactly what would be submitted and disables itself at zero.
struct BulkActionBar: View {
    let selection: BulkSelection
    let operations: OperationCenter
    let inventory: InstalledInventory

    var body: some View {
        HStack(spacing: 8) {
            ForEach(BulkSelection.Action.allCases, id: \.self) { action in
                Button(selection.label(for: action), role: role(action)) {
                    // Confirming is decided by the centre, not here: a `nil`
                    // request means it was already submitted.
                    operations.submitBulk(
                        action,
                        over: selection.ids(for: action),
                        in: inventory
                    )
                }
                .disabled(!selection.isAvailable(action) || !operations.isAvailable)
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .help(operations.unavailableGuidance ?? "Act on the selected packages")
    }

    private func role(_ action: BulkSelection.Action) -> ButtonRole? {
        action == .uninstall ? .destructive : nil
    }
}
