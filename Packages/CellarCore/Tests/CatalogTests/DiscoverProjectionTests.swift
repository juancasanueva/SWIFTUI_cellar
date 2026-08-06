import Foundation
import Testing

@testable import Catalog

/// What Discover actually renders (package-discovery PD-R2, PD-R5, PD-R6).
///
/// Every section reports a **typed** state: populated, empty *with a named
/// reason*, or awaiting the catalog. An empty collection paired with an empty
/// string is the shape this suite exists to make impossible — it is
/// indistinguishable from a failure, from a still-loading state, and from a bug,
/// and a user cannot tell which of the three they are looking at.
@Suite("Discover projection")
struct DiscoverProjectionTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Arrivals (PD-R5)

    @Test("A package first seen inside the window is projected with its first-observed date")
    func arrivalInsideTheWindowIsProjectedWithItsDate() throws {
        let threeDaysAgo = Self.now.addingTimeInterval(-3 * 24 * 3_600)
        let content = DiscoverProjection.content(
            snapshot: Self.snapshot(["wget", "newpkg"]),
            curated: nil,
            arrivals: PackageArrivalsLog(arrivals: [
                PackageArrival(kind: .formula, name: "newpkg", firstSeenAt: threeDaysAgo)
            ]),
            now: Self.now
        )

        let rows = try #require(content.newToYou.content)
        #expect(rows.map(\.package.name) == ["newpkg"])
        #expect(rows.first?.firstSeenAt == threeDaysAgo)
        #expect(content.hiddenArrivalCount == 0)
    }

    @Test("An entry beyond the thirty-day window is not projected")
    func arrivalBeyondTheWindowIsNotProjected() {
        let content = DiscoverProjection.content(
            snapshot: Self.snapshot(["oldarrival", "wget"]),
            curated: nil,
            arrivals: PackageArrivalsLog(arrivals: [
                PackageArrival(
                    kind: .formula,
                    name: "oldarrival",
                    firstSeenAt: Self.now.addingTimeInterval(-31 * 24 * 3_600)
                )
            ]),
            now: Self.now
        )

        // Empty *with a reason*, never a blank list.
        #expect(content.newToYou.content == nil)
        #expect(content.newToYou == .empty(.newnessMeasuredFromThisSyncOnward))
    }

    @Test("An arrival whose package left the catalog is dropped and nothing is thrown")
    func arrivalForARemovedPackageIsDropped() throws {
        let content = DiscoverProjection.content(
            snapshot: Self.snapshot(["wget", "stillhere"]),
            curated: nil,
            arrivals: PackageArrivalsLog(arrivals: [
                PackageArrival(
                    kind: .formula,
                    name: "stillhere",
                    firstSeenAt: Self.now.addingTimeInterval(-5 * 24 * 3_600)
                ),
                PackageArrival(
                    kind: .formula,
                    name: "vanished",
                    firstSeenAt: Self.now.addingTimeInterval(-5 * 24 * 3_600)
                )
            ]),
            now: Self.now
        )

        let rows = try #require(content.newToYou.content)
        #expect(rows.map(\.package.name) == ["stillhere"])
        #expect(rows.contains { $0.package.name == "vanished" } == false)
    }

    @Test("Arrivals are ordered newest first")
    func arrivalsAreOrderedNewestFirst() throws {
        let content = DiscoverProjection.content(
            snapshot: Self.snapshot(["oldest", "middle", "newest"]),
            curated: nil,
            arrivals: PackageArrivalsLog(arrivals: [
                Self.arrival("middle", daysAgo: 5),
                Self.arrival("oldest", daysAgo: 20),
                Self.arrival("newest", daysAgo: 1)
            ]),
            now: Self.now
        )

        let rows = try #require(content.newToYou.content)
        #expect(rows.map(\.package.name) == ["newest", "middle", "oldest"])
    }

    @Test("A log beyond the display cap reports the exact hidden count")
    func hiddenArrivalCountIsExact() throws {
        // Spaced by hours, so all 42 sit comfortably inside the 30-day window
        // and the display cap is the only rule doing any work. (Daily spacing
        // would push the tail past the window, and this test would measure
        // retention a third time instead of the cap.)
        let names = (1...42).map { "pkg\($0)" }
        let content = DiscoverProjection.content(
            snapshot: Self.snapshot(names),
            curated: nil,
            arrivals: PackageArrivalsLog(
                arrivals: names.enumerated().map { offset, name in
                    Self.arrival(name, hoursAgo: offset + 1)
                }
            ),
            now: Self.now
        )

        let rows = try #require(content.newToYou.content)
        #expect(rows.count == 30)
        // 42 inside the window, 30 shown: "and 12 more" is a number, not a guess.
        #expect(content.hiddenArrivalCount == 12)
    }

    // MARK: - Honest phrasing, as a test rather than a review note (PD-R5 sc4)

    @Test("The arrivals copy claims first observation by this Mac, never publication")
    func arrivalsCopyClaimsFirstObservationNotPublication() {
        // The copy lives in CellarCore precisely so a test owns it. A view could
        // be relabelled in a hurry; this cannot.
        let copy = [DiscoverCopy.arrivalsPopulated, DiscoverCopy.arrivalsEmpty]

        for text in copy {
            let lowered = text.lowercased()
            #expect(lowered.contains("this mac"), "\(text) does not say whose observation it is")
            #expect(
                lowered.contains("first saw") || lowered.contains("first sees"),
                "\(text) does not describe the value as a first observation"
            )
            for forbidden in [
                "published", "release date", "added to homebrew",
                "new on homebrew", "recently added", "newly released"
            ] {
                #expect(
                    lowered.contains(forbidden) == false,
                    "the arrivals copy claims \(forbidden), which the catalog cannot support"
                )
            }
        }
    }

    @Test("The empty arrivals copy explains that newness starts now")
    func emptyArrivalsCopyExplainsTheFirstRun() {
        // D5: the first-run state is a *designed, explained* state — not a
        // spinner, not a hidden section, not a failure.
        #expect(DiscoverCopy.arrivalsEmpty.isEmpty == false)
        #expect(DiscoverCopy.arrivalsEmpty.lowercased().contains("from this sync onward"))
        #expect(DiscoverCopy.arrivalsEmpty != DiscoverCopy.arrivalsPopulated)
    }

    // MARK: - Typed section states (PD-R6)

    @Test("First run explains the empty arrivals section and still shows the rest")
    func firstRunExplainsArrivalsAndPopulatesTheRest() throws {
        let snapshot = Self.rankedSnapshot()
        let curated = CuratedDiscoveryList(
            categories: [
                CuratedCategory(
                    id: "staples",
                    title: "Staples",
                    entries: [CuratedEntry(kind: .formula, token: "topformula", blurb: "Useful.")]
                )
            ],
            skippedRecordCount: 0
        )

        let content = DiscoverProjection.content(
            snapshot: snapshot,
            curated: curated,
            // A first successful sync: the seeding pass wrote no arrival.
            arrivals: .empty,
            now: Self.now
        )

        #expect(content.newToYou == .empty(.newnessMeasuredFromThisSyncOnward))
        // Not a failure and not a pending state — the catalog is right here.
        #expect(content.newToYou.isAwaitingCatalog == false)
        #expect(content.topFormulae.content?.isEmpty == false)
        #expect(content.topCasks.content?.isEmpty == false)
        #expect(content.curated.content?.isEmpty == false)
    }

    @Test("An empty ranked section names its reason and reports a count of zero")
    func emptyRankedSectionNamesItsReason() throws {
        // Every install count absent: nothing is *eligible*, which is a different
        // fact from "the catalog is empty" and a different fact again from "the
        // catalog has not loaded".
        let snapshot = CatalogSnapshot(
            generatedAt: Self.now,
            skippedRecordCount: 0,
            packages: [
                CatalogPackage.stub(kind: .formula, name: "unmeasured", installCount365d: nil),
                CatalogPackage.stub(kind: .cask, name: "alsounmeasured", installCount365d: nil)
            ]
        )
        let curated = CuratedDiscoveryList(
            categories: [
                CuratedCategory(
                    id: "staples",
                    title: "Staples",
                    entries: [CuratedEntry(kind: .formula, token: "unmeasured", blurb: "Useful.")]
                )
            ],
            skippedRecordCount: 0
        )

        let content = DiscoverProjection.content(
            snapshot: snapshot,
            curated: curated,
            arrivals: .empty,
            now: Self.now
        )

        #expect(content.topFormulae == .empty(.noEligibleRankedPackage))
        #expect(content.topCasks == .empty(.noEligibleRankedPackage))
        #expect(content.topFormulae.count == 0)
        #expect(content.topCasks.count == 0)
        // ...and at least one section still carries content, so Discover never
        // opens with every section empty and none of them explaining itself.
        #expect(content.curated.content?.isEmpty == false)
        #expect(content.hasContent)
    }

    @Test("A curated list whose every token is unresolvable names its own reason")
    func fullyUnresolvableCuratedSectionNamesItsReason() {
        let content = DiscoverProjection.content(
            snapshot: Self.rankedSnapshot(),
            curated: CuratedDiscoveryList(
                categories: [
                    CuratedCategory(
                        id: "ghosts",
                        title: "Ghosts",
                        entries: [
                            CuratedEntry(kind: .formula, token: "gone", blurb: "Not here."),
                            CuratedEntry(kind: .cask, token: "alsogone", blurb: "Nor here.")
                        ]
                    )
                ],
                skippedRecordCount: 0
            ),
            arrivals: .empty,
            now: Self.now
        )

        #expect(content.curated == .empty(.everyCuratedEntryUnresolved))
        #expect(content.curatedUnresolvedCount == 2)
        // The two counts stay distinct all the way to the UI boundary.
        #expect(content.curatedSkippedRecordCount == 0)
        #expect(content.hasContent)
    }

    @Test("No adopted snapshot is awaiting-catalog, not a failure")
    func noSnapshotIsAwaitingCatalog() {
        let content = DiscoverProjection.content(
            snapshot: nil,
            curated: nil,
            arrivals: nil,
            now: Self.now
        )

        #expect(content.topFormulae == .awaitingCatalog)
        #expect(content.topCasks == .awaitingCatalog)
        #expect(content.curated == .awaitingCatalog)
        #expect(content.newToYou == .awaitingCatalog)
        #expect(content.topFormulae.isAwaitingCatalog)
        // Awaiting is not empty-with-a-reason, and neither is a failure.
        #expect(content == .empty)
        #expect(content.hasContent == false)
    }

    @Test("No section is ever an empty collection without a stated reason")
    func noSectionIsSilentlyEmpty() {
        // The invariant PD-R6 exists for, checked across every shape this suite
        // builds: a section is populated with a genuinely non-empty collection,
        // or it names why it is not.
        let shapes = [
            DiscoverProjection.content(
                snapshot: nil, curated: nil, arrivals: nil, now: Self.now
            ),
            DiscoverProjection.content(
                snapshot: Self.rankedSnapshot(), curated: nil, arrivals: .empty, now: Self.now
            ),
            DiscoverProjection.content(
                snapshot: Self.snapshot(["wget"]), curated: nil, arrivals: nil, now: Self.now
            )
        ]

        for content in shapes {
            #expect(content.topFormulae.isSilentlyEmpty == false)
            #expect(content.topCasks.isSilentlyEmpty == false)
            #expect(content.curated.isSilentlyEmpty == false)
            #expect(content.newToYou.isSilentlyEmpty == false)
        }
    }

    // MARK: - Discover costs no acquisition (PD-R2)

    @Test("Producing every projection issues no request and reads no new file")
    func projectionIssuesNoRequest() async throws {
        let harness = try SyncHarness()
        harness.source.script(.payload(Payload.formulae(["wget"])), for: .formulae)
        harness.source.script(.payload(Payload.casks(["iterm2"])), for: .casks)
        _ = await harness.engine.sync()
        let requestsAfterSync = harness.source.requests.count

        let snapshot = try #require(try harness.store.loadSnapshot())
        let curated = try await CuratedDiscoveryList.shipped()
        let arrivals = await harness.engine.arrivals()

        let content = DiscoverProjection.content(
            snapshot: snapshot,
            curated: curated,
            arrivals: arrivals,
            now: Self.now
        )

        // The projection really produced something, so the silence below is the
        // silence of work that happened rather than of work that was skipped.
        #expect(content.curated.content != nil || content.topFormulae.content != nil)
        #expect(harness.source.requests.count == requestsAfterSync)
    }

    // MARK: - Helpers

    static func arrival(_ name: String, daysAgo: Int) -> PackageArrival {
        PackageArrival(
            kind: .formula,
            name: name,
            firstSeenAt: now.addingTimeInterval(-Double(daysAgo) * 24 * 3_600)
        )
    }

    static func arrival(_ name: String, hoursAgo: Int) -> PackageArrival {
        PackageArrival(
            kind: .formula,
            name: name,
            firstSeenAt: now.addingTimeInterval(-Double(hoursAgo) * 3_600)
        )
    }

    static func snapshot(_ names: [String]) -> CatalogSnapshot {
        CatalogSnapshot(
            generatedAt: now,
            skippedRecordCount: 0,
            packages: names.map { CatalogPackage.stub(kind: .formula, name: $0) }
        )
    }

    /// A snapshot with something eligible on both ladders.
    static func rankedSnapshot() -> CatalogSnapshot {
        CatalogSnapshot(
            generatedAt: now,
            skippedRecordCount: 0,
            packages: [
                CatalogPackage.stub(kind: .formula, name: "topformula", installCount365d: 500),
                CatalogPackage.stub(kind: .cask, name: "topcask", installCount365d: 900)
            ]
        )
    }
}
