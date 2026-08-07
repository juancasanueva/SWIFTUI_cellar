//
//  HealthSectionUITests.swift
//  cellarUITests
//

import XCTest

/// The checks only a running app can make about Health and the widened bulk bar.
///
/// Three of them are worth a launch, and each one is a claim about pixels that no
/// unit test can reach:
///
/// - **Placement.** `.health` sits between Services and Security in the sidebar.
///   The enum ordering is asserted in `cellarTests`; whether the rows render in
///   that order on screen is not.
/// - **The score never appears without its caveat**, and a machine nothing could
///   be measured on gets a sentence rather than a `0` or a `100`.
/// - **Pin and unpin are two controls with two different numbers** over one mixed
///   selection, and an all-cask selection leaves both unavailable rather than
///   present and inert.
///
/// Deterministic by construction: `--ui-testing-m5-health` swaps the brew locator,
/// the launcher and the installed payload for fixtures, so no `brew` runs and the
/// inventory is the exact mixed selection `installed-inventory` II14 sc4 names.
final class HealthSectionUITests: XCTestCase {

    // MARK: - 12.1 — placement, the score, and the run-doctor claim

    @MainActor
    func testHealthSitsBetweenServicesAndSecurityInTheSidebar() throws {
        let app = launchHealthFixture()

        let services = app.descendants(matching: .any)["sidebar-services"]
        let cleanup = app.descendants(matching: .any)["sidebar-cleanup"]
        let health = app.descendants(matching: .any)["sidebar-health"]
        let security = app.descendants(matching: .any)["sidebar-security"]

        XCTAssertTrue(health.waitForExistence(timeout: 15), "Health is not in the sidebar")
        XCTAssertTrue(services.exists)
        XCTAssertTrue(security.exists)

        // Compared by vertical position, which is what "between" means on screen.
        XCTAssertLessThan(services.frame.minY, health.frame.minY, "Health is above Services")
        XCTAssertLessThan(cleanup.frame.minY, health.frame.minY, "Health is above Cleanup")
        XCTAssertLessThan(health.frame.minY, security.frame.minY, "Health is below Security")
    }

    /// Health did not take the landing spot, and Home still leads the sidebar.
    ///
    /// **Recorded rather than absorbed (finding F13).** `tasks.md` 12.1 asks this
    /// test to assert that "Home is still the section the app lands on". It never
    /// was: `ContentView` has shipped `@State private var section: AppSection = .browse`
    /// since M1, so the app lands on Browse and always has. Asserting Home here
    /// would require changing the landing section — a user-visible change no
    /// requirement in this delta asks for, and one `design.md` HD9 explicitly rules
    /// out ("No new `@State` selection"). What this change actually owes is
    /// asserted instead: Health is not what the app opens on, and this change moved
    /// nothing.
    @MainActor
    func testTheAppDoesNotLandOnHealth() throws {
        let app = launchHealthFixture()

        XCTAssertTrue(
            app.descendants(matching: .any)["sidebar-home"].waitForExistence(timeout: 15),
            "Home is no longer in the sidebar"
        )
        // The Health column is not on screen until Health is chosen.
        XCTAssertFalse(
            app.descendants(matching: .any)["health-score"].exists,
            "the app landed on the Health section"
        )
        XCTAssertTrue(app.descendants(matching: .any)["sidebar-browse"].exists)
    }

    @MainActor
    func testTheScoreNeverRendersWithoutItsUnknowns() throws {
        let app = launchHealthFixture()
        openHealth(in: app)

        let score = app.descendants(matching: .any)["health-score"]
        XCTAssertTrue(score.waitForExistence(timeout: 15), "the score never appeared")

        let figure = (score.value as? String) ?? score.label
        XCTAssertFalse(figure.isEmpty, "the score is present and empty")

        // Nothing on this fixture can answer security, Homebrew's own age or
        // doctor, so the caveat is not optional here — it is the whole point.
        let caveat = app.descendants(matching: .any)["health-score-caveat"]
        XCTAssertTrue(
            caveat.waitForExistence(timeout: 15),
            "a score with unanswered signals rendered as though it were complete"
        )
        let sentence = (caveat.value as? String) ?? caveat.label
        XCTAssertTrue(
            sentence.localizedCaseInsensitiveContains("unanswered"),
            "the caveat does not say what is missing, but: \(sentence)"
        )
    }

    /// A machine nothing could be measured on gets a sentence, not a verdict.
    @MainActor
    func testNothingAnsweredRendersASentenceRatherThanZeroOrOneHundred() throws {
        let app = launchHealthFixture(extraArguments: ["--ui-testing-m5-health-unscorable"])
        openHealth(in: app)

        let score = app.descendants(matching: .any)["health-score"]
        XCTAssertTrue(score.waitForExistence(timeout: 15), "the score never appeared")

        let figure = ((score.value as? String) ?? score.label)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertNotEqual(figure, "0", "a machine nothing was measured on scored 0")
        XCTAssertNotEqual(figure, "100", "a machine nothing was measured on scored 100")
        XCTAssertTrue(
            figure.localizedCaseInsensitiveContains("nothing could be scored"),
            "the unscorable state rendered as: \(figure)"
        )
    }

    @MainActor
    func testTheRunDoctorControlClaimsNoRepair() throws {
        let app = launchHealthFixture()
        openHealth(in: app)

        let control = app.descendants(matching: .any)["health-run-doctor"]
        XCTAssertTrue(control.waitForExistence(timeout: 15), "the run-doctor control never appeared")

        let words = ((control.value as? String) ?? control.label)
            + " " + (control.title)
        for claim in ["fix", "repair", "resolve"] {
            XCTAssertFalse(
                words.localizedCaseInsensitiveContains(claim),
                "the run-doctor control claims to \(claim): \(words)"
            )
        }

        // The row it belongs to carries Homebrew's own de-emphasis rather than
        // presenting the warnings as defects the user must clear.
        let deEmphasis = app.descendants(matching: .any)["health-doctor-de-emphasis"]
        XCTAssertTrue(deEmphasis.waitForExistence(timeout: 15), "the doctor row claims more than brew does")
        let framing = (deEmphasis.value as? String) ?? deEmphasis.label
        XCTAssertTrue(
            framing.localizedCaseInsensitiveContains("maintainers"),
            "the de-emphasis does not quote Homebrew, but: \(framing)"
        )
    }

    /// A signal nobody answered names its reason instead of reporting a zero.
    @MainActor
    func testAnUnansweredRowNamesItsReasonRatherThanReportingZero() throws {
        let app = launchHealthFixture()
        openHealth(in: app)

        let doctorRow = app.descendants(matching: .any)["health-unknown-doctor"]
        XCTAssertTrue(doctorRow.waitForExistence(timeout: 15), "the doctor row reported a number nobody measured")
        let reason = (doctorRow.value as? String) ?? doctorRow.label
        XCTAssertTrue(
            reason.localizedCaseInsensitiveContains("not been run"),
            "the doctor row does not say why it cannot answer, but: \(reason)"
        )
        // …and it did not render a count for a measurement nobody took.
        XCTAssertFalse(app.descendants(matching: .any)["health-summary-doctor"].exists)
    }

    // MARK: - 12.2 — the widened bulk bar

    @MainActor
    func testAMixedSelectionOffersPinAndUnpinWithTheirOwnCounts() throws {
        let app = launchHealthFixture()
        selectEverythingInstalled(in: app)

        // Two unpinned formulae, one pinned formula. Two verbs, two numbers,
        // neither guessing about the other's members (II13 sc5, II14 sc4).
        XCTAssertTrue(
            app.buttons["Pin 2"].waitForExistence(timeout: 15),
            "pin did not announce its own eligible set; buttons were \(Self.labels(in: app))"
        )
        XCTAssertTrue(app.buttons["Unpin 1"].exists, "unpin did not announce its own eligible set")
        XCTAssertTrue(app.buttons["Pin 2"].isEnabled)
        XCTAssertTrue(app.buttons["Unpin 1"].isEnabled)
    }

    @MainActor
    func testAnAllCaskSelectionLeavesPinAndUnpinUnavailableRatherThanInert() throws {
        let app = launchHealthFixture(extraArguments: ["--ui-testing-m5-health-casks"])
        selectEverythingInstalled(in: app)

        let pin = app.buttons["Pin 0"]
        XCTAssertTrue(
            pin.waitForExistence(timeout: 15),
            "the pin control never appeared; buttons were \(Self.labels(in: app))"
        )
        // Present, and **disabled** — a control that is enabled and does nothing
        // when pressed is the failure mode II13 sc5 forbids by name.
        XCTAssertFalse(pin.isEnabled, "pin is enabled over a selection it cannot act on")
        XCTAssertFalse(app.buttons["Unpin 0"].isEnabled, "unpin is enabled over a selection it cannot act on")
    }

    @MainActor
    func testTheBulkSnoozeControlImpliesNoDuration() throws { // swiftlint:disable:this function_body_length
        let app = launchHealthFixture()
        selectEverythingInstalled(in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["bulk-snooze"].waitForExistence(timeout: 15),
            "the bulk snooze control never appeared; buttons were \(Self.labels(in: app))"
        )
        // Read off the button's own title rather than an ancestor's: the
        // identifier is carried by a wrapper whose label is empty, and asserting
        // on an empty string is how a copy test passes while reading nothing.
        let words = try XCTUnwrap(
            Self.labels(in: app).first { $0.localizedCaseInsensitiveContains("snooze") },
            "no snooze button title among \(Self.labels(in: app))"
        )
        for duration in ["hour", "day", "week", "month", "minute", "later", "remind", "expire", "temporar"] {
            XCTAssertFalse(
                words.localizedCaseInsensitiveContains(duration),
                "the bulk snooze control implies a \(duration): \(words)"
            )
        }
        // It counts what it would write.
        XCTAssertTrue(
            words.rangeOfCharacter(from: .decimalDigits) != nil,
            "the snooze control announces no count: \(words)"
        )
    }

    // MARK: - Helpers

    @MainActor
    private func openHealth(in app: XCUIApplication) {
        let row = app.descendants(matching: .any)["sidebar-health"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Health is not in the sidebar")
        row.click()
    }

    /// Opens Installed and selects every listed package.
    ///
    /// Select-all rather than a sequence of modifier clicks: the bulk bar appears
    /// for any non-empty selection, and what these cases are about is the numbers
    /// on it rather than the gesture that produced them.
    @MainActor
    private func selectEverythingInstalled(in app: XCUIApplication) {
        let row = app.descendants(matching: .any)["sidebar-installed"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Installed is not in the sidebar")
        row.click()

        let list = app.descendants(matching: .any)["installed-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15), "the installed list never appeared")
        list.click()
        app.typeKey("a", modifierFlags: .command)
    }

    /// Read from `label`, not `title`.
    ///
    /// A SwiftUI `Button` publishes its text as the element's **label**; `title`
    /// is empty for every one of them, and reading it is how a copy assertion
    /// passes over an empty string while proving nothing.
    @MainActor
    private static func labels(in app: XCUIApplication) -> [String] {
        app.buttons.allElementsBoundByIndex.map(\.label)
    }

    @MainActor
    private func launchHealthFixture(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-m5-health")
        app.launchArguments.append(contentsOf: extraArguments)
        app.launch()
        return app
    }
}
