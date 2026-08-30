import BrewProcess
import Foundation

public struct HomebrewRoots: Codable, Sendable, Hashable {
    public let prefix: URL
    public let cellar: URL
    public let caskroom: URL
    public let cache: URL
    /// Where `npm install -g` puts packages: `<npm prefix>/lib/node_modules`.
    /// Nil when npm is off or undetected, and then nothing measures it.
    public let npmGlobals: URL?

    public init(installation: BrewInstallation, userCacheDirectory: URL, npmPrefix: URL? = nil) {
        let prefix = installation.executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
        self.prefix = prefix
        cellar = prefix.appendingPathComponent("Cellar", isDirectory: true)
        caskroom = prefix.appendingPathComponent("Caskroom", isDirectory: true)
        cache = userCacheDirectory.appendingPathComponent("Homebrew", isDirectory: true)
        npmGlobals = npmPrefix?
            .standardizedFileURL
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("node_modules", isDirectory: true)
    }

    public var identity: DiskRootsIdentity {
        DiskRootsIdentity(cellar: cellar.path, caskroom: caskroom.path, cache: cache.path, npmGlobals: npmGlobals?.path)
    }

    /// Optional only for `.npm`; the three Homebrew areas always have a URL.
    public func url(for area: DiskArea) -> URL? {
        switch area {
        case .cellar: cellar
        case .caskroom: caskroom
        case .cache: cache
        case .npm: npmGlobals
        }
    }
}

public struct DiskRootsIdentity: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let cellar: String
    public let caskroom: String
    public let cache: String
    /// Optional, and encoded only when set, so a cache file written before the
    /// key existed still decodes and an identity without npm still encodes the
    /// four keys it always did. Being part of the identity is what makes
    /// switching npm on or off count as "roots moved": the store compares
    /// identities on entry and rescans on a mismatch.
    public let npmGlobals: String?

    public init(
        schemaVersion: Int = 1,
        cellar: String,
        caskroom: String,
        cache: String,
        npmGlobals: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.cellar = cellar
        self.caskroom = caskroom
        self.cache = cache
        self.npmGlobals = npmGlobals
    }

    /// The areas a scan of these roots reports a state for. `DiskArea.allCases`
    /// is not that set: the npm area exists only when a globals directory is
    /// configured, so "every root reported" has to be judged against this.
    public var measuredAreas: Set<DiskArea> {
        var areas: Set<DiskArea> = [.cellar, .caskroom, .cache]
        if npmGlobals != nil { areas.insert(.npm) }
        return areas
    }

    /// The directory a measured version occupies, under these roots.
    ///
    /// Derived rather than stored, because the engine already builds every
    /// measured path from the roots and the raw name and version components;
    /// carrying the path in the snapshot would widen the cache schema to say
    /// what this recomputes exactly. Brew kinds keep a version directory; an
    /// npm package is one directory whose version lives in its manifest. A
    /// scoped npm name is two components, appended one at a time so `@scope`
    /// and `name` stay separate segments. Nil only for npm without globals.
    public func location(of version: DiskVersionUsage) -> URL? {
        let package = version.id.package
        switch package.kind {
        case .formula:
            return URL(fileURLWithPath: cellar, isDirectory: true)
                .appendingPathComponent(package.name, isDirectory: true)
                .appendingPathComponent(version.id.rawVersion, isDirectory: true)
        case .cask:
            return URL(fileURLWithPath: caskroom, isDirectory: true)
                .appendingPathComponent(package.name, isDirectory: true)
                .appendingPathComponent(version.id.rawVersion, isDirectory: true)
        case .npm:
            guard let npmGlobals else { return nil }
            return package.name.split(separator: "/").reduce(URL(fileURLWithPath: npmGlobals, isDirectory: true)) {
                $0.appendingPathComponent(String($1), isDirectory: true)
            }
        }
    }
}
