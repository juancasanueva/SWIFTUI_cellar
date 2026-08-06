//
//  DiscoverCuratedSection.swift
//  cellar
//

import Catalog
import SwiftUI

/// The hand-picked list, one section per declared category.
///
/// Category and entry order is the resource's, never re-sorted here — that rule
/// belongs to the decoder and is asserted there.
struct DiscoverCuratedSection: View {
    let model: DiscoverCuratedModel
    @Binding var selection: PackageID?

    var body: some View {
        if let explanation = model.explanation {
            Section {
                DiscoverSectionNote(text: explanation)
            } header: {
                Text("Worth a look")
            }
        } else {
            ForEach(model.categories) { category in
                Section {
                    ForEach(category.rows) { row in
                        DiscoverCuratedRowView(row: row)
                            .tag(row.id)
                    }
                } header: {
                    Text(category.title)
                }
            }
        }
    }
}

private struct DiscoverCuratedRowView: View {
    let row: DiscoverCuratedRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.displayName)
            // The blurb is Cellar's own words about why this is worth having.
            // Deliberately not the package's `desc`, which is Homebrew's.
            Text(row.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
