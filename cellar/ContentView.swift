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
    /// The AppKit seam an import reads through, chosen once in the composition
    /// root so the Taps list holds no launch-argument knowledge (design DD4).
    let brewfileSourceChooser: any BrewfileSourceChoosing
    /// The **two** readings the Health section owns. Every other signal it
    /// renders is one of the stores above, read where it already lives.
    let health: HealthStore
    let security: SecurityStore
    let securityConsent: SecurityConsentPreference
    let advisoryCredentials: any AdvisoryCredentialStoring
    let dismissals: DismissalStore
    let integrity: ArtifactIntegrityStore
    /// The brew-managed artifacts worth assessing, built by `ArtifactLocator`
    /// from Homebrew's own roots. Empty until detection resolves.
    let artifactLocations: [ArtifactLocation]
    /// The launch-and-activation refresh, offered again behind the toolbar's
    /// Refresh button. Injected so the shell owns no refresh pipeline.
    var refresh: @MainActor () async -> Void = {}

    @State private var section: AppSection = .home
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

    /// The list pane's width, shared by every list-and-detail section and kept
    /// across launches. The design draws 342; the divider makes it the user's.
    @AppStorage("shell.listPaneWidth") private var listPaneWidth = 342.0

    /// How narrow and how wide the list pane may be dragged. The lower bound
    /// keeps every row affordance reachable; the upper leaves the detail pane
    /// worth having.
    private static let listPaneRange: ClosedRange<Double> = 260...600

    /// The sections whose left pane is the resizable list. A `Set` rather than
    /// a fourth `AppSection` switch on purpose: the placement suite pins the
    /// shell to exactly two exhaustive switches (content and detail).
    private static let listSections: Set<AppSection> = [
        .discover, .browse, .installed, .favorites, .updates,
        .taps, .services, .security,
    ]

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

    /// The design's window: a fixed custom sidebar beside a toolbar-topped
    /// content area, drawn on the app's own surfaces rather than system chrome.
    ///
    /// Sections that keep a list-plus-detail arrangement render it *inside*
    /// their pane; single-surface sections take the whole width. Both panes sit
    /// in their own `NavigationStack` so the toolbar items and search fields
    /// the feature views still declare keep rendering while each section is
    /// ported to the design's own controls.
    private var shell: some View {
        HStack(spacing: 0) {
            SidebarView(
                section: $section,
                installed: installed,
                metadata: metadata,
                services: services,
                security: security,
                taps: taps
            )
            VStack(spacing: 0) {
                ShellToolbar(
                    section: section,
                    refresh: refresh,
                    isActivityExpanded: $isActivityExpanded
                )
                HStack(spacing: 0) {
                    if let detail = detailPane {
                        // The width lives on the pane, not on the view inside
                        // it: a fixed-width child inside a flexible pane is
                        // what centred the list and opened a gap whenever the
                        // detail column's empty state had nothing to stretch it.
                        if Self.listSections.contains(section) {
                            NavigationStack { content }
                                .frame(width: listPaneWidth)
                            PaneResizeDivider(width: $listPaneWidth, range: Self.listPaneRange)
                            NavigationStack { detail }
                                .frame(maxWidth: .infinity)
                        } else {
                            // Health: a flexible dashboard beside its fixed
                            // breakdown rail.
                            NavigationStack { content }
                                .frame(maxWidth: .infinity)
                            Rectangle().fill(Theme.hairline).frame(width: 0.5)
                            NavigationStack { detail }
                        }
                    } else {
                        NavigationStack { content }
                    }
                }
            }
        }
        .background(Theme.windowBackground)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .home:
            HomeView(
                brewDetection: brewDetection,
                catalog: catalog,
                installed: installed,
                metadata: metadata,
                security: security,
                diskUsage: diskUsage,
                taps: taps,
                services: services,
                history: history,
                operations: operations,
                section: $section,
                selection: $selection
            )
        case .discover:
            DiscoverView(catalog: catalog, selection: $selection)
        case .browse:
            BrowseView(
                catalog: catalog,
                installed: installed,
                operations: operations,
                diskUsage: diskUsage,
                selection: $selection
            )
        case .installed:
            InstalledListView(
                installed: installed,
                catalog: catalog,
                operations: operations,
                metadata: metadata,
                selection: $selection
            )
        case .favorites:
            InstalledListView(
                installed: installed,
                catalog: catalog,
                operations: operations,
                metadata: metadata,
                selection: $selection,
                lens: .favorites
            )
        case .updates:
            InstalledListView(
                installed: installed,
                catalog: catalog,
                operations: operations,
                metadata: metadata,
                selection: $selection,
                lens: .updates
            )
        case .taps:
            TapsListView(
                taps: taps,
                operations: operations,
                // Both read-only, and both snapshots the app is already
                // holding: the Brewfile diff is a pure projection over them
                // and forces no re-acquisition.
                installed: installed,
                detection: brewDetection.state,
                selection: $tapSelection,
                sourceChooser: brewfileSourceChooser
            )
        case .services:
            ServicesListView(
                services: services,
                refresher: servicesRefresher,
                operations: operations,
                selection: $serviceSelection
            )
        case .cleanup:
            CleanupView(
                detection: brewDetection,
                installed: installed,
                diskUsage: diskUsage,
                cleanup: cleanup,
                operations: operations
            )
        case .health:
            HealthView(
                health: health,
                brewDetection: brewDetection,
                // Six of the eight signals, read where they already live. The
                // section holds none of them and refreshes none of them.
                installed: installed,
                metadata: metadata,
                security: security,
                cleanup: cleanup,
                diskUsage: diskUsage,
                operations: operations
            )
        case .security:
            SecurityView(
                security: security,
                consent: securityConsent,
                credentials: advisoryCredentials,
                selection: $findingSelection
            )
        case .brewfile:
            BrewfileSectionView(
                taps: taps,
                installed: installed,
                detection: brewDetection.state,
                operations: operations,
                sourceChooser: brewfileSourceChooser
            )
        case .history:
            HistoryView(history: history)
        case .settings:
            SettingsView(brewDetection: brewDetection)
        }
    }

    /// The right-hand pane, or `nil` for a section the design draws full-width.
    private var detailPane: AnyView? {
        switch section {
        case .home, .cleanup, .brewfile, .history, .settings:
            return nil
        case .services:
            return AnyView(ServiceDetailView(services: services))
        case .taps:
            return AnyView(
                TapDetailView(
                    taps: taps,
                    installed: installed,
                    operations: operations,
                    tapName: tapSelection,
                    currentForceEvidence: forceEvidence,
                    showInInstalled: showInInstalled
                )
            )
        case .health:
            // The weights table — the surface that makes the number
            // arguable, rather than a second copy of the rows.
            return AnyView(HealthBreakdownPanel(health: health).frame(width: 380))
        case .security:
            if findingSelection == nil, artifactLocations.isEmpty == false || integrity.reports.isEmpty == false {
                // The integrity half occupies the detail column whenever no
                // finding is selected: it is a second view of the same
                // inventory rather than a separate destination.
                return AnyView(ArtifactIntegrityPanel(store: integrity, locations: artifactLocations))
            }
            return AnyView(
                SecurityFindingDetail(
                    selection: findingSelection,
                    security: security,
                    dismissals: dismissals,
                    operations: operations,
                    catalog: catalog
                )
            )
        case .discover, .browse, .installed, .favorites, .updates:
            // The same detail view for all of them: a package is a package,
            // and the catalog record is the thing worth reading about it.
            return AnyView(
                PackageDetailView(
                    catalog: catalog,
                    installed: installed,
                    operations: operations,
                    metadata: metadata,
                    diskUsage: diskUsage,
                    id: selection,
                    selection: $selection
                )
            )
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
