import Foundation
import Testing

@testable import SecurityKit

/// What a signed artifact must say about **who signed it**.
///
/// The spec requires signing *identity* to be visible: identifier, team
/// identifier and authority chain. The panel shipped rendering
/// `ArtifactSigningState.label` alone — "Signed by 24VZTF6M5V" — which is the
/// team and nothing else. A team identifier is not an identity, and MV-7 exists
/// precisely to compare all three against `codesign -dv --verbose=4` literally.
///
/// The projection lives here rather than in the view for the usual reason: a rule
/// inside a `body` is a rule no test can reach, and this one had already been got
/// wrong once.
@Suite("Artifact identity presentation")
struct ArtifactIdentityPresentationTests {
    private static let ghostty = ArtifactSigningIdentity(
        identifier: "com.mitchellh.ghostty",
        teamIdentifier: "24VZTF6M5V",
        authorities: [
            "Developer ID Application: Mitchell Hashimoto (24VZTF6M5V)",
            "Developer ID Certification Authority",
            "Apple Root CA"
        ]
    )

    // MARK: - The Developer ID case, which is what MV-7 compares

    @Test("A signed artifact projects its identifier, team and full authority chain")
    func aSignedArtifactProjectsIdentifierTeamAndAuthorityChain() {
        let fields = SecurityPresentation.identityFields(for: .signed(Self.ghostty))

        #expect(
            fields.map(\.value) == [
                "com.mitchellh.ghostty",
                "24VZTF6M5V",
                "Developer ID Application: Mitchell Hashimoto (24VZTF6M5V)",
                "Developer ID Certification Authority",
                "Apple Root CA"
            ],
            "the three fields MV-7 compares are not all projected, or not in order"
        )
    }

    /// The chain is **leaf first**, exactly as the platform reported it and
    /// exactly as `codesign` prints it. Sorting or reversing it would make a
    /// literal comparison fail for a reason that has nothing to do with the
    /// artifact.
    @Test("The authority chain keeps the platform's order, leaf first")
    func theAuthorityChainKeepsThePlatformsOrder() {
        let fields = SecurityPresentation.identityFields(for: .signed(Self.ghostty))
        let authorities = fields.filter { $0.label == "Authority" }.map(\.value)

        #expect(authorities == Self.ghostty.authorities)
        #expect(authorities.first?.hasPrefix("Developer ID Application:") == true)
        #expect(authorities.last == "Apple Root CA")
    }

    /// Labels mirror `codesign -dv --verbose=4`'s own vocabulary, so MV-7 is a
    /// side-by-side reading rather than a translation exercise.
    @Test("Field labels match codesign's vocabulary")
    func fieldLabelsMatchCodesignVocabulary() {
        let fields = SecurityPresentation.identityFields(for: .signed(Self.ghostty))

        #expect(fields.map(\.label) == [
            "Identifier", "Team identifier", "Authority", "Authority", "Authority"
        ])
    }

    /// Every field needs a distinct accessibility key, or three `Authority` rows
    /// collapse onto one identifier and a UI test can only ever see the first.
    @Test("Every field carries a distinct key")
    func everyFieldCarriesADistinctKey() {
        let fields = SecurityPresentation.identityFields(for: .signed(Self.ghostty))
        let keys = fields.map(\.key)

        #expect(keys == ["identifier", "team", "authority-0", "authority-1", "authority-2"])
        #expect(Set(keys).count == keys.count)
    }

    @Test("Field identifiers compose with the package name in the house scheme")
    func fieldIdentifiersComposeWithThePackageName() {
        let fields = SecurityPresentation.identityFields(for: .signed(Self.ghostty))

        #expect(
            fields.map { SecurityPresentation.identityFieldIdentifier($0, package: "ghostty") } == [
                "security-integrity-ghostty-identifier",
                "security-integrity-ghostty-team",
                "security-integrity-ghostty-authority-0",
                "security-integrity-ghostty-authority-1",
                "security-integrity-ghostty-authority-2"
            ]
        )
    }

    // MARK: - Ad-hoc, which is every brew bottle

    /// The U3 probe measured that every formula binary is ad-hoc signed, with an
    /// identifier like `rg-555549448f89ec4d458733e9aff65b2c3b7acce2` and **no**
    /// team and **no** authority chain. The identifier is real and must be shown;
    /// inventing the other two would be worse than omitting them.
    @Test("An ad-hoc artifact projects its identifier and nothing it does not have")
    func anAdHocArtifactProjectsItsIdentifierAndNothingElse() {
        let fields = SecurityPresentation.identityFields(
            for: .adHoc(identifier: "rg-555549448f89ec4d458733e9aff65b2c3b7acce2")
        )

        #expect(fields.map(\.key) == ["identifier"])
        #expect(fields.first?.value == "rg-555549448f89ec4d458733e9aff65b2c3b7acce2")
        #expect(fields.contains { $0.label == "Team identifier" } == false)
        #expect(fields.contains { $0.label == "Authority" } == false)
    }

    /// A Developer ID signature with no team reported is possible and must not
    /// produce an empty row that reads as "signed by nobody".
    @Test("A signed artifact with no team identifier omits the team row")
    func aSignedArtifactWithNoTeamOmitsTheTeamRow() {
        let identity = ArtifactSigningIdentity(
            identifier: "com.example.tool",
            teamIdentifier: nil,
            authorities: ["Apple Root CA"]
        )

        let fields = SecurityPresentation.identityFields(for: .signed(identity))

        #expect(fields.map(\.key) == ["identifier", "authority-0"])
        #expect(fields.contains { $0.value.isEmpty } == false, "an empty value reached the surface")
    }

    // MARK: - The states with no identity at all

    /// Unsigned, invalid and could-not-assess have no identity to report. They
    /// project **nothing** rather than blank rows — an empty labelled field reads
    /// as a fact about the artifact, and there is no fact here.
    @Test(
        "States with no identity project no fields",
        arguments: [
            ArtifactSigningState.unsigned,
            .invalid(.brokenSeal),
            .couldNotAssess(.assessmentUnavailable),
            .couldNotAssess(.artifactUnreadable)
        ]
    )
    func statesWithNoIdentityProjectNoFields(state: ArtifactSigningState) {
        #expect(SecurityPresentation.identityFields(for: state).isEmpty)
    }

    /// The positive control for the test above: a state that *does* have an
    /// identity must project fields, or "no fields" would pass for a projection
    /// that never returns anything at all.
    @Test("The projection is not empty for every state")
    func theProjectionIsNotEmptyForEveryState() {
        #expect(SecurityPresentation.identityFields(for: .signed(Self.ghostty)).isEmpty == false)
        #expect(SecurityPresentation.identityFields(for: .adHoc(identifier: "x-1")).isEmpty == false)
    }

    /// The row summary is unchanged and still leads with the team — this addition
    /// supplements it rather than replacing it, so nothing that already worked
    /// moved.
    @Test("The existing signing label is untouched")
    func theExistingSigningLabelIsUntouched() {
        #expect(ArtifactSigningState.signed(Self.ghostty).label == "Signed by 24VZTF6M5V")
        #expect(ArtifactSigningState.adHoc(identifier: "rg-abc").label == "Ad-hoc signed")
    }
}
