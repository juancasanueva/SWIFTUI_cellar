//
//  ReleaseNotesConsentPreference.swift
//  cellar
//

import Foundation
import Observation
import ReleaseNotes

/// Where the release-notes consent answer actually lives: this app's preferences.
///
/// `ReleaseNotes` holds no `UserDefaults` and no `@AppStorage` — a structural
/// guard in `ReleaseNotesCredentialStoreTests` asserts it — because a library
/// that can reach the defaults domain is a library that anything able to write a
/// plist can make consent on the user's behalf. So the value is owned here and
/// handed across the `ReleaseNotesConsentProviding` seam.
///
/// A boolean plus a date is a **preference, not a secret**: it goes in defaults,
/// while the GitHub token goes in the Keychain. The same split
/// `SecurityConsentPreference` already makes, under its own two keys — this grant
/// is not that grant, and neither may be read as the other.
@MainActor
@Observable
final class ReleaseNotesConsentPreference: ReleaseNotesConsentProviding {
    /// Whether a repository name may leave this machine to ask GitHub what
    /// changed.
    private(set) var consent: ReleaseNotesConsent

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date

    /// Distinct from `security.scan.consentGranted`, and deliberately so: turning
    /// advisory scanning on says nothing about GitHub.
    static let grantedKey = "releaseNotes.consentGranted"
    static let grantedAtKey = "releaseNotes.consentGrantedAt"

    init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        // A missing key is "not granted". There is deliberately no default that
        // reads as consent, and no migration that could invent one.
        if defaults.bool(forKey: Self.grantedKey),
           let grantedAt = defaults.object(forKey: Self.grantedAtKey) as? Date {
            consent = .granted(at: grantedAt)
        } else {
            consent = .notGranted
        }
    }

    var isGranted: Bool { consent.isGranted }

    func grant() {
        let date = now()
        consent = .granted(at: date)
        defaults.set(true, forKey: Self.grantedKey)
        defaults.set(date, forKey: Self.grantedAtKey)
    }

    /// Revocation leaves no residue. Both keys go, so nothing on disk could later
    /// be misread as a lapsed grant.
    func revoke() {
        consent = .notGranted
        defaults.removeObject(forKey: Self.grantedKey)
        defaults.removeObject(forKey: Self.grantedAtKey)
    }

    func currentConsent() async -> ReleaseNotesConsent { consent }
}
