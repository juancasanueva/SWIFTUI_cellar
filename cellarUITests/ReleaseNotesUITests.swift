//
//  ReleaseNotesUITests.swift
//  cellarUITests
//

import XCTest

/// The three things a projection test cannot check: that the affordance is
/// reachable, that a refusal shows the **consent surface** rather than a spinner,
/// and that a rate-limited answer does not read as an absence.
///
/// Every unit test in this slice proves a value is correct. None of them proves a
/// human can get to it, and none of them proves the sentence a human actually
/// sees. That gap is where this capability's worst failure lives: a user told "no
/// release notes" when the truth is "you are rate-limited until 21:15" will
/// reasonably conclude the project publishes nothing.
///
/// Deterministic by construction: `--ui-testing-m5-release-notes` injects a fixed
/// outdated inventory and a stubbed transport, so nothing here depends on what is
/// installed, on network access, or on GitHub's mood.
final class ReleaseNotesUITests: XCTestCase {
    // MARK: - Without a grant

    /// The refusal is an invitation. Not a spinner that never resolves, not an
    /// empty sheet, and not one of the four absences — the user has simply not
    /// been asked yet.
    @MainActor
    func testWithoutAGrantTheActionShowsTheConsentSurface() throws {
        let app = launch()

        let action = releaseNotesButton(in: app)
        XCTAssertTrue(
            action.waitForExistence(timeout: 15),
            "the outdated row offers no release-notes action"
        )

        action.click()

        let consent = app.descendants(matching: .any)["release-notes-consent"]
        XCTAssertTrue(
            consent.waitForExistence(timeout: 10),
            "clicking with no grant did not show the consent surface"
        )

        // And it is the consent surface rather than a notes sheet that happens to
        // be empty.
        XCTAssertFalse(
            app.descendants(matching: .any)["release-notes-sheet"].exists,
            "an unconsented click opened the notes sheet"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["release-notes-loading"].exists,
            "an unconsented click showed a spinner"
        )

        // The disclosure is on screen, not behind a disclosure triangle: what
        // leaves the machine has to be readable before the button that grants it.
        let disclosure = app.descendants(matching: .any)["release-notes-consent-disclosure"]
        XCTAssertTrue(disclosure.exists, "the consent surface hides its disclosure")
        XCTAssertTrue(
            app.descendants(matching: .any)["release-notes-consent-grant"].exists,
            "the consent surface offers no way to grant"
        )
        // The token field is offered here, where it is explained, rather than
        // only after a wall is hit.
        XCTAssertTrue(
            app.descendants(matching: .any)["release-notes-consent-token"].exists,
            "the consent surface offers no token field"
        )
    }

    /// The affordance is offered only where it can work. The fixture's second
    /// package is outdated too and resolves to no repository, so this is a real
    /// discrimination and not a row that simply is not there.
    @MainActor
    func testTheActionIsOfferedOnlyForAPackageWithAResolvableRepository() throws {
        let app = launch()

        XCTAssertTrue(
            releaseNotesButton(in: app).waitForExistence(timeout: 15),
            "the resolvable outdated row offers no action"
        )
        // Both rows are on screen…
        XCTAssertTrue(
            app.descendants(matching: .any)["installed-row-formula-widget"].exists,
            "the unresolvable row is missing, so this proves nothing"
        )
        // …and only one of them carries the action.
        XCTAssertFalse(
            app.descendants(matching: .any)["release-notes-open-widget"].exists,
            "a package with no resolvable repository was offered the action"
        )
    }

    // MARK: - With a grant

    @MainActor
    func testWithAGrantAndAStubbedTransportANoteRenders() throws {
        let app = launch(granted: true)

        let action = releaseNotesButton(in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        action.click()

        let sheet = app.descendants(matching: .any)["release-notes-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 10), "the notes sheet never appeared")

        let headline = app.descendants(matching: .any)["release-notes-headline"]
        XCTAssertTrue(
            headline.waitForExistence(timeout: 10),
            "the sheet settled on no headline at all"
        )

        // The body the stub published is on screen, so this is a rendered note
        // and not an empty sheet that merely opened.
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "value CONTAINS[c] %@", "--sort")
            ).firstMatch.waitForExistence(timeout: 10),
            "the release body did not render"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["release-notes-consent"].exists,
            "a granted click showed the consent surface again"
        )
    }

    // MARK: - Rate limited

    /// The case this suite exists for. A `403` with an exhausted budget must show
    /// **when** the limit resets and offer the token, and must not read as one of
    /// the absences.
    @MainActor
    func testARateLimitedResponseShowsTheResetTimeAndTheTokenAffordance() throws {
        let app = launch(granted: true, rateLimited: true)

        let action = releaseNotesButton(in: app)
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        action.click()

        let rateLimited = app.descendants(matching: .any)["release-notes-rate-limited"]
        XCTAssertTrue(
            rateLimited.waitForExistence(timeout: 10),
            "a rate-limited response did not present as a rate limit"
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["release-notes-rate-limit-reset"].exists,
            "the rate-limited state does not say when the limit resets"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["release-notes-rate-limit-token"].exists,
            "the rate-limited state does not offer the token affordance"
        )

        // And it does not read as an absence. Asserted over the whole window's
        // text, because the failure mode is a *sentence*, not a missing element.
        let absences = ["no release notes", "publishes no releases", "no release matches"]
        let visible = app.staticTexts.allElementsBoundByIndex
            .compactMap { $0.value as? String ?? $0.label }
            .joined(separator: " ")
            .lowercased()
        for absence in absences {
            XCTAssertFalse(
                visible.contains(absence),
                "a rate-limited response read as an absence: \(absence)"
            )
        }
    }

    // MARK: - Launch

    @MainActor
    private func launch(granted: Bool = false, rateLimited: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-m5-release-notes"]
        if granted { app.launchArguments.append("--ui-testing-m5-release-notes-granted") }
        if rateLimited { app.launchArguments.append("--ui-testing-m5-release-notes-rate-limited") }
        app.launch()
        // By identifier, not by text: the sidebar row and the navigation title
        // both read "Installed", so a text query is ambiguous.
        let installed = app.descendants(matching: .any)["sidebar-installed"]
        XCTAssertTrue(installed.waitForExistence(timeout: 20), "Installed is not in the sidebar")
        installed.click()
        return app
    }

    @MainActor
    private func releaseNotesButton(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["release-notes-open-hyperfine"]
    }
}
