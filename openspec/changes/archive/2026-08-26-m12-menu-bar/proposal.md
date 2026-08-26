# Proposal: `m12-menu-bar` — an optional menu bar extra over one outdated projection

Anchors PRD.md **M6 "Ship"** (§7 :217, "Menu bar extra") — its fifth slice. Scope is the **first
bullet of §3.8 only** (:113). §3.8's background checks, `SMAppService` login item, schedules and
`UNUserNotificationCenter` (:114–115) are explicit non-goals. Inputs: `explore.md` (obs `#7819`,
as-of `main` @ `f2efbdd`), maintainer scope decisions 2026-08-25 (**binding**, D1–D4 below).

## Intent

Cellar tells the user how many packages are outdated only while its window is open. The number it
would show there is already computed, already snooze-aware, and already app-level: every store is
owned by `cellarApp` for the app's lifetime (cellarApp.swift:23–194, the rule
`installed-inventory` "Refresh loops are owned for the app's lifetime" spec:475–480 requires), so a
second scene reads the same instances with no new store, no new loop and no duplicated state. The
missing piece is a surface, not a mechanism.

It is worth doing now for a second reason. The count already **disagrees with itself** in the
shipped app: the Updates list, the Updates lens, the bulk-upgrade label and Health all read the
snooze-aware `InstalledBrowse.outdatedIDs(metadata:)`, while the sidebar "Updates" badge
(SidebarView.swift:217–219) and the Home attention card (HomeView.swift:142) read
`packages.filter(\.isOutdated).count`. `installed-inventory` spec:495–505 (the snooze requirement,
II12) says a snoozed package "MUST NOT contribute to the outdated count **or badge**", so those two
surfaces are non-compliant today. Adding a third consumer without settling this would ship a menu
bar that contradicts either the sidebar or the spec.

## Scope

### In Scope

- **D1 — Badge alignment (binding).** `SidebarView`, `HomeView`'s attention card and the menu bar
  all read `InstalledBrowse.outdatedCount(metadata:)` / `outdatedIDs(metadata:)`. Fixing the two
  non-compliant surfaces is part of this change, not a follow-up: it changes a number the user
  already sees, so it is stated as a decision.
- **`MenuBarProjection`** (working name) — a `nonisolated`, `Sendable` value in
  `Packages/CellarCore/Sources/BrewClient/`: the outdated count, the top-N outdated entries, and a
  service summary. A **projection over** `InstalledBrowse` and the services snapshot, never a
  reimplementation — the `upgradableIDs` idiom (InstalledFilterMode.swift:186–196), created for
  exactly the M2-2 defect where a label and a submission computed the same number twice.
- A third `Scene` in `cellarApp` — `MenuBarExtra` with `.menuBarExtraStyle(.window)`, gated by
  `isInserted:`, repeating the theme environment the way the About `Window` does
  (cellarApp.swift:562–570). The count reaches the status item as a **title string** beside an SF
  Symbol; no rendered badge image.
- **D2 — Upgrade action (binding).** An **uncounted "Upgrade all"** submitting
  `MutationCommand.upgradeAll` (bare `brew upgrade`, `requiresConfirmation == false`), with the
  exact command shown or copyable via the shipped `CopyCommandButton` convention
  (InstalledListView.swift:241; PRD §3.9 :119). The **badge** carries N; the **button** carries
  none — so the "A bulk action's label counts exactly the set it submits" requirement
  (installed-inventory spec:647–652) is satisfied by construction rather than by argument.
- **Top outdated packages**: a fixed **N = 5** from the projection, in the inventory's existing name
  order (InstalledModels.swift:193–196 — there is no severity or recency order today), plus an
  "and M more" line. The rest is reached by opening the main window's Updates section.
- **D3 — Services (binding).** Last-known status, **one** refresh when the popover opens, **no**
  5-second poll while open. `ServicesRefreshCoordinator`'s two-half visibility conjunction is **not**
  extended. Controls: running → **Stop**, **Restart**; stopped → **"Start at login"** and
  **"Run once"** as two separately labelled items (service-management spec:196 — a single toggle
  would have to silently pick one).
- **D4 — Default off (binding).** Opt-in through a **"Show in menu bar"** Settings toggle, persisted
  in a small `UserDefaults`-backed preference with an injectable suite (the
  `AutomaticUpdateChecks(defaults:)` precedent, cellarApp.swift:381–385), so a UI-test launch never
  writes the developer's real preferences. `SettingsView.swift:9–15` — which names "a menu bar
  extra" as a capability Cellar does not have — is amended in the same change.
- **"Open Cellar"**: the `WindowGroup` gains an `id:` so `openWindow(id:)` serves it, mirroring
  `AboutView.swift:152–156`, rather than an AppKit activation path.

### Out of Scope (explicit non-goals)

- Background checks, `SMAppService`, login items, periodic `brew update`, scheduled re-scans, and
  **any** `UNUserNotificationCenter` use (PRD :114–115). No Settings row for them either — the
  `SettingsView` rule still forbids rows for capabilities that do not exist.
- **Any confirmation from the popover.** `pendingConfirmation` lives on the shared `OperationCenter`
  and its only presenter is `ContentView.body` (ContentView.swift:163–167); a request raised with no
  window open would latch unanswered and block the whole confirmation channel. Uninstall, zap and
  every confirmation-requiring verb stay out.
- **Any egress from the popover**: no `.task` loader, no `Process`, no `URLSession`, and **no**
  `PackageIconTile`/`CaskIconLoader` artwork — a cask icon in a popover is a new network surface
  fired by opening a menu.
- A new `AppSection` — the menu bar is a scene, not a section. `AppSection.allCases.count == 22` and
  `ContentView`'s asserted switch count of 3 (AppSectionPlacementTests.swift:36, :159) stay put.
- Any status-item **XCUITest**, and any new brew invocation or command shape.
- Approach **D** (AppKit `NSStatusItem` + `NSHostingView`) — rejected: hand-rolled lifetime and
  teardown, a new AppKit surface inside a structurally policed target, and strictly more code for a
  drawn-badge benefit D2 does not ask for.
- Approach **B** (`.menu` style) — rejected: it cannot carry `themeCard`, `StatusPill` or the accent
  tint, so the surface would look like a different app, and PRD's "outdated count badge" would
  degrade to a bare title with no room for the top-outdated presentation. Its free keyboard and
  VoiceOver support is a real loss, carried as R6.

## Capabilities

### New Capabilities

- `menu-bar`: the scene's existence and its opt-in preference; the **single-projection duty** for
  the count; what the popover may and may not do (no egress, no loader, no artwork pipeline, no
  confirmation-raising mutation); the one-refresh-on-open services contract; and "open main window".
  Folding this into `installed-inventory` would put scene composition into a capability whose
  subject is an inventory value type. Per `config.yaml:47`, the **projection** is specified as
  CellarCore behaviour; the scene wiring is proven by app-target composition tests, the split Health,
  tap-search and release-notes already use.

### Modified Capabilities

- `installed-inventory`: **ADDED** — every surface that announces the outdated count derives it from
  one projection, generalising the bulk-label requirement (spec:647–652) from one control to every
  count-bearing surface. This is the honest delta shape: the snooze requirement (spec:495–505)
  already binds badges, so D1's sidebar/Home fix is *compliance*, and the new requirement is what
  makes a third consumer safe to add. Shipped scenarios stay byte-identical.
- `service-management`: **MODIFIED** — one clause on "The services surface polls only while visible"
  (spec:100–113). Today's text couples "becomes visible" to "then refresh every 5 seconds", so a
  secondary read-only surface has no described home. The clause states that such a surface MAY
  perform a **single** baseline refresh on appearance, MUST NOT report visibility, MUST NOT start or
  extend a poll, and is suppressed while a service mutation is in flight. All four shipped scenarios
  byte-identical; one added.
- `package-mutation`: **none.** `upgradeAll` already lowers to bare `["upgrade"]` and already
  requires no confirmation (spec:180–186, :245–251) — activated, not changed.

## Approach

**A + C** from `explore.md` §11. **C** first: the projection is a value type in `BrewClient` (the
target that owns `InstalledInventory`), unit-tested in the fast `swift test` loop with no SwiftUI and
no `Process`, so "the menu bar and the sidebar cannot disagree" becomes a property of a value rather
than of two view files that happen to concur. **A** second: the scene reads that projection plus the
already-wired `installed`, `metadata`, `services` and `operations` instances, and renders them with
the shipped theme components, so the popover cannot drift from the app's design.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `BrewClient/MenuBarProjection.swift` | **New** | Count, top-N outdated entries, service summary; derived, never recomputed |
| `cellar/MenuBar/MenuBarPopoverView.swift` | **New** | The whole popover surface: badge row, top outdated, Upgrade all + copy, service controls, Open Cellar |
| `cellar/MenuBar/MenuBarPreference.swift` | **New** | `UserDefaults`-backed opt-in with an injectable suite |
| `cellar/cellarApp.swift` | Modified | Third scene with `isInserted:`; theme environment repeated; `id:` on the `WindowGroup`; preference constructed in `init()` |
| `cellar/Settings/…` | Modified/New | "Show in menu bar" row in its own group file (the `UpdatesSettingsGroup` precedent); `SettingsView.swift:9–15` doc comment amended |
| `cellar/Shell/SidebarView.swift:217–219` | Modified | Badge reads `outdatedCount(metadata:)` (**D1**) |
| `cellar/Home/HomeView.swift:142` | Modified | Attention card reads the same projection (**D1**) |
| `Tests/BrewClientTests/` | **New** | Projection rows: snooze exclusion, self-updating casks, top-N ordering and truncation, empty/unavailable inventory |
| `cellarTests/` | **New/Modified** | Menu-bar composition + `AppSecuritySources` prohibition sweep; sidebar/Home badge-source assertions |
| `cellar.xcodeproj/project.pbxproj` | **Untouched — binding 0-line diff** | `cellar/` and `cellarTests/` are themselves `PBXFileSystemSynchronizedRootGroup` roots (pbxproj:44–53), so a **new `cellar/MenuBar/` directory joins the target with no project-file edit** |

### Impact on existing tests

- `AppSectionPlacementTests` — expected **unchanged**: no new `AppSection`, and `ContentView` gains
  no switch, so :36 (22 cases) and :159 (3 switches) must still pass untouched. A diff to either
  literal is a defect in this change, not a licensed edit.
- The `AppSecuritySources.load()` sweep (SecurityCompositionSupport.swift:42–86) enumerates every
  `.swift` under `cellar/`, so `cellar/MenuBar/` enters it the moment it exists. This change adds
  its own prohibitions in that idiom rather than relying on the sweep to notice.
- `HealthComposition` expectations — **unchanged**: HealthComposition.swift:71 already reads
  `browse.outdatedIDs(metadata:)`, so D1 does not touch the Health reading path. Health is
  deliberately **not** migrated onto `MenuBarProjection` in this change.
- `SnoozeProjectionTests` (`BrewClientTests`) is the existing owner of the snooze-aware set and is
  the baseline the new projection rows compose above.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| R1 Three outdated numbers; D1 changes a number users already see | **High** | Pre-existing, not introduced. One projection, one ADDED requirement, and per-surface source assertions so a regression fails a test rather than a screenshot |
| R2 Services visibility: a naive `setVisible(true)` from the popover collides with the section's own reporting and can leave the poll running after the section closes | **High** | D3 forbids it: one refresh on open, no visibility report, conjunction untouched (ServicesRefreshCoordinator.swift:52–62) |
| R3 A latched confirmation blocks the whole channel | Med | No confirmation-raising verb is offered; asserted as an absence in the popover's source |
| R4 Accidental egress (artwork, loader, `Process`) fired by opening a popover | Med | Explicit prohibition test in the `AppSecuritySources` idiom; the only permitted async is the single services refresh D3 names |
| R5 Stale data on open — `refreshEverything()` is keyed to `didBecomeActiveNotification` (cellarApp.swift:649–657) and a status-item click may not activate the app | Med | Accepted for the inventory: the popover shows last-known state honestly. `sdd-design` decides whether the projection surfaces a freshness cue |
| R6 No free keyboard or VoiceOver support in a `.window` popover, against PRD :123 | Med | Cost of rejecting B. `Button`-based controls throughout, explicit `accessibilityLabel`s, and an accessibility acceptance item below |
| R7 `scenePhase` no longer reports with every window closed (cellarApp.swift:525–527 hangs off the `WindowGroup`'s content) | Med | The section's own `onDisappear` still falsifies the conjunction, so no poll survives; `sdd-design` records the latching explicitly rather than discovering it |
| R8 `MenuBarExtra(isInserted:)` needs a `Binding<Bool>` where `@Bindable` is unavailable (`App` is not a `View`) | Med | A known-shape design decision, not a research task: `@Observable` preference + manual `Binding(get:set:)`, or `@AppStorage` on the `App`. `sdd-design` picks one and says why |
| R9 Artifact overshoot against the 5,000 budget (m7 overshot 5–7×; m11 finished at ~4,900–5,200) | Med | Forecast below; `sdd-tasks` re-measures before apply and slices rather than discovering it at verification |

## Rollback Plan

`rules.proposal` mandates one for anything touching the Xcode project file or target membership.
**Neither is touched**: `cellar/` and `cellarTests/` are synchronized root groups (pbxproj:44–53), so
a new `cellar/MenuBar/` directory and its files join their targets with a **0-line pbxproj diff**. A
non-zero `project.pbxproj` diff is a defect, not a rollback step — restore with
`git checkout HEAD -- cellar.xcodeproj/project.pbxproj` and re-verify membership.

Two independent boundaries:

1. **The scene.** Deleting `cellar/MenuBar/`, the scene block, the Settings group and the preference
   returns the app to today. The feature is **off by default**, so an unshipped defect is invisible
   to anyone who never enabled it; the stored preference is one `UserDefaults` key with no migration
   and no file format.
2. **D1.** The badge alignment is revertible on its own (two call sites) without touching the menu
   bar, and the menu bar is revertible without reverting D1.

Whole change: revert the PR. Nothing persists — no new process, no new brew invocation, no schema.
The three spec artifacts revert with the change folder; promoted `openspec/specs/` are untouched
until archive.

## Dependencies

None new. No new brew invocation, no new external service, no new package. Every store, verb and
theme component the popover renders is already shipped and app-level.

## Size Forecast

Projection + its `BrewClientTests` rows ≈ **400–580**; popover, preference and Settings group ≈
**350–500**; `cellarApp`, sidebar and Home wiring ≈ **60–100**; app-target composition/prohibition
tests ≈ **300–500**; spec artifacts (new `menu-bar` spec + two deltas) ≈ **350–600**; remaining SDD
artifacts (design, tasks, verify report) ≈ **600–1,000**.

**Total ≈ 2,100–3,300 authored lines against the 5,000 budget under the cached `single-pr`
strategy — budget risk: Medium.** Single-PR delivery is viable; the pressure is artifact overshoot,
not code. `sdd-tasks` must sequence D1 as its own early work unit so a slice remains available
without unpicking the scene.

## Success Criteria

- [ ] With the Settings toggle **off** (the default), the app has no status item and behaves exactly
      as it does today.
- [ ] Turning "Show in menu bar" on inserts the status item; turning it off removes it; the choice
      survives relaunch and is written to an injectable defaults suite.
- [ ] The status item's count, the sidebar "Updates" badge and the Home attention card **all** equal
      `InstalledBrowse.outdatedCount(metadata:)`, including with a snooze in effect and with a
      self-updating cask installed.
- [ ] The popover lists at most 5 outdated packages in inventory name order plus an "and M more"
      line, drawn from the same set the count counts.
- [ ] "Upgrade all" submits bare `brew upgrade`, carries **no count**, discloses the exact command,
      and raises no confirmation.
- [ ] A running service offers Stop and Restart; a stopped one offers "Start at login" and
      "Run once" as two labelled items; no single toggle exists.
- [ ] Opening the popover performs exactly **one** services refresh and starts no poll; closing and
      reopening the Services section still polls exactly as it does today.
- [ ] "Open Cellar" opens the main window, including when every window is closed.
- [ ] The menu-bar sources contain no `.task` loader, no `Process(`, no `URLSession`, no
      `CaskIconLoader`/`PackageIconTile`, and no confirmation-raising verb — each asserted as an
      absence.
- [ ] `AppSection.allCases.count == 22` and `ContentView`'s switch count of 3 are unchanged; no new
      `AppSection` exists.
- [ ] `SettingsView.swift`'s doc comment no longer claims Cellar has no menu bar extra.
- [ ] `cellar.xcodeproj/project.pbxproj` diff is 0 lines.
