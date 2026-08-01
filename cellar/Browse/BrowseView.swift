//
//  BrowseView.swift
//  cellar
//

import Catalog
import SwiftUI

/// The searchable package list.
///
/// Bound straight to `CatalogStore.results`: the store reranks synchronously on
/// the main actor as the query changes, so there is no debounce, no loading
/// spinner per keystroke, and no chance of an older query's results arriving
/// last (design D4).
struct BrowseView: View {
    let catalog: CatalogStore
    @Binding var selection: PackageID?

    var body: some View {
        @Bindable var catalog = catalog

        VStack(spacing: 0) {
            SyncBanner(status: catalog.syncStatus, packageCount: catalog.packageCount) {
                Task { await catalog.refreshNow() }
            }
            CatalogFilterBar(filters: $catalog.filters)
            Divider()

            List(catalog.results, selection: $selection) { package in
                PackageRow(package: package)
                    .tag(package.id)
            }
            .overlay {
                if catalog.results.isEmpty {
                    EmptyResults(query: catalog.query, isReady: catalog.isReady)
                }
            }
        }
        .searchable(
            text: $catalog.query,
            placement: .toolbar,
            prompt: "Search \(catalog.packageCount) packages"
        )
        .navigationTitle(AppSection.browse.title)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await catalog.refreshNow() }
                } label: {
                    Label("Refresh catalog", systemImage: "arrow.clockwise")
                }
                .disabled(catalog.syncStatus.isBusy)
            }
        }
    }
}

/// Why the list is empty, which is never the same reason twice.
private struct EmptyResults: View {
    let query: String
    let isReady: Bool

    var body: some View {
        if !isReady {
            ContentUnavailableView("Loading catalog", systemImage: "shippingbox")
        } else if query.isEmpty {
            ContentUnavailableView(
                "No packages yet",
                systemImage: "shippingbox",
                description: Text("The catalog downloads in the background on first launch.")
            )
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

#Preview {
    @Previewable @State var selection: PackageID?
    return BrowseView(
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory),
        selection: $selection
    )
}
