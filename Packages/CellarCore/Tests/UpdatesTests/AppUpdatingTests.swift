//
//  AppUpdatingTests.swift
//  UpdatesTests
//

import Foundation
import Observation
import Testing

@testable import Updates

/// An in-memory `AppUpdating`, in the test target and never shipped.
///
/// It exists so the contract can be driven without the updater framework, which
/// ships no test harness. Everything the app asks of an updater is asked of this
/// instead, and the count is a number rather than an impression: "exactly one
/// check" is only provable if something counted.
@MainActor
@Observable
final class FakeAppUpdater: AppUpdating {
    private(set) var checkCount = 0
    var canCheckForUpdates: Bool
    private(set) var lastUpdateCheckDate: Date?

    /// How many times the flag was written, not merely what it ends up as.
    ///
    /// "The launch wiring writes the preference exactly once" is a claim about
    /// the number of writes: a policy that wrote `false` and then `true` and then
    /// `false` again would leave the same final value and would flip the
    /// updater's schedule on twice on the way there.
    @ObservationIgnored private(set) var automaticWriteCount = 0
    @ObservationIgnored private var storedAutomaticChecks: Bool

    var automaticallyChecksForUpdates: Bool {
        get { storedAutomaticChecks }
        set {
            storedAutomaticChecks = newValue
            automaticWriteCount += 1
        }
    }

    init(canCheckForUpdates: Bool = true, automaticallyChecksForUpdates: Bool = false) {
        self.canCheckForUpdates = canCheckForUpdates
        self.storedAutomaticChecks = automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        checkCount += 1
    }

    func recordCheck(at date: Date) {
        lastUpdateCheckDate = date
    }
}

/// The seam every update surface speaks to.
@MainActor
@Suite("App updating")
struct AppUpdatingTests {
    // MARK: - T7 — invoking the command starts exactly one check

    /// One invocation, one check — and two invocations, two checks.
    ///
    /// The second half is what makes the first meaningful: an implementation
    /// that ignored the call entirely would satisfy "not more than one", and one
    /// that latched after the first would satisfy "at least one".
    @Test("Each invocation starts exactly one check")
    func eachInvocationStartsExactlyOneCheck() {
        let updater = FakeAppUpdater()

        #expect(updater.checkCount == 0)
        updater.checkForUpdates()
        #expect(updater.checkCount == 1)
        updater.checkForUpdates()
        #expect(updater.checkCount == 2)
    }

    /// The automatic-check flag is readable and writable through the seam.
    ///
    /// Both directions, because the launch-time wiring writes it and the
    /// Settings toggle reads it back; a write-only or read-only seam would leave
    /// one of the two surfaces lying.
    @Test("The automatic-check flag round-trips through the seam")
    func theAutomaticCheckFlagRoundTrips() {
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: false)

        #expect(updater.automaticallyChecksForUpdates == false)
        updater.automaticallyChecksForUpdates = true
        #expect(updater.automaticallyChecksForUpdates == true)
        updater.automaticallyChecksForUpdates = false
        #expect(updater.automaticallyChecksForUpdates == false)
    }

    /// The seam reports whether a check can run at all, independently of whether
    /// automatic checking is on.
    ///
    /// The two are deliberately unrelated: the explicit command must stay live
    /// while automatic checking is off, and must go dark only while a check is
    /// genuinely in flight.
    @Test("Whether a check can run is independent of automatic checking")
    func whetherACheckCanRunIsIndependentOfAutomaticChecking() {
        let idle = FakeAppUpdater(canCheckForUpdates: true, automaticallyChecksForUpdates: false)
        let inFlight = FakeAppUpdater(canCheckForUpdates: false, automaticallyChecksForUpdates: true)

        #expect(idle.canCheckForUpdates)
        #expect(idle.automaticallyChecksForUpdates == false)
        #expect(inFlight.canCheckForUpdates == false)
        #expect(inFlight.automaticallyChecksForUpdates)
    }

    /// A fresh updater has never checked, and says so through the seam.
    @Test("The recorded check date starts absent and follows a recorded check")
    func theRecordedCheckDateFollowsARecordedCheck() {
        let updater = FakeAppUpdater()
        let checked = Date(timeIntervalSince1970: 1_787_000_000)

        #expect(updater.lastUpdateCheckDate == nil)
        updater.recordCheck(at: checked)
        #expect(updater.lastUpdateCheckDate == checked)
    }
}
