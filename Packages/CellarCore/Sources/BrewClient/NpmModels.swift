import Catalog
import Foundation

/// One globally installed npm package, as `npm ls -g --json --depth=0` reports it.
public struct NpmGlobalPackage: Sendable, Hashable {
    /// The token npm installs by. Scoped names keep their `@scope/` prefix.
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }

    public var id: PackageID { PackageID(kind: .npm, name: name) }
}

/// One row of `npm outdated -g --json`.
public struct NpmOutdatedRecord: Sendable, Hashable {
    /// The version installed now.
    public let current: String
    /// The newest version the *declared range* allows.
    ///
    /// Preserved because npm reports it, and deliberately not consulted for
    /// outdatedness: the upgrade verb Cellar issues is
    /// `npm install -g <name>@latest`, so `wanted` would announce an update the
    /// button does not perform, and hide one it does.
    public let wanted: String?
    /// The newest published version. What an upgrade will actually install, and
    /// therefore the version a snooze is taken against.
    public let latest: String

    public init(current: String, wanted: String?, latest: String) {
        self.current = current
        self.wanted = wanted
        self.latest = latest
    }

    public var isOutdated: Bool { current != latest }
}

/// Why an outdated check has not produced an answer.
///
/// Distinct from a failure, because the two are different sentences and only one
/// of them names something that went wrong.
public enum NpmNotCheckedReason: Sendable, Hashable {
    /// The source is on and the first check has not run yet.
    case notYetChecked
    /// The check was cancelled. Nothing went wrong; there is simply no answer.
    case cancelled
}

/// How current the npm outdated picture is.
///
/// Three states rather than an optional set, because the difference between them
/// is the difference between three sentences a user has to be able to tell
/// apart: "nothing needs updating", "we have not looked", and "we looked and
/// could not reach the registry". Collapsing the last two into an empty set
/// makes an offline machine read as up to date, which is the exact claim this
/// capability must never make (npm-source: neither `failed` nor `notChecked`
/// may ever be presented, counted or summarised as up to date).
public enum NpmOutdatedState: Sendable, Equatable {
    /// A completed check, and when it completed.
    case fresh([String: NpmOutdatedRecord], at: Date)
    case notChecked(NpmNotCheckedReason)
    case failed(NpmInventoryError)

    /// The records, and `nil` for both non-answers. Only `fresh` may contribute
    /// an npm entry to the outdated set.
    public var records: [String: NpmOutdatedRecord]? {
        guard case .fresh(let records, _) = self else { return nil }
        return records
    }

    public var checkedAt: Date? {
        guard case .fresh(_, let checkedAt) = self else { return nil }
        return checkedAt
    }

    public var failure: NpmInventoryError? {
        guard case .failed(let error) = self else { return nil }
        return error
    }

    /// Whether npm may be *stated* to be up to date.
    ///
    /// A completed check that found nothing, and nothing else. This is the
    /// property every summary must ask instead of testing an empty collection.
    public var isUpToDate: Bool {
        guard case .fresh(let records, _) = self else { return false }
        return records.values.contains(where: \.isOutdated) == false
    }

    /// The offered version for a package, when a completed check named one.
    public func latest(for name: String) -> String? {
        records?[name]?.latest
    }
}

/// Everything read from npm in one refresh: what is installed, and how current
/// the outdated picture is.
public struct NpmInventory: Sendable, Equatable {
    public let packages: [NpmGlobalPackage]
    public let outdated: NpmOutdatedState

    public init(packages: [NpmGlobalPackage], outdated: NpmOutdatedState) {
        self.packages = packages
        self.outdated = outdated
    }

    /// The inventory of a machine with the source on and nothing read yet.
    public static let empty = NpmInventory(packages: [], outdated: .notChecked(.notYetChecked))

    public var isEmpty: Bool { packages.isEmpty }

    /// npm's globals as rows of the one installed inventory.
    ///
    /// This is where hybrid approach C is paid for. There is no second inventory
    /// type and no app-level union: an npm global becomes an `InstalledPackage`
    /// like any other, so every consumer of `inventory.outdatedIDs` — the
    /// sidebar, Home, Health, the menu bar and the Installed list — keeps
    /// reading the property it already reads.
    ///
    /// Four members of `InstalledPackage` describe things only Homebrew's
    /// payload carries, and all four are left **absent** rather than defaulted:
    /// `tap`, `linkedKeg` and `declaresAutoUpdates` are `nil`, and the install
    /// timestamp is `nil` because npm's listing does not record one. Filling any
    /// of them with a plausible value would state a fact about this machine that
    /// nothing was ever read to support.
    ///
    /// The offered version is `latest` and never `wanted`: the upgrade verb is
    /// `npm install -g <name>@latest`, so a row must offer the version the button
    /// actually installs.
    ///
    /// The listing decides what is installed and at which version, and the
    /// report only decides what is *offered*. The two come from two separate
    /// invocations, so a package upgraded between them makes the report's
    /// `current` stale — and a row that trusted it would announce an update the
    /// user has already applied.
    public func installedPackages() -> [InstalledPackage] {
        let offered = outdated.records

        return packages.map { global in
            // `nil` at every non-fresh freshness. `notChecked` and `failed` must
            // never contribute an offered version, because `catalogVersion`
            // differing from the installed one is what a surface reads as
            // "behind" (npm-source: only `fresh` contributes).
            let latest = offered?[global.name]?.latest
            let keg = InstalledKeg(
                version: global.version,
                installedAt: nil,
                installedOnRequest: true
            )
            return InstalledPackage(
                kind: .npm,
                name: global.name,
                displayName: global.name,
                desc: nil,
                homepage: nil,
                tap: nil,
                catalogVersion: latest ?? global.version,
                kegs: [keg],
                primaryKeg: keg,
                snapshotOutdated: latest.map { $0 != global.version } ?? false,
                isPinned: false,
                pinnedVersion: nil,
                declaresAutoUpdates: nil,
                linkedKeg: nil
            )
        }
    }
}
