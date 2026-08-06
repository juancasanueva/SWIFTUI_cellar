import Foundation
import Testing

@testable import Catalog

/// The projected inspection value types: what they expose, and what they cost on
/// disk.
///
/// These types are persisted 7,684 times, so the encode shape is a requirement
/// and not a style preference (design: empty collections are omitted).
@Suite("Cask inspection value types")
struct InspectionTypeTests {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func encodedKeys(_ value: some Encodable) throws -> Set<String> {
        let data = try encoder.encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return Set((object as? [String: Any]).map { Array($0.keys) } ?? [])
    }

    // MARK: - The declared checksum (N2)

    @Test("A published digest round-trips as the checksum the cask declares")
    func declaredChecksumRoundTrips() throws {
        let digest = "36e78c5049560eaa8e122224f6652eb4b229c61cd5e7332d6d25b5c36f7398e7"
        let checksum = CaskDownloadChecksum.declared(digest)

        // A single-value container: the persisted form is the string itself, so
        // the enum costs nothing over the `String?` it replaces.
        let data = try Self.encoder.encode(checksum)
        #expect(String(decoding: data, as: UTF8.self) == "\"\(digest)\"")

        let decoded = try JSONDecoder().decode(CaskDownloadChecksum.self, from: data)
        #expect(decoded == checksum)
        #expect(decoded.declaredDigest == digest)
    }

    @Test("The no_check literal is a declaration of no checksum, never a digest")
    func noCheckIsNotADigest() throws {
        let decoded = try JSONDecoder().decode(
            CaskDownloadChecksum.self, from: Data("\"no_check\"".utf8)
        )

        #expect(decoded == .notChecked)
        // The literal must not leak out as though it were a digest.
        #expect(decoded.declaredDigest == nil)

        let reencoded = try Self.encoder.encode(decoded)
        #expect(String(decoding: reencoded, as: UTF8.self) == "\"no_check\"")
    }

    // MARK: - Empty collections cost bytes, so they are not written (design)

    @Test("An install plan with no representable stanza persists only its count")
    func emptyInstallPlanOmitsItsCollections() throws {
        let plan = CaskInstallPlan(
            apps: [], binaries: [], packageInstallers: [], unrepresentedStanzaCount: 3
        )

        #expect(try Self.encodedKeys(plan) == ["unrepresentedStanzaCount"])

        let decoded = try JSONDecoder().decode(
            CaskInstallPlan.self, from: Self.encoder.encode(plan)
        )
        // Read side: arrays, never optionals. Absence is per-field on the group
        // above, not smuggled in as a nil collection here.
        #expect(decoded.apps.isEmpty)
        #expect(decoded.binaries.isEmpty)
        #expect(decoded.packageInstallers.isEmpty)
        #expect(decoded.unrepresentedStanzaCount == 3)
        #expect(decoded == plan)
    }

    @Test("A fully populated install plan round-trips with every field")
    func populatedInstallPlanRoundTrips() throws {
        let plan = CaskInstallPlan(
            apps: [CaskInstallArtifact(source: "iTerm.app", target: "/Applications/iTerm.app")],
            binaries: [CaskInstallArtifact(source: "bin/iterm", target: "iterm")],
            packageInstallers: [CaskInstallArtifact(source: "iTerm.pkg", target: nil)],
            unrepresentedStanzaCount: 0
        )

        // A zero remainder is not written either — it is the common case.
        #expect(try Self.encodedKeys(plan) == ["apps", "binaries", "packageInstallers"])

        let decoded = try JSONDecoder().decode(
            CaskInstallPlan.self, from: Self.encoder.encode(plan)
        )
        #expect(decoded == plan)
        #expect(decoded.apps.first?.target == "/Applications/iTerm.app")
        #expect(decoded.packageInstallers.first?.target == nil)
        // ...and the remainder still reads as `0`, not as absence.
        #expect(decoded.unrepresentedStanzaCount == 0)
    }

    @Test("An app that published no destination lands in the folder Homebrew uses")
    func appDestinationFallsBackToApplications() {
        let published = CaskInstallArtifact(source: "iTerm.app", target: "/Users/x/Apps/iTerm.app")
        let bare = CaskInstallArtifact(source: "iTerm.app", target: nil)

        #expect(CaskInstallDestination(appTarget: published.target) == .explicit("/Users/x/Apps/iTerm.app"))
        #expect(CaskInstallDestination(appTarget: bare.target) == .defaultApplicationsFolder)
        #expect(CaskInstallDestination(appTarget: bare.target).path == "/Applications")
        #expect(CaskInstallDestination(appTarget: published.target).path == "/Users/x/Apps/iTerm.app")
    }

    @Test("Requirements and conflicts omit their empty collections too")
    func emptyRelationGroupsOmitTheirCollections() throws {
        let requirements = CaskRequirements(
            formulae: [], casks: [], macOSRequirement: ">= 12", unrepresentedCount: 0
        )
        #expect(try Self.encodedKeys(requirements) == ["macOSRequirement"])

        let conflicts = CaskConflicts(casks: [], formulae: [], unrepresentedCount: 2)
        #expect(try Self.encodedKeys(conflicts) == ["unrepresentedCount"])

        let decodedRequirements = try JSONDecoder().decode(
            CaskRequirements.self, from: Self.encoder.encode(requirements)
        )
        #expect(decodedRequirements.formulae.isEmpty)
        #expect(decodedRequirements.casks.isEmpty)
        #expect(decodedRequirements.macOSRequirement == ">= 12")

        let decodedConflicts = try JSONDecoder().decode(
            CaskConflicts.self, from: Self.encoder.encode(conflicts)
        )
        #expect(decodedConflicts.casks.isEmpty)
        #expect(decodedConflicts.formulae.isEmpty)
        #expect(decodedConflicts.unrepresentedCount == 2)
    }

    @Test("Populated requirements and conflicts round-trip with every name")
    func populatedRelationGroupsRoundTrip() throws {
        let requirements = CaskRequirements(
            formulae: ["git"], casks: ["xquartz"], macOSRequirement: ">= 13", unrepresentedCount: 1
        )
        let conflicts = CaskConflicts(
            casks: ["iterm2@beta", "iterm2@nightly"], formulae: ["iterm-cli"], unrepresentedCount: 0
        )

        #expect(
            try Self.encodedKeys(requirements)
                == ["formulae", "casks", "macOSRequirement", "unrepresentedCount"]
        )
        #expect(try Self.encodedKeys(conflicts) == ["casks", "formulae"])

        #expect(
            try JSONDecoder().decode(
                CaskRequirements.self, from: Self.encoder.encode(requirements)
            ) == requirements
        )
        #expect(
            try JSONDecoder().decode(
                CaskConflicts.self, from: Self.encoder.encode(conflicts)
            ) == conflicts
        )
    }

    @Test("A cask inspection with no group populated persists as nothing but its own absence")
    func emptyInspectionOmitsEveryGroup() throws {
        let inspection = CaskInspection(
            downloadURL: nil,
            declaredChecksum: nil,
            installPlan: nil,
            requirements: nil,
            conflicts: nil
        )

        #expect(try Self.encodedKeys(inspection).isEmpty)

        let decoded = try JSONDecoder().decode(
            CaskInspection.self, from: Self.encoder.encode(inspection)
        )
        #expect(decoded.downloadURL == nil)
        #expect(decoded.installPlan == nil)
        #expect(decoded.requirements == nil)
        #expect(decoded.conflicts == nil)
        #expect(decoded.declaredChecksum == nil)
    }

    // MARK: - What may become a link (TM2)

    /// `downloadURL` is catalog-published text: whoever can land a cask in the
    /// tap chooses it. A `Link` hands its destination to the workspace opener,
    /// so the predicate that decides what may become one lives here, in
    /// CellarCore, where it is testable without a view — and not in SwiftUI,
    /// where it would be one `URL(string:)!` away from opening `file:///`.
    static let hostileDownloadURLs = [
        "javascript:alert(1)",
        "file:///etc/passwd",
        "data:text/html,<script>alert(1)</script>",
        "ftp://example.invalid/x.dmg",
        "example.com/x.dmg",
        "  http://example.invalid/x.dmg",
        "://example.invalid/x.dmg",
        "https://",
        ""
    ]

    @Test(
        "Only an http or https download URL is ever handed to a link opener",
        arguments: hostileDownloadURLs
    )
    func hostileSchemesAreNotBrowsable(published: String) {
        let inspection = CaskInspection(
            downloadURL: published,
            declaredChecksum: nil,
            installPlan: nil,
            requirements: nil,
            conflicts: nil
        )

        #expect(inspection.browsableDownloadURL == nil)
        // Refused for linking is not dropped: the text stays available so the
        // caller can render it as selectable text.
        #expect(inspection.downloadURL == published)
    }

    @Test(
        "An http or https download URL is browsable, whatever case its scheme was published in",
        arguments: [
            "https://iterm2.com/downloads/stable/iTerm2-3_6_11.zip",
            "http://example.invalid/x.dmg",
            "HTTPS://EXAMPLE.COM/x.dmg",
            "Http://Example.invalid/X.dmg"
        ]
    )
    func browsableSchemesAreAccepted(published: String) throws {
        let inspection = CaskInspection(
            downloadURL: published,
            declaredChecksum: nil,
            installPlan: nil,
            requirements: nil,
            conflicts: nil
        )

        let url = try #require(inspection.browsableDownloadURL)
        #expect(url.scheme?.lowercased() == (published.lowercased().hasPrefix("https") ? "https" : "http"))
        #expect(url.absoluteString == published)
    }

    @Test("A cask that published no download URL has nothing to link to")
    func absentDownloadURLIsNotBrowsable() {
        let inspection = CaskInspection(
            downloadURL: nil,
            declaredChecksum: .declared("abc"),
            installPlan: nil,
            requirements: nil,
            conflicts: nil
        )

        #expect(inspection.browsableDownloadURL == nil)
        // The predicate is about the URL, not about the whole inspection.
        #expect(inspection.declaredChecksum?.declaredDigest == "abc")
    }

    // MARK: - What the file may not contain (TM1, TM3)

    /// A prohibition enforced by the projection's *shape* has to be checked
    /// against the shape. Reflection catches a field that exists; this catches
    /// the code that would introduce one, including a helper or a type alias
    /// reflection would never see.
    ///
    /// The file's own documentation names every forbidden token, which is why
    /// the scan reads it with comments stripped: a prohibition *described* must
    /// not read as a prohibition *violated*.
    @Test("The inspection projection cannot speak the vocabulary it forbids")
    func inspectionSourceCarriesNoVerdictVocabulary() throws {
        let code = try CatalogSources.code(of: "CatalogInspection.swift")
        CatalogSources.assertAnchored(code, expecting: "browsableDownloadURL")
        // A second anchor, so a stripper bug that emptied the file would fail
        // here rather than pass every absence below.
        #expect(code.contains("public struct CaskInspection"))

        for forbidden in ["signature", "notariz", "verified", "trust", "identity", "teamIdentifier"] {
            #expect(
                code.lowercased().contains(forbidden.lowercased()) == false,
                "CatalogInspection.swift names \(forbidden)"
            )
        }
    }

    @Test("The inspection projection can neither run nor delete anything")
    func inspectionSourceCarriesNoExecutionVocabulary() throws {
        let code = try CatalogSources.code(of: "CatalogInspection.swift")
        CatalogSources.assertAnchored(code, expecting: "CaskInstallPlan")

        for forbidden in [
            "Process", "OperationCenter", "MutationCommand", "removeItem", "FileManager",
            "launchctl", "pkgutil"
        ] {
            #expect(
                code.contains(forbidden) == false,
                "CatalogInspection.swift references \(forbidden)"
            )
        }
    }

    @Test("Nothing untyped is stored: no JSON value tree, no dictionary of Any")
    func inspectionStoresNothingUntyped() throws {
        let code = try CatalogSources.code(of: "CatalogInspection.swift")
        CatalogSources.assertAnchored(code, expecting: "public let downloadURL: String?")

        // The whole design rests on this: keeping the stanza tree as a value
        // tree cost +28.3 MB resident and was rejected. A stored property of
        // one of these shapes is that decision being quietly reversed.
        for forbidden in ["JSONValue", "[String: Any]", "[String : Any]", "AnyCodable", "Any]"] {
            #expect(code.contains(forbidden) == false, "CatalogInspection.swift stores \(forbidden)")
        }
        // ...and the same for the wire types that feed it, which is where an
        // untyped escape hatch would actually be tempting.
        for name in ["Wire/CaskArtifactsWire.swift", "Wire/CaskRelationsWire.swift"] {
            let wire = try CatalogSources.code(of: name)
            #expect(wire.isEmpty == false)
            for forbidden in ["JSONValue", "[String: Any]", "AnyCodable"] {
                #expect(wire.contains(forbidden) == false, "\(name) stores \(forbidden)")
            }
        }
    }

    @Test("Formula sources carry both URLs as strings, and an absent head stays absent")
    func formulaSourcesRoundTrip() throws {
        let both = FormulaSources(
            stableURL: "https://example.invalid/git-2.55.0.tar.xz",
            headURL: "https://github.com/git/git.git"
        )
        let headless = FormulaSources(
            stableURL: "https://example.invalid/headless-3.1.4.tar.gz", headURL: nil
        )

        #expect(try Self.encodedKeys(both) == ["stableURL", "headURL"])
        #expect(try Self.encodedKeys(headless) == ["stableURL"])

        #expect(
            try JSONDecoder().decode(FormulaSources.self, from: Self.encoder.encode(both)) == both
        )
        let decodedHeadless = try JSONDecoder().decode(
            FormulaSources.self, from: Self.encoder.encode(headless)
        )
        #expect(decodedHeadless.headURL == nil)
        #expect(decodedHeadless.stableURL == "https://example.invalid/headless-3.1.4.tar.gz")
    }
}
