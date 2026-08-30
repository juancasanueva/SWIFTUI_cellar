import Catalog
import DiskUsage
import Foundation

/// The byte totals behind the Cleanup storage bar, derived once from the same
/// snapshot the rows render. Pure over its inputs so the one rule with a trap
/// in it — the npm double-count guard — can be stated in a test without a view.
nonisolated struct CleanupStorageBytes: Equatable {
    /// Linked formula kegs, less the npm globals when they live inside one.
    let cellar: Int64
    /// Kegs on disk but not linked, split out because "on disk but not linked"
    /// is worth seeing on its own — less the npm globals when they live inside
    /// one of these instead.
    let unlinked: Int64
    let caskroom: Int64
    let cache: Int64
    /// The global npm package directory; zero whenever npm is off.
    let npmGlobals: Int64

    init(packages: [DiskPackageUsage], snapshot: DiskUsageSnapshot?) {
        let formulaVersions = packages
            .filter { $0.id.kind == .formula }
            .flatMap(\.versions)
        let linked = formulaVersions
            .filter { $0.linkState != .unlinked }
            .reduce(Int64(0)) { $0 + $1.observation.allocatedBytes }
        let unlinkedTotal = formulaVersions
            .filter { $0.linkState == .unlinked }
            .reduce(Int64(0)) { $0 + $1.observation.allocatedBytes }
        caskroom = packages
            .filter { $0.id.kind == .cask }
            .reduce(Int64(0)) { $0 + $1.observation.allocatedBytes }
        cache = snapshot?.cache.allocatedBytes ?? 0
        npmGlobals = snapshot?.npmGlobals.allocatedBytes ?? 0
        // A Homebrew-installed node keeps `lib/node_modules` inside its own
        // keg, so those bytes are already in that keg's total. Move them into
        // the npm segment rather than showing them twice — out of whichever
        // bucket the keg sits in, since an unlinked node counts under
        // "Keg-only & unlinked", not under "Cellar". Clamp because a snapshot
        // mid-refresh can pair an old keg total with a new npm one.
        let overlap = snapshot?.npmGlobalsLiesInsideCellar == true ? npmGlobals : 0
        let hostKeg = snapshot.flatMap { Self.hostKeg(of: $0, among: formulaVersions) }
        if hostKeg?.linkState == .unlinked {
            cellar = linked
            unlinked = max(0, unlinkedTotal - overlap)
        } else {
            cellar = max(0, linked - overlap)
            unlinked = unlinkedTotal
        }
    }

    /// The formula version whose keg contains the npm globals: the one whose
    /// `<cellar>/<name>/<version>` prefixes the globals path. Nil when the
    /// globals are elsewhere or when no listed version owns that keg — a
    /// snapshot mid-refresh can name a keg the packages do not carry yet — and
    /// then the caller falls back to the linked bucket, where a node keg
    /// ordinarily sits.
    private static func hostKeg(
        of snapshot: DiskUsageSnapshot,
        among formulaVersions: [DiskVersionUsage]
    ) -> DiskVersionUsage? {
        guard snapshot.npmGlobalsLiesInsideCellar, let globals = snapshot.roots.npmGlobals else { return nil }
        let cellar = URL(fileURLWithPath: snapshot.roots.cellar).standardizedFileURL.pathComponents
        let components = URL(fileURLWithPath: globals).standardizedFileURL.pathComponents
        // Two components past the Cellar: the formula name and the version.
        guard components.count > cellar.count + 1 else { return nil }
        let name = components[cellar.count]
        let version = components[cellar.count + 1]
        return formulaVersions.first { $0.id.package.name == name && $0.id.rawVersion == version }
    }
}
