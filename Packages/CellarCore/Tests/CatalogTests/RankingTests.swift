import Foundation
import Testing

@testable import Catalog

@Suite("Ranking order")
struct RankingTests {
    @Test("Match class orders the result set, strongest first")
    func matchClassOrdersResults() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .formula, name: "curl", desc: "Like wget, but curl"),
            CatalogPackage.stub(kind: .formula, name: "libwget", desc: "Library"),
            CatalogPackage.stub(kind: .formula, name: "wget2", desc: "Successor"),
            CatalogPackage.stub(kind: .formula, name: "wget", desc: "Internet file retriever")
        ])

        let hits = index.search("wget")

        #expect(hits.map(\.id.name) == ["wget", "wget2", "libwget", "curl"])
        #expect(hits.map(\.rank) == [.exactToken, .namePrefix, .nameSubstring, .descriptionSubstring])
    }

    @Test("A record is ranked by its strongest class only")
    func strongestClassWins() {
        // `wget` is simultaneously an exact match, a prefix match, a substring
        // match and a description match. It must appear once, at rank 0.
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .formula, name: "wget", desc: "wget wget wget")
        ])

        let hits = index.search("wget")

        #expect(hits.count == 1)
        #expect(hits[0].rank == .exactToken)
    }

    @Test("A token inside a multi-word name is an exact match")
    func tokenInsideNameIsExact() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .cask, name: "visual-studio-code", installCount365d: 10),
            CatalogPackage.stub(kind: .formula, name: "codespell", installCount365d: 99)
        ])

        let hits = index.search("code")

        #expect(hits.map(\.id.name) == ["visual-studio-code", "codespell"])
        #expect(hits.map(\.rank) == [.exactToken, .namePrefix])
    }

    @Test("Install count breaks a class tie, descending")
    func installCountBreaksTies() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .formula, name: "nodenv", installCount365d: 12_000),
            CatalogPackage.stub(kind: .formula, name: "node-build", installCount365d: 900_000)
        ])

        let hits = index.search("node")

        #expect(hits.map(\.id.name) == ["node-build", "nodenv"])
    }

    @Test("An absent count sorts after every present count in its class")
    func absentCountsSortLast() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .formula, name: "alpha-unknown", installCount365d: nil),
            CatalogPackage.stub(kind: .formula, name: "alpha-tiny", installCount365d: 5)
        ])

        let hits = index.search("alpha")

        // 5 is a smaller number than "unknown" is, but "unknown" is not a number.
        #expect(hits.map(\.id.name) == ["alpha-tiny", "alpha-unknown"])
    }

    @Test("A full tie breaks by name, then formula before cask, reproducibly")
    func fullTiesBreakDeterministically() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .cask, name: "alpha", installCount365d: 7),
            CatalogPackage.stub(kind: .formula, name: "alpha", installCount365d: 7),
            CatalogPackage.stub(kind: .formula, name: "alphb", installCount365d: 7)
        ])

        let first = index.search("alph")
        let second = index.search("alph")

        #expect(first.map(\.id) == [
            PackageID(kind: .formula, name: "alpha"),
            PackageID(kind: .cask, name: "alpha"),
            PackageID(kind: .formula, name: "alphb")
        ])
        #expect(first == second)
    }

    @Test("Ranking holds on the captured fixture, not just hand-made records")
    func rankingHoldsOnRealRecords() throws {
        let snapshot = CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(from: Fixture.data("formula-slice")),
            casks: try CatalogDecoder.decodeCasks(from: Fixture.data("cask-slice")),
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let index = PackageSearchIndex(snapshot: snapshot)

        let hits = index.search("wget")

        #expect(hits.first?.id == PackageID(kind: .formula, name: "wget"))
        #expect(hits.first?.rank == .exactToken)
    }
}
