import Foundation
import Testing

@testable import Catalog

/// Whether this binary was built with optimisation.
///
/// A `-Onone` byte scan is 5–20× slower than the shipped one, so running the
/// ceiling in a debug build would assert against a number nobody experiences.
enum BuildConfiguration {
    static var isRelease: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }
}

/// The 8 ms as-you-type ceiling, measured.
///
/// This assertion is the licence for searching synchronously on the main actor
/// (design D4). If it ever breaks, the escalation is a char-bitmask pre-gate,
/// then trigrams, then an off-main hop — in that order. Weakening the number is
/// not on the list.
///
/// Run with `swift test -c release --filter SearchLatency`.
@Suite("Search latency", .serialized)
struct SearchLatencyTests {
    static let ceiling = Duration.milliseconds(8)
    static let recordCount = 15_500

    @Test(
        "p95 as-you-type latency stays under 8 ms on a realistic index",
        .enabled(if: BuildConfiguration.isRelease),
        .timeLimit(.minutes(2)),
        .heavyFixture
    )
    func p95StaysUnderCeiling() {
        // Build time is deliberately outside the measurement: the index is built
        // once per sync, the query runs on every keystroke.
        let index = PackageSearchIndex(snapshot: LatencyFixture.snapshot(count: Self.recordCount))
        #expect(index.recordCount == Self.recordCount)

        let queries = LatencyFixture.asYouTypePrefixes()
        #expect(queries.count == 50)

        // Warm-up: first-touch page faults on a 1–2 MB buffer are not latency.
        for _ in 0..<5 {
            for query in queries { _ = index.search(query) }
        }

        var samples: [Duration] = []
        samples.reserveCapacity(queries.count * 20)
        let clock = ContinuousClock()
        for _ in 0..<20 {
            for query in queries {
                let start = clock.now
                let hits = index.search(query)
                samples.append(clock.now - start)
                // Keeps the optimiser from deleting the call it is timing.
                blackHole(hits.count)
            }
        }

        #expect(samples.count == 1_000)
        let sorted = samples.sorted()
        let p95 = sorted[Int(Double(sorted.count) * 0.95)]
        let median = sorted[sorted.count / 2]

        #expect(
            p95 < Self.ceiling,
            "p95 \(p95) exceeded the \(Self.ceiling) ceiling (median \(median), max \(sorted.last!))"
        )
    }

    @Test("The latency fixture is the size and shape the ceiling is claimed for", .heavyFixture)
    func fixtureIsRealistic() {
        let snapshot = LatencyFixture.snapshot(count: Self.recordCount)

        #expect(snapshot.packages.count == Self.recordCount)
        let nameLengths = snapshot.packages.map(\.name.count)
        let descLengths = snapshot.packages.map { ($0.desc ?? "").count }
        let meanName = Double(nameLengths.reduce(0, +)) / Double(nameLengths.count)
        let meanDesc = Double(descLengths.reduce(0, +)) / Double(descLengths.count)

        // Live capture, 2026-08-01: mean name 10.2 chars, mean description 35.2.
        #expect((8.0...13.0).contains(meanName), "mean name length \(meanName)")
        #expect((30.0...42.0).contains(meanDesc), "mean description length \(meanDesc)")
        #expect(snapshot.packages.contains { ($0.desc ?? "").isEmpty })
        #expect(Set(snapshot.packages.map(\.kind)) == [.formula, .cask])
    }

    @inline(never)
    private func blackHole(_ value: Int) {
        if value == Int.min { fatalError("unreachable") }
    }
}

/// A seeded generator sized and shaped like the live catalog.
///
/// Seeded, so a latency regression is reproducible rather than a coin flip.
enum LatencyFixture {
    /// Real package names, used to make the as-you-type prefixes realistic.
    static let realNames = [
        "wget", "git", "node", "python", "openssl", "ffmpeg", "docker", "kubectl",
        "postgresql", "ripgrep"
    ]

    static func snapshot(count: Int) -> CatalogSnapshot {
        var generator = SplitMix64(seed: 0x5EED_CA7A_10_9)
        var packages: [CatalogPackage] = []
        packages.reserveCapacity(count)

        for index in 0..<count {
            let kind: PackageKind = index % 3 == 0 ? .cask : .formula
            let name: String
            if index < realNames.count {
                name = realNames[index]
            } else {
                // The `-index` suffix keeps names unique; it counts toward the
                // target length so the mean matches the live capture.
                let suffix = "-\(index)"
                let target = 3 + Int(generator.next() % 15)
                name = word(&generator, length: target - suffix.count) + suffix
            }
            let hasDescription = generator.next() % 100 >= 16  // 16% empty, as live
            let description = hasDescription
                ? sentence(&generator, targetLength: 18 + Int(generator.next() % 45))
                : nil
            let count = generator.next() % 7 == 0 ? nil : Int(generator.next() % 3_000_000)

            packages.append(
                CatalogPackage.stub(
                    kind: kind,
                    name: name,
                    desc: description,
                    installCount365d: count
                )
            )
        }

        return CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            skippedRecordCount: 0,
            packages: packages
        )
    }

    /// 50 queries: the progressive 1–5 character prefixes of 10 real names,
    /// which is exactly what an index sees while somebody types.
    static func asYouTypePrefixes() -> [String] {
        realNames.flatMap { name in
            (1...5).map { String(name.prefix($0)) }
        }
    }

    private static func word(_ generator: inout SplitMix64, length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        return String((0..<max(1, length)).map { _ in
            alphabet[Int(generator.next() % UInt64(alphabet.count))]
        })
    }

    private static func sentence(_ generator: inout SplitMix64, targetLength: Int) -> String {
        var words: [String] = []
        var length = 0
        while length < targetLength {
            let next = word(&generator, length: 2 + Int(generator.next() % 8))
            words.append(next)
            length += next.count + 1
        }
        return words.joined(separator: " ")
    }
}

/// A tiny deterministic PRNG, so the fixture is byte-identical on every machine.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
