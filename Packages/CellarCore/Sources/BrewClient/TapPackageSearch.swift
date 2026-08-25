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
/// It carries six facts and its copy, and nothing else. No description, no
/// **published** version, no homepage, no licence, no dependency list, no
/// install count, no deprecation or disabled flag and no size is
/// *representable*, because the tap inventory publishes none of them. The one
/// version it does carry is the version brew **offers** for a package this Mac
/// has installed, which comes from the installed receipt rather than from the
/// tap (PS8 round 4, DD-19).
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
    /// What the withheld state still has to explain, and `nil` for every other
    /// state (PS8).
    ///
    /// The install state itself is presented by the **shared status pill** the
    /// catalog result surface draws, so `Installed.` and `Not installed.` are
    /// withdrawn: the pill's presence carries the first fact and its absence
    /// carries the second, and a sentence repeating either beside the chip is
    /// the duplicate presentation `installed-inventory` II8 forbids (DD-9).
    /// What survives is genuinely explanatory — *what* Homebrew is withholding —
    /// and it stays here rather than in the view, exactly as `collisionNote`
    /// does. An absence is `nil`, never `""`.
    public let stateNote: String?
    /// The version brew currently **offers**, and `nil` unless this Mac has the
    /// package *and* its receipt reports it outdated (PS8 round 4).
    ///
    /// Read from the installed receipt, never from the tap and never from the
    /// catalog — so it costs no brew invocation and stays inside PD6's and TM5's
    /// boundaries. The gate is the receipt's **own** `isOutdated`, which is
    /// `installed-inventory` II4's shipped rule including the self-updating-cask
    /// exclusion, so this surface cannot disagree with the Installed list about
    /// which packages have an update.
    ///
    /// **Stored, not computed** — unlike `isInstalled`. `Mirror` enumerates
    /// stored properties only, and PS8's facts scenario reads that enumeration:
    /// a computed offer would be a fact the type carries and the enumeration
    /// denies. Storing it is also what keeps the synthesised `Hashable` from
    /// needing anything more than the hand-written `hash(into:)` below.
    public let nextVersion: String?
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

    /// Whether this Mac has the package — **both** installed states say yes.
    ///
    /// Computed rather than stored, so the hit still carries exactly its five
    /// facts: `Mirror` enumerates stored properties, and PS8's five-facts
    /// scenario reads that enumeration. It is the one fact the row consults to
    /// draw the shared `Installed` pill, and it deliberately cannot stand in for
    /// `routableID`: routing additionally needs the hit to be uncollided and
    /// unique, which no `Bool` about installation can express (DD-4, DD-9).
    public var isInstalled: Bool { state != .notInstalled }

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

/// Why the tap search surface shows what it shows (PS8, DD-6).
///
/// The surface it answers for is **always reachable from the sidebar**, so it
/// can never hide the way a section could: it has to *say why* it is empty, and
/// there are four distinct reasons. Folded from the shipped
/// `TapProjection.state(loadState:inventory:)`, which already distinguishes the
/// first three — including the rule that keeps a resident inventory visible
/// while a refresh is in flight. Only `.noMatch` is new here, because only it
/// depends on the hit count.
public enum TapSearchPresentation: Sendable, Equatable {
    /// Nothing resident yet and a read in flight.
    case loading
    /// Brew is absent. An **absence**, never an error (PS8).
    case unavailable(InstalledAbsence)
    /// The refresh failed with nothing good to fall back on. Still an ordinary
    /// empty state: the surface reports no banner and demands no retry.
    case failed(TapInventoryError)
    /// Available, and no installed third-party tap publishes anything.
    case noTaps
    /// A query that matched nothing. Deliberately carries the query, because
    /// the empty state the catalog surface already owns is worded around it.
    case noMatch(query: String)
    case content

    /// The pinned sentence for this state, or `nil` where none is pinned.
    ///
    /// The whole point of the projection owning it: a `unit` test can reach
    /// these bytes, and a second presenting surface cannot word the same fact
    /// differently (DD-17). `.noMatch` reuses the ordinary search empty state
    /// the catalog query surface already renders, so no copy is pinned for it.
    public var emptyStateCopy: String? {
        switch self {
        case .unavailable, .failed: Self.unavailableCopy
        case .noTaps: Self.noTapsCopy
        case .loading, .noMatch, .content: nil
        }
    }

    private static let unavailableCopy = "No packages from your taps."
    private static let noTapsCopy = "Your taps publish nothing yet."
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

    /// Every user-visible **sentence** on this surface originates here, so a
    /// second presenting surface cannot word the same fact differently.
    /// `private` rather than `public`: the view renders `stateNote` and
    /// `collisionNote`, it does not reach for the constants behind them.
    ///
    /// Two sentences left in round 3. `Installed.` and `Not installed.` are
    /// **withdrawn** for this surface — the shared `Installed` pill carries that
    /// state now — and are deliberately not kept "just in case": a live constant
    /// no caller reads is how withdrawn copy comes back. Both are untouched in
    /// `TapPackage.statusExplanation`, which serves the tap-detail rows TM5
    /// governs.
    private static let withheldCopy =
        "Installed. Homebrew withholds its tap while this tap is untrusted."
    private static let collisionCopy =
        "Also in the catalog. Homebrew installs the catalog package."

    // MARK: - Composition

    /// The matching hits, ordered by `(rank, bare token, kind, tap name)`.
    ///
    /// An **empty or whitespace-only query lists every published package** at
    /// `.exactToken`, so the order falls entirely to the remaining three keys —
    /// exactly as `PackageSearchIndex.defaultOrder(filters:limit:)` answers an
    /// empty catalog query with the whole filtered catalog. One rule orders the
    /// default listing and the search results, so a later reader has one order
    /// to keep in step rather than two (DD-16).
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
                stateNote: Self.note(for: match.package.state),
                nextVersion: offeredVersion(for: match.package),
                alsoInCatalog: collides,
                collisionNote: collides ? Self.collisionCopy : nil,
                rank: match.rank,
                routableID: routable ? match.package.id : nil
            )
        }
    }

    /// The version brew offers for this package, or `nil` (PS8 round 4, DD-19).
    ///
    /// Keyed off **`installedHandoff`**, not off `package.id`. The two differ
    /// exactly where it matters: `TapProjection.installState` answers
    /// `.notInstalled` for a receipt whose `tap` names a *different* tap, so a
    /// lookup by bare identity would offer a version to a row this projection
    /// calls not installed. Both installed states answer, because both **are**
    /// installed.
    private func offeredVersion(for package: TapPackage) -> String? {
        guard
            let id = package.installedHandoff,
            let receipt = installed.package(id),
            receipt.isOutdated
        else { return nil }
        return receipt.catalogVersion
    }

    /// Why the surface shows what it shows (DD-6).
    ///
    /// Built by **switching over the shipped `TapProjection.state(…)`** and
    /// folding the hit count on top. Nothing here re-reads `TapLoadState`: that
    /// projection already answers absence, failure, emptiness and the
    /// last-good rule, and a second opinion on a question one projection
    /// already answers is exactly the drift PT5's one-projection rule forbids.
    public static func presentation(
        tapState: TapLoadState,
        inventory: TapInventory,
        query: String,
        hitCount: Int
    ) -> TapSearchPresentation {
        /// The half that depends on the hits rather than on the load state.
        ///
        /// With no needle the surface lists everything, so zero hits means
        /// nothing is published rather than nothing matched (DD-16).
        func resolved() -> TapSearchPresentation {
            if hitCount > 0 { return .content }
            return PackageText.normalize(query).isEmpty ? .noTaps : .noMatch(query: query)
        }

        switch TapProjection.state(loadState: tapState, inventory: inventory) {
        case .idle:
            return .loading
        case .loading(let hasLastGood):
            return hasLastGood ? resolved() : .loading
        case .unavailable(let absence):
            return .unavailable(absence)
        // A failed refresh over a resident inventory still has rows to show,
        // and "No packages from your taps." would be false while they are on
        // screen. The last-good rule is inherited, not re-litigated.
        case .error(let error, let hasLastGood):
            return hasLastGood ? resolved() : .failed(error)
        case .content(let isThirdPartyEmpty):
            return isThirdPartyEmpty ? .noTaps : resolved()
        }
    }

    /// The number behind the surface's prompt and the shell's count label.
    ///
    /// Third-party taps only — the same set `hits(_:)` draws from, so the count
    /// and the default listing can never disagree. A view-side sum would be the
    /// same claim in a place no `unit` test can reach (DD-17).
    public static func packageCount(inventory: TapInventory) -> Int {
        TapProjection(inventory: inventory).thirdPartyTaps
            .reduce(0) { $0 + $1.formulaNames.count + $1.caskTokens.count }
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
        // The default listing: an empty needle is carried by every name, at the
        // strongest class, so the ladder stays uniform and DD-5's remaining
        // three keys do the whole ordering (DD-16).
        if needle.isEmpty { return .exactToken }
        if haystack == needle || hasToken(haystack, needle) { return .exactToken }
        if hasPrefix(haystack, needle) || hasTokenPrefix(haystack, needle) { return .namePrefix }
        return contains(haystack, needle) ? .nameSubstring : nil
    }

    /// The one state that still has something to explain (PS8 round 3, DD-9).
    ///
    /// Exhaustive on purpose: a fourth install state would have to decide here,
    /// visibly, at compile time, rather than silently inherit `nil`.
    private static func note(for state: TapPackageInstallState) -> String? {
        switch state {
        case .installed, .notInstalled: nil
        case .installedTapWithheld: withheldCopy
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
