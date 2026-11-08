//
//  CaskInstalledApp.swift
//  cellar
//

import Foundation

/// Where an installed cask's app lives, read from the link Homebrew wrote
/// when it installed it — `ArtifactLocator`'s cask rule, for one token.
///
/// Needs no catalog record, so a third-party tap's cask resolves exactly like
/// a `homebrew/cask` one. Only `Caskroom/<token>/<installed version>` is
/// listed; `/Applications` is never enumerated.
nonisolated enum CaskInstalledApp {
    /// The first `.app` entry in the installed version's Caskroom directory,
    /// resolved through its symlink — or `nil` when there is none, or when the
    /// app it points at no longer exists.
    static func url(
        token: String,
        version: String,
        caskroom: URL,
        fileSystem: any ArtifactFileSystem = SystemArtifactFileSystem()
    ) -> URL? {
        let versionDirectory = caskroom
            .appendingPathComponent(token)
            .appendingPathComponent(version)
        return fileSystem.contentsOfDirectory(at: versionDirectory)
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { $0.resolvingSymlinksInPath() }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
