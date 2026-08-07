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
        HStack(spacing: 5) {
            FilterChip(label: "Dependencies", isOn: includeDependencies) {
                includeDependencies.toggle()
            }
            .disabled(isDisabled)
            .help("Include packages installed only as dependencies")

            FilterChip(label: "Favorites", isOn: favoritesOnly) {
                favoritesOnly.toggle()
            }
            .disabled(isDisabled || !isFavoritesEnabled)
            .help(isFavoritesEnabled ? "Show favorites only" : "Local metadata is unavailable.")

            if upgradableCount > 0 {
                Label("\(upgradableCount) outdated", systemImage: "arrow.up.circle")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.orange)
                    .padding(.leading, 5)
            }

            Spacer(minLength: 0)

            if case .loading = state {
                ProgressView().controlSize(.small)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
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
