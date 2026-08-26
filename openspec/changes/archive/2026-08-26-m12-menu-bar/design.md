# Design: an optional menu bar extra over one outdated projection (`m12-menu-bar`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec canonical + Engram mirror `sdd/m12-menu-bar/design`, project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

`next_recommended: sdd-tasks`.

**Revision 2 (corrective re-run).** Reconciled against the specs, which landed in parallel after revision 1
was written: `openspec/changes/m12-menu-bar/specs/menu-bar/spec.md` (**ADDED-only**, 10 requirements /
25 scenarios), `specs/installed-inventory/spec.md` (**1 ADDED**, 3 scenarios) and
`specs/service-management/spec.md` (**1 MODIFIED**, 1 added scenario). Ten corrections were applied; each is
cited in the row it changed. Where this document and the specs disagreed, **the spec won** — in every case
the spec was stricter, and in three cases (**DD-3**, **DD-9**, **DD-10**) revision 1 was simply wrong.

**Inputs.** proposal obs `#7820` (APPROVED 2026-08-25, decisions **D1–D4** binding), `explore.md` obs `#7819`
(as-of `main` @ `f2efbdd`), the three spec deltas above, and the ten bound decisions in the launch brief.
Risks **R1 … R9** carry from the proposal by name; **R10 … R12** are new. Approach **A + C** stands; **B**
and **D** remain rejected. Verification classes are the spec's two:
**`unit`** (`swift test --package-path Packages/CellarCore`) and
**`unit-app`** (`xcodebuild test … -only-testing:cellarTests`). **`ui`: 0, deliberately** (menu-bar spec:33).

> **Size note.** Exceeds the skill's 800-word default by explicit launch-brief instruction: the brief
> enumerates nine design questions, a DD register, a file inventory with byte-identical claims, and a test
> plan reconciled scenario by scenario against 29 delivered scenarios. Tables, not prose — the m9/m10/m11
> precedent. `openspec/config.yaml` `rules.design` additionally requires actor-isolation and `Sendable`
> statements (**DD-14**).

## Context and constraints

Five constraints shape every decision below, all read from the code rather than assumed:

1. **Every store is already app-level.** `cellar/cellarApp.swift` owns all of them as `@State` and builds
   them in `init()` (`:23–194`, `:201–469`). A third `Scene` needs **no new store and no new loop** — which
   menu-bar spec:386–388 and its scenario at :398–406 now require outright.
2. **Environment is per-scene.** The About `Window` repeats `.environment(theme)`, `.tint(theme.base)`,
   `.preferredColorScheme(.dark)` (`cellar/cellarApp.swift:562–570`) because the `WindowGroup`'s injections
   (`:506–516`) do not reach it. `ActionPillStyle` reads `@Environment(ThemeStore.self)`
   (`cellar/Theme/PaneSearchField.swift:51`), so an unthemed scene renders in system chrome
   (menu-bar spec:381–384).
3. **Two outdated numbers ship today.** `cellar/Shell/SidebarView.swift:218` and
   `cellar/Home/HomeView.swift:142` read `packages.filter(\.isOutdated)`; every other surface reads
   `InstalledBrowse.outdatedIDs(metadata:)`
   (`Packages/CellarCore/Sources/BrewClient/InstalledFilterMode.swift:171–184`). **D1** settles this, and
   installed-inventory spec:45–68 generalises it.
4. **The services poll is a two-half conjunction on purpose.** `isVisible = isSectionVisible && isAppActive`
   (`Packages/CellarCore/Sources/BrewClient/ServicesRefreshCoordinator.swift:59–62`), reported from
   `cellar/Services/ServicesListView.swift:58–59` and `cellar/cellarApp.swift:525–527`. The type's own
   comment says folding them would let one overrule the other; service-management spec:56–59 now forbids a
   third half in text.
5. **`cellar/` is swept textually.** `AppSecuritySources.load()` enumerates every `.swift` under `cellar/`
   and strips comments (`cellarTests/SecurityCompositionSupport.swift:42–86`), so `cellar/MenuBar/` enters
   the net the moment it exists. Menu-bar spec:290–297 and installed-inventory spec:77–85 both call for
   **directory-wide and app-wide** sweeps, not single-file reads.

## Architecture overview

    ┌─ cellarApp (App) ─ owns every store as @State, builds them once in init() ─────────────┐
    │                                                                                        │
    │  installed  metadata  services  servicesRefresher  operations  theme  menuBar(new)      │
    │      │          │         │             │              │         │        │             │
    │      └──────────┴─────────┴─────────────┴──────────────┴─────────┴────────┘             │
    │                                    │                                                    │
    │   ┌────────────────┐   ┌───────────┴────────┐   ┌──────────────────────────────────┐    │
    │   │ WindowGroup    │   │ Window("about")    │   │ MenuBarExtra(isInserted:)  NEW    │    │
    │   │ id: "main" NEW │   │ (unchanged)        │   │ .menuBarExtraStyle(.window)       │    │
    │   │ ContentView    │   │ AboutView          │   │ title = count · systemImage       │    │
    │   │ .environment(  │   │ .environment(theme)│   │ MenuBarPopoverView                │    │
    │   │   theme, …)    │   │ .tint / .dark      │   │ .environment(theme) .tint .dark   │    │
    │   │ scenePhase →   │   │                    │   │ .task { refreshBaseline() }  ← the │    │
    │   │  setActive     │   │                    │   │        ONLY async in this scene   │    │
    │   └────────────────┘   └────────────────────┘   └──────────────────────────────────┘    │
    └────────────────────────────────────────────────────────────────────────────────────────┘

    InstalledStore.inventory ─┐
    MetadataStore.snapshot ───┼─► InstalledBrowse(inventory:isAvailable:)
                              │        .outdatedIDs(metadata:) / .outdatedCount(metadata:)
                              │              │            │                │
                              │              ▼            ▼                ▼
                              │       SidebarView   HomeView         MenuBarProjection
                              │        badge (D1)   attention (D1)   (delegates; count AND set)
    ServicesStore.services ───┴───────────────────────────────────────────►  │
                                                                              ▼
                                       statusItemTitle: String? · topOutdated(≤5) · andMoreLabel: String?

## Architecture decisions

| # | Decision | Rejected alternatives | Rationale |
|---|---|---|---|
| **DD-1** | `MenuBarProjection` is a `public struct: Sendable, Equatable` in `Packages/CellarCore/Sources/BrewClient/MenuBarProjection.swift`. It takes `browse: InstalledBrowse`, `metadata: MetadataLookup?`, `services: [ServiceRecord]` as **parameters at `init`**, and **delegates** to `browse.outdatedCount(metadata:)` **and** `browse.outdatedIDs(metadata:)`. **Correction 4:** it exposes the full set as `public let outdatedIDs: Set<PackageID>`, not merely the top five | Recomputing `packages.filter(\.isOutdated)`; reading `InstalledPackage.isOutdated` or `InstalledInventory.outdatedIDs` directly; storing store references; a `@MainActor` class | menu-bar spec:57–58 requires **both** the count and "the outdated set it exposes" to equal the delegated projection's answers, and installed-inventory spec:65–67 requires that where a surface presents a count *and* a set, both come from that one projection — its scenario at :87–94 reads them **together** and asserts `count == set.count`. Revision 1 exposed only `topOutdated` (≤ 5), so the set the spec names was not exposed at all and **T1** could assert only a subset. Structurally: the `upgradableIDs` precedent (`InstalledFilterMode.swift:186–196`) exists because a label and a submission once computed one number twice; menu-bar spec:62–64 says agreement must be structural, not coincidental |
| **DD-2** | **D1** targets `InstalledBrowse`, **not** `MenuBarProjection`. `cellar/Shell/SidebarView.swift` and `cellar/Home/HomeView.swift` each build `InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil)` and read `outdatedIDs(metadata:)`. **Correction 10:** neither builds a `MetadataLookup` today, so each obtains one exactly as `cellar/Health/HealthView.swift:295` already does — **`metadata.availability.isAvailable ? metadata.snapshot.lookup : nil`** — from the `metadata: MetadataStore` property both already declare (`SidebarView.swift:25`, `HomeView.swift:24`) | Routing the shell's badge and Home's card through `MenuBarProjection`; passing a new `MetadataLookup` parameter down from `ContentView`; leaving both and matching today's number in the menu bar | Both views already hold `installed` and `metadata`, so **`cellar/ContentView.swift` needs no call-site change and stays byte-identical** (**DD-15**). Making an app-shell badge depend on a menu-bar type would invert the dependency and hand the sidebar a value capped at five (**DD-3**). The `availability.isAvailable ? … : nil` shape is what makes a cold or unavailable metadata store degrade to today's behaviour with no branch — `outdatedIDs(metadata:)` guards `guard let metadata else { return inventory.outdatedIDs }` (`InstalledFilterMode.swift:172`). Agreement is enforced one level down, where all three already meet (installed-inventory spec:69–75, proved by **T7**) |
| **DD-3** | `topOutdatedLimit = 5`. `topOutdated` filters the **ordered** `browse.inventory.packages` array by `outdatedIDs` (name order, `InstalledModels.swift:162`, `:193–196`) and takes `prefix(5)` — no second sort. **Correction 3:** the remainder is **`remainingOutdatedCount: Int?`** and **`andMoreLabel: String?`**, both `nil` when five or fewer are outdated. Never `0`, never `""`. `andMoreLabel` is `"and 1 more"` in the singular and `"and M more"` otherwise | `additionalOutdatedCount: Int` returning `0` (revision 1 — **wrong**); a view-side `prefix(5)`; a severity, recency or size order; a view-composed remainder sentence | menu-bar spec:113–114 is explicit: "it MUST expose **no remainder at all** — absence preserved as absence, never zero, never an empty string, never a suppressed line that still occupies the value", and its scenario at :124–130 asserts "neither exposes a remainder value at all, rather than a remainder of zero". Revision 1's `Int` could not express that. The singular is pinned copy (spec:41, :112) and is reachable in practice — spec's own scenario at :132–138 produces a remainder of exactly 1. Filtering the **ordered** array rather than the `Set` makes the order total without a comparator; there is no recency or severity order for outdated packages today (spec:107–109) |
| **DD-4** | "Upgrade all" is **uncounted**, calls `operations.submit(.upgradeAll)`, and sits beside `CopyCommandButton(text: MutationCommand.upgradeAll.displayCommand)` (`cellar/Activity/ActivityDrawer.swift:125`). The badge carries N. **Correction 7:** the string `brew upgrade` is **never written as a literal** in menu-bar sources | A counted "Upgrade outdated (N)"; a fan-out over `submitUpgrades(for:in:)`; composing the disclosed command locally; no copy affordance | `MutationCommand.upgradeAll` lowers to bare `["upgrade"]` with `requiresConfirmation == false`, so this is one call and no sheet. menu-bar spec:168–172 forbids any count in the label; spec:178–181 requires the disclosed command to be taken **verbatim** from `displayCommand` so "the popover and the installed list cannot disclose two different commands for one submission", and its scenario at :198 asserts **"no literal `brew upgrade` string is composed in these sources"**. `cellar/Home/HomeView.swift:159` already submits exactly this way; the copy button is the shipped convention (`cellar/Installed/InstalledListView.swift:241`, PRD :119) |
| **DD-5** | New `public static func compactControls(for status: ServiceStatus) -> [ServiceRowControl]` on the shipped `ServiceRowControl` (`ServiceCommand.swift:245–285`), switching **exhaustively over all eight `ServiceStatus` cases**: `.started ⇒ [.stop, .restart]`; `.none`, `.scheduled`, `.stopped`, `.error`, `.unknown`, `.other`, `.unrecognised(_) ⇒ [.start, .run]`. `cellar/Services/ServiceControls.swift:36` gains **one defaulted** `var controls: [ServiceRowControl] = ServiceRowControl.allCases`, so `cellar/Services/ServicesListView.swift` stays **byte-identical**. The popover composes **no verb of its own** | A per-service toggle; a bespoke control set in the app target; a non-defaulted parameter; a `default:` arm in the status switch | menu-bar spec:239–243 forbids a single switch whose "on" position would silently choose between registering a login item and not, and requires that **every** status the shipped model can report map to exactly one of the two sets — "never both and never neither" (:265–271). **Correction 5:** `ServiceStatus` is **not `CaseIterable`** and carries **eight** cases including `.other` and `.unrecognised(String)`; its own doc comment records that `unrecognised` cannot be named `other` because `other` is one of brew's seven real values (`ServicesWire.swift:29–42`). An exhaustive switch with no `default:` is what makes a ninth brew status a compile-time decision. Putting the rule in CellarCore makes SM5's claim a `unit` test over the returned array; the defaulted parameter is m11 **DD-15**'s trick and buys the 0-line diff on the Services section |
| **DD-6** | New `public func refreshBaseline() async` on `ServicesRefreshCoordinator`: returns immediately when `mutations?.isMutating == true`, otherwise `await performRefresh()`. It touches **none** of `isSectionVisible`, `isAppActive`, `applyVisibility()`, `syncPolling()`, and schedules nothing on the injected clock. **The trigger is `.task { await servicesRefresher.refreshBaseline() }` on the `MenuBarExtra` content inside `cellar/cellarApp.swift`** — never inside `cellar/MenuBar/MenuBarPopoverView.swift` | `setVisible(true)` from the popover; a third visibility half; a `.task` or `onAppear` in any menu-bar file; a poll while open; deferring the skipped refresh to the mutation's terminal | service-management spec:56–62 licenses exactly this: one baseline refresh, no visibility report, no cadence, nothing on the injected clock, skipped while mutating and **not deferred** — the terminal already owes its own refresh (`ServicesRefreshCoordinator.swift:111–117`). **R2 closes structurally**: the popover has no way to reach either half of the conjunction. Putting the trigger in `cellarApp.swift` is what lets **DD-12**'s prohibition on `cellar/MenuBar/` be absolute — that file already carries eleven `.task` modifiers and is not, and must not become, a prohibition subject (menu-bar spec:292 scopes the sweep to "the menu-bar directory"). The in-flight skip mirrors the poll's own `guard mutations?.isMutating != true else { continue }` (`:225`) |
| **DD-7** | `cellar/MenuBar/MenuBarPreference.swift`: `@MainActor @Observable final class MenuBarPreference` with `var isShown: Bool { didSet { defaults.set(…) } }` over an **injected** `UserDefaults`, a **missing key reading `false`**. Held as app-level `@State`; the scene binds with an explicit `Binding(get: { menuBar.isShown }, set: { menuBar.isShown = $0 })` | `@AppStorage` declared on the `App`; a local `@Bindable var menuBar = …` inside the `some Scene` body; a `struct` over `UserDefaults` like `AutomaticUpdateChecks`; SwiftData | **R8.** `MenuBarExtra(isInserted:)` needs a `Binding<Bool>` and `@Bindable` is not available as a stored property on a non-`View`. A `struct` is ruled out outright: `cellar/Updates/AutomaticUpdateChecks.swift:23–38` has no observation, so a Settings toggle would not move the status item. `@AppStorage` cannot take a suite chosen at composition time from `AppTestFixtures` the way `ReleaseNotesConsentPreference`/`AutomaticUpdateChecks` do (`cellar/cellarApp.swift:349–353`, `:381–385`), and would put two independent wrappers over one key. The explicit `Binding(get:set:)` is this app's own shipped precedent (`cellar/Updates/UpdatesSettingsGroup.swift:58–64`). menu-bar spec:316–319 pins the injectable suite and forbids SwiftData; spec:332–339 requires the insertion be bound to the preference **and nothing else**. `cellar/Theme/ThemeStore.swift:16–32` is the class shape being copied |
| **DD-8** | The `MenuBarExtra` content repeats **exactly** the About window's three injections — `.environment(theme)`, `.tint(theme.base)`, `.preferredColorScheme(.dark)` — and nothing else. `MenuBarPopoverView` reuses `themeCard(fill:)` (`cellar/Theme/Theme.swift:139`), `StatusPill` (`cellar/Browse/StatusPill.swift:22`), `HairlineDivider` (`cellar/Theme/HairlineDivider.swift:15`), `SectionHeader` (`cellar/Theme/SectionHeader.swift:9`), `ShellChipButtonStyle` (`cellar/Shell/ShellToolbar.swift:87`), `ActionPillStyle` (`cellar/Theme/PaneSearchField.swift:49`), `CopyCommandButton` and `ServiceControls` | Injecting `releaseNotes`, `releaseNotesConsent`, `\.appUpdater` "for symmetry"; composing lookalike pills and dividers | Constraint 2, and menu-bar spec:381–384 names the three by role. The three the About window repeats are the **complete** set the reused components need; adding the release-notes or updater seams would give a popover reach into surfaces it must not have. Component reuse is m11 **DD-18/DD-25**'s rule: reference the one shipped component, never a lookalike — and menu-bar spec:245–246 requires the four service labels be "reused byte-for-byte rather than reworded" |
| **DD-9** | `.menuBarExtraStyle(.window)`. **Correction 2:** `statusItemTitle` is **`String?`** and is **`nil`** when the count is zero — never `"0"`, never `""`. The count reaches the status item through `MenuBarExtra(_ title: String, systemImage: "shippingbox", isInserted:)`, whose title argument is exactly **`menuBar.isShown ? (menuBarProjection.statusItemTitle ?? "") : ""`**. The `?? ""` is a **framework adaptation performed at that one call site in `cellar/cellarApp.swift` and nowhere else**; no file under `cellar/MenuBar/` ever sees it | `statusItemTitle: String` returning `""` at zero (revision 1 — **wrong**); a custom `label:` view; `ImageRenderer`/`NSImage` badge composition; `.menu` style; AppKit `NSStatusItem` | menu-bar spec:146–148 requires the absence be modelled **as absence** "so the surface never decides it locally", and its scenario at :155 asserts the absent value "is not the string `0` **and not the empty string**". Revision 1's non-optional `String` returning `""` failed that assertion literally. `Optional` is the type that carries the absence; the initializer needs a `String`, so exactly one adaptation exists, at the boundary, and **T12** pins it — spec:162 forbids a *locally composed count*, which `?? ""` is not. The documented title initializer is the only rendering the framework guarantees; a rendered badge is approach **D**'s cost for a benefit **D2** does not ask for, and spec:142–144 forbids an image renderer, a drawn badge and an AppKit status-item image path outright. **The outer ternary is load-bearing**: `?:` short-circuits, so with the feature off (the default) `menuBarProjection` is never evaluated, `installed.inventory` is never read inside `App.body`, and **no observation is established at App level at all** — which is how spec:310–311's "no other observable difference" becomes structural (**R12**) |
| **DD-10** | The `WindowGroup` gains `id: "main"`. **Correction 1:** "Open Cellar" is **`openWindow(id: "main")` and nothing else**. No `NSApplication`, no `NSApp`, no activation call anywhere in `cellar/MenuBar/` or in the scene block. The popover raises **no** confirmation-capable verb, and no entry other than `Open Cellar` opens, requires or checks for a window | `NSApplication.shared.activate()` alongside `openWindow` (revision 1 — **wrong**); an AppKit activation path with no `id:`; a second main-window scene; opening the window before a mutation | `proposal.md:86–87` already chose `openWindow(id:)` over "an AppKit activation path", and menu-bar spec:356–357 makes it a prohibition — "MUST NOT introduce an AppKit activation path, an `NSApplication` or `NSApp` reference" — with the scenario at :365 asserting the absence directly. Revision 1 reintroduced exactly what the proposal had rejected, for a frontmost-ness the spec never asks for: spec:352–354 requires only that the entry **open the main window, including with every window closed**, which `openWindow(id:)` does. `cellar/Shell/AboutView.swift:152–156` is the shipped precedent and adding the id is one line. **R3** is closed by absence: `pendingConfirmation` is presented only by `cellar/ContentView.swift:163–167`, so a request raised with no window would latch and block the channel (spec:280–284) — the popover therefore offers only `upgradeAll` and the four service verbs, all with `requiresConfirmation == false` |
| **DD-11** | The Settings row is `cellar/MenuBar/MenuBarSettingsGroup.swift` — its own file, its own card, reproducing the group/row shape the way `cellar/Updates/UpdatesSettingsGroup.swift` does, with the exact copy **`Show in menu bar`** declared **once**. `cellar/Settings/SettingsView.swift` changes by **two hunks**: the doc comment at `:9–15` loses "a menu bar extra" from its list of absent capabilities, and one line `MenuBarSettingsGroup()` joins the stack beside `UpdatesSettingsGroup()` (`:77`) | A row inside `SettingsView.group("Interface")`; relaxing `SettingsView`'s private `group`/`row` helpers; adding a schedule or notification row "while we are here" | `UpdatesSettingsGroup`'s own comment (`:17–20`) states the rule: the card shape is reproduced rather than borrowed **because** `group(_:rows:)` and `row(label:sub:accessory:)` are private to `SettingsView`, and the point of a separate file is that deleting it removes the whole surface. menu-bar spec:321–323 pins the copy, requires **exactly one** row, forbids a row for background schedules or notifications (capabilities that still do not exist, PRD :114–115), and requires the doc comment stop asserting the capability is absent — leaving it would make the file assert something false about the app |
| **DD-12** | Every `.swift` file under `cellar/MenuBar/` is a **projection reader**. None contains `.task`, `Task {`, `await `, `async `, `Process(`, `URLSession`, `CaskIconLoader`, `PackageIconTile`, `CaskIconView(`, `ImageRenderer`, `NSImage`, `NSStatusItem`, `NSApplication`, `NSApp`, `pendingConfirmation`, `setVisible(`, `setActive(`, `refreshEverything`, `.uninstall`, `.zap`. `MenuBarPopoverView` takes `projection: MenuBarProjection` as a `let` | A `.task` loader in the popover; cask artwork on the outdated rows; a "Refresh" button; scanning one file instead of the directory | This is the `ReleaseNotesEgressCompositionTests` / `TapSearchCompositionTests` idiom (`:145`, `:936`), and menu-bar spec:275–288 makes it a requirement — "asserted as **absences** by the shipped source-scanning idiom, not merely described". **Correction 6:** spec:292 scopes the sweep to "every `.swift` source file under the menu-bar directory", so **T8** and **T12** enumerate the directory rather than reading one file by name. **R4**: artwork would fire a network request on every popover open — `cellar/Installed/InstalledListView.swift:43–45` already documents that passing `nil` keeps the letter tile. The single permitted async hop lives one file up (**DD-6**), which is what makes this list absolute rather than "except for the one we needed" |
| **DD-13** | **In scope**: every interactive element in the popover is a `Button` (never `onTapGesture`), carries an `.accessibilityIdentifier` (`menu-bar-upgrade-all`, `menu-bar-open-cellar`, `menu-bar-copy-command`, `menu-bar-settings-toggle`, `menu-bar-service-<name>-<control>`) and an explicit `.accessibilityLabel` where the visible text is not self-describing; outdated rows group with `.accessibilityElement(children: .combine)`. **Out of scope**: the status item itself, whose accessibility description is the framework's and follows the SF Symbol when the title is absent (**DD-9**) | Claiming parity with `.menu`'s free semantics; adding a focus-management layer | **R6** is real and was accepted when approach **B** was rejected: `.window` style buys the design and costs the free menu semantics. `cellar/Services/ServiceControls.swift:49` already sets `.accessibilityLabel("\(control.label) \(service.name)")`, so reusing it (**DD-5**) inherits correct labels for the largest group of controls. Stating the status item as out of scope is the honest half: nothing in this change can set it, and the spec pins no copy for it (spec:44) |
| **DD-14** | **CellarCore**: `MenuBarProjection` and `compactControls(for:)` are `nonisolated` by module default (`Packages/CellarCore/Package.swift` declares no `.defaultIsolation`) and `Sendable`/`Equatable` by composition — `InstalledInventory`, `PackageID` and `ServiceRecord` are already `Sendable, Hashable`. `refreshBaseline()` is `@MainActor` because `ServicesRefreshCoordinator` is (`:24`). **App target**: MainActor by default (`cellar.xcodeproj/project.pbxproj:451`, `:488`); the projection is built **synchronously in the scene body**, recomputed per body evaluation, **never memoized** | `@MainActor` on the projection; an `actor`; hopping off-main to build it; caching it in `@State` | The whole projection is a `Set` membership filter over an array bounded by the installed package count — the work the sidebar badge already does on every render. `@MainActor` would make it unreachable from the `swift test` inner loop, which is the entire point of approach **C** and of menu-bar spec:12–14's split. A cache is a second source of truth. `Equatable` is not decoration: spec:96–102 asserts that composing twice over identical inputs yields **equal** values, which is what "pure over its inputs" means here (**T19**). The only `await` in the change is **DD-6**'s |
| **DD-15** | **No new `AppSection`.** `AppSection.allCases.count` stays **22** and `cellar/ContentView.swift`'s asserted AppSection-switch count stays **3**. `cellar/Shell/AppSection.swift`, `cellar/ContentView.swift` and `cellarTests/AppSectionPlacementTests.swift` are all **byte-identical** | A `.menuBar` section; a Settings sub-section | A menu bar is a `Scene`, not a navigable section — no sidebar row, no list pane, no detail. menu-bar spec:377–379 says a diff to either literal "is a defect in this change rather than a licensed edit". `AppSectionPlacementTests.swift:36` and `:158–161` pin both; the suite passing **unedited** is the proof (the m11 round-6 idiom) |

## Interfaces / contracts

```swift
// Packages/CellarCore/Sources/BrewClient/MenuBarProjection.swift  (NEW)

/// Everything the menu bar shows, derived once from the stores the window
/// already reads. A projection **over** `InstalledBrowse`, never a second
/// derivation of outdated-ness (DD-1; menu-bar spec:49-68).
public struct MenuBarProjection: Sendable, Equatable {
    public struct OutdatedEntry: Sendable, Equatable, Identifiable {
        public let id: PackageID
        public let name: String
        public let installedVersion: String
        public let catalogVersion: String
    }

    /// Fixed at five (DD-3). Public so the test names the same number the view does.
    public static let topOutdatedLimit = 5

    public let outdatedCount: Int             // == browse.outdatedCount(metadata:)
    public let outdatedIDs: Set<PackageID>    // == browse.outdatedIDs(metadata:)   (correction 4)
    public let topOutdated: [OutdatedEntry]   // <= 5, inventory name order, drawn from outdatedIDs
    public let services: [ServiceRecord]      // last known, brew's own order
    public let runningServiceCount: Int

    public init(browse: InstalledBrowse, metadata: MetadataLookup?, services: [ServiceRecord])

    /// The status item's title, ABSENT when nothing is outdated (DD-9; spec:146-148).
    /// Never `"0"`, never `""` — the absence is the value.
    public var statusItemTitle: String? { outdatedCount == 0 ? nil : "\(outdatedCount)" }

    /// The remainder, ABSENT when five or fewer are outdated (DD-3; spec:113-114).
    /// Never `0`.
    public var remainingOutdatedCount: Int? {
        let rest = outdatedCount - topOutdated.count
        return rest > 0 ? rest : nil
    }

    /// `"and 1 more"` / `"and 7 more"`, ABSENT on the same terms (spec:41, :112).
    public var andMoreLabel: String? {
        remainingOutdatedCount.map { $0 == 1 ? "and 1 more" : "and \($0) more" }
    }
}

// Packages/CellarCore/Sources/BrewClient/ServiceCommand.swift  (MODIFIED, +~18)
extension ServiceRowControl {
    /// The controls a compact secondary surface offers. Narrows the list; never
    /// collapses start-at-login and run-once into one control (SM5, DD-5).
    /// Exhaustive over all EIGHT ServiceStatus cases, no `default:` arm —
    /// ServiceStatus is not CaseIterable (ServicesWire.swift:33-42).
    public static func compactControls(for status: ServiceStatus) -> [ServiceRowControl] {
        switch status {
        case .started: [.stop, .restart]
        case .none, .scheduled, .stopped, .error, .unknown, .other, .unrecognised: [.start, .run]
        }
    }
}

// Packages/CellarCore/Sources/BrewClient/ServicesRefreshCoordinator.swift  (MODIFIED, +~12)
extension ServicesRefreshCoordinator {
    /// One refresh for a secondary read-only surface that has just appeared.
    /// Reports no visibility, starts no poll, schedules nothing on the clock,
    /// and is SKIPPED — not deferred — while one of our own service mutations
    /// is in flight (DD-6; service-management spec:56-64).
    public func refreshBaseline() async
}
```

```swift
// cellar/cellarApp.swift  (MODIFIED — the third scene)
MenuBarExtra(
    // The projection owns the absence; this is the ONE place it is adapted to the
    // framework's non-optional title, and no menu-bar source sees the adaptation
    // (DD-9). The outer ternary short-circuits, so with the feature off the
    // projection is never composed and no inventory observation is established.
    menuBar.isShown ? (menuBarProjection.statusItemTitle ?? "") : "",
    systemImage: "shippingbox",
    isInserted: Binding(get: { menuBar.isShown }, set: { menuBar.isShown = $0 })   // DD-7
) {
    MenuBarPopoverView(
        projection: menuBarProjection,
        operations: operations,
        services: services,
        openMainWindow: { openWindow(id: "main") }        // DD-10 — and nothing else
    )
        .environment(theme)                                // DD-8, the About-window three
        .tint(theme.base)
        .preferredColorScheme(.dark)
        .task { await servicesRefresher.refreshBaseline() }   // DD-6 — lives HERE, not in the view
}
.menuBarExtraStyle(.window)

@MainActor
private var menuBarProjection: MenuBarProjection {
    // Recomputed per body evaluation, never cached: a cache is a second source
    // of truth, and this is one Set membership filter (DD-1, DD-14).
    MenuBarProjection(
        browse: InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil),
        metadata: metadata.availability.isAvailable ? metadata.snapshot.lookup : nil,
        services: services.services
    )
}
```

`cellar/Shell/SidebarView.swift` and `cellar/Home/HomeView.swift` obtain their lookup with the **same
expression** (**DD-2**, correction 10) — `metadata.availability.isAvailable ? metadata.snapshot.lookup : nil`
— from the `metadata: MetadataStore` property each already declares, so no call site in
`cellar/ContentView.swift` changes.

The UI-test defaults suite follows `AutomaticUpdateChecks`' shape but gates on **`AppTestFixtures.isEnabled`**
rather than a feature-specific flag, because **D10** ships no `--ui-testing-menu-bar` fixture: every UI-test
launch must be kept out of the developer's real defaults, not only the ones that opted in.

## File inventory

### New

| File | Est. | Contents |
|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/MenuBarProjection.swift` | ~125 | **DD-1, DD-3, DD-9**: the value, its two optional projections, the pinned remainder copy |
| `Packages/CellarCore/Tests/BrewClientTests/MenuBarProjectionTests.swift` | ~280 | `unit` rows **T1, T2, T3, T19** |
| `cellar/MenuBar/MenuBarPreference.swift` | ~40 | **DD-7** |
| `cellar/MenuBar/MenuBarPopoverView.swift` | ~200 | **DD-4, DD-8, DD-12, DD-13**: badge row, top outdated, Upgrade all + copy, services, Open Cellar |
| `cellar/MenuBar/MenuBarSettingsGroup.swift` | ~70 | **DD-11** |
| `cellarTests/MenuBarCompositionTests.swift` | ~470 | `unit-app` rows **T7–T18**, plus a `private enum MenuBarSources` that enumerates `cellar/MenuBar/` off disk via `#filePath` and reuses `AppSecuritySources.stripComments(from:)` (correction 6) |

### Modified

| File | Est. delta | Exact edits expected |
|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/ServiceCommand.swift` | +18 | **DD-5**: `compactControls(for:)` only — no existing case, label or command moves |
| `Packages/CellarCore/Sources/BrewClient/ServicesRefreshCoordinator.swift` | +12 | **DD-6**: `refreshBaseline()` only — `isVisible`, `setVisible`, `setActive`, `syncPolling`, `poll` all untouched |
| `Packages/CellarCore/Tests/BrewClientTests/ServicesRefreshControlTests.swift` | +75 | `unit` rows **T5**, **T6** |
| `Packages/CellarCore/Tests/BrewClientTests/ServiceCommandTests.swift` | +55 | `unit` row **T4** (all eight statuses) |
| `cellar/cellarApp.swift` | +44 / −1 | `@State private var menuBar`; its construction in `init()`; `id: "main"` on the `WindowGroup`; `@Environment(\.openWindow)`; the third scene block; `.environment(menuBar)` on the `WindowGroup` content so the Settings card reads it |
| `cellar/Services/ServiceControls.swift` | +4 | **DD-5**: one defaulted `controls` property; `ForEach(controls, …)` replaces `ForEach(ServiceRowControl.allCases, …)` |
| `cellar/Settings/SettingsView.swift` | +1 / −1 | **DD-11**: the doc comment at `:9–15`, and one line beside `UpdatesSettingsGroup()` |
| `cellar/Shell/SidebarView.swift` | +6 / −1 | **D1/DD-2**: `outdatedCount` becomes an `InstalledBrowse` read with the `HealthView.swift:295` lookup expression |
| `cellar/Home/HomeView.swift` | +7 / −1 | **D1/DD-2**: `attention`'s `outdated` becomes the same |

### Must stay byte-identical (asserted, not reviewed)

| File | Why the claim holds |
|---|---|
| `cellar/ContentView.swift` | **DD-2** keeps the `SidebarView(` and `HomeView(` call sites unchanged (both already take `metadata: MetadataStore`, `SidebarView.swift:25` / `HomeView.swift:24`); **DD-15** adds no section. Its AppSection-switch count stays **3** |
| `cellar/Shell/AppSection.swift` | **DD-15**: no new case, no new title, no new symbol |
| `cellarTests/AppSectionPlacementTests.swift` | **DD-15**: `:36` stays `22`, `:158–161` stays `3`. The suite passing unedited is the proof |
| `cellar/Services/ServicesListView.swift` | **DD-5**: the `ServiceControls(` call site needs no argument because `controls` defaults |
| `Packages/CellarCore/Sources/BrewClient/InstalledFilterMode.swift` | **DD-1**: the projection delegates; `outdatedIDs`/`outdatedCount`/`upgradableIDs` are consumed, never widened |
| `cellar/Health/HealthComposition.swift` | Already reads `browse.outdatedIDs(metadata:)` (`:71`). Health is deliberately **not** migrated onto `MenuBarProjection` |
| `cellar/ContentView.swift`'s `.mutationConfirmation(…)`, `cellar/Activity/MutationConfirmation.swift` | **DD-10**: no confirmation-raising verb is offered, so the presenter needs no second home |
| `cellar/Casks/CaskIconView.swift`, `cellar/Casks/CaskIconLoader.swift` | **DD-12**: consumed by nothing here |
| `cellar/Installed/BulkActionBar.swift`, `cellar/Installed/InstalledRow.swift`, `cellar/Browse/PackageRow.swift` | **T18**: their `isOutdated` reads are **per-package** (`BulkActionBar.swift:52`, `InstalledRow.swift:168`, `PackageRow.swift:51`, `:80`), which the requirement permits. The sweep's shape must not touch them |
| `cellar.xcodeproj/project.pbxproj` | **0-line diff, binding.** `cellar/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup`s (`:44–53`), so `cellar/MenuBar/` needs no reference. A non-zero diff is a defect — restore with `git checkout HEAD -- cellar.xcodeproj/project.pbxproj` |

## Test plan

Strict TDD: every row is RED before its implementation exists. All quoted copy is **pinned by the spec**;
`sdd-apply` reproduces it and does not choose it. The **Scenario** column reconciles this map against the
delivered specs; `sdd-tasks` must confirm the mapping scenario by scenario before it closes.

**Coverage**: 29 delivered scenarios — menu-bar 25 (12 `unit` + 13 `unit-app`), installed-inventory 3
(1 `unit` + 2 `unit-app`), service-management 1 (`unit`). Every one has a row below.

| # | Class | RED test | Scenario | Proves |
|---|---|---|---|---|
| **T1** | `unit` | `theProjectionCountsAndSetsExactlyWhatTheBrowseDoes` | menu-bar :70, :80; installed-inventory :87 | **DD-1, correction 4**: over a fixture with a snoozed package, an outdated self-updating cask and three other outdated packages, `outdatedCount == 3`, **`outdatedIDs == browse.outdatedIDs(metadata:)` by set equality** (not subset), `outdatedCount == outdatedIDs.count`, and both equal the delegated answers; the cask is absent with no auto-update rule stated here. Triangulated with **no** metadata, where both fall back to `inventory.outdatedIDs` |
| **T2** | `unit` | `aSnoozedPackageIsInNeitherTheCountTheSetNorTheEntries` | menu-bar :70, :132 | **D1**: the snoozed package is absent from `outdatedCount`, `outdatedIDs` and `topOutdated`; with seven outdated of which the alphabetically first is snoozed, `topOutdated.count == 5` excluding it and `remainingOutdatedCount == 1` so entries + remainder == the announced count exactly. `packages.filter(\.isOutdated).count` on the same fixture is **strictly greater**, so the row fails if the projection ever reverts to the naive filter |
| **T3** | `unit` | `theRemainderAndTheTitleAreAbsencesNotZeroes` | menu-bar :88, :116, :124, :132, :150 | **DD-3 + DD-9, corrections 2 and 3**: 12 outdated ⇒ 5 entries (the first five in name order) and `remainingOutdatedCount == 7`, `andMoreLabel == "and 7 more"`; **6 outdated ⇒ `andMoreLabel == "and 1 more"` (the singular)**; 5 and 4 outdated ⇒ `remainingOutdatedCount == nil` **and** `andMoreLabel == nil`, asserted as `nil` rather than `0`/`""`; 3 outdated ⇒ `statusItemTitle == "3"`; 0 outdated ⇒ `statusItemTitle == nil`, explicitly `!= "0"` and `!= ""`, `topOutdated.isEmpty`, `remainingOutdatedCount == nil`; an **empty** inventory and separately an **unavailable** one each yield that same ordinary zero, throw nothing and are indistinguishable from each other |
| **T4** | `unit` | `everyReportableStatusMapsToExactlyOneControlSet` | menu-bar :248, :256, :265 | **DD-5, correction 5**: over an explicit array of **all eight** `ServiceStatus` cases — `.started`, `.none`, `.scheduled`, `.stopped`, `.error`, `.unknown`, `.other`, `.unrecognised("a-status-this-build-does-not-know")` (the enum is **not** `CaseIterable`, `ServicesWire.swift:33–42`) — `.started ⇒ [.stop, .restart]` exactly, and each of the other seven `⇒ [.start, .run]` exactly. For **every** status: the returned set is non-empty, is never both sets, contains **at most one** control with `isLoginRegistering == true`, and is never a one-element list containing `.start` or `.run` alone. `.start.command(for:)` and `.run.command(for:)` lower to `services start <name>` and `services run <name>`, so neither is a flag on the other. `ServiceRowControl.allCases` and every `label` are re-asserted unchanged |
| **T5** | `unit` | `aBaselineRefreshStartsNoPollAndReportsNoVisibility` | service-management :99 | **DD-6, R2**: on a coordinator whose section is **not** visible, `refreshBaseline()` performs exactly **one** refresh; advancing the injected clock by 60 s produces **no further brew invocation**; `isPolling == false` throughout; no visibility was reported, so a subsequent `setVisible(true)` still starts the poll normally with its own baseline — the secondary refresh consumed neither half of the conjunction |
| **T6** | `unit` | `aBaselineRefreshIsSkippedEntirelyWhileAMutationIsInFlight` | menu-bar :224 | **DD-6**: with the services gate mutating, `refreshBaseline()` performs **zero** refreshes **and queues none** — advancing to the mutation's terminal outcome shows exactly the **one** refresh the terminal already owes, not two. Released, the next call refreshes once. Triangulated against the shipped poll suppression so the two share one rule |
| **T7** | `unit-app` | `everyOutdatedSurfaceReadsTheOneProjection` | installed-inventory :69 | **D1/DD-2**: `cellar/Shell/SidebarView.swift`, `cellar/Home/HomeView.swift` and `MenuBarProjection.swift` each contain `outdatedCount(metadata:` or `outdatedIDs(metadata:`; **none** contains `filter(\.isOutdated)` or `filter { $0.isOutdated`; the two app files each construct `InstalledBrowse(inventory: installed.inventory, isAvailable: installed.absence == nil)` **and** obtain the lookup with `metadata.availability.isAvailable ? metadata.snapshot.lookup : nil` (correction 10); and `MenuBarProjection.swift` contains no `isOutdated` derivation of its own |
| **T8** | `unit-app` | `noMenuBarSourceLoadsEgressesOrConfirms` | menu-bar :290, :299 | **DD-12, correction 6**: **every** `.swift` under `cellar/MenuBar/` (enumerated off disk, comments stripped; a **positive anchor** requires the enumeration to find ≥ 3 files and each to appear in `AppSecuritySources.load()` by name, so a scan that read nothing fails rather than sweeping clean) contains none of `.task`, `Task {`, `await `, `async `, `Process(`, `URLSession`, `CaskIconLoader`, `PackageIconTile`, `CaskIconView(`; and none references `pendingConfirmation`, `.mutationConfirmation`, `MutationCommand.uninstall`, `.zap`, or any verb whose `requiresConfirmation` is true. Prohibitions asserted **before** the first `#require` so a throw cannot skip them |
| **T9** | `unit-app` | `theOneServicesRefreshLivesInTheAppAndStartsNoPoll` | menu-bar :215 | **DD-6**: `cellar/cellarApp.swift` contains **exactly one** `refreshBaseline(` call, inside the `MenuBarExtra` block (range comparison against `MenuBarExtra(` and `.menuBarExtraStyle`); no file under `cellar/MenuBar/` contains `refreshBaseline`, `servicesRefresher`, `ServicesRefreshCoordinator`, `setVisible(`, `setActive(`, `Timer`, `ContinuousClock`, `clock.sleep` or `.seconds(`; and `cellar/Services/ServicesListView.swift`'s `setVisible(true)`/`setVisible(false)` pair is **unchanged** |
| **T10** | `unit-app` | `theMenuBarSceneRepeatsTheAboutWindowsEnvironment` | menu-bar :398 (first clause) | **DD-8**: the `MenuBarExtra` block contains `.environment(theme)`, `.tint(theme.base)`, `.preferredColorScheme(.dark)` and `.menuBarExtraStyle(.window)`; it contains none of `releaseNotes`, `appUpdater`; and `cellar/cellarApp.swift` declares `Window("About` with the same three, so "the same three" is proven **against the precedent** rather than asserted |
| **T11** | `unit-app` | `thePreferenceIsOffByDefaultAndIsTheOnlyInsertionCondition` | menu-bar :325, :332 | **D4/DD-7**: a `MenuBarPreference` over a fresh scratch suite reads `isShown == false`; setting it writes the key and a second instance over the same suite reads `true`; `cellar/cellarApp.swift` constructs it with `AppTestFixtures.isEnabled ? UserDefaults(suiteName:`, never `.standard` unconditionally, and no menu-bar source references SwiftData or `LocalStores`; and the scene's `isInserted:` argument text is `Binding(get: { menuBar.isShown }, set: { menuBar.isShown = $0 })` — bound to the preference **alone**, with no `&&`, no `||` and no other condition |
| **T12** | `unit-app` | `theStatusItemIsATitleWithNoBadgeImageAndNoLocalCount` | menu-bar :158 | **DD-9, corrections 2 and 6**: `MenuBarProjection.swift` declares `statusItemTitle` as **`String?`** and returns neither `"0"` nor `""` from it; the `MenuBarExtra` title argument is the exact text `menuBar.isShown ? (menuBarProjection.statusItemTitle ?? "") : ""`, and `?? ""` appears in `cellar/cellarApp.swift` **exactly once**; **every** `.swift` under `cellar/MenuBar/` and the scene block contain no `ImageRenderer`, no `NSImage`, no `NSStatusItem`, and no locally composed count (`\(outdatedCount)`, `.count)` inside a `Text(`); and `statusItemTitle` is declared once, in `MenuBarProjection.swift` |
| **T13** | `unit-app` | `theUpgradeVerbIsUncountedDisclosedAndTheWindowEntryIsPureSwiftUI` | menu-bar :183, :192, :360 | **DD-4, DD-10, corrections 1 and 7**: `MenuBarPopoverView.swift` contains `operations.submit(.upgradeAll)` and `CopyCommandButton(text: MutationCommand.upgradeAll.displayCommand)`; its `"Upgrade all"` literal is followed by no interpolation and no parenthesised total; it contains no `submitUpgrades(`, no `upgradableIDs(`, no `MutationCommand.upgrade(`; **no menu-bar source contains the literal string `brew upgrade`**; `cellar/cellarApp.swift` declares `WindowGroup` with `id: "main"` and the entry's action is `openWindow(id: "main")`; and **no `.swift` under `cellar/MenuBar/`, and no text inside the `MenuBarExtra` block, contains `NSApplication`, `NSApp` or `.activate(`** |
| **T14** | `unit-app` | `theMenuBarAddsNoSectionAndNoShellLiteralMoves` | menu-bar :390 | **DD-15**: no source under `cellar/` adds an `AppSection` case or a fourth `ContentView` AppSection switch; `AppSection.allCases.count == 22` and the exact rawValue list are unchanged; `cellarTests/AppSectionPlacementTests.swift` is byte-identical and passes unedited |
| **T15** | `unit-app` | `noEntryDependsOnAWindowBeingOpen` | menu-bar :368 | **DD-10, correction 8**: across every `.swift` under `cellar/MenuBar/`, `openWindow(` appears **exactly once**, inside the `Open Cellar` action; no other entry's action references `openWindow`, `dismissWindow`, `NSWindow`, `.windows`, `isKeyWindow`, `keyWindow`, `\.scenePhase` or `\.controlActiveState`; the `Upgrade all` and service submissions are unconditional (no `guard`/`if` on a window token precedes them); and `openMainWindow` is a plain closure parameter, so the popover cannot check what it opened |
| **T16** | `unit-app` | `theSceneConstructsNoStoreAndNoRefreshLoop` | menu-bar :398 (second clause) | **Correction 8**: no `.swift` under `cellar/MenuBar/` contains `InstalledStore(`, `ServicesStore(`, `MetadataStore(`, `CatalogStore(`, `OperationCenter(`, `LoopOwner`, `RefreshCoordinator(`, `loops.start(` or `@State private var` holding a store type; `MenuBarPopoverView` declares its inputs as `let` properties; and the `MenuBarExtra` block passes the **same identifiers** the `WindowGroup` passes (`operations`, `services`, `theme`) rather than constructing anything |
| **T17** | `unit-app` | `settingsGainsOneRowAndStillDeniesTheAbsentCapabilities` | menu-bar :341 | **DD-11, correction 8**: `cellar/Settings/SettingsView.swift` no longer contains `a menu bar extra` and does contain `MenuBarSettingsGroup()`; the literal `Show in menu bar` appears **exactly once** across the app sources, in `cellar/MenuBar/MenuBarSettingsGroup.swift`; that file declares exactly one row and one toggle; and no Settings-owned source references `UNUserNotificationCenter`, `SMAppService`, `UNNotification`, or a row label containing `schedule`/`Schedule`/`notification`/`Notification` (the shipped `Check for updates automatically` row is Cellar's **own** updates and is explicitly excluded by naming it) |
| **T18** | `unit-app` | `noSurfaceInTheAppAnnouncesASelfComputedOutdatedCount` | installed-inventory :77 | **Correction 8**, the app-wide sweep. Over **every** `.swift` under `cellar/` with comments stripped, scanning **only for collection-derivation shapes**: `filter(\.isOutdated)`, `filter { $0.isOutdated`, `filter { package in package.isOutdated`, and `.outdatedIDs`/`.outdatedCount` **not** immediately followed by `(metadata:`. Expect **zero** matches after this change; at HEAD exactly two match (`cellar/Shell/SidebarView.swift:218`, `cellar/Home/HomeView.swift:142`). **Positive anchor**: the same detector, handed the literal string `installed.inventory.packages.filter(\.isOutdated).count`, must match — a detector that stopped recognising anything fails here rather than reporting a clean sweep. **Deliberately excluded by the scan's shape**: per-package reads such as `installed.isOutdated` and `entry.installed?.isOutdated` (`cellar/Installed/BulkActionBar.swift:52`, `cellar/Installed/InstalledRow.swift:168`, `cellar/Browse/PackageRow.swift:51`, `:80`, `cellar/Home/HomeView.swift:572`, `:583`, and ~15 more) — the requirement is about deriving a **count or a set**, never about reading one package's flag, and a bare-token scan would condemn twenty legitimate call sites |
| **T19** | `unit` | `theProjectionHasNoEffectfulDependencyAndIsEqualComposedTwice` | menu-bar :96 | **DD-14, correction 8**: `MenuBarProjection` conforms to `Equatable`; two compositions over **identical** inputs are `==` (and two over inputs differing by one snooze are `!=`, so the equality is not vacuous); `Mirror` over the value enumerates only the declared facts and no store, launcher, session or clock; and the initializer's parameter list contains no type conforming to `ProcessLaunching`, no `URLSession`, no `*Store`, no `*Coordinator` and no `Clock` — there is nothing of that kind to inject |

**Existing suites that MUST keep passing unedited**: `AppSectionPlacementTests`, `HomeCompositionTests`,
`HealthCompositionTests`, `SnoozeProjectionTests`, `InstalledFilterCompositionTests`, `ServicesRefreshTests`,
`ServiceSubmissionTests`, `ServicesPresentationTests`, `ServicesRefreshControlTests`' shipped rows,
`MutationCommandTests`, `SecurityCompositionTests`. The placement suite and the Health suite passing
**without edits** are the proof of **DD-15** and of "Health is not migrated".

## Threat Matrix

**N/A — no new routing, shell, subprocess, VCS/PR automation, executable-file classification, or
process-integration boundary.** The popover composes no argv, spawns no process and adds no brew invocation:
"Upgrade all" is the byte-unchanged `MutationCommand.upgradeAll` through the shipped `OperationCenter`, and
every service verb is the byte-unchanged `ServiceRowControl.command(for:)` through `submit(service:)` and its
shipped in-flight guard (`OperationCenterServices.swift:33–39`). The one new async hop (**DD-6**) calls a
method on a coordinator that already exists and already owns that probe. After **correction 1** the surface
contains no AppKit call at all. A `MenuBarExtra` scene is scene composition, not routing in the
threat-matrix sense.

## Risks and mitigations

| # | Risk | Mitigation in this design |
|---|---|---|
| **R1** | Three outdated numbers; **D1** changes a number users already see | **DD-2** + **T7** + **T18**: all three read one call one layer down, asserted per surface and swept app-wide. Pre-existing non-compliance with installed-inventory `:495–505`, fixed here |
| **R2** | Services visibility collision leaves the poll running | **DD-6** + **T5**/**T9**: `refreshBaseline()` cannot reach either half of the conjunction, and no menu-bar source carries a visibility or cadence token |
| **R3** | A latched confirmation blocks the channel | **DD-10** + **T8**: only `requiresConfirmation == false` verbs are offered; the channel is asserted absent |
| **R4** | Accidental egress on popover open | **DD-12** + **T8**, swept over the whole directory in the `AppSecuritySources` idiom |
| **R5** | Stale data on open | Accepted, and **DD-6** narrows it: the services list refreshes once; the inventory is read as-is. **No freshness cue** (bound decision 6; menu-bar spec:45, :68) — a cue would be presentation for a state the app cannot measure per-surface |
| **R6** | No free keyboard/VoiceOver in a `.window` popover | **DD-13**: `Button`-based controls with identifiers and labels; `ServiceControls`' shipped labels inherited. Status item explicitly out of scope |
| **R7** | `scenePhase` unreported with every window closed | **Recorded and safe.** `.onChange(of: scenePhase)` hangs off the `WindowGroup` content (`:525–527`), so with no window `isAppActive` latches — but `ServicesListView.onDisappear` sets `isSectionVisible = false` on window close and the gate is `&&`. **A latched `isAppActive == true` cannot start a poll on its own.** The menu bar reports neither half |
| **R8** | `isInserted:` needs a `Binding<Bool>` where `@Bindable` is unavailable | **DD-7**, over the shipped `cellar/Updates/UpdatesSettingsGroup.swift:58–64` precedent |
| **R9** | Artifact overshoot against 5,000 | Forecast below; `sdd-tasks` re-measures before apply |
| **R10** | **New.** `.task` on `MenuBarExtra` content may not re-fire on every presentation under `.window` style | **The design does not depend on it.** Bound decision 3 and menu-bar spec:203 make the contract *last-known status*; the refresh is a freshening, never a load. If it fires once per launch instead of once per open, the popover still shows the list the app already holds and the Services section still polls exactly as today. `sdd-apply` verifies the observed behaviour and records it; no fallback mechanism is added speculatively |
| **R11** | **New, and now observation-only.** The system may activate the app when a status item is clicked, and `observeActivations()` (`cellar/cellarApp.swift:649–657`) already calls `refreshEverything()` — a superset of the intended single refresh | **Correction 1 removed this change's only deliberate activation call**, so nothing here *causes* an activation; whatever the system does on a status-item click is shipped app-lifetime behaviour that this change neither extends nor gates. `ServicesStore` coalesces same-request refreshes, and `refreshEverything`'s `servicesRefresher.refresh(for:)` ends in `syncPolling()`, which `guard isVisible else { return }`s — so **no poll starts** (R2 again, from the second direction). Recorded for the verify report, not designed around |
| **R12** | **New.** Reading the inventory in `App.body` widens the App scene body's observation to every inventory refresh | **DD-9**'s outer ternary short-circuits, so with the feature off (the default) no observation is established at all — which is what makes menu-bar spec:310–311's "no other observable difference" true rather than hoped (**T12** pins the exact expression). With it on, the cost is scene-body re-evaluation, which reconstructs value structs; `.task` identity is stable so no loop restarts |

## Migration / rollout

**No migration.** One new additive `UserDefaults` key (`menuBar.isShown`); no existing key changes meaning;
nothing persists to SwiftData (menu-bar spec:318–319); no process, no brew invocation, no schema. Off by
default, so an unshipped defect is invisible to anyone who never enables it.

**Two independent rollback boundaries**, exactly as the proposal promised:

1. *The scene.* `git rm -r cellar/MenuBar`, delete the `MenuBarExtra` block, the `menuBar` `@State` and its
   `init()` construction, the `id: "main"` line, the `MenuBarSettingsGroup()` line and the `SettingsView`
   doc-comment hunk, and `MenuBarProjection.swift` with its test. `ServiceControls`' defaulted parameter and
   `compactControls(for:)` may stay or go independently — both are additive.
2. *D1.* `cellar/Shell/SidebarView.swift` and `cellar/Home/HomeView.swift` revert on their own, two call
   sites, without touching the menu bar; and the menu bar reverts without touching them.

Whole change: revert the PR. `cellar.xcodeproj/project.pbxproj` is untouched either way.

## Size forecast

Projection + its tests ≈ 405; services deltas + their tests ≈ 160; popover, preference, Settings card ≈ 310;
app wiring + D1 ≈ 60; composition tests ≈ 470; spec artifacts (delivered) ≈ 520; remaining SDD artifacts
≈ 700–1,000. **Total ≈ 2,600–2,900 against 5,000.** `400-line budget risk: N/A` (project budget is 5,000);
**5,000-line budget risk: Low**. Single PR under the cached `single-pr` strategy. `sdd-tasks` should still
sequence **D1** as its own early work unit so a slice stays available if the forecast moves.

## Open questions

- [x] **Closed (DD-7)**: the `Binding<Bool>` is an explicit `Binding(get:set:)` over an `@Observable`
      preference held as app-level `@State`.
- [x] **Closed (DD-6)**: the single services refresh is triggered by a `.task` on the `MenuBarExtra` content
      **in `cellar/cellarApp.swift`**, calling a new coordinator method; no file under `cellar/MenuBar/`
      carries an async token.
- [x] **Closed (DD-9, corrected)**: `statusItemTitle` is `String?` and is **`nil`** at zero — never `"0"`,
      never `""`. The framework adaptation is one `?? ""` at one call site.
- [x] **Closed (DD-3, corrected)**: the remainder is `Int?`/`String?`, absent at ≤ 5, with the singular
      `and 1 more`.
- [x] **Closed (DD-10, corrected)**: `openWindow(id: "main")` alone. No `NSApplication`, no `NSApp`, no
      activation call.
- [x] **Closed (DD-1, DD-14)**: the projection exposes the full `outdatedIDs` set, is `Equatable`, and is
      recomputed per body evaluation without memoization.
- [x] **Closed (DD-13)**: keyboard/VoiceOver duties are the popover's controls; the status item is out of
      scope, and the spec pins no copy for it.
- [ ] **For `sdd-apply`, verify before committing.** The SF Symbol used for the status item must exist in
      this SDK. `cellar/Shell/AppSection.swift:164–170` records two cases where a plausible name had to be
      verified or replaced (correction 9). Candidates in order: `shippingbox`, then `cube.box`. Verify in
      SF Symbols; do not ship an unverified name.
- [ ] **For `sdd-apply`, observe and record (R10).** Whether `.task` on `.window`-style `MenuBarExtra`
      content re-runs per presentation. Record what is observed in the verify report; do not add a fallback
      mechanism unless the observation shows the refresh never fires at all.

**No product-level open questions.** D1–D4 and the ten bound decisions are settled and are not reopened here;
the ten corrections above changed only how this document describes their implementation, never what was
decided.
