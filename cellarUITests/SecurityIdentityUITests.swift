//
//  SecurityIdentityUITests.swift
//  cellarUITests
//

import XCTest

/// The one check a presentation test cannot make: that the signing-identity
/// control is actually **interactive**.
///
/// This exists because it shipped broken twice over. First the panel rendered
/// only the team identifier; then the fix rendered all three fields behind a
/// `DisclosureGroup` that drew no indicator and responded to no click, so the
/// authority chain stayed unreachable and MV-7 still could not close. Both passed
/// every unit test, because a projection test proves a value exists and says
/// nothing about whether a human can get to it.
///
/// Deterministic by construction: `--ui-testing-m4-security` injects two fixed
/// reports, so this never depends on what happens to be installed or on a real
/// sweep completing.
final class SecurityIdentityUITests: XCTestCase {
    @MainActor
    func testSigningIdentityDisclosureRevealsTheAuthorityChain() throws {
        let app = launchSecurityFixture()

        app.staticTexts["Security"].click()

        let disclosure = app.descendants(matching: .any)["security-integrity-ghostty-identity"]
        XCTAssertTrue(
            disclosure.waitForExistence(timeout: 10),
            "the signing-identity control never appeared"
        )

        // Collapsed: the chain is not on screen. Asserted *before* the tap, so a
        // control that was already open could not make this test pass by accident.
        let leafAuthority = app.descendants(matching: .any)["security-integrity-ghostty-authority-0"]
        XCTAssertFalse(leafAuthority.exists, "the chain was visible before the control was used")

        disclosure.click()

        XCTAssertTrue(
            leafAuthority.waitForExistence(timeout: 5),
            "tapping the signing-identity control revealed nothing — it is not interactive"
        )
        for suffix in ["identifier", "team", "authority-0", "authority-1", "authority-2"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["security-integrity-ghostty-\(suffix)"].exists,
                "\(suffix) is missing, so MV-7 cannot compare all three fields"
            )
        }

        // And it closes again, or it is a reveal rather than a disclosure.
        disclosure.click()
        XCTAssertFalse(
            leafAuthority.waitForExistence(timeout: 2),
            "the control does not collapse"
        )
    }

    /// An ad-hoc artifact has an identifier and genuinely no chain. Its control
    /// must still work, and must not invent the two fields it does not have.
    @MainActor
    func testAdHocIdentityDisclosesItsIdentifierAndNoChain() throws {
        let app = launchSecurityFixture()
        app.staticTexts["Security"].click()

        let disclosure = app.descendants(matching: .any)["security-integrity-ripgrep-identity"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
        disclosure.click()

        XCTAssertTrue(
            app.descendants(matching: .any)["security-integrity-ripgrep-identifier"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.descendants(matching: .any)["security-integrity-ripgrep-team"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["security-integrity-ripgrep-authority-0"].exists)
    }

    @MainActor
    private func launchSecurityFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-m4-security")
        app.launch()
        return app
    }
}
