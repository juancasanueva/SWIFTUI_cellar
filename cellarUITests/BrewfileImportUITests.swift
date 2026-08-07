//
//  BrewfileImportUITests.swift
//  cellarUITests
//

import XCTest

/// The two claims about Brewfile import that only a running app can make.
///
/// The first is that a file full of things Cellar does not install is still an
/// importable file: the skips are counted, each is named, and the import button
/// stays enabled. A unit test proves the store's `canImport` ignores the skip
/// count; only a launch proves the button the user actually presses agrees.
///
/// The second is the DD1 defect, proven at the surface a user reads. An erased
/// tap+install batch used to confirm with "This removes installed software." —
/// the wrong warning, on the one screen where the warning is the whole point.
/// This asserts the tapTrust sentence is there **and** that the package-removal
/// sentence is not, because a test that only checked for the right text would
/// have passed on a screen showing both.
///
/// Deterministic by construction: `--ui-testing-m5-brewfile` swaps the
/// `NSOpenPanel` seam for a stub that returns a Brewfile this launch wrote to a
/// temporary file, so no panel is ever driven and no file is ever picked by
/// coordinates.
final class BrewfileImportUITests: XCTestCase {

    @MainActor
    func testASkipHeavyBrewfileStillImports() throws {
        let app = launchBrewfileFixture()
        openImportSheet(in: app)

        // Counted, and named. "9 entries skipped" with no reason would be a
        // number the user cannot act on.
        let headline = app.descendants(matching: .any)
            .matching(identifier: "brewfile-skip-headline-unsupportedEntryKind")
            .firstMatch
        XCTAssertTrue(
            headline.waitForExistence(timeout: 15),
            "the unsupported-kind skips were never counted on screen"
        )
        XCTAssertTrue(
            text(of: headline).contains("3"),
            "the skip count is not shown: \(text(of: headline))"
        )

        let reason = app.descendants(matching: .any)
            .matching(identifier: "brewfile-skip-reason-unsupportedEntryKind")
            .firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 15), "the skip reason was not named")
        XCTAssertTrue(
            text(of: reason).contains("formulae, casks and taps"),
            "the reason does not say why: \(text(of: reason))"
        )

        let option = app.descendants(matching: .any)
            .matching(identifier: "brewfile-skip-reason-unsupportedOption")
            .firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 15), "the option skip was not named")

        // The whole point: skips do not gate the import.
        // Queried through `descendants` rather than `buttons`: inside a sheet's
        // footer the control does not always surface under the button trait, and
        // a `buttons` query that reaches nothing asserts nothing.
        let importButton = app.descendants(matching: .any)["brewfile-import-button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        XCTAssertTrue(importButton.isEnabled, "counted skips disabled the import button")
    }

    @MainActor
    func testATapCarryingImportShowsTheTrustWarningAndNotTheRemovalOne() throws {
        let app = launchBrewfileFixture()
        openImportSheet(in: app)

        // Queried through `descendants` rather than `buttons`: inside a sheet's
        // footer the control does not always surface under the button trait, and
        // a `buttons` query that reaches nothing asserts nothing.
        let importButton = app.descendants(matching: .any)["brewfile-import-button"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        importButton.click()

        let warning = app.descendants(matching: .any)
            .matching(identifier: "confirmation-warning")
            .firstMatch
        XCTAssertTrue(
            warning.waitForExistence(timeout: 15),
            "a tap-carrying import raised no confirmation at all"
        )

        let sentence = text(of: warning)
        XCTAssertTrue(
            sentence.contains("trusts third-party formulae and casks"),
            "the confirmation did not present the tap-trust disclosure: \(sentence)"
        )
        XCTAssertFalse(
            sentence.contains("This removes installed software."),
            "the erased batch presented the package-removal disclosure — DD1 has regressed"
        )
        XCTAssertTrue(
            sentence.contains("gentleman-programming/tap"),
            "the disclosure did not name the tap: \(sentence)"
        )
    }

    // MARK: - Arrangement

    @MainActor
    private func launchBrewfileFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-m3-taps", "--ui-testing-m5-brewfile"]
        app.launch()
        return app
    }

    @MainActor
    private func openImportSheet(in app: XCUIApplication) {
        let taps = app.descendants(matching: .any)["sidebar-taps"]
        XCTAssertTrue(taps.waitForExistence(timeout: 20), "the Taps section never appeared")
        taps.click()

        let affordance = app.descendants(matching: .any)["brewfile-import-affordance"]
        XCTAssertTrue(
            affordance.waitForExistence(timeout: 20),
            "the import affordance is not in the Taps toolbar"
        )
        affordance.click()

        let sheet = app.descendants(matching: .any)["brewfile-import-sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 20), "the import sheet never appeared")
    }

    /// Inside a `List`, a row's text does not surface as an element `label` at
    /// all, so a label-only read reaches nothing — which is exactly how an
    /// earlier sibling test passed while proving nothing.
    @MainActor
    private func text(of element: XCUIElement) -> String {
        let value = (element.value as? String) ?? ""
        return value.isEmpty ? element.label : value
    }
}
