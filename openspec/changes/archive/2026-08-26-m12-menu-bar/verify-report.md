```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:22338799054685115ddd30d64fe7f25a226e93104973d264c15bdd0e3413b6ff
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 12/12
scenarios: 33/33
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:851f81b3341187e32844957e1344f016e897efe809108ca8a4a166be83cdf514
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
build_exit_code: 0
build_output_hash: sha256:e5cb01c192ef9c1a6cc7febd144d5191283a676e0f3c0c1dac69c6901c579c02
```

## Verification Report

**Change**: `m12-menu-bar`
**Version**: menu-bar (new capability, 10 req / 25 scen) · installed-inventory delta (1 ADDED, 3 scen) · service-management delta (1 MODIFIED, 5 scen)
**Mode**: Strict TDD
**Branch**: `feat/m12-menu-bar`, seven commits `d507258..270f41e` on `main` @ `f2efbdd`
**Re-verified**: at HEAD `270f41e` after the maintainer's tap-copy fix; supersedes the `22516eb` run that reported `fail`
**Artifact store**: hybrid (OpenSpec + Engram `swiftui_cellar`)

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total (checkboxes in `tasks.md`) | 26 |
| Tasks complete | 26 |
| Tasks incomplete | 0 |

`apply-progress.md` reports "29/29 tasks complete". The file contains 26 checkboxes (3 + 5 + 5 + 4 + 4 + 5), all ticked. Bookkeeping mismatch only — see WARNING W1.

### Build & Tests Execution

**Build**: Passed — both targets compiled clean under Swift 6; no new warnings surfaced in either log.

**Tests** — all re-executed at HEAD `270f41e`:

| Suite | Command | Exit | Result |
|---|---|---|---|
| CellarCore package | `swift test --package-path Packages/CellarCore` | **0** | **1891 tests / 219 suites PASSED**, 1 known issue, 0 failures |
| App unit | `xcodebuild test … -only-testing:cellarTests` | **0** | **285 rows passed, 0 failed** — TEST SUCCEEDED |
| Full (incl. UI) | `xcodebuild test …` | 65 | **314 passed, 7 failed** — all 7 are `cellarUITests` Cleanup rows (see W2) |

**The core suite is now green.** The 2 `TapShippingProofTests.swift:617` failures that blocked the previous
run are resolved by commit `270f41e` (analysed below), and both rows pass:
`The complete tap action surface stays bounded to its four capabilities` and
`No new control submits anything and the surface is display only`. All 19 m12-delivered rows remain green.

The remaining 7 UI failures are Cleanup rows only. Note that the **count moved from 8 to 7** between the
`22516eb` and `270f41e` full runs — `testCleanupCO7FullConfirmationDisclosesCommandProvenanceAndWarning`
passed this time with no relevant code change between the two. That instability is itself evidence for the
frame-dependency diagnosis in W2: the click lands or misses depending on the window geometry, so the row
count is not deterministic. No failure occurred anywhere outside `cellarUITests` Cleanup in either run.

### Commit `270f41e` — outside m12's spec scope, same PR by maintainer decision

`fix(taps): point the official-source pane at the Search section by its real name`

**Diff confirmed minimal and isolated**: `cellar/Taps/TapDetailView.swift` only, **1 insertion / 1 deletion**,
one string literal at `:82`. `git show --name-only` lists exactly one file. Nothing else in the repository
is touched.

```
-  … Browse and install its packages from Search catalog.")
+  … Browse and install its packages from the Search section.")
```

**Why it clears the suite.** `TapShippingProofTests` concatenates `TapsListView.swift` and
`TapDetailView.swift` and asserts the text contains none of nine excluded capability names, one of which is
the literal `"Search catalog"`. PR #89 (`01dbc05`) introduced prose naming that section, which tripped the
exclusion. Re-checked independently: after the fix, **none** of the nine excluded capabilities appears in
the tap UI.

**One correction to the commit's framing, recorded for accuracy.** The message describes `the Search section`
as "the AppSection's real name", implying the old copy was wrong. That is only half right.
`AppSection.swift:114` gives `case .browse: "Search"` for `title`, and `AppSection.swift:144` gives
`case .browse: "Search catalog"` for `sidebarTitle` — **both are shipped, user-visible names for the same
section**; the toolbar says one and the sidebar says the other. So the previous copy was not factually
inaccurate; it named the sidebar wording a user actually reads. The new copy is equally accurate and
additionally satisfies the exclusion, so the change is a legitimate resolution — but it is a copy adjustment
that clears a textual proof, not the correction of a factual error.

**Scope**: this commit implements no m12 requirement, is referenced by no m12 scenario, and touches no file
in m12's binding 0-line-diff set. It is verified here only because it shares the PR. All m12 binding 0-line
diffs were **re-confirmed at `270f41e`** and remain empty.

**Coverage**: Not available — no coverage tool is configured for this project. Not a failure.

### The 19 test rows this change delivers — all green

| Row | Class | Test | Result |
|---|---|---|---|
| T1 | unit | `The projection counts and sets exactly what the browse does` | PASS |
| T2 | unit | `A snoozed package is in neither the count, the set, nor the entries` | PASS |
| T3 | unit | `The remainder and the title are absences, not zeroes` | PASS |
| T4 | unit | `Every reportable status maps to exactly one control set` | PASS |
| T5 | unit | `A baseline refresh starts no poll and reports no visibility` | PASS |
| T6 | unit | `A baseline refresh is skipped entirely while a mutation is in flight` | PASS |
| T19 | unit | `The projection has no effectful dependency and is equal composed twice` | PASS |
| T7 | unit-app | `everyOutdatedSurfaceReadsTheOneProjection` | PASS |
| T8 | unit-app | `noMenuBarSourceLoadsEgressesOrConfirms` | PASS |
| T9 | unit-app | `theOneServicesRefreshLivesInTheAppAndStartsNoPoll` | PASS |
| T10 | unit-app | `theMenuBarSceneRepeatsTheAboutWindowsEnvironment` | PASS |
| T11 | unit-app | `thePreferenceIsOffByDefaultAndIsTheOnlyInsertionCondition` | PASS |
| T12 | unit-app | `theStatusItemIsATitleWithNoBadgeImageAndNoLocalCount` | PASS |
| T13 | unit-app | `theUpgradeVerbIsUncountedDisclosedAndTheWindowEntryIsPureSwiftUI` | PASS |
| T14 | unit-app | `theMenuBarAddsNoSectionAndNoShellLiteralMoves` | PASS |
| T15 | unit-app | `noEntryDependsOnAWindowBeingOpen` | PASS |
| T16 | unit-app | `theSceneConstructsNoStoreAndNoRefreshLoop` | PASS |
| T17 | unit-app | `settingsGainsOneRowAndStillDeniesTheAbsentCapabilities` | PASS |
| T18 | unit-app | `noSurfaceInTheAppAnnouncesASelfComputedOutdatedCount` | PASS |

Declared classes were 14 `unit` + 15 `unit-app`; delivered as 7 `unit` rows + 12 `unit-app` rows carrying
those assertions (several declared classes are asserted inside one row — e.g. T4 alone carries all three
service-control scenarios). `ui`: 0, deliberately, per menu-bar spec:33.

### Spec Compliance Matrix

#### menu-bar (10 requirements / 25 scenarios)

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| Projection is pure, delegates outdated-ness | Count equals snooze-aware projection under a snooze | T1 | COMPLIANT |
| " | Self-updating cask excluded without deciding so | T1 | COMPLIANT |
| " | Unavailable/empty inventory is an ordinary zero | T3 | COMPLIANT |
| " | No effectful dependency to inject | T19 | COMPLIANT |
| At most five entries, name order, remainder | Twelve outdated ⇒ five entries + remainder 7 | T3 | COMPLIANT |
| " | Exactly five ⇒ no remainder | T3 | COMPLIANT |
| " | Snoozed in neither entries nor remainder | T2 | COMPLIANT |
| Status item carries count as text, nothing at zero | Title is the count, absent at zero | T3 | COMPLIANT |
| " | Scene renders title and no badge image | T12 | COMPLIANT |
| Upgrade all uncounted, bare command, disclosed | Label carries no count; submission is bare | T13 | COMPLIANT |
| " | Disclosed command is the shipped one | T13 | COMPLIANT |
| Services last-known, one refresh, never polled | Opening refreshes once, leaves no poll | T9, T5 | COMPLIANT |
| " | Mutation in flight suppresses the one refresh | T6 | COMPLIANT |
| Two labelled control sets, never one toggle | Running offers Stop and Restart | T4 | COMPLIANT |
| " | Stopped offers both start controls, separately | T4 | COMPLIANT |
| " | Every status maps to exactly one set | T4 | COMPLIANT |
| Reads only: no load, egress, confirm, artwork | Sources contain none of the forbidden tokens | T8 | COMPLIANT |
| " | No confirmation-raising verb, no channel | T8 | COMPLIANT |
| Opt-in, off by default, injectable suite | With no stored value the app is unchanged | T11 | COMPLIANT |
| " | Insertion bound to the preference alone | T11, T12 | COMPLIANT |
| " | Settings gains one row, stops denying capability | T17 | COMPLIANT |
| Open Cellar opens main window, windows closed | Entry opens main window by scene identifier | T15 | COMPLIANT |
| " | No entry depends on a window being open | T15 | COMPLIANT |
| A scene, not a section; repeats environment | No new section, no shell literal moves | T14 | COMPLIANT |
| " | Scene repeats theme environment, owns no store | T10, T16 | COMPLIANT |

#### installed-inventory (1 requirement / 3 scenarios)

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| Every count-bearing surface reads one projection | Sidebar, Home card and menu bar read one projection | T7 | COMPLIANT |
| " | No surface announces a self-computed count | T18 | COMPLIANT |
| " | Count and set a surface presents cannot disagree | T1 | COMPLIANT |

#### service-management (1 requirement / 5 scenarios)

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| Services surface polls only while visible | Refreshes on the poll cadence while visible (reproduced) | shipped `ServicesRefreshTests` | COMPLIANT |
| " | Hiding stops polling entirely (reproduced) | shipped `ServicesRefreshTests` | COMPLIANT |
| " | Only one poll loop per launch (reproduced) | shipped `ServicesRefreshTests` | COMPLIANT |
| " | Polling suppressed while mutation in flight (reproduced) | shipped `ServicesRefreshTests` | COMPLIANT |
| " | Secondary read-only surface refreshes once, reports nothing | T5, T6 | COMPLIANT |

The delta's byte-identical claim was **verified mechanically**: the four reproduced scenarios in the MODIFIED
block are character-for-character identical to `openspec/specs/service-management/spec.md`; only the fifth is
new. Shipped baselines also verified: installed-inventory 15 req / 79 scen, service-management 12 req / 40
scen, and `openspec/specs/menu-bar/` does not exist — so the ADDED-only claim holds and no destructive-delta
warning fires.

**Compliance summary**: 33/33 scenarios compliant, 12/12 requirements complete.

### Binding 0-line diffs — all verified

`git diff --numstat main...HEAD` is **empty** for every one:

| File | Diff |
|---|---|
| `cellar.xcodeproj/project.pbxproj` | 0 lines |
| `cellar/Shell/AppSection.swift` | 0 lines |
| `cellar/ContentView.swift` | 0 lines |
| `cellarTests/AppSectionPlacementTests.swift` | 0 lines |
| `cellar/Services/ServicesListView.swift` | 0 lines |
| `cellar/Services/ServiceRow.swift` | 0 lines |
| `cellarUITests/` (whole directory) | 0 lines |

`cellar/MenuBar/` joined the app target through the existing `PBXFileSystemSynchronizedRootGroup` with no
project-file edit, exactly as the proposal predicted. `AppSectionPlacementTests` passes **unedited**, which is
the DD-15 proof.

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| Projection delegates, never re-derives | Implemented | `MenuBarProjection.init` calls `browse.outdatedIDs(metadata:)` and `browse.outdatedCount(metadata:)`; the file contains no `isOutdated` token at all |
| Absence modelled as absence | Implemented | `statusItemTitle: String?`, `remainingOutdatedCount: Int?`, `andMoreLabel: String?` — all `nil`, never `0`/`""` |
| Name order without a comparator | Implemented | filters the **ordered** `browse.inventory.packages` by the ID set, then `prefix(5)`; no second sort |
| Exhaustive status switch, no `default:` | Implemented | `compactControls(for:)` names all eight cases including `.other` and `.unrecognised` |
| Baseline refresh touches no visibility | Implemented | `refreshBaseline()` is `guard mutations?.isMutating != true else { return }; await performRefresh()` — no `isSectionVisible`, `isAppActive`, `applyVisibility()`, `syncPolling()`, no clock |
| Off by default | Implemented | `MenuBarPreference.init` reads `defaults.bool(forKey:)` (missing key ⇒ `false`); `didSet` does not fire during initialization, so a fresh launch **writes nothing** |
| Opt-in insertion, one condition | Implemented | `isInserted: Binding(get: { menuBar.isShown }, set: { menuBar.isShown = $0 })` — no `&&`, no `||` |
| No new egress | Implemented | independent sweep of `cellar/MenuBar/`: 0 hits for `Process(`, `URLSession`, `CaskIconLoader`, `PackageIconTile`, `CaskIconView(`, `.task`, `Task {`, `await `, `async ` |
| No new confirmation | Implemented | 0 hits for `pendingConfirmation`; T8 reads `requiresConfirmation` per offered verb and anchors on `zap` being `true` |
| No AppKit path | Implemented | 0 hits for `NSApplication`, `NSApp`, `NSStatusItem`, `NSImage`, `ImageRenderer` |
| Command disclosed verbatim | Implemented | the only `brew upgrade` occurrence under `cellar/MenuBar/` is `MenuBarPopoverView.swift:126`, inside a **doc comment**; the comment-stripped scan sees zero, which is precisely why the spec mandates stripping |

### Swift 6 / concurrency correctness

| Check | Verdict |
|---|---|
| `MenuBarProjection` isolation | Correct — `nonisolated` by module default, `Sendable, Equatable` by composition. Reachable from the `swift test` inner loop, which is what the `unit`/`unit-app` split depends on |
| `compactControls(for:)` | Correct — a `nonisolated` pure static function on an existing `Sendable` enum |
| `refreshBaseline()` | Correct — `@MainActor` by inheritance from `ServicesRefreshCoordinator`; the single `await` in the whole change |
| `MenuBarPreference` | Correct — `@MainActor @Observable final class`; `@ObservationIgnored` on the injected `UserDefaults` so the suite is not observed. `@MainActor` is justified (it backs a `Binding` a scene reads), not a blanket fix |
| `menuBarProjection` computed var | Correct — `@MainActor`, builds a `Sendable` value synchronously from MainActor-isolated stores, never memoized |
| New data-race warnings | None — both targets compile clean |

No `@unchecked Sendable`, no `nonisolated(unsafe)`, no `@preconcurrency`, and no `Task.detached` anywhere in
the change.

### Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| DD-1 projection delegates count **and** set | Yes | both exposed; `outdatedIDs` whole, not just the top five |
| DD-2 D1 targets `InstalledBrowse`, shared lookup expression | Yes | both app surfaces use `metadata.availability.isAvailable ? metadata.snapshot.lookup : nil`; `ContentView.swift` byte-identical |
| DD-3 limit 5, `Int?`/`String?` remainder, singular | Yes | `and 1 more` / `and M more`, `nil` at ≤ 5 |
| DD-4 uncounted Upgrade all, verbatim disclosure | Yes | `Button("Upgrade all")`, `CopyCommandButton(text: MutationCommand.upgradeAll.displayCommand)` |
| DD-5 `compactControls(for:)`, defaulted parameter | Yes, extended | see deviation 6 |
| DD-6 `refreshBaseline()`, trigger in `cellarApp.swift` | Yes | `.task` lives on the scene, not in any menu-bar file |
| DD-7 `@Observable` preference, injected suite | Yes | explicit `Binding(get:set:)` per the `UpdatesSettingsGroup` precedent |
| DD-8 About-window three injections, component reuse | Partly | see deviation 1 |
| DD-9 `String?` title, one `?? ""` adaptation, short-circuit ternary | Yes, assertion reshaped | see deviation 2 |
| DD-10 `openWindow(id: "main")` alone | Yes, assertion relocated | see deviation 3 |
| DD-11 own Settings file, copy once, two `SettingsView` hunks | Yes | `SettingsView.swift` diff is exactly +1/−1 line plus the doc-comment hunk |
| DD-12 menu-bar directory is a projection reader | Yes | independently re-swept, zero hits |
| DD-13 identifiers and labels | Yes, extended | see deviation 6 |
| DD-14 isolation and `Sendable` statements | Yes | verified above |
| DD-15 no new `AppSection` | Yes | `allCases.count == 22` and the exact rawValue list asserted; three binding files byte-identical |

### Design deviations — verdict on each of the 7

| # | Deviation | Verdict | Reasoning |
|---|---|---|---|
| 1 | `MenuBarPopoverView` takes no `services: ServicesStore` | **Accepted with rationale** | The projection already carries `services: [ServiceRecord]` after correction 4. Passing the store too would create exactly the second source of truth DD-1 and DD-14 forbid, and menu-bar spec:386–388 requires the surface introduce no duplicated state. The scene still passes the app-level `operations` and `theme` identifiers, which T16 asserts. Verified: every service row reads `projection.services`. Following the design's stale interface sketch here would have **violated the spec**. |
| 2 | T12's "`?? \"\"` appears in `cellarApp.swift` exactly once" reshaped | **Accepted with rationale** | Factually unavailable — the shipped file already carried one `?? ""` at `:320` before this change, so the design's literal wording could never have been green. The delivered assertion is **stronger**, not weaker: `statusItemTitle ?? ""` appears exactly once across **all** app sources, `var statusItemTitle` is declared exactly once, and no file under `cellar/MenuBar/` contains `?? ""` at all. That is the design's actual intent (the absence is adapted at one boundary and nowhere inside it). |
| 3 | T15's `openWindow(` location moved from `cellar/MenuBar/` to `cellarApp.swift` | **Accepted with rationale** | The design's T15 row contradicted its own DD-10 and DD-12, which put the call in `cellarApp.swift` and give the popover a plain closure. DD-10's closing clause settles it explicitly. Delivered: `openWindow(` appears exactly once in `cellarApp.swift` as `openMainWindow: { openWindow(id: "main") }`, and zero menu-bar sources reference any window token. The design was internally inconsistent; apply resolved it the way the design's own prose directed. |
| 4 | T7 written whole in unit 6 rather than extended | **Accepted — bookkeeping only** | Task 1.1 assigned unit 1 `T18` only, so no partial T7 existed to extend. Task 6.3's menu-bar clause is present in the delivered row (verified: T7 asserts the scene's browse expression, lookup expression and `MenuBarProjection(`). No coverage lost. |
| 5 | T11 and T13 split across work units | **Accepted — sequencing only** | Their scene-text halves cannot be green before the scene exists. Both rows are whole and green at HEAD. This is the same split the tasks file already applies to T7. |
| 6 | `ServiceControls` gained a second defaulted parameter, `identifierPrefix` | **Accepted with rationale** | DD-13 requires `menu-bar-service-<name>-<control>` identifiers while DD-8 requires reusing the shipped control component. A defaulted `nil` applies no identifier at all, so the Services section's accessibility tree is byte-unchanged — the same trick DD-5 already sanctions for `controls`. **Verified**: `ServicesListView.swift` and `ServiceRow.swift` are both 0-line diffs. The design's own File Inventory predicted `+4` on this file and got `+24`; the extra is this parameter and its doc comment, not behaviour. |
| 7 | `HomeView` reads `outdatedIDs(metadata:)` where task 1.2 says `outdatedCount(metadata:)` | **Accepted with rationale** | The card needs the packages themselves for its formula/cask split, and the number it announces is that set's size. **DD-2 itself says both views read `outdatedIDs(metadata:)`** — the deviation is against the tasks file, not the design, and the design wins. Spec compliance is unaffected: T1 proves `outdatedCount == outdatedIDs.count`, so the count is delegated either way, and installed-inventory spec:65–67 explicitly contemplates a surface presenting both. `SidebarView` reads `outdatedCount(metadata:)`. Neither filters by `isOutdated` — T18's app-wide sweep is green. |

**No deviation breaks a spec requirement.** Three of them (1, 2, 3) are cases where the design's own sketch
was stale or self-contradictory and apply resolved it toward the spec, which is the documented precedence
rule ("Where this document and the specs disagreed, the spec won").

### Task 6.4 — the two open questions

Both were closed by observation during apply and neither is speculative:

1. **`shippingbox` exists in this SDK** — resolved by `NSImage(systemSymbolName:)`, with a deliberately
   invalid name rejected so the check was not vacuously true. The `cube.box` fallback was correctly **not**
   added.
2. **`.task` re-fires per presentation under `.menuBarExtraStyle(.window)`** — measured 0 fires at insertion
   and 3 fires across 3 open/close cycles. The design's contract holds as written, and no speculative
   fallback was added, as R10 required.

R11 (system activation on status-item click) is recorded as observation-only: correction 1 removed this
change's only deliberate activation call, and `refreshEverything`'s path ends in `syncPolling()`, which
`guard isVisible else { return }`s — so no poll can start from it.

---

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | Pass | Full "TDD cycle evidence" table present in `apply-progress.md`, 7 rows |
| All tasks have tests | Pass | 26/26 tasks map to a row; every behavioural task has a covering test |
| RED confirmed (tests exist) | Pass | 3/3 test files exist; each RED note names a concrete compiler error (`cannot find 'MenuBarProjection' in scope`, `no member 'compactControls'`, `no member 'refreshBaseline'`) — errors only reachable before the implementation existed |
| GREEN confirmed (tests pass) | Pass | 19/19 delivered rows pass on re-execution in this phase |
| Triangulation adequate | Pass | 12 fixtures for the projection (12/6/5/4/3/0 outdated, empty, unavailable, snoozed, self-updating cask, no-metadata); all 8 `ServiceStatus` cases; both preference directions |
| Safety Net for modified files | Pass | Every modified-file row records a run of the shipped suite first (11/11, 9/9, 4/4, 1/1, 3/3, 5/5); `N/A (new)` appears only on genuinely new files |

**TDD Compliance**: 6/6 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|-------|-------|-------|-------|
| Unit (`unit`, CellarCore) | 7 rows | 3 | Swift Testing |
| Integration / composition (`unit-app`) | 12 rows | 1 | Swift Testing + `#filePath` source scan |
| E2E (`ui`) | 0 | 0 | XCUITest — 0 deliberately, menu-bar spec:33 |
| **Total** | **19** | **4** | |

The `ui` zero is spec-sanctioned and correct: a status item lives in the system status bar, which
`XCUIApplication` does not reach reliably. Every claim in the delta is provable without one, and apply
additionally drove a real status-item session through `System Events` as a runtime harness.

### Changed File Coverage

Coverage analysis skipped — no coverage tool is configured for this project. Not a failure.

### Assertion Quality

Audited all 4 test files this change creates or modifies (132 `#expect`, 29 `#require`).

**Assertion quality**: 0 CRITICAL, 0 WARNING — all assertions verify real behaviour.

Specifically checked and clean:

- **Tautologies**: none. Zero `#expect(true)` / `#expect(1 == 1)` forms.
- **Ghost loops**: none. Every sweep loop is preceded by a cardinality anchor that fails if the collection is
  empty — `#expect(sources.count > 40)`, `#expect(sorted.count >= 3)`, `#expect(owned.count >= 3)`,
  `#expect(signatures.count == 2)`, `#expect(Set(everyStatus).count == 8)`. A scan that read nothing fails
  rather than sweeping clean.
- **Detector anchors**: `OutdatedDerivation` is anchored positively against the exact literal the sidebar
  shipped with, **and** negatively against a delegated read, so it cannot silently stop recognising the shape
  it exists to find.
- **Non-vacuous equality**: T19 asserts `first == second` **and** `first != snoozed`, so `Equatable` is not
  satisfied by a degenerate implementation.
- **Absence asserted as absence**: T3 asserts `statusItemTitle == nil` **and** `!= "0"` **and** `!= ""`.
- **Positive controls on negative sweeps**: T8 anchors on `MutationCommand.zap(cask).requiresConfirmation`
  being `true`; T13 anchors on `MutationCommand.upgradeAll.displayCommand == "brew upgrade"`; T17 anchors on
  `Check for updates automatically` and `Accent colour` being present; T10 proves the three environment
  modifiers against the About-window precedent rather than asserting them.
- **Comment stripping**: every source scan reuses `AppSecuritySources.stripComments(from:)`, so a prohibition
  *described* is never mistaken for one *violated*. Independently confirmed: the sole raw `brew upgrade` hit
  under `cellar/MenuBar/` is a doc comment.
- **Not implementation-coupled**: assertions target submitted commands, argv, exposed values and structural
  source facts the specs themselves pin — not CSS-equivalents or mock call counts.
- **Mock ratio**: not applicable; no mocking framework, and the projection has nothing effectful to mock.

The single `isEmpty` assertion in the core file (`#expect(zero.topOutdated.isEmpty)`) has companion non-empty
assertions over the same fixture shape (`topOutdated.count == 5`, `== count` for 5 and 4), so it is not an
orphan empty check.

### Quality Metrics

**Linter**: Not available — no SwiftLint configuration in this project.
**Type Checker**: Pass — both targets compile clean under Swift 6 with no new diagnostics.

---

### Issues Found

**CRITICAL**: None.

The single CRITICAL of the previous run (`C1` — the declared `unit` command exiting 1 from 2 pre-existing
`TapShippingProofTests` failures) is **resolved** by commit `270f41e`. `swift test --package-path
Packages/CellarCore` now exits **0** with 1891/1891 passing. No CRITICAL finding was ever attributable to
m12's implementation.

**WARNING**:

- **W1 — Task-count mismatch in `apply-progress.md`.** It states "29/29 tasks complete"; `tasks.md` contains
  **26** checkboxes (3+5+5+4+4+5), all ticked, none unchecked. Bookkeeping only — no task is incomplete and
  no coverage is missing. Worth correcting before archive so the artifact does not misstate its own scope.
- **W2 — `cellarUITests` Cleanup rows fail, and m12 is the trigger that exposes them.** 7 rows failed at
  `270f41e`, 8 at `22516eb`; the differing row passed with no relevant change between runs, so the set is
  flaky rather than deterministic. The bug is genuinely pre-existing — `sidebar-cleanup` sits below the fold
  at the declared `.defaultSize`, so `openCleanup(in:)`'s click never lands — and apply proved it by
  reproducing the failure at `e0e6ffd` with the saved window-frame keys removed and no m12 scene change
  present. But it passed on this machine before only because a saved 1390×1115 frame masked it, and **m12
  resets that autosave key**: both `id: "main"` (required by menu-bar spec:352–354) and the added
  `.environment(menuBar)` change the `WindowGroup`'s identity. So while m12 did not *cause* the defect, it
  removes the accident that was hiding it. Out of scope by maintainer decision. Remedies in preference
  order: scroll the sidebar to the row in `openCleanup(in:)`; raise `.defaultSize` height; or set an explicit
  frame in the fixture launch.

**SUGGESTION**:

- **S1 — The popover introduces copy the spec does not pin.** `Everything is up to date`,
  `Nothing is waiting for an update.`, `outdated`, and the `Updates`/`Services` section headers are all new
  strings. None contradicts a requirement — the zero-outdated prohibition is scoped to the **status item
  title**, which is correctly absent — but the menu-bar delta's copy table claims to enumerate what this
  capability owns, and these are outside it. Consider pinning them in the spec at archive so a later reword
  is a spec change rather than a silent one.
- **S2 — `UserDefaults(suiteName:) ?? .standard` in `cellarApp.swift`.** Under a UI-test launch the fallback
  would write the developer's real defaults. The name is UUID-derived so the initializer cannot realistically
  return `nil`, and T11 correctly asserts `.standard` is never used unconditionally — but a `fatalError` or a
  volatile in-memory suite would close the theoretical hole entirely.
- **S3 — App-unit row count moved.** `apply-progress.md` records 274 rows; both re-runs in this phase measured
  **285** passing rows. Worth reconciling the counting method before archive.
- **S4 — Declared vs delivered verification-class counts.** The specs declare 14 `unit` + 15 `unit-app`;
  19 test rows carry all 33 scenarios (several classes are asserted within one row, e.g. T4 carries three
  scenarios). Coverage is complete, but the archived spec's class counts will not match a naive row count.
- **S5 — The tap exclusion detector cannot distinguish offering a capability from mentioning it.**
  `TapShippingProofTests` excludes nine capability names by substring over the concatenated tap sources, so
  ordinary prose that *cross-references* another section reads as the tap surface *growing* that capability.
  That is what PR #89 tripped and what `270f41e` worked around by rewording. The proof's intent — "the tap
  action surface stays bounded to its four capabilities" — is about controls and submissions, which the suite
  already asserts separately via `staticButtonLabels(in:)` and the `Button {` ban. Consider scoping the
  substring sweep to control labels rather than whole-file text, or the next legitimate cross-reference will
  trip it again.

### Verdict

**PASS WITH WARNINGS**

All **12 requirements** and all **33 scenarios** across the three delta specs are compliant with passing
runtime evidence. Both declared verification commands are green at HEAD `270f41e`: the CellarCore package
suite passes 1891/1891 (exit 0) and the app unit suite passes 285/285 (exit 0). Every one of the 19
m12-delivered test rows is green, every binding 0-line diff holds, Swift 6 isolation is correct, no new
egress or confirmation exists, and the status item is off by default and structurally unobservable until
enabled. All 7 design deviations are accepted with rationale and none breaks a spec.

Two warnings remain, neither blocking and neither an m12 defect: a bookkeeping mismatch in `apply-progress.md`
(W1) and the pre-existing, flaky `cellarUITests` Cleanup rows that this change unmasks rather than causes
(W2), which the maintainer has scoped out.

**Archive-ready**, subject to the maintainer accepting W2 as a tracked follow-up.
