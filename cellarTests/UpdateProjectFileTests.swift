//
//  UpdateProjectFileTests.swift
//  cellarTests
//

import Foundation
import Testing

/// Reads `cellar.xcodeproj/project.pbxproj` off disk.
///
/// Deliberately self-contained rather than importing `ReleasePipelineSources`:
/// the update slice is a net-new, independently revertible change, and rollback
/// should be the deletion of a single file rather than an unpicking of a shared
/// helper. That is the same reason `ReleasePipelineSources` itself copied the
/// `#filePath` anchor from `AppSecuritySources` instead of importing it — the
/// test runner promises nothing about the working directory.
nonisolated enum UpdateProjectSources {
    /// The repository root, found relative to this file.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
    }

    static let projectFile = "cellar.xcodeproj/project.pbxproj"

    static func url(_ relativePath: String) -> URL {
        repositoryRoot.appendingPathComponent(relativePath)
    }

    static func text(_ relativePath: String) throws -> String {
        try String(contentsOf: url(relativePath), encoding: .utf8)
    }

    static func projectText() throws -> String {
        try text(projectFile)
    }

    /// Every `XCBuildConfiguration` body in the project file, as text.
    ///
    /// A build setting is only meaningful inside the configuration that owns it:
    /// "the file contains `INFOPLIST_FILE = …;`" would be satisfied by a single
    /// occurrence in a single configuration, and this change must land its two
    /// settings in **both** app-target blocks or the Debug and Release bundles
    /// stop agreeing about what feed they trust. So the file is cut into blocks
    /// first and every assertion is made per block. A block runs from its `isa`
    /// line to the two-tab `};` that closes it; the three-tab `};` closing the
    /// inner `buildSettings` dictionary cannot be mistaken for it.
    static func buildConfigurationBlocks() throws -> [String] {
        let marker = "isa = XCBuildConfiguration;"
        let terminator = "\n\t\t};"
        return try projectText()
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

/// What `project.pbxproj` must declare for the update slice.
///
/// Structural, over text, because these are claims about what the repository
/// declares rather than about what a test-host binary happens to contain. The
/// proposal's pbxproj change list is literal and binding, so every assertion
/// below maps to one of its numbered items and nothing else is pinned here.
@Suite("Update project file")
struct UpdateProjectFileTests {
    static let applicationCategory =
        "INFOPLIST_KEY_LSApplicationCategoryType = \"public.app-category.developer-tools\";"

    // MARK: - T12(a) — pbxproj item 6, the application category

    /// The category lands in **both** app-target blocks, and the generator stays on.
    ///
    /// Two counts rather than one presence check. `count == 2` fails a one-block
    /// edit, which is the mistake `appTargetConfigurationsAreIdenticalModuloName`
    /// exists to catch and which this change would otherwise be the first to
    /// make. `GENERATE_INFOPLIST_FILE = YES;` is re-asserted here because the
    /// category is an `INFOPLIST_KEY_*` setting: it only reaches the bundle while
    /// the generator is running, so turning the generator off would silently
    /// drop it rather than fail loudly.
    @Test("Both app-target configurations declare the developer-tools application category")
    func appTargetsDeclareTheApplicationCategory() throws {
        let blocks = try UpdateProjectSources.appTargetBuildConfigurationBlocks()

        #expect(blocks.count == 2)
        #expect(try UpdateProjectSources.appTargetBlocksDeclaring(Self.applicationCategory) == 2)
        #expect(try UpdateProjectSources.appTargetBlocksDeclaring("GENERATE_INFOPLIST_FILE = YES;") == 2)
    }
}
