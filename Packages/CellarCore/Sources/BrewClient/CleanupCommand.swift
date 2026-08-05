import BrewProcess
import Catalog
import DiskUsage

/// The exact preview and mutation command pair for one cleanup scope.
///
/// Both projections are argv vectors. Package payloads come only from
/// `PackageTarget`, display text is never parsed, and no shell is involved.
public struct CleanupCommand: BrewMutating, Sendable, Equatable {
    public let scope: CleanupScope

    public init(scope: CleanupScope) {
        self.scope = scope
    }

    /// Builds package cleanup only after the shared argv-name gate accepts it.
    public static func package(kind: PackageKind, name: String) -> CleanupCommand? {
        guard MutationName.isSafe(name), let scope = CleanupScope.package(kind: kind, name: name) else {
            return nil
        }
        return CleanupCommand(scope: scope)
    }

    /// Validates a raw package request while retaining a presentable rejection.
    public static func validatingPackage(
        kind: PackageKind,
        name: String
    ) -> Result<CleanupCommand, CleanupTargetRejection> {
        guard let command = package(kind: kind, name: name) else {
            return .failure(.invalidPackageName)
        }
        return .success(command)
    }

    /// The read-only dry-run command paired with this mutation.
    public var previewCommand: BrewCommand {
        .read(previewArguments, environmentOverrides: environmentOverrides)
    }

    /// Typed command-local policy shared by preview and mutation.
    public var environmentOverrides: Set<BrewEnvironment.CommandOverride> {
        switch scope {
        case .global, .package, .full: [.noAutoremove]
        case .autoremove: []
        }
    }

    /// The argv vector for the mutation, excluding the `brew` executable.
    public var arguments: [String] {
        switch scope {
        case .global: ["cleanup"]
        case .package(let target): ["cleanup", target.name]
        case .full: ["cleanup", "--prune=all"]
        case .autoremove: ["autoremove"]
        }
    }

    /// The mutation command with this scope's local environment policy.
    public var brewCommand: BrewCommand {
        .mutate(arguments, environmentOverrides: environmentOverrides)
    }

    public var verb: String {
        switch scope {
        case .global: "cleanupGlobal"
        case .package: "cleanupPackage"
        case .full: "cleanupFull"
        case .autoremove: "cleanupAutoremove"
        }
    }

    public var packageID: PackageID? {
        guard case .package(let target) = scope else { return nil }
        return target.id
    }

    public var requiresConfirmation: Bool { true }

    public var invalidates: InvalidationScope { [.installedInventory, .diskUsage] }

    public var diskAreas: Set<DiskArea> {
        switch scope {
        case .global, .full: [.cellar, .caskroom, .cache]
        case .package(let target):
            target.kind == .formula ? [.cellar, .cache] : [.caskroom, .cache]
        case .autoremove: [.cellar]
        }
    }

    private var previewArguments: [String] {
        switch scope {
        case .global: ["cleanup", "--dry-run"]
        case .package(let target): ["cleanup", "--dry-run", target.name]
        case .full: ["cleanup", "--dry-run", "--prune=all"]
        case .autoremove: ["autoremove", "--dry-run"]
        }
    }
}
