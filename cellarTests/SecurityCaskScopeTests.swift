//
//  SecurityCaskScopeTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import SecurityKit
import Testing

@testable import cellar

/// Where cask artifacts come from.
///
/// Split from `SecurityArtifactScopeTests` after the MV-7 / MV-9 defect, which is
/// the honest reason: the cask half grew from two tests to eight because two live
/// manual checks found it broken, and the formula half did not move at all. One
/// file made that impossible to see in a diff.
@Suite("Security cask scope")
struct SecurityCaskScopeTests {
    private typealias Arranged = SecurityScopeArrangement

    private static func locator(
        _ roots: SecurityScopeArrangement.TestRoots,
        _ fileSystem: RecordingFileSystem
    ) -> ArtifactLocator {
        ArtifactLocator(cellar: roots.cellar, caskroom: roots.caskroom, fileSystem: fileSystem)
    }

    private static func package(
        _ name: String,
        kind: PackageKind = .cask,
        version: String = "1.0.0"
    ) -> InstalledPackage {
        Arranged.package(name, kind: kind, version: version)
    }

    private static func installCask(
        _ token: String,
        _ bundleName: String,
        version: String,
        in roots: SecurityScopeArrangement.TestRoots
    ) throws -> URL {
        try Arranged.installCask(token, bundleName, version: version, in: roots)
    }

    private static func makeBundle(at url: URL) throws { try Arranged.makeBundle(at: url) }

    private func withHomebrewTree(
        _ body: (SecurityScopeArrangement.TestRoots, RecordingFileSystem) throws -> Void
    ) throws {
        try Arranged.withHomebrewTree(body)
    }

    /// The obs 7454(1) carry-forward, **corrected**.
    ///
    /// Nine of ten Caskroom `.app` entries on this machine are symlinks into
    /// `/Applications`, and the tenth is a stale directory macOS rejects. The
    /// original reading of that — "a Caskroom-only walk finds nothing usable" —
    /// was wrong and shipped the MV-7 / MV-9 defect: the walk finds *symlinks*,
    /// and a symlink is the record brew wrote down, not an absence.
    ///
    /// This version therefore hands the locator nothing. The claim is that it
    /// finds the recorded artifact itself and reports the **resolved bundle**,
    /// not the Caskroom symlink. The original handed in the bundle path and
    /// proved it was resolved — which is precisely the shape that let the bug
    /// through, because the app never handed it anything.
    @Test("Cask artifacts resolve through the recorded Caskroom symlink to the real bundle")
    func caskArtifactsResolveThroughTheRecordedSymlinkToTheRealBundle() throws {
        try withHomebrewTree { roots, recorder in
            let bundle = try Self.installCask("ghostty", "Ghostty.app", version: "1.2.3", in: roots)
            let symlink = roots.caskroom.appendingPathComponent("ghostty/1.2.3/Ghostty.app")

            let located = Self.locator(roots, recorder).locations(
                for: [Self.package("ghostty", kind: .cask, version: "1.2.3")]
            )

            #expect(located.count == 1, "the brew-recorded artifact was not located")
            #expect(located.first?.url.path == bundle.path)
            #expect(located.first?.kind == .bundle)
            #expect(
                located.first?.url.path.hasPrefix(roots.caskroom.path) == false,
                "the symlink was reported rather than the bundle it points at"
            )
            // The Caskroom entry really is a symlink, or the resolution proves nothing.
            #expect(ArtifactAssessability.classify(symlink) == nil)
        }
    }

    /// **The MV-7 / MV-9 defect, reproduced.**
    ///
    /// Every cask test above hands the locator a path and then proves it resolves
    /// it. None of them asked the question the live app asks: *where does that
    /// path come from?* It came from nowhere — `cellarApp.swift` passed `[:]`, so
    /// `caskLocations` received an empty list for every cask and yielded nothing.
    /// The live sweep found 468 artifacts, all of them formula binaries, and not
    /// one cask. A seam with no supplier, and a suite that tested the seam.
    ///
    /// This test builds locations **the way the composition root builds them** —
    /// no handed-in paths — over a filesystem holding the real Caskroom shape.
    @Test("Building locations the way the app does yields cask locations")
    func buildingLocationsTheWayTheAppDoesYieldsCaskLocations() throws {
        try withHomebrewTree { roots, recorder in
            let bundle = try Self.installCask("ghostty", "Ghostty.app", version: "1.2.3", in: roots)
            let cask = Self.package("ghostty", kind: .cask, version: "1.2.3")

            let located = Self.locator(roots, recorder).locations(for: [cask])

            #expect(located.count == 1, "no cask artifact was located — MV-7 and MV-9 both fail here")
            #expect(located.first?.packageID.name == "ghostty")
            #expect(located.first?.kind == .bundle)
            #expect(
                located.first?.url.path == bundle.path,
                "the Caskroom symlink was reported rather than the bundle it points at"
            )
        }
    }

    /// Formulae and casks in one inventory, as the app always has them. The
    /// regression was invisible precisely because the formula half worked.
    @Test("A mixed inventory yields both formula and cask artifacts")
    func aMixedInventoryYieldsBothFormulaAndCaskArtifacts() throws {
        try withHomebrewTree { roots, recorder in
            _ = try Self.installCask("ghostty", "Ghostty.app", version: "1.2.3", in: roots)
            _ = try Self.installCask("applite", "Applite.app", version: "1.3.1", in: roots)

            let located = Self.locator(roots, recorder).locations(
                for: [
                    Self.package("bat", kind: .formula),
                    Self.package("ghostty", kind: .cask, version: "1.2.3"),
                    Self.package("applite", kind: .cask, version: "1.3.1")
                ]
            )

            #expect(located.filter { $0.packageID.kind == .cask }.count == 2)
            #expect(located.filter { $0.packageID.kind == .formula }.count == 1)
            #expect(Set(located.map(\.packageID.name)) == ["bat", "ghostty", "applite"])
        }
    }

    /// **MV-9's decoy, asserted rather than assumed.**
    ///
    /// A non-brew application sitting beside the brew-installed ones must never
    /// appear. It follows from the mechanism — it has no Caskroom entry pointing
    /// at it, and the Caskroom is the only place enumerated — but "it follows"
    /// is not a test, and this is the check a human ran by hand.
    @Test("A non-brew app beside the brew-installed ones never appears")
    func aNonBrewAppBesideTheBrewInstalledOnesNeverAppears() throws {
        try withHomebrewTree { roots, recorder in
            _ = try Self.installCask("ghostty", "Ghostty.app", version: "1.2.3", in: roots)
            // Same directory, same shape, no Caskroom entry: installed by hand.
            let decoy = roots.prefix.appendingPathComponent("Applications/NotFromBrew.app")
            try Self.makeBundle(at: decoy)

            let located = Self.locator(roots, recorder).locations(
                for: [Self.package("ghostty", kind: .cask, version: "1.2.3")]
            )

            #expect(located.count == 1, "the positive anchor failed, so the absence proves nothing")
            #expect(located.contains { $0.url.path == decoy.path } == false, "a non-brew app was swept")
            #expect(
                recorder.enumerated.contains { $0.hasPrefix(decoy.deletingLastPathComponent().path) } == false,
                "the applications directory was enumerated"
            )
        }
    }

    /// The version directory is the one brew recorded for the installed version,
    /// not "whatever is in the Caskroom". An older leftover must not be swept.
    @Test("Only the installed version's Caskroom directory is enumerated")
    func onlyTheInstalledVersionsCaskroomDirectoryIsEnumerated() throws {
        try withHomebrewTree { roots, recorder in
            let current = try Self.installCask("ghostty", "Ghostty.app", version: "1.2.3", in: roots)
            let stale = try Self.installCask("ghostty", "Ghostty.app", version: "1.0.0", in: roots)

            let located = Self.locator(roots, recorder).locations(
                for: [Self.package("ghostty", kind: .cask, version: "1.2.3")]
            )

            #expect(located.map(\.url.path) == [current.path])
            #expect(located.contains { $0.url.path == stale.path } == false)
            #expect(
                recorder.enumerated.contains { $0.hasSuffix("ghostty/1.0.0") } == false,
                "a version directory that is not installed was enumerated"
            )
        }
    }

    /// The no-fallback rule, restated against the real mechanism: a version
    /// directory holding no `.app` yields nothing, and nothing is substituted
    /// from a neighbouring version.
    @Test("A cask whose version directory holds no app produces nothing")
    func aCaskWhoseVersionDirectoryHoldsNoAppProducesNothing() throws {
        try withHomebrewTree { roots, recorder in
            // Metadata only, which is what an incomplete install leaves behind.
            let versionDirectory = roots.caskroom.appendingPathComponent("ghostty/1.2.3")
            try FileManager.default.createDirectory(at: versionDirectory, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: versionDirectory.appendingPathComponent("config.json"))
            // A different version *is* fully installed, and must not be substituted.
            _ = try Self.installCask("ghostty", "Ghostty.app", version: "9.9.9", in: roots)

            let located = Self.locator(roots, recorder).locations(
                for: [Self.package("ghostty", kind: .cask, version: "1.2.3")]
            )

            #expect(located.isEmpty, "a cask with no app artifact was located anyway")
        }
    }

    /// The one real cask on this machine that yields nothing, pinned so the gap is
    /// documented rather than surprising.
    ///
    /// `the-unarchiver` leaves a Caskroom entry that is a **real directory**, not
    /// a symlink, holding a second nested `The Unarchiver.app` — and the outer one
    /// has no `Contents/MacOS`. `SecStaticCodeCreateWithPath` rejects it outright
    /// with `-67028 bundle format unrecognized`, measured during the U3 probe, so
    /// there is nothing here that could honestly be assessed. Nine of ten casks
    /// resolve; this is the tenth, and it is a gap rather than a defect.
    @Test("A stale Caskroom directory shell yields nothing rather than an unassessable entry")
    func aStaleCaskroomDirectoryShellYieldsNothing() throws {
        try withHomebrewTree { roots, recorder in
            let outer = roots.caskroom
                .appendingPathComponent("the-unarchiver/4.3.9,147,1742287964/The Unarchiver.app")
            // A directory named `.app` whose only content is another `.app`.
            try Self.makeBundle(at: outer.appendingPathComponent("The Unarchiver.app"))

            let located = Self.locator(roots, recorder).locations(
                for: [Self.package("the-unarchiver", kind: .cask, version: "4.3.9,147,1742287964")]
            )

            #expect(located.isEmpty, "an unassessable Caskroom shell was reported as an artifact")
        }
    }

    /// A cask brew reports whose Caskroom directory is absent entirely — what a
    /// half-removed cask leaves. No crash, no guess, no entry.
    @Test("A cask with no Caskroom directory at all produces nothing")
    func aCaskWithNoCaskroomDirectoryProducesNothing() throws {
        try withHomebrewTree { roots, recorder in
            let located = Self.locator(roots, recorder).locations(
                for: [Self.package("vanished", kind: .cask, version: "1.0.0")]
            )

            #expect(located.isEmpty)
        }
    }
}
