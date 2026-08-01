import Foundation
import Testing

@testable import Catalog

@Suite("Search index")
struct SearchIndexTests {
    @Test("Building the index normalises each record once, up front")
    func buildNormalisesEachRecordOnce() {
        let packages = [
            CatalogPackage.stub(kind: .formula, name: "openssl@3", desc: "Cryptography and SSL"),
            CatalogPackage.stub(kind: .cask, name: "visual-studio-code", desc: "Café-friendly editor")
        ]
        let index = PackageSearchIndex.stub(packages)

        #expect(index.recordCount == 2)
        // The normalised bytes live in the index, so a search is a byte scan and
        // never re-derives them per keystroke.
        #expect(index.normalizedName(at: 0) == PackageText.normalize("openssl@3"))
        #expect(index.normalizedName(at: 1) == PackageText.normalize("visual-studio-code"))
        #expect(index.normalizedDescription(at: 1) == PackageText.normalize("Café-friendly editor"))

        #expect(index.search("openssl").map(\.id.name) == ["openssl@3"])
        #expect(index.search("OpenSSL").map(\.id.name) == ["openssl@3"])
        #expect(index.search("cafe").map(\.id.name) == ["visual-studio-code"])
    }

    @Test("Repeated searches over one built index are identical")
    func searchIsIdempotent() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .formula, name: "wget", installCount365d: 10),
            CatalogPackage.stub(kind: .formula, name: "wget2", installCount365d: 5)
        ])

        #expect(index.search("wget") == index.search("wget"))
        #expect(index.search("wget").count == 2)
    }

    @Test("The same name in both namespaces yields two distinct results")
    func sameNameInBothNamespaces() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .formula, name: "docker", installCount365d: 100),
            CatalogPackage.stub(kind: .cask, name: "docker", installCount365d: 50)
        ])

        let hits = index.search("docker")

        #expect(hits.count == 2)
        #expect(Set(hits.map(\.id.kind)) == [.formula, .cask])
        #expect(hits.map(\.id) == [
            PackageID(kind: .formula, name: "docker"),
            PackageID(kind: .cask, name: "docker")
        ])
    }

    @Test("Every hit carries exactly one kind")
    func everyHitCarriesAKind() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .formula, name: "git"),
            CatalogPackage.stub(kind: .cask, name: "gitup")
        ])

        let hits = index.search("git")

        #expect(hits.count == 2)
        #expect(hits.allSatisfy { PackageKind.allCases.contains($0.id.kind) })
    }

    @Test("Detail lookup resolves by the pair, and a miss is not-found")
    func detailLookupIsByPair() {
        let index = PackageSearchIndex.stub([
            CatalogPackage.stub(kind: .formula, name: "docker", desc: "the formula"),
            CatalogPackage.stub(kind: .cask, name: "docker", desc: "the cask")
        ])

        #expect(index.package(PackageID(kind: .formula, name: "docker"))?.desc == "the formula")
        #expect(index.package(PackageID(kind: .cask, name: "docker"))?.desc == "the cask")
        #expect(index.package(PackageID(kind: .formula, name: "nosuchpackage")) == nil)
    }
}

extension PackageSearchIndex {
    /// A hand-written index, which is how every ranking rule in this suite is
    /// pinned to an input a reader can hold in their head.
    static func stub(_ packages: [CatalogPackage]) -> PackageSearchIndex {
        PackageSearchIndex(
            snapshot: CatalogSnapshot(
                generatedAt: Date(timeIntervalSince1970: 0),
                skippedRecordCount: 0,
                packages: packages
            )
        )
    }
}
