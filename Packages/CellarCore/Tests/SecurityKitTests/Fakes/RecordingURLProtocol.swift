import Foundation
import SecurityKit
import Synchronization

/// The network seam every acquisition test runs behind.
///
/// A `URLProtocol` rather than a hand-rolled `AdvisorySource` fake, because the
/// questions these tests ask are about the **request** — its method, its URL, its
/// body, its cache policy, its headers — and a protocol fake would answer them
/// about a type that never touches `URLSession`. The claim under test is that the
/// shipped source puts exactly these bytes on the wire and nothing else; only a
/// seam below `URLSession` can witness that.
///
/// ## Why every recording is tagged
///
/// `URLProtocol` registration is process-global and Swift Testing runs suites
/// concurrently, so one shared ledger means one suite's requests land in another
/// suite's assertions — silently, and as a wrong count rather than a crash.
/// Each `RecordingNetwork` therefore stamps its own session with a private tag
/// header and only ever sees its own exchanges.
final class RecordingURLProtocol: URLProtocol {
    static let tagHeader = "X-Cellar-Recorder"

    /// One request, exactly as it reached the transport.
    struct Exchange: Sendable {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data?
        let cachePolicy: URLRequest.CachePolicy
    }

    /// What the recorder answers with.
    enum Stub: Sendable {
        case response(statusCode: Int, headers: [String: String], body: Data)
        /// The transport itself failed — no HTTP status, no body.
        case transportFailure

        static func ok(_ body: Data) -> Self {
            .response(statusCode: 200, headers: [:], body: body)
        }
    }

    struct Ledger: Sendable {
        var queued: [Stub] = []
        var fallback: Stub = .ok(Data("{}".utf8))
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
            body: Self.body(of: request),
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

    // MARK: - Body

    /// `URLSession` moves a request's `httpBody` into an `httpBodyStream` before
    /// a `URLProtocol` ever sees it, so reading `httpBody` alone records `nil`
    /// for every POST and the byte comparison would pass against nothing.
    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let capacity = 8 * 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: capacity)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// One test's private view of the network.
///
/// Built from the **shipped** `AdvisorySession.configuration()` rather than a
/// bespoke one: if the advisory session stopped disabling the URL cache, these
/// tests would run against the regression instead of around it.
struct RecordingNetwork: Sendable {
    let tag: String
    let session: URLSession

    init(
        queue: [RecordingURLProtocol.Stub] = [],
        fallback: RecordingURLProtocol.Stub = .ok(Data("{}".utf8))
    ) {
        let tag = UUID().uuidString
        self.tag = tag
        RecordingURLProtocol.ledgers.withLock {
            $0[tag] = RecordingURLProtocol.Ledger(queued: queue, fallback: fallback)
        }

        let configuration = AdvisorySession.configuration()
        configuration.protocolClasses = [RecordingURLProtocol.self]
        // Every request through this session carries the tag, which is both how
        // the protocol claims the request and how it finds the right ledger.
        configuration.httpAdditionalHeaders = [RecordingURLProtocol.tagHeader: tag]
        session = URLSession(configuration: configuration)
    }

    var exchanges: [RecordingURLProtocol.Exchange] {
        RecordingURLProtocol.ledgers.withLock { $0[tag]?.exchanges ?? [] }
    }
}
