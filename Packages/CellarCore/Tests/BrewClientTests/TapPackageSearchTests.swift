import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// Packages published by installed third-party taps, found from the query
/// surface as a **composed source** (`package-search` PS8).
///
/// Everything here is a claim about a pure value: the ladder, the total order,
/// the collision fact, the routability rule, the section-visibility rule and
/// **every user-visible string the surface shows**. Nothing in this suite builds
/// a store, a launcher or a view, because the projection takes none of them —
/// which is itself one of the claims.
@Suite("Tap package search")
struct TapPackageSearchTests {
    // MARK: - Arrangement

    private func search(
        _ taps: [TapRecord],
        installed: InstalledInventory = .empty
    ) -> TapPackageSearch {
        TapPackageSearch(inventory: TapSearchFixture.inventory(taps), installed: installed)
    }

    private func hits(
        _ taps: [TapRecord],
        _ query: String,
        installed: InstalledInventory = .empty,
        kinds: Set<PackageKind> = [.formula, .cask],
        hideInstalled: Bool = false,
        catalog: Set<PackageID> = []
    ) -> [TapSearchHit] {
        search(taps, installed: installed).hits(
            query: query,
            kinds: kinds,
            hideInstalled: hideInstalled,
            isInCatalog: { catalog.contains($0) }
        )
    }

    // MARK: - ps1 — a tap package the catalog does not carry is found

    @Test("A tap package the catalog does not carry is found by a non-empty query")
    func aTapPackageIsFoundByANonEmptyQuery() {
        let found = hits([TapSearchFixture.acmeWidgets], "widget")

        #expect(found.map(\.displayName) == ["widget", "widget-cli", "superwidget"])
        #expect(found.allSatisfy { $0.tapName == "acme/tools" })
        #expect(found.map(\.publishedName) == [
            "acme/tools/widget", "acme/tools/widget-cli", "acme/tools/superwidget"
        ])
        // The ladder runs strongest first and never goes back up: the order is
        // the classes ascending, then the tiebreaks inside each class.
        #expect(zip(found, found.dropFirst()).allSatisfy { $0.rank <= $1.rank })
        #expect(found.first?.rank == .exactToken)
        #expect(found.last?.rank == .nameSubstring)
        // Triangulated: a query no published token carries returns nothing at
        // all rather than the whole tap.
        #expect(hits([TapSearchFixture.acmeWidgets], "sprocket").isEmpty)
    }

    @Test("The ladder classifies exactly as the catalog index does on one fixture")
    func theLadderConvergesWithTheCatalogIndexOnOneFixture() throws {
        let names = ["widget", "widget-cli", "superwidget"]
        let index = TapSearchFixture.index(
            names.map { TapSearchFixture.catalogPackage(.formula, $0) }
        )

        for query in ["widget", "wid", "cli", "get"] {
            let indexRanks = Dictionary(
                uniqueKeysWithValues: index.search(query).map { ($0.id.name, $0.rank.rawValue) }
            )
            let tapRanks = Dictionary(
                uniqueKeysWithValues: hits([TapSearchFixture.acmeWidgets], query)
                    .map { ($0.displayName, $0.rank.rawValue) }
            )
            #expect(tapRanks == indexRanks, "the two lists answer \(query) by different rules")
        }
        // Non-vacuous: the fixture really does exercise more than one class.
        #expect(Set(index.search("widget").map(\.rank)).count > 1)
    }

    @Test("Official taps never enter the section")
    func officialTapsNeverEnterTheSection() {
        let taps = [
            TapSearchFixture.officialCore,
            TapSearchFixture.officialCask,
            TapSearchFixture.acmeWidgets
        ]

        #expect(hits(taps, "wget").isEmpty)
        #expect(hits(taps, "visual").isEmpty)
        // …and the third-party tap in the same inventory is still found, so the
        // exclusion is the official-name rule and not an empty composition.
        #expect(hits(taps, "widget").isEmpty == false)
    }

    // MARK: - ps2 — the ladder is token-aware over the shared normalisation

    @Test("A hyphenated name matches by token at every rung")
    func aHyphenatedNameMatchesByTokenAtEveryRung() throws {
        #expect(PackageText.normalizedString("gentle-ai") == "gentle ai")
        let taps = [TapSearchFixture.gentlemanTap]

        let exact = try #require(hits(taps, "ai").first)
        let prefix = try #require(hits(taps, "gent").first)
        let substring = try #require(hits(taps, "tle").first)

        #expect(exact.rank == .exactToken)
        #expect(prefix.rank == .namePrefix)
        #expect(substring.rank == .nameSubstring)
        #expect(Set([exact.rank, prefix.rank, substring.rank]).count == 3)
        #expect(exact.displayName == "gentle-ai")
    }

    @Test("A tap-name query matches through the published name and is capped")
    func aTapNameQueryMatchesThroughThePublishedName() throws {
        // A second tap whose **bare token** carries the query, so the cap is
        // observable as an order and not only as a rank.
        let owned = TapSearchFixture.tap(
            "other/tap",
            formulae: ["other/tap/gentleman-tools"]
        )
        let found = hits([TapSearchFixture.gentlemanTap, owned], "gentleman")

        #expect(found.map(\.displayName) == ["gentleman-tools", "gentle-ai"])
        #expect(found.map(\.rank) == [.exactToken, .nameSubstring])
        // The capped hit matches the bare token not at all.
        let capped = try #require(found.last)
        #expect(PackageText.normalizedString(capped.displayName).contains("gentleman") == false)
        #expect(
            PackageText.normalizedString(capped.publishedName)
                == "gentleman programming tap gentle ai"
        )
    }

    // MARK: - ps3 — the composed order is total and reproducible

    @Test("The composed order is total and reproducible")
    func theOrderIsTotalAndReproducible() {
        let taps = [TapSearchFixture.acmeBothKinds, TapSearchFixture.bravoBothKinds]
        let expected = [
            TapSearchHit.RowID(tapName: "acme/tools", kind: .formula, name: "widget"),
            TapSearchHit.RowID(tapName: "bravo/tools", kind: .formula, name: "widget"),
            TapSearchHit.RowID(tapName: "acme/tools", kind: .cask, name: "widget"),
            TapSearchHit.RowID(tapName: "bravo/tools", kind: .cask, name: "widget")
        ]

        #expect(hits(taps, "widget").map(\.id) == expected)
        #expect(hits(taps, "widget").map(\.id) == expected)
        // …and shuffling the inventory input changes nothing: the order is the
        // rule's, not the input's.
        #expect(hits(taps.reversed(), "widget").map(\.id) == expected)
        // All four are in one class, so the order below rank is what is being
        // proven here.
        #expect(Set(hits(taps, "widget").map(\.rank)) == [.exactToken])
    }

    // MARK: - ps4 — five facts, its copy, and nothing else

    @Test("A hit carries its five facts and its copy, and nothing else")
    func aHitCarriesItsFiveFactsAndItsCopyAndNothingElse() throws {
        let tap = TapSearchFixture.tap("acme/tools", casks: ["acme/tools/widget"])
        let hit = try #require(hits([tap], "widget").first)

        #expect(hit.id.kind == .cask)
        #expect(hit.displayName == "widget")
        #expect(hit.publishedName == "acme/tools/widget")
        #expect(hit.tapName == "acme/tools")
        #expect(hit.state == .notInstalled)
        #expect(hit.stateCopy == "Not installed.")
        #expect(hit.collisionNote == nil)

        let labels = Mirror(reflecting: hit).children.compactMap(\.label).sorted()
        #expect(labels == [
            "alsoInCatalog", "collisionNote", "displayName", "id", "mutationTarget",
            "publishedName", "rank", "routableID", "state", "stateCopy", "tapName"
        ])
        // The absence set, enumerated rather than assumed: none of these is
        // representable, because the tap inventory publishes none of them and
        // reading them would need the tap-source read TM5 forbids.
        for absent in [
            "desc", "description", "version", "homepage", "license", "dependencies",
            "dependents", "installcount", "deprecated", "disabled", "size", "caveats"
        ] {
            #expect(
                labels.contains { $0.lowercased().contains(absent) } == false,
                "the hit exposes \(absent)"
            )
        }
        // …and no emitted value stands in for an absence.
        for child in Mirror(reflecting: hit).children {
            guard let text = child.value as? String else { continue }
            #expect(["", "-", "—", "unknown", "n/a"].contains(text.lowercased()) == false)
        }
    }

    // MARK: - ps5 — the kind filter restricts the composed source

    @Test("The kind filter restricts the composed source")
    func theKindFilterIsHonoured() throws {
        let taps = [TapSearchFixture.acmeBothKinds]

        let casks = hits(taps, "widget", kinds: [.cask])
        #expect(casks.count == 1)
        #expect(casks.first?.id.kind == .cask)

        let formulae = hits(taps, "widget", kinds: [.formula])
        #expect(formulae.count == 1)
        #expect(formulae.first?.id.kind == .formula)

        // PS4 stands: the declared catalog filter set gains no member for this
        // source.
        let declared = Mirror(reflecting: SearchFilters()).children.compactMap(\.label).sorted()
        #expect(declared == ["excludeDeprecated", "excludeDisabled", "kinds"])
    }

    // MARK: - ps6 — an empty query composes no tap source

    @Test("An empty or whitespace-only query composes no tap source")
    func theSectionIsAbsentForAnEmptyOrWhitespaceQuery() {
        let taps = [TapSearchFixture.acmeForty]
        #expect(TapSearchFixture.acmeForty.formulaNames.count == 40)

        for query in ["", "   ", "\t\n"] {
            #expect(hits(taps, query).isEmpty, "query \(query.debugDescription) composed a source")
            #expect(
                TapPackageSearch.isSectionVisible(
                    query: query,
                    outdatedOnly: false,
                    tapState: .loaded
                ) == false
            )
        }
        // Triangulated: a real query over the same forty packages does compose.
        #expect(hits(taps, "pkg1").isEmpty == false)
        #expect(
            TapPackageSearch.isSectionVisible(query: "pkg1", outdatedOnly: false, tapState: .loaded)
        )
    }

    // MARK: - ps7 — an unavailable tap inventory is an absence, not an error

    @Test("An absent or failed tap state hides the section without an error")
    func absentOrFailedTapStateHidesTheSectionWithoutAnError() {
        for state in [TapSearchFixture.brewAbsent, TapSearchFixture.refreshFailed] {
            #expect(
                TapPackageSearch.isSectionVisible(
                    query: "widget",
                    outdatedOnly: false,
                    tapState: state
                ) == false
            )
        }
        for state in [TapLoadState.idle, .loading, .loaded] {
            #expect(
                TapPackageSearch.isSectionVisible(
                    query: "widget",
                    outdatedOnly: false,
                    tapState: state
                )
            )
        }

        // …and the catalog answers the same query identically either way: brew's
        // absence never reaches a catalog result (II7).
        let index = TapSearchFixture.index([
            TapSearchFixture.catalogPackage(.formula, "widgetry"),
            TapSearchFixture.catalogPackage(.formula, "curl")
        ])
        let withoutTaps = index.search("widget")
        _ = hits([TapSearchFixture.acmeWidgets], "widget")
        #expect(index.search("widget") == withoutTaps)
    }

    // MARK: - ps8 — a catalog collision is reported and never suppressed

    @Test("A colliding hit is shown and is not routable")
    func aCollidingHitIsShownAndIsNotRoutable() throws {
        let wget = PackageID(kind: .formula, name: "wget")
        let hit = try #require(
            hits([TapSearchFixture.acmeWget], "wget", catalog: [wget]).first
        )

        #expect(hit.alsoInCatalog)
        #expect(hit.routableID == nil)
        #expect(hit.mutationTarget == wget)
        // The row identity is its own type and carries the tap of origin, so it
        // can never be compared against, or mistaken for, the catalog row's
        // `PackageID`.
        #expect(hit.id == TapSearchHit.RowID(tapName: "acme/tools", kind: .formula, name: "wget"))
        #expect(hit.id.tapName == "acme/tools")
        // Triangulated: with no catalog record the same fixture reports no
        // collision, so the fact is the catalog's and not the fixture's.
        let alone = try #require(hits([TapSearchFixture.acmeWget], "wget").first)
        #expect(alone.alsoInCatalog == false)
        #expect(alone.collisionNote == nil)
    }

    @Test("Every mutation target is the bare token")
    func everyMutationTargetIsBare() throws {
        let taps = [
            TapSearchFixture.gentlemanTap,
            TapSearchFixture.acmeBothKinds,
            TapSearchFixture.tap("deep/nest", casks: ["deep/nest/widget-pro"])
        ]
        let all = hits(taps, "widget") + hits(taps, "gentle")
        #expect(all.isEmpty == false)

        for hit in all {
            #expect(
                hit.mutationTarget.name.contains("/") == false,
                "\(hit.publishedName) produced a qualified target"
            )
            #expect(hit.publishedName.contains("/"))
            // PM9's gate accepts every target this source emits, so the install
            // affordance is never silently absent.
            #expect(PackageTarget(hit.mutationTarget) != nil)
        }
    }

    @Test("The collision note is present exactly when the collision is")
    func theCollisionNoteIsPresentExactlyWhenItIsTrue() throws {
        let wget = PackageID(kind: .formula, name: "wget")
        let taps = [TapSearchFixture.acmeWget, TapSearchFixture.tap(
            "bravo/tools",
            formulae: ["bravo/tools/wgetter"]
        )]
        let found = hits(taps, "wget", catalog: [wget])
        #expect(found.count == 2)

        for hit in found {
            #expect(
                (hit.collisionNote != nil) == hit.alsoInCatalog,
                "\(hit.publishedName) disagrees with itself about the collision"
            )
        }
        let colliding = try #require(found.first { $0.alsoInCatalog })
        #expect(
            colliding.collisionNote == "Also in the catalog. Homebrew installs the catalog package."
        )
        #expect(found.contains { $0.alsoInCatalog == false })
    }

    // MARK: - ps9 — the three install states carry their exact copy

    @Test("The three install states stay distinct and carry their exact copy")
    func theThreeInstallStatesCarryTheirExactCopy() throws {
        let found = hits(
            TapSearchFixture.threeStateTaps,
            "widget",
            installed: TapSearchFixture.threeStateInstalled
        )
        #expect(found.count == 3)

        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.displayName, $0) })
        let installed = try #require(byName["widget-installed"])
        let withheld = try #require(byName["widget-withheld"])
        let absent = try #require(byName["widget-absent"])

        #expect(installed.state == .installed(PackageID(kind: .formula, name: "widget-installed")))
        #expect(
            withheld.state == .installedTapWithheld(
                PackageID(kind: .formula, name: "widget-withheld")
            )
        )
        #expect(absent.state == .notInstalled)
        #expect(Set([installed.stateCopy, withheld.stateCopy, absent.stateCopy]).count == 3)

        #expect(installed.stateCopy == "Installed.")
        #expect(
            withheld.stateCopy == "Installed. Homebrew withholds its tap while this tap is untrusted."
        )
        #expect(absent.stateCopy == "Not installed.")
        // The trap this row exists for: the shipped tap-detail projection is
        // silent for the installed state, so reusing it would leave the row
        // with nothing to say (DD-9).
        #expect(found.allSatisfy { $0.stateCopy.isEmpty == false })
    }

    // MARK: - ps10 — an ambiguous installed hit is not routable

    @Test("An installed hit whose token the catalog also carries is not routable")
    func anAmbiguousInstalledHitIsNotRoutable() throws {
        let wget = PackageID(kind: .formula, name: "wget")
        let installed = InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "wget", tap: "acme/tools")
        ])
        let hit = try #require(
            hits([TapSearchFixture.acmeWget], "wget", installed: installed, catalog: [wget]).first
        )

        #expect(hit.state == .installed(wget))
        #expect(hit.routableID == nil)
        // Presented and installable regardless: only the detail route is
        // withheld.
        #expect(hit.mutationTarget == wget)
        #expect(hit.stateCopy == "Installed.")
    }

    @Test("Two taps publishing one name are both unroutable")
    func twoTapsPublishingOneNameAreBothUnroutable() {
        let found = hits(
            [TapSearchFixture.acmeDuplicate, TapSearchFixture.bravoDuplicate],
            "widget",
            installed: TapSearchFixture.withheldWidgetInstalled
        )

        #expect(found.count == 2)
        #expect(Set(found.map(\.id)).count == 2)
        #expect(Set(found.map(\.mutationTarget)).count == 1)
        #expect(found.allSatisfy { $0.routableID == nil })
        #expect(found.allSatisfy { $0.alsoInCatalog == false })
        #expect(found.allSatisfy {
            $0.state == .installedTapWithheld(PackageID(kind: .formula, name: "widget"))
        })
    }

    @Test("An installed, unambiguous hit hands over its exact identity")
    func anInstalledUnambiguousHitIsRoutable() throws {
        let widget = PackageID(kind: .formula, name: "widget")
        let sole = TapSearchFixture.tap("acme/tools", formulae: ["acme/tools/widget"])

        let hit = try #require(
            hits([sole], "widget", installed: TapSearchFixture.acmeWidgetInstalled).first
        )
        #expect(hit.routableID == widget)
        #expect(hit.routableID == hit.mutationTarget)

        // The withheld state routes too: the handoff selects by exact
        // `PackageID`, and that identity is exact regardless of what brew
        // withholds (TM5).
        let withheldTap = TapSearchFixture.tap(
            "acme/tools",
            formulae: ["acme/tools/widget"],
            trust: .untrusted
        )
        let withheld = try #require(
            hits([withheldTap], "widget", installed: TapSearchFixture.withheldWidgetInstalled).first
        )
        #expect(withheld.state == .installedTapWithheld(widget))
        #expect(withheld.routableID == widget)
    }

    @Test("A not-installed hit is never routable")
    func aNotInstalledHitIsNeverRoutable() {
        let found = hits([TapSearchFixture.acmeWidgets], "widget")

        #expect(found.count == 3)
        #expect(found.allSatisfy { $0.state == .notInstalled })
        #expect(found.allSatisfy { $0.routableID == nil })
        // …and each is still presented and still installable.
        #expect(found.allSatisfy { PackageTarget($0.mutationTarget) != nil })
    }

    // MARK: - ps11 — installed-state controls compose above the tap source

    @Test("Hide installed subtracts from the section")
    func hideInstalledSubtractsFromTheSection() {
        let taps = TapSearchFixture.threeStateTaps
        let installed = TapSearchFixture.threeStateInstalled

        let all = hits(taps, "widget", installed: installed)
        #expect(all.count == 3)

        let subtracted = hits(taps, "widget", installed: installed, hideInstalled: true)
        #expect(subtracted.map(\.displayName) == ["widget-absent"])
        // Both installed states are subtracted, not only the exact-tap one.
        #expect(subtracted.allSatisfy { $0.state == .notInstalled })
    }

    @Test("The outdated chip hides the section whole rather than emptying it")
    func theOutdatedChipHidesTheSection() {
        for query in ["widget", "wid"] {
            #expect(
                TapPackageSearch.isSectionVisible(
                    query: query,
                    outdatedOnly: true,
                    tapState: .loaded
                ) == false
            )
        }
        // The distinction that matters: the hits themselves are unchanged, so
        // the section is *hidden* rather than emitting zero rows and reading as
        // the false claim "your taps have nothing" (DD-6).
        #expect(hits([TapSearchFixture.acmeWidgets], "widget").count == 3)
    }

    // MARK: - ps12 — the combined keystroke turn stays under the ceiling

    /// The catalog query **and** the tap composition, on one turn, as the view
    /// runs them.
    ///
    /// Explicitly **not** a re-run of the shipped PS6 measurement: that one
    /// never touches the tap inventory, so it cannot observe the regression this
    /// change could cause. The ceiling is not negotiable — a miss is fixed in
    /// the projection, never by a larger number, a smaller inventory, fewer
    /// queries or a p90.
    @Test(
        "The combined catalog and tap keystroke turn stays under the 8 ms ceiling",
        .enabled(if: TapSearchBuildConfiguration.isRelease),
        .timeLimit(.minutes(2))
    )
    func theCombinedKeystrokeTurnStaysUnderTheCeiling() {
        let index = PackageSearchIndex(snapshot: TapSearchLatencyFixture.catalogSnapshot())
        let taps = TapSearchLatencyFixture.tapInventory()
        let installed = TapSearchLatencyFixture.installedInventory(from: taps)
        let source = TapPackageSearch(inventory: taps, installed: installed)
        let queries = TapSearchLatencyFixture.asYouTypePrefixes()

        #expect(index.recordCount == TapSearchLatencyFixture.catalogRecordCount)
        #expect(queries.count >= 100)

        // Warm-up: first-touch page faults on a 1–2 MB buffer are not latency.
        for _ in 0..<5 {
            for query in queries { blackHole(turn(query, index: index, source: source)) }
        }

        var samples: [Duration] = []
        samples.reserveCapacity(queries.count * 10)
        let clock = ContinuousClock()
        for _ in 0..<10 {
            for query in queries {
                let start = clock.now
                let produced = turn(query, index: index, source: source)
                samples.append(clock.now - start)
                blackHole(produced)
            }
        }

        #expect(samples.count == queries.count * 10)
        let sorted = samples.sorted()
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let median = sorted[sorted.count / 2]

        #expect(
            p95 < Duration.milliseconds(8),
            "combined p95 \(p95) exceeded the 8 ms ceiling (median \(median), max \(sorted.last!))"
        )
    }

    /// One keystroke: what `BrowseView` does per render, in the same order.
    private func turn(
        _ query: String,
        index: PackageSearchIndex,
        source: TapPackageSearch
    ) -> Int {
        let catalog = index.search(query)
        let catalogIDs = Set(catalog.map(\.id))
        let tap = source.hits(
            query: query,
            kinds: [.formula, .cask],
            hideInstalled: false,
            isInCatalog: { catalogIDs.contains($0) }
        )
        return catalog.count + tap.count
    }

    @Test("The latency fixture is the size and shape the ceiling is claimed for")
    func theCatalogFixtureIsTheOnePS6MeasuresOver() {
        let snapshot = TapSearchLatencyFixture.catalogSnapshot()

        // The shipped PS6 shape assertions, re-stated over the reproduced
        // generator, so "the same fixture" is proven and not assumed.
        #expect(snapshot.packages.count == TapSearchLatencyFixture.catalogRecordCount)
        let nameLengths = snapshot.packages.map(\.name.count)
        let descLengths = snapshot.packages.map { ($0.desc ?? "").count }
        let meanName = Double(nameLengths.reduce(0, +)) / Double(nameLengths.count)
        let meanDesc = Double(descLengths.reduce(0, +)) / Double(descLengths.count)
        #expect((8.0...13.0).contains(meanName), "mean name length \(meanName)")
        #expect((30.0...42.0).contains(meanDesc), "mean description length \(meanDesc)")
        #expect(snapshot.packages.contains { ($0.desc ?? "").isEmpty })
        #expect(Set(snapshot.packages.map(\.kind)) == [.formula, .cask])

        // …and the tap half is the realistic size the scenario names, with both
        // kinds and a query that really does reach it.
        let taps = TapSearchLatencyFixture.tapInventory()
        let published = taps.taps.reduce(0) { $0 + $1.formulaNames.count + $1.caskTokens.count }
        #expect(published == TapSearchLatencyFixture.tapPackageCount)
        #expect(taps.taps.count == TapSearchLatencyFixture.tapCount)
        #expect(taps.taps.allSatisfy { $0.caskTokens.isEmpty == false })
        let source = TapPackageSearch(
            inventory: taps,
            installed: TapSearchLatencyFixture.installedInventory(from: taps)
        )
        let reached = source.hits(
            query: "wget",
            kinds: [.formula, .cask],
            hideInstalled: false,
            isInCatalog: { _ in false }
        )
        #expect(reached.isEmpty == false, "no as-you-type query reaches the tap fixture")
        #expect(source.installed.packages.isEmpty == false)
    }

    /// Keeps the optimiser from deleting the call it is timing.
    @inline(never)
    private func blackHole(_ value: Int) {
        if value == Int.min { fatalError("unreachable") }
    }

    // MARK: - ps16 at the unit layer — nothing to inject

    @Test("The projection takes no launcher, no catalog store and no refresh handle")
    func theProjectionTakesNoLauncherAndNoCatalogStore() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let file = try #require(
            sources.first { $0.name == "TapPackageSearch.swift" },
            "the scan found no TapPackageSearch.swift"
        )

        // The whole input surface, positively anchored.
        #expect(file.code.contains("public init(inventory: TapInventory, installed: InstalledInventory)"))
        #expect(file.code.contains("isInCatalog: (PackageID) -> Bool"))
        #expect(file.code.contains("public static func isSectionVisible("))
        // The predicate is a parameter, never a stored member: a stored closure
        // makes `Hashable` unrepresentable and would drag `Catalog` into the
        // type's own state (DD-1).
        #expect(file.code.contains("let isInCatalog") == false)

        for forbidden in [
            "Process", "BrewProcess", "ProcessSpec", "ProcessLaunching", "CatalogStore",
            "TapStore", "InstalledStore", "PackageSearchIndex", "Clock", "FileManager"
        ] {
            #expect(
                file.code.containsIdentifier(forbidden) == false,
                "the projection can be handed a \(forbidden)"
            )
        }
        for forbidden in ["refresh(", "launcher", "await ", "async ", "Task {"] {
            #expect(
                file.code.contains(forbidden) == false,
                "the projection reaches acquisition through \(forbidden)"
            )
        }
    }

    // MARK: - PD6 sc4 — a composed tap section leaves catalog search unchanged

    @Test("A composed tap search leaves the index unchanged")
    func aComposedTapSearchLeavesTheIndexUnchanged() {
        let widget = PackageID(kind: .formula, name: "widget")
        let snapshot = TapSearchFixture.snapshot([
            TapSearchFixture.catalogPackage(.formula, "curl"),
            TapSearchFixture.catalogPackage(.formula, "wget")
        ])
        let index = PackageSearchIndex(snapshot: snapshot)

        let before = index.search("widget")
        let beforeLookup = index.package(widget)

        let composed = hits(
            [TapSearchFixture.acmeWidgets],
            "widget",
            catalog: Set(snapshot.packages.map(\.id))
        )
        #expect(composed.isEmpty == false)

        #expect(index.search("widget") == before)
        #expect(index.package(widget) == beforeLookup)
        #expect(index.package(widget) == nil)
        #expect(index.recordCount == snapshot.packages.count)
        #expect(snapshot.packages.contains { $0.id == widget } == false)
        // …and the composed hit is not, and never becomes, a catalog record.
        #expect(composed.allSatisfy { index.package($0.mutationTarget) == nil })
    }

    // MARK: - TM5 sc11 — the inventory feeds an outside surface

    @Test("The tap inventory feeds a surface outside tap management")
    func theTapInventoryFeedsASurfaceOutsideTapManagement() {
        let launcher = RecordingProcessLauncher()

        let found = hits([TapSearchFixture.acmeWidgets], "widget")

        #expect(found.isEmpty == false)
        #expect(launcher.launchCount == 0)
        #expect(launcher.specs.isEmpty)
        // The published names are all the source it reads: no formula or cask
        // source is opened, because there is nothing on the hit that would need
        // one.
        #expect(found.allSatisfy { $0.publishedName.hasPrefix("acme/tools/") })
    }

    // MARK: - TM11 sc3 — a tap package found here adds no tap-management action

    @Test("A tap package found here adds no tap-management action")
    func aTapPackageFoundHereAddsNoTapManagementAction() throws {
        // TM11's enumerated set, in the requirement's order. Unchanged by this
        // source, which is the whole of the scenario.
        #expect([
            "refresh", "filter", "Installed handoff", "canonical add", "plain untap",
            "eligible force untap", "trust", "untrust"
        ].count == 8)

        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let command = try #require(sources.first { $0.name == "TapCommand.swift" })
        let file = try #require(sources.first { $0.name == "TapPackageSearch.swift" })

        // Anchored on the verbs tap management really can submit today…
        for verb in ["addTap", "trustTap", "untrustTap", "removeTap", "forceRemoveTap"] {
            #expect(
                command.code.containsIdentifier(verb),
                "tap management's own verb \(verb) moved, so the absence below anchors on nothing"
            )
            #expect(
                file.code.containsIdentifier(verb) == false,
                "the composed source names tap management's \(verb)"
            )
        }
        #expect(file.code.containsIdentifier("TapCommand") == false)
        // …and composing a hit constructs none of them.
        #expect(hits([TapSearchFixture.acmeWidgets], "widget").isEmpty == false)
    }
}
