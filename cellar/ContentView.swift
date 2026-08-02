//
//  ContentView.swift
//  cellar
//
//  Created by Juan Casanueva on 01/08/2026.
//

import BrewClient
import BrewProcess
import Catalog
import SwiftUI

/// The three-column shell: sections, list, detail.
///
/// The detail column is driven by a `PackageID` rather than a `CatalogPackage`
/// so a sync that replaces the snapshot mid-browse re-resolves the selection
/// against the new catalog instead of showing a stale copy.
struct ContentView: View {
    let brewDetection: BrewDetectionStore
    let catalog: CatalogStore
    let installed: InstalledStore

    @State private var section: AppSection = .browse
    @State private var selection: PackageID?

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
        } content: {
            switch section {
            case .home:
                HomeView(brewDetection: brewDetection, catalog: catalog)
                    .navigationSplitViewColumnWidth(min: 320, ideal: 480)
            case .browse:
                BrowseView(catalog: catalog, installed: installed, selection: $selection)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360)
            case .installed:
                InstalledListView(
                    installed: installed,
                    catalog: catalog,
                    selection: $selection
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
            }
        } detail: {
            switch section {
            case .home:
                BrewDetectionSummary(state: brewDetection.state)
            case .browse, .installed:
                // The same detail view for both: a package is a package, and
                // the catalog record is the thing worth reading about it.
                PackageDetailView(catalog: catalog, id: selection, selection: $selection)
            }
        }
    }
}

#Preview {
    ContentView(
        brewDetection: BrewDetectionStore(),
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory),
        installed: InstalledStore()
    )
}
