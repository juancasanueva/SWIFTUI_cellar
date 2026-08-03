# Apply progress: m3-services — batch 1 (read half, Phases 0–7)

**Mode**: Strict TDD (`openspec/config.yaml` → `testing.strict_tdd: true`, `rules.apply.tdd: true`).
**Artifact store**: hybrid — this file and Engram `sdd/m3-services/apply-progress`.
**Branch**: `feature/m3-services`, base `main` @ `284aab9` (the planning markdown landed separately in
PR #8, so this branch carries code only).
**Batch scope**: Phases 0–7 inclusive. Phase 8 (`BrewMutating`) onward is a later batch and was **not**
started. The split boundary in `tasks.md` was respected exactly.

## `size:exception` — recorded before any code was written (task 0.2)

`delivery_strategy: exception-ok`, chain strategy `size-exception`, accepted by the maintainer
(ruling #7182-1) after being shown the two-way split and the under-pricing record. The exception is
recorded here, at apply time, not requested at the ledger gate.

This batch's measured candidate: **27 files changed, 3,185 insertions, 50 deletions** at
`git diff main...HEAD --shortstat`. That is code only — the 1,744 markdown lines the `tasks.md`
forecast counted are already on `main`. Against the read half's own forecast band (≈2,600–3,100
including its share of markdown), the code-only figure lands **inside** the band's upper half.

## Baseline (task 0.1)

Measured on `284aab9` before any edit:

| Metric | Expected | Measured |
|---|---|---|
| `swift test --package-path Packages/CellarCore` | 571 tests / 77 suites | **571 tests / 77 suites**, 1 known issue |
| `swiftlint --quiet` findings | 60 | **60** |

## Completed tasks

Phase 0 — 0.1, 0.2.
Phase 1 — 1.1, 1.2, 1.3, 1.4, 1.5.
Phase 2 — 2.1, 2.2, 2.3, 2.4, 2.5, 2.6.
Phase 3 — 3.1, 3.2, 3.3, 3.4, 3.5.
Phase 4 — 4.1, 4.2, 4.3.
Phase 5 — 5.1, 5.2, 5.3, 5.4, 5.5.
Phase 6 — 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7.
Phase 7 — 7.1, 7.2, 7.3.

**36 of 84 tasks complete** (2 + 5 + 6 + 5 + 3 + 5 + 7 + 3). Remaining in this change: Phases 8–17,
**48 tasks** — the whole control half plus the shared reconciliation, manual-verification and
full-gate phases.

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 1.1 | `BrewProcessTests/EnvironmentTests.swift` | Unit | 571/571 | ✅ failed: `pinned["HOMEBREW_COLOR"] → "0" == nil` | ✅ | ✅ 3 existing approval assertions rewritten to the new behaviour | ➖ |
| 1.2 | same | Unit | 571/571 | ✅ failed: the force key reached the spawned spec | ✅ | ✅ read + mutate argv both asserted | ✅ waited on the gate's launch |
| 1.3 | — (GREEN) | — | — | — | ✅ | — | ✅ doc comment corrected |
| 1.4 | `BrewProcessTests/BrewIntegrationTests.swift` | Integration (real brew, self-skipping, `.tags(.realBrew)`) | — | ✅ **observed live** — reverted the key and captured `\u{1B}[32m==>` in 6 real lines | ✅ | ➖ single scenario | ✅ discovers its formula rather than hardcoding one |
| 1.5 | — (docs) | — | — | — | — | — | — |
| 2.1 | `Fakes/ServicesFixture.swift` | Fixture | N/A (new) | — | — | — | — |
| 2.2 | `ServicesDecodeTests.swift` | Unit | N/A (new) | ✅ `ServiceRecord` not in scope | ✅ | ✅ 7 statuses + `mystery` + `other`-vs-catch-all + undecodable + not-a-list | ➖ |
| 2.3 | same | Unit | N/A (new) | ✅ | ✅ | ✅ null pair **and** present pair | ➖ |
| 2.4 | — (GREEN) | — | — | — | ✅ | — | ✅ dedupe extracted to a pure function |
| 2.5 | `ServicesDecodeTests.swift` | Unit | N/A (new) | ✅ | ✅ | ✅ identical / distinct / error-log-only / both-null | ➖ |
| 2.6 | — (GREEN) | — | — | — | ✅ | — | ➖ |
| 3.1 | `ServicesPayloadTests.swift` | Unit | N/A (new) | ✅ `ServicesListPayloadSource` not in scope | ✅ | ✅ argv + executable + decoded bytes | ➖ |
| 3.2 | same | Unit | N/A (new) | ✅ | ✅ | ✅ 3 names, none carrying `--all` | ➖ |
| 3.3 | — (GREEN, Fake It) | — | — | — | ✅ | — | — |
| 3.4 | `ServicesPayloadTests.swift` | Unit | 8/8 | ✅ **the Fake It broke**: 3 of 4 payload rules unimplemented | ✅ | ✅ non-zero / cancelled-by-us / signalled-by-others / interleaved stderr / 3 blank shapes | ➖ |
| 3.5 | — (GREEN, generalised) | — | — | — | ✅ | — | ✅ `stderrTail` extracted |
| 4.1 | `ServicesStoreTests.swift` | Unit | N/A (new) | ✅ `ServicesStore` not in scope | ✅ | ✅ coalesce / invalidation-mark / different installation / late-older / failure / malformed | ➖ |
| 4.2 | same | Unit | N/A (new) | ✅ | ✅ | ✅ absent + invalid path + populates-when-brew-appears | ➖ |
| 4.3 | — (GREEN) | — | — | — | ✅ | — | ✅ `LocalStoresTests > oneContainerServesBothStores` re-run green |
| 5.1 | `ServicesRefreshTests.swift` | Unit (`TestClock`) | N/A (new) | ✅ `ServicesRefreshCoordinator` not in scope | ✅ | ✅ 3 ticks + a 4-second non-tick | ➖ |
| 5.2 | same | Unit | N/A (new) | ✅ | ✅ | ✅ 60 s of simulated time, twice — once counting probes, once counting spawns | ✅ |
| 5.3 | same | Unit | N/A (new) | ✅ **and verified by mutation** — see "Issues found" | ✅ | ✅ 3 shows + 2 hide/show cycles | ✅ assertion rewritten to count clock sleepers |
| 5.4 | same | Unit | N/A (new) | ✅ | ✅ | ✅ every recorded argv asserted, not just the count | ➖ |
| 5.5 | — (GREEN) | — | — | — | ✅ | — | ✅ visibility split into two reported halves |
| 6.1 | — (enum case) | — | — | — | ✅ | ➖ structural, one possible output | — |
| 6.2 | — (views) | — | — | — | ✅ `xcodebuild build` SUCCEEDED | — | — |
| 6.3 | `ServicesPresentationTests.swift` | Unit | N/A (new) | ✅ `ServiceStatus` has no member `label` | ✅ | ✅ 8 statuses, distinct labels, tone/isFailure agreement, no orphan tone | ➖ |
| 6.4 | same | Unit | N/A (new) | ✅ | ✅ | ✅ status replacement + 8 forbidden symbols over 6 sources, positively anchored | ➖ |
| 6.5 | — (GREEN) | — | — | — | ✅ | ➖ protocol seam | — |
| 6.6 | — (view) | — | — | — | ✅ build | — | — |
| 6.7 | — (wiring) | — | — | — | ✅ build + `cellarTests` green | — | — |
| 7.1 | `PersistenceTests/HistoryStoreFailureTests.swift` | Unit | 12/12 | ✅ **failed on the real defect**: one keystroke reported a healthy history | ✅ | ✅ 3 further reloads | ✅ suite split out for `type_body_length` |
| 7.2 | same | Unit | 12/12 | ✅ | ✅ | ✅ successful append + successful clear + unopened store keeps its own reason | ➖ |
| 7.3 | — (GREEN) | — | — | — | ✅ | — | ✅ sticky set **before** the reload, not after |

### Test summary

- Tests before: **571 / 77 suites**. After: **626 / 83 suites**, 1 known issue (the same pre-existing one).
- **55 tests added**, all passing. Layers: Unit 54, Integration 1 (real `brew`, self-skipping).
- New pure functions: `ServiceDetail.logPaths(log:errorLog:)`, `ServicesPayload.payload(from:exit:)`,
  `ServiceStatus.init(raw:)` / `.label` / `.tone` / `.isFailure`.
- Approval tests rewritten for changed behaviour: 3 (the `HOMEBREW_COLOR == "0"` assertions).

## Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused test command | `swift test --package-path Packages/CellarCore` → **626 tests / 83 suites passed, 1 known issue** |
| Full suite | `xcodebuild test … -destination 'platform=macOS,arch=arm64'` → **\*\* TEST SUCCEEDED \*\***, `cellarUITests` 2/2 and `cellarTests` green alongside the package suites |
| Runtime harness | `xcodebuild build … -destination 'platform=macOS,arch=arm64'` → **BUILD SUCCEEDED**, zero concurrency warnings. Real-`brew` integration test 1.4 passes. Live app run: **zero child processes over 20 s** while parked on Browse. Live `od -c` A/B: **0** ESC-carrying lines under the pinned environment, **14** under the old key |
| Lint | `swiftlint --quiet` = **60** findings, equal to the baseline. Zero new |
| File length | Largest new file `ServicesWire.swift` at 287 lines; every new file and every touched file under the 400-line `file_length` warning |
| Rollback boundary | Seven commits, one per work unit. Reverting `8e8fe7e` restores the history store; reverting `46f8090` removes the whole services surface from the app; reverting the first six removes services from CellarCore entirely. Nothing outside `Services*`/`LogFileOpening*`/`BrewEnvironment`/`HistoryStore`/`AppSection`/`ContentView`/`cellarApp` was touched |

## Scope guard (early run of 17.2, for this batch only)

- `rg 'isSettling|settleGrace'` over `Sources/` and `cellar/` → **zero**.
- `git diff main -- Sources/BrewClient/InstalledChangeObserving.swift` → **empty** (task 9.7 holds).
- `BulkSelection.Action` still exactly `upgrade`, `uninstall`.
- The only taps/cleanup path touched is `m3-services-cleanup-taps/explore.md`, which task 1.5 requires.

## Deviations from the design, all deliberate

1. **`ServicesError` is declared in `ServicesWire.swift`**, not in `ServicesPayloadSource.swift` as the
   design's file table says. The decoder needs it one phase earlier and every commit has to compile on
   its own. No behavioural difference; the enum is closed and identical.
2. **`ServiceTarget` ships in Phase 3**, not in Phase 11's `ServiceCommand.swift`. The read half builds
   the codebase's only parameterised read argv, so it needs the validated wrapper now — otherwise the
   detail probe would take a raw `String` and the threat-matrix guarantee would be false for a whole
   phase. Phase 11 must express `ServiceCommand` **over** it rather than redeclaring it.
3. **Visibility is two reported inputs, `setVisible` and `setActive`**, not one. SM3 names two reasons a
   surface stops being visible — the window was hidden, the section was deselected — and they are
   observed in two different places. One setter would let whichever reported last overrule the other,
   so ⌘H with Services selected would keep polling. The gate is their conjunction.
4. **`ServicesPresentation.swift` is a new file** the design's table does not list. It keeps the
   status→label/tone projection out of `ServicesWire.swift`, which is the file `tasks.md` flagged as
   most likely to breach `file_length`.
5. **`HistoryStoreFailureTests.swift` is a new suite.** Folding Phase 7's tests into
   `HistoryStoreTests` pushed that type past SwiftLint's `type_body_length`. Task 17.1 requires a split
   rather than a suppression, applied here rather than deferred.

## Issues found

1. **A test that passed while proving nothing** — `onlyOnePollLoopRunsPerLaunch`, first version. It
   counted probes, and `ServicesStore` coalesces same-request refreshes onto one acquisition, so two
   or three concurrent poll loops produce exactly the same probe count as one. Verified by mutation:
   with **both** loop guards deleted the test still passed. Rewritten to count sleepers on the injected
   clock — one live loop is one sleeper — and re-verified by the same mutation, which now reports
   `sleeperCount → 3 == 1`. The pattern generalises: any assertion downstream of a coalescing store
   cannot count upstream callers.
2. **`log_path == error_log_path` is the live shape**, not a hypothetical. `brew services info --json`
   on this machine returns `/opt/homebrew/var/log/atuin.log` for both keys, so the dedupe rule is
   load-bearing on day one rather than defensive.
3. **The `HOMEBREW_COLOR` defect is confirmed live, twice.** Reverting the key made the integration
   test capture `\u{1B}[32m==>\u{1B}[0m` from a real `brew info`, and a direct `od -c` A/B counted 14
   ESC-carrying lines under the old key against 0 under the new one.
4. **A false red on the full suite, caused by my own tooling, not by the code.** The first
   `xcodebuild test` run reported `** TEST FAILED **` with
   `cellarUITests-Runner … The test runner hung before establishing connection.` Two `xcodebuild test`
   invocations were running concurrently — a first one that had been moved to the background after a
   timeout, and a second started while it still held the UI-test runner. Chased down rather than
   waved off: `cellarUITests` alone passes on `main` (**TEST SUCCEEDED**), passes at `HEAD`
   (**TEST SUCCEEDED**), and the whole suite passes at `HEAD` when nothing else is running
   (**TEST SUCCEEDED**, `Executed 4 tests, 0 failures`). `cellarUITests` is untouched Xcode template
   code — unmodified since `Initial Commit` — so it could not have been broken by this batch. **Never
   run two `xcodebuild test` invocations against the same scheme at once.**
5. **A `.signalled(SIGINT)` exit is not a cancellation.** `BrewExit.isCancelled` is true only for
   `.cancelled(signal:)` — Cellar's own cancel. My first payload test conflated them; the production
   rule was right and the test was wrong. A `brew` killed from Activity Monitor is a failure, and
   reporting it as "you cancelled this" would be a lie.

## Manual verification — what was and was not obtained

Task 16.1 is **reserved for the orchestrator/user and remains unchecked**. Of the twelve pre-written
checks, these fall inside Phases 1–7. Recorded honestly, per ruling #7180 c and the M2-3 IH6 lesson:

| Check | Status | Actual observation |
|---|---|---|
| **MV-11** (no ANSI reaches the UI) | **Byte half obtained; human-visible half NOT obtained** | Live `od -c` on a real `brew info --formula abseil` with the pinned environment: **0** ESC bytes. The same command under `HOMEBREW_COLOR=0`: **14** ESC-carrying lines. The authoritative proof is integration test 1.4, which passes. The Activity-drawer half needs GUI interaction I cannot perform |
| **MV-2 (c)** (zero spawns while hidden) | **Corroborated live, partially** | The built app was launched and parked on its default Browse section for 20 s: `pgrep -P <cellar pid>` returned **zero** child processes at all 40 samples. That is the "not visible → no probe" half on the real app. Parts (a), (b) and (d) need clicking Services and are NOT obtained |
| **MV-1** (surface lists real state) | **NOT obtained** | Requires selecting Services in the sidebar. I cannot drive the GUI |
| **MV-5** (detail pane, deduped logs) | **NOT obtained live**; the rule is proven headlessly | Requires selecting a row. The dedupe is proven by `identicalLogAndErrorLogPathsArePresentedOnce` against the machine's real payload shape, in which the two paths **are** identical |
| **MV-9** (all seven statuses render) | **NOT obtained** | Requires a temporary fixture patch, a build, and visual inspection. Deliberately not attempted: the check mandates a patch that MUST NOT be committed, and I cannot inspect the result. Task 6.3 proves the mapping headlessly |
| **MV-10** (brew-absent guidance) | **NOT obtained** | Requires a configured-brew-path affordance in the UI. Coverage rests on tasks 4.2 and (later) 12.3, exactly as the check itself anticipates |

Everything the machine could answer, it answered. Nothing above is claimed as covered that was not.

## Next

`sdd-apply` again for Phase 8 onward (the control half). Do **not** run `sdd-verify` yet: Phases 8–17
are untouched, and Phase 17's full gate and Phase 16's manual checks are scoped to the whole change.

Two notes the next batch must carry:

- `ServiceCommand` must be expressed **over the existing `ServiceTarget`**, not redeclare it.
- `ServicesRefreshCoordinator` already has the seam Phase 14 needs; the terminals consumer and the
  `isMutating` suppression are genuinely absent, not faked.
