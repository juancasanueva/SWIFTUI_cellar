//
//  BundleNamingTests.swift
//  cellarTests
//

import Foundation
import Testing

/// Reads the four files that decide what the delivered bundle is called, off disk.
///
/// Deliberately self-contained rather than importing `UpdateProjectSources` or
/// `ReleasePipelineSources`: the rename is a net-new, independently revertible
/// change, and rollback should be the deletion of a single file rather than an
/// unpicking of a shared helper. That is the same reason `UpdateProjectSources`
/// and `CaskZapSources` each redeclare the `#filePath` anchor — the test runner
/// promises nothing about the working directory, so the repository root is found
/// relative to this file and never relative to where the runner happens to start.
nonisolated enum BundleNamingSources {
    /// The repository root, found relative to this file.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static let projectFile = "cellar.xcodeproj/project.pbxproj"
    static let schemeFile = "cellar.xcodeproj/xcshareddata/xcschemes/cellar.xcscheme"
    static let releaseScript = "scripts/release.sh"
    static let releaseWorkflow = ".github/workflows/release.yml"

    static func url(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }

    static func text(_ relativePath: String) throws -> String {
        try String(contentsOf: url(relativePath), encoding: .utf8)
    }

    /// How many times `needle` occurs in `haystack`, counted exactly.
    ///
    /// Exact counts, never `contains`, are the whole discipline of this file.
    /// `"Home-Cellar.app"` *contains* `"Cellar.app"` but does **not** contain
    /// `"cellar.app"`, so a substring assertion in either direction is the trap
    /// this rename sets. The capital `C` is the assertion, and no comparison
    /// here may be case-insensitive.
    static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }

    /// Every `XCBuildConfiguration` body in the project file, as text.
    ///
    /// A build setting is only meaningful inside the configuration that owns it:
    /// "the file contains `PRODUCT_NAME = …;`" would be satisfied by a single
    /// occurrence in a single configuration, while this change must land both of
    /// its settings in **both** app-target blocks or the Debug and Release
    /// bundles stop agreeing about what they are called. So the file is cut into
    /// blocks first and every assertion is made per block. A block runs from its
    /// `isa` line to the two-tab `};` that closes it; the three-tab `};` closing
    /// the inner `buildSettings` dictionary cannot be mistaken for it.
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

    /// How many configuration blocks declare `setting`, counted per block.
    static func appTargetBlocksDeclaring(_ setting: String) throws -> Int {
        try appTargetBuildConfigurationBlocks().filter { $0.contains(setting) }.count
    }
}

/// What the build system, the shared scheme, the release script and the release
/// workflow must declare so that exactly one name reaches a user's disk.
///
/// Every assertion below is an **exact count** against a case-sensitive literal.
/// That is not stylistic: the old name is a case-folded substring of the new one
/// in one direction and not the other, so `contains` and `caseInsensitiveCompare`
/// both produce assertions that pass while the rename is half-done.
@Suite("Bundle naming")
struct BundleNamingTests {
    /// Quoted, because that is how Xcode serialises it. `Home-Cellar` contains a
    /// hyphen, which is outside the bare-identifier set the OpenStep-plist writer
    /// leaves unquoted, so pinning the unquoted form would pass exactly once —
    /// until the next time any tool rewrites the project file.
    static let productName = "PRODUCT_NAME = \"Home-Cellar\";"

    /// Bare, for the same reason inverted: `cellar` *is* a bare identifier, so
    /// Xcode writes it without quotes and a quoted assertion would rot.
    static let moduleName = "PRODUCT_MODULE_NAME = cellar;"

    static let testHost =
        "TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/Home-Cellar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Home-Cellar\";"

    // MARK: - Unit 1 — the product is renamed and the module is pinned, together

    /// The rename and the pin are asserted in **one** test on purpose.
    ///
    /// `PRODUCT_MODULE_NAME` is undeclared today, so the module name resolves
    /// from the undocumented default `$(PRODUCT_NAME:c99extidentifier)`. Renaming
    /// the product alone would silently turn the Swift module into `Home_Cellar`
    /// and break all 22 `@testable import cellar` files. Pinning the module is
    /// therefore not an independent tidy-up: it is the half of this change that
    /// makes the other half survivable, and a reader who finds one line without
    /// the other should find them failing in the same place.
    ///
    /// Two counts rather than two presence checks. `== 2` fails a one-block edit,
    /// which is exactly what `appTargetConfigurationsAreIdenticalModuloName`
    /// already forbids and what this change would otherwise be the first to try.
    @Test("Both app-target configurations name the product Home-Cellar and pin the module to cellar")
    func bothAppTargetConfigurationsNameTheProductAndPinTheModule() throws {
        let blocks = try BundleNamingSources.appTargetBuildConfigurationBlocks()

        #expect(blocks.count == 2)
        #expect(try BundleNamingSources.appTargetBlocksDeclaring(Self.productName) == 2)
        #expect(try BundleNamingSources.appTargetBlocksDeclaring(Self.moduleName) == 2)
    }

    // MARK: - Unit 2 — the test host follows the product, and nothing is left behind

    /// The test host is the one path in the project file that must move in
    /// lockstep with the product, in both directions.
    ///
    /// `TEST_HOST` names the bundle the test runner launches. A `PRODUCT_NAME`
    /// change without it leaves both test targets pointing at a bundle that no
    /// longer exists, and the whole `cellarTests` bundle fails to launch — a
    /// state that is not merely red, it is unrunnable, which is why the two edits
    /// are one commit.
    ///
    /// The zero-count half is the anti-leftover assertion: `cellar.app` must not
    /// survive **anywhere** in the file, comment or value. It is a separate claim
    /// from "the new path is present twice", because a file can carry both.
    @Test("The test host resolves through the renamed bundle and no old bundle name survives")
    func theTestHostResolvesThroughTheRenamedBundle() throws {
        let project = try BundleNamingSources.text(BundleNamingSources.projectFile)

        #expect(BundleNamingSources.occurrences(of: Self.testHost, in: project) == 2)
        #expect(BundleNamingSources.occurrences(of: "cellar.app", in: project) == 0)
    }

    // MARK: - Unit 4 — the shared scheme builds the renamed bundle, and stops there

    /// Three `BuildableName` sites and one anti-overreach count.
    ///
    /// The scheme names the built product in its Build, Test and Launch/Profile
    /// sections; all three must move or `xcodebuild` and Xcode disagree about
    /// what they just produced. The `BlueprintName` count is the other half:
    /// the blueprint names the Xcode **target**, which this change deliberately
    /// does not rename. Asserting it still reads `cellar` exactly three times is
    /// how an over-eager find-and-replace fails here rather than in the next
    /// person's `-scheme cellar` invocation.
    ///
    /// `BlueprintName = "cellar"` carries its closing quote for that reason: the
    /// scheme also declares `"cellarTests"` and `"cellarUITests"`, and a prefix
    /// match would count five where the truth is three.
    @Test("The shared scheme builds Home-Cellar.app without renaming the blueprint")
    func theSharedSchemeBuildsTheRenamedBundle() throws {
        let scheme = try BundleNamingSources.text(BundleNamingSources.schemeFile)

        #expect(BundleNamingSources.occurrences(of: "BuildableName = \"Home-Cellar.app\"", in: scheme) == 3)
        #expect(BundleNamingSources.occurrences(of: "BuildableName = \"cellar.app\"", in: scheme) == 0)
        #expect(BundleNamingSources.occurrences(of: "BlueprintName = \"cellar\"", in: scheme) == 3)
    }

    // MARK: - Unit 3 — the release script stops letting one constant mean four things

    /// `SCHEME` served four roles: the scheme `xcodebuild` builds, the archive
    /// filename, the exported bundle name, and the main executable name. Two of
    /// those follow the Xcode target and two follow the product, and this change
    /// moves the product without moving the target — so a rename that kept one
    /// constant would have to be wrong about half of them. That is why this is a
    /// split and not a substitution, and why the split is itself the assertion.
    ///
    /// Six counts, in three deliberate pairs:
    ///
    /// - `PRODUCT` is declared, and `-scheme "$SCHEME"` **still** invokes the
    ///   scheme by its unchanged name. The second half is the one that catches an
    ///   over-eager rename: a script that passed `-scheme "$PRODUCT"` would fail
    ///   only at release time, on a tag, with nothing built.
    /// - The two old spellings are gone. Zero, not "fewer".
    /// - The two new spellings appear exactly twice each — once on the exported
    ///   copy and once on the re-downloaded, notarization-verified copy. Both
    ///   paths must move together or `verify` inspects a bundle the export step
    ///   never produced.
    ///
    /// `ARCHIVE_PATH="$BUILD/$SCHEME.xcarchive"` is deliberately *not* covered by
    /// the `$SCHEME.app` count and deliberately not renamed (DD-4): the archive is
    /// a build intermediate no user ever sees.
    @Test("The release script separates the product name from the scheme name")
    func theReleaseScriptSeparatesTheProductFromTheScheme() throws {
        let script = try BundleNamingSources.text(BundleNamingSources.releaseScript)

        #expect(script.contains("readonly PRODUCT=\"Home-Cellar\""))
        #expect(script.contains("-scheme \"$SCHEME\""))

        #expect(BundleNamingSources.occurrences(of: "$SCHEME.app", in: script) == 0)
        #expect(BundleNamingSources.occurrences(of: "MacOS/$SCHEME", in: script) == 0)

        #expect(BundleNamingSources.occurrences(of: "$PRODUCT.app", in: script) == 2)
        #expect(BundleNamingSources.occurrences(of: "MacOS/$PRODUCT", in: script) == 2)
    }

    // MARK: - Unit 5 — the workflow inspects the path that now exists

    /// The workflow hardcodes the export path rather than deriving it, so it does
    /// not follow `PRODUCT_NAME` on its own.
    ///
    /// This is the one line in the release run that would fail *after* signing
    /// and *before* publishing: `codesign -dvvv` on a path that no longer exists
    /// exits non-zero on a tag, with an archive already built and nothing
    /// released. Nothing else notices, because the asset name, the zip path and
    /// the display-name gate were all already spelled `Home-Cellar`.
    ///
    /// Both halves are asserted: the new path is present *and* the old one is
    /// gone. A workflow that gained the new line while keeping the old one would
    /// still fail on the same tag.
    @Test("The release workflow inspects the renamed export path")
    func theWorkflowInspectsTheRenamedExportPath() throws {
        let workflow = try BundleNamingSources.text(BundleNamingSources.releaseWorkflow)

        #expect(workflow.contains("build/export/Home-Cellar.app"))
        #expect(!workflow.contains("build/export/cellar.app"))
    }
}
