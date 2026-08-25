import Foundation

/// Icon URL construction for cask artwork, ported from CaskHub.
///
/// Pure string building: this module never issues the requests. The app layer
/// decides when — and whether — to fetch.
public enum CaskIconURL {
    /// The CaskFlow icon for a token: the jsDelivr CDN mirror first, then the
    /// raw GitHub branch as its fallback.
    public static func caskFlowIconURLs(for token: String) -> [URL] {
        [
            URL(string: "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/\(token).png"),
            URL(string: "https://raw.githubusercontent.com/alielsokary/CaskFlow/icons/\(token).png")
        ].compactMap { $0 }
    }

    /// The App-Fair appcasks icon, published one release tag per cask.
    public static func appFairIconURL(for token: String) -> URL? {
        URL(string: "https://github.com/App-Fair/appcasks/releases/download/cask-\(token)/AppIcon.png")
    }

    /// Every URL worth trying, in order.
    ///
    /// `isPublishedByHomebrew` is the origin gate: CaskFlow and App-Fair both
    /// index `homebrew/cask` and nothing else, so a cask a third-party tap
    /// publishes has no rung anywhere — every URL would be a guaranteed 404
    /// that hands the tap's token to GitHub for nothing. The ladder is empty.
    ///
    /// `isKnownToken` is the manifest gate — `CaskCategoryCatalog.iconTokens`
    /// membership. A token outside the manifest has no CaskFlow icon, so those
    /// URLs would be guaranteed 404s and are skipped; App-Fair is the last
    /// resort for a `homebrew/cask` cask.
    public static func candidateURLs(
        for token: String,
        isKnownToken: Bool,
        isPublishedByHomebrew: Bool
    ) -> [URL] {
        guard isPublishedByHomebrew else { return [] }
        var urls = isKnownToken ? caskFlowIconURLs(for: token) : []
        if let appFair = appFairIconURL(for: token) {
            urls.append(appFair)
        }
        return urls
    }
}
