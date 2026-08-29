//
//  HomeAttentionCopy.swift
//  cellar
//

import BrewClient
import Foundation

/// The Home page's two sentences about how current this Mac is.
///
/// Extracted from `HomeView.body` for the reason the npm slice made unavoidable:
/// both were literals built inside a view, and both were wrong in the same way
/// once a third source existed. The subtitle counted formulae and called
/// everything else a cask; the greeting claimed "everything on this Mac is
/// current" from an empty attention list, which an unreachable npm registry
/// makes false — and that is the one claim a user acts on by doing nothing
/// (`installed-inventory`: an unchecked npm never reads as up to date).
///
/// `nonisolated` and pure over its arguments, exactly like `HealthCopy`: these
/// are assertable without standing up a window, which is what a sentence
/// carrying a claim about the machine has to be.
nonisolated enum HomeAttentionCopy {
    /// The greeting's second line.
    ///
    /// With npm off, or with npm's check completed, this is byte-for-byte the
    /// sentence the page has always shown. The hedged wording appears only when
    /// there genuinely is an npm half nobody managed to check, and it names both
    /// what *is* known and why the rest is not.
    static func sentence(
        attentionCount: Int,
        hasHomebrew: Bool,
        updates: InstalledUpdatesSummary
    ) -> String {
        guard hasHomebrew else { return noHomebrew }

        let lead: String? = switch attentionCount {
        case 0: nil
        case 1: "One thing wants your attention today."
        default: "\(number(attentionCount)) things want your attention today."
        }

        // `npmNotCheckedCopy` is absent when npm answered *and* when the source
        // is off, so both of those keep the shipped claim.
        let currency: String
        if let npmCue = updates.npmNotCheckedCopy {
            currency = (attentionCount == 0
                ? "Everything Homebrew reported is current"
                : "Everything else Homebrew reported is current")
                + " · " + npmCue
        } else {
            currency = attentionCount == 0
                ? "Everything on this Mac is current."
                : "Everything else on this Mac is current."
        }

        return [lead, currency].compactMap(\.self).joined(separator: " ")
    }

    static let noHomebrew = "Cellar is a window onto the brew already on your Mac."

    /// The outdated card's headline, over the merged count.
    static func outdatedTitle(count: Int) -> String {
        count == 1 ? "1 package has an update" : "\(count) packages have updates"
    }

    /// The outdated card's subtitle: what the updates *are*, and npm's
    /// disclosure when there is one.
    static func outdatedSubtitle(
        breakdown: OutdatedKindBreakdown,
        updates: InstalledUpdatesSummary
    ) -> String {
        [breakdown.summary, updates.npmNotCheckedCopy]
            .compactMap(\.self)
            .filter { $0.isEmpty == false }
            .joined(separator: " · ")
    }

    /// Two, Three, Four — and the numeral past the words the shipped sentence
    /// had.
    private static func number(_ count: Int) -> String {
        let words = ["Two", "Three", "Four"]
        guard count >= 2, count - 2 < words.count else { return "\(count)" }
        return words[count - 2]
    }
}
