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
    /// Which kinds are shown. Formulae, casks and — when the npm source is on —
    /// npm packages, each a toggle that is on by default; the selection itself
    /// refuses to turn the last one off.
    @Binding var kinds: InstalledKindSelection
    @Binding var includeDependencies: Bool
    /// How many packages a bulk upgrade would submit.
    ///
    /// This is `InstalledBrowse.upgradableIDs.count` — **the same projection the
    /// bulk action submits**, so the number announced here and the set that runs
    /// cannot drift apart. Counting the outdated rows separately is exactly the
    /// M2-2 defect this closes (installed-inventory II14).
    let upgradableCount: Int
    let state: InstalledLoadState
    /// Whether the npm chip is offered, and why not when it is not.
    ///
    /// Defaulted to `disabled`, which is what every existing call site means and
    /// what a build with the switch off renders: the chip is absent entirely
    /// rather than present and inert. A greyed-out control that changes nothing
    /// is the shape `SettingsView`'s own rule already refuses, and the reason a
    /// user would want is in Settings, not on a chip they cannot press.
    /// `NpmSourceUnavailableReason.guidance` carries that sentence for the
    /// surfaces that do want to say it.
    var npmSource: NpmSourceAvailability = .disabled

    /// Formulae / Casks / npm toggles, the dependency toggle and the outdated count.
    var body: some View {
        HStack(spacing: 5) {
            kindChip("Formulae", .formula)
                .accessibilityIdentifier("installed-kind-formula")
            kindChip("Casks", .cask)
                .accessibilityIdentifier("installed-kind-cask")
            if npmSource.isAvailable {
                kindChip("npm", .npm)
                    .accessibilityIdentifier("installed-source-npm")
            }

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

    private func kindChip(_ label: String, _ kind: PackageKind) -> some View {
        FilterChip(label: label, isOn: kinds.contains(kind)) {
            kinds.toggle(kind, npmEnabled: npmSource.isAvailable)
        }
        .disabled(isDisabled)
    }

    private var isDisabled: Bool {
        if case .brewAbsent = state { return true }
        return false
    }
}

#Preview {
    @Previewable @State var kinds = InstalledKindSelection()
    @Previewable @State var includeDependencies = false
    return InstalledFilterBar(
        kinds: $kinds,
        includeDependencies: $includeDependencies,
        upgradableCount: 3,
        state: .loaded,
        npmSource: .available
    )
}
