//
//  InstalledEmptyState.swift
//  cellar
//

import BrewClient
import BrewProcess
import SwiftUI

/// Why the Installed list is empty — which is never the same reason twice.
///
/// Absent brew is **guidance, not an error**: there is nothing to retry and
/// nothing has failed, so the view offers the install one-liner rather than a
/// red banner. Browse and search keep working either way (installed-inventory
/// II9).
struct InstalledEmptyState: View {
    let state: InstalledLoadState
    /// Which slice of the inventory is standing empty. "Nothing has an update"
    /// and "nothing was installed on request" are different facts, and telling
    /// the first user the second sentence sends them hunting for a toggle that
    /// would show them nothing.
    var lens: InstalledLens = .all

    var body: some View {
        switch state {
        case .idle, .loading:
            ContentUnavailableView("Reading installed packages", systemImage: "shippingbox")

        case .loaded:
            switch lens {
            case .updates:
                ContentUnavailableView(
                    "Everything is up to date",
                    systemImage: "checkmark.circle",
                    description: Text("No installed package has a pending update.")
                )
            case .favorites:
                ContentUnavailableView(
                    "No favorites yet",
                    systemImage: "heart",
                    description: Text("Click the star on any package to keep it here.")
                )
            case .all:
                ContentUnavailableView(
                    "Nothing installed on request",
                    systemImage: "shippingbox",
                    description: Text("Turn on “Show dependencies” to see everything brew installed.")
                )
            }

        case .brewAbsent(let absence):
            BrewAbsentGuidance(absence: absence)

        case .failed(let error):
            ContentUnavailableView(
                "Could not read installed packages",
                systemImage: "exclamationmark.triangle",
                description: Text(error.shortDescription)
            )
        }
    }
}

/// Read-only guidance for a machine with no usable Homebrew.
private struct BrewAbsentGuidance: View {
    let absence: InstalledAbsence

    var body: some View {
        // The wording lives in `InstalledPresentation`, next to the type it
        // describes and inside the `swift test` inner loop, exactly as
        // `CatalogPresentation` already does for sync errors.
        ContentUnavailableView {
            Label(absence.title, systemImage: "shippingbox")
        } description: {
            Text(absence.explanation)
        } actions: {
            if let guidance = absence.installGuidance {
                Link("Open brew.sh", destination: guidance.website)
                Text(guidance.installCommand)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
        }
    }
}

#Preview("Absent") {
    InstalledEmptyState(state: .brewAbsent(.notInstalled(.standard)))
}

#Preview("Failed") {
    InstalledEmptyState(state: .failed(.malformedPayload))
}
