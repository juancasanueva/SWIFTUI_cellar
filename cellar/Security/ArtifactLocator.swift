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
/// **Casks**: the `.app` entries in the Caskroom directory for the **installed
/// version**, resolved through the symlinks Homebrew put there.
///
/// The U3 probe measured that nine of ten Caskroom `.app` entries on this machine
/// are symlinks into `/Applications`, and the tenth is a stale directory macOS
/// rejects. An earlier version of this comment concluded from that "a Caskroom
/// walk finds nothing usable" — **which was wrong, and shipped a real defect.**
/// The walk finds *symlinks*, and a symlink is not nothing: it is precisely the
/// record Homebrew wrote down when it installed the cask, and resolving it is one
/// line. Believing the comment, the composition root passed an empty dictionary
/// and the live sweep reported 468 formula binaries and **zero casks**, which is
/// how MV-7 and MV-9 caught it.
///
/// This is still not an `/Applications` sweep, and the distinction is exact: the
/// only directory listed is `Caskroom/<token>/<installed version>`. The bundle is
/// reached by *resolving a link found there*, never by enumerating the directory
/// it happens to live in. A non-brew application has no Caskroom entry pointing at
/// it and is therefore unreachable, which is MV-9's decoy guarantee.
///
/// A cask whose version directory holds no `.app` yields nothing — there is
/// deliberately no fallback that goes looking somewhere else.
nonisolated struct ArtifactLocator {
    let cellar: URL
    let caskroom: URL
    let fileSystem: any ArtifactFileSystem

    init(cellar: URL, caskroom: URL, fileSystem: any ArtifactFileSystem = SystemArtifactFileSystem()) {
        self.cellar = cellar
        self.caskroom = caskroom
        self.fileSystem = fileSystem
    }

    /// Everything worth assessing, for the whole inventory.
    ///
    /// There is deliberately **no parameter for cask artifacts**. The previous
    /// signature took one, and nothing ever supplied it: `cellarApp` passed `[:]`
    /// and every cask silently produced nothing. A seam whose only supplier is a
    /// test is not a seam, it is a hole — so the locator now discovers what it
    /// needs from the roots it was given, and the failure mode cannot recur by
    /// omission.
    func locations(for inventory: [InstalledPackage]) -> [ArtifactLocation] {
        inventory.flatMap { package in
            switch package.kind {
            case .formula: formulaLocations(for: package)
            case .cask: caskLocations(for: package)
            // Nothing to assess, and deliberately so. Both branches above read a
            // Homebrew tree — `Cellar/<name>/<version>/bin` and
            // `Caskroom/<token>/<version>` — that an npm global has no entry in.
            // A `default:` would have sent every npm package down the formula
            // path, where `Cellar/typescript/…` may well exist and belong to a
            // *different* package of the same name. Artifact integrity is not
            // extended to npm in this change; producing no location is the
            // honest report of that, not a gap (design D2).
            case .npm: [ArtifactLocation]()
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

    /// The `.app` entries Homebrew recorded for this cask's installed version.
    ///
    /// One directory listing, at `Caskroom/<token>/<installed version>`. The
    /// version comes from `primaryKeg.version`, which for a cask is brew's own
    /// `installed` field — verified against this machine to match the Caskroom
    /// directory name exactly, including the comma-laden
    /// `the-unarchiver 4.3.9,147,1742287964`. A version brew reports that has no
    /// matching directory yields nothing rather than a guess at a neighbour.
    private func caskLocations(for package: InstalledPackage) -> [ArtifactLocation] {
        let versionDirectory = caskroom
            .appendingPathComponent(package.name)
            .appendingPathComponent(package.primaryKeg.version)

        return fileSystem.contentsOfDirectory(at: versionDirectory)
            .filter { $0.pathExtension == "app" }
            // Resolved **once**, here, against the link brew wrote — which is why
            // `ArtifactAssessability` can refuse symlinks outright. Doing it
            // implicitly inside the predicate would turn an explicit step into an
            // invisible one and quietly widen what gets visited.
            .map { $0.resolvingSymlinksInPath() }
            .compactMap { ArtifactLocation(packageID: package.id, url: $0) }
    }
}
