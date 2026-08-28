//
//  HealthRowView.swift
//  cellar
//

import BrewClient
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
    /// The doctor's grouped `Warning:` blocks, listed on demand. Every other
    /// row passes nothing; an empty list draws no disclosure at all.
    var warnings: [DoctorWarning] = []

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded, !warnings.isEmpty {
                DoctorWarningList(warnings: warnings)
                    .padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.15), value: isExpanded)
        // Every leaf keeps its own identifier (A9). Without this the row's stack
        // is merged into a single accessibility element and the per-signal
        // identifiers — which are how a UI test asks "does this row say why it
        // cannot answer" — disappear from the hierarchy entirely.
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
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
                if !warnings.isEmpty {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Label(
                            isExpanded
                                ? HealthCopy.hideDoctorWarnings
                                : HealthCopy.showDoctorWarnings(warnings.count),
                            systemImage: isExpanded ? "chevron.down" : "chevron.right"
                        )
                        .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.infoText)
                    .padding(.top, 4)
                    .accessibilityIdentifier("health-doctor-warnings-toggle")
                }
            }
            Spacer(minLength: 0)
            if let remediate, let title = HealthCopy.remediationTitle(row.remediation) {
                Button(title, action: remediate)
                    .buttonStyle(ActionPillStyle())
                    .disabled(!isRemediationEnabled)
                    .accessibilityIdentifier("health-remediate-\(row.input.rawValue)")
            }
        }
    }
}

/// The warnings verbatim: headline as the title, brew's own detail lines below
/// it in mono, indentation preserved because `DoctorWarning` preserves it.
private struct DoctorWarningList: View {
    let warnings: [DoctorWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Identity by position: brew can emit two identical warnings and
            // both must stay on screen.
            ForEach(Array(warnings.enumerated()), id: \.offset) { index, warning in
                VStack(alignment: .leading, spacing: 3) {
                    Text(warning.headline.isEmpty ? HealthCopy.untitledDoctorWarning : warning.headline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                    if !warning.detail.isEmpty {
                        Text(warning.detail.joined(separator: "\n"))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textFaint)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityIdentifier("health-doctor-warning-\(index)")
            }
        }
        .accessibilityIdentifier("health-doctor-warnings")
    }
}
