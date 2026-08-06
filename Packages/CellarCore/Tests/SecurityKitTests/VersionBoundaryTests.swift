import Catalog
import Foundation
import Testing

@testable import SecurityKit

/// Three version strings, three different rules, and every bug in this feature
/// would come from conflating two of them.
///
/// 1. **Query version** — what OSV is asked about. The lexical upstream, with a
///    Homebrew `_N` packaging revision removed.
/// 2. **Coverage** — decided by *OSV*, from its own declared ranges. Nothing
///    here evaluates a range. The only local decision is whether the query
///    version is interpretable in the mapped ecosystem's scheme at all; if it is
///    not, nothing is asked and the gap is admitted.
/// 3. **Fix comparison** — a later, separate step over the **installed** string
///    and the advisory's fixed string, both of which must parse as strict SemVer.
///
/// The consequence, which is the single most misreadable interaction in the
/// design: an installed `1.2.3_1` is **covered** and produces a finding that
/// says "fix published, comparison not possible for this version scheme". A
/// Homebrew revision never suppresses coverage, and never yields an ordering.
@Suite("Version boundary")
struct VersionBoundaryTests {
    // MARK: - (a) The query version

    @Test("The query version is the lexical upstream, not the installed string")
    func theQueryVersionIsTheLexicalUpstreamNotTheInstalledString() throws {
        let plan = AdvisoryQueryPlanner.plan(
            for: PackageID(kind: .formula, name: "bat"),
            installedVersion: "1.2.3_1"
        )

        guard case .query(let query) = plan else {
            Issue.record("a revision-suffixed install must still be queried")
            return
        }

        #expect(query.queryVersion == "1.2.3")
        // The installed string survives alongside it, because fix comparison
        // needs the string the user actually has, not the one we asked about.
        #expect(query.installedVersion == "1.2.3_1")
        #expect(query.ecosystem == "crates.io")
        #expect(query.ecosystemPackageName == "bat")
    }

    /// The unsuffixed case, so the test above is about the suffix and not about
    /// a planner that rewrites everything.
    @Test("A version with no revision suffix is queried exactly as installed")
    func anUnsuffixedVersionIsQueriedUnchanged() throws {
        let plan = AdvisoryQueryPlanner.plan(
            for: PackageID(kind: .formula, name: "ripgrep"),
            installedVersion: "15.2.0"
        )

        guard case .query(let query) = plan else {
            Issue.record("a strict SemVer install must be queried")
            return
        }
        #expect(query.queryVersion == "15.2.0")
        #expect(query.queryVersion == query.installedVersion)
    }

    /// The real capture, reproduced from the table. Every version in the
    /// phase-2 `querybatch-request.json` must be reachable through the planner,
    /// or task 7.1's byte-comparison is testing a request this code cannot
    /// produce.
    ///
    /// `protobuf 35.1` is the row that matters: two components, so **not** strict
    /// SemVer, and perfectly ordinary PEP 440. Gating every ecosystem on SemVer
    /// would have dropped it, and the captured request proves OSV answers it.
    @Test(
        "Every package in the captured request is still queryable, at the captured version",
        arguments: [
            ("bat", "0.26.1"),
            ("eza", "0.23.5"),
            ("llhttp", "9.4.3"),
            ("protobuf", "35.1"),
            ("ripgrep", "15.2.0"),
            ("sd", "1.1.0"),
            ("uv", "0.12.1")
        ]
    )
    func everyCapturedQueryIsStillProduced(formula: String, version: String) throws {
        let plan = AdvisoryQueryPlanner.plan(
            for: PackageID(kind: .formula, name: formula),
            installedVersion: version
        )

        guard case .query(let query) = plan else {
            Issue.record("\(formula) \(version) is in the captured request and was not planned")
            return
        }
        #expect(query.queryVersion == version)
    }

    // MARK: - (b) Coverage is OSV's answer

    /// The matcher performs **no range arithmetic**.
    ///
    /// This advisory is real: `GHSA-p24j-h477-76q3` fixes `bat` at `0.18.2`. The
    /// installed version here is `9.9.9` — far past the fix, and a local range
    /// evaluation would confidently drop the advisory as inapplicable. It does
    /// not get dropped, because OSV returned it, and OSV is the thing that
    /// evaluates ranges. The *fix* verdict records that the fix is already in;
    /// the *coverage* is OSV's.
    @Test("Coverage is OSV's answer, not a local range evaluation")
    func coverageIsOSVsAnswerNotALocalRangeEvaluation() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-GHSA-p24j-h477-76q3.json")
        )
        let query = try #require(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "bat"),
                installedVersion: "9.9.9"
            ).query
        )

        let outcome = CVEMatcher().match(query: query, answer: .answered([advisory]))

        guard case .covered(.findings(let findings)) = outcome else {
            Issue.record("an advisory OSV returned was dropped locally")
            return
        }
        #expect(findings.count == 1)
        #expect(findings[0].advisoryID == "GHSA-p24j-h477-76q3")
        // The fix verdict is where "already fixed" belongs -- not in whether the
        // advisory exists.
        #expect(findings[0].fix == .fixedAtOrBefore)
    }

    /// The structural half. If the matcher ever grows a range evaluation, it
    /// will need the tokens a range evaluation needs.
    @Test("The matcher's source evaluates no version range")
    func theMatcherEvaluatesNoRange() throws {
        let sources = try SecurityKitSources.load()
        let matcher = try #require(sources.first { $0.name == "CVEMatcher.swift" })

        #expect(matcher.code.contains("func match("), "the scan did not read the matcher")

        for token in ["introduced", "lastAffected", "contains(", "ClosedRange", "Range"] {
            #expect(
                matcher.code.containsIdentifier(token) == false,
                "the matcher looks like it evaluates ranges: \(token)"
            )
        }
    }

    // MARK: - (c) An uninterpretable version is not queried

    @Test(
        "An uninterpretable version is not queried and reports its scheme as unsupported",
        arguments: ["2024-01-05", "r5", "8e", "HEAD", "20040914", "3.7b"]
    )
    func anUninterpretableVersionIsNotQueriedAndReportsUnsupportedVersionScheme(
        version: String
    ) {
        // `bat` is mapped to crates.io, which is a SemVer ecosystem, so none of
        // these can be asked about honestly.
        let plan = AdvisoryQueryPlanner.plan(
            for: PackageID(kind: .formula, name: "bat"),
            installedVersion: version
        )

        #expect(plan == .notCovered(.unsupportedVersionScheme))
        #expect(plan.query == nil, "an uninterpretable version produced a query")
    }

    /// **Zero** queries, counted rather than asserted per package, because "not
    /// queried" is a statement about what leaves the machine.
    @Test("An inventory of uninterpretable versions produces no query at all")
    func anInventoryOfUninterpretableVersionsProducesNoQuery() {
        let inventory = ["2024-01-05", "r5", "8e", "HEAD"].map {
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "bat"),
                installedVersion: $0
            )
        }

        #expect(inventory.compactMap(\.query).isEmpty)
        #expect(inventory.count == 4, "the walk ran against nothing")
        #expect(inventory.allSatisfy { $0 == .notCovered(.unsupportedVersionScheme) })
    }

    /// The ecosystems disagree about what a version is, and pretending otherwise
    /// is how `protobuf 35.1` would be lost. PyPI's PEP 440 accepts a
    /// two-component release; crates.io's SemVer does not.
    @Test("The interpretability rule is the mapped ecosystem's, not one rule for all")
    func interpretabilityFollowsTheMappedEcosystem() {
        // The same version string, two ecosystems, two honest answers.
        let pypi = AdvisoryQueryPlanner.plan(
            for: PackageID(kind: .formula, name: "protobuf"),
            installedVersion: "35.1"
        )
        let crates = AdvisoryQueryPlanner.plan(
            for: PackageID(kind: .formula, name: "bat"),
            installedVersion: "35.1"
        )

        #expect(pypi.query?.queryVersion == "35.1")
        #expect(crates == .notCovered(.unsupportedVersionScheme))
    }

    /// Every ecosystem the table names must have a scheme, or a future entry
    /// would silently make its whole ecosystem unqueryable.
    @Test("Every ecosystem in the curated table has a version scheme")
    func everyMappedEcosystemHasAScheme() {
        let ecosystems = Set(EcosystemMapping.entries.map(\.ecosystem))

        #expect(ecosystems.isEmpty == false)
        for ecosystem in ecosystems {
            #expect(
                EcosystemVersionScheme.forEcosystem(ecosystem) != nil,
                "\(ecosystem) is mapped but has no version scheme"
            )
        }
    }

    // MARK: - 6.2 The spec's own scenario

    /// The interaction the design says cannot be allowed to surprise anyone.
    ///
    /// Installed `0.18.1_1` is a Homebrew packaging revision of `bat`. It is
    /// **covered** — OSV was asked about upstream `0.18.1` and answered with the
    /// real `GHSA-p24j-h477-76q3`, which declares a fix at `0.18.2`. And the fix
    /// is **not comparable**, because `0.18.1_1` is not strict SemVer. So the
    /// finding reports that a fix is published and that no ordering can be
    /// asserted for this pair — which is precisely the spec's `1.2.3_1` versus
    /// `1.2.4` scenario, occurring against a real advisory.
    @Test("A revision-suffixed install is covered and reports an uncomparable fix")
    func aRevisionSuffixedInstallIsCoveredAndReportsAnUncomparableFix() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-GHSA-p24j-h477-76q3.json")
        )
        let plan = AdvisoryQueryPlanner.plan(
            for: PackageID(kind: .formula, name: "bat"),
            installedVersion: "0.18.1_1"
        )
        let query = try #require(plan.query)

        // Covered: the suffix was split off and the upstream was asked about.
        #expect(query.queryVersion == "0.18.1")
        #expect(query.installedVersion == "0.18.1_1")

        let outcome = CVEMatcher().match(query: query, answer: .answered([advisory]))
        guard case .covered(.findings(let findings)) = outcome else {
            Issue.record("a revision suffix suppressed coverage")
            return
        }

        let finding = try #require(findings.first)
        #expect(finding.advisoryID == "GHSA-p24j-h477-76q3")
        #expect(finding.declaredFixVersion == "0.18.2", "the fix is published and reported")
        #expect(finding.fix == .notComparable(scheme: .homebrewRevision))
        // The two verdicts that must never be asserted for this pair.
        #expect(finding.fix != .stillAffected)
        #expect(finding.fix != .fixedAtOrBefore)
    }

    /// The control for the case above: the same real advisory against a strict
    /// SemVer install *does* produce an ordering. Without this,
    /// `notComparable` could be the answer to everything.
    @Test("The same advisory against a strict SemVer install does order")
    func theSameAdvisoryAgainstAStrictInstallDoesOrder() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-GHSA-p24j-h477-76q3.json")
        )

        for (installed, expected) in [
            ("0.18.1", FixVersionComparison.stillAffected),
            ("0.18.2", .fixedAtOrBefore),
            ("0.19.0", .fixedAtOrBefore)
        ] {
            let query = try #require(
                AdvisoryQueryPlanner.plan(
                    for: PackageID(kind: .formula, name: "bat"),
                    installedVersion: installed
                ).query
            )
            let outcome = CVEMatcher().match(query: query, answer: .answered([advisory]))

            guard case .covered(.findings(let findings)) = outcome, let finding = findings.first else {
                Issue.record("\(installed) produced no finding")
                return
            }
            #expect(finding.fix == expected, "\(installed)")
        }
    }

    /// A declared absence of a fix survives the whole pipeline. RustSec's
    /// unmaintained-crate records carry an `introduced` event and no `fixed`
    /// event, which is a statement, not a missing field.
    @Test("An advisory that declares no fix reports no fix published")
    func anAdvisoryDeclaringNoFixReportsNoFixPublished() throws {
        // The real record names `ansi_term`, so the query is built for the
        // ecosystem package the advisory actually addresses.
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-RUSTSEC-2021-0139.json")
        )
        let query = AdvisoryQuery(
            packageID: PackageID(kind: .formula, name: "ansi-term"),
            installedVersion: "0.12.1",
            queryVersion: "0.12.1",
            ecosystem: "crates.io",
            ecosystemPackageName: "ansi_term"
        )

        let outcome = CVEMatcher().match(query: query, answer: .answered([advisory]))
        guard case .covered(.findings(let findings)) = outcome, let finding = findings.first else {
            Issue.record("the unmaintained advisory produced no finding")
            return
        }

        #expect(finding.fix == .noFixPublished)
        #expect(finding.fix != .fixUnknown, "a declared absence is not an unknown")
        #expect(finding.declaredFixVersion == nil)
    }
}
