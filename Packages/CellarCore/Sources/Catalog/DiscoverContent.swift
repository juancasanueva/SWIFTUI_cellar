import Foundation

/// One "new to you" row: a package, and when this machine first saw it.
public struct ArrivalRow: Sendable, Hashable, Identifiable {
    public var id: PackageID { package.id }

    public let package: CatalogPackage
    /// First observation **by this installation**. Deliberately not named
    /// `releasedAt` or `addedAt`: the field name is the first place a wrong
    /// claim would creep in.
    public let firstSeenAt: Date

    public init(package: CatalogPackage, firstSeenAt: Date) {
        self.package = package
        self.firstSeenAt = firstSeenAt
    }
}

/// Why a section has nothing to show.
///
/// Named reasons rather than a bare `isEmpty`, because "nothing has arrived
/// yet", "nothing is eligible to rank" and "the catalog has not loaded" are
/// three different facts a user would act on differently.
public enum DiscoverEmptyReason: Sendable, Hashable {
    /// Nothing has arrived yet. The ordinary first-run state (D5), and the only
    /// section permitted to be empty for an ordinary reason.
    case newnessMeasuredFromThisSyncOnward
    /// No package in the snapshot carries a published install count, so nothing
    /// is eligible for the ladder.
    case noEligibleRankedPackage
    /// Every curated entry named a token the adopted snapshot does not contain.
    case everyCuratedEntryUnresolved
}

/// A section's availability, as a value rather than as a convention.
///
/// The shape this type exists to make unrepresentable is an empty collection
/// paired with an empty string: a consumer cannot tell that apart from a
/// failure, from a still-loading state, or from a bug, so it is the one thing
/// Discover must never hand a view (package-discovery PD-R6).
public enum DiscoverSectionState<Content: Sendable & Hashable>: Sendable, Hashable {
    case populated(Content)
    case empty(DiscoverEmptyReason)
    /// No usable snapshot has been adopted yet. An ordinary state, never an
    /// error.
    case awaitingCatalog

    public var content: Content? {
        guard case .populated(let content) = self else { return nil }
        return content
    }

    public var emptyReason: DiscoverEmptyReason? {
        guard case .empty(let reason) = self else { return nil }
        return reason
    }

    public var isAwaitingCatalog: Bool { self == .awaitingCatalog }
}

extension DiscoverSectionState where Content: Collection {
    /// How many rows this section carries. `0` for both empty states, which is
    /// the count PD-R6 requires an empty section to report alongside its reason.
    public var count: Int { content?.count ?? 0 }

    /// Whether this section is empty *without saying why* — the state the type
    /// is designed to exclude. Always `false`; asserted rather than assumed,
    /// because a `.populated([])` is constructible and would be exactly the
    /// silent blank PD-R6 forbids.
    public var isSilentlyEmpty: Bool {
        guard case .populated(let content) = self else { return false }
        return content.isEmpty
    }
}

/// Everything Discover renders. No SwiftUI in sight.
public struct DiscoverContent: Sendable, Hashable {
    public let topFormulae: DiscoverSectionState<[RankedPackage]>
    public let topCasks: DiscoverSectionState<[RankedPackage]>
    public let curated: DiscoverSectionState<[ResolvedCuratedCategory]>
    public let newToYou: DiscoverSectionState<[ArrivalRow]>

    /// Malformed entries in the shipped curated file — a shipping bug.
    public let curatedSkippedRecordCount: Int
    /// Valid curated entries with no catalog match — ordinary drift.
    public let curatedUnresolvedCount: Int
    /// Arrivals inside the window but beyond the display cap; the "and N more"
    /// affordance.
    public let hiddenArrivalCount: Int

    public init(
        topFormulae: DiscoverSectionState<[RankedPackage]>,
        topCasks: DiscoverSectionState<[RankedPackage]>,
        curated: DiscoverSectionState<[ResolvedCuratedCategory]>,
        newToYou: DiscoverSectionState<[ArrivalRow]>,
        curatedSkippedRecordCount: Int,
        curatedUnresolvedCount: Int,
        hiddenArrivalCount: Int
    ) {
        self.topFormulae = topFormulae
        self.topCasks = topCasks
        self.curated = curated
        self.newToYou = newToYou
        self.curatedSkippedRecordCount = curatedSkippedRecordCount
        self.curatedUnresolvedCount = curatedUnresolvedCount
        self.hiddenArrivalCount = hiddenArrivalCount
    }

    /// Before any snapshot has been adopted: every section is waiting, and none
    /// of them is failing.
    public static let empty = DiscoverContent(
        topFormulae: .awaitingCatalog,
        topCasks: .awaitingCatalog,
        curated: .awaitingCatalog,
        newToYou: .awaitingCatalog,
        curatedSkippedRecordCount: 0,
        curatedUnresolvedCount: 0,
        hiddenArrivalCount: 0
    )

    /// Whether at least one section has something to show.
    public var hasContent: Bool {
        topFormulae.content?.isEmpty == false
            || topCasks.content?.isEmpty == false
            || curated.content?.isEmpty == false
            || newToYou.content?.isEmpty == false
    }
}

/// The explanatory copy CellarCore supplies for the arrivals section.
///
/// It lives here, and not in a view, because the honest-phrasing rule is a
/// requirement of the capability rather than a UI note — so a **test** owns the
/// words. Newness is measured from this machine's first observation; the catalog
/// carries no publication or release date, so any wording implying one would be
/// a claim Cellar cannot support (package-discovery PD-R5).
public enum DiscoverCopy {
    public static let arrivalsPopulated =
        "Packages this Mac first saw in the last 30 days."

    public static let arrivalsEmpty = """
        Nothing here yet. Cellar counts a package as new when this Mac first \
        sees it, so anything it meets from this sync onward shows up here for \
        30 days.
        """

    public static let noEligibleRankedPackage =
        "No package in this catalog reports an install count yet."

    public static let everyCuratedEntryUnresolved =
        "None of the picks are in this catalog right now."

    public static let awaitingCatalog =
        "Waiting for the catalog to finish loading."

    /// The sentence for a state, so a view never invents one.
    public static func text(for reason: DiscoverEmptyReason) -> String {
        switch reason {
        case .newnessMeasuredFromThisSyncOnward: arrivalsEmpty
        case .noEligibleRankedPackage: noEligibleRankedPackage
        case .everyCuratedEntryUnresolved: everyCuratedEntryUnresolved
        }
    }
}

/// Builds `DiscoverContent` from what the catalog already holds.
///
/// Pure and `nonisolated`: a snapshot already in memory, a resource already in
/// the bundle, and a sidecar the sync already read. No request, no subprocess,
/// no sync triggered by a section being rendered (PD-R2).
public enum DiscoverProjection {
    /// How many arrivals a section shows before the rest become "and N more".
    public static let defaultArrivalDisplayLimit = 30

    /// `content(...)` off the caller's actor.
    ///
    /// `@concurrent` rather than a plain `nonisolated func`, mirroring
    /// `PackageSearchIndex.build`: a synchronous nonisolated call from the main
    /// actor still runs *on* it, and ranking ~16k records twice is exactly the
    /// kind of work the adoption path keeps off the main actor.
    @concurrent
    public static func build(
        snapshot: CatalogSnapshot?,
        curated: CuratedDiscoveryList?,
        arrivals: PackageArrivalsLog?,
        now: Date,
        arrivalDisplayLimit: Int = defaultArrivalDisplayLimit
    ) async -> DiscoverContent {
        content(
            snapshot: snapshot,
            curated: curated,
            arrivals: arrivals,
            now: now,
            arrivalDisplayLimit: arrivalDisplayLimit
        )
    }

    public nonisolated static func content(
        snapshot: CatalogSnapshot?,
        curated: CuratedDiscoveryList?,
        arrivals: PackageArrivalsLog?,
        now: Date,
        arrivalDisplayLimit: Int = defaultArrivalDisplayLimit
    ) -> DiscoverContent {
        // No usable snapshot: every section waits. Not an error, and not an
        // empty-with-a-reason either — nothing has been measured yet.
        guard let snapshot else { return .empty }

        let resolved = (curated ?? .empty).resolved(against: snapshot.packages)
        let rows = arrivalRows(from: arrivals, in: snapshot, now: now)
        let shown = Array(rows.prefix(arrivalDisplayLimit))

        return DiscoverContent(
            topFormulae: section(
                DiscoverRanking.ladder(.formula, in: snapshot.packages),
                emptyBecause: .noEligibleRankedPackage
            ),
            topCasks: section(
                DiscoverRanking.ladder(.cask, in: snapshot.packages),
                emptyBecause: .noEligibleRankedPackage
            ),
            curated: section(
                resolved.categories,
                emptyBecause: .everyCuratedEntryUnresolved
            ),
            newToYou: section(
                shown,
                emptyBecause: .newnessMeasuredFromThisSyncOnward
            ),
            curatedSkippedRecordCount: resolved.skippedRecordCount,
            curatedUnresolvedCount: resolved.unresolvedEntryCount,
            hiddenArrivalCount: rows.count - shown.count
        )
    }

    /// The one place a collection becomes a section, so an empty one can never
    /// reach a view without a reason attached.
    private static func section<Element>(
        _ content: [Element],
        emptyBecause reason: DiscoverEmptyReason
    ) -> DiscoverSectionState<[Element]> {
        content.isEmpty ? .empty(reason) : .populated(content)
    }

    /// Arrivals inside the window whose package is still in the catalog, newest
    /// first.
    ///
    /// Pruned here as well as at write time: that is what makes the thirty-day
    /// rule true on a machine that has not synced in weeks. An entry naming a
    /// package the snapshot no longer holds is dropped silently — the log
    /// expires it within thirty days anyway, and a counter for it would be
    /// noise rather than honesty.
    private static func arrivalRows(
        from arrivals: PackageArrivalsLog?,
        in snapshot: CatalogSnapshot,
        now: Date
    ) -> [ArrivalRow] {
        guard let arrivals else { return [] }

        var byID: [PackageID: CatalogPackage] = [:]
        byID.reserveCapacity(snapshot.packages.count)
        for package in snapshot.packages { byID[package.id] = package }

        return arrivals
            .pruned(now: now)
            .arrivals
            .compactMap { arrival in
                byID[arrival.id].map { ArrivalRow(package: $0, firstSeenAt: arrival.firstSeenAt) }
            }
    }
}
