//
//  ArtifactLocator.swift
//  cellar
//

import BrewClient
import Catalog
import Foundation
import SecurityKit

/// The one directory-listing operation the locator performs.
///
/// A seam, so "`/Applications` was never enumerated" is a *recorded* fact in the
/// tests rather than a claim about code somebody read. An absence nothing counted
/// is an absence nothing proved.
nonisolated protocol ArtifactFileSystem: Sendable {
    func contentsOfDirectory(at url: URL) -> [URL]
}

nonisolated struct SystemArtifactFileSystem: ArtifactFileSystem {
    func contentsOfDirectory(at url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

/// Builds the list of artifacts worth assessing, from Homebrew's own roots only.
///
/// The second composition point, in the app target for the same reason as the
/// first: it needs `HomebrewRoots` from `DiskUsage` and `InstalledPackage` from
/// `BrewClient` *and* must emit `SecurityKit` values, and no CellarCore target
/// sees all three.
///
/// ## Two scopes, both bounded
///
/// **Formulae**: the primary keg's `bin/` and `sbin/`, and nothing else. Not
/// `include/`, not `share/man/`, not `lib/`, and not the non-primary kegs — a
/// whole-keg walk is unbounded and dominated by headers and manual pages that
/// carry no signature.
///
/// **Casks**: the path **Homebrew itself recorded**, resolved. This is the obs
/// 7454(1) carry-forward and it is not an `/Applications` sweep: the U3 probe
/// measured that nine of ten Caskroom `.app` entries on this machine are symlinks
/// into `/Applications` and the tenth is a stale directory macOS rejects outright,
/// so a Caskroom walk finds nothing usable. A cask with no recorded artifact
/// yields nothing — there is deliberately no fallback that goes looking.
nonisolated struct ArtifactLocator {
    let cellar: URL
    let caskroom: URL
    let fileSystem: any ArtifactFileSystem

    init(cellar: URL, caskroom: URL, fileSystem: any ArtifactFileSystem = SystemArtifactFileSystem()) {
        self.cellar = cellar
        self.caskroom = caskroom
        self.fileSystem = fileSystem
    }

    /// - Parameter caskArtifacts: the `app` artifact targets Homebrew recorded,
    ///   per cask. Passed in rather than discovered, because discovering them
    ///   means asking brew and this type does not run commands.
    func locations(
        for inventory: [InstalledPackage],
        caskArtifacts: [PackageID: [URL]]
    ) -> [ArtifactLocation] {
        inventory.flatMap { package in
            switch package.kind {
            case .formula: formulaLocations(for: package)
            case .cask: caskLocations(for: package, recorded: caskArtifacts[package.id] ?? [])
            }
        }
    }

    // MARK: - Formulae

    private func formulaLocations(for package: InstalledPackage) -> [ArtifactLocation] {
        let keg = cellar
            .appendingPathComponent(package.name)
            .appendingPathComponent(package.primaryKeg.version)

        return ["bin", "sbin"]
            .map(keg.appendingPathComponent)
            .flatMap(fileSystem.contentsOfDirectory)
            // Every candidate goes through the predicate, including the symlinks
            // a keg's `bin/` is full of. Nothing reaches the engine unclassified.
            .compactMap { ArtifactLocation(packageID: package.id, url: $0) }
    }

    // MARK: - Casks

    private func caskLocations(
        for package: InstalledPackage,
        recorded: [URL]
    ) -> [ArtifactLocation] {
        recorded
            // Resolved **once**, here, against the path brew recorded — which is
            // why `ArtifactAssessability` can refuse symlinks outright. Doing it
            // implicitly inside the predicate would turn an explicit step into an
            // invisible one and quietly widen what gets visited.
            .map { $0.resolvingSymlinksInPath() }
            .compactMap { ArtifactLocation(packageID: package.id, url: $0) }
    }
}
