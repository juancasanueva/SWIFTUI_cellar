import Catalog
import Foundation
import Testing

@testable import SecurityKit

/// The matcher composes; it does not infer.
///
/// Everything it knows comes from three places: the curated table said which
/// ecosystem package this is, OSV said which advisories apply to that package at
/// that version, and the dismissal lookup said which findings the user already
/// answered. There is no fourth source, and in particular there is no reading of
/// advisory prose to see whether it "sounds like" the installed package.
@Suite("CVE matcher")
struct CVEMatcherTests {
    // MARK: - The four states

    /// Exhaustive over `CVEScanOutcome`, reached through the real code paths
    /// rather than by constructing four enum values.
    ///
    /// The switch below has no `default`, so adding a fifth state breaks this
    /// test at compile time — which is the point of the type having exactly four.
    @Test("Every outcome is exactly one of the four states")
    func everyOutcomeIsExactlyOneOfTheFourStates() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-GHSA-p24j-h477-76q3.json")
        )
        let batQuery = try #require(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "bat"),
                installedVersion: "0.18.1"
            ).query
        )
        let matcher = CVEMatcher()

        let outcomes: [CVEScanOutcome] = [
            matcher.match(query: batQuery, answer: .answered([advisory])),
            matcher.match(query: batQuery, answer: .answered([])),
            .notCovered(.unmapped),
            matcher.match(query: batQuery, answer: .unanswered(.rateLimited))
        ]

        var seen: [String] = []
        for outcome in outcomes {
            switch outcome {
            case .covered(.findings(let findings)):
                #expect(findings.isEmpty == false, "covered-with-findings must have findings")
                seen.append("findings")
            case .covered(.clean(let clean)):
                #expect(clean.queriedVersion == "0.18.1")
                #expect(clean.answeredBy == .osv)
                seen.append("clean")
            case .notCovered(let reason):
                #expect(reason == .unmapped)
                seen.append("notCovered")
            case .unavailable(let error):
                #expect(error == .rateLimited)
                seen.append("unavailable")
            }
        }

        #expect(seen == ["findings", "clean", "notCovered", "unavailable"])
    }

    /// The collapse the type exists to prevent, stated directly: an unanswered
    /// package is not a clean one, and no amount of missing findings makes it
    /// one.
    @Test("An unanswered package never becomes clean")
    func anUnansweredPackageNeverBecomesClean() throws {
        let query = try #require(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "bat"),
                installedVersion: "0.26.1"
            ).query
        )

        for error in [AdvisoryError.rateLimited, .offline, .transportFailed, .malformedRecord] {
            let outcome = CVEMatcher().match(query: query, answer: .unanswered(error))

            #expect(outcome == .unavailable(error))
            #expect(
                outcome != .covered(.clean(CleanCoverage(answeredBy: .osv, queriedVersion: "0.26.1")))
            )
        }
    }

    // MARK: - Kind

    @Test("A cask is not covered, for the kind reason")
    func aCaskIsNotCoveredKindUnsupported() {
        #expect(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .cask, name: "firefox"),
                installedVersion: "1.2.3"
            ) == .notCovered(.kindUnsupported)
        )
        // Even when its name is mapped and its version is impeccable.
        #expect(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .cask, name: "bat"),
                installedVersion: "0.26.1"
            ) == .notCovered(.kindUnsupported)
        )
    }

    // MARK: - The primary keg

    /// "Only the primary keg is scanned" is enforced by the shape of the API,
    /// not by a rule somebody follows.
    ///
    /// The planner accepts **one** version string. There is no overload that
    /// takes a list of kegs, so producing a second query for a second keg is not
    /// something a caller can do by accident — it would require inventing a
    /// second package. Choosing *which* keg is primary already has an owner
    /// (`InstalledDecoder.primaryKeg`, in `BrewClient`), and this target
    /// deliberately cannot see it.
    @Test("Only the primary keg is ever matched")
    func onlyThePrimaryKegIsEverMatched() throws {
        // A formula with a linked keg and two older unlinked ones. The caller
        // resolves the primary; exactly one query results, at that version.
        let primary = "0.26.1"
        let unlinked = ["0.24.0", "0.25.0"]

        let plans = ([primary] + unlinked).prefix(1).map {
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "bat"),
                installedVersion: $0
            )
        }
        let queries = plans.compactMap(\.query)

        #expect(queries.count == 1)
        #expect(queries[0].queryVersion == primary)
        #expect(unlinked.contains(queries[0].queryVersion) == false)

        // The structural half: nothing in this target knows what a keg is, so
        // nothing in it can enumerate one.
        let sources = try SecurityKitSources.load()
        #expect(sources.isEmpty == false)
        for token in ["kegs", "InstalledKeg", "linkedKeg", "primaryKeg"] {
            let offenders = sources.filter { $0.code.containsIdentifier(token) }
            #expect(offenders.isEmpty, "\(token) leaked into \(offenders.map(\.name).sorted())")
        }
    }

    // MARK: - No inference

    /// The threat-matrix rule: inference is not discovery.
    ///
    /// `curl` is installed, an advisory's summary text names it outright, and
    /// `curl` is absent from the curated table because U1 measured it as an
    /// identity collision. The outcome is `notCovered(.unmapped)`, no query is
    /// produced, and the advisory is never even fetched — so there is nothing
    /// for prose to influence.
    @Test("The matcher performs no name similarity or keyword matching")
    func theMatcherPerformsNoNameSimilarityOrKeywordMatching() throws {
        let plan = AdvisoryQueryPlanner.plan(
            for: PackageID(kind: .formula, name: "curl"),
            installedVersion: "8.21.0"
        )

        #expect(plan == .notCovered(.unmapped))
        #expect(plan.query == nil)

        // The second half, where an advisory *is* in hand: its prose names the
        // queried formula and its `affected` entry names something else. The
        // prose loses.
        let query = try #require(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "bat"),
                installedVersion: "0.26.1"
            ).query
        )
        let decoy = OSVAdvisory(
            id: "GHSA-decoy-0000-0000",
            modified: Date(timeIntervalSince1970: 0),
            summary: "Critical remote code execution in bat, the cat clone",
            details: "Affects bat and every tool named bat. bat bat bat.",
            aliases: ["CVE-2026-9999"],
            advertisedSeverity: "CRITICAL",
            severityVectors: [],
            affected: [
                OSVAffected(
                    ecosystem: "crates.io",
                    packageName: "some-unrelated-crate",
                    ranges: [OSVRange(type: "SEMVER", introduced: ["0"], fixed: ["9.9.9"],
                                      lastAffected: [])]
                )
            ]
        )

        let outcome = CVEMatcher().match(query: query, answer: .answered([decoy]))

        #expect(
            outcome == .covered(.clean(CleanCoverage(answeredBy: .osv, queriedVersion: "0.26.1"))),
            "an advisory was matched by its prose rather than by its affected package"
        )
    }

    /// The ecosystem is half the identity. The same package name in a different
    /// ecosystem is different software — which is the whole reason the table
    /// stores pairs rather than names.
    @Test("An advisory for the same name in another ecosystem is not a finding")
    func anAdvisoryInAnotherEcosystemIsNotAFinding() throws {
        let query = try #require(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "bat"),
                installedVersion: "0.26.1"
            ).query
        )
        let wrongEcosystem = OSVAdvisory(
            id: "GHSA-elsewhere-0000",
            modified: Date(timeIntervalSince1970: 0),
            summary: "An advisory for a RubyGems package that is also called bat",
            details: "",
            aliases: [],
            advertisedSeverity: "HIGH",
            severityVectors: [],
            affected: [
                OSVAffected(ecosystem: "RubyGems", packageName: "bat", ranges: [])
            ]
        )

        let outcome = CVEMatcher().match(query: query, answer: .answered([wrongEcosystem]))

        #expect(
            outcome == .covered(.clean(CleanCoverage(answeredBy: .osv, queriedVersion: "0.26.1")))
        )
    }

    // MARK: - Choosing among several declared fixes

    /// A real advisory that declares **four** fixed versions, one per maintained
    /// branch: `PYSEC-2026-899` fixes `protobuf` at `3.18.3`, `3.19.5`, `3.20.2`
    /// and `4.21.6`.
    ///
    /// The fix that matters to an install is the earliest declared one at or
    /// above it. Two of the rows below are the ones a careless rule gets wrong:
    ///
    /// - `3.20.2` is **fixed** — it *is* one of the declared fixes. Taking the
    ///   last declared fix (`4.21.6`) instead would report an up-to-date install
    ///   as still affected.
    /// - `3.18.0` is **still affected**, and only `3.18.3` says so; taking the
    ///   first declared fix would be right here by accident and wrong at `3.20.1`.
    ///
    /// This is a choice among values the advisory itself declared, ordered with
    /// the strict-SemVer comparator. No bound is interpreted, and no membership
    /// of a range is computed.
    @Test(
        "The relevant declared fix is the earliest one at or above the install",
        arguments: [
            ("3.18.0", "3.18.3", FixVersionComparison.stillAffected),
            ("3.18.3", "3.18.3", .fixedAtOrBefore),
            ("3.19.0", "3.19.5", .stillAffected),
            ("3.20.1", "3.20.2", .stillAffected),
            ("3.20.2", "3.20.2", .fixedAtOrBefore),
            ("4.21.6", "4.21.6", .fixedAtOrBefore),
            // Past every declared branch: the latest declared fix is the
            // relevant one, and the install is beyond it.
            ("5.0.0", "4.21.6", .fixedAtOrBefore)
        ]
    )
    func theRelevantDeclaredFixIsTheEarliestAtOrAboveTheInstall(
        installed: String,
        declared: String,
        verdict: FixVersionComparison
    ) throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-PYSEC-2026-899.json")
        )
        let affected = try #require(advisory.affected.first)
        #expect(
            affected.ranges.flatMap(\.fixed) == ["3.18.3", "3.19.5", "3.20.2", "4.21.6"],
            "the fixture no longer declares four branch fixes"
        )

        let query = AdvisoryQuery(
            packageID: PackageID(kind: .formula, name: "protobuf"),
            installedVersion: installed,
            queryVersion: installed,
            ecosystem: "PyPI",
            ecosystemPackageName: "protobuf"
        )
        let outcome = CVEMatcher().match(query: query, answer: .answered([advisory]))

        guard case .covered(.findings(let findings)) = outcome, let finding = findings.first else {
            Issue.record("\(installed) produced no finding")
            return
        }
        #expect(finding.declaredFixVersion == declared)
        #expect(finding.fix == verdict)
    }

    // MARK: - Enrichment

    /// Severity arrives from NVD and is keyed by CVE identifier alone. When it
    /// does not arrive, the finding stays and its tier is `unrated` — the
    /// finding is never dropped and never invented a severity.
    @Test("Enrichment supplies severity by CVE identifier, and its absence leaves unrated")
    func enrichmentSuppliesSeverityByCveIdentifier() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-PYSEC-2026-899.json")
        )
        let query = AdvisoryQuery(
            packageID: PackageID(kind: .formula, name: "protobuf"),
            installedVersion: "3.20.1",
            queryVersion: "3.20.1",
            ecosystem: "PyPI",
            ecosystemPackageName: "protobuf"
        )
        let matcher = CVEMatcher()

        let enriched = matcher.match(
            query: query,
            answer: .answered([advisory]),
            severities: ["CVE-2022-1941": .high]
        )
        guard case .covered(.findings(let withSeverity)) = enriched else {
            Issue.record("the enriched match produced no finding")
            return
        }
        #expect(withSeverity[0].cveID == "CVE-2022-1941")
        #expect(withSeverity[0].severity == .high)

        // Without enrichment, the advisory's own published word is used. This
        // record publishes none, so the tier is unrated and the finding stays.
        let unenriched = matcher.match(query: query, answer: .answered([advisory]))
        guard case .covered(.findings(let withoutSeverity)) = unenriched else {
            Issue.record("an unenriched match dropped its finding")
            return
        }
        #expect(withoutSeverity[0].severity == .unrated)
        #expect(withoutSeverity.count == withSeverity.count)
    }
}
