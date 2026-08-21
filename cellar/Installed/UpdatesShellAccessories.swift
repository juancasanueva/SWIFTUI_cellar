//
//  UpdatesShellAccessories.swift
//  cellar
//

import BrewClient
import SwiftUI

/// The Updates bar's own chip: an explicit `brew update`.
///
/// The Refresh button beside it re-reads what the local brew already knows;
/// this one advances that knowledge. Cellar pins `HOMEBREW_NO_AUTO_UPDATE=1`
/// on every invocation, so without this affordance the app can show a fresher
/// "Latest version" from its own catalog than any upgrade would install —
/// permanently, until the user runs `brew update` in a terminal.
///
/// The view owns no rule: eligibility is `OperationCenter.isAvailable` and
/// `isHomebrewUpdateInFlight`, both proven in the package's own suite. It
/// submits through the same spine as every mutation, so the operation gets the
/// activity log, cancel, history entry and the inventory re-snapshot its
/// terminal pays (via `.installedInventory` in the command's own scope).
struct UpdatesShellAccessories: View {
    let operations: OperationCenter

    var body: some View {
        Button("Update Homebrew", systemImage: "arrow.triangle.2.circlepath") {
            operations.submit(.update)
        }
        .buttonStyle(ShellChipButtonStyle())
        .disabled(!operations.isAvailable || operations.isHomebrewUpdateInFlight)
        .help(
            operations.unavailableGuidance
                ?? "Run brew update so Homebrew learns about the newest versions"
        )
    }
}
