//
//  InstalledFilterBar.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The Installed list's controls: the kind chips, the dependency toggle and
/// the outdated count.
struct InstalledFilterBar: View {
    /// `nil` shows both kinds — the same three-way choice the Search catalog's
    /// kind chips offer.
    @Binding var kind: PackageKind?
    @Binding var includeDependencies: Bool
    /// How many packages a bulk upgrade would submit.
    ///
    /// This is `InstalledBrowse.upgradableIDs.count` — **the same projection the
    /// bulk action submits**, so the number announced here and the set that runs
    /// cannot drift apart. Counting the outdated rows separately is exactly the
    /// M2-2 defect this closes (installed-inventory II14).
    let upgradableCount: Int
    let state: InstalledLoadState

    var body: some View {
        HStack(spacing: 5) {
            FilterChip(label: "All", isOn: kind == nil) {
                kind = nil
            }
            .disabled(isDisabled)
            FilterChip(label: "Formulae", isOn: kind == .formula) {
                kind = .formula
            }
            .disabled(isDisabled)
            FilterChip(label: "Casks", isOn: kind == .cask) {
                kind = .cask
            }
            .disabled(isDisabled)

            FilterChip(label: "Dependencies", isOn: includeDependencies) {
                includeDependencies.toggle()
            }
            .disabled(isDisabled)
            .help("Include packages installed only as dependencies")

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
    @Previewable @State var kind: PackageKind?
    @Previewable @State var includeDependencies = false
    return InstalledFilterBar(
        kind: $kind,
        includeDependencies: $includeDependencies,
        upgradableCount: 3,
        state: .loaded
    )
}
