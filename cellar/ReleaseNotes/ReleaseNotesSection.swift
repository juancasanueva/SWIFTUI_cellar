//
//  ReleaseNotesSection.swift
//  cellar
//

import Catalog
import ReleaseNotes
import SwiftUI

/// The one thing both entry points share: an explicit button, the two sheets it
/// can open, and no trigger of any kind.
///
/// Extracted rather than written twice because the *absence* is the interesting
/// part. There is no `.task`, no `.onAppear`, no `.onChange` and no
/// `.onHover` anywhere in this file: work starts when `action` runs, which
/// happens when a person presses a button. Two copies of that discipline would
/// be one copy away from someone adding a convenience trigger to one of them.
struct ReleaseNotesButton: View {
    let id: PackageID
    let displayName: String
    let version: String
    let candidates: RepositoryCandidates
    /// The label the entry point wants. The row uses a compact one; the detail
    /// view uses a full sentence.
    var label: String = "What's new?"
    var showsSlug = false

    @Environment(ReleaseNotesStore.self) private var store: ReleaseNotesStore?
    @Environment(ReleaseNotesConsentPreference.self)
    private var consent: ReleaseNotesConsentPreference?
    @Environment(\.releaseNotesCredentials) private var credentials

    @State private var isShowingNotes = false
    @State private var isShowingConsent = false

    private var affordance: ReleaseNotesAffordance {
        ReleaseNotesAffordance(isOutdated: true, candidates: candidates)
    }

    var body: some View {
        Button(label) { open() }
            .buttonStyle(.borderless)
            .help(helpText)
            .accessibilityIdentifier("release-notes-open-\(id.name)")
            .sheet(isPresented: $isShowingNotes) {
                ReleaseNotesSheet(
                    packageName: displayName,
                    version: version,
                    state: store?.state(for: id) ?? .idle,
                    onOpenConsent: {
                        isShowingNotes = false
                        isShowingConsent = true
                    },
                    onRetry: { load() }
                )
            }
            .sheet(isPresented: $isShowingConsent) {
                if let consent, let credentials {
                    ReleaseNotesConsentSheet(
                        consent: consent,
                        credentials: credentials,
                        rateLimit: store?.rateLimit
                    )
                }
            }
    }

    /// The whole trigger surface of this capability: one function, called from
    /// one `Button`.
    ///
    /// A user with no grant is shown the **consent surface**, not a spinner and
    /// not an empty sheet: the honest answer to "what's new?" when nothing has
    /// been asked yet is "may I ask?".
    private func open() {
        guard consent?.isGranted == true else {
            isShowingConsent = true
            return
        }
        isShowingNotes = true
        load()
    }

    private func load() {
        store?.load(id, version: version, candidates: candidates)
    }

    /// Names the repository before the click, so what leaves the machine is
    /// visible in advance rather than disclosed after the fact.
    private var helpText: String {
        guard showsSlug, let slug = affordance.repositorySlug else {
            return "Ask GitHub what changed in this release"
        }
        return "Ask GitHub what changed in \(slug) \(version)"
    }
}

/// The package-detail entry point (D4 secondary).
///
/// Shown **only when a repository resolves**, which costs nothing to decide, so a
/// package nobody could ask about never grows a button that cannot work.
struct ReleaseNotesSection: View {
    let package: CatalogPackage
    let installedVersion: String?

    private var candidates: RepositoryCandidates { RepositoryCandidates(package) }

    var body: some View {
        // `isOutdated: true` here reads the affordance's *resolvability* half
        // only: on the detail surface the question is "can this be asked at all",
        // not "is an upgrade waiting".
        if ReleaseNotesAffordance(isOutdated: true, candidates: candidates).isOffered {
            Section {
                ReleaseNotesButton(
                    id: package.id,
                    displayName: package.displayName,
                    version: installedVersion ?? package.version,
                    candidates: candidates,
                    label: "What's new in \(installedVersion ?? package.version)?",
                    showsSlug: true
                )
                .accessibilityIdentifier("release-notes-section-button")
            } header: {
                Text("Release notes")
                    .font(.headline)
            }
            .accessibilityIdentifier("release-notes-section")
        }
    }
}

// MARK: - The credential seam in the environment

extension EnvironmentValues {
    /// The Keychain seam, held by the app and handed to the consent sheet.
    ///
    /// An environment value rather than a constructor parameter threaded through
    /// four views, and optional so a preview and a test host both render with it
    /// simply absent.
    @Entry var releaseNotesCredentials: (any ReleaseNotesCredentialStoring)?
}
