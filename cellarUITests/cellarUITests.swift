//
//  cellarUITests.swift
//  cellarUITests
//
//  Created by Juan Casanueva on 01/08/2026.
//

import XCTest

final class cellarUITests: XCTestCase {

    @MainActor
    func testCleanupCO7PreviewFirstScopesAndStorageRows() throws {
        let app = launchCleanupFixture("--ui-testing-m3-cleanup-content")
        openCleanup(in: app)

        XCTAssertTrue(app.outlines["disk-usage-list"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["disk-package-formula-wget"].exists)
        XCTAssertTrue(app.buttons["disk-package-cask-ghostty"].exists)

        for scope in ["global", "package-formula-wget", "full", "autoremove"] {
            let preview = app.buttons["cleanup-preview-\(scope)"]
            XCTAssertTrue(preview.exists, "Missing preview-first action for \(scope)")
            XCTAssertFalse(app.buttons["cleanup-action-\(scope)"].exists)
            preview.click()
            XCTAssertTrue(app.buttons["cleanup-action-\(scope)"].waitForExistence(timeout: 2))
        }
    }

    @MainActor
    func testCleanupCO7StateMatrixIsDeterministicAndHonest() throws {
        let empty = launchCleanupFixture("--ui-testing-m3-cleanup-empty")
        openCleanup(in: empty)
        empty.buttons["cleanup-preview-global"].click()
        XCTAssertTrue(empty.staticTexts["cleanup-state-empty"].waitForExistence(timeout: 2))
        XCTAssertFalse(empty.buttons["cleanup-action-global"].exists)
        empty.terminate()

        let unknown = launchCleanupFixture("--ui-testing-m3-cleanup-unknown-total")
        openCleanup(in: unknown)
        unknown.buttons["cleanup-preview-global"].click()
        XCTAssertTrue(unknown.staticTexts["cleanup-state-content"].waitForExistence(timeout: 2))
        XCTAssertTrue(text(of: unknown.staticTexts["cleanup-provenance"]).contains("did not report"))
        unknown.terminate()

        let partial = launchCleanupFixture("--ui-testing-m3-cleanup-partial")
        openCleanup(in: partial)
        partial.buttons["cleanup-preview-global"].click()
        XCTAssertTrue(partial.staticTexts["cleanup-state-partial"].waitForExistence(timeout: 2))
        XCTAssertFalse(partial.buttons["cleanup-action-global"].exists)
        partial.terminate()

        let error = launchCleanupFixture("--ui-testing-m3-cleanup-error")
        openCleanup(in: error)
        error.buttons["cleanup-preview-global"].click()
        XCTAssertTrue(error.staticTexts["cleanup-state-error"].waitForExistence(timeout: 2))
        XCTAssertTrue(text(of: error.staticTexts["cleanup-diagnostics"]).contains("cleanup locked"))
        error.terminate()

        let cancelled = launchCleanupFixture("--ui-testing-m3-cleanup-cancelled")
        openCleanup(in: cancelled)
        cancelled.buttons["cleanup-preview-global"].click()
        XCTAssertTrue(cancelled.staticTexts["cleanup-state-loading"].waitForExistence(timeout: 2))
        cancelled.buttons["cleanup-cancel"].click()
        XCTAssertTrue(cancelled.staticTexts["cleanup-state-cancelled"].waitForExistence(timeout: 2))
        cancelled.terminate()

        let absent = launchCleanupFixture("--ui-testing-m3-cleanup-brew-absence")
        openCleanup(in: absent)
        XCTAssertTrue(absent.staticTexts["cleanup-state-unavailable"].waitForExistence(timeout: 2))
        XCTAssertFalse(absent.buttons["cleanup-preview-global"].isEnabled)
    }

    @MainActor
    func testCleanupCO7FullConfirmationDisclosesCommandProvenanceAndWarning() throws {
        let app = launchCleanupFixture("--ui-testing-m3-cleanup-confirmation")
        openCleanup(in: app)
        app.buttons["cleanup-preview-full"].click()
        app.buttons["cleanup-action-full"].click()

        let confirmation = app.descendants(matching: .any)["cleanup-confirmation"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertEqual(confirmation.staticTexts["cleanup-command"].value as? String, "brew cleanup --prune=all")
        XCTAssertTrue(text(of: confirmation.staticTexts["cleanup-provenance"]).contains("Homebrew reported"))
        XCTAssertTrue(text(of: confirmation.staticTexts["cleanup-full-warning"]).contains("regardless of age"))
        XCTAssertTrue(text(of: confirmation.staticTexts["cleanup-full-warning"]).contains("installed packages"))
        XCTAssertTrue(text(of: confirmation.staticTexts["cleanup-full-warning"]).contains("not cache-only"))
        app.buttons["Cancel"].click()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 2))
    }

    @MainActor
    func testCleanupCO7AutoremoveDisclosesExactOrphans() throws {
        let app = launchCleanupFixture("--ui-testing-m3-cleanup-confirmation")
        openCleanup(in: app)
        app.buttons["cleanup-preview-autoremove"].click()
        app.buttons["cleanup-action-autoremove"].click()

        let confirmation = app.descendants(matching: .any)["cleanup-confirmation"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(text(of: confirmation.staticTexts["cleanup-orphan-count"]).contains("1 orphan"))
        XCTAssertEqual(text(of: confirmation.staticTexts["cleanup-orphan-wget"]), "wget")
        XCTAssertTrue(text(of: confirmation.staticTexts["cleanup-orphan-allocation"]).contains("currently on disk"))
        XCTAssertFalse(text(of: confirmation.staticTexts["cleanup-orphan-allocation"]).contains("reclaimable"))
    }

    @MainActor
    func testCleanupCO7DenialRefreshRequiresReconfirmation() throws {
        let app = launchCleanupFixture("--ui-testing-m3-cleanup-denial-refresh")
        openCleanup(in: app)
        app.buttons["cleanup-preview-global"].click()
        app.buttons["cleanup-action-global"].click()
        app.buttons["Confirm Cleanup"].click()

        XCTAssertTrue(app.staticTexts["cleanup-state-stale"].waitForExistence(timeout: 2))
        XCTAssertTrue(text(of: app.staticTexts["cleanup-state-stale"]).contains("changed"))
        XCTAssertFalse(app.buttons["cleanup-action-global"].exists)
        XCTAssertTrue(app.buttons["cleanup-preview-global"].exists)
    }

    @MainActor
    func testCleanupCO7TerminalOutcomeRefreshesStorage() throws {
        let app = launchCleanupFixture("--ui-testing-m3-cleanup-post-terminal-refresh")
        openCleanup(in: app)
        XCTAssertFalse(app.staticTexts["cleanup-post-terminal-refresh"].exists)
        app.buttons["cleanup-preview-global"].click()
        app.buttons["cleanup-action-global"].click()
        app.buttons["Confirm Cleanup"].click()

        XCTAssertTrue(app.staticTexts["cleanup-post-terminal-refresh"].waitForExistence(timeout: 3))
        XCTAssertTrue(text(of: app.staticTexts["cleanup-post-terminal-refresh"]).contains("revalidating"))
    }

    @MainActor
    func testCleanupRouteShowsStablePackageFirstOnDiskRows() throws {
        let app = launchDiskFixture()
        app.staticTexts["Cleanup"].click()

        XCTAssertTrue(app.outlines["disk-usage-list"].waitForExistence(timeout: 2))
        // The rows are hand-built disclosures (buttons), not DisclosureGroups:
        // the native control merges its label into one element, which made the
        // per-package cleanup pills unreachable — see CleanupRow.
        let wget = app.buttons["disk-package-formula-wget"]
        XCTAssertTrue(wget.exists)
        XCTAssertTrue(app.buttons["disk-package-cask-ghostty"].exists)
        XCTAssertTrue(wget.label.contains("20 kB on disk"))
        wget.click()
        XCTAssertEqual(wget.value as? String, "Expanded")
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
        XCTAssertTrue(warning.buttons["disk-package-formula-wget"].exists)
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

        // TM4: an official row opens the read-only pane, never the third-party
        // detail — no untap of any kind, whatever the inventory holds.
        app.outlines["taps-list"].staticTexts["Homebrew Core"].click()
        XCTAssertTrue(app.descendants(matching: .any)["official-tap-detail"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Official source"].exists)
        XCTAssertFalse(app.buttons["tap-untap-button"].exists)
        XCTAssertFalse(app.buttons["tap-force-untap-button"].exists)
        XCTAssertFalse(app.buttons["tap-untrust-button"].exists)
        XCTAssertFalse(app.buttons["tap-trust-button"].exists)

        let field = app.textFields["tap-add-field"]
        XCTAssertTrue(field.exists)
        field.click()
        field.typeText("acme/new-tools")
        app.buttons["tap-add-button"].click()

        let addCommand = app.staticTexts["confirmation-command"]
        XCTAssertTrue(addCommand.waitForExistence(timeout: 2))
        XCTAssertEqual(addCommand.value as? String, "brew tap acme/new-tools")
        // The disclosure says what `brew tap` does and does not do (D2): the
        // clone happens now, the tap's formulae and casks load only once trusted.
        let addWarning = (app.staticTexts["confirmation-warning"].value as? String) ?? ""
        XCTAssertTrue(addWarning.contains("clones a third-party repository"), addWarning)
        XCTAssertTrue(addWarning.contains("until you trust it"), addWarning)
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
        XCTAssertTrue(app.staticTexts["Not installed."].exists)

        app.buttons["tap-force-untap-button"].click()
        // A force untap is two commands, disclosed in the order they run: the
        // removal first, the trust revocation only once brew has accepted it.
        let forceCommands = app.staticTexts.matching(identifier: "confirmation-command")
        XCTAssertTrue(forceCommands.firstMatch.waitForExistence(timeout: 2))
        XCTAssertEqual(forceCommands.count, 2)
        XCTAssertEqual(forceCommands.element(boundBy: 0).value as? String, "brew untap --force acme/tools")
        XCTAssertEqual(forceCommands.element(boundBy: 1).value as? String, "brew untrust acme/tools")
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
            .containing(.any, identifier: "installed-row-formula-widget")
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
    private func launchCleanupFixture(_ mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-m3-cleanup", mode]
        app.launch()
        return app
    }

    @MainActor
    private func openCleanup(in app: XCUIApplication) {
        app.staticTexts["Cleanup"].click()
        XCTAssertTrue(app.staticTexts["Cleanup"].waitForExistence(timeout: 2))
    }

    @MainActor
    private func text(of element: XCUIElement) -> String {
        (element.value as? String) ?? element.label
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
