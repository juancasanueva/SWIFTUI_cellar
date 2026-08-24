import Catalog

/// The three classes a name-only record can match, strongest first.
///
/// `PackageSearchIndex`'s first three classes, re-expressed here. There is no
/// fourth: the fourth needs a description, and a not-installed tap package has
/// none — obtaining one would need the tap-source read `tap-management` TM5
/// forbids (design DD-3).
public enum TapMatchRank: Int, Comparable, Sendable, CaseIterable {
    case exactToken = 0
    case namePrefix
    case nameSubstring

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One package published by an installed third-party tap, matched against a
/// query (`package-search` PS8).
///
/// It carries five facts and its copy, and nothing else. No description, no
/// version, no homepage, no licence, no dependency list, no install count, no
/// deprecation or disabled flag and no size is *representable*, because the tap
/// inventory publishes none of them.
public struct TapSearchHit: Sendable, Hashable, Identifiable {
    /// Row identity — deliberately **not** a `PackageID` (DD-2).
    ///
    /// `TapPackage.id` lives in the same identity space the catalog uses, so two
    /// rows can share one `PackageID`. A structured id cannot be accidentally
    /// compared against, passed to, or matched with a `PackageID`, and the tap
    /// of origin is what keeps two taps publishing one name separately
    /// addressable.
    public struct RowID: Sendable, Hashable {
        public let tapName: String
        public let kind: PackageKind
        public let name: String

        public init(tapName: String, kind: PackageKind, name: String) {
            self.tapName = tapName
            self.kind = kind
            self.name = name
        }
    }

    public let id: RowID
    /// The bare token argv names. `package-mutation` PM10: never `/`-qualified,
    /// not even for a hit whose token the catalog also carries.
    public let mutationTarget: PackageID
    /// The qualified name the tap declares, for display and for matching. Never
    /// argv.
    public let publishedName: String
    public let displayName: String
    public let tapName: String
    public let state: TapPackageInstallState
    /// PS8: the copy is supplied here and never composed by the presenting
    /// surface. Deliberately **not** `TapPackage.statusExplanation`, which is
    /// `nil` for the installed state and would leave an installed row silent.
    public let stateCopy: String
    /// A catalog record carries this bare token, so Homebrew resolves the
    /// install there. Surfaced, never suppressed.
    public let alsoInCatalog: Bool
    /// PS8: non-nil exactly when `alsoInCatalog`.
    public let collisionNote: String?
    public let rank: TapMatchRank
    /// The identity this row may hand to a selection, or `nil` when it must not
    /// be selectable: not installed, `alsoInCatalog`, or another emitted hit
    /// carries the same `PackageID` (DD-4).
    public let routableID: PackageID?

    /// Hashed on the row identity alone.
    ///
    /// `RowID` is unique among the hits one composition emits, so this is a
    /// faithful hash — and writing it by hand is what lets `state` stay the
    /// shipped `Equatable`-only `TapPackageInstallState` rather than dragging a
    /// conformance onto a type this change does not otherwise touch.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Packages published by installed third-party taps, composed **above** the
/// search index and never pushed into it (PS8, `package-detail` PD6, TM5).
///
/// Pure, `nonisolated` by the package's default, and `Sendable` by composition.
/// Its whole input surface is two already-resident inventories, a query, a kind
/// set, a `Bool` and a catalog-membership predicate — so there is no process
/// launcher, no store and no refresh handle to inject even in principle, and
/// composing the source costs no brew invocation.
public struct TapPackageSearch: Sendable {
    public let inventory: TapInventory
    public let installed: InstalledInventory

    public init(inventory: TapInventory, installed: InstalledInventory) {
        self.inventory = inventory
        self.installed = installed
    }

    // MARK: - The copy this surface shows (PS8)

    /// Every user-visible string on this surface originates here, so a second
    /// presenting surface cannot word the same fact differently. `private`
    /// rather than `public`: the view renders `stateCopy` and `collisionNote`,
    /// it does not reach for the constants behind them.
    private static let installedCopy = "Installed."
    private static let withheldCopy =
        "Installed. Homebrew withholds its tap while this tap is untrusted."
    private static let notInstalledCopy = "Not installed."
    private static let collisionCopy =
        "Also in the catalog. Homebrew installs the catalog package."

    // MARK: - Composition

    /// The matching hits, ordered by `(rank, bare token, kind, tap name)`.
    ///
    /// `isInCatalog` is a **parameter, never a stored property**: storing the
    /// closure would make `Hashable` unrepresentable on the hit and would draw
    /// `Catalog` into this type's own state. It answers the collision fact
    /// alone and never contributes a hit's content (DD-1, PD6).
    public func hits(
        query: String,
        kinds: Set<PackageKind>,
        hideInstalled: Bool,
        isInCatalog: (PackageID) -> Bool
    ) -> [TapSearchHit] {
        let needle = PackageText.normalize(query)
        guard needle.isEmpty == false else { return [] }

        var matches: [Match] = []
        for tap in TapProjection(inventory: inventory).thirdPartyTaps {
            for package in TapProjection.packages(for: tap, installed: installed) {
                guard kinds.contains(package.id.kind) else { continue }
                guard hideInstalled == false || package.isInstalled == false else { continue }
                let name = PackageText.normalize(package.displayName)
                guard
                    let rank = Self.classify(
                        name: name,
                        published: package.publishedName,
                        needle: needle
                    )
                else { continue }
                matches.append(
                    Match(package: package, tapName: tap.name, rank: rank, normalizedName: name)
                )
            }
        }
        matches.sort(by: Self.precedes)

        // Identity ambiguity is a property of the **emitted set**, so it is
        // counted once over the survivors rather than re-derived per row.
        var occurrences: [PackageID: Int] = [:]
        for match in matches { occurrences[match.package.id, default: 0] += 1 }

        return matches.map { match in
            let collides = isInCatalog(match.package.id)
            let unique = occurrences[match.package.id] == 1
            let routable = match.package.isInstalled && collides == false && unique
            return TapSearchHit(
                id: TapSearchHit.RowID(
                    tapName: match.tapName,
                    kind: match.package.id.kind,
                    name: match.package.id.name
                ),
                mutationTarget: match.package.id,
                publishedName: match.package.publishedName,
                displayName: match.package.displayName,
                tapName: match.tapName,
                state: match.package.state,
                stateCopy: Self.copy(for: match.package.state),
                alsoInCatalog: collides,
                collisionNote: collides ? Self.collisionCopy : nil,
                rank: match.rank,
                routableID: routable ? match.package.id : nil
            )
        }
    }

    /// The four absence rules, in one pure place (DD-6).
    ///
    /// `outdatedOnly` reaches **this** function and never `hits(_:)`: a tap hit
    /// carries no version, so filtering by outdatedness would emit zero hits and
    /// read as the false claim "your taps have nothing" rather than as "this
    /// chip does not apply here". An unavailable inventory is an **absence**,
    /// never an error and never a banner.
    public static func isSectionVisible(
        query: String,
        outdatedOnly: Bool,
        tapState: TapLoadState
    ) -> Bool {
        guard outdatedOnly == false else { return false }
        // Emptiness is judged on the **normalised** query, so a whitespace-only
        // query behaves exactly as an empty one does.
        guard PackageText.normalize(query).isEmpty == false else { return false }
        switch tapState {
        case .idle, .loading, .loaded: return true
        case .brewAbsent, .failed: return false
        }
    }

    // MARK: - Matching

    private struct Match {
        let package: TapPackage
        let tapName: String
        let rank: TapMatchRank
        let normalizedName: [UInt8]
    }

    /// The strongest class this package matches, or `nil` for no match.
    ///
    /// The bare token is tried first and answers alone when it matches at all. A
    /// hit found **only** through the published qualified name is capped at
    /// `nameSubstring`, because that name carries the tap's own owner and repo:
    /// promoting it would put every package of a matching tap above a package
    /// whose own token begins with the query (DD-3).
    private static func classify(
        name: [UInt8],
        published: String,
        needle: [UInt8]
    ) -> TapMatchRank? {
        if let rank = rank(of: name, needle: needle) { return rank }
        let qualified = PackageText.normalize(published)
        return rank(of: qualified, needle: needle) == nil ? nil : .nameSubstring
    }

    private static func rank(of haystack: [UInt8], needle: [UInt8]) -> TapMatchRank? {
        if haystack == needle || hasToken(haystack, needle) { return .exactToken }
        if hasPrefix(haystack, needle) || hasTokenPrefix(haystack, needle) { return .namePrefix }
        return contains(haystack, needle) ? .nameSubstring : nil
    }

    private static func copy(for state: TapPackageInstallState) -> String {
        switch state {
        case .installed: installedCopy
        case .installedTapWithheld: withheldCopy
        case .notInstalled: notInstalledCopy
        }
    }

    // MARK: - Order

    /// `(rank asc, normalised bare token asc, formula before cask, tap name asc)`.
    ///
    /// Total by construction. The fourth key is what makes it so: without the
    /// tap name, two taps publishing the same token and kind compare equal and
    /// can swap between refreshes.
    private static func precedes(_ lhs: Match, _ rhs: Match) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        if lhs.normalizedName != rhs.normalizedName {
            return lhs.normalizedName.lexicographicallyPrecedes(rhs.normalizedName)
        }
        if lhs.package.id.kind != rhs.package.id.kind { return lhs.package.id.kind == .formula }
        return lhs.tapName < rhs.tapName
    }

    // MARK: - Byte scans

    /// The normalisation's own separator: every non-alphanumeric run collapses
    /// to exactly one of these.
    private static let separator: UInt8 = 0x20

    private static func hasPrefix(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        haystack.count >= needle.count && matches(haystack, needle, at: 0)
    }

    /// Whether one whole space-delimited token of `haystack` equals `needle`.
    ///
    /// Load-bearing rather than decorative: the shared normalisation makes `-` a
    /// separator, so `gentle-ai` is the two tokens `gentle ai` and `ai` has to
    /// match it exactly rather than as a substring.
    private static func hasToken(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        forEachTokenStart(haystack) { start in
            let end = start + needle.count
            guard end <= haystack.count, end == haystack.count || haystack[end] == separator else {
                return false
            }
            return matches(haystack, needle, at: start)
        }
    }

    private static func hasTokenPrefix(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        forEachTokenStart(haystack) { start in
            start + needle.count <= haystack.count && matches(haystack, needle, at: start)
        }
    }

    private static func forEachTokenStart(_ haystack: [UInt8], _ body: (Int) -> Bool) -> Bool {
        var index = 0
        while index < haystack.count {
            if index == 0 || haystack[index - 1] == separator, body(index) { return true }
            index += 1
        }
        return false
    }

    private static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        guard needle.count <= haystack.count, let first = needle.first else { return false }
        let last = haystack.count - needle.count
        var start = 0
        while start <= last {
            // Cheap first-byte gate before the full comparison.
            if haystack[start] == first, matches(haystack, needle, at: start) { return true }
            start += 1
        }
        return false
    }

    private static func matches(_ haystack: [UInt8], _ needle: [UInt8], at start: Int) -> Bool {
        var offset = 0
        while offset < needle.count {
            if haystack[start + offset] != needle[offset] { return false }
            offset += 1
        }
        return true
    }
}
