import Foundation
import ReleaseNotes
import Testing

/// The rate-limit budget, parsed from **every** response and not only from a
/// refusal.
///
/// The spec requires none of this — it only requires that a 403 carrying an
/// exhausted budget be its own outcome. Parsing from a 200 as well is a design
/// decision, and this suite is why it ships deliberately: the remaining budget is
/// what lets the sheet warn *before* the wall, and the optional token is only
/// worth offering if a user can see why they would want one. A capability that
/// read these headers only on failure could tell you that you had run out and
/// never that you were about to.
@Suite("Rate-limit status")
struct RateLimitStatusTests {
    // MARK: - From a captured 200

    @Test("The budget parses from a captured 200, not only from a refusal")
    func theBudgetParsesFromACaptured200() throws {
        let status = RateLimitStatus(headers: try Fixture.headers(
            "GitHub/releases-git-populated.headers.txt"
        ))

        #expect(status.limit == 60)
        // The live capture recorded a partially-spent unauthenticated budget.
        let remaining = try #require(status.remaining)
        #expect(remaining > 0 && remaining < 60, "the capture recorded \(remaining) remaining")
        #expect(status.isExhausted == false)

        // Epoch seconds became a real instant, not the epoch and not `now`.
        let reset = try #require(status.resetAt)
        #expect(reset > Date(timeIntervalSince1970: 1_700_000_000))
        #expect(reset < Date(timeIntervalSince1970: 1_900_000_000))
    }

    // MARK: - From a captured 403

    @Test("The budget parses from the rate-limited refusal and reports exhaustion")
    func theBudgetParsesFromTheRateLimitedRefusal() throws {
        let status = RateLimitStatus(headers: try Fixture.headers(
            "GitHub/error-403-ratelimit.headers.txt"
        ))

        #expect(status.limit == 60)
        #expect(status.remaining == 0)
        #expect(status.isExhausted)

        let reset = try #require(status.resetAt)
        #expect(reset == Date(timeIntervalSince1970: 1_786_055_400))
    }

    // MARK: - Absence is absence, never zero

    /// The bug this test exists to prevent: `Int(header ?? "") ?? 0` reads a
    /// **missing** `x-ratelimit-remaining` as an exhausted budget, so every
    /// response from a host that does not publish the header would look like a
    /// rate limit. The live 401 capture proves that shape is real — a rejected
    /// credential carries no rate-limit header at all.
    @Test("A response with no rate-limit headers yields nil fields, never zero")
    func aResponseWithNoRateLimitHeadersYieldsNilFields() throws {
        let status = RateLimitStatus(headers: try Fixture.headers(
            "GitHub/error-401-unauthorized.headers.txt"
        ))

        #expect(status.limit == nil)
        #expect(status.remaining == nil)
        #expect(status.resetAt == nil)
        // And therefore it is **not** exhausted. A rejected token must never read
        // as a rate limit.
        #expect(status.isExhausted == false)
        #expect(status.isEmpty)
    }

    @Test("An empty header set yields an empty status rather than a zero budget")
    func anEmptyHeaderSetYieldsAnEmptyStatus() {
        let status = RateLimitStatus(headers: [:])

        #expect(status.limit == nil)
        #expect(status.remaining == nil)
        #expect(status.resetAt == nil)
        #expect(status.isExhausted == false)
        #expect(status.isEmpty)
    }

    @Test(
        "A malformed header value is absent, not zero",
        arguments: ["", " ", "unknown", "-", "60,000", "1.5e3"]
    )
    func aMalformedHeaderValueIsAbsentNotZero(raw: String) {
        let status = RateLimitStatus(headers: [
            "x-ratelimit-limit": raw,
            "x-ratelimit-remaining": raw,
            "x-ratelimit-reset": raw
        ])

        #expect(status.limit == nil, "\(raw) parsed as a limit")
        #expect(status.remaining == nil, "\(raw) parsed as a remaining count")
        #expect(status.resetAt == nil, "\(raw) parsed as a reset time")
        #expect(status.isExhausted == false)
    }

    // MARK: - Exhaustion

    /// `isExhausted` is `remaining == 0` and nothing else — not "remaining is
    /// missing", not "the status was 403". A 403 for a private repository carries
    /// a full budget and is not a rate limit.
    @Test(
        "Exhaustion is exactly a remaining count of zero",
        arguments: [(0, true), (1, false), (59, false)]
    )
    func exhaustionIsExactlyARemainingCountOfZero(remaining: Int, exhausted: Bool) {
        let status = RateLimitStatus(limit: 60, remaining: remaining, resetAt: nil)

        #expect(status.isExhausted == exhausted)
    }

    @Test("A 403 carrying a full budget is not exhausted")
    func a403CarryingAFullBudgetIsNotExhausted() {
        let status = RateLimitStatus(headers: [
            "x-ratelimit-limit": "60",
            "x-ratelimit-remaining": "58",
            "x-ratelimit-reset": "1786055400"
        ])

        #expect(status.isExhausted == false)
        #expect(status.remaining == 58)
    }

    // MARK: - Header name handling

    /// HTTP/2 delivers header names lowercased and HTTP/1.1 does not, and
    /// `HTTPURLResponse` preserves whatever arrived. Depending on one casing
    /// would make the budget invisible over the other protocol.
    @Test("Header names are read case-insensitively")
    func headerNamesAreReadCaseInsensitively() {
        let status = RateLimitStatus(headers: [
            "X-RateLimit-Limit": "5000",
            "X-Ratelimit-Remaining": "4999",
            "x-RATELIMIT-reset": "1786055400"
        ])

        #expect(status.limit == 5_000)
        #expect(status.remaining == 4_999)
        #expect(status.resetAt == Date(timeIntervalSince1970: 1_786_055_400))
    }

    @Test("Surrounding whitespace in a header value is tolerated")
    func surroundingWhitespaceIsTolerated() {
        let status = RateLimitStatus(headers: ["x-ratelimit-remaining": "  7  "])

        #expect(status.remaining == 7)
    }

    // MARK: - Value semantics

    @Test("A status round-trips through Codable")
    func aStatusRoundTripsThroughCodable() throws {
        let status = RateLimitStatus(
            limit: 60, remaining: 0, resetAt: Date(timeIntervalSince1970: 1_786_055_400)
        )

        let decoded = try JSONDecoder().decode(
            RateLimitStatus.self,
            from: JSONEncoder().encode(status)
        )

        #expect(decoded == status)
        #expect(decoded.isExhausted)
    }
}
