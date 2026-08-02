import Foundation
import Testing

@testable import Catalog

@Suite("Search index", .serialized)
struct SearchIndexTests {
    /// The size the p95 ceiling is claimed for, so "realistic" means one thing.
    static let realisticRecordCount = SearchLatencyTests.recordCount

    // MARK: - Off-main construction (PSA1)

    @Test("The main actor keeps servicing work throughout a 15,500-record build", .heavyFixture)
    @MainActor
    func mainActorStaysResponsiveDuringTheBuild() async {
        let snapshot = LatencyFixture.snapshot(count: Self.realisticRecordCount)
        let finished = Flag()
        let turns = Counter()

        // Main-actor work that keeps offering itself for as long as the build
        // runs, so what is measured is the *duration* of the build, not the one
        // scheduling turn any `await` hands out for free.
        let ticker = Task { @MainActor in
            while !finished.isSet {
                await Task.yield()
                turns.increment()
            }
        }
        await Task.yield()

        let before = turns.value
        let index = await PackageSearchIndex.build(from: snapshot)
        let during = turns.value - before
        finished.set()
        await ticker.value

        #expect(index.recordCount == Self.realisticRecordCount)
        // Measured against a `@MainActor` build, this is exactly 0: the build
        // holds the actor from the moment it starts, so no main-actor turn can
        // complete inside the window. It is a regression test, not a timing one.
        #expect(during > 0, "no main-actor turn completed while the index was building")
    }

    @Test("An off-main build answers identically to a synchronous one")
    func offMainBuildAnswersIdentically() async {
        let packages = [
            CatalogPackage.stub(kind: .formula, name: "docker", desc: "container runtime", installCount365d: 100),
            CatalogPackage.stub(kind: .cask, name: "docker", desc: "container desktop", installCount365d: 50),
            CatalogPackage.stub(kind: .formula, name: "dockerize", desc: "wait for services"),
            CatalogPackage.stub(kind: .formula, name: "openssl@3", desc: "Cryptography and SSL"),
            CatalogPackage.stub(kind: .cask, name: "visual-studio-code", desc: "Café-friendly editor"),
        ]
        let snapshot = CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            skippedRecordCount: 0,
            packages: packages
        )

        let synchronous = PackageSearchIndex(snapshot: snapshot)
        let offMain = await PackageSearchIndex.build(from: snapshot)

        #expect(offMain.recordCount == synchronous.recordCount)
        for query in ["docker", "dock", "cafe", "ssl", ""] {
            #expect(
                offMain.search(query) == synchronous.search(query),
                "query \(query.isEmpty ? "<empty>" : query) diverged"
            )
        }
        #expect(
            offMain.search("docker", filters: SearchFilters(kinds: [.cask]))
                == synchronous.search("docker", filters: SearchFilters(kinds: [.cask]))
        )

        // Normalisation is still one pass, materialised into the index rather
        // than re-derived per keystroke.
        for offset in 0..<packages.count {
            #expect(offMain.normalizedName(at: offset) == PackageText.normalize(packages[offset].name))
            #expect(
                offMain.normalizedDescription(at: offset)
                    == PackageText.normalize(packages[offset].desc ?? "")
            )
        }
    }

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
