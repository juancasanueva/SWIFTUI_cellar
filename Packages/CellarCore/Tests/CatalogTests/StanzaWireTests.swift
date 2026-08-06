import Foundation
import Testing

@testable import Catalog

/// The artifacts and relations wires: what a cask says it installs, read for the
/// three kinds this build projects and *counted* for every other kind.
///
/// Nothing in this file may throw. An unreadable stanza costs a count, never the
/// record (catalog-sync T4).
@Suite("Cask stanza decoding")
struct StanzaWireTests {
    static func record(_ fixture: String) throws -> CaskWire {
        let wire = try CatalogDecoder.caskWireRecords(from: Fixture.wrappedInArray(fixture))
        #expect(wire.skippedCount == 0, "\(fixture) must not cost its record")
        return try #require(wire.elements.first)
    }

    static func artifacts(_ fixture: String) throws -> CaskArtifactsWire {
        try #require(try record(fixture).artifacts)
    }

    // MARK: - The three projected kinds (R6)

    @Test("Every projected stanza kind decodes with its source and destination")
    func projectedKindsDecode() throws {
        let artifacts = try Self.artifacts("cask-every-stanza")

        #expect(
            artifacts.apps == [
                CaskArtifactItemWire(
                    source: "Every Stanza.app",
                    target: "/Applications/Every Stanza.app"
                )
            ]
        )
        #expect(
            artifacts.binaries == [
                CaskArtifactItemWire(
                    source: "Every Stanza.app/Contents/MacOS/every-stanza",
                    target: "every-stanza"
                )
            ]
        )
        #expect(
            artifacts.packageInstallers == [
                CaskArtifactItemWire(source: "EveryStanza.pkg", target: nil)
            ]
        )
        // `uninstall` and `zap` — counted, never read.
        #expect(artifacts.unrepresentedStanzaCount == 2)
    }

    @Test("A destination published beside the stanza key attaches rather than counting")
    func siblingTargetAttaches() throws {
        // Homebrew serialises `app "X.app", target: "Y"` two ways; `iterm2` uses
        // the sibling-key form and `cask-every-stanza` the in-array companion.
        let artifacts = try Self.artifacts("cask-iterm2")

        #expect(
            artifacts.apps == [
                CaskArtifactItemWire(source: "iTerm.app", target: "/Applications/iTerm.app")
            ]
        )
        // The `zap` stanza is the only unrepresented one: `target` is a modifier
        // of the `app` stanza, not a stanza kind, so it must not inflate this.
        #expect(artifacts.unrepresentedStanzaCount == 1)
    }

    // MARK: - The counted remainder (T4, R7)

    @Test("Three unmodelled stanza kinds cost three counts and no record")
    func unmodelledKindsAreCounted() throws {
        let artifacts = try Self.artifacts("cask-unrepresented")

        #expect(artifacts.apps.map(\.source) == ["Unrepresented.app"])
        #expect(artifacts.unrepresentedStanzaCount == 3)
    }

    @Test("A cask of only unmodelled stanzas still decodes, carrying its count")
    func onlyUnmodelledKindsStillDecodes() throws {
        let artifacts = try Self.artifacts("cask-only-unrepresented")

        #expect(artifacts.apps.isEmpty)
        #expect(artifacts.binaries.isEmpty)
        #expect(artifacts.packageInstallers.isEmpty)
        #expect(artifacts.unrepresentedStanzaCount >= 1)
        #expect(artifacts.unrepresentedStanzaCount == 2)
    }

    @Test("An artifacts element that is not an object costs one count, not the record")
    func nonObjectElementIsCounted() throws {
        let payload = Data(#"""
        [{"token":"odd","tap":"homebrew/cask","name":["Odd"],"version":"1.0",
          "artifacts":[{"app":["Odd.app"]},"not-an-object",42]}]
        """#.utf8)

        let wire = try CatalogDecoder.caskWireRecords(from: payload)
        let artifacts = try #require(wire.elements.first?.artifacts)

        #expect(artifacts.apps.map(\.source) == ["Odd.app"])
        #expect(artifacts.unrepresentedStanzaCount == 2)
        #expect(wire.skippedCount == 0)
    }

    @Test("The remainder is zero, not absent, when every published stanza was represented")
    func remainderIsZeroWhenNothingWasUnrepresented() throws {
        let payload = Data(#"""
        [{"token":"tidy","tap":"homebrew/cask","name":["Tidy"],"version":"1.0",
          "artifacts":[{"app":["Tidy.app"]},{"binary":["tidy"]},{"pkg":["Tidy.pkg"]}]}]
        """#.utf8)

        let artifacts = try #require(
            try CatalogDecoder.caskWireRecords(from: payload).elements.first?.artifacts
        )

        #expect(artifacts.unrepresentedStanzaCount == 0)
        #expect(artifacts.apps.count == 1)
        #expect(artifacts.binaries.count == 1)
        #expect(artifacts.packageInstallers.count == 1)
    }

    // MARK: - Relations (T1, T4)

    @Test("depends_on decodes its formula, cask and macOS forms")
    func dependsOnDecodesEveryModelledForm() throws {
        let dependsOn = try #require(try Self.record("cask-every-stanza").dependsOn)

        #expect(dependsOn.formulae == ["git"])
        #expect(dependsOn.casks == ["xquartz"])
        #expect(dependsOn.macOSRequirement == ">= 13")
        #expect(dependsOn.unrepresentedCount == 0)
    }

    @Test("An unmodelled relation key is counted, not fatal")
    func unmodelledRelationIsCounted() throws {
        let record = try Self.record("cask-unrepresented")

        let dependsOn = try #require(record.dependsOn)
        #expect(dependsOn.formulae == ["git"])
        // `arch` is a real Homebrew relation this build does not model.
        #expect(dependsOn.unrepresentedCount == 1)
        #expect(dependsOn.macOSRequirement == nil)

        let conflictsWith = try #require(record.conflictsWith)
        #expect(conflictsWith.casks == ["unrepresented@beta"])
        #expect(conflictsWith.unrepresentedCount == 1)
    }

    @Test("conflicts_with yields every published name")
    func conflictsWithYieldsEveryName() throws {
        let iterm = try #require(try Self.record("cask-iterm2").conflictsWith)

        #expect(iterm.casks == ["iterm2@beta", "iterm2@nightly"])
        #expect(iterm.formulae.isEmpty)
        #expect(iterm.unrepresentedCount == 0)

        let every = try #require(try Self.record("cask-every-stanza").conflictsWith)
        #expect(every.casks == ["every-stanza@beta"])
        #expect(every.formulae == ["every-stanza-cli"])
    }

    @Test("A macOS requirement published as a bare list still renders")
    func macOSRequirementAsListRenders() throws {
        let payload = Data(#"""
        [{"token":"listy","tap":"homebrew/cask","name":["Listy"],"version":"1.0",
          "depends_on":{"macos":[">= :monterey"]}}]
        """#.utf8)

        let record = try #require(
            try CatalogDecoder.caskWireRecords(from: payload).elements.first
        )

        #expect(record.dependsOn?.macOSRequirement == ">= :monterey")
        #expect(record.dependsOn?.unrepresentedCount == 0)
    }

    @Test("An artifacts value that is not a list is absent, and the record survives")
    func nonListArtifactsIsAbsent() throws {
        let payload = Data(#"""
        [{"token":"weird","tap":"homebrew/cask","name":["Weird"],"version":"1.0",
          "artifacts":{"app":["Weird.app"]}}]
        """#.utf8)

        let wire = try CatalogDecoder.caskWireRecords(from: payload)

        #expect(wire.elements.first?.token == "weird")
        #expect(wire.elements.first?.artifacts == nil)
        #expect(wire.skippedCount == 0)
    }
}
