//
//  BrowseView.swift
//  cellar
//

import BrewClient
import Catalog
import SwiftUI

/// The searchable package list.
///
/// Bound straight to `CatalogStore.results`: the store reranks synchronously on
/// the main actor as the query changes, so there is no debounce, no loading
/// spinner per keystroke, and no chance of an older query's results arriving
/// last (design D4).
///
/// Installed state is composed on top of those results rather than pushed into
/// the index. The rule lives in `InstalledBrowse`, in `BrewClient`, where it is
/// unit-tested; this view only owns the picker.
struct BrowseView: View {
    let catalog: CatalogStore
    let installed: InstalledStore
    @Binding var selection: PackageID?

    @State private var mode: InstalledFilterMode = .all

    var body: some View {
        @Bindable var catalog = catalog

        VStack(spacing: 0) {
            SyncBanner(status: catalog.syncStatus, packageCount: catalog.packageCount) {
                Task { await catalog.refreshNow() }
            }
            CatalogFilterBar(
                filters: $catalog.filters,
                mode: $mode,
                isInstalledFilterEnabled: browse.isFilterEnabled
            )
            Divider()

            List(rows, selection: $selection) { entry in
                PackageRow(entry: entry)
                    .tag(entry.id)
            }
            .overlay {
                if rows.isEmpty {
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

    private var browse: InstalledBrowse {
        InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil)
    }

    private var rows: [PackageEntry] {
        browse.rows(
            mode: mode,
            query: catalog.query,
            // The same controls the index already answers for `all` and
            // `notInstalled`, now honoured under the two inventory-driven modes
            // as well — so no enabled control is inert (design D8d).
            filters: catalog.filters,
            catalogResults: catalog.results,
            catalogLookup: { catalog.package($0) }
        )
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
        installed: InstalledStore(),
        selection: $selection
    )
}
