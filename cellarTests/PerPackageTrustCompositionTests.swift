//
//  PerPackageTrustCompositionTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import Testing

@testable import cellar

/// The composition claims a core unit test cannot make: that the four surfaces
/// this change touches read **one** projection value rather than each deriving
/// its own, and that the marker is added to a package row without disturbing
/// anything already on it.
///
/// Asserted structurally over the view sources, because two views computing the
/// same count independently is exactly the drift `package-trust` PT5 forbids —
/// and it would still pass a per-view rendering test on the day they disagree.
@MainActor
@Suite("Per-package trust composition", .timeLimit(.minutes(1)))
struct PerPackageTrustCompositionTests {
    // MARK: - PT5 :303-308, DD-6, DD-10 — one projection, four surfaces

    @Test("The row, the header and the rows read one projection")
    func rowHeaderAndRowsReadOneProjection() throws {
        let sources = try PerPackageTrustSources.views()

        // Positively anchored: the scan really did find all three files.
        #expect(sources.map(\.name).sorted()
            == ["PackageDetailView.swift", "TapDetailView.swift", "TapsListView.swift"])

        for name in ["TapsListView.swift", "TapDetailView.swift"] {
            let code = try #require(sources.first { $0.name == name }?.code)
            #expect(
                code.contains("TapProjection.grants(for:"),
                "\(name) does not read the shared grant projection"
            )
        }
        // The tap list also renders the section from the same projection type,
        // and the detail marks its package rows from the value it already read.
        let list = try #require(sources.first { $0.name == "TapsListView.swift" }?.code)
        #expect(list.contains("TapProjection.unattributedSection(in:"))
        let detail = try #require(sources.first { $0.name == "TapDetailView.swift" }?.code)
        #expect(detail.contains(".marked.contains("))

        // Package detail resolves by exact identity, through the one function
        // that owns that rule.
        let package = try #require(sources.first { $0.name == "PackageDetailView.swift" }?.code)
        #expect(
            package.contains("TapProjection.grantsIndividually("),
            "PackageDetailView does not resolve the marker by exact identity"
        )
        // …and it holds the store itself, not a pre-computed `Bool` or a closure,
        // so the marker updates when the report refreshes (DD-10).
        #expect(package.contains("let trustGrants: TrustGrantStore"))

        // No surface composes the copy or the count locally.
        for source in sources {
            #expect(
                source.code.contains("trusted individually") == false,
                "\(source.name) composes the count line locally"
            )
            #expect(
                source.code.contains("\"Trusted individually\"") == false,
                "\(source.name) composes the marker copy locally"
            )
            for local in ["case .noneRecorded", "case .nothingToShow", "case .unattributed"] {
                #expect(
                    source.code.contains(local) == false,
                    "\(source.name) derives a section rendering locally: \(local)"
                )
            }
        }
    }

    // MARK: - PT5 :326-332, TM1 preserved — the marker is additive

    /// The marker replaces, suppresses and rewords nothing. Both installed
    /// states carry it, and both keep their own TM1 copy and their **Show in
    /// Installed** handoff.
    @Test("The marker is additive on the package row")
    func theMarkerIsAdditiveOnThePackageRow() throws {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"],
            caskTokens: ["acme/tools/desk"],
            trust: .untrusted
        )
        let widget = PackageID(kind: .formula, name: "widget")
        let desk = PackageID(kind: .cask, name: "desk")
        let installed = InstalledInventory(packages: [
            // Installed, with its tap known.
            Self.package(kind: .formula, name: "widget", tap: "acme/tools"),
            // Installed, with the tap withheld — TM1's middle state.
            Self.package(kind: .cask, name: "desk", tap: nil)
        ])
        let report = TrustGrantState.reported(TrustGrantLedger(
            formulae: ["acme/tools/widget"],
            casks: ["acme/tools/desk"]
        ))

        let rows = TapProjection.packages(for: tap, installed: installed)
        let presentation = TapProjection.grants(for: tap, in: report)
        let widgetRow = try #require(rows.first { $0.id == widget })
        let deskRow = try #require(rows.first { $0.id == desk })

        // Both rows are marked, from the one projection value.
        #expect(presentation.marked == [widget, desk])
        #expect(presentation.countLine == "2 trusted individually")
        #expect(TapProjection.grantMarker == "Trusted individually")

        // …and each keeps its own unchanged install-state copy.
        #expect(widgetRow.state == .installed(widget))
        #expect(widgetRow.statusExplanation == nil)
        #expect(deskRow.state == .installedTapWithheld(desk))
        #expect(
            deskRow.statusExplanation
                == "Installed. Homebrew withholds its tap while this tap is untrusted."
        )
        // …and its Show in Installed handoff.
        #expect(widgetRow.installedHandoff == widget)
        #expect(deskRow.installedHandoff == desk)

        // Triangulated: an unmarked row on the same tap is otherwise identical,
        // so the marker really is the only difference the grant makes.
        let unreported = TapProjection.grants(for: tap, in: .unreported)
        #expect(unreported.marked.isEmpty)
        #expect(unreported.countLine == nil)
        #expect(TapProjection.packages(for: tap, installed: installed) == rows)

        // The row source still renders both of the things it rendered before,
        // beside the marker rather than instead of either.
        let detail = try #require(
            PerPackageTrustSources.views().first { $0.name == "TapDetailView.swift" }?.code
        )
        #expect(detail.contains("package.statusExplanation"))
        #expect(detail.contains("Show in Installed"))
        #expect(detail.contains("TapProjection.grantMarker"))
    }

    private static func package(
        kind: PackageKind,
        name: String,
        tap: String?
    ) -> InstalledPackage {
        let keg = InstalledKeg(
            version: "1.0",
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            installedOnRequest: true
        )
        return InstalledPackage(
            kind: kind,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            tap: tap,
            catalogVersion: "1.0",
            kegs: [keg],
            primaryKeg: keg,
            snapshotOutdated: false,
            isPinned: false,
            pinnedVersion: nil,
            declaresAutoUpdates: kind == .cask ? false : nil
        )
    }
}

/// The view sources this suite scans, anchored on this file rather than on the
/// runner's working directory.
nonisolated enum PerPackageTrustSources {
    struct ViewSource {
        let name: String
        let code: String
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static func views() throws -> [ViewSource] {
        try [
            "cellar/Taps/TapsListView.swift",
            "cellar/Taps/TapDetailView.swift",
            "cellar/Browse/PackageDetailView.swift"
        ].map { relative in
            ViewSource(
                name: URL(fileURLWithPath: relative).lastPathComponent,
                code: try String(
                    contentsOf: repositoryRoot.appendingPathComponent(relative),
                    encoding: .utf8
                )
            )
        }
    }
}
