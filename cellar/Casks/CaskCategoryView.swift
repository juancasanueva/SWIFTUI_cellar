//
//  CaskCategoryView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// How a category page orders itself — CaskHub's three options verbatim,
/// defaulting to Most Popular on every category change.
enum CaskCategorySort: String, CaseIterable {
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

/// One vendored category as a page: everything the shelf of the same name
/// merely samples, uncapped, through the shared collection chrome.
///
/// Presentation only: which casks belong to a category, and in what order,
/// live in `CaskBrowseProjection`'s `casksByCategory` and are asserted in
/// `CellarCore`. Which category this page shows is the shell's data — the id
/// `ContentView` holds beside the `.caskCategory` section — so the view
/// resolves it against `caskBrowse.categories` and says so plainly when it
/// cannot.
struct CaskCategoryView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    let operations: OperationCenter
    let assets: CaskBrowseAssets
    let iconLoader: CaskIconLoader
    /// The category to show, or `nil` when nothing has picked one yet.
    let categoryID: String?
    /// See `CaskCollectionTopBar.shellControls`.
    var shellControls: ShellHeaderControls? = nil

    /// The grid/list choice, the same key every cask page persists.
    @AppStorage("casks.viewMode") private var viewMode: CaskBrowseViewMode = .grid

    @State private var searchText = ""
    /// `searchText` debounced 200 ms — see `caskSearchDebounce`.
    @State private var appliedSearch = ""
    @State private var sort: CaskCategorySort = .mostPopular

    private var content: CaskBrowseContent { catalog.caskBrowse }

    /// The vendored summary behind the id, or `nil` for an id the catalog
    /// does not know — which the body renders as "pick one", never as a crash.
    private var summary: CaskCategorySummary? {
        content.categories.first { $0.id == categoryID }
    }

    /// The category's whole membership, already popularity-ordered by the
    /// projection's single pass.
    private var categoryCasks: [CatalogPackage] {
        guard let categoryID else { return [] }
        return content.casksByCategory[categoryID] ?? []
    }

    /// The sort menu's ordering over the projection's popularity order.
    private var sortedCasks: [CatalogPackage] {
        switch sort {
        case .mostPopular:
            categoryCasks
        case .nameAscending:
            categoryCasks.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .nameDescending:
            categoryCasks.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending
            }
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
                } else if summary == nil {
                    note("Pick a category.")
                } else if displayedCasks.isEmpty {
                    note(
                        appliedSearch.isEmpty
                            ? "No casks in this category."
                            : "Nothing in this category matches “\(appliedSearch)”."
                    )
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
            .padding(EdgeInsets(top: 6, leading: 20, bottom: 48, trailing: 20))
        }
        .caskCollectionTopBarPinned {
            CaskCollectionTopBar(
                title: summary?.displayName ?? AppSection.caskCategory.title,
                countLabel: "\(displayedCasks.count.formatted()) casks",
                viewMode: $viewMode,
                searchText: $searchText,
                shellControls: shellControls
            ) {
                sortMenu
            }
        }
        .background(Color.white.opacity(0.014))
        .task { await assets.load() }
        .caskSearchDebounce(searchText, into: $appliedSearch)
        // A new category is a new page: the sort resets rather than carrying
        // one category's choice into the next, CaskHub's own behaviour.
        .onChange(of: categoryID) {
            sort = .mostPopular
        }
        .accessibilityIdentifier("cask-category-page")
    }

    /// The quiet centred note every cask page states its empty cases in.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 40)
    }

    // MARK: - The sort menu

    private var sortMenu: some View {
        Menu {
            ForEach(CaskCategorySort.allCases, id: \.self) { option in
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
        .accessibilityIdentifier("cask-category-sort")
    }
}
