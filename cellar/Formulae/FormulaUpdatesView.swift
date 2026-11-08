//
//  FormulaUpdatesView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// `CaskUpdatesView` on the other kind: the installed formulae that have an
/// update, through the shared collection chrome, each card's verb already
/// Update, with one Update All below.
///
/// No self-updating toggle: a formula never updates itself, so there is no
/// second set to opt into.
struct FormulaUpdatesView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    var shellControls: ShellHeaderControls? = nil

    /// The grid/list choice, the formula pages' shared key.
    @AppStorage("formulae.viewMode") private var viewMode: CaskBrowseViewMode = .list

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""

    private var outdatedFormulae: [CatalogPackage] {
        CaskUpdatesProjection.packages(of: .formula, in: installed.inventory, catalog: { catalog.package($0) })
    }

    private var displayedFormulae: [CatalogPackage] {
        guard !appliedSearch.isEmpty else { return outdatedFormulae }
        return CaskCollectionSearch.matches(in: outdatedFormulae, query: appliedSearch)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if outdatedFormulae.isEmpty {
                    note("Every installed formula is up to date.")
                } else if displayedFormulae.isEmpty {
                    note("No formula update matches “\(appliedSearch)”.")
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
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 72, trailing: 20))
        }
        .caskCollectionTopBarPinned {
            CaskCollectionTopBar(
                title: AppSection.formulaUpdates.title,
                countLabel: "\(displayedFormulae.count.formatted()) formulae",
                viewMode: $viewMode,
                searchText: $searchText,
                shellControls: shellControls
            )
        }
        .overlay(alignment: .bottom) {
            if !displayedFormulae.isEmpty {
                UpdateAllPill(
                    ids: displayedFormulae.map(\.id),
                    installed: installed,
                    operations: operations,
                    help: "Update every formula listed",
                    identifier: "formula-update-all"
                )
            }
        }
        .background(Color.white.opacity(0.014))
        .caskSearchDebounce(searchText, into: $appliedSearch)
        .accessibilityIdentifier("formula-updates-page")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }
}
