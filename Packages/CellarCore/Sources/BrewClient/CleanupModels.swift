import Catalog

/// A cleanup boundary whose package payload, when present, has already passed
/// the shared mutation-name gate.
public enum CleanupScope: Sendable, Hashable {
    /// Homebrew's normal cleanup policy across the installation.
    case global
    /// Cleanup limited to one validated formula or cask identity.
    case package(PackageTarget)
    /// Cleanup of all cached downloads regardless of age.
    case full
    /// Removal of formulae that are no longer required dependencies.
    case autoremove

    /// Returns package cleanup only when `name` is safe as one argv element.
    public static func package(kind: PackageKind, name: String) -> CleanupScope? {
        PackageTarget(kind: kind, name: name).map(Self.package)
    }
}

/// Why a raw package request could not become a cleanup command.
public enum CleanupTargetRejection: Error, Sendable, Equatable {
    /// The package name was empty, option-looking, or contained whitespace.
    case invalidPackageName

    /// Read-only guidance suitable for presenting beside a disabled action.
    public var guidance: String {
        switch self {
        case .invalidPackageName:
            "Choose a Homebrew package with a non-empty name that contains no whitespace and does not begin with '-'."
        }
    }
}
