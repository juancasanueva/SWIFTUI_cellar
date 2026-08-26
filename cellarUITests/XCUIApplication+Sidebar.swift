import XCTest

extension XCUIApplication {
    /// Opens a sidebar section by its `sidebar-<section>` identifier.
    ///
    /// The sidebar rows live in a `ScrollView`, and at the default window size
    /// the Insights group sits below the fold. A clipped row still reports
    /// `isHittable`, and a click on it lands outside the viewport and selects
    /// nothing, so the row is scrolled into the scroll view's visible frame
    /// first; the click then never depends on a saved window frame.
    @MainActor
    @discardableResult
    func openSidebarSection(
        _ identifier: String,
        timeout: TimeInterval = 15,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let row = descendants(matching: .any)[identifier]
        XCTAssertTrue(
            row.waitForExistence(timeout: timeout),
            "\(identifier) is not in the sidebar", file: file, line: line
        )
        let sidebar = scrollViews.containing(.any, identifier: identifier).firstMatch
        if sidebar.exists {
            scroll(row, intoViewOf: sidebar)
            XCTAssertTrue(
                sidebar.frame.contains(row.frame),
                "\(identifier) never scrolled into view: row \(row.frame) in \(sidebar.frame)",
                file: file, line: line
            )
        }
        row.click()
        return row
    }

    /// Scrolls a bounded number of wheel ticks until the row is inside the
    /// viewport: toward the row first, then the other way in case the wheel
    /// sign points the other direction on this host.
    @MainActor
    private func scroll(_ row: XCUIElement, intoViewOf sidebar: XCUIElement) {
        func isVisible() -> Bool { sidebar.frame.contains(row.frame) }
        guard !isVisible() else { return }
        let towardRow: CGFloat = row.frame.midY > sidebar.frame.midY ? -40 : 40
        for delta in [towardRow, -towardRow] {
            for _ in 0..<12 where !isVisible() {
                sidebar.scroll(byDeltaX: 0, deltaY: delta)
            }
            if isVisible() { return }
        }
    }
}
