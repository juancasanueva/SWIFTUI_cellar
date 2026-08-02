//
//  cellarApp.swift
//  cellar
//
//  Created by Juan Casanueva on 01/08/2026.
//

import AppKit
import BrewClient
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

    /// What this machine has installed.
    @State private var installed: InstalledStore
    /// The seam M2-2 will drive while a Cellar-initiated mutation runs.
    @State private var mutations: InstalledMutationGate
    /// Owns cadence: launch, activation, and debounced external changes.
    @State private var refresher: InstalledRefreshCoordinator

    /// The queue of Cellar-initiated mutations, and everything the activity
    /// surfaces read. It is what finally drives `mutations`, the gate M2-1
    /// shipped with no callers at all.
    @State private var operations: OperationCenter

    /// The app's long-lived loops.
    ///
    /// App-level state outlives every scene, so closing the window that started
    /// Cellar no longer cancels the catalog refresh schedule or drops the sync
    /// event subscription (M1 follow-ups #8 and #9).
    @State private var loops = LoopOwner()

    init() {
        let installed = InstalledStore()
        let mutations = InstalledMutationGate()
        _installed = State(initialValue: installed)
        _mutations = State(initialValue: mutations)
        _refresher = State(
            initialValue: InstalledRefreshCoordinator(store: installed, mutations: mutations)
        )
        _operations = State(initialValue: OperationCenter(gate: mutations))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                brewDetection: brewDetection,
                catalog: catalog,
                installed: installed,
                operations: operations
            )
                // Evaluate at launch, and again whenever the app comes back to
                // the front: brew may have been installed, upgraded, or removed
                // from a terminal while Cellar was in the background.
                .task { await refreshEverything() }
                .task { await observeActivations() }
                // Owned by `loops`, not by this scene: `start` is idempotent per
                // id, so a second window joins rather than starting a second
                // loop, and closing this one leaves both running.
                .task { loops.start("catalog") { await catalog.start() } }
                .task { loops.start("installed") { await refresher.run() } }
                .task { loops.start("installed-watcher") { await watchInstalledRoots() } }
        }
    }

    /// Detection first, then everything that depends on it.
    ///
    /// The operation centre is attached from the same place, so mutations become
    /// available the moment brew does and go unavailable the moment it stops
    /// being — with no restart either way (package-mutation PM7).
    @MainActor
    private func refreshEverything() async {
        await brewDetection.refresh()
        operations.attach(installation: brewDetection.state.installation)
        await refresher.refresh(for: brewDetection.state)
    }

    @MainActor
    private func observeActivations() async {
        let activations = NotificationCenter.default.notifications(
            named: NSApplication.didBecomeActiveNotification
        )
        for await _ in activations {
            await refreshEverything()
        }
    }

    /// Watches Homebrew's installation roots, once there is an installation to
    /// watch, and forwards every signal to the coordinator's quiet window.
    ///
    /// The watcher is latency, not correctness: if the prefix appears after
    /// launch this loop has already returned, and the activation refresh above
    /// still keeps the inventory right (design D9).
    @MainActor
    private func watchInstalledRoots() async {
        // Joins the launch evaluation rather than starting a second probe —
        // detection's single flight is keyed by the configured path.
        await brewDetection.refresh()
        guard let installation = brewDetection.state.installation else { return }

        let observer = FSEventsInstalledObserver(installation: installation)
        for await _ in observer.changes() {
            refresher.changeDetected()
        }
    }
}
