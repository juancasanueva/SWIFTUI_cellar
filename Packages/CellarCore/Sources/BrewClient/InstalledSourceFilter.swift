import BrewProcess
import Catalog
import Foundation

/// Whether the Source control may be used, and why not when it may not.
///
/// Four states rather than a `Bool` plus a reason, so "unavailable with no
/// reason" is unrepresentable. The three unavailable ones are different
/// sentences — "you have not turned this on", "we could not find npm", "the npm
/// you configured did not work" — and only one of them is the user's next step.
public enum NpmSourceAvailability: Sendable, Hashable {
    case available
    case disabled
    case absent
    case invalid

    public var isAvailable: Bool { self == .available }

    public var unavailableReason: NpmSourceUnavailableReason? {
        switch self {
        case .available: nil
        case .disabled: .disabled
        case .absent: .absent
        case .invalid: .invalid
        }
    }

    /// The availability implied by a detection state.
    ///
    /// `configuredPathMissing` folds into `invalid`: both mean the path the user
    /// chose did not work, which is one thing to tell them here. Settings, which
    /// is where they would fix it, keeps the distinction.
    public init(_ detection: NpmDetectionState) {
        switch detection {
        case .detected: self = .available
        case .disabled: self = .disabled
        case .absent: self = .absent
        case .invalid, .configuredPathMissing: self = .invalid
        }
    }
}

/// Why the Source control is not usable.
public enum NpmSourceUnavailableReason: Sendable, Hashable, CaseIterable {
    case disabled
    case absent
    case invalid

    /// What to say when the user asks why the control is greyed out.
    ///
    /// Copy lives here rather than beside the chip so the three sentences are
    /// assertable without rendering anything, and so a fourth reason cannot be
    /// added without someone writing its sentence. Each names **npm**: a
    /// brew-worded refusal on an npm control would send the user to fix the
    /// wrong thing.
    public var guidance: String {
        switch self {
        case .disabled: "Turn the npm source on in Settings to filter by source"
        case .absent: "npm was not detected on this Mac"
        case .invalid: "The npm path configured in Settings did not work"
        }
    }
}

/// The tag a row shows beside its name.
///
/// Derived from `kind` and nowhere else, so a row cannot be labelled by where it
/// happened to be composed. A formula gets none: it is the unmarked case, and a
/// pill on every row would carry no information at all.
public enum PackageKindTag: String, Sendable, Hashable, CaseIterable {
    case cask
    case npm

    public init?(kind: PackageKind) {
        switch kind {
        case .formula: return nil
        case .cask: self = .cask
        case .npm: self = .npm
        }
    }

    public var label: String {
        switch self {
        case .cask: "CASK"
        case .npm: "NPM"
        }
    }
}

extension InstalledPackage {
    /// This row's tag, or `nil` for the unmarked case.
    public var kindTag: PackageKindTag? { PackageKindTag(kind: kind) }
}

extension InstalledBrowse {
    /// The same inventory, told what the npm source is currently doing.
    ///
    /// A separate step rather than a fourth argument at every call site, because
    /// the three surfaces that announce the outdated number — the sidebar badge,
    /// Home and the menu bar — must keep building the browse with **one**
    /// expression, and only two of them care about npm at all. Narrowing
    /// afterwards leaves that expression intact and keeps the agreement between
    /// them structural rather than coincidental.
    public func withNpmSource(_ source: NpmSourceAvailability) -> InstalledBrowse {
        InstalledBrowse(inventory: inventory, isAvailable: isAvailable, npmSource: source)
    }

    /// Whether the Source picker should be interactive.
    public var isSourceFilterEnabled: Bool { npmSource.isAvailable }

    public var sourceUnavailableReason: NpmSourceUnavailableReason? {
        npmSource.unavailableReason
    }

    /// The source actually in effect.
    ///
    /// With npm unavailable every selection collapses to "all", so the rows a
    /// user sees are exactly the rows they would see with no source filtering at
    /// all — the discipline `effectiveMode` already follows for the
    /// installed-state filters. A stale "npm" selection left over from before the
    /// source was switched off must not empty the list.
    public func effectiveSource(_ requested: PackageSource?) -> PackageSource? {
        isSourceFilterEnabled ? requested : nil
    }

    /// The Installed list under the Source dimension.
    ///
    /// Composed by intersecting with membership by `PackageID.kind`, so it
    /// combines with the dependency toggle rather than replacing it.
    public func entries(
        source: PackageSource?,
        includingDependencies: Bool = true
    ) -> [InstalledPackage] {
        let rows = inventory.packages(includingDependencies: includingDependencies)
        guard let source = effectiveSource(source) else { return rows }
        return rows.filter { $0.kind.source == source }
    }

    /// The outdated identities belonging to one source.
    public func outdatedIDs(
        source: PackageSource,
        metadata: MetadataLookup?
    ) -> Set<PackageID> {
        outdatedIDs(metadata: metadata).filter { $0.kind.source == source }
    }
}

/// What every surface that announces updates says, per source.
///
/// Pure over the inventory, the metadata lookup and npm's freshness — the three
/// inputs, and nothing else. The rule it exists to enforce is the one a
/// `Bool` cannot express: **an npm that was not checked, or whose check failed,
/// is not up to date**. Collapsing freshness into a count makes an offline
/// machine report as current, which is the one claim this capability must never
/// make.
public struct InstalledUpdatesSummary: Sendable, Equatable {
    /// The npm half, present exactly when the source is contributing.
    public struct NpmComponent: Sendable, Equatable {
        /// Outdated npm packages, snooze-aware.
        public let count: Int
        public let freshness: NpmOutdatedState

        /// Whether npm may be *stated* to be current.
        public var isUpToDate: Bool { freshness.isUpToDate && count == 0 }
    }

    /// Outdated Homebrew packages, snooze-aware.
    public let homebrewCount: Int
    /// `nil` when the npm source is off or undetected.
    ///
    /// Absent rather than a zero-count component: "npm has nothing outdated" and
    /// "there is no npm here" are different statements, and a surface that got a
    /// zero would render a component about a source the user never enabled.
    public let npm: NpmComponent?

    public init(
        browse: InstalledBrowse,
        metadata: MetadataLookup?,
        npmFreshness: NpmOutdatedState
    ) {
        homebrewCount = browse.outdatedIDs(source: .homebrew, metadata: metadata).count
        npm = browse.isSourceFilterEnabled
            ? NpmComponent(
                count: browse.outdatedIDs(source: .npm, metadata: metadata).count,
                freshness: npmFreshness
            )
            : nil
    }

    /// The number every surface announces.
    ///
    /// Equal to `InstalledBrowse.outdatedCount(metadata:)` over the merged
    /// inventory by construction: the two components partition the same set, and
    /// with npm off there are no npm rows in it to partition.
    public var total: Int { homebrewCount + (npm?.count ?? 0) }

    /// Whether "up to date" may be said at all.
    ///
    /// Requires both halves to agree, and the npm half requires a *completed*
    /// check. With npm off there is no npm half to satisfy.
    public var isUpToDate: Bool {
        guard homebrewCount == 0 else { return false }
        guard let npm else { return true }
        return npm.isUpToDate
    }
}
