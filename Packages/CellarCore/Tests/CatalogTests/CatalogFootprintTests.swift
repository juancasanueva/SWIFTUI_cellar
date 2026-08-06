import Darwin
import Foundation
import Testing

@testable import Catalog

/// The recorded footprint bound for the M5 inspection widening (catalog-sync P6).
///
/// Probe U4 measured the widening over the real dumps and **rejected** carrying
/// the stanza tree: +28.3 MB resident, +6.6 MB on disk, a 4.7x launch reload.
/// The trimmed typed shape this package ships measured +6.3 MB / +3.6 MB / +21%.
/// This suite is what stops a later widening from re-crossing that line on a
/// user's machine rather than in a test.
///
/// **Ratios, not absolutes.** Wall-clock and resident numbers are machine
/// dependent; a same-process ratio against a baseline-shaped catalog is not. The
/// one absolute is the disk ceiling, which is a real product constraint.
///
/// **Malloc-zone bytes, not `phys_footprint`.** Under magazine malloc
/// `phys_footprint` never falls on free, so a baseline-then-widened comparison
/// *inside one process* would read the baseline's high-water mark as the
/// widened figure and pass no matter what. `MemoryProbe.physFootprint()` stays
/// correct for — and stays in — the growth-only budget in `CatalogMemoryTests`.
@Suite("Catalog footprint budget", .serialized)
struct CatalogFootprintTests {
    /// The live catalog, as of the capture the fixtures came from.
    static let caskCount = 7_684
    static let formulaCount = 8_530

    /// The recorded bounds, and what this harness actually measures against them
    /// on the anchored synthetic corpus:
    ///
    /// | Quantity | Bound | Measured | U4's rejected raw variant |
    /// |---|---|---|---|
    /// | encoded snapshot | 1.6x, and 16 MB absolute | 1.56x, 11.4 MB | 1.78x |
    /// | resident, loaded  | 1.6x | 1.23x | 2.59x |
    /// | snapshot load time | 2.0x | 1.57x | 4.75x |
    ///
    /// The encoded figures are byte counts and therefore identical on every
    /// machine; only the load ratio is wall-clock, and it carries the widest
    /// margin for that reason.
    static let encodedRatioBound = 1.6
    static let encodedAbsoluteBound = 16 * 1_048_576
    static let residentRatioBound = 1.6
    static let loadRatioBound = 2.0

    /// How far the synthetic corpus may drift from the real records it stands in
    /// for before the bound above stops meaning anything.
    static let anchorTolerance = 0.25

    @Test(
        "The full-catalog footprint stays within its recorded bound",
        .heavyFixture,
        .serialized,
        .timeLimit(.minutes(2))
    )
    func fullCatalogFootprintStaysWithinItsBound() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // One process, one measurement each, baseline first. The baseline is the
        // *same* records without the widened keys, so the delta is the widening
        // and nothing else.
        let baseline = try Self.measure(in: root, named: "baseline", widened: false)
        let widened = try Self.measure(in: root, named: "widened", widened: true)

        // The measurement really ran over a full-scale catalog.
        #expect(baseline.recordCount == Self.caskCount + Self.formulaCount)
        #expect(widened.recordCount == baseline.recordCount)
        #expect(baseline.encodedBytes > 4 * 1_048_576)
        #expect(widened.residentBytes > 0)
        #expect(widened.loadSeconds > 0)

        let encodedRatio = Double(widened.encodedBytes) / Double(baseline.encodedBytes)
        let residentRatio = Double(widened.residentBytes) / Double(baseline.residentBytes)
        let loadRatio = widened.loadSeconds / baseline.loadSeconds

        #expect(
            encodedRatio <= Self.encodedRatioBound,
            """
            encoded \(widened.encodedBytes / 1_048_576) MB vs baseline \
            \(baseline.encodedBytes / 1_048_576) MB = \(encodedRatio)x, \
            bound \(Self.encodedRatioBound)x
            """
        )
        #expect(
            widened.encodedBytes <= Self.encodedAbsoluteBound,
            "encoded \(widened.encodedBytes / 1_048_576) MB, ceiling \(Self.encodedAbsoluteBound / 1_048_576) MB"
        )
        #expect(
            residentRatio <= Self.residentRatioBound,
            """
            resident \(widened.residentBytes / 1_048_576) MB vs baseline \
            \(baseline.residentBytes / 1_048_576) MB = \(residentRatio)x, \
            bound \(Self.residentRatioBound)x
            """
        )
        #expect(
            loadRatio <= Self.loadRatioBound,
            """
            load \(widened.loadSeconds)s vs baseline \(baseline.loadSeconds)s \
            = \(loadRatio)x, bound \(Self.loadRatioBound)x
            """
        )
    }

    // MARK: - The anchor (the bound is worthless without it)

    @Test(
        "The synthetic corpus is the size the real records are",
        .heavyFixture,
        .timeLimit(.minutes(2))
    )
    func syntheticRecordsMatchTheRealOnes() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // A bound measured over unrealistically thin records would pass no matter
        // how expensive the widening really is, so the synthetic corpus is held
        // against the real records in two independent ways:
        //
        //  * its **baseline** size against the 50 verbatim live records in each
        //    `*-slice.json` — a thin baseline is what silently inflates a ratio;
        //  * its **widening delta** against the delta a verbatim live record
        //    actually pays, measured by re-projecting that same record with the
        //    widened keys removed. Same record, both sides: no corpus mismatch
        //    can flatter this number.
        let realCaskBaseline = try Self.perRecordEncodedBytes(ofSliceFixture: "cask-slice")
        let realCaskDelta = try Self.realWideningDelta(
            fixtures: ["cask-iterm2"],
            widenedKeys: ["url", "sha256", "artifacts", "depends_on", "conflicts_with"],
            kind: .cask
        )
        let realFormulaBaseline = try Self.perRecordEncodedBytes(ofSliceFixture: "formula-slice", kind: .formula)
        let realFormulaDelta = try Self.realWideningDelta(
            fixtures: ["formula-git", "formula-wget"],
            widenedKeys: ["urls"],
            kind: .formula
        )

        let syntheticCaskBaseline = try Self.perRecordEncodedBytes(
            ofSyntheticIn: root, named: "anchor-cask-baseline", kind: .cask, widened: false
        )
        let syntheticCaskWidened = try Self.perRecordEncodedBytes(
            ofSyntheticIn: root, named: "anchor-cask-widened", kind: .cask, widened: true
        )
        let syntheticFormulaBaseline = try Self.perRecordEncodedBytes(
            ofSyntheticIn: root, named: "anchor-formula-baseline", kind: .formula, widened: false
        )
        let syntheticFormulaWidened = try Self.perRecordEncodedBytes(
            ofSyntheticIn: root, named: "anchor-formula-widened", kind: .formula, widened: true
        )

        Self.expectWithinTolerance(
            syntheticCaskBaseline, of: realCaskBaseline, label: "baseline synthetic cask record"
        )
        Self.expectWithinTolerance(
            syntheticCaskWidened - syntheticCaskBaseline,
            of: realCaskDelta,
            label: "synthetic cask widening delta"
        )
        Self.expectWithinTolerance(
            syntheticFormulaBaseline,
            of: realFormulaBaseline,
            label: "baseline synthetic formula record"
        )
        Self.expectWithinTolerance(
            syntheticFormulaWidened - syntheticFormulaBaseline,
            of: realFormulaDelta,
            label: "synthetic formula widening delta"
        )

        // ...and the widening really is the thing that separates the two
        // corpora, so the ratio test above measures a widening and not two
        // identical payloads.
        #expect(syntheticCaskWidened > syntheticCaskBaseline)
        #expect(syntheticFormulaWidened > syntheticFormulaBaseline)
    }

    static func expectWithinTolerance(
        _ measured: Double,
        of anchor: Double,
        label: String
    ) {
        let drift = abs(measured - anchor) / anchor
        #expect(
            drift <= anchorTolerance,
            """
            \(label) encodes to \(Int(measured)) B, real records encode to \
            \(Int(anchor)) B — \(Int(drift * 100))% adrift, tolerance \
            \(Int(anchorTolerance * 100))%. Fix the generator, not the bound.
            """
        )
    }

    // MARK: - Measurement

    struct FootprintMeasurement {
        let recordCount: Int
        let encodedBytes: Int
        let residentBytes: Int
        let loadSeconds: Double
    }

    static func measure(
        in root: URL,
        named name: String,
        widened: Bool
    ) throws -> FootprintMeasurement {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = CatalogFileStore(directory: directory)

        var recordCount = 0
        try autoreleasepool {
            let snapshot = try buildSnapshot(in: directory, widened: widened)
            recordCount = snapshot.packages.count
            try store.persist(snapshot, state: state(recordCount: recordCount))
        }
        let encodedBytes = try Data(contentsOf: store.snapshotURL).count

        var residentBytes = 0
        var loadSeconds = 0.0
        try autoreleasepool {
            // Measured around the *load*, which is what a launch actually pays:
            // the sync-time arena is gone by now.
            let before = MallocProbe.bytesInUse()
            let start = ContinuousClock.now
            let loaded = try store.loadSnapshot()
            loadSeconds = seconds(start.duration(to: .now))
            residentBytes = MallocProbe.bytesInUse() - before

            #expect(loaded?.packages.count == recordCount)
            withExtendedLifetime(loaded) {}
        }

        return FootprintMeasurement(
            recordCount: recordCount,
            encodedBytes: encodedBytes,
            residentBytes: residentBytes,
            loadSeconds: loadSeconds
        )
    }

    static func buildSnapshot(in directory: URL, widened: Bool) throws -> CatalogSnapshot {
        let caskPayload = directory.appendingPathComponent("cask.json")
        let formulaPayload = directory.appendingPathComponent("formula.json")
        try SyntheticPayload.writeCasks(to: caskPayload, count: caskCount, widened: widened)
        try SyntheticPayload.writeFormulae(
            to: formulaPayload, count: formulaCount, widened: widened
        )

        return CatalogDecoder.link(
            formulae: try CatalogDecoder.decodeFormulae(
                contentsOf: formulaPayload, deletingAfterwards: true
            ),
            casks: try CatalogDecoder.decodeCasks(
                contentsOf: caskPayload, deletingAfterwards: true
            ),
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    // MARK: - Per-record encoded size

    static func decode(_ data: Data, kind: PackageKind) throws -> DecodedResource {
        kind == .cask
            ? try CatalogDecoder.decodeCasks(from: data)
            : try CatalogDecoder.decodeFormulae(from: data)
    }

    static func perRecordEncodedBytes(
        ofSliceFixture name: String,
        kind: PackageKind = .cask
    ) throws -> Double {
        try perRecordEncodedBytes(of: try decode(Fixture.data(name), kind: kind))
    }

    static func perRecordEncodedBytes(
        ofSyntheticIn root: URL,
        named name: String,
        kind: PackageKind,
        widened: Bool
    ) throws -> Double {
        let payload = root.appendingPathComponent("\(name).json")
        if kind == .cask {
            try SyntheticPayload.writeCasks(to: payload, count: 200, widened: widened)
        } else {
            try SyntheticPayload.writeFormulae(to: payload, count: 200, widened: widened)
        }
        defer { try? FileManager.default.removeItem(at: payload) }
        return try perRecordEncodedBytes(of: try decode(Data(contentsOf: payload), kind: kind))
    }

    /// What the widening costs a **verbatim live record**, measured by projecting
    /// that same record twice: once as published, once with the widened keys
    /// removed from the payload. Both sides are the same record, so nothing
    /// about corpus composition can distort the number.
    static func realWideningDelta(
        fixtures: [String],
        widenedKeys: [String],
        kind: PackageKind
    ) throws -> Double {
        let published = try perRecordEncodedBytes(
            of: try decode(Fixture.arrayOf(fixtures), kind: kind)
        )

        var stripped: [Any] = []
        for name in fixtures {
            guard var object = try JSONSerialization.jsonObject(with: Fixture.data(name))
                as? [String: Any] else { continue }
            for key in widenedKeys { object.removeValue(forKey: key) }
            stripped.append(object)
        }
        #expect(stripped.count == fixtures.count)
        let base = try perRecordEncodedBytes(
            of: try decode(try JSONSerialization.data(withJSONObject: stripped), kind: kind)
        )

        #expect(published > base, "removing the widened keys changed nothing, so the anchor is blind")
        return published - base
    }

    static func perRecordEncodedBytes(of resource: DecodedResource) throws -> Double {
        #expect(resource.packages.isEmpty == false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(resource.packages)
        return Double(data.count) / Double(resource.packages.count)
    }

    // MARK: - Helpers

    static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) * 1e-18
    }

    static func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cellar-footprint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func state(recordCount: Int) -> CatalogState {
        CatalogState(
            sources: [
                .casks: SourceState(
                    validators: ConditionalValidators(),
                    downloadedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    recordCount: recordCount,
                    byteCount: 0
                )
            ],
            lastSuccessAt: Date(timeIntervalSince1970: 1_800_000_000),
            skippedRecordCount: 0
        )
    }
}
