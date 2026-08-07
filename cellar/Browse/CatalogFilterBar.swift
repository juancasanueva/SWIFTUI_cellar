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
    /// Hides rows this machine already has. A view-level subtraction over the
    /// composed rows, not a catalog predicate: the catalog still has no idea
    /// what is installed (PS4). The old four-way installed-state chips are
    /// gone by request — this toggle and the Outdated chip are what remain.
    @Binding var hideInstalled: Bool
    /// The design's fourth chip: narrows the list to installed packages with a
    /// pending update, composing with the kind chips and the query.
    @Binding var outdatedOnly: Bool
    /// False when there is no inventory, which makes the toggle inert rather
    /// than wrong — so it is disabled instead.
    let isInstalledFilterEnabled: Bool

    var body: some View {
        HStack(spacing: 5) {
                FilterChip(label: "All", isOn: kindSelection.wrappedValue == .all) {
                    kindSelection.wrappedValue = .all
                }
                FilterChip(label: "Formulae", isOn: kindSelection.wrappedValue == .formula) {
                    kindSelection.wrappedValue = .formula
                }
                FilterChip(label: "Casks", isOn: kindSelection.wrappedValue == .cask) {
                    kindSelection.wrappedValue = .cask
                }
                if isInstalledFilterEnabled {
                    FilterChip(label: "Outdated", isOn: outdatedOnly) {
                        outdatedOnly.toggle()
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Toggle("Hide deprecated", isOn: $filters.excludeDeprecated)
                    Toggle("Hide disabled", isOn: $filters.excludeDisabled)
                    Toggle("Hide installed", isOn: $hideInstalled)
                        // Without an inventory nothing is known to be
                        // installed, so the toggle would be inert rather than
                        // wrong — disabled with the reason, like the mode chips.
                        .disabled(!isInstalledFilterEnabled)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Deprecated, disabled and installed packages")
        }
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
    @Previewable @State var hideInstalled = false
    @Previewable @State var outdatedOnly = false
    return CatalogFilterBar(
        filters: $filters,
        hideInstalled: $hideInstalled,
        outdatedOnly: $outdatedOnly,
        isInstalledFilterEnabled: true
    )
}
