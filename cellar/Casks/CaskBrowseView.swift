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

    /// The grid/list choice, kept across launches like the shell's pane width.
    @AppStorage("casks.viewMode") private var viewMode: CaskBrowseViewMode = .grid

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — typing filters a few thousand cards, so
    /// the filter runs per pause rather than per keystroke.
    @State private var appliedSearch = ""

    private var content: CaskBrowseContent { catalog.caskBrowse }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                topBar
                if content == .empty {
                    CaskCatalogSyncingNote()
                } else if appliedSearch.isEmpty {
                    if let housePick = content.housePick {
                        heroCard(for: housePick)
                    }
                    ForEach(content.sections) { shelf in
                        shelfView(shelf)
                    }
                } else {
                    searchResults
                }
            }
            .frame(maxWidth: 1086)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 48, trailing: 20))
        }
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
            searchText: $searchText
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
                    size: 76,
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
            HStack {
                Text(shelf.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                // TODO: A `.category` destination has no page yet, so only the
                // two ranked shelves carry a View All.
                if let destination = viewAllSection(for: shelf.destination) {
                    Button("View All") {
                        section = destination
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.base)
                    .accessibilityIdentifier("cask-view-all-\(destination.rawValue)")
                }
            }
            casksView(shelf.casks)
        }
    }

    /// Where a shelf's View All leads, or `nil` for a shelf with no page yet.
    private func viewAllSection(for destination: CaskBrowseDestination) -> AppSection? {
        switch destination {
        case .topCharts: .caskTopCharts
        case .recentlyAdded: .caskRecentlyAdded
        case .category: nil
        }
    }

    private func casksView(_ casks: [CatalogPackage]) -> some View {
        CaskCollectionView(
            casks: casks,
            viewMode: viewMode,
            installed: installed,
            operations: operations,
            assets: assets,
            iconLoader: iconLoader
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
