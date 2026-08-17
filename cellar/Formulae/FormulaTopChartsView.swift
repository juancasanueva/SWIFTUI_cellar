//
//  FormulaTopChartsView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The formula Top Charts: the whole eligible universe ranked by one
/// analytics window's installs-on-request — `CaskTopChartsView`'s shape on
/// the other kind, fed by a formula-configured `CaskChartsStore`.
struct FormulaTopChartsView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    let charts: CaskChartsStore
    var shellControls: ShellHeaderControls? = nil

    /// The grid/list choice, the formula pages' shared key.
    @AppStorage("formulae.viewMode") private var viewMode: CaskBrowseViewMode = .grid

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""
    @State private var sort: CaskTopChartsSort = .mostPopular

    private var content: FormulaBrowseContent { catalog.formulaBrowse }

    /// The selected window's counts, or `nil` for the annual window the
    /// packages already carry — the cask page's rule verbatim.
    private var selectedCounts: [String: Int]? {
        charts.period == .days365 ? nil : charts.countsByPeriod[charts.period]
    }

    /// Period ranking first, then the sort menu's ordering over it.
    private var rankedFormulae: [CatalogPackage] {
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

    private var displayedFormulae: [CatalogPackage] {
        guard !appliedSearch.isEmpty else { return rankedFormulae }
        return CaskCollectionSearch.matches(in: rankedFormulae, query: appliedSearch)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if content == .empty {
                    CaskCatalogSyncingNote()
                } else if displayedFormulae.isEmpty {
                    Text("Nothing on the charts matches “\(appliedSearch)”.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    CaskCollectionView(
                        casks: displayedFormulae,
                        viewMode: viewMode,
                        installed: installed,
                        operations: operations,
                        assets: assets,
                        iconLoader: iconLoader,
                        counts: selectedCounts,
                        remoteIcons: false
                    )
                }
            }
            .frame(maxWidth: 1086)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 48, trailing: 20))
        }
        .caskCollectionTopBarPinned {
            CaskCollectionTopBar(
                title: "Top Charts",
                countLabel: "\(displayedFormulae.count.formatted()) formulae",
                viewMode: $viewMode,
                searchText: $searchText,
                shellControls: shellControls
            ) {
                if charts.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                periodChip
                sortMenu
            }
        }
        .background(Color.white.opacity(0.014))
        // Re-selecting the committed period is what loads the disk cache
        // lazily on first appearance — and a no-op fetch otherwise.
        .task { await charts.select(charts.period) }
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .accessibilityIdentifier("formula-topcharts-page")
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
        .accessibilityIdentifier("formula-charts-period")
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
        .accessibilityIdentifier("formula-charts-sort")
    }
}
