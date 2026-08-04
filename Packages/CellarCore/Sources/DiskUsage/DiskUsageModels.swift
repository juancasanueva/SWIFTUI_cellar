import Catalog
import Foundation

public enum DiskArea: String, Codable, CaseIterable, Sendable, Hashable {
    case cellar
    case caskroom
    case cache
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
    public let warnings: [DiskUsageWarning]

    public init(
        schemaVersion: Int = 1,
        roots: DiskRootsIdentity,
        generatedAt: Date,
        rootStates: [DiskArea: DiskRootState],
        packages: [DiskPackageUsage],
        cache: DiskObservation,
        warnings: [DiskUsageWarning] = []
    ) {
        self.schemaVersion = schemaVersion
        self.roots = roots
        self.generatedAt = generatedAt
        self.rootStates = rootStates
        self.packages = Self.sorted(packages)
        self.cache = cache
        self.warnings = warnings
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
