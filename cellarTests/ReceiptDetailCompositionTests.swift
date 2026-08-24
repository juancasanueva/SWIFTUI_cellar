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
        #expect(
            projection.code.components(separatedBy: "public init(").count == 5,
            "the projection grew an initializer beyond the four value types' own"
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

    // MARK: - II15 sc11, DD-8 — the row's verbs, from the row's own surface

    @Test("The receipt pane offers the same verbs as the installed row")
    func theReceiptPaneOffersTheSameVerbsAsTheRow() throws {
        let pane = try ReceiptDetailSources.pane()
        let row = try ReceiptDetailSources.source(at: "cellar/Installed/InstalledRow.swift")

        // The same shared surface the installed list row uses, for the same
        // catalog-less entry shape.
        #expect(pane.code.contains("MutationMenu(center:"))
        #expect(pane.code.contains("catalog: nil"))
        #expect(
            row.code.contains("MutationMenu(center:"),
            "the row no longer uses the shared surface, so the pane matching it proves nothing"
        )
        // …and no verb is re-implemented here.
        #expect(pane.code.contains("MutationCommand") == false, "the pane builds its own verb")
        #expect(pane.code.contains("submit(") == false)
        #expect(pane.code.contains("PackageTarget(") == false)
    }

    // MARK: - II15 sc12, R2, DD-12 — the copy stays a claim about the catalog

    @Test("The scoped catalog-miss copy is unchanged")
    func theScopedCatalogMissCopyIsUnchanged() throws {
        let pane = try ReceiptDetailSources.pane()
        let shipped = try ReceiptDetailSources.source(at: "cellar/Browse/PackageDetailView.swift")

        // Byte-for-byte against the sentence that already ships, apostrophe
        // included, rather than against a copy retyped in this test.
        let sentence = "This installed package is not in Cellar\u{2019}s core/cask catalog."
        #expect(
            shipped.raw.contains(sentence),
            "the shipped sentence moved, so the comparison below anchors on nothing"
        )
        #expect(pane.raw.contains(sentence), "the pane's footer is not the shipped sentence")
        #expect(sentence.unicodeScalars.contains("\u{2019}"))
        #expect(
            pane.raw.contains("Cellar's core/cask") == false,
            "the pane straightened the typographic apostrophe"
        )
        // …and the surface makes no claim about where the package came from.
        #expect(pane.raw.lowercased().contains("third-party") == false)
        #expect(pane.raw.lowercased().contains("third party") == false)
    }

    // MARK: - II15 sc9, DD-6 — no install date, on either source

    @Test("The receipt pane renders no install date")
    func theReceiptPaneRendersNoInstallDate() throws {
        let sources = try ReceiptDetailSources.load()
        try ReceiptDetailSources.assertAnchored(sources)

        for source in sources {
            for forbidden in ["Installed on", "installedAt", "installed_on", "Install date"] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) reports an install date: \(forbidden)"
                )
            }
            // No exposed value derives from the epoch the decoder collapses a
            // missing timestamp to.
            for forbidden in ["timeIntervalSince1970", "epoch", "Date(", "DateFormatter"] {
                #expect(
                    source.code.contains(forbidden) == false,
                    "\(source.name) derives a value from a timestamp: \(forbidden)"
                )
            }
        }

        // …and the value itself carries no such fact for a receipt that has one
        // to report, so the absence is the projection's rule and not the
        // fixture's silence.
        let detail = InstalledDetailProjection(Self.receipt())
        #expect(detail.orderedFacts.isEmpty == false)
        #expect(detail.orderedFacts.contains { $0.label.lowercased().contains("install") } == false)
        #expect(detail.orderedFacts.contains { $0.value.contains("1970") } == false)
    }

    // MARK: - Arrangement

    /// A receipt with an install timestamp to report, so the absence of an
    /// install-date fact above is a rule rather than missing input.
    private static func receipt() -> InstalledPackage {
        let keg = InstalledKeg(
            version: "1.4.0",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
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
