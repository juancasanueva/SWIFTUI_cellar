import Foundation
import Testing

@testable import Catalog

@Suite("Dependents inversion")
struct DependentsTests {
    @Test("A runtime edge makes the dependant a dependent of its dependency")
    func runtimeEdgeInverts() throws {
        let snapshot = try Self.fixtureSnapshot()
        let pcre2 = try #require(snapshot.packages.first { $0.name == "pcre2" })

        #expect(pcre2.dependents.contains("git"))
    }

    @Test("A build-only edge also produces a dependent")
    func buildEdgeInverts() throws {
        let snapshot = try Self.fixtureSnapshot()
        let pkgconf = try #require(snapshot.packages.first { $0.name == "pkgconf" })

        // `wget` declares `pkgconf` only under build_dependencies. Ignoring
        // build edges would hide most of what a low-level library is used by.
        #expect(pkgconf.dependents.contains("wget"))
        let wget = try #require(snapshot.packages.first { $0.name == "wget" })
        #expect(wget.buildDependencies.map(\.name) == ["pkgconf"])
        #expect(wget.dependencies.map(\.name).contains("pkgconf") == false)
    }

    @Test("Inversion is complete and symmetric over the snapshot")
    func inversionIsSymmetric() throws {
        let snapshot = try Self.fixtureSnapshot()
        let byName = Dictionary(
            uniqueKeysWithValues: snapshot.packages
                .filter { $0.kind == .formula }
                .map { ($0.name, $0) }
        )

        var checkedEdges = 0
        for package in byName.values {
            for edge in package.dependencies + package.buildDependencies where edge.isResolvable {
                let target = try #require(byName[edge.name])
                #expect(
                    target.dependents.contains(package.name),
                    "\(package.name) -> \(edge.name) was not inverted"
                )
                checkedEdges += 1
            }
        }
        // The loop must actually have had edges to check.
        #expect(checkedEdges > 20)
    }

    @Test("A leaf reports an empty dependents list, not an absent one")
    func leafHasEmptyDependents() throws {
        let snapshot = try Self.fixtureSnapshot()
        let iterm = try #require(snapshot.packages.first { $0.name == "iterm2" })

        #expect(iterm.dependents.isEmpty)
        // Empty, not absent: the field is always present and always a list.
        #expect(iterm.dependents == [])
    }

    @Test("An edge to a name outside the snapshot creates no dependents entry")
    func danglingEdgeCreatesNoEntry() throws {
        let payload = Data(#"""
        [{"name":"pcre2","tap":"homebrew/core","desc":"regex","versions":{"stable":"10.0"}},
         {"name":"git","tap":"homebrew/core","desc":"scm","versions":{"stable":"2.55.0"},
          "dependencies":["pcre2","ghost-lib"],"build_dependencies":[]}]
        """#.utf8)
        let snapshot = CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(from: payload),
            casks: .empty,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(snapshot.packages.map(\.name).sorted() == ["git", "pcre2"])
        #expect(snapshot.packages.contains { $0.name == "ghost-lib" } == false)
        let pcre2 = try #require(snapshot.packages.first { $0.name == "pcre2" })
        #expect(pcre2.dependents == ["git"])
    }

    @Test("Dependents are ordered deterministically")
    func dependentsAreOrdered() throws {
        let payload = Data(#"""
        [{"name":"zlib","tap":"homebrew/core","desc":"compression","versions":{"stable":"1.3"}},
         {"name":"zeta","tap":"homebrew/core","desc":"z","versions":{"stable":"1.0"},
          "dependencies":["zlib"]},
         {"name":"alpha","tap":"homebrew/core","desc":"a","versions":{"stable":"1.0"},
          "dependencies":["zlib"]},
         {"name":"mid","tap":"homebrew/core","desc":"m","versions":{"stable":"1.0"},
          "build_dependencies":["zlib"]}]
        """#.utf8)
        let snapshot = CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(from: payload),
            casks: .empty,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let zlib = try #require(snapshot.packages.first { $0.name == "zlib" })

        #expect(zlib.dependents == ["alpha", "mid", "zeta"])
    }

    @Test("A package depending on the same name twice is listed once as a dependent")
    func duplicateEdgesCollapse() throws {
        let payload = Data(#"""
        [{"name":"gettext","tap":"homebrew/core","desc":"i18n","versions":{"stable":"0.2"}},
         {"name":"git","tap":"homebrew/core","desc":"scm","versions":{"stable":"2.55.0"},
          "dependencies":["gettext"],"build_dependencies":["gettext"]}]
        """#.utf8)
        let snapshot = CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(from: payload),
            casks: .empty,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let gettext = try #require(snapshot.packages.first { $0.name == "gettext" })

        // The two lists are kept separate on the *dependency* side, but "git
        // needs gettext" is one fact on the dependent side.
        #expect(gettext.dependents == ["git"])
    }

    static func fixtureSnapshot() throws -> CatalogSnapshot {
        CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(from: Fixture.data("formula-slice")),
            casks: try CatalogDecoder.decodeCasks(from: Fixture.data("cask-slice")),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}
