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
public enum AdvisoryError: Error, Sendable, Hashable {
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
    case rateLimited
    /// The request failed below the application layer.
    case transportFailed
}

/// One advisory that applies to one installed package.
public struct VulnerabilityFinding: Sendable, Hashable, Identifiable {
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
    public let answeredBy: AdvisorySourceID

    public var id: String { advisoryID }

    public init(
        advisoryID: String,
        cveID: String?,
        aliases: [String],
        summary: String,
        severity: SeverityTier,
        ecosystem: String,
        ecosystemPackageName: String,
        answeredBy: AdvisorySourceID
    ) {
        self.advisoryID = advisoryID
        self.cveID = cveID
        self.aliases = aliases
        self.summary = summary
        self.severity = severity
        self.ecosystem = ecosystem
        self.ecosystemPackageName = ecosystemPackageName
        self.answeredBy = answeredBy
    }
}

/// The evidence behind a clean result.
///
/// A clean outcome is a **positive claim** — somebody was asked about a specific
/// version and answered "nothing" — so it is not constructible without naming
/// who was asked and about what. That is what stops "we have no findings" from
/// being spelled the same way as "we have no answers".
public struct CleanCoverage: Sendable, Hashable {
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
/// match `case .covered(clean:)`, which forces the other three states into view
/// at every call site.
public enum CVEScanOutcome: Sendable, Hashable {
    /// The package was queried and advisories came back.
    case covered(findings: [VulnerabilityFinding])
    /// The package was queried and nothing came back.
    case covered(clean: CleanCoverage)
    /// The package was never queried, for a typed reason.
    case notCovered(NotCoveredReason)
    /// The package should have been queried and the answer never arrived.
    case unavailable(AdvisoryError)
}
