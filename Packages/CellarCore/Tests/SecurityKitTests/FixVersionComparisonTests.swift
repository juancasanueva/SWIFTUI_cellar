import Foundation
import Testing

@testable import SecurityKit

/// The five answers a fix version can produce, and the two that are most often
/// wrongly merged.
///
/// "No fix published" and "fix unknown" are different facts. The first is an
/// advisory *stating* that nothing fixes this — RustSec's unmaintained-crate
/// records say exactly that — and the second is an advisory that never addressed
/// the question. A user who reads "no fix available" acts differently from one
/// who reads "we could not tell", and folding them loses the difference.
///
/// "Not comparable" is the third one people delete. It is what an installed
/// `1.2.3_1` against a fix at `1.2.4` produces, and the temptation is always to
/// strip the suffix and compare anyway. That is the exact leak
/// `local-package-metadata` forbids, one file away from the snooze rule.
@Suite("Fix version comparison")
struct FixVersionComparisonTests {
    // MARK: - The five cases

    @Test("A fix at or before the installed version is fixed")
    func aFixAtOrBeforeTheInstalledVersionIsFixed() throws {
        let installed = try #require(StrictSemVer.parse("1.2.4"))
        let earlier = try #require(StrictSemVer.parse("1.2.3"))
        let same = try #require(StrictSemVer.parse("1.2.4"))

        #expect(
            FixVersionComparator.compare(installed: installed, fixed: earlier)
                == .fixedAtOrBefore
        )
        // "At" is half the case name and is the boundary people get wrong: the
        // version the fix landed in is fixed, not still affected.
        #expect(
            FixVersionComparator.compare(installed: installed, fixed: same) == .fixedAtOrBefore
        )
    }

    @Test("A fix after the installed version leaves it affected")
    func aFixAfterTheInstalledVersionLeavesItAffected() throws {
        let installed = try #require(StrictSemVer.parse("1.2.3"))
        let fixed = try #require(StrictSemVer.parse("1.2.4"))

        #expect(
            FixVersionComparator.compare(installed: installed, fixed: fixed) == .stillAffected
        )
    }

    /// A declared "there is no fix" is **not** "we do not know".
    @Test("A declared absence of a fix is not the same as an unknown fix")
    func aDeclaredNoFixIsNotAnUnknownFix() throws {
        let installed = try #require(StrictSemVer.parse("1.2.3"))

        #expect(
            FixVersionComparator.resolve(installed: .comparable(installed), fix: .notPublished)
                == .noFixPublished
        )
        #expect(
            FixVersionComparator.resolve(installed: .comparable(installed), fix: .unknown)
                == .fixUnknown
        )
        #expect(FixVersionComparison.noFixPublished != .fixUnknown)
    }

    /// The spec's own scenario, and the single most misreadable interaction in
    /// the design. `1.2.3_1` is a Homebrew packaging revision: it is *covered*,
    /// because OSV was queried with upstream `1.2.3`, and it is *not comparable*,
    /// because the installed string is not strict SemVer. No ordering verdict is
    /// produced in either direction.
    @Test("A Homebrew revision against a published fix is not comparable, in either direction")
    func aHomebrewRevisionIsNotComparable() throws {
        let fixed = try #require(StrictSemVer.parse("1.2.4"))
        // The installed string, as the corpus really contains it.
        #expect(StrictSemVer.parse("1.2.3_1") == nil)

        let verdict = FixVersionComparator.resolve(
            installed: .uninterpretable(.homebrewRevision),
            fix: .published(fixed)
        )

        #expect(verdict == .notComparable(scheme: .homebrewRevision))
        #expect(verdict != .stillAffected)
        #expect(verdict != .fixedAtOrBefore)
    }

    /// The other side of the same gap: the advisory's fixed string is the one
    /// that will not parse. `2026-07-16` is a real installed shape and a real
    /// shape for a declared fix in a date-versioned ecosystem.
    @Test("An uninterpretable fixed version is not comparable either")
    func anUninterpretableFixedVersionIsNotComparable() throws {
        let installed = try #require(StrictSemVer.parse("1.2.3"))

        #expect(
            FixVersionComparator.resolve(
                installed: .comparable(installed),
                fix: .publishedUninterpretable(.other)
            ) == .notComparable(scheme: .other)
        )
    }

    /// All five, reached from `resolve`, so the matrix is exhaustive rather than
    /// five separate tests that happen to cover it.
    @Test("Every one of the five verdicts is reachable and distinct")
    func everyVerdictIsReachableAndDistinct() throws {
        let older = try #require(StrictSemVer.parse("1.2.3"))
        let newer = try #require(StrictSemVer.parse("1.2.4"))

        let verdicts: [FixVersionComparison] = [
            FixVersionComparator.resolve(installed: .comparable(newer), fix: .published(older)),
            FixVersionComparator.resolve(installed: .comparable(older), fix: .published(newer)),
            FixVersionComparator.resolve(installed: .comparable(older), fix: .notPublished),
            FixVersionComparator.resolve(installed: .comparable(older), fix: .unknown),
            FixVersionComparator.resolve(
                installed: .uninterpretable(.homebrewRevision),
                fix: .published(newer)
            )
        ]

        #expect(verdicts == [
            .fixedAtOrBefore,
            .stillAffected,
            .noFixPublished,
            .fixUnknown,
            .notComparable(scheme: .homebrewRevision)
        ])
        #expect(Set(verdicts).count == 5, "two verdicts collapsed into one")
    }

    /// The scheme is carried, not flattened: "not comparable, because it is a
    /// Homebrew revision" and "not comparable, because it is a date" are
    /// different things to tell a user.
    @Test("The not-comparable verdict names which scheme defeated it")
    func theNotComparableVerdictNamesItsScheme() {
        #expect(
            FixVersionComparison.notComparable(scheme: .homebrewRevision)
                != .notComparable(scheme: .other)
        )
    }

    // MARK: - The type-level guard

    /// The guard that makes the whole boundary structural rather than
    /// disciplinary.
    ///
    /// A comparator that accepts two `String`s can be handed two Homebrew
    /// version strings, and `local-package-metadata` forbids exactly that
    /// comparison — a wrong ordering there silently suppresses a real update
    /// forever. The manifest half of the guarantee is task 1.2 (`BrewClient`
    /// cannot reach `SecurityKit`); this is the type half, and together they
    /// mean the comparison cannot be reached *and* could not be misused if it
    /// were.
    ///
    /// The claim is deliberately absolute and therefore checkable: the word
    /// `String` does not appear anywhere in the file. Not in a signature, not in
    /// an overload, not in a raw value, not in a convenience initialiser someone
    /// adds later because it seemed harmless.
    @Test("The comparator cannot be called with strings")
    func theComparatorCannotBeCalledWithStrings() throws {
        let sources = try SecurityKitSources.load()
        let file = try #require(sources.first { $0.name == "FixVersionComparison.swift" })

        // Anchored positively, or a renamed or emptied file passes for free.
        #expect(file.code.contains("StrictSemVer"), "the scan did not read the comparator")
        #expect(file.code.contains("func compare("), "the scan did not read the comparison")

        for token in ["String", "Substring", "Character", "rawValue"] {
            #expect(
                file.code.containsIdentifier(token) == false,
                "\(token) appears in the comparator's source"
            )
        }
    }

    /// The negative control: the scan pointed at a comparator that *does* take
    /// strings must object, or the assertion above would pass against anything.
    @Test(
        "The string scanner detects a comparator it should reject",
        arguments: [
            "public static func compare(installed: String, fixed: String) -> Bool { }",
            "public init?(rawValue: String) { }",
            "extension FixVersionComparison { var label: String { \"\" } }",
            "func parse(_ text: Substring) -> Self? { nil }"
        ]
    )
    func theStringScannerDetectsAStringComparator(violation: String) {
        #expect(
            ["String", "Substring", "Character", "rawValue"]
                .contains { violation.containsIdentifier($0) },
            "the scanner missed a string-typed surface: \(violation)"
        )
    }
}
