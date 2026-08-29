import Foundation
import SwiftData

/// Where the local metadata store lives, and how it is opened (design D3, D4).
///
/// Both factories build the container the same way — `Schema(versionedSchema:)`
/// plus `MetadataMigrationPlan` — so the in-memory container a test opens and
/// the on-disk one the app opens are the *same* container in every respect that
/// could differ, including migration behaviour.
public enum PersistenceContainer {
    /// The shipped location, alongside the existing `…/<bundleID>/Catalog/`
    /// directory (the `CatalogStore.defaultDirectory()` precedent).
    public static func defaultDirectory(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.juancasanueva.cellar"
    ) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Metadata", isDirectory: true)
    }

    public static func defaultURL(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.juancasanueva.cellar"
    ) -> URL {
        defaultDirectory(bundleIdentifier: bundleIdentifier)
            .appendingPathComponent("Metadata.store", isDirectory: false)
    }

    /// A container backed by a file at `url`.
    ///
    /// Creates the enclosing directory first: SwiftData will not make one, and
    /// on a first launch there is nothing there yet. A failure to create it
    /// throws here, which is exactly what `MetadataStore` folds into
    /// `.unavailable(reason:)` rather than letting it become a boot loop (D4).
    public static func onDisk(at url: URL = defaultURL()) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try container(ModelConfiguration(url: url))
    }

    /// A container that never touches the disk. Tests and previews.
    public static func inMemory() throws -> ModelContainer {
        try container(ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private static func container(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: SchemaV3.self),
            migrationPlan: MetadataMigrationPlan.self,
            configurations: configuration
        )
    }
}

/// What a store is currently able to do.
///
/// The same shape as `InstalledAbsence`/`CatalogStore`: a degraded store is a
/// *state* the UI renders, never a crash and never a thrown error reaching an
/// unrelated path. A corrupt or unwritable store costs local metadata and
/// nothing else — the app still browses, installs and upgrades
/// (local-package-metadata LPM6, design D4).
public enum StoreAvailability: Sendable, Equatable {
    case available
    /// Carries the reason, because an affordance that is disabled without one
    /// is indistinguishable from an affordance that is broken.
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }

    public var reason: String? {
        guard case .unavailable(let reason) = self else { return nil }
        return reason
    }
}
