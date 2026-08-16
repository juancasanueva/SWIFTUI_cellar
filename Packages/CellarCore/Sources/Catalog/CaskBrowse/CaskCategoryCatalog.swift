import Foundation

/// One category as the CaskFlow pipeline names it: a display name and an SF
/// Symbol.
public struct CaskCategoryDefinition: Sendable, Hashable {
    public let displayName: String
    public let icon: String

    public init(displayName: String, icon: String) {
        self.displayName = displayName
        self.icon = icon
    }
}

/// Where one cask token belongs: a primary category and any number of
/// secondaries. The pipeline may repeat itself; `uniqueCategoryIDs(for:)` is
/// where the repetition dies.
public struct CaskCategoryMapping: Sendable, Hashable {
    public let primary: String
    public let secondary: [String]

    public init(primary: String, secondary: [String]) {
        self.primary = primary
        self.secondary = secondary
    }
}

/// The vendored CaskHub category catalog: category definitions, the
/// token-to-category mapping, and the manifest of tokens with a CaskFlow icon.
///
/// Gated by an exact schema version **in both directions**, following the
/// `DiscoverySchema` idiom: a file this build cannot read — older *or* newer —
/// is "no data", never an error. The upstream pipeline versions its asset for
/// its own reasons, so the gate carries its own constant rather than borrowing
/// anyone else's.
public struct CaskCategoryCatalog: Sendable, Hashable {
    /// The one version this build reads. Everything else decodes to `nil`.
    public static let schemaVersion = 2

    public let version: Int
    public let generatedDate: String
    public let releaseTag: String?
    public let categories: [String: CaskCategoryDefinition]
    public let tokenToCategory: [String: CaskCategoryMapping]
    /// Tokens with an icon on the CaskFlow icons branch, stamped into the
    /// release asset. The manifest gate for `CaskIconURL.candidateURLs`.
    public let iconTokens: Set<String>

    public init(
        version: Int,
        generatedDate: String,
        releaseTag: String?,
        categories: [String: CaskCategoryDefinition],
        tokenToCategory: [String: CaskCategoryMapping],
        iconTokens: Set<String>
    ) {
        self.version = version
        self.generatedDate = generatedDate
        self.releaseTag = releaseTag
        self.categories = categories
        self.tokenToCategory = tokenToCategory
        self.iconTokens = iconTokens
    }

    /// The categories in presentation order: localized-name ascending, with
    /// "other" forced last regardless of its name (CaskHub's rule — the
    /// catch-all closes the list, never interleaves it).
    public var orderedCategories: [(id: String, definition: CaskCategoryDefinition)] {
        categories
            .sorted { lhs, rhs in
                if lhs.key == "other" { return false }
                if rhs.key == "other" { return true }
                return lhs.value.displayName
                    .localizedCaseInsensitiveCompare(rhs.value.displayName) == .orderedAscending
            }
            .map { (id: $0.key, definition: $0.value) }
    }

    /// A token's categories: primary first, then each secondary, de-duplicated
    /// preserving order. An unmapped token has no categories rather than a
    /// default one.
    public func uniqueCategoryIDs(for token: String) -> [String] {
        guard let mapping = tokenToCategory[token] else { return [] }
        var ids = [mapping.primary]
        for id in mapping.secondary where !ids.contains(id) {
            ids.append(id)
        }
        return ids
    }

    // MARK: - Decoding

    /// Decodes the asset, or `nil` for anything this build cannot read: a
    /// version mismatch and malformed bytes are the same designed outcome.
    ///
    /// `@concurrent` mirroring `CuratedDiscoveryList.decode`: a synchronous
    /// nonisolated call from an actor still runs *on* that actor, and ~400 KB
    /// of JSON belongs off the main one.
    @concurrent
    public static func decode(_ data: Data) async -> Self? {
        guard
            let wire = try? JSONDecoder().decode(Wire.self, from: data),
            wire.version == schemaVersion
        else { return nil }
        return CaskCategoryCatalog(
            version: wire.version,
            generatedDate: wire.generatedDate,
            releaseTag: wire.releaseTag,
            categories: wire.categories.mapValues {
                CaskCategoryDefinition(displayName: $0.displayName, icon: $0.icon)
            },
            tokenToCategory: wire.tokenToCategory.mapValues {
                CaskCategoryMapping(primary: $0.primary, secondary: $0.secondary ?? [])
            },
            iconTokens: Set(wire.iconTokens ?? [])
        )
    }

    /// The catalog shipped in this build's resource bundle, or `nil` when the
    /// resource is missing, unreadable or version-mismatched.
    ///
    /// Two entry points rather than one defaulted parameter: SwiftPM generates
    /// `Bundle.module` as **internal**, and an internal value cannot be the
    /// default argument of a public function.
    public static func shipped() async -> Self? {
        await shipped(from: .module)
    }

    public static func shipped(from bundle: Bundle) async -> Self? {
        guard
            let url = bundle.url(
                forResource: "categories",
                withExtension: "json",
                subdirectory: "CaskBrowseData"
            ),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return await decode(data)
    }

    // MARK: - Wire

    private struct DefinitionWire: Decodable {
        let displayName: String
        let icon: String
    }

    private struct MappingWire: Decodable {
        let primary: String
        let secondary: [String]?
    }

    private struct Wire: Decodable {
        let version: Int
        let generatedDate: String
        let releaseTag: String?
        let categories: [String: DefinitionWire]
        let tokenToCategory: [String: MappingWire]
        /// Absent in pre-2026.07 data.
        let iconTokens: [String]?
    }
}
