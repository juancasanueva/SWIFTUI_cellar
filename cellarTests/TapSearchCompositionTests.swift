//
//  TapSearchCompositionTests.swift
//  cellarTests
//

import AppKit
import BrewClient
import Catalog
import Foundation
import Testing

@testable import cellar

/// The claims about the tap search surface that only its **composition** can
/// make (`package-search` PS8 sc13–sc17).
///
/// Asserted structurally over the sources the surface is made of, in the shipped
/// `AppSecuritySources` / `ReceiptDetailSources` idiom: every one of them is
/// either an absence — no trust gate, no trust badge, no process layer, no local
/// copy, no new routing branch, no catalog surface touched — or a claim about
/// *where* a value is composed, and neither can be made by rendering a view.
/// Comments are stripped first, so a prohibition described in a doc comment is
/// never mistaken for one violated in code.
@Suite("Tap search composition", .timeLimit(.minutes(1)))
struct TapSearchCompositionTests {

    // MARK: - ps17 — the catalog query surface is untouched

    /// The round-2 scope change's load-bearing claim.
    ///
    /// The `git diff` in the work unit proves it once, at apply time; this
    /// proves it every run, which is what protects the property after the pull
    /// request merges.
    @Test("Browse is untouched by this change")
    func browseIsUntouchedByThisChange() throws {
        let sources = try TapSearchSources.load()
        try TapSearchSources.assertAnchored(sources)
        let browse = try TapSearchSources.browse()
        let root = try TapSearchSources.source(at: "cellar/ContentView.swift")

        for forbidden in [
            "TapPackageSearch", "TapSearchHit", "TapSearchSection", "TapSearchView",
            "TapStore", "taps", "tapHits"
        ] {
            #expect(
                browse.code.contains(forbidden) == false,
                "the catalog query surface still references \(forbidden)"
            )
        }
        // …and it still is what it was: the flat list and the single-source
        // overlay it had before this change ever started.
        #expect(browse.code.contains("List(rows, selection: $selection)"))
        #expect(browse.code.contains("if rows.isEmpty {"))
        #expect(browse.code.contains("EmptyResults(query: catalog.query, isReady: catalog.isReady)"))
        #expect(browse.code.contains("private struct EmptyResults: View"))
        // The prompt still counts catalog records and nothing else.
        #expect(browse.raw.contains("prompt: \"Search \\(catalog.packageCount.formatted()) packages…\""))

        // The composition root hands it no tap store either: the argument round
        // one added is gone from that call site.
        let call = try TapSearchSources.callSite("BrowseView(", in: root.code)
        #expect(call.contains("taps:") == false, "ContentView still hands BrowseView the tap store")
    }

    @Test("The tap search section file is gone, and nothing still names it")
    func theTapSearchSectionFileIsGone() throws {
        let swiftFiles = try TapSearchSources.swiftSources()
        #expect(swiftFiles.count > 50, "the tree walk read almost nothing, so the absence proves nothing")

        for file in swiftFiles {
            #expect(
                file.code.contains("TapSearchSection") == false,
                "\(file.name) still names the deleted section"
            )
        }
        // The withdrawn string went with it: it named a section that no longer
        // exists, so a surviving copy would be a second name for this surface.
        for file in swiftFiles {
            #expect(
                file.raw.contains("From your taps") == false,
                "\(file.name) still carries the withdrawn section title"
            )
        }
        // Positively anchored: the file that replaced it is the one the scanner
        // list names, and it really is on disk.
        #expect(TapSearchSources.paths.contains("cellar/Browse/TapSearchView.swift"))
        #expect(try TapSearchSources.surface().code.contains("struct TapSearchView: View"))
    }

    // MARK: - ps13, DD-14 — the surface is wired at every AppSection site

    @MainActor
    @Test("The tap search surface is wired at every AppSection site")
    func theTapSearchSurfaceIsWiredAtEveryAppSectionSite() throws {
        let order = AppSection.allCases
        let browse = try #require(order.firstIndex(of: .browse))
        let tapSearch = try #require(order.firstIndex(of: .tapSearch))

        #expect(AppSection.tapSearch.rawValue == "tapSearch")
        #expect(tapSearch == browse + 1, "the tap surface is not the catalog surface's sibling")

        // Site 1 and site 2 are asserted **separately**: they are different
        // strings, and `sidebarTitle` is the one a user actually clicks.
        #expect(AppSection.tapSearch.title == "Search taps")
        #expect(AppSection.tapSearch.sidebarTitle == "Search our taps")
        #expect(AppSection.tapSearch.sidebarTitle != AppSection.tapSearch.title)

        // Site 3. Distinct from Browse's, and — the trap `AppSection.swift`
        // already records once — a name that really exists in this SDK.
        #expect(AppSection.tapSearch.systemImage == "sparkle.magnifyingglass")
        #expect(AppSection.tapSearch.systemImage != AppSection.browse.systemImage)
        #expect(
            NSImage(
                systemSymbolName: AppSection.tapSearch.systemImage,
                accessibilityDescription: nil
            ) != nil,
            "the sidebar row's symbol does not exist in this SDK, so the row renders blank"
        )

        // Site 4.
        #expect(AppSection.sidebarGroups[0].title == "Overview")
        #expect(AppSection.sidebarGroups[0].sections == [.home, .browse, .tapSearch])

        // Sites 5, and the two `Set` literals that are not switches and so fail
        // silently rather than at compile time.
        let root = try TapSearchSources.source(at: "cellar/ContentView.swift")
        for name in ["listSections", "pinnedHeaderSections", "shellTitleBarSections"] {
            let literal = try #require(
                TapSearchSources.setLiteral(named: name, in: root.code),
                "ContentView no longer declares \(name)"
            )
            #expect(literal.contains(".tapSearch"), "\(name) does not carry the tap search surface")
            // Anchored: the reader really did find a populated literal.
            #expect(literal.contains(".browse"))
        }

        // Site 6, and the list-pane width it shares with Browse.
        #expect(root.code.contains("case .tapSearch:"))
        #expect(root.code.contains("TapSearchView("))
        #expect(root.code.contains("section == .browse || section == .tapSearch ? 400 : 342"))
        // The count label is this surface's own, over the projection rather
        // than over a view-side sum or the catalog's record count (DD-17).
        #expect(root.code.contains("TapPackageSearch.packageCount(inventory: taps.inventory)"))
    }

    /// The surface title and the sidebar row are **one** string, in one place.
    ///
    /// The spec pins both to "Search our taps"; the shell renders the pinned
    /// bar's title from `section.sidebarTitle` for every member of
    /// `shellTitleBarSections`, so membership is what makes the two identical
    /// rather than a second literal in the view — which PS8's copy-ownership
    /// clause forbids outright.
    @MainActor
    @Test("The surface title and the sidebar entry are the same pinned string")
    func theSurfaceTitleIsTheSidebarEntry() throws {
        let root = try TapSearchSources.source(at: "cellar/ContentView.swift")

        #expect(root.code.contains("ShellTitleBar(\n                            title: section.sidebarTitle,"))
        let titleBar = try #require(
            TapSearchSources.setLiteral(named: "shellTitleBarSections", in: root.code)
        )
        #expect(titleBar.contains(".tapSearch"))
        #expect(AppSection.tapSearch.sidebarTitle == "Search our taps")
        // …and the view composes no title of its own to disagree with it.
        let surface = try TapSearchSources.surface()
        #expect(surface.raw.contains("\"Search our taps\"") == false)
        #expect(surface.code.contains("ShellTitleBar") == false)
    }

    // MARK: - ps13, ps14 — a visual copy of Browse, on the shared detail

    @Test("The tap surface mirrors Browse's composition")
    func theTapSurfaceMirrorsBrowsesComposition() throws {
        let surface = try TapSearchSources.surface()
        let browse = try TapSearchSources.browse()

        for shared in [
            "PaneSearchField(", "CatalogFilterBar(", "List(", "KindTag(",
            "MutationMenu(center:", ".themedListSelection("
        ] {
            #expect(surface.code.contains(shared), "the tap surface does not compose \(shared)")
        }
        // Anchored on the catalog list itself: five of the six are in its own
        // file, and the kind chip is in the row view that file renders — so
        // "the same six" is proven against Browse rather than merely asserted.
        for shared in [
            "PaneSearchField(", "CatalogFilterBar(", "List(", "MutationMenu(center:",
            ".themedListSelection("
        ] {
            #expect(browse.code.contains(shared), "Browse no longer composes \(shared)")
        }
        let row = try TapSearchSources.source(at: "cellar/Browse/PackageRow.swift")
        #expect(row.code.contains("KindTag("), "Browse's row no longer composes the kind chip")
        // The one place the two lists differ on purpose: the tap list is
        // selection-driven per row, so its `List` takes the binding directly.
        #expect(surface.code.contains("List(selection: $selection)"))
        #expect(browse.code.contains("List(rows, selection: $selection)"))
        // The prompt counts what *this* surface lists, never catalog records.
        #expect(surface.raw.contains("prompt: \"Search \\(packageCount.formatted()) packages…\""))
        #expect(surface.code.contains("catalog.packageCount") == false)
    }

    @Test("The tap surface resolves through the shared detail with no new branch")
    func theTapSurfaceResolvesThroughTheSharedDetail() throws {
        let surface = try TapSearchSources.surface()
        let root = try TapSearchSources.source(at: "cellar/ContentView.swift")
        let detail = try TapSearchSources.source(at: "cellar/Browse/PackageDetailView.swift")

        // One identity space, one selection, and the tap arm joins the shipped
        // `PackageDetailView` arm rather than opening a branch of its own.
        #expect(root.code.contains("@State private var selection: PackageID?"))
        #expect(surface.code.contains("@Binding var selection: PackageID?"))
        #expect(root.code.contains("case .browse, .tapSearch, .installed, .favorites, .updates:"))
        for forbidden in ["TapSearchHit", "TapPackageSearch", "TapSearchView", "TapInventory"] {
            #expect(
                detail.code.contains(forbidden) == false,
                "PackageDetailView grew a branch for \(forbidden)"
            )
        }
        #expect(surface.code.contains("TapSearchSelection") == false)
    }

    @Test("Not-installed and ambiguous tap rows are not selectable")
    func notInstalledTapRowsAreNotSelectable() throws {
        let surface = try TapSearchSources.surface()

        #expect(surface.code.contains(".selectionDisabled("))
        // The two inert cases are one code path: the projection already decided,
        // and the view reads `routableID` rather than re-deriving anything.
        #expect(surface.code.contains("if let routable = hit.routableID"))
        #expect(surface.code.contains(".tag(routable)"))
        #expect(
            surface.code.components(separatedBy: ".tag(").count == 2,
            "the row is tagged in more than one place, so a nil routable id can still reach a tag"
        )
        for forbidden in [".tag(hit.mutationTarget)", ".tag(hit.id)", ".tag(hit."] {
            #expect(
                surface.code.contains(forbidden) == false,
                "the row tags an identity the projection did not clear: \(forbidden)"
            )
        }
        // Nothing here re-derives the rule the projection owns: routability is
        // read off the hit, and the facts behind it are never consulted.
        //
        // `hit.isInstalled` left this list in round 3, deliberately and
        // narrowly. The row now reads it to draw the shared pill, and a `Bool`
        // about installation **cannot** express routability: routing
        // additionally requires the hit to be uncollided and unique, and those
        // are the two facts still forbidden below. The guard's subject is
        // unchanged.
        for forbidden in ["alsoInCatalog", "hit.state ==", "== .notInstalled", "occurrences"] {
            #expect(
                surface.code.contains(forbidden) == false,
                "the view re-derives routability through \(forbidden)"
            )
        }
        // Proven rather than argued: the two reads are separate, and the one
        // that gates selection is still `routableID`.
        #expect(surface.code.contains("if hit.isInstalled {"))
        #expect(surface.code.contains("if let routable = hit.routableID"))
        #expect(
            surface.code.contains(".selectionDisabled()")
                && surface.code.contains("hit.isInstalled ? ") == false,
            "selection is gated on installed-ness rather than on the projection's routability"
        )
    }

    // MARK: - ps11's view half, DD-15 — no control that cannot answer

    @Test("The tap filter bar offers no inert control")
    func theTapFilterBarOffersNoInertControl() throws {
        let surface = try TapSearchSources.surface()
        let bar = try TapSearchSources.source(at: "cellar/Browse/CatalogFilterBar.swift")
        let browse = try TapSearchSources.browse()

        #expect(surface.code.contains("showsOutdatedChip: false"))
        #expect(surface.code.contains("showsCatalogPredicates: false"))
        #expect(surface.code.contains("outdatedOnly: .constant(false)"))
        for inert in ["\"Outdated\"", "\"Hide deprecated\"", "\"Hide disabled\""] {
            #expect(
                surface.raw.contains(inert) == false,
                "the tap surface renders \(inert), which its source can never answer"
            )
        }

        // Both parameters default, which is what keeps Browse's call site
        // byte-identical to its base revision (DD-15, DD-8).
        #expect(bar.code.contains("var showsOutdatedChip = true"))
        #expect(bar.code.contains("var showsCatalogPredicates = true"))
        #expect(bar.code.contains("if showsOutdatedChip, isInstalledFilterEnabled {"))
        #expect(bar.code.contains("if showsCatalogPredicates {"))
        let call = try TapSearchSources.callSite("CatalogFilterBar(", in: browse.code)
        #expect(call.contains("showsOutdatedChip") == false)
        #expect(call.contains("showsCatalogPredicates") == false)
        // Anchored: Browse really does still call the bar, so the absence above
        // is about arguments and not about a missing call.
        #expect(call.contains("isInstalledFilterEnabled: browse.isFilterEnabled"))
    }

    // MARK: - ps15, PS8's copy-ownership clause — the copy lives in the projection

    @Test("The surface copy lives in the projection, not in the view")
    func theSurfaceCopyLivesInTheProjectionNotTheView() throws {
        let projection = try TapSearchSources.projection()
        let surface = try TapSearchSources.surface()

        for copy in TapSearchSources.pinnedCopy {
            #expect(
                projection.raw.contains(copy),
                "the projection no longer supplies \(copy.debugDescription)"
            )
            #expect(
                surface.raw.contains(copy) == false,
                "the view composes \(copy.debugDescription) locally"
            )
        }
        // Round 3: the two withdrawn strings are produced by neither file, as
        // complete literals. Anchored on the surviving withheld sentence above,
        // so the absence is about these two strings and not about a scan that
        // read nothing.
        for source in [projection, surface] {
            for withdrawn in TapSearchSources.withdrawnCopy {
                #expect(
                    source.raw.contains(withdrawn) == false,
                    "\(source.name) still produces the withdrawn string \(withdrawn)"
                )
            }
        }

        // What the view renders instead: the values, never the sentences.
        #expect(surface.code.contains("hit.stateNote"))
        #expect(surface.code.contains("hit.collisionNote"))
        #expect(surface.code.contains("presentation.emptyStateCopy"))
        // …and it derives no empty-state reason of its own: it switches over
        // the projection's answer.
        #expect(surface.code.contains("TapSearchPresentation"))
        #expect(surface.code.contains("taps.state") || surface.code.contains("tapState: taps.state"))
        for local in ["case .brewAbsent", "case .loaded", "TapLoadState"] {
            #expect(
                surface.code.contains(local) == false,
                "the view re-derives the load state through \(local)"
            )
        }
    }

    /// PS8's round-3 clause: the **same** pill, not one that looks the same.
    ///
    /// The whole point of the extraction is that this can be asserted at all.
    /// While the pill was `PackageRow`'s own `private func`, "the same pill"
    /// was unrepresentable — Swift `private` is file-scoped — and the strongest
    /// available claim would have been that two files draw a chip with matching
    /// literals, which is exactly the drift II8 and PT5 forbid.
    @Test("Both search surfaces draw the one shared installed pill")
    func bothSearchSurfacesDrawTheOneSharedPill() throws {
        let surface = try TapSearchSources.surface()
        let row = try TapSearchSources.packageRow()
        let pill = try TapSearchSources.pill()

        // The component exists and owns the label, once.
        #expect(pill.code.contains("struct StatusPill: View"))
        #expect(pill.raw.contains("label: \"Installed\""))
        #expect(
            pill.code.components(separatedBy: "\"Installed\"").count == 2,
            "the pinned label is declared more than once inside the component itself"
        )

        // Both surfaces reach for that one constant.
        #expect(
            row.code.contains("StatusPill.installed"),
            "the catalog row no longer draws the shared pill"
        )
        #expect(
            surface.code.contains("StatusPill.installed"),
            "the tap row does not draw the shared pill"
        )
        // …and `PackageRow`'s private predecessor is gone, so there is no second
        // pill left for either surface to drift towards.
        #expect(row.code.contains("private func statusPill(") == false)

        // Neither presenting surface composes the label.
        for source in [surface, row] {
            #expect(
                source.raw.contains("\"Installed\"") == false,
                "\(source.name) composes the pill's label locally"
            )
        }
        // The tap row draws it on installed-ness alone — both installed states,
        // which is why it reads the hit's fact rather than matching one case.
        #expect(surface.code.contains("if hit.isInstalled {"))
        // …and it sits in the title line, right after the kind chip, exactly
        // where the catalog row puts it.
        let tapMark = try #require(surface.code.range(of: "StatusPill.installed"))
        let tapKind = try #require(surface.code.range(of: "KindTag(kind:"))
        #expect(tapKind.upperBound < tapMark.lowerBound)
        let rowMark = try #require(row.code.range(of: "StatusPill.installed"))
        let rowKind = try #require(row.code.range(of: "KindTag(kind:"))
        #expect(rowKind.upperBound < rowMark.lowerBound)

        // The zero-diff file is untouched by the extraction: the declaration
        // was in `PackageRow.swift` all along, which is the only reason this
        // extraction was available at all (DD-8, DD-18).
        let browse = try TapSearchSources.browse()
        #expect(browse.code.contains("StatusPill") == false)
        #expect(browse.code.contains("statusPill") == false)
    }

    /// PS8's round-4 clause: the **same** update pill, in the same place.
    ///
    /// Shaped deliberately unlike the row above it. `StatusPill` had to be
    /// extracted before "the same pill" was representable at all (DD-18);
    /// `UpdateTag` was already `internal`, already drawn by the Installed and
    /// Updates lists, and already took the version as a **value** — so round 4
    /// costs `PackageRow.swift` a zero-line diff, and the claim here is that the
    /// tap row *joined* an existing component rather than that one was built.
    ///
    /// One asymmetry is stated rather than papered over: `UpdateTag` is declared
    /// **inside** `PackageRow.swift`, so "the presenting surface composes no
    /// label" is provable for `TapSearchView.swift` and meaningless for
    /// `PackageRow.swift`, where the surface and the declaration are one file.
    /// The uniqueness of the declaration carries that half instead.
    @Test("Both search surfaces draw the one shared update pill")
    func bothSearchSurfacesDrawTheOneSharedUpdatePill() throws {
        let surface = try TapSearchSources.surface()
        let row = try TapSearchSources.packageRow()

        // One component, declared once in the whole tree.
        let declaring = try TapSearchSources.swiftSources()
            .filter { $0.code.contains("struct UpdateTag: View") }
        #expect(
            declaring.map(\.name) == ["PackageRow.swift"],
            "the update chip is declared in \(declaring.map(\.name)) rather than exactly once"
        )

        // Both surfaces reach for it, and both hand it the version as a value
        // rather than wording anything about it themselves.
        #expect(
            row.code.contains("UpdateTag(nextVersion:"),
            "the catalog row no longer draws the shared update pill"
        )
        #expect(
            surface.code.contains("UpdateTag(nextVersion:"),
            "the tap row does not draw the shared update pill"
        )

        // The tap row gates it on the offered version's presence **alone** — the
        // projection already decided, and installed-ness is the other pill's
        // question.
        #expect(surface.code.contains("if let next = hit.nextVersion {"))
        #expect(
            surface.code.contains("UpdateTag(nextVersion: next)"),
            "the tap row passes something other than the projection's offered version"
        )
        for forbidden in ["isOutdated", "catalogVersion", "installed.package("] {
            #expect(
                surface.code.contains(forbidden) == false,
                "the view re-derives the offered version through \(forbidden)"
            )
        }

        // …and it sits **after** the installed pill, exactly where the catalog
        // row puts it, so the two rows read in the same order.
        let tapInstalled = try #require(surface.code.range(of: "StatusPill.installed"))
        let tapUpdate = try #require(surface.code.range(of: "UpdateTag(nextVersion:"))
        #expect(tapInstalled.upperBound < tapUpdate.lowerBound)
        let rowInstalled = try #require(row.code.range(of: "StatusPill.installed"))
        let rowUpdate = try #require(row.code.range(of: "UpdateTag(nextVersion:"))
        #expect(rowInstalled.upperBound < rowUpdate.lowerBound)

        // The tap surface composes no update wording of its own: the pill's copy
        // is the component's, and the component is not in this file.
        for local in ["\"UPDATE\"", "\"Update\"", "\"Update available"] {
            #expect(
                surface.raw.contains(local) == false,
                "the tap surface composes the update pill's copy locally: \(local)"
            )
        }
        // Anchored, so the absence above is about this file rather than about a
        // scan that read nothing: the label really does live with the component.
        #expect(row.raw.contains("Text(\"UPDATE\")"))
        #expect(row.code.contains("struct UpdateTag: View"))

        // The zero-diff file is untouched for the third round running.
        let browse = try TapSearchSources.browse()
        #expect(browse.code.contains("UpdateTag") == false)
        #expect(browse.code.contains("nextVersion") == false)
    }

    // MARK: - ps15, PM10 — no trust gate, no badge, no control

    @Test("The tap search surface composes no trust gate and no badge")
    func theTapSearchSurfaceComposesNoTrustGateAndNoBadge() throws {
        // PS8 sc15 names both the projection and the surface: neither may read
        // or present tap trust. Browse is byte-identical to main and has its
        // own scan, so it is not one of the two.
        let projection = try TapSearchSources.projection()
        let surface = try TapSearchSources.surface()

        for source in [projection, surface] {
            for forbidden in [
                "TrustGrantStore", "TrustGrantState", "TapProjection.trust(", "TapCommand",
                "\"Untrusted\"", "\"Trust", "grantsIndividually", "grantMarker"
            ] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) reads or presents tap trust through \(forbidden)"
                )
            }
        }

        // Nothing about trust reaches the surface at all, in either
        // granularity — the prohibition is the whole surface's, not one
        // symbol's (PM10). The projection is exempt from this whole-file sweep
        // only because it carries TM5's pinned copy "…while this tap is
        // untrusted."; every trust identifier is still forbidden in it above.
        #expect(
            surface.code.lowercased().contains("trust") == false,
            "\(surface.name) still names trust in code"
        )

        // The mutation affordances are offered unconditionally, through the
        // shared menu, over an entry carrying the projection's installed record
        // and **never** a catalog one (PS8 round 5, DD-20; PD6).
        #expect(surface.code.contains("MutationMenu(center:"))
        #expect(surface.code.contains("PackageEntry(installed: hit.installed, catalog: nil"))
        #expect(surface.code.contains("id: hit.mutationTarget"))
        // …and no verb, argv or target is re-implemented here.
        for forbidden in ["MutationCommand", "PackageTarget(", "submit(", "FormulaID", "CaskID"] {
            #expect(surface.code.contains(forbidden) == false, "the row builds its own \(forbidden)")
        }
        // The shared menu really is the surface that renders Install, so
        // matching it proves something.
        let menu = try TapSearchSources.source(at: "cellar/Activity/MutationMenu.swift")
        #expect(menu.code.contains("action(\"Install\", .install(target))"))
        #expect(menu.code.contains("Copy install command"))
    }

    // MARK: - ps18 (round 5), DD-20 — the installed record reaches the menu

    /// PS8 round 5: an installed tap row must offer the verbs the Installed and
    /// catalog surfaces offer the same package.
    ///
    /// The defect this pins was a *composition* one, not a missing verb: the row
    /// handed the shared menu an entry built with `installed: nil`, so the
    /// menu's own installed branch could never be taken however installed the
    /// package was. The claim is therefore about what the row hands over and
    /// about what it still refuses to declare for itself.
    @Test("An installed tap row reaches the mutation menu with its record")
    func anInstalledTapRowReachesTheMutationMenuWithItsRecord() throws {
        let surface = try TapSearchSources.surface()
        let menu = try TapSearchSources.source(at: "cellar/Activity/MutationMenu.swift")

        // What the row hands over: the projection's resolved record, no catalog
        // record, the bare target.
        let entry = try TapSearchSources.callSite("PackageEntry(", in: surface.code)
        #expect(entry.contains("installed: hit.installed"))
        #expect(entry.contains("catalog: nil"))
        #expect(entry.contains("id: hit.mutationTarget"))
        // The literal the defect lived in, gone from the whole file rather than
        // merely from that call.
        #expect(
            surface.code.contains("installed: nil") == false,
            "the tap row still builds an entry with no installed record"
        )
        // …and it neither looks a record up nor re-keys one: the tap-aware
        // resolution is the projection's, where a `unit` test can reach it.
        //
        // `installed.inventory` is deliberately **not** forbidden — the view
        // hands that whole inventory *to* the projection (`:109`), which is the
        // shipped composition and the opposite of resolving a record here. What
        // is forbidden is a lookup: a `package(_:)` call or the handoff key.
        for forbidden in [
            "installed.package(", "inventory.package(", "installedHandoff", ".installed?."
        ] {
            #expect(
                surface.code.contains(forbidden) == false,
                "the tap row resolves the installed record itself through \(forbidden)"
            )
        }

        // The shared menu really is what branches on that record, so handing it
        // over proves something: it reads `entry.isInstalled` and declares every
        // installed-time verb exactly once.
        #expect(menu.code.contains("if entry.isInstalled {"))
        for verb in [
            "action(\"Reinstall\", .reinstall(target))",
            "action(\"Uninstall…\", .uninstall(target))",
            "action(\"Uninstall and Zap…\", .zap(cask))",
            "action(\"Upgrade\", .upgrade(target))",
            "action(\"Pin\", .pin(formula))",
            "action(\"Unpin\", .unpin(formula))"
        ] {
            #expect(
                menu.code.components(separatedBy: verb).count == 2,
                "the shared menu does not declare \(verb) exactly once"
            )
        }

        // …and none of those verbs, nor the machinery behind them, is declared
        // by the presenting surface: the row supplies a record and a target, and
        // decides nothing (PS8, PM10).
        for local in [
            "\"Reinstall\"", "\"Uninstall", "\"Upgrade\"", "\"Pin\"", "\"Unpin\"", "\"Zap",
            "MutationCommand", "PackageTarget(", "submit(", "FormulaID", "CaskID",
            "isOutdated", "isPinned"
        ] {
            #expect(
                surface.raw.contains(local) == false,
                "the tap row re-implements the shared menu's \(local)"
            )
        }

        // The zero-diff file is untouched for the fourth round running.
        let browse = try TapSearchSources.browse()
        #expect(browse.code.contains("TapSearchHit") == false)
        #expect(browse.code.contains("hit.installed") == false)
    }

    // MARK: - ps16 — neither tap-search file reaches the process layer

    @Test("Neither tap search file reaches the process layer")
    func neitherTapSearchFileReachesTheProcessLayer() throws {
        let scanned = [try TapSearchSources.projection(), try TapSearchSources.surface()]

        for source in scanned {
            for forbidden in [
                "Process", "BrewProcess", "ProcessSpec", "launcher", "Launcher", "brewPath", "/bin/"
            ] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) reaches the process layer through \(forbidden)"
                )
            }
            // …and presenting the surface starts nothing: no refresh, no task,
            // no await anywhere in the render path (DD-12).
            for forbidden in ["refresh", ".task", "Task {", "await ", "async "] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) starts work when the surface is presented: \(forbidden)"
                )
            }
        }
    }
}

/// The sources this suite scans, read off disk relative to this file rather than
/// to a working directory the runner does not promise.
///
/// One of them lives in `Packages/CellarCore`, which is why this scanner exists
/// beside `AppSecuritySources` rather than reusing its app-target enumeration —
/// it borrows that type's comment stripper, so the two agree on what "code" is.
nonisolated enum TapSearchSources {
    struct Source: Sendable {
        let name: String
        /// The file with `//` and `/* */` comments removed.
        let code: String
        /// The file exactly as it is on disk, for copy compared byte-for-byte.
        let raw: String
    }

    static let paths = [
        "Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift",
        "cellar/Browse/TapSearchView.swift",
        "cellar/Browse/BrowseView.swift"
    ]

    /// The four sentences the projection owns and the view may never compose:
    /// the two a hit can carry, plus the two empty states the scope change
    /// added.
    static let pinnedCopy = [
        "Installed. Homebrew withholds its tap while this tap is untrusted.",
        "Also in the catalog. Homebrew installs the catalog package.",
        "No packages from your taps.",
        "Your taps publish nothing yet."
    ]

    /// The two strings round 3 **withdrew** from this surface, quoted as
    /// complete Swift literals.
    ///
    /// The quotes are load-bearing, not decoration: `Installed.` is a prefix of
    /// the withheld sentence, so a bare substring search would report the
    /// projection guilty for carrying the copy it is *required* to carry. A
    /// whole literal is the only honest shape for this absence.
    ///
    /// Both survive untouched in `TapProjection.statusExplanation`, which serves
    /// the tap-detail rows TM5 governs — this claim is about these two files.
    static let withdrawnCopy = [
        "\"Installed.\"",
        "\"Not installed.\""
    ]

    /// Where the installed mark's label is declared — once, for both surfaces.
    static func pill() throws -> Source {
        try source(at: "cellar/Browse/StatusPill.swift")
    }

    static func packageRow() throws -> Source {
        try source(at: "cellar/Browse/PackageRow.swift")
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static func load() throws -> [Source] {
        try paths.map { try source(at: $0) }
    }

    /// Every Swift file the app target and the tap projection are built from.
    ///
    /// A tree walk rather than a list, because the claim it serves is that a
    /// deleted type is named **nowhere** — and a list would only prove it is
    /// unnamed in the places someone remembered to list.
    static func swiftSources() throws -> [Source] {
        try ["cellar", "cellarTests", "Packages/CellarCore/Sources"].flatMap { root -> [Source] in
            let base = repositoryRoot.appendingPathComponent(root)
            guard let walk = FileManager.default.enumerator(atPath: base.path) else { return [] }
            return try walk.compactMap { entry -> Source? in
                guard let relative = entry as? String, relative.hasSuffix(".swift") else { return nil }
                // This suite names the deleted type in its own assertions.
                guard relative.hasSuffix("TapSearchCompositionTests.swift") == false else { return nil }
                return try source(at: "\(root)/\(relative)")
            }
        }
    }

    /// The `[...]` literal assigned to the named `Set<AppSection>`, or `nil`.
    ///
    /// The shipped `AppSectionPlacementTests` reader, restated here because
    /// that one is `private` to its own suite.
    static func setLiteral(named name: String, in code: String) -> String? {
        guard let declaration = code.range(of: "let \(name): Set<AppSection> = [") else {
            return nil
        }
        guard let close = code[declaration.upperBound...].firstIndex(of: "]") else { return nil }
        return String(code[declaration.upperBound..<close])
    }

    static func source(at relative: String) throws -> Source {
        let raw = try String(
            contentsOf: repositoryRoot.appendingPathComponent(relative),
            encoding: .utf8
        )
        return Source(
            name: URL(fileURLWithPath: relative).lastPathComponent,
            code: AppSecuritySources.stripComments(from: raw),
            raw: raw
        )
    }

    static func projection() throws -> Source {
        try source(at: "Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift")
    }

    static func surface() throws -> Source {
        try source(at: "cellar/Browse/TapSearchView.swift")
    }

    static func browse() throws -> Source {
        try source(at: "cellar/Browse/BrowseView.swift")
    }

    /// The text of one call, from its opening parenthesis to the matching close.
    ///
    /// A claim about a call site has to be scoped to that call: `taps: taps`
    /// appears at several call sites in `ContentView`, and finding it anywhere
    /// in the file would prove nothing about this one.
    static func callSite(_ opening: String, in code: String) throws -> String {
        let start = try #require(code.range(of: opening), "no call to \(opening)")
        var depth = 0
        var index = code.index(before: start.upperBound)
        while index < code.endIndex {
            if code[index] == "(" { depth += 1 }
            if code[index] == ")" {
                depth -= 1
                if depth == 0 { return String(code[start.lowerBound...index]) }
            }
            index = code.index(after: index)
        }
        Issue.record("the call to \(opening) never closes")
        return ""
    }

    /// The positive anchor every absence runs behind: without it a renamed file
    /// would make every prohibition below pass while reading nothing at all.
    static func assertAnchored(_ sources: [Source]) throws {
        #expect(sources.count == paths.count)
        let projection = try projection()
        #expect(
            projection.code.contains("public struct TapPackageSearch"),
            "the projection scan read a file that is not the projection"
        )
        let surface = try surface()
        #expect(
            surface.code.contains("struct TapSearchView: View"),
            "the surface scan read a file that is not the tap search surface"
        )
        let browse = try browse()
        #expect(
            browse.code.contains("struct BrowseView: View"),
            "the Browse scan read a file that is not the Browse list"
        )
    }
}
