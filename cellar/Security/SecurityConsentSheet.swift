//
//  SecurityConsentSheet.swift
//  cellar
//

import SecurityKit
import SwiftUI

/// The disclosure, in plain language, before anything leaves the machine.
///
/// Three rules this sheet exists to hold:
///
/// 1. It names **both hosts** by their real addresses, not "our servers".
/// 2. It names **exactly what is sent** — mapped package names and versions —
///    and, just as importantly, what is not.
/// 3. Turning it off is offered in the same place as turning it on, so
///    revocation is never harder to find than the grant.
///
/// The optional NVD key is entered here and stored in the Keychain by
/// `KeychainAdvisoryCredentialStore`. It is never written to preferences, never
/// echoed back into the field after it is saved, and never logged.
struct SecurityConsentSheet: View {
    let consent: SecurityConsentPreference
    let credentials: any AdvisoryCredentialStoring
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var keyStatus: KeyStatus = .unknown

    private enum KeyStatus: Equatable {
        case unknown
        case absent
        case stored
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check installed packages against advisory databases?")
                .font(.title2.bold())

            disclosure

            Divider()

            apiKeySection

            Spacer(minLength: 0)

            controls
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 460)
        .accessibilityIdentifier("security-consent")
        .task { await readKeyStatus() }
    }

    @ViewBuilder
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What leaves this Mac")
                .font(.headline)
            Text(Self.whatIsSent)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("security-consent-disclosure")

            Text("Where it goes")
                .font(.headline)
            ForEach(Self.hosts, id: \.host) { destination in
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.host)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    Text(destination.purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("security-consent-host-\(destination.host)")
            }

            Text("What never leaves")
                .font(.headline)
            Text(Self.whatIsNotSent)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NVD API key (optional)")
                .font(.headline)
            Text(
                """
                A key raises the rate limit for severity lookups. Cellar stores it in your \
                Keychain, never in preferences or a plist, and never writes it to a log.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                SecureField("Paste a key to store it", text: $apiKey)
                    .accessibilityIdentifier("security-consent-api-key")
                Button("Store") { Task { await storeKey() } }
                    .disabled(apiKey.isEmpty)
                Button("Remove") { Task { await removeKey() } }
                    .disabled(keyStatus != .stored)
            }
            Text(keyStatusDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("security-consent-api-key-status")
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack {
            if consent.isGranted {
                Button("Turn checking off", role: .destructive) {
                    consent.revoke()
                    dismiss()
                }
                .accessibilityIdentifier("security-consent-revoke")
                Text("Findings already downloaded stay readable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Not now") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(consent.isGranted ? "Done" : "Turn checking on") {
                if !consent.isGranted { consent.grant() }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("security-consent-grant")
        }
    }

    private var keyStatusDescription: String {
        switch keyStatus {
        case .unknown: "Reading the Keychain…"
        case .absent: "No key stored. Lookups run unauthenticated at the lower rate limit."
        case .stored: "A key is stored in your Keychain."
        case .failed(let reason): reason
        }
    }

    private func readKeyStatus() async {
        do {
            keyStatus = try await credentials.apiKey() == nil ? .absent : .stored
        } catch {
            keyStatus = .failed("The Keychain could not be read.")
        }
    }

    private func storeKey() async {
        do {
            try await credentials.store(apiKey: apiKey)
            // Cleared rather than masked: the field never holds the secret after
            // the store succeeds, so nothing can read it back out of the view.
            apiKey = ""
            keyStatus = .stored
        } catch {
            keyStatus = .failed("The key could not be stored in the Keychain.")
        }
    }

    private func removeKey() async {
        do {
            try await credentials.removeAPIKey()
            keyStatus = .absent
        } catch {
            keyStatus = .failed("The key could not be removed from the Keychain.")
        }
    }

    // MARK: - The disclosure text

    /// Named constants rather than literals inside the body, so the sentence the
    /// user consented to is one value with one place to change it — which is what
    /// makes `ScanConsent.grantedAt` meaningful as a version of the question.
    static let whatIsSent = """
        The name and installed version of each package Cellar can map to an advisory database \
        — a few dozen of your installed formulae at most — and, for advisories that come back, \
        their CVE identifiers. Nothing else about this Mac is sent.
        """

    static let whatIsNotSent = """
        Not your other installed packages, not your taps, not file paths, not your username, \
        not any identifier for this Mac, and no analytics of any kind.
        """

    static let hosts: [(host: String, purpose: String)] = [
        (
            "api.osv.dev",
            "Asked whether an advisory applies to a package at your installed version."
        ),
        (
            "services.nvd.nist.gov",
            "Asked for severity scores, by CVE identifier only. No request names a package you have installed."
        )
    ]
}
