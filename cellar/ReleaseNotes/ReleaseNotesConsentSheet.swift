//
//  ReleaseNotesConsentSheet.swift
//  cellar
//

import ReleaseNotes
import SwiftUI

/// The disclosure, in plain language, before anything leaves the machine.
///
/// Four rules this sheet exists to hold:
///
/// 1. The sentence describing what leaves is **the library's**, not a paraphrase
///    written here. `ReleaseNotesConsent.disclosure` is the one home for it, and
///    `ReleaseNotesCompositionTests` asserts this sheet shows it verbatim. Two
///    copies of a consent sentence drift; one cannot.
/// 2. It names what is **not** sent as specifically as what is, because a
///    disclosure that only lists inclusions leaves the reader to imagine the rest.
/// 3. Turning it off is offered in the same place as turning it on, so revocation
///    is never harder to find than the grant.
/// 4. The optional GitHub token is entered here and stored in the Keychain by
///    `KeychainReleaseNotesCredentialStore`, under a service name distinct from
///    the NVD key's. It is never written to preferences, never echoed back into
///    the field after it is saved, and never logged.
struct ReleaseNotesConsentSheet: View {
    let consent: ReleaseNotesConsentPreference
    let credentials: any ReleaseNotesCredentialStoring
    /// The budget GitHub last published, when Cellar has one. Shown here because
    /// the token field is only worth offering to somebody who can see why they
    /// would want it.
    var rateLimit: RateLimitStatus?

    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var tokenStatus: TokenStatus = .unknown

    private enum TokenStatus: Equatable {
        case unknown
        case absent
        case stored
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ask GitHub what changed in a release?")
                .font(.title2.bold())

            disclosure

            Divider()

            tokenSection

            Spacer(minLength: 0)

            controls
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 480)
        .accessibilityIdentifier("release-notes-consent")
        .task { await readTokenStatus() }
    }

    @ViewBuilder
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What leaves this Mac")
                .font(.headline)
            Text(Self.whatIsSent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("release-notes-consent-disclosure")

            Text("What never leaves")
                .font(.headline)
            Text(Self.whatIsNotSent)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("GitHub personal access token (optional)")
                .font(.headline)
            Text(Self.tokenExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let rateLimit, let remaining = rateLimit.remaining, let limit = rateLimit.limit {
                Text("GitHub last reported \(remaining) of \(limit) requests left this hour.")
                    .font(.caption)
                    .foregroundStyle(rateLimit.isExhausted ? .orange : .secondary)
                    .accessibilityIdentifier("release-notes-consent-budget")
            }

            HStack {
                SecureField("Paste a token to store it", text: $token)
                    .accessibilityIdentifier("release-notes-consent-token")
                Button("Store") { Task { await storeToken() } }
                    .disabled(token.isEmpty)
                Button("Remove") { Task { await removeToken() } }
                    .disabled(tokenStatus != .stored)
                    .accessibilityIdentifier("release-notes-consent-token-remove")
            }
            Text(tokenStatusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("release-notes-consent-token-status")
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            if consent.isGranted {
                Button("Turn release notes off", role: .destructive) {
                    consent.revoke()
                    dismiss()
                }
                .accessibilityIdentifier("release-notes-consent-revoke")
                Text("Notes already fetched stay readable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Not now") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(consent.isGranted ? "Done" : "Turn release notes on") {
                if !consent.isGranted { consent.grant() }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("release-notes-consent-grant")
        }
    }

    private var tokenStatusDescription: String {
        switch tokenStatus {
        case .unknown: "Reading the Keychain…"
        case .absent: "No token stored. Requests go unauthenticated at the lower limit."
        case .stored: "A token is stored in your Keychain."
        case .failed(let reason): reason
        }
    }

    private func readTokenStatus() async {
        do {
            tokenStatus = try await credentials.personalAccessToken() == nil ? .absent : .stored
        } catch {
            tokenStatus = .failed("The Keychain could not be read.")
        }
    }

    private func storeToken() async {
        do {
            try await credentials.store(personalAccessToken: token)
            // Cleared rather than masked: the field never holds the secret after
            // the store succeeds, so nothing can read it back out of the view.
            token = ""
            tokenStatus = .stored
        } catch {
            tokenStatus = .failed("The token could not be stored in the Keychain.")
        }
    }

    private func removeToken() async {
        do {
            try await credentials.removePersonalAccessToken()
            tokenStatus = .absent
        } catch {
            tokenStatus = .failed("The token could not be removed from the Keychain.")
        }
    }

    // MARK: - The disclosure text

    /// Supplied by `CellarCore`, not written here.
    ///
    /// The requirement is explicit that the disclosure comes from the library,
    /// and this is that requirement as one line of code: there is no app-side
    /// wording to drift out of step with what the library says a request does.
    static let whatIsSent = ReleaseNotesConsent.disclosure

    /// The app's half: what a reader would otherwise have to assume.
    ///
    /// Named constants rather than literals inside the body, so the sentence the
    /// user consented to is one value with one place to change it — which is what
    /// makes `ReleaseNotesConsent.grantedAt` meaningful as a version of the
    /// question.
    static let whatIsNotSent = """
        Not your other installed packages, not your taps, not the versions you have, not file \
        paths, not your username, and no analytics of any kind. Turning this on does not turn on \
        advisory scanning, and turning that on did not turn this on — they are separate questions \
        with separate answers.
        """

    static let tokenExplanation = """
        Without a token GitHub allows about 60 requests an hour from your network; with one it \
        allows 5,000. A token is never required — release notes work without it, you just run out \
        sooner. Cellar stores it in your Keychain, under its own item, never in preferences or a \
        plist, and never writes it to a log. A read-only token with no scopes is enough.
        """
}
