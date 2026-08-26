# Exploration — m12-menu-bar (PRD §3.8 menu bar extra)

**As-of anchor**: `main` @ `f2efbdd57a774f45adcee90511d68da478185a5f` (`.git/refs/heads/main`). Repository root `/Users/juancasanueva/programming/swiftUI/cellar`.

Artifact store: hybrid — Engram topic `sdd/m12-menu-bar/explore` (observation 7819); OpenSpec file `openspec/changes/m12-menu-bar/explore.md` (this file, persisted by the orchestrator from the Engram observation because the explore executor had no write tool).

Exploration only. No proposal, no implementation.

## 1. Scope restated

PRD.md:113 promises one thing: an optional `MenuBarExtra` with an outdated count badge, top outdated packages, quick "upgrade all", quick service toggles, and "open main window". PRD.md:114–115 (SMAppService login item, periodic schedules, `UNUserNotificationCenter`) are explicit **non-goals** for m12.

The codebase contains zero `MenuBarExtra` today. The only occurrence of the phrase is `cellar/Settings/SettingsView.swift:14`, which records the rule this change must honour and must then amend.

## 2. App composition — the state-sharing problem is already solved

`cellar/cellarApp.swift` owns every store as app-level `@State` (lines 23–194): `brewDetection`, `catalog`, `installed`, four `InstalledMutationGate`s, `refresher`, `taps`, `trustGrants`, `tapsRefresher`, `diskUsage`, `diskRefresher`, `cleanup`, `health`, `security`, `securityConsent`, `releaseNotes`, `dismissals`, `integrity`, `operations`, `metadata`, `history`, `services`, `servicesRefresher`, `theme`, `caskAssets`, `caskIcons`, `caskCharts`, `formulaCharts`, `loops`. Everything is constructed in `init()` (cellarApp.swift:201–469).

The ownership rationale is already written down at cellarApp.swift:183–194: "App-level state outlives every scene, so closing the window that started Cellar no longer cancels the catalog refresh schedule". `LoopOwner` (`Packages/CellarCore/Sources/BrewClient/LoopOwner.swift:19–38`) enforces one loop per id per launch, and `installed-inventory` spec:475–480 requires exactly that.

**Consequence: a second `Scene` needs no new store and no new loop.** A `MenuBarExtra` sibling of the existing `WindowGroup` reads the same `@Observable` instances the window reads. This is the single most important structural finding.

Two scenes exist today (cellarApp.swift:471–571):
- `WindowGroup { ContentView(...) }` — `.windowStyle(.hiddenTitleBar)`, `.defaultSize(1440×900)`, `.commands { AboutCommands(); CheckForUpdatesCommands(updater:) }`. **No `id:`.**
- `Window("About Cellar", id: "about") { AboutView() }` — the precedent for a second scene, and it repeats `.environment(theme)`, `.tint(theme.base)`, `.preferredColorScheme(.dark)` (cellarApp.swift:562–570).

Environment injection is **per-scene**, not per-app: `.environment(theme)`, `.tint`, `.preferredColorScheme(.dark)`, `.environment(releaseNotes)`, `.environment(releaseNotesConsent)`, `.environment(\.releaseNotesCredentials, …)`, `.environment(\.appUpdater, …)` all hang off the `WindowGroup`'s content (cellarApp.swift:506–516). A menu-bar scene must repeat whatever its content reads, exactly as the About window does, or it renders in the system appearance while the rest of the app is the design's dark surface.

"Open main window": `AboutView.swift:152–156` is the only `openWindow` call site (`@Environment(\.openWindow)` → `openWindow(id: "about")`). The `WindowGroup` carries no `id`, so "open main window" needs either an `id:` added to it (one line, then `openWindow(id:)` works) or an AppKit activation path. Adding the id is the smaller and more idiomatic change.

`scenePhase` is read at cellarApp.swift:199 and applied at cellarApp.swift:525–527 — `.onChange(of: scenePhase, initial: true) { servicesRefresher.setActive(phase == .active) }` — **attached to the `WindowGroup`'s content**. With every window closed, that modifier's view no longer exists, so the "app is active" half of the services visibility conjunction becomes unreported. Any design that keeps the menu bar alive with no window must not assume `scenePhase` still drives that setter.

Activation refresh: `observeActivations()` (cellarApp.swift:649–657) awaits `NSApplication.didBecomeActiveNotification` and calls `refreshEverything()` (596–608). Clicking a status item does not reliably activate the app, so a popover can open on an inventory snapshot older than the window's would be.

## 3. Outdated projection — there are two answers today, and they disagree

The derivation ladder:

- `InstalledPackage.isOutdated` — `Packages/CellarCore/Sources/BrewClient/InstalledModels.swift:126–131`. Formula: the snapshot flag verbatim. Cask: `snapshotOutdated && !isSelfUpdating` (installed-inventory spec:159 "Auto-updating casks never count as outdated").
- `InstalledInventory.outdatedIDs` — InstalledModels.swift:188, built once in the off-main decode pass. `outdatedCount` — InstalledModels.swift:200.
- `InstalledBrowse.outdatedIDs(metadata:)` — `InstalledFilterMode.swift:171–180`. Projects snoozed packages out; degrades to `inventory.outdatedIDs` with no metadata. `outdatedCount(metadata:)` — InstalledFilterMode.swift:182–184.
- `InstalledBrowse.upgradableIDs(includingDependencies:metadata:)` — InstalledFilterMode.swift:197–206. Outdated minus pinned, no unpin submitted on their behalf (package-mutation PM2).

Consumers, split into two camps:

| Surface | Reads | Snooze-aware |
|---|---|---|
| Updates list sections | `InstalledListView.swift:313` → `browse.outdatedIDs(metadata: lookup)` | yes |
| Updates lens filter | `InstalledListView.swift:274` | yes |
| Bulk upgrade label + submission | `InstalledListView.swift:287–289, 232–234` → `upgradableIDs` | yes |
| Health outdated reading | `cellar/Health/HealthComposition.swift:71` | yes |
| **Sidebar "Updates" badge** | `cellar/Shell/SidebarView.swift:217–219` → `installed.inventory.packages.filter(\.isOutdated).count` | **no** |
| **Home attention card** | `cellar/Home/HomeView.swift:142` → `installed.inventory.packages.filter(\.isOutdated)` | **no** |

`SidebarView` is handed `metadata` at SidebarView.swift:25 and uses it for `favoritesCount` (210–215) but not for `outdatedCount`. `installed-inventory` spec:495–505 states a snoozed package "MUST NOT contribute to the outdated count **or badge**", so the sidebar badge is already at odds with its own capability spec, and `HomeView`'s attention sentence with it.

**The menu bar would be the third consumer of this number.** The prompt's requirement — "the menu bar can never disagree with the sidebar badge" — is currently satisfiable in two mutually exclusive ways: match the correct projection (and diverge from today's sidebar), or match today's sidebar (and violate II). The design must choose, and the honest choice is `InstalledBrowse.outdatedCount(metadata:)` plus aligning `SidebarView` and `HomeView` in the same change. That alignment is small in lines but changes a number a user already sees, so it is a scope decision for the proposal, not something to slip in.

## 4. Upgrade all — no confirmation is owed, and that removes the hard problem

`MutationCommand.upgradeAll` lowers to bare `["upgrade"]` (`MutationCommand.swift:271–272`) and `requiresConfirmation` is **false** (MutationCommand.swift:291–296). package-mutation spec:245–251 ("Non-destructive mutations run without confirmation") and spec:180–186 ("Upgrade all is a bare brew upgrade") confirm it.

So a menu-bar "Upgrade all" is `operations.submit(.upgradeAll)` and nothing else — exactly what `HomeView.swift:159` already does from an attention card, and what `InstalledListView.swift:236–238` does from the bulk bar. **No sheet is required, so "can a popover present a sheet" does not block this milestone.**

Two related duties remain:

1. **PM3 exact-command disclosure.** The gate itself covers uninstall and zap only (package-mutation spec:194–220), and the confirmation sheet renders `displayCommand` verbatim (`cellar/Activity/MutationConfirmation.swift:61–69`). The app's own convention nonetheless puts a copy affordance beside the non-confirmed bulk button: `CopyCommandButton(text: MutationCommand.upgradeAll.displayCommand)` at InstalledListView.swift:241, and PRD.md:119 makes "Copy command everywhere" a cross-cutting promise. The menu should carry the same honesty (show or copy `brew upgrade`).
2. **II "A bulk action's label counts exactly the set it submits"** (installed-inventory spec:647–652). This is the sharpest constraint on the menu's layout: a button labelled with N that submits bare `brew upgrade` announces one number and submits a different set (bare upgrade covers everything brew considers outdated, ignoring Cellar's snooze exclusion and its dependency toggle). Two compliant shapes: (a) badge shows N, the button says "Upgrade all" with no count and copies `brew upgrade`; (b) the button says "Upgrade outdated (N)" and submits `operations.submitUpgrades(for: upgradableIDs, in: installed.inventory)` — the fan-out at `OperationCenterBulk.swift:29–38`.

**A latent hazard worth recording even though m12 raises no confirmation.** `pendingConfirmation` lives on the shared `OperationCenter` (OperationCenter.swift:35, box at `OperationCenterBulk.swift:387–507`), and the only presenter is `ContentView.body`'s `.mutationConfirmation(...)` (ContentView.swift:163–167) — a `.sheet(item:)` on the window. If any menu-bar affordance ever raised a request with no window open, the request would latch unanswered and block later confirmations. The design should state explicitly that the menu bar raises no confirmation, or that raising one opens the main window first.

## 5. Services — "quick toggles" is the phrase that needs the most care

- Four verbs, no `--all`, one invocation per service: `ServiceCommand.swift:64–97` and its file header point 4; service-management spec:143–157.
- **Start-at-login and run-once are two controls, never one flag**: `ServiceRowControl` (`ServiceCommand.swift:245–285`), `.start` = "Start at login", `.run` = "Run once", and `isLoginRegistering` is true for exactly one of them (ServiceCommand.swift:272). service-management spec:196 makes it a requirement. **A single per-service switch in a menu would violate it**, because "on" would have to silently pick one. Honest menu shapes: a running service offers `Stop` and `Restart` (unambiguous); a stopped service offers both `Start at login` and `Run once` as separately labelled items.
- No service verb requires confirmation (ServiceCommand.swift:143; service-management spec:156–157).
- Submission goes through `operations.submit(service:)` with the per-service in-flight guard (`OperationCenterServices.swift:33–39`), which returns the existing item rather than queueing a contradictory second one.
- **The poll.** `ServicesRefreshCoordinator` (whole file) gates a 5-second poll on `isVisible = isSectionVisible && isAppActive` (line 62). The two halves are reported from two places on purpose — `ServicesListView.swift:58–59` (`onAppear`/`onDisappear`) and cellarApp.swift:525–527 (`scenePhase`) — and the type's own comment (lines 52–58) explains that folding them into one setter would let whichever reported last overrule the other. service-management spec:100–113 requires polling to stop **entirely** when not visible and at most one poll loop per launch. The poll deliberately is not a `LoopOwner` slot (ServicesRefreshCoordinator.swift:16–23).

  An open popover showing live service state is a visible services surface by any honest reading, yet it is not the Services section and the app may not be `.active`. Three candidate answers: (i) the popover reports visibility like the section does — but `setVisible` is one boolean shared with the section, so the existing two-half conjunction is the precedent for adding a **third reported half** rather than overloading one; (ii) the popover shows last-known state and performs one baseline refresh on open, with no poll — cheapest, and it keeps "no poll while not visible" literally true; (iii) the popover shows no service state at all and only offers verbs. (ii) is the recommendation to carry into design.

## 6. Egress and process discipline — the structural test net the menu bar lands in

- `AppTestFixtures.isEnabled` (`cellar/AppTestFixtures.swift:22–36`) selects every seam at composition time; `CaskIconLoader(isDisabled: AppTestFixtures.isEnabled)` (cellarApp.swift:167) is the artwork kill switch; the updater is never the real one under a UI-test launch (cellarApp.swift:386–392).
- **Source-scanning suites read every `.swift` under `cellar/` automatically.** `AppSecuritySources.load()` enumerates the whole app target and strips comments so a prohibition *described* is never mistaken for one *violated* (`cellarTests/SecurityCompositionSupport.swift:42–86`). Any new menu-bar file is inside that sweep from the moment it exists.
- Token prohibitions already in force, by precedent: `HealthCompositionTests.swift:339,349,505` scans `.task` blocks and forbids `ProcessLaunching`, `URLSession`, `CatalogStore`, `SecurityStore`, `InstalledStore` inside them; `TapSearchCompositionTests.swift:936` and `ReceiptDetailCompositionTests.swift:49` forbid `refresh`, `.task`, `Task {`, `await `, `async ` in named view files; `ReleaseNotesEgressCompositionTests.swift:145` forbids `.task {`, `.task(`, `.onAppear`, `.onHover`, `.onChange`, `.onReceive` in the release-notes surface; `HealthRemediationTests.swift:125–146` forbids `Process(`.
- **Design consequence**: the popover must be a projection *reader*, not a loader. No `.task`, no `Process`, no `URLSession` in the menu-bar view file, and no `PackageIconTile`/`CaskIconLoader` artwork (that pipeline reaches the network; `InstalledListView.swift:43–45` documents that passing `nil` keeps the letter tile). A menu-bar list showing cask icons would be a brand-new egress surface fired by opening a popover.
- `cellarTests/AppSectionPlacementTests.swift` pins app-shell shape: `AppSection.allCases.count == 22` and the exact rawValue list (lines 36, 54–62); every `AppSection` switch must cover `.health` and carry no `default:` (146–172); and `switches.filter { $0.file == "ContentView.swift" }.count == 3` is asserted literally (line 159). A menu bar is not a section and should add none; if it ever introduces an `AppSection` switch, it belongs in its own file, and any change to ContentView's switch count is a deliberate edit to that literal.

## 7. Settings — the rule, and where a toggle would live

`SettingsView.swift:9–15` states it verbatim: "Rows the design sketches for capabilities Cellar does not have (background schedules, a menu bar extra) are deliberately absent rather than present-but-inert." The comment **names the menu bar extra**, so shipping the capability requires amending this doc comment in the same change — leaving it would make the file assert something false about itself.

Structure to reuse: `group(_:rows:)` (SettingsView.swift:101–111), `row(label:sub:accessory:)` (117–136), and `UpdatesSettingsGroup()` (77) — the precedent for a self-contained card in its own file whose whole surface rolls back by deleting one file and one line.

Persistence precedents, in order of fit:
1. `AutomaticUpdateChecks(defaults:)` (cellarApp.swift:381–385) and `ReleaseNotesConsentPreference(defaults:)` (349–353) — a small preference type over `UserDefaults` with an injectable suite so a UI-test launch never writes the developer's real preferences. Best fit.
2. `ThemeStore` (`cellar/Theme/ThemeStore.swift:16–32`) — `@Observable` with plain `UserDefaults` read/write in a `didSet`. Note this already avoids the `@AppStorage`-inside-`@Observable` trap the swiftui-patterns skill calls out (observation tracking never sees an `@AppStorage` change).
3. `ContentView.listPaneWidths` (ContentView.swift:88–126) — `@State` cache over per-key `UserDefaults`, used because `@AppStorage` cannot vary its key.
4. SwiftData (`LocalStores`, cellarApp.swift:129–143) is for **data** — favorites, notes, snoozes, history, dismissals — not preferences. A menu-bar visibility toggle does not belong there.

One mechanical caveat for the design: `MenuBarExtra(isInserted:)` takes a `Binding<Bool>`, and the `App` struct is not a `View`, so `@Bindable` is unavailable there. The shape matching this codebase is an `@Observable` preference held as app-level `@State` plus a manual `Binding(get:set:)`, or an `@AppStorage` declared directly on the `App` (which does work, since `App` is a `DynamicProperty` host) — the design should pick one and say why.

## 8. Theme and design reuse

Available and already app-wide: `ThemeStore.base/light/dark/tint(_:)` (ThemeStore.swift:57–63), `View.themeCard(...)` (`cellar/Theme/Theme.swift:139`), `Theme.mono`, `Theme.windowBackground`, `Theme.textPrimary`, `Theme.separator`, `StatusPill` (`cellar/Browse/StatusPill.swift:22`), `PackageIconTile` (`cellar/Casks/CaskIconView.swift:80`), `ActionPillStyle` (`cellar/Theme/PaneSearchField.swift:49`), `ShellChipButtonStyle` (`cellar/Shell/ShellToolbar.swift:87`), `HairlineDivider`, `SectionHeader`.

`.menuBarExtraStyle(.window)` vs `.menu`:

| | `.window` | `.menu` (default) |
|---|---|---|
| Content | Real SwiftUI view hierarchy in a panel | Native `NSMenu` items only |
| Theme reuse | Full — `themeCard`, `StatusPill`, tints all apply | None; system menu appearance, custom views ignored or degraded |
| Design drift risk | Low, because it reuses the same components | High, because the menu cannot look like the app |
| Keyboard / VoiceOver | Must be built | Free, native |
| Sheets / confirmations | Not reliably presentable | Not presentable |
| Complexity | Medium | Low |

The **badge** itself has no dedicated API: `MenuBarExtra` has no badge modifier. The count reaches the menu bar either as a title string (`MenuBarExtra("\(count)", systemImage: …)`, which macOS renders as text beside the icon) or as a rendered `NSImage`/`ImageRenderer` composite. The text label is the honest, cheap answer and is an open question rather than a decision.

## 9. Testing seams

- XCUITest launches with `XCUIApplication().launchArguments` plus a `--ui-testing-*` flag (`cellarUITests/cellarUITests.swift:331–350`, `HealthSectionUITests.swift:271–273`, `TapTrustUITests.swift:82–83`, etc.). No existing UI test touches `statusItems` or `menuBars`.
- A `MenuBarExtra` status item lives in the system status bar. `XCUIApplication.menuBars` reaches the app's **main** menu bar, not the status bar; status items are typically reached through the system UI process, are macOS-version-sensitive, and are a known source of flakiness. The archived m6 verify report already records XCUITest window-visibility flakiness on this project ("app menu bar present but no Window in the accessibility tree" — `openspec/changes/archive/2026-08-22-m6-tip-jar/verify-report.md:198`), and a Taps UI-test fix is open backlog.
- **Recommended proof strategy**: (a) pure value tests in `Packages/CellarCore` for whatever projection the menu reads (`swift test` inner loop, no app target, no window); (b) app-target composition/source-scan tests in the `AppSecuritySources` idiom for the structural claims — the badge reads `outdatedCount(metadata:)` and nothing else; the menu file contains no `.task`/`Process(`/`URLSession`/`CaskIconLoader`; the scene repeats the theme environment; `isInserted` is bound to the preference; the app declares exactly the expected number of scenes. Treat any status-item XCUITest as optional and non-blocking.

## 10. Specs touched

Existing capabilities under `openspec/specs/`:

- `installed-inventory` — owns `isOutdated`, `outdatedIDs`, the snooze/badge clause (spec:495–505), the label-equals-submission clause (spec:647–652), and app-lifetime loops (spec:475–480). Consumed, and likely **MODIFIED** if the badge alignment lands here.
- `package-mutation` — upgrade scopes (spec:152–164) and the confirmation gate (spec:194–220). Consumed; probably no delta unless a new submission shape appears.
- `service-management` — poll visibility (spec:100–113, which names exactly two reasons a surface stops being visible), four verbs (spec:143–157), start-vs-run distinctness (spec:196). Likely **MODIFIED**: a menu-bar surface is a third visibility reporter and the spec should say so rather than leave it implied.
- `app-updates` — unrelated (it is Sparkle/Cellar's own updates, not package updates). Not touched.
- **There is no `settings` capability spec.** The SettingsView rule lives in a doc comment plus `AppSectionPlacementTests`. A "Show in menu bar" toggle has no spec home today.

**A new capability `menu-bar` is warranted.** It would own: the scene's existence and its preference; the badge's single-projection duty; what the popover may and may not do (no egress, no loader, no confirmation, no artwork pipeline); the visibility contract it reports to services; and "open main window". Folding it into `installed-inventory` would put scene composition into a capability whose subject is an inventory value type.

Tension to record: `openspec/config.yaml:47` requires specs to "specify observable behavior of CellarCore types without referencing SwiftUI views", and most menu-bar behaviour is app-target scene composition. The honest split is the one Health, tap-search and release-notes already use: put the **projection** in `CellarCore` as a testable value (a `MenuBarProjection`-shaped type over the inventory and metadata), spec that, and prove the scene wiring with app-target composition/source-scan tests.

## 11. Candidate approaches

### A. `.window`-style `MenuBarExtra` reusing the app's stores — recommended
Add a third `Scene` to `cellarApp` beside `WindowGroup` and the About `Window`, gated by `isInserted:` on a `UserDefaults`-backed preference, repeating the theme environment like the About window does. Content is a small view reading `installed`, `metadata`, `services`, `operations` — the same instances the window reads.

- Pros: no new store, no new loop, no duplicated state; full theme reuse so the popover cannot drift; badge and list read one projection; the existing composition-test net covers the new file automatically; "upgrade all" needs no confirmation so it is a one-line submit; rollback is deleting one file and one scene block.
- Cons: keyboard and VoiceOver must be built by hand; the badge needs a rendering decision; the services visibility question must be answered honestly; `scenePhase` no longer reports when all windows are closed.
- Effort: **Medium**.

### B. `.menu`-style native items
Native `NSMenu` items only: a title carrying the count, a section of top outdated package names, "Upgrade all", per-service verbs, "Open Cellar".

- Pros: lowest complexity; free keyboard, VoiceOver and menu semantics; no window/panel lifecycle at all; impossible to accidentally start a loader inside a native menu item.
- Cons: cannot carry the design at all — no `themeCard`, no `StatusPill`, no accent tint — so the menu looks like a different app; PRD's "outdated count badge" degrades to a plain title string; no room for a rich top-outdated presentation.
- Effort: **Low**.

### C. Separate lightweight projection type (composable with A or B)
Introduce a `Sendable` value in `BrewClient` — count, top-N outdated entries, service summary — derived from `InstalledBrowse` and `ServicesStore`, and have the menu read only that.

- Pros: makes "the menu and the sidebar cannot disagree" a testable property of a value rather than of two view files that happen to concur — precisely the `upgradableIDs` precedent (InstalledFilterMode.swift:186–196, "the M2-2 defect where the button counted the dependency-filtered entries while the submission filtered the whole inventory"); it is spec-able CellarCore behaviour, which resolves the config.yaml:47 tension; testable in the fast `swift test` loop.
- Cons: one more type; risks becoming a second source of truth if it recomputes rather than delegates — it must be a projection *over* `InstalledBrowse`, never a reimplementation.
- Effort: **Low–Medium** on top of A.

### D. AppKit `NSStatusItem` + `NSHostingView`
- Pros: total control over the status-item image, including a genuine drawn badge.
- Cons: hand-rolled lifetime and teardown; an `NSStatusItem` is a new AppKit surface in a target whose composition rules are structurally policed; strictly more code than A for a badge-rendering benefit A can also reach via `ImageRenderer`.
- Effort: **High**. Not recommended.

**Recommendation for the proposal to weigh: A + C.** A because every store is already app-level and the theme components are already there; C because the disagreement risk the topic names is exactly the failure `upgradableIDs` was created to prevent, and a value type is the only way to make it a test rather than a habit.

## 12. Open questions for the proposal

1. **Badge projection alignment.** Does m12 also fix `SidebarView.swift:217–219` and `HomeView.swift:142` to use `outdatedCount(metadata:)`? Matching today's sidebar means violating installed-inventory spec:499; matching the spec means changing a number users already see. This must be decided before the spec is written.
2. **"Upgrade all" label shape.** Badge-N plus an uncounted "Upgrade all" (bare `brew upgrade`), or a counted "Upgrade outdated (N)" submitting the `upgradableIDs` fan-out? II spec:647–652 forbids the mixture.
3. **Services in the popover.** Live poll (needs a third visibility half in `ServicesRefreshCoordinator`), one baseline refresh on open with no poll, or last-known state only?
4. **Which service controls appear.** Stop/Restart for running services and both `Start at login` and `Run once` for stopped ones — or a narrower set? A single toggle is not available (spec:196).
5. **How the count reaches the status item** — title string vs rendered image.
6. **"Top outdated packages" — how many, ordered how?** The inventory is sorted by name (InstalledModels.swift:193–196); there is no recency or severity order for outdated packages today.
7. **Where "Show in menu bar" persists and how the `Binding<Bool>` is formed** at the `App` level.
8. **Default on or off?** The PRD says "optional". Cellar's convention for anything with a cost is off by default (`AutomaticUpdateChecks`, both consent preferences).
9. **Does the `WindowGroup` gain an `id:`** so `openWindow(id:)` can serve "open main window"?
10. **Does the menu-bar surface get its own `--ui-testing-*` fixture flag**, and is any XCUITest of the status item in scope at all?
11. **New capability spec `menu-bar` — yes or no**, and what part of it lives in `CellarCore` versus composition tests.

## 13. Non-goals (explicit)

- Background update checks, `SMAppService`, login items, periodic `brew update`, scheduled re-scans (PRD.md:114).
- User notifications / `UNUserNotificationCenter` of any kind (PRD.md:115).
- Any Settings row for schedules or notifications — the `SettingsView.swift:9–15` rule still forbids rows for capabilities that do not exist.
- Uninstall, zap, or any confirmation-requiring mutation from the menu bar.
- Cask artwork in the popover (a new egress surface).
- A new `AppSection`; the menu bar is a scene, not a section.
- Localization work beyond what the app already does.

## 14. Risks

1. **Two outdated numbers already exist in the shipped app.** Adding a third consumer without settling question 1 ships a menu bar that disagrees with either the sidebar or the spec. Highest-severity risk, and it is pre-existing rather than introduced.
2. **Services visibility.** A naive `setVisible(true)` from the popover collides with the section's own reporting and can leave the poll running after the section closes — service-management spec:106–109 says polling must stop entirely. The coordinator's two-half conjunction (ServicesRefreshCoordinator.swift:52–62) exists because of exactly this class of bug.
3. **`scenePhase` reporting with no window.** cellarApp.swift:525–527 hangs off the `WindowGroup`'s content; a windowless launch with only the menu bar leaves `setActive` unreported and the last value latched.
4. **A latched confirmation.** `pendingConfirmation` is presented only by `ContentView` (ContentView.swift:163–167). Any menu-bar path that could raise one with no window open would block the whole confirmation channel.
5. **Egress by accident.** `PackageIconTile`/`CaskIconLoader` in a popover would fire artwork requests on every open. The existing egress composition suites will catch it only if the design plans a matching prohibition test.
6. **Structural test breakage.** `AppSectionPlacementTests.swift:159` pins ContentView's switch count at 3 and lines 36/54–62 pin the section vocabulary; new source files enter `AppSecuritySources.load()`'s sweep automatically.
7. **Menu-bar accessibility.** A `.window`-style popover gets no free keyboard or VoiceOver support; PRD.md:123 promises full keyboard navigation and VoiceOver labels on all controls.
8. **XCUITest reach.** Status items are not reliably reachable from `XCUIApplication`, and this project already has recorded UI-test flakiness. Planning the milestone's proof around UI tests would be a mistake.
9. **Stale data on open.** The activation refresh is keyed to `NSApplication.didBecomeActiveNotification` (cellarApp.swift:649–657); a status-item click may not activate the app.
10. **Settings doc comment.** `SettingsView.swift:14` names the menu bar extra as a capability Cellar does not have. Shipping without amending it leaves the file asserting something false.
