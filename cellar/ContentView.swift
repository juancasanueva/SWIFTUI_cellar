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
import SecurityKit
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
    let cleanup: CleanupStore
    let cleanupPreviewSource: any CleanupPreviewSourcing
    let security: SecurityStore
    let securityConsent: SecurityConsentPreference
    let advisoryCredentials: any AdvisoryCredentialStoring
    let dismissals: DismissalStore
    let integrity: ArtifactIntegrityStore
    /// The brew-managed artifacts worth assessing, built by `ArtifactLocator`
    /// from Homebrew's own roots. Empty until detection resolves.
    let artifactLocations: [ArtifactLocation]

    @State private var section: AppSection = .browse
    @State private var selection: PackageID?
    /// A finding carries its own identity — a package plus an advisory — because
    /// the same advisory can apply to two installed packages and they are two
    /// different rows.
    @State private var findingSelection: SecurityFindingSelection?
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
            .mutationConfirmation(
                operations,
                currentForceEvidence: forceEvidence,
                confirmCleanup: confirmCleanup
            )
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
                CleanupView(
                    detection: brewDetection,
                    installed: installed,
                    diskUsage: diskUsage,
                    cleanup: cleanup,
                    operations: operations
                )
                    .navigationSplitViewColumnWidth(min: 360, ideal: 520)
            case .security:
                SecurityView(
                    security: security,
                    consent: securityConsent,
                    credentials: advisoryCredentials,
                    selection: $findingSelection
                )
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
            case .security:
                if findingSelection == nil, artifactLocations.isEmpty == false {
                    // The integrity half occupies the detail column whenever no
                    // finding is selected: it is a second view of the same
                    // inventory rather than a separate destination.
                    ArtifactIntegrityPanel(store: integrity, locations: artifactLocations)
                } else {
                        SecurityFindingDetail(
                        selection: findingSelection,
                        security: security,
                        dismissals: dismissals,
                        operations: operations,
                        catalog: catalog
                    )
                }
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

    private func confirmCleanup(_ request: OperationCenter.ConfirmationRequest) {
        operations.confirmCleanup(
            request,
            source: cleanupPreviewSource,
            detection: brewDetection.state,
            diskUsage: cleanupDiskUsageContext,
            publish: cleanup.adopt
        )
    }

    private var cleanupDiskUsageContext: CleanupDiskUsageContext? {
        guard let snapshot = diskUsage.visibleSnapshot else { return nil }
        return CleanupDiskUsageContext(snapshot: snapshot, expectedRoots: snapshot.roots)
    }
}
