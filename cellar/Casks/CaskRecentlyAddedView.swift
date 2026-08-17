//
//  CaskRecentlyAddedView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// How the Recently Added page orders itself once the window has filtered it —
/// CaskHub's five options verbatim, defaulting to Newest on every entry.
enum CaskRecentlyAddedSort: String, CaseIterable {
    case mostPopular
    case nameAscending
    case nameDescending
    case oldest
    case newest

    var label: String {
        switch self {
        case .mostPopular: "Most Popular"
        case .nameAscending: "Name A–Z"
        case .nameDescending: "Name Z–A"
        case .oldest: "Oldest"
        case .newest: "Newest"
        }
    }
}

/// The selectable recency windows — CaskHub's three, with 30 the default.
private let caskRecentWindowOptions = [30, 60, 90]

/// CaskHub's Recently Added on Cellar's skin: the eligible universe narrowed
/// to what a selectable window calls new, newest first.
///
/// Presentation only: what is recent, and what newest means, live in
/// `CaskBrowseProjection` and are asserted in `CellarCore`. This view renders
/// `recentCasks(in:addedDates:now:windowDays:)` through the shared chrome,
/// with the window persisted and the sort deliberately not — CaskHub resets
/// to Newest on every entry.
struct CaskRecentlyAddedView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    /// See `CaskCollectionView.onSelectCategory`.
    var onSelectCategory: ((String) -> Void)? = nil
    /// See `CaskCollectionTopBar.shellControls`.
    var shellControls: ShellHeaderControls? = nil

    /// The grid/list choice, the same key every cask page persists.
    @AppStorage("casks.viewMode") private var viewMode: CaskBrowseViewMode = .list
    /// The recency window, persisted like CaskHub persists it.
    @AppStorage("casks.recentWindow") private var windowDays = 30

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""
    @State private var sort: CaskRecentlyAddedSort = .newest

    private var content: CaskBrowseContent { catalog.caskBrowse }

    /// The window's casks, still in the universe's popularity order.
    private var recentCasks: [CatalogPackage] {
        CaskBrowseProjection.recentCasks(
            in: content.allByPopularity,
            addedDates: content.addedDates,
            now: Date(),
            windowDays: windowDays
        )
    }

    /// The window filter first, then the sort menu's ordering over it.
    private var sortedCasks: [CatalogPackage] {
        switch sort {
        case .mostPopular:
            recentCasks
        case .nameAscending:
            recentCasks.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
        case .nameDescending:
            recentCasks.sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedDescending
            }
        case .oldest:
            CaskBrowseProjection.sortedByOldest(recentCasks, addedDates: content.addedDates)
        case .newest:
            CaskBrowseProjection.sortedByNewest(recentCasks, addedDates: content.addedDates)
        }
    }

    private var displayedCasks: [CatalogPackage] {
        guard !appliedSearch.isEmpty else { return sortedCasks }
        return CaskCollectionSearch.matches(in: sortedCasks, query: appliedSearch)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if content == .empty {
                    CaskCatalogSyncingNote()
                } else if displayedCasks.isEmpty {
                    Text(
                        appliedSearch.isEmpty
                            ? "Nothing new in the last \(windowDays) days."
                            : "Nothing new matches “\(appliedSearch)”."
                    )
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                } else {
                    CaskCollectionView(
                        casks: displayedCasks,
                        viewMode: viewMode,
                        installed: installed,
                        operations: operations,
                        assets: assets,
                        iconLoader: iconLoader,
                        onSelectCategory: onSelectCategory
                    )
                }
            }
            .frame(maxWidth: 1086)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 48, trailing: 20))
        }
        .caskCollectionTopBarPinned {
            CaskCollectionTopBar(
                title: "Recently Added",
                countLabel: "\(displayedCasks.count.formatted()) casks",
                viewMode: $viewMode,
                searchText: $searchText,
                shellControls: shellControls
            ) {
                windowChip
                sortMenu
            }
        }
        .background(Color.white.opacity(0.014))
        .task { await assets.load() }
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .accessibilityIdentifier("cask-recentlyadded-page")
    }

    // MARK: - The window chip

    private var windowChip: some View {
        Menu {
            ForEach(caskRecentWindowOptions, id: \.self) { days in
                Button("\(days) Days") { windowDays = days }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10.5))
                Text("\(windowDays) Days")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Theme.controlFill, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Recency window")
        .accessibilityIdentifier("cask-recent-window")
    }

    // MARK: - The sort menu

    private var sortMenu: some View {
        Menu {
            ForEach(CaskRecentlyAddedSort.allCases, id: \.self) { option in
                Button(option.label) { sort = option }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10.5))
                Text(sort.label)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Theme.controlFill, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort order")
        .accessibilityIdentifier("cask-recent-sort")
    }
}
