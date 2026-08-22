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

    /// Every invocation of `command` as a **command token**, returned as the
    /// remainder of the line it starts.
    ///
    /// A bare substring search is not good enough here. `gh` occurs inside
    /// "through" and "enough"; `git` occurs inside "gitignored". A prohibition
    /// that fires on English prose in a comment is a prohibition someone will
    /// eventually weaken to shut it up, so it is written to fire only on an
    /// actual invocation: start of line, or after whitespace, `;`, `|`, `&` or
    /// `(`, and followed by whitespace or end of line.
    static func commandInvocations(of command: String, in text: String) -> [String] {
        let pattern = "(?:^|[\\s;|&(])\(NSRegularExpression.escapedPattern(for: command))(?=\\s|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return text.split(separator: "\n", omittingEmptySubsequences: false).flatMap { line -> [String] in
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                guard let matched = Range(match.range, in: text) else { return nil }
                // Drop the separator the pattern consumed, so the result starts
                // at the command itself.
                let start = text[matched].hasPrefix(command) ? matched.lowerBound
                    : text.index(after: matched.lowerBound)
                return String(text[start...])
            }
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

    // MARK: - 2.1 T9 — the string catalog is the single authority for the copyright

    /// S29: the value lives in the catalog, and the build setting carries no
    /// competing one.
    ///
    /// Two sources for one key drift. `LOCALIZATION_PREFERS_STRING_CATALOGS` is
    /// already `YES` and the catalog already owns both bundle-name keys, so the
    /// copyright joins them there. `INFOPLIST_KEY_NSHumanReadableCopyright`
    /// stays empty — measured, an empty `INFOPLIST_KEY_*` value is dropped from
    /// the generated Info.plist rather than emitted, so the empty setting is not
    /// a second, quieter authority.
    @Test("The string catalog carries the copyright and the build setting does not")
    func stringCatalogIsTheOnlyCopyrightAuthority() throws {
        let data = try Data(contentsOf: ReleasePipelineSources.url(ReleaseMetadataTests.catalogFile))
        let catalog = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let strings = try #require(catalog["strings"] as? [String: Any])
        let copyright = try #require(strings["NSHumanReadableCopyright"] as? [String: Any])
        let localizations = try #require(copyright["localizations"] as? [String: Any])
        let english = try #require(localizations["en"] as? [String: Any])
        let unit = try #require(english["stringUnit"] as? [String: Any])

        #expect(unit["value"] as? String == ReleaseMetadataTests.copyright)
        #expect(unit["state"] as? String == "translated")

        // The bundle-name keys the catalog already owned are still there: the
        // copyright joined them rather than replacing the file's purpose.
        #expect(strings["CFBundleDisplayName"] != nil)
        #expect(strings["CFBundleName"] != nil)

        let blocks = try ReleasePipelineSources.appTargetBuildConfigurationBlocks()
        #expect(blocks.count == 2)
        for block in blocks {
            let declared = block
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("INFOPLIST_KEY_NSHumanReadableCopyright") }
            #expect(declared == ["INFOPLIST_KEY_NSHumanReadableCopyright = \"\";"])
        }
    }

    // MARK: - 2.2 T10 — the delivered bundle reports it

    /// S28: what the Finder inspector and the About window actually read.
    ///
    /// `localizedInfoDictionary` is pinned deliberately and must never fall back
    /// to `infoDictionary`: catalog-sourced keys land in the compiled
    /// `InfoPlist.strings`, and the raw key was measured **absent** from the
    /// generated Info.plist, so a fallback would assert on a key that does not
    /// exist and pass for the wrong reason.
    @Test("The app bundle reports the human-readable copyright")
    func bundleReportsCopyright() throws {
        let localized = try #require(Bundle.main.localizedInfoDictionary)
        let value = try #require(localized["NSHumanReadableCopyright"] as? String)

        #expect(value == ReleaseMetadataTests.copyright)
        #expect(!value.isEmpty)
    }

    private static let copyright = "Copyright © 2026 Juan Casanueva. All rights reserved."
    private static let catalogFile = "cellar/InfoPlist.xcstrings"
}

/// Where the release infrastructure lives.
///
/// `cellar/` is a `PBXFileSystemSynchronizedRootGroup`: a `.plist`, `.yml` or
/// `.sh` dropped inside it silently joins the app target and ships **signed
/// inside the bundle**. That is a future mistake, not a present one, which is
/// exactly why the guard is a test rather than a comment.
@Suite("Release pipeline placement")
struct ReleasePipelinePlacementTests {
    // MARK: - 3.1 T1 — the script and its export options exist, outside cellar/

    /// S21: `scripts/release.sh` is the one executable file this slice adds, so
    /// its executable bit is asserted rather than assumed — a release script
    /// that is not executable is a documentation-like path that fails at the
    /// worst possible moment.
    @Test("The release script and its export options exist under scripts/")
    func releaseScriptAndExportOptionsExist() {
        #expect(ReleasePipelineSources.exists("scripts/ExportOptions.plist"))
        #expect(ReleasePipelineSources.exists("scripts/release.sh"))
        #expect(
            FileManager.default.isExecutableFile(
                atPath: ReleasePipelineSources.url("scripts/release.sh").path
            )
        )
    }
}

/// What the release workflow and the release script are allowed to say.
///
/// Structural assertions over text, because the properties that matter here —
/// "no step traces its own commands", "nothing can retract a release" — are
/// absences, and an absence in a shell script is only provable by reading it.
@Suite("Release workflow contract")
struct ReleaseWorkflowContractTests {
    private static let scriptPath = "scripts/release.sh"
    private static let exportOptionsPath = "scripts/ExportOptions.plist"

    // MARK: - 3.2 T7 — the export configuration declares Developer ID

    /// S22: parsed as a property list, not grepped — a malformed plist that
    /// happens to contain the right words would fail `xcodebuild -exportArchive`
    /// at release time, and this is the check that would have caught it.
    @Test("The export options declare developer-id, automatic signing, and the team")
    func exportOptionsDeclareDeveloperIDDistribution() throws {
        let data = try Data(contentsOf: ReleasePipelineSources.url(Self.exportOptionsPath))
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        let options = try #require(parsed as? [String: Any])

        #expect(options["method"] as? String == "developer-id")
        #expect(options["signingStyle"] as? String == "automatic")
        #expect(options["teamID"] as? String == "Z3S5JK8E38")
    }

    // MARK: - 3.3 T8 — the script carries the whole sequence

    /// S20: the local path rehearses the real one, so it must carry every stage
    /// the release run depends on. A rehearsal missing a stage is not a
    /// rehearsal; it is a different build that happens to succeed.
    @Test("The release script carries every build, sign, notarize, staple and verify command")
    func releaseScriptCarriesTheWholeSequence() throws {
        let script = try ReleasePipelineSources.text(Self.scriptPath)

        #expect(script.contains("set -euo pipefail"))

        for command in [
            "xcodebuild archive",
            "-exportArchive",
            "ditto -c -k --keepParent --sequesterRsrc",
            "notarytool submit",
            "--wait",
            "stapler staple",
            "stapler validate",
            "spctl -a -vvv -t install",
            "codesign -dvvv",
            "--entitlements :-",
            "lipo -archs"
        ] {
            #expect(script.contains(command), "release.sh must carry: \(command)")
        }

        // The three keys `verify` reads back off the extracted copy — version,
        // build number, and the display name the follow-up slices bind against.
        for key in ["CFBundleShortVersionString", "CFBundleVersion", "CFBundleDisplayName"] {
            #expect(script.contains("plutil -extract \(key) raw"), "verify must read \(key)")
        }

        // S23: nothing from scripts/ or .github/ may ship inside the bundle, and
        // the gate that proves it enumerates the delivered Contents/ directory.
        #expect(script.contains("\"$VERIFIED_APP/Contents\""))
        #expect(script.contains("ExportOptions"))
    }

    /// The published archive can only ever be the post-staple one.
    ///
    /// R8: `ditto` into an existing zip path is an in-place add, not a replace,
    /// so an un-deleted pre-notarization archive would leave the stapled ticket
    /// out of the asset users download and make first launch require network
    /// access. The deletion is asserted **by position**, not by presence: the
    /// order is the whole property.
    @Test("Stapling deletes the pre-notarization archive before repackaging")
    func stapleDeletesTheArchiveBeforeRepackaging() throws {
        let script = try ReleasePipelineSources.text(Self.scriptPath)
        let body = try #require(Self.functionBody(named: "phase_staple", in: script))

        let staple = try #require(body.range(of: "stapler staple"))
        let remove = try #require(body.range(of: "rm -f"))
        let repackage = try #require(body.range(of: "phase_package"))

        #expect(staple.upperBound < remove.lowerBound)
        #expect(remove.upperBound < repackage.lowerBound)
    }

    // MARK: - 3.4 T15a — the script cannot publish and cannot pick a repository

    /// S19, S20: publication exists only in the automated workflow.
    ///
    /// Threat rows *git repository selection*, *commit state* and *push state*
    /// all collapse into one assertion: a script that contains no `git` and no
    /// `gh` invocation cannot select a repository, cannot stage or commit, and
    /// cannot push or publish — regardless of the `$PWD` it is run from.
    @Test("The release script contains no git and no gh invocation at all")
    func releaseScriptCannotPublishOrSelectARepository() throws {
        let script = try ReleasePipelineSources.text(Self.scriptPath)

        #expect(ReleasePipelineSources.commandInvocations(of: "gh", in: script).isEmpty)
        #expect(ReleasePipelineSources.commandInvocations(of: "git", in: script).isEmpty)
        // The helper only proves an absence if it can find a presence: the
        // script does invoke xcodebuild, and the same matcher sees it.
        #expect(!ReleasePipelineSources.commandInvocations(of: "xcodebuild", in: script).isEmpty)
    }

    // MARK: - 3.5 T16a — no step traces its own commands

    /// S26: `set -x` around a credential writes it to the log verbatim. The
    /// script never handles one, but it is invoked by steps that do, and the
    /// prohibition is cheaper to keep than to reintroduce.
    @Test("The release script never enables shell command tracing")
    func releaseScriptNeverTracesCommands() throws {
        let script = try ReleasePipelineSources.text(Self.scriptPath)

        #expect(!script.contains("set -x"))
        #expect(!script.contains("set -eux"))
    }

    /// The body of a shell function, from its opening line to the column-zero
    /// `}` that closes it.
    static func functionBody(named name: String, in script: String) -> String? {
        guard let start = script.range(of: "\(name)() {") else { return nil }
        let rest = script[start.upperBound...]
        guard let end = rest.range(of: "\n}") else { return nil }
        return String(rest[rest.startIndex..<end.lowerBound])
    }
}
