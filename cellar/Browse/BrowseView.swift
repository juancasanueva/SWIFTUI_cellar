//
//  BrowseView.swift
//  cellar
//

import BrewClient
import Catalog
import DiskUsage
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
    let operations: OperationCenter
    /// Read only for the per-row size metric — the same measurement Cleanup
    /// shows. Nothing here starts a scan.
    let diskUsage: DiskUsageStore
    /// The cask artwork pipeline; `nil` — a preview, say — keeps the letter
    /// tile for every row (see `PackageIconTile`).
    var assets: CaskBrowseAssets?
    var iconLoader: CaskIconLoader?
    @Binding var selection: PackageID?

    @State private var hideInstalled = false
    @State private var outdatedOnly = false

    var body: some View {
        @Bindable var catalog = catalog

        VStack(spacing: 0) {
            SyncBanner(status: catalog.syncStatus, packageCount: catalog.packageCount) {
                Task { await catalog.refreshNow() }
            }
            VStack(spacing: 10) {
                PaneSearchField(
                    text: $catalog.query,
                    prompt: "Search \(catalog.packageCount.formatted()) packages…"
                )
                CatalogFilterBar(
                    filters: $catalog.filters,
                    hideInstalled: $hideInstalled,
                    outdatedOnly: $outdatedOnly,
                    isInstalledFilterEnabled: browse.isFilterEnabled
                )
            }
            .padding(EdgeInsets(top: 11, leading: 13, bottom: 11, trailing: 13))
            HairlineDivider()

            List(rows, selection: $selection) { entry in
                HStack(spacing: 6) {
                    PackageRow(
                        entry: entry,
                        sizeOnDisk: sizesOnDisk[entry.id],
                        assets: assets,
                        iconLoader: iconLoader
                    )
                    Spacer(minLength: 0)
                    MutationMenu(center: operations, entry: entry)
                }
                .tag(entry.id)
                .themedListSelection(isSelected: selection == entry.id)
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if rows.isEmpty {
                    EmptyResults(query: catalog.query, isReady: catalog.isReady)
                }
            }
        }
        .background(Color.white.opacity(0.014))
        // The manifest gate behind each row's icon lookup; idempotent, so the
        // Discover pages and this list can all ask (see `CaskBrowseAssets`).
        .task { await assets?.load() }
    }

    private var browse: InstalledBrowse {
        InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil)
    }

    /// One lookup built per render rather than one array walk per row.
    ///
    /// The settled snapshot first, then the in-flight scan's incremental
    /// answers on top — so a first launch with no cache fills sizes in as they
    /// are measured instead of all at once at the end.
    private var sizesOnDisk: [PackageID: Int64] {
        var sizes = Dictionary(
            uniqueKeysWithValues: diskUsage.visiblePackages.map {
                ($0.id, $0.observation.allocatedBytes)
            }
        )
        for (id, usage) in diskUsage.incrementalPackages {
            sizes[id] = usage.observation.allocatedBytes
        }
        return sizes
    }

    private var rows: [PackageEntry] {
        // Of the old four-way installed-state modes, only Outdated survives —
        // as the design's fourth chip; "Hide installed" covers the rest.
        let composed = browse.rows(
            mode: outdatedOnly ? .outdated : .all,
            query: catalog.query,
            // The same controls the index already answers for `all` and
            // `notInstalled`, now honoured under the two inventory-driven modes
            // as well — so no enabled control is inert (design D8d).
            filters: catalog.filters,
            catalogResults: catalog.results,
            catalogLookup: { catalog.package($0) }
        )
        guard hideInstalled else { return composed }
        return composed.filter { !$0.isInstalled }
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
        operations: OperationCenter(),
        diskUsage: DiskUsageStore(
            cache: DiskUsageCache(
                fileURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("preview-disk-usage.json")
            )
        ),
        selection: $selection
    )
}
