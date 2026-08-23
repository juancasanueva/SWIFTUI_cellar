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
    static let workflowPath = ".github/workflows/release.yml"

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

    /// A workflow cut into steps at its `- name:` boundaries.
    ///
    /// The properties worth asserting about a workflow are per-step — "the step
    /// that deletes the keychain also runs unconditionally", "the private-repo
    /// gate runs before any step that builds". Asserting that two substrings
    /// both appear somewhere in the file would pass for a workflow where they
    /// sit in different steps, which is precisely the failure being guarded
    /// against.
    static func workflowSteps(in workflow: String) -> [String] {
        var steps: [String] = []
        var current: [String]?

        for line in workflow.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("- name:") {
                if let started = current { steps.append(started.joined(separator: "\n")) }
                current = [String(line)]
            } else {
                current?.append(String(line))
            }
        }
        if let last = current { steps.append(last.joined(separator: "\n")) }
        return steps
    }

    /// A top-level YAML block, from its column-zero key to the next column-zero
    /// key.
    static func topLevelBlock(named key: String, in yaml: String) -> String? {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0 == "\(key):" || $0.hasPrefix("\(key):") && !$0.hasPrefix(" ") })
        else { return nil }

        var block = [lines[start]]
        for line in lines[(start + 1)...] {
            let isNewTopLevelKey = !line.isEmpty
                && !line.hasPrefix(" ")
                && !line.hasPrefix("\t")
                && !line.hasPrefix("#")
            if isNewTopLevelKey { break }
            block.append(line)
        }
        return block.joined(separator: "\n")
    }

    /// Directories that are not "the repository": version-control internals,
    /// build output, and local tool state. Everything else is scanned.
    static let uncheckedDirectories: Set<String> = [
        ".git", ".build", "build", ".swiftpm", "DerivedData", ".codegraph", ".atl"
    ]

    /// Every file in the repository, excluding the directories above.
    static func repositoryFiles(under relativePath: String = "") -> [URL] {
        let root = relativePath.isEmpty ? repositoryRoot : url(relativePath)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var files: [URL] = []
        while let candidate = enumerator.nextObject() as? URL {
            let isDirectory = (try? candidate.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                if uncheckedDirectories.contains(candidate.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            files.append(candidate)
        }
        return files
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

    // MARK: - 5.1 T17b — the cost of not bumping the project file is written down

    /// S8: the tag is the version, so a local archive reports `1.0.0 (1)`
    /// forever — and the About window will show exactly that.
    ///
    /// That is a deliberate trade, not an oversight, and the spec refuses to let
    /// it stay an undocumented trap for manual testing: the fact and the exact
    /// one-line override that corrects it must both be in the repository. The
    /// assertion is on the override *line*, not on two loose substrings, because
    /// a reader who has to assemble the command from two paragraphs has not been
    /// given a command.
    @Test("The runbook records the 1.0.0 (1) fact and the override that corrects it")
    func runbookRecordsTheVersionPolicyAndItsOverride() throws {
        let runbook = try ReleasePipelineSources.text(ReleaseMetadataTests.runbookFile)

        #expect(runbook.contains("1.0.0 (1)"))

        let overrides = runbook
            .split(separator: "\n")
            .filter { $0.contains("MARKETING_VERSION=") && $0.contains("CURRENT_PROJECT_VERSION=") }
        #expect(!overrides.isEmpty, "the runbook must carry a single-line build-time version override")
    }

    // MARK: - 5.2 T18 — the entitlements rationale names what is absent

    /// S12: the PRD's standing obligation, discharged in the repository.
    ///
    /// An absent entitlement leaves no trace anywhere — not in the project file,
    /// not in the signature, not in a diff — so the only way it can be reviewed
    /// is if the reason for its absence is written down. All five names are
    /// asserted literally: the three that must never be added, and the two
    /// sandbox-era settings that sit inert beside a disabled sandbox and would
    /// come alive the moment an entitlements file appeared.
    @Test("The runbook names every entitlement that is deliberately absent")
    func runbookNamesTheAbsentEntitlements() throws {
        let runbook = try ReleasePipelineSources.text(ReleaseMetadataTests.runbookFile)

        for name in [
            "allow-jit",
            "allow-unsigned-executable-memory",
            "disable-library-validation",
            "ENABLE_USER_SELECTED_FILES",
            "REGISTER_APP_GROUPS"
        ] {
            #expect(runbook.contains(name), "the entitlements rationale must name \(name)")
        }
    }

    private static let copyright = "Copyright © 2026 Juan Casanueva. All rights reserved."
    private static let catalogFile = "cellar/InfoPlist.xcstrings"
    private static let runbookFile = "RELEASING.md"
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

    // MARK: - 4.1 T2 — the workflow exists

    /// S21: the pipeline definition lives under `.github/`, outside the
    /// synchronized root group that would otherwise ship it to users.
    @Test("The release workflow exists under .github/workflows")
    func releaseWorkflowExists() {
        #expect(ReleasePipelineSources.exists(ReleasePipelineSources.workflowPath))
    }

    // MARK: - 4.10 T12 — nothing release-shaped inside the synchronized group

    /// S21: `cellar/` joins the app target wholesale.
    ///
    /// GREEN on arrival, deliberately: the trap is a *future* mistake, and a pin
    /// that only arrives after someone falls into it has never prevented
    /// anything. The extensions listed are exactly the shapes this slice adds.
    @Test("No plist, yml, yaml or sh file lives inside the app's synchronized group")
    func appSourcesCarryNoReleaseInfrastructure() {
        let files = ReleasePipelineSources.repositoryFiles(under: "cellar")
        let offenders = files.filter { ["plist", "yml", "yaml", "sh"].contains($0.pathExtension) }

        #expect(offenders.map(\.lastPathComponent) == [])
        // The scan is only meaningful if it saw the group at all.
        #expect(files.count > 10)
    }

    // MARK: - 4.10 T13 — no credential material, and no entitlements file

    /// S24 and S11, in one sweep of the tree.
    ///
    /// A committed key is unrecoverable once pushed, and a `.entitlements` file
    /// appearing later would make `ENABLE_USER_SELECTED_FILES` and
    /// `REGISTER_APP_GROUPS` live — re-activating the export-write trap recorded
    /// in the archived tip-jar slice. Both hold today; both are pinned so they
    /// keep holding.
    ///
    /// The PEM check matches a *complete* header — `-----BEGIN <TYPE>-----` —
    /// rather than the bare prefix. Release documentation legitimately quotes
    /// the prefix when describing this very check, and a guard that fires on
    /// prose about itself is a guard someone eventually deletes.
    @Test("The repository carries no key material, certificate blob, or entitlements file")
    func repositoryCarriesNoCredentialMaterial() throws {
        let pemHeader = try NSRegularExpression(pattern: "-----BEGIN [A-Z0-9 ]+-----")
        let credentialExtensions = ["p12", "p8", "cer", "mobileprovision", "entitlements"]

        var offenders: [String] = []
        var scanned = 0

        for file in ReleasePipelineSources.repositoryFiles() {
            if credentialExtensions.contains(file.pathExtension) {
                offenders.append(file.lastPathComponent)
                continue
            }
            guard let data = try? Data(contentsOf: file) else { continue }
            scanned += 1
            let text = String(decoding: data, as: UTF8.self)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if pemHeader.firstMatch(in: text, range: range) != nil {
                offenders.append(file.lastPathComponent)
            }
        }

        #expect(offenders == [])
        // An absence is only proof if something counted the presences.
        #expect(scanned > 100)

        let project = try ReleasePipelineSources.text(ReleasePipelineSources.projectFile)
        #expect(!project.contains("CODE_SIGN_ENTITLEMENTS"))
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

    // MARK: - 4.2 T3 — only a version tag can trigger a release

    /// S3: the trigger surface is the whole security boundary of this workflow.
    ///
    /// It holds a Developer ID certificate and an App Store Connect key, so a
    /// `pull_request:` trigger would hand both to anyone who could open a pull
    /// request. The negatives are therefore asserted as hard as the positives.
    /// The runner, the Xcode pin and `concurrency:` are design-owned pins rather
    /// than spec coverage, kept here because nothing else would notice them
    /// drifting.
    @Test("The workflow is triggered only by a pushed v* tag")
    func onlyAVersionTagTriggersTheWorkflow() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflowPath)
        let triggers = try #require(ReleasePipelineSources.topLevelBlock(named: "on", in: workflow))

        #expect(triggers.contains("push:"))
        #expect(triggers.contains("tags:"))
        #expect(triggers.contains("'v*'"))

        // `branches:` is only meaningful inside the trigger block; the other
        // three are triggers wherever they appear, so both scopes are checked.
        for forbidden in ["pull_request:", "schedule:", "workflow_dispatch:", "branches:"] {
            #expect(!triggers.contains(forbidden), "the trigger block must not declare \(forbidden)")
        }
        for forbidden in ["pull_request:", "schedule:", "workflow_dispatch:"] {
            #expect(!workflow.contains(forbidden), "the workflow must not declare \(forbidden)")
        }

        // R7: this is a release workflow, not the project's test CI.
        #expect(!workflow.contains("xcodebuild test"))

        #expect(workflow.contains("runs-on: macos-26"))
        #expect(workflow.contains("contents: write"))
        #expect(workflow.contains("concurrency:"))
        #expect(workflow.contains("xcode-select -s /Applications/Xcode_26.6.app"))
    }

    // MARK: - 4.3 T19 — the private-repository fail-fast

    /// S4: an asset nobody can download is not a release.
    ///
    /// Pinned structurally because it can never be exercised by a real run: the
    /// dry run happens on a public repository, so the only proof that the gate
    /// exists — and that it runs *before* anything is signed or submitted — is
    /// its position among the steps.
    @Test("A private repository fails the run before any build step")
    func privateRepositoryFailsFastBeforeAnyBuildStep() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflowPath)
        let steps = ReleasePipelineSources.workflowSteps(in: workflow)

        let gate = try #require(
            steps.firstIndex { $0.contains("github.event.repository.private") && $0.contains("exit 1") }
        )
        let building = steps.indices.filter { steps[$0].contains("scripts/release.sh") }

        #expect(!building.isEmpty)
        #expect(building.allSatisfy { gate < $0 })
    }

    // MARK: - 4.4 T4 — credential cleanup cannot be skipped by a failure

    /// S25: injected credentials must die with the run, including when the run
    /// dies first.
    ///
    /// Asserted on the step that actually deletes the keychain, not on the file
    /// as a whole: `if: always()` appearing somewhere and `security
    /// delete-keychain` appearing somewhere is exactly the shape a broken
    /// workflow takes.
    @Test("The keychain deletion step is declared to run unconditionally")
    func keychainDeletionRunsUnconditionally() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflowPath)
        let steps = ReleasePipelineSources.workflowSteps(in: workflow)
        let cleanup = steps.filter { $0.contains("security delete-keychain") }

        #expect(cleanup.count == 1)
        #expect(cleanup.allSatisfy { $0.contains("if: always()") })
        // The API key leaves with it: a `.p8` outliving the run is the same leak.
        #expect(cleanup.allSatisfy { $0.contains("asc.p8") })
    }

    // MARK: - 4.5 T5 — secrets appear only as env bindings

    /// S26: a secret interpolated into a `run:` line is echoed into the step
    /// header of every job log, before the runner has a chance to mask it.
    ///
    /// So the shape is pinned, not just the count: every reference must be a
    /// bare `NAME: ${{ secrets.NAME }}` binding and nothing else.
    @Test("Every secret reference is the right-hand side of an env binding")
    func secretsAppearOnlyAsEnvironmentBindings() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflowPath)
        let binding = try NSRegularExpression(
            pattern: "^[A-Z0-9_]+: \\$\\{\\{ secrets\\.[A-Z0-9_]+ \\}\\}$"
        )

        let referencing = workflow
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains("secrets.") }

        // Non-vacuity, not an exact count: the App Store Connect bindings are
        // repeated once per step that needs them, deliberately, because YAML
        // anchors are not reliable across workflow contexts. Which *names* may
        // appear is the next test's job.
        #expect(referencing.count >= 7)
        for line in referencing {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            #expect(
                binding.firstMatch(in: line, range: range) != nil,
                "secret reference is not a plain env binding: \(line)"
            )
        }
    }

    // MARK: - 4.6 T6 — exactly the seven declared secrets

    /// S26: set equality, so an eighth secret fails too.
    ///
    /// A release pipeline that quietly grows a new credential is a release
    /// pipeline whose blast radius nobody re-reviewed. Adding one is allowed;
    /// adding one without touching this list is not.
    ///
    /// **Why the seventh arrived (m6-sparkle-updates).** Publishing an update
    /// feed means signing the released zip with an EdDSA private key, because
    /// every installed copy verifies the signature against the public key
    /// compiled into its own bundle rather than trusting the feed's transport.
    /// The key is bound only as an environment variable and reaches the signing
    /// tool on standard input; it is never written to a file, never a command
    /// argument, and never traced. Losing it severs the update channel for every
    /// copy already installed, so it is backed up offline as well as stored here.
    @Test("The workflow references exactly the seven expected secrets")
    func workflowReferencesExactlyTheExpectedSecrets() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflowPath)
        let reference = try NSRegularExpression(pattern: "secrets\\.([A-Z0-9_]+)")
        let range = NSRange(workflow.startIndex..<workflow.endIndex, in: workflow)

        let referenced = Set(
            reference.matches(in: workflow, range: range).compactMap { match -> String? in
                guard let name = Range(match.range(at: 1), in: workflow) else { return nil }
                return String(workflow[name])
            }
        )

        #expect(referenced == [
            "BUILD_CERTIFICATE_BASE64",
            "P12_PASSWORD",
            "KEYCHAIN_PASSWORD",
            "APPLE_API_KEY_P8",
            "APPLE_API_KEY_ID",
            "APPLE_API_ISSUER_ID",
            "SPARKLE_PRIVATE_KEY"
        ])
    }

    // MARK: - 4.7 T15b — nothing in the repository can retract a release

    /// S18, S19: decision 5 — never delete or unflag a prior release.
    ///
    /// A future Sparkle appcast will point at published assets; unflagging one
    /// strands every installed copy that trusted it. Withdrawing a release stays
    /// a deliberate maintainer action, so the automation is structurally
    /// incapable of it: the only `gh` invocation is `gh release create`, and
    /// there is no `git` invocation at all.
    @Test("The only release-management invocation is gh release create")
    func theWorkflowCanOnlyEverCreateARelease() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflowPath)

        let gh = ReleasePipelineSources.commandInvocations(of: "gh", in: workflow)
        #expect(gh.count == 1)
        #expect(gh.allSatisfy { $0.hasPrefix("gh release create") })

        #expect(ReleasePipelineSources.commandInvocations(of: "git", in: workflow).isEmpty)

        for forbidden in [
            "gh release delete", "gh release edit", "git push", "git tag", "git commit", "git add"
        ] {
            #expect(!workflow.contains(forbidden), "the workflow must not carry: \(forbidden)")
        }
    }

    // MARK: - 4.8 T16b — the workflow never traces its own commands

    /// S26: the steps that handle the certificate and the API key are the ones
    /// `set -x` would betray, so the prohibition is asserted over the whole file
    /// rather than per step.
    @Test("The workflow never enables shell command tracing")
    func workflowNeverTracesCommands() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflowPath)

        #expect(!workflow.contains("set -x"))
        #expect(!workflow.contains("set -eux"))
    }

    // MARK: - m6-cask-tap T5 — the release run gains no cross-repository reach

    /// D1/D2: the release run gains no cross-repository reach.
    ///
    /// A `curl` to a dispatch endpoint would pass `gh == 1 / git == 0`, because
    /// the Pages guard already establishes `curl` plus a bearer token as an
    /// accepted shape. Passing the letter is not the point — this asserts the
    /// decision itself, so "we chose not to insert here" stays chosen.
    @Test("The release workflow gains no cross-repository reach")
    func theWorkflowGainsNoCrossRepositoryReach() throws {
        let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflowPath)

        // The declined extension point is gone, rather than standing as an
        // invitation the suite would refuse.
        #expect(!workflow.contains("extension point"))

        for token in ["repository_dispatch", "dispatches"] {
            #expect(!workflow.contains(token), "the workflow must not carry: \(token)")
        }

        let apiCalls = workflow
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains("api.github.com/repos/") }
        // Anchored: the distinct-commit gate really does call the API, so the
        // loop below is not empty for the wrong reason.
        #expect(!apiCalls.isEmpty)
        for call in apiCalls {
            #expect(
                call.contains("api.github.com/repos/${GITHUB_REPOSITORY}")
                    || call.contains("api.github.com/repos/${{ github.repository }}"),
                "a GitHub API call names a repository that is not this one: \(call)"
            )
        }

        for name in ["homebrew-cellar", "juancasanueva/cellar"] {
            #expect(!workflow.contains(name), "the workflow must not name \(name)")
        }
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
