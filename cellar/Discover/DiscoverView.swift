//
//  DiscoverView.swift
//  cellar
//

import Catalog
import SwiftUI

/// Where you look when you do not yet have a query.
///
/// Reads `CatalogStore.discover`, which is projected off the main actor inside
/// the same adoption that installs the search index — so this view can never see
/// a fresh catalog beside a stale set of recommendations.
///
/// Presentation only. Every rule worth arguing about — what is eligible to rank,
/// which curated entry resolves, what counts as new — is settled in `CellarCore`
/// and asserted there.
struct DiscoverView: View {
    let catalog: CatalogStore
    @Binding var selection: PackageID?

    var body: some View {
        List(selection: $selection) {
            DiscoverNewToYouSection(model: arrivals, selection: $selection)
            DiscoverLadderSection(model: topFormulae, selection: $selection)
            DiscoverLadderSection(model: topCasks, selection: $selection)
            DiscoverCuratedSection(model: curated, selection: $selection)
        }
        .navigationTitle(AppSection.discover.title)
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

    private var content: DiscoverContent { catalog.discover }

    private var arrivals: DiscoverArrivalsModel {
        DiscoverArrivalsModel(
            state: content.newToYou,
            hiddenCount: content.hiddenArrivalCount
        )
    }

    private var topFormulae: DiscoverLadderModel {
        DiscoverLadderModel(title: "Most installed formulae", state: content.topFormulae)
    }

    private var topCasks: DiscoverLadderModel {
        DiscoverLadderModel(title: "Most installed casks", state: content.topCasks)
    }

    private var curated: DiscoverCuratedModel {
        DiscoverCuratedModel(state: content.curated)
    }
}
