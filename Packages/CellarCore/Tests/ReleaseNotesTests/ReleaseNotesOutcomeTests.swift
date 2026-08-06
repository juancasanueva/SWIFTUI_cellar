import Foundation
import ReleaseNotes
import Testing

/// Four absences are four values, and a rate-limit refusal is none of them.
///
/// This is the requirement the whole capability is shaped around. "No release
/// notes" is at least five different situations — nobody could work out which
/// repository this is; the repository publishes no releases at all; it publishes
/// releases but not for your version; we were refused; we could not ask — and
/// collapsing any two of them produces a sheet that lies. A user told "no release
/// notes" when the truth is "GitHub is rate-limiting you until 21:15" will
/// reasonably conclude the project publishes nothing.
///
/// So each is a distinct case of one enum, none of them is an empty string or a
/// `nil`, and every one is discriminable without reading free text.
@Suite("Release-notes outcomes")
struct ReleaseNotesOutcomeTests {
    // MARK: - Arrangement

    private var repository: GitHubRepository {
        GitHubRepository(owner: "acme", name: "foo")!
    }

    private var resolved: ResolvedRepository {
        ResolvedRepository(repository: repository, source: .homepage, agreeingSourceCount: 1)
    }

    private var release: GitHubRelease {
        GitHubRelease(tagName: "v2.44.0", name: "2.44.0", body: "notes")
    }

    private var allFive: [ReleaseNotesOutcome] {
        [
            .notes(resolved, release),
            .unresolvableRepository(triedSources: Set(RepositorySource.allCases)),
            .repositoryPublishesNoReleases(resolved),
            .noReleaseMatchesVersion(
                resolved, version: "2.44.0", inspected: 26, pageWasFull: false
            ),
            .unavailable(.rateLimited(RateLimitStatus(limit: 60, remaining: 0, resetAt: Date())))
        ]
    }

    // MARK: - Five, and mutually distinct

    @Test("All five outcomes are reachable and no two of them are equal")
    func allFiveOutcomesAreReachableAndDistinct() {
        let outcomes = allFive

        #expect(outcomes.count == 5)
        #expect(Set(outcomes).count == 5, "two outcomes compared equal")
    }

    /// The claim that matters more than equality: a consumer can tell them apart
    /// **without parsing free text**. A `switch` that must be exhaustive is the
    /// strongest form of that, so this test is written as one.
    @Test("Each outcome is discriminable by pattern, not by reading a string")
    func eachOutcomeIsDiscriminableByPattern() {
        var seen: Set<String> = []

        for outcome in allFive {
            switch outcome {
            case .notes(let resolved, let release):
                #expect(resolved.repository.name == "foo")
                #expect(release.tagName == "v2.44.0")
                seen.insert("notes")
            case .unresolvableRepository(let tried):
                #expect(tried == Set(RepositorySource.allCases))
                seen.insert("unresolvable")
            case .repositoryPublishesNoReleases(let resolved):
                #expect(resolved.repository.owner == "acme")
                seen.insert("noReleases")
            case .noReleaseMatchesVersion(_, let version, let inspected, let pageWasFull):
                #expect(version == "2.44.0")
                #expect(inspected == 26)
                #expect(pageWasFull == false)
                seen.insert("noMatch")
            case .unavailable(let failure):
                #expect(failure.isRateLimited)
                seen.insert("unavailable")
            }
        }

        #expect(seen.count == 5, "the switch reached only \(seen.sorted())")
    }

    /// The three absences carry the evidence for their own claim, which is what
    /// lets the sheet say something true rather than something vague.
    @Test("The no-matching-version outcome carries repository, version, count and page bound")
    func theNoMatchingVersionOutcomeCarriesItsEvidence() throws {
        let outcome = ReleaseNotesOutcome.noReleaseMatchesVersion(
            resolved, version: "2.44.0", inspected: 30, pageWasFull: true
        )

        guard case .noReleaseMatchesVersion(let repo, let version, let inspected, let full)
            = outcome
        else {
            Issue.record("the outcome did not carry its payload")
            return
        }

        #expect(repo.repository == repository)
        #expect(version == "2.44.0")
        #expect(inspected == 30)
        // The qualifier that keeps a full page honest: "not among the 30 most
        // recent releases" rather than "no such release exists".
        #expect(full)
    }

    @Test("The unresolvable outcome names the sources that were tried")
    func theUnresolvableOutcomeNamesTheSourcesTried() {
        let outcome = ReleaseNotesOutcome.unresolvableRepository(
            triedSources: Set(RepositorySource.allCases)
        )

        guard case .unresolvableRepository(let tried) = outcome else {
            Issue.record("the outcome did not carry its payload")
            return
        }

        #expect(tried.count == 4)
        #expect(tried.contains(.stableURL))
        #expect(tried.contains(.caskDownloadURL))
        // And it is not the same value as "publishes no releases", which is the
        // absence it is most often confused with.
        #expect(outcome != .repositoryPublishesNoReleases(resolved))
    }

    /// None of the four non-matched outcomes is an empty body, an empty string, a
    /// `nil` or a pending state that never settles. Stated positively: a matched
    /// release with an **empty body** is a fifth thing again, and is not any of
    /// them.
    @Test("A matched release with an empty body is not an absence")
    func aMatchedReleaseWithAnEmptyBodyIsNotAnAbsence() {
        let empty = ReleaseNotesOutcome.notes(
            resolved, GitHubRelease(tagName: "v2.44.0", name: "2.44.0", body: "")
        )

        guard case .notes(_, let release) = empty else {
            Issue.record("an empty body collapsed into another outcome")
            return
        }

        #expect(release.body == "")
        #expect(empty != .repositoryPublishesNoReleases(resolved))
        #expect(
            empty != .noReleaseMatchesVersion(
                resolved, version: "2.44.0", inspected: 1, pageWasFull: false
            )
        )
    }

    // MARK: - Cacheability (D3)

    /// A cached rate-limit refusal outlives the window it describes and turns a
    /// transient wall into a persistent lie, so **no** unavailable outcome is
    /// ever written. Asserted as "false for `.unavailable` and only for it", so a
    /// later case cannot join the exception by accident.
    @Test("Only the unavailable outcome is uncacheable, and every unavailable one is")
    func onlyTheUnavailableOutcomeIsUncacheable() {
        for outcome in allFive {
            if case .unavailable = outcome {
                #expect(outcome.isCacheable == false, "an unavailable outcome was cacheable")
            } else {
                #expect(outcome.isCacheable, "\(outcome) was refused the cache")
            }
        }

        // Every failure reason, not only the rate-limited one: a cached "we could
        // not reach the network" is the same lie one layer down.
        for failure in ReleaseNotesFailure.allTestCases {
            #expect(
                ReleaseNotesOutcome.unavailable(failure).isCacheable == false,
                "\(failure) was cacheable"
            )
        }
    }

    // MARK: - The failure reasons

    @Test("Every failure reason is distinct from the rate-limit reason and from each other")
    func everyFailureReasonIsDistinct() {
        let failures = ReleaseNotesFailure.allTestCases

        #expect(failures.count == 8, "the failure set has \(failures.count) cases")
        #expect(Set(failures).count == failures.count, "two failure reasons compared equal")

        let rateLimited = failures.filter(\.isRateLimited)
        #expect(rateLimited.count == 1, "more than one reason claims to be a rate limit")

        // The pairing the requirement singles out: a rejected credential is not a
        // rate limit, and it claims no reset time or budget.
        #expect(ReleaseNotesFailure.unauthorized.isRateLimited == false)
        #expect(ReleaseNotesFailure.unauthorized.rateLimit == nil)
        #expect(ReleaseNotesFailure.httpStatus(403).isRateLimited == false)
        #expect(ReleaseNotesFailure.transport.isRateLimited == false)
    }

    /// A rate-limit refusal carries its reset time, because "try again later" is
    /// not an instruction and "try again after 21:15" is.
    @Test("The rate-limit reason carries the status it was refused with")
    func theRateLimitReasonCarriesItsStatus() throws {
        let reset = Date(timeIntervalSince1970: 1_786_055_400)
        let failure = ReleaseNotesFailure.rateLimited(
            RateLimitStatus(limit: 60, remaining: 0, resetAt: reset)
        )

        #expect(failure.isRateLimited)
        let status = try #require(failure.rateLimit)
        #expect(status.resetAt == reset)
        #expect(status.limit == 60)
        #expect(status.remaining == 0)
        #expect(status.isExhausted)
    }

    /// `httpStatus` really does carry the status, so a 500 and a 418 are not the
    /// same outcome — and neither of them is the 403 that means a rate limit.
    @Test("A plain HTTP status failure carries its code and is not the 403 rate limit")
    func aPlainHttpStatusFailureCarriesItsCode() {
        #expect(ReleaseNotesFailure.httpStatus(500) != ReleaseNotesFailure.httpStatus(418))
        #expect(
            ReleaseNotesFailure.httpStatus(403)
                != ReleaseNotesFailure.rateLimited(
                    RateLimitStatus(limit: 60, remaining: 0, resetAt: nil)
                )
        )
    }

    @Test("An outcome round-trips through Codable without changing case")
    func anOutcomeRoundTripsThroughCodable() throws {
        for outcome in allFive where outcome.isCacheable {
            let decoded = try JSONDecoder().decode(
                ReleaseNotesOutcome.self,
                from: JSONEncoder().encode(outcome)
            )
            #expect(decoded == outcome, "\(outcome) did not survive a round trip")
        }
    }
}

// MARK: - The exhaustive failure list

extension ReleaseNotesFailure {
    /// Every reason, written out once.
    ///
    /// A hand-written list rather than `CaseIterable`, which associated values
    /// rule out. The count is asserted where it is used, so adding a reason and
    /// forgetting this list fails the suite rather than quietly shrinking the
    /// thing under test.
    static var allTestCases: [ReleaseNotesFailure] {
        [
            .blockedPendingConsent,
            .rateLimited(RateLimitStatus(limit: 60, remaining: 0, resetAt: nil)),
            .unauthorized,
            .httpStatus(500),
            .transport,
            .payloadTooLarge,
            .malformedPayload,
            .cancelled
        ]
    }
}
