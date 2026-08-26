//
//  MenuBarCompositionTests.swift
//  cellarTests
//

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
        let menuBar = try Self.menuBarSources()
        #expect(menuBar.isEmpty == false, "no menu-bar source was found to scan")
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

    // MARK: - Support

    /// Every `.swift` under `cellar/MenuBar/`, comments stripped.
    ///
    /// Selected by name from the app-wide sweep rather than enumerated a second
    /// time, so a file that never joined the target cannot be scanned into a
    /// clean result here either.
    private static func menuBarSources() throws -> [AppSecuritySources.Source] {
        try AppSecuritySources.load().filter { $0.name.hasPrefix("MenuBar") }
    }
}
