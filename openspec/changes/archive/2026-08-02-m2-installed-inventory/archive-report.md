# Archive report: m2-installed-inventory

**Change**: `m2-installed-inventory` — M2 slice **M2-1** ("Installed Inventory") of the four-slice
M2 plan accepted in Engram `#7065`. Adds the whole "what do *I* have, what needs updating?"
capability: a new `BrewClient` target, one `brew info --installed --json=v2` probe, the installed
list, browse installed-state filters, FSEvents-driven freshness, and app-lifetime loop ownership.
**Closed**: 2026-08-02 · **Artifact store**: hybrid (OpenSpec files + Engram, project
`swiftui_cellar`)
**Status at close**: shipped and merged to `main`. SDD cycle complete — **60/60 tasks**, zero
CRITICAL findings, zero cut phases.

This report is the terminal record of the cycle. Where it disagrees with `tasks` (#7085),
`apply-progress` (#7086) or `verify-report` (#7089), those are intermediate snapshots and **this
report states the final state**.

## Final state

| Fact | Value at close |
|---|---|
| Delivery | Single PR **#4** — <https://github.com/juancasanueva/SWIFTUI_cellar/pull/4> (`feature/m2-installed-inventory` → `main`), merged by the user |
| Merge commit | **`0fc2739`** on `main` |
| Branch head at merge | **`86e2216`** (verified tree `2a10c64` + post-verify correction `ecf56e3` + umbrella `explore.md` adoption) |
| Tasks | **60 of 60** checked in the archived `tasks.md`. **No cut phase, no stale checkbox, no reconciliation performed at archive time** |
| Task 10.1 (manual FSEvents) | **EXECUTED and PASSED** post-apply, evidence table in `tasks.md` — install leg and uninstall leg each produced **exactly one** debounced refresh; `brew upgrade` leg a consented skip |
| Tests (package) | **345** `@Test` in **47** suites — `swift test --package-path Packages/CellarCore`, exit 0 (baseline on `main` @ `ebac63d`: 243 / 36 → **+102 tests, +11 suites, zero deletions**) |
| Tests (app scheme) | `xcodebuild test … -skip-testing:cellarUITests` → `** TEST SUCCEEDED **`, exit 0 |
| Verify verdict | **PASS WITH WARNINGS** — 0 blockers, **0 CRITICAL**, 3 WARNING, 5 SUGGESTION; **15/15** requirements, **50/50** scenarios COMPLIANT, each mapped to a named test that passed at runtime |
| Verify warning 1 | **RESOLVED** post-verify in commit **`ecf56e3`** (task 10.2's lint record corrected). See "Snapshot claims superseded" |
| Native review | **two approved lineages, both with receipts** — `review-bbe42e6b3e7d13e7` (branch diff) and `review-6fb3404d57900709` (umbrella `explore.md` adoption) |
| Gates | `pre-commit`, `pre-push`, `pre-pr` all validated **allow** |
| Authored diff | **4,918** changed lines (production 2,122 / tests 2,531 / fixtures 265), excluding `openspec/` artifacts |
| Delivery strategy | `single-pr` under a user-accepted **widened `size:exception`** (Engram `#7087`) |
| Attempt ledger | `apply` and `verify` both settled **`passed`**, with **two maintainer resets** recorded (line-cap rulings, not defects) |

### The size overrun, and what it teaches

The forecast was 2,400–2,800 authored lines; the change delivered **4,918**. Production landed
essentially on forecast (2,122 against ~1,550 for source + app + manifest). **The overrun is almost
entirely test volume**: 2,531 lines against ~900 forecast, plus a 265-line fixture, because strict
TDD demanded a RED per scenario, both threat-matrix rows got their own named suites, and three
concurrency invariants (detection request key, store ordinal guard, coordinator suppression and
window extension) were **mutation-verified** rather than assumed.

The pre-agreed remedy (cut Phases 6+7 to a second PR) was recorded in `tasks.md` and deliberately
**not applied**: the session brief pinned `single-pr`, and the cut is not a clean prefix — Phases 6+7
sit between 5 and 8, and Phase 9's `cellarApp.swift` depends on `LoopOwner` and
`InstalledRefreshCoordinator`. The user accepted the widened exception instead of the surgery.

**Forecasting correction, carried forward**: under strict TDD with a RED per scenario plus mutation
verification, budget tests at **~1.2× production**, not the ~0.85× this change assumed.

## Native review receipt gate

| Lineage | Candidate | Outcome |
|---|---|---|
| **`review-bbe42e6b3e7d13e7`** | The branch diff vs `origin/main` — 53 paths / ~6,800 lines, medium risk, reliability lens | **Approved.** 0 blockers, **4 WARNING / 3 SUGGESTION**, all M2-2-relevant robustness gaps (see follow-ups 1–7). This is the governing receipt for the code |
| **`review-6fb3404d57900709`** | Workspace candidate: the untracked umbrella `openspec/changes/m2-mutations-installed/explore.md` (209 lines, medium risk, reliability lens) | **Approved.** 2 WARNING / 4 SUGGESTION. The file was then staged and committed at `86e2216` under that receipt |

`reviewGate.result: allow` on both lineages; `pre-commit`, `pre-push` and `pre-pr` all validated
allow against the same receipts. The archive gate is satisfied — nothing was overridden.

**Process lesson recorded** (from lineage `review-6fb3404d57900709`): the `pre-commit` gate projects
the **staged index**, so a receipt for intended-untracked paths returns `scope-changed` against an
empty index and validates only once those paths are staged. M2-0's lesson was "clean the workspace
before a delivery review"; M2-1's is its complement — an *adopted* untracked file must be staged
before its own gate can pass.

## Snapshot claims explicitly superseded by this report

| Snapshot claim | Source | Final state |
|---|---|---|
| "59/60 tasks; only `10.1` remains unchecked, deliberately, for the orchestrator" | `tasks` #7085, `apply-progress` #7086 | **60/60.** Task 10.1 was executed by the orchestrator on a Debug build at `5ffdf3d` against live brew 6.0.14 and **passed**; its verbatim evidence table is in the archived `tasks.md` and in Engram `#7088` |
| "`brew upgrade` leg of 10.1 deliberately not run" — listed as WARNING 3 | `verify-report` #7089 | Still true and still deliberate (consent scope: upgrading 12 outdated formulae including `node@22` exceeded the consented mutation). Coalescing of a multi-write mutation into one refresh **is** evidenced by the install leg (12 files written over ~1 s → one refresh) |
| "Lint record in task 10.2 / apply-progress is inaccurate … Correct `tasks.md` before archive" — WARNING 1 | `verify-report` #7089 | **RESOLVED before archive**, in commit **`ecf56e3`**. `tasks.md` 10.2 now records `nesting` (`InstalledWire.swift:43`) and `function_parameter_count` (`FSEventsInstalledObserver.swift:159`, signature fixed by the C FSEvents API) as **NEW with this change**, not pre-existing. Neither is a defect |
| "Branch … 8 commits `b8967e9..5ffdf3d`, **not pushed**" | `tasks` #7085 | Pushed and merged as PR #4 at `0fc2739`. The archived `tasks.md` commit trail lists the seven phase-aligned commits |
| "Branch/head `feature/m2-installed-inventory` @ `2a10c64`" | `verify-report` #7089 | Verified head only. Two commits followed: `ecf56e3` (warning-1 correction) and `86e2216` (umbrella `explore.md` adoption). Neither touched `Sources/` or `Tests/` |
| "Untracked strays … `openspec/changes/m2-mutations-installed/`. Exclude before the PR" — SUGGESTION | `verify-report` #7089 | **Superseded by a deliberate decision.** `explore.md` was reviewed on its own lineage, **adopted and tracked** at `86e2216`, and **stays in place** — it belongs to the still-open M2 umbrella and is *not* part of this archive. `default.profraw` remains a workspace stray |
| "Verify attempt settle blocked on trivial ledger overage (report = 345 lines vs 300 cap) — pending maintainer reset" | verify outcome #7090 | Reset granted. Both `apply` and `verify` attempts settled **`passed`**; two maintainer resets (line-cap rulings) are recorded in the ledger |
| Proposal / design **D11**: "`appleSilicon → native`, `intelCarryOver → rosettaCarryOver`" rename | `proposal` #7080, `design` #7083 | **The rename was a code no-op, and D11's arrow is written backwards.** The source has always used `.appleSilicon` / `.intelCarryOver` (`rg 'rosettaCarryOver\|BrewPrefix\.native'` over the repo returns nothing). The S1 drift was **spec-side only** and is closed by the `brew-detection` merge below. Phase 1 therefore cost ~0 lines instead of the forecast ~90 |

No unrankable contradiction was found between the launch prompt's final-state facts and the
repository or higher-ranked artifacts.

## Specs merged (source of truth updated)

| Domain | Action | Details |
|---|---|---|
| `installed-inventory` | **Created** `openspec/specs/installed-inventory/spec.md` | **11 ADDED** requirements / **34 scenarios** promoted verbatim from the ADDED-only delta. New capability; nothing modified, removed or renamed |
| `brew-detection` | **Amended** `openspec/specs/brew-detection/spec.md` | **4 MODIFIED** requirements replaced as whole blocks / 16 scenarios. "Absent brew is a soft signal" untouched. 5 / 15 → **5 requirements / 17 scenarios** |
| `package-search` | **Untouched, deliberately** | PS4 "Filters answerable from the catalog alone" stays byte-identical; composition happens above the index. Verified at verification time by `git diff --exit-code` = 0 against `main`, and no commit after `2a10c64` touched the file. The file was not opened for writing at archive time |

Merge method, following the M1 and M2-0 precedent: requirement and scenario text copied **verbatim**
from the delta files; the delta-only `(Previously: …)` annotations were dropped from the requirement
bodies and their substance recorded in `## Provenance`; every requirement not named in a delta was
left untouched. Counts live in the provenance bullets, since the main specs carry no count header.

Two things the `brew-detection` merge deliberately preserves: the requirement **title** "Rosetta
prefix is fully supported, advisory only" and the word "Rosetta" in prose, because the advisory
itself is `Advisory.rosettaPrefix` in code and is already aligned. Only the two `BrewPrefix` case
names changed.

The `brew-detection` provenance now records that **both** M2-0-routed items are closed: the S1
vocabulary nit (documentation only) and the `configuredPath` `didSet` stale-join gap (a real
behaviour change, delivered as a request-keyed slot plus an ordinal publication guard at
`BrewDetectionStore.swift:73` and `:93`). The `installed-inventory` provenance carries three
implementation/verification notes rather than spec edits, because in each case the requirement text
is already correct: the `installed_as_dependency` over-generalisation, the M2-2-latent mutation-gate
and `clear(to:)` gaps, and the app-target binding coverage boundary.

## What shipped

- **New `BrewClient` target** — the only place that sees both `BrewProcess` and `Catalog`,
  one-directionally. CS1 is now enforced *structurally* by the package graph and guarded by a
  negative-control test that parses `Package.swift` (`Tests/CatalogTests/PackageGraphTests.swift`).
- **One probe, self-sufficient inventory** — `brew info --installed --json=v2` via
  `BrewCommand.read`, drained by a thin adapter over a pure `payload(from:exit:)`, decoded
  `@concurrent` off the main actor into an immutable `Sendable` `InstalledInventory`. Outdated,
  pinned, on-request, install dates and the self-updating "newer version exists" signal are all
  **derived from that one payload** — no second spawn.
- **Asymmetric decode via two wire types** (an apply-time refinement of the design's "two
  `init(from:)`"): the formula/cask asymmetry is expressed in the type system. Multi-keg formulae
  keep every keg.
- **`InstalledStore`** — request-keyed single flight (keyed by `installation.executableURL`) plus a
  monotonic ordinal publication guard; last good inventory survives a failure. Added a
  `refresh(for: BrewDetectionState)` overload because `refresh(using: BrewInstallation?)` cannot
  distinguish "never installed" from "your configured path is not executable", which II9 sc2 requires.
- **`BrewDetectionStore` request-keyed fix** (scope delta reconciled into this change, Engram
  `#7084`) — closes M2-0 follow-up #2. The RED reproduced the defect exactly; both the key and the
  ordinal were mutation-verified.
- **Freshness** — `InstalledChangeObserving` seam, `FSEventsInstalledObserver` (recursive FSEvents;
  `DispatchSource` would miss every upgrade), and `InstalledRefreshCoordinator` with a 2 s quiet
  window on an injected `Clock`, mutation suppression, and a baseline (launch + activation) refresh
  that works with **no observer attached at all**. Zero `@unchecked Sendable` in `Sources/BrewClient/`.
- **`LoopOwner`** — app-lifetime, idempotent-per-id loop ownership. Closes M1 follow-ups **#8** and
  **#9**: closing the founding window no longer cancels the refresh loops, and the event stream is
  never re-subscribed.
- **Browse composition + Installed UI** — `InstalledFilterMode` resolution rule lives in `BrewClient`
  (so it is RED-first testable in the fast loop) while the picker stays in the app target;
  `SearchFilters`, `PackageSearchIndex` and `package-search/spec.md` are byte-identical. Installed
  sidebar section, dependency toggle (default off), a separate "Updates itself" group, and
  brew-absent read-only guidance.

Beyond the design's File Changes table, three additive files were justified at verification:
`Tests/CatalogTests/PackageGraphTests.swift` (task 1.1 mandates it),
`Sources/BrewClient/InstalledPresentation.swift` + test (wording moved *down* out of the app target
to match `CatalogPresentation`, gaining fast-loop coverage), and `cellar/Browse/PackageRow.swift`
(row takes a `PackageEntry` so an installed package with no catalog record still renders).

**All 11 apply deviations were validated at verification as non-spec-breaking.**

## Follow-up register (16 open, none blocking)

Carried forward. Items 1–7 come from branch review `review-bbe42e6b3e7d13e7`, 8–10 from verify
SUGGESTIONs, 11–16 from the docs review of the umbrella `explore.md`
(`review-6fb3404d57900709`) and are owed **to that file**, not to this archive.

| # | Follow-up | Source | Routed to |
|---|---|---|---|
| 1 | **Catalog filter controls are inert under the `installed` / `outdated` Browse modes** — those modes source rows from the inventory, so the catalog-side filter UI silently does nothing | review WARNING | M2-2 |
| 2 | **A change signal during an in-flight acquisition joins the pre-change probe**, so the resulting inventory can predate the event that triggered it | review WARNING | M2-2 |
| 3 | **The mutation gate is not re-checked after an already-open quiet window elapses** — a mutation starting mid-window is not suppressed. **Latent until M2-2 drives `isMutating`** | review WARNING | M2-2 |
| 4 | **`clear(to:)` while a refresh is in flight strands the acquisition** — `brewAbsent` can stick even after a valid installation returns | review WARNING | M2-2 |
| 5 | **Unreachable `Task.isCancelled` guards in the debounce path** — dead code, or a missing cancellation edge | review SUGGESTION | unassigned |
| 6 | **`FSEventsInstalledObserver.changes()` is not idempotent** — a second call does not return an equivalent stream | review SUGGESTION | unassigned |
| 7 | **`skippedRecordCount` is never surfaced** — decode tolerance is silent to the user | review SUGGESTION | unassigned |
| 8 | **Two `DetectionTests` display names still say "native" / "Intel prefix"** while spec and code standardise on `appleSilicon` / `intelCarryOver`. Assertions are correct; only prose lags | verify SUGGESTION | unassigned |
| 9 | **`InstalledRefreshTests > baselineRecordsTheInstallation` should pin `installations.count == 2`** next to its `allSatisfy` | verify SUGGESTION | unassigned |
| 10 | **`TestClock` is now a *third* copy.** M2-0 D5's `CellarTestSupport` extraction (M2-0 follow-up #3, proposal defect #10) is still owed and grew. **Schedule before M2-2 adds a fourth** | verify SUGGESTION + M2-0 #3 | before M2-2 |
| 11 | `explore.md`'s **`installed_as_dependency` negative claim is over-generalised** — the field EXISTS and this change's own fixture models it 7×; `installed_on_request == false` is a correct *fallback* derivation, not an equivalence. Correct the claim, keep the derivation | docs review WARNING | `explore.md` |
| 12 | `explore.md`'s **pin read path needs an `UNVERIFIED` marking** | docs review WARNING | `explore.md` |
| 13 | `explore.md` **follow-up #6 carries a Defer/Prelude verdict conflict** | docs review SUGGESTION | `explore.md` |
| 14 | `explore.md` **cites stale `project.pbxproj` line numbers** | docs review SUGGESTION | `explore.md` |
| 15 | `explore.md` **states superseded facts in the present tense and has no as-of anchor** | docs review SUGGESTION | `explore.md` |
| 16 | `explore.md` **six-slice arithmetic slip** | docs review SUGGESTION | `explore.md` |

### Inherited register — status at this close

| Item | Status |
|---|---|
| M2-0 #2 — `BrewDetectionStore.configuredPath` `didSet` stale join | **CLOSED by this change** (request-keyed slot + ordinal guard) |
| M1 #8 / #9 — refresh-loop scene ownership, event-stream reattach | **CLOSED by this change** (`LoopOwner`) |
| M2-0 #1 — `CatalogStore` adoption ordinal stamps on call arrival | **Still open.** This change copied the *recipe* into `InstalledStore` but touched no `Sources/Catalog/` production code, so the catalog-side one-line guard is still owed |
| M2-0 #3 — `CellarTestSupport` + cancellation-aware `TestClock` | **Still open**, now item 10 above |
| M2-0 #4, #5, #6, #7 | **Still open, unassigned** — unbounded watcher loop / no `.timeLimit`; poisoned-snapshot recovery gated on staleness; undelivered engine-side zero-package guard; latency test builds via the synchronous initialiser |
| M1 #4 / #5 — payload size cap, `payloadByteLimit` unwired | **Still deferred** |

## Artifact traceability

| Artifact | Engram observation | OpenSpec file (archived) |
|---|---|---|
| M2 slicing decision | `#7065` | (Engram only) |
| product decisions (Q1–Q4 settled) | `#7079` | (Engram only) |
| proposal | `#7080` `sdd/m2-installed-inventory/proposal` | `proposal.md` |
| cask-outdated live probe (design gate, RESOLVED) | `#7081` | (Engram only) |
| spec (2 deltas) | `#7082` `sdd/m2-installed-inventory/spec` | `specs/{installed-inventory,brew-detection}/spec.md` |
| design | `#7083` `sdd/m2-installed-inventory/design` | `design.md` |
| spec↔design reconciliation (D6 scope delta included) | `#7084` | (Engram only) |
| tasks | `#7085` `sdd/m2-installed-inventory/tasks` — **"59/60" superseded by this report** | `tasks.md` (authoritative checklist, 60/60) |
| apply-progress | `#7086` `sdd/m2-installed-inventory/apply-progress` — **"59/60" and "not pushed" superseded** | (Engram only) |
| apply settlement (widened `size:exception`) | `#7087` | (Engram only) |
| task 10.1 manual FSEvents verification PASSED | `#7088` | evidence table inside `tasks.md` |
| verify-report | `#7089` `sdd/m2-installed-inventory/verify-report` — **WARNING 1 resolved after it was written** | `verify-report.md` |
| verify outcome | `#7090` | (Engram only) |
| delivery (two review lineages, gate lessons) | `#7091` `sdd/m2-installed-inventory/delivery` | (Engram only) |
| archive-report | `sdd/m2-installed-inventory/archive-report` | this file |

No `sdd/m2-installed-inventory/review/{transaction,ledger,receipt,gate-context}` Engram topics
exist; review authority was read from the repository CAS receipts for lineages
`review-bbe42e6b3e7d13e7` and `review-6fb3404d57900709`, as recorded in `#7091`.

Verification evidence:
`evidence_revision sha256:7b64b398fca0f2232b73983afdb40d23f5a9c9319dcbaeff1daf3db54a52ff91`;
`test_output_hash sha256:4acd7ccc…`; `build_output_hash sha256:effb98d3…`; `verify-report.md`
`sha256:59e297797ae4a4a6d26f9fec00902449bfda6fc2b28e8970c01308dbdf0e7060`, admitted by
`gentle-ai sdd-verify-validate --requirements 15 --scenarios 50` (`valid: true`) before any write.

## Archive integrity

- **`tasks.md` is fully checked (60/60).** No checkbox was altered at archive time and no
  stale-checkbox reconciliation was performed or needed. **Archive classification: clean** — zero
  CRITICAL findings, zero blockers, no gate overridden, no partial archive.
- **`openspec/changes/m2-mutations-installed/explore.md` is NOT part of this archive.** It was
  adopted and tracked at `86e2216` and stays in place: it is the still-open M2 umbrella exploration,
  and follow-ups 11–16 above are owed to it.
- **Pending mechanical step, owed to the orchestrator**: the five phase artifacts (`proposal.md`,
  `design.md`, `tasks.md`, `verify-report.md`, `specs/installed-inventory/spec.md`,
  `specs/brew-detection/spec.md`) still sit at `openspec/changes/m2-installed-inventory/` and must be
  moved here with a **byte-preserving `git mv`**. The archive executor had no shell tool available
  and deliberately did **not** hand-copy them: `verify-report.md`'s recorded
  `sha256:59e29779…` is part of the audit trail, and a transcription would have broken it. This
  report was written directly at its archive path; every merged spec change below it is already
  applied.

  ```
  git mv openspec/changes/m2-installed-inventory/* \
         openspec/changes/archive/2026-08-02-m2-installed-inventory/
  rmdir openspec/changes/m2-installed-inventory
  ```

## Next

`m2-mutations-installed` — M2 slice **M2-2**, which adds install/uninstall/upgrade mutations, the
queue and the activity UI. It inherits follow-ups 1–4 above (all four become reachable the moment a
real mutation drives `isMutating`), and should absorb follow-up 10 (`CellarTestSupport`) *before* it
adds a fourth `TestClock` copy.
