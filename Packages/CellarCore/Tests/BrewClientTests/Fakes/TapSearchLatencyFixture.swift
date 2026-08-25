import Foundation
import Testing

@testable import BrewClient
@testable import Catalog

/// Whether this binary was built with optimisation.
///
/// A `-Onone` byte scan is 5–20× slower than the shipped one, so measuring the
/// ceiling in a debug build would assert against a number nobody experiences.
/// The shipped PS6 measurement gates on exactly this, and the combined turn
/// gates on it for exactly the same reason.
enum TapSearchBuildConfiguration {
    static var isRelease: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }
}

/// The two inventories one keystroke turn touches: the catalog PS6 measures
/// over, and a resident tap inventory of realistic size.
///
/// **Why the catalog generator is reproduced rather than imported.** PS6's
/// generator lives in `CatalogTests`, and one SwiftPM test target cannot import
/// another; moving it into `CellarTestSupport` would give that deliberately
/// dependency-free target an edge on `Catalog`. It is therefore reproduced
/// verbatim — same seed, same PRNG, same shape rules, so the same bytes — and
/// `theCatalogFixtureIsTheOnePS6MeasuresOver` re-asserts the shipped size and
/// shape invariants rather than trusting the copy.
enum TapSearchLatencyFixture {
    /// The size PS6's ceiling is claimed for.
    static let catalogRecordCount = 15_500
    /// "Several taps publishing approximately 500 packages in total."
    static let tapPackageCount = 500
    static let tapCount = 6

    /// Real package names, used to make the as-you-type prefixes realistic.
    static let realNames = [
        "wget", "git", "node", "python", "openssl", "ffmpeg", "docker", "kubectl",
        "postgresql", "ripgrep"
    ]

    // MARK: - The catalog half (PS6's fixture)

    static func catalogSnapshot(count: Int = catalogRecordCount) -> CatalogSnapshot {
        var generator = TapSearchSplitMix64(seed: 0x5EED_CA7A_10_9)
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
            let installs = generator.next() % 7 == 0 ? nil : Int(generator.next() % 3_000_000)

            packages.append(
                TapSearchFixture.catalogPackage(
                    kind, name, desc: description, installCount: installs
                )
            )
        }

        return CatalogSnapshot(
            generatedAt: Date(timeIntervalSince1970: 0),
            skippedRecordCount: 0,
            packages: packages
        )
    }

    // MARK: - The tap half

    /// Six third-party taps publishing ~500 packages between them, roughly one
    /// cask in three, seeded so a latency regression is reproducible.
    ///
    /// Every fifth token is built from a real name so the as-you-type prefixes
    /// hit the tap source as well as the catalog: a fixture nothing matches
    /// would measure the scan and never the emission.
    static func tapInventory() -> TapInventory {
        var generator = TapSearchSplitMix64(seed: 0x7A9_5EED_11_0B)
        var formulae: [[String]] = Array(repeating: [], count: tapCount)
        var casks: [[String]] = Array(repeating: [], count: tapCount)

        for index in 0..<tapPackageCount {
            let owner = index % tapCount
            let tapName = "owner\(owner)/tools"
            let token: String
            if index % 5 == 0 {
                token = "\(realNames[index % realNames.count])-tap\(index)"
            } else {
                token = word(&generator, length: 4 + Int(generator.next() % 10)) + "-\(index)"
            }
            let published = "\(tapName)/\(token)"
            // Every third package **of each tap**, so no tap is formula-only:
            // `index % 3` would land on only two of the six owners.
            if (index / tapCount) % 3 == 0 {
                casks[owner].append(published)
            } else {
                formulae[owner].append(published)
            }
        }

        return TapInventory(taps: (0..<tapCount).map { owner in
            TapSearchFixture.tap(
                "owner\(owner)/tools",
                formulae: formulae[owner],
                casks: casks[owner]
            )
        })
    }

    /// A machine with a few of those tap packages installed, so the three-state
    /// resolution is exercised on every turn rather than short-circuited.
    static func installedInventory(from taps: TapInventory) -> InstalledInventory {
        let published = taps.taps.flatMap { tap in
            (tap.formulaNames.map { (PackageKind.formula, $0, tap.name) }
                + tap.caskTokens.map { (PackageKind.cask, $0, tap.name) })
        }
        let sampled = stride(from: 0, to: published.count, by: 12).map { published[$0] }
        return InstalledInventory(packages: sampled.map { kind, name, tap in
            InstalledFixture.receipt(
                kind,
                String(name.dropFirst(tap.count + 1)),
                tap: tap
            )
        })
    }

    // MARK: - Queries

    /// 100 queries: the progressive 1–10 character prefixes of 10 real names,
    /// which is what both sources see while somebody types.
    static func asYouTypePrefixes() -> [String] {
        realNames.flatMap { name in
            (1...10).map { String(name.prefix($0)) }
        }
    }

    // MARK: - Word generation

    private static func word(_ generator: inout TapSearchSplitMix64, length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        return String((0..<max(1, length)).map { _ in
            alphabet[Int(generator.next() % UInt64(alphabet.count))]
        })
    }

    private static func sentence(
        _ generator: inout TapSearchSplitMix64,
        targetLength: Int
    ) -> String {
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
struct TapSearchSplitMix64 {
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
