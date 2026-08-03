```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:8ed3a79ce94a965b02011a5f2f2cdc5fb2c4b2ee5960d4e2536fcf819d76293a
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 5/5
scenarios: 24/24
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:c934ddd2d39432ac261e81a6b05c3b677216958286366a73556a6ee8d097e6a4
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:7f3cae203ae46d77f946d54cfc85ad95933d835054a6d37737c2e8daaef1478a
```

## Verification Report

**Change**: m3-hardening-prelude (M3-0) · **Branch**: `feature/m3-hardening-prelude` @ `d41dc95` (13 commits, unpushed)
**Mode**: Strict TDD · **Artifacts**: proposal + design + tasks + 5 delta specs (full verification)

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 34 |
| Tasks complete | 34 |
| Tasks incomplete | 0 |

### Build & Tests Execution

**Tests**: ✅ `Test run with 571 tests in 77 suites passed after 5.319 seconds with 1 known issue.`
The known issue is pre-existing (`OperationCenterCancelTests.swift:183` — "Finishing a call that never launched fails this test instead of crashing the suite"), unrelated to this slice. Baseline on `main` was 555 tests / 73 suites, so +16 tests / +4 suites.

**Build**: ✅ `** BUILD SUCCEEDED **`. Zero compiler diagnostics; the only emitted warning is the pre-existing `appintentsmetadataprocessor: Metadata extraction skipped` note, which is not a compiler diagnostic. Zero concurrency warnings.

**SwiftLint**: ✅ 60 findings, exactly the task 0.1 baseline of 60 — zero new.

**Coverage**: ➖ Not available (no coverage tool configured for this package).

### Spec Compliance Matrix

The six **new** RED anchors, each independently re-proven RED against `main` production code (see TDD Compliance):

| Requirement | New Scenario | Test | Result |
|---|---|---|---|
| catalog-sync: A snapshot is adopted exactly once, in order | An older snapshot arriving after a newer one has installed is discarded | `CatalogAdoptionTests > anOlderSnapshotArrivingAfterANewerOneIsDiscarded` + `theAdoptedRevisionDoesNotRegressAfterDiscardingAnOlderSnapshot` | ✅ COMPLIANT |
| brew-execution: Terminal result and exit handling | An unknown operation identity yields a typed unknown result | `ExitTests > anUnknownOperationYieldsATypedUnknownResultRatherThanSuccess` | ✅ COMPLIANT |
| operation-activity: Every terminal outcome records exactly one history entry | An operation that never spawns still records once | `OperationCenterTests > aSubmitWithNoRunnerRecordsExactlyOneHistoryEntry` | ✅ COMPLIANT |
| installation-history: Clear history is a single confirmed all-or-nothing action | A failed clear leaves every entry present and reports why | `HistoryStoreTests > aFailedClearKeepsEveryEntryAndReportsTheReason` | ✅ COMPLIANT |
| installation-history: (same) | A failed clear's reason survives the reload that follows it | same test — asserts `availability`/`lastError` **after** the reload | ✅ COMPLIANT |
| installed-inventory: Multi-select is explicit, ordered, and offered only for bulk-eligible verbs | A bulk add enters the selection in displayed order | `InstalledSectionsTests > bulkAddEntersTheSelectionInDisplayedOrderNotInventoryOrder` | ✅ COMPLIANT (see W4) |

The 18 **carried-forward** scenarios were re-run as part of the full green suite and each retains a named covering test. Spot-mapped examples: `CatalogAdoptionTests > aLateAdoptionOfAnOlderSnapshotIsDiscarded` / `everyQueryIssuedDuringAnAdoptionIsAnsweredFromTheLastGoodIndex` / `aManualRefreshWithTheEventStreamRunningBuildsOneIndex`; `ExitTests > aNonZeroExitIsAResultCarryingItsCode` and `anyOtherSpawnFaultIsReportedAsLaunchFailed`; `HistoryStoreTests > aConfirmedClearEmptiesTheHistoryAndLeavesEveryFavoriteNoteAndSnooze` and `HistoryRecorderTests > theOnlyPerEntryControlIsCopy`; `BulkSelectionTests > deselectingOnePackageLeavesTheOthers` / `exactlyUpgradeAndUninstallAreBulkEligible` / `anEmptySelectionReportsEveryBulkControlUnavailable`. No carried scenario regressed.

**Compliance summary**: 24/24 scenarios compliant across 5/5 MODIFIED requirements.

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| catalog-sync ordinal ordering | ✅ Implemented | `CatalogStore.swift` guard is now `snapshot.revision.ordinal > (adoptedRevision?.ordinal ?? 0)`; the older snapshot leaves through the same door, so the `adoptedRevision =` assignment is unreachable for it and the record cannot regress. |
| brew-execution typed unknown | ✅ Implemented | `BrewExit.Reason.unknownOperation` declared inside the enum; `BrewExit.unknownOperation` = `status: -1`. Both fabricated `BrewExit(status: 0, reason: .exited)` returns in `BrewRunner.exit(of:)` replaced. Non-throwing, so no caller gains a throwing path. |
| operation-activity one entry | ✅ Implemented | `OperationCenter.submit` hoists `gate?.begin()` above `guard let runner` and routes the no-runner branch through `finish(item, with: .launchFailed)` — the single settle site. |
| installation-history failed clear | ✅ Implemented | `clearAll()` rolls back, calls `reload()` **first**, then applies `availability`/`lastError`. Success path clears `lastError`. Inline surface only; no alert, no retry. |
| installed-inventory displayed order | ✅ Implemented | `InstalledSections` partitions in an if/else-if chain; `InstalledListView` renders all three sections from it and `reconcileOrder` maps over `sections.displayed` instead of `entries`. |

### Coherence (Design D1–D9)

| Decision | Followed? | Notes |
|---|---|---|
| D1 single ordinal guard | ✅ Yes | One guard, no separate is-older branch. See S2. |
| D2 sequences retained | ✅ Yes | `adoptionSequence`/`installedSequence` untouched. |
| D3 `begin()` hoist + funnel routing | ✅ Yes | One begin per submit, one end per finish; inline settle deleted. |
| D4 reload-then-fail ordering | ✅ Yes | `reload()` precedes the availability/error assignment on the failure path. |
| D5 injected clear seam | ✅ Yes | `Clearing` typealias + `init(container:clearing:)`; no filesystem-permission fake. |
| D6 one container, both stores | ⚠️ Yes, widened | `LocalStores` opens one container and injects it into both; open failure folds into one shared reason. Deviation W3. |
| D7 NoteDraft commit-before-reset | ✅ Yes | `onChange(of: entry.id)` commits against `oldValue` before resetting; doc comment corrected (a multiline `TextEditor` has no `onSubmit`). |
| D8 `.unknownOperation` in Reason → existing `launchFailed` | ✅ Yes | Case inside the `Reason` declaration, factory in an extension, one `classify` branch to the **existing** `.launchFailed`. No new `MutationOutcome` case, no message churn. |
| D9 `InstalledSections.displayed` | ✅ Yes | One projection read twice; section titles unchanged. |

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | Full cycle table present in apply-progress (#7135) |
| All tasks have tests | ✅ | 12 RED tasks → 16 new test functions across 5 files (3 new) |
| RED confirmed | ✅ | Independently re-proven — see below |
| GREEN confirmed | ✅ | 571/571 pass on my own execution |
| Triangulation adequate | ✅ | Every new behaviour has ≥2 cases; `NoteDraftTests` carries 13 |
| Safety Net for modified files | ✅ | Baselines recorded per phase (555 → 571, monotonic) |

**RED independently re-proven.** I created a scratch worktree at `main` (`3562cd1`), copied across **only** the two behavioural test files, and ran them against unmodified `main` production code:

```text
Test "A submit with no runner records exactly one history entry" recorded an issue at
  OperationCenterTests.swift:83: Expectation failed: (harness.recorder.drafts.count → 0) == 1
Test "An older snapshot arriving after a newer one has installed is discarded" recorded an issue at
  CatalogAdoptionTests.swift:129: Expectation failed: (store.packageCount → 2) == 3
  CatalogAdoptionTests.swift:130: Expectation failed: (store.indexBuildCount → 2) == 1
Test "The adopted revision does not regress after discarding an older snapshot" recorded an issue at
  CatalogAdoptionTests.swift:152: Expectation failed: (store.indexBuildCount → 3) == 1
Test run with 15 tests in 2 suites failed after 0.372 seconds with 7 issues.
```

These signatures match apply-progress's recorded RED byte for byte. The remaining four new tests are compile-error RED: `unknownOperation`, `clearing:`, `InstalledSections` and `NoteDraft` each return **zero** matches across `Sources/` on `main`, so those tests could not have compiled, let alone passed. Worktree removed after the check.

**TDD Compliance**: 6/6 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit | 12 | 4 | Swift Testing |
| Integration (in-package harness) | 4 | 3 | Swift Testing + `CenterHarness` / `PersistenceContainer` |
| E2E | 0 | 0 | not installed (app-target wiring covered by `xcodebuild` + manual 9.1) |
| **Total new** | **16** | **5** | |

### Assertion Quality

✅ All assertions verify real behaviour. No tautologies, no ghost loops, no smoke-only tests, no mock-heavy files. Notable strengths: negative assertions carry failure messages that name the defect (`"the older snapshot was installed over the newer one"`); `HistoryStoreTests` reads back through the raw `FetchDescriptor` as well as the projection, so a lying projection cannot pass; `LocalStoresTests` asserts container **object identity** (`===`) rather than inferring sharing; `NoteDraftTests` distinguishes `nil` (owes nothing) from `""` (clears the note), which is the exact bug boundary; `UnknownOperationTests` asserts `outcome != .failed(status: -1)`, proving the sentinel status is never shown to the user.

### Scope Guard

| Check | Result |
|---|---|
| `BrewMutating` / `InvalidationScope` / `ServiceCommand` / `TapCommand` / `CleanupCommand` in `Sources/` + `cellar/` | ✅ Zero |
| Services / taps / cleanup / disk-usage files in diff | ✅ None |
| `Package.swift`, `project.pbxproj`, new SPM target | ✅ None |
| `MutationOutcome.forcesReSnapshot` changed | ✅ Unchanged (PM6 untouched). It appears in the diff only as a **new assertion** in `UnknownOperationTests`, proving the unknown path still owes its re-snapshot. |
| `m3-services-cleanup-taps/explore.md` in diff | ✅ Absent from the diff **and** from all branch history (`git log --all` returns no commit touching it) |
| Delta headers | ✅ Exactly five `## MODIFIED Requirements`; zero ADDED / REMOVED / RENAMED |

### Housekeeping

| Check | Result |
|---|---|
| `openspec/config.yaml:7` | ✅ `review_budget_lines: 2000` |
| `openspec/config.yaml:59` | ✅ "Forecast the 2,000-line review budget explicitly." |
| M2 archive location | ✅ `openspec/changes/archive/2026-08-03-m2-mutations-installed/explore.md`, recorded by git as a clean `R100` rename; the old path is gone from `HEAD` |
| `installed-inventory/spec.md` citation repointed | ✅ Now cites the archive path |

### Issues Found

**CRITICAL**: None.

**WARNING**

- **W1 — Candidate exceeds the declared 2,000-line budget once this report lands.** `git diff main...HEAD --shortstat` measures **1,843 insertions + 72 deletions = 1,915** changed lines before this file. tasks.md 9.3 recorded 1,880 and apply-progress recorded 1,899, so the artifacts drifted upward as they were amended, and 9.3's claim that "no `size:exception` is requested" no longer holds. The slice proceeds under the session's accepted ~2,400-line exception; that exception is real but it is **not** reflected in `tasks.md`, which still asserts the candidate fits.
- **W2 — Design deviation: task 2.4's test location.** design.md's testing-strategy table names `BrewClientTests/ClassificationTests`; the test landed in a new `BrewClientTests/UnknownOperationTests.swift`. Justified — adding it to `ClassificationTests` pushed that struct to 259 lines and raised a new `type_body_length` finding, which the zero-new-findings gate forbids. RED was observed in both locations. Recorded inline in tasks.md 2.4. Does not break a spec.
- **W3 — Design deviation: access widening beyond what D6 named.** design.md named only `MetadataStore.init(unavailable:)` as `private → internal`. In practice both stores' `container` properties were also widened to internal, and `LocalStores` carries an internal `container`. Justified — it turns "one container, both stores" from an inference into a directly assertable `===` identity. Nothing became public.
- **W4 — Manual 9.1(a) evidence is partial, and 9.1(c) covers app-target glue only.** 9.1(a)'s before-launch `stat` was not captured (the app was launched before the task's exact steps were read); the after-state shows exactly one `.store` file (`fd -e store` = 1, inode `451684779`) with no "could not be opened" reason. The one-container rule itself is fully proven headlessly by `LocalStoresTests > oneContainerServesBothStores`, so the missing before-stat weakens the wiring evidence, not the rule. Separately, `bulkAddEntersTheSelectionInDisplayedOrder` asserts the displayed-order projection and the submission order through production code, but composes the bulk-add reconciliation in the test — the real `reconcileOrder` lives in the app target and rests on `xcodebuild` plus manual 9.1(c). Both scopings were planned, not discovered here.

**SUGGESTION**

- **S1 — 13 commits against a planned 10.** Three additions: the SDD artifacts needed a home on the branch, the verification-gate commit, and the 9.1 manual-evidence commit. Each keeps a clean rollback boundary; apply-progress documents the first two and the third postdates it.
- **S2 — D1's "byte-for-byte" claim is slightly stronger than the code.** The guard moved from `snapshot.revision != adoptedRevision` to an ordinal comparison. Equal-ordinal-but-different-revision would now be discarded where it previously adopted. Ordinals are minted monotonically per materialization so this is unreachable today, but the design's "keeps today's contract byte-for-byte" holds only while equal ordinal implies equal revision.
- **S3 — Branch history was rewritten.** `git filter-branch --index-filter` purged `m3-services-cleanup-taps/explore.md`, and the path now sits in `.git/info/exclude`. Verified clean and the branch is unpushed, so no collaborator is affected — but any pre-existing local copy of this branch would need a hard reset.
- **S4 — 16 new tests against a forecast 14.** An overshoot in the right direction: the relocated classification test plus one added `NoteDraft` starting-state test.

### Verdict

**PASS WITH WARNINGS** — all 34 tasks complete, all 5 MODIFIED requirements and 24 scenarios have passing named coverage, all six RED anchors independently re-proven against `main`, and every design decision D1–D9 is honoured; four warnings concern budget bookkeeping, two documented design deviations, and honestly-scoped partial manual evidence, none of which blocks archive.
