import Foundation

/// Where a Homebrew installation lives.
public enum BrewPrefix: Sendable, Equatable {
    /// `/opt/homebrew` — the native Apple Silicon prefix.
    case appleSilicon
    /// `/usr/local` — an Intel-era prefix carried over by migration or Rosetta.
    case intelCarryOver
    /// A user-configured location.
    case custom(URL)
}

/// A non-blocking note about an otherwise fully supported installation.
public enum Advisory: Sendable, Equatable, Hashable {
    /// Homebrew is installed under the Intel prefix. Everything works; the user
    /// may want to migrate eventually.
    case rosettaPrefix
}

/// A validated Homebrew installation Cellar can drive.
public struct BrewInstallation: Sendable, Equatable {
    /// The `brew` binary itself, with symlinks already resolved.
    public let executableURL: URL
    public let prefix: BrewPrefix
    public let version: BrewVersion
    /// Advisories never disable, degrade, or gate anything.
    public let advisories: Set<Advisory>

    public init(
        executableURL: URL,
        prefix: BrewPrefix,
        version: BrewVersion,
        advisories: Set<Advisory> = []
    ) {
        self.executableURL = executableURL
        self.prefix = prefix
        self.version = version
        self.advisories = advisories
    }
}
