import Catalog
import Foundation

public enum DiskArea: String, Codable, CaseIterable, Sendable, Hashable {
    case cellar
    case caskroom
    case cache
    /// The global npm package directory. Unlike the three Homebrew areas it is
    /// only measured when npm is detected, so `allCases` is not the set of
    /// areas a given scan covers: `DiskRootsIdentity.measuredAreas` is.
    case npm
}

public enum DiskRootState: Codable, Sendable, Hashable {
    case present
    case absent
    case failed(String)
}

public enum FormulaLinkState: Codable, Sendable, Hashable {
    case linked(String)
    case unlinked
    case notApplicable
}

public struct DiskObservation: Codable, Sendable, Hashable {
    public let allocatedBytes: Int64
    public let logicalBytes: Int64

    public init(allocatedBytes: Int64 = 0, logicalBytes: Int64 = 0) {
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
    }

    public static let zero = DiskObservation()

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            allocatedBytes: lhs.allocatedBytes + rhs.allocatedBytes,
            logicalBytes: lhs.logicalBytes + rhs.logicalBytes
        )
    }
}

public struct DiskVersionID: Codable, Sendable, Hashable {
    public let package: PackageID
    public let rawVersion: String

    public init(package: PackageID, rawVersion: String) {
        self.package = package
        self.rawVersion = rawVersion
    }
}

public struct DiskVersionUsage: Codable, Sendable, Hashable, Identifiable {
    public let id: DiskVersionID
    public let observation: DiskObservation
    public let linkState: FormulaLinkState

    public init(id: DiskVersionID, observation: DiskObservation, linkState: FormulaLinkState) {
        self.id = id
        self.observation = observation
        self.linkState = linkState
    }
}

public struct DiskPackageUsage: Codable, Sendable, Hashable, Identifiable {
    public let id: PackageID
    public let versions: [DiskVersionUsage]
    public let observation: DiskObservation

    public init(id: PackageID, versions: [DiskVersionUsage]) {
        self.id = id
        self.versions = versions.sorted { $0.id.rawVersion < $1.id.rawVersion }
        observation = versions.reduce(.zero) { $0 + $1.observation }
    }
}

public struct DiskUsageWarning: Codable, Sendable, Hashable, Identifiable {
    public let area: DiskArea
    public let path: String
    public let message: String
    public var id: String { "\(area.rawValue):\(path):\(message)" }

    public init(area: DiskArea, path: String, message: String) {
        self.area = area
        self.path = path
        self.message = message
    }
}

public struct DiskUsageSnapshot: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let roots: DiskRootsIdentity
    public let generatedAt: Date
    public let rootStates: [DiskArea: DiskRootState]
    public let packages: [DiskPackageUsage]
    public let cache: DiskObservation
    /// The global npm package directory, `.zero` whenever `roots.npmGlobals` is
    /// nil or the directory is absent.
    public let npmGlobals: DiskObservation
    public let warnings: [DiskUsageWarning]

    public init(
        schemaVersion: Int = 1,
        roots: DiskRootsIdentity,
        generatedAt: Date,
        rootStates: [DiskArea: DiskRootState],
        packages: [DiskPackageUsage],
        cache: DiskObservation,
        npmGlobals: DiskObservation = .zero,
        warnings: [DiskUsageWarning] = []
    ) {
        self.schemaVersion = schemaVersion
        self.roots = roots
        self.generatedAt = generatedAt
        self.rootStates = rootStates
        self.packages = Self.sorted(packages)
        self.cache = cache
        self.npmGlobals = npmGlobals
        self.warnings = warnings
    }

    /// Hand-written for one key. `npmGlobals` was added after cache files were
    /// already on disk, and `DiskUsageCache.load()` throws on a decode failure
    /// rather than degrading to a cold start, so a missing key has to read as
    /// `.zero` instead of `keyNotFound`. Encoding stays synthesized.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            roots: try container.decode(DiskRootsIdentity.self, forKey: .roots),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            rootStates: try container.decode([DiskArea: DiskRootState].self, forKey: .rootStates),
            packages: try container.decode([DiskPackageUsage].self, forKey: .packages),
            cache: try container.decode(DiskObservation.self, forKey: .cache),
            npmGlobals: try container.decodeIfPresent(DiskObservation.self, forKey: .npmGlobals) ?? .zero,
            warnings: try container.decode([DiskUsageWarning].self, forKey: .warnings)
        )
    }

    /// Whether the npm globals directory sits inside the Cellar, which is where
    /// a Homebrew-installed node keeps it (`<prefix>/lib/node_modules` resolves
    /// into the node keg). When it does, the same bytes are counted once under
    /// the node formula and once under `npmGlobals`, and whoever adds the two
    /// has to subtract the overlap. Compared on standardized paths so a trailing
    /// slash or a `..` cannot hide the containment.
    public var npmGlobalsLiesInsideCellar: Bool {
        guard let npmGlobals = roots.npmGlobals else { return false }
        let cellar = URL(fileURLWithPath: roots.cellar).standardizedFileURL.pathComponents
        let globals = URL(fileURLWithPath: npmGlobals).standardizedFileURL.pathComponents
        return globals.count > cellar.count && globals.prefix(cellar.count).elementsEqual(cellar)
    }

    public var isComplete: Bool {
        warnings.isEmpty && rootStates.values.allSatisfy {
            if case .failed = $0 { return false }
            return true
        }
    }

    public static func sorted(_ packages: [DiskPackageUsage]) -> [DiskPackageUsage] {
        packages.sorted {
            if $0.observation.allocatedBytes != $1.observation.allocatedBytes {
                return $0.observation.allocatedBytes > $1.observation.allocatedBytes
            }
            if $0.id.kind != $1.id.kind { return $0.id.kind == .formula }
            return $0.id.name < $1.id.name
        }
    }
}
