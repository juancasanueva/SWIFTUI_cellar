import Foundation
import Testing

@testable import Catalog

/// The catalog is Homebrew's. Adding `PackageKind.npm` to the shared identity
/// must not make an npm name reachable through a roster, an arrivals diff, an
/// install-count index or a sync resource — each of those speaks about packages
/// Homebrew publishes, and npm publishes none of them.
@Suite("npm is never a catalog kind")
struct NpmKindExhaustivenessTests {
    @Test("The seen-set never claims to have observed an npm identity")
    func rosterNeverContainsNpm() {
        let roster = KnownPackageRoster(formulae: ["typescript"], casks: ["iterm2"])

        #expect(roster.contains(PackageID(kind: .formula, name: "typescript")))
        #expect(roster.contains(PackageID(kind: .cask, name: "iterm2")))
        #expect(roster.contains(PackageID(kind: .npm, name: "typescript")) == false)
    }

    @Test("An npm observation enters neither the roster nor the arrivals log")
    func diffSkipsNpmObservations() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let seeded = KnownPackageRoster(formulae: [], casks: [])

        let result = DiscoveryRosterDiff.advance(
            roster: seeded,
            arrivals: .empty,
            observing: [
                CatalogPackage.stub(kind: .formula, name: "wget"),
                CatalogPackage.stub(kind: .npm, name: "typescript")
            ],
            now: now
        )

        #expect(result.roster.formulae == ["wget"])
        #expect(result.roster.casks.isEmpty)
        #expect(result.arrivals.arrivals.map(\.name) == ["wget"])
        #expect(result.roster.contains(PackageID(kind: .npm, name: "typescript")) == false)
    }

    @Test("An install-count endpoint read as npm yields no measurement at all")
    func analyticsHasNoNpmNames() throws {
        let payload = Data("""
        {"items":[{"formula":"wget","cask":"iterm2","count":"1,234"}]}
        """.utf8)

        let formulae = try AnalyticsIndex.decode(payload, kind: .formula)
        let npm = try AnalyticsIndex.decode(payload, kind: .npm)

        #expect(formulae.count(for: PackageID(kind: .formula, name: "wget")) == 1234)
        #expect(npm.isEmpty)
        #expect(npm.count(for: PackageID(kind: .npm, name: "wget")) == nil)
    }

    @Test("No sync resource declares the npm kind")
    func syncResourcesAreHomebrewOnly() {
        let kinds = CatalogResource.allCases.map(\.kind)

        #expect(kinds.contains(.formula))
        #expect(kinds.contains(.cask))
        #expect(kinds.contains(.npm) == false)
    }

    @Test("A catalog index built from Homebrew records answers nothing for an npm identity")
    func searchIndexHasNoNpmEntry() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .formula, name: "typescript", installCount365d: 10)
        ])

        #expect(index.package(PackageID(kind: .formula, name: "typescript")) != nil)
        #expect(index.package(PackageID(kind: .npm, name: "typescript")) == nil)
    }
}
