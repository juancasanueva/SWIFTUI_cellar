//
//  TipThankYouPreferenceTests.swift
//  cellarTests
//

import Foundation
import Testing
import TipJar

@testable import cellar

/// Requirement 6 — "The thank-you is one local boolean, and that is the whole
/// record" — at the one place the record actually touches disk.
///
/// `TipJarTests` proves the *rule*: five of the six outcomes write nothing. This
/// proves the *storage*: what survives a relaunch is a single namespaced boolean
/// and nothing else — no date, no count, no transaction id, no product id, no
/// price, no storefront. That list is the whole reason this suite reads the
/// domain back key by key rather than only asking the preference what it thinks.
@Suite("Tip thank-you preference")
@MainActor
struct TipThankYouPreferenceTests {
    /// A defaults suite of this test's own, so nothing here can read or write the
    /// developer's real preferences and two tests can never see each other's
    /// writes.
    private static func suite(_ function: String = #function) -> UserDefaults {
        let name = "cellar-tip-tests-\(function)-\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    // MARK: - The thank-you survives a relaunch

    @Test("A recorded tip is read back by a fresh instance")
    func aRecordedTipIsReadBackByAFreshInstance() async {
        let defaults = Self.suite()

        let recording = TipThankYouPreference(defaults: defaults)
        #expect(await recording.hasTipped() == false, "the suite was not empty to begin with")

        await recording.recordTip()

        // A *fresh* instance, which is what a relaunch actually is: the value has
        // to come off disk rather than out of the instance that wrote it.
        let relaunched = TipThankYouPreference(defaults: defaults)
        #expect(await relaunched.hasTipped(), "a user who already gave would be asked again")
        #expect(relaunched.isTipRecorded, "the observable reading disagrees with the stored one")
    }

    /// Triangulation: a suite nothing ever wrote to must come back unset, or the
    /// read above could be answering `true` regardless.
    @Test("An untouched store reads back unset")
    func anUntouchedStoreReadsBackUnset() async {
        let defaults = Self.suite()

        let preference = TipThankYouPreference(defaults: defaults)

        #expect(await preference.hasTipped() == false)
        #expect(preference.isTipRecorded == false)
        #expect(
            defaults.object(forKey: TipThankYouPreference.hasTippedKey) == nil,
            "a default was invented for a tip nobody gave"
        )
    }

    // MARK: - Nothing else is remembered

    @Test("Recording writes exactly one namespaced key, and it is a boolean")
    func recordingWritesExactlyOneNamespacedKeyAndItIsABoolean() async {
        let defaults = Self.suite()

        await TipThankYouPreference(defaults: defaults).recordTip()

        let written = defaults.dictionaryRepresentation()
            .keys
            .filter { $0.hasPrefix("tip.") }
        #expect(written == ["tip.jar.hasTipped"], "the tip wrote something other than its one flag")
        #expect(TipThankYouPreference.hasTippedKey == "tip.jar.hasTipped")
        #expect(defaults.object(forKey: TipThankYouPreference.hasTippedKey) as? Bool == true)
    }

    /// The forbidden list, read back from the domain itself rather than trusted.
    /// A date or a transaction id appearing here is the exact thing the
    /// no-telemetry claim would be broken by.
    @Test("No date, count, identifier, price or storefront is stored")
    func noDateCountIdentifierPriceOrStorefrontIsStored() async {
        let defaults = Self.suite()

        let preference = TipThankYouPreference(defaults: defaults)
        await preference.recordTip()
        // Twice, because a counter would only become visible on the second one.
        await preference.recordTip()

        let stored = defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix("tip.") }
        #expect(stored.count == 1, "the tip remembers more than one thing")

        let value = stored["tip.jar.hasTipped"]
        #expect(value as? Bool == true)
        #expect(value as? Date == nil)
        #expect(value as? String == nil, "an identifier, price or storefront was kept")
        // A `Bool` in a defaults domain comes back as an `NSNumber`, so
        // `as? Int` succeeds for a flag as readily as for a counter and proves
        // nothing on its own. What separates the two is the **value after two
        // recordings**: a flag is still 1, a count is 2.
        #expect((value as? NSNumber)?.intValue == 1, "a tip count was kept instead of a flag")
        #expect(
            CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID(),
            "the record is stored as a number rather than as the one boolean it is"
        )
        #expect(
            stored.keys.contains { $0.contains(TipProductIDs.tip) } == false,
            "the product id was written into the record"
        )
    }

    /// Recording twice must stay one boolean rather than becoming a history: a
    /// consumable may be bought again, and the record is not allowed to grow
    /// with each one.
    @Test("A second tip leaves the record the same size and the same shape")
    func aSecondTipLeavesTheRecordTheSameSizeAndTheSameShape() async {
        let defaults = Self.suite()
        let preference = TipThankYouPreference(defaults: defaults)

        await preference.recordTip()
        let afterFirst = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("tip.") }

        await preference.recordTip()
        let afterSecond = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("tip.") }

        #expect(afterFirst.count == 1)
        #expect(Set(afterFirst.keys) == Set(afterSecond.keys))
        #expect(afterSecond["tip.jar.hasTipped"] as? Bool == true)
        #expect(await preference.hasTipped())
    }

    // MARK: - It really is the seam the store talks to

    /// The conformance, exercised through the protocol rather than through the
    /// concrete type: the store only ever sees `TipGratitudeRecording`, so that
    /// is the surface worth proving.
    @Test("The preference satisfies the gratitude seam the store consumes")
    func thePreferenceSatisfiesTheGratitudeSeamTheStoreConsumes() async {
        let defaults = Self.suite()
        let seam: any TipGratitudeRecording = TipThankYouPreference(defaults: defaults)

        #expect(await seam.hasTipped() == false)
        await seam.recordTip()
        #expect(await seam.hasTipped())
    }
}
