//
//  TapTrustUITests.swift
//  cellarUITests
//

import XCTest

/// The one claim about the trust surface that only a running app can make: that
/// the control a user can actually press appears for exactly the state it can
/// succeed for (tap-management TM12 :452-458).
///
/// A unit test proves `TapProjection.trust(for:)` returns the right three
/// values, and a source scan proves both views read that projection. Neither
/// proves that the view then draws what it read — and an `unreported` tap whose
/// Trust button is on screen would offer the user a `brew trust` the brew under
/// it cannot run.
///
/// Deterministic by construction: `--ui-testing-m7-tap-trust` swaps the tap
/// payload for three third-party taps, one in each state, so nothing depends on
/// what this Mac has tapped.
final class TapTrustUITests: XCTestCase {

    @MainActor
    func testTheTrustControlAppearsOnlyForAnUntrustedTap() throws {
        let app = launchTapTrustFixture()
        openTaps(in: app)

        // Untrusted — the badge, and the grant.
        select(tap: "acme/untrusted", in: app)
        let badge = app.descendants(matching: .any).matching(identifier: "tap-detail-trust-badge").firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 15), "an untrusted tap showed no badge in the detail header")
        XCTAssertEqual(text(of: badge), "Untrusted", "the badge text is not the pinned copy")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "tap-trust-button").firstMatch.waitForExistence(timeout: 15),
            "an untrusted tap offered no Trust control"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "tap-untrust-button").firstMatch.exists,
            "an untrusted tap offered Untrust, which would revoke a grant it does not have"
        )

        // Trusted — no badge, and the revocation instead.
        select(tap: "acme/trusted", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "tap-untrust-button").firstMatch.waitForExistence(timeout: 15),
            "a trusted tap offered no Untrust control"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "tap-trust-button").firstMatch.exists,
            "a trusted tap offered Trust"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "tap-detail-trust-badge").firstMatch.exists,
            "a trusted tap carried a badge in its header"
        )

        // Unreported — a Homebrew with no trust concept claims nothing and
        // offers nothing.
        select(tap: "acme/unreported", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "tap-untap-button").firstMatch.waitForExistence(timeout: 15),
            "the unreported tap's detail pane never appeared, so the absences below prove nothing"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "tap-trust-button").firstMatch.exists,
            "an unreported tap offered Trust"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "tap-untrust-button").firstMatch.exists,
            "an unreported tap offered Untrust"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "tap-detail-trust-badge").firstMatch.exists,
            "an unreported tap carried a badge in its header"
        )
    }

    // MARK: - Arrangement

    @MainActor
    private func launchTapTrustFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-m3-taps", "--ui-testing-m7-tap-trust"]
        app.launch()
        return app
    }

    @MainActor
    private func openTaps(in app: XCUIApplication) {
        let taps = app.descendants(matching: .any)["sidebar-taps"]
        XCTAssertTrue(taps.waitForExistence(timeout: 20), "the Taps section never appeared")
        taps.click()

        let list = app.descendants(matching: .any)["taps-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 20), "the tap list never appeared")
    }

    @MainActor
    private func select(tap name: String, in app: XCUIApplication) {
        let list = app.descendants(matching: .any)["taps-list"]
        let row = list.descendants(matching: .any).staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "\(name) is not in the tap list")
        row.click()
    }

    /// Inside a `List`, a row's text does not surface as an element `label` at
    /// all, so a label-only read reaches nothing.
    @MainActor
    private func text(of element: XCUIElement) -> String {
        let value = (element.value as? String) ?? ""
        return value.isEmpty ? element.label : value
    }
}
