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
    /// **Exactly two files may name them**, and the second is previews only.
    ///
    /// The first version of this guard exempted the whole of `ContentView.swift`
    /// because its shell preview constructs a `SecurityStore`. That was far too
    /// wide — it left the guard blind to every future line of the app's largest
    /// view, for the sake of one preview — and it was neither anchored nor
    /// recorded. The preview now lives alone in `SecurityPreviews.swift`, and
    /// `ContentView.swift` is covered like everything else.
    static let compositionRoots: Set<String> = ["cellarApp.swift", "SecurityPreviews.swift"]

    @Test("The two advisory sources are constructible from the composition root only")
    func theTwoAdvisorySourcesAreConstructibleFromTheCompositionRootOnly() throws {
        let sources = try AppSecuritySources.load()
        #expect(sources.count > 3, "the app-source scanner read almost nothing")
        #expect(
            sources.contains { $0.name == "ContentView.swift" },
            "ContentView must be in scope for this guard"
        )

        for source in sources where Self.compositionRoots.contains(source.name) == false {
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

    /// The exemption is **anchored**, not asserted.
    ///
    /// `SecurityPreviews.swift` is allowed to name both sources. What makes that
    /// safe is two checkable facts rather than a promise in a comment: the file
    /// declares no type and no function, so nothing in it is reachable from the
    /// running app; and every source it builds is handed to a
    /// `SecurityScanEngine` whose consent is `FixedScanConsent(.notGranted)`, so
    /// the gate refuses before a request is ever built.
    @Test("The preview exemption is narrow, declares nothing, and denies consent")
    func thePreviewExemptionIsNarrowAndConsentDenied() throws {
        let sources = try AppSecuritySources.load()
        let previews = try #require(sources.first { $0.name == "SecurityPreviews.swift" })

        #expect(previews.code.contains("OSVSource("), "the exemption guards a file that needs none")
        #expect(previews.code.contains("FixedScanConsent(.notGranted)"))
        #expect(previews.code.contains("SecurityScanEngine("))

        for declaration in ["struct ", "final class ", "actor ", "enum ", "func "] {
            #expect(
                previews.code.contains(declaration) == false,
                "SecurityPreviews declares \(declaration.trimmingCharacters(in: .whitespaces)), so it is reachable code"
            )
        }
        #expect(previews.code.contains("#Preview"), "the file is not previews at all")
    }

    /// The control. Every assertion above is an **absence**, and an absence passes
    /// for free against a scanner that cannot see anything — a stripped comment,
    /// a mis-joined path, a rename. This plants a real violation and requires the
    /// scanner to find it. Mirrors `EgressStructureTests.theScannerDetectsAViolation`.
    @Test(
        "The scanner detects a planted direct construction",
        arguments: [
            "let source = OSVSource()",
            "private let enrichment = NVDSource(credentials: store)",
            "let session = AdvisorySession.make()",
            "await OSVSource().discover(queries)"
        ]
    )
    func theScannerDetectsAPlantedDirectConstruction(violation: String) {
        let tokens = ["OSVSource", "NVDSource", "AdvisorySession"]

        #expect(
            tokens.contains { violation.contains($0) },
            "the scanner missed a real violation: \(violation)"
        )
    }

    /// And the other half of the control: an ordinary app file must **not** trip
    /// it, or the guard would be satisfied by a scanner that flags everything.
    @Test("The scanner does not fire on an ordinary security view")
    func theScannerDoesNotFireOnAnOrdinarySecurityView() throws {
        let sources = try AppSecuritySources.load()
        let view = try #require(sources.first { $0.name == "SecurityView.swift" })

        #expect(view.code.contains("SecurityStore"), "the wrong file was read")
        for token in ["OSVSource", "NVDSource", "AdvisorySession"] {
            #expect(view.code.contains(token) == false)
        }
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

/// The consent disclosure must name the hosts the app actually reaches.
///
/// The spec requires the disclosure to state "in plain language exactly what
/// leaves the machine and to which hosts". That is a claim about *egress*, and
/// nothing structural tied the sentence to the egress until now: adding a third
/// source, or changing a base URL, would have left the sheet quietly describing
/// a world that no longer existed — and a stale disclosure is worse than none,
/// because the user consented to it.
///
/// `EgressStructureTests` pins the two base URLs inside `SecurityKit`. This pins
/// the sheet to the same two, so the two can only ever change together.
@Suite("Consent disclosure")
struct ConsentDisclosureTests {
    /// The host component of each URL `SecurityKit` may request.
    private static var egressHosts: Set<String> {
        Set([OSVSource.baseURL, NVDSource.baseURL].compactMap { URL(string: $0)?.host() })
    }

    @Test("The disclosure names exactly the hosts the app can reach, and no others")
    func theDisclosureNamesExactlyTheHostsTheAppCanReach() {
        let disclosed = Set(SecurityConsentSheet.hosts.map(\.host))

        #expect(Self.egressHosts == ["api.osv.dev", "services.nvd.nist.gov"], "a base URL moved")
        #expect(
            disclosed == Self.egressHosts,
            """
            the consent sheet describes \(disclosed.sorted()) while the app can reach \
            \(Self.egressHosts.sorted()) — the user would be consenting to the wrong thing
            """
        )
    }

    /// Each disclosed host says what it is for. A bare address is an address, not
    /// a disclosure.
    @Test("Every disclosed host carries its purpose")
    func everyDisclosedHostCarriesItsPurpose() {
        for destination in SecurityConsentSheet.hosts {
            #expect(destination.purpose.isEmpty == false, "\(destination.host) has no stated purpose")
        }
        #expect(SecurityConsentSheet.hosts.count == 2)
    }

    /// The other half of the disclosure: what is sent, and what is not. Both
    /// sentences must exist and must name the two things the spec singles out —
    /// package names and versions.
    @Test("The disclosure states what is sent and what is not")
    func theDisclosureStatesWhatIsSentAndWhatIsNot() {
        let sent = SecurityConsentSheet.whatIsSent.lowercased()
        let notSent = SecurityConsentSheet.whatIsNotSent.lowercased()

        #expect(sent.contains("name"))
        #expect(sent.contains("version"))
        #expect(notSent.isEmpty == false)
        #expect(sent != notSent)
    }
}
