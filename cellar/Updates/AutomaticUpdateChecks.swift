//
//  AutomaticUpdateChecks.swift
//  cellar
//

import Foundation

/// Whether Cellar may look for updates on its own.
///
/// A value type over an injected `UserDefaults`, mirroring
/// `SecurityConsentPreference`: the defaults domain is a parameter, so the
/// launch-time wiring reads the real one and a test reads a scratch suite. That
/// is what makes "a fresh install does not check automatically" a testable
/// claim rather than a hope about the developer's machine.
///
/// A **missing key reads `false`**. There is deliberately no default that reads
/// as consent and no migration that could invent one: an update check is
/// network egress, and "we never asked" must not be storable as "they said yes".
///
/// This value — not the updater framework's own bundled key, and not whatever
/// the framework persisted on a previous launch — is the authority. The launch
/// wiring writes it to the updater every time.
struct AutomaticUpdateChecks {
    static let key = "updates.automaticChecksEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nonmutating set` because the storage is the defaults domain, not this
    /// value: a `let` binding held by a view can still record the user's answer.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
