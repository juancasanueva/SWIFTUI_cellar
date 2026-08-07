//
//  HealthScorePresentation.swift
//  cellar
//

import Catalog
import Foundation

/// Everything the score renders, built from **one** value.
///
/// The requirement is that the number is unrepresentable without its unknowns
/// (`system-health`, "The score is computed over answered inputs only, and its
/// unknowns are inseparable from it"). `HealthScore` enforces that inside
/// `Catalog` by making its memberwise initialiser `fileprivate`; this type is
/// where the same rule has to survive the trip into a view.
///
/// So: one initialiser, taking one `HealthScoreState`. There is no second way to
/// build a presentation, no `init(value:)`, and no accessor that returns the
/// number on its own — which means there is no arrangement of view code that can
/// render "100" while dropping "one signal unanswered". Rendering the number
/// requires holding the whole thing.
///
/// `.unscorable` renders `HealthCopy.nothingScored` rather than a figure. A `0`
/// and a `100` are both verdicts, and neither is one anybody earned on a machine
/// nothing was measured on.
nonisolated struct HealthScorePresentation: Sendable, Hashable {
    /// The number, as text — or the sentence that replaces it when there is none.
    let headline: String
    /// `nil` only when every signal answered.
    let caveat: String?
    /// One line per answered input: its name, its weight, its health and its
    /// points.
    let contributions: [String]
    /// One line per unanswered input, each naming its own reason.
    let unknowns: [String]
    /// The visible denominator, or `nil` when there is no number to divide.
    let answeredWeight: String?

    init(_ state: HealthScoreState) {
        switch state {
        case .scored(let score):
            headline = String(score.value)
            caveat = score.isComplete ? nil : HealthCopy.scoreCaveat(unknownCount: score.unknownInputs.count)
            contributions = score.contributions.map {
                HealthCopy.contribution($0.input, weight: $0.weight, health: $0.health, points: $0.points)
            }
            unknowns = score.unknownInputs.map { HealthCopy.unknown($0.input, reason: $0.reason) }
            answeredWeight = HealthCopy.answeredWeight(score.answeredWeight)

        case .unscorable(let unknownInputs):
            headline = HealthCopy.nothingScored
            caveat = HealthCopy.nothingScoredDetail
            contributions = []
            unknowns = unknownInputs.map { HealthCopy.unknown($0.input, reason: $0.reason) }
            answeredWeight = nil
        }
    }

    /// Whether a figure is being shown at all, for the surface that has to choose
    /// a font size.
    var isScored: Bool { answeredWeight != nil }
}
