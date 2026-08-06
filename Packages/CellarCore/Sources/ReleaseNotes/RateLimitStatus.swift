import Foundation

/// What GitHub said about the request budget, read from **every** response.
///
/// ## Why this is parsed on success too
///
/// The requirement only cares about the refusal: a 403 with an exhausted budget
/// must be its own outcome. Reading the headers on a 200 as well is a design
/// decision and it buys two things the refusal cannot. The sheet can warn
/// *before* the wall — "4 of 60 requests left this hour" is actionable, "you have
/// been rate-limited" is a wall you already hit — and the optional token is only
/// worth offering to somebody who can see why they would want one.
///
/// ## Why every field is optional
///
/// Because absence and zero are different facts, and conflating them is the one
/// bug this type exists to prevent. `Int(header ?? "") ?? 0` reads a **missing**
/// `x-ratelimit-remaining` as an exhausted budget, which would report every
/// response from a path that does not publish the header as a rate limit. The
/// live 401 capture in `Fixtures/GitHub/` proves that shape is real: a rejected
/// credential carries no rate-limit header at all.
public struct RateLimitStatus: Sendable, Hashable, Codable {
    /// The published ceiling: 60 unauthenticated, 5,000 with a token.
    public let limit: Int?
    public let remaining: Int?
    /// When the window resets, decoded from epoch seconds.
    public let resetAt: Date?

    public init(limit: Int?, remaining: Int?, resetAt: Date?) {
        self.limit = limit
        self.remaining = remaining
        self.resetAt = resetAt
    }

    /// Exactly a remaining count of zero, and nothing else.
    ///
    /// Not "remaining is missing" and not "the status was 403": GitHub answers
    /// 403 for a private repository too, with a full budget, and that is not a
    /// rate limit.
    public var isExhausted: Bool { remaining == 0 }

    /// Whether the response said anything about the budget at all.
    public var isEmpty: Bool { limit == nil && remaining == nil && resetAt == nil }

    // MARK: - The header parse

    /// Reads the three published headers, case-insensitively.
    ///
    /// HTTP/2 delivers header names lowercased and HTTP/1.1 does not, and
    /// `HTTPURLResponse` preserves whatever arrived; depending on one casing
    /// would make the budget invisible over the other protocol.
    ///
    /// A value that is not a whole number is treated as **absent**, not as zero,
    /// for the reason above.
    public init(headers: [String: String]) {
        let normalized = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        func number(_ name: String) -> Int? {
            guard let raw = normalized[name]?.trimmingCharacters(in: .whitespaces),
                  raw.isEmpty == false
            else { return nil }
            return Int(raw)
        }

        limit = number("x-ratelimit-limit")
        remaining = number("x-ratelimit-remaining")
        resetAt = number("x-ratelimit-reset").map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// The status of a response that said nothing about the budget.
    public static let unknown = RateLimitStatus(limit: nil, remaining: nil, resetAt: nil)
}
