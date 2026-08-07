//
//  DiscoverLadderSection.swift
//  cellar
//

import Catalog
import SwiftUI

/// One most-installed ladder.
///
/// Presentation only: the ordering, the eligibility rule and the 1-based ranks
/// are all decided in `DiscoverRanking` and asserted there. This view places
/// what it is handed.
struct DiscoverLadderSection: View {
    let model: DiscoverLadderModel
    @Binding var selection: PackageID?

    var body: some View {
        Section {
            if let explanation = model.explanation {
                DiscoverSectionNote(text: explanation)
            } else {
                ForEach(model.rows) { row in
                    DiscoverLadderRowView(row: row)
                        .tag(row.id)
            .themedListSelection(isSelected: selection == row.id)
                }
            }
        } header: {
            Text(model.title)
        }
    }
}

private struct DiscoverLadderRowView: View {
    let row: DiscoverLadderRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(row.rank)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                // Catalog-published text renders as `Text` and nothing else —
                // no link, no URL built from it (threat-matrix TM4).
                Text(row.displayName)
                if let desc = row.desc {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // The count with the metric that belongs to *this* kind, so the
            // number is never read as something it does not measure.
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.installsLabel)
                    .font(.caption.monospacedDigit())
                Text(row.metricLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
