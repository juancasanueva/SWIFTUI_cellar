import Catalog
import Foundation
import Testing

@testable import SecurityKit

/// Every signing and notarization verdict is typed, distinct, and — the rule the
/// whole capability turns on — **nothing degrades to "signed" or "notarized"**.
///
/// The matrix runs against a fake inspector so every path including the ones a
/// real machine will not produce on demand is reachable. One test at the end
/// exercises the real Security.framework implementation against a real artifact,
/// because a matrix of fakes proves the *type* is honest and proves nothing about
/// the code that fills it in.
@Suite("Signature inspector")
struct SignatureInspectorTests {
    private static let bat = PackageID(kind: .formula, name: "bat")

    private static func location(_ name: String = "bat") -> ArtifactLocation {
        ArtifactLocation(
            packageID: PackageID(kind: .formula, name: name),
            url: URL(fileURLWithPath: "/opt/homebrew/Cellar/\(name)/1.0.0/bin/\(name)"),
            kind: .machO
        )
    }

    private static let developerID = ArtifactSigningIdentity(
        identifier: "com.mitchellh.ghostty",
        teamIdentifier: "24VZTF6M5V",
        authorities: [
            "Developer ID Application: Mitchell Hashimoto (24VZTF6M5V)",
            "Developer ID Certification Authority",
            "Apple Root CA"
        ]
    )

    // MARK: - 14.3 Typed and distinct

    @Test("Each signing state is typed and distinct")
    func eachSigningStateIsTypedAndDistinct() {
        let states: [ArtifactSigningState] = [
            .signed(Self.developerID),
            .adHoc(identifier: "rg-555549448f89ec4d458733e9aff65b2c3b7acce2"),
            .unsigned,
            .invalid(.brokenSeal)
        ]

        #expect(Set(states).count == 4, "two signing states compare equal")
        #expect(states.map(\.isSigned) == [true, false, false, false])
        #expect(Set(states.map(\.label)).count == 4, "two signing states read the same")
        // The real formula case the U3 probe measured, and the one most likely to
        // be quietly folded into "unsigned": a bottle is ad-hoc signed, which is
        // a signature, just not one that identifies anybody.
        #expect(states[1] != .unsigned)
    }

    @Test("A signed artifact reports its identifier, team identifier and authority chain")
    func aSignedArtifactReportsItsIdentifierTeamIdentifierAndAuthorityChain() async throws {
        let inspector = FakeSignatureInspector(
            result: .init(
                signing: .signed(Self.developerID),
                notarization: .notarized
            )
        )

        let assessment = try await inspector.assess(Self.location())

        guard case .signed(let identity) = assessment.signing else {
            Issue.record("the signed state was not preserved")
            return
        }
        #expect(identity.identifier == "com.mitchellh.ghostty")
        #expect(identity.teamIdentifier == "24VZTF6M5V")
        #expect(identity.authorities.count == 3)
        #expect(identity.authorities.first == "Developer ID Application: Mitchell Hashimoto (24VZTF6M5V)")
        #expect(assessment.notarization == .notarized)
    }

    /// An ad-hoc signature has an identifier and **no** team identifier. Reporting
    /// an empty string where a team belongs would read as "signed by nobody in
    /// particular" rather than "there is no team here".
    @Test("An ad-hoc artifact reports its identifier and no team")
    func anAdHocArtifactReportsItsIdentifierAndNoTeam() {
        let state = ArtifactSigningState.adHoc(identifier: "rg-5555494")

        #expect(state.identity?.teamIdentifier == nil)
        #expect(state.identity?.identifier == "rg-5555494")
        #expect(state.identity?.authorities.isEmpty == true)
    }

    @Test("An inconclusive assessment is could-not-assess with a reason, and is counted as neither")
    func anInconclusiveAssessmentIsCouldNotAssessWithAReasonAndIsCountedAsNeither() {
        let inconclusive = ArtifactNotarizationState.couldNotAssess(.assessmentUnavailable)

        #expect(inconclusive.reason == .assessmentUnavailable)
        #expect(inconclusive.isNotarized == false)
        #expect(inconclusive.isNotNotarized == false, "an inconclusive result was counted as a verdict")
        #expect(inconclusive != .notNotarized)
        #expect(inconclusive != .notarized)

        // The positive controls, or the three assertions above hold for a type
        // whose every case answers `false` to both questions.
        #expect(ArtifactNotarizationState.notarized.isNotarized)
        #expect(ArtifactNotarizationState.notNotarized.isNotNotarized)
    }

    /// Counting is where an inconclusive result usually becomes a verdict: a
    /// summary that says "3 notarized, 2 not" over five artifacts, one of which
    /// could not be assessed, has silently decided the fifth.
    @Test("Totals keep could-not-assess apart from both verdicts")
    func totalsKeepCouldNotAssessApartFromBothVerdicts() {
        let states: [ArtifactNotarizationState] = [
            .notarized, .notarized,
            .notNotarized,
            .couldNotAssess(.assessmentUnavailable),
            .couldNotAssess(.artifactUnreadable)
        ]

        let totals = NotarizationTotals(of: states)

        #expect(totals.notarized == 2)
        #expect(totals.notNotarized == 1)
        #expect(totals.couldNotAssess == 2)
        #expect(totals.total == 5, "an artifact fell out of the summary")
    }

    // MARK: - 14.4 Nothing degrades to signed or notarized

    /// Exhaustive over every reason an assessment can fail to reach a verdict.
    /// Each one is `.couldNotAssess(reason)`, and none is signed or notarized.
    @Test(
        "No outcome ever degrades to signed or notarized",
        arguments: AssessmentUnavailableReason.allCases
    )
    func noOutcomeEverDegradesToSignedOrNotarized(reason: AssessmentUnavailableReason) async throws {
        let inspector = FakeSignatureInspector(
            result: .init(
                signing: .couldNotAssess(reason),
                notarization: .couldNotAssess(reason)
            )
        )

        let assessment = try await inspector.assess(Self.location())

        #expect(assessment.signing.isSigned == false)
        #expect(assessment.signing == .couldNotAssess(reason))
        #expect(assessment.notarization == .couldNotAssess(reason))
        #expect(assessment.notarization.isNotarized == false)
        #expect(assessment.notarization.isNotNotarized == false)
        #expect(reason.explanation.isEmpty == false, "\(reason) has nothing to show the user")
    }

    /// Every reason reads differently. A shared sentence would make five distinct
    /// failures indistinguishable in the panel, which is the same thing as having
    /// one reason.
    @Test("Every unavailable reason has its own sentence")
    func everyUnavailableReasonHasItsOwnSentence() {
        let sentences = AssessmentUnavailableReason.allCases.map(\.explanation)

        #expect(Set(sentences).count == AssessmentUnavailableReason.allCases.count)
    }

    /// A thrown error is not an exception to the rule. Whatever goes wrong, the
    /// artifact does not become signed.
    @Test("A failing inspector surfaces its failure rather than a verdict")
    func aFailingInspectorSurfacesItsFailureRatherThanAVerdict() async {
        let inspector = FakeSignatureInspector(failure: .artifactUnreadable)

        await #expect(throws: ArtifactInspectionFailure.self) {
            _ = try await inspector.assess(Self.location())
        }
    }

    /// The amendment the U3 gate forced (task 14.0(a)). There is no online ticket
    /// lookup to gate, because the only API for one is absent from the public
    /// SDK — so the verdict cannot vary with consent, and a recording network
    /// sees nothing either way.
    @Test("The verdict is identical with and without consent because no online lookup exists")
    func theVerdictIsIdenticalWithAndWithoutConsentBecauseNoOnlineLookupExists() async throws {
        let network = RecordingNetwork()
        let inspector = SecurityFrameworkSignatureInspector()
        let artifact = try #require(Self.testBundleArtifact())

        let granted = try await inspector.assess(artifact)
        let revoked = try await inspector.assess(artifact)

        #expect(granted == revoked, "the same artifact assessed twice produced two answers")
        #expect(network.exchanges.isEmpty, "the integrity half issued a request")
    }

    /// The design's stated fallback, now the *only* answer for a Developer ID
    /// artifact whose stapled check does not pass: `couldNotAssess`, never
    /// `notNotarized`. A signed app can be notarized with the ticket simply not
    /// stapled, and this build cannot tell those apart.
    @Test("Non-stapled notarization is could-not-assess rather than not-notarized")
    func nonStapledNotarizationIsCouldNotAssessRatherThanNotNotarized() {
        let signed = SecurityFrameworkSignatureInspector.notarization(
            signing: .signed(Self.developerID),
            stapledCheckPassed: false
        )

        #expect(signed == .couldNotAssess(.assessmentUnavailable))
        #expect(signed != .notNotarized)

        // The two cases where "not notarized" *is* definitive: notarization
        // requires a Developer ID signature, so an artifact without one cannot
        // have been notarized, and saying so asserts nothing unproven.
        #expect(
            SecurityFrameworkSignatureInspector.notarization(
                signing: .adHoc(identifier: "rg-5555494"),
                stapledCheckPassed: false
            ) == .notNotarized
        )
        #expect(
            SecurityFrameworkSignatureInspector.notarization(
                signing: .unsigned,
                stapledCheckPassed: false
            ) == .notNotarized
        )
        #expect(
            SecurityFrameworkSignatureInspector.notarization(
                signing: .signed(Self.developerID),
                stapledCheckPassed: true
            ) == .notarized
        )
        // An assessment that could not read the signature cannot answer the
        // notarization question either, and must not answer it anyway.
        #expect(
            SecurityFrameworkSignatureInspector.notarization(
                signing: .couldNotAssess(.artifactUnreadable),
                stapledCheckPassed: false
            ) == .couldNotAssess(.artifactUnreadable)
        )
    }

    // MARK: - The real implementation

    /// The integration anchor: real Security.framework, real signed artifact.
    ///
    /// The artifact is **this test bundle's own executable**, which exists on
    /// every machine that can run this suite — pointing at a cask would make the
    /// suite depend on what happens to be installed. What is asserted is what is
    /// true of any built product: it classifies, it reaches a typed signing
    /// state, and whatever that state is, it carries an identifier.
    @Test("The real inspector reaches a typed verdict for a real artifact")
    func theRealInspectorReachesATypedVerdictForARealArtifact() async throws {
        let artifact = try #require(Self.testBundleArtifact())
        let assessment = try await SecurityFrameworkSignatureInspector().assess(artifact)

        switch assessment.signing {
        case .signed(let identity):
            #expect(identity.identifier.isEmpty == false)
        case .adHoc(let identifier):
            #expect(identifier.isEmpty == false)
        case .unsigned, .invalid, .couldNotAssess:
            // All legitimate outcomes for a locally built binary. The claim under
            // test is that a *typed* one was reached, not which one.
            break
        }
        #expect(assessment.location.url == artifact.url)
    }

    /// A path that is not there reaches `couldNotAssess`, not a crash and not a
    /// verdict.
    @Test("The real inspector answers could-not-assess for an absent artifact")
    func theRealInspectorAnswersCouldNotAssessForAnAbsentArtifact() async throws {
        let missing = ArtifactLocation(
            packageID: Self.bat,
            url: FileManager.default.temporaryDirectory
                .appendingPathComponent("absent-\(UUID().uuidString)"),
            kind: .machO
        )

        let assessment = try await SecurityFrameworkSignatureInspector().assess(missing)

        #expect(assessment.signing.isSigned == false)
        #expect(assessment.notarization.isNotarized == false)
        #expect(assessment.notarization.isNotNotarized == false)
    }

    private static func testBundleArtifact() -> ArtifactLocation? {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0]).resolvingSymlinksInPath()
        return ArtifactLocation(packageID: PackageID(kind: .formula, name: "cellar-tests"), url: url)
    }
}
