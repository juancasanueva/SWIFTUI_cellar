# Tasks: an optional menu bar extra over one outdated projection (`m12-menu-bar`)

Refs: `MB:n` / `II:n` / `SM:n` = line `n` of `specs/menu-bar|installed-inventory|service-management/spec.md`;
`Tn` = design test row; `DD-n` = design decision. Commands: **core** = `swift test --package-path Packages/CellarCore`;
**app** = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ≈1,900–2,200 code+tests; ≈2,600–2,900 with SDD artifacts |
| 400-line budget risk | High |
| 5,000-line budget risk (project rule) | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR; work units 1–6 stay separate commits |
| Delivery strategy | single-pr |
| Chain strategy | size-exception |

Decision needed before apply: Yes
Chained PRs recommended: No
Chain strategy: size-exception
400-line budget risk: High

`single-pr` over budget requires a recorded `size:exception` before apply. The maintainer already set an
unlimited review budget for this milestone, so this is a confirmation, not a reopened decision.

### Suggested Work Units

| Unit | Goal | PR | Focused test | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | D1 badge alignment | 1 | app `/MenuBarCompositionTests` | Launch; sidebar badge and Home card agree under a snooze | `SidebarView.swift`, `HomeView.swift` |
| 2 | `MenuBarProjection` | 1 | core `--filter MenuBarProjectionTests` | N/A — pure value, no runtime boundary | `MenuBarProjection.swift` + its tests |
| 3 | Services deltas | 1 | core `--filter "ServiceCommandTests\|ServicesRefreshControlTests"` | N/A — proven on the injected clock | `compactControls`, `refreshBaseline()` |
| 4 | Preference + Settings | 1 | app `/MenuBarCompositionTests` | Toggle `Show in menu bar`, relaunch, still on | `MenuBarPreference.swift`, `MenuBarSettingsGroup.swift` |
| 5 | Popover view | 1 | app `/MenuBarCompositionTests` | N/A — not yet in a scene; source-scan proven | `MenuBarPopoverView.swift` |
| 6 | Scene wiring | 1 | app, then full `test_command` | Enable, click status item, Upgrade all, Open Cellar with no window | scene block + `@State` + `id: "main"` |

Units 1–4 are mutually independent and may run in parallel. Unit 5 requires 2 and 3. Unit 6 requires 4 and 5.

## Phase 1: D1 badge alignment (unit 1)

- [x] 1.1 RED `T18` in new `cellarTests/MenuBarCompositionTests.swift`: app-wide scan finds zero collection-derivation shapes, with a positive anchor proving the detector matches the literal (II:77).
- [x] 1.2 GREEN `cellar/Shell/SidebarView.swift:218` and `cellar/Home/HomeView.swift:142` read `InstalledBrowse(...).outdatedCount(metadata:)`, lookup as `metadata.availability.isAvailable ? metadata.snapshot.lookup : nil` (II:45, DD-2).
- [x] 1.3 Assert `cellar/ContentView.swift` byte-identical; run app.

## Phase 2: `MenuBarProjection` (unit 2)

- [x] 2.1 RED `T1`/`T2` in new `Packages/CellarCore/Tests/BrewClientTests/MenuBarProjectionTests.swift`: set equality with `outdatedIDs(metadata:)`, snooze and self-updating cask excluded by delegation (MB:70, MB:80, MB:132, II:87).
- [x] 2.2 RED `T3`: 12 ⇒ 5 + `and 7 more`; 6 ⇒ `and 1 more`; 5 and 4 ⇒ `nil`; 0 ⇒ title `nil`, never `"0"`/`""`; empty and unavailable are ordinary zeroes (MB:88, MB:116, MB:124, MB:150).
- [x] 2.3 RED `T19`: `Equatable` non-vacuous, composed twice equal, no launcher/session/store/clock parameter (MB:96).
- [x] 2.4 GREEN new `Packages/CellarCore/Sources/BrewClient/MenuBarProjection.swift` exactly per the DD-1/DD-3/DD-9 interface.
- [x] 2.5 REFACTOR: confirm no `filter(\.isOutdated)` and no `InstalledPackage.isOutdated` read; run core.

## Phase 3: Services core deltas (unit 3)

- [x] 3.1 RED `T4` in `ServiceCommandTests.swift`: all eight `ServiceStatus` cases including `.other` and `.unrecognised("…")`; never a lone `.start`/`.run`; distinct argv (MB:248, MB:256, MB:265).
- [x] 3.2 GREEN `ServiceRowControl.compactControls(for:)` in `ServiceCommand.swift` — exhaustive switch, no `default:` (DD-5).
- [x] 3.3 RED `T5`/`T6` in `ServicesRefreshControlTests.swift`: one refresh, no visibility reported, nothing scheduled on the clock, 60s advance adds no invocation, skipped (not deferred) while mutating (SM:99, MB:224).
- [x] 3.4 GREEN `refreshBaseline()` on `ServicesRefreshCoordinator.swift`, touching no visibility state (DD-6).
- [x] 3.5 Add the defaulted `controls` parameter at `cellar/Services/ServiceControls.swift:36`; assert `ServicesListView.swift` 0-line diff; run core.

## Phase 4: Preference and Settings (unit 4)

- [x] 4.1 RED `T11`: missing key ⇒ `false`, scene not inserted, insertion bound to the preference and nothing else (MB:325, MB:332).
- [x] 4.2 RED `T17`: `Show in menu bar` exactly once, no schedule/notification row, shipped update row explicitly excluded from the forbidden list (MB:341).
- [x] 4.3 GREEN new `cellar/MenuBar/MenuBarPreference.swift` — `@MainActor @Observable final class` over injected `UserDefaults` (DD-7).
- [x] 4.4 GREEN new `cellar/MenuBar/MenuBarSettingsGroup.swift` plus two hunks in `cellar/Settings/SettingsView.swift` (doc comment :9–15, one line at :77) (DD-11); run app.

## Phase 5: Popover view (unit 5)

- [x] 5.1 RED `T8`: `private enum MenuBarSources` enumerates every `.swift` under `cellar/MenuBar/` via `#filePath`, reusing `AppSecuritySources.stripComments(from:)`; positive anchor ≥3 files; every DD-12 token absent; no `pendingConfirmation` (MB:290, MB:299).
- [x] 5.2 GREEN new `cellar/MenuBar/MenuBarPopoverView.swift`: count row, ≤5 entries plus `andMoreLabel`, uncounted `Upgrade all` with `CopyCommandButton`, `compactControls` rows, `Open Cellar` (DD-8).
- [x] 5.3 RED then GREEN `T13`: no literal `brew upgrade`; no `NSApplication`/`NSApp`/`.activate(` anywhere (MB:183, MB:192, MB:360).
- [x] 5.4 Add the DD-13 accessibility identifiers and labels; group rows with `.accessibilityElement(children: .combine)`; run app.

## Phase 6: Scene wiring and verification (unit 6)

- [x] 6.1 RED `T9`, `T10`, `T12`, `T14`, `T15`, `T16`: one refresh site in the app, About-window environment repeated, `String?` title with exactly one `?? ""`, no new section, `openWindow(` exactly once, no store or loop in the scene (MB:158, MB:215, MB:368, MB:390, MB:398).
- [x] 6.2 GREEN `cellar/cellarApp.swift`: `MenuBarExtra` with the short-circuiting ternary title, `isInserted:` `Binding(get:set:)`, `.menuBarExtraStyle(.window)`, `.task { await servicesRefresher.refreshBaseline() }`, `id: "main"` on `WindowGroup`, preference `@State` built in `init()` (DD-6, DD-9, DD-10).
- [x] 6.3 Extend `T7` with the menu-bar clause so all three surfaces trace to `outdatedCount(metadata:)` (II:69).
- [x] 6.4 Verify `shippingbox` exists in this SDK (fallback `cube.box`); record whether `.task` re-fires per presentation under `.window` style (R10). Observation only — no speculative fallback.
- [x] 6.5 Assert 0-line diffs on `cellar.xcodeproj/project.pbxproj`, `cellar/Shell/AppSection.swift`, `cellar/ContentView.swift`, `cellarTests/AppSectionPlacementTests.swift`; run core and the full `test_command`.

## Notes

- Threat matrix: **N/A** per design — no routing, shell, subprocess, VCS or process-integration boundary is introduced, and the surface contains no AppKit call.
- Verification classes: 14 `unit` + 15 `unit-app`; `ui` is 0 deliberately (MB:33).
- Must keep passing unedited: `AppSectionPlacementTests`, `HomeCompositionTests`, `HealthCompositionTests`, `SnoozeProjectionTests`, `InstalledFilterCompositionTests`, `ServicesRefreshTests`, `ServiceSubmissionTests`, `ServicesPresentationTests`, `MutationCommandTests`, `SecurityCompositionTests`.
