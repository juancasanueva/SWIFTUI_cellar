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

/// The package-detail entry point (D4 secondary), rendered **in the pane**.
///
/// The design shows release notes inline rather than in a dialog, and this view
/// follows it — without loosening the egress rule: nothing is fetched until the
/// one explicit button is pressed, the fetch is `store.load` in this file and
/// nowhere else, and there is no `.task`, `.onAppear` or `.onChange` anywhere
/// here. The pane renders whatever the store already holds; a package never
/// asked about renders the button, not a request.
///
/// Shown **only when a repository resolves**, which costs nothing to decide, so a
/// package nobody could ask about never grows a button that cannot work.
struct ReleaseNotesSection: View {
    let package: CatalogPackage
    let installedVersion: String?

    @Environment(ReleaseNotesStore.self) private var store: ReleaseNotesStore?
    @Environment(ReleaseNotesConsentPreference.self)
    private var consent: ReleaseNotesConsentPreference?
    @Environment(\.releaseNotesCredentials) private var credentials
    @Environment(ThemeStore.self) private var theme

    @State private var isShowingConsent = false

    private var candidates: RepositoryCandidates { RepositoryCandidates(package) }
    private var version: String { installedVersion ?? package.version }

    /// `isOutdated: true` reads the affordance's *resolvability* half only: on
    /// the detail surface the question is "can this be asked at all", not "is
    /// an upgrade waiting".
    private var affordance: ReleaseNotesAffordance {
        ReleaseNotesAffordance(isOutdated: true, candidates: candidates)
    }

    var body: some View {
        if affordance.isOffered {
            VStack(alignment: .leading, spacing: 14) {
                headerRow
                switch store?.state(for: package.id) ?? .idle {
                case .idle:
                    fetchButton
                case .loading, .loaded, .failed:
                    ReleaseNotesContent(
                        state: store?.state(for: package.id) ?? .idle,
                        onOpenConsent: { isShowingConsent = true },
                        onRetry: { load() }
                    )
                    .padding(EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20))
                    .frame(maxWidth: 840, alignment: .topLeading)
                    .themeCard(fill: Color.white.opacity(0.02), radius: 10)
                }
            }
            .accessibilityIdentifier("release-notes-section")
            .sheet(isPresented: $isShowingConsent) {
                if let consent, let credentials {
                    ReleaseNotesConsentSheet(
                        consent: consent,
                        credentials: credentials,
                        rateLimit: store?.rateLimit
                    )
                }
            }
        } else {
            Text("Release notes aren't available: no repository resolves from this package's published URLs.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.45))
                .accessibilityIdentifier("release-notes-section")
        }
    }

    /// The design's header row: the section name, the repository the notes
    /// come from, and the GitHub link once there is a release to link to.
    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Release notes")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let slug = affordance.repositorySlug {
                Text(slug)
                    .font(Theme.mono(11))
                    .foregroundStyle(Color.white.opacity(0.34))
            }
            Spacer(minLength: 0)
            if let link = browsableLink {
                Link(destination: link) {
                    Text("View on GitHub")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            Theme.controlFill,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .accessibilityIdentifier("release-notes-github-link")
            }
        }
        .frame(maxWidth: 840)
    }

    /// The one trigger (D4): an explicit accent button naming what will be
    /// asked, and of whom, before anything leaves the machine.
    private var fetchButton: some View {
        Button {
            guard consent?.isGranted == true else {
                isShowingConsent = true
                return
            }
            load()
        } label: {
            Text("What's new in \(version)?")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.windowBackground)
                .padding(.horizontal, 14)
                .frame(height: 29)
                .background(theme.base, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityIdentifier("release-notes-section-button")
    }

    private func load() {
        store?.load(package.id, version: version, candidates: candidates)
    }

    private var browsableLink: URL? {
        guard let state = store?.state(for: package.id), let outcome = state.outcome else { return nil }
        return ReleaseNotesPresentation(outcome: outcome).browsableLink
    }

    /// Names the repository before the click, so what leaves the machine is
    /// visible in advance rather than disclosed after the fact.
    private var helpText: String {
        guard let slug = affordance.repositorySlug else {
            return "Ask GitHub what changed in this release"
        }
        return "Ask GitHub what changed in \(slug) \(version)"
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
