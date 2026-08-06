import Foundation

// MARK: - What acquisition returns

/// One query's answer, together with what the database said about its age.
///
/// A struct rather than a bare `AdvisoryAnswer` because the answer and the
/// timestamp travel to two different places: the answer goes to the matcher, and
/// `newestModified` goes to the cache, where it is the second, independent
/// invalidation the spec requires. Keeping them in one value keeps them keyed to
/// the same query — two parallel arrays would be one off-by-one away from
/// invalidating the wrong entry.
public struct DiscoveredAnswer: Sendable, Hashable {
    public let answer: AdvisoryAnswer
    /// The newest `modified` across the advisories `querybatch` named for this
    /// query, or `nil` when it named none.
    public let newestModified: Date?

    public init(answer: AdvisoryAnswer, newestModified: Date?) {
        self.answer = answer
        self.newestModified = newestModified
    }
}

/// What one discovery request produced.
///
/// `answers` is **positional**: entry *i* answers query *i*. That is OSV's own
/// contract and it is the reason a slot is never dropped — see
/// `OSVWire.querybatch(from:)`.
public struct AdvisoryDiscovery: Sendable, Hashable {
    public let answers: [DiscoveredAnswer]
    public let skippedRecordCount: Int

    public init(answers: [DiscoveredAnswer], skippedRecordCount: Int) {
        self.answers = answers
        self.skippedRecordCount = skippedRecordCount
    }
}

/// What one enrichment request produced.
///
/// Keyed by CVE identifier because that is the only thing enrichment knows
/// about. There is no package identity anywhere in this value, which is the
/// shape of the guarantee that no request ever named one.
public struct AdvisoryEnrichment: Sendable, Hashable {
    public let severities: [String: SeverityTier]
    public let skippedRecordCount: Int

    public init(severities: [String: SeverityTier], skippedRecordCount: Int) {
        self.severities = severities
        self.skippedRecordCount = skippedRecordCount
    }
}

// MARK: - The seams

/// Decides *affectedness*: which advisories apply to which installed packages.
public protocol AdvisoryDiscovering: Sendable {
    func discover(_ queries: [AdvisoryQuery]) async throws(AdvisoryError) -> AdvisoryDiscovery
}

/// Supplies *severity* for identifiers discovery already found.
public protocol AdvisoryEnriching: Sendable {
    func enrich(_ cveIDs: [String]) async throws(AdvisoryError) -> AdvisoryEnrichment
}

/// Both halves of acquisition.
///
/// ## Why this is a composition rather than one protocol
///
/// The design names a single `AdvisorySource` exposing `discover` and `enrich`.
/// The two shipped conformers each implement exactly one of them: OSV decides
/// affectedness, NVD supplies severity, and **neither is a fallback for the
/// other**. A single protocol would force each one to carry a permanently
/// unimplemented half, and every call site would then have to know which methods
/// on the value in its hands actually do anything — a fact the type system would
/// no longer be carrying. Splitting the roles keeps the design's vocabulary,
/// keeps the composed name for anything that genuinely needs both, and makes an
/// engine's dependency on "something that can discover" spellable exactly.
public typealias AdvisorySource = AdvisoryDiscovering & AdvisoryEnriching

// MARK: - The session

/// The one `URLSession` configuration advisory acquisition may use.
///
/// Shared by both sources rather than written twice, because the interesting
/// property is a *negative* one — no cache anywhere — and a duplicated negative
/// is a negative that only half survives the next edit.
public enum AdvisorySession {
    /// A fresh configuration. Never reuse one across sessions: `protocolClasses`
    /// and friends are per-instance, and a shared instance is a shared mutation
    /// surface.
    public static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        // Belt: `.ephemeral` still installs an in-memory `URLCache`. For advisory
        // data a replayed 200 is worse than a failed request — it presents
        // yesterday's "nothing found" as today's answer while the freshness
        // label says `.live`.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    public static func make() -> URLSession {
        URLSession(configuration: configuration())
    }

    // MARK: - Shared request handling

    /// Eight mebibytes. Advisory payloads are small; anything at this size is a
    /// mistake or an attack, and either way it is not worth decoding.
    public static let payloadByteLimit = 8 * 1_048_576

    /// Performs one request and hands back a body that is safe to decode.
    ///
    /// The order here is the whole contract, and it is the U2(c) probe answer
    /// written as code:
    ///
    /// 1. transport failures become `offline` — there is no status to read;
    /// 2. **status is classified before anything is decoded**, because the real
    ///    429 is seventeen bytes of `text/plain` and decoding first would report
    ///    a rate limit as a malformed payload;
    /// 3. the byte count is judged before the decoder runs, so an oversized body
    ///    is `payloadTooLarge` and never a decode failure.
    static func body(
        for request: URLRequest,
        on session: URLSession,
        byteLimit: Int
    ) async throws(AdvisoryError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw .transportFailed
        } catch {
            throw .offline
        }

        guard let http = response as? HTTPURLResponse else { throw .malformedPayload }
        if http.statusCode == 429 { throw .rateLimited }
        guard (200...299).contains(http.statusCode) else { throw .transportFailed }

        let declared = http.expectedContentLength
        guard declared <= Int64(byteLimit), data.count <= byteLimit else {
            throw .payloadTooLarge
        }
        return data
    }
}
