//
//  InstalledFilterBar.swift
//  cellar
//

import BrewClient
import BrewProcess
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
    /// `nil` shows every source. Its own dimension beside the kind chips: npm is
    /// not a kind of Homebrew package.
    @Binding var source: PackageSource?
    /// Whether the Source chips may be used, and why not when they may not.
    ///
    /// Defaulted to `disabled`, which is what every existing call site means and
    /// what a build with the switch off renders: the chips are absent entirely
    /// rather than present and inert.
    var npmSource: NpmSourceAvailability = .disabled

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            kindRow
            // Its own row: two filter dimensions side by side wrap the chips
            // mid-word once the source chips appear.
            if npmSource.isAvailable {
                HStack(spacing: 5) {
                    sourceChips
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13))
    }

    /// All / Formulae / Casks, the dependency toggle and the outdated count.
    private var kindRow: some View {
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
    }

    /// All / Homebrew / npm, rendered only when npm is genuinely available.
    ///
    /// Absent rather than disabled when it is not. A greyed-out control that
    /// changes nothing is the shape `SettingsView`'s own rule already refuses,
    /// and the reason a user would want is in Settings, not on a chip they
    /// cannot press. `NpmSourceUnavailableReason.guidance` carries that sentence
    /// for the surfaces that do want to say it.
    @ViewBuilder
    private var sourceChips: some View {
        FilterChip(label: "Any source", isOn: source == nil) { source = nil }
            .disabled(isDisabled)
        FilterChip(label: "Homebrew", isOn: source == .homebrew) { source = .homebrew }
            .disabled(isDisabled)
        FilterChip(label: "npm", isOn: source == .npm) { source = .npm }
            .disabled(isDisabled)
            .accessibilityIdentifier("installed-source-npm")
    }

    private var isDisabled: Bool {
        if case .brewAbsent = state { return true }
        return false
    }
}

#Preview {
    @Previewable @State var kind: PackageKind?
    @Previewable @State var source: PackageSource?
    @Previewable @State var includeDependencies = false
    return InstalledFilterBar(
        kind: $kind,
        includeDependencies: $includeDependencies,
        upgradableCount: 3,
        state: .loaded,
        source: $source,
        npmSource: .available
    )
}
