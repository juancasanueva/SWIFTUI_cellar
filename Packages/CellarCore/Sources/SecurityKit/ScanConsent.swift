import Foundation

/// Whether the user has agreed that package names and versions may leave this
/// machine, and when.
///
/// ## Why this is a value with one constructor
///
/// Everything about advisory scanning that could embarrass a user turns on a
/// single question, so the answer is not a mutable boolean that any code path
/// can flip. `granted(at:)` is the only way to build a consenting value, and it
/// requires a date — so a grant always knows when it was given, and "consented"
/// can never be reached by a default, a partial decode, or an uninitialised
/// field.
///
/// The date is not decoration either. The disclosure is versioned by nothing but
/// this timestamp: a grant given before a change to what leaves the machine is a
/// grant to a different question, and knowing when it was given is what lets the
/// app notice.
///
/// ## Where it lives
///
/// In the app's preferences, written by the app. This target holds no
/// `UserDefaults` and no `@AppStorage` — asserted structurally in
/// `CredentialStoreTests` — because a library that reaches into the defaults
/// domain is a library that can be made to consent on the user's behalf by
/// anything that can write a plist.
public struct ScanConsent: Sendable, Hashable, Codable {
    public let isGranted: Bool
    /// When consent was given, and `nil` whenever it was not.
    ///
    /// The two fields cannot disagree because no public initialiser lets them.
    public let grantedAt: Date?

    private init(isGranted: Bool, grantedAt: Date?) {
        self.isGranted = isGranted
        self.grantedAt = grantedAt
    }

    /// The starting state, and the state after revocation. They are the same
    /// value on purpose: revocation leaves no residue that could later be
    /// misread as a lapsed grant.
    public static let notGranted = ScanConsent(isGranted: false, grantedAt: nil)

    public static func granted(at date: Date) -> ScanConsent {
        ScanConsent(isGranted: true, grantedAt: date)
    }

    public func revoked() -> ScanConsent { .notGranted }

    /// The check every egress path runs before it runs anything else.
    ///
    /// Throwing rather than returning a boolean is deliberate. A `Bool` invites
    /// `if consented { … }` with no `else`, which is exactly "parking silently":
    /// the scan does nothing, says nothing, and the user is left looking at an
    /// empty security surface wondering whether that means they are safe. A
    /// typed refusal has to be caught and shown.
    public func authorise() throws(AdvisoryError) {
        guard isGranted else { throw .blockedPendingConsent }
    }
}

/// Where the running consent value comes from.
///
/// A seam because the value lives in the app's preferences and this target may
/// not read them, and `async` because a conforming implementation on the app
/// side is `@MainActor`.
public protocol ScanConsentProviding: Sendable {
    func currentConsent() async -> ScanConsent
}

/// A fixed answer, for composition roots that already hold the value.
public struct FixedScanConsent: ScanConsentProviding {
    private let consent: ScanConsent

    public init(_ consent: ScanConsent) {
        self.consent = consent
    }

    public func currentConsent() async -> ScanConsent { consent }
}
