# Apply progress: m3-services

**Mode**: Strict TDD (`openspec/config.yaml` → `testing.strict_tdd: true`, `rules.apply.tdd: true`).
**Artifact store**: hybrid — this file and Engram `sdd/m3-services/apply-progress`.
**Branch**: `feature/m3-services`, base `main` @ `284aab9`. The planning markdown landed separately
in PR #8, so this branch carries code plus only the markdown the apply phase itself produces.
**Status**: **83 of 84 tasks complete.** Task 16.1 (manual verification) is reserved for the
orchestrator/user and is deliberately left unchecked.

Two batches. Batch 1 (Phases 0–7, the read half) is preserved verbatim at the end of this file;
nothing in it has been rewritten. Batch 2 (Phases 8–17, the control half) is recorded here.

---

# Batch 2 — the control half, Phases 8–17

**Batch scope**: Phases 8–17 inclusive, 48 tasks, of which 47 are complete and one (16.1) is the
user's. Base for this batch: `24fe71a`, batch 1's head.

## `size:exception`

Recorded at task 0.2 before batch 1 wrote any code (ruling #7182-1), and it covers this batch and the
verify report. `delivery_strategy: exception-ok`, chain strategy `size-exception`. The maintainer
accepted it with the two-way split and the under-pricing record in front of them, so no decision is
re-litigated here — but the outcome **is** measured against the forecast, in task 17.3 below.

## Completed tasks

Phase 8 — 8.1 … 8.6. Phase 9 — 9.1 … 9.7. Phase 10 — 10.1 … 10.3. Phase 11 — 11.1 … 11.10.
Phase 12 — 12.1 … 12.5. Phase 13 — 13.1 … 13.4. Phase 14 — 14.1 … 14.4. Phase 15 — 15.1 … 15.5.
Phase 16 — **16.1 deliberately unchecked** (partial evidence recorded in `tasks.md`, see below).
Phase 17 — 17.1, 17.2, 17.3.

**Cumulative: 83 of 84.**

## Seven work-unit commits

| Commit | Unit |
|---|---|
| `6fdec42` | `refactor(brew-client): generalize the mutation spine behind BrewMutating` |
| `cfd2038` | `feat(brew-client): refresh only the state domains a command invalidates` |
| `b968f47` | `fix(brew-client): close the pending-confirmation setter` |
| `731bdfe` | `feat(brew-client): classify service outcomes from output markers` |
| `059cc09` | `feat(brew-client): submit service verbs one per service, guarded` |
| `1f1f0f4` | `feat(persistence): record service verbs with a null package identity` |
| `20cf59b` | `feat(services): wire the row controls to the guarded submit path` |
| `7814d79` | `docs(sdd): reconcile the spec headers, register and follow-ups` |

## TDD Cycle Evidence

Strict TDD was active throughout. Where a test was written **after** its production code — which
happened four times, all recorded — RED was obtained by **mutation** instead of by ordering, and the
mutation and its exact failing assertion are named. That is weaker than ordering and is not presented
as equivalent.

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 8.1 | `BrewMutatingTests.swift` | Unit | 626/626 | ✅ `BrewMutating` not in scope | ✅ | ✅ foreign command through the real spine + the whole package vocabulary, kept exhaustive by the **compiler** | ✅ `ProbeMutation` extracted to `Fakes/` |
| 8.2 | same | Unit | 626/626 | ✅ | ✅ | ✅ equal / differing / foreign erasures, plus a structural no-way-back scan | ➖ |
| 8.3–8.5 | — (GREEN) | — | — | — | ✅ | — | ✅ concrete `submit`/`request` overloads so leading-dot literals still infer |
| 8.6 | `MutationCommandTests.swift` | Unit | 630/630 | ✅ **verified by mutation** — one injected `\(` fails it *by file name* | ✅ | ✅ scans every `*Command.swift`, anchored positively first | ➖ |
| 9.1 | `MutationGatesTests.swift` | Unit | 631/631 | ✅ `MutationGates` not in scope | ✅ | ✅ success / non-zero / typed busy / cancelled, each ×1 re-snapshot | ✅ harness tuple → struct with `stop()` |
| 9.2 | same | Unit | 631/631 | ✅ | ✅ | ✅ three terminals, zero inventory probes asserted on the **literal argv** | ➖ |
| 9.3 | `InstalledRefreshScopeTests.swift` | Unit | 635/635 | ⚠️ **written after GREEN; RED obtained by mutation** — broadcasting instead of intersecting fails it at `isMutating → true` | ✅ | ✅ paired with the shipped suppression test as its contrast | ✅ split out at `type_body_length` |
| 9.4 | `OperationCenterScopedHistoryTests.swift` | Unit | 635/635 | ⚠️ **same** — the mutation fails it at `installed.value → 1` | ✅ | ✅ working / absent / failing recorder | ✅ split out at `type_body_length` |
| 9.5–9.6 | — (GREEN) | — | — | — | ✅ | — | ✅ `forcesReSnapshot` deleted; two approval tests rewritten to the new truth |
| 9.7 | — (scope guard) | — | — | — | ✅ `git diff main -- InstalledChangeObserving.swift` = **0 lines** | — | — |
| 10.1 | `ConfirmationBoxTests.swift` | Unit | 637/637 | ✅ **failed on the real defect** — `internal(set)` present, direct assignment present | ✅ | ✅ four setter widths + an assignment scan over both files | ✅ scan tightened after it caught itself |
| 10.2 | same | Unit | 637/637 | ✅ | ✅ | ✅ request → confirm → request → decline | ➖ |
| 10.3 | — (GREEN) | — | — | — | ✅ | ✅ `withObservationTracking` proves the nested read still wakes observers | ✅ OA5 summary split to its own file at 409 lines |
| 11.1–11.3 | `ServiceCommandTests.swift` | Unit | 640/640 | ✅ `ServiceCommand` not in scope | ✅ | ✅ 10 hostile names, 6 legitimate, 12 argv vectors, the 5-control surface | ✅ `ServiceTarget` **moved** (not redeclared) into `ServiceCommand.swift` |
| 11.5 | `ServiceClassificationTests.swift` | Unit | 640/640 | ✅ `.noChange` not in scope | ✅ | ✅ cold start / already-started / not-started / unmatched both ways / 3 interpolated names | ➖ |
| 11.6 | `ServiceClassificationContainmentTests.swift` | Unit | 640/640 | ✅ | ✅ | ✅ **55** command×payload pairs; **verified by mutation** — moving the marker pass to the shared default fails **both** containment tests | ✅ split out at `file_length`; tuple → named `Payload` |
| 11.7, 11.10 | — (GREEN) | — | — | — | ✅ | — | ✅ four exhaustive switches updated; `HistoryRow` label added |
| 11.8–11.9 | `ServiceClassification*Tests.swift` | Unit | 640/640 | ✅ | ✅ | ✅ root warning on 0 vs non-zero; hostile payload leaves argv byte-identical | ➖ |
| 12.1–12.4 | `ServiceSubmissionTests.swift` | Unit | 662/662 | ✅ `submit(service:)` not in scope | ✅ | ✅ same/different service, 3 terminal kinds, 3-service fan-out, 2 brew-absent shapes | ✅ guard **verified by mutation** — deleting it fails 3 assertions |
| 12.5 | — (GREEN) | — | — | — | ✅ | — | ✅ guard holds items, so release needs no hook in `finish` |
| 13.1–13.2 | `ServiceHistoryTests.swift` | Unit | 668/668 | ⚠️ **written after GREEN; RED obtained by two mutations** — fabricating a `PackageID`, and de-namespacing a verb, each fail them by name | ✅ | ✅ 4 verbs, 10 toggles, a `.noChange` entry, a refused duplicate | ➖ |
| 13.3 | `HistoryStoreTests.swift` | Unit | 668/668 | ⚠️ **same** | ✅ | ✅ verb search, argv search, unfiltered projection | ➖ |
| 13.4 | — (GREEN) | — | — | — | ✅ (landed with 11.4) | — | — |
| 14.1–14.2 | `ServicesRefreshControlTests.swift` | Unit (`TestClock`) | 673/673 | ✅ `mutations:` not in scope | ✅ | ✅ suppression across 4 intervals, then failed **and** cancelled terminals | ✅ split from `ServicesRefreshTests` at its length bound |
| 14.3 | — (GREEN) | — | — | — | ✅ **verified by two mutations** — dropping the guard lets 5 refreshes run mid-mutation; emptying the consumer drops the owed refresh to 0 | — | ✅ |
| 14.4 | — (views + wiring) | — | — | — | ✅ `xcodebuild build` SUCCEEDED | — | — |
| 15.1–15.5 | — (docs) | — | — | — | — | — | — |

### Test summary

- Tests before this batch: **626 / 83 suites**. After: **676 / 94 suites**, 1 pre-existing known issue.
- **50 tests added in this batch** (105 across the whole change, against the 571 baseline). All unit.
- **9 mutation verifications**, every one of which failed the test it was aimed at, on the assertion
  that names the defect. Listed in the table above.
- Approval tests rewritten because the specified behaviour changed: **2**
  (`everyOutcomeForcesAReSnapshot` and the `UnknownOperationTests` re-snapshot assertion).
- New pure functions: `ServiceCommand.arguments` / `.verb` / `.classify`, `ServiceRowControl.command(for:)`,
  `AnyBrewMutation.init`, `InvalidationScope`.

## Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused test command | `swift test --package-path Packages/CellarCore` → **676 tests / 94 suites passed**, 1 known issue |
| Full suite | `xcodebuild test … -destination 'platform=macOS,arch=arm64'` → **\*\* TEST SUCCEEDED \*\***, `cellarUITests` 4/4, `cellarTests` green. Run **alone**, per batch 1's false-red lesson |
| Runtime harness | `xcodebuild build … -destination 'platform=macOS,arch=arm64'` → **BUILD SUCCEEDED**, **zero** warnings of any kind in the raw log. Live brew probes on 6.0.15 re-confirmed all four classification markers and both MV-3 discriminators (see task 16.1) |
| Lint | `swiftlint --quiet` = **60**, equal to the 0.1 baseline. Zero new |
| File length | Largest file `OperationCenter.swift` at **391**; every new and touched file under 400. Four splits rather than suppressions |
| Rollback boundary | Eight commits, one per work unit. Reverting `20cf59b` removes the row controls and the poll's mutation half; `1f1f0f4`+`059cc09`+`731bdfe` remove the services command family entirely; `b968f47` restores the confirmation setter; `cfd2038` restores unconditional re-snapshot; `6fdec42` restores the package-only spine. Nothing outside the named files was touched |

## Deviations from the design, all deliberate

1. **`ServiceTarget` was *moved* into `ServiceCommand.swift`, not redeclared.** Batch 1 shipped it in
   `ServicesPayloadSource.swift` because the read half needed it a phase early. Task 11.4 names it as
   part of `ServiceCommand.swift`, and the structural scan from 8.6 requires every `*Command.swift` to
   route names through `MutationName.isSafe` — which is only true if the wrapper lives there. One
   declaration, one gate, and the read sources still use it.
2. **The design under-counted the app-target call sites.** It claimed every existing site compiles
   unchanged; `MutationConfirmation.swift` switched on `request.command` as a `MutationCommand` case
   and could not. It now reads the request's **verb**, which is the projection the durable history is
   searched by and already distinguishes zap from an ordinary uninstall. The four sites the design
   named do compile unchanged.
3. **`submit` and `request` gained concrete `MutationCommand` overloads.** A leading-dot literal —
   `operations.submit(.upgradeAll)` — cannot infer a contextual base against a generic parameter, so
   without them the "compiles unchanged" claim would have been false. Both forward to one
   implementation; there is one submission path, not two.
4. **`AnyBrewMutation` carries no classifier.** It conforms to `BrewMutating` with the protocol
   default. Classification always runs on the **concrete** command at the terminal, because
   `OperationCenter.run` is generic and holds it, so the erasure is never on that path — and
   `ServiceHistoryTests > aNoChangeOutcomeRecordsOneEntryNamingItself` proves it end to end through
   the real centre.
5. **`OperationCenterSummary.swift` is a new file the design's table does not list**, and three test
   suites were split for the same reason: SwiftLint's `file_length` / `type_body_length` bounds.
   Task 17.1 requires a split rather than a suppression, and that rule was followed every time.
6. **`ConfirmationBox` lives in `OperationCenterBulk.swift`**, beside the confirmation surface it
   serves, rather than in `OperationCenter.swift` which was already at the 400-line bound.

## Issues found

1. **A task expectation that was simply wrong, corrected rather than papered over.** Task 11.1 listed
   `$(…)` and `;` among names that must be "rejected at construction". They are **not** rejected:
   `MutationName.isSafe` refuses exactly "empty, leading `-`, or containing whitespace", and the
   `package-mutation` delta says PM9 is untouched — so widening the shared gate would change package
   construction rules the delta explicitly preserves. The guarantee that actually holds is the one the
   threat matrix names: **argv is a vector**. `Process.arguments` is handed the name as one literal
   element and no shell is ever involved, so `$(whoami)` reaches brew as a service name that does not
   exist. The test now asserts that, **through the real process seam**, rather than asserting a
   rejection that would have been security theatre.
2. **`brew services start` on an already-running service does not register it at login.** Found while
   obtaining MV-3: starting a service that "Run once" had already started took brew's already-started
   branch and left `~/Library/LaunchAgents` empty. MV-3 must therefore be run from a **stopped**
   service — as `tasks.md` already says — or it reports a false negative about the start/run
   distinction. Recorded because a reader running the check out of order would draw the wrong
   conclusion.
3. **A stale SwiftPM incremental build produced a wrong-case enum result.** Inserting `.noChange` into
   the middle of `MutationOutcome` shifted the case tags, and one `swift test` run reported a draft
   recorded as `.cancelled` coming back as `"noChange"`. The mapping was correct; a re-run was green
   and has stayed green, including under a full `xcodebuild test`. **After inserting a case into a
   public enum, re-run before believing a failure** — it cost twenty minutes of chasing a defect that
   did not exist.
4. **The `forcesReSnapshot` scope guard cannot reach zero, and that is correct.** Task 17.2 asks for
   zero matches. `Sources/` and `cellar/` are at zero. One match survives in
   `MutationGatesTests.swift:255`, and it is the assertion **that the member is gone** — a guard
   cannot forbid a name without naming it. Recorded as the single deliberate exception rather than
   quietly weakening the guard's wording.
5. **A spec/design discrepancy this phase did not resolve on its own authority.** The shipped verbs
   are `serviceStart`/`serviceRun`/`serviceStop`/`serviceRestart` (design D9, task 13.4, namespaced so
   an IH5 search cannot collide with a package verb). The `installation-history` delta's IH1 sc5 text
   says the verbs are `start`, `stop`, `restart`, `run`. Both readings satisfy every IH5 scenario,
   because the namespaced form still matches a case-insensitive `stop` search and the service's name
   is found through the argv either way. Implementation follows the design; **the delta text needs
   reconciling**, and that is recorded in `follow-ups.md` rather than decided here.

## Manual verification — what was and was not obtained

Task 16.1 is **reserved for the orchestrator/user and remains unchecked**. Everything obtained is
recorded in full inside `tasks.md` under 16.1, with the actual observed bytes. In summary, on brew
**6.0.15** (newer than the 6.0.14 the design probed), with the machine restored to its exact baseline
afterwards:

| Check | Status |
|---|---|
| **MV-3** discriminator | **OBTAINED live.** `run` leaves `~/Library/LaunchAgents` empty; `start` from stopped creates `homebrew.mxcl.atuin.plist`. The GUI half — enumerating five controls and clicking them — is not obtainable |
| **MV-4** classification | **OBTAINED live for all four clicks.** All four markers confirmed byte-for-byte, and both no-op cases genuinely exit **0**. The Activity-drawer labels need the GUI |
| **MV-5** data half | **OBTAINED.** `log_path == error_log_path` on this machine, so the dedupe rule is load-bearing on day one. The pane needs the GUI |
| **MV-11** byte half | **OBTAINED on the services path.** 0 ESC bytes pinned, 3 under the old key. The drawer half needs the GUI |
| **MV-1, MV-2 (a)(b)(d), MV-6, MV-7, MV-8, MV-9, MV-10, MV-12** | **NOT obtained.** Every one needs a human to click something or read a window. MV-9 additionally requires a temporary fixture patch that must not be committed, so it was deliberately not attempted |

Nothing above is claimed as covered that was not. This is the M2-3 IH6 lesson applied.

## Next

`sdd-verify`. All 17 implementation phases are complete; the only outstanding task is 16.1, which is
the user's to run and which now has a written record of exactly which halves are already answered.

---

## Batch 1 — the read half, Phases 0–7 (preserved verbatim)

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

### Batch 1's "Next" — now discharged

`sdd-apply` again for Phase 8 onward (the control half). Do **not** run `sdd-verify` yet: Phases 8–17
are untouched, and Phase 17's full gate and Phase 16's manual checks are scoped to the whole change.

Two notes the next batch must carry:

- `ServiceCommand` must be expressed **over the existing `ServiceTarget`**, not redeclare it.
- `ServicesRefreshCoordinator` already has the seam Phase 14 needs; the terminals consumer and the
  `isMutating` suppression are genuinely absent, not faked.
