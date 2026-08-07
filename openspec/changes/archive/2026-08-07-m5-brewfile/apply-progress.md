# Apply Progress: m5-brewfile

**Batches**: 2 of 2 · **Mode**: Strict TDD · **Delivery**: single-pr with accepted `size:exception`
**Status**: complete — **61 / 61 tasks complete**. Task 10.4 was closed on 2026-08-07: the
`BrewfileApplyAdvisory` copy, the six skip-reason sentences, the on-screen skip-group shape, and the
four import-summary lines were presented to the maintainer verbatim and **accepted as-is** with no
rewording (decision record obs #7520).

> The tasks artifact's header says "63 tasks"; the file actually carries **61** numbered checkboxes
> (7+4+11+4+6+7+4+4+4+6+4). Counted here from the artifact, not from its header.

## Batch 1 — Phases 0–8 (CellarCore), 51 tasks

Everything in batch 1 is **CellarCore only**. No app-target file changed, and `Package.swift` /
`project.pbxproj` were untouched.

### Phase 0 — the spine change (DD1, PM1)
- [x] 0.1 GUARD `BrewMutatingTests.swift` — equality/hashing characterised before the stored
      property, plus the deliberate extension after 0.5
- [x] 0.2 RED erased mixed batch → `.tapTrust`
- [x] 0.3 RED erased install-only → `.packageRemoval`; every shipped call site unchanged; protocol default
- [x] 0.4 RED structural — no downcast, type test or verb-string on a disclosure path
- [x] 0.5 GREEN `BrewMutating.disclosure` requirement + `.packageRemoval` default; `AnyBrewMutation`
      carries it (eighth projection)
- [x] 0.6 GREEN `OperationCenterBulk.request(_:)` reads `first.disclosure`; the cast is gone
- [x] 0.7 Checkpoint — FAST and APP green, **zero** shipped test edits (amendment A5)

### Phase 1 — fixtures (BF3, BF5, BF8, TM1)
- [x] 1.1 Real capture: `brew bundle dump --file <tmp> --force --formula --cask --tap`,
      Homebrew `6.0.15-125-g7372067`, exit 0 · `dump-file.brewfile` (5268 B), `dump-stderr.txt`
      (399 B, non-empty at exit 0), `dump-stdout.txt` (0 B, empty on purpose)
- [x] 1.2 `README.md` + `probe-manifest.txt` to the `Fixtures/Cleanup` standard, incl. U8's
      marker-file evidence re-verified first-hand
- [x] 1.3 Adversarial fixtures: `hostile-ruby`, `mixed-kinds`, `trusted-taps` (U9's three lines
      verbatim), `undecodable` (invalid UTF-8, one line), `empty` (0 B)
- [x] 1.4 RED `BrewfileFixtureManifestTests.swift` — SHA-256 per stream, both directions

### Phase 2 — entry model and parser (BF2–BF5, PM9, TM1, TM2, DD2)
- [x] 2.1 RED `BrewfileEntryTests.swift` · [x] 2.2 GREEN `BrewfileEntry.swift`
- [x] 2.3–2.5 RED `BrewfileParserTests.swift` — grammar, tap-prefixed names, `trusted:`
- [x] 2.6–2.10 RED `BrewfileSkipTests.swift` — skip taxonomy, no-blocking, hostile input,
      byte tolerance, purity
- [x] 2.11 GREEN `BrewfileParser.swift` (`@concurrent` on its own line, line-oriented, refuse-by-skip)

### Phase 3 — the diff (BF6, D1)
- [x] 3.1–3.3 RED `BrewfileDiffTests.swift` · [x] 3.4 GREEN `BrewfileDiff.swift`

### Phase 4 — plan and erased submission (BF7, PM1, PM9, DD1)
- [x] 4.1–4.4 RED `BrewfilePlanTests.swift` · [x] 4.5 GREEN `BrewfilePlan.swift`
- [x] 4.6 `MutationCommand.swift` provenance block restated — **zero changed executable lines**

### Phase 5 — export dump (BF1, BF8, TM3, DD3)
- [x] 5.1–5.2 RED `BundleDumpCommandTests.swift` · [x] 5.3–5.6 RED `BundleDumpSourceTests.swift`
- [x] 5.7 GREEN `BundleDumpCommand.swift`, `BundleDumpSource.swift`

### Phase 6 — publication (BF9, D2, DD4)
- [x] 6.1–6.3 RED `BrewfilePublicationTests.swift` · [x] 6.4 GREEN `BrewfilePublication.swift`
      (publication + both picker seams)

### Phase 7 — the store (DD5, DD6)
- [x] 7.1–7.3 RED `BrewfileStoreTests.swift` · [x] 7.4 GREEN `BrewfileStore.swift`

### Phase 8 — structural guards and regression
- [x] 8.1–8.2 RED `BrewfileArgvStructureTests.swift`
- [x] 8.3 `CatalogFootprintTests` passes **unchanged and un-rebased**, zero-line diff
- [x] 8.4 U10 divergence check: **no divergence** (amendment A7)

## Batch 2 — Phases 9–10 (app layer), 9 tasks

### Phase 9 — app layer (D3, DD4), zero-line `project.pbxproj` diff
- [x] 9.1 GREEN `cellar/Taps/BrewfilePanels.swift` — `NSOpenPanel`/`NSSavePanel` conformers for the
      two shipped seams, each split into a `configure(_:)` a test can apply to a real panel and read
      back without ever running one modally. The `ENABLE_USER_SELECTED_FILES = readonly` trap is
      recorded in the file's own doc comment, and a test fails if the note is ever deleted.
- [x] 9.2 RED `cellarTests/BrewfileCompositionTests.swift` — **per-instance** tagged ledger
      (`BrewfileCompositionLedger` keyed by a per-launcher `UUID`, guarded by a `Mutex`), explicitly
      **not** `CompositionRequestSpy`'s shared static. Asserts through a real `OperationCenter` that a
      tap-carrying import raises **exactly one** confirmation carrying `.tapTrust`.
- [x] 9.3 GREEN `cellar/Taps/BrewfileImportSheet.swift` — the diff list plus five presentation values
      (`BrewfileImportRow`, `BrewfileSkipGroup`, `BrewfileSkipCopy`, `BrewfileImportSummaryCopy`,
      `BrewfileImportAction`), following the `PackageInspectionRow` idiom (amendment A12).
- [x] 9.4 GREEN `cellar/Taps/BrewfileExportSheet.swift` + `BrewfileExportPresentation` — the panel is
      gated on `canPublish`, which is true only in `.preview`.
- [x] 9.5 GREEN `cellar/Taps/TapsListView.swift` — two `.toolbar` affordances inside the existing
      Taps section. No new `AppSection` case, no navigation destination, **zero** pbxproj diff.
- [x] 9.6 RED then GREEN `cellarUITests/BrewfileImportUITests.swift` — two E2E cases, both green.

### Phase 10 — close-out
- [x] 10.1 FAST + APP + FULL + BUILD run; all diff-stat confirmations hold (below)
- [x] 10.2 Amendments A9–A12 recorded in `design.md` → *Apply-Time Amendments*
- [x] 10.3 Rollback note written into `design.md` → *Rollback*
- [ ] 10.4 **OWED TO THE MAINTAINER.** The copy is implemented as named constants and every string is
      asserted, but "the wording is honest enough" is not something a test can decide. The exact
      strings are surfaced in the batch-2 return summary for review before the PR opens.

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 0.1 | `BrewMutatingTests.swift` | Unit | 1396/1396 | ✅ Guard written first (green before) | ✅ Passed | ✅ 7 projections + hashing | ➖ None needed |
| 0.2–0.4 | `ConfirmationDisclosureTests.swift` | Unit | 1396/1396 | ✅ Compile-failed on absent `disclosure` | ✅ Passed after 0.5/0.6 | ✅ tapTrust / packageRemoval / forceUntap / protocol default | ➖ None needed |
| 0.5–0.6 | (above) | Unit | 1396/1396 | ✅ (0.2–0.4) | ✅ 1405 tests | ✅ Guard extended: disclosure-only difference is unequal + hashes apart | ✅ `ConfirmationDisclosure` → `Hashable` |
| 1.4 | `BrewfileFixtureManifestTests.swift` | Unit | N/A (new) | ✅ RED demonstrated by appending 2 bytes to a fixture → 3 issues; restored | ✅ Passed | ✅ Digest + byte count + both directions + bit-flip control | ➖ None needed |
| 2.1 | `BrewfileEntryTests.swift` | Unit | N/A (new) | ✅ `cannot find 'BrewfileEntry'` | ✅ Passed | ✅ 4 refused names, 6 accepted, 6 categories | ➖ None needed |
| 2.3–2.5 | `BrewfileParserTests.swift` | Unit | N/A (new) | ✅ `cannot find 'BrewfileParser'` | ✅ Passed | ✅ 13 grammar cases incl. real capture | ➖ None needed |
| 2.6–2.10 | `BrewfileSkipTests.swift` | Unit | N/A (new) | ✅ `cannot find 'BrewfileParser'` | ✅ Passed | ✅ 10 kinds, 3 options, 4 refused names, 4 metacharacters | ➖ None needed |
| 3.1–3.3 | `BrewfileDiffTests.swift` | Unit | N/A (new) | ✅ `cannot find 'BrewfileDiff'` | ✅ Passed | ✅ 3 states, 4 summaries, selection gate ×3 paths | ➖ None needed |
| 4.1–4.4 | `BrewfilePlanTests.swift` | Unit | 1448/1448 | ✅ `cannot find 'BrewfilePlan'` | ✅ Passed | ✅ 12 cases incl. tap-last ordering + declining | ➖ None needed |
| 4.6 | (existing suites) | Unit | 1469/1469 | ➖ Comment-only, no behaviour | ✅ Zero changed executable lines | ➖ Structural | ✅ Premise restated |
| 5.1–5.2 | `BundleDumpCommandTests.swift` | Unit | N/A (new) | ✅ `cannot find 'BundleDumpCommand'` | ✅ Passed | ✅ 11 forbidden subcommands enumerated | ➖ None needed |
| 5.3–5.6 | `BundleDumpSourceTests.swift` | Unit | N/A (new) | ✅ `cannot find 'BundleDumpSource'` | ✅ Passed | ✅ success / non-zero / cancellation / absent brew | ➖ None needed |
| 6.1–6.3 | `BrewfilePublicationTests.swift` | Unit | N/A (new) | ✅ `cannot find type 'BrewfileDestinationChoosing'` | ✅ Passed | ✅ byte-identity, failed write, cancellation, 6 persistence forms, 5 well-known paths | ➖ None needed |
| 7.1–7.3 | `BrewfileStoreTests.swift` | Unit | 1487/1487 | ✅ `cannot find type 'BrewfileStore'` | ✅ Passed (2 real failures fixed: preview-after-failure semantics, computed-property scan) | ✅ 3 empties, selection gate, export/publish/failure/cancel, advisory ×3 | ✅ `retryableDocument` extracted |
| 8.1–8.2 | `BrewfileArgvStructureTests.swift` | Unit | 1511/1511 | ✅ Surface-count and identifier scans failed first | ✅ Passed | ✅ 11 subcommands + 8-file surface scan | ✅ whole-identifier scan so `rubyConditional` is not a false positive |
| 8.3 | `CatalogFootprintTests.swift` | Unit | ✅ un-rebased | ➖ Regression, unchanged | ✅ Passed, zero-line diff | ➖ N/A | ➖ Not touched |
| 8.4 | `BrewfileArgvStructureTests.swift` | Unit | N/A | ✅ Written before the check ran | ✅ Passed, zero `unrecognisedLine` | ✅ 79 lines accounted for individually | ➖ None needed |
| 9.1 | `BrewfileCompositionTests.swift` | Unit (app) | **74/74** APP baseline | ✅ `cannot find 'BrewfileSourcePanel' in scope` ×10 | ✅ 5/6 passed; the 6th was RED for 9.3/9.4 by design | ✅ open-panel config, save-panel config, two prompts, 11 forbidden memories, 4 well-known paths, sandbox trap | ➖ None needed |
| 9.2 | `BrewfileCompositionTests.swift` | Integration (app) | 74/74 | ✅ `cannot find 'BrewfileImportAction' in scope` ×5 | ✅ Passed after 9.3 | ✅ tapTrust ×1, declining → 0 spawns, confirming → 3 spawns tap-first, install-only → 2 spawns no confirmation, empty selection → 0 | ➖ None needed |
| 9.3 | `BrewfileCompositionTests.swift` | Unit (app) | 74/74 | ✅ `cannot find 'BrewfileImportRow'`/`BrewfileSkipCopy`/`BrewfileSkipGroup`/`BrewfileImportSummaryCopy` | ✅ Passed | ✅ present/missing/skipped rows, line-numbered reason, 4 grouped categories, 6-category copy sweep, only-skips file, trust claim | ➖ None needed |
| 9.4 | `BrewfileCompositionTests.swift` | Unit (app) | 88/88 | ✅ `cannot find 'BrewfileExportPresentation' in scope` ×8 | ✅ Passed | ✅ 3 gate states, failed dump asks no panel, verbatim bytes, real atomic write, cancellation keeps preview, 5 distinct headlines | ➖ None needed |
| 9.5 | `BrewfileCompositionTests.swift` + `TapShippingProofTests.swift` | Unit (app + package) | 96/96 APP, 1517 FAST | ✅ `bothAffordancesAreWiredIntoTheTapsList` failed on the absent toolbar | ✅ Passed | ✅ 9-case `AppSection` list, 6 wiring identifiers, no destination, sheets presented from exactly one view | ✅ Buttons respelled with static labels so the shipped enumeration guard still reads them |
| 9.6 | `BrewfileImportUITests.swift` | **E2E** | N/A (new) | ✅ Ran and failed twice for two *different* real reasons (no stub chooser → real panel; then the container-identifier override) | ✅ Both passed | ✅ Skip-heavy import stays enabled **and** tapTrust text present while removal text absent | ✅ A9: root identifiers removed from both sheets |

### Test summary
- **Package suite (FAST)**: 1396 → **1517** tests (+121), all passing; 1 **pre-existing** known issue.
- **App suite (APP)**: 74 → **100** tests (+26), `** TEST SUCCEEDED **`.
- **UI suite**: +2 new E2E tests, both passing.
- Layers: Unit 121 (package) + 24 (app), Integration 5 (app, real `OperationCenter` + real filesystem),
  E2E 2. Live `brew` probes: 3 (batch 1).
- Approval tests: 1 (task 0.1's guard).
- Pure functions/values created in batch 2: `BrewfileImportRow`, `BrewfileSkipGroup`,
  `BrewfileSkipCopy`, `BrewfileImportSummaryCopy`, `BrewfileExportPresentation`,
  `BrewfileSourcePanel.configure`, `BrewfileDestinationPanel.configure`.

## Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused test command (batch 2) | `xcodebuild test … -only-testing:cellarTests` → **100 tests, TEST SUCCEEDED** (74 at batch-2 start) |
| Focused test command (package) | `swift test --package-path Packages/CellarCore` → **1517 tests in 188 suites passed**, 1 pre-existing known issue |
| E2E harness | `xcodebuild test … -only-testing:cellarUITests/BrewfileImportUITests` → **2/2 passed**. A launched app imports a mixed-kinds Brewfile through the shipped read path, shows `3 lines skipped` with its named reason, keeps the import button enabled, and — on confirming — presents `Adding gentleman-programming/tap trusts third-party formulae and casks that can distribute code.` while the string `This removes installed software.` is **absent**. That is DD1 proven at the surface a user reads. |
| FULL | `xcodebuild test …` → 4 `ReleaseNotesUITests` cases fail. **Verified pre-existing**: an isolated `git worktree` at `HEAD` (`7d48779`) reproduces the identical 4 tests / 7 failures, so this change neither caused nor worsened them. Everything else in FULL is green. |
| BUILD | `xcodebuild build …` → `** BUILD SUCCEEDED **` |
| Runtime harness 1 (batch 1) | Real `brew bundle dump` replayed offline through `BrewfileParser.decode`: 148 lines → 78 typed entries + 1 named skip, **zero** `unrecognisedLine` |
| Runtime harness 2 (batch 1) | Live `/opt/homebrew/bin/brew bundle dump --file <tmp>/cellar-brewfile/<UUID>/Brewfile --force --formula --cask --tap` → exit 0, 5268-byte document, temp removed, `$HOME` unchanged, no `~/Brewfile` |
| Runtime harness 3 (batch 1, security) | Live `brew bundle check --file <tmp>/Hostile.brewfile` → exit 1 **and `marker.txt` written** — U8 re-verified, artifacts removed |
| Rollback boundary | See `design.md` → *Rollback*. One `git revert`. The app layer is separately removable (zero pbxproj objects). **The Phase 0 spine revert must not stop halfway.** |

## Diff and budget

| Check | Result |
|---|---|
| `Packages/CellarCore/Package.swift` | **untouched** (zero-line diff) |
| `cellar.xcodeproj/project.pbxproj` | **untouched** (zero-line diff) |
| `Tests/CatalogTests/CatalogFootprintTests.swift` | **untouched**, passing un-rebased |
| Assertion lines removed across `Tests/`, `cellarTests/`, `cellarUITests/` | **zero** (`git diff -U0` filtered on `#expect`/`XCTAssert`/`Issue.record` deletions) |
| Batch 1 authored | ≈ **5,629** lines |
| Batch 2 authored | **1,806** lines (1,632 new across 5 files + 174 insertions across 6 tracked files) |
| **Authored total** | **≈ 7,435** lines, excluding this change's lifecycle markdown |
| Budget | 5,000 (`review_budget_lines`) — over, under the **user-accepted `size:exception`** |

## Deviations from design

Twelve, all recorded in `design.md` → *Apply-Time Amendments*. Batch 1 wrote **A1–A8**; batch 2 wrote:

- **A9** a container-level `accessibilityIdentifier` **replaces** its descendants' outside a `List`;
  both sheets moved theirs off the root.
- **A10** `TapShippingProofTests`' bounded-tap-surface guard **extended, not weakened** — the only
  shipped test this change edited in either batch (+32 lines, zero assertions removed).
- **A11** the UI-test import fixture is inline in `AppTestFixtures`, because reaching
  `Fixtures/Bundle/mixed-kinds.brewfile` from the app target would need a pbxproj resource.
- **A12** the import sheet's five presentation values live in `BrewfileImportSheet.swift`, so the
  design's app-file inventory holds exactly.

## Issues found

1. **`ReleaseNotesUITests` is broken at `main`.** Four cases, seven failures, all reproduced in a
   clean worktree at `7d48779`. Out of scope here, and deliberately not fixed inside this change — but
   it means `FULL` has not been green on this repository since before this slice started, and someone
   should own it.
2. **The 400-line-per-file convention is exceeded by `cellarTests/BrewfileCompositionTests.swift`**
   (808 lines). It is a test file holding three suites; splitting it is cheap and was not done to keep
   the batch-2 boundary clean.

## Risks

1. **The diff is ≈ 7,435 authored lines** against a 5,000 budget, under an accepted `size:exception`.
   If the maintainer would rather have two PRs, Phase 8 → Phase 9 is still the clean cut: batch 1 is
   independently revertible and independently green, and batch 2 touches no CellarCore source at all
   (only one CellarCore *test* file, A10).
2. **`ENABLE_USER_SELECTED_FILES = readonly`** is inert behind `ENABLE_APP_SANDBOX = NO`. Recorded in
   `BrewfilePanels.swift` and guarded by a test that fails if the note is deleted. If the sandbox is
   ever enabled it permits the import read and blocks the export write — half a feature.
3. **Task 10.4 is still owed.** Every user-facing string is a named constant and every one is
   asserted, but no test can decide whether the wording is honest. Surfaced in the return summary.
