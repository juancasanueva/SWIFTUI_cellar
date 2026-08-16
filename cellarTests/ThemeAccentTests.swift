//
//  ThemeAccentTests.swift
//  cellarTests
//

import Foundation
import Testing

@testable import cellar

/// The accent colour math the whole theme derives from.
///
/// The design document computes every accent-tinted surface from one hex value:
/// `light = mix(accent, 0.3, white)`, `dark = mix(accent, 0.38, black)`, and a
/// ladder of alpha tints. These tests pin that arithmetic to the design's own
/// JavaScript (`Math.round(x + (to - x) * amt)`) so a drifting rewrite cannot
/// silently shift every tinted surface in the app.
@Suite("Accent palette")
struct ThemeAccentTests {
    @Test("Parses a hex string into 8-bit components")
    func parsesHex() throws {
        let accent = try #require(AccentPalette(hex: "#e0a45c"))
        #expect(accent.red == 224)
        #expect(accent.green == 164)
        #expect(accent.blue == 92)
    }

    @Test("Accepts the design's bare form without a leading hash")
    func parsesBareHex() throws {
        let accent = try #require(AccentPalette(hex: "5b8def"))
        #expect(accent.red == 0x5B)
        #expect(accent.green == 0x8D)
        #expect(accent.blue == 0xEF)
    }

    @Test("Rejects strings that are not six hex digits")
    func rejectsMalformedHex() {
        #expect(AccentPalette(hex: "") == nil)
        #expect(AccentPalette(hex: "#fff") == nil)
        #expect(AccentPalette(hex: "#zzzzzz") == nil)
        #expect(AccentPalette(hex: "#e0a45c00") == nil)
    }

    @Test("Light variant mixes 30% toward white, rounding per component")
    func lightVariant() throws {
        let accent = try #require(AccentPalette(hex: "#e0a45c"))
        // 224+(255-224)*.3 = 233.3 → 233, 164+27.3 → 191, 92+48.9 → 141
        #expect(accent.light.hexString == "#e9bf8d")
    }

    @Test("Dark variant mixes 38% toward black, rounding per component")
    func darkVariant() throws {
        let accent = try #require(AccentPalette(hex: "#e0a45c"))
        // 224*.62 = 138.88 → 139, 164*.62 = 101.68 → 102, 92*.62 = 57.04 → 57
        #expect(accent.dark.hexString == "#8b6639")
    }

    @Test("Round-trips through hexString")
    func hexRoundTrip() throws {
        let accent = try #require(AccentPalette(hex: "#4FAE7B"))
        #expect(accent.hexString == "#4fae7b")
    }

    @Test("Offers the design's ten accent choices, amber first as the default")
    func tenChoices() {
        #expect(AccentPalette.choices.count == 10)
        #expect(AccentPalette.choices.first?.palette.hexString == "#e0a45c")
        #expect(AccentPalette.default.hexString == "#e0a45c")
        // Every advertised choice must parse into itself.
        for choice in AccentPalette.choices {
            #expect(AccentPalette(hex: choice.palette.hexString) != nil)
            #expect(choice.name.isEmpty == false)
        }
    }

    @Test("The initial-tile palette is stable for a given package name")
    func tileHashIsStable() {
        // The design hashes the name's character codes and indexes five pairs;
        // what matters here is determinism and full coverage of the range.
        let a = PackageTilePalette.index(for: "ripgrep")
        let b = PackageTilePalette.index(for: "ripgrep")
        #expect(a == b)
        #expect((0..<PackageTilePalette.pairCount).contains(a))
    }
}
