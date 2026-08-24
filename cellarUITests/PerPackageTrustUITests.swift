//
//  PerPackageTrustUITests.swift
//  cellarUITests
//

import XCTest

/// The one claim about the per-package surface that only a running app can make:
/// that a count line and a section appear for exactly the report states that
/// have something to say, and that neither disturbs the shipped badge.
///
/// A unit test proves `TapProjection.grants(for:in:)` returns `nil` for an
/// unreported report, and a source scan proves both views read that projection.
/// Neither proves the view then draws what it read — and a "0 trusted
/// individually" beside an `Untrusted` badge would read as a verdict about a
/// package nobody measured.
///
/// Deterministic by construction: `--ui-testing-m9-per-package-trust` and its
/// two siblings swap the grant payload for a report in each state, over the same
/// three taps `--ui-testing-m7-tap-trust` already pins.
final class PerPackageTrustUITests: XCTestCase {

    @MainActor
    func testTheCountLineAndSectionAppearOnlyWhenReported() throws {
        // 1. A decoded report with an attributed grant: the count line appears
        //    on the row and in the header, and the orphan entry gets its section.
        let granted = launch(with: "--ui-testing-m9-per-package-trust")
        openTaps(in: granted)
        select(tap: "acme/untrusted", in: granted)

        let headerCount = element("tap-detail-grant-count", in: granted)
        XCTAssertTrue(
            headerCount.waitForExistence(timeout: 20),
            "a reported grant showed no count line in the detail header"
        )
        XCTAssertEqual(text(of: headerCount), "1 trusted individually")
        XCTAssertTrue(
            element("tap-row-grant-count", in: granted).exists,
            "a reported grant showed no count line on the tap row"
        )
        let orphanSentence = element("tap-grant-section-sentence", in: granted)
        XCTAssertTrue(orphanSentence.waitForExistence(timeout: 20), "the orphan section never appeared")
        XCTAssertEqual(
            text(of: orphanSentence),
            "Homebrew still records these grants. Cellar shows them; it does not remove them."
        )
        assertBadgeIsUnchanged(in: granted)

        // A tap with no attributed grant carries no count line at all — the same
        // launch, so this is the absence beside a present one.
        select(tap: "acme/trusted", in: granted)
        XCTAssertTrue(
            element("tap-untrust-button", in: granted).waitForExistence(timeout: 20),
            "the trusted tap's detail pane never appeared, so the absence below proves nothing"
        )
        XCTAssertFalse(
            element("tap-detail-grant-count", in: granted).exists,
            "a tap with no attributed grant carried a count line"
        )
        granted.terminate()

        // 2. brew answered, and recorded nothing.
        let empty = launch(with: "--ui-testing-m9-per-package-trust-empty")
        openTaps(in: empty)
        let emptySentence = element("tap-grant-section-sentence", in: empty)
        XCTAssertTrue(emptySentence.waitForExistence(timeout: 20), "a reported-empty report rendered nothing")
        XCTAssertEqual(text(of: emptySentence), "Homebrew records no packages trusted individually.")
        select(tap: "acme/untrusted", in: empty)
        XCTAssertTrue(
            element("tap-untap-button", in: empty).waitForExistence(timeout: 20),
            "the detail pane never appeared, so the absence below proves nothing"
        )
        XCTAssertFalse(
            element("tap-detail-grant-count", in: empty).exists,
            "a reported-empty report rendered a count line"
        )
        assertBadgeIsUnchanged(in: empty)
        empty.terminate()

        // 3. brew did not answer at all. A different sentence, and still no count.
        let unreported = launch(with: "--ui-testing-m9-per-package-trust-unreported")
        openTaps(in: unreported)
        let unreportedSentence = element("tap-grant-section-sentence", in: unreported)
        XCTAssertTrue(unreportedSentence.waitForExistence(timeout: 20), "an unreported report rendered nothing")
        XCTAssertEqual(text(of: unreportedSentence), "This Homebrew does not report per-package trust.")
        select(tap: "acme/untrusted", in: unreported)
        XCTAssertTrue(
            element("tap-untap-button", in: unreported).waitForExistence(timeout: 20),
            "the detail pane never appeared, so the absence below proves nothing"
        )
        XCTAssertFalse(
            element("tap-detail-grant-count", in: unreported).exists,
            "an unreported report rendered a count line"
        )
        assertBadgeIsUnchanged(in: unreported)
        unreported.terminate()
    }

    // MARK: - Arrangement

    @MainActor
    private func launch(with fixture: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-m3-taps", "--ui-testing-m7-tap-trust", fixture]
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

    /// The badge is byte-unchanged in every report state — the count line is an
    /// added component beside it, never a qualifier on it (TM12.7).
    @MainActor
    private func assertBadgeIsUnchanged(in app: XCUIApplication) {
        select(tap: "acme/untrusted", in: app)
        let badge = element("tap-detail-trust-badge", in: app)
        XCTAssertTrue(badge.waitForExistence(timeout: 20), "the untrusted tap lost its badge")
        XCTAssertEqual(text(of: badge), "Untrusted", "the badge text is not the pinned copy")
    }

    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Inside a `List`, a row's text does not surface as an element `label` at
    /// all, so a label-only read reaches nothing.
    @MainActor
    private func text(of element: XCUIElement) -> String {
        let value = (element.value as? String) ?? ""
        return value.isEmpty ? element.label : value
    }
}
