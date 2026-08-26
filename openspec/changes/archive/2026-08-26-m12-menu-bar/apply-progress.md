# Apply progress: `m12-menu-bar`

**Mode**: Strict TDD (`strict_tdd: true`, Swift Testing `@Test` / `#expect`).
**Delivery**: `single-pr` with a recorded `size:exception` (project budget 5,000; authored delta 1,642).
**Branch**: `feat/m12-menu-bar`, six work-unit commits, not pushed, no PR opened.
**Batch**: first and only apply batch — no prior `apply-progress` existed.

29/29 tasks complete. All six work units delivered.

## Work unit summary

| Unit | Commit | Focused test command | Result |
|---|---|---|---|
| 1 D1 badge alignment | `d507258` | app `-only-testing:cellarTests/MenuBarCompositionTests` + `HomeCompositionTests` + `AppSectionPlacementTests` | 12/12 pass |
| 2 `MenuBarProjection` | `0acdb10` | core `--filter MenuBarProjectionTests` | 4/4 pass |
| 3 Services deltas | `962360f` | core `--filter 'ServiceCommandTests\|ServicesRefreshControlTests'` | 16/16 pass |
| 4 Preference + Settings | `445f9ac` | app `-only-testing:cellarTests/MenuBarCompositionTests` | 5/5 pass |
| 5 Popover view | `e0e6ffd` | app `-only-testing:cellarTests/MenuBarCompositionTests` | 7/7 pass |
| 6 Scene wiring | `22516eb` | app `-only-testing:cellarTests/MenuBarCompositionTests`, then full `test_command` | 12/12 pass |

## TDD cycle evidence

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 1.1–1.3 T18 | `cellarTests/MenuBarCompositionTests.swift` | unit-app | 11/11 (`HomeCompositionTests`, `AppSectionPlacementTests`) | Written — failed on the two shipped offenders | Passed | 4 detector cases (positive anchor, two delegated reads, one raw read) | Detector extracted to `OutdatedDerivation`, tests still green |
| 2.1–2.5 T1/T2/T3/T19 | `Packages/CellarCore/Tests/BrewClientTests/MenuBarProjectionTests.swift` | unit | N/A (new file) | Written — `cannot find 'MenuBarProjection' in scope` | Passed | 12 fixtures: 12/6/5/4/3/0 outdated, empty, unavailable, snoozed, self-updating cask, no-metadata | Initializer scan widened to every declared init after the anchor caught the nested one |
| 3.1–3.2 T4 | `ServiceCommandTests.swift` | unit | 9/9 shipped rows in the suite | Written — `no member 'compactControls'` | Passed | All 8 `ServiceStatus` cases, both sets, argv pair | Exclusive-or assertion replaced a `Set` superset check (`ServiceRowControl` needs no `Hashable` use) |
| 3.3–3.5 T5/T6 | `ServicesRefreshControlTests.swift` | unit | 4/4 shipped rows in the suite | Written — `no member 'refreshBaseline'` | Passed | Not-visible baseline, 60 s advance, later `setVisible(true)`, mutation in flight, release | None needed |
| 4.1–4.4 T11/T17 | `cellarTests/MenuBarCompositionTests.swift` | unit-app | 1/1 (T18) | Written — `cannot find 'MenuBarPreference' in scope` | Passed | Missing key, set true, reread, set false; Settings carriers, token sweep | Copy hoisted to one `rowLabel` constant so the literal appears once |
| 5.1–5.4 T8/T13 | `cellarTests/MenuBarCompositionTests.swift` | unit-app | 3/3 | Written — `MenuBarSources` anchor found 2 files, popover absent | Passed | Forbidden-token sweep, confirmation requirement read per verb, `zap` as a positive control | `MenuBarSources` enumerates the directory and cross-checks every file against the app target's own sweep |
| 6.1–6.5 T7/T9/T10/T12/T14/T15/T16 | `cellarTests/MenuBarCompositionTests.swift` | unit-app | 5/5 | Written — 6 of 7 failed before the wiring | Passed | Scene block vs About block, three surfaces vs one call, absence sweeps | T12 narrowed so the one permitted boundary adaptation is not forbidden at its own call site |

### Test summary

- Tests written: **31** (`unit` 8 new rows across 3 core files, `unit-app` 12 rows in one new app file, plus 11 detector/anchor sub-cases).
- Layers: unit (12), unit-app (12), ui (0 — deliberate, menu-bar spec:33).
- Approval tests: none — no refactoring task in this change.
- Pure values created: `MenuBarProjection` and its `OutdatedEntry`, plus `ServiceRowControl.compactControls(for:)`.

## Work unit evidence

| Unit | Runtime harness | Result | Rollback boundary |
|---|---|---|---|
| 1 | Built and launched `Home-Cellar.app` | Launched clean | `SidebarView.swift`, `HomeView.swift` |
| 2 | N/A — pure value, no runtime boundary | — | `MenuBarProjection.swift` + its test |
| 3 | N/A — proven on the injected `TestClock` | — | `compactControls(for:)`, `refreshBaseline()`, `ServiceControls`' defaulted parameter |
| 4 | Built and launched; Settings renders with the seam absent | Launched clean | `cellar/MenuBar/MenuBarPreference.swift`, `MenuBarSettingsGroup.swift`, two `SettingsView` hunks |
| 5 | N/A at this point — not yet in a scene; proven by source scan | — | `cellar/MenuBar/MenuBarPopoverView.swift` |
| 6 | Full status-item session, below | All steps observed | scene block, `@State` + `init()` line, `id: "main"`, `.environment(menuBar)` |

### Unit 6 runtime session (observed, `System Events` driving the real app)

- Preference key absent → `menu bar 2 of process "Home-Cellar"` does not exist. **No status item, app unchanged.**
- Preference set true, app relaunched → status item present (`menu bar item "Box"`). **The choice survived relaunch.**
- Popover opened → static texts `8`, `outdated`, `UPDATES`, five entries (`ffmpeg`, `libksba`, `little-cms2`, `neovim`, `pnpm`), `and 3 more` (5 + 3 = 8), `brew upgrade`, `SERVICES`, `atuin`, `Not running`.
- Accessibility identifiers present: `menu-bar-upgrade-all`, `menu-bar-copy-command`, `menu-bar-service-atuin-start`, `menu-bar-service-atuin-run`, `menu-bar-open-cellar`. A stopped service offered **exactly** the two start controls and neither `stop` nor `restart`.
- Every window closed, then `menu-bar-open-cellar` clicked → **one standard window opened.** "Open Cellar" works with no window open.
- `Upgrade all` was deliberately **not** clicked: it submits a real `brew upgrade` on the maintainer's machine. Its presence, enablement and disclosed command were verified instead.
- The Settings switch's live click could not be driven: XCUITest-free accessibility traversal of the main window did not enumerate its contents. Both preference states were still observed end to end through relaunch, and the insertion expression is pinned by T11.

## Task 6.4 — the two open questions, answered

**1. Does `shippingbox` exist in this SDK?** **Yes.** `NSImage(systemSymbolName:)` resolved `shippingbox`, `cube.box` and `macwindow`, and rejected a deliberately invalid name, so the check was meaningful rather than vacuously true. The status item rendered with accessibility description `Box`. **The `cube.box` fallback is unnecessary and was not added.**

**2. Does `.task` re-fire per presentation under `.menuBarExtraStyle(.window)`?** **Yes — exactly once per presentation, and not at insertion.** Measured with a standalone `MenuBarExtra` probe whose `.task` appended to a file:

- After launch and insertion, before any click: **0 fires** — the content is built lazily.
- Three open/close cycles: **3 fires**, one per open.

So the design's contract holds as written: the single services refresh happens on each popover open. **No fallback mechanism was added** (R10 closed by observation, per MB:203).

## Final test results

| Suite | Command | Result |
|---|---|---|
| CellarCore | `swift test --package-path Packages/CellarCore` | **1891 tests / 219 suites, 2 failures** (both pre-existing on `main`, see below) + 1 expected known issue |
| App unit | `xcodebuild test … -only-testing:cellarTests` | **274 tests, 0 failures** — TEST SUCCEEDED |
| App UI | `xcodebuild test …` (full `test_command`) | **37 tests, 8 failures** — all eight are the Cleanup rows, latently fragile on `main` (see below) |

## Deviations from the design

1. **`MenuBarPopoverView` does not take a `services: ServicesStore` parameter** (design's interface sketch, DD-8 snippet). The projection already carries `services: [ServiceRecord]` after correction 4, so a second reference to the same list would be exactly the second source of truth DD-1 and DD-14 forbid. Every service row reads `projection.services`; the store is unused and therefore not passed. T16 still proves the scene constructs nothing and passes the same app-level identifiers.
2. **T12's "`?? \"\"` appears in `cellar/cellarApp.swift` exactly once" was factually unavailable.** The shipped file already contained one `?? ""` at `:320` before this change. The assertion was written in the form that carries the design's actual intent: `statusItemTitle ?? ""` appears exactly once across every app source, `var statusItemTitle` is declared exactly once (in `MenuBarProjection.swift`), and **no** file under `cellar/MenuBar/` contains `?? ""` at all.
3. **T15's "`openWindow(` appears exactly once across `cellar/MenuBar/`"** contradicts DD-10 and DD-12, which put the call in `cellarApp.swift` and give the popover a plain closure. The design's own closing clause ("`openMainWindow` is a plain closure parameter, so the popover cannot check what it opened") settles it. Asserted as: `openWindow(` appears exactly once in `cellarApp.swift`, inside the `MenuBarExtra` block, as `openMainWindow: { openWindow(id: "main") }`, and **zero** menu-bar sources reference `openWindow` or any other window token.
4. **T7 was written whole in unit 6 rather than extended.** Task 1.1 assigned unit 1 `T18` only, so no partial T7 existed to extend; task 6.3's menu-bar clause is included in the single delivered row.
5. **T11 and T13 were split across units** for the same reason the tasks file splits T7: their scene-text halves cannot be green before the scene exists. T11's preference half landed in unit 4 and its scene half in unit 6; T13's popover half landed in unit 5 and its `cellarApp` half in unit 6.
6. **`ServiceControls` gained a second defaulted parameter, `identifierPrefix`.** DD-13 requires `menu-bar-service-<name>-<control>` identifiers while DD-8 requires reusing the shipped control component. A defaulted `nil` prefix applies no identifier at all, so the Services section's accessibility tree is byte-unchanged — the same trick DD-5 already uses for `controls`.
7. **`HomeView` reads `outdatedIDs(metadata:)` where task 1.2 says `outdatedCount(metadata:)`.** The card needs the packages themselves for its formula/cask split, and the count it announces is that set's size. DD-2 and T7 both name either call; `SidebarView` reads `outdatedCount(metadata:)`.

## Binding 0-line diffs — all verified

`cellar.xcodeproj/project.pbxproj`, `cellar/ContentView.swift`, `cellar/Shell/AppSection.swift`, `cellarTests/AppSectionPlacementTests.swift`, `cellar/Services/ServicesListView.swift`, `cellar/Services/ServiceRow.swift` and the whole of `cellarUITests/` are **untouched**. `cellar/MenuBar/` joined the target with no project-file edit, as the proposal predicted.

## Issues found

### 1. Two `TapShippingProofTests` rows fail on `main` (pre-existing, not this change)

`The complete tap action surface stays bounded to its four capabilities` and `No new control submits anything and the surface is display only`, both at `TapShippingProofTests.swift:617`. Verified by running the same filter in a clean worktree at `main` @ `f2efbdd`: they fail identically with none of this change present. They scan `cellar/Taps/TapsListView.swift` and `cellar/Taps/TapDetailView.swift`, neither of which m12 touches. Likely introduced by PR #89 (`01dbc05`), which added official-source copy to the tap UI while the suite still excludes that capability string.

`CatalogFootprintTests/The full-catalog footprint stays within its recorded bound` also reported a negative `residentBytes` under one full parallel run and passed when run alone — an environment-dependent measurement, not a code defect.

### 2. Eight Cleanup XCUITest rows are fragile to the saved window frame (pre-existing, surfaced here)

The eight failures are all in `cellarUITests/cellarUITests.swift` and share one cause: at the app's own `.defaultSize(width: 1440, height: 900)` the sidebar's `ScrollView` ends near y=1126 while `sidebar-cleanup` sits at y=1161, so `openCleanup(in:)`'s click never lands, the section never changes, and every later `cleanup-*` identifier is absent.

They pass on `main` **only because this machine has a saved window frame of 1390×1115** under the scene's AppKit autosave key. That key is derived from the `WindowGroup`'s identity, so both `id: "main"` (required by menu-bar spec:352–354) and the added `.environment(menuBar)` modifier reset it, and the window reverts to the declared default.

**Proven pre-existing.** With `git diff` empty at `e0e6ffd` — no m12 scene change present — removing the 32 `NSWindow Frame` / `NSSplitView Subview Frames` keys from `~/Library/Preferences/com.juancasanueva.cellar.plist` made `testCleanupCO7AutoremoveDisclosesExactOrphans` fail identically; restoring the backup made it pass again. These rows therefore also fail on a fresh machine and on CI, independently of m12.

Not repaired here: `cellarUITests/` is outside this change's task list, and editing it would mask the finding. Remedies for the maintainer, in preference order: have `openCleanup(in:)` scroll the sidebar to the row before clicking; raise the window's `.defaultSize` height; or set an explicit frame in the fixture launch.

Diagnostic gotcha recorded with it: `defaults read` and a live process can disagree because `cfprefsd` serves a cached value, so `app.debugDescription` geometry — not `defaults read` — is ground truth.

## Workload / PR boundary

- Mode: single PR, `size:exception` recorded by the maintainer.
- Boundary: starts at `main` @ `f2efbdd`, ends at `22516eb`; six commits, one per work unit, each independently revertible.
- Authored delta: **1,635 additions / 7 deletions = 1,642 lines** against the project's 5,000 budget.
