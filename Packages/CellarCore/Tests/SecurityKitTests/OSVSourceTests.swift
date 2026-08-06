import Catalog
import Foundation
import SecurityKit
import Testing

/// What `OSVSource` puts on the wire, and what it refuses to read.
///
/// Every test here runs behind `RecordingURLProtocol`, so the subject is the
/// **request**, not a stand-in for it. The three rules being pinned are the ones
/// a future edit is most likely to break quietly: exactly one discovery request
/// carrying exactly the mapped subset, a session that cannot cache, and a
/// response whose status is judged before a single byte is decoded.
///
/// Each test owns a `RecordingNetwork`, whose tag keeps its ledger private even
/// though `URLProtocol` registration is process-global.
@Suite("OSV advisory source")
struct OSVSourceTests {
    // MARK: - The captured request

    /// The seven mapped packages at their real installed versions — the exact
    /// input the phase-2 capture was taken with.
    static let capturedQueries: [(formula: String, version: String)] = [
        ("bat", "0.26.1"),
        ("eza", "0.23.5"),
        ("llhttp", "9.4.3"),
        ("protobuf", "35.1"),
        ("ripgrep", "15.2.0"),
        ("sd", "1.1.0"),
        ("uv", "0.12.1")
    ]

    /// The five packages the **affected** capture was taken with, at the older
    /// versions chosen to reach real advisories.
    static let affectedQueries: [(formula: String, version: String)] = [
        ("protobuf", "3.20.1"),
        ("llhttp", "2.1.2"),
        ("bat", "0.15.0"),
        ("uv", "0.1.0"),
        ("ripgrep", "0.10.0")
    ]

    static func plannedQueries(
        _ captured: [(formula: String, version: String)] = capturedQueries
    ) throws -> [AdvisoryQuery] {
        try captured.map { formula, version in
            try #require(
                AdvisoryQueryPlanner.plan(
                    for: PackageID(kind: .formula, name: formula),
                    installedVersion: version
                ).query,
                "\(formula) \(version) is in a captured request and is no longer planned"
            )
        }
    }

    /// Both sides of the request comparison, through one serializer that knows
    /// nothing about this target's types.
    ///
    /// The capture was **authored** pretty-printed with a trailing newline, and a
    /// real client sends compact JSON, so the raw bytes cannot be equal. What
    /// must be equal is the request's content: the same seven queries, the same
    /// ecosystems, names and versions, in the same order, and no other key
    /// anywhere. Normalising both sides through `JSONSerialization` — which has
    /// no knowledge of `AdvisoryQuery` and cannot silently agree with a bug in
    /// the encoder — makes that an exact byte comparison of canonical forms. A
    /// dropped field, an extra field or a reordered array all change the bytes.
    static func canonical(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    @Test("Discovery posts exactly one querybatch carrying exactly the mapped subset")
    func discoveryPostsExactlyOneQuerybatchWithTheMappedSubset() async throws {
        let captured = try Fixture.data("OSV/querybatch-response.json")
        let network = RecordingNetwork(queue: [.ok(captured)])
        let source = OSVSource(session: network.session)

        let discovery = try await source.discover(Self.plannedQueries())

        let exchanges = network.exchanges
        #expect(exchanges.count == 1, "discovery issued \(exchanges.count) requests, not one")
        let request = try #require(exchanges.first)
        #expect(request.method == "POST")
        #expect(request.url.absoluteString == "https://api.osv.dev/v1/querybatch")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

        let body = try #require(request.body, "the querybatch request carried no body")
        let produced = try Self.canonical(body)
        let expected = try Self.canonical(Fixture.data("OSV/querybatch-request.json"))
        #expect(
            produced == expected,
            """
            the request body no longer matches the capture:
            \(String(data: produced, encoding: .utf8) ?? "<not utf8>")
            """
        )

        // The capture is all-clean, so every slot is a real answer with nothing
        // in it — and that is a different value from no answer at all.
        #expect(discovery.answers.count == 7)
        #expect(discovery.answers.allSatisfy { $0.answer == .answered([]) })
    }

    /// The subset is genuinely a subset: nothing the planner refused reaches the
    /// wire, and a request is not issued at all when nothing is mappable.
    @Test("An empty query list issues no request whatsoever")
    func anEmptyQueryListIssuesNoRequest() async throws {
        let network = RecordingNetwork()
        let source = OSVSource(session: network.session)

        let discovery = try await source.discover([])

        #expect(network.exchanges.isEmpty, "an empty scan still reached the network")
        #expect(discovery.answers.isEmpty)
    }

    // MARK: - The session

    /// The configuration the shipped source uses, asserted rather than assumed.
    ///
    /// A URL cache here would let a stale 200 be replayed in place of a fresh
    /// query, which for advisory data means presenting yesterday's "clean" as
    /// today's answer while the freshness label claims `.live`.
    @Test("The advisory session is ephemeral, holds no URL cache, and reloads ignoring it")
    func theSessionIsEphemeralWithNoURLCache() async throws {
        let configuration = AdvisorySession.configuration()

        #expect(configuration.urlCache == nil, "the advisory session kept a URL cache")
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        // `.ephemeral` is what makes the credential and cookie stores private to
        // this session rather than the process-wide shared ones. `.default`
        // fails both of these; `.ephemeral` passes both.
        #expect(configuration.urlCredentialStorage !== URLCredentialStorage.shared)
        #expect(configuration.httpCookieStorage !== HTTPCookieStorage.shared)

        // Belt and braces: the policy is on the request too, because an
        // intermediate can serve a stored response to a request that did not
        // forbid it.
        let network = RecordingNetwork(
            queue: [.ok(try Fixture.data("OSV/querybatch-response.json"))]
        )
        let source = OSVSource(session: network.session)
        _ = try await source.discover(Self.plannedQueries())

        let request = try #require(network.exchanges.first)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    // MARK: - The byte guard

    /// Eight mebibytes is the ceiling, and it is enforced **before** the decoder
    /// runs.
    ///
    /// The oversized body is deliberately not JSON. If the guard ran after the
    /// decode, this would surface as `malformedPayload`; it surfaces as
    /// `payloadTooLarge`, which is only reachable if the size was judged first.
    @Test("A body over eight mebibytes is rejected before any decode is attempted")
    func aBodyOverEightMebibytesIsRejectedBeforeDecode() async throws {
        let oversized = Data(repeating: UInt8(ascii: "A"), count: 8 * 1_048_576 + 1)
        let network = RecordingNetwork(queue: [.ok(oversized)])
        let source = OSVSource(session: network.session)

        await #expect(throws: AdvisoryError.payloadTooLarge) {
            try await source.discover(Self.plannedQueries())
        }
    }

    /// The other side of the boundary, so the guard is `>` and not `>=` and is
    /// not simply rejecting everything.
    @Test("A body of exactly eight mebibytes is read normally")
    func aBodyOfExactlyEightMebibytesIsAccepted() async throws {
        let envelope = #"{"results":[{},{},{},{},{},{},{}],"pad":""#
        let suffix = #""}"#
        let padding = 8 * 1_048_576 - envelope.utf8.count - suffix.utf8.count
        let payload = Data((envelope + String(repeating: "A", count: padding) + suffix).utf8)
        #expect(payload.count == 8 * 1_048_576)

        let network = RecordingNetwork(queue: [.ok(payload)])
        let source = OSVSource(session: network.session)

        let discovery = try await source.discover(Self.plannedQueries())

        #expect(discovery.answers.count == 7)
    }

    // MARK: - Status before decode

    /// The real rate-limited capture: `429`, `text/plain`, seventeen bytes
    /// reading `error code: 1015`.
    ///
    /// This is the U2(c) probe answer stated as a test. Decoding before
    /// classifying would report a *JSON* failure for a rate limit, and the whole
    /// scan would then be indistinguishable from a corrupt response.
    @Test("A rate-limited response is classified from its status, not from its body")
    func aNonSuccessStatusIsClassifiedBeforeAnyDecodeAttempt() async throws {
        let body = try Fixture.data("NVD/ratelimited-response.body")
        #expect(body.count == 17, "the captured rate-limit body is not the 17 bytes recorded")

        let network = RecordingNetwork(
            queue: [
                .response(
                    statusCode: 429,
                    headers: ["content-type": "text/plain; charset=UTF-8", "retry-after": "0"],
                    body: body
                )
            ]
        )
        let source = OSVSource(session: network.session)

        await #expect(throws: AdvisoryError.rateLimited) {
            try await source.discover(Self.plannedQueries())
        }
    }

    /// A second non-success status, so `rateLimited` is not simply what every
    /// failure returns.
    @Test("A server error is a transport failure rather than a rate limit")
    func aServerErrorIsClassifiedApartFromARateLimit() async throws {
        let body = try Fixture.data("NVD/ratelimited-response.body")
        let network = RecordingNetwork(
            queue: [.response(statusCode: 503, headers: [:], body: body)]
        )
        let source = OSVSource(session: network.session)

        await #expect(throws: AdvisoryError.transportFailed) {
            try await source.discover(Self.plannedQueries())
        }
    }

    /// The control that makes the two above mean something. The *same*
    /// undecodable bytes behind a `200` reach the decoder and fail there, which
    /// is the only way to know the status classification is doing the work
    /// rather than the decoder failing for everyone.
    @Test("The same undecodable bytes behind a 200 fail in the decoder, not in the classifier")
    func undecodableBytesBehindASuccessStatusFailInTheDecoder() async throws {
        let body = try Fixture.data("NVD/ratelimited-response.body")
        let network = RecordingNetwork(queue: [.ok(body)])
        let source = OSVSource(session: network.session)

        await #expect(throws: AdvisoryError.malformedPayload) {
            try await source.discover(Self.plannedQueries())
        }
    }

    /// A transport that never produced a status at all.
    @Test("A transport failure with no HTTP response at all is reported as offline")
    func aTransportFailureIsReportedAsOffline() async throws {
        let network = RecordingNetwork(queue: [.transportFailure])
        let source = OSVSource(session: network.session)

        await #expect(throws: AdvisoryError.offline) {
            try await source.discover(Self.plannedQueries())
        }
    }

    // MARK: - Hydration

    /// Discovery is two hops: `querybatch` names advisories, `vulns/{id}`
    /// hydrates them. The real affected capture drives this, so the counts come
    /// from captured data rather than from the author's expectation.
    @Test("Every advisory querybatch names is hydrated exactly once, by identifier")
    func everyNamedAdvisoryIsHydratedOnceByIdentifier() async throws {
        let batch = try Fixture.data("OSV/querybatch-affected-response.json")
        let decoded = try OSVWire.querybatch(from: batch)

        var named: [String] = []
        for result in decoded.results {
            guard case .answered(let references) = result else { continue }
            named.append(contentsOf: references.map(\.id))
        }
        let unique = Array(Set(named)).sorted()
        #expect(unique.count >= 5, "the affected capture named too few advisories to test with")

        // The querybatch answer is queued; every hydration after it takes the
        // fallback, because the claim under test is *which URLs were reached and
        // how many times*, not what came back from them. What a real hydration
        // decodes into is `OSVWireTests`' subject.
        let network = RecordingNetwork(queue: [.ok(batch)], fallback: .ok(Self.minimalAdvisory))
        let source = OSVSource(session: network.session)

        _ = try await source.discover(Self.plannedQueries(Self.affectedQueries))

        let exchanges = network.exchanges
        #expect(
            exchanges.count == 1 + unique.count,
            "hydration issued \(exchanges.count - 1) requests for \(unique.count) advisories"
        )
        let hydrationURLs = exchanges.dropFirst().map(\.url.absoluteString).sorted()
        #expect(
            hydrationURLs == unique.map { "https://api.osv.dev/v1/vulns/\($0)" }.sorted(),
            "a hydration reached a URL that is not an advisory identifier"
        )
        #expect(exchanges.dropFirst().allSatisfy { $0.method == "GET" })
    }

    /// The smallest payload `OSVWire.advisory(from:)` accepts. Only its
    /// well-formedness matters here.
    private static let minimalAdvisory = Data(
        #"{"id":"OSV-STUB","modified":"2026-07-07T17:56:36.712428283Z"}"#.utf8
    )

    /// A positional result that could not be read stays unanswered, and does not
    /// borrow the answer of the query beside it.
    @Test("An unreadable result slot becomes an unanswered package, not a clean one")
    func anUnreadableResultSlotBecomesUnansweredRatherThanClean() async throws {
        let payload = try Fixture.data("OSV/querybatch-badresult-response.json")
        let network = RecordingNetwork(queue: [.ok(payload)], fallback: .ok(Self.minimalAdvisory))
        let source = OSVSource(session: network.session)

        // The capture holds three slots, so three queries go with it. A count
        // that did not line up would be rejected outright — see below.
        let discovery = try await source.discover(
            Self.plannedQueries(Array(Self.affectedQueries.prefix(3)))
        )

        #expect(discovery.answers.count == 3)
        #expect(
            discovery.answers[0].answer == .unanswered(.malformedRecord),
            "the unreadable slot was not reported as unanswered"
        )
        #expect(
            discovery.answers.dropFirst().allSatisfy {
                if case .answered = $0.answer { return true } else { return false }
            },
            "the bad slot swallowed the answers beside it"
        )
        #expect(discovery.skippedRecordCount > 0)
    }

    /// The positional payload's own safety rule: if the answer count does not
    /// match the question count, **no** position can be trusted.
    ///
    /// Batch 2 established that a dropped result re-attributes every later answer
    /// to the wrong package. This is the same failure arriving from the server
    /// side rather than from the decoder, and it must fail the request rather
    /// than file somebody else's advisories against the first few packages.
    @Test("A result count that disagrees with the query count fails the whole request")
    func aResultCountThatDisagreesWithTheQueryCountFailsTheRequest() async throws {
        let payload = try Fixture.data("OSV/querybatch-badrecord-response.json")
        let network = RecordingNetwork(queue: [.ok(payload)], fallback: .ok(Self.minimalAdvisory))
        let source = OSVSource(session: network.session)

        await #expect(throws: AdvisoryError.malformedPayload) {
            // One result, seven questions.
            try await source.discover(Self.plannedQueries())
        }
    }
}
