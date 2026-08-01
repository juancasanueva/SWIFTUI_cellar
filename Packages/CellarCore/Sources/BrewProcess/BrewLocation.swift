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

/// Where to send a user who has no Homebrew yet.
public struct BrewInstallGuidance: Sendable, Equatable {
    public let website: URL
    /// The official install one-liner, verbatim from brew.sh.
    public let installCommand: String

    public static let standard = BrewInstallGuidance(
        website: URL(string: "https://brew.sh")!,
        installCommand:
            #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#
    )
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

/// The outcome of looking for Homebrew.
public enum BrewDetectionState: Sendable, Equatable {
    /// A usable installation.
    case detected(BrewInstallation)
    /// A configured path that exists but failed validation. Detection never
    /// falls back to an auto-discovered prefix from here (design decision D6).
    case invalid(URL, BrewValidationError)
    /// A configured path that is no longer on disk.
    case configuredPathMissing(URL)
    /// No Homebrew anywhere. A soft signal: it gates nothing, it only tells the
    /// UI to render guidance.
    case absent

    /// Install guidance, present exactly when Homebrew is absent.
    public var installGuidance: BrewInstallGuidance? {
        guard case .absent = self else { return nil }
        return .standard
    }

    /// The installation, when one was found.
    public var installation: BrewInstallation? {
        guard case .detected(let installation) = self else { return nil }
        return installation
    }
}

/// Finds and validates Homebrew.
public protocol BrewLocating: Sendable {
    func detect(configuredPath: URL?) async -> BrewDetectionState
}

/// File-system questions detection needs to ask.
///
/// Split out from `FileManager` so every branch — missing, present but not
/// executable, symlinked elsewhere — is reachable in a test without creating
/// real files.
public protocol ExecutableProbing: Sendable {
    /// Whether anything at all exists at `url`.
    func exists(at url: URL) -> Bool
    /// Whether `url` is a regular file with the execute bit set.
    func isExecutableRegularFile(at url: URL) -> Bool
    /// The URL with every symlink resolved, so validation probes the real
    /// binary rather than a link that could point anywhere.
    func resolvingSymlinks(at url: URL) -> URL
}

/// The production probe, backed by `FileManager`.
public struct DefaultExecutableProbe: ExecutableProbing {
    public init() {}

    public func exists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isExecutableRegularFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue == false
        else { return false }
        return FileManager.default.isExecutableFile(atPath: url.path)
    }

    public func resolvingSymlinks(at url: URL) -> URL {
        url.resolvingSymlinksInPath()
    }
}
