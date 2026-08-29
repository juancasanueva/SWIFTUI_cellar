import Foundation
import Testing

@testable import Catalog

@Suite("Package source identity")
struct PackageSourceTests {
    @Test("Every kind names the tool that installed it")
    func kindsMapToTheirSource() {
        #expect(PackageKind.formula.source == .homebrew)
        #expect(PackageKind.cask.source == .homebrew)
        #expect(PackageKind.npm.source == .npm)
    }

    @Test("The source enumeration is exactly Homebrew and npm")
    func sourceCasesAreClosed() {
        #expect(PackageSource.allCases == [.homebrew, .npm])
    }

    @Test("A source round-trips through its raw value")
    func sourceRawValuesAreStable() {
        #expect(PackageSource.homebrew.rawValue == "homebrew")
        #expect(PackageSource.npm.rawValue == "npm")
        #expect(PackageSource(rawValue: "npm") == .npm)
        #expect(PackageSource(rawValue: "cargo") == nil)
    }

    @Test("The npm kind's raw value is the persisted string npm")
    func npmKindRawValue() {
        #expect(PackageKind.npm.rawValue == "npm")
        #expect(PackageKind(rawValue: "npm") == .npm)
    }

    @Test("An npm identity survives a coding round trip")
    func npmIdentityRoundTrips() throws {
        let id = PackageID(kind: .npm, name: "@angular/cli")

        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(PackageID.self, from: data)

        #expect(decoded == id)
        #expect(decoded.kind == .npm)
        #expect(decoded.name == "@angular/cli")
    }

    @Test("A build without the npm kind reads such a row as absent, not as a failure")
    func unknownKindDecodesToNil() {
        #expect(PackageKind(rawValue: "pipx") == nil)
    }

    @Test("Identity keeps npm and Homebrew namespaces apart under one name")
    func namespacesDoNotCollide() {
        let formula = PackageID(kind: .formula, name: "typescript")
        let npm = PackageID(kind: .npm, name: "typescript")

        #expect(formula != npm)
        #expect(Set([formula, npm]).count == 2)
    }
}
