//
//  UpdateCompositionTests.swift
//  cellarTests
//

import Foundation
import Testing

@testable import cellar

/// What the app target is allowed to say about the updater framework.
///
/// Structural, over the comment-stripped sources `AppSecuritySources.load()`
/// returns, because every claim here is an **absence** — "no other file names
/// this type", "nothing writes this key at runtime" — and an absence cannot be
/// proved by importing the thing it is about. Comment stripping is why a
/// prohibition described in a doc comment is never mistaken for one violated in
/// code.
@Suite("Update composition")
struct UpdateCompositionTests {
    static let checkerFile = "SparkleUpdateChecker.swift"

    /// Files that render something. `cellarApp.swift` is deliberately not one of
    /// them: it declares an `App`, and dependency injection is exactly the job
    /// the app entry point is allowed to do.
    static func surfaces(in sources: [AppSecuritySources.Source]) -> [AppSecuritySources.Source] {
        sources.filter { $0.code.contains(": View {") || $0.code.contains(": Commands {") }
    }

    // MARK: - T8 — exactly one file imports the updater framework

    /// One import, in the file whose whole purpose is to hold it.
    ///
    /// The count is what matters. "SparkleUpdateChecker imports Sparkle" would
    /// still be true on the day a second file did too, and the second file is
    /// the one that would quietly spread framework types through the app.
    @Test("Exactly one file imports the updater framework, and it is the checker")
    func exactlyOneFileImportsTheUpdaterFramework() throws {
        let sources = try AppSecuritySources.load()
        let importers = sources.filter { $0.code.contains("import Sparkle") }

        #expect(importers.map(\.name) == [Self.checkerFile])
        // The sweep is only meaningful if it read the app target at all.
        #expect(sources.count > 10)
    }

    // MARK: - T9 — no user-interface file names the framework's types

    /// The framework's updater types appear in one file and nowhere else.
    @Test("Only the checker names the framework's updater types")
    func onlyTheCheckerNamesTheFrameworksUpdaterTypes() throws {
        let sources = try AppSecuritySources.load()
        let frameworkTypes = ["SPUStandardUpdaterController", "SPUUpdater", "SUUpdater"]

        for type in frameworkTypes {
            let naming = sources.filter { $0.code.contains(type) }.map(\.name)
            #expect(naming.allSatisfy { $0 == Self.checkerFile }, "\(type) escaped the checker")
        }

        let checker = try #require(sources.first { $0.name == Self.checkerFile })
        #expect(checker.code.contains("SPUStandardUpdaterController"))
    }

    /// No rendering file names the concrete checker.
    ///
    /// Every update surface speaks to Cellar's own protocol, so the real updater
    /// and the in-memory one are interchangeable and a UI test can never
    /// construct something that reaches the network.
    @Test("No view or commands file names the concrete checker")
    func noSurfaceNamesTheConcreteChecker() throws {
        let sources = try AppSecuritySources.load()
        let surfaces = Self.surfaces(in: sources)

        let offenders = surfaces
            .filter { $0.name != Self.checkerFile && $0.code.contains("SparkleUpdateChecker") }
            .map(\.name)

        #expect(offenders == [])
        // The filter is only meaningful if it found surfaces to filter.
        #expect(surfaces.count > 10)
        #expect(surfaces.contains { $0.name == "UpdatesSettingsGroup.swift" })
        #expect(surfaces.contains { $0.name == "CheckForUpdatesCommands.swift" })

        // The UI-test fixtures name the in-memory updater and never the real
        // one, so a UI-test launch structurally cannot start an updater, reach
        // the feed, or open an updater window.
        let fixtures = try #require(sources.first { $0.name == "AppTestFixtures.swift" })
        #expect(!fixtures.code.contains("SparkleUpdateChecker"))
        #expect(fixtures.code.contains("AppTestUpdater"))
    }

    // MARK: - T21 — nothing can substitute a different feed or key at run time

    /// The feed and the key are build-time facts with no runtime escape hatch.
    ///
    /// This is the other half of the key-material guard: that one proves no
    /// second key is *committed*, this one proves no key or feed can be
    /// *supplied* while the app runs. A key an attacker can supply is a key an
    /// attacker can supply, which is the entire security argument for compiling
    /// it in.
    @Test("Nothing in the app can substitute a different feed or verification key")
    func nothingCanSubstituteADifferentFeedOrKey() throws {
        let sources = try AppSecuritySources.load()
        let overrides = ["SPUUpdaterDelegate", "feedURLString(for:", "setFeedURL", "updater.feedURL"]

        for override in overrides {
            let offenders = sources.filter { $0.code.contains(override) }.map(\.name)
            #expect(offenders == [], "\(override) is a runtime feed override")
        }

        for key in ["SUFeedURL", "SUPublicEDKey"] {
            let offenders = sources.filter { $0.code.contains(key) }.map(\.name)
            #expect(offenders == [], "\(key) is named in app source rather than only in the bundle")
        }
    }

    // MARK: - T23 — the command is present in the app menu

    /// The command is wired into the scene, and it **adds** a group rather than
    /// replacing one.
    ///
    /// `replacing:` substitutes the *content* of the `.appInfo` group and
    /// `after:` inserts a new group behind it. `AboutCommands` already uses
    /// `replacing:` to own the About item, so a second `replacing:` would
    /// silently displace it and the About window would lose its entry point.
    /// The two compose only in this arrangement.
    @Test("The check-for-updates command is added after the About item, never replacing it")
    func theCommandIsAddedAfterTheAboutItem() throws {
        let sources = try AppSecuritySources.load()

        let app = try #require(sources.first { $0.name == "cellarApp.swift" })
        #expect(app.code.contains("CheckForUpdatesCommands"))
        #expect(app.code.contains("AboutCommands()"))

        let commands = try #require(sources.first { $0.name == "CheckForUpdatesCommands.swift" })
        #expect(commands.code.contains("CommandGroup(after: .appInfo)"))
        #expect(!commands.code.contains("CommandGroup(replacing: .appInfo)"))

        // The About group keeps its own `replacing:`, which is what the new
        // group has to coexist with rather than take over.
        let about = try #require(sources.first { $0.name == "AboutView.swift" })
        #expect(about.code.contains("CommandGroup(replacing: .appInfo)"))
    }

    // MARK: - T25 — the Updates group renders nothing inert

    /// Exactly two controls, both with behaviour behind them.
    ///
    /// The design sketched an update-channel picker. Cellar has no channels —
    /// prereleases never enter the feed at all — so the picker would be a
    /// control that changes nothing, and `SettingsView`'s own rule is that rows
    /// the design sketches for capabilities Cellar does not have are absent
    /// rather than present-but-inert.
    ///
    /// The count of accessibility identifiers is the assertion that actually
    /// forbids a third row: naming the two that must exist would still pass on
    /// the day a picker was added beside them.
    @Test("The Updates group declares exactly the toggle and the last-checked label")
    func theUpdatesGroupDeclaresExactlyTwoRows() throws {
        let sources = try AppSecuritySources.load()
        let group = try #require(sources.first { $0.name == "UpdatesSettingsGroup.swift" })

        let identifiers = ["updates-automatic-toggle", "updates-last-checked"]
        for identifier in identifiers {
            #expect(group.code.contains("accessibilityIdentifier(\"\(identifier)\")"))
        }
        let declared = group.code.components(separatedBy: "accessibilityIdentifier(").count - 1
        #expect(declared == identifiers.count)

        #expect(!group.code.contains("Picker"))
        #expect(!group.code.lowercased().contains("channel"))
    }

    // MARK: - T22 (structural half) — the framework's own prompt is unreachable

    /// The preference is applied **before** the updater starts.
    ///
    /// Order, not presence. Left unset, the framework asks the user on second
    /// launch whether to enable automatic checks — a system alert Cellar never
    /// wanted and cannot style. Writing the preference first means the value is
    /// already there when the updater starts, so the prompt has nothing to ask
    /// about. Starting first and writing second would show it once, on exactly
    /// the launch nobody tests.
    @Test("The preference is applied before the updater starts")
    func thePreferenceIsAppliedBeforeTheUpdaterStarts() throws {
        let sources = try AppSecuritySources.load()
        let checker = try #require(sources.first { $0.name == Self.checkerFile })

        let apply = try #require(checker.code.range(of: "AutomaticUpdateChecksPolicy.apply("))
        let start = try #require(checker.code.range(of: "startUpdater()"))

        #expect(apply.lowerBound < start.lowerBound)
        #expect(checker.code.contains("startingUpdater: false"))
    }
}
