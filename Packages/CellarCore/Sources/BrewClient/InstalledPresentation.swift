import BrewProcess
import Foundation

extension InstalledInventoryError {
    /// One line a consumer can render without inspecting acquisition internals,
    /// mirroring `CatalogSyncError.shortDescription`.
    public var shortDescription: String {
        switch self {
        case .brewUnavailable:
            "brew could not be run."
        case .commandFailed(let status, let message):
            // brew's own words whenever it produced any: "the command failed"
            // tells the user nothing they can act on.
            message.isEmpty ? "brew exited with status \(status)." : message
        case .malformedPayload:
            "brew returned something Cellar could not read."
        case .cancelled:
            "The refresh was cancelled."
        }
    }
}

extension BrewValidationError {
    /// Why a configured path was rejected, as a sentence fragment.
    public var shortDescription: String {
        switch self {
        case .notExecutable:
            "it is not an executable file"
        case .notHomebrew:
            "it does not report itself as Homebrew"
        case .versionTooOld(let found, let minimum):
            "Homebrew \(found.triple) is older than the supported \(minimum.triple)"
        case .probeFailed(_, let message):
            message
        }
    }
}

extension BrewVersion {
    /// `6.0.14`, for putting a version in a sentence.
    public var triple: String { "\(major).\(minor).\(patch)" }
}

extension InstalledAbsence {
    /// The headline for the empty state. Three situations, three headlines: a
    /// user who configured a path needs to know *that path* is the problem.
    public var title: String {
        switch self {
        case .notInstalled: "Homebrew is not installed"
        case .configuredPathRejected: "That brew cannot be used"
        case .configuredPathMissing: "The configured brew is gone"
        }
    }

    /// The sentence under it.
    public var explanation: String {
        switch self {
        case .notInstalled:
            """
            Cellar reads what you have installed by asking brew. \
            Browsing the catalog works without it.
            """
        case .configuredPathRejected(let url, let reason):
            "\(url.path): \(reason.shortDescription)."
        case .configuredPathMissing(let url):
            """
            There is nothing at \(url.path) any more. \
            Point Cellar somewhere else, or install Homebrew.
            """
        }
    }
}
