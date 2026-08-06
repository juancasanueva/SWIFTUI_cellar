import Foundation

/// Which advisory database answered.
///
/// Two sources with two different jobs: OSV decides *affectedness*, NVD supplies
/// *severity*. Neither is a fallback for the other, so a result always names
/// which one it came from.
public enum AdvisorySourceID: String, Sendable, Hashable, Codable, CaseIterable {
    case osv
    case nvd
}

/// Why a package was not scanned.
///
/// Three cases and **no fourth**. Each one is a different honest gap, and the
/// absence of a `.other(String)` escape is deliberate: a free-text reason is a
/// place to hide a bug, and the spec requires typed values.
public enum NotCoveredReason: String, Sendable, Hashable, Codable, CaseIterable {
    /// The package is absent from the curated mapping table. This is the common
    /// case — real curated coverage is a few percent of an inventory — and it is
    /// the state the presentation is designed around, not an edge case.
    case unmapped
    /// A cask. Only formulae are scanned.
    case kindUnsupported
    /// The installed version cannot be interpreted in the mapped ecosystem's
    /// scheme, so nothing was queried. An answer computed against a string the
    /// database would have coerced is worse than an admitted gap.
    case unsupportedVersionScheme
}

/// How bad a finding is, or that nobody said.
///
/// `unrated` is a **sixth tier, not a missing fifth**. The spec forbids
/// inferring, ranking or defaulting an unscored advisory to medium, so there is
/// no arithmetic anywhere that treats absence as a middling score.
public enum SeverityTier: String, Sendable, Hashable, Codable, CaseIterable {
    case critical
    case high
    case medium
    case low
    case none
    case unrated

    /// Where this tier sits in a rendered list.
    ///
    /// A **bucket position, not a severity judgement**. `unrated` sorts last
    /// because a reader scanning downward should reach everything that was
    /// scored before reaching everything that was not — it does not sort last
    /// because it is "less severe than none". Nothing computes with this value
    /// beyond ordering.
    public var displayOrder: Int {
        switch self {
        case .critical: 0
        case .high: 1
        case .medium: 2
        case .low: 3
        case .none: 4
        case .unrated: 5
        }
    }

    /// Whether a published score produced this tier.
    ///
    /// The one question the presentation is allowed to ask about `unrated`.
    public var isScored: Bool { self != .unrated }
}

/// Whether a result came off the wire or off the disk, and how old it is.
public enum ResultFreshness: Sendable, Hashable {
    case live
    case cached(fetchedAt: Date)
}

/// Why an answer is missing.
///
/// Every case is a *typed* reason a package went unanswered, because the spec
/// forbids an unanswered package from silently becoming a clean one.
public enum AdvisoryError: Error, Sendable, Hashable, Codable {
    /// The response envelope could not be read at all. Nothing in it is
    /// recoverable, so the whole request failed.
    case malformedPayload
    /// This package's own record could not be read, while the rest of the batch
    /// was fine. Not clean — unanswered.
    case malformedRecord
    /// No network was reachable.
    case offline
    /// The source refused on rate grounds. Severity and health are unchanged by
    /// this: a rate limit is not evidence of anything about the package.
    ///
    /// Kept apart from every other non-success status because it is the one that
    /// is *expected*, recoverable and worth retrying later — and because the
    /// captured 429 is seventeen bytes of `text/plain`, so a decoder reached
    /// before the classifier would report it as a malformed payload and lose the
    /// distinction entirely.
    case rateLimited
    /// The request failed below the application layer, or the source answered
    /// with a status that carries no advisory content.
    case transportFailed
    /// The response body exceeded the ceiling this target will read into memory.
    ///
    /// Judged from the byte count **before** the decoder is offered a single
    /// byte, so a hostile or broken origin cannot make the process allocate its
    /// way out of memory on the way to finding out the payload was nonsense.
    case payloadTooLarge
}

/// One advisory that applies to one installed package.
public struct VulnerabilityFinding: Sendable, Hashable, Codable, Identifiable {
    /// The advisory's own identifier in the database that published it —
    /// `GHSA-…`, `PYSEC-…`, `RUSTSEC-…`.
    public let advisoryID: String
    /// The CVE this advisory aliases, when it has one. Enrichment is keyed by
    /// this and by nothing else.
    public let cveID: String?
    public let aliases: [String]
    public let summary: String
    public let severity: SeverityTier
    /// The ecosystem and package name the advisory was actually reported for,
    /// so a finding can be framed as "reported for `<ecosystem>/<package>`"
    /// rather than as a claim about the Homebrew formula.
    public let ecosystem: String
    public let ecosystemPackageName: String
    /// The fixed version the advisory declared, verbatim, or `nil` when it
    /// declared none. Reported even when it cannot be compared — "a fix exists
    /// at 0.18.2" is useful on its own.
    public let declaredFixVersion: String?
    /// What can honestly be said about the installed version against that fix.
    public let fix: FixVersionComparison
    public let answeredBy: AdvisorySourceID
    /// Whether the user already answered this exact finding at this exact
    /// installed version.
    ///
    /// A flag rather than a removal, and that is deliberate. Deleting dismissed
    /// findings would let a package whose every finding was dismissed collapse
    /// into `covered(clean:)`, which is a coverage state the user never
    /// consented to and the spec forbids dismissal from changing. Carrying the
    /// flag keeps the coverage state fixed and leaves suppression to the
    /// presentation, where it belongs.
    public let isDismissed: Bool

    public var id: String { advisoryID }

    public init(
        advisoryID: String,
        cveID: String?,
        aliases: [String],
        summary: String,
        severity: SeverityTier,
        ecosystem: String,
        ecosystemPackageName: String,
        declaredFixVersion: String?,
        fix: FixVersionComparison,
        answeredBy: AdvisorySourceID,
        isDismissed: Bool
    ) {
        self.advisoryID = advisoryID
        self.cveID = cveID
        self.aliases = aliases
        self.summary = summary
        self.severity = severity
        self.ecosystem = ecosystem
        self.ecosystemPackageName = ecosystemPackageName
        self.declaredFixVersion = declaredFixVersion
        self.fix = fix
        self.answeredBy = answeredBy
        self.isDismissed = isDismissed
    }
}

/// The evidence behind a clean result.
///
/// A clean outcome is a **positive claim** — somebody was asked about a specific
/// version and answered "nothing" — so it is not constructible without naming
/// who was asked and about what. That is what stops "we have no findings" from
/// being spelled the same way as "we have no answers".
public struct CleanCoverage: Sendable, Hashable, Codable {
    public let answeredBy: AdvisorySourceID
    /// The version actually put on the wire, which for a Homebrew revision is
    /// the upstream part rather than the installed string.
    public let queriedVersion: String

    public init(answeredBy: AdvisorySourceID, queriedVersion: String) {
        self.answeredBy = answeredBy
        self.queriedVersion = queriedVersion
    }
}

/// What is known about one installed package after a scan.
///
/// Four states, and the type is the whole point. `[VulnerabilityFinding]` plus
/// `isEmpty` would make "no vulnerabilities found" and "nobody could tell us"
/// the same value, and that collapse is the single failure this feature exists
/// to prevent. There is **no `isClean` accessor**: the only way to ask is to
/// match `case .covered(.clean)`, which forces the other three states into view
/// at every call site.
///
/// ## Why `Coverage` is nested rather than two `covered` cases
///
/// The design writes these as `.covered(findings:)` and `.covered(clean:)`.
/// Swift *declares* two same-named cases with different labels without
/// complaint — and then refuses to pattern-match them: every `case .covered(…)`
/// resolves to whichever was declared last, and the other becomes
/// `error: tuple pattern element label 'findings' must be 'clean'`. Measured,
/// not assumed.
///
/// So the pair is nested one level. The four states, their names and the absence
/// of any boolean shortcut are all unchanged; `.covered(.findings)` and
/// `.covered(.clean)` still read as the spec's own vocabulary, and a `switch`
/// over `CVEScanOutcome` is still exhaustive over exactly four possibilities.
public enum CVEScanOutcome: Sendable, Hashable, Codable {
    /// The package was queried and an answer came back.
    case covered(Coverage)
    /// The package was never queried, for a typed reason.
    case notCovered(NotCoveredReason)
    /// The package should have been queried and the answer never arrived.
    case unavailable(AdvisoryError)

    /// The two shapes an answer can take. Distinct cases, never an array that
    /// might be empty.
    public enum Coverage: Sendable, Hashable, Codable {
        case findings([VulnerabilityFinding])
        case clean(CleanCoverage)
    }
}
