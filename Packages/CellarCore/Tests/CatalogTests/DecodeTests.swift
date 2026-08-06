import Foundation
import Testing

@testable import Catalog

@Suite("Tolerant payload decoding")
struct DecodeTests {
    // MARK: - Shapes the published API actually emits (CS5)

    @Test("A cask name array collapses to a single display name")
    func caskNameArrayYieldsDisplayName() throws {
        let decoded = try CatalogDecoder.decodeCasks(from: Fixture.wrappedInArray("cask-iterm2"))
        let iterm = try #require(decoded.packages.first)

        #expect(iterm.name == "iterm2")
        #expect(iterm.displayName == "iTerm2")
    }

    @Test("The first entry of a multilingual name array wins")
    func multilingualNameArrayPicksFirst() throws {
        let decoded = try CatalogDecoder.decodeCasks(from: Fixture.data("cask-slice"))
        let code = try #require(decoded.packages.first { $0.name == "visual-studio-code" })

        #expect(code.displayName == "Microsoft Visual Studio Code")
    }

    @Test("Null description and caveats decode as absent, not empty")
    func nullFieldsDecodeAsAbsent() throws {
        let decoded = try CatalogDecoder.decodeCasks(from: Fixture.wrappedInArray("cask-iterm2"))
        let iterm = try #require(decoded.packages.first)

        #expect(iterm.caveats == nil)
        #expect(iterm.caveats != "")
        #expect(iterm.desc == "Terminal emulator as alternative to Apple's Terminal app")

        let slice = try CatalogDecoder.decodeCasks(from: Fixture.data("cask-slice"))
        let noDesc = try #require(slice.packages.first { $0.name == "apptrap" })
        #expect(noDesc.desc == nil)
        #expect(noDesc.desc != "")
    }

    @Test("Mixed uses_from_macos elements both decode and the record survives")
    func mixedUsesFromMacOSDecodes() throws {
        let payload = Data(#"""
        [{"name":"aamath","tap":"homebrew/core","desc":"ASCII art maths",
          "versions":{"stable":"0.3"},"dependencies":[],"build_dependencies":[],
          "uses_from_macos":["curl",{"llvm":["build"]},{"bison":"build"}]}]
        """#.utf8)

        let wire = try CatalogDecoder.formulaWireRecords(from: payload)
        let record = try #require(wire.elements.first)

        #expect(record.usesFromMacos?.map(\.name) == ["curl", "llvm", "bison"])
        #expect(wire.skippedCount == 0)

        let decoded = try CatalogDecoder.decodeFormulae(from: payload)
        #expect(decoded.packages.map(\.name) == ["aamath"])
    }

    @Test("Keys the decoder does not model are discarded, not fatal")
    func unknownKeysAreIgnored() throws {
        let decoded = try CatalogDecoder.decodeFormulae(from: Fixture.data("formula-unknown-keys"))
        let wget = try #require(decoded.packages.first)

        #expect(wget.name == "wget")
        #expect(wget.desc == "Internet file retriever")
    }

    // MARK: - The widened key subset (T1, T2)

    @Test("The five widened cask keys decode from a published record")
    func widenedCaskKeysDecode() throws {
        let wire = try CatalogDecoder.caskWireRecords(from: Fixture.wrappedInArray("cask-iterm2"))
        let iterm = try #require(wire.elements.first)

        #expect(iterm.url == "https://iterm2.com/downloads/stable/iTerm2-3_6_11.zip")
        #expect(iterm.sha256 == "36e78c5049560eaa8e122224f6652eb4b229c61cd5e7332d6d25b5c36f7398e7")
        #expect(iterm.artifacts?.apps.map(\.source) == ["iTerm.app"])
        #expect(iterm.dependsOn?.macOSRequirement == ">= 12")
        #expect(iterm.conflictsWith?.casks == ["iterm2@beta", "iterm2@nightly"])
        #expect(wire.skippedCount == 0)
    }

    @Test(
        "A cask omitting every widened key, and one publishing them all as null, both decode",
        arguments: ["cask-bare", "cask-bare-null"]
    )
    func widenedCaskKeysAreAbsentNotEmpty(fixture: String) throws {
        let wire = try CatalogDecoder.caskWireRecords(from: Fixture.wrappedInArray(fixture))
        let record = try #require(wire.elements.first)

        // Typed absence: not "", not [], not 0. Each is checked against the empty
        // value it would collapse into if a default were substituted.
        #expect(record.url == nil)
        #expect(record.url != "")
        #expect(record.sha256 == nil)
        #expect(record.sha256 != "")
        #expect(record.artifacts == nil)
        #expect(record.dependsOn == nil)
        #expect(record.conflictsWith == nil)
        // The record itself survived: the widening cost it nothing.
        #expect(record.token == (fixture == "cask-bare" ? "bare" : "bare-null"))
        #expect(wire.skippedCount == 0)
    }

    @Test("Formula stable and head source URLs decode, and an absent head stays absent")
    func formulaSourceURLsDecode() throws {
        let git = try #require(
            try CatalogDecoder.formulaWireRecords(
                from: Fixture.wrappedInArray("formula-git")
            ).elements.first
        )

        #expect(
            git.urls?.stable?.url
                == "https://mirrors.edge.kernel.org/pub/software/scm/git/git-2.55.0.tar.xz"
        )
        #expect(git.urls?.head?.url == "https://github.com/git/git.git")

        let headless = try #require(
            try CatalogDecoder.formulaWireRecords(
                from: Fixture.wrappedInArray("formula-headless")
            ).elements.first
        )

        #expect(headless.urls?.stable?.url == "https://example.invalid/releases/headless-3.1.4.tar.gz")
        #expect(headless.urls?.head == nil)
        // The `checksum` under `urls.stable` is the formula digest and is
        // deliberately out of scope: only the source URL is widened here.
        #expect(headless.versions?.stable == "3.1.4")
    }

    // MARK: - The widening changes nothing about which records decode (T5)

    /// Recorded by running the slice fixtures on the **pre-widening** build,
    /// before a single new key existed. They are not re-derived here on purpose:
    /// a number read off the widened build would agree with itself no matter
    /// what the widening broke.
    ///
    /// If this fails, the tolerance of the new wire types is wrong. Fix the
    /// wire — never the fixture, never the expected number.
    static let preWideningCaskRecords = 50
    static let preWideningCaskSkipped = 0
    static let preWideningFormulaRecords = 50
    static let preWideningFormulaSkipped = 0

    @Test("The widening does not change which records decode")
    func wideningPreservesTheRecordAndSkippedCounts() throws {
        let casks = try CatalogDecoder.decodeCasks(from: Fixture.data("cask-slice"))
        #expect(casks.packages.count == Self.preWideningCaskRecords)
        #expect(casks.skippedRecordCount == Self.preWideningCaskSkipped)

        let formulae = try CatalogDecoder.decodeFormulae(from: Fixture.data("formula-slice"))
        #expect(formulae.packages.count == Self.preWideningFormulaRecords)
        #expect(formulae.skippedRecordCount == Self.preWideningFormulaSkipped)
    }

    @Test("A widened key published in a shape this build cannot read costs no record")
    func anUnreadableWidenedValueCostsNoRecord() throws {
        // Every one of the five in a shape the wire types do not model: the
        // record must survive with all five absent, exactly as if it had omitted
        // them. Only the keys that existed before the widening may cost a record.
        let payload = Data(#"""
        [{"token":"hostile","tap":"homebrew/cask","name":["Hostile"],"version":"1.0",
          "url":42,"sha256":["not","a","digest"],"artifacts":{"app":"nope"},
          "depends_on":["not","an","object"],"conflicts_with":7}]
        """#.utf8)

        let decoded = try CatalogDecoder.decodeCasks(from: payload)

        #expect(decoded.packages.map(\.name) == ["hostile"])
        #expect(decoded.skippedRecordCount == 0)
        #expect(decoded.packages.first?.caskInspection == nil)
        #expect(decoded.packages.first?.version == "1.0")
    }

    // MARK: - Record-level tolerance (CS5, D6)

    @Test("Three malformed records among a hundred cost three records, not the payload")
    func oneMalformedRecordDoesNotKillThePayload() throws {
        let payload = Self.formulaPayload(validCount: 97, malformedCount: 3)

        let decoded = try CatalogDecoder.decodeFormulae(from: payload)

        #expect(decoded.packages.count == 97)
        #expect(decoded.skippedRecordCount == 3)
    }

    @Test("A payload with zero usable records is a malformed payload")
    func zeroUsableRecordsThrows() {
        let allBad = Self.formulaPayload(validCount: 0, malformedCount: 5)

        #expect(throws: CatalogSyncError.malformedPayload) {
            try CatalogDecoder.decodeFormulae(from: allBad)
        }
        #expect(throws: CatalogSyncError.malformedPayload) {
            try CatalogDecoder.decodeFormulae(from: Data("[]".utf8))
        }
    }

    @Test("An unreadable envelope is a malformed payload")
    func unreadableEnvelopeThrows() {
        #expect(throws: CatalogSyncError.malformedPayload) {
            try CatalogDecoder.decodeFormulae(from: Data("<!DOCTYPE html><html>nope".utf8))
        }
        #expect(throws: CatalogSyncError.malformedPayload) {
            try CatalogDecoder.decodeCasks(from: Data(#"{"error":"not an array"}"#.utf8))
        }
    }

    // MARK: - Helpers

    /// Builds a formula payload whose malformed records fail on a type the wire
    /// shape requires (`name` as a number), which is exactly how a real schema
    /// drift would land.
    static func formulaPayload(validCount: Int, malformedCount: Int) -> Data {
        var records: [String] = []
        for index in 0..<validCount {
            records.append("""
            {"name":"pkg\(index)","tap":"homebrew/core","desc":"package \(index)",
             "versions":{"stable":"1.\(index).0"},"dependencies":[],"build_dependencies":[]}
            """)
        }
        for index in 0..<malformedCount {
            records.append("""
            {"name":\(index),"tap":"homebrew/core","versions":{"stable":"1.0.0"}}
            """)
        }
        return Data("[\(records.joined(separator: ","))]".utf8)
    }
}
