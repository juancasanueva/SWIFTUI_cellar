import Foundation

/// Why a candidate npm was refused.
///
/// Each case is a distinct thing to tell the user, which is why there is no
/// catch-all: "the path you configured is not executable" and "the path you
/// configured is some other program called npm" lead to different fixes.
///
/// The URL is not carried inside the reason — `NpmDetectionState.invalid` holds
/// it once, beside the reason, so the two can never disagree.
public enum NpmValidationError: Error, Sendable, Equatable, Hashable {
    /// Present, but not a regular file with the execute bit set.
    case notExecutable
    /// It ran, and what it printed for `--version` is not a version.
    case notNpm(output: String)
    /// It ran and reported a version, but `prefix -g` did not answer.
    case noGlobalPrefix
    /// The probe could not be spawned at all.
    case probeFailed(message: String)
}

/// The outcome of looking for npm.
///
/// Deliberately a sibling of `BrewDetectionState` rather than a widening of it.
/// Brew's states are shipped vocabulary that a dozen surfaces already read; a
/// fifth case on that enum would have made every one of them answer a question
/// about npm. The shapes rhyme because the rules genuinely are the same — one
/// selection, a configured path that never falls through, a soft absence — and
/// the one case with no brew counterpart is the one npm needs because it is
/// opt-in.
public enum NpmDetectionState: Sendable, Equatable {
    /// A usable npm, with everything Settings has to disclose about it.
    case detected(NpmEnvironment)
    /// A configured path that exists but failed validation. Detection never
    /// falls back to a discovered candidate from here.
    case invalid(URL, NpmValidationError)
    /// A configured path that is no longer on disk.
    case configuredPathMissing(URL)
    /// No npm anywhere. A soft signal: it gates nothing beyond npm itself.
    case absent
    /// The source is switched off. Distinct from `absent`, because "you turned
    /// this off" and "we looked and found nothing" are different sentences, and
    /// only one of them should offer to help you install npm.
    case disabled

    /// The validated npm, when there is one.
    public var environment: NpmEnvironment? {
        guard case .detected(let environment) = self else { return nil }
        return environment
    }

    /// Whether npm commands may be built and run at all.
    public var isAvailable: Bool { environment != nil }
}

/// Finds and validates npm.
public protocol NpmLocating: Sendable {
    func detect(configuredPath: URL?) async -> NpmDetectionState
}

/// Directory listing, as the one question the per-Node-version managers need.
///
/// Separate from `ExecutableProbing` rather than a sixth method on it: that
/// protocol answers questions about *one path a caller already names*, and every
/// existing conformer and fake is built on that. nvm and mise install under a
/// directory *per Node version*, so choosing between them means asking what is
/// there — a different question, and one no brew code path has ever needed.
public protocol DirectoryEnumerating: Sendable {
    /// The immediate subdirectories of `url`, or an empty array when it cannot
    /// be listed. A missing directory is an ordinary answer, never an error:
    /// most Macs have no `~/.nvm` at all.
    func subdirectories(of url: URL) -> [URL]
}

/// The production enumerator, backed by `FileManager`.
public struct DefaultDirectoryEnumerator: DirectoryEnumerating {
    public init() {}

    public func subdirectories(of url: URL) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return (contents ?? []).filter { child in
            (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}
