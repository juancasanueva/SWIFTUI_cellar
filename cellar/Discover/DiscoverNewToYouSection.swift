//
//  DiscoverNewToYouSection.swift
//  cellar
//

import Catalog
import SwiftUI

/// What this Mac has seen for the first time in the last thirty days.
///
/// The empty state is a **designed, explained** state (D5): never a spinner,
/// never a hidden section. The sentence comes from `CellarCore`, where a test
/// owns the wording — the claim being made is about this machine's first
/// observation, and the catalog carries no publication date that could support
/// anything stronger.
struct DiscoverNewToYouSection: View {
    let model: DiscoverArrivalsModel
    @Binding var selection: PackageID?

    var body: some View {
        Section {
            if model.isEmpty {
                DiscoverSectionNote(text: model.explanation ?? "")
            } else {
                ForEach(model.rows) { row in
                    DiscoverArrivalRowView(row: row)
                        .tag(row.id)
            .themedListSelection(isSelected: selection == row.id)
                }
                if let hidden = model.hiddenLabel {
                    Text(hidden)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("New to you")
        } footer: {
            // Shown even when the section is populated: the sentence is what
            // stops the dates from being read as release dates.
            if model.isEmpty == false, let explanation = model.explanation {
                Text(explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DiscoverArrivalRowView: View {
    let row: DiscoverArrivalRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.displayName)
            Spacer(minLength: 8)
            Text(row.firstSeenLabel(relativeTo: .now))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// The one way a Discover section says why it has nothing to show.
///
/// Shared so no section can quietly render a blank list instead: every empty
/// state in this tree goes through here, and the text it is handed always came
/// from `CellarCore`.
struct DiscoverSectionNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
            // Named so a UI test can find the sentence: inside a `List`, the
            // note's text is nested deeply enough that querying by label alone
            // does not reach it reliably.
            .accessibilityIdentifier("discover-section-note")
            .accessibilityLabel(text)
    }
}
