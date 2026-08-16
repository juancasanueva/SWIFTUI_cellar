//
//  CaskTopChartsView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// How the Top Charts page orders itself once the period has ranked it —
/// CaskHub's three options verbatim.
enum CaskTopChartsSort: String, CaseIterable {
    case mostPopular
    case nameAscending
    case nameDescending

    var label: String {
        switch self {
        case .mostPopular: "Most Popular"
        case .nameAscending: "Name A–Z"
        case .nameDescending: "Name Z–A"
        }
    }
}

/// CaskHub's Top Charts on Cellar's skin: the whole eligible universe ranked
/// by one analytics window's installs, with a period chip that fetches the
/// shorter windows lazily.
///
/// Presentation only, twice over: what is eligible and how a window re-ranks
/// it live in `CaskBrowseProjection`, and when a window is fetched, cached or
/// dropped lives in `CaskChartsStore` — both asserted in `CellarCore`. This
/// view renders `chart(allByPopularity, counts:)` through the shared chrome
/// and forwards the chip's choice.
struct CaskTopChartsView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    let charts: CaskChartsStore

    /// The grid/list choice, the same key every cask page persists.
    @AppStorage("casks.viewMode") private var viewMode: CaskBrowseViewMode = .grid

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""
    @State private var sort: CaskTopChartsSort = .mostPopular

    private var content: CaskBrowseContent { catalog.caskBrowse }

    /// The selected window's counts, or `nil` for the annual window — whose
    /// ranking `allByPopularity` already encodes and whose numbers every
    /// package carries itself.
    private var selectedCounts: [String: Int]? {
        charts.period == .days365 ? nil : charts.countsByPeriod[charts.period]
    }

    /// Period ranking first, then the sort menu's ordering over it.
    private var rankedCasks: [CatalogPackage] {
        let ranked = CaskBrowseProjection.chart(content.allByPopularity, counts: selectedCounts)
        return switch sort {
        case .mostPopular:
            ranked
        case .nameAscending:
            ranked.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .nameDescending:
            ranked.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending
            }
        }
    }

    private var displayedCasks: [CatalogPackage] {
        guard !appliedSearch.isEmpty else { return rankedCasks }
        return CaskCollectionSearch.matches(in: rankedCasks, query: appliedSearch)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CaskCollectionTopBar(
                    title: "Top Charts",
                    countLabel: "\(displayedCasks.count.formatted()) casks",
                    viewMode: $viewMode,
                    searchText: $searchText
                ) {
                    if charts.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                    periodChip
                    sortMenu
                }
                if content == .empty {
                    CaskCatalogSyncingNote()
                } else if displayedCasks.isEmpty {
                    Text("Nothing on the charts matches “\(appliedSearch)”.")
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
                        counts: selectedCounts
                    )
                }
            }
            .frame(maxWidth: 1086)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 48, trailing: 20))
        }
        .background(Color.white.opacity(0.014))
        .task { await assets.load() }
        // Re-selecting the committed period is what loads the disk cache
        // lazily on first appearance — and a no-op fetch otherwise.
        .task { await charts.select(charts.period) }
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .accessibilityIdentifier("cask-topcharts-page")
    }

    // MARK: - The period chip

    private var periodChip: some View {
        Menu {
            ForEach(CaskChartsPeriod.allCases, id: \.self) { period in
                Button(period.label) {
                    Task { await charts.select(period) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "clock")
                    .font(.system(size: 10.5))
                Text(charts.period.label)
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
        .help("Ranking window")
        .accessibilityIdentifier("cask-charts-period")
    }

    // MARK: - The sort menu

    private var sortMenu: some View {
        Menu {
            ForEach(CaskTopChartsSort.allCases, id: \.self) { option in
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
        .accessibilityIdentifier("cask-charts-sort")
    }
}
