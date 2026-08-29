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
    /// npm's detection state, read by the Settings card and by the Source chip.
    /// A sibling of `brewDetection` rather than a widening of it: nothing about
    /// Homebrew's own detection changes.
    let npmDetection: NpmDetectionStore
    /// What npm reports. Read for the Source chip's availability and for the
    /// freshness the summary copy needs.
    let npm: NpmStore
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    /// Favorites, notes and snoozes. Passed down as a store rather than as a
    /// snapshot because the rows write to it as well as read from it.
    let metadata: MetadataStore
    let history: HistoryStore
    /// The vendored cask category catalog and the icon pipeline, both owned by
    /// the composition root like every other store — the cask pages read them,
    /// construct neither.
    let caskAssets: CaskBrowseAssets
    let caskIcons: CaskIconLoader
    /// Per-period Top Charts rankings, owned by the composition root like the
    /// assets above — the page reads it, constructs nothing.
    let caskCharts: CaskChartsStore
    /// The formula-configured sibling — see `cellarApp.formulaCharts`.
    let formulaCharts: CaskChartsStore
    let services: ServicesStore
    let servicesRefresher: ServicesRefreshCoordinator
    let taps: TapStore
    /// The per-package grant report, passed as the `@Observable` store rather
    /// than as a pre-computed value so every marker updates when it refreshes
    /// (package-trust DD-10).
    let trustGrants: TrustGrantStore
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
    /// Which category page `.caskCategory` shows — the data half of the one
    /// section whose page is not named by its case. Written by the sidebar's
    /// category rows, the cards' category labels, and the shelves' View All.
    @State private var caskCategoryID: String?
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

    /// Each list-and-detail section's own pane width, kept across launches.
    /// Per section rather than shared, because a categories rail and a package
    /// list earn different widths — dragging one must not move the other. The
    /// design draws 342; the divider makes each one the user's.
    ///
    /// A `@State` cache over per-section `UserDefaults` keys instead of
    /// `@AppStorage`, because `@AppStorage` cannot vary its key by section.
    /// The retired shared `shell.listPaneWidth` seeds a section's first read,
    /// so an existing user's dragged width carries over.
    @State private var listPaneWidths: [AppSection: Double] = [:]

    /// The design's 342 — except the two search surfaces, whose rows carry
    /// state chips and a trailing menu that 342 truncates; they open at 400.
    private static func defaultListPaneWidth(for section: AppSection) -> Double {
        section == .browse || section == .tapSearch ? 400 : 342
    }

    private static let legacyListPaneWidthKey = "shell.listPaneWidth"

    private func listPaneWidth(for section: AppSection) -> Double {
        if let width = listPaneWidths[section] { return width }
        let defaults = UserDefaults.standard
        let key = "shell.listPaneWidth.\(section.rawValue)"
        if defaults.object(forKey: key) != nil { return defaults.double(forKey: key) }
        if defaults.object(forKey: Self.legacyListPaneWidthKey) != nil {
            return defaults.double(forKey: Self.legacyListPaneWidthKey)
        }
        return Self.defaultListPaneWidth(for: section)
    }

    /// The current section's width as a binding, for the divider's drag.
    private var listPaneWidthBinding: Binding<Double> {
        Binding(
            get: { listPaneWidth(for: section) },
            set: { newValue in
                listPaneWidths[section] = newValue
                UserDefaults.standard.set(
                    newValue,
                    forKey: "shell.listPaneWidth.\(section.rawValue)"
                )
            }
        )
    }

    /// The native split view's column state: `.all` or `.detailOnly`. The
    /// system sidebar toggle drives it, and it is what moves that toggle from
    /// the sidebar's toolbar to the detail's when the column collapses.
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all

    /// How narrow and how wide the list pane may be dragged. The lower bound
    /// keeps every row affordance reachable; the upper leaves the detail pane
    /// worth having.
    private static let listPaneRange: ClosedRange<Double> = 260...600

    /// What the detail pane keeps before the list pane starts giving width
    /// back: roughly one grid column plus the pinned bar's icon-only minimum.
    private static let detailPaneReserve: Double = 480

    /// The list pane's rendered width: the user's dragged choice, narrowed —
    /// never below the range's floor — when the window cannot host it beside
    /// `detailPaneReserve`. The stored preference is untouched, so widening
    /// the window restores exactly the width the user picked.
    private func clampedListWidth(available: Double) -> Double {
        min(
            listPaneWidth(for: section),
            max(Self.listPaneRange.lowerBound, available - Self.detailPaneReserve)
        )
    }

    /// The sections whose left pane is the resizable list. A `Set` rather than
    /// a fourth `AppSection` switch on purpose: the placement suite pins the
    /// shell to exactly two exhaustive switches (content and detail).
    private static let listSections: Set<AppSection> = [
        .browse, .tapSearch, .caskCategory, .installed, .favorites, .updates,
        .taps,
    ]

    var body: some View {
        shell
            .mutationConfirmation(
                operations,
                currentForceEvidence: forceEvidence,
                confirmCleanup: confirmCleanup
            )
    }

    /// The design's window on the system's chassis: a native
    /// `NavigationSplitView` sidebar — material background, rounded corners,
    /// the toggle beside the traffic lights, the collapse animation — beside a
    /// toolbar-topped content area drawn on the app's own surfaces.
    ///
    /// Sections that keep a list-plus-detail arrangement render it *inside*
    /// their pane; single-surface sections take the whole width. Both panes sit
    /// in their own `NavigationStack` so the toolbar items and search fields
    /// the feature views still declare keep rendering while each section is
    /// ported to the design's own controls.
    private var shell: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            SidebarView(
                section: $section,
                installed: installed,
                metadata: metadata,
                services: services,
                security: security,
                taps: taps
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 228, max: 300)
        } detail: {
            Group {
                // Home, Search catalog and the installed lenses lead with the
                // discover pages' capsule card — title and shell controls, no
                // collection controls — pinned at the shell so it spans the
                // whole pane row.
                if Self.shellTitleBarSections.contains(section) {
                    paneArea.caskCollectionTopBarPinned {
                        // The sidebar's wording, not the toolbar's: the row a
                        // user clicked says "Search catalog", so the card it
                        // lands on says the same.
                        ShellTitleBar(
                            title: section.sidebarTitle,
                            countLabel: countLabel,
                            shellControls: shellHeaderControls,
                            leadingAccessories: shellTitleBarLeadingAccessories,
                            accessories: shellTitleBarAccessories
                        )
                    }
                } else {
                    paneArea
                }
            }
            // An inset rather than a sheet: a mutation is background work, and
            // a sheet would hold the app hostage while brew compiles. The bar
            // renders nothing at all when the centre is empty (design D10).
            // On the detail column, not the whole window: the sidebar column
            // does not yield to a window-wide bottom inset, so a bar there
            // paints over its Settings footer instead of above it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActivityBar(
                    center: operations,
                    isExpanded: $isActivityExpanded,
                    trustableTap: trustableTap(for:)
                )
            }
            .background(Theme.windowBackground)
            // Into the native toolbar row rather than a drawn strip: macOS
            // clips app content out of the titlebar region, so a custom strip
            // there stays clickable but never paints.
            .toolbar {
                ShellToolbarItems(
                    section: section,
                    showsPageChrome: !Self.pinnedHeaderSections.contains(section),
                    refresh: refresh,
                    isActivityExpanded: $isActivityExpanded
                )
            }
            // The design draws its own dark ground; the glass wash would sit
            // between it and the toolbar items.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        // The dark ground the sidebar's translucent material blurs over — this
        // is what tints the system sidebar to the design's palette.
        .containerBackground(for: .window) { Theme.windowBackground }
    }

    /// The pane row itself, extracted so the shell can pin a title bar over it
    /// for the sections that want one.
    private var paneArea: some View {
            // A GeometryReader rather than a plain stack: the pinned cask bars
            // give the detail pane a hard minimum width, and an HStack whose
            // children's minimums exceed the column overflows *centred* — which
            // slides the list pane under the sidebar. The list yields width
            // first, and whatever still cannot fit clips off the trailing edge.
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    if let detail = detailPane {
                        // The width lives on the pane, not on the view inside
                        // it: a fixed-width child inside a flexible pane is
                        // what centred the list and opened a gap whenever the
                        // detail column's empty state had nothing to stretch it.
                        // Every section with a detail pane is a list section:
                        // Health, the one flexible-beside-fixed layout, now
                        // opens its breakdown from the score's popover instead.
                        NavigationStack { content }
                            .frame(width: clampedListWidth(available: geometry.size.width))
                        PaneResizeDivider(width: listPaneWidthBinding, range: Self.listPaneRange)
                        NavigationStack { detail }
                            .frame(maxWidth: .infinity)
                    } else {
                        NavigationStack { content }
                    }
                }
                // Leading-aligned, not clipped: an overflowing pane row spills
                // off the window's own trailing edge, while the pinned cask
                // bars keep their rise above these bounds into the titlebar
                // region — which `.clipped()` here was cutting off entirely.
                .frame(width: geometry.size.width, alignment: .leading)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .home:
            HomeView(
                brewDetection: brewDetection,
                catalog: catalog,
                installed: installed,
                npmDetection: npmDetection,
                npm: npm,
                metadata: metadata,
                security: security,
                diskUsage: diskUsage,
                taps: taps,
                services: services,
                history: history,
                operations: operations,
                health: health,
                cleanup: cleanup,
                assets: caskAssets,
                iconLoader: caskIcons,
                section: $section,
                selection: $selection
            )
        case .browse:
            BrowseView(
                catalog: catalog,
                installed: installed,
                operations: operations,
                diskUsage: diskUsage,
                assets: caskAssets,
                iconLoader: caskIcons,
                selection: $selection
            )
        case .tapSearch:
            TapSearchView(
                taps: taps,
                installed: installed,
                catalog: catalog,
                operations: operations,
                assets: caskAssets,
                iconLoader: caskIcons,
                selection: $selection
            )
        case .caskBrowse:
            CaskBrowseView(
                catalog: catalog,
                installed: installed,
                operations: operations,
                assets: caskAssets,
                iconLoader: caskIcons,
                section: $section,
                onSelectCategory: openCategory,
                shellControls: shellHeaderControls
            )
        case .caskFeatured:
            CaskFeaturedView(
                catalog: catalog,
                installed: installed,
                operations: operations,
                assets: caskAssets,
                iconLoader: caskIcons,
                onSelectCategory: openCategory,
                shellControls: shellHeaderControls
            )
        case .caskTopCharts:
            CaskTopChartsView(
                catalog: catalog,
                installed: installed,
                operations: operations,
                assets: caskAssets,
                iconLoader: caskIcons,
                charts: caskCharts,
                onSelectCategory: openCategory,
                shellControls: shellHeaderControls
            )
        case .caskRecentlyAdded:
            CaskRecentlyAddedView(
                catalog: catalog,
                installed: installed,
                operations: operations,
                assets: caskAssets,
                iconLoader: caskIcons,
                onSelectCategory: openCategory,
                shellControls: shellHeaderControls
            )
        case .caskCategory:
            CaskCategoriesListView(catalog: catalog, selection: $caskCategoryID)
        case .formulaBrowse:
            FormulaBrowseView(
                catalog: catalog,
                installed: installed,
                operations: operations,
                assets: caskAssets,
                iconLoader: caskIcons,
                section: $section,
                shellControls: shellHeaderControls
            )
        case .formulaFeatured:
            FormulaFeaturedView(
                catalog: catalog,
                installed: installed,
                operations: operations,
                assets: caskAssets,
                iconLoader: caskIcons,
                shellControls: shellHeaderControls
            )
        case .formulaTopCharts:
            FormulaTopChartsView(
                catalog: catalog,
                installed: installed,
                operations: operations,
                assets: caskAssets,
                iconLoader: caskIcons,
                charts: formulaCharts,
                shellControls: shellHeaderControls
            )
        case .installed:
            InstalledListView(
                installed: installed,
                npmDetection: npmDetection,
                catalog: catalog,
                operations: operations,
                metadata: metadata,
                assets: caskAssets,
                iconLoader: caskIcons,
                selection: $selection
            )
        case .favorites:
            InstalledListView(
                installed: installed,
                npmDetection: npmDetection,
                catalog: catalog,
                operations: operations,
                metadata: metadata,
                assets: caskAssets,
                iconLoader: caskIcons,
                selection: $selection,
                lens: .favorites
            )
        case .updates:
            InstalledListView(
                installed: installed,
                npmDetection: npmDetection,
                catalog: catalog,
                operations: operations,
                metadata: metadata,
                assets: caskAssets,
                iconLoader: caskIcons,
                selection: $selection,
                lens: .updates
            )
        case .taps:
            TapsListView(
                taps: taps,
                trustGrants: trustGrants,
                operations: operations,
                selection: $tapSelection
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
                npmDetection: npmDetection,
                npm: npm,
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
                selection: $findingSelection,
                dismissals: dismissals,
                operations: operations,
                catalog: catalog,
                integrity: integrity,
                artifactLocations: artifactLocations
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
            SettingsView(brewDetection: brewDetection, npmDetection: npmDetection)
        }
    }

    /// The right-hand pane, or `nil` for a section the design draws full-width.
    private var detailPane: AnyView? {
        switch section {
        case .home, .caskBrowse, .caskFeatured, .caskTopCharts, .caskRecentlyAdded,
             .formulaBrowse, .formulaFeatured, .formulaTopCharts,
             .cleanup, .brewfile, .history, .settings:
            // The collection pages are full-width like CaskHub's own; nothing
            // here drives the shared package detail column.
            return nil
        case .caskCategory:
            // The one cask page that is not full-width: the categories list
            // pane drives this detail, the selected category's own page.
            return AnyView(
                CaskCategoryView(
                    catalog: catalog,
                    installed: installed,
                    operations: operations,
                    assets: caskAssets,
                    iconLoader: caskIcons,
                    categoryID: caskCategoryID,
                    shellControls: shellHeaderControls
                )
            )
        case .services:
            // No detail column: the dashboard's cards expand in place.
            return nil
        case .taps:
            return AnyView(
                TapDetailView(
                    taps: taps,
                    trustGrants: trustGrants,
                    installed: installed,
                    operations: operations,
                    tapName: tapSelection,
                    currentForceEvidence: forceEvidence,
                    showInInstalled: showInInstalled
                )
            )
        case .health:
            // No fixed rail: the weights table opens from the score's "?"
            // popover, so the dashboard takes the whole width.
            return nil
        case .security:
            // No detail column: the dashboard embeds the integrity section
            // and opens a finding in a sheet.
            return nil
        case .browse, .tapSearch, .installed, .favorites, .updates:
            // The same detail view for all of them: a package is a package,
            // and the catalog record is the thing worth reading about it. A
            // routable tap hit lands here through the *existing* resolution
            // order, by its exact `PackageID` — still no arm of its own here
            // (DD-4). Round 6 adds the tap inventory as an input, because that
            // order gained a third branch **inside** the shared view: catalog,
            // then receipt, then the names one installed tap published (DD-21).
            return AnyView(
                PackageDetailView(
                    catalog: catalog,
                    installed: installed,
                    operations: operations,
                    metadata: metadata,
                    diskUsage: diskUsage,
                    trustGrants: trustGrants,
                    taps: taps,
                    assets: caskAssets,
                    iconLoader: caskIcons,
                    id: selection,
                    selection: $selection
                )
            )
        }
    }

    /// The refusal recovery's candidate, in the same `@MainActor` idiom as
    /// `forceEvidence(for:)` below: a closure the drawer can call, over stores
    /// the drawer never sees (design DD-12).
    ///
    /// The identity is one Cellar typed itself — `ActivityItem.command.packageID`
    /// — and the candidate set is the `tap-info` snapshot Cellar already holds,
    /// so no byte of brew's refusal takes part in the answer.
    private func trustableTap(for package: PackageID?) -> TapName? {
        guard case .loaded = taps.state else { return nil }
        return UntrustedTapRecovery.trustableTap(forRefused: package, in: taps.inventory)
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

    /// The one category navigation every affordance shares: the sidebar's
    /// rows, the cards' labels, and the shelves' View All all land here.
    private func openCategory(_ id: String) {
        caskCategoryID = id
        section = .caskCategory
    }

    /// The sections whose pinned capsule bar is the whole header: the toolbar
    /// row shows no title and no controls for them — the bar names the page
    /// and carries the shared `ShellHeaderControls` itself. The discover pages
    /// pin their own collection bar; the rest get the shell's plain
    /// `ShellTitleBar` instead.
    private static let pinnedHeaderSections: Set<AppSection> = [
        .home, .browse, .tapSearch, .installed, .favorites, .updates, .services, .health, .security,
        .cleanup, .taps, .brewfile, .history, .settings,
        .caskBrowse, .caskFeatured, .caskTopCharts, .caskRecentlyAdded, .caskCategory,
        .formulaBrowse, .formulaFeatured, .formulaTopCharts,
    ]

    /// The subset whose bar the shell itself pins — the sections with no
    /// collection controls of their own.
    private static let shellTitleBarSections: Set<AppSection> = [
        .home, .browse, .tapSearch, .installed, .favorites, .updates, .services, .health, .security,
        .cleanup, .taps, .brewfile, .history, .settings,
    ]

    /// What the pinned bar counts, for the two sections that have a number
    /// worth showing.
    ///
    /// Each surface counts **its own** records: Search catalog counts catalog
    /// packages, and Search our taps counts what the installed third-party taps
    /// publish, through the same projection that answers its listing so the two
    /// can never disagree (DD-17).
    /// Deliberately **not** a `switch`: the placement suite treats any switch
    /// with two or more `AppSection` labels as one of the shell's exhaustive
    /// section switches, and this is a two-section special case rather than a
    /// decision every future section must make.
    private var countLabel: String? {
        if section == .browse {
            return "\(catalog.packageCount.formatted()) packages"
        }
        if section == .tapSearch {
            return "\(TapPackageSearch.packageCount(inventory: taps.inventory).formatted()) packages"
        }
        return nil
    }

    /// The section-owned control the pinned bar draws before the shared pair.
    private var shellTitleBarLeadingAccessories: AnyView? {
        switch section {
        case .history:
            AnyView(HistorySearchField(history: history))
        default:
            nil
        }
    }

    /// The section-owned chips the pinned bar carries beside the shared pair —
    /// each one a self-contained accessory view the section's own file defines.
    ///
    /// Exhaustive with no `default:`, like every other `AppSection` switch: a
    /// new section must decide — visibly, at compile time — whether it carries
    /// a chip of its own.
    private var shellTitleBarAccessories: AnyView? {
        switch section {
        case .history:
            AnyView(HistoryShellAccessories(history: history))
        case .updates:
            AnyView(UpdatesShellAccessories(operations: operations))
        case .health, .home, .browse, .tapSearch, .installed, .favorites, .taps, .services,
             .cleanup, .security, .brewfile, .settings,
             .caskBrowse, .caskFeatured, .caskTopCharts, .caskRecentlyAdded, .caskCategory,
             .formulaBrowse, .formulaFeatured, .formulaTopCharts:
            nil
        }
    }

    /// The one Refresh/Activity pair the cask pages embed in their bars — the
    /// same closure and binding the toolbar row renders everywhere else.
    private var shellHeaderControls: ShellHeaderControls {
        ShellHeaderControls(refresh: refresh, isActivityExpanded: $isActivityExpanded)
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
