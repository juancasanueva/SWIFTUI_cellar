import Foundation
import Testing

@testable import BrewClient

@Suite("Tolerant tap decoding")
struct TapDecodeTests {
    @Test("Unknown keys and one malformed record preserve valid taps")
    func malformedRecordIsSkipped() async throws {
        let data = Data("""
        [
          {"name":"acme/tools","user":"acme","repo":"tools","formula_names":["acme/tools/widget"],"unknown":42},
          {"name":7,"repo":false},
          {"name":"other/home","user":"other","repository":"home","cask_tokens":["desk"]}
        ]
        """.utf8)

        let inventory = try await TapDecoder.decode(data)

        #expect(inventory.taps.map(\.name) == ["acme/tools", "other/home"])
        #expect(inventory.skippedRecordCount == 1)
        #expect(inventory.taps[0].formulaNames == ["acme/tools/widget"])
        #expect(inventory.taps[1].caskTokens == ["desk"])
    }

    @Test("Repo wins over repository and last commit remains prose")
    func aliasesAndProseArePreserved() async throws {
        let data = Data("""
        [
          {"name":"acme/tools","repo":"primary","repository":"other","last_commit":"3 weeks ago"},
          {"name":"other/home","repo":null,"repository":"fallback"}
        ]
        """.utf8)

        let inventory = try await TapDecoder.decode(data)

        #expect(inventory.taps.map(\.repository) == ["primary", "fallback"])
        #expect(inventory.taps.first?.lastCommit == "3 weeks ago")
    }

    @Test("Remote credentials are removed and malformed envelopes are typed")
    func credentialsAreRedactedAndEnvelopesAreTyped() async throws {
        let inventory = try await TapDecoder.decode(Data("""
        [{"name":"acme/tools","repo":"tools","remote":"https://alice:secret@example.com/acme/tools"}]
        """.utf8))

        #expect(inventory.taps.first?.remote?.absoluteString == "https://example.com/acme/tools")
        #expect(inventory.taps.first?.remote?.absoluteString.contains("alice") == false)
        await #expect(throws: TapInventoryError.malformedJSON) {
            try await TapDecoder.decode(Data("not json".utf8))
        }
        await #expect(throws: TapInventoryError.nonArrayEnvelope) {
            try await TapDecoder.decode(Data("{\"taps\":[]}".utf8))
        }
    }
}
