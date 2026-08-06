import Foundation
import ReleaseNotes
import Testing

/// One opened request costs **one** request, and everything it can settle as is a
/// typed value.
///
/// Every assertion below is made below `URLSession`, through a recording
/// `URLProtocol`, because the claims are about what reaches the wire: how many
/// requests, to which path, carrying which headers, under which cache policy.
/// A fake conforming to `ReleaseNotesSource` could satisfy all of them while the
/// shipped type did something else entirely.
///
/// **The page size is never a literal here.** `perPage` is injected and every
/// page-boundary assertion compares against the injected bound, so a future
/// change to the default cannot be papered over by a test that says "thirty".
@Suite("GitHub release-notes source")
struct GitHubReleaseNotesSourceTests {
    // MARK: - Arrangement

    private var repository: GitHubRepository {
        GitHubRepository(owner: "acme", name: "foo")!
    }

    private func grant() throws -> ReleaseNotesGrant {
        try ReleaseNotesConsent.granted(at: Date(timeIntervalSince1970: 1_000_000)).authorise()
    }

    private func source(
        _ network: RecordingNetwork,
        perPage: Int = 30,
        byteLimit: Int = 2 * 1_048_576
    ) -> GitHubReleaseNotesSource {
        GitHubReleaseNotesSource(
            session: network.session,
            byteLimit: byteLimit,
            perPage: perPage
        )
    }

    // MARK: - Exactly one request

    @Test("One call issues exactly one request, to the releases list, at the injected page size")
    func oneCallIssuesExactlyOneRequest() async throws {
        let network = RecordingNetwork(queue: [
            .releases(try Fixture.data("GitHub/releases-git-populated.json"))
        ])
        let perPage = 17

        _ = try await source(network, perPage: perPage).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        #expect(network.requestCount == 1, "the call issued \(network.requestCount) requests")

        let exchange = try #require(network.exchanges.first)
        #expect(exchange.method == "GET")
        #expect(exchange.url.path == "/repos/acme/foo/releases")
        // Against the **injected** bound, never against a literal 30.
        #expect(exchange.url.query == "per_page=\(perPage)")
    }

    /// The page size is a parameter, not a constant of the capability. Three
    /// different bounds, three different requests, and none of them says thirty.
    @Test("The requested page size is exactly the injected bound", arguments: [1, 30, 100])
    func theRequestedPageSizeIsTheInjectedBound(perPage: Int) async throws {
        let network = RecordingNetwork(queue: [.releases(Data("[]".utf8))])

        _ = try await source(network, perPage: perPage).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        let exchange = try #require(network.exchanges.first)
        #expect(exchange.url.query == "per_page=\(perPage)")
    }

    /// The default is a judgment, not a decision from the proposal — recorded as
    /// design Open Question 1. It is asserted here so a change to it is a visible
    /// change rather than a silent one, and nowhere else.
    @Test("The shipped default page size is thirty, and it is the only place that says so")
    func theShippedDefaultPageSizeIsThirty() async throws {
        let network = RecordingNetwork(queue: [.releases(Data("[]".utf8))])

        _ = try await GitHubReleaseNotesSource(session: network.session).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        #expect(try #require(network.exchanges.first).url.query == "per_page=30")
        #expect(GitHubReleaseNotesSource.defaultPageSize == 30)
    }

    @Test("The request reaches the compiled-in host and no other")
    func theRequestReachesTheCompiledInHost() async throws {
        let network = RecordingNetwork(queue: [.releases(Data("[]".utf8))])

        _ = try await source(network).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        let exchange = try #require(network.exchanges.first)
        #expect(exchange.url.host() == "api.github.com")
        #expect(exchange.url.scheme == "https")
        #expect(GitHubReleaseNotesSource.baseURL == "https://api.github.com/")
    }

    // MARK: - No ambient state

    @Test("The session configuration carries no cache, no cookies and a byte limit")
    func theSessionConfigurationCarriesNoAmbientState() {
        let configuration = ReleaseNotesSession.configuration()

        #expect(configuration.urlCache == nil, "the session installed a URL cache")
        #expect(configuration.httpCookieStorage == nil, "the session installed cookie storage")
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(ReleaseNotesSession.payloadByteLimit == 2 * 1_048_576)
    }

    @Test("Every issued request ignores the local cache")
    func everyIssuedRequestIgnoresTheLocalCache() async throws {
        let network = RecordingNetwork(queue: [.releases(Data("[]".utf8))])

        _ = try await source(network).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        #expect(
            try #require(network.exchanges.first).cachePolicy == .reloadIgnoringLocalCacheData
        )
    }

    // MARK: - Conditional requests

    @Test("A held validator is sent as If-None-Match, and an absent one sends no header")
    func aHeldValidatorIsSentAsIfNoneMatch() async throws {
        let withValidator = RecordingNetwork(queue: [.notModified(etag: "\"abc123\"")])
        _ = try await source(withValidator).releases(
            for: repository,
            validators: ConditionalValidators(etag: "\"abc123\""),
            token: nil,
            grant: try grant()
        )
        #expect(
            try #require(withValidator.exchanges.first).headers["If-None-Match"] == "\"abc123\""
        )

        let without = RecordingNetwork(queue: [.releases(Data("[]".utf8))])
        _ = try await source(without).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )
        #expect(
            try #require(without.exchanges.first).headers["If-None-Match"] == nil,
            "a request with no held validator sent a conditional header"
        )
    }

    /// A 304 spends one request and no body. The decode must not run — which is
    /// most of the point of holding the validator at all.
    @Test("A 304 returns notModified, decodes nothing, and still carries the budget")
    func a304ReturnsNotModifiedAndDecodesNothing() async throws {
        let network = RecordingNetwork(queue: [.notModified(etag: "\"abc123\"")])

        let outcome = try await source(network).releases(
            for: repository,
            validators: ConditionalValidators(etag: "\"abc123\""),
            token: nil,
            grant: try grant()
        )

        guard case .notModified(let rateLimit) = outcome else {
            Issue.record("a 304 settled as \(outcome)")
            return
        }
        // The budget is read from the 304 too, because a conditional request
        // still costs one against the hour.
        #expect(rateLimit.remaining == 57)
        #expect(network.requestCount == 1)
    }

    // MARK: - The token

    @Test("A stored token authenticates the request as a bearer credential")
    func aStoredTokenAuthenticatesTheRequest() async throws {
        let network = RecordingNetwork(queue: [.releases(Data("[]".utf8))])

        _ = try await source(network).releases(
            for: repository, validators: nil, token: "ghp_tokenUnderTest", grant: try grant()
        )

        let exchange = try #require(network.exchanges.first)
        #expect(exchange.headers["Authorization"] == "Bearer ghp_tokenUnderTest")
        // In a header, never in the query string, where every proxy and server
        // log on the path would record it verbatim.
        #expect(exchange.url.query?.contains("ghp_") != true)
        #expect(exchange.url.absoluteString.contains("ghp_") == false)
    }

    @Test("No token still issues the request, settles normally, and names no missing token")
    func noTokenStillIssuesTheRequest() async throws {
        let network = RecordingNetwork(queue: [
            .releases(try Fixture.data("GitHub/releases-git-populated.json"))
        ])

        let outcome = try await source(network).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        guard case .fetched(let releases, _, _) = outcome else {
            Issue.record("an unauthenticated request settled as \(outcome)")
            return
        }
        #expect(releases.count == 26)
        #expect(network.requestCount == 1)
        #expect(try #require(network.exchanges.first).headers["Authorization"] == nil)
    }

    /// No credential other than this capability's token is carried. Asserted as a
    /// **whole header set**, so a cookie, a referer or an ambient auth header
    /// added later fails here rather than travelling unnoticed.
    @Test("The request carries no credential or identifier beyond the optional token")
    func theRequestCarriesNoOtherCredential() async throws {
        let network = RecordingNetwork(queue: [.releases(Data("[]".utf8))])

        _ = try await source(network).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        let headers = try #require(network.exchanges.first).headers
        for forbidden in ["Cookie", "Referer", "X-GitHub-Token", "apiKey", "Authorization"] {
            #expect(headers[forbidden] == nil, "the request carried \(forbidden)")
        }
        // Anchored positively: the headers it *does* send are the two it should.
        #expect(headers["Accept"] == "application/vnd.github+json")
        #expect(headers["X-GitHub-Api-Version"] == "2022-11-28")
    }

    // MARK: - The byte limit

    @Test("A body over the byte limit is refused, with nothing decoded")
    func aBodyOverTheByteLimitIsRefused() async throws {
        let oversized = Data(repeating: UInt8(ascii: " "), count: 4_096)
        let network = RecordingNetwork(queue: [.releases(oversized)])

        await #expect(throws: ReleaseNotesFailure.payloadTooLarge) {
            try await source(network, byteLimit: 1_024).releases(
                for: repository, validators: nil, token: nil, grant: try grant()
            )
        }
    }

    /// The declared length is judged **before** a byte of the body is consumed,
    /// so an oversized response costs a header read rather than a full download.
    @Test("A declared content length over the limit refuses before the body is read")
    func aDeclaredContentLengthOverTheLimitRefusesBeforeTheBodyIsRead() async throws {
        let network = RecordingNetwork(queue: [
            .response(
                statusCode: 200,
                headers: [
                    "Content-Type": "application/json",
                    "Content-Length": "9999999"
                ],
                body: Data(repeating: UInt8(ascii: " "), count: 64)
            )
        ])

        await #expect(throws: ReleaseNotesFailure.payloadTooLarge) {
            try await source(network, byteLimit: 1_024).releases(
                for: repository, validators: nil, token: nil, grant: try grant()
            )
        }
    }

    /// The paired positive, so `payloadTooLarge` is a decision about size and not
    /// a value the source always produces.
    @Test("A body under the limit is decoded normally")
    func aBodyUnderTheLimitIsDecodedNormally() async throws {
        let body = try Fixture.data("GitHub/releases-git-populated.json")
        let network = RecordingNetwork(queue: [.releases(body)])

        let outcome = try await source(network, byteLimit: body.count + 1).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        guard case .fetched(let releases, _, _) = outcome else {
            Issue.record("a body under the limit settled as \(outcome)")
            return
        }
        #expect(releases.count == 26)
    }

    // MARK: - Refusals

    /// The refusal this whole capability is shaped around: a 403 with an
    /// exhausted budget is **not** a plain status failure, **not** an absence, and
    /// **not** a retry trigger.
    @Test("A 403 with an exhausted budget is the rate-limit failure carrying its reset time")
    func a403WithAnExhaustedBudgetIsTheRateLimitFailure() async throws {
        let network = RecordingNetwork(queue: [.rateLimited()])

        var caught: ReleaseNotesFailure?
        do {
            _ = try await source(network).releases(
                for: repository, validators: nil, token: nil, grant: try grant()
            )
        } catch {
            caught = error as? ReleaseNotesFailure
        }

        let failure = try #require(caught)
        #expect(failure.isRateLimited)
        #expect(failure != .httpStatus(403))
        let status = try #require(failure.rateLimit)
        #expect(status.resetAt == Date(timeIntervalSince1970: 1_786_055_400))
        #expect(status.remaining == 0)
        // No automatic retry: one refusal, one request.
        #expect(network.requestCount == 1, "the refusal triggered a retry")
    }

    /// `429` is the same condition with a different code, so it settles the same
    /// way.
    @Test("A 429 with an exhausted budget is also the rate-limit failure")
    func a429WithAnExhaustedBudgetIsAlsoTheRateLimitFailure() async throws {
        let network = RecordingNetwork(queue: [
            .response(
                statusCode: 429,
                headers: ["x-ratelimit-limit": "60", "x-ratelimit-remaining": "0",
                          "x-ratelimit-reset": "1786055400"],
                body: Data(#"{"message":"Too many requests"}"#.utf8)
            )
        ])

        var caught: ReleaseNotesFailure?
        do {
            _ = try await source(network).releases(
                for: repository, validators: nil, token: nil, grant: try grant()
            )
        } catch { caught = error as? ReleaseNotesFailure }

        #expect(try #require(caught).isRateLimited)
    }

    /// A 403 with a **full** budget is a different thing entirely — a private or
    /// blocked repository — and must not claim a reset time nobody published.
    @Test("A 403 with a full budget is a plain HTTP status failure, not a rate limit")
    func a403WithAFullBudgetIsAPlainStatusFailure() async throws {
        let network = RecordingNetwork(queue: [
            .response(
                statusCode: 403,
                headers: ["x-ratelimit-limit": "60", "x-ratelimit-remaining": "58"],
                body: Data(#"{"message":"Repository access blocked"}"#.utf8)
            )
        ])

        var caught: ReleaseNotesFailure?
        do {
            _ = try await source(network).releases(
                for: repository, validators: nil, token: nil, grant: try grant()
            )
        } catch { caught = error as? ReleaseNotesFailure }

        #expect(caught == .httpStatus(403))
        #expect(try #require(caught).isRateLimited == false)
        #expect(try #require(caught).rateLimit == nil)
    }

    @Test("A 401 is the rejected-credential failure and claims no reset or budget")
    func a401IsTheRejectedCredentialFailure() async throws {
        let network = RecordingNetwork(queue: [.unauthorized()])

        var caught: ReleaseNotesFailure?
        do {
            _ = try await source(network).releases(
                for: repository, validators: nil, token: "ghp_wrong", grant: try grant()
            )
        } catch { caught = error as? ReleaseNotesFailure }

        #expect(caught == .unauthorized)
        #expect(try #require(caught).isRateLimited == false)
        #expect(try #require(caught).rateLimit == nil)
    }

    @Test(
        "Another non-success status is reported with its code",
        arguments: [404, 418, 500, 503]
    )
    func anotherNonSuccessStatusIsReportedWithItsCode(status: Int) async throws {
        let network = RecordingNetwork(queue: [
            .response(statusCode: status, headers: [:], body: Data("{}".utf8))
        ])

        var caught: ReleaseNotesFailure?
        do {
            _ = try await source(network).releases(
                for: repository, validators: nil, token: nil, grant: try grant()
            )
        } catch { caught = error as? ReleaseNotesFailure }

        #expect(caught == .httpStatus(status))
    }

    @Test("A transport failure is its own reason and never an absence")
    func aTransportFailureIsItsOwnReason() async throws {
        let network = RecordingNetwork(queue: [.transportFailure])

        var caught: ReleaseNotesFailure?
        do {
            _ = try await source(network).releases(
                for: repository, validators: nil, token: nil, grant: try grant()
            )
        } catch { caught = error as? ReleaseNotesFailure }

        #expect(caught == .transport)
        #expect(try #require(caught).isRateLimited == false)
    }

    @Test("A 200 whose body is not a release list is a malformed payload")
    func a200WhoseBodyIsNotAReleaseListIsMalformed() async throws {
        let network = RecordingNetwork(queue: [
            .releases(try Fixture.data("GitHub/error-403-ratelimit.json"))
        ])

        var caught: ReleaseNotesFailure?
        do {
            _ = try await source(network).releases(
                for: repository, validators: nil, token: nil, grant: try grant()
            )
        } catch { caught = error as? ReleaseNotesFailure }

        #expect(caught == .malformedPayload)
    }

    // MARK: - Cancellation

    @Test("A cancelled load settles as the cancelled failure, never as an error dialog")
    func aCancelledLoadSettlesAsCancelled() async throws {
        let network = RecordingNetwork(queue: [.releases(Data("[]".utf8))])
        let shipped = source(network)
        let repository = repository
        let grant = try grant()

        let task = Task {
            // Cancelled before the first check point, so the request is never
            // issued at all.
            try await shipped.releases(
                for: repository, validators: nil, token: nil, grant: grant
            )
        }
        task.cancel()

        var caught: ReleaseNotesFailure?
        do {
            _ = try await task.value
        } catch { caught = error as? ReleaseNotesFailure }

        #expect(caught == .cancelled)
        #expect(network.requestCount == 0, "a cancelled load still issued a request")
    }

    // MARK: - The success path carries the budget

    @Test("A successful fetch carries the ETag and the budget it was answered with")
    func aSuccessfulFetchCarriesTheEtagAndTheBudget() async throws {
        let network = RecordingNetwork(queue: [
            .releases(
                try Fixture.data("GitHub/releases-git-populated.json"),
                etag: "\"deadbeef\"",
                remaining: 41
            )
        ])

        let outcome = try await source(network).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        guard case .fetched(let releases, let etag, let rateLimit) = outcome else {
            Issue.record("a 200 settled as \(outcome)")
            return
        }
        #expect(releases.count == 26)
        #expect(etag == "\"deadbeef\"")
        // Parsed from a **200**, which is the design decision this asserts.
        #expect(rateLimit.remaining == 41)
        #expect(rateLimit.limit == 60)
        #expect(rateLimit.isExhausted == false)
    }

    @Test("An empty page is a successful fetch of nothing, not a failure")
    func anEmptyPageIsASuccessfulFetchOfNothing() async throws {
        let network = RecordingNetwork(queue: [
            .releases(try Fixture.data("GitHub/releases-empty.json"))
        ])

        let outcome = try await source(network).releases(
            for: repository, validators: nil, token: nil, grant: try grant()
        )

        guard case .fetched(let releases, _, _) = outcome else {
            Issue.record("an empty page settled as \(outcome)")
            return
        }
        #expect(releases.isEmpty)
    }
}
