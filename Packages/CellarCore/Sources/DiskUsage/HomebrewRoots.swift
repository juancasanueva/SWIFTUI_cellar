import BrewProcess
import Foundation

public struct HomebrewRoots: Codable, Sendable, Hashable {
    public let prefix: URL
    public let cellar: URL
    public let caskroom: URL
    public let cache: URL

    public init(installation: BrewInstallation, userCacheDirectory: URL) {
        let prefix = installation.executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
        self.prefix = prefix
        cellar = prefix.appendingPathComponent("Cellar", isDirectory: true)
        caskroom = prefix.appendingPathComponent("Caskroom", isDirectory: true)
        cache = userCacheDirectory.appendingPathComponent("Homebrew", isDirectory: true)
    }

    public var identity: DiskRootsIdentity {
        DiskRootsIdentity(cellar: cellar.path, caskroom: caskroom.path, cache: cache.path)
    }

    public func url(for area: DiskArea) -> URL {
        switch area {
        case .cellar: cellar
        case .caskroom: caskroom
        case .cache: cache
        }
    }
}

public struct DiskRootsIdentity: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let cellar: String
    public let caskroom: String
    public let cache: String

    public init(schemaVersion: Int = 1, cellar: String, caskroom: String, cache: String) {
        self.schemaVersion = schemaVersion
        self.cellar = cellar
        self.caskroom = caskroom
        self.cache = cache
    }
}
