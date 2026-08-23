//
//  UpdateCheckPresentationTests.swift
//  UpdatesTests
//

import Foundation
import Testing

@testable import Updates

/// What the update surfaces are allowed to say about when Cellar last looked.
///
/// Deterministic because `now` is injected: a label that read the clock could
/// only be tested for its shape, and "no fabricated date" is a claim about the
/// value, not the shape.
@Suite("Update check presentation")
struct UpdateCheckPresentationTests {
    static let now = Date(timeIntervalSince1970: 1_787_000_000)

    // MARK: - T6 — a never-checked app says so

    /// The never-checked wording carries **no digits at all**.
    ///
    /// That is the assertion that actually forbids the failure mode: a
    /// fabricated date, a placeholder, or an epoch would all still read as a
    /// sentence, and only "there is no number in it" rules out all three at once
    /// without enumerating them.
    @Test("A never-checked app says so, with no date in the text")
    func aNeverCheckedAppSaysSo() {
        let presentation = UpdateCheckPresentation(lastCheck: nil, now: Self.now)

        let carriesADigit = presentation.label.rangeOfCharacter(from: .decimalDigits) != nil

        #expect(presentation.label == "Never checked")
        #expect(carriesADigit == false)
    }

    // MARK: - T6 — a checked app reports the date it checked

    /// A recorded date produces a "Last checked …" label, and different dates
    /// produce different labels.
    ///
    /// Wording beyond the prefix is the formatter's and the user's locale's, so
    /// it is not pinned. What is pinned is that the label is *derived from the
    /// date*: three offsets, three distinct labels. A hardcoded "Last checked
    /// recently" would satisfy the prefix and fail this.
    @Test("A checked app reports its check, and the label follows the date")
    func aCheckedAppReportsItsCheck() {
        let offsets: [TimeInterval] = [-3600, -3 * 86_400, -21 * 86_400]
        let labels = offsets.map { offset in
            UpdateCheckPresentation(lastCheck: Self.now.addingTimeInterval(offset), now: Self.now).label
        }

        for label in labels {
            #expect(label.hasPrefix("Last checked "))
            #expect(label.count > "Last checked ".count)
        }
        #expect(Set(labels).count == 3)
    }

    /// The same inputs produce the same label, every time.
    ///
    /// The whole reason `now` is a parameter rather than `Date()`.
    @Test("The label is a pure function of the two dates")
    func theLabelIsAPureFunctionOfTheTwoDates() {
        let checked = Self.now.addingTimeInterval(-7200)

        let first = UpdateCheckPresentation(lastCheck: checked, now: Self.now)
        let second = UpdateCheckPresentation(lastCheck: checked, now: Self.now)

        #expect(first == second)
        #expect(first.label == second.label)
    }

    // MARK: - T6 — the label follows the updater's recorded date

    /// Absent to present changes the wording.
    ///
    /// This is the surface's honesty requirement in one assertion: an app that
    /// has just checked must stop saying it never has.
    @Test("The label changes when the recorded date arrives")
    func theLabelChangesWhenTheRecordedDateArrives() {
        let before = UpdateCheckPresentation(lastCheck: nil, now: Self.now)
        let after = UpdateCheckPresentation(lastCheck: Self.now.addingTimeInterval(-60), now: Self.now)

        #expect(before.label == "Never checked")
        #expect(after.label != before.label)
        #expect(after.label.hasPrefix("Last checked "))
    }
}
