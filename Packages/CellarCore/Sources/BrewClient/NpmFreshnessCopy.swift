import Catalog
import Foundation

/// The words for npm's three freshness states, and the one sentence they forbid.
///
/// Copy in `BrewClient` rather than beside each surface, for the reason the
/// unavailable-reason sentences already live here: three surfaces — the menu
/// bar, Health and Home — have to turn one tri-state into words, and three
/// independent authors of that sentence is exactly how "up to date" ends up over
/// an offline machine. Here it is assertable without rendering anything, and a
/// fourth state cannot be added without someone writing its sentence.
///
/// Every sentence names **npm**. A `notChecked` on the npm half worded in
/// Homebrew's vocabulary would send a user to fix the wrong thing.
extension NpmOutdatedState {
    /// The three words every surface can look for, and the prefix of every
    /// sentence below.
    public static let notCheckedHeadline = "npm not checked"

    /// What to say when npm has no answer, and `nil` when it has one.
    ///
    /// Absent on `fresh` because the count already says everything there is to
    /// say: a cue beside a number that is simply correct is noise.
    public var notCheckedCopy: String? {
        switch self {
        case .fresh:
            nil
        case .notChecked(.notYetChecked):
            Self.notCheckedHeadline + " yet"
        case .notChecked(.cancelled):
            Self.notCheckedHeadline + " · the check was cancelled"
        case .failed(let error):
            Self.notCheckedHeadline + " · " + error.notCheckedReason
        }
    }
}

extension NpmInventoryError {
    /// Why the check produced no answer, in a user's words rather than the
    /// enum's.
    ///
    /// Never the subprocess's own bytes: `commandFailed` carries a verbatim
    /// stderr tail, which belongs in a log rather than in a summary line. The
    /// network case names the network *and* the registry, because "npm failed"
    /// leaves a user with nothing to check and "no connection" is something they
    /// can act on.
    var notCheckedReason: String {
        switch self {
        case .npmUnavailable: "npm could not be run"
        case .commandFailed: "npm could not complete the check"
        case .malformedPayload: "npm's report could not be read"
        case .networkUnavailable: "the registry could not be reached over the network"
        case .cancelled: "the check was cancelled"
        }
    }
}

/// What a set of outdated identities *is*, by kind.
///
/// A projection rather than three `filter`s at the call site, because the call
/// site that had them counted formulae and then called **everything else** a
/// cask — which was correct exactly as long as there were only two kinds. An npm
/// global silently became a cask the day a third arrived, on a surface where
/// nothing would have looked wrong.
///
/// Pure over the ids and nothing else. It derives no outdated-ness of its own:
/// the set it is handed is always the snooze-aware projection's.
public struct OutdatedKindBreakdown: Sendable, Equatable {
    public let formulae: Int
    public let casks: Int
    public let npm: Int

    public init(ids: some Sequence<PackageID>) {
        var formulae = 0
        var casks = 0
        var npm = 0
        // An explicit arm per kind, and no `default:`: a fourth kind must break
        // this rather than quietly join one of the three.
        for id in ids {
            switch id.kind {
            case .formula: formulae += 1
            case .cask: casks += 1
            case .npm: npm += 1
            }
        }
        self.formulae = formulae
        self.casks = casks
        self.npm = npm
    }

    public var total: Int { formulae + casks + npm }

    /// "1 formula · 2 casks · 3 npm packages", with every empty clause
    /// **absent** rather than rendered as a zero.
    public var summary: String {
        [
            formulae > 0 ? "\(formulae) formula\(formulae == 1 ? "" : "e")" : nil,
            casks > 0 ? "\(casks) cask\(casks == 1 ? "" : "s")" : nil,
            npm > 0 ? "\(npm) npm package\(npm == 1 ? "" : "s")" : nil,
        ]
            .compactMap(\.self)
            .joined(separator: " · ")
    }
}

extension InstalledUpdatesSummary {
    /// The sentence a surface may show when there is genuinely nothing to do.
    ///
    /// A named constant rather than a literal per surface, so the menu bar, Home
    /// and Health cannot drift into three different claims about the same state.
    public static let upToDateLabel = "Everything is up to date"

    /// The npm half's disclosure, absent when npm answered — and absent when the
    /// source is off, because there is then no npm half to disclose anything
    /// about.
    public var npmNotCheckedCopy: String? { npm?.freshness.notCheckedCopy }

    /// What an upgrade-all does **not** cover.
    ///
    /// Both surfaces that offer that button — the menu-bar popover and the
    /// Health outdated row — submit bare `brew upgrade`, which fans out to
    /// nothing and touches no npm package. One constant rather than two
    /// sentences, so the two surfaces cannot describe the same gap two ways.
    public static let npmUpgradeScopeNote = "npm packages update from the Updates list"

    /// The note above, present exactly when there is an npm package it explains
    /// and absent otherwise — including on every machine with the source off.
    public var npmUpgradeScopeCopy: String? {
        guard let npm, npm.count > 0 else { return nil }
        return Self.npmUpgradeScopeNote
    }

    /// The up-to-date sentence, **absent** whenever it may not be said.
    ///
    /// The absence is the value. A surface reads this rather than testing a
    /// count against zero, which is what makes "an unchecked npm never reads as
    /// up to date" structural: there is no zero for a view to misread, because
    /// `isUpToDate` already requires npm's check to have completed.
    public var upToDateCopy: String? { isUpToDate ? Self.upToDateLabel : nil }
}
