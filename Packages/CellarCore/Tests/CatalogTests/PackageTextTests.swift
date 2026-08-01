import Foundation
import Testing

@testable import Catalog

@Suite("Search text normalisation")
struct PackageTextTests {
    @Test("Normalisation lowercases")
    func lowercases() {
        #expect(PackageText.normalizedString("GH") == "gh")
        #expect(PackageText.normalizedString("iTerm2") == "iterm2")
        #expect(PackageText.normalizedString("PostgreSQL") == "postgresql")
    }

    @Test("Normalisation folds diacritics to ASCII")
    func foldsDiacritics() {
        #expect(PackageText.normalizedString("café") == "cafe")
        #expect(PackageText.normalizedString("naïve résumé") == "naive resume")
        #expect(PackageText.normalizedString("Ångström") == "angstrom")
    }

    @Test("A query and the text it should match normalise to the same bytes")
    func queryAndTextConverge() {
        // The whole point: matching compares pre-normalised bytes, so `cafe`
        // and `café` are the same needle and the same haystack.
        #expect(PackageText.normalize("cafe") == PackageText.normalize("café"))
        #expect(PackageText.normalize("GH") == PackageText.normalize("gh"))
    }

    @Test(
        "Runs of non-alphanumerics collapse to a single space",
        arguments: [
            ("visual-studio-code", "visual studio code"),
            ("openssl@3", "openssl 3"),
            ("node.js  --  cli", "node js cli"),
            ("  leading and trailing  ", "leading and trailing"),
            ("a___b", "a b")
        ]
    )
    func collapsesSeparators(input: String, expected: String) {
        #expect(PackageText.normalizedString(input) == expected)
    }

    @Test("Normalisation yields ASCII bytes only")
    func yieldsASCIIBytes() {
        let bytes = PackageText.normalize("115浏览器 Browser")
        #expect(bytes.allSatisfy { $0 == 0x20 || ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x7A) })
        #expect(String(decoding: bytes, as: UTF8.self) == "115 browser")
    }

    @Test("An empty or separator-only string normalises to nothing")
    func emptyInputs() {
        #expect(PackageText.normalize("").isEmpty)
        #expect(PackageText.normalize("   ").isEmpty)
        #expect(PackageText.normalize("---").isEmpty)
    }
}
