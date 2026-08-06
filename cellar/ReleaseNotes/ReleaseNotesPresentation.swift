//
//  ReleaseNotesPresentation.swift
//  cellar
//

import Foundation
import ReleaseNotes

/// One outcome, turned into the sentences a surface shows.
///
/// A plain `nonisolated` value type and not a view, for the reason the whole
/// capability is shaped around: **the five outcomes must reach the user as five
/// different things**, and if that mapping lives inside a `body` it can only be
/// checked by rendering a view and reading pixels. Here it is a function from an
/// enum to two strings and four flags, and a test can assert that no two outcomes
/// produce the same headline.
///
/// The copy is deliberately specific. "No release notes" is the sentence this
/// type exists to prevent: a user shown it when the truth is "GitHub is
/// rate-limiting you until 21:15" will reasonably conclude the project publishes
/// nothing.
nonisolated struct ReleaseNotesPresentation: Sendable, Hashable {
    let outcome: ReleaseNotesOutcome

    init(outcome: ReleaseNotesOutcome) {
        self.outcome = outcome
    }

    // MARK: - The sentences

    var headline: String {
        switch outcome {
        case .notes(_, let release):
            release.name?.isEmpty == false ? release.name! : release.tagName
        case .unresolvableRepository:
            "No GitHub repository found for this package"
        case .repositoryPublishesNoReleases:
            "This project publishes no releases on GitHub"
        case .noReleaseMatchesVersion:
            "No release notes for this version"
        case .unavailable(let failure):
            Self.headline(for: failure)
        }
    }

    var detail: String {
        switch outcome {
        case .notes(let resolved, let release):
            "\(resolved.repository.slug) · \(release.tagName)"
        case .unresolvableRepository(let tried):
            "Cellar looked at \(tried.count) published URLs for this package and none of them "
                + "named a GitHub repository. Nothing was sent anywhere."
        case .repositoryPublishesNoReleases(let resolved):
            "\(resolved.repository.slug) has no published releases. Some projects tag versions "
                + "without writing release notes."
        case .noReleaseMatchesVersion(let resolved, let version, let inspected, let pageWasFull):
            pageWasFull
                ? "\(resolved.repository.slug) published no release tagged \(version) among the "
                    + "\(inspected) most recent. Your version may be older than that."
                : "\(resolved.repository.slug) publishes \(inspected) releases and none of them "
                    + "is tagged \(version)."
        case .unavailable(let failure):
            Self.detail(for: failure)
        }
    }

    // MARK: - What the surface must offer

    /// A refusal pending consent asks for consent. It must never render as an
    /// absence, a spinner, or an empty sheet — the user has simply not been asked
    /// yet.
    var needsConsent: Bool {
        outcome.failure == .blockedPendingConsent
    }

    var isRateLimited: Bool { outcome.failure?.isRateLimited == true }

    /// When the budget resets, so the surface can say *when* rather than "later".
    var resetAt: Date? { outcome.failure?.rateLimit?.resetAt }

    /// Whether to offer the personal-access-token field.
    ///
    /// Only on the rate-limited state, and only there. Offering it beside a
    /// transport failure would imply a token fixes a problem it cannot touch.
    var offersTokenAffordance: Bool { isRateLimited }

    /// Whether the miss is *qualified* — the page filled its bound, so the claim
    /// is "not among the most recent releases fetched" and not an absolute
    /// absence Cellar has no way of knowing.
    var isQualifiedMiss: Bool {
        if case .noReleaseMatchesVersion(_, _, _, let pageWasFull) = outcome { pageWasFull }
        else { false }
    }

    var release: GitHubRelease? { outcome.release }

    /// The prepared body, and `nil` when there is no matched release.
    ///
    /// An empty body is a `RenderedReleaseNote` with no blocks, not a `nil` — a
    /// matched release with nothing written in it is still a matched release.
    var renderedBody: RenderedReleaseNote? {
        guard let release = outcome.release else { return nil }
        return ReleaseNoteRenderer.render(release.body ?? "")
    }

    /// The link to the release on GitHub, when it passes the allowlist.
    var browsableLink: URL? {
        guard let raw = outcome.release?.htmlURL?.absoluteString else { return nil }
        return ReleaseNoteRenderer.browsableLink(raw)
    }

    // MARK: - Failures

    private static func headline(for failure: ReleaseNotesFailure) -> String {
        switch failure {
        case .blockedPendingConsent: "Ask GitHub what changed in this release?"
        case .rateLimited: "GitHub is rate-limiting Cellar"
        case .unauthorized: "GitHub rejected the stored token"
        case .httpStatus: "GitHub could not answer"
        case .transport: "Cellar could not reach GitHub"
        case .payloadTooLarge: "That release page was too large to read"
        case .malformedPayload: "GitHub sent something Cellar could not read"
        case .cancelled: "Cancelled"
        }
    }

    private static func detail(for failure: ReleaseNotesFailure) -> String {
        switch failure {
        case .blockedPendingConsent:
            return "Cellar has not asked GitHub anything yet. Turn release notes on to allow it."
        case .rateLimited(let status):
            var sentence = "Unauthenticated requests are limited to "
                + "\(status.limit.map(String.init) ?? "a few") an hour, and this hour's are used up."
            if let reset = status.resetAt {
                sentence += " The limit resets at \(Self.time.string(from: reset))."
            }
            return sentence + " Adding a GitHub token raises the limit."
        case .unauthorized:
            return "The stored personal access token was refused. Remove it or paste a new one; "
                + "release notes also work with no token at all."
        case .httpStatus(let code):
            return "GitHub answered \(code). This is not a rate limit and not an answer about the "
                + "project's releases."
        case .transport:
            return "The request never reached GitHub. This says nothing about whether the project "
                + "publishes releases."
        case .payloadTooLarge:
            return "The response was larger than Cellar is willing to read, so nothing was decoded."
        case .malformedPayload:
            return "The response was not a list of releases."
        case .cancelled:
            return "The request was cancelled."
        }
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

/// Whether to offer the "What's new?" action for a row at all.
///
/// A value rather than an `if` inside a `body`, because it is asked once per row
/// on a list that can be hundreds long and the answer must provably cost
/// nothing: `GitHubRepositoryResolver.resolve` is a pure function over four
/// strings, issues no request, reads no cache and spawns nothing.
///
/// Both conditions are required. Offering it on an up-to-date package would make
/// it a browsing affordance rather than an upgrade one (D4); offering it where no
/// repository resolves would show a button that cannot work.
nonisolated struct ReleaseNotesAffordance: Sendable, Hashable {
    let isOutdated: Bool
    let resolved: ResolvedRepository?

    init(isOutdated: Bool, candidates: RepositoryCandidates) {
        self.isOutdated = isOutdated
        self.resolved = GitHubRepositoryResolver.resolve(candidates)
    }

    var isOffered: Bool { isOutdated && resolved != nil }

    /// The repository the action would ask about, for a tooltip that names it —
    /// so the user knows what leaves the machine before they click.
    var repositorySlug: String? { resolved?.repository.slug }
}
