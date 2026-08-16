//
//  CaskPresentation.swift
//  cellar
//

import Foundation

/// The pure formatting behind the cask cards and the hero — kept off any actor
/// so `CaskPresentationTests` can assert every string without a view in sight.
nonisolated enum CaskPresentation {
    /// `1_100_000` → "1.1M", `29` → "29".
    ///
    /// Pinned to `en_US` on purpose: the K/M suffixes are part of the design's
    /// look, and a locale-following spelling would redraw every card's meta
    /// line by region.
    static func compactCount(_ count: Int) -> String {
        count.formatted(
            IntegerFormatStyle<Int>.number
                .notation(.compactName)
                .locale(Locale(identifier: "en_US"))
        )
    }

    /// The card's one meta line: "↓ 1.1M · v2.1.224", or the version alone
    /// when the analytics feed reported nothing — `nil` is *unreported*, which
    /// is not zero.
    static func cardMeta(installCount: Int?, version: String) -> String {
        guard let installCount else { return "v\(version)" }
        return "↓ \(compactCount(installCount)) · v\(version)"
    }

    /// The count a card shows under a page's selected analytics window: the
    /// override's number when one is threaded through, or the catalog's own
    /// annual count when the page passed none.
    ///
    /// A token absent from a non-nil override resolves to `nil` — version-only
    /// meta — never to the annual count, because labelling annual data as a
    /// shorter period would be a quiet lie on every card.
    static func resolvedInstallCount(
        installCount365d: Int?,
        token: String,
        counts: [String: Int]?
    ) -> Int? {
        guard let counts else { return installCount365d }
        return counts[token]
    }

    /// The hero's meta line: pours, version, category — each segment present
    /// only when its value is, so no separator ever dangles.
    static func heroMeta(installCount: Int?, version: String, categoryName: String?) -> String {
        var segments: [String] = []
        if let installCount {
            segments.append("\(compactCount(installCount)) pours")
        }
        segments.append("v\(version)")
        if let categoryName {
            segments.append(categoryName)
        }
        return segments.joined(separator: " · ")
    }
}
