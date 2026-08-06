import Foundation

/// One hand-picked recommendation.
///
/// `blurb` says *why you might want this*, in Cellar's voice. It is deliberately
/// **not** the package's own `desc`: that text is Homebrew's, it is written to
/// identify rather than to recommend, and republishing it as our
/// recommendation would be putting our name on someone else's words (D1).
public struct CuratedEntry: Sendable, Hashable {
    public let kind: PackageKind
    /// The token Homebrew installs by, resolved against the snapshot as
    /// `(kind, name)`.
    public let token: String
    public let blurb: String

    public init(kind: PackageKind, token: String, blurb: String) {
        self.kind = kind
        self.token = token
        self.blurb = blurb
    }
}

/// A named group of recommendations, in the order the resource declared it.
public struct CuratedCategory: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let entries: [CuratedEntry]

    public init(id: String, title: String, entries: [CuratedEntry]) {
        self.id = id
        self.title = title
        self.entries = entries
    }
}

/// Why the shipped curated resource could not be read at all.
///
/// Distinct from an unreadable *entry*, which is skipped and counted rather than
/// thrown: this is the file itself being absent from the bundle, which is a
/// build-configuration failure and not something to degrade around silently.
public enum CuratedDiscoveryError: Error, Sendable, Hashable {
    case resourceMissing
}

/// The curated list as shipped, after tolerant decoding.
///
/// Tolerant in the same sense the catalog decoder is: keys this build does not
/// model are discarded rather than failing, and one unusable entry never costs
/// the file. Every entry the file published but this build cannot expose is
/// **counted**, so a shipping mistake shows up as a number rather than as a
/// quietly shorter list (package-discovery PD-R3).
public struct CuratedDiscoveryList: Sendable, Hashable {
    public let categories: [CuratedCategory]
    /// Entries the resource published that could not be exposed: a missing kind,
    /// token or blurb, a blank blurb, a kind Homebrew does not have, or a token
    /// already claimed by an earlier category.
    ///
    /// This is a **shipping bug** — a defect in the file this repository ships —
    /// and is kept strictly apart from `unresolvedEntryCount`, which is ordinary
    /// catalog drift nobody did wrong.
    public let skippedRecordCount: Int

    public init(categories: [CuratedCategory], skippedRecordCount: Int) {
        self.categories = categories
        self.skippedRecordCount = skippedRecordCount
    }

    public static let empty = CuratedDiscoveryList(categories: [], skippedRecordCount: 0)

    /// Decodes the resource, skipping and counting what it cannot expose.
    ///
    /// `@concurrent` rather than a plain `nonisolated func`, mirroring
    /// `CatalogDecoder.decode` (M1 D2): a synchronous nonisolated call from an
    /// actor still runs *on* that actor, and the projection this feeds is built
    /// off the main actor.
    @concurrent
    public static func decode(_ data: Data) async throws -> Self {
        project(try JSONDecoder().decode(ListWire.self, from: data))
    }

    /// The list shipped in this build's resource bundle.
    ///
    /// The accessor the app itself uses, so a test that calls it proves the
    /// SwiftPM resource bundle really reached the built product rather than only
    /// the test bundle.
    ///
    /// Two entry points rather than one defaulted parameter: SwiftPM generates
    /// `Bundle.module` as **internal**, and an internal value cannot be the
    /// default argument of a public function. The default therefore lives in a
    /// body, which is the only place this module may name it.
    public static func shipped() async throws -> Self {
        try await shipped(from: .module)
    }

    public static func shipped(from bundle: Bundle) async throws -> Self {
        guard
            let url = bundle.url(
                forResource: "curated-discovery",
                withExtension: "json",
                subdirectory: "Discovery"
            )
        else { throw CuratedDiscoveryError.resourceMissing }
        return try await decode(try Data(contentsOf: url))
    }

    // MARK: - Projection

    private static func project(_ wire: ListWire) -> Self {
        var categories: [CuratedCategory] = []
        var skipped = 0
        // A token belongs to one category — the first that declared it. Keyed by
        // `PackageID` and not by name, because the same token in the two
        // namespaces is two different packages.
        var claimed: Set<PackageID> = []

        for declared in wire.categories ?? [] {
            guard let category = declared.element else {
                skipped += 1
                continue
            }
            guard
                let id = nonEmpty(category.id),
                let title = nonEmpty(category.title)
            else {
                // The entries were readable but there is nowhere to put them.
                skipped += category.entries?.count ?? 1
                continue
            }

            var entries: [CuratedEntry] = []
            for declaredEntry in category.entries ?? [] {
                guard let entry = resolve(declaredEntry, claiming: &claimed) else {
                    skipped += 1
                    continue
                }
                entries.append(entry)
            }
            // Declared order, never re-sorted (PD-R3). An empty category is left
            // in place here and dropped at resolution, which is where PD-R4 puts
            // the rule.
            categories.append(CuratedCategory(id: id, title: title, entries: entries))
        }

        return CuratedDiscoveryList(categories: categories, skippedRecordCount: skipped)
    }

    /// One entry, or `nil` when it cannot be exposed.
    ///
    /// Every branch skips. Nothing here substitutes a value for a missing one —
    /// an entry missing any of kind, token or blurb is not a renderable
    /// recommendation, and inventing the third field would be publishing a
    /// recommendation nobody wrote.
    private static func resolve(
        _ declared: Tolerant<EntryWire>,
        claiming claimed: inout Set<PackageID>
    ) -> CuratedEntry? {
        guard
            let entry = declared.element,
            let token = nonEmpty(entry.token),
            let blurb = nonEmpty(entry.blurb),
            let declaredKind = entry.kind,
            let kind = PackageKind(rawValue: declaredKind)
        else { return nil }

        // First declaration wins; each later one is counted by the caller.
        guard claimed.insert(PackageID(kind: kind, name: token)).inserted else { return nil }
        return CuratedEntry(kind: kind, token: token, blurb: blurb)
    }

    /// A published empty or whitespace-only string is the file publishing
    /// nothing, and absence is what the projection promises for it.
    private static func nonEmpty(_ string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Resolution against the adopted snapshot

/// A curated entry that really is in the catalog, carrying the record it names.
public struct ResolvedCuratedEntry: Sendable, Hashable, Identifiable {
    public var id: PackageID { package.id }

    public let package: CatalogPackage
    /// The resource's words. A view may render `package.desc` beside this, never
    /// as a substitute for it.
    public let blurb: String

    public init(package: CatalogPackage, blurb: String) {
        self.package = package
        self.blurb = blurb
    }
}

/// A category with at least one resolvable entry. An empty one never exists:
/// resolution drops it rather than exposing a heading with nothing under it.
public struct ResolvedCuratedCategory: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let entries: [ResolvedCuratedEntry]

    public init(id: String, title: String, entries: [ResolvedCuratedEntry]) {
        self.id = id
        self.title = title
        self.entries = entries
    }
}

/// The curated list as Discover can actually render it.
public struct ResolvedCuratedList: Sendable, Hashable {
    public let categories: [ResolvedCuratedCategory]
    /// Carried through from decoding: malformed entries in the shipped file.
    public let skippedRecordCount: Int
    /// Valid entries naming a package the adopted snapshot does not contain.
    ///
    /// A different fact with a different owner from `skippedRecordCount`: this
    /// one is ordinary catalog drift — a token renamed or removed upstream —
    /// and nobody did anything wrong. `0` rather than absent when everything
    /// resolved, so "all good" is distinguishable from "nobody looked".
    public let unresolvedEntryCount: Int

    public init(
        categories: [ResolvedCuratedCategory],
        skippedRecordCount: Int,
        unresolvedEntryCount: Int
    ) {
        self.categories = categories
        self.skippedRecordCount = skippedRecordCount
        self.unresolvedEntryCount = unresolvedEntryCount
    }

    public static let empty = ResolvedCuratedList(
        categories: [],
        skippedRecordCount: 0,
        unresolvedEntryCount: 0
    )
}

extension CuratedDiscoveryList {
    /// Resolves every entry by `(kind, name)` against the adopted snapshot.
    ///
    /// An entry whose token is not in the snapshot is dropped and counted — it
    /// must never reach a view, because a row a user cannot install is worse
    /// than no row (package-discovery PD-R4).
    public nonisolated func resolved(against packages: [CatalogPackage]) -> ResolvedCuratedList {
        var byID: [PackageID: CatalogPackage] = [:]
        byID.reserveCapacity(packages.count)
        for package in packages { byID[package.id] = package }

        var resolvedCategories: [ResolvedCuratedCategory] = []
        var unresolved = 0

        for category in categories {
            var entries: [ResolvedCuratedEntry] = []
            for entry in category.entries {
                guard let package = byID[PackageID(kind: entry.kind, name: entry.token)] else {
                    unresolved += 1
                    continue
                }
                entries.append(ResolvedCuratedEntry(package: package, blurb: entry.blurb))
            }
            // A category every one of whose tokens went missing is gone, not
            // empty: an empty heading is a dead row with extra steps.
            guard !entries.isEmpty else { continue }
            resolvedCategories.append(
                ResolvedCuratedCategory(id: category.id, title: category.title, entries: entries)
            )
        }

        return ResolvedCuratedList(
            categories: resolvedCategories,
            skippedRecordCount: skippedRecordCount,
            unresolvedEntryCount: unresolved
        )
    }
}

// MARK: - Wire

/// An element that never fails its container.
///
/// The tolerance seam: decoding an array of these always advances, so one
/// unusable element is `nil` here instead of an error that costs every sibling.
private struct Tolerant<Element: Decodable>: Decodable {
    let element: Element?

    init(from decoder: any Decoder) throws {
        element = try? Element(from: decoder)
    }
}

/// Every field optional on purpose: validation belongs in the projection, where
/// a rejection can be *counted*, rather than in the decoder, where it would only
/// throw.
private struct EntryWire: Decodable {
    let kind: String?
    let token: String?
    let blurb: String?
}

private struct CategoryWire: Decodable {
    let id: String?
    let title: String?
    let entries: [Tolerant<EntryWire>]?
}

private struct ListWire: Decodable {
    let categories: [Tolerant<CategoryWire>]?
}
