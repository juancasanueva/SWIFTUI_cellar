//
//  HomeCompositionTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import DiskUsage
import Foundation
import Testing

@testable import cellar

/// When the Home page may claim Homebrew itself needs updating.
///
/// The projection is pure over its inputs, so every claim here runs without a
/// window: version disagreement between what the local brew offers and what the
/// synced catalog publishes is the evidence, and the fetch-marker age is only a
/// fallback for when no package can be compared at all.
@Suite("Homebrew update need")
struct HomebrewUpdateNeedTests {
    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let day = HealthThresholds.lastUpdateFreshSeconds

    /// One comparable formula whose offered version differs from the catalog's.
    @Test("A formula the catalog knows a different version for shows the card")
    func aDisagreeingFormulaShowsTheCard() {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [HealthFixtures.package("go", offering: "1.26.6")],
            catalogVersion: { _ in "1.27.0" },
            lastUpdate: .read(Self.now),
            now: Self.now
        )
        #expect(behind)
    }

    @Test("Agreement across every comparable package hides the card, whatever the marker says")
    func agreementHidesTheCard() {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [
                HealthFixtures.package("go", offering: "1.27.0"),
                HealthFixtures.package("iterm2", kind: .cask, offering: "3.5.0"),
            ],
            catalogVersion: { $0.kind == .formula ? "1.27.0" : "3.5.0" },
            // The marker is ancient, and it must not matter: the primary
            // signal answered.
            lastUpdate: .read(Self.now.addingTimeInterval(-30 * Self.day)),
            now: Self.now
        )
        #expect(behind == false)
    }

    /// A self-updating cask legitimately runs ahead of both catalogs.
    @Test("A self-updating cask's disagreement alone never shows the card")
    func aSelfUpdatingCaskAloneNeverShowsTheCard() {
        var cask = HealthFixtures.package("raycast", kind: .cask, offering: "1.0.0")
        cask = InstalledPackage(
            kind: cask.kind,
            name: cask.name,
            displayName: cask.displayName,
            desc: cask.desc,
            homepage: cask.homepage,
            tap: cask.tap,
            catalogVersion: cask.catalogVersion,
            kegs: cask.kegs,
            primaryKeg: cask.primaryKeg,
            snapshotOutdated: cask.snapshotOutdated,
            isPinned: cask.isPinned,
            pinnedVersion: cask.pinnedVersion,
            declaresAutoUpdates: true
        )
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [cask],
            catalogVersion: { _ in "2.0.0" },
            lastUpdate: .read(Self.now),
            now: Self.now
        )
        #expect(behind == false)
    }

    @Test("With no catalog answer, a stale fetch marker shows the card")
    func noCatalogAndAStaleMarkerShowsTheCard() {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [HealthFixtures.package("go", offering: "1.26.6")],
            catalogVersion: { _ in nil },
            lastUpdate: .read(Self.now.addingTimeInterval(-2 * Self.day)),
            now: Self.now
        )
        #expect(behind)
    }

    @Test("With no catalog answer, a fresh fetch marker hides the card")
    func noCatalogAndAFreshMarkerHidesTheCard() {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [HealthFixtures.package("go", offering: "1.26.6")],
            catalogVersion: { _ in nil },
            lastUpdate: .read(Self.now.addingTimeInterval(-Self.day / 2)),
            now: Self.now
        )
        #expect(behind == false)
    }

    /// A non-answer is not evidence: absent, unreadable, future-dated and
    /// never-read all keep the card away rather than crying wolf.
    @Test(
        "A marker that answers nothing never shows the card",
        arguments: [
            HomebrewLastUpdate.absent,
            .unreadable,
            .futureDated(Date(timeIntervalSince1970: 1_800_000_000)),
            nil,
        ]
    )
    func aNonAnswerNeverShowsTheCard(reading: HomebrewLastUpdate?) {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [HealthFixtures.package("go", offering: "1.26.6")],
            catalogVersion: { _ in nil },
            lastUpdate: reading,
            now: Self.now
        )
        #expect(behind == false)
    }
}

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

    /// The card appears on evidence, not unconditionally — and an update the
    /// user just started must not sweep its own card out from under the cursor.
    @Test("The card is gated by the staleness projection and survives its own operation")
    func theCardIsGatedByTheProjectionAndSurvivesItsOwnOperation() throws {
        let maintenance = try #require(
            Self.body(of: "private var maintenance: [AttentionItem]", in: try Self.homeSource()),
            "the maintenance projection is missing"
        )
        #expect(
            maintenance.contains("HomebrewUpdateNeed.isBehind"),
            "the card is not gated by the tested projection"
        )
        #expect(
            maintenance.contains("operations.isHomebrewUpdateInFlight"),
            "an in-flight update no longer holds its own card on screen"
        )
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
