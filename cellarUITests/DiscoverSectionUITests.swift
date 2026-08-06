//
//  DiscoverSectionUITests.swift
//  cellarUITests
//

import XCTest

/// The checks only a running app can make about Discover.
///
/// Two of them matter enough to pay for a launch. The first is placement: D4 put
/// Discover *between* Home and Browse, and a sidebar order is not observable
/// from a unit test. The second is the first-run state — D5 calls it a designed,
/// explained state rather than a spinner or a hidden section, and "the section
/// is present and says something true" is precisely a claim about pixels.
///
/// Deterministic by construction: `--ui-testing-m5-discover` points the catalog
/// at an empty temporary directory, so the app really does start with no
/// snapshot, no roster and no arrivals log — a genuine first run, on a machine
/// whose real catalog directory is already full.
final class DiscoverSectionUITests: XCTestCase {
    @MainActor
    func testDiscoverSitsBetweenHomeAndBrowseInTheSidebar() throws {
        let app = launchDiscoverFixture()

        // Queried by identifier, not by text: the sidebar row and the navigation
        // title carry the same words, and matching on those matches two
        // elements and can assert on neither.
        let home = app.descendants(matching: .any)["sidebar-home"]
        let discover = app.descendants(matching: .any)["sidebar-discover"]
        let browse = app.descendants(matching: .any)["sidebar-browse"]

        XCTAssertTrue(discover.waitForExistence(timeout: 15), "Discover is not in the sidebar")
        XCTAssertTrue(home.exists)
        XCTAssertTrue(browse.exists)

        // Compared by vertical position, which is what "between" actually means
        // on screen — an enum ordering is already asserted in cellarTests.
        XCTAssertLessThan(
            home.frame.minY, discover.frame.minY,
            "Discover is above Home"
        )
        XCTAssertLessThan(
            discover.frame.minY, browse.frame.minY,
            "Discover is below Browse"
        )
    }

    @MainActor
    func testDiscoverShowsEverySectionOnAFirstRun() throws {
        let app = launchDiscoverFixture()
        openDiscover(in: app)

        // All three sections are present. None of them is hidden when it has
        // nothing to show — that is the whole of D5.
        for header in ["New to you", "Most installed formulae", "Most installed casks"] {
            XCTAssertTrue(
                app.staticTexts[header].waitForExistence(timeout: 15),
                "the \(header) section never appeared"
            )
        }
    }

    @MainActor
    func testAFirstRunExplainsItselfRatherThanSpinningOrBlanking() throws {
        let app = launchDiscoverFixture()
        openDiscover(in: app)

        XCTAssertTrue(app.staticTexts["New to you"].waitForExistence(timeout: 15))

        // Queried by identifier and read from `value`. Inside a `List` the
        // note's text does not surface as an element `label` at all, so a
        // label-matching predicate reaches nothing — which is exactly how an
        // earlier draft of this test passed while proving nothing.
        let note = app.descendants(matching: .any)
            .matching(identifier: "discover-section-note")
            .firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 15), "the arrivals section explained nothing")

        let sentence = (note.value as? String) ?? note.label
        XCTAssertFalse(sentence.isEmpty, "the arrivals note is present but empty")

        // A launch against an empty catalog directory passes through two
        // explained states — awaiting the catalog, then, once a sync lands, the
        // seeded "nothing yet" state. Both sentences are `CellarCore`'s, and the
        // point of D5 is that the section is **never** blank in either: whichever
        // one is on screen, it explains itself. Which of the two shows depends on
        // whether a network sync completed, so accepting either is what keeps
        // this deterministic instead of quietly network-dependent.
        XCTAssertTrue(
            Self.explanations.contains { sentence.localizedCaseInsensitiveContains($0) },
            "the arrivals section showed neither of its explanations, but: \(sentence)"
        )

        // ...and it is an explanation rather than a pending state.
        XCTAssertEqual(
            app.progressIndicators.count, 0,
            "Discover showed a spinner where a designed, explained state belongs"
        )

        // The sentence on screen claims nothing the catalog cannot support. The
        // exhaustive form of this rule is the source scan in `cellarTests`; this
        // is the same rule checked against rendered pixels.
        for claim in [
            "newly released", "recently added", "new on Homebrew", "release date", "published"
        ] {
            XCTAssertFalse(
                sentence.localizedCaseInsensitiveContains(claim),
                "the arrivals note claims \(claim)"
            )
        }
    }

    /// The two sentences `DiscoverCopy` supplies for a machine that has not yet
    /// recorded an arrival, matched as substrings so wrapping cannot break them.
    private static let explanations = [
        "from this sync onward",
        "Waiting for the catalog"
    ]

    @MainActor
    private func openDiscover(in app: XCUIApplication) {
        let row = app.descendants(matching: .any)["sidebar-discover"]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Discover is not in the sidebar")
        row.click()
    }

    @MainActor
    private func launchDiscoverFixture() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing-m5-discover")
        app.launch()
        return app
    }
}
