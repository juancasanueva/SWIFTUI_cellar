import Foundation
import Testing

@testable import Catalog

/// The newness sidecars' own recorded size bounds (catalog-sync CS-M1, CS-A1,
/// CS-A2).
///
/// The snapshot's footprint bound is measured over the **snapshot alone**, so
/// persisting new durable state cannot be admitted by re-basing it. That means
/// every additional file has to carry a bound of its own, or "we did not move
/// the snapshot bound" would just be an accounting trick — the bytes would
/// simply live somewhere unmeasured.
///
/// **Ratios as well as absolutes**, for the machine-independence reason slice 1
/// recorded: a ratio against the snapshot in the same process is stable
/// everywhere, and the absolute ceiling is the real product constraint.
@Suite("Discovery sidecar footprint", .serialized)
struct DiscoverySidecarFootprintTests {
    /// The recorded bounds, and what this harness measures against them on the
    /// anchored synthetic corpus (7,684 casks + 8,530 formulae):
    ///
    /// | Quantity | Bound | Why that number |
    /// |---|---|---|
    /// | encoded roster / encoded snapshot | 0.06x | names only, against a full projection |
    /// | encoded roster | 512 KB | ~16k identities at ~16 B each, with headroom |
    /// | encoded arrivals log, full | 64 KB | `retentionLimit` entries at ~64 B each |
    static let rosterRatioBound = 0.06
    static let rosterAbsoluteBound = 512 * 1_024
    static let arrivalsAbsoluteBound = 64 * 1_024

    @Test(
        "The roster stays within its own recorded bound at full catalog scale",
        .heavyFixture,
        .timeLimit(.minutes(2))
    )
    func rosterStaysWithinItsBound() throws {
        let root = try CatalogFootprintTests.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970

        var snapshotBytes = 0
        var rosterBytes = 0
        var identityCount = 0

        try autoreleasepool {
            let snapshot = try CatalogFootprintTests.buildSnapshot(in: root, widened: true)
            snapshotBytes = try encoder.encode(snapshot).count

            // The seeding pass over a full catalog: exactly what a first sync
            // writes on a real machine.
            let seeded = DiscoveryRosterDiff.advance(
                roster: nil,
                arrivals: nil,
                observing: snapshot.packages,
                now: Date(timeIntervalSince1970: 1_800_000_000)
            )
            rosterBytes = try encoder.encode(seeded.roster).count
            identityCount = seeded.roster.formulae.count + seeded.roster.casks.count

            // The measurement really ran over a full-scale catalog, so the
            // ratio below is not flattered by a thin corpus.
            #expect(
                snapshot.packages.count
                    == CatalogFootprintTests.caskCount + CatalogFootprintTests.formulaCount
            )
            #expect(seeded.arrivals.arrivals.isEmpty)
        }

        #expect(identityCount == CatalogFootprintTests.caskCount + CatalogFootprintTests.formulaCount)
        #expect(snapshotBytes > 4 * 1_048_576)

        let ratio = Double(rosterBytes) / Double(snapshotBytes)
        #expect(
            ratio <= Self.rosterRatioBound,
            """
            roster \(rosterBytes / 1_024) KB against snapshot \
            \(snapshotBytes / 1_048_576) MB = \(ratio)x, bound \(Self.rosterRatioBound)x
            """
        )
        #expect(
            rosterBytes <= Self.rosterAbsoluteBound,
            "roster \(rosterBytes / 1_024) KB, ceiling \(Self.rosterAbsoluteBound / 1_024) KB"
        )
    }

    /// Token lengths measured from the live endpoints on 2026-08-06, over the
    /// same capture the corpus counts above come from:
    ///
    /// | Namespace | n | mean | p95 | max |
    /// |---|---|---|---|---|
    /// | formulae (`name`) | 8,530 | 7.9 | 15 | 31 |
    /// | casks (`token`) | 7,684 | 12.8 | 25 | 54 |
    ///
    /// The synthetic names below are built to those means. A bound measured over
    /// `p1` would pass and tell nobody anything; one measured over 20-character
    /// names would fail and tell nobody anything either. Fix the generator, not
    /// the bound.
    static let realFormulaNameLength = 8
    static let realCaskTokenLength = 13

    @Test("A full arrivals log stays within its own recorded bound")
    func fullArrivalsLogStaysWithinItsBound() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // A log at the retention cap — the largest this file can ever be,
        // because `pruned(now:)` refuses to hand back more than
        // `retentionLimit`. Alternating kinds puts the split near the real
        // catalog's, and each name is exactly its namespace's measured mean.
        let log = PackageArrivalsLog(
            arrivals: (0..<PackageArrivalsLog.retentionLimit).map { index in
                index.isMultiple(of: 2)
                    ? PackageArrival(
                        kind: .formula,
                        name: "f" + String(format: "%07d", index),
                        firstSeenAt: now.addingTimeInterval(-Double(index) * 60)
                    )
                    : PackageArrival(
                        kind: .cask,
                        name: "c" + String(format: "%012d", index),
                        firstSeenAt: now.addingTimeInterval(-Double(index) * 60)
                    )
            }
        )

        // The anchor, asserted rather than trusted: a generator that quietly
        // shortened its names would make the bound below meaningless.
        let formulaNames = log.arrivals.filter { $0.kind == .formula }.map(\.name)
        let caskNames = log.arrivals.filter { $0.kind == .cask }.map(\.name)
        #expect(formulaNames.allSatisfy { $0.count == Self.realFormulaNameLength })
        #expect(caskNames.allSatisfy { $0.count == Self.realCaskTokenLength })
        #expect(formulaNames.count == 500)
        #expect(caskNames.count == 500)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let bytes = try encoder.encode(log).count

        #expect(log.arrivals.count == 1_000)
        #expect(
            bytes <= Self.arrivalsAbsoluteBound,
            "arrivals \(bytes / 1_024) KB, ceiling \(Self.arrivalsAbsoluteBound / 1_024) KB"
        )
        // The cap really is what bounds it: pruning cannot return more.
        #expect(log.pruned(now: now).arrivals.count <= PackageArrivalsLog.retentionLimit)
    }
}

/// Structural claims that keep newness out of the snapshot (catalog-sync CS-A1).
///
/// Cheap and textual, so deliberately outside the heavy-fixture suite above.
@Suite("Discovery structural guards")
struct DiscoveryStructuralGuardTests {
    @Test("The snapshot gained no newness field and did not move its schema version")
    func snapshotIsUntouchedByThisCapability() throws {
        // Reflection rather than a hand-written list: a hand-written list keeps
        // passing on the day someone adds the field it was written to forbid.
        let package = CatalogPackage.stub(kind: .formula, name: "wget")
        let labels = Mirror(reflecting: package).children.compactMap(\.label)

        #expect(
            labels == [
                "kind", "name", "displayName", "desc", "homepage", "license", "version", "tap",
                "dependencies", "buildDependencies", "dependents", "caveats",
                "deprecated", "deprecationReason", "deprecationDate",
                "disabled", "disableReason", "disableDate",
                "autoUpdates", "installCount365d", "caskInspection", "formulaSources"
            ]
        )
        #expect(labels.count == 22)

        // ...and the models file names none of this capability's vocabulary, so
        // a field cannot arrive there under a different spelling either.
        let code = try CatalogSources.code(of: "CatalogModels.swift")
        CatalogSources.assertAnchored(code, expecting: "CatalogPackage")
        for forbidden in ["firstSeen", "arrival", "roster", "seenness"] {
            #expect(
                code.lowercased().contains(forbidden.lowercased()) == false,
                "CatalogModels.swift names \(forbidden)"
            )
        }

        // The snapshot's own version did not move: this slice persists
        // additional files, and adds no field to the projection.
        #expect(CatalogSnapshot.currentSchemaVersion == 2)
    }

    @Test("Newness is never derived from the process-local revision ordinal")
    func newnessNeverDerivesFromTheRevisionOrdinal() throws {
        // The mechanism correction this slice exists to honour.
        // `CatalogSnapshotRevision` is documented as process-local and never
        // persisted — ordinals restart at 1 on every launch, so a diff keyed on
        // one would report the entire catalog as new on the second launch.
        let discoverySources = [
            "DiscoverRanking.swift",
            "CuratedDiscovery.swift",
            "DiscoveryRoster.swift",
            "DiscoveryRosterDiff.swift",
            "DiscoverContent.swift"
        ]

        for name in discoverySources {
            let code = try CatalogSources.code(of: name)
            CatalogSources.assertAnchored(code, expecting: "public")
            #expect(
                code.contains("CatalogSnapshotRevision") == false,
                "\(name) derives from the process-local revision ordinal"
            )
            #expect(code.contains(".revision") == false, "\(name) reads a snapshot revision")
        }
    }

    @Test("The discovery sources never read the wall clock directly")
    func discoverySourcesTakeAnInjectedNow() throws {
        // Every pruning and diffing function is pure over an injected `now`. A
        // retention rule that read `Date()` would be testable once a month.
        for name in ["DiscoveryRoster.swift", "DiscoveryRosterDiff.swift", "DiscoverContent.swift"] {
            let code = try CatalogSources.code(of: name)
            CatalogSources.assertAnchored(code, expecting: "now")
            #expect(code.contains("Date()") == false, "\(name) reads the wall clock directly")
        }
    }
}
