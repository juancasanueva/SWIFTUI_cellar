import Foundation
import Testing

@testable import Catalog

@Suite("Search filters and edge queries")
struct FilterTests {
    static func catalog() -> PackageSearchIndex {
        PackageSearchIndex.stub([
            CatalogPackage.stub(
                kind: .formula, name: "docker", installCount365d: 100
            ),
            CatalogPackage.stub(
                kind: .cask, name: "docker", installCount365d: 50
            ),
            CatalogPackage.stub(
                kind: .formula, name: "docker-old",
                deprecated: true, deprecationReason: "unmaintained", installCount365d: 10
            ),
            CatalogPackage.stub(
                kind: .formula, name: "docker-dead",
                disabled: true, disableReason: "removed", installCount365d: 1
            )
        ])
    }

    @Test("Deprecated packages are included by default, flag exposed for badging")
    func deprecatedIncludedByDefault() {
        let index = Self.catalog()

        let hits = index.search("docker")

        #expect(hits.map(\.id.name).contains("docker-old"))
        let deprecated = index.package(PackageID(kind: .formula, name: "docker-old"))
        #expect(deprecated?.deprecated == true)
        #expect(deprecated?.deprecationReason == "unmaintained")
    }

    @Test("excludeDeprecated removes only the deprecated matches")
    func excludeDeprecatedKeepsTheRest() {
        var filters = SearchFilters()
        filters.excludeDeprecated = true

        let hits = Self.catalog().search("docker", filters: filters)

        #expect(hits.map(\.id.name).contains("docker-old") == false)
        #expect(hits.map(\.id.name).contains("docker"))
        #expect(hits.count == 3)
    }

    @Test("excludeDisabled removes only the disabled matches")
    func excludeDisabledKeepsTheRest() {
        var filters = SearchFilters()
        filters.excludeDisabled = true

        let hits = Self.catalog().search("docker", filters: filters)

        #expect(hits.map(\.id.name).contains("docker-dead") == false)
        #expect(hits.count == 3)
    }

    @Test("A kind filter restricts the namespace")
    func kindFilterRestrictsNamespace() {
        var filters = SearchFilters()
        filters.kinds = [.cask]

        let hits = Self.catalog().search("docker", filters: filters)

        #expect(hits.count == 1)
        #expect(hits[0].id == PackageID(kind: .cask, name: "docker"))
    }

    @Test("No declared filter refers to installed, not-installed or outdated state")
    func noFilterReferencesInstalledState() {
        let labels = Mirror(reflecting: SearchFilters()).children.compactMap(\.label)

        #expect(labels == ["kinds", "excludeDeprecated", "excludeDisabled"])
        // The persisted catalog simply cannot answer these; offering the filter
        // would be a promise the data cannot keep.
        #expect(labels.allSatisfy { !$0.lowercased().contains("install") })
        #expect(labels.allSatisfy { !$0.lowercased().contains("outdated") })
    }

    @Test(
        "An empty or whitespace-only query returns the whole filtered catalog",
        arguments: ["", "   ", "\t\n"]
    )
    func emptyQueryReturnsEverything(query: String) {
        let hits = Self.catalog().search(query)

        #expect(hits.count == 4)
        // Default order is install count descending.
        #expect(hits.map(\.id.name) == ["docker", "docker", "docker-old", "docker-dead"])
        #expect(hits.map(\.id.kind) == [.formula, .cask, .formula, .formula])
    }

    @Test("An empty query still honours the filters")
    func emptyQueryHonoursFilters() {
        var filters = SearchFilters()
        filters.kinds = [.cask]

        let hits = Self.catalog().search("", filters: filters)

        #expect(hits.count == 1)
        #expect(hits[0].id.kind == .cask)
    }

    @Test("A query matching nothing returns an empty set and throws nothing")
    func noMatchReturnsEmpty() {
        let index = Self.catalog()

        let hits = index.search("zzzzznotapackage")

        // Empty because the scan ran and rejected all four records — the same
        // index answers `docker` with four hits.
        #expect(hits.isEmpty)
        #expect(index.search("docker").count == 4)
    }

    @Test("A limit caps the result set without changing the order")
    func limitCapsResults() {
        let hits = Self.catalog().search("docker", limit: 2)

        #expect(hits.count == 2)
        #expect(hits.map(\.id.name) == ["docker", "docker"])
    }
}
