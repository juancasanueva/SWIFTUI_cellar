import Foundation
import SecurityKit
import Testing

/// Consent, as a value.
///
/// Everything about this feature that could embarrass a user turns on one
/// question — *did they say yes* — and the whole point of making it a value with
/// one constructor is that "yes" cannot be arrived at by accident. There is no
/// mutable boolean, no default-true, and no way to build a granted consent
/// without a date on it.
@Suite("Scan consent")
struct ScanConsentTests {
    // MARK: - The default

    /// First launch is not consent, and the absence of a stored preference is
    /// not consent either.
    @Test("Consent is absent until it is given")
    func consentIsAbsentUntilItIsGiven() {
        #expect(ScanConsent.notGranted.isGranted == false)
        #expect(ScanConsent.notGranted.grantedAt == nil)
    }

    // MARK: - The gate

    /// The `vulnerability-scanning` requirement: nothing egresses before
    /// consent — and when something tries, it says so.
    ///
    /// A typed refusal rather than silence. "You have not opted in" and "we
    /// tried and could not reach anyone" are different sentences, and a surface
    /// showing the second for the first would be lying about what the app did.
    /// Parking silently is the failure this test exists to prevent: a scan that
    /// simply returns nothing leaves the user staring at an empty security
    /// surface with no idea why.
    @Test("A blocked egress emits blockedPendingConsent rather than parking silently")
    func aBlockedEgressEmitsBlockedPendingConsentRatherThanParkingSilently() {
        #expect(throws: AdvisoryError.blockedPendingConsent) {
            try ScanConsent.notGranted.authorise()
        }

        // The control: a granted consent authorises without throwing, so the
        // refusal above is consent's doing rather than a gate that refuses
        // everyone.
        let granted = ScanConsent.granted(at: Date(timeIntervalSince1970: 1_780_000_000))
        #expect(throws: Never.self) { try granted.authorise() }
        #expect(granted.isGranted)
        #expect(granted.grantedAt == Date(timeIntervalSince1970: 1_780_000_000))
    }

    // MARK: - Reversibility

    /// Off is fully off, and it leaves no residue that could be misread as a
    /// lapsed grant.
    @Test("Revocation clears the grant and its date, and is idempotent")
    func revocationClearsTheGrantAndItsDate() {
        let granted = ScanConsent.granted(at: Date(timeIntervalSince1970: 1_780_000_000))
        let revoked = granted.revoked()

        #expect(revoked.isGranted == false)
        #expect(revoked.grantedAt == nil)
        #expect(revoked == ScanConsent.notGranted)
        #expect(revoked.revoked() == revoked)

        #expect(throws: AdvisoryError.blockedPendingConsent) { try revoked.authorise() }
    }

    /// Consent is stored by the app in its preferences, so it has to survive
    /// that round trip intact — a decode that lost `grantedAt` would leave a
    /// grant nobody can date.
    @Test("Consent survives the preference round trip")
    func consentSurvivesThePreferenceRoundTrip() throws {
        let granted = ScanConsent.granted(at: Date(timeIntervalSince1970: 1_780_000_000))

        let encoded = try JSONEncoder().encode(granted)
        let decoded = try JSONDecoder().decode(ScanConsent.self, from: encoded)

        #expect(decoded == granted)
        #expect(decoded.grantedAt == granted.grantedAt)

        let revoked = try JSONDecoder().decode(
            ScanConsent.self,
            from: try JSONEncoder().encode(ScanConsent.notGranted)
        )
        #expect(revoked.isGranted == false)
    }
}
