import Foundation

/// Whether the user has agreed that a repository name may leave this machine to
/// ask GitHub what changed, and when they agreed.
///
/// ## Why this is a second consent value and not a shared one
///
/// `ScanConsent` answers a different question. It authorises sending *package
/// names and versions* to two advisory databases; this authorises sending *one
/// repository name* to GitHub. Agreeing to the first is not agreeing to the
/// second, and a user who turned advisory scanning on has said nothing about
/// GitHub. So the values are separate, the Keychain items are separate, and this
/// target cannot see `SecurityKit` at all — which makes that separation a fact of
/// the build graph rather than a rule someone remembers.
///
/// The rules themselves are the same rules, restated rather than reinvented: one
/// consenting constructor that requires a date, revocation that leaves no
/// residue, and a throwing refusal.
///
/// ## Why `authorise()` returns a token
///
/// This is the one deliberate divergence from `ScanConsent`'s shape, and it is a
/// strengthening of the same rule. `ReleaseNotesGrant` has an **internal**
/// initialiser, so `authorise()` is its only producer, and the type that owns the
/// `URLSession` requires one to be handed in. "Nothing leaves this Mac before a
/// dated grant" therefore stops being a discipline the next contributor has to
/// notice and becomes something the compiler enforces.
public struct ReleaseNotesConsent: Sendable, Hashable, Codable {
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
    /// value on purpose: revocation leaves no residue that could later be misread
    /// as a lapsed grant.
    public static let notGranted = ReleaseNotesConsent(isGranted: false, grantedAt: nil)

    public static func granted(at date: Date) -> ReleaseNotesConsent {
        ReleaseNotesConsent(isGranted: true, grantedAt: date)
    }

    public func revoked() -> ReleaseNotesConsent { .notGranted }

    /// The check the egress path runs before it runs anything else.
    ///
    /// Throwing rather than returning a boolean, for the reason `ScanConsent`
    /// already records: a `Bool` invites `if consented { … }` with no `else`,
    /// which is a sheet that opens on nothing while the user wonders whether "no
    /// release notes" meant refusal or an empty repository.
    @discardableResult
    public func authorise() throws(ReleaseNotesError) -> ReleaseNotesGrant {
        guard isGranted else { throw .blockedPendingConsent }
        return ReleaseNotesGrant()
    }

    // MARK: - The disclosure

    /// What the user is agreeing to, supplied by `CellarCore` rather than written
    /// into a view.
    ///
    /// One value with one place to change it, which is what makes `grantedAt`
    /// meaningful: a grant given before this sentence changed is a grant to a
    /// different question, and the date is how the app could notice.
    ///
    /// It names the host, names what leaves, and — the part a well-meaning copy
    /// edit tends to remove — states the *inference* that name allows. It does not
    /// claim the request reveals nothing, because it does reveal something.
    public static let disclosure = """
        Cellar asks api.github.com for the releases published by this package's own \
        repository, and it asks only when you click.

        What leaves this Mac is the repository name — for example acme/foo — and \
        nothing else. That name is not neutral: it tells GitHub this Mac has that \
        package installed and that you are about to upgrade it. GitHub also sees \
        which IP address the request came from, as it does for any web request.

        Not sent: your other installed packages, your taps, any version number, any \
        file path, your username, or any identifier for this Mac. Cellar asks once \
        per package and version, remembers the answer, and never asks during a bulk \
        upgrade or a background refresh.
        """
}

/// Proof that a dated grant existed at the moment a request was built.
///
/// The initialiser is **internal**, so the only value of this type anyone outside
/// this module can obtain is one `ReleaseNotesConsent.authorise()` returned. The
/// fetch entry point takes one, so an unconsented request is not something a test
/// has to catch — it is something that does not compile.
///
/// It carries no payload deliberately. A grant is not a credential and must never
/// become one: nothing about it should be worth storing, forwarding or logging.
public struct ReleaseNotesGrant: Sendable, Hashable {
    init() {}
}

/// Where the running consent value comes from.
///
/// A seam because the value lives in the app's preferences and this target may
/// not read them, and `async` because a conforming implementation on the app side
/// is `@MainActor`.
public protocol ReleaseNotesConsentProviding: Sendable {
    func currentConsent() async -> ReleaseNotesConsent
}

/// A fixed answer, for composition roots that already hold the value.
public struct FixedReleaseNotesConsent: ReleaseNotesConsentProviding {
    private let consent: ReleaseNotesConsent

    public init(_ consent: ReleaseNotesConsent) {
        self.consent = consent
    }

    public func currentConsent() async -> ReleaseNotesConsent { consent }
}
