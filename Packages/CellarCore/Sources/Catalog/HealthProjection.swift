import Foundation

/// One dashboard row.
///
/// The shape is what enforces the rule. `summary` is `nil` whenever the signal
/// was not answered, so a row **cannot** render a count for a signal nobody could
/// answer for: there is no value there to render. And `unknownReason` names the
/// gap, so "could not answer" is never a blank.
///
/// Both can be non-`nil` at once. That is a partially answered signal reporting
/// both halves — what it found, and what it could not reach.
public struct HealthRow: Sendable, Hashable {
    public let input: HealthInput
    public let title: String
    /// What was measured, when something was. `nil` for every unanswered signal.
    public let summary: String?
    /// The named reason for whatever this row could not answer. Non-`nil` for an
    /// unanswered signal, and for the unanswered half of a partial one.
    public let unknownReason: HealthUnknownReason?
    /// A verb another capability already ships, or `.none`. A row with nothing
    /// to offer offers a case rather than a disabled control.
    public let remediation: HealthRemediation

    public var isAnswered: Bool { summary != nil }
    /// Answered, and still carrying a named gap.
    public var isPartiallyAnswered: Bool { summary != nil && unknownReason != nil }
}

/// Everything the Health section renders.
///
/// `score` is a `HealthScoreState`, so the number and its unknown set are read
/// off **one value**. There is no `scoreValue` beside it and no accessor
/// returning the number on its own: a surface cannot render the figure while
/// dropping the caveat, because there is no way to obtain one without the other.
public struct HealthContent: Sendable, Hashable {
    public let rows: [HealthRow]
    public let score: HealthScoreState
    /// The moment the caller said it was. A stamp, not a clock read — nothing in
    /// the rules depends on it.
    public let generatedAt: Date
}

/// Builds the Health section's content from values the app already holds.
///
/// **Rendering acquires nothing.** No subprocess, no catalog sync, no security
/// scan, no disk-usage measurement, no inventory refresh, and no timer or polling
/// loop. That is not enforced by discipline: the signature takes one value and a
/// date, so there is no seam in scope to trigger. A health dashboard that
/// re-measures because you looked at it is a background job with a window
/// attached, and this capability owns exactly two acquisitions — the doctor run
/// and the last-update reading — both explicitly initiated elsewhere.
///
/// A signal that has not been measured is projected as unmeasured. It is never
/// substituted with a computed default, and asking for it never obtains it.
///
/// Pure, in the `DiscoverProjection` idiom, so all of the above is testable with
/// no store, no clock and no process.
public enum HealthProjection {
    /// One row per input.
    ///
    /// `advisoryCoverage` sits directly under the vulnerabilities it qualifies.
    /// It carries 15 points of the score, and a weighted signal with no row of
    /// its own is a number the user cannot explain from the screen.
    static let rowOrder: [HealthInput] = [
        .outdated, .vulnerable, .advisoryCoverage, .orphans, .duplicateVersions, .cache, .lastUpdate, .doctor
    ]

    /// Titles as named constants rather than body literals, so the copy is
    /// reviewable in one place.
    static func title(for input: HealthInput) -> String {
        switch input {
        case .outdated: "Outdated packages"
        case .vulnerable: "Known vulnerabilities"
        case .orphans: "Orphaned dependencies"
        case .duplicateVersions: "Duplicate installed versions"
        case .cache: "Download cache"
        case .lastUpdate: "Homebrew itself"
        case .doctor: "Homebrew's own checks"
        case .advisoryCoverage: "Advisory coverage"
        }
    }

    /// The verb each row may offer, and only ever one another capability ships.
    ///
    /// `vulnerable` and `lastUpdate` offer `.none` deliberately: Cellar has no
    /// verb that fixes a CVE, and `brew update` is a `.mutate` PRD §3.4 does not
    /// list among this dashboard's actions. `duplicateVersions` reclaims its disk
    /// through the shipped cleanup verb rather than a new one.
    static func remediation(for input: HealthInput) -> HealthRemediation {
        switch input {
        case .outdated: .upgradeAll
        case .orphans: .autoremove
        case .cache, .duplicateVersions: .cleanupCache
        case .doctor: .runDoctor
        case .vulnerable, .lastUpdate, .advisoryCoverage: .none
        }
    }

    /// Builds the content off the caller's executor.
    ///
    /// `@concurrent` rather than a plain `nonisolated func`, mirroring
    /// `DiscoverContent.build` and `PackageSearchIndex.build` (M1 D2): a
    /// synchronous nonisolated call from the main actor still runs *on* it. The
    /// built value crosses back with no lock — `HealthContent` is `Sendable` by
    /// composition.
    @concurrent
    public static func build(inputs: HealthInputs, now: Date) async -> HealthContent {
        let rows = rowOrder.map { input -> HealthRow in
            let measurement = inputs.measurement(for: input)
            return HealthRow(
                input: input,
                title: title(for: input),
                summary: measurement?.summary,
                unknownReason: measurement?.unanswered ?? inputs[input].unknownReason,
                remediation: remediation(for: input)
            )
        }

        return HealthContent(
            rows: rows,
            score: HealthScoring.score(inputs),
            generatedAt: now
        )
    }
}
