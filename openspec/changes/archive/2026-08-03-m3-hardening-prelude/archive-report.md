# Archive report: m3-hardening-prelude

**Change**: `m3-hardening-prelude` — M3 slice **M3-0** ("Hardening Prelude"), the **first** of the
five slices in the M3 plan accepted in Engram `#7127`. Ten defect fixes and no feature: three of them
live spec violations, one with a data-integrity tail, all of them sitting exactly where M3-1 is about
to restructure the mutation spine. This slice closes the project's **oldest open defect** (the
`CatalogStore` adoption ordinal, opened at M2-0 and carried by three consecutive slices) and every
one of the six native-review findings M2-3 routed forward.

**Closed**: 2026-08-03 · **Artifact store**: hybrid (OpenSpec files + Engram, project
`swiftui_cellar`)
**PRD milestone**: **M3 — Services, Cleanup & Taps.** This change opens M3; it ships no M3 feature
and no new capability. Four feature slices remain (M3-1 … M3-4).
**Status at close**: shipped and merged to `main`. SDD cycle complete — **34/34 tasks**, zero open
CRITICAL findings, zero cut items, drop-first order never exercised.

This report is the terminal record of the cycle. Where it disagrees with `tasks.md`,
`apply-progress` (`#7135`) or `verify-report.md` (`#7137`), those are intermediate snapshots and
**this report states the final state**.

## Final state

| Fact | Value at close |
|---|---|
| Delivery | Single PR **#7** — <https://github.com/juancasanueva/SWIFTUI_cellar/pull/7> (`feature/m3-hardening-prelude` → `main`), merged by the user |
| `main` at close | **`3d55ed3`**, working tree clean |
| Branch head at merge | **14 commits**: **12 apply commits** (`47034c5..cfb70ae`), the task-9.1 manual-evidence commit, and the verify-report + W1-reconcile commit **`12540da`** |
| Tasks | **34 of 34** checked in the archived `tasks.md`, including the orchestrator-reserved **9.1**. **No stale checkbox and no archive-time reconciliation was performed** |
| Task 9.1 (manual verification) | **EXECUTED** by orchestrator + user on 2026-08-03 against a Debug build — **all four steps PASS**, with two honestly-scoped partials recorded rather than papered over (below). Evidence verbatim in the archived `tasks.md` and Engram `#7136` |
| Verify verdict | **PASS_WITH_WARNINGS** (validator-admitted on the **first** attempt, `evidence_revision sha256:8ed3a79c…`) — **0 CRITICAL**, **4 WARNING**, **4 SUGGESTION**; **5/5** requirements, **24/24** scenarios |
| Tests (package) | **571** `@Test` in **77** suites — `swift test --package-path Packages/CellarCore`, exit 0, **1 pre-existing deliberate known issue** (`OperationCenterCancelTests.swift:183`). Baseline on `main` @ `3562cd1`: 555 / 73 → **+16 tests, +4 suites, zero deletions** |
| Build | `xcodebuild build … -scheme cellar` → `** BUILD SUCCEEDED **`, zero concurrency warnings (only the pre-existing `appintentsmetadataprocessor` note, which is not a compiler diagnostic) |
| Lint | `swiftlint --quiet` = **60** findings, byte-identical to the 0.1 baseline — **zero new**. Every modified and new file under the 400-line `file_length` limit (largest: `BrewRunner.swift` 365) |
| Native review | Lineage **`review-fa82e5eaa3023fc4`** — **approved with receipt**. Base-diff `main..feature/m3-hardening-prelude`, **35 files / 2,515 ledger lines**, medium risk → single review-reliability lens, correction budget 200 (**unused**): **0 blockers / 2 WARNING / 2 SUGGESTION** |
| Gates | `pre-push` and `pre-pr` both validated **allow** against that receipt (`--base-ref origin/main`) |
| Candidate size | `git diff main...HEAD --shortstat` = **1,915** changed lines; the attempt **ledger's own accounting = 2,018** against the 2,000 cap. The user accepted a **small `size:exception`** (~2,400 effective) to cover the verify report |
| Delivery strategy | `single-pr` under that late, user-accepted `size:exception`. **No item was dropped** — the planned drop-first order (#7, then #8, never #4) was never exercised |
| Design gates | **Zero blocking gates.** The design carried D1–D9 with no probe gate; the M3 probe gates U1–U8 block M3-1 and later, not this slice |

### The budget was crossed by bookkeeping, not by scope

The forecast band was ~1,480–1,930 against the session's 2,000, and the **code** landed inside it:
apply measured 1,899 at its last commit and verify re-measured **1,915** by `git shortstat`. What
crossed the line was the attempt ledger's own accounting, which counts SDD bookkeeping edits the
`shortstat` figure does not and reached **2,018**. The verify report itself (~300 lines) then had to
land inside whatever headroom remained, and there was none.

**Calibration for M3-1 and after**: forecast against the **ledger's** number, not `git shortstat` —
on this slice the ledger ran ~6% higher, and on M2-3 the candidate ran ~40% above the authored
forecast. A slice planned to land *exactly* at the cap will cross it during verification, because the
verify report is itself part of the candidate. Leave the report's own ~300 lines in the budget from
the start.

## Native review receipt gate

| Lineage | Candidate | Outcome |
|---|---|---|
| **`review-fa82e5eaa3023fc4`** | base-diff `main..feature/m3-hardening-prelude`, head **`12540da`** — 35 files / 2,515 ledger lines, medium risk, single review-reliability lens | **Approved with receipt.** 0 BLOCKER / CRITICAL, **2 WARNING / 2 SUGGESTION**, correction budget 200 **unused** (no refuter, no correction transaction). Verification evidence captured (571 tests / 77 suites green + `BUILD SUCCEEDED`) |

`reviewGate.result: allow`; the `pre-push` and `pre-pr` gates both validated allow against that same
receipt, and PR #7 merged at `3d55ed3`. **The archive gate is satisfied — nothing was overridden and
no reviewer was relaunched at archive time.**

The reviewer did not merely fail to object; it **positively verified** all ten fixes, and those
verifications are worth carrying because each one closes a plausible objection to the shipped design:

- the catalog ordinal guard is **race-free** — `CatalogStore` is `@MainActor` and the check-then-assign
  sequence has no suspension point;
- **begin/end pairing is structurally sound** — every `ActivityItem` is constructed only inside
  `submit`, so no path reaches a terminal outcome outside the `finish` funnel;
- the fabricated success is **unrepresentable**, not merely avoided — `.unknownOperation` is decided
  *before* the stderr scan, so no fault classification can re-derive a success from it;
- `LocalStores` genuinely shares one container (`===` identity) and folds an open failure into both
  stores;
- `NoteDraft` distinguishes **nil from empty**, so an emptied note clears rather than being ignored;
- `InstalledSections` partitions with an exhaustive `if / else-if` chain, so no entry can be
  double-counted across sections.

No `sdd/m3-hardening-prelude/review/{transaction,ledger,receipt,gate-context}` Engram topics exist.
Review authority was read from the repository CAS receipt for lineage `review-fa82e5eaa3023fc4` as
recorded in Engram `#7138`, following the M2-1, M2-2 and M2-3 precedent.

All four review findings are **registered as follow-ups** below. None contradicts a scenario.

## Snapshot claims explicitly superseded by this report

| Snapshot claim | Source | Final state |
|---|---|---|
| "**33/34 tasks complete**. Only 9.1 remains — orchestrator-reserved, deliberately unchecked" | `apply-progress` `#7135` | **34/34.** Task 9.1 was executed on 2026-08-03 by orchestrator + user against a Debug build; all four steps PASS. Evidence in the archived `tasks.md` and Engram `#7136` |
| "**Not pushed.**" / no PR | `apply-progress` `#7135` | Pushed and merged as PR **#7**; `main` at close is **`3d55ed3`** |
| "Branch `feature/m3-hardening-prelude` @ **`d41dc95`**, 13 commits, **unpushed**" | `verify-report` `#7137` | Verified head only. The final branch head is **`12540da`** and the branch carried **14** commits. The verify report and the W1 tasks.md reconciliation landed in that same commit |
| "**1,880** changed lines … no `size:exception` is needed" | `tasks.md` 9.3, as first written | **Superseded in-place during verification** (W1): re-measured **1,915** by `git shortstat`, **2,018** by the ledger, and a small `size:exception` (~2,400 effective) was accepted. The archived `tasks.md` carries a `[Superseded 2026-08-03, verify W1]` note recording exactly this — the reconciliation happened **before** archive, not at archive time |
| "**13 commits** vs planned 10" (verify SUGGESTION 1) | `verify-report` `#7137` | **12 apply commits** (`47034c5..cfb70ae`) plus the 9.1 evidence commit and `12540da` = **14 on the branch**. The "13" was the count at the verified head, before the report's own commit |
| "`git shortstat` = **1,899 / 2,000** … ~100 lines of headroom remain for the verify report" | `apply-progress` `#7135` | The headroom did not survive the report. Final: 1,915 by `shortstat`, 2,018 by ledger, exception accepted |
| Verify W4: "manual 9.1(a) before-launch `stat` not captured" | `verify-report` `#7137` | **Still true and deliberately not resolved** — see "Two honest partials" below. This is the one snapshot claim this report **confirms** rather than supersedes |

### Two honest partials, recorded rather than resolved

Both were planned scopings, both were re-affirmed at close, and neither is a defect:

1. **9.1(a) — one container at launch.** The before-launch `stat` was not captured (the app was
   launched before the task's exact steps were read). What *was* observed after the session: exactly
   **one** `.store` file exists (`fd -e store` count 1, `stat` `451684779 1785735401 90112`), and
   star + note + mutation + History all worked in one session with no "could not be opened" reason,
   surviving relaunch. The one-container **rule** is proven headlessly by `LocalStoresTests >
   oneContainerServesBothStores`, which asserts object identity on the container itself. The manual
   step confirms the *wiring*; the rule never depended on it.
2. **9.1(d) — failed-clear inline surface.** Forcing a SwiftData delete to throw is not reliably
   reachable through the UI, so only the reachable half was observed: Clear presents a confirmation
   with **no blocking alert and no retry control**. The failure path's runtime evidence is the
   headless seam tests (4.1 / 4.2). The tasks file said this would be partial *before* it was run,
   and the verify report stated the partiality rather than claiming full manual coverage.

**Every RED anchor was independently re-proven.** Verify copied only the new test files into a
scratch worktree at `main` and re-ran them: `drafts.count → 0 == 1`, `packageCount → 2 == 3`,
`indexBuildCount → 2 == 1`, `→ 3 == 1`, matching `apply-progress` byte for byte. The other four new
tests are compile-error RED — `unknownOperation`, `clearing:`, `InstalledSections` and `NoteDraft`
all return zero matches in `Sources/` on `main`. The TDD claim is evidence here, not assertion.

### Deviations from design/tasks — six, all assessed benign by verify

| # | Deviation | Why it is benign |
|---|---|---|
| 1 | **12 apply commits, not the planned 10** | The SDD artifacts were untracked on `main` and had to enter the branch somewhere; a dedicated `docs(sdd)` commit preserves 0a's and 0b's exact rollback boundaries. M2-3's precedent folded them into the first feature commit — this is cleaner |
| 2 | **Item #6's classification test landed in a new `UnknownOperationTests.swift`**, not `ClassificationTests.swift` as the design's table named | Adding it there pushed that struct to 259 lines and raised a **new** `type_body_length` finding, which the zero-new-findings gate forbids. RED was observed in **both** locations before the GREEN branch existed |
| 3 | **Both stores' `container` widened `private` → internal** (design D6 named only `MetadataStore.init(unavailable:)`) | Without it, "one container, both stores" is *inferred* rather than asserted; the widening is what lets the test assert `===` identity. Nothing became public |
| 4 | **16 new test functions, not the forecast 14** | The relocation in deviation 2 plus one added `NoteDraft` starting-state test |
| 5 | **Task 8.1's probe emptied the reader rather than using a wrong filename** | The stronger of the two failure modes: a wrong filename already throws out of `String(contentsOf:)`, whereas an emptied source is exactly the "over-eager comment strip" the design named — and it used to pass all four negative assertions silently |
| 6 | **`m3-services-cleanup-taps/explore.md` purged from branch history via `git filter-branch`** | See "Archive integrity" — the file is intact on disk and deliberately outside this candidate |

**No deviation is contract drift.** Each either implements a spec clause the design under-specified,
or was forced by a `tasks.md` gate the design did not anticipate.

## Specs merged (source of truth updated)

Five MODIFIED deltas, **zero ADDED, zero REMOVED, zero RENAMED**, and **zero new capabilities** — the
capabilities contract the proposal declared was met exactly. Every replacement is a **strict
superset**: each keeps its original body paragraphs and all its original scenarios verbatim, and
appends.

| Domain | Action | Details | Final totals |
|---|---|---|---|
| `catalog-sync` | **Amended** | **1 MODIFIED** requirement replaced as a whole block (+1 scenario) — "A snapshot is adopted exactly once, in order". 13 / 39 → **13 / 40**. The other twelve untouched | **13 / 40** |
| `operation-activity` | **Amended** | **1 MODIFIED** (+1 scenario) — "Every terminal outcome records exactly one history entry". 6 / 22 → **6 / 23**. The other five untouched | **6 / 23** |
| `installation-history` | **Amended** | **1 MODIFIED** (+2 scenarios) — "Clear history is a single confirmed all-or-nothing action". 7 / 21 → **7 / 23**. The other six untouched | **7 / 23** |
| `brew-execution` | **Amended** | **1 MODIFIED** (+1 scenario) — "Terminal result and exit handling". 6 / 19 → **6 / 20**. The other five untouched | **6 / 20** |
| `installed-inventory` | **Amended** | **1 MODIFIED** (+1 scenario) — "Multi-select is explicit, ordered, and offered only for bulk-eligible verbs". 14 / 54 → **14 / 55**. The other thirteen untouched | **14 / 55** |
| `local-package-metadata`, `package-mutation`, `package-detail`, `package-search`, `brew-detection` | **Untouched, deliberately** | No delta named them; **none was opened for writing at archive time** | 7 / 21, 9 / 34, 6 / 17, 7 / 19, 5 / 17 |

### Main specs after this archive — ten capabilities, 80 requirements, 269 scenarios

| Capability | Requirements | Scenarios | Last changed by |
|---|---|---|---|
| `brew-detection` | 5 | 17 | m2-catalog-hardening (M2-0) |
| `brew-execution` | 6 | **20** | **m3-hardening-prelude (M3-0)** |
| `catalog-sync` | 13 | **40** | **m3-hardening-prelude (M3-0)** |
| `installation-history` | 7 | **23** | **m3-hardening-prelude (M3-0)** |
| `installed-inventory` | 14 | **55** | **m3-hardening-prelude (M3-0)** |
| `local-package-metadata` | 7 | 21 | m2-local-metadata-history (M2-3) |
| `operation-activity` | 6 | **23** | **m3-hardening-prelude (M3-0)** |
| `package-detail` | 6 | 17 | m1-catalog-browse (M1) |
| `package-mutation` | 9 | 34 | m2-local-metadata-history (M2-3) |
| `package-search` | 7 | 19 | m2-catalog-hardening (M2-0) — **PS4 untouched across all of M2 and now M3-0** |
| **Total** | **80** | **269** | |

Requirement count is **unchanged at 80** — this slice added no requirement, only tightened five.
Scenario count **263 → 269** (+6), matching the delta set exactly (1 + 1 + 2 + 1 + 1).

**Merge method**, following the M1, M2-0, M2-1, M2-2 and M2-3 precedent: requirement and scenario
text copied **verbatim** from the delta files; the delta-only `(Previously: …)` annotations dropped
from the requirement bodies and their substance recorded in each spec's `## Provenance`; every
requirement not named in a delta left untouched.

**No destructive delta was merged** — the repo's `rules.archive` requires a warning before one, and
none was needed. **Zero archive reconciliations were required this cycle**: every promoted
requirement and scenario is byte-identical to its delta, and verify raised no spec-wording finding.

**Four resolved follow-ups were struck through in the promoted specs rather than deleted**, so the
audit trail of what was wrong survives beside the text that fixed it: M2-3's W1 (`operation-activity`),
W2 (`installation-history`), S1 (`brew-execution`) and S2 (`installed-inventory`). Two **new** review
findings were written into the promoted specs as implementation notes — finding (a) into
`installation-history` and finding (c) into `installed-inventory` — because each is a behaviour or
coverage observation against text that is itself correct. Every scenario in all five amended
capabilities is COMPLIANT.

## What shipped

Ten fixes, no feature. Each one is now pinned by a named test that was proven RED first.

- **The catalog adopts by revision, not by arrival** (`catalog-sync`). "Newer" is the snapshot's
  `revision.ordinal` — materialization order, already monotonic — and deliberately **not** a
  `fetchedAt` timestamp, so no new state was introduced. One guard makes the `adoptedRevision =`
  assignment unreachable for an older snapshot, which closes both halves the proposal named: an older
  snapshot no longer installs over a newer one, **and** the adopted-revision record no longer
  regresses and disarms the newer snapshot's deduplication. `adoptionSequence` / `installedSequence`
  stay — they guard build *completion*, not arrival (D2). Equal ordinal keeps the join-a-duplicate
  contract byte-for-byte. **This closes M2-0 #1 / M2-2 #12, the oldest open defect in the project**,
  which two consecutive archive reports had asked in writing be closed standalone.
- **A submit with no runner records exactly one history entry** (`operation-activity`). `gate?.begin()`
  is hoisted **above** the runner guard and the no-runner branch routes through `finish(item, with:
  .launchFailed)` — the single idempotent settle site — so there is one `begin()` per submit and one
  `end()` per finish. The universal exactly-one-entry rule was kept with **no carve-out** (settled Q4)
  and the implementation made to honour it, which is the invariant M3-1 inherits when it generalizes
  `submit`.
- **A failed Clear History stays observable** (`installation-history`). `clearAll()` now calls
  `reload()` **first** and applies `availability = .unavailable(reason:)` and `lastError` **after** —
  reloading afterwards was the bug itself. The failure branch is reachable in the `swift test` loop
  through an injected `init(container:clearing:)` closure, deliberately **not** a filesystem-permission
  fake (D5), which would have been flaky. Inline surface only: no alert, no retry (settled Q1).
- **One `ModelContainer`, injected into both stores** (no spec delta; design D6). `LocalStores` opens
  a single `PersistenceContainer.onDisk(at:)` and injects it into `MetadataStore` and `HistoryStore`,
  folding an open failure into **both** stores' `.unavailable(reason:)` so they cannot disagree about
  why the store is unreadable. `cellarApp` shrinks to three lines, and **M3-1's services store joins
  here rather than opening a third container** — which is precisely why this had to land before a
  services feature. The only fix in the slice with a data-integrity tail, and the one the drop-first
  order protected absolutely.
- **A note draft commits before the package switches** (no spec delta; design D7). The rule moved out
  of the view into a pure `NoteDraft` value (`starting(from:)` / `pendingWrite(against:)`, `nil` = owes
  nothing) that distinguishes **nil from empty**, so an emptied note clears rather than being ignored.
  The view commits against the `onChange(of: entry.id)` closure's **`oldValue`** — the only place the
  departing package's identity still exists, since `stored` already reads the new one. A switch is
  navigation, not cancel (settled Q2). The doc comment claiming an `onSubmit` commit was **corrected**:
  a multiline `TextEditor` has no `onSubmit`, so that comment described a mechanism that could not
  exist.
- **An unknown operation yields a typed unknown result** (`brew-execution`). `case unknownOperation`
  went **inside** the `BrewExit.Reason` declaration — a Swift enum case cannot be added in an
  extension, so the design's sketch was invalid Swift and was not copied literally — with
  `BrewExit.unknownOperation = BrewExit(status: -1, reason: .unknownOperation)`. `-1` cannot collide
  with a wait status (0–255) or a signalled `128+n`, and because `isSuccess` is `reason == .exited &&
  status == 0`, **the fabricated success is now unrepresentable by construction**. It stayed a
  **value**, never a throw — `exit(of:)` reaches ~30 call sites through `BrewOperation.exit()` — and
  maps to the **existing** `MutationOutcome.launchFailed`, so no new outcome case, message or
  `summaryLabel` churn.
- **A bulk selection enters in displayed order** (`installed-inventory`). `InstalledSections`
  (`outdated` / `selfUpdating` / `rest` + `displayed`) is **one projection read twice** — the view's
  three `Section`s render from it and `reconcileOrder` maps over it — so rendering and selection order
  cannot drift again. Section titles are unchanged, and the scenario deliberately does not enumerate
  them: the section set belongs to the view and has already changed once.
- **The display-only structural scan can no longer pass vacuously** (test integrity). A positive
  anchor (`#expect(source.contains("HistoryEntry"))`) precedes the four negative assertions, and the
  anchor was **proven to bite**: with the reader forced to return `""`, the amended test failed with
  one issue per scanned file, where the unamended version passed all four negative assertions
  silently. Probe reverted.
- **`.timeLimit(.minutes(1))`** on the catalog adoption suite (M2-0 #4) — whole minutes only;
  `.seconds(30)` traps at runtime. Establishing the habit before M3-1 adds a polling loop and M3-3 a
  cancellable traversal, both of which are test-hang shapes.
- **Housekeeping**: `openspec/config.yaml` now declares `review_budget_lines: 2000` at `:7` **and**
  says `2,000` in the `:59` prose, so no future `sdd-tasks` guard line cites a budget nobody uses; and
  `openspec/changes/m2-mutations-installed/` — the last M2 artifact living outside `archive/` — moved
  to `openspec/changes/archive/2026-08-03-m2-mutations-installed/` as a clean `R100` rename, with the
  `openspec/specs/installed-inventory/spec.md:547` citation repointed to the archive path (path text
  only, not a spec delta).

**All nine routed follow-ups are CLOSED** — M2-2 #12 / M2-0 #1, W1, W2, W3, W4, S1, S2, VS1 and
M2-0 #4 — exactly the bundle the M3 umbrella exploration's §5 assigned to the prelude. That is the
third consecutive slice where routing a review finding to the change that makes it reachable paid
off, and the first where a *whole* routed bundle closed in one slice.

## Follow-up register (15 open, none blocking)

**(a)–(d)** are the four findings from native review lineage `review-fa82e5eaa3023fc4`. The rest are
inherited from the M2-3 register with their M3 umbrella §5 verdicts unchanged. Nothing here blocks
the archive; every one of them sits against spec text that is correct as written.

| # | Follow-up | Source | Routed to |
|---|---|---|---|
| **(a)** | **A failed clear's reason is erased by the next reload.** The history search field reloads the projection on every keystroke (`didSet`), and that reload sets `availability` back to `.available` while `lastError` survives — so the availability half of the surface can be cleared by an unrelated interaction. **Introduced by this slice's own fix** and deterministic. The requirement binds the reason to "the projection reload that **follows the attempt**", which the delivery satisfies, so no scenario is violated — the gap is that a reader may expect the reason to persist until acknowledged | review WARNING | **M3-1 — top absorption candidate**, as a fix *or* as a deliberate spec clarification of how long the reason must live |
| **(b)** | **A note draft is still lost on view TEARDOWN.** Only focus-loss and `entry.id` triggers exist; there is no `onDisappear` commit, so deselecting the package or leaving the detail view still drops an uncommitted draft. **Pre-existing** — this slice fixed the *switch* case, which was the one W4 named | review WARNING | **M3-1**, or the next slice that opens Browse |
| **(c)** | **The app-target `reconcileOrder` expression is unproved by an automated test.** `InstalledSectionsTests` composes the reconciliation in-test rather than calling the app-target function. The ordering *rule* is fully proven headless; the wiring rests on `xcodebuild build` plus manual 9.1(c) | review SUGGESTION | folds into the **VS3** ruling |
| **(d)** | **Two note-commit triggers could double-fire on one switch** — focus loss and the `entry.id` change may both fire for a single package switch. **Inferential** (not observed) and **pre-existing**; the write is idempotent against the same stored value, so no data loss is implied | review SUGGESTION | unassigned |
| **M3-0 VS2** | **D1's "byte-for-byte" equal-ordinal claim holds only while equal ordinal implies equal revision.** True today by construction, but it is an unstated invariant of `CatalogSnapshotRevision` rather than an asserted one | verify SUGGESTION | unassigned — assert it, or state it in the type |
| **VS2** (M2-3) | `OperationCenter.pendingConfirmation` widened to `public internal(set)`; a small `ConfirmationBox` type would restore `private(set)` | M2-3 verify SUGGESTION | **Absorb into M3-1** — it rewrites the confirmation surface anyway (cleanup and `untap --force` both need it) |
| **M2-2 #6** | A mutation's own post-terminal FSEvents echo costs one redundant `brew info --installed` (~3 s later). Conforming, not a defect | M2-2 register | **Absorb into M3-1** — the same code and the same design question as the typed `InvalidationScope` |
| **M2-2 #7** | Duplicate submission of the same command is accepted and runs to a benign outcome. Permitted by design | M2-2 register | **Absorb narrowly into M3-1** — a start/stop toggle is a button users double-click; ship a services-scoped guard, leave the general dedup rule deferred |
| **M2-2 #9** | The sudo signature set is unprobed against a live sudo-requiring path | M2-2 register | **Absorb into M3-1** — probe gate **U5** makes it safely reachable for the first time |
| **VS4** (M2-3) | `HistoryDraft.date` is `Date()` at the terminal, not an injected clock. Nothing is flaky today | M2-3 verify SUGGESTION | **Absorb into M3-1 if needed** — it introduces a clock-driven poll loop; add the additive `clock:` seam then rather than reaching for `Date()` again |
| **VS3** (M2-3) | App-target UI carries residual risk with **no** automated coverage; `cellarUITests` exists but is skipped. M3 adds four more untested surfaces, and finding (c) is a fresh instance | M2-3 verify SUGGESTION | **Explicit ruling required in M3-1's proposal**: accept planned manual evidence again, or fund a small harness as its own slice. Standing one up inside a feature slice is how feature slices overrun |
| **M2-2 #8** | Carry `standardInput` through `ProcessSpec` so "standard input is never interactive" is testable at the recording seam | M2-2 register | **Deferred** — but gate **U5** may change this verdict: if a root-domain service start *hangs* rather than failing, stdin observability stops being cosmetic |
| **M2-2 #10** | `skippedRecordCount` is never surfaced — decode tolerance is silent | M2-2 register | **Deferred, and do not solve it for one decoder** — M3 adds three more tolerant decoders, each with its own skipped count |
| **M2-2 #13** | Catalog hardening bundle: M2-0 #5–#7, M1 #4/#5 — poisoned-snapshot recovery gated on staleness; undelivered engine-side zero-package guard; latency test via the synchronous initialiser; payload size cap; unwired `payloadByteLimit` | inherited | **Deferred** — no M3 coupling; belongs in a catalog slice or M5 |
| **M2-1 #8 / #9** | `DetectionTests` display-name prose, `InstalledRefreshTests` count assertion | inherited | **Deferred** — test-prose nits, untouched since M2-1 |

### Inherited register — status at this close

| Item | Status |
|---|---|
| M2-2 #12 / M2-0 #1 — `CatalogStore` adoption ordinal stamps on call arrival | **CLOSED** — revision-ordered guard, specified in `catalog-sync` and pinned by two named tests. **The project's oldest open defect is closed** |
| M2-3 W1 — no-runner submit writes no history entry | **CLOSED** — routed through `finish()`, specified in `operation-activity` |
| M2-3 W2 — failed Clear History silently masked | **CLOSED** — reload-then-apply, specified in `installation-history`. Note that follow-up **(a)** is a *narrower successor*, not a reopening: the reason now survives the attempt's own reload, but not an arbitrary later one |
| M2-3 W3 — two `ModelContainer`s over one store file | **CLOSED** by `LocalStores`; `===` identity asserted headlessly |
| M2-3 W4 — uncommitted note draft lost on package switch | **CLOSED for the switch case** by `NoteDraft` + commit-against-`oldValue`. Follow-up **(b)** carries the *teardown* case, which W4 did not name |
| M2-3 S1 — `exit(of:)` fabricates `BrewExit(status: 0)` for an unknown id | **CLOSED** — typed `.unknownOperation`, specified in `brew-execution` |
| M2-3 S2 — bulk multi-add appends in flat inventory order | **CLOSED** by `InstalledSections`; the comment's claim is now requirement text **and** the code honours it |
| M2-3 VS1 — structural scan can pass vacuously | **CLOSED** — positive anchor added and proven to bite |
| M2-0 #4 — unbounded watcher loop, no `.timeLimit` | **CLOSED** — `.timeLimit(.minutes(1))` on the adoption suite |
| M2-3 VS2, VS3, VS4; M2-2 #6, #7, #8, #9, #10, #13; M2-1 #8/#9 | **Still open** — deferred or routed as above, unchanged by this slice |

**Two closures are partial by scope and are recorded as such rather than as clean kills**: W2's
successor is (a), and W4's successor is (b). Neither successor is the original finding, and neither
was introduced carelessly — (a) is a consequence of the fix's chosen surface, and (b) is a case the
original finding never named.

## M3 slice plan — status

Plan accepted 2026-08-03 (Engram `#7127`); umbrella exploration `#7126`, file at
`openspec/changes/m3-services-cleanup-taps/explore.md`.

| # | Slice | Forecast | Status |
|---|---|---|---|
| **M3-0** | `m3-hardening-prelude` | 900–1,500 (delivered ~1,915 by `shortstat`) | **ARCHIVED 2026-08-03 — this report** |
| **M3-1** | `m3-services` | 2,600–3,400 · needs `size:exception` | **NEXT** — blocked on the pre-propose requirements below |
| M3-2 | `m3-taps` | 1,700–2,300 · borderline | not started |
| M3-3 | `m3-disk-usage` | 2,800–3,800 · needs `size:exception` | not started |
| M3-4 | `m3-cleanup` | 2,400–3,200 · needs `size:exception` | not started |

### Required before `sdd-propose m3-services` (M3-1)

**1 — Close four probe gates.** U1, U2 and U6 are **CLOSED** and U7 is **partial** (Engram `#7128`).
Still open:

| Gate | Question | Why it blocks M3-1 |
|---|---|---|
| **U3** | Non-empty `brew autoremove -n` output shape | Blocks the **M3-4** parser, not M3-1 — but it is captured in the same session. Zero orphans existed locally, so the parser has no ground truth |
| **U4** | Do `brew cleanup -n` / `autoremove -n` take Homebrew's lock? | If yes they are `.mutate`, not `.read`, and every preview queues behind an in-flight install — a materially different UX. **M3-4**, resolve before its proposal |
| **U5** | `brew services start` on a **root-domain** service with stdin `/dev/null`: fail fast, hang, or sudo signature? | **M3-1 blocking.** PRD §4.2 forbids privilege escalation and `SystemProcess` hard-wires `standardInput = .nullDevice`. Also the only safe reachable probe for M2-2 #9, and may flip M2-2 #8's verdict |
| **U8** | `brew services start` on an **already started** service — idempotent success or non-zero? | **M3-1 blocking** — it decides the outcome classification for the most common repeated user gesture. Requires actually starting a service; coordinate with the user |

Re-measure **U7** (Caskroom / cache `du` and inode count were truncated) in the M3-3 design session.
`du -sk /opt/homebrew/Cellar` = 1.5 s / ~3.9 GB says traversal is affordable but must still be
off-main, cancellable and cached.

**2 — Settle three product questions**, none of which should be allowed to ship by default:

1. **Do service toggles write history rows?** `installation-history` IH1 says *every* mutation Cellar
   submits writes exactly one entry, and the funnel writes **by construction** — so silence here means
   "toggle a service ten times, get ten rows" ships without anyone deciding it. Either IH1 is modified
   to define the non-package verb vocabulary and null-package form, or IH3 gains an explicit carve-out.
2. **Poll cadence and its visibility gate.** Suggested **5 s while visible, never while hidden** —
   stop on disappear, not merely slow down. Record it as settled rather than leaving a magic number.
3. **The VS3 ruling** — manual evidence again (with the manual checks *planned*, given M2-3's IH6
   CRITICAL and this slice's finding (c)), or fund a UI-test harness as its own slice.

**3 — Two architectural decisions M3-1 owns**, both flagged in the umbrella §6 and deliberately
**not** pre-built by this slice (the scope guard verified zero `BrewMutating`, `InvalidationScope`,
`ServiceCommand`, `TapCommand` or `CleanupCommand` symbols exist):

- **Generalize the command to a `BrewMutating` protocol** rather than adding cases to
  `MutationCommand`. Only the protocol route keeps `package-mutation` PM1 ("exactly six mutating
  commands") **literally true** with zero spec edit.
- **Replace the unconditional re-snapshot with a typed `InvalidationScope`.**
  `MutationOutcome.forcesReSnapshot` is hardcoded `true`, so a `services start` would otherwise pay a
  1.27 s / 663 KB inventory probe for a change that touches no installed package. This **MODIFIES
  PM6** — write that delta deliberately. The invariant that must survive: every terminal outcome still
  owes exactly one refresh of whatever it *does* invalidate, including cancelled and failed ones.

**One trap worth restating**: `installed-inventory` II13 sc4 proves exhaustively over
`BulkSelection.Action.allCases` that exactly two bulk verbs exist. A "stop all services" multi-select
must be a **new type over a new entity** — extending that enum breaks a shipped scenario.

## Archive integrity

- **`tasks.md` is fully checked (34/34)**, including the orchestrator-reserved 9.1. No checkbox was
  altered at archive time and no stale-checkbox reconciliation was performed or needed. The one
  in-place supersession in that file — 9.3's candidate-size note — was written **during verification**
  (W1) and committed in `12540da`, not at archive time. **Archive classification: clean** — zero open
  CRITICAL findings, zero blockers, no gate overridden, no partial archive.
- **Zero archive reconciliations.** Every promoted requirement and scenario is byte-identical to its
  delta.
- **Five capabilities were never opened for writing**: `local-package-metadata`, `package-mutation`,
  `package-detail`, `package-search`, `brew-detection`. They stay byte-identical.
- **The scope guard held.** 33 changed files, none matching `Package.swift`, `project.pbxproj`, or any
  services / taps / cleanup / disk-usage path; no new SPM target; zero M3-1 symbols anywhere in
  `Sources/` or `cellar/`; `forcesReSnapshot` absent from the `MutationOutcome.swift` diff (PM6
  untouched); the delta set exactly five MODIFIED with zero ADDED / REMOVED / RENAMED.
- **`openspec/changes/m3-services-cleanup-taps/explore.md` is NOT tracked in git, and that is a real
  risk worth naming.** It was swept into the branch twice by `git add -A` and purged with
  `git filter-branch --index-filter`; the path now sits in `.git/info/exclude`. Including it would
  have put the candidate at ~2,475 lines. The file is **intact on disk and untracked**, so the M3
  umbrella exploration — the single investigation all four remaining slices propose from — currently
  survives only as that working-tree file plus Engram `#7126`. **It should be adopted into `main` in
  its own dedicated commit under its own review receipt**, exactly as `86e2216` adopted the M2
  umbrella, before M3-1 starts.
- **The branch history was rewritten** (verify SUGGESTION 3). It was unpushed at the time, so the
  rewrite was safe; any pre-existing local copy of `feature/m3-hardening-prelude` needs a hard reset
  rather than a merge. The branch is merged and this is now history.
- **Verify was admitted on the first attempt**, unlike M2-3, which required a FAIL → remediation →
  re-admission cycle. No CRITICAL was raised at any point in this cycle.

Verification evidence: `evidence_revision sha256:8ed3a79c…`;
`test_output_hash sha256:c934ddd2…`; `build_output_hash sha256:7f3cae20…`; admitted by
`gentle-ai sdd-verify-validate --requirements 5 --scenarios 24` (`valid: true`,
`verdict: pass_with_warnings`).

## Artifact traceability

| Artifact | Engram observation | OpenSpec file (archived) |
|---|---|---|
| M3 umbrella exploration | `#7126` `sdd/m3-services-cleanup-taps/explore` | `openspec/changes/m3-services-cleanup-taps/explore.md` — **untracked on disk**, see Archive integrity |
| M3 slicing decision (five slices, prelude first) | `#7127` `sdd/m3-services-cleanup-taps/slicing` | (Engram only) |
| probe gates U1/U2/U6 closed, U7 partial | `#7128` `sdd/m3-services-cleanup-taps/probe-gates` | (Engram only) |
| proposal | `#7129` `sdd/m3-hardening-prelude/proposal` | `proposal.md` |
| product decisions Q1–Q6 settled (inline clear failure, silent note commit, one entry for unknown ops, displayed bulk order, revision-ordered "newer", archive folder naming) | `#7130` `sdd/m3-hardening-prelude/product-decisions` | (Engram only) |
| spec (5 MODIFIED deltas) | — no Engram topic; **the files are the artifact** | `specs/{catalog-sync,operation-activity,installation-history,brew-execution,installed-inventory}/spec.md` |
| design | — no Engram topic; mirrored by the design gate below | `design.md` (D1–D9) |
| spec + design gate (counts verified on disk, four hallucination spot-checks VERIFIED, three orchestrator reconciliations applied inline) | `#7133` `sdd/m3-hardening-prelude/design-gate` | (Engram only) |
| tasks | `#7134` `sdd/m3-hardening-prelude/tasks` (index + forecast mirror; **the file wins on any divergence**) | `tasks.md` — **34/34**, includes 9.1's verbatim manual evidence and 9.3's superseded size note |
| apply-progress | `#7135` — **"33/34", "not pushed" and the 1,899-line headroom claim all superseded by this report** | (Engram only) |
| task 9.1 manual verification (all four steps PASS, two honest partials) + the `size:exception` acceptance | `#7136` `sdd/m3-hardening-prelude/manual-9-1` | evidence table inside `tasks.md` |
| verify-report | `#7137` `sdd/m3-hardening-prelude/verify-report` — **its head/commit-count and "unpushed" claims are stale; W1's size figures were reconciled into `tasks.md` in the same commit as the report** | `verify-report.md` |
| native review (lineage, positive verifications, four findings, CLI evidence-capture sequence) | `#7138` `sdd/m3-hardening-prelude/review` | (Engram only) |
| delivery | `#7139` `sdd/m3-hardening-prelude/delivery` — **"PR #7 open" superseded by the merge at `3d55ed3`** | (Engram only) |
| archive-report | `sdd/m3-hardening-prelude/archive-report` | this file |
| project checkpoint (updated at this close: **M2 complete + M3-0 archived; next M3-1**) | `cellar/project-checkpoint` (supersedes `#7062`) | (Engram only) |

**No `sdd/m3-hardening-prelude/spec` or `/design` Engram topic exists.** In hybrid mode the files are
authoritative for both, and the design gate `#7133` is the Engram-side record of what they contain.
This is recorded so a future auditor does not read the absence as a missing artifact.

**The `verify-report.md` digest is part of the audit trail.** It is preserved because the change
folder is moved into this archive with a byte-preserving `git mv` in the same commit that adds this
report — no artifact was re-transcribed.

## Next

**M3-0 is closed. The next slice is M3-1 — `m3-services`**: the `BrewMutating` generalization with
services as its first consumer, the typed `InvalidationScope`, `services list --json` and
`services info --json` sources plus `ServicesStore`, a visibility-gated poll loop on `LoopOwner`, the
four verbs (start / stop / restart / run) with per-service fan-out, and the Services view with log and
plist paths.

Four things to do before `sdd-propose m3-services`:

1. **Adopt `m3-services-cleanup-taps/explore.md` into `main`** in its own dedicated commit under its
   own review receipt. It is the investigation all four remaining slices propose from and it is
   currently untracked.
2. **Close probe gates U5 and U8** (both M3-1 blocking), and capture U3/U4 in the same session.
3. **Settle the three product questions** — service-toggle history rows, poll cadence, the VS3 ruling.
4. **Accept the `size:exception` before apply starts**, not during verification. This slice's one
   avoidable friction was discovering the overrun at the ledger gate; M3-1 is forecast at 2,600–3,400
   against a 2,000 budget and will need one from the outset.
