//
//  CatalogFilterBar.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The catalog predicates, plus the installed-state mode.
///
/// The two are not the same kind of thing and are not stored together:
/// `SearchFilters` is answered by the published index, while the installed-state
/// mode is *composed* above it from the local snapshot. The catalog still has no
/// idea what this machine has installed (package-search PS4) — this bar simply
/// renders both controls next to each other.
struct CatalogFilterBar: View {
    @Binding var filters: SearchFilters
    @Binding var mode: InstalledFilterMode
    /// False when there is no inventory, which forces the mode to `all`.
    let isInstalledFilterEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            Picker("Kind", selection: kindSelection) {
                Text("All").tag(KindSelection.all)
                Text("Formulae").tag(KindSelection.formula)
                Text("Casks").tag(KindSelection.cask)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Picker("Installed state", selection: $mode) {
                ForEach(InstalledFilterMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!isInstalledFilterEnabled)
            .help(
                isInstalledFilterEnabled
                    ? "Filter by what this machine has installed"
                    : "Needs Homebrew: Cellar cannot tell what is installed without it"
            )

            Toggle("Hide deprecated", isOn: $filters.excludeDeprecated)
                .toggleStyle(.checkbox)
            Toggle("Hide disabled", isOn: $filters.excludeDisabled)
                .toggleStyle(.checkbox)

            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var kindSelection: Binding<KindSelection> {
        Binding(
            get: { KindSelection(kinds: filters.kinds) },
            set: { filters.kinds = $0.kinds }
        )
    }

    /// A three-way picker over what the model stores as a set, so "neither" is
    /// unrepresentable in the UI.
    enum KindSelection: Hashable {
        case all, formula, cask

        init(kinds: Set<PackageKind>) {
            switch kinds {
            case [.formula]: self = .formula
            case [.cask]: self = .cask
            default: self = .all
            }
        }

        var kinds: Set<PackageKind> {
            switch self {
            case .all: [.formula, .cask]
            case .formula: [.formula]
            case .cask: [.cask]
            }
        }
    }
}

#Preview {
    @Previewable @State var filters = SearchFilters()
    @Previewable @State var mode = InstalledFilterMode.all
    return CatalogFilterBar(filters: $filters, mode: $mode, isInstalledFilterEnabled: true)
}
