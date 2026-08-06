//
//  ReleaseNotesCompositionTests.swift
//  cellarTests
//

import Catalog
import Foundation
import ReleaseNotes
import Testing

@testable import cellar

/// What the app target composes, and what it must not.
///
/// This suite exists at the app layer for a reason recorded in `tasks.md` rather
/// than discovered here: `ReleaseNotes` depends on `Catalog` alone, so it can see
/// neither `SecurityKit` nor `BrewClient`. Two claims therefore cannot be made
/// inside `CellarCore` at all — that the two Keychain service names differ, and
/// that a bulk upgrade reaches no release-notes egress — because no target there
/// sees both halves. This is the only place that does.
///
/// The first test is also the **pbxproj edit's test**: `import ReleaseNotes`
/// resolves only if the product link reached the target.
@Suite("Release-notes composition")
struct ReleaseNotesCompositionTests {
    // MARK: - The product link

    /// The whole of task 11.1, asserted rather than assumed.
    ///
    /// The app imports `SecurityKit` today with **no** product link, because
    /// linked `Persistence` depends on it and carries it transitively.
    /// `ReleaseNotes` has no such carrier — nothing depends on it, by design — so
    /// the link is structurally required, and this test is what fails when it is
    /// missing.
    @Test("The ReleaseNotes product is linked into the app target and its types resolve")
    func theReleaseNotesProductIsLinkedIntoTheAppTarget() throws {
        let repository = try #require(GitHubRepository(owner: "sharkdp", name: "hyperfine"))

        #expect(repository.slug == "sharkdp/hyperfine")
        #expect(ReleaseNotes.cacheFileName == "release-notes-v1.json")
        #expect(ReleaseNotesSchema.currentVersion == 1)
        #expect(GitHubReleaseNotesSource.baseURL == "https://api.github.com/")
    }

    // MARK: - The disclosure

    /// The disclosure is a **named constant**, not a literal buried in a view
    /// body, so the sentence the user consented to has one home — which is what
    /// makes `ReleaseNotesConsent.grantedAt` meaningful as a version of the
    /// question that was asked.
    @Test("The consent surface renders the disclosure constant, not a body literal")
    func theConsentSurfaceRendersTheDisclosureConstant() throws {
        let sources = try AppSecuritySources.load()
        let sheet = try #require(
            sources.first { $0.name == "ReleaseNotesConsentSheet.swift" },
            "the app has no ReleaseNotesConsentSheet.swift"
        )

        // It renders the constant.
        #expect(sheet.code.contains("Self.whatIsSent"))
        // And the sheet's source contains **no** host literal at all: the host
        // may only reach the user through the constant, so a copy edit cannot
        // leave the sheet saying one thing and the library another.
        #expect(
            sheet.code.contains("api.github.com") == false,
            "the sheet names the host in its own source rather than through the constant"
        )
    }

    @Test("The app-side disclosure names the host, what is sent, and claims no anonymity")
    func theAppSideDisclosureNamesTheHostAndWhatIsSent() {
        let disclosure = ReleaseNotesConsentSheet.whatIsSent

        #expect(disclosure.contains("api.github.com"))
        #expect(disclosure.lowercased().contains("repository name"))
        #expect(disclosure.lowercased().contains("installed"))
        #expect(disclosure.lowercased().contains("upgrade"))

        for forbidden in ["anonymous", "nothing about this mac", "no identifying"] {
            #expect(
                disclosure.lowercased().contains(forbidden) == false,
                "the disclosure claims \(forbidden)"
            )
        }
    }

    /// The spec requires the disclosure to be **supplied by `CellarCore`**, and
    /// this is that requirement as an equality: the sheet shows the library's
    /// sentence, not a paraphrase of it. Two copies could drift; one cannot.
    @Test("The sheet shows the library's disclosure verbatim")
    func theSheetShowsTheLibrarysDisclosureVerbatim() {
        #expect(ReleaseNotesConsentSheet.whatIsSent == ReleaseNotesConsent.disclosure)
        #expect(ReleaseNotesConsentSheet.whatIsSent.isEmpty == false)
    }

    // MARK: - The presentable states

    /// The five outcomes reach the surface as five **distinct** presentable
    /// states, decided by a plain value type that needs no view to test.
    @Test("Every outcome maps to a distinct presentable state")
    func everyOutcomeMapsToADistinctPresentableState() {
        let resolved = ResolvedRepository(
            repository: GitHubRepository(owner: "acme", name: "foo")!,
            source: .homepage,
            agreeingSourceCount: 1
        )
        let outcomes: [ReleaseNotesOutcome] = [
            .notes(resolved, GitHubRelease(tagName: "v2.44.0", name: "2.44.0", body: "notes")),
            .unresolvableRepository(triedSources: Set(RepositorySource.allCases)),
            .repositoryPublishesNoReleases(resolved),
            .noReleaseMatchesVersion(resolved, version: "2.44.0", inspected: 26, pageWasFull: false),
            .unavailable(.rateLimited(
                RateLimitStatus(limit: 60, remaining: 0, resetAt: Date(timeIntervalSince1970: 1))
            ))
        ]

        let headlines = outcomes.map { ReleaseNotesPresentation(outcome: $0).headline }

        #expect(Set(headlines).count == 5, "two outcomes render the same headline: \(headlines)")
        #expect(headlines.allSatisfy { $0.isEmpty == false })
    }

    /// The rate-limited state must not read as an absence. It is the one place
    /// where a vague sentence would actively mislead: a user told "no release
    /// notes" will conclude the project publishes none.
    @Test("A rate-limited state shows the reset time and the token affordance, not an absence")
    func aRateLimitedStateShowsTheResetTimeAndTheTokenAffordance() {
        let reset = Date(timeIntervalSince1970: 1_786_055_400)
        let presentation = ReleaseNotesPresentation(
            outcome: .unavailable(.rateLimited(
                RateLimitStatus(limit: 60, remaining: 0, resetAt: reset)
            ))
        )

        #expect(presentation.isRateLimited)
        #expect(presentation.resetAt == reset)
        #expect(presentation.offersTokenAffordance)

        // And it does not read as one of the absences.
        let absence = ReleaseNotesPresentation(
            outcome: .repositoryPublishesNoReleases(
                ResolvedRepository(
                    repository: GitHubRepository(owner: "acme", name: "foo")!,
                    source: .homepage,
                    agreeingSourceCount: 1
                )
            )
        )
        #expect(presentation.headline != absence.headline)
        #expect(presentation.headline.lowercased().contains("no release notes") == false)
        #expect(absence.offersTokenAffordance == false)
        #expect(absence.isRateLimited == false)
    }

    /// A page that filled its bound is a *qualified* miss, and the copy has to
    /// say so — otherwise the app asserts an absolute absence it cannot know.
    @Test("A page-was-full miss reads as a qualified miss, not an absolute absence")
    func aPageWasFullMissReadsAsQualified() {
        let resolved = ResolvedRepository(
            repository: GitHubRepository(owner: "acme", name: "foo")!,
            source: .homepage,
            agreeingSourceCount: 1
        )

        let qualified = ReleaseNotesPresentation(outcome: .noReleaseMatchesVersion(
            resolved, version: "0.1.0", inspected: 30, pageWasFull: true
        ))
        let unqualified = ReleaseNotesPresentation(outcome: .noReleaseMatchesVersion(
            resolved, version: "0.1.0", inspected: 26, pageWasFull: false
        ))

        #expect(qualified.detail != unqualified.detail)
        #expect(qualified.detail.contains("30"), "the qualified miss hides how far it looked")
        #expect(qualified.isQualifiedMiss)
        #expect(unqualified.isQualifiedMiss == false)
    }

    /// A consent refusal must show the **consent surface**, not a spinner and not
    /// an empty sheet — decided by a value, so the E2E test is confirming a rule
    /// rather than discovering one.
    @Test("A consent refusal asks for consent rather than reporting an absence")
    func aConsentRefusalAsksForConsent() {
        let presentation = ReleaseNotesPresentation(
            outcome: .unavailable(.blockedPendingConsent)
        )

        #expect(presentation.needsConsent)
        #expect(presentation.isRateLimited == false)
        #expect(presentation.headline.isEmpty == false)
        // Every other state does not ask for consent, so the flag is a decision
        // and not a default.
        #expect(
            ReleaseNotesPresentation(outcome: .unavailable(.transport)).needsConsent == false
        )
    }

    /// The row's own affordance is a value too: it is offered only when the row
    /// is outdated **and** a repository resolves, so a package nobody could ask
    /// about never shows a button that cannot work.
    @Test("The row affordance is offered only for an outdated package with a resolvable repository")
    func theRowAffordanceIsOfferedOnlyWhenItCanWork() {
        let resolvable = RepositoryCandidates(
            homepage: "https://github.com/acme/foo",
            headURL: nil, stableURL: nil, caskDownloadURL: nil
        )
        let unresolvable = RepositoryCandidates(
            homepage: "https://gnu.org/software/foo",
            headURL: nil, stableURL: nil, caskDownloadURL: nil
        )

        #expect(ReleaseNotesAffordance(isOutdated: true, candidates: resolvable).isOffered)
        #expect(ReleaseNotesAffordance(isOutdated: false, candidates: resolvable).isOffered == false)
        #expect(ReleaseNotesAffordance(isOutdated: true, candidates: unresolvable).isOffered == false)
        #expect(ReleaseNotesAffordance(isOutdated: false, candidates: unresolvable).isOffered == false)
    }

    /// Deciding whether to offer the action costs nothing, which is what makes it
    /// safe to ask on every row of a long list.
    @Test("Deciding whether to offer the action issues no request")
    func decidingWhetherToOfferTheActionIssuesNoRequest() {
        let spy = CompositionRequestSpy()
        spy.install()
        defer { spy.uninstall() }

        for index in 0..<200 {
            _ = ReleaseNotesAffordance(
                isOutdated: true,
                candidates: RepositoryCandidates(
                    homepage: "https://github.com/acme/foo-\(index)",
                    headURL: nil, stableURL: nil, caskDownloadURL: nil
                )
            ).isOffered
        }

        #expect(spy.observedCount == 0, "the affordance cost \(spy.observedCount) requests")
    }
}
