import Foundation

/// The vendored CaskHub added-dates asset: when each cask token first appeared
/// in Homebrew, as mined by the CaskFlow pipeline.
///
/// Timestamps stay **strings** on purpose. They are ISO8601, so lexicographic
/// order *is* chronological order, and every consumer — the recency window,
/// the newest-first sort — compares strings exactly as CaskHub does. Parsing
/// them would buy nothing and open a formatting seam that could disagree with
/// the comparisons.
public struct CaskAddedDates: Sendable, Hashable {
    /// The one version this build reads. Everything else decodes to `nil` —
    /// the same exact-both-directions gate as `CaskCategoryCatalog`.
    public static let schemaVersion = 1

    public let version: Int
    public let generatedDate: String
    /// Token to ISO8601 timestamp of its first appearance upstream.
    public let tokenAddedDates: [String: String]

    public init(version: Int, generatedDate: String, tokenAddedDates: [String: String]) {
        self.version = version
        self.generatedDate = generatedDate
        self.tokenAddedDates = tokenAddedDates
    }

    // MARK: - Decoding

    /// Decodes the asset, or `nil` for anything this build cannot read: a
    /// version mismatch and malformed bytes are the same designed outcome.
    @concurrent
    public static func decode(_ data: Data) async -> Self? {
        guard
            let wire = try? JSONDecoder().decode(Wire.self, from: data),
            wire.version == schemaVersion
        else { return nil }
        return CaskAddedDates(
            version: wire.version,
            generatedDate: wire.generatedDate,
            tokenAddedDates: wire.tokenAddedDates
        )
    }

    /// The dates shipped in this build's resource bundle, or `nil` when the
    /// resource is missing, unreadable or version-mismatched.
    public static func shipped() async -> Self? {
        await shipped(from: .module)
    }

    public static func shipped(from bundle: Bundle) async -> Self? {
        guard
            let url = bundle.url(
                forResource: "added_dates",
                withExtension: "json",
                subdirectory: "CaskBrowseData"
            ),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return await decode(data)
    }

    // MARK: - Wire

    private struct Wire: Decodable {
        let version: Int
        let generatedDate: String
        let tokenAddedDates: [String: String]
    }
}
