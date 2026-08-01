import Foundation
import Testing

@testable import Catalog

@Suite("Detail projection")
struct ProjectionTests {
    // MARK: - Required fields (PD1)

    @Test("A formula projection carries every required detail field")
    func formulaProjectionIsComplete() throws {
        let wget = try Self.formula("wget")

        #expect(wget.kind == .formula)
        #expect(wget.name == "wget")
        #expect(wget.displayName == "wget")
        #expect(wget.desc == "Internet file retriever")
        #expect(wget.homepage == URL(string: "https://www.gnu.org/software/wget/"))
        #expect(wget.license == "GPL-3.0-or-later")
        #expect(wget.version == "1.25.0")
        #expect(wget.tap == "homebrew/core")
        #expect(wget.deprecated == false)
        #expect(wget.disabled == false)
        #expect(wget.buildDependencies.map(\.name) == ["pkgconf"])
        #expect(wget.dependents.isEmpty)
        #expect(wget.installCount == nil)
    }

    @Test("A cask projection carries every required detail field")
    func caskProjectionIsComplete() throws {
        let iterm = try Self.cask("iterm2")

        #expect(iterm.kind == .cask)
        #expect(iterm.name == "iterm2")
        #expect(iterm.displayName == "iTerm2")
        #expect(iterm.version == "3.6.11")
        #expect(iterm.homepage == URL(string: "https://iterm2.com/"))
        #expect(iterm.tap == "homebrew/cask")
        #expect(iterm.desc == "Terminal emulator as alternative to Apple's Terminal app")
    }

    // MARK: - Deprecation and disabled status (PD4)

    @Test("A deprecated record exposes its flag, reason and date")
    func deprecatedRecordExposesReasonAndDate() throws {
        let aamath = try Self.formula("aamath", in: "formula-slice")

        #expect(aamath.deprecated)
        #expect(aamath.deprecationReason == "unmaintained")
        #expect(aamath.deprecationDate == Self.day("2026-07-17"))
    }

    @Test("A disabled record exposes its flag, reason and date")
    func disabledRecordExposesReasonAndDate() throws {
        let payload = Data(#"""
        [{"name":"aftman","tap":"homebrew/core","desc":"gone",
          "versions":{"stable":"0.3.0"},
          "disabled":true,"disable_reason":"unmaintained","disable_date":"2026-01-05"}]
        """#.utf8)
        let record = try #require(CatalogDecoder.decodeFormulae(from: payload).packages.first)

        #expect(record.disabled)
        #expect(record.disableReason == "unmaintained")
        #expect(record.disableDate == Self.day("2026-01-05"))
    }

    @Test("A healthy record reports both flags false with all four fields absent")
    func healthyRecordHasNoReasonsOrDates() throws {
        // The live payload publishes a *scheduled* disable date on a formula that
        // is deprecated but still enabled; a healthy record must expose neither.
        let wget = try Self.formula("wget")

        #expect(wget.deprecated == false)
        #expect(wget.disabled == false)
        #expect(wget.deprecationReason == nil)
        #expect(wget.deprecationDate == nil)
        #expect(wget.disableReason == nil)
        #expect(wget.disableDate == nil)
    }

    @Test("A deprecated-but-enabled record hides the scheduled disable date")
    func scheduledDisableIsNotDisabled() throws {
        let aamath = try Self.formula("aamath", in: "formula-slice")

        #expect(aamath.deprecated)
        #expect(aamath.disabled == false)
        #expect(aamath.disableDate == nil)
        #expect(aamath.disableReason == nil)
    }

    // MARK: - Tap coverage (PD6)

    @Test("Every projected record belongs to a covered tap")
    func everyRecordBelongsToACoveredTap() throws {
        let formulae = try CatalogDecoder.decodeFormulae(from: Fixture.data("formula-slice"))
        let casks = try CatalogDecoder.decodeCasks(from: Fixture.data("cask-slice"))

        #expect(formulae.packages.count == 50)
        #expect(casks.packages.count == 50)
        #expect(formulae.packages.allSatisfy { $0.tap == "homebrew/core" })
        #expect(casks.packages.allSatisfy { $0.tap == "homebrew/cask" })
    }

    @Test("A third-party tap record is dropped without a decode failure")
    func thirdPartyTapRecordIsDroppedSilently() throws {
        let payload = Data(#"""
        [{"name":"wget","tap":"homebrew/core","desc":"Internet file retriever",
          "versions":{"stable":"1.25.0"}},
         {"name":"privatetool","tap":"acme/internal","desc":"private",
          "versions":{"stable":"9.9.9"}}]
        """#.utf8)

        let decoded = try CatalogDecoder.decodeFormulae(from: payload)

        #expect(decoded.packages.map(\.name) == ["wget"])
        // Out of scope is not malformed: the record must not inflate the tally.
        #expect(decoded.skippedRecordCount == 0)
    }

    // MARK: - Dependency lists (PD2)

    @Test("Dependency lists stay flat, direct, ordered and un-deduplicated")
    func dependencyListsAreFlatAndDirect() throws {
        let snapshot = try Self.linkedSnapshot()
        let git = try #require(snapshot.packages.first { $0.id == PackageID(kind: .formula, name: "git") })

        #expect(git.dependencies.map(\.name) == ["pcre2", "gettext"])
        #expect(git.buildDependencies.map(\.name) == ["gettext", "pkgconf"])
        // `gettext` appears in both lists — deduplicating across them would lose
        // the fact that it is needed at build time *and* at run time.
        #expect(git.dependencies.contains { $0.name == "gettext" })
        #expect(git.buildDependencies.contains { $0.name == "gettext" })

        let pcre2 = try #require(snapshot.packages.first { $0.name == "pcre2" })
        // No transitive edge of pcre2 leaked into git's own lists.
        #expect(pcre2.dependencies.isEmpty)
        #expect(Set(git.dependencies.map(\.name)).isDisjoint(with: ["libedit", "bzip2"]))
    }

    @Test("A dependency outside the snapshot is listed and marked unresolvable")
    func danglingDependencyIsMarkedUnresolvable() throws {
        let payload = Data(#"""
        [{"name":"pcre2","tap":"homebrew/core","desc":"regex","versions":{"stable":"10.0"}},
         {"name":"git","tap":"homebrew/core","desc":"scm","versions":{"stable":"2.55.0"},
          "dependencies":["pcre2","ghost-lib"],"build_dependencies":[]}]
        """#.utf8)
        let snapshot = CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(from: payload),
            casks: DecodedResource(packages: [], skippedRecordCount: 0),
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let git = try #require(snapshot.packages.first { $0.name == "git" })

        #expect(git.dependencies.map(\.name) == ["pcre2", "ghost-lib"])
        #expect(git.dependencies.map(\.isResolvable) == [true, false])
    }

    // MARK: - Helpers

    static func formula(_ name: String, in fixture: String = "formula-wget") throws -> CatalogPackage {
        let data = fixture.hasSuffix("slice")
            ? try Fixture.data(fixture)
            : try Fixture.wrappedInArray(fixture)
        let decoded = try CatalogDecoder.decodeFormulae(from: data)
        return try #require(decoded.packages.first { $0.name == name })
    }

    static func cask(_ name: String, in fixture: String = "cask-iterm2") throws -> CatalogPackage {
        let data = fixture.hasSuffix("slice")
            ? try Fixture.data(fixture)
            : try Fixture.wrappedInArray(fixture)
        let decoded = try CatalogDecoder.decodeCasks(from: data)
        return try #require(decoded.packages.first { $0.name == name })
    }

    static func linkedSnapshot() throws -> CatalogSnapshot {
        CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(from: Fixture.data("formula-slice")),
            casks: try CatalogDecoder.decodeCasks(from: Fixture.data("cask-slice")),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    static func day(_ string: String) -> Date? {
        CatalogDecoder.day(string)
    }
}
