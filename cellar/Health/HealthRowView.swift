//
//  HealthRowView.swift
//  cellar
//

import Catalog
import SwiftUI

/// One signal, and what it could not answer about itself.
///
/// The shape of `HealthRow` is what makes the rule renderable: `summary` is `nil`
/// for every unanswered signal, so there is no number here to accidentally show
/// as a zero. Both halves can be present at once — that is a partially answered
/// signal reporting what it found *and* what it could not reach, which
/// `system-health` requires and which a single "value or reason" field could not
/// express.
///
/// Every word comes from `HealthCopy`; this view owns only the layout and the
/// identifiers.
struct HealthRowView: View {
    let row: HealthRow
    /// `nil` when the row's remediation is `.none`, which is a case rather than a
    /// disabled control: an inert button is the failure mode the requirement
    /// names by name.
    let remediate: (() -> Void)?
    let isRemediationEnabled: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.headline)
                    .accessibilityIdentifier("health-row-\(row.input.rawValue)")
                if let summary = row.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("health-summary-\(row.input.rawValue)")
                }
                if let reason = row.unknownReason {
                    Text(HealthCopy.reasonName(reason))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("health-unknown-\(row.input.rawValue)")
                }
                if row.input == .doctor {
                    Text(HealthCopy.doctorDeEmphasis)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityIdentifier("health-doctor-de-emphasis")
                }
            }
            Spacer(minLength: 0)
            if let remediate, let title = HealthCopy.remediationTitle(row.remediation) {
                Button(title, action: remediate)
                    .buttonStyle(.borderless)
                    .disabled(!isRemediationEnabled)
                    .accessibilityIdentifier("health-remediate-\(row.input.rawValue)")
            }
        }
        .padding(.vertical, 4)
        // Every leaf keeps its own identifier (A9). Without this the row's stack
        // is merged into a single accessibility element and the per-signal
        // identifiers — which are how a UI test asks "does this row say why it
        // cannot answer" — disappear from the hierarchy entirely.
        .accessibilityElement(children: .contain)
    }
}
