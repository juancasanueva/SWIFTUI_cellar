import Foundation
import Synchronization

/// Which tool installed a package, and therefore which tool can change it.
///
/// Derived from `PackageKind` rather than stored beside it: one identity keeps
/// favourites, snooze, history and every count keyed on the pair they already
/// use, and no persisted row gains a column (design D1).
public enum PackageSource: String, Codable, Sendable, Hashable, CaseIterable {
    case homebrew
    case npm
}

/// Which namespace a package belongs to.
///
/// `formula` and `cask` are Homebrew's two. `npm` is not a Homebrew namespace at
/// all — it joins this enum so that one `PackageID` spans both sources, which is
/// what lets the merged inventory, the outdated set and every persisted row stay
/// single-typed. The consequence is recorded and accepted: `Catalog` now carries
/// a kind the catalog itself never publishes, and every switch over this enum
/// has to say so explicitly.
public enum PackageKind: String, Codable, Sendable, Hashable, CaseIterable {
    case formula
    case cask
    case npm

    /// The tool that installed a package of this kind.
    public var source: PackageSource {
        switch self {
        case .formula, .cask: .homebrew
        case .npm: .npm
        }
    }
}

/// A package's identity.
///
/// `name` alone is ambiguous — Homebrew publishes the same token in both
/// namespaces — so identity is the pair, everywhere, with no "look it up by
/// name and hope" convenience overload (package-search PS1).
public struct PackageID: Hashable, Sendable, Codable {
    public let kind: PackageKind
    public let name: String

    public init(kind: PackageKind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// One edge of a package's declared dependency list.
///
/// `isResolvable` is decided once, at sync time, against the complete snapshot:
/// the projection knows every name it persisted, so a consumer never has to ask
/// "does this link go anywhere?" per render (package-detail PD2).
public struct PackageDependency: Codable, Sendable, Hashable {
    public let name: String
    /// Whether a package with this name exists in the same snapshot.
    public let isResolvable: Bool

    public init(name: String, isResolvable: Bool) {
        self.name = name
        self.isResolvable = isResolvable
    }
}

/// What an install count actually counts.
public enum InstallMetric: String, Codable, Sendable, Hashable {
    /// Formulae: installs the user asked for, excluding dependency pull-ins.
    case installsOnRequest
    /// Casks: installs.
    case installs
}

/// An install count together with the facts needed to describe it honestly.
///
/// Homebrew's analytics cover only users who did not opt out, so the number is
/// always a floor, never a total (package-detail PD5). Composed on demand rather
/// than persisted: the window, the metric and the lower-bound flag are all
/// derivable, and storing them 16,000 times would triple the snapshot.
public struct InstallCount: Sendable, Hashable {
    public let value: Int
    public let windowDays: Int
    public let metric: InstallMetric
    /// Always true — opted-out users are invisible to the published analytics.
    public let isLowerBound: Bool
}

/// The slim projection persisted for one package.
///
/// Deliberately far narrower than the published record: everything search and
/// detail need, and nothing else (catalog-sync CS6).
public struct CatalogPackage: Codable, Sendable, Hashable, Identifiable {
    public var id: PackageID { PackageID(kind: kind, name: name) }

    public let kind: PackageKind
    /// The token Homebrew installs by — `iterm2`, not `iTerm2`.
    public let name: String
    /// What a human calls it. Equals `name` for formulae.
    public let displayName: String
    public let desc: String?
    public let homepage: URL?
    public let license: String?
    public let version: String
    public let tap: String
    public let dependencies: [PackageDependency]
    public let buildDependencies: [PackageDependency]
    public let dependents: [String]
    public let caveats: String?
    public let deprecated: Bool
    public let deprecationReason: String?
    public let deprecationDate: Date?
    public let disabled: Bool
    public let disableReason: String?
    public let disableDate: Date?
    /// Casks only: the app updates itself, so `brew upgrade` is not the path.
    public let autoUpdates: Bool
    /// Absent means "no analytics entry", which is not the same as zero installs.
    public let installCount365d: Int?
    /// Casks only: what the record says it downloads and installs. Absent for a
    /// cask that published none of the widened keys, and for every formula.
    ///
    /// Two grouped optionals and not seven flat fields on purpose: this type has
    /// a hand-written twenty-parameter `init` and two full-field copy helpers,
    /// so every field added here costs three call sites and risks a silent drop
    /// in each.
    public let caskInspection: CaskInspection?
    /// Formulae only: where the source comes from. Carried for the release-notes
    /// slice; nothing renders it yet.
    public let formulaSources: FormulaSources?

    public init(
        kind: PackageKind,
        name: String,
        displayName: String,
        desc: String?,
        homepage: URL?,
        license: String?,
        version: String,
        tap: String,
        dependencies: [PackageDependency],
        buildDependencies: [PackageDependency],
        dependents: [String],
        caveats: String?,
        deprecated: Bool,
        deprecationReason: String?,
        deprecationDate: Date?,
        disabled: Bool,
        disableReason: String?,
        disableDate: Date?,
        autoUpdates: Bool,
        installCount365d: Int?,
        // Defaulted so no existing call site changes.
        caskInspection: CaskInspection? = nil,
        formulaSources: FormulaSources? = nil
    ) {
        self.kind = kind
        self.name = name
        self.displayName = displayName
        self.desc = desc
        self.homepage = homepage
        self.license = license
        self.version = version
        self.tap = tap
        self.dependencies = dependencies
        self.buildDependencies = buildDependencies
        self.dependents = dependents
        self.caveats = caveats
        self.deprecated = deprecated
        self.deprecationReason = deprecationReason
        self.deprecationDate = deprecationDate
        self.disabled = disabled
        self.disableReason = disableReason
        self.disableDate = disableDate
        self.autoUpdates = autoUpdates
        self.installCount365d = installCount365d
        self.caskInspection = caskInspection
        self.formulaSources = formulaSources
    }

    /// The count with its window, metric and lower-bound semantics attached.
    public var installCount: InstallCount? {
        guard let installCount365d else { return nil }
        return InstallCount(
            value: installCount365d,
            windowDays: CatalogPackage.analyticsWindowDays,
            metric: kind == .formula ? .installsOnRequest : .installs,
            isLowerBound: true
        )
    }

    public static let analyticsWindowDays = 365

    /// A copy carrying settled dependency edges.
    ///
    /// Edges are the only fields decided after the whole snapshot is known, so
    /// they are the only ones this narrow copy touches.
    func replacingEdges(
        dependencies: [PackageDependency],
        buildDependencies: [PackageDependency],
        dependents: [String]
    ) -> CatalogPackage {
        CatalogPackage(
            kind: kind,
            name: name,
            displayName: displayName,
            desc: desc,
            homepage: homepage,
            license: license,
            version: version,
            tap: tap,
            dependencies: dependencies,
            buildDependencies: buildDependencies,
            dependents: dependents,
            caveats: caveats,
            deprecated: deprecated,
            deprecationReason: deprecationReason,
            deprecationDate: deprecationDate,
            disabled: disabled,
            disableReason: disableReason,
            disableDate: disableDate,
            autoUpdates: autoUpdates,
            installCount365d: installCount365d,
            caskInspection: caskInspection,
            formulaSources: formulaSources
        )
    }

    /// A copy carrying a joined analytics count.
    func replacingInstallCount(_ count: Int?) -> CatalogPackage {
        CatalogPackage(
            kind: kind,
            name: name,
            displayName: displayName,
            desc: desc,
            homepage: homepage,
            license: license,
            version: version,
            tap: tap,
            dependencies: dependencies,
            buildDependencies: buildDependencies,
            dependents: dependents,
            caveats: caveats,
            deprecated: deprecated,
            deprecationReason: deprecationReason,
            deprecationDate: deprecationDate,
            disabled: disabled,
            disableReason: disableReason,
            disableDate: disableDate,
            autoUpdates: autoUpdates,
            installCount365d: count,
            caskInspection: caskInspection,
            formulaSources: formulaSources
        )
    }
}

/// Which materialization of catalog content a snapshot is.
///
/// Process-local and never persisted: the point is to tell "this is the catalog
/// I already indexed" from "this is new content", and one launch is the only
/// scope in which an index exists. Consumers can compare revisions but cannot
/// mint one, so identity always comes from a real materialization (design D2).
public struct CatalogSnapshotRevision: Hashable, Sendable {
    private static let counter = Atomic<UInt64>(0)

    let ordinal: UInt64

    static func next() -> Self {
        Self(ordinal: counter.wrappingAdd(1, ordering: .relaxed).newValue)
    }
}

/// The persisted catalog: `catalog.json`.
///
/// Version history:
///
/// * **1** — the original slim projection.
/// * **2** — M5 inspection: `CatalogPackage` gained `caskInspection` and
///   `formulaSources`, so every v1 file is classified as no cache and re-synced
///   once. The check is exact in both directions, which is what makes reverting
///   that change a complete rollback rather than a decode with missing fields.
public struct CatalogSnapshot: Codable, Sendable {
    /// Bumped `1` -> `2` by the M5 inspection widening: the persisted projection
    /// gained `caskInspection` and `formulaSources`, so every file written by
    /// the previous build is classified as no cache and re-synced once.
    ///
    /// The check is exact in both directions, which is what makes reverting this
    /// slice a complete rollback rather than a decode of missing fields.
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    /// Records the payload published but this build could not read.
    public let skippedRecordCount: Int
    public let packages: [CatalogPackage]
    /// This materialization's identity. Outside `CodingKeys`, so it adds no key
    /// to the persisted JSON and no reason of its own to move `schemaVersion` —
    /// which the `1` -> `2` bump above did move, for a change to the *packages*
    /// shape rather than to this field.
    public let revision: CatalogSnapshotRevision

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case skippedRecordCount
        case packages
    }

    public init(
        schemaVersion: Int = CatalogSnapshot.currentSchemaVersion,
        generatedAt: Date,
        skippedRecordCount: Int,
        packages: [CatalogPackage]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.skippedRecordCount = skippedRecordCount
        self.packages = packages
        self.revision = .next()
    }

    private init(
        schemaVersion: Int,
        generatedAt: Date,
        skippedRecordCount: Int,
        packages: [CatalogPackage],
        revision: CatalogSnapshotRevision
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.skippedRecordCount = skippedRecordCount
        self.packages = packages
        self.revision = revision
    }

    /// The same content under an identity that already exists.
    ///
    /// Decoding always mints, so re-reading one file would otherwise look like
    /// new content every time; the engine pins the identity of the bytes on disk
    /// and re-stamps what it reads (design D2).
    func carrying(_ revision: CatalogSnapshotRevision) -> CatalogSnapshot {
        CatalogSnapshot(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            skippedRecordCount: skippedRecordCount,
            packages: packages,
            revision: revision
        )
    }

    /// Explicit because `revision` is outside `CodingKeys`: every decode is a
    /// fresh materialization and gets a fresh identity.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        skippedRecordCount = try container.decode(Int.self, forKey: .skippedRecordCount)
        packages = try container.decode([CatalogPackage].self, forKey: .packages)
        revision = .next()
    }
}

/// Which remote resource a stored validator belongs to.
public enum CatalogResource: String, Sendable, Hashable, Codable, CaseIterable {
    case formulae
    case casks
    case analyticsFormula = "analytics-formula"
    case analyticsCask = "analytics-cask"
}

/// Conditional-request validators as the origin sent them.
///
/// `lastModified` is kept as the **raw header string**. Round-tripping it
/// through a `DateFormatter` risks re-emitting a byte-different value the origin
/// no longer recognises, which silently turns every revalidation into a full
/// 31 MB download (design D7).
public struct ConditionalValidators: Sendable, Hashable, Codable {
    public var etag: String?
    public var lastModified: String?

    public init(etag: String? = nil, lastModified: String? = nil) {
        self.etag = etag
        self.lastModified = lastModified
    }

    public var isEmpty: Bool { etag == nil && lastModified == nil }
}

/// Per-resource acquisition bookkeeping.
public struct SourceState: Codable, Sendable, Hashable {
    public var validators: ConditionalValidators
    /// When this resource was last successfully fetched or revalidated.
    public var downloadedAt: Date
    public var recordCount: Int
    public var byteCount: Int

    public init(
        validators: ConditionalValidators,
        downloadedAt: Date,
        recordCount: Int,
        byteCount: Int
    ) {
        self.validators = validators
        self.downloadedAt = downloadedAt
        self.recordCount = recordCount
        self.byteCount = byteCount
    }
}

/// The state sidecar: `catalog-state.json`.
public struct CatalogState: Codable, Sendable, Hashable {
    public var schemaVersion: Int
    public var sources: [CatalogResource: SourceState]
    public var lastSuccessAt: Date
    public var skippedRecordCount: Int

    public init(
        schemaVersion: Int = CatalogSnapshot.currentSchemaVersion,
        sources: [CatalogResource: SourceState],
        lastSuccessAt: Date,
        skippedRecordCount: Int
    ) {
        self.schemaVersion = schemaVersion
        self.sources = sources
        self.lastSuccessAt = lastSuccessAt
        self.skippedRecordCount = skippedRecordCount
    }

    /// The newest successful acquisition across every resource.
    ///
    /// Freshness is decided by the *oldest* payload source, because a fresh
    /// analytics fetch does not make a two-day-old formula dump current.
    public var oldestPayloadDownloadedAt: Date? {
        let payloads: [Date] = [CatalogResource.formulae, .casks].compactMap {
            sources[$0]?.downloadedAt
        }
        return payloads.min()
    }
}
