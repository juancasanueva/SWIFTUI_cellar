import Catalog
import Foundation

/// Everything the menu bar shows, derived once from the stores the window
/// already reads.
///
/// A projection **over** `InstalledBrowse`, never a second derivation of
/// outdated-ness. It delegates both the count and the set, so the status item,
/// the sidebar badge and the Updates list cannot disagree: agreement is a
/// property of one value rather than of three view files that happen to concur.
/// This is the `upgradableIDs` idiom, which exists because a label and a
/// submission once computed one number twice.
///
/// Pure over its inputs, so the whole surface is provable in the `swift test`
/// inner loop with no SwiftUI and no `Process`. There is deliberately nothing
/// effectful to inject: no store, no launcher, no session, no clock.
public struct MenuBarProjection: Sendable, Equatable {
    /// One outdated package, reduced to what a compact row states. Carries no
    /// artwork reference: that pipeline reaches the network, and opening a menu
    /// would fire it.
    public struct OutdatedEntry: Sendable, Equatable, Identifiable {
        public let id: PackageID
        public let name: String
        public let installedVersion: String
        public let catalogVersion: String

        public init(id: PackageID, name: String, installedVersion: String, catalogVersion: String) {
            self.id = id
            self.name = name
            self.installedVersion = installedVersion
            self.catalogVersion = catalogVersion
        }
    }

    /// How many outdated packages the surface presents before it summarises the
    /// rest. Public so a test names the same number the view does.
    public static let topOutdatedLimit = 5

    /// Equal to `InstalledBrowse.outdatedCount(metadata:)` for the same inputs,
    /// because it *is* that call.
    public let outdatedCount: Int
    /// Equal to `InstalledBrowse.outdatedIDs(metadata:)` for the same inputs.
    /// Exposed whole rather than only as the five presented entries: a surface
    /// that shows a count beside a list must draw both from one answer.
    public let outdatedIDs: Set<PackageID>
    /// At most `topOutdatedLimit`, drawn from `outdatedIDs`, in the installed
    /// inventory's existing name order — the only order this inventory has.
    public let topOutdated: [OutdatedEntry]
    /// Last known, in brew's own order. Never refreshed from here.
    public let services: [ServiceRecord]
    public let runningServiceCount: Int

    public init(browse: InstalledBrowse, metadata: MetadataLookup?, services: [ServiceRecord]) {
        let outdated = browse.outdatedIDs(metadata: metadata)
        outdatedIDs = outdated
        outdatedCount = browse.outdatedCount(metadata: metadata)
        // Filtering the **ordered** package array rather than sorting the set is
        // what makes the order total without a comparator. There is no severity
        // or recency order for outdated packages today, and inventing one here
        // would make this surface disagree with the Updates list.
        topOutdated = browse.inventory.packages
            .filter { outdated.contains($0.id) }
            .prefix(Self.topOutdatedLimit)
            .map {
                OutdatedEntry(
                    id: $0.id,
                    name: $0.name,
                    installedVersion: $0.installedVersion,
                    catalogVersion: $0.catalogVersion
                )
            }
        self.services = services
        runningServiceCount = services.filter { $0.status == .started }.count
    }

    /// The status item's title, **absent** when nothing is outdated.
    ///
    /// Never `"0"`, never `""`: the absence is the value, so the surface never
    /// has to decide locally what "nothing outdated" looks like.
    public var statusItemTitle: String? {
        outdatedCount == 0 ? nil : "\(outdatedCount)"
    }

    /// How many outdated packages are not among the presented entries, **absent**
    /// when every one of them is. Never `0`.
    public var remainingOutdatedCount: Int? {
        let rest = outdatedCount - topOutdated.count
        return rest > 0 ? rest : nil
    }

    /// The remainder line, absent on the same terms. Singular at exactly one,
    /// which a seven-outdated inventory with one snooze reaches in practice.
    public var andMoreLabel: String? {
        remainingOutdatedCount.map { $0 == 1 ? "and 1 more" : "and \($0) more" }
    }
}
