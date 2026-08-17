//
//  FormulaFeaturedView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The formula Featured page: the top hundred by annual installs-on-request,
/// through the shared collection chrome — `CaskFeaturedView`'s shape on the
/// other kind.
struct FormulaFeaturedView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    var shellControls: ShellHeaderControls? = nil

    /// The grid/list choice, the formula pages' shared key.
    @AppStorage("formulae.viewMode") private var viewMode: CaskBrowseViewMode = .grid

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""

    private var content: FormulaBrowseContent { catalog.formulaBrowse }

    /// The featured hundred, narrowed by the search when one is applied.
    private var displayedFormulae: [CatalogPackage] {
        guard !appliedSearch.isEmpty else { return content.featured }
        return CaskCollectionSearch.matches(in: content.featured, query: appliedSearch)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if content == .empty {
                    CaskCatalogSyncingNote()
                } else if displayedFormulae.isEmpty {
                    Text("Nothing featured matches “\(appliedSearch)”.")
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
                title: "Featured",
                countLabel: "\(displayedFormulae.count.formatted()) formulae",
                viewMode: $viewMode,
                searchText: $searchText,
                shellControls: shellControls
            )
        }
        .background(Color.white.opacity(0.014))
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .accessibilityIdentifier("formula-featured-page")
    }
}
