import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess
@testable import Catalog

@Suite("Tap projection")
struct TapProjectionTests {
    @Test("Official sources appear once, are explanatory, and never mutate")
    func officialSourcesAreExplanatoryOnly() {
        let projection = TapProjection(inventory: TapInventory(taps: [
            TapRecord(name: "homebrew/core", repository: "core"),
            TapRecord(name: "homebrew/cask", repository: "cask")
        ]))

        #expect(projection.officialSources.map(\.title) == ["Homebrew Core", "Homebrew Cask"])
        #expect(projection.officialSources.allSatisfy {
            $0.explanation == "API-backed; no local tap required"
        })
        #expect(projection.officialSources.allSatisfy { $0.isMutable == false })
        #expect(projection.thirdPartyTaps.isEmpty)
        #expect(projection.canAddTap)
    }

    @Test("The package summary pluralizes, omits zero components, and names emptiness")
    func packageSummaryReadsLikeTheDesign() {
        #expect(summary(formulae: 5, casks: 1) == "5 formulae · 1 cask")
        #expect(summary(formulae: 1, casks: 2) == "1 formula · 2 casks")
        #expect(summary(formulae: 4, casks: 0) == "4 formulae")
        #expect(summary(formulae: 0, casks: 1) == "1 cask")
        #expect(summary(formulae: 0, casks: 0) == "No packages")
    }

    private func summary(formulae: Int, casks: Int) -> String {
        TapProjection.packageSummary(
            for: TapRecord(
                name: "acme/tools",
                repository: "tools",
                formulaNames: (0..<formulae).map { "f\($0)" },
                caskTokens: (0..<casks).map { "c\($0)" }
            )
        )
    }

    @Test("Only the selected tap prefix is removed and equal tokens keep kind identity")
    func packageIdentityAndDisplayAreKindAware() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget", "other/tap/widget"],
            caskTokens: ["widget"]
        )

        let packages = TapProjection.packages(for: tap, installed: .empty)

        #expect(packages.map(\.displayName) == ["widget", "other/tap/widget", "widget"])
        #expect(packages.map(\.id.kind) == [.formula, .formula, .cask])
        #expect(Set(packages.map(\.id)).count == 3)
    }

    @Test("Exact installed tap and package kind alone enable Installed handoff")
    func exactInstalledCrossReferenceControlsHandoff() {
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: ["acme/tools/widget"],
            caskTokens: ["widget"]
        )
        let installed = InstalledInventory(packages: [
            installedPackage(kind: .formula, name: "widget", tap: "acme/tools"),
            installedPackage(kind: .cask, name: "widget", tap: "other/tools")
        ])

        let packages = TapProjection.packages(for: tap, installed: installed)

        #expect(packages[0].installedHandoff == PackageID(kind: .formula, name: "widget"))
        #expect(packages[1].installedHandoff == nil)
        #expect(packages[1].uninstalledExplanation == "Not in Cellar’s core/cask catalog.")
    }

    @Test("Name and kind filters return only matching visible rows from a large inventory")
    func largeInventoryFiltersLazily() {
        let formulae = (0..<2_000).map { "acme/tools/formula-\($0)" }
        let casks = (0..<2_000).map { "cask-\($0)" }
        let tap = TapRecord(
            name: "acme/tools",
            repository: "tools",
            formulaNames: formulae,
            caskTokens: casks
        )
        let all = TapProjection.packages(for: tap, installed: .empty)

        let visible = TapProjection.filter(all, query: "cask-199", kind: .cask)

        #expect(visible.map(\.displayName) == [
            "cask-199", "cask-1990", "cask-1991", "cask-1992", "cask-1993",
            "cask-1994", "cask-1995", "cask-1996", "cask-1997", "cask-1998", "cask-1999"
        ])
        #expect(visible.allSatisfy { $0.id.kind == .cask })
    }

    @Test("Brew absence, empty success, and failure remain distinct states")
    func presentationStatesRemainDistinct() {
        let absence = InstalledAbsence.notInstalled(.standard)
        #expect(TapProjection.state(loadState: .brewAbsent(absence), inventory: .empty) == .unavailable(absence))
        #expect(TapProjection.state(loadState: .loaded, inventory: .empty) == .content(isThirdPartyEmpty: true))
        #expect(
            TapProjection.state(loadState: .failed(.malformedJSON), inventory: .empty)
                == .error(.malformedJSON, hasLastGood: false)
        )
        let lastGood = TapInventory(taps: [TapRecord(name: "acme/tools", repository: "tools")])
        #expect(
            TapProjection.state(loadState: .failed(.cancelled), inventory: lastGood)
                == .error(.cancelled, hasLastGood: true)
        )
    }

    private func installedPackage(kind: PackageKind, name: String, tap: String) -> InstalledPackage {
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
