//
//  NpmSourceToggleUITests.swift
//  cellarUITests
//

import XCTest

/// The one claim about the npm source only a running app can make: the switch in
/// Settings adds a whole surface and takes it away again, with no relaunch.
///
/// Everything else in this capability is a value and is proven in `swift test`
/// — detection, the environment, the decoders, the projections and every
/// sentence. What no unit test reaches is the wiring *between* them: the
/// preference reaching the detection store, the store's published transition
/// reaching the refresh coordinator, the coordinator's listing reaching the one
/// merged inventory, and the inventory reaching a chip and a pill on screen.
/// That chain is four hops through three files, and a break anywhere in it looks
/// exactly like "nothing happened" (`npm-source`: turning it on MUST start
/// detection without a relaunch; `installed-inventory`: the Source filter and
/// the npm tag).
///
/// Deliberately **not** fixture-driven. Every other UI suite here swaps the
/// launcher for scripted output, which is right when the claim is about layout.
/// This claim is about a real `npm` being found and read, so the test skips on a
/// machine that has none rather than proving the chain against a fake that could
/// not fail.
///
/// It leaves the preference **off**, which is where it found it and where every
/// default build has it.
final class NpmSourceToggleUITests: XCTestCase {
    private static let npmPath = "/opt/homebrew/bin/npm"

    @MainActor
    func testTogglingTheNpmSourceAddsAndRemovesTheChipAndTheTag() throws {
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: Self.npmPath),
            "this machine has no npm at \(Self.npmPath)"
        )

        let app = XCUIApplication()
        app.launch()
        defer { setNpmSource(in: app, on: false) }

        // Start from a known answer rather than from whatever a previous run
        // left in the defaults domain.
        setNpmSource(in: app, on: false)
        app.openSidebarSection("sidebar-installed")
        XCTAssertFalse(
            npmChip(in: app).waitForExistence(timeout: 5),
            "the npm Source chip is on screen with the source switched off"
        )
        XCTAssertFalse(npmTag(in: app).exists, "an NPM tag is on screen with the source switched off")

        // On: detection runs, the listing lands, and both surfaces appear.
        //
        // Detection is asserted first and separately. It is the first hop of the
        // chain, and a chip that never appears because npm was never found is a
        // different defect from a chip that never appears because the rows did
        // not reach the list — so the two are told apart here rather than in a
        // debugger.
        setNpmSource(in: app, on: true)
        XCTAssertTrue(
            app.descendants(matching: .any)["npm-detected-path"].waitForExistence(timeout: 30),
            "Settings reports no detected npm, so nothing downstream of detection can appear"
        )

        app.openSidebarSection("sidebar-installed")
        XCTAssertTrue(
            npmChip(in: app).waitForExistence(timeout: 30),
            "the npm Source chip never appeared after the switch was turned on"
        )
        npmChip(in: app).click()
        XCTAssertTrue(
            npmTag(in: app).waitForExistence(timeout: 30),
            "no row carries the NPM tag, so no npm global reached the one inventory"
        )

        // Off again: the surface goes away as completely as it arrived.
        setNpmSource(in: app, on: false)
        app.openSidebarSection("sidebar-installed")
        XCTAssertTrue(
            waitForDisappearance(of: npmChip(in: app)),
            "the npm Source chip survived the switch being turned off"
        )
        XCTAssertTrue(
            waitForDisappearance(of: npmTag(in: app)),
            "an NPM-tagged row survived the switch being turned off"
        )
    }

    // MARK: - Support

    /// The Source chip, which is **absent** rather than disabled while npm is
    /// unavailable — so its existence is the assertion, not its enablement.
    @MainActor
    private func npmChip(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["installed-source-npm"]
    }

    /// The row tag.
    ///
    /// Queried by the identifier `KindTag` derives from the tag itself. The
    /// accessibility *label* would be the more meaningful thing to assert, but
    /// macOS does not surface a plain `Text`'s label through
    /// `XCUIApplication.staticTexts` here — every one of them comes back empty —
    /// so the identifier is what makes this claim assertable at all.
    @MainActor
    private func npmTag(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["kind-tag-npm"]
    }

    /// Drives the Settings switch to a known position, and no further.
    @MainActor
    private func setNpmSource(
        in app: XCUIApplication,
        on wanted: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        app.openSidebarSection("sidebar-settings")
        let toggle = app.descendants(matching: .any)["npm-source-toggle"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 15),
            "the npm switch is not in Settings", file: file, line: line
        )
        guard isOn(toggle) != wanted else { return }
        toggle.click()
        // The switch reports its new position before anything downstream of it
        // has run, which is exactly the point: nothing here waits for a
        // relaunch, because there is not supposed to be one.
        XCTAssertTrue(
            waitFor(toggle, toBe: wanted),
            "the npm switch did not move to \(wanted)", file: file, line: line
        )
    }

    @MainActor
    private func isOn(_ toggle: XCUIElement) -> Bool {
        String(describing: toggle.value ?? "0") == "1"
    }

    @MainActor
    private func waitFor(_ toggle: XCUIElement, toBe wanted: Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isOn(toggle) == wanted { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return isOn(toggle) == wanted
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists == false { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.exists == false
    }
}
