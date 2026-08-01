//
//  cellarApp.swift
//  cellar
//
//  Created by Juan Casanueva on 01/08/2026.
//

import AppKit
import BrewProcess
import SwiftData
import SwiftUI

@main
struct cellarApp: App {
    /// Detection state for the whole app. Owned here so every scene observes
    /// the same evaluation.
    @State private var brewDetection = BrewDetectionStore()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(brewDetection: brewDetection)
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
        }
        .modelContainer(sharedModelContainer)
    }
}
