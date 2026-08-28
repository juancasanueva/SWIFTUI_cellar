//
//  HealthCopy.swift
//  cellar
//

import Catalog
import Foundation

/// Every user-facing word the Health section says.
///
/// Named constants rather than body literals, on the `SecurityConsentSheet`
/// precedent, for one reason: this section's copy makes **claims** — about what a
/// number means, about what an action does, and about what Homebrew's own
/// warnings are worth — and a claim scattered across five view bodies cannot be
/// reviewed as a whole. `HealthCompositionTests` asserts that no Health view
/// renders a string literal of its own, so this file is provably the only place
/// the wording lives.
///
/// The rules that outlive any particular phrasing:
///
/// - The run-doctor copy states that it **re-measures** and contains none of
///   "fix", "repair" or "resolve" (`system-health`, "Doctor is a read, and
///   running it fixes nothing"). `brew doctor` has no fix mode; promising one
///   would be a lie the shipping app tells.
/// - The doctor row carries **Homebrew's own** de-emphasis rather than Cellar's
///   opinion of it, quoted from the manual the captured fixture's preamble
///   repeats.
/// - The score's caveat is never optional prose. It is rendered from the same
///   value as the number, so "72" and "one signal unanswered" cannot come apart.
nonisolated enum HealthCopy {

    // MARK: - The score

    static let sectionTitle = "Health"
    static let scoreTitle = "Health score"
    /// The design document's hero heading and ring caption.
    static let heroTitle = "System health"
    static let scoreRingCaption = "Score"
    static let quickActionsTitle = "Quick actions"
    /// The command shown beside the run-doctor chip, exactly as it would run.
    static let runDoctorCommand = "brew doctor"

    /// What a machine nothing was measured on gets instead of a number.
    ///
    /// Not `0` and not `100`: both read as verdicts, one catastrophic and one
    /// perfect, about something nobody looked at.
    static let nothingScored = "Nothing could be scored yet"

    static let nothingScoredDetail =
        "No signal has been answered on this Mac yet, so there is no number to show. "
        + "Each row below names what it is still waiting for."

    static let breakdownTitle = "How this number was reached"

    static let breakdownExplanation =
        "Every weight is shown so the number can be argued with. "
        + "Signals nobody could answer are left out of both sides of the division "
        + "and listed underneath instead."

    static let inputColumn = "Signal"
    static let weightColumn = "Weight"
    static let healthColumn = "Health"
    static let pointsColumn = "Points"

    /// The visible denominator: the summed weight of the signals that answered.
    static func answeredWeight(_ weight: Int) -> String {
        "Answered weight \(weight) of \(HealthWeights.total)"
    }

    static let unknownsTitle = "Not answered"

    /// The caveat that travels with the number whenever anything is unanswered —
    /// including a 100.
    static func scoreCaveat(unknownCount: Int) -> String {
        unknownCount == 1
            ? "1 signal is unanswered, so this number is not the whole picture."
            : "\(unknownCount) signals are unanswered, so this number is not the whole picture."
    }

    /// One line in the unknown list, naming the signal and why it could not
    /// answer.
    static func unknown(_ input: HealthInput, reason: HealthUnknownReason) -> String {
        "\(inputName(input)) — \(reasonName(reason))"
    }

    static func contribution(_ input: HealthInput, weight: Int, health: Double, points: Double) -> String {
        "\(inputName(input)) · \(weightColumn) \(weight) · \(healthColumn) \(percent(health)) · "
            + "\(pointsColumn) \(rounded(points))"
    }

    // MARK: - Naming the eight signals and the eleven gaps

    static func inputName(_ input: HealthInput) -> String {
        switch input {
        case .outdated: "Outdated packages"
        case .vulnerable: "Known vulnerabilities"
        case .advisoryCoverage: "Advisory coverage"
        case .lastUpdate: "Homebrew itself"
        case .orphans: "Orphaned dependencies"
        case .duplicateVersions: "Duplicate installed versions"
        case .cache: "Download cache"
        case .doctor: "Homebrew's own checks"
        }
    }

    /// Why a signal could not answer, in the user's words rather than the enum's.
    ///
    /// Every one of these is a state some capability genuinely produces, and every
    /// one of them reads like good news if it is rendered as a blank.
    static func reasonName(_ reason: HealthUnknownReason) -> String {
        switch reason {
        case .notCovered: "no package in the inventory is covered by an advisory source"
        case .unavailable: "the source could not be reached"
        case .partial: "only part of the inventory was answered"
        case .unmeasured: "not measured yet"
        case .failed: "the measurement failed"
        case .cancelled: "the measurement was cancelled"
        case .unknown: "Homebrew reported nothing to read"
        case .absent: "no fetch marker was found in the checkout"
        case .unreadable: "the fetch marker could not be read"
        case .futureDated: "the fetch marker is dated in the future"
        case .notRun: "doctor has not been run"
        }
    }

    // MARK: - The doctor row

    static let runDoctorTitle = "Run doctor"

    /// The claim, stated exactly once.
    ///
    /// Contains none of "fix", "repair" or "resolve", asserted by
    /// `HealthCompositionTests`. Read it as a promise the app can keep: brew is
    /// asked the question again and the answer is shown; nothing on this Mac
    /// changes either way.
    static let runDoctorExplanation =
        "Re-measures Homebrew's own checks and shows what it reports. "
        + "It changes nothing on this Mac: `brew doctor` only looks."

    /// Homebrew's framing, quoted rather than paraphrased.
    ///
    /// The captured 622-byte report opens with this sentence, and it is the reason
    /// this input carries the lowest weight in the score. Presenting these
    /// warnings as defects the user must clear overstates what Homebrew itself
    /// declines to claim.
    static let doctorDeEmphasis =
        "Homebrew describes these warnings as \"just used to help the Homebrew maintainers "
        + "with debugging\" a reported issue. Most working Macs have some. They are weighted "
        + "lightly here for exactly that reason."

    static func showDoctorWarnings(_ count: Int) -> String {
        count == 1 ? "Show warning" : "Show \(count) warnings"
    }

    static let hideDoctorWarnings = "Hide warnings"

    /// A `Warning:` line brew left empty; the block is still listed.
    static let untitledDoctorWarning = "Warning without a headline"

    // MARK: - The rows

    static let rowsTitle = "Signals"
    static let readLastUpdateTitle = "Re-read Homebrew's age"

    static func remediationTitle(_ remediation: HealthRemediation) -> String? {
        switch remediation {
        case .upgradeAll: "Upgrade all"
        case .autoremove: "Remove orphans"
        case .cleanupCache: "Clean up"
        case .runDoctor: runDoctorTitle
        case .none: nil
        }
    }

    // MARK: - The measured summaries

    static func outdatedSummary(outdated: Int, installed: Int) -> String {
        "\(outdated) of \(installed) packages are behind"
    }

    static func vulnerableSummary(vulnerable: Int, answered: Int, unanswered: Int) -> String {
        unanswered > 0
            ? "\(vulnerable) vulnerable of \(answered) answered · \(unanswered) unanswered"
            : "\(vulnerable) vulnerable of \(answered) answered"
    }

    static func coverageSummary(answered: Int, total: Int) -> String {
        "\(answered) of \(total) packages answered"
    }

    static func orphansSummary(count: Int) -> String {
        count == 1 ? "1 orphaned dependency" : "\(count) orphaned dependencies"
    }

    static func duplicateVersionsSummary(count: Int, incomplete: Bool) -> String {
        let base = count == 1 ? "1 extra installed version" : "\(count) extra installed versions"
        return incomplete ? "\(base) · the measurement is incomplete" : base
    }

    static func cacheSummary(bytes: Int64, reclaimable: Int64?, incomplete: Bool) -> String {
        var parts = [byteCount(bytes)]
        if let reclaimable { parts.append("\(byteCount(reclaimable)) reclaimable") }
        if incomplete { parts.append("the measurement is incomplete") }
        return parts.joined(separator: " · ")
    }

    static func lastUpdateSummary(days: Int) -> String {
        switch days {
        case ..<1: "Updated today"
        case 1: "Updated 1 day ago"
        default: "Updated \(days) days ago"
        }
    }

    static func doctorSummary(warnings: Int, partial: Bool) -> String {
        let base = warnings == 1 ? "1 warning" : "\(warnings) warnings"
        return partial ? "\(base) · part of the report was not recognised" : base
    }

    // MARK: - Formatting

    static func byteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func percent(_ health: Double) -> String {
        "\(Int((health * 100).rounded()))%"
    }

    static func rounded(_ points: Double) -> String {
        String(format: "%.1f", points)
    }
}
