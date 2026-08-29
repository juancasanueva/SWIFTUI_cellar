//
//  InstalledEmptyState.swift
//  cellar
//

import BrewClient
import BrewProcess
import Catalog
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
    /// Which source the user narrowed to, when they narrowed to one.
    ///
    /// "You have no npm globals" and "nothing is installed on request" are
    /// different facts, and offering the dependency toggle to somebody looking
    /// at an empty npm list points them at a control that would show them
    /// nothing.
    var source: PackageSource?
    /// Whether the npm source is on and detected. Only meaningful when the whole
    /// list is empty: with npm off there are no npm rows to be missing, so the
    /// sentence is the brew-only one this list always showed.
    var isNpmContributing = false

    /// Whether the only source that could have contributed rows is npm.
    ///
    /// With Homebrew absent the list has no brew half to be empty, so the brew
    /// wording would be answering a question nobody asked.
    private var isNpmOnlyView: Bool {
        if case .brewAbsent = state { return true }
        return false
    }

    /// Whether an empty `all` list should be worded for npm.
    ///
    /// Extracted as a static function so the branch is provable without a
    /// window: which of two sentences an empty list shows is a decision, and a
    /// decision made inside `body` is a decision no test can reach. Rendering
    /// still happens below; only the choice moved.
    ///
    /// - Parameters:
    ///   - source: which source the user narrowed to, if any.
    ///   - isNpmContributing: whether npm is on and reporting.
    ///   - isBrewAbsent: whether there is a Homebrew half at all.
    static func isNpmEmptiness(
        source: PackageSource?,
        isNpmContributing: Bool,
        isBrewAbsent: Bool
    ) -> Bool {
        source == .npm || (source == nil && isNpmContributing && isBrewAbsent)
    }

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
                if Self.isNpmEmptiness(
                    source: source,
                    isNpmContributing: isNpmContributing,
                    isBrewAbsent: isNpmOnlyView
                ) {
                    ContentUnavailableView(
                        "No npm packages installed globally",
                        systemImage: "shippingbox",
                        description: Text("Global npm packages appear here once you install one.")
                    )
                } else {
                    ContentUnavailableView(
                        "Nothing installed on request",
                        systemImage: "shippingbox",
                        description: Text(
                            "Turn on “Show dependencies” to see everything brew installed."
                        )
                    )
                }
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
