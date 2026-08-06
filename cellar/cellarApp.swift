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
import DiskUsage
import Persistence
import SecurityKit
import SwiftUI

@main
struct cellarApp: App {
    /// Detection state for the whole app. Owned here so every scene observes
    /// the same evaluation.
    @State private var brewDetection: BrewDetectionStore

    /// The catalog, likewise owned once. There is no `ModelContainer` any more:
    /// the catalog is derived data with its own on-disk format, and nothing in
    /// this milestone stores anything a user could lose.
    @State private var catalog = CatalogStore(directory: CatalogStore.defaultDirectory())

    /// What this machine has installed.
    @State private var installed: InstalledStore
    /// The seam driven while a Cellar-initiated mutation that invalidates the
    /// **installed set** runs.
    @State private var mutations: InstalledMutationGate
    /// The same seam for the **services** domain. A second instance of the same
    /// type, because a gate is a depth counter plus a terminals stream and there
    /// is nothing installed-specific in it — the rename it deserves is recorded
    /// as debt rather than taken here (design D2).
    @State private var serviceMutations: InstalledMutationGate
    /// The tap inventory has its own invalidation domain and refresh consumer.
    @State private var tapMutations: InstalledMutationGate
    /// Owns cadence: launch, activation, and debounced external changes.
    @State private var refresher: InstalledRefreshCoordinator
    @State private var taps: TapStore
    @State private var tapsRefresher: TapRefreshCoordinator
    @State private var diskUsage: DiskUsageStore
    @State private var diskMutations: InstalledMutationGate
    @State private var diskRefresher: DiskUsageRefreshCoordinator
    @State private var cleanup: CleanupStore
    private let cleanupPreviewSource: any CleanupPreviewSourcing

    /// Advisory coverage and findings.
    ///
    /// Owned here like every other store, and wired to its engine exactly as the
    /// catalog is: `Task { await store.start() }`, cancelled with the scene and
    /// never awaited. The engine reads consent on **every** egress path, so
    /// revoking takes effect on the next scheduled pass rather than at the next
    /// launch — which is why the consent preference is injected into the engine
    /// rather than consulted once here at construction.
    @State private var security: SecurityStore
    /// The recorded answer to "may package names and versions leave this Mac".
    /// A preference, so it lives in defaults; the NVD key is a secret and lives
    /// in the Keychain instead.
    @State private var securityConsent: SecurityConsentPreference
    /// The Keychain seam, held rather than rebuilt per sheet so the consent sheet
    /// and the enrichment source read the same store.
    private let advisoryCredentials: any AdvisoryCredentialStoring
    /// Dismissed findings, on the same container as metadata and history.
    @State private var dismissals: DismissalStore

    /// The queue of Cellar-initiated mutations, and everything the activity
    /// surfaces read. It is what finally drives `mutations`, the gate M2-1
    /// shipped with no callers at all.
    @State private var operations: OperationCenter

    /// Favorites, notes and snoozes, and the durable mutation history.
    ///
    /// Owned here as `@State` on the `CatalogStore` precedent, and injected
    /// down. There is deliberately **no `.modelContainer(…)` scene modifier and
    /// no `@Query`**: the stores publish plain `Sendable` values, so no `@Model`
    /// instance ever leaves `Persistence` and every composition rule stays
    /// provable over values in `BrewClient` (design D3). Adding the modifier
    /// later remains a one-line option if `@Query` is ever wanted.
    ///
    /// Both come from one `LocalStores`, which opens **one** `ModelContainer`
    /// over the store file and injects it into both. They used to be built
    /// separately here, and each opened its own container over the same file:
    /// two stacks and two sets of pending changes writing one SQLite file.
    ///
    /// `LocalStores` does not throw. A store that cannot be opened is a *state*
    /// the UI renders disabled with its reason attached — one failure, one
    /// reason, on both — and a `try!` here would turn a recoverable disk problem
    /// into a boot loop (D4, D6).
    @State private var metadata: MetadataStore
    @State private var history: HistoryStore

    /// The background services Homebrew manages, and the poll that keeps them
    /// current.
    ///
    /// The store opens **no** `ModelContainer`: service state is launchd's
    /// truth, re-read every five seconds while the surface is visible, so there
    /// is nothing here worth persisting and nothing a user could lose.
    @State private var services: ServicesStore
    @State private var servicesRefresher: ServicesRefreshCoordinator

    /// Correlates a force-untap terminal with both refreshes it must await.
    private let refreshRegistry: MutationRefreshRegistry

    /// The app's long-lived loops.
    ///
    /// App-level state outlives every scene, so closing the window that started
    /// Cellar no longer cancels the catalog refresh schedule or drops the sync
    /// event subscription (M1 follow-ups #8 and #9).
    ///
    /// The services **poll** is deliberately not one of them: a `LoopOwner`
    /// slot stays claimed for the rest of the launch even after its body
    /// returns, so a poll started there would never restart after the first
    /// hide. The coordinator owns it instead, and only its app-lifetime
    /// terminals consumer takes a slot here.
    @State private var loops = LoopOwner()

    /// Whether the app itself is in the foreground. One of the two reported
    /// halves of "the services surface is visible"; the other is the view's
    /// `onAppear`/`onDisappear`.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let isUITesting = AppTestFixtures.isEnabled
        let locator: any BrewLocating = isUITesting ? AppTestBrewLocator() : DefaultBrewLocator()
        let installedSource: any InstalledPayloadSourcing = isUITesting
            ? AppTestInstalledPayloadSource()
            : BrewInfoPayloadSource()
        let tapSource: any TapPayloadSourcing = isUITesting
            ? AppTestTapPayloadSource()
            : BrewTapPayloadSource()
        let installed = InstalledStore(source: installedSource)
        let taps = TapStore(source: tapSource)
        let mutations = InstalledMutationGate()
        let serviceMutations = InstalledMutationGate()
        let tapMutations = InstalledMutationGate()
        let diskMutations = InstalledMutationGate()
        let refreshRegistry = MutationRefreshRegistry()
        let services = ServicesStore()
        let diskCacheURL = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Cellar/disk-usage-v1.json")
        let advisoryCacheURL = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Cellar/\(SecurityKit.advisoryCacheFileName)")
        let diskUsage = DiskUsageStore(
            cache: DiskUsageCache(fileURL: diskCacheURL),
            initialSnapshot: isUITesting && AppTestFixtures.mode != .absent
                ? AppTestFixtures.diskSnapshot : nil,
            initiallyStale: isUITesting && !AppTestFixtures.isCleanupEnabled
        )
        let cleanupPreviewSource: any CleanupPreviewSourcing = AppTestFixtures.isCleanupEnabled
            ? AppTestCleanupPreviewSource(mode: AppTestFixtures.cleanupMode)
            : CleanupPreviewSource()
        // One container, opened once, shared by both stores.
        let stores = LocalStores()
        _brewDetection = State(initialValue: BrewDetectionStore(locator: locator))
        _installed = State(initialValue: installed)
        _mutations = State(initialValue: mutations)
        _serviceMutations = State(initialValue: serviceMutations)
        _tapMutations = State(initialValue: tapMutations)
        _diskMutations = State(initialValue: diskMutations)
        _diskUsage = State(initialValue: diskUsage)
        _cleanup = State(initialValue: CleanupStore(source: cleanupPreviewSource))
        self.cleanupPreviewSource = cleanupPreviewSource
        _taps = State(initialValue: taps)
        self.refreshRegistry = refreshRegistry
        _metadata = State(initialValue: stores.metadata)
        _history = State(initialValue: stores.history)
        _dismissals = State(initialValue: stores.dismissals)
        let securityConsent = SecurityConsentPreference()
        let advisoryCredentials = KeychainAdvisoryCredentialStore()
        _securityConsent = State(initialValue: securityConsent)
        self.advisoryCredentials = advisoryCredentials
        // The two sources are reachable from this file and from nowhere else in
        // the app: neither carries an internal consent check, and the gate lives
        // in the engine. `SecurityCompositionTests` asserts that structurally, so
        // a view that reached for `OSVSource` directly would fail the suite
        // rather than quietly transmit before consent.
        _security = State(
            initialValue: SecurityStore(
                engine: SecurityScanEngine(
                    discovery: OSVSource(),
                    enrichment: NVDSource(credentials: advisoryCredentials),
                    cache: AdvisoryCache(fileURL: advisoryCacheURL),
                    consent: securityConsent,
                    queries: { [] }
                )
            )
        )
        _services = State(initialValue: services)
        _servicesRefresher = State(
            initialValue: ServicesRefreshCoordinator(store: services, mutations: serviceMutations)
        )
        _refresher = State(
            initialValue: InstalledRefreshCoordinator(
                store: installed,
                mutations: mutations,
                refreshRegistry: refreshRegistry
            )
        )
        _tapsRefresher = State(
            initialValue: TapRefreshCoordinator(
                store: taps,
                mutations: tapMutations,
                refreshRegistry: refreshRegistry
            )
        )
        _diskRefresher = State(
            initialValue: DiskUsageRefreshCoordinator(
                store: diskUsage,
                mutations: diskMutations,
                refreshRegistry: refreshRegistry
            )
        )
        // The recorder is injected once, here, and nowhere else: `finish` is the
        // only caller, so this is the whole of "history is written" as a wiring
        // fact. Removing this argument returns the centre to its M2-2 behaviour
        // exactly, which is what makes the feature one injection from revertible
        // (installation-history IH7).
        // Two domains, and a command opens only the gates its own `invalidates`
        // scope names — so a service toggle costs zero inventory probes and does
        // not suppress the installed watcher while it runs (design D2).
        _operations = State(
            initialValue: OperationCenter(
                gates: MutationGates([
                    (.installedInventory, mutations),
                    (.services, serviceMutations),
                    (.taps, tapMutations)
                    ,(.diskUsage, diskMutations)
                ]),
                history: SwiftDataHistoryRecorder(store: stores.history),
                refreshRegistry: refreshRegistry,
                launcherFactory: { _ -> any ProcessLaunching in
                    if isUITesting { return AppTestProcessLauncher() }
                    return SystemProcessLauncher()
                }
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                brewDetection: brewDetection,
                catalog: catalog,
                installed: installed,
                operations: operations,
                metadata: metadata,
                history: history,
                services: services,
                servicesRefresher: servicesRefresher,
                taps: taps,
                diskUsage: diskUsage,
                cleanup: cleanup,
                cleanupPreviewSource: cleanupPreviewSource,
                security: security,
                securityConsent: securityConsent,
                advisoryCredentials: advisoryCredentials,
                dismissals: dismissals
            )
                // Evaluate at launch, and again whenever the app comes back to
                // the front: brew may have been installed, upgraded, or removed
                // from a terminal while Cellar was in the background.
                .task { await refreshEverything() }
                .task { await observeActivations() }
                // The app half of "visible". The view reports the other half;
                // the poll runs only when both agree, so ⌘H with Services
                // selected costs zero probes.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    servicesRefresher.setActive(phase == .active)
                }
                // Owned by `loops`, not by this scene: `start` is idempotent per
                // id, so a second window joins rather than starting a second
                // loop, and closing this one leaves both running.
                .task { loops.start("catalog") { await catalog.start() } }
                // The same shape as the catalog: the store loads its cache, then
                // observes the engine and runs the refresh loop for as long as the
                // scene lives. `loadCache` consults no consent, so findings stay
                // readable offline and after revocation.
                .task { loops.start("security") { await security.start() } }
                .task { loops.start("installed") { await refresher.run() } }
                .task { loops.start("installed-watcher") { await watchInstalledRoots() } }
                // The **terminals consumer only** — never the poll. A `LoopOwner`
                // slot stays claimed for the rest of the launch even after its
                // body returns, so a poll started here would never restart after
                // the first hide. The coordinator owns the poll itself.
                .task { loops.start("services") { await servicesRefresher.run() } }
                .task {
                    loops.start("taps-and-disk-usage") {
                        await withTaskGroup(of: Void.self) { group in
                            group.addTask { await tapsRefresher.run() }
                            group.addTask { await diskRefresher.run() }
                        }
                    }
                }
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
        await tapsRefresher.refresh(for: brewDetection.state)
        // Services becomes available the moment brew does, and the poll starts
        // itself if the surface is already showing — which is the ordinary
        // launch order, since detection resolves after the first render.
        await servicesRefresher.refresh(for: brewDetection.state)
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
        let fanout = HomebrewChangeFanout(
            observer: observer,
            installedChanged: { refresher.changeDetected() },
            diskChanged: { areas in diskRefresher.invalidate(areas) }
        )
        await fanout.run()
    }
}
