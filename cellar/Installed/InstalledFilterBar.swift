//
//  InstalledFilterBar.swift
//  cellar
//

import BrewClient
import SwiftUI

/// The Installed list's controls: the dependency toggle, the favorites filter
/// and the outdated count.
struct InstalledFilterBar: View {
    @Binding var includeDependencies: Bool
    @Binding var favoritesOnly: Bool
    /// How many packages a bulk upgrade would submit.
    ///
    /// This is `InstalledBrowse.upgradableIDs.count` — **the same projection the
    /// bulk action submits**, so the number announced here and the set that runs
    /// cannot drift apart. Counting the outdated rows separately is exactly the
    /// M2-2 defect this closes (installed-inventory II14).
    let upgradableCount: Int
    /// Disabled when there is no metadata to intersect with, and, like the
    /// installed-state filters, disabled means the results are identical to the
    /// same query with no favorites filtering at all (II8).
    let isFavoritesEnabled: Bool
    let state: InstalledLoadState

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Show dependencies", isOn: $includeDependencies)
                .toggleStyle(.checkbox)
                .disabled(isDisabled)

            Toggle(isOn: $favoritesOnly) {
                Label("Favorites", systemImage: favoritesOnly ? "star.fill" : "star")
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .disabled(isDisabled || !isFavoritesEnabled)
            .help(isFavoritesEnabled ? "Show favorites only" : "Local metadata is unavailable.")

            if upgradableCount > 0 {
                Label("\(upgradableCount) outdated", systemImage: "arrow.up.circle")
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            if case .loading = state {
                ProgressView().controlSize(.small)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var isDisabled: Bool {
        if case .brewAbsent = state { return true }
        return false
    }
}

#Preview {
    @Previewable @State var includeDependencies = false
    @Previewable @State var favoritesOnly = false
    return InstalledFilterBar(
        includeDependencies: $includeDependencies,
        favoritesOnly: $favoritesOnly,
        upgradableCount: 3,
        isFavoritesEnabled: true,
        state: .loaded
    )
}
