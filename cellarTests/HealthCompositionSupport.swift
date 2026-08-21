//
//  HealthCompositionSupport.swift
//  cellarTests
//

import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Foundation
import SecurityKit
import Synchronization

@testable import cellar

/// Values the Health composition maps from, built by hand.
///
/// Every one of these is a shape some shipped capability actually produces. They
/// are constructed here rather than acquired, because the whole claim under test
/// is that Health *reads resident state* and acquires nothing — a fixture that
/// had to run a scan to exist would make that claim untestable.
nonisolated enum HealthFixtures {
    static func keg(_ version: String) -> InstalledKeg {
        InstalledKeg(version: version, installedAt: Date(timeIntervalSince1970: 0), installedOnRequest: true)
    }

    static func package(
        _ name: String,
        kind: PackageKind = .formula,
        installed: String = "1.0.0",
        offering: String = "1.0.0",
        outdated: Bool = false,
        pinned: Bool = false,
        extraVersions: [String] = [],
        tap: String = "homebrew/core"
    ) -> InstalledPackage {
        let kegs = ([installed] + extraVersions).map(keg)
        return InstalledPackage(
            kind: kind,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            tap: tap,
            catalogVersion: offering,
            kegs: kegs,
            primaryKeg: kegs[0],
            snapshotOutdated: outdated,
            isPinned: pinned,
            pinnedVersion: pinned ? installed : nil,
            declaresAutoUpdates: kind == .cask ? false : nil
        )
    }

    static func browse(_ packages: [InstalledPackage], isAvailable: Bool = true) -> InstalledBrowse {
        InstalledBrowse(inventory: InstalledInventory(packages: packages), isAvailable: isAvailable)
    }

    static func entries(_ packages: [InstalledPackage]) -> [PackageEntry] {
        packages.map { PackageEntry(installed: $0, catalog: nil, id: $0.id) }
    }

    static let roots = DiskRootsIdentity(
        cellar: "/opt/homebrew/Cellar",
        caskroom: "/opt/homebrew/Caskroom",
        cache: "/Users/tester/Library/Caches/Homebrew"
    )

    /// A disk snapshot with the three root states spelled out, so "one root
    /// failed" and "nothing was measured" are two different fixtures rather than
    /// two readings of one.
    static func snapshot(
        cacheBytes: Int64 = 0,
        rootStates: [DiskArea: DiskRootState] = [.cellar: .present, .caskroom: .present, .cache: .present],
        packages: [DiskPackageUsage] = [],
        warnings: [DiskUsageWarning] = []
    ) -> DiskUsageSnapshot {
        DiskUsageSnapshot(
            roots: roots,
            generatedAt: Date(timeIntervalSince1970: 1_000_000),
            rootStates: rootStates,
            packages: packages,
            cache: DiskObservation(allocatedBytes: cacheBytes, logicalBytes: cacheBytes),
            warnings: warnings
        )
    }

    static func diskPackage(_ name: String, versions: [String]) -> DiskPackageUsage {
        DiskPackageUsage(
            id: PackageID(kind: .formula, name: name),
            versions: versions.map { version in
                DiskVersionUsage(
                    id: DiskVersionID(package: PackageID(kind: .formula, name: name), rawVersion: version),
                    observation: DiskObservation(allocatedBytes: 1_024, logicalBytes: 1_024),
                    linkState: .notApplicable
                )
            }
        )
    }

    /// Coverage totals built from the four outcomes, so the shipped constructor
    /// is what decides the counts rather than this fixture.
    static func totals(vulnerable: Int, clean: Int, notCovered: Int, unavailable: Int) -> CoverageTotals {
        let finding: CVEScanOutcome = .covered(.findings([]))
        let cleanCoverage: CVEScanOutcome = .covered(
            .clean(CleanCoverage(answeredBy: .osv, queriedVersion: "1.0.0"))
        )
        var outcomes: [CVEScanOutcome] = []
        outcomes.append(contentsOf: Array(repeating: finding, count: vulnerable))
        outcomes.append(contentsOf: Array(repeating: cleanCoverage, count: clean))
        outcomes.append(contentsOf: Array(repeating: .notCovered(.unmapped), count: notCovered))
        outcomes.append(contentsOf: Array(repeating: .unavailable(.offline), count: unavailable))
        return CoverageTotals(of: outcomes)
    }

    static func evidence(warnings: Int, partial: Bool = false, ready: Bool = false) -> DoctorEvidence {
        DoctorEvidence(
            rawStdout: Data("\n".utf8),
            rawStderr: Data(),
            preamble: [],
            warnings: (0..<warnings).map { DoctorWarning(headline: "w\($0)", detail: []) },
            unknownLines: [],
            issues: partial ? [.orphanDetailLine] : [],
            reportsReady: ready,
            provenance: DoctorParserProvenance(documentStream: .stderr)
        )
    }

    static let installation = BrewInstallation(
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
        prefix: .appleSilicon,
        version: BrewVersion(major: 4, minor: 0, patch: 0)
    )

    static let homebrewRoots = HomebrewRoots(
        installation: installation,
        userCacheDirectory: URL(fileURLWithPath: "/Users/tester/Library/Caches")
    )
}

/// A `FileMetadataAccess` with no disk behind it.
///
/// The seam exists precisely so the last-update reading is provable with no real
/// Homebrew checkout; this is the app-side half of what `HomebrewUpdateReaderTests`
/// proves in the package.
nonisolated struct StubFileMetadataAccess: FileMetadataAccess {
    let answers: [String: FileModificationDate]

    func modificationDate(at url: URL) -> FileModificationDate {
        answers[url.path] ?? .absent
    }
}

/// A doctor source that answers from a value and counts how often it was asked.
///
/// Per instance, like `CompositionLauncher`: "the section rendered and nobody ran
/// doctor" is a claim about *this* test, and a shared static counter is the shape
/// that produces a false zero when suites run concurrently.
nonisolated final class StubDoctorSource: DoctorSourcing, Sendable {
    private let recorded = Mutex(0)
    let outcome: DoctorOutcome

    init(outcome: DoctorOutcome) {
        self.outcome = outcome
    }

    var runCount: Int { recorded.withLock { $0 } }

    func run(using installation: BrewInstallation) async -> DoctorOutcome {
        recorded.withLock { $0 += 1 }
        return outcome
    }
}

/// Records every snooze a bulk action wrote, with the version it named.
///
/// A recording sink rather than a store, so "one snooze per package, each naming
/// that package's own offered version" is an assertion over an ordered ledger.
/// `BulkSnoozeTests` proves the same thing a second time against a real
/// `MetadataStore` on an in-memory container, because the ledger cannot prove
/// that re-snoozing replaces rather than accumulates.
nonisolated final class RecordingSnoozeSink: Sendable {
    private let recorded = Mutex<[SnoozeWrite]>([])

    struct SnoozeWrite: Sendable, Hashable {
        let id: PackageID
        let version: String
    }

    var writes: [SnoozeWrite] { recorded.withLock { $0 } }

    func snooze(_ id: PackageID, offering version: String) {
        recorded.withLock { $0.append(SnoozeWrite(id: id, version: version)) }
    }
}
