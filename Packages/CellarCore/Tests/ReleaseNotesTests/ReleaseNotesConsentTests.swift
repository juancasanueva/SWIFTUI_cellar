import Foundation
import ReleaseNotes
import Testing

/// Nothing leaves this Mac before a **dated** release-notes grant, and the grant
/// that authorises a CVE scan is not this grant.
///
/// The shape mirrors `ScanConsent` exactly — one consenting constructor that
/// requires a date, revocation that leaves no residue, a throwing refusal rather
/// than a boolean — with one deliberate strengthening: `authorise()` returns a
/// `ReleaseNotesGrant` the network type *requires*, and that token has no public
/// initialiser. Egress before a grant is therefore a compile error first and a
/// failing test second.
@Suite("Release-notes consent")
struct ReleaseNotesConsentTests {
    // MARK: - The refusal

    @Test("Without a grant, authorising throws the typed pending-consent refusal")
    func withoutAGrantAuthorisingThrows() {
        let consent = ReleaseNotesConsent.notGranted

        #expect(consent.isGranted == false)
        #expect(consent.grantedAt == nil)
        #expect(throws: ReleaseNotesError.blockedPendingConsent) {
            try consent.authorise()
        }
    }

    /// Throwing, never `Bool`. A boolean invites `if consented { … }` with no
    /// `else`, which is a sheet that opens on nothing and a user left wondering
    /// whether "no release notes" meant the request was refused or the repository
    /// publishes none. A typed refusal has to be caught and shown.
    @Test("The refusal is a typed error and not a silently absent result")
    func theRefusalIsTypedAndNotAnAbsentResult() {
        var caught: ReleaseNotesError?
        do {
            _ = try ReleaseNotesConsent.notGranted.authorise()
        } catch {
            caught = error
        }

        #expect(caught == .blockedPendingConsent)
        // The other direction, so the assertion above is about the refusal and
        // not about a value that is always produced: a granted consent throws
        // nothing at all.
        #expect(throws: Never.self) {
            try ReleaseNotesConsent.granted(at: Date()).authorise()
        }
    }

    // MARK: - The grant

    @Test("granted(at:) is the only consenting constructor and always carries its date")
    func grantedAtIsTheOnlyConsentingConstructor() throws {
        let date = Date(timeIntervalSince1970: 1_786_000_000)
        let consent = ReleaseNotesConsent.granted(at: date)

        #expect(consent.isGranted)
        #expect(consent.grantedAt == date)

        // The grant exists, which is the whole assertion: the network surface
        // cannot be called without one, and this is its only producer.
        #expect(throws: Never.self) { try consent.authorise() }

        // The paired negative, so "it did not throw" is a property of the grant
        // and not of a method that never throws.
        #expect(throws: ReleaseNotesError.blockedPendingConsent) {
            try ReleaseNotesConsent.notGranted.authorise()
        }
    }

    @Test("A consenting value round-trips through Codable carrying its date")
    func aConsentingValueRoundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_786_000_000)
        let consent = ReleaseNotesConsent.granted(at: date)

        let decoded = try JSONDecoder().decode(
            ReleaseNotesConsent.self,
            from: JSONEncoder().encode(consent)
        )

        #expect(decoded == consent)
        #expect(decoded.grantedAt == date)
        #expect(throws: Never.self) { try decoded.authorise() }
    }

    // MARK: - Revocation

    @Test("Revocation leaves no residue, including the date")
    func revocationLeavesNoResidue() {
        let granted = ReleaseNotesConsent.granted(at: Date(timeIntervalSince1970: 1_000_000))

        let revoked = granted.revoked()

        #expect(revoked == .notGranted)
        #expect(revoked.isGranted == false)
        // The clause that matters and is easy to get wrong: a lingering date is
        // exactly what a later reader would misinterpret as a lapsed grant.
        #expect(revoked.grantedAt == nil)
        #expect(throws: ReleaseNotesError.blockedPendingConsent) { try revoked.authorise() }
    }

    /// A revoked grant costs nothing, counted through a **per-instance** recorder.
    ///
    /// The control is the shipped source on the same transport: a *granted*
    /// consent produces a grant, and that grant buys exactly one request. So the
    /// zero is the zero of a live egress path that a revocation closed, and not
    /// the zero of a recorder nobody wired up — nor, as with the process-global
    /// counter this replaced, a zero a sibling suite's `install()` had reset.
    @Test("A revoked grant issues no request, counted")
    func aRevokedGrantIssuesNoRequest() async throws {
        let network = RecordingNetwork()
        let source = GitHubReleaseNotesSource(session: network.session)
        let repository = try #require(GitHubRepository(owner: "acme", name: "foo"))

        let consent = ReleaseNotesConsent
            .granted(at: Date(timeIntervalSince1970: 1_000_000))
            .revoked()

        #expect(throws: ReleaseNotesError.blockedPendingConsent) { try consent.authorise() }
        #expect(network.requestCount == 0)

        // The control: the same source, on the same transport, reached through a
        // grant that does exist.
        let grant = try ReleaseNotesConsent.granted(at: Date()).authorise()
        _ = try await source.releases(
            for: repository, validators: nil, token: nil, grant: grant
        )
        #expect(network.requestCount == 1, "the recorder did not notice a real request")
    }

    // MARK: - The seam

    @Test("A fixed provider hands back exactly the value it was built with")
    func aFixedProviderHandsBackItsValue() async throws {
        let date = Date(timeIntervalSince1970: 2_000_000)

        let granting = FixedReleaseNotesConsent(.granted(at: date))
        #expect(await granting.currentConsent().grantedAt == date)
        let carried = await granting.currentConsent()
        #expect(throws: Never.self) { try carried.authorise() }

        let refusing = FixedReleaseNotesConsent(.notGranted)
        #expect(await refusing.currentConsent() == .notGranted)
    }

    // MARK: - The disclosure

    /// The disclosure is supplied by `CellarCore`, not written into a view, so
    /// the sentence the user consented to has one home and `grantedAt` is
    /// meaningful as a version of the question that was asked.
    @Test("The disclosure names the host and what a repository name reveals")
    func theDisclosureNamesTheHostAndWhatIsRevealed() {
        let disclosure = ReleaseNotesConsent.disclosure

        #expect(disclosure.contains("api.github.com"))
        #expect(disclosure.lowercased().contains("repository name"))
        // The inference the user is entitled to have spelled out: the request
        // reveals that this Mac has the package and is about to upgrade it.
        #expect(disclosure.lowercased().contains("installed"))
        #expect(disclosure.lowercased().contains("upgrade"))
    }

    /// The other half, and the one a well-meaning copy edit breaks: the
    /// disclosure must not claim anonymity it does not have.
    @Test(
        "The disclosure claims no anonymity",
        arguments: ["anonymous", "nothing about this Mac", "no identifying"]
    )
    func theDisclosureClaimsNoAnonymity(forbidden: String) {
        #expect(
            ReleaseNotesConsent.disclosure.lowercased().contains(forbidden.lowercased()) == false,
            "the disclosure claims \(forbidden)"
        )
    }

    // MARK: - Structural: the grant is unforgeable

    /// `ReleaseNotesGrant` has **no public initialiser**, so `authorise()` is its
    /// only producer and "egress before a dated grant" is a type error.
    ///
    /// The `IntegrityProhibitionTests` idiom: a public-surface enumeration of the
    /// declaring file, comments stripped, asserting that the only `init` on the
    /// grant is not public. A behavioural test cannot prove this — the violation
    /// would be a call that does not compile — so it is asserted against the
    /// source a reviewer reads.
    @Test("The grant declares no public initialiser, so authorise() is its only producer")
    func theGrantDeclaresNoPublicInitialiser() throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        let declaring = try #require(
            sources.first { $0.code.contains("public struct ReleaseNotesGrant") },
            "no file declares ReleaseNotesGrant"
        )

        // Anchored positively first: the declaration really is in the text being
        // scanned, and it really does declare an initialiser.
        #expect(declaring.code.contains("public struct ReleaseNotesGrant"))
        #expect(declaring.code.contains("init()"))
        #expect(
            declaring.code.contains("public init()") == false,
            "ReleaseNotesGrant gained a public initialiser in \(declaring.name)"
        )
    }

    /// The structural half of "the security-scan grant does not authorise release
    /// notes": this target cannot even *see* `ScanConsent`.
    ///
    /// That makes the requirement a fact of the build graph rather than a
    /// convention somebody could relax with one `import`.
    @Test("The target imports no SecurityKit symbol, so no scan grant can reach it")
    func theTargetImportsNoSecurityKitSymbol() throws {
        let sources = try ReleaseNotesSources.load()
        ReleaseNotesSources.assertAnchored(sources)

        for token in ["SecurityKit", "ScanConsent", "AdvisoryError", "AdvisoryCredentialStoring"] {
            let offenders = sources.filter { $0.code.containsIdentifier(token) }
            #expect(
                offenders.isEmpty,
                "\(token) leaked into \(offenders.map(\.name).sorted())"
            )
        }
    }
}
