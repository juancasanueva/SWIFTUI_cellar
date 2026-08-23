//
//  AppVersionTests.swift
//  UpdatesTests
//

import Foundation
import Testing

@testable import Updates

/// One row of the ordering table: two versions and the claim that the second is
/// the newer of the two.
struct OrderingCase: Sendable, CustomStringConvertible {
    let olderVersion: String
    let olderBuild: String?
    let newerVersion: String
    let newerBuild: String?
    let reason: String

    var description: String { reason }
}

/// A malformed input and the named failure it must produce.
struct MalformedShape: Sendable, CustomStringConvertible {
    let input: String
    let build: String?
    let failure: AppVersionParseFailure

    var description: String { "\(input.isEmpty ? "<empty>" : input) (\(build ?? "no build"))" }
}

/// The two raw strings a bundle's information dictionary hands over.
struct RawPair: Sendable, CustomStringConvertible {
    let short: String?
    let build: String?

    var description: String { "\(short ?? "nil") / \(build ?? "nil")" }
}

/// What the app is allowed to claim about its own version, and how two versions
/// compare.
///
/// Everything here is driven by literal strings, so it is a pure unit test with
/// no bundle in it. The app-side read is one line of dependency injection and is
/// covered structurally by the bundle suite in `cellarTests`.
@Suite("App version")
struct AppVersionTests {
    // MARK: - T1 — the ordering table

    static let orderingTable: [OrderingCase] = [
        OrderingCase(
            olderVersion: "1.0.0",
            olderBuild: "9",
            newerVersion: "1.0.1",
            newerBuild: "1",
            reason: "a higher marketing version wins even with a lower build number"
        ),
        OrderingCase(
            olderVersion: "1.0.0",
            olderBuild: "1",
            newerVersion: "1.0.0",
            newerBuild: "2",
            reason: "a rebuild of the same marketing version is newer"
        ),
        OrderingCase(
            olderVersion: "0.0.1-rc.1",
            olderBuild: nil,
            newerVersion: "0.0.1",
            newerBuild: nil,
            reason: "a prerelease sorts below its own release"
        ),
        OrderingCase(
            olderVersion: "1.0.0-rc.1",
            olderBuild: nil,
            newerVersion: "1.0.0-rc.2",
            newerBuild: nil,
            reason: "a later release candidate is newer than an earlier one"
        )
    ]

    /// The whole ordering contract, one row at a time.
    ///
    /// Each row asserts the comparison in **both** directions and asserts the two
    /// versions are distinct. A `<` that is merely never true would satisfy a
    /// one-directional check, and an ordering that collapsed two versions into
    /// equality would satisfy both.
    @Test("Versions compare by marketing version, then prerelease, then build", arguments: orderingTable)
    func versionsCompareInOrder(testCase: OrderingCase) throws {
        let older = try AppVersion(parsing: testCase.olderVersion, buildNumber: testCase.olderBuild)
        let newer = try AppVersion(parsing: testCase.newerVersion, buildNumber: testCase.newerBuild)

        #expect(older < newer)
        #expect(newer > older)
        #expect(older != newer)
    }

    /// A prerelease is *reported* as one, not merely ordered as one.
    ///
    /// The spec asks for both: `0.0.1-rc.1` must parse as a prerelease and must
    /// order below `0.0.1`. An implementation that dropped the suffix entirely
    /// would order the two as equal and would still answer "not a prerelease"
    /// truthfully, which is why the report is asserted separately.
    @Test("A prerelease suffix is parsed, not discarded")
    func aPrereleaseSuffixIsParsed() throws {
        let candidate = try AppVersion(parsing: "0.0.1-rc.1")
        let release = try AppVersion(parsing: "0.0.1")

        let prerelease = try #require(candidate.prerelease)
        #expect(prerelease.identifier == "rc")
        #expect(prerelease.ordinal == 1)

        #expect(release.prerelease == nil)
        #expect(candidate.major == 0)
        #expect(candidate.minor == 0)
        #expect(candidate.patch == 1)
    }

    // MARK: - T2 — every malformed shape is a typed outcome

    static let malformedShapes: [MalformedShape] = [
        MalformedShape(input: "", build: nil, failure: .empty),
        MalformedShape(input: "1.0", build: nil, failure: .wrongComponentCount("1.0")),
        MalformedShape(input: "1.0.x", build: nil, failure: .nonNumericComponent("x")),
        MalformedShape(input: "v1.0.0", build: nil, failure: .nonNumericComponent("v1")),
        MalformedShape(input: "1.0.0", build: "seven", failure: .nonNumericBuildNumber("seven"))
    ]

    /// Every malformed shape names itself.
    ///
    /// A typed case rather than a `Bool` or a `nil`, because the caller that
    /// eventually surfaces this has to say *what* was wrong: "1.0" and "1.0.x"
    /// are different defects with different fixes, and an implementation that
    /// collapsed them would be indistinguishable from one that guessed.
    ///
    /// There is deliberately no fallback: no `0.0.0`, no truncation of `v1.0.0`
    /// to `1.0.0`. A fabricated version compares, and a version that compares is
    /// a version that can offer or refuse an update for the wrong reason.
    @Test("A malformed version throws its own named failure", arguments: malformedShapes)
    func aMalformedVersionThrowsItsNamedFailure(shape: MalformedShape) {
        #expect(throws: shape.failure) {
            try AppVersion(parsing: shape.input, buildNumber: shape.build)
        }
    }

    // MARK: - T7a — the pair the running bundle supplies

    /// The two raw strings an information dictionary hands over.
    ///
    /// `1.0.0` and `7` is the spec's own example. The build number is asserted as
    /// an `Int` rather than as the string it arrived as, because "build 7" and
    /// "build 07" are the same build and only one of them survives a string
    /// comparison.
    @Test("The version pair is built from the bundle's two raw strings")
    func theVersionPairIsBuiltFromRawStrings() throws {
        let version = try #require(AppVersion(shortVersionString: "1.0.0", buildNumber: "7"))

        #expect(version.major == 1)
        #expect(version.minor == 0)
        #expect(version.patch == 0)
        #expect(version.prerelease == nil)
        #expect(version.buildNumber == 7)
    }

    /// Absent or unparseable input produces **no version at all**.
    ///
    /// The failable initialiser is what the launch-time read uses, and the only
    /// safe answer to "this bundle does not say what it is" is silence. A
    /// substituted placeholder would be a version the app did not build with,
    /// which the spec forbids in the same breath as it forbids displaying one.
    @Test(
        "An absent or unparseable pair yields no version",
        arguments: [
            RawPair(short: nil, build: "7"),
            RawPair(short: "1.0.0", build: nil),
            RawPair(short: nil, build: nil),
            RawPair(short: "not-a-version", build: "7"),
            RawPair(short: "1.0.0", build: "seven")
        ]
    )
    func anAbsentOrUnparseablePairYieldsNoVersion(pair: RawPair) {
        #expect(AppVersion(shortVersionString: pair.short, buildNumber: pair.build) == nil)
    }
}
