//
//  UpdatePackageManifestTests.swift
//  cellarTests
//

import Foundation
import Testing

/// Reads `Packages/CellarCore/Package.swift` as text.
///
/// Textual by necessity: a claim about what a manifest does **not** declare
/// cannot be made by importing the package it describes. Self-contained, like
/// the other update suites, so the slice rolls back by deleting its own files.
nonisolated enum UpdateManifestSources {
    static let manifest = "Packages/CellarCore/Package.swift"

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static func manifestText() throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(manifest), encoding: .utf8)
    }

    /// Every `.target(…)` / `.library(…)` / `.testTarget(…)` body, cut at its own
    /// balanced closing parenthesis.
    ///
    /// Balanced rather than "up to the next `)`" because every declaration in
    /// this manifest nests at least one — `swiftSettings: [.swiftLanguageMode(.v6)]`
    /// alone would truncate a naive cut and make an absence assertion pass for
    /// the wrong reason.
    ///
    /// The opening is anchored on the newline and the manifest's eight-space
    /// indentation, which is what keeps `.target(` from also matching the
    /// `.testTarget(` that sits beside it.
    static func declarations(of kind: String, in manifest: String) -> [String] {
        let opening = "\n        .\(kind)("
        var bodies: [String] = []
        var searchStart = manifest.startIndex

        while let found = manifest.range(of: opening, range: searchStart..<manifest.endIndex) {
            var depth = 1
            var index = found.upperBound
            while index < manifest.endIndex, depth > 0 {
                if manifest[index] == "(" { depth += 1 }
                if manifest[index] == ")" { depth -= 1 }
                if depth > 0 { index = manifest.index(after: index) }
            }
            bodies.append(String(manifest[found.upperBound..<index]))
            searchStart = index
        }
        return bodies
    }

    static func declaration(of kind: String, named name: String, in manifest: String) throws -> String {
        let matches = declarations(of: kind, in: manifest).filter { $0.contains("name: \"\(name)\"") }
        #expect(matches.count == 1)
        return try #require(matches.first)
    }
}

/// T24: the update module reaches nothing, and the build graph says so.
///
/// This is the compile-time isolation DD-1 is entirely built on, so it is pinned
/// rather than trusted. "The updater cannot reach Homebrew, the package catalog
/// or persisted app data" is only a fact while the target declares no
/// dependencies; the moment someone adds one for convenience it becomes a review
/// comment nobody makes.
@Suite("Update package manifest")
struct UpdatePackageManifestTests {
    // MARK: - T24 — the Updates target declares no dependencies at all

    /// The absence of a `dependencies:` key, not an empty one.
    ///
    /// `dependencies: []` would be equally isolated today and would read as an
    /// invitation tomorrow. The manifest's own doc comment says the absence *is*
    /// the guarantee, and this asserts exactly that.
    @Test("The Updates target declares no dependencies")
    func updatesTargetDeclaresNoDependencies() throws {
        let manifest = try UpdateManifestSources.manifestText()
        let updates = try UpdateManifestSources.declaration(of: "target", named: "Updates", in: manifest)

        #expect(!updates.contains("dependencies:"))
        #expect(updates.contains("swiftSettings: [.swiftLanguageMode(.v6)]"))

        // The absence is only meaningful if the same reader can see a
        // `dependencies:` key where one genuinely exists.
        let releaseNotes = try UpdateManifestSources.declaration(
            of: "target",
            named: "ReleaseNotes",
            in: manifest
        )
        #expect(releaseNotes.contains("dependencies: [\"Catalog\"]"))
    }

    /// The product exists and exposes the target, so the app can link it.
    ///
    /// DD-1's isolation is only useful if the app can actually reach the module.
    /// Six of the seven existing products are linked explicitly and `SecurityKit`
    /// reaches the app transitively through `Persistence`; a dependency-free
    /// `Updates` has no such path, which is why it needs its own library.
    @Test("The Updates library exposes exactly the Updates target")
    func updatesLibraryExposesTheUpdatesTarget() throws {
        let manifest = try UpdateManifestSources.manifestText()
        let library = try UpdateManifestSources.declaration(of: "library", named: "Updates", in: manifest)

        #expect(library.contains("targets: [\"Updates\"]"))
    }
}
