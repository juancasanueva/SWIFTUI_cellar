//
//  CatalogFilterBar.swift
//  cellar
//

import Catalog
import SwiftUI

/// The three predicates the persisted catalog can actually answer.
///
/// There is no "installed" or "outdated" toggle here, and that is not an
/// omission: the catalog is the published index, and it has no idea what this
/// machine has installed (package-search PS4).
struct CatalogFilterBar: View {
    @Binding var filters: SearchFilters

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
    return CatalogFilterBar(filters: $filters)
}
