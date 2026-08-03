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
    @Binding var selection: String?

    var body: some View {
        List(services.services, selection: $selection) { service in
            ServiceRow(service: service)
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

    /// Absence is guidance, not an error state — the same guidance the rest of
    /// the app surfaces, read from the same `InstalledAbsence`.
    @ViewBuilder
    private var emptyState: some View {
        if let absence = services.absence {
            ContentUnavailableView {
                Label(absence.title, systemImage: "exclamationmark.triangle")
            } description: {
                Text(absence.explanation)
            } actions: {
                if let guidance = absence.installGuidance {
                    CopyCommandButton(text: guidance.installCommand)
                }
            }
        } else {
            ContentUnavailableView(
                "No services",
                systemImage: AppSection.services.systemImage,
                description: Text("Homebrew is not managing any background services on this Mac.")
            )
        }
    }
}

#Preview {
    @Previewable @State var selection: String?
    return ServicesListView(
        services: ServicesStore(),
        refresher: ServicesRefreshCoordinator(store: ServicesStore()),
        selection: $selection
    )
}
