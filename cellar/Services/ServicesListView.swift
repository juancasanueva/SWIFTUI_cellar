//
//  ServicesListView.swift
//  cellar
//

import BrewClient
import BrewProcess
import SwiftUI

/// The background services Homebrew manages, as one full-width surface: a
/// running/stopped summary, then one card per service with its five verbs on
/// the card and its detail behind a click.
///
/// The view **reports** visibility; it never decides it. `onAppear` and
/// `onDisappear` cover selecting another section and closing the window, and
/// `scenePhase` in `cellarApp` covers hiding the app. The coordinator owns what
/// that means — a five-second poll while visible, and nothing at all while not.
///
/// There is no manual refresh control, for the same reason the Installed list
/// has none: while this surface is on screen the list is never more than five
/// seconds old, so a button could only ever duplicate work already scheduled.
struct ServicesListView: View {
    let services: ServicesStore
    let refresher: ServicesRefreshCoordinator
    /// The cards' controls submit through the same guarded path; the list
    /// itself submits nothing.
    let operations: OperationCenter
    @Binding var selection: String?
    /// The seam. `BrewClient` owns the protocol; this target owns the single
    /// `NSWorkspace` implementation.
    var opener: any LogFileOpening = WorkspaceLogFileOpener()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !services.services.isEmpty {
                    summary
                }
                ForEach(services.services) { service in
                    ServiceCard(
                        service: service,
                        services: services,
                        operations: operations,
                        opener: opener,
                        selection: $selection
                    )
                }
            }
            .padding(EdgeInsets(top: 24, leading: 30, bottom: 34, trailing: 30))
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .overlay {
            if services.services.isEmpty {
                emptyState
            }
        }
        .background(Theme.windowBackground)
        .onAppear { refresher.setVisible(true) }
        .onDisappear { refresher.setVisible(false) }
        .onChange(of: selection) { _, name in
            // The detail probe runs here and only here, which is what keeps a
            // poll tick from fetching detail for anything.
            Task { await services.select(name) }
        }
    }

    /// The counts, from the same projection the cards render. Failed earns its
    /// own count only when there is one — a permanent zero would read as a
    /// category this Mac is expected to fill.
    private var summary: some View {
        let tones = services.services.map(\.status.tone)
        let running = tones.filter { $0 == .running }.count
        let failed = tones.filter { $0 == .failed }.count
        let stopped = tones.count - running - failed
        return HStack(spacing: 16) {
            countLabel(running, "running", dot: Theme.successBase)
            countLabel(stopped, "stopped", dot: Color.white.opacity(0.3))
            if failed > 0 {
                countLabel(failed, "failed", dot: Theme.dangerBase)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 4)
    }

    private func countLabel(_ count: Int, _ word: String, dot: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text("\(count)")
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(word)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(word)")
    }

    /// Why the list is empty, decided by `ServicesLoadState.emptyState` rather
    /// than by this view.
    private var emptyState: some View {
        ServicesEmptyStateView(state: services.state.emptyState)
    }
}

/// Why the services list is empty — which is never the same reason twice.
///
/// `InstalledEmptyState`'s shape, and for the same reason: `idle`, `loading`
/// and `failed` are not an absence, and rendering them as one tells the user
/// that brew is managing nothing when nobody has asked yet, or when the asking
/// failed. Absent brew stays **guidance, not an error**: there is nothing to
/// retry and nothing has failed, so it offers the install one-liner rather than
/// a red banner (SM11).
///
/// The words and the mapping both live in `ServicesPresentation`, inside the
/// `swift test` inner loop; this view owns only the symbols and the layout.
private struct ServicesEmptyStateView: View {
    let state: ServicesEmptyState

    var body: some View {
        switch state {
        case .reading, .nothingManaged:
            ContentUnavailableView(
                state.title,
                systemImage: AppSection.services.systemImage,
                description: Text(state.message)
            )

        case .brewAbsent(let absence):
            ContentUnavailableView {
                Label(state.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(state.message)
            } actions: {
                if let guidance = absence.installGuidance {
                    CopyCommandButton(text: guidance.installCommand)
                }
            }

        case .failed:
            ContentUnavailableView(
                state.title,
                systemImage: "exclamationmark.triangle",
                description: Text(state.message)
            )
        }
    }
}

#Preview {
    @Previewable @State var selection: String?
    return ServicesListView(
        services: ServicesStore(),
        refresher: ServicesRefreshCoordinator(store: ServicesStore()),
        operations: OperationCenter(),
        selection: $selection,
        opener: NoLogFileOpening()
    )
}

#Preview("Reading") {
    ServicesEmptyStateView(state: .reading)
}

#Preview("Failed") {
    ServicesEmptyStateView(state: ServicesLoadState.failed(.malformedPayload).emptyState)
}

#Preview("Absent") {
    ServicesEmptyStateView(state: .brewAbsent(.notInstalled(.standard)))
}
