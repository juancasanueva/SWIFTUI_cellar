//
//  ReceiptDetailCompositionTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import Testing

@testable import cellar

/// The claims about the receipt-backed detail pane that only its **composition**
/// can make (installed-inventory II15 sc2, sc9–sc12).
///
/// Asserted structurally over the two sources the surface is made of, in the
/// shipped `AppSecuritySources` idiom: a claim that a surface does *not* reach
/// the process layer, does *not* offer a trust control and does *not* compose a
/// marker of its own cannot be made by rendering it, because every one of them
/// is an absence. Comments are stripped first, so a prohibition described in a
/// doc comment is never mistaken for one violated in code.
@Suite("Receipt detail composition", .timeLimit(.minutes(1)))
struct ReceiptDetailCompositionTests {

    // MARK: - II15 sc2 — no process layer, and nothing to inject

    @Test("Composing the reduced detail reaches no process layer")
    func composingTheReducedDetailReachesNoProcessLayer() throws {
        let sources = try ReceiptDetailSources.load()
        try ReceiptDetailSources.assertAnchored(sources)

        for source in sources {
            for forbidden in [
                "Process",
                "BrewProcess",
                "ProcessSpec",
                "launcher",
                "Launcher",
                "brewPath",
                "/bin/"
            ] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) reaches the process layer through \(forbidden)"
                )
            }
            // …and presenting the detail triggers no acquisition either: no
            // refresh, no task, no await anywhere in the render path (DD-10).
            for forbidden in ["refresh", ".task", "Task {", "await ", "async "] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) starts work when the detail is presented: \(forbidden)"
                )
            }
        }

        // The composition takes exactly one installed record. There is no
        // second parameter, so there is no launcher dependency to inject even
        // in principle — which is why a fake-launcher test would assert nothing
        // here.
        let projection = try ReceiptDetailSources.projection(in: sources)
        #expect(projection.code.contains("public init(_ package: InstalledPackage)"))
        // Five, not four: `NpmState` joined `Fact`, `FormulaState`, `CaskState`
        // and the projection itself when npm became a second source. The number
        // is deliberately exact rather than a lower bound — the guard exists so
        // a *second* way to construct the projection cannot arrive unnoticed,
        // and the line below states the shape that would actually be dangerous.
        #expect(
            projection.code.components(separatedBy: "public init(").count == 6,
            "the projection grew an initializer beyond the five value types' own"
        )
        #expect(projection.code.contains("public init(_ package: InstalledPackage, ") == false)
        #expect(InstalledDetailProjection(Self.receipt()).orderedFacts.isEmpty == false)
    }

    // MARK: - II15 sc10, PD8, PT5 — the marker comes from the one projection

    @Test("The receipt pane resolves the marker through the one projection")
    func theReceiptPaneResolvesTheMarkerThroughTheOneProjection() throws {
        let pane = try ReceiptDetailSources.pane()

        #expect(
            pane.code.contains("TapProjection.grantsIndividually("),
            "the pane does not resolve the marker by exact identity"
        )
        #expect(
            pane.code.contains("TapProjection.grantMarker"),
            "the pane does not take the marker copy from the projection that owns it"
        )
        // Not even in a comment: the copy exists in exactly one place in the
        // tree, and this file is not it.
        #expect(pane.raw.contains("\"Trusted individually\"") == false)
        #expect(pane.raw.contains("trusted individually") == false)
        // The copy the pane defers to is the one the projection publishes.
        #expect(TapProjection.grantMarker == "Trusted individually")
    }

    // MARK: - II15 sc7 second THEN, sc10, PD8, PT3 — resolved only under the guard

    /// The presentation half of sc7's "and it carries no per-package grant
    /// marker": a receipt whose tap Homebrew withholds yields neither the origin
    /// fact nor a marker, because both come out of the **same** `if let` and
    /// there is no second path to either.
    ///
    /// This is the class that can say it. The value cannot: PD8 forbids the
    /// projection a marker member, so its half of the THEN is the absence
    /// `InstalledDetailProjectionTests.aWithheldTapCarriesNoGrantMarkerEither`
    /// asserts. What is left is a claim about *where the call site sits*, and a
    /// claim about a call site is a claim about the source.
    ///
    /// It also closes the binding this file's sc10 case left open: a refactor
    /// that resolved the marker and then dropped it instead of handing it to the
    /// origin fact would satisfy "mentions `grantMarker`" and fail here.
    @Test("The receipt pane resolves the marker only under the tap guard")
    func theReceiptPaneResolvesTheMarkerOnlyUnderTheTapGuard() throws {
        let pane = try ReceiptDetailSources.pane()
        let lines = pane.code.components(separatedBy: "\n")

        let tapGuard = try #require(
            lines.firstIndex {
                $0.contains("if let tap = snapshot.tap, let origin = detail.tapOfOrigin")
            },
            "the pane's one tap guard moved, so the containment below anchors on nothing"
        )
        let callSites = lines.indices.filter { lines[$0].contains("marker(for:") }
        #expect(callSites.count == 1, "the marker is resolved in \(callSites.count) places, not one")
        let callSite = try #require(callSites.first)

        // Lexically inside that guard's block: walking from the guard, brace
        // depth returns to zero only after the call. A marker resolved above the
        // guard, or after it closed, fails here — which is the only way a
        // withheld tap could produce one.
        var depth = 0
        var closing: Int?
        for index in tapGuard..<lines.count {
            depth += lines[index].filter { $0 == "{" }.count
            depth -= lines[index].filter { $0 == "}" }.count
            if depth == 0 {
                closing = index
                break
            }
        }
        let closes = try #require(closing, "the tap guard's block never closes")
        #expect(callSite > tapGuard, "the marker is resolved before the tap is unwrapped")
        #expect(callSite < closes, "the marker is resolved after the tap guard closed")

        // …and no absent tap can reach the resolver even in principle: it takes
        // a non-optional tap, so `snapshot.tap` arrives unwrapped or not at all.
        #expect(pane.code.contains("publishedBy tap: String)"))
        #expect(pane.code.contains("publishedBy tap: String?") == false)

        // The resolved marker is bound to the origin fact rather than resolved
        // and discarded: it travels as that fact's note, beside the tap it is
        // a fact about.
        #expect(
            lines[callSite]
                .contains("receiptFact(origin, note: marker(for: snapshot.id, publishedBy: tap))"),
            "the resolved marker no longer reaches the origin fact as its note"
        )
    }

    // MARK: - II15 sc11, PT6, PT7 — no trust control, asserted as an absence

    @Test("The receipt pane offers no trust control")
    func theReceiptPaneOffersNoTrustControl() throws {
        let pane = try ReceiptDetailSources.pane()

        #expect(pane.code.contains("\"Trust") == false, "the pane offers a trust control")
        #expect(pane.code.contains("TapCommand") == false, "the pane can submit a tap trust change")
        for forbidden in ["untrusted", "unverified", "unsigned", "unnotarized", "notariz"] {
            #expect(
                pane.raw.lowercased().contains(forbidden) == false,
                "the pane states or implies \(forbidden)"
            )
        }
        // Nothing on it grants or revokes anything at all.
        for forbidden in ["grant(", "revoke", "submit(.trust", "TrustGrantCommand"] {
            #expect(pane.code.contains(forbidden) == false, "the pane alters trust via \(forbidden)")
        }
    }

    // MARK: - II15 sc11 (round 8), DD-24 — the catalog pane's Actions section

    /// The maintainer's 2026-08-25 instruction, asserted where it can be:
    /// this pane shows the **same** Actions section the catalog pane shows, at
    /// the foot of the pane, and its header's primary slot is empty.
    ///
    /// "The same section" is a claim about **one declaration reached from two
    /// places**, which no rendering test can make — a second copy would render
    /// identically and pass. So the pane is pinned to the call, the call is
    /// pinned with its closing parenthesis, and every verb literal is asserted
    /// **absent here and present exactly once there**, which is what makes the
    /// absence non-vacuous.
    @Test("The receipt pane offers the catalog pane's Actions section")
    func theReceiptPaneOffersTheCatalogPanesActionsSection() throws {
        let pane = try ReceiptDetailSources.pane()
        let detail = try ReceiptDetailSources.source(at: "cellar/Browse/PackageDetailView.swift")
        let row = try ReceiptDetailSources.source(at: "cellar/Installed/InstalledRow.swift")

        // 1. The pane calls the one shared builder with its own entry. The
        //    terminator is part of the pin: a scan for the bare name would pass
        //    for a differently-shaped call, including one that rebuilt the entry.
        #expect(
            pane.code.contains("actionsSection(for: receiptEntry(for: snapshot))"),
            "the pane does not reach the catalog pane's Actions section"
        )
        #expect(pane.code.contains("catalog: nil"))
        // 2. It sits last, after the pane's own footer content, where the
        //    catalog pane places it.
        let footer = try #require(pane.code.range(of: "receiptFooter\n"))
        let actions = try #require(
            pane.code.range(of: "actionsSection(for: receiptEntry(for: snapshot))")
        )
        #expect(
            footer.upperBound < actions.lowerBound,
            "the Actions section is not the last block of the pane"
        )
        // 3. The header's primary slot is empty: one pane, one place to act.
        #expect(pane.code.contains("EmptyView()"), "the header slot is not empty")
        #expect(
            pane.code.contains("MutationMenu(") == false,
            "the pane still hangs the row's menu in its header"
        )
        // 4. …and the menu is untouched where it belongs. Without this, the
        //    absence above would also pass if the shared menu had been deleted.
        #expect(
            row.code.contains("MutationMenu(center:"),
            "the installed row lost the shared menu, so the pane's absence proves nothing"
        )
        // 5. No verb, argv, target or section copy is composed here.
        for local in ["MutationCommand", "PackageTarget(", "submit(", "SectionHeader(\"Actions\")"] {
            #expect(pane.code.contains(local) == false, "the pane builds its own \(local)")
        }
        for verb in ReceiptDetailSources.verbLiterals {
            #expect(
                pane.code.contains(verb) == false,
                "the pane words the verb \(verb) locally instead of sharing the section"
            )
        }

        // 6. Non-vacuous: the section really is where those verbs live, exactly
        //    once each, with the command line, its copy button and the shared
        //    unavailable guidance.
        let section = try ReceiptDetailSources.actionsSection(in: detail)
        for verb in ReceiptDetailSources.verbLiterals {
            #expect(
                section.components(separatedBy: verb).count == 2,
                "the shared Actions section does not declare \(verb) exactly once"
            )
        }
        #expect(section.contains("SectionHeader(\"Actions\")"))
        #expect(section.contains("CopyCommandButton(text: primaryCommand("))
        #expect(section.contains("operations.unavailableGuidance"))

        // 7. It is built from the entry both panes can supply — never from a
        //    catalog record, which neither of them has and PD6 forbids either
        //    of them to synthesize.
        #expect(detail.code.contains("func actionsSection(for entry: PackageEntry) -> some View"))
        #expect(
            detail.code.contains("private func actionsSection") == false,
            "the section is file-scoped again, so no extension can reach it"
        )
        #expect(section.contains("CatalogPackage") == false)

        // 8. PT7, PM10: the shared section carries no trust control, so reusing
        //    it adds none to this pane.
        for trust in ["Trust", "trust", "Grant", "grant"] {
            #expect(
                section.contains(trust) == false,
                "the shared Actions section composes a trust presentation: \(trust)"
            )
        }
    }

    // MARK: - II15 sc12, R2, DD-12 — the copy stays a claim about the catalog

    /// Anchored on the **pane's own file** and nothing else. The same sentence
    /// also survives in `PackageDetailView.swift` as the fallback for a package
    /// with no installed record at all — a different code path — and an anchor
    /// that read that file was satisfied by the wrong line: rewording the
    /// fallback would have failed this test while the pane stayed correct, and
    /// deleting the pane's footer would not have failed it (m10 archive S8).
    @Test("The scoped catalog-miss copy is unchanged")
    func theScopedCatalogMissCopyIsUnchanged() throws {
        let pane = try ReceiptDetailSources.pane()

        // Byte-for-byte, apostrophe included, against the sentence as it ships
        // in the pane — never against a copy retyped in this test.
        let sentence = "This installed package is not in Cellar\u{2019}s core/cask catalog."
        #expect(sentence.unicodeScalars.contains("\u{2019}"))
        #expect(
            pane.raw.components(separatedBy: sentence).count == 2,
            "the pane's footer is not exactly one occurrence of the shipped sentence"
        )
        #expect(
            pane.raw.contains("Cellar's core/cask") == false,
            "the pane straightened the typographic apostrophe"
        )
        // …and the surface makes no claim about where the package came from.
        #expect(pane.raw.lowercased().contains("third-party") == false)
        #expect(pane.raw.lowercased().contains("third party") == false)
    }

    // MARK: - II15 sc9 — the install date is the receipt's, or absent

    /// The surface reports the date the projection carries and derives nothing
    /// from a timestamp itself: no epoch arithmetic, no `Date(` construction,
    /// no formatter of its own beyond the locale-aware `formatted` call on the
    /// value it was handed. A receipt with no timestamp yields no row.
    @Test("The receipt pane reports the install date from the projection, never from a timestamp")
    func theReceiptPaneReportsTheInstallDateFromTheProjection() throws {
        let sources = try ReceiptDetailSources.load()
        try ReceiptDetailSources.assertAnchored(sources)

        let pane = try ReceiptDetailSources.source(at: "cellar/Browse/PackageDetailView+Receipt.swift")
        #expect(pane.code.contains("\"Installed on\""), "the pane has no install-date row")
        #expect(
            pane.code.contains("if let installedAt = detail.installedAt"),
            "the row is not guarded on the projection's own optional"
        )

        for source in sources {
            for forbidden in ["timeIntervalSince1970", "1970", "Date(", "DateFormatter", "epoch"] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) derives a value from a timestamp: \(forbidden)"
                )
            }
        }

        // The value is the keg's own, and its absence is preserved as absence.
        let dated = InstalledDetailProjection(Self.receipt())
        #expect(dated.installedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(dated.orderedFacts.contains { $0.value.contains("1970") } == false)
        let undated = InstalledDetailProjection(Self.receipt(installedAt: nil))
        #expect(undated.installedAt == nil)
    }

    // MARK: - Arrangement

    /// A receipt with an install timestamp to report, so the absence of an
    /// install-date fact above is a rule rather than missing input.
    private static func receipt(
        installedAt: Date? = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> InstalledPackage {
        let keg = InstalledKeg(
            version: "1.4.0",
            installedAt: installedAt,
            installedOnRequest: true
        )
        return InstalledPackage(
            kind: .formula,
            name: "widget",
            displayName: "widget",
            desc: "A widget for acme things",
            homepage: URL(string: "https://acme.example/widget"),
            tap: "acme/tools",
            catalogVersion: "1.4.0",
            kegs: [keg],
            primaryKeg: keg,
            snapshotOutdated: false,
            isPinned: false,
            pinnedVersion: nil,
            declaresAutoUpdates: nil,
            linkedKeg: "1.4.0"
        )
    }
}

/// The two sources the receipt-backed surface is made of, read off disk relative
/// to this file rather than to a working directory the runner does not promise.
///
/// One of them lives in `Packages/CellarCore`, which is why this scanner exists
/// beside `AppSecuritySources` rather than reusing its app-target enumeration —
/// it borrows that type's comment stripper, so the two agree on what "code" is.
nonisolated enum ReceiptDetailSources {
    struct Source: Sendable {
        let name: String
        /// The file with `//` and `/* */` comments removed.
        let code: String
        /// The file exactly as it is on disk, for copy compared byte-for-byte.
        let raw: String
    }

    static let paths = [
        "Packages/CellarCore/Sources/BrewClient/InstalledDetailProjection.swift",
        "cellar/Browse/PackageDetailView+Receipt.swift"
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

    /// Every verb label the shared Actions section declares, as complete Swift
    /// literals.
    ///
    /// The quotes are load-bearing, not decoration: `Uninstall` is a prefix of
    /// `Uninstall and Zap…`, and `Install` is a substring of `Installed as`, so
    /// a bare substring search would report both a false match and a false
    /// duplicate. A whole literal is the only honest shape for these claims.
    static let verbLiterals = [
        "\"Upgrade\"",
        "\"Reinstall\"",
        "\"Pin version\"",
        "\"Unpin\"",
        "\"Uninstall…\"",
        "\"Uninstall and Zap…\"",
        "\"Install\""
    ]

    /// The shared Actions section's own body, extracted by brace matching from
    /// its declaration.
    ///
    /// Extracted rather than scanned whole-file, so a claim about "the section"
    /// is a claim about the section: `PackageDetailView.swift` legitimately
    /// carries a trust marker and a catalog type elsewhere, and a whole-file
    /// sweep would report the section guilty of both.
    static func actionsSection(in detail: Source) throws -> String {
        let lines = detail.code.components(separatedBy: "\n")
        let start = try #require(
            lines.firstIndex { $0.contains("func actionsSection(for entry: PackageEntry)") },
            "the shared Actions section moved, so every claim about it anchors on nothing"
        )
        var depth = 0
        var body: [String] = []
        for index in start..<lines.count {
            body.append(lines[index])
            depth += lines[index].filter { $0 == "{" }.count
            depth -= lines[index].filter { $0 == "}" }.count
            if depth == 0, index > start { break }
        }
        #expect(depth == 0, "the shared Actions section's block never closes")
        #expect(body.count > 20, "the extracted Actions section is too small to be it")
        return body.joined(separator: "\n")
    }

    static func pane() throws -> Source {
        try source(at: "cellar/Browse/PackageDetailView+Receipt.swift")
    }

    static func projection(in sources: [Source]) throws -> Source {
        try #require(sources.first { $0.name == "InstalledDetailProjection.swift" })
    }

    /// The positive anchor every absence runs behind: without it a renamed file
    /// would make every prohibition below pass while reading nothing at all.
    static func assertAnchored(_ sources: [Source]) throws {
        #expect(sources.count == paths.count)
        let projection = try projection(in: sources)
        #expect(
            projection.code.contains("public struct InstalledDetailProjection"),
            "the projection scan read a file that is not the projection"
        )
        let pane = try #require(sources.first { $0.name == "PackageDetailView+Receipt.swift" })
        #expect(
            pane.code.contains("func uncatalogedContent(for snapshot: InstalledPackage)"),
            "the pane scan read a file that does not supply the receipt-backed detail"
        )
    }
}
