import Foundation
import Testing

@testable import Catalog

/// Icon URL construction, ported from CaskHub. Pure string building — no
/// request is ever issued from this module.
@Suite("Cask icon URLs")
struct CaskIconURLTests {
    @Test("CaskFlow serves the CDN mirror first, then the raw branch")
    func caskFlowURLsInMirrorOrder() {
        #expect(CaskIconURL.caskFlowIconURLs(for: "iterm2").map(\.absoluteString) == [
            "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/iterm2.png",
            "https://raw.githubusercontent.com/alielsokary/CaskFlow/icons/iterm2.png"
        ])
    }

    @Test("App Fair hosts one icon per cask release tag")
    func appFairURL() {
        #expect(
            CaskIconURL.appFairIconURL(for: "iterm2")?.absoluteString
                == "https://github.com/App-Fair/appcasks/releases/download/cask-iterm2/AppIcon.png"
        )
    }

    @Test("A token in the icon manifest tries CaskFlow first, App Fair last")
    func knownTokenGetsTheFullLadder() {
        let urls = CaskIconURL.candidateURLs(for: "iterm2", isKnownToken: true)

        #expect(urls.map(\.absoluteString) == [
            "https://cdn.jsdelivr.net/gh/alielsokary/CaskFlow@icons/iterm2.png",
            "https://raw.githubusercontent.com/alielsokary/CaskFlow/icons/iterm2.png",
            "https://github.com/App-Fair/appcasks/releases/download/cask-iterm2/AppIcon.png"
        ])
    }

    @Test("A token outside the manifest skips CaskFlow — those URLs are guaranteed 404s")
    func unknownTokenSkipsCaskFlow() {
        let urls = CaskIconURL.candidateURLs(for: "obscure-app", isKnownToken: false)

        #expect(urls.map(\.absoluteString) == [
            "https://github.com/App-Fair/appcasks/releases/download/cask-obscure-app/AppIcon.png"
        ])
    }
}
