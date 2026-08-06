import Foundation
import ReleaseNotes
import Synchronization

/// The network seam every acquisition test runs behind.
///
/// A `URLProtocol` rather than a hand-rolled `ReleaseNotesSource` fake, because
/// the questions these tests ask are about the **request** — its method, its URL,
/// its headers, its cache policy, and above all *how many of it there were* — and
/// a protocol fake would answer them about a type that never touches
/// `URLSession`. The claim under test is that the shipped source puts exactly
/// these bytes on the wire and nothing else; only a seam below `URLSession` can
/// witness that.
///
/// ## Why every recording is tagged
///
/// `URLProtocol` registration is per-configuration here, but the ledger is
/// process-global and Swift Testing runs suites concurrently, so one shared
/// ledger would mean one suite's requests landing in another suite's assertions —
/// silently, and as a wrong count rather than a crash. Each `RecordingNetwork`
/// stamps its own session with a private tag header and only ever sees its own
/// exchanges.
final class RecordingURLProtocol: URLProtocol {
    static let tagHeader = "X-Cellar-Release-Notes-Recorder"

    /// One request, exactly as it reached the transport.
    struct Exchange: Sendable {
        let url: URL
        let method: String
        let headers: [String: String]
        let cachePolicy: URLRequest.CachePolicy
    }

    /// What the recorder answers with.
    enum Stub: Sendable {
        case response(statusCode: Int, headers: [String: String], body: Data)
        /// The transport itself failed — no HTTP status, no body.
        case transportFailure

        static func ok(_ body: Data, headers: [String: String] = [:]) -> Self {
            .response(statusCode: 200, headers: headers, body: body)
        }
    }

    struct Ledger: Sendable {
        var queued: [Stub] = []
        var fallback: Stub = .ok(Data("[]".utf8))
        var exchanges: [Exchange] = []
    }

    // MARK: - The registry

    static let ledgers = Mutex<[String: Ledger]>([:])

    // MARK: - URLProtocol

    // `URLProtocol` declares both of these as class methods, so an override
    // cannot be `static`. The rule is right in general and inapplicable here.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: tagHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let tag = request.value(forHTTPHeaderField: Self.tagHeader) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        var headers = request.allHTTPHeaderFields ?? [:]
        headers.removeValue(forKey: Self.tagHeader)

        let exchange = Exchange(
            url: request.url ?? URL(fileURLWithPath: "/"),
            method: request.httpMethod ?? "",
            headers: headers,
            cachePolicy: request.cachePolicy
        )

        let stub = Self.ledgers.withLock { ledgers -> Stub in
            var ledger = ledgers[tag] ?? Ledger()
            ledger.exchanges.append(exchange)
            let stub = ledger.queued.isEmpty ? ledger.fallback : ledger.queued.removeFirst()
            ledgers[tag] = ledger
            return stub
        }

        switch stub {
        case .transportFailure:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .response(let statusCode, let headers, let body):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                      url: url,
                      statusCode: statusCode,
                      httpVersion: "HTTP/2",
                      headerFields: headers
                  )
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// One test's private view of the network.
///
/// Built from the **shipped** `ReleaseNotesSession.configuration()` rather than a
/// bespoke one: if the session stopped disabling the URL cache, or stopped being
/// ephemeral, these tests would run against the regression instead of around it.
struct RecordingNetwork: Sendable {
    let tag: String
    let session: URLSession

    init(
        queue: [RecordingURLProtocol.Stub] = [],
        fallback: RecordingURLProtocol.Stub = .ok(Data("[]".utf8))
    ) {
        let tag = UUID().uuidString
        self.tag = tag
        RecordingURLProtocol.ledgers.withLock {
            $0[tag] = RecordingURLProtocol.Ledger(queued: queue, fallback: fallback)
        }

        let configuration = ReleaseNotesSession.configuration()
        configuration.protocolClasses = [RecordingURLProtocol.self]
        // Every request through this session carries the tag, which is both how
        // the protocol claims the request and how it finds the right ledger.
        configuration.httpAdditionalHeaders = [RecordingURLProtocol.tagHeader: tag]
        session = URLSession(configuration: configuration)
    }

    var exchanges: [RecordingURLProtocol.Exchange] {
        RecordingURLProtocol.ledgers.withLock { $0[tag]?.exchanges ?? [] }
    }

    var requestCount: Int { exchanges.count }
}

// MARK: - Convenience stubs

extension RecordingURLProtocol.Stub {
    /// The rate-limit headers a live GitHub 200 carries, so a success path can be
    /// asserted to surface a budget rather than an empty status.
    static func releases(_ body: Data, etag: String? = nil, remaining: Int = 58) -> Self {
        var headers = [
            "Content-Type": "application/json; charset=utf-8",
            "x-ratelimit-limit": "60",
            "x-ratelimit-remaining": String(remaining),
            "x-ratelimit-reset": "1786055400"
        ]
        if let etag { headers["ETag"] = etag }
        return .response(statusCode: 200, headers: headers, body: body)
    }

    /// A `403` with an exhausted budget: the refusal that must never read as an
    /// absence.
    static func rateLimited(resetEpoch: Int = 1_786_055_400) -> Self {
        .response(
            statusCode: 403,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "x-ratelimit-limit": "60",
                "x-ratelimit-remaining": "0",
                "x-ratelimit-reset": String(resetEpoch)
            ],
            body: Data(#"{"message":"API rate limit exceeded"}"#.utf8)
        )
    }

    /// A `401`, carrying **no** rate-limit header at all — the shape the live
    /// capture recorded.
    static func unauthorized() -> Self {
        .response(
            statusCode: 401,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: Data(#"{"message":"Bad credentials"}"#.utf8)
        )
    }

    static func notModified(etag: String) -> Self {
        .response(
            statusCode: 304,
            headers: [
                "ETag": etag,
                "x-ratelimit-limit": "60",
                "x-ratelimit-remaining": "57",
                "x-ratelimit-reset": "1786055400"
            ],
            body: Data()
        )
    }
}
