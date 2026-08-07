//
//  HealthBreakdownPanel.swift
//  cellar
//

import Catalog
import SwiftUI

/// The weights table — the surface that makes the number arguable.
///
/// A score nobody can take apart is authoritative by accident, because the only
/// available response to it is to believe it or ignore it. Every weight, every
/// normalised health and every resulting point value is rendered here, together
/// with the visible denominator and the list of signals that were left out of
/// both sides of the division.
///
/// It renders a `HealthScorePresentation`, which is built from one
/// `HealthScoreState` and carries the caveat with the figure — so this panel
/// could not drop the caveat even if it tried.
struct HealthBreakdownPanel: View {
    let health: HealthStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(HealthCopy.breakdownTitle)
                    .font(.title3)
                Text(HealthCopy.breakdownExplanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let presentation {
                    contributions(presentation)
                    unknowns(presentation)
                } else {
                    Text(HealthCopy.nothingScoredDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("health-breakdown")
    }

    private var presentation: HealthScorePresentation? {
        health.content.map { HealthScorePresentation($0.score) }
    }

    @ViewBuilder
    private func contributions(_ presentation: HealthScorePresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let answeredWeight = presentation.answeredWeight {
                Text(answeredWeight)
                    .font(.headline)
                    .accessibilityIdentifier("health-answered-weight")
            }
            ForEach(presentation.contributions, id: \.self) { line in
                Text(line)
                    .font(.callout)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func unknowns(_ presentation: HealthScorePresentation) -> some View {
        if presentation.unknowns.isEmpty == false {
            VStack(alignment: .leading, spacing: 6) {
                Text(HealthCopy.unknownsTitle)
                    .font(.headline)
                ForEach(presentation.unknowns, id: \.self) { line in
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("health-unknowns")
        }
    }
}
