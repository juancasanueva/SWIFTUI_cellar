//
//  HomeCompositionTests.swift
//  cellarTests
//

import Foundation
import Testing

/// What the Home section's card stack is wired to, read off the source the way
/// `BrewfilePlacementTests` reads the Taps list.
///
/// Textual by necessity: the cards are `private` values built inside `body`'s
/// projections, so there is no way to observe them from a test without standing
/// up a window — and the claims here are about *wiring*, not rendering.
@Suite("Home composition")
struct HomeCompositionTests {

    /// The Update Homebrew card exists, submits through the one mutation spine,
    /// and reads its whole eligibility off the centre's own projections.
    @Test("The Update Homebrew card submits .update and reads the centre's projections")
    func theUpdateHomebrewCardSubmitsThroughTheSpine() throws {
        let home = try Self.homeSource()

        // The card's stable identity; `AttentionCard` derives the
        // `home-attention-homebrew-update` accessibility identifier from it.
        #expect(home.contains("\"homebrew-update\""))
        #expect(home.contains("operations.submit(.update)"))
        #expect(
            home.contains("operations.isAvailable && !operations.isHomebrewUpdateInFlight"),
            "the card's eligibility is not the centre's availability and in-flight pair"
        )
        #expect(home.contains("\"Update Homebrew\""))
    }

    /// The card is maintenance, not attention: it must not inflate the
    /// "N things want your attention today" sentence, which counts `attention`
    /// and nothing else.
    @Test("The Update Homebrew card is not counted as a thing wanting attention")
    func theUpdateHomebrewCardIsNotAnAttentionItem() throws {
        let home = try Self.homeSource()

        let attention = try #require(
            Self.body(of: "private var attention: [AttentionItem]", in: home),
            "HomeView no longer declares the attention projection this claim is about"
        )
        #expect(
            attention.contains("homebrew-update") == false,
            "the maintenance card entered the attention count"
        )

        let maintenance = try #require(
            Self.body(of: "private var maintenance: [AttentionItem]", in: home),
            "the maintenance projection is missing"
        )
        #expect(maintenance.contains("homebrew-update"))
    }

    // MARK: - Reading

    private static func homeSource() throws -> String {
        let source = try #require(
            try AppSecuritySources.load().first { $0.name == "HomeView.swift" },
            "HomeView.swift was not found in the app target"
        )
        return source.code
    }

    /// The brace-balanced body following `declaration`, or `nil` when absent.
    private static func body(of declaration: String, in source: String) -> String? {
        guard let start = source.range(of: declaration) else { return nil }
        guard let open = source[start.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var index = open
        while index < source.endIndex {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return String(source[open...index]) }
            }
            index = source.index(after: index)
        }
        return nil
    }
}
