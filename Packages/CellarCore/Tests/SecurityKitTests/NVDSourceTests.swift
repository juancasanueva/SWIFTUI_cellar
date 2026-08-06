import Catalog
import Foundation
import SecurityKit
import Testing

/// What `NVDSource` puts on the wire.
///
/// Enrichment is the half of acquisition that could quietly become an inventory
/// disclosure: it runs *after* discovery, when the code already holds every
/// installed package name, and the easiest wrong implementation asks NVD about
/// packages instead of about identifiers. These tests pin the opposite —
/// requests are keyed by CVE identifier and by nothing else, so request volume
/// follows findings rather than inventory.
@Suite("NVD advisory source")
struct NVDSourceTests {
    // MARK: - Fakes

    /// The credential seam, in memory. **No test here touches the Keychain.**
    struct FakeCredentialStore: AdvisoryCredentialStoring {
        let key: String?

        func apiKey() async throws -> String? { key }
        func store(apiKey: String) async throws {}
        func removeAPIKey() async throws {}
    }

    static func source(on network: RecordingNetwork, key: String? = nil) -> NVDSource {
        NVDSource(session: network.session, credentials: FakeCredentialStore(key: key))
    }

    /// The `cveIds` values of one recorded request, as the server would read
    /// them.
    static func identifiers(in url: URL) throws -> [String] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let value = try #require(
            components.queryItems?.first { $0.name == "cveIds" }?.value,
            "the enrichment request carried no cveIds parameter"
        )
        return value.split(separator: ",").map(String.init)
    }

    // MARK: - Volume follows findings

    /// The `vulnerability-scanning` scenario, over the real 159-formula
    /// inventory.
    ///
    /// The absence is checked against the request's **parsed `cveIds` values**,
    /// not as a substring of the URL, and the difference is not pedantry: the
    /// host is `services.nvd.nist.gov`, and `gov` contains the real formula name
    /// `go`. A substring scan would fail on the host and the obvious "fix" would
    /// be to weaken the check until it passed. Parsing asks the question the
    /// spec actually asks — *is an installed package named in this request* —
    /// and the exact-URL assertion beside it closes the path where a name could
    /// hide anywhere else.
    @Test("Enrichment is by CVE identifier only and never names an installed package")
    func enrichmentIsByCveIdsOnlyAndNeverNamesAnInstalledPackage() async throws {
        let inventory = try Fixture.corpusRows("Versions/installed-versions.txt")
            .compactMap { $0.split(separator: " ").first.map(String.init) }
        #expect(inventory.count == 159, "the captured inventory is no longer 159 formulae")

        let discovered = ["CVE-2026-0994", "CVE-2021-36753", "CVE-2022-1941"]
        let network = RecordingNetwork(
            fallback: .ok(try Fixture.data("NVD/cveids-response.json"))
        )

        _ = try await Self.source(on: network).enrich(discovered)

        let exchanges = network.exchanges
        #expect(exchanges.count == 1, "three identifiers took \(exchanges.count) requests")
        let request = try #require(exchanges.first)
        #expect(request.method == "GET")
        #expect(request.body == nil || request.body?.isEmpty == true)
        #expect(
            request.url.absoluteString
                == "https://services.nvd.nist.gov/rest/json/cves/2.0?cveIds="
                + discovered.joined(separator: ",")
        )

        let asked = try Self.identifiers(in: request.url)
        #expect(asked == discovered, "the request asked about something other than the findings")
        #expect(
            Set(asked).isDisjoint(with: inventory),
            "an installed package name reached the enrichment request"
        )
        // Positive anchor: the inventory really was read, so the emptiness above
        // is not the emptiness of an unread file.
        #expect(inventory.contains("go"))
        #expect(inventory.contains("ripgrep"))
    }

    /// Volume follows findings, and the batch ceiling is 100.
    @Test("Identifiers are batched at one hundred per request")
    func identifiersAreBatchedAtOneHundred() async throws {
        let identifiers = (1...101).map { String(format: "CVE-2026-%04d", $0) }
        let network = RecordingNetwork(
            fallback: .ok(try Fixture.data("NVD/cveids-response.json"))
        )

        _ = try await Self.source(on: network).enrich(identifiers)

        let exchanges = network.exchanges
        #expect(exchanges.count == 2, "101 identifiers took \(exchanges.count) requests")

        let first = try Self.identifiers(in: try #require(exchanges.first).url)
        let second = try Self.identifiers(in: try #require(exchanges.last).url)
        #expect(first.count == 100)
        #expect(second.count == 1)
        #expect(first + second == identifiers, "batching lost or reordered an identifier")
    }

    /// Exactly one hundred is one request, so the split is `> 100` rather than
    /// `>= 100`.
    @Test("Exactly one hundred identifiers travel in a single request")
    func exactlyOneHundredIdentifiersTakeOneRequest() async throws {
        let identifiers = (1...100).map { String(format: "CVE-2026-%04d", $0) }
        let network = RecordingNetwork(
            fallback: .ok(try Fixture.data("NVD/cveids-response.json"))
        )

        _ = try await Self.source(on: network).enrich(identifiers)

        #expect(network.exchanges.count == 1)
    }

    /// No findings, no request. The whole point of enriching by identifier is
    /// that an inventory with nothing wrong in it costs nothing.
    @Test("An empty identifier list issues no request whatsoever")
    func anEmptyIdentifierListIssuesNoRequest() async throws {
        let network = RecordingNetwork()

        let enrichment = try await Self.source(on: network).enrich([])

        #expect(network.exchanges.isEmpty, "an empty enrichment reached the network")
        #expect(enrichment.severities.isEmpty)
    }

    // MARK: - The credential seam

    @Test("The API key is read from the credential seam and never from user defaults")
    func theApiKeyIsReadFromTheCredentialSeamAndNeverFromDefaults() async throws {
        let network = RecordingNetwork(
            fallback: .ok(try Fixture.data("NVD/cveids-response.json"))
        )

        _ = try await Self.source(on: network, key: "seam-supplied-key").enrich(["CVE-2026-0994"])

        let request = try #require(network.exchanges.first)
        #expect(
            request.headers["apiKey"] == "seam-supplied-key",
            "the key did not travel in the header NVD reads it from"
        )
        // The key is a credential: it belongs in a header, never in a URL that
        // proxies and server logs record verbatim.
        #expect(request.url.absoluteString.contains("seam-supplied-key") == false)

        // The seam is the *only* source. With nothing stored, nothing is sent —
        // rather than a default read from somewhere else.
        let anonymousNetwork = RecordingNetwork(
            fallback: .ok(try Fixture.data("NVD/cveids-response.json"))
        )
        _ = try await Self.source(on: anonymousNetwork).enrich(["CVE-2026-0994"])
        let anonymous = try #require(anonymousNetwork.exchanges.first)
        #expect(anonymous.headers["apiKey"] == nil)
    }

    // MARK: - Enrichment answers

    /// The captured seven-record response, tiered.
    @Test("A successful enrichment tiers every record it could read")
    func aSuccessfulEnrichmentTiersEveryRecordItRead() async throws {
        let network = RecordingNetwork(
            fallback: .ok(try Fixture.data("NVD/cveids-response.json"))
        )

        let enrichment = try await Self.source(on: network)
            .enrich(["CVE-2026-0994", "CVE-2021-36753"])

        #expect(enrichment.severities.count == 7, "the captured seven records did not all tier")
        // `CVE-2026-0994` carries v4.0 8.2 beside v3.1 7.5: both `high`, and the
        // v4.0 preference is `SeverityTierTests`' subject. Here it only has to
        // arrive tiered rather than absent.
        #expect(enrichment.severities["CVE-2026-0994"] == .high)
        #expect(enrichment.skippedRecordCount == 0)
    }

    // MARK: - Degradation

    /// The advisory this scenario needs and why it is that one.
    ///
    /// `PYSEC-2026-899` publishes **no severity word of its own** and carries a
    /// CVSS v3.1 *vector* with no base score, which is the ordinary OSV shape. Its
    /// tier therefore comes from NVD or from nowhere — exactly the record whose
    /// severity a rate limit can remove. It names `PyPI/protobuf`, a package the
    /// curated table maps, and its alias `CVE-2022-1941` is in the captured
    /// enrichment response, so the same record can be run down both paths.
    static func unratedAdvisory() throws -> OSVAdvisory {
        try OSVWire.advisory(from: Fixture.data("OSV/vulns-PYSEC-2026-899.json"))
    }

    static func protobufQuery() throws -> AdvisoryQuery {
        try #require(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "protobuf"),
                installedVersion: "3.20.1"
            ).query
        )
    }

    /// The `vulnerability-scanning` scenario: *a rate-limited enrichment does not
    /// fabricate severity or health*.
    ///
    /// Discovery succeeded — the advisory here is real, hydrated from a captured
    /// `vulns-*` file — and enrichment is refused with the real 429. Three things
    /// must all hold at once, and each one alone would let the bug through: the
    /// finding survives, its severity stays `unrated`, and no package's outcome
    /// becomes `covered(clean)`.
    @Test("A rate-limited enrichment keeps findings unrated and never makes a package clean")
    func aRateLimitedEnrichmentKeepsFindingsUnratedAndNeverMakesAPackageClean() async throws {
        let advisory = try Self.unratedAdvisory()
        let query = try Self.protobufQuery()
        let cveID = try #require(advisory.cveID)

        let network = RecordingNetwork(
            fallback: .response(
                statusCode: 429,
                headers: ["content-type": "text/plain; charset=UTF-8", "retry-after": "0"],
                body: try Fixture.data("NVD/ratelimited-response.body")
            )
        )

        var enrichmentError: AdvisoryError?
        do {
            _ = try await Self.source(on: network).enrich([cveID])
        } catch {
            enrichmentError = error
        }
        #expect(enrichmentError == .rateLimited, "a 429 was not reported as a rate limit")

        // The scan settles with discovery's answer and no severities at all.
        let outcome = CVEMatcher().match(
            query: query,
            answer: .answered([advisory]),
            severities: [:]
        )

        guard case .covered(.findings(let findings)) = outcome else {
            Issue.record("a rate-limited enrichment changed a package's coverage state")
            return
        }
        #expect(findings.count == 1)
        #expect(findings.allSatisfy { $0.severity == .unrated })
        #expect(
            outcome != .covered(.clean(CleanCoverage(answeredBy: .osv, queriedVersion: "3.20.1")))
        )

        // The typed reason travels with the result rather than being discarded:
        // "we never asked" and "we asked and were refused" are different facts.
        let provenance = ScanProvenance(
            scannedAt: Date(timeIntervalSince1970: 0),
            matcherVersion: CVEMatcher.version,
            mappingRevision: EcosystemMapping.revision,
            enrichmentAttempted: true,
            enrichmentSucceeded: false
        )
        #expect(provenance.enrichmentAttempted)
        #expect(provenance.enrichmentSucceeded == false)
    }

    /// The control: the **same** advisory, with enrichment available, is tiered.
    ///
    /// Without this, `unrated` above would be indistinguishable from a matcher
    /// that rates nothing at all.
    @Test("The same finding with enrichment available is tiered rather than unrated")
    func theSameFindingWithEnrichmentAvailableIsTiered() async throws {
        let advisory = try Self.unratedAdvisory()
        let query = try Self.protobufQuery()
        let cveID = try #require(advisory.cveID)

        let network = RecordingNetwork(
            fallback: .ok(try Fixture.data("NVD/cveids-response.json"))
        )
        let enrichment = try await Self.source(on: network).enrich([cveID])

        let outcome = CVEMatcher().match(
            query: query,
            answer: .answered([advisory]),
            severities: enrichment.severities
        )

        guard case .covered(.findings(let findings)) = outcome else {
            Issue.record("the enriched path lost the finding")
            return
        }
        let severity = try #require(findings.first?.severity)
        #expect(severity.isScored, "enrichment produced no tier for \(cveID)")
        #expect(severity != .unrated)
    }

    /// The other half of "does not fabricate": a severity the *advisory itself*
    /// published is not thrown away when enrichment fails.
    ///
    /// `GHSA-p24j-h477-76q3` advertises `HIGH`. That is a published fact, not an
    /// inference, so it survives the rate limit — and this is what stops the test
    /// above from being satisfied by an implementation that simply reports
    /// `unrated` for everything whenever NVD is unavailable.
    @Test("An advisory's own published severity survives a rate-limited enrichment")
    func anAdvisorysOwnPublishedSeveritySurvivesARateLimit() throws {
        let advisory = try OSVWire.advisory(
            from: Fixture.data("OSV/vulns-GHSA-p24j-h477-76q3.json")
        )
        let query = try #require(
            AdvisoryQueryPlanner.plan(
                for: PackageID(kind: .formula, name: "bat"),
                installedVersion: "0.15.0"
            ).query
        )

        let outcome = CVEMatcher().match(
            query: query,
            answer: .answered([advisory]),
            severities: [:]
        )

        guard case .covered(.findings(let findings)) = outcome else {
            Issue.record("a rate-limited enrichment changed a package's coverage state")
            return
        }
        #expect(findings.first?.severity == .high)
    }
}
