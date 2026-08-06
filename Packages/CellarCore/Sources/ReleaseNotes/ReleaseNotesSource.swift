import Foundation

// MARK: - What acquisition returns

/// The validators held for a repository, so a stale entry can be revalidated
/// instead of refetched.
///
/// A named value rather than a bare `String?` because the scarce resource here is
/// **requests per hour**, not bytes: a 304 spends the same one request as a 200
/// and saves only the body. Naming it leaves room for a second validator without
/// changing every call site, and makes "no validator held" a value rather than a
/// `nil` somebody has to interpret.
public struct ConditionalValidators: Sendable, Hashable {
    public let etag: String?

    public init(etag: String?) {
        self.etag = etag
    }
}

/// What one request produced.
public enum ReleaseFetchOutcome: Sendable, Hashable {
    /// The held validator still matches. **Nothing was decoded** — that is the
    /// whole benefit — and the cached answer may be reused with a refreshed
    /// timestamp. The budget is still carried, because a conditional request
    /// still costs one against the hour.
    case notModified(RateLimitStatus)
    case fetched([GitHubRelease], etag: String?, rateLimit: RateLimitStatus)
}

// MARK: - The seam

/// Where published releases come from.
///
/// **Singular by construction.** There is one method, it names one repository,
/// and no array overload, batch form or prefetch exists anywhere in this target.
/// That is not stylistic: a plural entry point is all it would take for somebody
/// to wire release notes into a list render or a bulk upgrade, and thirty
/// requests would leave this Mac because a view appeared. The shape is the guard.
///
/// The `grant` parameter is the other half. `ReleaseNotesGrant` has an internal
/// initialiser, so the only way to call this at all is to have gone through
/// `ReleaseNotesConsent.authorise()` — unconsented egress does not compile.
public protocol ReleaseNotesSource: Sendable {
    func releases(
        for repository: GitHubRepository,
        validators: ConditionalValidators?,
        token: String?,
        grant: ReleaseNotesGrant
    ) async throws(ReleaseNotesFailure) -> ReleaseFetchOutcome
}

// MARK: - The session

/// The one `URLSession` configuration this capability may use.
///
/// Named rather than built inline so the interesting properties — all of them
/// *negative* — are declared in one place. A duplicated negative is a negative
/// that only half survives the next edit.
public enum ReleaseNotesSession {
    /// A fresh configuration. Never reuse one across sessions: `protocolClasses`
    /// and friends are per-instance, and a shared instance is a shared mutation
    /// surface.
    public static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        // Belt: `.ephemeral` still installs an in-memory `URLCache`. A replayed
        // 200 here would present a stale release list as a fresh answer while the
        // conditional-request machinery believed it had revalidated.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Nothing about this request should be able to carry an identity between
        // calls. `.ephemeral` already isolates cookies; removing the store makes
        // the absence explicit and assertable.
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return configuration
    }

    public static func make() -> URLSession {
        URLSession(configuration: configuration())
    }

    /// Two mebibytes. A releases page is kilobytes; anything at this size is a
    /// mistake or an attack, and either way it is not worth receiving.
    public static let payloadByteLimit = 2 * 1_048_576
}

// MARK: - The shipped source

/// The **only** type in this target that owns a `URLSession`.
///
/// A `Sendable` struct rather than an actor: it holds a session and three
/// immutable settings, and there is no state to serialise. Concurrency safety
/// comes from having nothing to mutate.
///
/// ## Why the releases *list* and not the per-tag endpoint
///
/// `/repos/{o}/{r}/releases/tags/{tag}` looks like the obvious choice and is the
/// wrong one, decisively rather than stylistically. It answers **404 for both**
/// "this repository publishes no releases" and "no release matches this version",
/// and those must be different answers. The list endpoint tells them apart from
/// one response — an empty array versus a non-empty array with no matching tag —
/// which is exactly one request either way.
public struct GitHubReleaseNotesSource: ReleaseNotesSource {
    /// The one host this type reaches, compiled in.
    public static let baseURL = "https://api.github.com/"

    /// A judgment, not a decision from the proposal, and recorded as such in
    /// design Open Question 1. It bounds one response and covers the primary
    /// entry point — the newest version of an outdated package — completely. For
    /// an old installed version on a fast-releasing repository the match can fall
    /// off the page; `pageWasFull` keeps that honest, and the fix if it proves
    /// common is a larger page, never a second request.
    public static let defaultPageSize = 30

    private let session: URLSession
    private let baseURL: String
    private let byteLimit: Int
    private let perPage: Int

    public init(
        session: URLSession = ReleaseNotesSession.make(),
        baseURL: String = GitHubReleaseNotesSource.baseURL,
        byteLimit: Int = ReleaseNotesSession.payloadByteLimit,
        perPage: Int = GitHubReleaseNotesSource.defaultPageSize
    ) {
        self.session = session
        self.baseURL = baseURL
        self.byteLimit = byteLimit
        self.perPage = perPage
    }

    // MARK: - One request

    public func releases(
        for repository: GitHubRepository,
        validators: ConditionalValidators?,
        token: String?,
        grant: ReleaseNotesGrant
    ) async throws(ReleaseNotesFailure) -> ReleaseFetchOutcome {
        // Before the request: work that was superseded must cost nothing at all.
        guard Task.isCancelled == false else { throw .cancelled }

        let request = try Self.request(
            baseURL: baseURL,
            repository: repository,
            perPage: perPage,
            validators: validators,
            token: token
        )

        let (http, body) = try await receive(request)
        let rateLimit = RateLimitStatus(headers: Self.headerFields(of: http))

        if http.statusCode == 304 { return .notModified(rateLimit) }
        try Self.classify(status: http.statusCode, rateLimit: rateLimit)

        // Before the decode: a cancelled load must not pay for parsing a body
        // nobody will see.
        guard Task.isCancelled == false else { throw .cancelled }

        do {
            let releases = try await GitHubReleaseDecoder.decode(body)
            return .fetched(releases, etag: http.value(forHTTPHeaderField: "ETag"), rateLimit: rateLimit)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .malformedPayload
        }
    }

    // MARK: - Building it

    /// Built by concatenation from a compiled-in constant and two segments that
    /// `GitHubRepository.init?` has already restricted to `[A-Za-z0-9._-]`, so no
    /// part of the host, path or parameter name comes from unvalidated text and
    /// no percent-encoding step is needed to make it safe.
    private static func request(
        baseURL: String,
        repository: GitHubRepository,
        perPage: Int,
        validators: ConditionalValidators?,
        token: String?
    ) throws(ReleaseNotesFailure) -> URLRequest {
        guard let url = URL(
            string: baseURL + "repos/\(repository.owner)/\(repository.name)/releases"
                + "?per_page=\(perPage)"
        ) else {
            throw .transport
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let etag = validators?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let token {
            // A credential belongs in a header. In the query string it would be
            // recorded verbatim by every proxy and server log on the path.
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: - Receiving it

    /// Streams the response, refusing an oversized one **before** its body is
    /// read.
    ///
    /// `bytes(for:)` rather than `data(for:)` for exactly one reason: it hands
    /// back the response before the body, so a declared `Content-Length` over the
    /// limit costs a header read instead of a full download. The accumulation
    /// loop then bounds what actually arrives, which is the half that still holds
    /// when the declared length lies or is absent.
    ///
    /// This is *not* the catalog's file-based `download(for:)` path. Release
    /// bodies are kilobytes and the 31 MB reasoning behind `CatalogSource`'s file
    /// discipline does not transfer; only the byte-limit guard does, and it is
    /// kept.
    private func receive(
        _ request: URLRequest
    ) async throws(ReleaseNotesFailure) -> (HTTPURLResponse, Data) {
        let stream: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (stream, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transport
        }

        guard let http = response as? HTTPURLResponse else { throw .malformedPayload }

        // Before a single byte is consumed.
        let declared = http.expectedContentLength
        guard declared <= Int64(byteLimit) else { throw .payloadTooLarge }

        var body = Data()
        body.reserveCapacity(declared > 0 ? Int(declared) : 0)
        do {
            for try await byte in stream {
                body.append(byte)
                // And again as it arrives, because a declared length is a claim
                // and this is a fact.
                guard body.count <= byteLimit else { throw ReleaseNotesFailure.payloadTooLarge }
            }
        } catch let failure as ReleaseNotesFailure {
            throw failure
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .transport
        }

        return (http, body)
    }

    // MARK: - Reading the status

    /// Classifies **before** anything is decoded.
    ///
    /// The order is the whole contract. A rate-limit refusal is a short JSON
    /// object, and decoding first would report it as a malformed payload — which
    /// is the same collapse as reporting it as "no releases", one layer down.
    private static func classify(
        status: Int,
        rateLimit: RateLimitStatus
    ) throws(ReleaseNotesFailure) {
        guard (200...299).contains(status) == false else { return }

        // 401 first and unconditionally: a rejected credential carries no
        // rate-limit header at all (the live capture in `Fixtures/GitHub/` proves
        // it), so it must never be reached through an exhaustion check.
        if status == 401 { throw .unauthorized }

        // Exhaustion, not the status code, is what makes this a rate limit. A 403
        // for a private repository carries a full budget and is a different fact.
        if status == 403 || status == 429, rateLimit.isExhausted {
            throw .rateLimited(rateLimit)
        }

        throw .httpStatus(status)
    }

    private static func headerFields(of response: HTTPURLResponse) -> [String: String] {
        var fields: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            guard let name = name as? String, let value = value as? String else { continue }
            fields[name] = value
        }
        return fields
    }
}
