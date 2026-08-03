//
//  ServicesListView.swift
//  cellar
//

import BrewClient
import BrewProcess
import SwiftUI

/// The background services Homebrew manages.
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
    /// Passed to the rows so each one's controls submit through the same
    /// guarded path; the list itself submits nothing.
    let operations: OperationCenter
    @Binding var selection: String?

    var body: some View {
        List(services.services, selection: $selection) { service in
            ServiceRow(service: service, operations: operations)
                .tag(service.id)
        }
        .overlay {
            if services.services.isEmpty {
                emptyState
            }
        }
        .navigationTitle(AppSection.services.title)
        .onAppear { refresher.setVisible(true) }
        .onDisappear { refresher.setVisible(false) }
        .onChange(of: selection) { _, name in
            // The detail probe runs here and only here, which is what keeps a
            // poll tick from fetching detail for anything.
            Task { await services.select(name) }
        }
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
        selection: $selection
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
