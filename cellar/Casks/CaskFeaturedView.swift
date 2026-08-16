//
//  CaskFeaturedView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// CaskHub's Featured page on Cellar's skin: the top casks by annual installs,
/// as the same flat card grid every collection page draws. No hero, no
/// shelves, no sort control — the order *is* popularity.
///
/// Presentation only. What is featured, and in what order, is settled in
/// `CellarCore`'s projection and asserted there; this view renders
/// `catalog.caskBrowse.featured` through the shared collection chrome.
struct CaskFeaturedView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader

    /// The grid/list choice, the same key Browse persists: the toggle carries
    /// across pages.
    @AppStorage("casks.viewMode") private var viewMode: CaskBrowseViewMode = .grid

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""

    private var content: CaskBrowseContent { catalog.caskBrowse }

    /// The featured hundred, narrowed by the search when one is applied.
    private var displayedCasks: [CatalogPackage] {
        guard !appliedSearch.isEmpty else { return content.featured }
        return CaskCollectionSearch.matches(in: content.featured, query: appliedSearch)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CaskCollectionTopBar(
                    title: "Featured",
                    countLabel: "\(displayedCasks.count.formatted()) casks",
                    viewMode: $viewMode,
                    searchText: $searchText
                )
                if content == .empty {
                    CaskCatalogSyncingNote()
                } else if displayedCasks.isEmpty {
                    Text("Nothing featured matches “\(appliedSearch)”.")
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
                        iconLoader: iconLoader
                    )
                }
            }
            .frame(maxWidth: 1086)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 48, trailing: 20))
        }
        .background(Color.white.opacity(0.014))
        .task { await assets.load() }
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .accessibilityIdentifier("cask-featured-page")
    }
}
