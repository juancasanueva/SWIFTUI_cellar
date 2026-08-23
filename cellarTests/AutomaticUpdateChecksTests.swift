//
//  AutomaticUpdateChecksTests.swift
//  cellarTests
//

import Foundation
import Testing

@testable import cellar

/// Where the automatic-check answer actually lives.
///
/// Driven against a scratch defaults suite rather than `.standard`, so a test
/// run never reads or writes the developer's real preferences and the
/// fresh-install case is genuinely fresh instead of left over from a previous
/// run. The suite name carries a UUID for the same reason.
///
/// `@MainActor` because the app target compiles under
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so the type under test is
/// main-actor isolated like `SecurityConsentPreference` beside it.
@MainActor
@Suite("Automatic update checks")
struct AutomaticUpdateChecksTests {
    /// A defaults domain that exists only for this test, and is removed after it.
    private func withScratchSuite(_ body: (UserDefaults, String) throws -> Void) rethrows {
        let name = "cellar-tests-updates-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("could not create the scratch defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults, name)
    }

    // MARK: - T13 — a fresh install does not check automatically

    /// A missing key reads `false`.
    ///
    /// There is deliberately no default that reads as consent. An update check
    /// is network egress, and Cellar gates every other egress behind an explicit
    /// answer; "we never asked" and "they said yes" must not be the same value.
    @Test("A fresh install reads as off")
    func aFreshInstallReadsAsOff() {
        withScratchSuite { defaults, _ in
            let preference = AutomaticUpdateChecks(defaults: defaults)

            #expect(defaults.object(forKey: AutomaticUpdateChecks.key) == nil)
            #expect(preference.isEnabled == false)
        }
    }

    // MARK: - T13 — the user's choice survives a relaunch

    /// Written by one reader, read back by another over the same suite.
    ///
    /// A second instance is what makes this a persistence test rather than a
    /// property test: an implementation that cached the value in memory would
    /// pass a single-instance round trip and lose the answer at the next launch.
    @Test("The choice survives a relaunch, in both directions")
    func theChoiceSurvivesARelaunch() {
        withScratchSuite { defaults, name in
            AutomaticUpdateChecks(defaults: defaults).isEnabled = true
            let afterEnabling = UserDefaults(suiteName: name)
            #expect(AutomaticUpdateChecks(defaults: afterEnabling ?? defaults).isEnabled == true)

            AutomaticUpdateChecks(defaults: defaults).isEnabled = false
            let afterDisabling = UserDefaults(suiteName: name)
            #expect(AutomaticUpdateChecks(defaults: afterDisabling ?? defaults).isEnabled == false)
        }
    }

    /// Turning the preference off writes `false` rather than removing the key.
    ///
    /// Both read as off today. They stop being the same the moment anything else
    /// distinguishes "never answered" from "answered no", so the stored value is
    /// pinned rather than left to the reader's default.
    @Test("Turning it off records a stored false")
    func turningItOffRecordsAStoredFalse() {
        withScratchSuite { defaults, _ in
            let preference = AutomaticUpdateChecks(defaults: defaults)
            preference.isEnabled = true
            preference.isEnabled = false

            #expect(defaults.object(forKey: AutomaticUpdateChecks.key) as? Bool == false)
        }
    }

    // MARK: - T13 — nothing else in the suite is written

    /// Exactly one key, named.
    ///
    /// The whole defaults domain is read back, so this is a claim about what the
    /// type wrote rather than about what it was asked to write. A stray
    /// companion key — a timestamp, a migration marker, a cached mirror of
    /// Sparkle's own flag — would fail it.
    @Test("The preference writes exactly one key and nothing else")
    func thePreferenceWritesExactlyOneKey() {
        withScratchSuite { defaults, name in
            AutomaticUpdateChecks(defaults: defaults).isEnabled = true

            let domain = defaults.persistentDomain(forName: name) ?? [:]
            #expect(domain.keys.sorted() == [AutomaticUpdateChecks.key])
            #expect(AutomaticUpdateChecks.key == "updates.automaticChecksEnabled")
        }
    }
}
