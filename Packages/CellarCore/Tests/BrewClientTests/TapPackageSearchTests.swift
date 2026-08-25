import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

/// Packages published by installed third-party taps, found from the query
/// surface as a **composed source** (`package-search` PS8).
///
/// Everything here is a claim about a pure value: the ladder, the total order,
/// the collision fact, the routability rule, the presentation states and
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

    // MARK: - ps4 — six facts, its copy, and nothing else

    @Test("A hit carries its six facts and its copy, and nothing else")
    func aHitCarriesItsSixFactsAndItsCopyAndNothingElse() throws {
        let tap = TapSearchFixture.tap("acme/tools", casks: ["acme/tools/widget"])
        let hit = try #require(hits([tap], "widget").first)

        #expect(hit.id.kind == .cask)
        #expect(hit.displayName == "widget")
        #expect(hit.publishedName == "acme/tools/widget")
        #expect(hit.tapName == "acme/tools")
        #expect(hit.state == .notInstalled)
        #expect(hit.isInstalled == false)
        // The sixth fact, absent here because this hit is not installed: an
        // offered version is only representable for a package this Mac has
        // (PS8 round 4, DD-19). An absence, never `""`.
        #expect(hit.nextVersion == nil)
        // The install state is a **fact**, not a sentence: a not-installed hit
        // pins no copy at all now that the row's pill carries the state (PS8
        // round 3, DD-9). An absence, never `""`.
        #expect(hit.stateNote == nil)
        #expect(hit.collisionNote == nil)

        let labels = Mirror(reflecting: hit).children.compactMap(\.label).sorted()
        #expect(labels == [
            "alsoInCatalog", "collisionNote", "displayName", "id", "mutationTarget",
            "nextVersion", "publishedName", "rank", "routableID", "state", "stateNote",
            "tapName"
        ])
        // Round 4 narrows "no version" to "no **published** version": the one
        // version-shaped member is the offered version, read off this Mac's own
        // receipt rather than off the tap, so it is enumerated by name rather
        // than forbidden by token.
        #expect(labels.filter { $0.lowercased().contains("version") } == ["nextVersion"])
        // The absence set, enumerated rather than assumed: none of these is
        // representable, because the tap inventory publishes none of them and
        // reading them would need the tap-source read TM5 forbids.
        for absent in [
            "desc", "description", "homepage", "license", "dependencies",
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

    // MARK: - ps6 — an empty query lists everything the installed taps publish

    /// The rule inverted by the 2026-08-25 scope change (DD-16).
    ///
    /// The surface is reachable from the sidebar with no query typed, so an
    /// empty query is the *default listing* rather than an absence — exactly as
    /// `PackageSearchIndex.defaultOrder(filters:limit:)` answers an empty
    /// catalog query with the whole filtered catalog at `.exactToken`.
    @Test("An empty query lists everything the installed taps publish")
    func anEmptyQueryListsEveryTapPackage() {
        let taps = TapSearchFixture.fortyAcrossTwoTaps
        #expect(TapSearchFixture.acmeTwentyFive.formulaNames.count == 25)
        #expect(TapSearchFixture.bravoFifteen.caskTokens.count == 15)

        for query in ["", "   ", "\t\n"] {
            let found = hits(taps, query)
            #expect(
                found.map(\.displayName) == TapSearchFixture.fortyInOrder,
                "query \(query.debugDescription) did not list the forty in order"
            )
            #expect(found.allSatisfy { $0.rank == .exactToken })
            #expect(Set(found.map(\.id)).count == 40)
        }

        // Official taps stay excluded: the empty query lists what the *third
        // party* taps publish, not what brew ships.
        let withOfficial = taps + [TapSearchFixture.officialCore, TapSearchFixture.officialCask]
        #expect(hits(withOfficial, "").map(\.displayName) == TapSearchFixture.fortyInOrder)

        // …and the declared filters still restrict the listing.
        let casksOnly = hits(taps, "", kinds: [.cask])
        #expect(casksOnly.count == 15)
        #expect(casksOnly.allSatisfy { $0.id.kind == .cask })

        let installed = InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "pkg7", tap: "acme/tools")
        ])
        let subtracted = hits(taps, "", installed: installed, hideInstalled: true)
        #expect(subtracted.count == 39)
        #expect(subtracted.contains { $0.displayName == "pkg7" } == false)

        // Triangulated against a real query over the same inventory: a needle
        // that matches six of the forty still returns exactly those six, the
        // exact token ahead of the five it prefixes.
        #expect(
            hits(taps, "tok1").map(\.displayName)
                == ["tok1", "tok10", "tok11", "tok12", "tok13", "tok14"]
        )
    }

    @Test("The default listing order is the search order")
    func theDefaultListingOrderMatchesTheSearchOrder() {
        let taps = [TapSearchFixture.acmeTooling, TapSearchFixture.bravoTooling]

        let listed = hits(taps, "")
        let searched = hits(taps, "tool")

        #expect(listed.count == 4)
        #expect(listed.map(\.id) == searched.map(\.id))
        #expect(
            listed.map(\.displayName)
                == ["tool-alpha", "tool-beta", "tool-charlie", "tool-delta"]
        )
        // Non-vacuous: the query really does class all four the same way, so
        // the sequences match on the remaining keys rather than by accident of
        // a rank tiebreak.
        #expect(Set(searched.map(\.rank)) == [.exactToken])
        #expect(Set(listed.map(\.rank)) == [.exactToken])
    }

    // MARK: - ps7 — an unavailable or empty inventory is an ordinary empty state

    private func presentation(
        _ tapState: TapLoadState,
        _ taps: [TapRecord],
        query: String,
        hitCount: Int
    ) -> TapSearchPresentation {
        TapPackageSearch.presentation(
            tapState: tapState,
            inventory: TapSearchFixture.inventory(taps),
            query: query,
            hitCount: hitCount
        )
    }

    @Test("The presentation distinguishes every empty reason")
    func thePresentationDistinguishesEveryEmptyReason() {
        let absence = InstalledAbsence.notInstalled(.standard)
        let published = [TapSearchFixture.acmeWidgets]

        let unavailable = presentation(.brewAbsent(absence), [], query: "", hitCount: 0)
        let failed = presentation(
            .failed(.commandFailed(status: 1, message: "boom")),
            [],
            query: "",
            hitCount: 0
        )
        let noTaps = presentation(.loaded, [], query: "", hitCount: 0)
        let noMatch = presentation(.loaded, published, query: "sprocket", hitCount: 0)
        let content = presentation(.loaded, published, query: "widget", hitCount: 3)

        #expect(unavailable == .unavailable(absence))
        #expect(failed == .failed(.commandFailed(status: 1, message: "boom")))
        #expect(noTaps == .noTaps)
        #expect(noMatch == .noMatch(query: "sprocket"))
        #expect(content == .content)
        // Five values, and five *distinct* values: an absence is never folded
        // into a neighbour and never reported as an error.
        let every: [TapSearchPresentation] = [unavailable, failed, noTaps, noMatch, content]
        for (leftIndex, left) in every.enumerated() {
            for (rightIndex, right) in every.enumerated() where leftIndex != rightIndex {
                #expect(left != right, "\(left) and \(right) are one value, not two")
            }
        }

        // A loaded inventory carrying only official taps publishes nothing a
        // third party owns, so it is the same "nothing yet" as no taps at all.
        #expect(
            presentation(
                .loaded,
                [TapSearchFixture.officialCore, TapSearchFixture.officialCask],
                query: "",
                hitCount: 0
            ) == .noTaps
        )
        // …and so is a third-party tap that publishes nothing: the empty query
        // lists everything, so zero hits with no needle is an empty shelf, not
        // a failed search.
        #expect(
            presentation(.loaded, [TapSearchFixture.tap("acme/tools")], query: "", hitCount: 0)
                == .noTaps
        )
    }

    @Test("The presentation keeps stale content while a refresh is in flight")
    func thePresentationKeepsStaleContentWhileRefreshing() {
        let published = [TapSearchFixture.acmeWidgets]

        // Inherited, not re-derived: `TapProjection.state(…)` is what decides
        // that a resident inventory survives a refresh, and this folds the hit
        // count on top of that answer rather than reading `TapLoadState` again.
        #expect(
            TapProjection.state(loadState: .loading, inventory: TapSearchFixture.inventory(published))
                == .loading(hasLastGood: true)
        )
        #expect(presentation(.loading, published, query: "widget", hitCount: 3) == .content)
        #expect(presentation(.loading, published, query: "", hitCount: 3) == .content)
        // With nothing resident there is nothing stale to keep, so the refresh
        // is the whole answer.
        #expect(presentation(.loading, [], query: "widget", hitCount: 0) == .loading)
        #expect(presentation(.idle, [], query: "widget", hitCount: 0) == .loading)

        // The same inheritance on the failure path: a refresh that fails over a
        // resident inventory still has rows to show, and claiming otherwise
        // would be the false statement "no packages from your taps".
        #expect(
            presentation(.failed(.malformedJSON), published, query: "widget", hitCount: 3)
                == .content
        )
        #expect(
            presentation(.failed(.malformedJSON), [], query: "widget", hitCount: 0)
                == .failed(.malformedJSON)
        )
    }

    @Test("Each empty state carries its pinned sentence byte for byte")
    func theEmptyStateCopyIsExact() throws {
        let absence = InstalledAbsence.notInstalled(.standard)

        #expect(
            TapSearchPresentation.unavailable(absence).emptyStateCopy
                == "No packages from your taps."
        )
        #expect(
            TapSearchPresentation.failed(.malformedJSON).emptyStateCopy
                == "No packages from your taps."
        )
        #expect(TapSearchPresentation.noTaps.emptyStateCopy == "Your taps publish nothing yet.")
        // Distinct sentences for distinct facts: an unavailable inventory and
        // an empty one are not presented as the same thing.
        #expect(
            TapSearchPresentation.unavailable(absence).emptyStateCopy
                != TapSearchPresentation.noTaps.emptyStateCopy
        )
        for pinned in [
            TapSearchPresentation.unavailable(absence),
            .failed(.malformedJSON),
            .noTaps
        ] {
            let copy = try #require(pinned.emptyStateCopy)
            #expect(copy.isEmpty == false)
        }
        // The three states with nothing pinned: a no-match reuses the ordinary
        // search empty state the catalog surface already owns, and neither a
        // refresh nor a filled list has an empty state at all.
        #expect(TapSearchPresentation.noMatch(query: "sprocket").emptyStateCopy == nil)
        #expect(TapSearchPresentation.loading.emptyStateCopy == nil)
        #expect(TapSearchPresentation.content.emptyStateCopy == nil)
    }

    @Test("An unavailable inventory is an empty state and never an error")
    func anUnavailableInventoryIsAnEmptyStateNotAnError() {
        for state in [TapSearchFixture.brewAbsent, TapSearchFixture.refreshFailed] {
            let shown = presentation(state, [], query: "", hitCount: 0)
            #expect(shown.emptyStateCopy == "No packages from your taps.")
            // Nothing about it is a failure the surface must report: no error
            // banner, no retry demand, no failure copy.
            for word in ["error", "failed", "retry", "try again", "went wrong"] {
                #expect(
                    shown.emptyStateCopy?.lowercased().contains(word) != true,
                    "the empty state reports \(word)"
                )
            }
        }
        // Composing over an unavailable inventory throws nothing and yields the
        // ordinary empty result.
        #expect(hits([], "").isEmpty)
        #expect(hits([], "widget").isEmpty)

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

    // MARK: - DD-17 — the count behind the prompt and the shell's label

    @Test("The package count counts third-party taps only")
    func thePackageCountCountsThirdPartyTapsOnly() {
        let taps = TapSearchFixture.fortyAcrossTwoTaps
        let inventory = TapSearchFixture.inventory(taps)

        #expect(TapPackageSearch.packageCount(inventory: inventory) == 40)
        // The count is the listing's own size, by construction rather than by
        // coincidence: it equals what an empty query under default filters
        // returns.
        #expect(TapPackageSearch.packageCount(inventory: inventory) == hits(taps, "").count)

        // Official taps are excluded from both, so the two stay equal when one
        // is added.
        let withOfficial = TapSearchFixture.inventory(
            taps + [TapSearchFixture.officialCore, TapSearchFixture.officialCask]
        )
        #expect(TapPackageSearch.packageCount(inventory: withOfficial) == 40)
        #expect(
            TapPackageSearch.packageCount(inventory: withOfficial)
                == hits(taps + [TapSearchFixture.officialCore, TapSearchFixture.officialCask], "").count
        )
        // Triangulated at the ends: nothing published is zero, not a placeholder.
        #expect(TapPackageSearch.packageCount(inventory: .empty) == 0)
        #expect(
            TapPackageSearch.packageCount(
                inventory: TapSearchFixture.inventory([TapSearchFixture.acmeWidgets])
            ) == 3
        )
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

    // MARK: - ps9 — the states stay distinct, and only the withheld one speaks

    @Test("The three install states stay distinct, and only the withheld state pins a sentence")
    func onlyTheWithheldStateCarriesANote() throws {
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
        // Pairwise, because `TapPackageInstallState` is `Equatable` and not
        // `Hashable` — the hit hashes on its `RowID` for exactly that reason.
        #expect(installed.state != withheld.state)
        #expect(withheld.state != absent.state)
        #expect(installed.state != absent.state)

        // Installed-ness is a fact of the hit, and the **withheld state is
        // installed** — the row draws the same pill for both (PS8 round 3).
        #expect(installed.isInstalled)
        #expect(withheld.isInstalled)
        #expect(absent.isInstalled == false)

        // Only the withheld state has anything left to explain: what Homebrew
        // is withholding, in TM5's exact words.
        #expect(installed.stateNote == nil)
        #expect(
            withheld.stateNote == "Installed. Homebrew withholds its tap while this tap is untrusted."
        )
        #expect(absent.stateNote == nil)

        // The two withdrawn strings, enumerated rather than assumed: the pill's
        // presence and its absence carry those facts now, and a row repeating
        // them in a sentence is the duplicate presentation II8 forbids.
        for withdrawn in ["Installed.", "Not installed."] {
            #expect(
                found.contains { $0.stateNote == withdrawn } == false,
                "a hit still produces the withdrawn string \(withdrawn.debugDescription)"
            )
        }
        // …and exactly one of the three speaks at all, so "no copy" and "empty
        // copy" cannot be confused for one another.
        #expect(found.compactMap(\.stateNote) == [
            "Installed. Homebrew withholds its tap while this tap is untrusted."
        ])
    }

    // MARK: - ps9b (round 4) — the offered version

    /// PS8 round 4: the offered version is a fact of the hit, gated on the
    /// **receipt's own** outdated rule (`installed-inventory` II4).
    @Test("Only an installed hit its receipt reports outdated offers a version")
    func onlyAnOutdatedInstalledHitOffersAVersion() throws {
        let found = hits(
            TapSearchFixture.fourStateTaps,
            "widget",
            installed: TapSearchFixture.fourStateOutdatedInstalled
        )
        #expect(found.count == 4)

        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.displayName, $0) })
        let outdated = try #require(byName["widget-installed"])
        let withheld = try #require(byName["widget-withheld"])
        let current = try #require(byName["widget-current"])
        let absent = try #require(byName["widget-absent"])

        // Each hit reports **its own** receipt's offer, byte for byte — the two
        // versions differ, so a hit reading its neighbour's offer fails here.
        #expect(outdated.nextVersion == "2.0.0")
        #expect(withheld.nextVersion == "3.1.4")
        // …and the withheld state is installed, so it is not silently excluded
        // from the fact the way it would be by an exact-tap-only lookup.
        #expect(withheld.isInstalled)

        // An absence, never `""`: an up-to-date installed hit and a
        // not-installed one are indistinguishable on this fact.
        #expect(current.nextVersion == nil)
        #expect(absent.nextVersion == nil)
        #expect(current.isInstalled)
        #expect(absent.isInstalled == false)

        // The fact is the version being **offered**, never a restatement of the
        // one already installed.
        #expect(found.allSatisfy { $0.nextVersion != InstalledFixture.installedVersion })
        #expect(found.compactMap(\.nextVersion).sorted() == ["2.0.0", "3.1.4"])

        // Triangulated against the shipped up-to-date inventory: the same taps,
        // the same two installed records, and **no** offer at all — so the
        // derivation consults `isOutdated` rather than handing out
        // `catalogVersion` to everything installed.
        let upToDate = hits(
            TapSearchFixture.threeStateTaps,
            "widget",
            installed: TapSearchFixture.threeStateInstalled
        )
        #expect(upToDate.count == 3)
        #expect(upToDate.filter(\.isInstalled).count == 2)
        #expect(upToDate.allSatisfy { $0.nextVersion == nil })
    }

    /// The gate DD-19 keys off `installedHandoff` rather than off the bare
    /// `PackageID` — because `TapProjection.installState` deliberately answers
    /// `.notInstalled` for a receipt whose tap names a **different** tap.
    @Test("A receipt belonging to another tap offers no version to this tap's hit")
    func aReceiptFromAnotherTapOffersNoVersion() throws {
        let widget = PackageID(kind: .formula, name: "widget")
        let installed = InstalledInventory(packages: [
            InstalledFixture.receipt(.formula, "widget", tap: "bravo/tools", outdatedTo: "9.9.9")
        ])
        let hit = try #require(
            hits(
                [TapSearchFixture.tap("acme/tools", formulae: ["acme/tools/widget"])],
                "widget",
                installed: installed
            ).first
        )

        // This tap's package is **not** the installed one, so the hit is not
        // installed — and a not-installed hit offers nothing.
        #expect(hit.state == .notInstalled)
        #expect(hit.isInstalled == false)
        #expect(hit.nextVersion == nil)

        // Non-vacuous: the resident record really does share the identity and
        // really is outdated, so the absence is the gate working rather than an
        // empty inventory answering.
        let record = try #require(installed.package(widget))
        #expect(record.isOutdated)
        #expect(record.catalogVersion == "9.9.9")
        #expect(hit.mutationTarget == widget)
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
        // It is installed, so the row draws the pill — and has nothing further
        // to say, because this state pins no sentence (PS8 round 3).
        #expect(hit.isInstalled)
        #expect(hit.stateNote == nil)
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

    /// ps11's second clause, at the class the spec gives it.
    ///
    /// The design answers it only with a view scan, and a view scan cannot
    /// discharge a `unit` scenario. The honest `unit` form is the projection's
    /// own parameter surface: an outdated predicate is not *representable*
    /// here, so no surface built on it can offer an inert Outdated control.
    @Test("The tap source admits no outdated predicate at all")
    func theTapSourceAdmitsNoOutdatedPredicate() throws {
        let sources = try BrewClientSources.load()
        BrewClientSources.assertAnchored(sources)
        let file = try #require(
            sources.first { $0.name == "TapPackageSearch.swift" },
            "the scan found no TapPackageSearch.swift"
        )

        // The composition's parameter labels, enumerated off the declaration
        // itself rather than asserted one at a time.
        let start = try #require(file.code.range(of: "public func hits("))
        let end = try #require(
            file.code.range(of: ") -> [TapSearchHit]", range: start.upperBound..<file.code.endIndex)
        )
        let labels = file.code[start.upperBound..<end.lowerBound]
            .split(separator: ",")
            .compactMap { $0.split(separator: ":").first?.trimmingCharacters(in: .whitespacesAndNewlines) }
        #expect(labels == ["query", "kinds", "hideInstalled", "isInCatalog"])

        // …and the two symbols an outdated control would have to travel through
        // are absent from the file entirely: not merely unused, unrepresentable.
        #expect(
            file.code.contains("outdatedOnly") == false,
            "the projection still admits an outdated predicate"
        )
        #expect(
            file.code.contains("isSectionVisible") == false,
            "the visibility Bool the outdated chip rode on is still declared"
        )
    }

    // MARK: - ps12 — each surface holds the ceiling on its own turn

    /// This surface's own keystroke turn: `hits(…)` plus `presentation(…)`,
    /// once, as the view runs them per render.
    ///
    /// **No longer a combined turn.** The 2026-08-25 scope change took the tap
    /// results out of Browse, so nothing is added to the catalog's budget and
    /// the two surfaces answer separate keystrokes. The catalog half is
    /// measured on its own in the row below.
    ///
    /// The ceiling is not negotiable — a miss is fixed in the projection, never
    /// by a larger number, a smaller inventory, fewer queries or a p90.
    @Test(
        "The tap surface's keystroke turn stays under the 8 ms ceiling",
        .enabled(if: TapSearchBuildConfiguration.isRelease),
        .timeLimit(.minutes(2))
    )
    func theTapSurfaceKeystrokeTurnStaysUnderTheCeiling() {
        let taps = TapSearchLatencyFixture.tapInventory()
        let installed = TapSearchLatencyFixture.installedInventory(from: taps)
        let source = TapPackageSearch(inventory: taps, installed: installed)
        // The empty query is deliberately first and deliberately included: with
        // DD-16 it is the **worst case**, because every published package
        // matches it. A measurement that skipped it would claim the ceiling for
        // the cheapest turn the surface has.
        let queries = [""] + TapSearchLatencyFixture.asYouTypePrefixes()

        #expect(queries.count >= 100)
        #expect(
            source.hits(query: "", kinds: [.formula, .cask], hideInstalled: false, isInCatalog: { _ in false })
                .count == TapSearchLatencyFixture.tapPackageCount,
            "the empty query does not reach every package, so the worst case is not being measured"
        )

        // Warm-up: first-touch page faults on a 1–2 MB buffer are not latency.
        for _ in 0..<5 {
            for query in queries { blackHole(turn(query, source: source, tapState: .loaded, inventory: taps)) }
        }

        var samples: [Duration] = []
        samples.reserveCapacity(queries.count * 10)
        let clock = ContinuousClock()
        for _ in 0..<10 {
            for query in queries {
                let start = clock.now
                let produced = turn(query, source: source, tapState: .loaded, inventory: taps)
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
            "tap p95 \(p95) exceeded the 8 ms ceiling (median \(median), max \(sorted.last!))"
        )
        // The empty query is ten samples in a thousand, so a p95 alone could
        // step over the very turn DD-16 makes the worst one. The maximum
        // necessarily contains it.
        #expect(
            sorted.last! < Duration.milliseconds(8),
            "the slowest turn — the empty query lists every package — took \(sorted.last!)"
        )
    }

    /// PS6's own measurement, re-run over its own fixture with **no tap
    /// inventory in its turn**.
    ///
    /// The honest form of R6 after the scope change: `BrowseView` and
    /// `PackageSearchIndex` are untouched, so this number must be unchanged. A
    /// regression here means something leaked into the catalog's keystroke.
    @Test(
        "The catalog keystroke turn is unchanged by this source",
        .enabled(if: TapSearchBuildConfiguration.isRelease),
        .timeLimit(.minutes(2))
    )
    func theCatalogKeystrokeTurnIsUnchanged() {
        let index = PackageSearchIndex(snapshot: TapSearchLatencyFixture.catalogSnapshot())
        let queries = TapSearchLatencyFixture.asYouTypePrefixes()

        #expect(index.recordCount == TapSearchLatencyFixture.catalogRecordCount)
        #expect(queries.count >= 100)

        for _ in 0..<5 {
            for query in queries { blackHole(index.search(query).count) }
        }

        var samples: [Duration] = []
        samples.reserveCapacity(queries.count * 10)
        let clock = ContinuousClock()
        for _ in 0..<10 {
            for query in queries {
                let start = clock.now
                let hits = index.search(query)
                samples.append(clock.now - start)
                blackHole(hits.count)
            }
        }

        let sorted = samples.sorted()
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let median = sorted[sorted.count / 2]

        #expect(
            p95 < Duration.milliseconds(8),
            "catalog p95 \(p95) exceeded PS6's own 8 ms ceiling (median \(median), max \(sorted.last!))"
        )
    }

    /// One keystroke on the tap surface: what `TapSearchView` does per render,
    /// in the same order.
    private func turn(
        _ query: String,
        source: TapPackageSearch,
        tapState: TapLoadState,
        inventory: TapInventory
    ) -> Int {
        let found = source.hits(
            query: query,
            kinds: [.formula, .cask],
            hideInstalled: false,
            isInCatalog: { _ in false }
        )
        let shown = TapPackageSearch.presentation(
            tapState: tapState,
            inventory: inventory,
            query: query,
            hitCount: found.count
        )
        return found.count + (shown == .content ? 1 : 0)
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
        #expect(file.code.contains("public static func presentation("))
        #expect(file.code.contains("public static func packageCount(inventory: TapInventory) -> Int"))
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
