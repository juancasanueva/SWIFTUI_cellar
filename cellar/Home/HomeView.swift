//
//  HomeView.swift
//  cellar
//

import BrewProcess
import Catalog
import SwiftUI

/// The landing section: what Cellar found on this machine, and how fresh the
/// catalog is.
struct HomeView: View {
    let brewDetection: BrewDetectionStore
    let catalog: CatalogStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrewDetectionSummary(state: brewDetection.state)
                Divider()
                CatalogSummary(catalog: catalog)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(AppSection.home.title)
    }
}

/// Catalog freshness, stated in the same plain-text register as the detection
/// summary above it.
private struct CatalogSummary: View {
    let catalog: CatalogStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Catalog")
                .font(.headline)
            Text(catalog.syncStatus.shortDescription)
            Text("^[\(catalog.packageCount) package](inflect: true) indexed")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal)
    }
}

#Preview {
    HomeView(
        brewDetection: BrewDetectionStore(),
        catalog: CatalogStore(directory: FileManager.default.temporaryDirectory)
    )
}
