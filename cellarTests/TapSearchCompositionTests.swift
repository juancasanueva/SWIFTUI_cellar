//
//  TapSearchCompositionTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import Testing

@testable import cellar

/// The claims about the Browse tap section that only its **composition** can
/// make (`package-search` PS8 sc13–sc16).
///
/// Asserted structurally over the sources the surface is made of, in the shipped
/// `AppSecuritySources` / `ReceiptDetailSources` idiom: every one of them is
/// either an absence — no trust gate, no trust badge, no process layer, no local
/// copy, no new routing branch — or a claim about *where* a value is composed,
/// and neither can be made by rendering a view. Comments are stripped first, so
/// a prohibition described in a doc comment is never mistaken for one violated
/// in code.
@Suite("Tap search composition", .timeLimit(.minutes(1)))
struct TapSearchCompositionTests {

    // MARK: - ps13 — the section is composed from the resident store

    @Test("Browse composes the tap section from the resident store")
    func browseComposesTheTapSectionFromTheResidentStore() throws {
        let sources = try TapSearchSources.load()
        try TapSearchSources.assertAnchored(sources)
        let browse = try TapSearchSources.browse()
        let root = try TapSearchSources.source(at: "cellar/ContentView.swift")

        // The store the view already holds, passed as a `let` rather than
        // acquired: there is no new store and no new refresh.
        #expect(browse.code.contains("let taps: TapStore"))
        #expect(browse.code.contains("TapPackageSearch("))
        #expect(browse.code.contains("TapPackageSearch.isSectionVisible("))
        // …and the catalog reaches it as the membership predicate only.
        #expect(browse.code.contains("isInCatalog:"))
        #expect(browse.code.contains("catalog.package("))

        // One argument at the composition root, inside the `BrowseView(…)` call
        // itself rather than anywhere in the file.
        let call = try TapSearchSources.callSite("BrowseView(", in: root.code)
        #expect(call.contains("taps: taps"), "ContentView does not hand BrowseView the tap store")
    }

    @Test("The tap section is titled and positioned after the catalog results")
    func theTapSectionIsTitledAndPositionedLast() throws {
        let browse = try TapSearchSources.browse()
        let surface = try TapSearchSources.surface()

        // The title is the surface's own copy and is byte-exact.
        #expect(surface.raw.contains("\"From your taps\""))

        // One `List`, catalog rows first, the section after them.
        #expect(browse.code.contains("List(selection: $selection)"))
        #expect(
            browse.code.contains("List(rows, selection:") == false,
            "the flat list survived, so nothing can be positioned after it"
        )
        let rows = try #require(browse.code.range(of: "ForEach(rows)"))
        let tap = try #require(browse.code.range(of: "TapSearchSection("))
        #expect(rows.lowerBound < tap.lowerBound, "the tap section is composed above the catalog rows")
    }

    // MARK: - ps13, ps14, DD-4 — inert unless the identity is unambiguous

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
        // Nothing here re-derives the rule the projection owns.
        for forbidden in ["alsoInCatalog", "isInstalled", "== .notInstalled"] {
            #expect(
                surface.code.contains(forbidden) == false,
                "the view re-derives routability through \(forbidden)"
            )
        }
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
        // What the view renders instead: the values, never the sentences.
        #expect(surface.code.contains("hit.stateCopy"))
        #expect(surface.code.contains("hit.collisionNote"))
        // The section title is the one string the view owns — it is `Section`
        // copy, not hit copy — and it is byte-exact.
        #expect(surface.raw.contains("Section(\"From your taps\")"))
        #expect(projection.raw.contains("From your taps") == false)
    }

    // MARK: - ps15, PM10 — no trust gate, no badge, no control

    @Test("The Browse tap surface composes no trust gate and no badge")
    func theBrowseTapSurfaceComposesNoTrustGateAndNoBadge() throws {
        let scanned = [try TapSearchSources.browse(), try TapSearchSources.surface()]

        for source in scanned {
            for forbidden in [
                "TrustGrantStore", "TrustGrantState", "TapProjection.trust(", "TapCommand",
                "\"Untrusted\"", "\"Trust", "grantsIndividually", "grantMarker"
            ] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) reads or presents tap trust through \(forbidden)"
                )
            }
            // Nothing about trust reaches this surface at all, in either
            // granularity — the prohibition is the whole surface's, not one
            // symbol's (PM10).
            #expect(
                source.code.lowercased().contains("trust") == false,
                "\(source.name) still names trust in code"
            )
        }

        // The install affordance is offered unconditionally, through the shared
        // menu, over an entry with neither an installed nor a catalog record.
        let surface = try TapSearchSources.surface()
        #expect(surface.code.contains("MutationMenu(center:"))
        #expect(surface.code.contains("PackageEntry(installed: nil, catalog: nil"))
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

    // MARK: - ps14, DD-4 — the receipt detail, with no new routing branch

    @Test("The receipt detail is reached with no new routing branch")
    func theReceiptDetailIsReachedWithNoNewRoutingBranch() throws {
        let detail = try TapSearchSources.source(at: "cellar/Browse/PackageDetailView.swift")
        let root = try TapSearchSources.source(at: "cellar/ContentView.swift")
        let browse = try TapSearchSources.browse()

        // The detail gains nothing at all for this source.
        for forbidden in ["TapSearchHit", "TapPackageSearch", "TapSearchSection", "TapInventory"] {
            #expect(
                detail.code.contains(forbidden) == false,
                "PackageDetailView grew a branch for \(forbidden)"
            )
        }
        // Selection stays one identity space, so the shipped resolution order is
        // what an installed tap hit lands on.
        #expect(root.code.contains("@State private var selection: PackageID?"))
        #expect(browse.code.contains("@Binding var selection: PackageID?"))
        #expect(browse.code.contains("BrowseSelection") == false)
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
            // …and presenting the section starts nothing: no refresh, no task,
            // no await anywhere in the render path (DD-12).
            for forbidden in ["refresh", ".task", "Task {", "await ", "async "] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) starts work when the section is presented: \(forbidden)"
                )
            }
        }

        // Browse composes it synchronously too: the section adds no second
        // `.task` to the shipped one that loads cask artwork.
        let browse = try TapSearchSources.browse()
        #expect(
            browse.code.components(separatedBy: ".task {").count == 2,
            "the tap section added a task to the render path"
        )
        #expect(browse.code.contains("await TapPackageSearch") == false)
    }

    // MARK: - ps13, PS8's prompt clause, R5 — the shipped chrome is unchanged

    @Test("The search prompt still counts catalog records only")
    func theSearchPromptStillCountsCatalogRecordsOnly() throws {
        let browse = try TapSearchSources.browse()

        #expect(browse.raw.contains("prompt: \"Search \\(catalog.packageCount.formatted()) packages…\""))
        let prompt = try #require(
            browse.raw.components(separatedBy: "\n").first { $0.contains("prompt: \"Search") }
        )
        #expect(prompt.contains("tap") == false)
        #expect(prompt.contains("Hits") == false)
    }

    @Test("The empty state yields to tap hits")
    func theEmptyStateYieldsToTapHits() throws {
        let browse = try TapSearchSources.browse()

        // Both row sources guard the overlay, so a query matching only tap
        // packages shows the section rather than "no results".
        #expect(browse.code.contains("if rows.isEmpty, tapHits.isEmpty"))
        #expect(
            browse.code.contains("if rows.isEmpty {") == false,
            "the overlay still reads the catalog rows alone"
        )
        // No visibility is relaxed and no new copy is invented (DD-10, R5).
        #expect(browse.code.contains("private struct EmptyResults: View"))
        #expect(browse.code.contains("EmptyResults(query: catalog.query, isReady: catalog.isReady)"))
        let surface = try TapSearchSources.surface()
        #expect(surface.code.contains("EmptyResults") == false)
        #expect(surface.code.contains("ContentUnavailableView") == false)
    }

    @Test("Catalog row selection is unchanged")
    func catalogRowSelectionIsUnchanged() throws {
        let browse = try TapSearchSources.browse()

        #expect(browse.code.contains(".tag(entry.id)"))
        #expect(browse.code.contains(".themedListSelection(isSelected: selection == entry.id)"))
        #expect(browse.code.contains("PackageRow("))
        #expect(browse.code.contains("MutationMenu(center: operations, entry: entry)"))
        // The catalog rows keep their bare `ForEach`: a header nobody asked for
        // would push every existing row down (DD-8).
        #expect(browse.code.contains("Section(\"Catalog\")") == false)
        #expect(browse.code.contains("Section(\"Packages\")") == false)
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

    /// The four sentences the projection owns and the view may never compose.
    static let pinnedCopy = [
        "Installed.",
        "Installed. Homebrew withholds its tap while this tap is untrusted.",
        "Not installed.",
        "Also in the catalog. Homebrew installs the catalog package."
    ]

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static func load() throws -> [Source] {
        try paths.map { try source(at: $0) }
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
