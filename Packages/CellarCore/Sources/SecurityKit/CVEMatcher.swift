import Catalog
import Foundation

/// What OSV said about one query.
public enum AdvisoryAnswer: Sendable, Hashable {
    /// OSV answered. An empty array is a real answer — "nothing applies" — and
    /// is not the same value as no answer at all.
    case answered([OSVAdvisory])
    /// Nobody answered, for a typed reason.
    case unanswered(AdvisoryError)
}

/// The identity of one dismissal.
///
/// Scoped to the exact installed version, which is what makes an upgrade
/// re-surface a finding with no user action: the key simply stops matching, and
/// nothing is deleted or rewritten. `advisoryID` rather than `cveID` alone,
/// because a great many OSV records carry no CVE alias and would otherwise share
/// a `nil` identity with every other one.
public struct DismissalKey: Sendable, Hashable {
    public let advisoryID: String
    public let cveID: String?
    public let packageID: PackageID
    public let installedVersion: String

    public init(
        advisoryID: String,
        cveID: String?,
        packageID: PackageID,
        installedVersion: String
    ) {
        self.advisoryID = advisoryID
        self.cveID = cveID
        self.packageID = packageID
        self.installedVersion = installedVersion
    }
}

/// Whether the user already answered this finding.
///
/// A function rather than a store, mirroring `MetadataLookup`: the matcher stays
/// pure and the persistence layer stays on the other side of a value boundary.
public typealias DismissalLookup = @Sendable (DismissalKey) -> Bool

/// Composes OSV's answer, the curated mapping and the dismissal lookup into one
/// outcome per package.
///
/// ## What it does not do
///
/// It performs **no range arithmetic**. Whether a version is affected is OSV's
/// answer, computed server-side against OSV's own declared ranges; re-deciding
/// that locally would mean re-implementing per-ecosystem version algebra, which
/// is the exact landmine this project has already ruled out once.
///
/// It performs **no name similarity, vendor inference or keyword matching**. An
/// advisory applies to this package only when its `affected` entry names the
/// same ecosystem *and* the same package name the curated table produced.
/// Advisory prose is displayed, never consulted.
///
/// `VersionBoundaryTests.theMatcherEvaluatesNoRange` scans this file for the
/// tokens a range evaluation would need, so a future edit that starts one fails
/// the suite rather than passing review.
public struct CVEMatcher: Sendable {
    /// Travels with every result and invalidates the cache when it moves, so a
    /// fixed matcher can never be masked by a fresh-looking entry.
    public static let version = 1

    /// The default: nothing is dismissed.
    public static let nothingDismissed: DismissalLookup = { _ in false }

    public init() {}

    public func match(
        query: AdvisoryQuery,
        answer: AdvisoryAnswer,
        severities: [String: SeverityTier] = [:],
        isDismissed: DismissalLookup = CVEMatcher.nothingDismissed
    ) -> CVEScanOutcome {
        let advisories: [OSVAdvisory]
        switch answer {
        case .unanswered(let error): return .unavailable(error)
        case .answered(let answered): advisories = answered
        }

        let installed = installedVersion(of: query)
        let findings = advisories.compactMap { advisory in
            finding(
                from: advisory,
                query: query,
                installed: installed,
                severities: severities,
                isDismissed: isDismissed
            )
        }

        guard findings.isEmpty else { return .covered(.findings(findings)) }
        return .covered(
            .clean(CleanCoverage(answeredBy: .osv, queriedVersion: query.queryVersion))
        )
    }

    // MARK: - One advisory

    /// `nil` when the advisory does not name the queried package. That is the
    /// only filter, and it is an exact pair comparison.
    private func finding(
        from advisory: OSVAdvisory,
        query: AdvisoryQuery,
        installed: InstalledVersion,
        severities: [String: SeverityTier],
        isDismissed: DismissalLookup
    ) -> VulnerabilityFinding? {
        guard let affected = advisory.affected.first(where: {
            $0.ecosystem == query.ecosystem && $0.packageName == query.ecosystemPackageName
        }) else { return nil }

        let fix = fixState(for: affected, installed: installed)
        let key = DismissalKey(
            advisoryID: advisory.id,
            cveID: advisory.cveID,
            packageID: query.packageID,
            installedVersion: query.installedVersion
        )

        return VulnerabilityFinding(
            advisoryID: advisory.id,
            cveID: advisory.cveID,
            aliases: advisory.aliases,
            summary: advisory.summary,
            severity: severity(of: advisory, severities: severities),
            ecosystem: affected.ecosystem,
            ecosystemPackageName: affected.packageName,
            declaredFixVersion: fix.declared,
            fix: fix.verdict,
            answeredBy: .osv,
            isDismissed: isDismissed(key)
        )
    }

    /// NVD's number when enrichment supplied one, the advisory's own published
    /// word otherwise, and `unrated` when neither said anything.
    ///
    /// A missing enrichment never drops a finding and never invents a tier.
    private func severity(
        of advisory: OSVAdvisory,
        severities: [String: SeverityTier]
    ) -> SeverityTier {
        if let cveID = advisory.cveID, let enriched = severities[cveID] { return enriched }
        return SeverityTier.tiered(from: [], advertised: advisory.advertisedSeverity)
    }

    // MARK: - The fix

    /// Which declared fix applies, and what can honestly be said about it.
    ///
    /// Three shapes, and the first two are the pair the spec insists stay apart:
    /// no declared affected range at all is `fixUnknown` (the advisory never
    /// addressed the question), while a range carrying no fixed event is
    /// `noFixPublished` (the advisory is *saying* there is no fix — which is
    /// exactly what RustSec's unmaintained-crate records mean).
    ///
    /// **Selection, not range evaluation.** An advisory often declares several
    /// fixed events, one per maintained branch. The one that matters to an
    /// install is the earliest declared fix at or above it; when none is at or
    /// above, the install is past every branch and the latest declared fix is
    /// the relevant one. That is a choice *among values the advisory declared*,
    /// made with the strict-SemVer comparator this target already owns — no
    /// bound is interpreted and no membership is computed.
    private func fixState(
        for affected: OSVAffected,
        installed: InstalledVersion
    ) -> (declared: String?, verdict: FixVersionComparison) {
        guard affected.ranges.isEmpty == false else { return (nil, .fixUnknown) }

        let declared = affected.ranges.flatMap(\.fixed)
        guard declared.isEmpty == false else { return (nil, .noFixPublished) }

        let parsed = declared.compactMap { text in StrictSemVer.parse(text).map { (text, $0) } }
        guard parsed.isEmpty == false else {
            return (declared.first, .notComparable(scheme: .other))
        }

        let chosen = selected(among: parsed, installed: installed)
        return (
            chosen.0,
            FixVersionComparator.resolve(installed: installed, fix: .published(chosen.1))
        )
    }

    private func selected(
        among parsed: [(String, StrictSemVer)],
        installed: InstalledVersion
    ) -> (String, StrictSemVer) {
        let ascending = parsed.sorted { $0.1 < $1.1 }

        guard case .comparable(let installed) = installed else {
            // Nothing can be ordered against the install, so report the earliest
            // release that carries a fix: "a fix exists at X" is still true and
            // still useful.
            return ascending[0]
        }

        let atOrAbove = ascending.first { installed < $0.1 || installed == $0.1 }
        return atOrAbove ?? ascending[ascending.count - 1]
    }

    /// The installed side of a comparison, and the scheme when it has none.
    ///
    /// A `_N` suffix is reported as its own scheme rather than folded into
    /// "other", because "not comparable, it is a Homebrew packaging revision" is
    /// a different sentence to show a user than "not comparable, it is a date".
    private func installedVersion(of query: AdvisoryQuery) -> InstalledVersion {
        if let parsed = StrictSemVer.parse(query.installedVersion) { return .comparable(parsed) }
        let split = HomebrewRevision.split(query.installedVersion)
        return .uninterpretable(split.revision == nil ? .other : .homebrewRevision)
    }
}

// MARK: - Aggregation

/// The four counts, kept four.
///
/// This is where honesty is usually lost: every individual outcome can be
/// perfectly typed and the summary can still read "0 vulnerabilities" over an
/// inventory nobody could answer for. `notCovered` and `unavailable` are counted
/// separately and neither one is ever folded into `clean`.
public struct CoverageTotals: Sendable, Hashable {
    public let vulnerable: Int
    public let clean: Int
    public let notCovered: Int
    public let unavailable: Int

    public init(of outcomes: [CVEScanOutcome]) {
        var vulnerable = 0
        var clean = 0
        var notCovered = 0
        var unavailable = 0

        for outcome in outcomes {
            switch outcome {
            case .covered(.findings): vulnerable += 1
            case .covered(.clean): clean += 1
            case .notCovered: notCovered += 1
            case .unavailable: unavailable += 1
            }
        }

        self.vulnerable = vulnerable
        self.clean = clean
        self.notCovered = notCovered
        self.unavailable = unavailable
    }

    public var total: Int { vulnerable + clean + notCovered + unavailable }

    /// Whether anything in the inventory went unanswered.
    ///
    /// The question every badge, summary and empty state must ask before it
    /// claims the inventory has no vulnerabilities.
    public var hasUnansweredPackages: Bool { notCovered + unavailable != 0 }

    /// Whether every package in a non-empty inventory got an answer.
    public var isEntirelyAnswered: Bool { total != 0 && hasUnansweredPackages == false }
}
