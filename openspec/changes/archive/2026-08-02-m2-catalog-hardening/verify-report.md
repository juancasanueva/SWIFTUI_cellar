```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:8964a2fa1543a5db075248cd88a8381d5e8a85f15dacce1850a883518dcf3e78
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 6/6
scenarios: 22/22
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:8605570fb6bb3f95d0f397016e6c00ee949787cd48f95760b1e2ba5e7e1d5e60
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests
build_exit_code: 0
build_output_hash: sha256:8b6b4993dbc87fc43836eed9263fac10d9dbb29887387dac3c0d2e74c5904179
```

## Verification Report — RE-VERIFICATION

**Change**: m2-catalog-hardening
**Version**: spec deltas — catalog-sync (4 ADDED), brew-detection (1 MODIFIED), package-search (1 ADDED)
**Mode**: Strict TDD
**Branch**: `feature/m2-catalog-hardening` @ `b321703` (13 commits off `main@cc373e8`)
**Artifact store**: hybrid (this file + Engram `sdd/m2-catalog-hardening/verify-report`)

> **This report supersedes the FAIL verification of head `6668eb7` (evidence_revision
> `sha256:847b6a5a…`, Engram #7074).** That report raised exactly one blocker: the final commit had
> resurrected `openspec/changes/m2-mutations-installed/explore.md`, an unrelated 209-line exploration
> document that an earlier commit on the same branch had deliberately removed, which made checked
> task 6.2's scope-guard assertion false. Commit `b321703` untracks that file. This is a **targeted
> re-verification**: the remediation commit was inspected in full, the scope guard was re-evaluated
> against the new head, and the package suite was re-run so the receipt does not rest on a stale
> gate. The 22-scenario compliance trace, the REL and FULL gate results, and every non-blocking
> finding are carried forward from the superseded report and amended only where the new head changes
> them.

### Re-verification Scope

| Item | Finding |
|---|---|
| Remediation commit | `b321703` — `chore(sdd): untrack exploration of unproposed m2-mutations-installed change` |
| Files touched | `openspec/changes/m2-mutations-installed/explore.md` only — 209 deletions, 0 insertions |
| Production code touched | **None.** `git diff 6668eb7..HEAD --name-only` returns exactly that one path: zero files under `Sources/`, zero under `Tests/`, no `Package.swift`, no project/scheme edits. No spec scenario can regress. |
| `tasks.md` touched | **No.** Unchanged since `6668eb7`; task 6.2 remains `[x]` and its assertion is now true rather than false. |
| Unexpected content in the diff | **None.** |
| Commit hygiene | Conventional (`chore(sdd)`), body explains the 4bfe907 → 6668eb7 → b321703 sequence, no `Co-Authored-By` / AI attribution. |

### Blocker Resolution — verified at head `b321703`

The superseded report's single CRITICAL is closed at source. All four checks it named were re-run:

```text
$ git ls-files openspec/changes/m2-mutations-installed/
(no output — the path is untracked)

$ git diff main...HEAD --name-only | rg "m2-mutations-installed"
(no match)

$ git status --short
?? openspec/changes/m2-mutations-installed/          # present on disk, untracked, as 4bfe907 intended
?? openspec/changes/m2-catalog-hardening/verify-report.md

$ git diff main...HEAD --stat | tail -1
 28 files changed, 2198 insertions(+), 113 deletions(-)
```

- **Untracked, not deleted.** `explore.md` (26,751 bytes) is still on disk and still mirrored in
  Engram (#7064). Only the index entry was removed, which is precisely what `4bfe907` had done and
  what `6668eb7` accidentally undid. Whichever M2 feature change adopts the exploration will commit
  it under its own proposal.
- **No phantom change directory reaches `main`.** The merge diff no longer contains any
  `openspec/changes/m2-mutations-installed/` path, so no directory holding only an `explore.md` with
  no `proposal.md` can land. The only `openspec/` additions are the six `m2-catalog-hardening`
  artifacts.
- **File count and line count moved by exactly the expected delta**: 29 → 28 files,
  2,407 → 2,198 insertions (−209, the file's full size). Nothing else shifted.

### Task 6.2 — scope guard re-evaluated

Task 6.2 asserts: *"`git diff --stat main` touches only the files in design 'File Changes'; no new
public API on the `Catalog` or `BrewProcess` products; `CatalogSnapshot.currentSchemaVersion` still
1 and persisted JSON byte-identical; nothing from follow-ups #4/#5/#8/#9 or any M2 feature work is
present."*

| Clause | Status at `b321703` |
|---|---|
| Diff touches only design "File Changes" | ✅ True — 6 of 6 production files, plus the justified `CatalogSyncSupport.swift` lint split (verified a pure move) |
| No new public API on `Catalog` / `BrewProcess` | ✅ True — carried forward, re-confirmed unchanged by this commit |
| `currentSchemaVersion` still 1, JSON byte-identical | ✅ True — pinned by `revisionIsNotPersisted` |
| Nothing from follow-ups #4/#5/#8/#9 | ✅ True |
| No M2 feature work present | ✅ **Now true** — this was the false clause at `6668eb7` |

**Task 6.2's assertion is true at `b321703`.** The checked box is now honest.

### Build & Tests Execution

The package suite was re-run end to end against `b321703`. REL and FULL are carried forward from the
superseded report: the remediation commit touches no code, no test, and no build input, so neither
gate has a stale input.

**Tests (FAST, re-run for this report)**: PASS — 243 tests in 36 suites, exit 0.
```text
$ swift test   # cwd Packages/CellarCore, head b321703
Test run with 243 tests in 36 suites passed after 1.340 seconds.
```
Identical population to the superseded run (243/36), as required — a bookkeeping commit must not
move the test count.

**Tests (REL, carried forward)**: PASS — 2 tests in 1 suite, exit 0.
```text
$ swift test -c release --filter SearchLatency
Test "p95 as-you-type latency stays under 8 ms on a realistic index" passed after 1.182 seconds.
Test "The latency fixture is the size and shape the ceiling is claimed for" passed after 0.038 seconds.
Test run with 2 tests in 1 suite passed after 1.221 seconds.
```

**Build / FULL (carried forward)**: PASS.
```text
$ xcodebuild test -project cellar.xcodeproj -scheme cellar \
    -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests
** TEST SUCCEEDED **
```

**Lint (carried forward)**: `swiftlint lint` over all 21 changed `.swift` files — exit 0, no output.

**No test was deleted.** `@Test` declarations: 214 on `main` → 243 on HEAD (+29). A name-level diff
of every `@Test`-annotated function between `main` and HEAD found zero removals.

**Coverage**: ➖ Not available — no coverage tool configured for this package.

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total (`tasks.md`, authoritative) | 31 |
| Tasks complete | 27 |
| Tasks incomplete | 4 (Phase 5: 5.1–5.4) |
| Phase 5 status | CUT to a follow-up under the pre-agreed budget rule + accepted `size:exception` — **not** counted as a verification failure |

Phase 5's cut is cleanly annotated in `tasks.md` (a blockquote at the phase heading naming the budget
rule, the forecast, and the feature-branch-chain follow-up). Verified independently: no source or
test file on this branch references `CellarTestSupport`, and both `Fakes/TestClock.swift` copies are
still present and unmodified, so nothing in Phases 0–4/6 depends on the deferred work.

### Spec Compliance Matrix

Carried forward from the superseded report. The remediation commit is test-free and code-free, so no
row can have changed; all 22 were observed passing in the FAST re-run above.

#### catalog-sync — CSA1: A snapshot is adopted exactly once, in order

| Scenario | Test | Result |
|---|---|---|
| A manual refresh adopts its snapshot once | `CatalogAdoptionTests > refreshNowAdoptsItsSnapshotExactlyOnce` | ✅ COMPLIANT |
| A late adoption of an older snapshot is discarded | `CatalogAdoptionTests > lateOlderAdoptionIsDiscarded` | ✅ COMPLIANT |
| Results never blank while a snapshot is adopted | `CatalogAdoptionTests > queriesNeverBlankWhileASnapshotIsAdopted` | ✅ COMPLIANT |

#### catalog-sync — CSA2: A single-flight join is satisfied only by work still in flight

| Scenario | Test | Result |
|---|---|---|
| Concurrent callers coalesce onto one sync | `SyncEngineHardeningTests > concurrentCallersCoalesceOntoOneSync` | ✅ COMPLIANT |
| A settled sync does not answer a later caller | `SyncEngineHardeningTests > settledSyncDoesNotAnswerALaterCaller` | ✅ COMPLIANT |
| A cancelled sync does not answer a later caller | `SyncEngineHardeningTests > cancelledSyncDoesNotAnswerALaterCaller` | ✅ COMPLIANT |
| *(amendment)* settled run vacates before joiners resume | `SingleFlightRecipeTests` (3 tests) | ✅ COMPLIANT |
| *(amendment)* successor waits for the cancelled run to unwind staging | `SyncEngineHardeningTests > cancelledRunUnwindsBeforeItsSuccessorStages` | ✅ COMPLIANT |

#### catalog-sync — CSA3: A zero-package catalog is never published as success

| Scenario | Test | Result |
|---|---|---|
| A degenerate payload from the origin is rejected | `SyncEngineHardeningTests > degeneratePayloadIsRefused` | ✅ COMPLIANT |
| An unchanged answer with no readable cache does not succeed empty | `SyncEngineHardeningTests > unchangedWithNoReadableCacheDoesNotSucceed` | ✅ COMPLIANT |
| A degenerate first sync stays non-fatal | `SyncEngineHardeningTests > degenerateFirstSyncIsNonFatal` | ✅ COMPLIANT |
| A one-package catalog is not degenerate | `SyncEngineHardeningTests > onePackageCatalogPersists` | ✅ COMPLIANT |
| *(write-side structural guard)* | `FileStoreTests > zeroPackagePersistIsRefused` | ✅ COMPLIANT |

#### catalog-sync — CSA4: A persisted zero-package snapshot is treated as no cache

| Scenario | Test | Result |
|---|---|---|
| A poisoned snapshot on disk is silently ignored | `FileStoreTests > zeroPackageSnapshotReadsAsNoCache` + `CatalogAdoptionTests > poisonedSnapshotLaunchesAsAColdStart` | ✅ COMPLIANT |
| Recovery from a poisoned snapshot is unconditional | `SyncEngineHardeningTests > poisonedSnapshotForcesAnUnconditionalFetch` | ✅ COMPLIANT |
| A one-package persisted snapshot is still a usable cache | `FileStoreTests > onePackageSnapshotIsAUsableCache` | ✅ COMPLIANT |

#### brew-detection — BD1: Detection is observable, re-evaluated state (MODIFIED)

| Scenario | Test | Result |
|---|---|---|
| Evaluated at launch | `BrewDetectionStoreTests > launchEvaluationPublishesOnce` (M1, unchanged) | ✅ COMPLIANT |
| Focus re-evaluation observes a newly installed brew | `BrewDetectionStoreTests > focusRefreshObservesNewlyInstalledBrew` (M1, unchanged) | ✅ COMPLIANT |
| Disappearing configured path transitions away | `BrewDetectionStoreTests > vanishingConfiguredPathTransitions` + `configuredPathNotExecutable` (M1, unchanged) | ✅ COMPLIANT |
| A settled evaluation does not answer a later re-evaluation | `BrewDetectionStoreTests > settledEvaluationDoesNotAnswerALaterRefresh` (new) | ✅ COMPLIANT |
| An abandoned caller does not poison later re-evaluations | `BrewDetectionStoreTests > abandonedCallerDoesNotPoisonLaterRefreshes` (new) | ✅ COMPLIANT |
| Concurrent re-evaluations coalesce onto one probe | `BrewDetectionStoreTests > refreshIsSingleFlight` (M1, unchanged, still green) | ✅ COMPLIANT |

#### package-search — PSA1: Index construction never runs on the main actor

| Scenario | Test | Result |
|---|---|---|
| The main actor stays responsive during an index build | `SearchIndexTests > mainActorStaysResponsiveDuringTheBuild` + `CatalogAdoptionTests > adoptionDoesNotBlockTheMainActor` | ✅ COMPLIANT |
| An off-main build answers identically | `SearchIndexTests > offMainBuildAnswersIdentically` | ✅ COMPLIANT |
| The latency ceiling and single-pass build still hold | `SearchLatencyTests > p95StaysUnderCeiling` (REL) + `offMainBuildAnswersIdentically` normalisation assertions | ✅ COMPLIANT (see SUGGESTION 2) |

**Compliance summary**: 22/22 scenarios compliant, 6/6 requirements covered. 0 UNTESTED, 0 FAILING.

### Correctness (Static Evidence)

Carried forward; the remediation commit touches no production file.

| Requirement | Status | Notes |
|---|---|---|
| CSA1 adopt-once, in order | ✅ Implemented | `CatalogStore.adopt` claims `snapshot.revision` before any suspension, stamps a monotonic `adoptionSequence`, installs only while `ordinal > installedSequence`; install is one main-actor assignment after the `await`. |
| CSA2 single-flight join | ✅ Implemented | `CatalogSyncEngine.sync()` token-keyed `InFlightSync`; `defer { self.vacate(token) }` inside the task body; `while let current = inFlight { guard current.isCancelled else { join }; _ = await current.task.value }` drains a cancelled slot. `cancel()` marks *and* cancels. Same shape in `BrewDetectionStore.refresh()` minus the drain. |
| CSA3 zero-package never succeeds | ✅ Implemented | `CatalogFileStore.persist` guards `!snapshot.packages.isEmpty` **outside** the `do` block, so it throws `.malformedPayload` rather than the block's blanket `.persistence` rewrite. It propagates through `CatalogSyncEngine.persist` → the `catch` → `publish(.failed(.malformedPayload))`, so `succeed()` is never reached and neither file is written. The dead `previousSnapshot ?? CatalogSnapshot(…, packages: [])` fallback is gone, replaced by `if !acquired.changed, let previousSnapshot`. |
| CSA4 poisoned snapshot = no cache | ✅ Implemented | `CatalogFileStore.loadSnapshot` returns `nil` after decode when `packages.isEmpty`; the file is left in place. Recovery is unconditional through the *existing* `revalidatable: previousSnapshot != nil` path — no new branch, as the design required. |
| BD1 detection single-flight | ✅ Implemented | Token slot + `defer { self?.vacate(token) }` with `[locator, weak self]`. |
| PSA1 off-main index build | ✅ Implemented | `@concurrent public static func build(from:)` with the attribute preceding the modifier, wrapping the unchanged init. `PackageSearchIndex` remains `Sendable` by composition. |

**Public API added** matches the design exactly: `CatalogSnapshotRevision` (public type; `ordinal` and
`next()` internal, so a consumer can compare an identity but never mint one), `CatalogSnapshot.revision`,
its explicit `public init(from:)`, and `PackageSearchIndex.build(from:)`. `currentSchemaVersion` is
still 1 and `revisionIsNotPersisted` pins the persisted JSON to exactly
`{schemaVersion, generatedAt, skippedRecordCount, packages}`.

### Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| D1 `@concurrent` build + ordinal-guarded install | ✅ Yes | `rerank()` stays synchronous against the installed index; `isReady` still flips after `loadCache()`'s adoption. |
| D2 process-local `revision` pinned to disk | ✅ Yes | `Synchronization.Atomic` counter; `diskRevision` set on successful persist, `nil` on failed persist. |
| D3 token slot, mark-and-drain cancellation | ✅ Yes | Verified against the amended spec text specifically: the settled run vacates before joiners resume (`SingleFlightRecipeTests`, three shapes including the actor-isolated production shape) and the successor's `prepareStaging()` lands after the cancelled run's purge (`stagingLifecycle == [.created, .purged, .created, .purged]`). |
| D4 degenerate refused on write, invisible on read | ✅ Yes | Both guards present at the sites the design named; the write guard is outside the `do`. |
| D5 `CellarTestSupport` | ➖ Deferred | Phase 5 cut, cleanly annotated, no dependency from shipped work. |
| D6 test-migration policy | ✅ Yes | Exactly one M1 assertion changed: `CatalogStoreTests.coldLaunchIsNonBlocking` now polls for `.succeeded` before the pre-existing `guard case .succeeded` — the assertion is added to, not replaced. It landed in `e26a3e0`, the same commit as its fix, whose body cites "Defects #1 and #2" and explains the change. No M1 assertion was deleted or weakened. |
| Design deviation 1 — duplicate adoption *joins* rather than drops | ✅ Justified | Checked against both halves of the contract. CSA1's "adopted exactly once" is about the *index build*, and `indexBuildCount` is incremented only on the non-duplicate path — `refreshNowAdoptsItsSnapshotExactlyOnce` asserts `adoptionRequestCount + 2` against `indexBuildCount + 1`. The join is what preserves `refreshNow()`'s "returns once the resulting snapshot is queryable" contract when the event stream claims the revision first. Dropping instead would break that requirement. |
| Design deviation 3 — `CatalogSyncSupport.swift` | ✅ Verified pure move | Diffed against `main`: the four extensions (`CatalogResource.payloadResources`/`analyticsResources`/`kind`, `CatalogSyncError.from`, `CatalogDecoder.decode`/`decodeAnalytics`, analytics carry-over) all existed verbatim in `CatalogSyncEngine.swift` on `main` at the same visibility. The only semantic edit is `CatalogSyncEngine.counts(of:in:)` (private static) becoming `AnalyticsIndex.init(carriedOverFor:in:)` (internal init) with identical body. **No new public API from the split.** |
| Design deviation 4 — new `Fakes/{Gate,Recorder,HeavyFixtureLock}.swift` | ✅ Verified test-only | All three live under `Tests/CatalogTests/Fakes/`, none is referenced by any `Sources/` file, and the package graph is unchanged (`Package.swift` untouched). |

**`[weak self]` join safety (audited in the superseded report, unchanged here).** `CatalogStore.adopt`'s
adoption `Task` captures `self` weakly and re-checks `guard let self` after the build, so the task
never retains the store; `adoptionInFlight` holds the task, not the reverse, and the slot is cleared
only when it still holds that same task (`if adoptionInFlight == adoption`). The task body inherits
`@MainActor` from the enclosing method, so `installedSequence`, `index` and `packageCount` are all
touched on the main actor — no data race. The join path (`await adoptionInFlight?.value`) cannot
deadlock: the awaited task only awaits `PackageSearchIndex.build`, which depends on nothing the
joiner holds. A duplicate arriving after the adoption already settled finds `adoptionInFlight == nil`
and returns immediately with the snapshot already queryable. `BrewDetectionStore`'s
`defer { self?.vacate(token) }` keeps the pre-existing non-retaining behaviour.

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | 20-row "TDD Cycle Evidence" table in `apply-progress` (#7072) |
| All tasks have tests | ✅ | Every non-audit task names a test file; all files exist |
| RED confirmed (test files exist) | ✅ | 21/21 referenced test files present on disk |
| GREEN confirmed (tests pass) | ✅ | 243/243 re-executed at `b321703` |
| Triangulation adequate | ✅ | Every multi-scenario requirement has one test per scenario; the `TRIANGULATE` column matches the scenario counts in the deltas |
| Safety Net for modified files | ✅ | Every modified-file row carries an N/N count; the one `N/A (new)` row (1.1) is genuinely a new file |
| Task 1.1 stop-gate | ✅ | The D3 defer-ordering assumption was probed before any production edit and held under this toolchain (re-verified: 3/3 green) |

**TDD Compliance**: 7/7 checks passed.

**Green-on-arrival tasks (3.2, 3.4, 4.3, 4.4, 4.5, 4.6) — tautology audit** (carried forward). Each
was checked for whether it can actually fail. All six can:

- **3.2** `offMainBuildAnswersIdentically` — compares the off-main index against a synchronously
  built one across 5 queries plus a kind-filtered query, then asserts `normalizedName(at:)` /
  `normalizedDescription(at:)` equal `PackageText.normalize(...)` per record. A build that stopped
  being single-pass, or that re-derived normalisation per query, fails these.
- **3.4** `queriesNeverBlankWhileASnapshotIsAdopted` — carries an explicit anti-ghost guard,
  `#expect(during > 0, "no query was issued while the adoption was in progress")`, so the
  `sawEmpty.isSet == false` assertion cannot pass vacuously over an empty observation window. Both
  snapshots share the `pkg` prefix, so an empty result can only mean the swap blanked it.
- **4.3** `degeneratePayloadIsRefused` — asserts the error, the published status, byte-level
  `recorder.publishedPaths == writesBefore`, and that 15,001 records are still readable from disk.
- **4.4** two tests asserting `.malformedPayload`, `recorder.publishedPaths.isEmpty`, a `nil`
  `cachedSnapshot()`, and `fileExists == false` for `catalog.json`.
- **4.5** `onePackageCatalogPersists` — asserts the returned *and* the persisted package list.
- **4.6** `poisonedSnapshotForcesAnUnconditionalFetch` — the `validators == nil` assertions are not
  vacuous: the fake records validators on every request, and the companion test
  `SyncEngineTests > unchangedSourcesRevalidateOnly` asserts `requests(for: .formulae).last?.validators?.etag == "V1"`
  on the same recorder, so a fake that silently dropped validators would fail there.

### Assertion Quality

Audited every test file created or modified by this change (11 files, 29 new `@Test`s). Zero
tautologies, zero assertions that never call production code, zero ghost loops, zero smoke-only
tests, zero mock-heavy files. The two timing-shaped tests
(`mainActorStaysResponsiveDuringTheBuild`, `adoptionDoesNotBlockTheMainActor`) assert `during > 0`,
which is structurally impossible under a synchronous main-actor build and therefore a regression
guard rather than a flaky threshold.

**Assertion quality**: ✅ All assertions verify real behaviour — 0 CRITICAL, 0 WARNING.

**`.heavyFixture` audit.** `HeavyFixtureTrait` is a `TestScoping` trait that wraps the test body in an
actor lock and does nothing else — no skip, no retry, no relaxation. `CatalogMemoryTests` keeps
`peakBudget = 300 MB` and `retainedBudget = 40 MB` unchanged and keeps its `.timeLimit(.minutes(2))`.
`SearchLatencyTests` keeps `ceiling = 8 ms`, `recordCount = 15_500`, 1,000 samples and the same p95
index. The only diff in both files is the added trait. **No assertion or budget was weakened.**

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit | 243 | 22 | Swift Testing |
| Integration | 0 | 0 | — (no UI surface changed by this change) |
| E2E | 0 | 0 | XCUITest present but `cellarUITests` is pre-existing template breakage, deliberately skipped |
| **Total** | **243** | **22** | |

### Quality Metrics

**Linter**: ✅ `swiftlint lint` over all 21 changed `.swift` files — exit 0, no output.
**Type checker**: ✅ Both `swift build` (via `swift test`) and `xcodebuild` compiled clean under
Swift 6 language mode.

### Scope Guard

| Check | Result at `b321703` |
|---|---|
| Production files match design "File Changes" | ✅ 6 of 6 modified, plus the justified `CatalogSyncSupport.swift` lint split |
| No new public API beyond the design | ✅ Verified against `main` |
| `currentSchemaVersion` still 1, persisted JSON byte-identical | ✅ Pinned by `revisionIsNotPersisted` |
| Nothing from follow-ups #4/#5/#8/#9 | ✅ Absent |
| No M2 *feature* work | ✅ Absent from all `Sources/` and `Tests/` |
| No unrelated files in the diff | ✅ **RESOLVED by `b321703`** — see "Blocker Resolution" above |

### Commit Hygiene

| Check | Result |
|---|---|
| Conventional commits | ✅ All 13: `test(catalog)`, `fix(catalog)`, `fix(brew)`, `feat(catalog)`, `refactor(test)`, `refactor`, `chore(sdd)` ×2 |
| No `Co-Authored-By` / AI attribution | ✅ Scanned all 13 bodies for `co-authored`, `claude`, `generated with`, `anthropic`, `assistant` — zero matches |
| D6 policy (M1 assertion changes cite a defect number, in the fix's commit) | ✅ The one such change is in `e26a3e0`, whose body opens "Defects #1 and #2" and carries a dedicated "D6 audit for defects #1/#2" paragraph naming the assertion |
| Commit bodies name their RED tests and spec scenarios | ✅ Present throughout |

### Issues Found

**CRITICAL**: None.

> **Resolved — the superseded report's only blocker, preserved for the record.**
> *"`openspec/changes/m2-mutations-installed/explore.md` (209 lines) is present in the branch tree,
> contradicting checked task 6.2 and the branch's own stated intent. Commit `4bfe907` deliberately
> removed the file; the final commit `6668eb7` re-added it, evidently by another blanket stage.
> Merging would ship 209 unrelated review lines and create a phantom
> `openspec/changes/m2-mutations-installed/` directory on `main` containing only an `explore.md`
> with no `proposal.md`."*
> Closed by `b321703`, which untracks the file while leaving it on disk, exactly as `4bfe907`
> intended. Verified by four independent checks at the new head; no production code, test, or gate
> was touched.

**WARNING** — both carried forward unchanged; the new head does not affect either.

1. **Task-count bookkeeping is inconsistent across artifacts.** `tasks.md` (declared authoritative)
   holds 31 tasks with 27 checked. Engram `sdd/m2-catalog-hardening/tasks` (#7071) says "30 tasks"
   and `apply-progress` (#7072) says "28/30 tasks complete", while its own per-phase enumeration
   lists all 31 and marks 27. The file's numbers are the ones used in this report. Cosmetic, but it
   would mislead anyone reading the Engram mirror alone. `apply-progress` additionally still records
   `explore.md` as "removed again", which was false at `6668eb7` and is true again at `b321703`.
2. **`CatalogStore.adopt` orders installs by adoption-call arrival, not by snapshot recency.**
   `adoptionSequence` is stamped when `adopt` is *entered*, so the last caller to enter always wins
   the ordinal race. The spec's scenario — an older adoption already in progress when a newer
   snapshot is delivered — is handled correctly and is tested. The uncovered shape is the mirror
   image: an `adopt` call carrying an *older* snapshot that *begins* after a newer one was claimed
   would receive a higher ordinal and install over the newer catalog. Reachability is very low —
   it needs a second sync to complete inside a single index build (~30 ms) while the event-stream
   handler is still on the earlier snapshot — and the ordered single-iterator event stream plus
   single-flight sync makes it unreachable in the tested paths. `CatalogSnapshotRevision.ordinal` is
   already a monotonic materialization counter, so guarding on the revision ordinal instead of the
   call ordinal would close it in one line. **Carry to `m2-installed-inventory`**, which copies this
   recipe.

**SUGGESTION** — all three carried forward unchanged.

1. Stale comment in `CatalogAdoptionTests > lateOlderAdoptionIsDiscarded`: it reads *"`older` is
   15,500 records and `newer` is 3"* while the code uses `Self.snapshot(of: 8_000, prefix: "old")`.
   The intent (a big slow build overtaken by a tiny one) is unchanged; only the number is wrong.
2. PSA1 scenario 3 opens *"GIVEN an index built off the main actor"*, but
   `SearchLatencyTests.p95StaysUnderCeiling` builds via the synchronous `PackageSearchIndex(snapshot:)`
   initialiser (on a nonisolated test executor, so never on the main actor). Coverage is sound
   transitively — `build(from:)` is literally `PackageSearchIndex(snapshot: snapshot)` and
   `offMainBuildAnswersIdentically` proves the two are indistinguishable — but making the latency
   test `await PackageSearchIndex.build(from:)` would make the scenario literal at zero cost.
3. Both design "Open Questions" remain open by design (path-keyed single flight for
   `BrewDetectionStore`; adoption on an unchanged 304 sync). WARNING 2 above belongs with the first
   of them and should travel to `m2-installed-inventory`.

### Verdict

**PASS WITH WARNINGS** — 0 blockers, 0 CRITICAL, 2 WARNING, 3 SUGGESTION.

The single blocker from the superseded FAIL is closed by a one-file, code-free commit that untracks
an unrelated exploration document while leaving it on disk. Task 6.2's scope-guard assertion is now
true in every clause, the merge diff carries no `m2-mutations-installed` path, no phantom change
directory can reach `main`, and the package suite is unchanged at 243 tests in 36 suites. Everything
the superseded report established on behaviour stands: 22/22 spec scenarios covered by tests that
passed at runtime, 6/6 requirements implemented as designed, D1–D4 and D6 followed with D5
legitimately cut, strict-TDD evidence validated end to end, no tautological or weakened assertions,
no test deleted, lint clean.

The two remaining WARNINGs are non-blocking and neither is a defect in shipped behaviour: one is
artifact bookkeeping drift, the other is a very-low-reachability ordering gap already routed to
`m2-installed-inventory`, the slice that copies this single-flight recipe.

**This change is archive-ready.**
