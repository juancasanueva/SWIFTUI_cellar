import Foundation

/// One rung of a ranked ladder.
///
/// Carries the `InstallCount` rather than a bare number so a consumer can state
/// the claim honestly: the value is a floor over analytics-opted-in users, and it
/// counts a different quantity for a formula than for a cask
/// (package-discovery PD-R1).
public struct RankedPackage: Sendable, Hashable, Identifiable {
    public var id: PackageID { package.id }

    /// 1-based, and **within its own ladder** — both ladders start at 1, because
    /// they measure different things and are never merged.
    public let rank: Int
    public let package: CatalogPackage
    public let installs: InstallCount

    public init(rank: Int, package: CatalogPackage, installs: InstallCount) {
        self.rank = rank
        self.package = package
        self.installs = installs
    }
}

/// The most-installed ladders, one per package kind.
///
/// A namespace of pure functions over a snapshot the catalog already holds: no
/// store, no actor, no acquisition. Producing a ladder is a sort, which is what
/// lets Discover cost no new request (package-discovery PD-R2).
///
/// **Absent is not zero.** A package the analytics endpoint never listed has no
/// `installCount` and is *ineligible*, not rank-last. This deliberately does not
/// reuse `PackageSearchIndex`'s empty-query order: that order sorts unmeasured
/// records after every measurement, which is right for search — the user still
/// wants to find them — and wrong for a ranking, where an unmeasured package
/// claiming a rung would be a number the catalog never published.
public enum DiscoverRanking {
    /// D3: fifty rungs per ladder. Long enough to browse, short enough that the
    /// tail is still something people actually install.
    public static let ladderDepth = 50

    /// The ladder for one kind, highest count first.
    ///
    /// Eligible = matching `kind`, not deprecated, not disabled, and carrying a
    /// published install count. Order is `count` descending, then `name`
    /// ascending — a total order, because `(name, kind)` is unique, so the same
    /// snapshot always yields byte-identical ladders.
    public nonisolated static func ladder(
        _ kind: PackageKind,
        in packages: [CatalogPackage],
        depth: Int = ladderDepth
    ) -> [RankedPackage] {
        let eligible: [(package: CatalogPackage, installs: InstallCount)] = packages
            .compactMap { package in
                guard package.kind == kind else { return nil }
                // Recommending an abandoned package is worse than showing a
                // shorter list (D3).
                guard !package.deprecated, !package.disabled else { return nil }
                // The only place absence is decided. `installCount` is `nil`
                // exactly when the catalog published no measurement, and there
                // is no branch below that can invent one.
                guard let installs = package.installCount else { return nil }
                return (package, installs)
            }

        return eligible
            .sorted { left, right in
                left.installs.value == right.installs.value
                    ? left.package.name < right.package.name
                    : left.installs.value > right.installs.value
            }
            .prefix(depth)
            .enumerated()
            .map { offset, entry in
                RankedPackage(rank: offset + 1, package: entry.package, installs: entry.installs)
            }
    }
}
