//
//  ReleaseNotesCompositionSupport.swift
//  cellarTests
//

import Foundation
import ReleaseNotes
import Synchronization

/// A private, **per-instance** network seam for the composition guards.
///
/// Deliberately not `CompositionRequestSpy`. That one registers globally and
/// counts into a `static`, which is correct for the security suite's questions and
/// wrong for these: Swift Testing runs suites concurrently, so a test that
/// *makes* a request to prove the counter works will clobber a concurrent test
/// that asserts the counter is zero. The two failed in alternation until this
/// existed.
///
/// Built from the **shipped** `ReleaseNotesSession.configuration()`, so a
/// regression in the session's own discipline would show up here rather than be
/// tested around.
struct CompositionNetwork: Sendable {
    let tag: String
    let session: URLSession

    init() {
        let tag = UUID().uuidString
        self.tag = tag
        CompositionURLProtocol.counts.withLock { $0[tag] = 0 }

        let configuration = ReleaseNotesSession.configuration()
        configuration.protocolClasses = [CompositionURLProtocol.self]
        configuration.httpAdditionalHeaders = [CompositionURLProtocol.tagHeader: tag]
        session = URLSession(configuration: configuration)
    }

    var requestCount: Int {
        CompositionURLProtocol.counts.withLock { $0[tag] ?? 0 }
    }
}

/// Counts requests made through one `CompositionNetwork`, and answers them with
/// an empty release list so a load settles rather than hanging.
final class CompositionURLProtocol: URLProtocol {
    static let tagHeader = "X-Cellar-Composition-Recorder"
    static let counts = Mutex<[String: Int]>([:])

    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: tagHeader) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let tag = request.value(forHTTPHeaderField: Self.tagHeader),
              let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/2",
                  headerFields: ["Content-Type": "application/json"]
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        Self.counts.withLock { $0[tag, default: 0] += 1 }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
