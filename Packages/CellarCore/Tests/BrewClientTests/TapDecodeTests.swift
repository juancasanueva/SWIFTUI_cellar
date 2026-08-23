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

    /// `trusted` is Homebrew 6's per-tap grant flag, and it is three-valued
    /// rather than boolean: an absent or null field is a Homebrew with no trust
    /// concept, which is **not** the same fact as a Homebrew reporting `false`
    /// (tap-management TM12; the identical rule `declaresAutoUpdates` states for
    /// a cask's tri-state `auto_updates`).
    ///
    /// The fixture mirrors the real `tap-info --installed --json` object shape
    /// rather than a reduced one — the PR #67 lesson: a fixture that drops the
    /// keys brew actually sends proves nothing about the decoder brew meets.
    @Test("Trust decodes into three distinct states and absence is never reported false")
    func tapTrustIsThreeValuedAndAbsenceIsNotFalse() async throws {
        let data = Data("""
        [
          {"name":"acme/tools","user":"acme","repo":"tools","remote":"https://github.com/acme/tools",
           "formula_names":["acme/tools/widget"],"cask_tokens":[],"last_commit":"3 weeks ago","trusted":true},
          {"name":"beta/tools","user":"beta","repo":"tools","remote":"https://github.com/beta/tools",
           "formula_names":[],"cask_tokens":["beta/tools/desk"],"last_commit":"a day ago","trusted":false},
          {"name":"gamma/tools","user":"gamma","repo":"tools","remote":"https://github.com/gamma/tools",
           "formula_names":[],"cask_tokens":[],"last_commit":"an hour ago","trusted":null},
          {"name":"delta/tools","user":"delta","repo":"tools","remote":"https://github.com/delta/tools",
           "formula_names":[],"cask_tokens":[],"last_commit":"a minute ago"}
        ]
        """.utf8)

        let inventory = try await TapDecoder.decode(data)

        #expect(inventory.taps.map(\.name) == [
            "acme/tools", "beta/tools", "delta/tools", "gamma/tools"
        ])
        #expect(inventory.taps.map(\.trust) == [.trusted, .untrusted, .unreported, .unreported])
        #expect(inventory.skippedRecordCount == 0)

        // The two absence shapes are the same state, and neither is `untrusted`.
        let missing = try #require(inventory.taps.first { $0.name == "delta/tools" })
        let null = try #require(inventory.taps.first { $0.name == "gamma/tools" })
        #expect(missing.trust == null.trust)
        #expect(missing.trust != .untrusted)
        #expect(null.trust != .untrusted)

        // The rest of the record still decodes around the new key.
        #expect(inventory.taps[0].formulaNames == ["acme/tools/widget"])
        #expect(inventory.taps[1].caskTokens == ["beta/tools/desk"])
        #expect(inventory.taps[0].lastCommit == "3 weeks ago")
    }
}
