# Archive report: m2-local-metadata-history

**Change**: `m2-local-metadata-history` — M2 slice **M2-3** ("Local Metadata & History"), the
**fourth and last** slice of the M2 plan accepted in Engram `#7065`. Cellar could read and mutate
Homebrew but forgot everything it did: no favorite, no note, no snooze, no record. This change adds
the versioned persistence spine — a `Persistence` SPM target with a SwiftData `VersionedSchema` V1
and a migration plan from day one — plus the four PRD §3.2 surfaces built on it (favorites, notes,
version-scoped snooze, installation history), ordered bulk multi-select with per-package fan-out, and
the six M2-2 follow-ups that only became reachable once mutations shipped.

**Closed**: 2026-08-03 · **Artifact store**: hybrid (OpenSpec files + Engram, project
`swiftui_cellar`)
**PRD milestone**: **M2 — Mutations & Installed. This change CLOSES M2.** See "M2 exit criteria"
below for the clause-by-clause status.
**Status at close**: shipped and merged to `main`. SDD cycle complete — **90/90 tasks**, zero open
CRITICAL findings, zero cut phases.

This report is the terminal record of the cycle. Where it disagrees with `tasks.md`,
`apply-progress` (#7119) or `verify-report.md` (#7121), those are intermediate snapshots and **this
report states the final state**.

## Final state

| Fact | Value at close |
|---|---|
| Delivery | Single PR **#6** — <https://github.com/juancasanueva/SWIFTUI_cellar/pull/6> (`feature/m2-local-metadata-history` → `main`), merged by the user |
| Merge commit | **`66af57c`** on `main` |
| Branch head at merge | **15 commits** on `main` @ `8c9bc2a`: **7 apply run-1** (`0db02fc..b10e1c6`), **5 apply run-2** (`095dd2c..eb62dbb`), the 9.2 manual-evidence commit **`743e739`**, the IH6 declined-clear evidence commit **`3bf14fd`**, and the verify report **`0c873d0`** |
| Tasks | **90 of 90** checked in the archived `tasks.md`. **No cut phase, no stale checkbox, no reconciliation performed at archive time** |
| Task 9.2 (manual verification) | **EXECUTED** by orchestrator + user on 2026-08-03 against a running app and live brew — **all four checks PASS**, plus the (d-addendum) declined-clear observation that closed the verify CRITICAL. Evidence verbatim in the archived `tasks.md:488-505` and Engram `#7120` |
| Verify verdict | **PASS_WITH_WARNINGS** (validator-admitted, `evidence_revision sha256:dba16789…`) — **0 CRITICAL** (1 raised and resolved same day), **1 WARNING** (size overrun, pre-accepted), **4 SUGGESTION**; **25/25** requirements, **101/101** scenarios |
| Tests (package) | **555** `@Test` in **73** suites — `swift test --package-path Packages/CellarCore`, exit 0, **1 deliberate known issue** (task 3.5's harness proving it *fails* rather than traps). Phase 0 baseline on `main` @ `8c9bc2a`: 432 / 56 → **+123 tests, +17 suites, zero deletions** |
| Tests (app scheme) | `xcodebuild test … -skip-testing:cellarUITests` → `** TEST SUCCEEDED **`; `xcodebuild build …` → `** BUILD SUCCEEDED **` |
| Lint | `swiftlint` **60 violations / 6 serious — byte-identical to the `main` baseline, zero new findings**, and no finding in any file this change created. Every changed `.swift` under the 400-line limit (largest: `BrewRunner.swift` 363, `PackageDetailView.swift` 336, `OperationCenter.swift` 318) |
| Native review | Lineage **`review-e07590a04c4aff38`** — **approved with receipt**. Base-diff `main..feature/m2-local-metadata-history`, **68 files / 9,018 lines**, medium risk → single review-reliability lens, correction budget 200 (**unused**): **0 blockers / 4 WARNING / 2 SUGGESTION** |
| Gates | `pre-push` and `pre-pr` both validated **allow** against that receipt |
| Authored diff | **6,425** changed lines (6,106 insertions + 319 deletions), excluding `openspec/` artifacts — **~1.19× the top of the 4,000–5,400 forecast band** |
| Delivery strategy | `single-pr` under the user-accepted **`size:exception`**, accepted **before** apply started |
| Design gates | G1 closed pre-apply by live probe (`#7116`); **G2 upsert / G3 on-disk open / G4 `@MainActor` holder all answered GREEN on the real target** in Phase 0 — **no fallback path was taken**; G5 settled by user ruling (`#7117`) |

### The forecast overran, and the reason is worth carrying

Forecast 4,000–5,400 authored lines; delivered **6,425**. M2-2 was the first slice to land inside its
band, and this one did not. The overrun is concentrated in **tests for a brand-new target with a new
framework**: `Persistence` had no in-repo scaffolding to calibrate against, and the tasks' own
forecast named that as unpriced residual (a). The `PackageTarget` retype — unpriced residual (b) —
cost 56 mechanical call-site edits against an estimated 40–60, so that estimate held.

**Calibration for M3**: the ~1.2× tests-to-production multiplier is sound for *familiar* layers and
was sound again here for `BrewProcess`/`BrewClient`; it under-prices a first slice on a **new
framework**. Budget a new-framework target at roughly **1.5×** production until one slice of real data
exists for it.

## Native review receipt gate

| Lineage | Candidate | Outcome |
|---|---|---|
| **`review-e07590a04c4aff38`** | base-diff `main..feature/m2-local-metadata-history`, base tree `74722f5` / candidate tree `7c24b3c` (= head `0c873d0`) — 68 files / 9,018 lines, medium risk, single review-reliability lens | **Approved with receipt.** 0 blockers, **4 WARNING / 2 SUGGESTION**, correction budget 200 unused (no refuter, no correction transaction). Verification evidence captured (555 tests / 73 suites green + `BUILD SUCCEEDED`). Receipt at `.git/gentle-ai/review-transactions/v2/review-e07590a04c4aff38/review-receipt.json` |

`reviewGate.result: allow`; the `pre-push` and `pre-pr` gates both validated allow against that same
receipt, and PR #6 merged at `66af57c`. **The archive gate is satisfied — nothing was overridden and
no reviewer was relaunched at archive time.**

All six review findings are behaviour observations in the app-composition and execution-edge layers,
none of them contradicted by a scenario. All six are **registered as follow-ups** below.

No `sdd/m2-local-metadata-history/review/{transaction,ledger,receipt,gate-context}` Engram topics
exist. Review authority was read from the repository CAS receipt for lineage
`review-e07590a04c4aff38` as recorded in Engram `#7123`, following the M2-1 and M2-2 precedent.

**Stray lineage, recorded so it cannot mislead an auditor**: an accidental empty-workspace lineage
`review-9be9e201c4e8266c` was produced by a CLI flag probe and finalized harmlessly approved. Its
receipt binds only the **empty** snapshot and **cannot gate this branch**. The branch's authority is
`review-e07590a04c4aff38` and nothing else.

## The verify CRITICAL: raised, remediated, re-admitted

The first admitted verify verdict for this change was **FAIL**, on exactly one finding: IH6's
scenario "Declining deletes nothing" had **no covering test and no recorded manual observation** — the
only one of 101 scenarios with neither form of runtime evidence. The verifier's own first draft
attempted `pass_with_warnings` and the native validator **rejected it** ("passing verdict contradicts
failing or incomplete evidence"), which is the gate working as designed.

Remediation followed the report's own prescribed option (a), the cheaper and more faithful one for a
UI-only affordance: the user performed the observation in the real app — one Cellar-submitted history
row present, Clear history dialog opened, **Cancel** pressed, the row remained — recorded in
`tasks.md` 9.2 (d-addendum), commit **`3bf14fd`**. The report was updated truthfully (IH6 →
COMPLIANT, 101/101, **original finding preserved verbatim in the report**) and re-admitted:
`gentle-ai sdd-verify-validate --requirements 25 --scenarios 101` → `valid: true`,
`verdict: pass_with_warnings`, `evidence_revision sha256:dba16789…` **unchanged**, because **no source
changed between the two admissions — the delta is evidence, not implementation**.

**This is why the archive gate is satisfied without an override**: there is no open CRITICAL. The
CRITICAL existed, was closed by producing the missing evidence, and the verification was re-run
through the validator rather than asserted.

## Snapshot claims explicitly superseded by this report

| Snapshot claim | Source | Final state |
|---|---|---|
| "**89 / 90 tasks complete**; the one unchecked task is 9.2, deliberately reserved for the orchestrator" | `apply-progress` #7119, `tasks` | **90/90.** 9.2 was executed on 2026-08-03 by orchestrator + user against live brew, all four checks PASS, evidence in `tasks.md:488-505` and Engram `#7120` |
| "**Nothing pushed.**" / no PR | `apply-progress` #7119 | Pushed and merged as PR **#6** at **`66af57c`**. Final branch head `0c873d0` |
| "**Commits (11)** … (11 change commits on top of `8c9bc2a`)" | `apply-progress` #7119 | **12 apply commits**, not 11 — the artifact's own enumerated list runs 1–12 (7 in run 1, 5 in run 2) and contradicts its own header. The branch carried **15** commits in total once 9.2 evidence (`743e739`), the IH6 addendum (`3bf14fd`) and the verify report (`0c873d0`) landed |
| "**IH6 'Declining deletes nothing' is UNTESTED** — CRITICAL; incomplete scenario evidence cannot support a passing verdict" | `verify-report` initial admission (FAIL) | **RESOLVED the same day** by the prescribed manual observation (commit `3bf14fd`), scenario evidence 101/101, re-admitted `pass_with_warnings`. The archived `verify-report.md` preserves the original finding as history under a `[RESOLVED 2026-08-03]` marker — that is the audit trail, not an open item |
| "**Compliance summary: 100 / 101 scenarios COMPLIANT … 1 UNTESTED**" | `verify-report.md` line 197 | **101 / 101 COMPLIANT.** This summary line was **not updated** when IH6 was re-marked COMPLIANT during re-admission; it contradicts the same file's own IH6 matrix row, its YAML header (`scenarios: 101/101`) and its verdict section. The archived file is preserved byte-for-byte with the inconsistency intact; **this report is where the correction lives** |
| "Branch / head `743e739` (13 commits)" | `verify-report.md` | Verified head only. Two commits followed — `3bf14fd` (IH6 evidence) and `0c873d0` (the report itself) — neither changing production behaviour. Final: 15 commits |
| "67 files changed, 8,370 insertions, 324 deletions = 8,694 changed lines including `openspec/`" | `verify-report` WARNING 1, measured at `743e739` | **68 files / 9,018 lines** at the final candidate `0c873d0`, per the native review receipt. The authored figure excluding `openspec/` (**6,425**) is unchanged between the two heads — the delta is artifacts only |
| "`swiftlint` … 184 files (151 at baseline)" | `verify-report.md` | Not a regression: the file count rose only because `.build/` DerivedSources were present in the verify run. Violation counts are byte-identical to baseline (60 / 6) and every tail violation is in generated `resource_bundle_accessor.swift` |

### The deviation-count discrepancy, resolved by subject rather than by ordinal

`apply-progress` #7119 enumerates **nine** deliberate deviations from design (five from run 1, four
from run 2). The verify report assesses **six**, and the launch prompt names those same six. This is
the same shape of discrepancy M2-2's archive recorded, and here it **is resolvable from the documents
themselves** — the six verify assessed match apply's items **1, 3, 6, 7, 8 and 9** textually:

| Verify # | Deviation | apply-progress # |
|---|---|---|
| 1 | `BrewRunner` retention cap injectable, shipped default 200 | 1 |
| 2 | `naming(_:_:)`'s closure parameter is `(PackageTarget) -> MutationCommand` | 3 |
| 3 | `ActivityItem` gained `versions: VersionTransition?` | 6 |
| 4 | `OperationCenter.swift` split at 408 lines into `OperationCenterBulk.swift` | 7 |
| 5 | `cellar/Browse/PackageMetadataSection.swift` is a new file | 8 |
| 6 | `confirm(_:)` returns `[ActivityItem]` rather than `ActivityItem?` | 9 |

The three apply items verify did not enumerate separately are **2** (compaction also runs on the
unresponsive-cancel path), **4** (`PackageMetadata` + `MetadataSnapshot` landed in Phase 4 rather than
Phase 5) and **5** (`SchemaV1` grew from one placeholder model to three inside V1 — not a migration,
because V1 never shipped). Each is an intra-plan sequencing or implementation note rather than a
divergence from a design contract. **Verify never explicitly declared those three out of scope**, so
that reading is recorded as the most likely one, not asserted as fact. A future reader should match
deviations **by subject, never by ordinal**.

**What is not in doubt**: verify assessed all six of the adjudicated deviations as **benign** — each
either implements a spec clause the design under-specified, or was forced by a `tasks.md` gate the
design did not anticipate. **No deviation is contract drift.**

## Specs merged (source of truth updated)

| Domain | Action | Details | Final totals |
|---|---|---|---|
| `local-package-metadata` | **Created** `openspec/specs/local-package-metadata/spec.md` | **7 ADDED** requirements / **21 scenarios** promoted from the ADDED-only delta. New capability; nothing modified, removed or renamed | **7 / 21** |
| `installation-history` | **Created** `openspec/specs/installation-history/spec.md` | **7 ADDED** requirements / **21 scenarios** promoted from the ADDED-only delta. New capability; nothing modified, removed or renamed | **7 / 21** |
| `installed-inventory` | **Amended** | **1 MODIFIED** requirement replaced as a whole block (+3 scenarios) and **3 ADDED** requirements (+12 scenarios). 11 / 39 → **14 / 54**. The other ten requirements untouched | **14 / 54** |
| `package-mutation` | **Amended** | **1 MODIFIED** requirement replaced as a whole block (+2 scenarios) and **2 ADDED** requirements (+7 scenarios). 7 / 25 → **9 / 34**. The other six requirements untouched | **9 / 34** |
| `operation-activity` | **Amended** | **2 MODIFIED** requirements replaced as whole blocks (+3 scenarios) and **1 ADDED** requirement (+4 scenarios). 5 / 15 → **6 / 22**. The other three requirements untouched | **6 / 22** |
| `brew-execution` | **Amended** | **1 MODIFIED** requirement replaced as a whole block (+4 scenarios) — "Serialized mutations with concurrent reads". 6 / 15 → **6 / 19**. The other five requirements untouched | **6 / 19** |
| `catalog-sync`, `package-search`, `brew-detection`, `package-detail` | **Untouched, deliberately** | No delta named them; **none was opened for writing at archive time** | 13 / 39, 7 / 19, 5 / 17, 6 / 17 |

### Main specs after this archive — ten capabilities, 80 requirements, 263 scenarios

| Capability | Requirements | Scenarios | Last changed by |
|---|---|---|---|
| `brew-detection` | 5 | 17 | m2-catalog-hardening (M2-0) |
| `brew-execution` | 6 | **19** | **m2-local-metadata-history (M2-3)** |
| `catalog-sync` | 13 | 39 | m2-catalog-hardening (M2-0) |
| `installation-history` | **7** | **21** | **m2-local-metadata-history (M2-3)** — new |
| `installed-inventory` | **14** | **54** | **m2-local-metadata-history (M2-3)** |
| `local-package-metadata` | **7** | **21** | **m2-local-metadata-history (M2-3)** — new |
| `operation-activity` | **6** | **22** | **m2-local-metadata-history (M2-3)** |
| `package-detail` | 6 | 17 | m1-catalog-browse (M1) |
| `package-mutation` | **9** | **34** | **m2-local-metadata-history (M2-3)** |
| `package-search` | 7 | 19 | m2-catalog-hardening (M2-0) — **PS4 never touched across the whole of M2** |
| **Total** | **80** | **263** | |

**Correction to the prior checkpoint**: Engram `#7062` said "Main specs now SEVEN" while enumerating
eight. The count before this archive was **eight**; it is now **ten**.

Merge method, following the M1, M2-0, M2-1 and M2-2 precedent: requirement and scenario text copied
**verbatim** from the delta files; the delta-only `(Previously: …)` annotations dropped from the
requirement bodies and their substance recorded in each spec's `## Provenance`; every requirement not
named in a delta left untouched.

**No destructive delta was merged** (the repo's `rules.archive` requires a warning before one). All
six deltas are additive: **14 ADDED** requirements and **5 MODIFIED** whole-block replacements, **zero
REMOVED, zero RENAMED**. Every MODIFIED replacement is a strict superset of the text it replaced —
each keeps its original body paragraphs and all its original scenarios verbatim, and appends. The one
in-place edit inside a carried-over scenario is `installed-inventory`'s "The catalog filter set still
declares no installed predicate", which now also excludes a **favorite** predicate; that is the
delta's own wording, not an archive-time reconciliation.

**Zero archive reconciliations were required this cycle.** Unlike M2-2 (three), no promoted scenario
diverges from its delta. Verify raised no spec-wording finding.

Four known follow-ups were written into the promoted specs as **implementation notes** rather than
left only in this report, because each is a behaviour observation against text that is itself correct:
W1 into `operation-activity`, W2 into `installation-history`, S1 into `brew-execution`, S2 into
`installed-inventory`. Every scenario in all four capabilities is COMPLIANT.

## M2 exit criteria — PRD §7, checked clause by clause

> **M2 — Mutations & Installed.** Install/uninstall/reinstall with live logs, cancel, operation queue;
> Installed list with outdated detection; upgrade single/selected/all; pin, favorites, notes, snooze;
> installation history. *Exit: full daily package management without Terminal.*

| Clause | Status | Where it shipped |
|---|---|---|
| Install / uninstall / reinstall | **MET** | M2-2 — `package-mutation`, six typed verbs with explicit kind flags |
| Live logs | **MET** | M2-2 — `operation-activity`, verbatim per-operation streaming into a 2,000-line marked ring |
| Cancel | **MET, hardened in M2-3** | M2-2 for pending/running; M2-3 closed the detached-cancel hole (signal the process, settle only at the real terminal, never release the gate early) |
| Operation queue | **MET, bounded in M2-3** | M2-2 enumerable FIFO projection; M2-3 added ownership-based retirement so records stop accumulating, without breaking session-long enumeration |
| Installed list with outdated detection | **MET** | M2-1 — single `brew info --installed --json=v2` probe, self-updating casks excluded |
| Upgrade single / selected / all | **MET** | M2-2 shipped single + all and the per-package fan-out ruling; **M2-3 shipped selected as an ordered bulk selection** |
| Pin | **MET** | M2-2 |
| Favorites | **MET** | **M2-3** — stored flag + filter-bar filter |
| Notes | **MET** | **M2-3** — plain text, verbatim, never searched |
| Snooze | **MET, deliberately narrowed** | **M2-3** — version-scoped only. PRD §3.2's 1 day / 1 week / 1 month durations were **cut by settled product decision** (`#7111`): they need a clock seam and buy nothing over "until next version". **Recorded as a deliberate scope reduction, not an unmet criterion** |
| Installation history | **MET** | **M2-3** — durable, append-only, searchable, keep-all, confirmed all-or-nothing clear |
| *Exit: full daily package management without Terminal* | **MET** | Verified live in task 9.2 against real brew: install/uninstall from the UI, ordered multi-select with per-package fan-out, external Terminal changes reflected without user action, history written for Cellar's own work only |

**Two deliberate narrowings against PRD §3.2**, both settled product decisions rather than gaps, and
both recorded here so a future reader does not mistake them for oversights:

1. **Snooze durations** reduced to "until next version" only (above).
2. **Bulk verbs** restricted to **upgrade and uninstall**. PRD §3.2 also lists pin and snooze as
   multi-select actions; those were cut (settled 2026-08-02) and the restriction is now a spec rule
   proven exhaustively over `BulkSelection.Action.allCases`, not a convention.

Everything else PRD §3.2 lists for Installed — size on disk, last used, release-notes preview, adopt
existing apps — is **M5 scope by the PRD's own milestone plan**, not M2.

**Conclusion: M2 is COMPLETE.** All four slices (M2-0 catalog hardening, M2-1 installed inventory,
M2-2 mutations & activity, M2-3 local metadata & history) are archived. **Next milestone: M3 —
Services, Cleanup & Taps.**

## What shipped

- **A `Persistence` SPM target** inside `CellarCore` (explore §5 option A) — headless-testable in the
  `swift test` loop and free of the app target's MainActor-default isolation. It is the **outermost
  node**: nothing in the package depends back on it, `BrewClient` never links SwiftData, and `Catalog`
  still declares no `BrewProcess` dependency. `VersionedSchema` V1 plus a `SchemaMigrationPlan` from
  day one, three **independent** `@Model` types with no relationships (`PackageMeta`, `Snooze`,
  `HistoryEntry`), joint key `(kind, name)` stored as primitives so `#Predicate` stays simple while
  the store API speaks `PackageID`. No `@Model` instance ever crosses an isolation boundary.
- **Four gates answered on the real target, none needing a fallback** (Phase 0, verdicts recorded
  verbatim in the `PersistenceSpikeTests.swift` header): G2 — `#Unique([\.kindRaw, \.name])` **upserts**
  rather than throws, and formula `docker` / cask `docker` remain two rows; G3 — an **on-disk**
  container opens, writes and reopens with no app bundle present, so LPM1 sc1 and IH1 sc4 stay in the
  package suite; G4 — a `@MainActor` holder is clean under `.swiftLanguageMode(.v6)` in a
  `nonisolated`-default target.
- **Favorites, notes and version-scoped snooze**, with the **G5 rule**: revival is **string
  inequality**, never version ordering. Homebrew version strings cannot be ordered reliably and a
  comparator bug would *silently suppress a real update*; equality fails **visibly** instead (a
  republished older version revives the badge — an accepted false positive). The absence of a
  comparator is enforced by a structural test that reads real sources, strips comments, asserts nine
  forbidden tokens absent **and carries a positive anchor** so it cannot pass vacuously. Verify
  re-scanned the whole repo independently and confirmed it.
- **Installation history** — one durable entry per Cellar-performed mutation at its terminal outcome,
  carrying date, package, verb, version from→to, outcome and exact argv. "Upgrade all" is **one
  grouped entry** with no inventory diffing; a bulk selection is **one entry per package**. External
  brew changes are **never** logged (proven live: `brew install hello cowsay` from Terminal surfaced
  in Installed via FSEvents and wrote zero rows). Keep-all retention with no `fetchLimit` anywhere,
  newest-first searchable projection, and a single confirmed all-or-nothing clear with **no per-entry
  delete affordance**.
- **A stored row can never become a command.** The persisted argv is display-only: a structural scan
  proves no `-> MutationCommand`, `MutationCommand(`, `brewCommand` or `PackageTarget(` declaration
  exists anywhere in `Persistence`, and the only control a row exposes is copy.
- **Ordered bulk multi-select** — the native `List(selection:)` `Set<PackageID>` binding is kept for
  range selection, VoiceOver and Select All, with an ordered `[PackageID]` maintained **beside** it;
  the ordered array is the only thing the bulk surface and the confirmation sheet read, because `Set`
  iteration order is unstable across launches and would make submission order irreproducible. A bulk
  uninstall is confirmed **once**, naming **every** package.
- **`PackageTarget`** — a failable wrapper that makes "no enum case takes a bare `PackageID`" a
  **compiler fact**, closing M2-2 follow-up 3's two bypass sites. The safety rule lives in exactly one
  place (non-empty, no leading `-`, no whitespace) and the `-` prefix rejection is new in this slice:
  a name such as `--force` can no longer reach argv. Triangulated over 10 hostile names × 3
  constructors.
- **Ownership-based runner retention** (D6) — `BrewOperation.deinit` releases; eviction retires only
  records that are both compacted **and** released, sorted by ordinal, past a cap of 200. `exit(of:)`
  stays answerable for anything still awaited, and a retired record never removes its queue item.
  Plus a `queuePhase` equality guard, so observers see one change per real transition.
- **Detached cancel** — a cancel issued while the queue is detached from its runner now signals the
  process and settles only at the **real** terminal outcome, and neither releases the mutation gate
  nor forces the re-snapshot early. M2-2's hole left a running, uncancellable operation behind an
  already-reopened gate; bulk multi-select multiplied the exposure, which is exactly why the M2-2
  archive routed it here.

**All six absorbed M2-2 follow-ups are CLOSED** — 1 (bulk label/set mismatch), 2 (cancel after runner
detach), 3 (`naming(_:_:)` bypass), 4 (runner-record eviction + `queuePhase` guard), 5 (harness
index-after-timeout, now a failed expectation rather than a trap — the suite's one deliberate known
issue), 11 (`explore.md` doc corrections, landed in commit `eb62dbb` as the last change that could
correct the umbrella exploration before it is archived).

## Follow-up register (17 open, none blocking)

**W1–W4 and S1–S2** are the six findings from native review lineage `review-e07590a04c4aff38`.
**VS1–VS4** are the verify SUGGESTIONs. The rest are inherited and still open. Nothing here blocks the
archive; every one of them sits against spec text that is correct as written.

| # | Follow-up | Source | Routed to |
|---|---|---|---|
| **W1** | **The no-runner submit path settles `.launchFailed` without writing a history entry** — `OperationCenter.swift:159-163` bypasses `finish()`, so that one path produces a terminal outcome with **no** entry, a narrow exception to `operation-activity`'s "exactly one entry per terminal outcome". Reachable only when a mutation is submitted with no runner attached | review WARNING | **M3** |
| **W2** | **A failed Clear History is silently masked** — `clearAll()` sets the availability reason, then an unconditional `reload()` overwrites it back to `.available` and `lastError` is never set (`HistoryStore.swift:181-190`), so a clear that did not delete can render as if it had | review WARNING | **M3** |
| **W3** | **The app opens two `ModelContainer`s over one store file** — `cellarApp.swift:50` and `:63` both default to `PersistenceContainer.defaultURL()`. Design **D3** intended one container injected down, and no test covers the dual-coordinator configuration | review WARNING | **M3** |
| **W4** | **An uncommitted note draft is lost on package switch** — the only commit trigger in `PackageMetadataSection.swift` is focus loss, while `onChange(entry.id)` resets the draft first; the doc comment claims an `onSubmit` commit that does not exist | review WARNING | **M3** |
| **S1** | **`BrewRunner.exit(of:)` answers an unknown id with a fabricated `BrewExit(status: 0)`** rather than a typed unknown-operation result; only the `isReleased` gate prevents that value being observed | review SUGGESTION | **M3** |
| **S2** | **Bulk multi-add appends in flat inventory order**, not the displayed three-section order its own comment claims (`InstalledListView.swift:117`). Order is still deterministic and never `Set` order, so no scenario is violated — the divergence is code vs comment | review SUGGESTION | **M3** |
| **VS1** | **Give the display-only structural scan a positive anchor** — `HistoryRecorderTests > aStoredRowCannotBecomeACommand` is a pure-negative source scan; one `#expect(source.contains("commandText"))` would make vacuous passing structurally impossible, matching the G5 scan's pattern | verify SUGGESTION 1 | test hygiene |
| **VS2** | **`OperationCenter.pendingConfirmation` widened from `public private(set)` to `public internal(set)`** as a side effect of the 408-line split. The external contract is unchanged, but "only the confirmation flow writes this" is now a module convention rather than a compiler guarantee. A small `ConfirmationBox` type would restore `private(set)` | verify SUGGESTION 2 | **M3** |
| **VS3** | **Phase 8 (app-target UI) carries the residual risk with no automated coverage** — nothing exercises the ordered-selection `.onChange` diff, the note editor's focus-loss commit, the History search field, or **IH6's Cancel path** (whose only evidence is the 9.2 d-addendum manual observation). A small XCUITest would convert manual evidence into a regression gate | verify SUGGESTION 3 + the CRITICAL remediation | **M3** |
| **VS4** | **`HistoryDraft.date` is `Date()` at the terminal, not an injected clock.** Nothing is flaky today — no test asserts a wall-clock value and ordering is asserted through explicitly-dated drafts — but a slice needing deterministic timestamps should add an additive `clock:` seam rather than reach for `Date()` again | verify SUGGESTION 4 | unassigned |
| M2-2 #6 | **A mutation's own post-terminal FSEvents echo costs one redundant `brew info --installed`** (~3 s after the terminal outcome). **Conforming, not a defect** — M2-2 verify ruling 2. A short post-terminal grace window past `end()` would absorb it | M2-2 register (deferred here) | unassigned |
| M2-2 #7 | **Duplicate submission of the same install is accepted** and runs to a benign "already installed" outcome. **Permitted by design** — M2-2 verify ruling 3. An optional dedup guard is a nicety, not a correctness fix | M2-2 register (deferred here) | unassigned |
| M2-2 #8 | **Carry `standardInput` through `ProcessSpec`** so `package-mutation`'s "Standard input is never interactive" becomes testable at the recording seam as originally written. The behaviour is correct today at the composition root; only its observability is missing | M2-2 register (deferred here) | unassigned |
| M2-2 #9 | **The sudo signature set is still unprobed** against a live sudo-requiring cask. Safe by construction — a miss degrades to `.failed` with the log visible | M2-2 register (deferred here) | unassigned |
| M2-2 #10 | **`skippedRecordCount` is never surfaced** — decode tolerance remains silent to the user | M2-2 register, carried from M2-1 #7 | unassigned |
| M2-2 #12 | **M2-0 #1 — `CatalogStore` adoption ordinal stamps on call arrival.** Still open in `Sources/Catalog/`. **Now the oldest open defect in the project**, untouched by three consecutive slices. The M2-2 archive already asked that it be closed on its own rather than carried into another slice; it was not, and it is repeated here | M2-0 register | **close standalone, before M3 work starts** |
| M2-2 #13 | **M2-0 #4–#7, M1 #4/#5** — unbounded watcher loop with no `.timeLimit`; poisoned-snapshot recovery gated on staleness; undelivered engine-side zero-package guard; latency test built via the synchronous initialiser; payload size cap and unwired `payloadByteLimit` | inherited | still deferred |
| M2-1 #8 / #9 | **`DetectionTests` display-name prose, `InstalledRefreshTests` count assertion** — untouched since M2-1 | inherited | unassigned |

### Inherited register — status at this close

| Item | Status |
|---|---|
| M2-2 #1 — bulk-upgrade label and submission set disagree | **CLOSED** — both derive from `upgradableIDs`, and the divergent helper was deleted. Specified in `installed-inventory` II14 |
| M2-2 #2 — cancel after runner detach settles without signalling and pays the gate early | **CLOSED** — specified in `operation-activity` OA3 and proven by two named tests |
| M2-2 #3 — two call sites bypass `naming(_:_:)` | **CLOSED** by `PackageTarget`; "no enum case takes a bare `PackageID`" is now a compiler fact. Specified in `package-mutation` PM9 |
| M2-2 #4 — runner records never evicted + `queuePhase` written without an equality guard | **CLOSED** by ownership-based retirement (cap 200) and the publication guard. Specified in `brew-execution` BE1 |
| M2-2 #5 — `OperationCenterHarness` indexes after a silent poll timeout | **CLOSED** — now a failed expectation rather than a trap; it is the suite's one deliberate known issue |
| M2-2 #11 — `explore.md` doc corrections | **CLOSED** in commit `eb62dbb`, the last change able to correct the M2 umbrella exploration |
| M2-2 #6, #7, #8, #9, #10, #12, #13 | **Still open** — deferred at proposal time and unchanged by this slice. Listed above |

**Six of M2-2's follow-ups closed here, exactly the six the M2-2 archive routed to this slice.** That
is the second consecutive slice where routing a review WARNING to the change that makes it reachable
paid off: every one of them was closed with a RED test that reproduced it first, and item 4's
retention was a hard prerequisite for an honest history rather than an optional cleanup.

## Archive integrity

- **`tasks.md` is fully checked (90/90).** No checkbox was altered at archive time and no
  stale-checkbox reconciliation was performed or needed. Gate evidence: the phase-0 and phase-8/9
  ranges were read directly at archive time, and verify's mechanical count (`rg -c '^\s*- \[x\]'` → 90;
  `rg -c '^\s*- \[ \]'` → 0) covers the whole file. **Archive classification: clean** — zero open
  CRITICAL findings, zero blockers, no gate overridden, no partial archive.
- **Zero archive reconciliations.** Every promoted requirement and scenario is byte-identical to its
  delta; no scenario was reworded at promotion.
- **Four capabilities were never opened for writing**: `catalog-sync`, `package-search`,
  `brew-detection`, `package-detail`. They stay byte-identical.
- **`openspec/changes/m2-mutations-installed/explore.md` is NOT part of this archive.** It is the M2
  umbrella exploration, tracked since M2-1 at `86e2216`. M2-3 closed follow-up 11 against it
  (commit `eb62dbb`). **With M2 now complete, it is the natural candidate to archive alongside the M2
  milestone** — it is the last M2 artifact still living outside `archive/`.
- **The one CRITICAL raised this cycle was closed by producing evidence, not by an override.** The
  archived `verify-report.md` preserves the original FAIL finding under a `[RESOLVED]` marker; the
  passing verdict was re-admitted through `gentle-ai sdd-verify-validate` rather than asserted.

Verification evidence: `evidence_revision sha256:dba16789581b7966a9d76a0983250582ed6773c5952e96aa9776eb2ebf9e793d`;
`test_output_hash sha256:d1926f04482b2c0444f864a996624c33b4333caed3616ec38f1894541cd883b7`;
`build_output_hash sha256:20ee2b283e5016f53a0ab343507ec19af13e41d0c3c6ea4653aa776e3696e2ce`;
admitted by `gentle-ai sdd-verify-validate --requirements 25 --scenarios 101` (`valid: true`).

## Artifact traceability

| Artifact | Engram observation | OpenSpec file (archived) |
|---|---|---|
| M2 slicing decision | `#7065` | (Engram only) |
| product decisions Q1–Q4 settled (snooze scope, notes, favorites-as-filter, history rules) | `#7111` | (Engram only) |
| proposal | `#7112` `sdd/m2-local-metadata-history/proposal` | `proposal.md` |
| spec (6 deltas) | `#7114` `sdd/m2-local-metadata-history/spec` | `specs/{local-package-metadata,installation-history,installed-inventory,package-mutation,operation-activity,brew-execution}/spec.md` |
| design | `#7115` `sdd/m2-local-metadata-history/design` | `design.md` |
| design gate probe G1 (SwiftData headless, RESOLVED pre-apply) | `#7116` | (Engram only) |
| **G5 ruling** — snooze revival is string inequality, no version comparator anywhere | `#7117` | (Engram only) |
| tasks | `#7118` `sdd/m2-local-metadata-history/tasks` (index + forecast mirror; **the file wins on any divergence**) | `tasks.md` — **90/90**, includes 9.2's verbatim manual evidence |
| apply-progress | `#7119` — **"89/90", "nothing pushed" and the "11 commits" header all superseded by this report** | (Engram only) |
| task 9.2 manual verification (all four checks PASS) | `#7120` | evidence table inside `tasks.md:488-505` |
| verify-report | `#7121` `sdd/m2-local-metadata-history/verify-report` — **its line-197 compliance summary (100/101, 1 UNTESTED) is stale and superseded; the file's own header, matrix and verdict all say 101/101** | `verify-report.md` |
| verify outcome (FAIL → remediation → re-admission) | `#7122` | (Engram only) |
| native review (lineage, findings, CLI lessons, stray lineage) | `#7123` | (Engram only) |
| delivery | `#7113` `sdd/m2-local-metadata-history/delivery` — **"PR #6 open" superseded by the merge at `66af57c`**; its commit arithmetic self-corrects mid-text to the right answer (**15**) | (Engram only) |
| archive-report | `sdd/m2-local-metadata-history/archive-report` | this file |
| project checkpoint (updated at this close: **M2 COMPLETE**) | `cellar/project-checkpoint` (supersedes `#7062`) | (Engram only) |

**The `verify-report.md` digest is part of the audit trail.** It is preserved because the change
folder is moved into this archive with a byte-preserving `git mv` in the same commit that adds this
report — no artifact was re-transcribed.

## Next

**M2 is closed. The next milestone is M3 — Services, Cleanup & Taps**: a Services view driven by
`brew services` with start/stop/restart, the disk-usage engine and the Cleanup view with dry-run
previews, autoremove/orphans, and the taps manager. PRD exit: *TapHouse free-tier parity minus
security.*

Three things M3 should settle before its first slice:

1. **Close M2-2 #12 (the M2-0 catalog adoption ordinal) standalone.** It is the oldest open defect in
   the project, it has now survived three slices, and the M2-2 archive already asked for exactly this.
   It is a one-line guard in `Sources/Catalog/`.
2. **Take W1–W4 as a single small hardening slice.** All four are app-composition or execution-edge
   gaps in code M3 will not otherwise touch, and W3 (two `ModelContainer`s over one store file) is the
   only one with a plausible data-integrity tail — it should not sit behind a services feature.
3. **Price a new-framework target at ~1.5× production for tests, not 1.2×.** M3 introduces no new
   persistence framework, so 1.2× should hold again — but the rule is now recorded rather than
   rediscovered.
