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
    private typealias Arranged = SecurityScopeArrangement

    private static func locator(
        _ roots: SecurityScopeArrangement.TestRoots,
        _ fileSystem: RecordingFileSystem
    ) -> ArtifactLocator {
        Arranged.locator(roots, fileSystem)
    }

    private static func package(
        _ name: String,
        kind: PackageKind = .formula,
        version: String = "1.0.0",
        otherKegs: [String] = [],
        linked: String? = nil
    ) -> InstalledPackage {
        Arranged.package(name, kind: kind, version: version, otherKegs: otherKegs, linked: linked)
    }

    private static func makeBundle(at url: URL) throws { try Arranged.makeBundle(at: url) }

    private func withHomebrewTree(
        _ body: (SecurityScopeArrangement.TestRoots, RecordingFileSystem) throws -> Void
    ) throws {
        try Arranged.withHomebrewTree(body)
    }

    // MARK: - 15.3 Artifact scope

    @Test("Only brew-managed locations are enumerated")
    func onlyBrewManagedLocationsAreEnumerated() throws {
        try withHomebrewTree { roots, recorder in
            let mapped = Self.package("bat")
            _ = Self.locator(roots, recorder).locations(for: [mapped])

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
            let located = Self.locator(roots, recorder).locations(for: [package])

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
                .locations(for: [Self.package("bat")])

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
}
