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
import ReleaseNotes
import SecurityKit
import SwiftUI
import Updates

@main
struct cellarApp: App {
    /// Detection state for the whole app. Owned here so every scene observes
    /// the same evaluation.
    @State private var brewDetection: BrewDetectionStore

    /// The catalog, likewise owned once. There is no `ModelContainer` any more:
    /// the catalog is derived data with its own on-disk format, and nothing in
    /// this milestone stores anything a user could lose.
    ///
    /// The directory is the one fixture seam here: `--ui-testing-m5-discover`
    /// points it at an empty temporary directory, which is what makes a genuine
    /// **first run** reachable from a UI test on a machine that already has a
    /// synced catalog. Nothing else about the store changes.
    @State private var catalog: CatalogStore

    /// What this machine has installed.
    @State private var installed: InstalledStore
    /// npm's detection state. Off by default, so nothing here spawns anything
    /// until the Settings switch is on.
    @State private var npmDetection: NpmDetectionStore
    /// npm's globals and their freshness, contributed into `installed`.
    @State private var npm: NpmStore
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
    /// The per-package grant report. A sixth store, read-only, refreshed with
    /// the taps domain rather than one of its own (package-trust PT2, DD-3).
    @State private var trustGrants: TrustGrantStore
    @State private var tapsRefresher: TapRefreshCoordinator
    @State private var diskUsage: DiskUsageStore
    @State private var diskMutations: InstalledMutationGate
    /// The fifth invalidation domain. Registered unconditionally and simply
    /// never opened while npm is off: only an `NpmCommand` declares
    /// `.npmInventory`, and none can be built without a detected npm
    /// (design D11).
    @State private var npmMutations: InstalledMutationGate
    /// Owns npm's two cadences. The local listing rides the ordinary baseline;
    /// the registry check runs on detection, on npm terminals, on an explicit
    /// refresh and on a one-hour floor — **never** on activation (design D10).
    @State private var npmRefresher: NpmRefreshCoordinator
    @State private var diskRefresher: DiskUsageRefreshCoordinator
    @State private var cleanup: CleanupStore
    private let cleanupPreviewSource: any CleanupPreviewSourcing

    /// The two readings the Health section owns, and nothing else.
    ///
    /// Composed once here — the doctor source and the file-metadata seam — like
    /// every other seam in this file. Note what it is **not** wired to: no
    /// refresh coordinator, no loop, no `.task` of its own. The doctor run is
    /// user-initiated (`system-health`, "Doctor is a read"), and this file never
    /// calls it; the last-update reading is invocation-free and joins the launch
    /// and activation refresh below, because a file's modification date costs
    /// nothing to read and telling the user nothing until they click would be an
    /// affectation rather than a safeguard.
    @State private var health: HealthStore

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
    /// What changed in the release a package is about to be upgraded to.
    ///
    /// Owned here like every other store, and injected through the environment
    /// rather than threaded down four view signatures — but note what it is
    /// **not** wired to: no `.task`, no refresh coordinator, no loop. This store
    /// has no cadence at all. Its only caller is a button, which is what makes
    /// "one opened request costs one request" a property of the composition and
    /// not only of the store.
    @State private var releaseNotes: ReleaseNotesStore
    /// The recorded answer to "may a repository name leave this Mac". A separate
    /// question from the security-scan grant, under its own two defaults keys.
    @State private var releaseNotesConsent: ReleaseNotesConsentPreference
    /// The GitHub token's Keychain seam, under a service name distinct from the
    /// NVD key's. Held rather than rebuilt per sheet so the consent surface and
    /// the source read the same store.
    private let releaseNotesCredentials: any ReleaseNotesCredentialStoring

    /// Whether a newer Cellar exists, and the command that asks.
    ///
    /// Typed as the seam and never as the concrete checker, so a UI-test launch
    /// substitutes an in-memory updater and can never start a real one, reach
    /// the feed, or open an updater window. Held here because both the Settings
    /// card and the menu command must observe the same instance.
    private let updater: any AppUpdating

    /// Dismissed findings, on the same container as metadata and history.
    @State private var dismissals: DismissalStore
    /// The artifact-integrity half. Its results are not cached — a signature
    /// verdict describes the artifact as it is now — so this holds them for the
    /// life of the scene and no longer.
    @State private var integrity: ArtifactIntegrityStore

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

    /// The accent choice every tinted surface derives from.
    @State private var theme = ThemeStore()

    /// The vendored cask category catalog, decoded once for every cask surface,
    /// wired in `init` to the package catalog for the artwork origin gate.
    @State private var caskAssets: CaskBrowseAssets
    /// The cask artwork pipeline. Constructed here and nowhere else, so the
    /// session is a composition decision — and a UI-test launch disables it
    /// outright, which is what keeps those runs at zero network.
    @State private var caskIcons = CaskIconLoader(isDisabled: AppTestFixtures.isEnabled)
    /// Per-period Top Charts rankings. The HTTP source is constructed here and
    /// nowhere else, like every other network seam; a UI-test launch swaps in
    /// the no-network stub and an empty per-launch cache directory, so those
    /// runs stay at zero network and never adopt the developer's own cache.
    @State private var caskCharts: CaskChartsStore
    /// The same store class, formula-configured: the install-on-request
    /// endpoints, decoded as formulae, cached in its own file.
    @State private var formulaCharts: CaskChartsStore

    /// Whether this launch has started its one disk measurement. The scan used
    /// to start only when Cleanup appeared, which left the Search list's size
    /// column and Home's "On disk" tile empty until the user happened to visit
    /// it; one launch-time measurement feeds all three.
    @State private var hasStartedDiskMeasurement = false

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

    /// Whether Cellar puts a status item in the menu bar. Off unless the user
    /// turns it on, and the **only** condition the third scene is inserted
    /// under.
    @State private var menuBar: MenuBarPreference

    /// Whether the app itself is in the foreground. One of the two reported
    /// halves of "the services surface is visible"; the other is the view's
    /// `onAppear`/`onDisappear`.
    @Environment(\.scenePhase) private var scenePhase

    /// Opens the main window by its scene identifier, the way the About window
    /// is already opened. No AppKit activation path, and nothing else on the
    /// menu-bar surface opens, requires or checks for a window.
    @Environment(\.openWindow) private var openWindow

    init() {
        let isUITesting = AppTestFixtures.isEnabled
        let locator: any BrewLocating = isUITesting ? AppTestBrewLocator() : DefaultBrewLocator()
        let installedSource: any InstalledPayloadSourcing = isUITesting
            ? AppTestInstalledPayloadSource()
            : BrewInfoPayloadSource()
        let tapSource: any TapPayloadSourcing = isUITesting
            ? AppTestTapPayloadSource()
            : BrewTapPayloadSource()
        let grantSource: any TrustGrantSourcing = isUITesting
            ? AppTestTrustGrantPayloadSource()
            : BrewTrustGrantPayloadSource()
        let installed = InstalledStore(source: installedSource)
        let taps = TapStore(source: tapSource)
        let trustGrants = TrustGrantStore(source: grantSource)
        let mutations = InstalledMutationGate()
        let serviceMutations = InstalledMutationGate()
        let tapMutations = InstalledMutationGate()
        let diskMutations = InstalledMutationGate()
        let npmMutations = InstalledMutationGate()
        let refreshRegistry = MutationRefreshRegistry()
        let services = ServicesStore()
        // Under the Health fixture this points at an empty temporary file rather
        // than the real cache. Without that, a launch meant to answer *nothing*
        // silently loads the developer's own machine's disk measurement and the
        // "nothing could be scored" state becomes unreachable — a UI test that
        // passes on a fresh CI machine and fails on every real one.
        let diskCacheURL = AppTestFixtures.isHealthEnabled
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("cellar-ui-health-disk-\(UUID().uuidString).json")
            : (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Cellar/disk-usage-v1.json")
        // Redirected under the Health fixture for the same reason as the disk
        // cache: `SecurityStore.start()` loads this file with no consent and no
        // network, so a launch meant to answer nothing would otherwise adopt the
        // developer's own last scan and score 63 out of a machine nobody measured.
        let advisoryCacheURL = AppTestFixtures.isHealthEnabled
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("cellar-ui-health-advisories-\(UUID().uuidString).json")
            : (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
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
        // The artwork ladder asks the catalog whether `homebrew/cask` publishes
        // a token before it fetches anything: a third-party tap's cask has no
        // icon in either registry, so it must never cost a request.
        let catalog = CatalogStore(directory: AppTestFixtures.catalogDirectory)
        _catalog = State(initialValue: catalog)
        _caskAssets = State(initialValue: CaskBrowseAssets(publishesCask: { token in
            catalog.package(PackageID(kind: .cask, name: token)) != nil
        }))
        _brewDetection = State(initialValue: BrewDetectionStore(locator: locator))
        _installed = State(initialValue: installed)
        // Constructed unconditionally and *inert* until the preference is on:
        // the store publishes `.disabled` and probes nothing, so a build with
        // the switch off behaves exactly as a build without this capability.
        _npmDetection = State(initialValue: NpmDetectionStore())
        let npm = NpmStore(installed: installed)
        _npm = State(initialValue: npm)
        // Inert for the same reason: with no detected npm it has no environment
        // to read, so its cadence never starts and its terminals stream never
        // yields — the fifth gate is only ever opened by an `NpmCommand`.
        _npmRefresher = State(
            initialValue: NpmRefreshCoordinator(
                store: npm,
                mutations: npmMutations,
                refreshRegistry: refreshRegistry
            )
        )
        _mutations = State(initialValue: mutations)
        _serviceMutations = State(initialValue: serviceMutations)
        _tapMutations = State(initialValue: tapMutations)
        _diskMutations = State(initialValue: diskMutations)
        _npmMutations = State(initialValue: npmMutations)
        _diskUsage = State(initialValue: diskUsage)
        _cleanup = State(initialValue: CleanupStore(source: cleanupPreviewSource))
        self.cleanupPreviewSource = cleanupPreviewSource
        _taps = State(initialValue: taps)
        _trustGrants = State(initialValue: trustGrants)
        self.refreshRegistry = refreshRegistry
        _metadata = State(initialValue: stores.metadata)
        _history = State(initialValue: stores.history)
        _dismissals = State(initialValue: stores.dismissals)
        _integrity = State(
            initialValue: ArtifactIntegrityStore(
                initialReports: AppTestFixtures.isSecurityEnabled ? AppTestFixtures.integrityReports : []
            )
        )
        _health = State(
            initialValue: HealthStore(
                doctorSource: BrewDoctorSource(
                    launcher: isUITesting ? AppTestProcessLauncher() : SystemProcessLauncher()
                ),
                metadataAccess: SystemFileMetadataAccess()
            )
        )
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
                    // Both halves of what the scan must account for. The
                    // pre-decided majority — unmapped formulae, casks,
                    // uninterpretable versions — reaches the surface with its
                    // typed reason instead of being silently absent, which is
                    // what keeps the Not-covered count over the whole inventory
                    // rather than over the handful that could be asked about.
                    request: { @MainActor in
                        let plan = SecurityQueryBuilder.plan(for: installed.inventory.packages)
                        return AdvisoryScanRequest(
                            queries: plan.queries,
                            predecided: plan.outcomes.map { packageID, outcome in
                                PredecidedOutcome(
                                    packageID: packageID,
                                    installedVersion: installed.inventory.package(packageID)?
                                        .primaryKeg.version ?? "",
                                    outcome: outcome
                                )
                            }
                        )
                    }
                )
            )
        )
        // Beside `disk-usage-v1.json` and `security-advisories-v1.json`, and
        // carrying its own schema version — so a catalog field change can never
        // wipe it and reverting this slice leaves it orphaned but intact.
        //
        // Redirected under the release-notes fixture for the same reason as the
        // disk and advisory caches under the Health fixture: a rate-limited
        // launch would otherwise load a note a previous matched-mode run cached
        // on the developer's machine and show it as last-good, so the
        // rate-limited presentation becomes unreachable — a UI test that passes
        // on a fresh CI machine and fails on every real one.
        let releaseNotesCacheURL = AppTestFixtures.isReleaseNotesEnabled
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("cellar-ui-release-notes-\(UUID().uuidString).json")
            : (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Cellar/\(ReleaseNotes.cacheFileName)")
        // Under `--ui-testing-m5-release-notes` the grant is a launch argument,
        // so a UI test never has to write the developer's real preferences and
        // the ungranted path is genuinely ungranted rather than left over from a
        // previous run.
        let releaseNotesConsent = ReleaseNotesConsentPreference(
            defaults: AppTestFixtures.isReleaseNotesEnabled
                ? UserDefaults(suiteName: "cellar-ui-release-notes-\(UUID().uuidString)") ?? .standard
                : .standard
        )
        if AppTestFixtures.isReleaseNotesGranted { releaseNotesConsent.grant() }
        let releaseNotesCredentials = KeychainReleaseNotesCredentialStore()
        _releaseNotesConsent = State(initialValue: releaseNotesConsent)
        self.releaseNotesCredentials = releaseNotesCredentials
        _releaseNotes = State(
            initialValue: ReleaseNotesStore(
                source: AppTestFixtures.isReleaseNotesEnabled
                    ? GitHubReleaseNotesSource(session: AppTestReleaseNotesProtocol.session())
                    : GitHubReleaseNotesSource(),
                cache: ReleaseNotesCache(fileURL: releaseNotesCacheURL),
                // The consent preference is injected rather than read once here,
                // so revoking takes effect on the next click instead of at the
                // next launch.
                consent: releaseNotesConsent,
                credentials: releaseNotesCredentials
            )
        )
        // Cellar's own recorded answer to "may this app look for updates on its
        // own". A missing key reads `false`, and the checker writes this value
        // to the updater before starting it, so neither a bundled default nor a
        // value the framework persisted on a previous launch can decide whether
        // Cellar reaches the network.
        //
        // Under a UI-test launch the preference goes to a throwaway suite, for
        // the same reason the release-notes grant does: a UI test must never
        // write the developer's real preferences, and "off on a fresh install"
        // has to be genuinely fresh rather than left over from a previous run.
        let automaticUpdateChecks = AutomaticUpdateChecks(
            defaults: AppTestFixtures.isUpdatesEnabled
                ? UserDefaults(suiteName: "cellar-ui-updates-\(UUID().uuidString)") ?? .standard
                : .standard
        )
        // **No UI-test launch may construct `SparkleUpdateChecker`.** That is
        // what makes it structurally impossible for a UI test to start an
        // updater, reach the feed, or open an updater window — the same reason
        // `AppTestReleaseNotesProtocol` exists.
        updater = AppTestFixtures.isUpdatesEnabled
            ? AppTestUpdater() as any AppUpdating
            : SparkleUpdateChecker(automaticChecks: automaticUpdateChecks)
        // Beside `disk-usage-v1.json` and the other derived caches, carrying
        // its own schema version for the same reason each of them does.
        let caskChartsDirectory = isUITesting
            ? FileManager.default.temporaryDirectory
                .appendingPathComponent("cellar-ui-cask-charts-\(UUID().uuidString)", isDirectory: true)
            : (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("Cellar", isDirectory: true)
        _caskCharts = State(
            initialValue: CaskChartsStore(
                source: isUITesting ? AppTestCaskChartsSource() : HTTPCaskChartsSource(),
                directory: caskChartsDirectory
            )
        )
        _formulaCharts = State(
            initialValue: CaskChartsStore(
                source: isUITesting
                    ? AppTestCaskChartsSource()
                    : HTTPCaskChartsSource(
                        baseURL: HTTPCaskChartsSource.formulaBaseURL,
                        kind: .formula
                    ),
                directory: caskChartsDirectory,
                cacheFileName: "formula-charts-v1.json"
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
                grants: trustGrants,
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
                    ,(.npmInventory, npmMutations)
                ]),
                history: SwiftDataHistoryRecorder(store: stores.history),
                refreshRegistry: refreshRegistry,
                launcherFactory: { _ -> any ProcessLaunching in
                    if isUITesting { return AppTestProcessLauncher() }
                    return SystemProcessLauncher()
                }
            )
        )
        // The status item is opt-in and off by default, so a missing key reads
        // `false` and the third scene is simply not inserted.
        //
        // Under a UI-test launch the preference goes to a throwaway suite, for
        // the same reason the release-notes grant and the update-check answer
        // do: a UI test must never write the developer's real preferences.
        // Gated on `AppTestFixtures.isEnabled` rather than a feature-specific
        // flag, because there is no menu-bar fixture — every UI-test launch has
        // to be kept out of the real domain, not only the ones that opted in.
        _menuBar = State(
            initialValue: MenuBarPreference(
                defaults: isUITesting
                    ? UserDefaults(suiteName: "cellar-ui-menu-bar-\(UUID().uuidString)") ?? .standard
                    : .standard
            )
        )
    }

    var body: some Scene {
        // Identified so `openWindow(id:)` can serve it, which is what lets
        // "Open Cellar" work with every window closed — the route the About
        // window already uses, rather than an AppKit activation path.
        WindowGroup(id: "main") {
            ContentView(
                brewDetection: brewDetection,
                npmDetection: npmDetection,
                npm: npm,
                catalog: catalog,
                installed: installed,
                operations: operations,
                metadata: metadata,
                history: history,
                caskAssets: caskAssets,
                caskIcons: caskIcons,
                caskCharts: caskCharts,
                formulaCharts: formulaCharts,
                services: services,
                servicesRefresher: servicesRefresher,
                taps: taps,
                trustGrants: trustGrants,
                diskUsage: diskUsage,
                cleanup: cleanup,
                cleanupPreviewSource: cleanupPreviewSource,
                // The ordinary `NSOpenPanel`, unless this launch is a UI test.
                brewfileSourceChooser: AppTestFixtures.brewfileSourceChooser,
                health: health,
                security: security,
                securityConsent: securityConsent,
                advisoryCredentials: advisoryCredentials,
                dismissals: dismissals,
                integrity: integrity,
                artifactLocations: artifactLocations,
                refresh: { await refreshEverything() }
            )
                // Injected rather than threaded through four view signatures.
                // Deliberately **not** accompanied by a `.task`: nothing here
                // starts release-notes work, and the only thing that can is a
                // button.
                .environment(theme)
                // The design is one appearance: a dark window with its own
                // surface colours, not a system-material chrome. The tint is
                // the chosen accent, so list selection and native controls
                // follow the same colour every custom surface derives from.
                .tint(theme.base)
                .preferredColorScheme(.dark)
                .environment(releaseNotes)
                .environment(releaseNotesConsent)
                // Read by the Settings card, which is the only surface in the
                // window that knows about the status item at all.
                .environment(menuBar)
                .environment(\.releaseNotesCredentials, releaseNotesCredentials)
                .environment(\.appUpdater, updater)
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
                // The npm terminals consumer, on the same terms as the four
                // above. It costs nothing while the source is off: no npm
                // command can be built without a detected npm, so the fifth gate
                // never settles and this loop never wakes.
                .task { loops.start("npm") { await npmRefresher.run() } }
                // Detection is the only thing that starts or stops npm's
                // cadence. `initial: true` covers a launch with the source
                // already on; the change covers the switch being flipped while
                // the app runs, which is the "without a relaunch" requirement.
                .onChange(of: npmDetection.state, initial: true) { _, state in
                    Task { await npmRefresher.apply(state) }
                }
        }
        // The design's window: traffic lights floating over the sidebar, no
        // separate title bar, 1440×900 by default.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            AboutCommands()
            CheckForUpdatesCommands(updater: updater)
        }

        Window("About \(AppIdentity.name)", id: "about") {
            AboutView()
                .environment(theme)
                .tint(theme.base)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // The third scene: a status item carrying the outdated count, inserted
        // only while the preference says so.
        //
        // The title argument is where the projection's **absence** meets a
        // framework that wants a `String`, and it is the only place that
        // adaptation happens — no source under `cellar/MenuBar/` ever sees it.
        //
        // The outer ternary is load-bearing rather than defensive. `?:`
        // short-circuits, so with the feature off — the default — the
        // projection is never composed, `installed.inventory` is never read
        // inside `App.body`, and no observation is established at App level at
        // all. That is what makes "no other observable difference" structural
        // rather than hoped for.
        MenuBarExtra(
            menuBar.isShown ? (menuBarProjection.statusItemTitle ?? "") : "",
            systemImage: "shippingbox",
            isInserted: Binding(get: { menuBar.isShown }, set: { menuBar.isShown = $0 })
        ) {
            MenuBarPopoverView(
                projection: menuBarProjection,
                operations: operations,
                openMainWindow: { openWindow(id: "main") }
            )
                // Environment injection is per-scene, so the three the About
                // window repeats are repeated here for the same reason: a scene
                // that omits them renders in system chrome while the rest of
                // the app is the design's dark surface.
                .environment(theme)
                .tint(theme.base)
                .preferredColorScheme(.dark)
                // The one asynchronous hop this surface is allowed, and it
                // lives here rather than in the popover so the prohibition on
                // `cellar/MenuBar/` can be absolute. It reports no visibility,
                // starts no poll and schedules nothing on the clock.
                .task { await servicesRefresher.refreshBaseline() }
        }
        .menuBarExtraStyle(.window)
    }

    /// Everything the menu bar shows, composed from the instances the window
    /// already reads.
    ///
    /// Recomputed per body evaluation and never memoized: a cache would be a
    /// second source of truth, and this is one set-membership filter over an
    /// array the sidebar badge already walks on every render.
    @MainActor
    private var menuBarProjection: MenuBarProjection {
        let browse = InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil)
        return MenuBarProjection(
            browse: browse.withNpmSource(NpmSourceAvailability(npmDetection.state)),
            metadata: metadata.availability.isAvailable ? metadata.snapshot.lookup : nil,
            services: services.services,
            // A value, never the store: the projection stays pure over its four
            // inputs and can neither start a check nor learn one is running.
            npmFreshness: npm.inventory.outdated
        )
    }

    /// Detection first, then everything that depends on it.
    ///
    /// The operation centre is attached from the same place, so mutations become
    /// available the moment brew does and go unavailable the moment it stops
    /// being — with no restart either way (package-mutation PM7).
    /// The brew-managed artifacts worth assessing.
    ///
    /// Built from Homebrew's **own roots** and from the inventory brew reported.
    /// `/Applications` is never enumerated: cask bundles are reached through the
    /// path Homebrew recorded, which the U3 probe confirmed is a symlink the
    /// locator resolves rather than a directory it walks.
    @MainActor
    private var artifactLocations: [ArtifactLocation] {
        guard let installation = brewDetection.state.installation else { return [] }
        let roots = HomebrewRoots(
            installation: installation,
            userCacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
        )
        return ArtifactLocator(cellar: roots.cellar, caskroom: roots.caskroom)
            .locations(for: installed.inventory.packages)
    }

    /// Pushes the stored preference into detection and re-evaluates it.
    ///
    /// The preference lives in `UserDefaults` and has to be honoured at launch,
    /// not only while the Settings pane happens to be open — "the choice MUST
    /// survive relaunch" (`npm-source`). With the source off this sets
    /// `isEnabled` to the `false` it already holds, publishes `.disabled`, and
    /// spawns nothing: the store gates the probe at its source.
    ///
    /// It attaches the environment to the operation centre per source, so a Mac
    /// with no Homebrew still runs npm mutations and a Mac with npm off still
    /// runs brew's (PM7 as modified). It starts no cadence: only detection does
    /// that, through the scene's `onChange`.
    @MainActor
    private func refreshNpm() async {
        let preference = NpmSourcePreference()
        npmDetection.isEnabled = preference.isEnabled
        npmDetection.configuredPath = preference.configuredPath
        await npmDetection.refresh()
        operations.attach(npm: npmDetection.state.environment)
    }

    @MainActor
    private func refreshEverything() async {
        await brewDetection.refresh()
        operations.attach(installation: brewDetection.state.installation)
        await refreshNpm()
        await refresher.refresh(for: brewDetection.state)
        await tapsRefresher.refresh(for: brewDetection.state)
        // Services becomes available the moment brew does, and the poll starts
        // itself if the surface is already showing — which is the ordinary
        // launch order, since detection resolves after the first render.
        await servicesRefresher.refresh(for: brewDetection.state)
        // The npm listing rides the same baseline brew's inventory does; the
        // registry check deliberately does not (`npm-source`: activation does
        // not trigger the npm check).
        await npmRefresher.activate()
        readHomebrewAge()
        startDiskMeasurement()
    }

    /// The same cache-then-scan sequence `CleanupView` runs on appearance, run
    /// once per launch so the measurement exists before any section asks.
    /// Guarded off under UI-test fixtures exactly as the Cleanup path is: the
    /// fixtures inject their own snapshot and must not be overwritten.
    @MainActor
    private func startDiskMeasurement() {
        guard !hasStartedDiskMeasurement,
              !AppTestFixtures.isEnabled,
              let installation = brewDetection.state.installation
        else { return }
        hasStartedDiskMeasurement = true
        let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let roots = HomebrewRoots(installation: installation, userCacheDirectory: cacheDirectory)
        let links = Dictionary(
            uniqueKeysWithValues: installed.inventory.packages.map { ($0.id, $0.formulaLinkState) }
        )
        Task {
            await diskUsage.loadCached(for: roots.identity)
            diskUsage.startScan(roots: roots, formulaLinks: links)
        }
    }

    /// One `attributesOfItem` behind a seam: no process, no network, and no
    /// chance for Homebrew to auto-update on the way (`system-health`, "The
    /// last-update reading costs no brew invocation").
    @MainActor
    private func readHomebrewAge() {
        guard let installation = brewDetection.state.installation else { return }
        health.readLastUpdate(
            roots: HomebrewRoots(
                installation: installation,
                userCacheDirectory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
            ),
            now: Date()
        )
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
