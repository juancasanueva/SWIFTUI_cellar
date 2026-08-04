//
//  ContentView.swift
//  cellar
//
//  Created by Juan Casanueva on 01/08/2026.
//

import BrewClient
import BrewProcess
import Catalog
import DiskUsage
import Persistence
import SwiftUI

/// The three-column shell: sections, list, detail.
///
/// The detail column is driven by a `PackageID` rather than a `CatalogPackage`
/// so a sync that replaces the snapshot mid-browse re-resolves the selection
/// against the new catalog instead of showing a stale copy.
struct ContentView: View {
    let brewDetection: BrewDetectionStore
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    /// Favorites, notes and snoozes. Passed down as a store rather than as a
    /// snapshot because the rows write to it as well as read from it.
    let metadata: MetadataStore
    let history: HistoryStore
    let services: ServicesStore
    let servicesRefresher: ServicesRefreshCoordinator
    let taps: TapStore
    let diskUsage: DiskUsageStore

    @State private var section: AppSection = .browse
    @State private var selection: PackageID?
    /// Services carry their own identity, not a `PackageID`: a service is its
    /// own entity and never enters the package projection (SM12).
    @State private var serviceSelection: String?
    @State private var tapSelection: String?
    @State private var isActivityExpanded = false

    var body: some View {
        shell
            // An inset rather than a sheet: a mutation is background work, and a
            // sheet would hold the app hostage while brew compiles. The bar
            // renders nothing at all when the centre is empty (design D10).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActivityBar(center: operations, isExpanded: $isActivityExpanded)
            }
            .mutationConfirmation(operations, currentForceEvidence: forceEvidence)
    }

    private var shell: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } content: {
            switch section {
            case .home:
                HomeView(brewDetection: brewDetection, catalog: catalog)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 480)
            case .browse:
                BrowseView(
                    catalog: catalog,
                    installed: installed,
                    operations: operations,
                    selection: $selection
                )
                .navigationSplitViewColumnWidth(min: 280, ideal: 360)
            case .installed:
                InstalledListView(
                    installed: installed,
                    catalog: catalog,
                    operations: operations,
                    metadata: metadata,
                    selection: $selection
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
            case .taps:
                TapsListView(
                    taps: taps,
                    operations: operations,
                    selection: $tapSelection
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
            case .services:
                ServicesListView(
                    services: services,
                    refresher: servicesRefresher,
                    operations: operations,
                    selection: $serviceSelection
                )
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
            case .cleanup:
                CleanupView(detection: brewDetection, installed: installed, store: diskUsage)
                    .navigationSplitViewColumnWidth(min: 360, ideal: 520)
            case .history:
                HistoryView(history: history)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 460)
            }
        } detail: {
            switch section {
            case .home:
                BrewDetectionSummary(state: brewDetection.state)
            case .services:
                ServiceDetailView(services: services)
            case .taps:
                TapDetailView(
                    taps: taps,
                    installed: installed,
                    operations: operations,
                    tapName: tapSelection,
                    currentForceEvidence: forceEvidence,
                    showInInstalled: showInInstalled
                )
            case .cleanup:
                ContentUnavailableView(
                    "Storage visibility",
                    systemImage: AppSection.cleanup.systemImage,
                    description: Text("Expand a package to inspect its installed versions.")
                )
            case .history:
                // The list column already carries the whole record; a second
                // pane would only repeat it.
                ContentUnavailableView(
                    "History",
                    systemImage: AppSection.history.systemImage,
                    description: Text("Every package change Cellar made, newest first.")
                )
            case .browse, .installed:
                // The same detail view for both: a package is a package, and
                // the catalog record is the thing worth reading about it.
                PackageDetailView(
                    catalog: catalog,
                    installed: installed,
                    operations: operations,
                    metadata: metadata,
                    id: selection,
                    selection: $selection
                )
            }
        }
    }

    private func forceEvidence(for tap: TapName) -> ForceUntapEvidence? {
        guard case .loaded = taps.state,
              case .loaded = installed.state,
              taps.inventory.taps.contains(where: { $0.name == tap.rawValue })
        else { return nil }

        let affected = Set(
            installed.inventory.packages.lazy
                .filter { $0.tap == tap.rawValue }
                .map(\.id)
        )
        guard !affected.isEmpty else { return nil }
        return ForceUntapEvidence(tap: tap, affected: affected, isComplete: true)
    }

    private func showInInstalled(_ id: PackageID) {
        selection = id
        section = .installed
    }
}

#Preview {
    let services = ServicesStore()
    return ContentView(
        brewDetection: BrewDetectionStore(),
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory),
        installed: InstalledStore(),
        operations: OperationCenter(),
        metadata: MetadataStore(container: nil),
        history: HistoryStore(container: nil),
        services: services,
        servicesRefresher: ServicesRefreshCoordinator(store: services),
        taps: TapStore(),
        diskUsage: DiskUsageStore(
            cache: DiskUsageCache(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-disk.json"))
        )
    )
}
