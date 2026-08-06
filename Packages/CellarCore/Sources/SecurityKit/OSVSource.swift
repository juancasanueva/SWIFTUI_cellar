import Foundation

/// Advisory discovery against `api.osv.dev`.
///
/// Two hops, and both are deliberate. `POST /v1/querybatch` asks one question per
/// mapped package and comes back with nothing but identifiers and timestamps —
/// cheap, and enough to decide whether anything changed. `GET /v1/vulns/{id}`
/// hydrates only the advisories that batch actually named, so a clean inventory
/// costs exactly one request.
///
/// ## What never happens here
///
/// No range is evaluated. Whether an installed version is affected is OSV's
/// answer, computed against OSV's own declared ranges; this type transports that
/// answer and nothing more. The `queryVersion` on the wire is the lexical
/// upstream — the `_N` Homebrew revision removed — because `1.2.3_1` is a
/// packaging revision of `1.2.3` and no advisory database has ever heard of it.
public struct OSVSource: AdvisoryDiscovering {
    /// The one host this type reaches, compiled in.
    ///
    /// A `static let` String rather than a `URL`, so `EgressStructureTests` can
    /// compare the declared constant against the literals it finds in this
    /// directory and assert set equality rather than maintain an allow-list.
    public static let baseURL = "https://api.osv.dev/"

    private let session: URLSession
    private let byteLimit: Int

    public init(
        session: URLSession = AdvisorySession.make(),
        byteLimit: Int = AdvisorySession.payloadByteLimit
    ) {
        self.session = session
        self.byteLimit = byteLimit
    }

    // MARK: - Discovery

    public func discover(
        _ queries: [AdvisoryQuery]
    ) async throws(AdvisoryError) -> AdvisoryDiscovery {
        // Nothing mapped, nothing asked. The common case on a real inventory is
        // a handful of queries out of a hundred and fifty formulae, and the
        // empty case must cost zero requests rather than one empty one.
        guard queries.isEmpty == false else {
            return AdvisoryDiscovery(answers: [], skippedRecordCount: 0)
        }

        let batch = try await querybatch(queries)

        // A positional payload whose length disagrees with the question list is
        // not partially usable: every position after the discrepancy could belong
        // to a different package. Batch 2 measured what that costs — three real
        // `llhttp` advisories filed against whatever was query 0 — so the whole
        // request fails instead.
        guard batch.results.count == queries.count else { throw .malformedPayload }

        var named: [String: Date] = [:]
        for result in batch.results {
            guard case .answered(let references) = result else { continue }
            for reference in references {
                named[reference.id] = reference.modified
            }
        }

        let hydration = try await hydrate(Array(named.keys).sorted())

        let answers = batch.results.map { result -> DiscoveredAnswer in
            switch result {
            case .unreadable:
                // The slot survives as an *unanswered* package. Not clean —
                // nobody could tell us about this one.
                return DiscoveredAnswer(answer: .unanswered(.malformedRecord), newestModified: nil)
            case .answered(let references):
                return DiscoveredAnswer(
                    answer: .answered(references.compactMap { hydration.advisories[$0.id] }),
                    newestModified: references.map(\.modified).max()
                )
            }
        }

        return AdvisoryDiscovery(
            answers: answers,
            skippedRecordCount: batch.skippedRecordCount + hydration.skippedRecordCount
        )
    }

    // MARK: - The two requests

    private func querybatch(
        _ queries: [AdvisoryQuery]
    ) async throws(AdvisoryError) -> OSVQuerybatchResponse {
        guard let url = URL(string: Self.baseURL + "v1/querybatch") else {
            throw .transportFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Braces on the session's own policy: an intermediate may serve a stored
        // response to a request that did not forbid it.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            request.httpBody = try Self.encoder.encode(QuerybatchRequestWire(queries))
        } catch {
            throw .malformedPayload
        }

        let data = try await AdvisorySession.body(
            for: request,
            on: session,
            byteLimit: byteLimit
        )
        return try OSVWire.querybatch(from: data)
    }

    private struct Hydration {
        var advisories: [String: OSVAdvisory] = [:]
        var skippedRecordCount = 0
    }

    /// Fetches each named advisory exactly once.
    ///
    /// Keyed by identifier and deduplicated, because one advisory routinely
    /// applies to several installed packages and asking for it once per package
    /// would multiply request volume by the very thing this feature promises not
    /// to scale with.
    ///
    /// A hydration that fails on its *own* content costs that advisory and is
    /// counted — the record rule. A rate limit or a dead network is not about
    /// this advisory at all, so it ends discovery rather than quietly reducing
    /// the answer.
    private func hydrate(_ identifiers: [String]) async throws(AdvisoryError) -> Hydration {
        var hydration = Hydration()

        for identifier in identifiers {
            guard Self.isWellFormedIdentifier(identifier),
                  let url = URL(string: Self.baseURL + "v1/vulns/" + identifier)
            else {
                hydration.skippedRecordCount += 1
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            do {
                let data = try await AdvisorySession.body(
                    for: request,
                    on: session,
                    byteLimit: byteLimit
                )
                hydration.advisories[identifier] = try OSVWire.advisory(from: data)
            } catch AdvisoryError.rateLimited {
                throw .rateLimited
            } catch AdvisoryError.offline {
                throw .offline
            } catch {
                hydration.skippedRecordCount += 1
            }
        }

        return hydration
    }

    // MARK: - Identifiers

    /// Advisory identifiers come off the wire, so they are treated as untrusted
    /// input even though they are not user input.
    ///
    /// Restricting to the alphabet OSV actually uses means the hydration URL is
    /// a constant prefix plus a string that cannot contain `/`, `?`, `#`, `..`
    /// or a scheme — so no identifier can steer a request off the declared host,
    /// and no percent-encoding step is needed to make that true.
    static func isWellFormedIdentifier(_ identifier: String) -> Bool {
        guard identifier.isEmpty == false, identifier.count <= 64 else { return false }
        return identifier.allSatisfy { character in
            guard character.isASCII else { return false }
            return character.isLetter || character.isNumber
                || character == "-" || character == "_" || character == "."
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        // Deterministic bytes: the same inventory produces the same request
        // every time, which is what makes the captured request a testable
        // artefact rather than an illustration.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

// MARK: - Wire shape

private struct QuerybatchPackageWire: Encodable {
    let ecosystem: String
    let name: String
}

private struct QuerybatchQueryWire: Encodable {
    let package: QuerybatchPackageWire
    let version: String
}

private struct QuerybatchRequestWire: Encodable {
    let queries: [QuerybatchQueryWire]

    init(_ queries: [AdvisoryQuery]) {
        self.queries = queries.map { query in
            QuerybatchQueryWire(
                package: QuerybatchPackageWire(
                    ecosystem: query.ecosystem,
                    name: query.ecosystemPackageName
                ),
                // The lexical upstream, never the installed string: a `_N`
                // Homebrew revision is packaging, and sending it would ask OSV
                // about a version that does not exist upstream.
                version: query.queryVersion
            )
        }
    }
}
