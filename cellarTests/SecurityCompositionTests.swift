//
//  SecurityCompositionTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import DiskUsage
import Foundation
import SecurityKit
import Testing

@testable import cellar

/// The three composition points between `BrewClient`/`DiskUsage` and
/// `SecurityKit`.
///
/// They live in the app target because no CellarCore target may see both sides,
/// which is a named cost of the design's placement decision rather than an
/// accident — and the app target is the one M3-1's Phase 18 proved is where
/// defects hide. So these run under `xcodebuild test`, slowly, on purpose.
@Suite("Security composition")
struct SecurityCompositionTests {
    // MARK: - Arrangement

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
        let primary = keg(linked ?? version)
        return InstalledPackage(
            kind: kind,
            name: name,
            displayName: name,
            desc: nil,
            homepage: nil,
            tap: "homebrew/core",
            catalogVersion: version,
            kegs: ([version] + otherKegs).map(Self.keg),
            primaryKeg: primary,
            snapshotOutdated: false,
            isPinned: false,
            pinnedVersion: nil,
            declaresAutoUpdates: nil,
            linkedKeg: linked
        )
    }

    // MARK: - 15.1 The query builder

    /// The mapping table is small on purpose — U1 measured real coverage at 3-5%
    /// — so the overwhelming majority of an inventory must produce **no query**
    /// and its own typed `notCovered` outcome instead.
    @Test("The query builder emits one query per mapped formula and nothing else")
    func theQueryBuilderEmitsOneQueryPerMappedFormulaAndNothingElse() {
        let inventory = [
            Self.package("bat", version: "0.24.0"),
            Self.package("curl"),
            Self.package("coreutils"),
            Self.package("ghostty", kind: .cask),
            // A **mapped** formula whose version cannot be interpreted in its
            // ecosystem. It has to be mapped: the planner answers `.unmapped`
            // first, so an unmapped formula with a date version would never reach
            // the version rule and this row would prove nothing about it.
            Self.package("ripgrep", version: "2026-07-16")
        ]

        let plan = SecurityQueryBuilder.plan(for: inventory)

        #expect(plan.queries.count == 1, "something other than the one mapped formula was queried")
        #expect(plan.queries.first?.packageID.name == "bat")

        // Every package that produced no query produced a typed reason instead,
        // and all three reasons are represented.
        #expect(plan.outcomes.count == 4)
        #expect(plan.outcomes[PackageID(kind: .formula, name: "curl")] == .notCovered(.unmapped))
        #expect(plan.outcomes[PackageID(kind: .formula, name: "coreutils")] == .notCovered(.unmapped))
        #expect(plan.outcomes[PackageID(kind: .cask, name: "ghostty")] == .notCovered(.kindUnsupported))
        #expect(
            plan.outcomes[PackageID(kind: .formula, name: "ripgrep")]
                == .notCovered(.unsupportedVersionScheme)
        )
        #expect(plan.queries.count + plan.outcomes.count == inventory.count, "a package vanished")
    }

    /// An identity collision must not become a query. `curl` the Homebrew formula
    /// and `curl` the RubyGems package share a name and nothing else.
    @Test("An unmapped name never becomes a query no matter how plausible it looks")
    func anUnmappedNameNeverBecomesAQuery() {
        let plan = SecurityQueryBuilder.plan(for: [Self.package("curl"), Self.package("openssl@3")])

        #expect(plan.queries.isEmpty)
        #expect(plan.outcomes.values.allSatisfy { $0 == .notCovered(.unmapped) })
    }

    /// `InstalledDecoder.primaryKeg` already owns "linked wins, else newest", and
    /// `InstalledPackage.primaryKeg` exposes its answer. The builder **reads** it.
    /// Re-deriving it here would create a second owner of a rule that has one.
    @Test("The primary keg is read from InstalledPackage and not rederived")
    func thePrimaryKegIsReadFromInstalledPackageAndNotRederived() throws {
        let package = Self.package("bat", version: "0.9.0", otherKegs: ["1.5.0", "2.0.0"], linked: "1.5.0")

        let plan = SecurityQueryBuilder.plan(for: [package])
        let query = try #require(plan.queries.first)

        // Not the newest keg (2.0.0) and not the first (0.9.0): the linked one,
        // which is what `primaryKeg` reports.
        #expect(query.installedVersion == "1.5.0")
        #expect(package.kegs.count == 3, "the arrangement stopped exercising multiple kegs")
    }

    @Test("The query version is the Homebrew revision split of the installed version")
    func theQueryVersionIsTheHomebrewRevisionSplitOfTheInstalledVersion() throws {
        let plan = SecurityQueryBuilder.plan(for: [Self.package("bat", version: "1.2.3_1")])
        let query = try #require(plan.queries.first)

        #expect(query.installedVersion == "1.2.3_1", "the installed string must survive verbatim")
        #expect(query.queryVersion == "1.2.3", "the packaging revision must be split off before asking")
        #expect(HomebrewRevision.split("1.2.3_1").upstream == "1.2.3", "the split rule moved")
    }

    /// Building queries transmits nothing. The builder is a pure projection; the
    /// consent gate lives in the engine, and this proves the builder is not a
    /// second, ungated route to the network.
    @Test("Building queries issues no request")
    func buildingQueriesIssuesNoRequest() {
        let spy = CompositionRequestSpy()
        spy.install()
        defer { spy.uninstall() }

        _ = SecurityQueryBuilder.plan(for: (0..<50).map { _ in Self.package("bat", version: "0.24.0") })

        #expect(spy.observedCount == 0, "the query builder issued a request")
    }

    // MARK: - The consent-gate structural guard

    /// `OSVSource` and `NVDSource` are public and carry **no internal consent
    /// check** — the gate is in `SecurityScanEngine`. So the composition root must
    /// be the only place in the app that can name them, or a view could construct
    /// one and transmit before the user ever answered.
    @Test("The two advisory sources are constructible from the composition root only")
    func theTwoAdvisorySourcesAreConstructibleFromTheCompositionRootOnly() throws {
        let sources = try AppSecuritySources.load()
        #expect(sources.count > 3, "the app-source scanner read almost nothing")

        for source in sources where source.name != "cellarApp.swift" && source.name != "ContentView.swift" {
            for token in ["OSVSource", "NVDSource", "AdvisorySession"] {
                #expect(
                    source.code.contains(token) == false,
                    "\(source.name) names \(token), bypassing the engine's consent gate"
                )
            }
        }

        // The positive anchor: the composition root really does construct them,
        // so the scan above is an exclusion rather than a description of an empty
        // set.
        let root = try #require(sources.first { $0.name == "cellarApp.swift" })
        #expect(root.code.contains("OSVSource("))
        #expect(root.code.contains("NVDSource("))
        #expect(root.code.contains("SecurityScanEngine("), "the sources reach the network ungated")
    }

    /// The other half: nothing in the app calls `discover` or `enrich` directly.
    /// Constructing a source is harmless; using one outside the engine is not.
    @Test("No app-target file calls discover or enrich directly")
    func noAppTargetFileCallsDiscoverOrEnrichDirectly() throws {
        let sources = try AppSecuritySources.load()

        for source in sources {
            #expect(source.code.contains(".discover(") == false, "\(source.name) discovers directly")
            #expect(source.code.contains(".enrich(") == false, "\(source.name) enriches directly")
        }
    }
}
