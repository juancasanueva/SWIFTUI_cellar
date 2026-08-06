//
//  SecurityConsentPreference.swift
//  cellar
//

import Foundation
import Observation
import SecurityKit

/// Where the consent answer actually lives: this app's preferences.
///
/// `SecurityKit` holds no `UserDefaults` and no `@AppStorage` — a structural
/// guard in `CredentialStoreTests` asserts it — because a library that can reach
/// the defaults domain is a library that anything able to write a plist can make
/// consent on the user's behalf. So the value is owned here and handed across the
/// `ScanConsentProviding` seam.
///
/// A boolean plus a date is a **preference, not a secret**: it goes in defaults,
/// while the NVD API key goes in the Keychain. The two are different kinds of
/// thing and are stored differently on purpose.
@MainActor
@Observable
final class SecurityConsentPreference: ScanConsentProviding {
    /// Whether package names and versions may leave this machine.
    private(set) var consent: ScanConsent

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: @Sendable () -> Date

    static let grantedKey = "security.scan.consentGranted"
    static let grantedAtKey = "security.scan.consentGrantedAt"

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

    func currentConsent() async -> ScanConsent { consent }
}
