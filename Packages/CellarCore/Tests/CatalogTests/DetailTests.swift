import Foundation
import Testing

@testable import Catalog

@Suite("Detail resolution")
struct DetailTests {
    static func index() throws -> PackageSearchIndex {
        PackageSearchIndex(snapshot: try DependentsTests.fixtureSnapshot())
    }

    @Test("An unknown package resolves to not-found without throwing")
    func unknownPackageIsNotFound() throws {
        let index = try Self.index()

        #expect(index.package(PackageID(kind: .formula, name: "nosuchpackage")) == nil)
        // The same index does resolve a package it holds, so the nil above is a
        // real miss and not an empty index.
        #expect(index.package(PackageID(kind: .formula, name: "wget"))?.name == "wget")
    }

    @Test("A name in the wrong namespace is a miss, not a silent cross-namespace hit")
    func wrongNamespaceIsAMiss() throws {
        let index = try Self.index()

        #expect(index.package(PackageID(kind: .cask, name: "wget")) == nil)
        #expect(index.package(PackageID(kind: .formula, name: "iterm2")) == nil)
        #expect(index.package(PackageID(kind: .cask, name: "iterm2"))?.displayName == "iTerm2")
    }

    @Test("A third-party tap package is an ordinary not-found after a successful sync")
    func thirdPartyTapIsNotFound() async throws {
        let harness = try SyncHarness()
        let payload = Data(#"""
        [{"name":"wget","tap":"homebrew/core","desc":"Internet file retriever",
          "versions":{"stable":"1.25.0"}},
         {"name":"privatetool","tap":"acme/internal","desc":"private",
          "versions":{"stable":"9.9.9"}}]
        """#.utf8)
        harness.source.script(.payload(payload), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)

        let result = await harness.engine.sync()

        let snapshot = try #require(result.value)
        let index = PackageSearchIndex(snapshot: snapshot)
        #expect(index.package(PackageID(kind: .formula, name: "privatetool")) == nil)
        #expect(index.search("privatetool").isEmpty)
        // Absence is not a failure state.
        #expect(await harness.engine.status == .succeeded(at: harness.time.now))
        #expect(index.package(PackageID(kind: .formula, name: "wget")) != nil)
    }

    @Test("The resolved detail carries every PD1 field for a real formula")
    func formulaDetailIsComplete() throws {
        let index = try Self.index()
        let git = try #require(index.package(PackageID(kind: .formula, name: "git")))

        #expect(git.displayName == "git")
        #expect(git.kind == .formula)
        #expect(git.desc?.isEmpty == false)
        #expect(git.homepage != nil)
        // SPDX expressions are carried verbatim, not parsed into a single id.
        #expect(git.license?.hasPrefix("GPL-2.0-only AND ") == true)
        #expect(git.version.isEmpty == false)
        #expect(git.tap == "homebrew/core")
        #expect(git.dependencies.map(\.name) == ["pcre2", "gettext"])
        #expect(git.buildDependencies.map(\.name) == ["gettext", "pkgconf"])
        #expect(git.deprecated == false)
        #expect(git.disabled == false)
    }

    @Test("Absent optional fields stay absent through detail resolution")
    func absentFieldsStayAbsent() throws {
        let index = try Self.index()
        let iterm = try #require(index.package(PackageID(kind: .cask, name: "iterm2")))

        #expect(iterm.caveats == nil)
        #expect(iterm.license == nil)
        #expect(iterm.desc != nil)
        #expect(iterm.caveats != "")
    }
}
