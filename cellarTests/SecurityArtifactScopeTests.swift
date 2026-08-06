//
//  SecurityArtifactScopeTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import SecurityKit
import Testing

@testable import cellar

/// Artifact scope and refresh cadence.
///
/// Split from `SecurityCompositionTests`, which crossed the 400-line rule. The
/// split is along a real seam: that suite is about turning an inventory into
/// *questions*, and this one is about turning it into *files* and deciding when
/// to look at them.
@Suite("Security artifact scope")
struct SecurityArtifactScopeTests {
    private static func keg(_ version: String) -> InstalledKeg {
        InstalledKeg(version: version, installedAt: Date(timeIntervalSince1970: 0), installedOnRequest: true)
    }

    private static func package(
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

    // MARK: - 15.3 Artifact scope

    @Test("Only brew-managed locations are enumerated")
    func onlyBrewManagedLocationsAreEnumerated() throws {
        try withHomebrewTree { roots, recorder in
            let mapped = Self.package("bat")
            _ = Self.locator(roots, recorder).locations(for: [mapped], caskArtifacts: [:])

            #expect(recorder.enumerated.isEmpty == false, "nothing was enumerated at all")
            for path in recorder.enumerated {
                #expect(
                    path.hasPrefix(roots.cellar.path) || path.hasPrefix(roots.caskroom.path),
                    "\(path) is outside Homebrew's own roots"
                )
                #expect(path.hasPrefix("/Applications") == false, "/Applications was enumerated")
            }
        }
    }

    @Test("Formula scope is the primary keg's bin and sbin only")
    func formulaScopeIsThePrimaryKegsBinAndSbinOnly() throws {
        try withHomebrewTree { roots, recorder in
            let package = Self.package("bat", version: "1.0.0", otherKegs: ["0.9.0"])
            let located = Self.locator(roots, recorder).locations(for: [package], caskArtifacts: [:])

            #expect(located.isEmpty == false, "the keg produced no artifacts at all")
            for path in recorder.enumerated {
                let tail = path.dropFirst(roots.cellar.path.count)
                #expect(
                    tail.hasSuffix("/bin") || tail.hasSuffix("/sbin"),
                    "\(path) is neither bin nor sbin"
                )
                #expect(tail.contains("/0.9.0/") == false, "a non-primary keg was walked")
            }
            for forbidden in ["include", "share/man", "lib", "etc"] {
                #expect(
                    recorder.enumerated.contains { $0.contains("/\(forbidden)") } == false,
                    "\(forbidden) was walked"
                )
            }
        }
    }

    /// The obs 7454(1) carry-forward, driven by the task 14.0 fixture: nine of ten
    /// Caskroom `.app` entries on this machine are **symlinks into
    /// `/Applications`**, and the tenth is a stale directory macOS rejects. A
    /// Caskroom-only walk finds nothing usable, so the locator resolves the path
    /// **brew itself recorded** — which is not an `/Applications` sweep, because
    /// only paths Homebrew named are ever visited.
    @Test("Cask artifacts resolve through brew-recorded paths and not a literal Caskroom walk")
    func caskArtifactsResolveThroughBrewRecordedPathsAndNotALiteralCaskroomWalk() throws {
        try withHomebrewTree { roots, recorder in
            // The real shape: a Caskroom symlink whose target is the actual bundle.
            let real = roots.prefix.appendingPathComponent("Applications/Ghostty.app")
            try Self.makeBundle(at: real)
            let caskroomEntry = roots.caskroom.appendingPathComponent("ghostty/1.2.3/Ghostty.app")
            try FileManager.default.createDirectory(
                at: caskroomEntry.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: caskroomEntry, withDestinationURL: real)

            let cask = Self.package("ghostty", kind: .cask, version: "1.2.3")
            let located = Self.locator(roots, recorder)
                .locations(for: [cask], caskArtifacts: [cask.id: [real]])

            #expect(located.count == 1, "the brew-recorded artifact was not located")
            #expect(located.first?.url.path == real.path)
            #expect(located.first?.kind == .bundle)
            #expect(
                located.first?.url.path.hasPrefix(roots.caskroom.path) == false,
                "the symlink was reported rather than the bundle it points at"
            )
        }
    }

    /// The negative: a cask whose recorded artifact list is empty produces
    /// nothing, and does **not** fall back to walking the Caskroom.
    @Test("A cask with no recorded artifact produces nothing rather than a Caskroom guess")
    func aCaskWithNoRecordedArtifactProducesNothing() throws {
        try withHomebrewTree { roots, recorder in
            let caskroomEntry = roots.caskroom.appendingPathComponent("ghostty/1.2.3/Ghostty.app")
            try Self.makeBundle(at: caskroomEntry)

            let cask = Self.package("ghostty", kind: .cask, version: "1.2.3")
            let located = Self.locator(roots, recorder).locations(for: [cask], caskArtifacts: [:])

            #expect(located.isEmpty, "an unrecorded Caskroom bundle was located anyway")
        }
    }

    // MARK: - 15.4 Everything is filtered

    @Test("Every candidate is filtered through artifact assessability")
    func everyCandidateIsFilteredThroughArtifactAssessability() throws {
        try withHomebrewTree { roots, recorder in
            let bin = roots.cellar.appendingPathComponent("bat/1.0.0/bin")
            // One real Mach-O, and four things the predicate must reject.
            try Data("#!/bin/sh\n".utf8).write(to: bin.appendingPathComponent("wrapper.sh"))
            try Data(".TH RG 1\n".utf8).write(to: bin.appendingPathComponent("rg.1"))
            try Data("MIT\n".utf8).write(to: bin.appendingPathComponent("LICENSE"))
            try FileManager.default.createSymbolicLink(
                at: bin.appendingPathComponent("link"),
                withDestinationURL: bin.appendingPathComponent("bat")
            )

            let located = Self.locator(roots, recorder)
                .locations(for: [Self.package("bat")], caskArtifacts: [:])

            #expect(located.map(\.url.lastPathComponent) == ["bat"], "something unassessable got through")
            #expect(located.allSatisfy { ArtifactAssessability.classify($0.url) != nil })
        }
    }

    // MARK: - 15.6 Cadence

    @Test("A daily schedule and a post-mutation trigger each cause exactly one scan")
    func aDailyScheduleAndAPostMutationTriggerEachCauseExactlyOneScan() async {
        let scanner = RecordingSecurityScanner()
        let coordinator = SecurityRefreshCoordinator(
            scan: { await scanner.record() },
            isConsented: { true }
        )

        await coordinator.refreshIfNeeded()
        #expect(await scanner.count == 1, "the scheduled refresh did not scan")

        await coordinator.mutationCompleted()
        #expect(await scanner.count == 2, "the post-mutation trigger did not scan")
    }

    @Test("Neither fires while consent is off")
    func neitherFiresWhileConsentIsOff() async {
        let scanner = RecordingSecurityScanner()
        let coordinator = SecurityRefreshCoordinator(
            scan: { await scanner.record() },
            isConsented: { false }
        )

        await coordinator.refreshIfNeeded()
        await coordinator.mutationCompleted()

        #expect(await scanner.count == 0, "a scan ran with consent off")
    }

    /// Revocation takes effect on the very next trigger, not at the next launch.
    /// The consent answer is read per trigger for exactly this reason.
    @Test("Revoking consent stops the next trigger rather than the next launch")
    func revokingConsentStopsTheNextTrigger() async {
        let scanner = RecordingSecurityScanner()
        let consent = MutableConsentFlag(true)
        let coordinator = SecurityRefreshCoordinator(
            scan: { await scanner.record() },
            isConsented: { await consent.value }
        )

        await coordinator.mutationCompleted()
        #expect(await scanner.count == 1)

        await consent.set(false)
        await coordinator.mutationCompleted()
        await coordinator.refreshIfNeeded()

        #expect(await scanner.count == 1, "a trigger after revocation still scanned")
    }

    // MARK: - Helpers

    private static func makeBundle(at url: URL) throws {
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

    private static func locator(_ roots: TestRoots, _ fileSystem: RecordingFileSystem) -> ArtifactLocator {
        ArtifactLocator(cellar: roots.cellar, caskroom: roots.caskroom, fileSystem: fileSystem)
    }

    private func withHomebrewTree(
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
