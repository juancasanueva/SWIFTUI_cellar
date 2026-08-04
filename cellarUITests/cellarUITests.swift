//
//  cellarUITests.swift
//  cellarUITests
//
//  Created by Juan Casanueva on 01/08/2026.
//

import XCTest

final class cellarUITests: XCTestCase {

    @MainActor
    func testCleanupRouteShowsStablePackageFirstOnDiskRows() throws {
        let app = launchDiskFixture()
        app.staticTexts["Cleanup"].click()

        XCTAssertTrue(app.outlines["disk-usage-list"].waitForExistence(timeout: 2))
        let wget = app.staticTexts["disk-package-formula-wget"]
        XCTAssertTrue(wget.exists)
        XCTAssertTrue(app.staticTexts["disk-package-cask-ghostty"].exists)
        XCTAssertTrue(wget.label.contains("20 kB on disk"))
        let disclosure = app.disclosureTriangles.firstMatch
        disclosure.click()
        XCTAssertEqual(disclosure.value as? Int, 1)
        XCTAssertTrue(app.staticTexts["1.25.0"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Last complete scan — revalidating"].exists)
    }

    @MainActor
    func testCleanupAbsenceWarningsAndReadOnlyBoundary() throws {
        let absent = launchDiskFixture("--ui-testing-m3-disk-usage-absent")
        absent.staticTexts["Cleanup"].click()
        XCTAssertTrue(absent.staticTexts["Homebrew is not installed"].waitForExistence(timeout: 2))
        absent.terminate()

        let warning = launchDiskFixture("--ui-testing-m3-disk-usage-warning")
        warning.staticTexts["Cleanup"].click()
        XCTAssertTrue(warning.staticTexts["Some storage could not be measured"].waitForExistence(timeout: 2))
        XCTAssertTrue(warning.staticTexts["disk-package-formula-wget"].exists)
        XCTAssertFalse(warning.buttons["Uninstall"].exists)
        XCTAssertFalse(warning.staticTexts["reclaimable"].exists)
    }

    @MainActor
    func testInstalledDoesNotGainASizeColumn() throws {
        let app = launchDiskFixture()
        app.staticTexts["Installed"].click()
        XCTAssertTrue(app.outlines["installed-list"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["On disk"].exists)
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testTapsNavigationOfficialSourcesAndAddConfirmation() throws {
        let app = launchTapFixture()

        app.staticTexts["Taps"].click()

        XCTAssertTrue(app.staticTexts["Homebrew Core"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Homebrew Cask"].exists)
        XCTAssertTrue(app.staticTexts["official-tap-explanation-homebrew-core"].exists)
        XCTAssertTrue(app.staticTexts["official-tap-explanation-homebrew-cask"].exists)

        let field = app.textFields["tap-add-field"]
        XCTAssertTrue(field.exists)
        field.click()
        field.typeText("acme/new-tools")
        app.buttons["tap-add-button"].click()

        let addCommand = app.staticTexts["confirmation-command"]
        XCTAssertTrue(addCommand.waitForExistence(timeout: 2))
        XCTAssertEqual(addCommand.value as? String, "brew tap acme/new-tools")
        XCTAssertTrue(((app.staticTexts["confirmation-warning"].value as? String) ?? "")
            .localizedCaseInsensitiveContains("third-party formulae and casks"))
        app.buttons["Cancel"].click()
    }

    @MainActor
    func testTapDetailFilteringInstalledHandoffAndForceDisclosure() throws {
        let app = launchTapFixture()
        app.staticTexts["Taps"].click()
        app.outlines["taps-list"].staticTexts["acme/tools"].click()

        let filter = app.textFields["tap-package-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 2))
        filter.click()
        filter.typeText("widget")
        XCTAssertTrue(app.staticTexts["widget"].exists)
        XCTAssertTrue(app.buttons["Show in Installed"].exists)
        XCTAssertTrue(app.staticTexts["Not in Cellar’s core/cask catalog."].exists)

        app.buttons["tap-force-untap-button"].click()
        let forceCommand = app.staticTexts["confirmation-command"]
        XCTAssertTrue(forceCommand.waitForExistence(timeout: 2))
        XCTAssertEqual(forceCommand.value as? String, "brew untap --force acme/tools")
        XCTAssertTrue(app.staticTexts["confirmation-affected-formula-widget"].exists)
        app.buttons["Cancel"].click()
    }

    @MainActor
    func testInvalidTapTargetAndEmptyErrorStatesStayDistinct() throws {
        let app = launchTapFixture()
        app.staticTexts["Taps"].click()

        let field = app.textFields["tap-add-field"]
        field.click()
        field.typeText("https://example.com/a.git")
        XCTAssertFalse(app.buttons["tap-add-button"].isEnabled)
        XCTAssertTrue(app.staticTexts["Enter a tap as user/repo."].exists)
        XCTAssertTrue(app.staticTexts["Third-party taps"].exists)
        XCTAssertFalse(app.staticTexts["Could not load taps"].exists)
    }

    @MainActor
    func testPlainUntapAndInstalledHandoff() throws {
        let app = launchTapFixture()
        app.staticTexts["Taps"].click()
        app.outlines["taps-list"].staticTexts["acme/tools"].click()

        app.buttons["Show in Installed"].click()
        let installedList = app.outlines["installed-list"]
        XCTAssertTrue(installedList.waitForExistence(timeout: 2))
        let widgetRow = installedList.descendants(matching: .outlineRow)
            .containing(.staticText, identifier: "installed-row-formula-widget")
            .firstMatch
        XCTAssertTrue(widgetRow.waitForExistence(timeout: 2))
        XCTAssertTrue(widgetRow.isSelected, "Show in Installed must select formula:widget")
        XCTAssertTrue(app.staticTexts["No package selected"].waitForNonExistence(timeout: 2))

        app.staticTexts["Taps"].click()
        app.outlines["taps-list"].staticTexts["acme/tools"].click()
        app.buttons["tap-untap-button"].click()
        XCTAssertFalse(app.sheets.firstMatch.exists)
        app.buttons["Show activity"].click()
        XCTAssertTrue(app.staticTexts["brew untap acme/tools"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testTapEmptyErrorAndAbsentStates() throws {
        let empty = launchTapFixture("--ui-testing-m3-taps-empty")
        empty.staticTexts["Taps"].click()
        XCTAssertTrue(empty.staticTexts["No third-party taps are installed."].waitForExistence(timeout: 2))
        empty.terminate()

        let error = launchTapFixture("--ui-testing-m3-taps-error")
        error.staticTexts["Taps"].click()
        XCTAssertTrue(error.staticTexts["Could not load taps"].waitForExistence(timeout: 2))
        error.terminate()

        let absent = launchTapFixture("--ui-testing-m3-taps-absent")
        absent.staticTexts["Taps"].click()
        XCTAssertTrue(absent.staticTexts["Homebrew is not installed"].waitForExistence(timeout: 2))
        XCTAssertFalse(absent.buttons["tap-add-button"].isEnabled)
    }

    @MainActor
    func testLargeTapFilteringAndKeyboardAdd() throws {
        let app = launchTapFixture("--ui-testing-m3-taps-large")
        app.staticTexts["Taps"].click()
        app.outlines["taps-list"].staticTexts["acme/large"].click()
        let filter = app.textFields["tap-package-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 2))
        filter.click()
        filter.typeText("needle-4999")
        XCTAssertTrue(app.staticTexts["needle-4999"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["needle-0"].exists)

        app.textFields["tap-add-field"].click()
        app.textFields["tap-add-field"].typeText("acme/keyboard")
        app.typeKey(.return, modifierFlags: .command)
        let command = app.staticTexts["confirmation-command"]
        XCTAssertTrue(command.waitForExistence(timeout: 2))
        XCTAssertEqual(command.value as? String, "brew tap acme/keyboard")
    }

    @MainActor
    private func launchTapFixture(_ mode: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-m3-taps")
        if let mode { app.launchArguments.append(mode) }
        app.launch()
        return app
    }

    @MainActor
    private func launchDiskFixture(_ mode: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-m3-disk-usage")
        if let mode { app.launchArguments.append(mode) }
        app.launch()
        return app
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
