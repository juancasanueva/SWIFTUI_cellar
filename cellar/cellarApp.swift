//
//  cellarApp.swift
//  cellar
//
//  Created by Juan Casanueva on 01/08/2026.
//

import AppKit
import BrewProcess
import Catalog
import SwiftUI

@main
struct cellarApp: App {
    /// Detection state for the whole app. Owned here so every scene observes
    /// the same evaluation.
    @State private var brewDetection = BrewDetectionStore()

    /// The catalog, likewise owned once. There is no `ModelContainer` any more:
    /// the catalog is derived data with its own on-disk format, and nothing in
    /// this milestone stores anything a user could lose.
    @State private var catalog = CatalogStore(directory: CatalogStore.defaultDirectory())

    var body: some Scene {
        WindowGroup {
            ContentView(brewDetection: brewDetection, catalog: catalog)
                // Evaluate at launch, and again whenever the app comes back to
                // the front: brew may have been installed, upgraded, or removed
                // from a terminal while Cellar was in the background.
                .task { await brewDetection.refresh() }
                .task {
                    let activations = NotificationCenter.default.notifications(
                        named: NSApplication.didBecomeActiveNotification
                    )
                    for await _ in activations {
                        await brewDetection.refresh()
                    }
                }
                // Long-lived: `start()` loads the cache and then runs the
                // refresh schedule for as long as the scene exists, so closing
                // the window cancels the loop structurally.
                .task { await catalog.start() }
        }
    }
}
