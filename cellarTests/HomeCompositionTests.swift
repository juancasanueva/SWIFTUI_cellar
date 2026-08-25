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
    @Test("A core formula the catalog knows a different version for shows the card")
    func aDisagreeingFormulaShowsTheCard() {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [HealthFixtures.package("go", offering: "1.26.6")],
            catalogVersion: { _ in "1.27.0" },
            catalogDownloadedAt: Self.now,
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
                HealthFixtures.package("iterm2", kind: .cask, offering: "3.5.0", tap: "homebrew/cask"),
            ],
            catalogVersion: { $0.kind == .formula ? "1.27.0" : "3.5.0" },
            catalogDownloadedAt: Self.now,
            // The marker is ancient, and it must not matter: the primary
            // signal answered.
            lastUpdate: .read(Self.now.addingTimeInterval(-30 * Self.day)),
            now: Self.now
        )
        #expect(behind == false)
    }

    /// The live collision: `hunk` from modem-dev/tap versus homebrew/core's own
    /// `hunk`. `brew update` can never reconcile a tap's version with core's,
    /// so a tap package must contribute no evidence at all.
    @Test("A tap formula disagreeing with a same-named core formula never shows the card")
    func aTapFormulaCollisionNeverShowsTheCard() {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [
                HealthFixtures.package("hunk", offering: "0.17.0", tap: "modem-dev/tap"),
                HealthFixtures.package("tuicr", offering: "0.19.1", tap: "agavra/tap"),
            ],
            catalogVersion: { $0.name == "hunk" ? "0.19.0" : "0.23.1" },
            catalogDownloadedAt: Self.now,
            lastUpdate: .read(Self.now),
            now: Self.now
        )
        #expect(behind == false)
    }

    /// The catalog snapshot was downloaded *before* brew last fetched, so a
    /// disagreement may mean the snapshot is behind — not brew. Backwards
    /// evidence is no evidence.
    @Test("A snapshot older than the fetch marker turns disagreement into no evidence")
    func aStaleSnapshotInvalidatesTheDisagreement() {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [HealthFixtures.package("go", offering: "1.27.0")],
            catalogVersion: { _ in "1.26.6" },
            catalogDownloadedAt: Self.now.addingTimeInterval(-3_600),
            lastUpdate: .read(Self.now),
            now: Self.now
        )
        #expect(behind == false)
    }

    @Test("A snapshot at least as recent as the fetch marker keeps disagreement as evidence")
    func aCurrentSnapshotKeepsTheDisagreement() {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [HealthFixtures.package("go", offering: "1.26.6")],
            catalogVersion: { _ in "1.27.0" },
            // The boundary case: downloaded in the same instant the marker
            // reads. "At least as recent" includes equality.
            catalogDownloadedAt: Self.now,
            lastUpdate: .read(Self.now),
            now: Self.now
        )
        #expect(behind)
    }

    /// A marker that answers nothing cannot invalidate the snapshot: the
    /// primary signal stays usable exactly as before.
    @Test("A non-answer marker leaves the primary signal usable")
    func aNonAnswerMarkerLeavesThePrimarySignalUsable() {
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [HealthFixtures.package("go", offering: "1.26.6")],
            catalogVersion: { _ in "1.27.0" },
            catalogDownloadedAt: Self.now.addingTimeInterval(-2 * Self.day),
            lastUpdate: .absent,
            now: Self.now
        )
        #expect(behind)
    }

    /// A self-updating cask legitimately runs ahead of both catalogs.
    @Test("A self-updating cask's disagreement alone never shows the card")
    func aSelfUpdatingCaskAloneNeverShowsTheCard() {
        let base = HealthFixtures.package(
            "raycast", kind: .cask, offering: "1.0.0", tap: "homebrew/cask"
        )
        let cask = InstalledPackage(
            kind: base.kind,
            name: base.name,
            displayName: base.displayName,
            desc: base.desc,
            homepage: base.homepage,
            tap: base.tap,
            catalogVersion: base.catalogVersion,
            kegs: base.kegs,
            primaryKeg: base.primaryKeg,
            snapshotOutdated: base.snapshotOutdated,
            isPinned: base.isPinned,
            pinnedVersion: base.pinnedVersion,
            declaresAutoUpdates: true
        )
        let behind = HomebrewUpdateNeed.isBehind(
            packages: [cask],
            catalogVersion: { _ in "2.0.0" },
            catalogDownloadedAt: Self.now,
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
            catalogDownloadedAt: nil,
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
            catalogDownloadedAt: nil,
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
            catalogDownloadedAt: nil,
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

    /// The card is **always** on the Home page: `brew update` is the only way
    /// to learn whether brew is behind, so an affordance gated on that evidence
    /// hid the very action that produces it. The evidence now chooses the
    /// card's wording and tone, never its existence.
    @Test("The card is always present and lets the staleness projection choose its wording")
    func theCardIsAlwaysPresentAndTheProjectionChoosesItsWording() throws {
        let maintenance = try #require(
            Self.body(of: "private var maintenance: [AttentionItem]", in: try Self.homeSource()),
            "the maintenance projection is missing"
        )
        #expect(
            maintenance.contains("return []") == false,
            "the maintenance projection can still answer with no card"
        )
        #expect(
            maintenance.contains("HomebrewUpdateNeed.isBehind"),
            "the card's wording is not chosen by the tested projection"
        )
        #expect(
            maintenance.contains("HomebrewUpdateNeed.copy(behind:"),
            "the card words its own state instead of taking the projection's copy"
        )
        #expect(
            maintenance.contains("catalog.snapshotGeneratedAt"),
            "the projection is not told when the catalog's answers were fetched"
        )
    }

    /// The two wordings, as values: the plain invitation and the evidence-backed
    /// one differ in every user-visible field, so a wrong branch is visible.
    @Test("The card's copy is the plain invitation unless brew is demonstrably behind")
    func theCardCopyFollowsTheEvidence() {
        let plain = HomebrewUpdateNeed.copy(behind: false)
        let behind = HomebrewUpdateNeed.copy(behind: true)

        #expect(plain.title == "Homebrew learns about new versions from brew update")
        #expect(plain.sub == "Refreshes available versions and taps · installs nothing")
        #expect(plain.isEmphasized == false)

        #expect(behind.title == "Homebrew is behind what's published")
        #expect(behind.sub == "Run brew update to refresh available versions and taps · installs nothing")
        #expect(behind.isEmphasized)
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
