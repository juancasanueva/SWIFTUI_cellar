import Catalog
import DiskUsage
import Foundation

/// The byte totals behind the Cleanup storage bar, derived once from the same
/// snapshot the rows render. Pure over its inputs so the one rule with a trap
/// in it — the npm double-count guard — can be stated in a test without a view.
nonisolated struct CleanupStorageBytes: Equatable {
    /// Linked formula kegs, less the npm globals that live inside one of them.
    let cellar: Int64
    /// Kegs on disk but not linked, split out because "on disk but not linked"
    /// is worth seeing on its own.
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
        unlinked = formulaVersions
            .filter { $0.linkState == .unlinked }
            .reduce(Int64(0)) { $0 + $1.observation.allocatedBytes }
        caskroom = packages
            .filter { $0.id.kind == .cask }
            .reduce(Int64(0)) { $0 + $1.observation.allocatedBytes }
        cache = snapshot?.cache.allocatedBytes ?? 0
        npmGlobals = snapshot?.npmGlobals.allocatedBytes ?? 0
        // A Homebrew-installed node keeps `lib/node_modules` inside its own
        // keg, so those bytes are already in the node formula's total. Move
        // them into the npm segment rather than showing them twice, and clamp
        // because a snapshot mid-refresh can pair an old keg total with a new
        // npm one.
        let overlap = snapshot?.npmGlobalsLiesInsideCellar == true ? npmGlobals : 0
        cellar = max(0, linked - overlap)
    }
}
