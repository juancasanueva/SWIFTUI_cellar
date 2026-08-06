//
//  SecurityScopeArrangement.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import Testing

@testable import cellar

/// The Homebrew tree both scope suites arrange over.
///
/// One builder rather than two, so the formula suite and the cask suite cannot
/// drift into testing differently-shaped filesystems — the
/// `SecurityPresentationArrangement` discipline, applied after the cask half was
/// split out.
nonisolated enum SecurityScopeArrangement {
    static func keg(_ version: String) -> InstalledKeg {
        InstalledKeg(version: version, installedAt: Date(timeIntervalSince1970: 0), installedOnRequest: true)
    }

    static func package(
        _ name: String,
        kind: PackageKind = .formula,
        version: String = "1.0.0",
        otherKegs: [String] = [],
        linked: String? = nil
    ) -> InstalledPackage {
        InstalledPackage(
            kind: kind,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            tap: "homebrew/core",
            catalogVersion: version,
            kegs: ([version] + otherKegs).map(Self.keg),
            primaryKeg: keg(linked ?? version),
            snapshotOutdated: false,
            isPinned: false,
            pinnedVersion: nil,
            declaresAutoUpdates: nil,
            linkedKeg: linked
        )
    }

    /// Installs a cask the way Homebrew does: the bundle lives outside the
    /// Caskroom, and the Caskroom version directory holds a **symlink** to it.
    ///
    /// Verified against this machine during the U3 probe — nine of ten installed
    /// casks are exactly this shape. Returns the real bundle's URL.
    @discardableResult
    static func installCask(
        _ token: String,
        _ bundleName: String,
        version: String,
        in roots: TestRoots
    ) throws -> URL {
        let bundle = roots.prefix
            .appendingPathComponent("Applications")
            .appendingPathComponent("\(version)-\(bundleName)")
        try makeBundle(at: bundle)

        let versionDirectory = roots.caskroom
            .appendingPathComponent(token)
            .appendingPathComponent(version)
        try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: versionDirectory.appendingPathComponent(bundleName),
            withDestinationURL: bundle
        )
        return bundle
    }

    static func makeBundle(at url: URL) throws {
        let macOS = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data([0xcf, 0xfa, 0xed, 0xfe] + Array(repeating: 0, count: 60))
            .write(to: macOS.appendingPathComponent(url.deletingPathExtension().lastPathComponent))
    }

    /// The two roots the locator needs.
    ///
    /// `HomebrewRoots` publishes no memberwise initialiser, and the locator needs
    /// exactly two of its four URLs — so the seam takes the two rather than the
    /// whole value. That also keeps the locator honest: it is *given* the roots it
    /// may enumerate and cannot reach for a third.
    struct TestRoots {
        let prefix: URL
        let cellar: URL
        let caskroom: URL
    }

    static func locator(_ roots: TestRoots, _ fileSystem: RecordingFileSystem) -> ArtifactLocator {
        ArtifactLocator(cellar: roots.cellar, caskroom: roots.caskroom, fileSystem: fileSystem)
    }

    static func withHomebrewTree(
        _ body: (TestRoots, RecordingFileSystem) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("brew-\(UUID().uuidString)")
        let roots = TestRoots(
            prefix: root,
            cellar: root.appendingPathComponent("Cellar"),
            caskroom: root.appendingPathComponent("Caskroom")
        )
        for url in [roots.cellar, roots.caskroom] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        // A keg with a real executable in bin/, plus the directories the locator
        // must decline to walk.
        for relative in ["bat/1.0.0/bin", "bat/1.0.0/sbin", "bat/1.0.0/include",
                         "bat/1.0.0/share/man/man1", "bat/0.9.0/bin"] {
            try FileManager.default.createDirectory(
                at: roots.cellar.appendingPathComponent(relative),
                withIntermediateDirectories: true
            )
        }
        try Data([0xcf, 0xfa, 0xed, 0xfe] + Array(repeating: 0, count: 60))
            .write(to: roots.cellar.appendingPathComponent("bat/1.0.0/bin/bat"))
        try Data([0xcf, 0xfa, 0xed, 0xfe] + Array(repeating: 0, count: 60))
            .write(to: roots.cellar.appendingPathComponent("bat/0.9.0/bin/bat"))

        try body(roots, RecordingFileSystem())
    }
}
