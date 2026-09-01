//
//  MenuBarCompositionTests.swift
//  cellarTests
//

import BrewClient
import Catalog
import Foundation
import Testing

@testable import cellar

/// The shapes that derive a *collection or a count* of outdated packages
/// without going through the one snooze-aware projection.
///
/// Deliberately blind to per-package reads such as `installed.isOutdated` or
/// `entry.installed?.isOutdated`: the requirement is about deriving a count or
/// a set, never about reading one package's own flag, and a bare-token scan
/// would condemn twenty legitimate call sites
/// (installed-inventory spec:77-85).
private enum OutdatedDerivation {
    /// A collection filtered by the per-package flag — the shape the sidebar
    /// badge and the Home attention card shipped with.
    static let filterShapes = [
        "filter(\\.isOutdated)",
        "filter { $0.isOutdated",
        "filter { package in package.isOutdated",
    ]

    /// The inventory's own un-snoozed answers. Legitimate only when they are
    /// the projection's, which is exactly what the `(metadata:` argument makes
    /// visible at the call site.
    static let projectionTokens = [".outdatedIDs", ".outdatedCount"]

    /// The argument label that marks a delegated read.
    static let delegatedPrefix = "(metadata:"

    /// Every self-computed derivation in `code`, named by the shape that
    /// matched. Empty means the source announces no number of its own.
    static func derivations(in code: String) -> [String] {
        var found: [String] = []
        for shape in filterShapes where code.contains(shape) {
            found.append(shape)
        }
        for token in projectionTokens {
            var cursor = code.startIndex
            while let range = code.range(of: token, range: cursor..<code.endIndex) {
                if !code[range.upperBound...].hasPrefix(delegatedPrefix) {
                    found.append(token)
                }
                cursor = range.upperBound
            }
        }
        return found
    }
}

/// The menu bar's composition claims, and the app-wide sweep that keeps the
/// outdated number single-sourced.
///
/// Every claim here is an assertion over the repository's own sources, read off
/// disk in the shipped `AppSecuritySources` idiom: a claim about what the app
/// target does *not* contain cannot be made by importing it.
@Suite("Menu-bar composition")
struct MenuBarCompositionTests {
    // MARK: - T18 — the app-wide sweep (installed-inventory spec:77)

    /// No surface in the app announces a self-computed outdated count.
    ///
    /// The detector is anchored positively in the same test: handed the exact
    /// literal the sidebar shipped with, it must match. A detector that stopped
    /// recognising anything would otherwise report a clean sweep forever.
    @Test("No surface in the app announces a self-computed outdated count")
    func noSurfaceInTheAppAnnouncesASelfComputedOutdatedCount() throws {
        // Positive anchor first: the detector recognises the shipped literal.
        let shipped = "installed.inventory.packages.filter(\\.isOutdated).count"
        #expect(
            OutdatedDerivation.derivations(in: shipped).isEmpty == false,
            "the detector no longer recognises the shape it exists to find"
        )
        // And it separates a delegated read from a raw one.
        #expect(OutdatedDerivation.derivations(in: "browse.outdatedCount(metadata: lookup)").isEmpty)
        #expect(OutdatedDerivation.derivations(in: "browse.outdatedIDs(metadata: lookup)").isEmpty)
        #expect(
            OutdatedDerivation.derivations(in: "inventory.outdatedCount").isEmpty == false,
            "an un-snoozed count read straight off the inventory went unnoticed"
        )

        let sources = try AppSecuritySources.load()
        #expect(sources.count > 40, "the app sweep enumerated only \(sources.count) sources")

        var offenders: [String] = []
        for source in sources {
            for shape in OutdatedDerivation.derivations(in: source.code) {
                offenders.append("\(source.name): \(shape)")
            }
        }
        #expect(offenders.isEmpty, "self-computed outdated derivations: \(offenders)")
    }

    // MARK: - T11 — off by default, in an injectable suite (menu-bar spec:325)

    /// A fresh install has no status item, and the choice survives relaunch.
    ///
    /// The suite is a parameter for the reason `AutomaticUpdateChecks`' is: a
    /// UI-test launch must never write the developer's real preferences, and
    /// "off on a fresh install" has to be genuinely fresh rather than left over
    /// from a previous run.
    @Test("The preference is off by default and is the only insertion condition")
    @MainActor
    func thePreferenceIsOffByDefaultAndIsTheOnlyInsertionCondition() throws {
        let name = "cellar-tests-menu-bar-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { UserDefaults.standard.removePersistentDomain(forName: name) }

        // No stored value at all: the status item is absent, so the app behaves
        // exactly as it does without this capability.
        #expect(defaults.object(forKey: MenuBarPreference.key) == nil, "the scratch suite was not fresh")
        #expect(MenuBarPreference(defaults: defaults).isShown == false)

        // Turning it on writes the key, and a second instance over the same
        // suite reads it — which is what surviving a relaunch means.
        let preference = MenuBarPreference(defaults: defaults)
        preference.isShown = true
        #expect(defaults.bool(forKey: MenuBarPreference.key))
        #expect(MenuBarPreference(defaults: defaults).isShown)

        // And off again, so the toggle is not one-way.
        preference.isShown = false
        #expect(MenuBarPreference(defaults: defaults).isShown == false)

        // Nothing in this surface reaches for the data stores: a preference is
        // not data, and this project reserves SwiftData for data.
        let menuBar = try MenuBarSources.load()
        #expect(menuBar.contains { $0.name == "MenuBarPreference.swift" })
        for source in menuBar {
            for token in ["SwiftData", "LocalStores", "@Model", "ModelContainer"] {
                #expect(source.code.contains(token) == false, "\(source.name) references \(token)")
            }
        }
    }

    // MARK: - T17 — one row, and the absent capabilities stay absent (spec:341)

    @Test("Settings gains one row and still denies the absent capabilities")
    func settingsGainsOneRowAndStillDeniesTheAbsentCapabilities() throws {
        let sources = try AppSecuritySources.load()
        let settings = try #require(sources.first { $0.name == "SettingsView.swift" })

        // The file may no longer assert something false about the app.
        #expect(
            settings.code.localizedCaseInsensitiveContains("a menu bar extra") == false,
            "SettingsView still states that a menu bar extra is a capability Cellar lacks"
        )
        #expect(settings.code.contains("MenuBarSettingsGroup()"), "the card was never added to the stack")

        // Exactly one row carries the copy, and it is in its own file — so
        // deleting that file removes the whole surface.
        let carriers = sources.filter { $0.code.contains("Show in menu bar") }
        #expect(carriers.map(\.name) == ["MenuBarSettingsGroup.swift"], "carriers: \(carriers.map(\.name))")
        let group = try #require(carriers.first)
        #expect(
            group.code.components(separatedBy: "Show in menu bar").count - 1 == 1,
            "the copy is written more than once"
        )
        #expect(group.code.components(separatedBy: "Toggle(").count - 1 == 1, "more than one toggle")
        #expect(group.code.contains("menu-bar-settings-toggle"))

        // No row for a capability that still does not exist. Scanned over the
        // comment-stripped Settings sources, so a rule *described* is never
        // mistaken for one *violated*.
        let owned = sources.filter { $0.name == "SettingsView.swift" || $0.name.hasSuffix("SettingsGroup.swift") }
        #expect(owned.count >= 3, "only \(owned.count) Settings sources were read")
        // Anchored: the scan really did read the shipped rows. Cellar's own
        // update check is not a background schedule and not a notification, and
        // is named here so it is excluded on purpose rather than by luck.
        let joined = owned.map(\.code).joined(separator: "\n")
        #expect(joined.contains("Check for updates automatically"), "the Settings rows were not read")
        #expect(joined.contains("Accent colour"))

        for token in [
            "UNUserNotificationCenter", "SMAppService", "UNNotification",
            "schedule", "Schedule", "notification", "Notification"
        ] {
            for source in owned {
                #expect(
                    source.code.contains(token) == false,
                    "\(source.name) carries \(token) — a row for a capability Cellar does not have"
                )
            }
        }
    }

    // MARK: - T8 — the surface reads, and does nothing else (spec:290, :299)

    /// The whole menu-bar directory, swept for the tokens this surface may not
    /// contain.
    ///
    /// The prohibitions are asserted **before** the first `#require`, so a throw
    /// on the way to a later assertion cannot skip them.
    @Test("No menu-bar source loads, egresses or confirms")
    func noMenuBarSourceLoadsEgressesOrConfirms() throws {
        let sources = try MenuBarSources.load()

        for source in sources {
            for token in MenuBarSources.forbidden {
                #expect(source.code.contains(token) == false, "\(source.name) contains \(token)")
            }
        }

        // The verbs the surface actually offers, and their confirmation
        // requirement read rather than assumed. A request raised with no window
        // open would latch unanswered on the shared channel and block every
        // later confirmation in the app, so none of these may need one. That is
        // also why the popover submits `.upgradeAll` directly while the main
        // window asks through `submitUpgradeAll()` — the ask lives in the
        // centre's separate bulk gate, never on the command (bulk-confirmation
        // ruling 2026-09-01), so this flag stays false.
        let target = try #require(ServiceTarget(name: "atuin"))
        #expect(MutationCommand.upgradeAll.requiresConfirmation == false)
        for command in ServiceCommand.allVerbs(for: target) {
            #expect(command.requiresConfirmation == false, "\(command.verb) asks for confirmation")
        }
        // And a verb that does need one is genuinely excluded, so the sweep
        // above is not vacuous.
        let cask = try #require(CaskID(name: "docker"))
        #expect(MutationCommand.zap(cask).requiresConfirmation)
    }

    // MARK: - T13 — uncounted, disclosed, and pure SwiftUI (spec:183, :192, :360)

    @Test("The upgrade verb is uncounted and disclosed, and no AppKit activation exists")
    func theUpgradeVerbIsUncountedDisclosedAndTheWindowEntryIsPureSwiftUI() throws {
        let sources = try MenuBarSources.load()
        let popover = try #require(sources.first { $0.name == "MenuBarPopoverView.swift" })

        #expect(popover.code.contains("operations.submit(.upgradeAll)"))
        #expect(popover.code.contains("CopyCommandButton(text: MutationCommand.upgradeAll.displayCommand)"))

        // The badge carries the number; the button carries none. A label with no
        // count cannot announce a number different from the set `brew upgrade`
        // acts on.
        let label = try #require(popover.code.range(of: "\"Upgrade all\""))
        #expect(popover.code[label].contains("\\(") == false)
        let afterLabel = popover.code[label.upperBound...].prefix(24)
        #expect(afterLabel.hasPrefix(" (") == false, "a parenthesised total follows the label")
        #expect(popover.code.contains("Upgrade all (") == false)

        // No fan-out, and no second command family.
        for token in ["submitUpgrades(", "upgradableIDs(", "MutationCommand.upgrade("] {
            #expect(popover.code.contains(token) == false, "the popover reaches for \(token)")
        }

        // The disclosed command is the shipped one, worded nowhere here, so the
        // popover and the installed list cannot disclose two different commands
        // for one submission.
        for source in sources {
            #expect(source.code.contains("brew upgrade") == false, "\(source.name) composes the command")
            for token in ["NSApplication", "NSApp", ".activate("] {
                #expect(source.code.contains(token) == false, "\(source.name) contains \(token)")
            }
        }
        // Anchored: the shipped command really is the string the popover
        // discloses.
        #expect(MutationCommand.upgradeAll.displayCommand == "brew upgrade")
    }

    // MARK: - T7 — all three surfaces trace to one call (installed-inventory :69)

    @Test("Every outdated surface reads the one projection")
    func everyOutdatedSurfaceReadsTheOneProjection() throws {
        let sources = try AppSecuritySources.load()
        let sidebar = try #require(sources.first { $0.name == "SidebarView.swift" })
        let home = try #require(sources.first { $0.name == "HomeView.swift" })
        let app = try #require(sources.first { $0.name == "cellarApp.swift" })
        let projection = try Self.coreSource("MenuBarProjection.swift")

        // Each of the three derives the number from the one call.
        for source in [sidebar.code, home.code, projection] {
            #expect(
                source.contains("outdatedCount(metadata:") || source.contains("outdatedIDs(metadata:"),
                "a surface no longer delegates"
            )
            #expect(source.contains("filter(\\.isOutdated)") == false)
            #expect(source.contains("filter { $0.isOutdated") == false)
        }
        // And the projection derives no outdated-ness of its own.
        #expect(projection.contains("isOutdated") == false, "the projection re-derives outdated-ness")

        // The two app surfaces build the browse and obtain the lookup with the
        // same expressions, which is what makes them agree one level down rather
        // than by each getting it right separately.
        let browse = "InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil)"
        let lookup = "metadata.availability.isAvailable ? metadata.snapshot.lookup : nil"
        for source in [sidebar.code, home.code] {
            #expect(source.contains(browse), "a surface builds a different browse")
            #expect(source.contains(lookup), "a surface obtains a different lookup")
        }

        // The menu-bar clause: the third surface composes its projection from
        // exactly the same two expressions, so all three trace to one call.
        #expect(app.code.contains(browse), "the scene builds a different browse")
        #expect(app.code.contains(lookup), "the scene obtains a different lookup")
        #expect(app.code.contains("MenuBarProjection("), "the scene composes no projection")
    }

    // MARK: - T9 — one refresh, in the app, starting no poll (spec:215)

    @Test("The one services refresh lives in the app and starts no poll")
    func theOneServicesRefreshLivesInTheAppAndStartsNoPoll() throws {
        let sources = try AppSecuritySources.load()
        let app = try #require(sources.first { $0.name == "cellarApp.swift" })

        #expect(
            app.code.components(separatedBy: "refreshBaseline(").count - 1 == 1,
            "the app has more than one baseline call site"
        )
        let block = try Self.menuBarBlock(app.code)
        #expect(block.contains("refreshBaseline("), "the one baseline call is outside the menu-bar scene")

        // The surface itself carries no refresh, no cadence and no visibility
        // token at all: it cannot reach either half of the poll's conjunction.
        for source in try MenuBarSources.load() {
            for token in [
                "refreshBaseline", "servicesRefresher", "ServicesRefreshCoordinator",
                "Timer", "ContinuousClock", "clock.sleep", ".seconds("
            ] {
                #expect(source.code.contains(token) == false, "\(source.name) contains \(token)")
            }
        }

        // And the Services section's own reporting is untouched.
        let list = try #require(sources.first { $0.name == "ServicesListView.swift" })
        #expect(list.code.contains("setVisible(true)"))
        #expect(list.code.contains("setVisible(false)"))
    }

    // MARK: - T10 — the scene repeats the About window's environment (spec:398)

    @Test("The menu-bar scene repeats the About window's environment")
    func theMenuBarSceneRepeatsTheAboutWindowsEnvironment() throws {
        let app = try #require(try AppSecuritySources.load().first { $0.name == "cellarApp.swift" })
        let block = try Self.menuBarBlock(app.code)

        // Proven against the precedent rather than asserted: the About window
        // repeats exactly these three because environment injection is
        // per-scene, and a scene that omits them renders in system chrome while
        // the rest of the app is the design's dark surface.
        let about = try Self.aboutBlock(app.code)
        let three = [".environment(theme)", ".tint(theme.base)", ".preferredColorScheme(.dark)"]
        for modifier in three {
            #expect(about.contains(modifier), "the About window no longer applies \(modifier)")
            #expect(block.contains(modifier), "the menu-bar scene does not apply \(modifier)")
        }
        #expect(app.code.contains(".menuBarExtraStyle(.window)"))

        // And nothing else: the release-notes and updater seams would give a
        // popover reach into surfaces it must not have.
        for token in ["releaseNotes", "appUpdater"] {
            #expect(block.contains(token) == false, "the menu-bar scene injects \(token)")
        }
    }

    // MARK: - T12 — a title, no badge image, no locally composed count (:158)

    @Test("The status item is a title with no badge image and no local count")
    func theStatusItemIsATitleWithNoBadgeImageAndNoLocalCount() throws {
        let sources = try AppSecuritySources.load()
        let app = try #require(sources.first { $0.name == "cellarApp.swift" })
        let projection = try Self.coreSource("MenuBarProjection.swift")

        // The absence is modelled as absence, and it is modelled in exactly one
        // place.
        #expect(projection.contains("public var statusItemTitle: String? {"))
        for source in sources {
            #expect(
                source.code.contains("var statusItemTitle") == false,
                "\(source.name) declares a second status title"
            )
        }

        // Exactly one framework adaptation, at the boundary, and no menu-bar
        // source ever sees it. The outer ternary short-circuits, so with the
        // feature off the projection is never composed at all.
        let title = "menuBar.isShown ? (menuBarProjection.statusItemTitle ?? \"\") : \"\""
        #expect(app.code.contains(title), "the title argument is not the exact adapted expression")
        #expect(
            sources.map { $0.code.components(separatedBy: "statusItemTitle ?? \"\"").count - 1 }
                .reduce(0, +) == 1,
            "the adaptation appears more than once in the app"
        )

        // No drawn badge anywhere, and no count composed by a surface.
        let block = try Self.menuBarBlock(app.code)
        for source in try MenuBarSources.load() + [AppSecuritySources.Source(name: "the scene", code: block)] {
            for token in ["ImageRenderer", "NSImage", "NSStatusItem", "\\(outdatedCount)"] {
                #expect(source.code.contains(token) == false, "\(source.name) contains \(token)")
            }
            for line in source.code.split(separator: "\n") where line.contains("Text(") {
                #expect(line.contains(".count)") == false, "\(source.name) composes a count: \(line)")
            }
        }
        // The adaptation happens at the boundary and nowhere inside it: no file
        // under the menu-bar directory carries it.
        for source in try MenuBarSources.load() {
            #expect(source.code.contains("?? \"\"") == false, "\(source.name) adapts the absence itself")
        }
    }

    // MARK: - T14 — a scene, not a section (spec:390)

    @Test("The menu bar adds no section and no shell literal moves")
    func theMenuBarAddsNoSectionAndNoShellLiteralMoves() throws {
        #expect(AppSection.allCases.count == 22)
        #expect(
            AppSection.allCases.map(\.rawValue) == [
                "home", "browse", "tapSearch", "caskBrowse", "caskFeatured", "caskTopCharts",
                "caskRecentlyAdded", "caskCategory", "formulaBrowse", "formulaFeatured",
                "formulaTopCharts", "installed", "favorites", "updates", "taps", "services",
                "cleanup", "health", "security", "brewfile", "history", "settings"
            ]
        )

        let sources = try AppSecuritySources.load()
        let section = try #require(sources.first { $0.name == "AppSection.swift" })
        #expect(section.code.localizedCaseInsensitiveContains("menubar") == false)

        // No fourth switch, and no menu-bar reference at all, in the view whose
        // switch count is pinned.
        let content = try #require(sources.first { $0.name == "ContentView.swift" })
        #expect(content.code.contains("MenuBar") == false, "ContentView reaches for the menu bar")

        // A scene is not a section: nothing on this surface knows the vocabulary.
        for source in try MenuBarSources.load() {
            #expect(source.code.contains("AppSection") == false, "\(source.name) references AppSection")
        }
    }

    // MARK: - T15 — no entry depends on a window being open (spec:368)

    @Test("No entry depends on a window being open")
    func noEntryDependsOnAWindowBeingOpen() throws {
        let app = try #require(try AppSecuritySources.load().first { $0.name == "cellarApp.swift" })
        let block = try Self.menuBarBlock(app.code)

        // The one opening, in the one entry, by the scene's own identifier.
        #expect(app.code.contains("WindowGroup(id: \"main\")"), "the main window carries no identifier")
        #expect(
            app.code.components(separatedBy: "openWindow(").count - 1 == 1,
            "the app opens a window from more than one place"
        )
        #expect(block.contains("openMainWindow: { openWindow(id: \"main\") }"))

        // The popover takes a plain closure, so it cannot check what it opened
        // or make anything conditional on a window existing.
        let popover = try #require(try MenuBarSources.load().first { $0.name == "MenuBarPopoverView.swift" })
        #expect(popover.code.contains("let openMainWindow: () -> Void"))
        for source in try MenuBarSources.load() {
            for token in [
                "openWindow", "dismissWindow", "NSWindow", ".windows",
                "isKeyWindow", "keyWindow", "\\.scenePhase", "\\.controlActiveState"
            ] {
                #expect(source.code.contains(token) == false, "\(source.name) contains \(token)")
            }
        }

        // The submissions are unconditional: no window token gates either.
        let upgrade = try #require(popover.code.range(of: "operations.submit(.upgradeAll)"))
        let precedingLine = popover.code[..<upgrade.lowerBound].split(separator: "\n").suffix(1).joined()
        #expect(precedingLine.contains("guard") == false)
        #expect(precedingLine.contains("openWindow") == false)
    }

    // MARK: - T16 — the scene constructs no store and no loop (spec:398)

    @Test("The scene constructs no store and no refresh loop")
    func theSceneConstructsNoStoreAndNoRefreshLoop() throws {
        let app = try #require(try AppSecuritySources.load().first { $0.name == "cellarApp.swift" })
        let block = try Self.menuBarBlock(app.code)

        for source in try MenuBarSources.load() + [AppSecuritySources.Source(name: "the scene", code: block)] {
            for token in [
                "InstalledStore(", "ServicesStore(", "MetadataStore(", "CatalogStore(",
                "OperationCenter(", "LoopOwner", "RefreshCoordinator(", "loops.start(",
                "@State private var"
            ] {
                #expect(source.code.contains(token) == false, "\(source.name) constructs \(token)")
            }
        }

        // The popover's inputs are `let` properties, not state it owns.
        let popover = try #require(try MenuBarSources.load().first { $0.name == "MenuBarPopoverView.swift" })
        #expect(popover.code.contains("let projection: MenuBarProjection"))
        #expect(popover.code.contains("let operations: OperationCenter"))
        #expect(popover.code.contains("@State") == false, "the popover holds state of its own")

        // And the scene passes the same app-level identifiers the window does.
        #expect(block.contains("operations: operations"))
        #expect(block.contains(".environment(theme)"))
    }

    // MARK: - Support

    /// The `MenuBarExtra` scene block, from its opening call to the style
    /// modifier that closes it.
    private static func menuBarBlock(_ code: String) throws -> String {
        let start = try #require(code.range(of: "MenuBarExtra("), "the app declares no MenuBarExtra")
        let end = try #require(
            code.range(of: ".menuBarExtraStyle", range: start.upperBound..<code.endIndex),
            "the MenuBarExtra scene is not closed by a style modifier"
        )
        return String(code[start.lowerBound..<end.lowerBound])
    }

    /// The About `Window` block — the shipped precedent the menu-bar scene is
    /// compared against.
    private static func aboutBlock(_ code: String) throws -> String {
        let start = try #require(code.range(of: "Window(\"About"))
        let end = try #require(code.range(of: ".defaultPosition(.center)", range: start.upperBound..<code.endIndex))
        return String(code[start.lowerBound..<end.upperBound])
    }

    /// One `BrewClient` source, read off disk. The projection lives in the
    /// package, so the app-target sweep cannot see it.
    private static func coreSource(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Packages/CellarCore/Sources/BrewClient")
            .appendingPathComponent(name)
        let text = try String(contentsOf: url, encoding: .utf8)
        let stripped = AppSecuritySources.stripComments(from: text)
        #expect(stripped.isEmpty == false, "\(name) was read as empty")
        return stripped
    }

    /// Every `.swift` under `cellar/MenuBar/`, read off disk and stripped of
    /// comments.
    ///
    /// The directory is enumerated rather than named file by file, so a source
    /// added to this surface later joins the sweep the moment it exists. The
    /// stripper is `AppSecuritySources`' own, so a prohibition *described* in a
    /// doc comment is never mistaken for one *violated* in code.
    private enum MenuBarSources {
        /// Every token this surface may not contain. The one permitted
        /// asynchronous hop lives one file up, in the scene block, which is what
        /// makes this list absolute rather than "except for the one we needed".
        static let forbidden = [
            ".task", "Task {", "await ", "async ",
            "Process(", "URLSession",
            "CaskIconLoader", "PackageIconTile", "CaskIconView(",
            "ImageRenderer", "NSImage", "NSStatusItem",
            "pendingConfirmation", ".mutationConfirmation",
            "MutationCommand.uninstall", ".zap",
            "setVisible(", "setActive(", "refreshEverything",
            "SwiftData", "LocalStores"
        ]

        static var directory: URL {
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // cellarTests
                .deletingLastPathComponent()   // repository root
                .appendingPathComponent("cellar")
                .appendingPathComponent("MenuBar")
        }

        static func load() throws -> [AppSecuritySources.Source] {
            var sources: [AppSecuritySources.Source] = []
            for url in try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                sources.append(
                    AppSecuritySources.Source(
                        name: url.lastPathComponent,
                        code: AppSecuritySources.stripComments(from: text)
                    )
                )
            }
            let sorted = sources.sorted { $0.name < $1.name }

            // Positive anchor. A scan that read nothing sweeps clean, so the
            // enumeration has to find the surface — and every file it found has
            // to be one the app target itself compiles, which is what proves
            // the directory joined the target.
            #expect(sorted.count >= 3, "the menu-bar sweep found \(sorted.count) file(s)")
            let compiled = Set(try AppSecuritySources.load().map(\.name))
            for source in sorted {
                #expect(compiled.contains(source.name), "\(source.name) is not in the app target's sources")
            }
            return sorted
        }
    }
}

/// What the status item and its popover say once a second source can contribute.
///
/// Added by the npm slice, beside the composition claims above rather than in a
/// file of its own, because the rule under test is the same one: **the number
/// and the sentence come from one value**. The npm half only makes the stakes
/// higher — a count is merely wrong when it disagrees, but "up to date" over an
/// unreachable registry is a claim the user acts on by doing nothing
/// (`menu-bar`: the status item counts both sources and says when npm was not
/// checked; MB1 as modified).
@Suite("Menu bar and the npm source")
struct MenuBarNpmCompositionTests {
    private static let checkedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static func browse(
        _ packages: [InstalledPackage],
        npmSource: NpmSourceAvailability = .available
    ) -> InstalledBrowse {
        InstalledBrowse(
            inventory: InstalledInventory(packages: packages),
            isAvailable: true,
            npmSource: npmSource
        )
    }

    private static func npm(_ name: String, outdated: Bool) -> InstalledPackage {
        HealthFixtures.package(
            name,
            kind: .npm,
            installed: outdated ? "5.6.0" : "5.7.0",
            offering: "5.7.0",
            outdated: outdated,
            tap: ""
        )
    }

    // MARK: - The count

    @Test("Outdated npm packages reach the count and the entries, by delegation")
    func npmEntriesReachTheCountAndTheEntries() {
        let browse = Self.browse([
            HealthFixtures.package("git", offering: "2.48.0", outdated: true),
            HealthFixtures.package("iterm2", kind: .cask, offering: "3.6.0", outdated: true),
            HealthFixtures.package("wget"),
            Self.npm("typescript", outdated: true),
        ])
        let projection = MenuBarProjection(
            browse: browse,
            metadata: nil,
            services: [],
            npmFreshness: .fresh(
                ["typescript": NpmOutdatedRecord(current: "5.6.0", wanted: nil, latest: "5.7.0")],
                at: Self.checkedAt
            )
        )

        #expect(projection.statusItemTitle == "3")
        #expect(projection.outdatedCount == browse.outdatedCount(metadata: nil))
        #expect(projection.outdatedIDs == browse.outdatedIDs(metadata: nil))
        #expect(projection.topOutdated.map(\.name) == ["git", "iterm2", "typescript"])
        // Nothing needs disclosing: npm answered, and the count is simply right.
        #expect(projection.npmNotCheckedCopy == nil)
    }

    // MARK: - Offline is stated, not hidden

    @Test("An offline npm is stated and never rendered as up to date")
    func offlineNpmIsStatedNotHidden() throws {
        let projection = MenuBarProjection(
            browse: Self.browse([HealthFixtures.package("wget"), Self.npm("typescript", outdated: false)]),
            metadata: nil,
            services: [],
            npmFreshness: .failed(.networkUnavailable)
        )

        #expect(projection.statusItemTitle == nil, "an unchecked npm invented a count")
        #expect(projection.upToDateCopy == nil, "an unreachable registry read as up to date")

        let copy = try #require(projection.npmNotCheckedCopy, "the offline state was hidden")
        #expect(copy.contains("npm not checked"))
        #expect(copy.contains("network"))
    }

    /// Triangulation: the same shape with a completed check says the sentence
    /// the case above refuses, so the refusal is a decision rather than a
    /// missing branch.
    @Test("A completed check with nothing outdated is allowed to say up to date")
    func aCompletedCleanCheckMaySayUpToDate() {
        let projection = MenuBarProjection(
            browse: Self.browse([HealthFixtures.package("wget"), Self.npm("typescript", outdated: false)]),
            metadata: nil,
            services: [],
            npmFreshness: .fresh([:], at: Self.checkedAt)
        )

        #expect(projection.statusItemTitle == nil)
        #expect(projection.upToDateCopy == InstalledUpdatesSummary.upToDateLabel)
        #expect(projection.npmNotCheckedCopy == nil)
    }

    // MARK: - The disclosure beside `Upgrade all`

    /// `Upgrade all` submits bare `brew upgrade` and nothing else, so a popover
    /// that showed an npm package in its list and offered that button would be
    /// promising something it does not do.
    @Test("The disclosure appears exactly when npm has something outdated")
    func theDisclosureFollowsTheNpmCount() throws {
        let withNpmOutdated = MenuBarProjection(
            browse: Self.browse([
                HealthFixtures.package("git", offering: "2.48.0", outdated: true),
                Self.npm("typescript", outdated: true),
            ]),
            metadata: nil,
            services: [],
            npmFreshness: .fresh(
                ["typescript": NpmOutdatedRecord(current: "5.6.0", wanted: nil, latest: "5.7.0")],
                at: Self.checkedAt
            )
        )
        let disclosure = try #require(
            withNpmOutdated.npmUpgradeDisclosure,
            "an npm entry was listed beside a button that will not upgrade it"
        )
        #expect(disclosure.contains("npm"))
        #expect(disclosure.contains("Updates"))

        // Only brew is behind, so the button does exactly what the list implies.
        let brewOnly = MenuBarProjection(
            browse: Self.browse([
                HealthFixtures.package("git", offering: "2.48.0", outdated: true),
                Self.npm("typescript", outdated: false),
            ]),
            metadata: nil,
            services: [],
            npmFreshness: .fresh([:], at: Self.checkedAt)
        )
        #expect(brewOnly.npmUpgradeDisclosure == nil)
    }

    /// MB4 is untouched: the verb is still bare, still uncounted, and still
    /// fans out to nothing.
    @Test("The upgrade verb is unchanged by this capability")
    func theUpgradeVerbIsUnchanged() {
        #expect(MutationCommand.upgradeAll.displayCommand == "brew upgrade")
        #expect(MutationCommand.upgradeAll.source == .homebrew)
    }

    // MARK: - npm off

    @Test("With the source off the projection is identical to the shipped one")
    func npmOffIsIdenticalToTheShippedProjection() {
        let packages = [
            HealthFixtures.package("git", offering: "2.48.0", outdated: true),
            HealthFixtures.package("wget"),
        ]
        let shipped = MenuBarProjection(
            browse: Self.browse(packages, npmSource: .disabled), metadata: nil, services: []
        )

        // Every freshness, including the two that would otherwise disclose:
        // with the source off there is no npm half to say anything about.
        for freshness in [
            NpmOutdatedState.notChecked(.notYetChecked),
            .failed(.networkUnavailable),
            .fresh([:], at: Self.checkedAt),
        ] {
            let projection = MenuBarProjection(
                browse: Self.browse(packages, npmSource: .disabled),
                metadata: nil,
                services: [],
                npmFreshness: freshness
            )

            #expect(projection == shipped)
            #expect(projection.npmNotCheckedCopy == nil)
            #expect(projection.npmUpgradeDisclosure == nil)
            #expect(projection.statusItemTitle == "1")
        }
    }

    // MARK: - MB1: four pure inputs, none of them effectful

    @Test("The projection takes four inputs and none of them is effectful")
    func theProjectionTakesFourPureInputs() throws {
        let projection = try Self.coreSource("MenuBarProjection.swift")

        for label in ["browse:", "metadata:", "services:", "npmFreshness:"] {
            #expect(projection.contains(label), "the projection lost the \(label) input")
        }
        for effect in [
            "ProcessLaunching", "URLSession", "Clock", "Store", "launcher", "session", "refresh",
        ] {
            #expect(projection.contains(effect) == false, "\(effect) became an input")
        }
        // Still delegated, still not re-derived.
        #expect(projection.contains("outdatedCount(metadata:"))
        #expect(projection.contains("outdatedIDs(metadata:"))
        #expect(projection.contains("isOutdated") == false)
    }

    /// The popover reads the projection's sentences rather than composing its
    /// own, which is what makes "MUST NOT present up to date" a property of one
    /// value instead of a review note on one view.
    @Test("The popover words nothing itself")
    func thePopoverWordsNothingItself() throws {
        let popover = try #require(
            try AppSecuritySources.load().first { $0.name == "MenuBarPopoverView.swift" }
        ).code

        #expect(popover.contains("projection.upToDateCopy"))
        #expect(popover.contains("projection.npmNotCheckedCopy"))
        #expect(popover.contains("projection.npmUpgradeDisclosure"))
        #expect(
            popover.contains("\"Everything is up to date\"") == false,
            "the popover still owns the one sentence it may not decide"
        )
    }

    private static func coreSource(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // cellarTests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Packages/CellarCore/Sources/BrewClient")
            .appendingPathComponent(name)
        let text = try String(contentsOf: url, encoding: .utf8)
        let stripped = AppSecuritySources.stripComments(from: text)
        #expect(stripped.isEmpty == false, "\(name) was read as empty")
        return stripped
    }
}
