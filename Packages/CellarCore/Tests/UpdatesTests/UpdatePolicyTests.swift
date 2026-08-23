//
//  UpdatePolicyTests.swift
//  UpdatesTests
//

import Foundation
import Testing

@testable import Updates

/// The two update decisions, tested where they live.
///
/// Both are decisions — a `Bool` in, a `Bool` out — with no framework in them,
/// which is why they sit here rather than in the app target. The spec classes
/// both scenarios as unit-testable, and a scenario whose only evidence is a
/// source sweep is a scenario nobody can fail on purpose.
@MainActor
@Suite("Update policy")
struct UpdatePolicyTests {
    // MARK: - T7b — the persisted preference is written to the updater at launch

    /// The preference wins, in both directions, whatever the updater currently
    /// believes.
    ///
    /// Each case starts from an updater that **disagrees** with the preference.
    /// A policy that only wrote when it already matched would pass a test that
    /// started from agreement, and would leave a framework-persisted `true`
    /// intact on a machine where the user has turned checking off — which is the
    /// exact failure the requirement exists to prevent.
    @Test("The persisted preference is written to the updater", arguments: [true, false])
    func thePersistedPreferenceIsWrittenToTheUpdater(preference: Bool) {
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: !preference)

        AutomaticUpdateChecksPolicy.apply(preference: preference, to: updater)

        #expect(updater.automaticallyChecksForUpdates == preference)
        #expect(updater.automaticWriteCount == 1)
    }

    /// One write, not two.
    ///
    /// An update check is network egress. A policy that wrote `true` on the way
    /// to `false` would let the updater schedule a check in between, on a launch
    /// where the user had said no.
    @Test("Applying the preference writes exactly once")
    func applyingThePreferenceWritesExactlyOnce() {
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: true)

        AutomaticUpdateChecksPolicy.apply(preference: false, to: updater)

        #expect(updater.automaticWriteCount == 1)
        #expect(updater.automaticallyChecksForUpdates == false)
    }

    /// An off run leaves the updater off, even when it was already off.
    ///
    /// The idempotent case is asserted separately because it is the one a
    /// "only write when it differs" optimisation would silently change: the
    /// write count would drop to zero and the requirement — *at every launch the
    /// app writes the setting to the updater* — would quietly stop holding.
    @Test("An off run leaves automatic checking off")
    func anOffRunLeavesAutomaticCheckingOff() {
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: false)

        AutomaticUpdateChecksPolicy.apply(preference: false, to: updater)

        #expect(updater.automaticallyChecksForUpdates == false)
        #expect(updater.automaticWriteCount == 1)
    }

    // MARK: - T7c — the command is enabled exactly while a check can run

    /// The menu item is live if and only if the updater can check.
    ///
    /// Table-driven over the whole domain of the input, which is two values.
    /// Nothing else may enter this decision: not whether automatic checking is
    /// on, not whether the last check found anything, not whether the app has
    /// ever checked.
    @Test("The command is enabled exactly while the updater can check", arguments: [true, false])
    func theCommandIsEnabledExactlyWhileTheUpdaterCanCheck(canCheck: Bool) {
        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: canCheck) == canCheck)
    }

    /// The rule reads only `canCheckForUpdates`, driven through the seam.
    ///
    /// Two updaters that differ **only** in their automatic-check flag produce
    /// the same enablement, which is the half of the requirement a table over a
    /// bare `Bool` cannot state.
    @Test("Automatic checking does not decide the command's enablement")
    func automaticCheckingDoesNotDecideEnablement() {
        let automaticOff = FakeAppUpdater(canCheckForUpdates: true, automaticallyChecksForUpdates: false)
        let automaticOn = FakeAppUpdater(canCheckForUpdates: true, automaticallyChecksForUpdates: true)
        let inFlight = FakeAppUpdater(canCheckForUpdates: false, automaticallyChecksForUpdates: false)

        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: automaticOff.canCheckForUpdates))
        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: automaticOn.canCheckForUpdates))
        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: inFlight.canCheckForUpdates) == false)
    }
}
