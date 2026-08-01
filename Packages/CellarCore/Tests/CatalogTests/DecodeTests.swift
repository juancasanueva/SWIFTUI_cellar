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
