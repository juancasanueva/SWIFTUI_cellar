import Foundation

/// Why a release note could not be produced.
///
/// Every case here is a *reason a request did not answer*, and each one is
/// distinguishable from every other. That matters most for the first two: a
/// rate-limit refusal and a rejected credential are both "GitHub said 403-ish"
/// and mean entirely different things to a user. One says wait; the other says
/// your token is wrong.
///
/// It conforms to `Error` so the acquisition seam can declare it as a **typed**
/// thrown type: a call site therefore handles exactly these reasons and cannot be
/// handed some other library's error to interpret. It is still a value first —
/// the store turns each one into `.unavailable(_)` and renders it, rather than
/// letting a `catch` decide what the user sees.
public enum ReleaseNotesFailure: Error, Sendable, Hashable, Codable {
    /// No release-notes grant is recorded. No request was issued.
    case blockedPendingConsent
    /// `403` or `429` with an exhausted budget. Carries the reset time so the
    /// surface can say *when*, which is the difference between an instruction and
    /// a shrug. **Never** written to the cache, and never a retry trigger.
    case rateLimited(RateLimitStatus)
    /// `401`. A rejected token, which claims no reset time and no budget.
    case unauthorized
    /// Any other non-success status, carrying the code.
    case httpStatus(Int)
    /// The request never reached a status.
    case transport
    /// The body exceeded the byte limit. Nothing was decoded.
    case payloadTooLarge
    /// A 200 whose body was not a release list.
    case malformedPayload
    /// The work was superseded or the user navigated away. A typed value, never
    /// an error dialog.
    case cancelled

    /// Whether this is *the* rate-limit reason. Exactly one case answers `true`,
    /// which is what makes "a rejected token is not a rate limit" checkable.
    public var isRateLimited: Bool {
        if case .rateLimited = self { true } else { false }
    }

    /// The budget this refusal was made against, and `nil` for every reason that
    /// is not a rate limit — so no other failure can claim a reset time.
    public var rateLimit: RateLimitStatus? {
        if case .rateLimited(let status) = self { status } else { nil }
    }
}

/// What one opened release-notes request settled as: one success and four
/// absences.
///
/// ## Why five and not one optional
///
/// "No release notes" is at least five different situations, and a user shown the
/// same sentence for all of them will draw a wrong conclusion from four of them.
/// Nobody could work out which repository this is; the repository publishes no
/// releases at all; it publishes releases but none for your version; we were
/// refused; we could not ask. Each of those has a different next step, and only a
/// distinct value can carry it.
///
/// None of the four non-matched cases is an empty string, a `nil`, or a pending
/// state that never settles, and each is discriminable by pattern rather than by
/// reading free text.
public enum ReleaseNotesOutcome: Sendable, Hashable, Codable {
    /// A release matching the installed version, and the repository it came from.
    /// An empty body is still this case — an empty release note is a fact about
    /// the release, not an absence.
    case notes(ResolvedRepository, GitHubRelease)
    /// None of the four published URLs named a GitHub repository. Carries the
    /// sources that were tried, so the claim is "we looked at these four and
    /// found nothing" rather than a shrug.
    case unresolvableRepository(triedSources: Set<RepositorySource>)
    /// The repository resolved and answered with an empty list.
    case repositoryPublishesNoReleases(ResolvedRepository)
    /// The repository publishes releases, and none of them is this version.
    ///
    /// `inspected` and `pageWasFull` are what keep the claim honest. A page that
    /// filled its bound may simply not reach far enough back, so the surface can
    /// say "not among the 30 most recent releases" instead of asserting an
    /// absolute absence it cannot know.
    case noReleaseMatchesVersion(
        ResolvedRepository, version: String, inspected: Int, pageWasFull: Bool
    )
    /// The question could not be answered, with a typed reason.
    case unavailable(ReleaseNotesFailure)

    /// Whether this answer may be written to the cache.
    ///
    /// `false` for `.unavailable` and only for it (D3). A cached refusal outlives
    /// the window it describes: a rate-limit wall that lifts at 21:15 would keep
    /// being reported for the next 24 hours, turning a transient condition into a
    /// persistent lie the user cannot clear. An absence, by contrast, is a fact
    /// about the repository and is worth remembering for a day.
    public var isCacheable: Bool {
        if case .unavailable = self { false } else { true }
    }

    /// The repository behind this answer, when there is one.
    public var resolvedRepository: ResolvedRepository? {
        switch self {
        case .notes(let resolved, _),
             .repositoryPublishesNoReleases(let resolved),
             .noReleaseMatchesVersion(let resolved, _, _, _):
            resolved
        case .unresolvableRepository, .unavailable:
            nil
        }
    }

    /// The matched release, when there is one.
    public var release: GitHubRelease? {
        if case .notes(_, let release) = self { release } else { nil }
    }

    /// The typed reason this could not be answered, when it could not be.
    public var failure: ReleaseNotesFailure? {
        if case .unavailable(let failure) = self { failure } else { nil }
    }
}
