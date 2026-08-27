//
//  CaskBrowseView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The CaskHub storefront on Cellar's skin: a house pick, curated shelves, and
/// a grid of cards — full-width, like the design's own browse page.
///
/// Presentation only. What is eligible, what leads each shelf, and what the
/// house pick is are all settled in `CellarCore`'s projection and asserted
/// there; this view renders `catalog.caskBrowse` and submits verbs.
struct CaskBrowseView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    @Binding var section: AppSection
    /// Where a category navigation lands, handed a category id — the card
    /// labels' closure and the category shelves' View All, one path. The shell
    /// sets the id beside the section; `nil` leaves both affordances inert.
    var onSelectCategory: ((String) -> Void)? = nil
    /// The shell's Refresh/Activity pair, rendered inside the pinned bar —
    /// see `CaskCollectionTopBar.shellControls`.
    var shellControls: ShellHeaderControls? = nil

    /// The grid/list choice, kept across launches like the shell's pane width.
    @AppStorage("casks.viewMode") private var viewMode: CaskBrowseViewMode = .list

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — typing filters a few thousand cards, so
    /// the filter runs per pause rather than per keystroke.
    @State private var appliedSearch = ""

    private var content: CaskBrowseContent { catalog.caskBrowse }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if content == .empty {
                    CaskCatalogSyncingNote()
                } else if appliedSearch.isEmpty {
                    if let housePick = content.housePick {
                        heroCard(for: housePick)
                    }
                    ForEach(Array(content.sections.enumerated()), id: \.element.id) { index, shelf in
                        // A hairline between shelves, never before the first:
                        // the hero card already separates it from the top bar.
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 0.5)
                                .padding(.vertical, 12)
                        }
                        shelfView(shelf)
                    }
                } else {
                    searchResults
                }
            }
            .frame(maxWidth: 1086)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 48, trailing: 20))
        }
        .caskCollectionTopBarPinned { topBar }
        .background(Color.white.opacity(0.014))
        .task { await assets.load() }
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .accessibilityIdentifier("cask-browse-page")
    }

    // MARK: - Top bar

    private var topBar: some View {
        CaskCollectionTopBar(
            title: "Browse",
            countLabel: "\(content.caskCount.formatted()) casks",
            viewMode: $viewMode,
            searchText: $searchText,
            shellControls: shellControls
        )
    }

    // MARK: - Hero

    private func heroCard(for housePick: CatalogPackage) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("✷ HOUSE PICK")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(2)
                    .foregroundStyle(theme.base)
                Text(housePick.displayName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let desc = housePick.desc {
                    Text(desc)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textBody)
                        .lineLimit(2)
                }
                HStack(spacing: 14) {
                    heroAction(for: housePick)
                    Text(CaskPresentation.heroMeta(
                        installCount: housePick.installCount365d,
                        version: housePick.version,
                        categoryName: assets.primaryCategoryName(for: housePick.name)
                    ))
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.well)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 0.5)
                    )
                CaskIconView(
                    token: housePick.name,
                    size: 96,
                    isKnownToken: assets.isKnownIconToken(housePick.name),
                    iconLoader: iconLoader
                )
            }
            .frame(width: 104, height: 104)
        }
        .padding(EdgeInsets(top: 22, leading: 28, bottom: 22, trailing: 28))
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .leading)
        .themeCard(fill: Theme.cardFillLoud, radius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cask-house-pick")
    }

    @ViewBuilder
    private func heroAction(for housePick: CatalogPackage) -> some View {
        if let target = PackageTarget(housePick.id) {
            let installedPackage = installed.inventory.package(housePick.id)
            if let installedPackage, installedPackage.isOutdated {
                heroButton("Update", fill: theme.tint(0.22)) { submit(.upgrade(target)) }
            } else if installedPackage != nil {
                Text("● Installed")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.successText)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(Theme.successTint(0.15), in: Capsule())
            } else {
                heroButton("↓ Install", fill: theme.tint(0.12)) { submit(.install(target)) }
            }
        }
    }

    private func heroButton(
        _ label: String,
        fill: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.light)
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.tint(0.35), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!operations.isAvailable)
        .accessibilityIdentifier("cask-hero-install")
    }

    // MARK: - Shelves

    private func shelfView(_ shelf: CaskBrowseSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: shelfIcon(for: shelf.destination))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(shelf.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                viewAllButton(for: shelf.destination)
            }
            casksView(shelf.casks)
        }
    }

    /// The header's leading symbol: the two ranked shelves reuse their sidebar
    /// sections' icons, and a category shelf uses its vendored category icon —
    /// the same symbol the Categories pane draws for that row.
    private func shelfIcon(for destination: CaskBrowseDestination) -> String {
        switch destination {
        case .topCharts:
            AppSection.caskTopCharts.systemImage
        case .recentlyAdded:
            AppSection.caskRecentlyAdded.systemImage
        case .category(let id):
            content.categories.first { $0.id == id }?.icon
                ?? AppSection.caskCategory.systemImage
        }
    }

    /// Every shelf's View All: the two ranked shelves lead to their sections,
    /// and a category shelf leads to its category's page through the same
    /// closure the card labels use — absent the closure, no button at all.
    @ViewBuilder
    private func viewAllButton(for destination: CaskBrowseDestination) -> some View {
        switch destination {
        case .topCharts:
            viewAllButton(identifier: "cask-view-all-\(AppSection.caskTopCharts.rawValue)") {
                section = .caskTopCharts
            }
        case .recentlyAdded:
            viewAllButton(identifier: "cask-view-all-\(AppSection.caskRecentlyAdded.rawValue)") {
                section = .caskRecentlyAdded
            }
        case .category(let id):
            if let onSelectCategory {
                viewAllButton(identifier: "cask-view-all-category-\(id)") {
                    onSelectCategory(id)
                }
            }
        }
    }

    private func viewAllButton(
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button("View All", action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.base)
            .accessibilityIdentifier(identifier)
    }

    private func casksView(_ casks: [CatalogPackage]) -> some View {
        CaskCollectionView(
            casks: casks,
            viewMode: viewMode,
            installed: installed,
            operations: operations,
            assets: assets,
            iconLoader: iconLoader,
            onSelectCategory: onSelectCategory
        )
    }

    // MARK: - Search

    /// The whole eligible universe, in popularity order, so a match ranks by
    /// the same rule every shelf does. This used to be the shelves plus the
    /// house pick — the only casks the projection carried before the Top
    /// Charts slice exposed the uncapped set.
    private var searchMatches: [CatalogPackage] {
        CaskCollectionSearch.matches(in: content.allByPopularity, query: appliedSearch)
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Results")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(searchMatches.count.formatted())")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            if searchMatches.isEmpty {
                Text("No cask matches “\(appliedSearch)”.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                casksView(searchMatches)
            }
        }
    }

    @Environment(ThemeStore.self) private var theme

    /// The `PackageDetailView` idiom, verbatim: the confirmation rule is
    /// applied in exactly one place.
    private func submit(_ command: MutationCommand) {
        if operations.request(command) == nil {
            operations.submit(command)
        }
    }
}

/// The typed empty state: no snapshot has produced any browse content yet.
/// Cellar's own component — quiet, centred, and honest about why.
struct CaskCatalogSyncingNote: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textQuaternary)
            Text("The catalog is still syncing.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 120)
        .accessibilityIdentifier("cask-browse-syncing")
    }
}
