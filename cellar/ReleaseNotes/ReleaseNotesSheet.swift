//
//  ReleaseNotesSheet.swift
//  cellar
//

import Catalog
import ReleaseNotes
import SwiftUI

/// What changed in the release you are about to install.
///
/// Presentation only. Every decision this sheet appears to make — which of the
/// five outcomes this is, what sentence it deserves, whether a token would help,
/// whether a link may be followed — was made in `ReleaseNotesPresentation` or in
/// `CellarCore`, where it is testable without a view.
///
/// Two things it deliberately does not do: it never fetches a remote image, and
/// it never follows a link on its own. A release body is attacker-authored text,
/// and every `Link` here has already been through the http/https allowlist.
struct ReleaseNotesSheet: View {
    let packageName: String
    let version: String
    let state: ReleaseNotesState
    /// Shown when the user has not consented yet, so a refusal is an invitation
    /// rather than a dead end.
    var onOpenConsent: () -> Void = {}
    var onRetry: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ReleaseNotesContent(state: state, onOpenConsent: onOpenConsent, onRetry: onRetry)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider()

            HStack {
                if let presentation, let link = presentation.browsableLink {
                    Link("Open on GitHub", destination: link)
                        .accessibilityIdentifier("release-notes-github-link")
                }
                Spacer(minLength: 0)
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 480)
        .accessibilityIdentifier("release-notes-sheet")
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(packageName) \(version)")
                .font(.title3.bold())
            if let presentation {
                Text(presentation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("release-notes-detail")
            }
        }
    }

    private var presentation: ReleaseNotesPresentation? {
        state.outcome.map(ReleaseNotesPresentation.init(outcome:))
    }
}

/// The rendered outcome, shared by the row's sheet and the detail pane.
///
/// Presentation only, exactly like the sheet around it: which of the outcomes
/// this is and what it deserves to say was decided in
/// `ReleaseNotesPresentation`. It fetches nothing — both callbacks are handed
/// in by the one file allowed to start work.
struct ReleaseNotesContent: View {
    let state: ReleaseNotesState
    var onOpenConsent: () -> Void = {}
    var onRetry: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Asking GitHub…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("release-notes-loading")
        case .loaded, .failed:
            if let presentation {
                settled(presentation)
            }
        }
    }

    @ViewBuilder
    private func settled(_ presentation: ReleaseNotesPresentation) -> some View {
        Text(presentation.headline)
            .font(.headline)
            .accessibilityIdentifier("release-notes-headline")

        if let rendered = presentation.renderedBody {
            if rendered.blocks.isEmpty {
                // A matched release whose body is empty is still a matched
                // release. Saying so is what keeps it distinct from the two
                // absences.
                Text("This release was published without release notes.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("release-notes-empty-body")
            } else {
                ForEach(Array(rendered.blocks.enumerated()), id: \.offset) { _, block in
                    Text(block)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if rendered.degradedConstructs.isEmpty == false {
                    degradationNote(rendered)
                }
            }
        } else {
            Text(presentation.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if presentation.needsConsent {
            Button("Set up release notes…", action: onOpenConsent)
                .accessibilityIdentifier("release-notes-open-consent")
        }

        if presentation.isRateLimited {
            rateLimited(presentation)
        } else if presentation.outcome.failure != nil, presentation.needsConsent == false {
            Button("Try again", action: onRetry)
                .accessibilityIdentifier("release-notes-retry")
        }

        if let lastGood = state.lastGood, state.failure != nil {
            Text("Showing the last notes Cellar fetched for \(lastGood.release?.tagName ?? "this package").")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Told rather than hidden: a table rendered as pipes looks like a rendering
    /// bug, and a reader who knows it degraded can open the release on GitHub.
    @ViewBuilder
    private func degradationNote(_ rendered: RenderedReleaseNote) -> some View {
        Text(
            "Some formatting is shown as plain text: "
                + rendered.degradedConstructs.map(\.rawValue).sorted().joined(separator: ", ")
                + "."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("release-notes-degraded")
    }

    /// The one state where a vague sentence would actively mislead. It names the
    /// reset time and offers the token, and it never reads as "no release notes".
    @ViewBuilder
    private func rateLimited(_ presentation: ReleaseNotesPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reset = presentation.resetAt {
                Text("The limit resets at \(reset.formatted(date: .omitted, time: .shortened)).")
                    .accessibilityIdentifier("release-notes-rate-limit-reset")
            }
            if presentation.offersTokenAffordance {
                Button("Add a GitHub token…", action: onOpenConsent)
                    .accessibilityIdentifier("release-notes-rate-limit-token")
            }
        }
        // `.contain` keeps the reset/token identifiers reachable: without it
        // this container identifier replaces every child's (the A9 gotcha,
        // m5-brewfile).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("release-notes-rate-limited")
    }

    private var presentation: ReleaseNotesPresentation? {
        state.outcome.map(ReleaseNotesPresentation.init(outcome:))
    }
}
