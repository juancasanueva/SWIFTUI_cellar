//
//  CaskPresentationTests.swift
//  cellarTests
//

import Foundation
import Testing

@testable import cellar

/// The pure formatting the cask browse cards and hero render — asserted here so
/// a card never has to be screenshotted to prove a string.
@Suite("Cask presentation")
struct CaskPresentationTests {
    // MARK: - Compact counts

    /// Pinned to `en_US` so the K/M suffixes are the same on every machine the
    /// suite runs on; a locale-following format would make this test flake by
    /// region.
    @Test("A large count compacts with an en_US suffix")
    func aLargeCountCompactsWithAnEnUSSuffix() {
        #expect(CaskPresentation.compactCount(1_100_000) == "1.1M")
        #expect(CaskPresentation.compactCount(29_000) == "29K")
    }

    @Test("A small count stays literal")
    func aSmallCountStaysLiteral() {
        #expect(CaskPresentation.compactCount(29) == "29")
        #expect(CaskPresentation.compactCount(0) == "0")
    }

    // MARK: - The card's meta line

    @Test("A reported count renders beside the version")
    func aReportedCountRendersBesideTheVersion() {
        #expect(
            CaskPresentation.cardMeta(installCount: 1_100_000, version: "2.1.224")
                == "↓ 1.1M · v2.1.224"
        )
    }

    /// `installCount365d` is `nil` when the analytics feed did not report the
    /// cask at all — which is not zero, so the meta line says nothing about it.
    @Test("A nil count renders the version alone")
    func aNilCountRendersTheVersionAlone() {
        #expect(CaskPresentation.cardMeta(installCount: nil, version: "2.1.224") == "v2.1.224")
    }

    // MARK: - Per-period count overrides

    /// A page ranking by a shorter window threads that window's counts through;
    /// the card then shows the selected period's number, never the annual one.
    @Test("A counts override supplies the selected window's number")
    func aCountsOverrideSuppliesTheSelectedWindowsNumber() {
        let resolved = CaskPresentation.resolvedInstallCount(
            installCount365d: 1_100_000,
            token: "claude-code",
            counts: ["claude-code": 29_000]
        )
        #expect(resolved == 29_000)
        #expect(
            CaskPresentation.cardMeta(installCount: resolved, version: "2.1.224")
                == "↓ 29K · v2.1.224"
        )
    }

    /// "Never label annual data as a shorter period": a cask the selected
    /// window did not measure shows version-only, not the 365d count.
    @Test("A token absent from the override renders version-only, not the annual count")
    func anAbsentTokenRendersVersionOnly() {
        let resolved = CaskPresentation.resolvedInstallCount(
            installCount365d: 1_100_000,
            token: "claude-code",
            counts: ["someothercask": 5]
        )
        #expect(resolved == nil)
        #expect(CaskPresentation.cardMeta(installCount: resolved, version: "2.1.224") == "v2.1.224")
    }

    /// No override means the annual window: the catalog's own count stands.
    @Test("A nil override keeps the catalog's annual count")
    func aNilOverrideKeepsTheAnnualCount() {
        #expect(
            CaskPresentation.resolvedInstallCount(
                installCount365d: 1_100_000,
                token: "claude-code",
                counts: nil
            ) == 1_100_000
        )
        #expect(
            CaskPresentation.resolvedInstallCount(
                installCount365d: nil,
                token: "claude-code",
                counts: nil
            ) == nil
        )
    }

    // MARK: - The hero's meta line

    @Test("The hero meta carries pours, version, and category when all exist")
    func theHeroMetaCarriesAllThreeSegments() {
        #expect(
            CaskPresentation.heroMeta(
                installCount: 1_100_000,
                version: "2.1.224",
                categoryName: "Developer Tools"
            ) == "1.1M pours · v2.1.224 · Developer Tools"
        )
    }

    /// An unmapped token has no category rather than a default one, and the
    /// separator must not dangle behind the absence.
    @Test("The hero meta drops an absent category without a dangling separator")
    func theHeroMetaDropsAnAbsentCategory() {
        #expect(
            CaskPresentation.heroMeta(
                installCount: 1_100_000,
                version: "2.1.224",
                categoryName: nil
            ) == "1.1M pours · v2.1.224"
        )
        #expect(
            CaskPresentation.heroMeta(installCount: nil, version: "1.0", categoryName: nil)
                == "v1.0"
        )
    }
}
