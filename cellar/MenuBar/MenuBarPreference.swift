//
//  MenuBarPreference.swift
//  cellar
//

import Foundation
import Observation

/// Whether Cellar puts a status item in the menu bar.
///
/// A **missing key reads `false`**: the status item is opt-in, so with nothing
/// stored the app behaves exactly as it does without this capability — no scene
/// inserted, and no other observable difference.
///
/// An `@Observable` class rather than the `AutomaticUpdateChecks` value shape,
/// and the difference is load-bearing. `MenuBarExtra(isInserted:)` needs a
/// `Binding<Bool>`, and the scene has to re-evaluate when the Settings toggle
/// moves; a plain `struct` over `UserDefaults` has no observation, so flipping
/// the switch would not insert or remove the status item until the next launch.
///
/// The defaults domain is a parameter for the reason
/// `AutomaticUpdateChecks(defaults:)`'s is: a UI-test launch must never write
/// the developer's real preferences, and "off on a fresh install" has to be
/// genuinely fresh rather than left over from a previous run. It is a
/// preference, not data, so it does not go to SwiftData.
@MainActor
@Observable
final class MenuBarPreference {
    static let key = "menuBar.isShown"

    @ObservationIgnored private let defaults: UserDefaults

    var isShown: Bool {
        didSet { defaults.set(isShown, forKey: Self.key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isShown = defaults.bool(forKey: Self.key)
    }
}
