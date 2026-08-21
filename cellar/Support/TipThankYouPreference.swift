//
//  TipThankYouPreference.swift
//  cellar
//

import Foundation
import Observation
import TipJar

/// Where the thank-you actually lives: this app's preferences, as one boolean.
///
/// `TipJar` holds no `UserDefaults` and no `@AppStorage` — it has zero
/// dependencies and could not reach the defaults domain if it wanted to — so the
/// value is owned here and handed across the `TipGratitudeRecording` seam. The
/// same split `SecurityConsentPreference` and `ReleaseNotesConsentPreference`
/// already make, under a key of its own.
///
/// **One key, and one boolean under it.** Not a date, not a count, not a
/// transaction id, not an original transaction id, not a product id, not a
/// price, not a storefront. Cellar's no-telemetry claim is what a payment
/// feature is most likely to be suspected of breaking, so the record is the
/// smallest thing that works: enough not to re-ask someone who has already
/// given, and nothing a reviewer would have to take on trust. Reverting this
/// slice leaves exactly one inert, greppable key behind.
@MainActor
@Observable
final class TipThankYouPreference: TipGratitudeRecording {
    /// Whether a tip was ever completed on this machine. Read to say thank you —
    /// never to decide what a user may see or do.
    private(set) var isTipRecorded: Bool

    @ObservationIgnored private let defaults: UserDefaults

    /// Namespaced, and distinct from every consent key: having tipped says
    /// nothing about advisory scanning or GitHub, and none of the three may be
    /// read as another.
    static let hasTippedKey = "tip.jar.hasTipped"

    /// A UI-test launch gets a suite of its own, so those runs never write the
    /// developer's real preferences and the un-tipped path is genuinely
    /// un-tipped rather than left over from a previous run — the
    /// `ReleaseNotesConsentPreference` fixture shape.
    init(defaults: UserDefaults? = nil) {
        let store = defaults ?? Self.launchDefaults()
        self.defaults = store
        // A missing key is "never tipped". There is deliberately no default that
        // reads as a tip, and no migration that could invent one.
        isTipRecorded = store.bool(forKey: Self.hasTippedKey)
    }

    private static func launchDefaults() -> UserDefaults {
        guard AppTestFixtures.isEnabled else { return .standard }
        return UserDefaults(suiteName: "cellar-ui-tip-\(UUID().uuidString)") ?? .standard
    }

    // MARK: - The seam

    func hasTipped() async -> Bool { isTipRecorded }

    func recordTip() async {
        isTipRecorded = true
        defaults.set(true, forKey: Self.hasTippedKey)
    }
}
