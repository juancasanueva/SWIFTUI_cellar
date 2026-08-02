//
//  InstalledFilterBar.swift
//  cellar
//

import BrewClient
import SwiftUI

/// The Installed list's controls: the dependency toggle and the outdated count.
struct InstalledFilterBar: View {
    @Binding var includeDependencies: Bool
    let outdatedCount: Int
    let state: InstalledLoadState

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Show dependencies", isOn: $includeDependencies)
                .toggleStyle(.checkbox)
                .disabled(isDisabled)

            if outdatedCount > 0 {
                Label("\(outdatedCount) outdated", systemImage: "arrow.up.circle")
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
    return InstalledFilterBar(
        includeDependencies: $includeDependencies,
        outdatedCount: 3,
        state: .loaded
    )
}
