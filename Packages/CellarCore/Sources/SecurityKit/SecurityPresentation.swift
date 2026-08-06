import Catalog
import Foundation

// MARK: - The four sections

/// The four coverage states, in the order the surface must show them.
///
/// **Not covered sits directly under vulnerable, above clean.** That is not a
/// layout preference: the spec requires not-covered to be at least as prominent
/// as vulnerable in every summary, count and empty state, and on a real
/// inventory it is the state most packages are in. Putting it under "clean"
/// would bury the majority answer beneath a minority one.
public enum SecurityCoverageState: String, Sendable, Hashable, CaseIterable {
    case vulnerable
    case notCovered
    case clean
    case unavailable

    /// The accessibility identifier the app target renders, so the string the
    /// UI tests query is decided here rather than typed into a view body.
    public var identifier: String { "security-coverage-\(rawValue)" }

    public var title: String {
        switch self {
        case .vulnerable: "Vulnerable"
        case .notCovered: "Not covered"
        case .clean: "Clean"
        case .unavailable: "Unavailable"
        }
    }

    /// What the section means, in the surface's own voice.
    ///
    /// Every one of the four says what it *is*; none of them says what the other
    /// three are not. "Clean" in particular is scoped to the packages that were
    /// actually asked about.
    public var explanation: String {
        switch self {
        case .vulnerable:
            "An advisory database reported at least one advisory for the installed version."
        case .notCovered:
            "Nothing was asked about these packages, for the reason each one states."
        case .clean:
            "These packages were asked about at their installed version and no advisory came back."
        case .unavailable:
            "These packages should have been asked about and no answer arrived."
        }
    }

    /// Which state an outcome belongs to. Exhaustive over `CVEScanOutcome`, so a
    /// fifth outcome could not be silently absorbed into an existing section.
    public static func of(_ outcome: CVEScanOutcome) -> SecurityCoverageState {
        switch outcome {
        case .covered(.findings): .vulnerable
        case .covered(.clean): .clean
        case .notCovered: .notCovered
        case .unavailable: .unavailable
        }
    }
}

/// One row: what is known about one installed package.
public struct SecuritySectionItem: Sendable, Hashable, Identifiable {
    public let packageID: PackageID
    /// The version actually put on the wire, which for a Homebrew revision is
    /// the upstream part rather than the installed string.
    public let queriedVersion: String
    public let outcome: CVEScanOutcome
    public let freshness: ResultFreshness

    public var id: PackageID { packageID }

    public init(
        packageID: PackageID,
        queriedVersion: String,
        outcome: CVEScanOutcome,
        freshness: ResultFreshness
    ) {
        self.packageID = packageID
        self.queriedVersion = queriedVersion
        self.outcome = outcome
        self.freshness = freshness
    }

    public var state: SecurityCoverageState { .of(outcome) }

    /// Every advisory for this package, worst first, with `unrated` in its own
    /// bucket at the end.
    public var findings: [VulnerabilityFinding] {
        guard case .covered(.findings(let findings)) = outcome else { return [] }
        return findings.sorted { lhs, rhs in
            if lhs.severity.displayOrder != rhs.severity.displayOrder {
                return lhs.severity.displayOrder < rhs.severity.displayOrder
            }
            return lhs.advisoryID < rhs.advisoryID
        }
    }

    /// The findings the user has not answered yet.
    ///
    /// Suppression lives here rather than in the outcome: deleting a dismissed
    /// finding upstream would let a package whose every finding was dismissed
    /// collapse into `covered(clean:)`, a coverage state the user never
    /// consented to and the spec forbids dismissal from changing.
    public var activeFindings: [VulnerabilityFinding] { findings.filter { !$0.isDismissed } }

    public var dismissedFindings: [VulnerabilityFinding] { findings.filter(\.isDismissed) }

    public var notCoveredReason: NotCoveredReason? {
        guard case .notCovered(let reason) = outcome else { return nil }
        return reason
    }

    public var failure: AdvisoryError? {
        guard case .unavailable(let error) = outcome else { return nil }
        return error
    }
}

/// One rendered section, with the count that must survive aggregation.
public struct SecuritySection: Sendable, Hashable, Identifiable {
    public let state: SecurityCoverageState
    public let items: [SecuritySectionItem]

    public init(state: SecurityCoverageState, items: [SecuritySectionItem]) {
        self.state = state
        self.items = items
    }

    public var id: SecurityCoverageState { state }
    public var count: Int { items.count }
    public var identifier: String { state.identifier }
    public var title: String { state.title }
}

// MARK: - What the surface is entitled to say

/// The one sentence a summary, badge or empty state is allowed to lead with.
///
/// A `String` here would make the honesty rule unassertable — every caller could
/// compose its own confident sentence. The claim is a *case*, and exactly one
/// case is entitled to say the inventory has no vulnerabilities, so
/// `claimsNoVulnerabilities` is a property of the type rather than a promise
/// made in a code review.
public enum SecurityHeadline: Sendable, Hashable {
    /// Nothing has been asked yet. Not an answer of any kind.
    case notScanned
    /// Advisories exist. Carries the unanswered count too, because not-covered
    /// must be at least as prominent as vulnerable in *every* summary — a
    /// headline that names findings and drops the gap fails that requirement.
    case vulnerable(count: Int, unanswered: Int)
    /// Nothing came back for the packages that were asked about, and some were
    /// never asked. Deliberately distinct from `fullyAnsweredNoVulnerabilities`.
    case noFindingsWithGaps(unanswered: Int)
    /// Every package was answered and none is vulnerable. **The only case
    /// entitled to claim the inventory has no vulnerabilities.**
    case fullyAnsweredNoVulnerabilities

    /// Whether this headline asserts the inventory has no vulnerabilities.
    public var claimsNoVulnerabilities: Bool {
        if case .fullyAnsweredNoVulnerabilities = self { return true }
        return false
    }

    public var title: String {
        switch self {
        case .notScanned: "Not scanned"
        case .vulnerable(let count, _):
            "\(count) \(count == 1 ? "package" : "packages") with advisories"
        case .noFindingsWithGaps: "No advisories among the packages that were checked"
        case .fullyAnsweredNoVulnerabilities: "No advisories"
        }
    }

    /// The sentence under the headline. Never empty, and never silent about the
    /// packages nobody answered for.
    public var message: String {
        switch self {
        case .notScanned:
            "No scan has run yet, so nothing is known about this inventory."
        case .vulnerable(let count, let unanswered) where unanswered > 0:
            """
            \(count) \(count == 1 ? "package has" : "packages have") at least one advisory. \
            \(unanswered) \(unanswered == 1 ? "package is" : "packages are") unanswered and \
            could hold advisories nobody reported.
            """
        case .vulnerable(let count, _):
            """
            \(count) \(count == 1 ? "package has" : "packages have") at least one advisory. \
            Every package was answered.
            """
        case .noFindingsWithGaps(let unanswered):
            """
            Nothing came back for the packages that were checked. \
            \(unanswered) \(unanswered == 1 ? "package is" : "packages are") unanswered — \
            that is a gap in coverage, not a clean result.
            """
        case .fullyAnsweredNoVulnerabilities:
            "Every package in this inventory was answered and no advisory applies to any installed version."
        }
    }
}

// MARK: - The projection

/// The security surface's rules, as values.
public enum SecurityPresentation {
    /// Groups a settled scan into the four sections, always in the same order.
    ///
    /// All four are returned whenever anything was scanned at all, including the
    /// ones whose count is zero: a zero is a fact worth rendering, and hiding an
    /// empty section is how "Not covered: 152" quietly disappears the moment the
    /// vulnerable list happens to be empty. An inventory nothing was asked about
    /// yields no sections at all, which is the empty state's job rather than four
    /// hollow headers.
    public static func sections(of entries: some Sequence<AdvisoryCacheEntry>) -> [SecuritySection] {
        let items = entries.map { entry in
            SecuritySectionItem(
                packageID: entry.key.packageID,
                queriedVersion: entry.key.version,
                outcome: entry.outcome,
                freshness: entry.freshness
            )
        }
        guard items.isEmpty == false else { return [] }

        let grouped = Dictionary(grouping: items, by: \.state)
        return SecurityCoverageState.allCases.map { state in
            SecuritySection(
                state: state,
                items: (grouped[state] ?? []).sorted { $0.packageID.name < $1.packageID.name }
            )
        }
    }

    /// Which sentence the four counts entitle the surface to say.
    ///
    /// Read the order of the branches: the gap check comes *before* any clean
    /// claim can be reached, so there is no arrangement of counts in which an
    /// unanswered package and the words "no vulnerabilities" appear together.
    public static func headline(for totals: CoverageTotals) -> SecurityHeadline {
        guard totals.total > 0 else { return .notScanned }

        let unanswered = totals.notCovered + totals.unavailable
        if totals.vulnerable > 0 {
            return .vulnerable(count: totals.vulnerable, unanswered: unanswered)
        }
        if unanswered > 0 {
            return .noFindingsWithGaps(unanswered: unanswered)
        }
        return .fullyAnsweredNoVulnerabilities
    }

    /// The accessibility identifier for one finding's row.
    ///
    /// The design writes `security-finding-{cveID}`, and taken literally that
    /// breaks on the data this app actually receives: `GHSA-`, `RUSTSEC-` and
    /// `PYSEC-` advisories routinely publish no CVE alias, so every unaliased
    /// finding would answer to the same empty identifier. The advisory's own ID
    /// is the fallback, matching the identity `DismissedCVE` is keyed on.
    public static func findingIdentifier(_ finding: VulnerabilityFinding) -> String {
        "security-finding-\(Self.stableID(finding))"
    }

    public static func dismissIdentifier(_ finding: VulnerabilityFinding) -> String {
        "security-dismiss-\(Self.stableID(finding))"
    }

    private static func stableID(_ finding: VulnerabilityFinding) -> String {
        if let cveID = finding.cveID, cveID.isEmpty == false { return cveID }
        return finding.advisoryID
    }

    /// How a result's age should read, so no cached value is ever presented as
    /// fresh by a view that forgot to look.
    public static func freshnessLabel(_ freshness: ResultFreshness, now: Date) -> String {
        switch freshness {
        case .live:
            "Checked just now"
        case .cached(let fetchedAt):
            // Built per call rather than cached in a `static let`.
            // `RelativeDateTimeFormatter` is a mutable, non-`Sendable` class, so a
            // shared instance is a data race under the language mode this target
            // compiles in — and this runs once per visible row, not per entry.
            "Cached \(Self.ageFormatter().localizedString(for: fetchedAt, relativeTo: now))"
        }
    }

    private static func ageFormatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }
}
