import Foundation

/// One published GitHub release, projected to the fields a release note needs.
///
/// `Decodable` is the load-bearing conformance — nothing in this capability
/// *encodes* a release to send anywhere. `Encodable` comes along because the
/// cache persists a matched outcome, and a matched outcome carries the release it
/// matched.
///
/// The seven fields are the whole projection. A real response carries the
/// `assets` array, the `author` and `uploader` objects and a dozen `*_url`
/// fields; none of them is read, so none of them is modelled, which is also why
/// the captured fixtures ship as a projection rather than as two megabytes of
/// JSON (see `Fixtures/GitHub/README.md`).
public struct GitHubRelease: Sendable, Hashable, Codable {
    /// The upstream tag. The only field a release cannot be without: matching is
    /// a comparison against this, and a release with no tag cannot be matched.
    public let tagName: String
    /// GitHub allows both to be `null` for a release created from a bare tag.
    public let name: String?
    public let body: String?
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let publishedAt: Date?
    public let htmlURL: URL?

    public init(
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        isDraft: Bool = false,
        isPrerelease: Bool = false,
        publishedAt: Date? = nil,
        htmlURL: URL? = nil
    ) {
        self.tagName = tagName
        self.name = name
        self.body = body
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.publishedAt = publishedAt
        self.htmlURL = htmlURL
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case isDraft = "draft"
        case isPrerelease = "prerelease"
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }
}

/// Turns a captured or received body into releases, off the main actor.
///
/// `@concurrent` goes on its **own line, before `public static func`**. The other
/// order does not compile, and getting it wrong cost an apply cycle in M1 — which
/// is why it is written down here rather than remembered.
public enum GitHubReleaseDecoder {
    @concurrent
    public static func decode(_ data: Data) async throws -> [GitHubRelease] {
        let decoder = JSONDecoder()
        // GitHub publishes RFC 3339 with a `Z` offset. Named rather than
        // hand-parsed, so a malformed timestamp costs its own release through the
        // tolerant array below instead of being silently read as the epoch.
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LossyReleaseArray.self, from: data).releases
    }
}

/// An array decode that survives individual bad elements.
///
/// The `LossyArray` discipline the catalog already applies to ~16,000 published
/// records, for the same reason: releases are written by many hands over many
/// years, and one whose shape drifted must cost that release and nothing else.
///
/// What it deliberately does **not** survive is a payload that is not an array.
/// GitHub answers every error with a JSON *object*, and decoding that leniently
/// to `[]` would report a rate-limit refusal as "this repository publishes no
/// releases" — the exact collapse this capability exists to prevent.
private struct LossyReleaseArray: Decodable {
    let releases: [GitHubRelease]
    let skippedCount: Int

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var releases: [GitHubRelease] = []
        if let count = container.count { releases.reserveCapacity(count) }
        var skipped = 0

        while !container.isAtEnd {
            do {
                releases.append(try container.decode(GitHubRelease.self))
            } catch {
                // The container must still advance past the bad element or the
                // loop never terminates. `Skip` accepts any JSON value.
                _ = try? container.decode(Skip.self)
                skipped += 1
            }
        }

        self.releases = releases
        skippedCount = skipped
    }

    /// Consumes exactly one JSON value of any shape and keeps nothing.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {
            _ = try decoder.singleValueContainer()
        }
    }
}
