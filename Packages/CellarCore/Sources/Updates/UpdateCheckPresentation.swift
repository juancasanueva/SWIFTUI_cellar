//
//  UpdateCheckPresentation.swift
//  Updates
//

import Foundation

/// The words an update surface may use about when Cellar last looked.
///
/// A value type over two dates, so the label is a pure function of its inputs
/// and nothing reads the clock behind the caller's back. `now` is injected for
/// exactly that reason: a relative phrase computed against `Date()` could only
/// ever be tested for its shape, and "the app never invents a date" is a claim
/// about the value.
public struct UpdateCheckPresentation: Sendable, Hashable {
    /// What a bundle that has never checked says.
    ///
    /// Words, deliberately, with no number in them. A placeholder date, a
    /// defaulted date and the Unix epoch all read as plausible sentences and all
    /// state something untrue.
    public static let neverChecked = "Never checked"

    public let lastCheck: Date?
    public let now: Date

    public init(lastCheck: Date?, now: Date) {
        self.lastCheck = lastCheck
        self.now = now
    }

    public var label: String {
        guard let lastCheck else { return Self.neverChecked }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last checked \(formatter.localizedString(for: lastCheck, relativeTo: now))"
    }
}
