//
//  DiscoverCompositionTests.swift
//  cellarTests
//

import Catalog
import Foundation
import Testing

@testable import cellar

/// What only the **built application** can prove about Discover.
///
/// Two claims live here and nowhere else. The first is that the SwiftPM resource
/// bundle carrying the curated list actually reached the `.app` — a resource can
/// pass `swift test` happily and be missing at runtime, which is a failure a
/// user meets and no unit test sees. The second is the honest-phrasing rule,
/// which is a requirement rather than a review note, so a scan owns it.
@Suite("Discover composition")
struct DiscoverCompositionTests {
    // MARK: - The shipped resource reaches the built app (design risk 1)

    @Test("The curated list resolves from the built application bundle")
    func curatedListResolvesFromTheBuiltApp() async throws {
        // Loaded through the accessor the app itself calls, from inside the
        // running `.app` rather than from a SwiftPM test bundle.
        let list = try await CuratedDiscoveryList.shipped()

        #expect((3...5).contains(list.categories.count))
        let entries = list.categories.flatMap(\.entries)
        #expect((20...30).contains(entries.count))
        #expect(list.skippedRecordCount == 0)
        // The same shape `swift test` saw, so a bundle that shipped a stale or
        // truncated copy fails here too.
        #expect(entries.contains { $0.kind == .formula })
        #expect(entries.contains { $0.kind == .cask })
        #expect(entries.allSatisfy { $0.blurb.isEmpty == false })
    }

    // MARK: - Honest phrasing, as a scan (PD-R5, threat-matrix TM4)

    /// Every claim the catalog cannot support. "New to you" is a statement about
    /// *this machine's first observation*; none of these is.
    static let forbiddenClaims = [
        "published",
        "release date",
        "added to homebrew",
        "new on homebrew",
        "recently added",
        "newly released"
    ]

    @Test("No Discover source claims a package is new to Homebrew")
    func discoverSourcesMakeNoPublicationClaim() throws {
        let sources = try DiscoverSources.load()

        // The positive anchor: without it, a moved directory would make every
        // prohibition below pass while reading nothing at all.
        #expect(sources.isEmpty == false, "the scan found no Discover sources")
        #expect(
            sources.contains { $0.code.contains("DiscoverView") },
            "the scan never read the Discover view, so it read nothing real"
        )

        for source in sources {
            let lowered = source.code.lowercased()
            for claim in Self.forbiddenClaims {
                #expect(
                    lowered.contains(claim) == false,
                    "\(source.name) claims \(claim), which the catalog cannot support"
                )
            }
        }
    }

    @Test("No Discover view turns catalog text into a link, a URL or a command")
    func discoverViewsRenderCatalogTextInertly() throws {
        // TM4: names and descriptions are catalog-published text. They render as
        // `Text`, exactly as Browse already does — never as a tappable
        // destination built from a string the catalog supplied.
        let sources = try DiscoverSources.load()
        #expect(sources.isEmpty == false)

        for source in sources {
            #expect(source.code.contains("Link(") == false, "\(source.name) builds a Link")
            #expect(
                source.code.contains("URL(string:") == false,
                "\(source.name) builds a URL from catalog text"
            )
            #expect(source.code.contains("Process(") == false, "\(source.name) spawns a process")
            #expect(
                source.code.contains("NSWorkspace") == false,
                "\(source.name) opens something outside the app"
            )
        }
    }

    // MARK: - Row and section models are plain values (task 9.3)

    @Test("A ladder section emits one row per ranked package, with its own metric")
    func ladderSectionEmitsARowPerRankedPackage() throws {
        let ladder = DiscoverRanking.ladder(.formula, in: Self.rankedPackages())
        let section = DiscoverLadderModel(title: "Top formulae", state: .populated(ladder))

        #expect(section.rows.count == 3)
        #expect(section.rows.map(\.rank) == [1, 2, 3])
        #expect(section.rows.map(\.name) == ["alpha", "bravo", "charlie"])
        // The metric label matches the kind, because the two ladders measure
        // different quantities and a shared label would misreport one of them.
        #expect(section.rows.allSatisfy { $0.metricLabel == "installs on request" })
        #expect(section.rows.first?.installsLabel == "300")
        #expect(section.isEmpty == false)
        #expect(section.explanation == nil)
    }

    @Test("A cask ladder labels its own metric")
    func caskLadderLabelsItsOwnMetric() {
        let ladder = DiscoverRanking.ladder(
            .cask,
            in: [CatalogPackage.discoverStub(kind: .cask, name: "iterm2", installCount365d: 90)]
        )
        let section = DiscoverLadderModel(title: "Top casks", state: .populated(ladder))

        #expect(section.rows.map(\.metricLabel) == ["installs"])
        #expect(section.rows.map(\.name) == ["iterm2"])
    }

    @Test("An empty ladder section carries its explanation instead of a blank list")
    func emptyLadderSectionCarriesItsExplanation() throws {
        let section = DiscoverLadderModel(
            title: "Top formulae",
            state: .empty(.noEligibleRankedPackage)
        )

        #expect(section.rows.isEmpty)
        #expect(section.isEmpty)
        // Never an empty list beside an empty string: the reason travels with it.
        let explanation = try #require(section.explanation)
        #expect(explanation.isEmpty == false)
        #expect(explanation == DiscoverCopy.noEligibleRankedPackage)
    }

    @Test("A curated section emits a row only for an entry that resolved")
    func curatedSectionEmitsResolvedEntriesOnly() throws {
        let list = CuratedDiscoveryList(
            categories: [
                CuratedCategory(
                    id: "staples",
                    title: "Staples",
                    entries: [
                        CuratedEntry(kind: .formula, token: "alpha", blurb: "Worth having."),
                        CuratedEntry(kind: .formula, token: "gone", blurb: "Not in the catalog.")
                    ]
                )
            ],
            skippedRecordCount: 0
        )
        let resolved = list.resolved(against: Self.rankedPackages())
        let section = DiscoverCuratedModel(state: .populated(resolved.categories))

        #expect(section.categories.count == 1)
        let rows = try #require(section.categories.first?.rows)
        // Only the entry that resolved. A row a user cannot install is worse
        // than no row at all.
        #expect(rows.map(\.name) == ["alpha"])
        #expect(rows.map(\.blurb) == ["Worth having."])
        #expect(rows.contains { $0.name == "gone" } == false)
    }

    @Test("An arrivals section carries the CellarCore copy in both of its states")
    func arrivalsSectionCarriesTheSuppliedCopy() throws {
        let populated = DiscoverArrivalsModel(
            state: .populated([
                ArrivalRow(
                    package: CatalogPackage.discoverStub(kind: .formula, name: "newpkg"),
                    firstSeenAt: Date(timeIntervalSince1970: 1_800_000_000)
                )
            ]),
            hiddenCount: 4
        )
        let empty = DiscoverArrivalsModel(
            state: .empty(.newnessMeasuredFromThisSyncOnward),
            hiddenCount: 0
        )

        #expect(populated.rows.map(\.name) == ["newpkg"])
        #expect(populated.explanation == DiscoverCopy.arrivalsPopulated)
        #expect(populated.hiddenLabel == "and 4 more")

        // The first-run state is designed and explained, never a spinner and
        // never a hidden section (D5).
        #expect(empty.rows.isEmpty)
        #expect(empty.explanation == DiscoverCopy.arrivalsEmpty)
        #expect(empty.hiddenLabel == nil)
    }

    @Test("An arrival's relative label is reckoned from the instant it is given")
    func arrivalLabelUsesTheInstantItIsGiven() {
        let firstSeen = Date(timeIntervalSince1970: 1_800_000_000)
        let row = DiscoverArrivalRow(
            package: CatalogPackage.discoverStub(kind: .formula, name: "newpkg"),
            firstSeenAt: firstSeen
        )

        // An hour later versus three weeks later. A label that quietly read the
        // wall clock instead of its argument would return the same string for
        // both — which is how an injected clock becomes decorative.
        let soonAfter = row.firstSeenLabel(relativeTo: firstSeen.addingTimeInterval(3_600))
        let muchLater = row.firstSeenLabel(
            relativeTo: firstSeen.addingTimeInterval(21 * 24 * 3_600)
        )

        #expect(soonAfter.isEmpty == false)
        #expect(muchLater.isEmpty == false)
        #expect(soonAfter != muchLater)
    }

    // MARK: - The section sits between Home and Browse (D4)

    /// `@MainActor` because the app target defaults to main-actor isolation, so
    /// `AppSection`'s `title` and `systemImage` are main-isolated. The section
    /// order is a shell concern and belongs on that actor; the row models below
    /// are the parts deliberately kept `nonisolated`.
    @MainActor
    @Test("Discover sits between Home and Browse in the sidebar order")
    func discoverSitsBetweenHomeAndBrowse() throws {
        let order = AppSection.allCases
        let discover = try #require(order.firstIndex(of: .discover))
        let home = try #require(order.firstIndex(of: .home))
        let browse = try #require(order.firstIndex(of: .browse))

        #expect(home < discover)
        #expect(discover < browse)
        #expect(discover == home + 1)
        #expect(AppSection.discover.title == "Discover")
        #expect(AppSection.discover.systemImage == "sparkles")
    }

    // MARK: - Helpers

    static func rankedPackages() -> [CatalogPackage] {
        [
            CatalogPackage.discoverStub(kind: .formula, name: "alpha", installCount365d: 300),
            CatalogPackage.discoverStub(kind: .formula, name: "bravo", installCount365d: 200),
            CatalogPackage.discoverStub(kind: .formula, name: "charlie", installCount365d: 100)
        ]
    }
}

/// Reads `cellar/Discover/` off disk, the way `AppSecuritySources` reads the
/// whole app target.
///
/// Textual by necessity — a claim about what a file does *not* contain cannot be
/// made by importing it — and comments are stripped first, so a prohibition
/// *described* in a doc comment is never mistaken for one *violated* in code.
enum DiscoverSources {
    struct Source: Sendable {
        let name: String
        let code: String
    }

    static var directories: [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
        return [
            root.appendingPathComponent("cellar/Discover"),
            root.appendingPathComponent("Packages/CellarCore/Sources/Catalog")
        ]
    }

    /// The Discover views, plus the Catalog sources that own discovery — the two
    /// places a publication claim could be written.
    static let catalogDiscoverySources: Set<String> = [
        "DiscoverRanking.swift",
        "CuratedDiscovery.swift",
        "DiscoveryRoster.swift",
        "DiscoveryRosterDiff.swift",
        "DiscoverContent.swift"
    ]

    static func load() throws -> [Source] {
        var sources: [Source] = []
        for directory in Self.directories {
            let isCatalog = directory.lastPathComponent == "Catalog"
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: nil
            )
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let name = url.lastPathComponent
                // In the Catalog target, scan only the discovery sources: the
                // rest of the catalog legitimately talks about published data.
                if isCatalog, !Self.catalogDiscoverySources.contains(name) { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                sources.append(
                    Source(name: name, code: AppSecuritySources.stripComments(from: text))
                )
            }
        }
        return sources.sorted { $0.name < $1.name }
    }
}

extension CatalogPackage {
    /// A package with everything defaulted, so each test names only the fields
    /// it asserts on. The app target cannot see `CatalogTests`' own stub.
    static func discoverStub(
        kind: PackageKind,
        name: String,
        installCount365d: Int? = nil
    ) -> CatalogPackage {
        CatalogPackage(
            kind: kind,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            license: nil,
            version: "1.0.0",
            tap: kind == .formula ? "homebrew/core" : "homebrew/cask",
            dependencies: [],
            buildDependencies: [],
            dependents: [],
            caveats: nil,
            deprecated: false,
            deprecationReason: nil,
            deprecationDate: nil,
            disabled: false,
            disableReason: nil,
            disableDate: nil,
            autoUpdates: false,
            installCount365d: installCount365d
        )
    }
}
