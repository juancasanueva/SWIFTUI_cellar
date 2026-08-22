//
//  ReleasePipelineCompositionTests.swift
//  cellarTests
//

import Foundation
import Testing

/// Reads the repository off disk, the way `AppSecuritySources` reads `cellar/`.
///
/// Deliberately self-contained rather than importing `AppSecuritySources`: the
/// release pipeline is a net-new, independently revertible slice, and rollback
/// should be the deletion of a single file rather than an unpicking of a shared
/// helper. The `#filePath` anchor is the same idiom for the same reason — the
/// test runner promises nothing about the working directory.
nonisolated enum ReleasePipelineSources {
    /// The repository root, found relative to this file.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static func url(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }

    static func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relativePath).path)
    }

    static func text(_ relativePath: String) throws -> String {
        try String(contentsOf: url(relativePath), encoding: .utf8)
    }

    static let projectFile = "cellar.xcodeproj/project.pbxproj"

    /// Every `XCBuildConfiguration` body in the project file, as text.
    ///
    /// A build setting is only meaningful inside the configuration that owns it —
    /// "the file contains `ARCHS = arm64;`" would be satisfied by one occurrence
    /// in one configuration, which is exactly the mistake DD-9 guards against. So
    /// the file is cut into blocks first, and every assertion below is made per
    /// block. A block runs from its `isa` line to the two-tab `};` that closes
    /// it; the three-tab `};` that closes the inner `buildSettings` dictionary
    /// cannot be mistaken for it.
    static func buildConfigurationBlocks() throws -> [String] {
        let marker = "isa = XCBuildConfiguration;"
        let terminator = "\n\t\t};"
        return try text(projectFile)
            .components(separatedBy: marker)
            .dropFirst()
            .map { chunk in
                guard let end = chunk.range(of: terminator) else { return chunk }
                return String(chunk[chunk.startIndex..<end.lowerBound])
            }
    }

    /// The two configurations that build the shipped app.
    ///
    /// The trailing `;` is load-bearing: `com.juancasanueva.cellarTests;` also
    /// starts with `com.juancasanueva.cellar`, and the test target must not be
    /// mistaken for an app target.
    static func appTargetBuildConfigurationBlocks() throws -> [String] {
        try buildConfigurationBlocks()
            .filter { $0.contains("PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;") }
    }
}

/// What the project file and the string catalog must say about a delivered build.
///
/// Everything here is read off disk as text: these are claims about what the
/// repository declares, not about what a test-host binary happens to contain.
/// The one exception is the copyright, which is read from the bundle because the
/// spec's claim is about the *delivered* value rather than the declared one.
@Suite("Release metadata")
struct ReleaseMetadataTests {
    // MARK: - 1.1 T11 — the arm64 pin lands in both app-target configurations

    /// D3/DD-9: `ARCHS = arm64` in **both** app-target blocks.
    ///
    /// A design-owned pin rather than spec coverage — the spec's arm64 scenario
    /// is a `ci-gate` against the exported binary (`lipo -archs`), because the
    /// test host is built by `xcodebuild test`, not by `archive`, and therefore
    /// cannot prove what the release binary contains. This asserts the *cause*;
    /// the gate asserts the effect.
    @Test("Both app-target build configurations pin ARCHS to arm64")
    func appTargetsPinARM64() throws {
        let blocks = try ReleasePipelineSources.appTargetBuildConfigurationBlocks()

        #expect(blocks.count == 2)
        #expect(blocks.filter { $0.contains("name = Debug;") }.count == 1)
        #expect(blocks.filter { $0.contains("name = Release;") }.count == 1)

        #expect(blocks.filter { $0.contains("ARCHS = arm64;") }.count == 2)
    }

    // MARK: - 1.3 T14 — the Debug/Release byte-identity invariant

    /// The two app-target configurations are the same configuration twice, save
    /// for their name.
    ///
    /// A design-owned pin, not spec coverage. DD-9 chose to set `ARCHS` in both
    /// blocks *because* this invariant currently holds across all ~30 settings,
    /// and a Debug build whose architecture differs from Release is a trap. The
    /// invariant is worth more than the smaller diff, but only if something
    /// notices when it breaks — nothing did, until this.
    ///
    /// If the pre-authored Manual-signing fallback (DD-5, D9) is ever applied,
    /// this assertion must be **explicitly relaxed** to compare modulo
    /// `CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY` and
    /// `PROVISIONING_PROFILE_SPECIFIER`, with the reason recorded here. Deleting
    /// it is not an option.
    @Test("The two app-target build configurations differ only in their name")
    func appTargetConfigurationsAreIdenticalModuloName() throws {
        let blocks = try ReleasePipelineSources.appTargetBuildConfigurationBlocks()
        let debug = try #require(blocks.first { $0.contains("name = Debug;") })
        let release = try #require(blocks.first { $0.contains("name = Release;") })

        func settings(_ block: String) -> [String] {
            block
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("name = ") }
        }

        #expect(settings(debug) == settings(release))
        // The comparison is only meaningful if it compared something.
        #expect(settings(debug).contains("ARCHS = arm64;"))
    }

    // MARK: - 1.3 T17a — the project file is never bumped per release

    /// S8: the checked-in version values stay at `1.0.0 / 1`, because the tag is
    /// the source of truth and CI supplies both at build time.
    ///
    /// The two `ENABLE_*` settings are the S10 gate's blast radius, pinned here
    /// rather than only in the release run: hardened runtime on and sandbox off
    /// are what make the delivered build both notarizable and able to exec
    /// `brew`. Flipping either in the project file would fail the pipeline late,
    /// after Apple had already been asked for a round trip.
    @Test("The app targets keep 1.0.0 / 1, hardened runtime on, and the sandbox off")
    func appTargetsKeepCheckedInVersionAndRuntimePosture() throws {
        let blocks = try ReleasePipelineSources.appTargetBuildConfigurationBlocks()

        for setting in [
            "MARKETING_VERSION = 1.0.0;",
            "CURRENT_PROJECT_VERSION = 1;",
            "ENABLE_APP_SANDBOX = NO;",
            "ENABLE_HARDENED_RUNTIME = YES;"
        ] {
            #expect(blocks.filter { $0.contains(setting) }.count == 2, "\(setting) must hold in both blocks")
        }
    }
}
