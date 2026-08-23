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

    /// The body of one `/* Begin … section */ … /* End … section */` pair.
    ///
    /// An empty string when the section does not exist, which is a real answer
    /// rather than a missing one: the project had no `XCRemoteSwiftPackageReference`
    /// section at all before this change, so "the section is absent" and "the
    /// section is present but empty" must both read as zero entries.
    static func section(_ name: String, in project: String) -> String {
        guard let start = project.range(of: "/* Begin \(name) section */"),
              let end = project.range(of: "/* End \(name) section */"),
              start.upperBound <= end.lowerBound
        else { return "" }
        return String(project[start.upperBound..<end.lowerBound])
    }

    /// Every multi-line object in a section, cut at the two-tab `};` that closes it.
    static func objectBlocks(inSection name: String, of project: String) -> [String] {
        let body = section(name, in: project)
        guard !body.isEmpty else { return [] }
        let chunks: [String] = body.components(separatedBy: "\n\t\t};")
        return Array(chunks.dropLast())
    }

    static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }

    /// The app target's frameworks phase, told apart from the two empty test-target
    /// phases by the CellarCore products only the app links.
    static func appTargetFrameworksBuildPhase(in project: String) throws -> String {
        let phases = objectBlocks(inSection: "PBXFrameworksBuildPhase", of: project)
        return try #require(phases.first { $0.contains("ReleaseNotes in Frameworks */,") })
    }

    /// The `packageReferences` list on the project object.
    static func packageReferences(in project: String) throws -> String {
        let opening = "\t\t\tpackageReferences = (\n"
        let start = try #require(project.range(of: opening))
        let rest = project[start.upperBound...]
        let end = try #require(rest.range(of: "\n\t\t\t);"))
        return String(rest[rest.startIndex..<end.lowerBound])
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
    /// Quoted, because that is how Xcode serialises it. The value contains a
    /// hyphen, and the project-file writer quotes any value that is not a bare
    /// identifier. Pinning the unquoted form would pass exactly once — until the
    /// next time any tool rewrites the file.
    static let partialInfoPlist = "INFOPLIST_FILE = \"Resources/Cellar-Info.plist\";"

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

    // MARK: - T12 — pbxproj item 7, the partial property list

    /// The partial property list is merged by **both** configurations, and the
    /// generator is still running.
    ///
    /// `INFOPLIST_FILE` and `GENERATE_INFOPLIST_FILE = YES` are asserted
    /// together on purpose: this is a *merge*, not a replacement, and the
    /// twenty-six keys the generator contributes — including the catalog-sourced
    /// display name and copyright that two other suites bind to — only survive
    /// while the generator stays on. Setting the file and turning the generator
    /// off would still ship `SUFeedURL` and would silently strip everything else.
    @Test("Both app-target configurations merge the partial property list")
    func appTargetsMergeThePartialPropertyList() throws {
        #expect(try UpdateProjectSources.appTargetBlocksDeclaring(Self.partialInfoPlist) == 2)
        #expect(try UpdateProjectSources.appTargetBlocksDeclaring("GENERATE_INFOPLIST_FILE = YES;") == 2)
    }

    // MARK: - T12(b) — pbxproj items 1 to 5, the Sparkle dependency

    /// The whole Sparkle dependency, asserted as five exact counts.
    ///
    /// Counts rather than presences, because a package dependency that appears
    /// twice is as broken as one that appears once and points at the wrong
    /// version: Xcode will happily resolve two references to the same repository
    /// with different requirements. `exactVersion 2.9.6` is pinned here because
    /// the update channel's whole trust story rests on a known signing tool and
    /// a known framework, and a range would let either drift on a clean resolve.
    ///
    /// The `PBXCopyFilesBuildPhase` count of **0** is the load-bearing one. U25
    /// measured that Sparkle auto-embeds into `Contents/Frameworks` with no Embed
    /// Frameworks phase, which is why the change list has no such item. Pinning
    /// the zero is what stops an Embed phase arriving later from an Xcode UI
    /// edit and silently double-signing the framework.
    @Test("The project links exactly one pinned Sparkle package, with no embed phase")
    func projectLinksThePinnedSparklePackage() throws {
        let project = try UpdateProjectSources.projectText()

        let remote = UpdateProjectSources.objectBlocks(
            inSection: "XCRemoteSwiftPackageReference",
            of: project
        )
        let sparkle = try #require(
            remote.first { $0.contains("repositoryURL = \"https://github.com/sparkle-project/Sparkle\";") }
        )
        #expect(remote.count == 1)
        #expect(sparkle.contains("kind = exactVersion;"))
        #expect(sparkle.contains("version = 2.9.6;"))

        let references = try UpdateProjectSources.packageReferences(in: project)
        #expect(UpdateProjectSources.occurrences(of: "XCRemoteSwiftPackageReference \"Sparkle\"", in: references) == 1)

        let buildFiles = UpdateProjectSources.section("PBXBuildFile", in: project)
        let sparkleBuildFile = "/* Sparkle in Frameworks */ = {isa = PBXBuildFile;"
        #expect(UpdateProjectSources.occurrences(of: sparkleBuildFile, in: buildFiles) == 1)

        let phase = try UpdateProjectSources.appTargetFrameworksBuildPhase(in: project)
        #expect(UpdateProjectSources.occurrences(of: "/* Sparkle in Frameworks */,", in: phase) == 1)

        let products = UpdateProjectSources.objectBlocks(
            inSection: "XCSwiftPackageProductDependency",
            of: project
        )
        #expect(products.filter { $0.contains("productName = Sparkle;") }.count == 1)

        #expect(UpdateProjectSources.occurrences(of: "PBXCopyFilesBuildPhase", in: project) == 0)
    }

    // MARK: - T12(c) — pbxproj items 8 to 10, the Updates product linkage

    /// The `Updates` library is linked explicitly, because nothing pulls it in.
    ///
    /// Six of CellarCore's products are linked by name and `SecurityKit` reaches
    /// the app only transitively, through `Persistence`. `Updates` is
    /// dependency-free by design, so it has no such path: without these three
    /// entries `import Updates` does not resolve, and the obvious "fix" — giving
    /// an already-linked target a dependency on it — would invert the graph and
    /// destroy the isolation the target exists for.
    @Test("The project links the CellarCore Updates product explicitly")
    func projectLinksTheUpdatesProduct() throws {
        let project = try UpdateProjectSources.projectText()

        let buildFiles = UpdateProjectSources.section("PBXBuildFile", in: project)
        let updatesBuildFile = "/* Updates in Frameworks */ = {isa = PBXBuildFile;"
        #expect(UpdateProjectSources.occurrences(of: updatesBuildFile, in: buildFiles) == 1)

        let phase = try UpdateProjectSources.appTargetFrameworksBuildPhase(in: project)
        #expect(UpdateProjectSources.occurrences(of: "/* Updates in Frameworks */,", in: phase) == 1)

        let products = UpdateProjectSources.objectBlocks(
            inSection: "XCSwiftPackageProductDependency",
            of: project
        )
        #expect(products.filter { $0.contains("productName = Updates;") }.count == 1)

        // The `Updates` dependency is local, so unlike Sparkle it carries no
        // `package` back-reference. Asserted so the two are never conflated.
        let updates = try #require(products.first { $0.contains("productName = Updates;") })
        #expect(!updates.contains("package = "))
    }
}
