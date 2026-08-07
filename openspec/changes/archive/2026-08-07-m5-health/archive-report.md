# Archive Report: `m5-health` — Health Dashboard, `brew doctor` & Bulk Pin/Snooze

**Archived** `2026-08-07` to `openspec/changes/archive/2026-08-07-m5-health/`.
**PRD milestone closed**: **M5 "Pro-parity flows"** — slice **5 of 5**. *(`openspec/config.yaml`
`rules.archive`: "Record which PRD milestone the archived change closed.")*

> ## 🏁 M5 IS COMPLETE
>
> This change was the final slice of PRD milestone **M5 "Pro-parity flows"**. With it archived, M5
> is **DONE (5/5)**: `m5-discover`, `m5-pro-parity`'s earlier slices, `m5-release-notes`,
> `m5-brewfile` and `m5-health` have all shipped and been archived. Every M5 deferral recorded
> across the five slices is a **v1.1 item**, not an implication of incompleteness.
>
> The `m5-pro-parity` umbrella change directory is still present under `openspec/changes/`. It is
> **noted here for closure consideration** by the orchestrator and was **deliberately not touched**
> by this archive phase.

---

## State at close

This section is the terminal record and reflects the state **at close**, per the Final-State
Authority hierarchy. Where an intermediate snapshot (`apply-progress`, `verify-report`) said
something was pending that has since closed, the final state is reported and the closure is cited.

| Fact | State at close | Source |
|---|---|---|
| Delivery | **Merged.** PR #20 merged to `main` as merge commit **`3f2aeb5`** | repository (`git log`) |
| Commits | `1f384c5` feat(health) — 61 files, 8,614 insertions / 94 deletions · `b0003cf` docs(sdd) — 9 lifecycle files, 3,361 insertions | repository, Engram `#7540` |
| Working tree | **Clean**, `main` synced, at `3f2aeb5` when this phase began | repository |
| Tasks | **71/71 complete, zero unchecked** | `tasks.md` (grep-verified twice: before sync, after move) |
| Verification | **PASS WITH WARNINGS**, revision 3 — 0 CRITICAL, 0 blockers, **1 WARNING, 5 SUGGESTION**, **80/80 scenarios, 15/15 requirements** | `verify-report.md` rev 3, Engram `#7538` |
| Review gate | **Structurally absent** — RDD is disabled for this clone and **no review was ever started** for this candidate. Archived under **ordinary repository policy**. **No review approval is claimed.** | launch context, native-review-gate rule |
| Test suites | CellarCore **1,656 tests / 199 suites green** (1 pre-existing known issue) · `cellarTests` **146 cases green** · `HealthSectionUITests` **9/9** | launch context (final), verify rev 3 |
| FULL failures | **Exactly** the pre-existing `ReleaseNotesUITests` 4-case / 7-failure baseline — orchestrator-owned, unchanged by this slice | verify rev 3, apply-progress |
| Zero-line-diff contract | All seven binding paths held, including `project.pbxproj` and `openspec/specs/brew-execution/spec.md` (re-measured at archive: 0-line diff) | this phase + verify rev 3 |

### Two stale intermediate claims, explicitly superseded

1. **A batch-4 `apply-progress` risk note claimed task 13.3 was still open. That claim is WRONG and
   is not carried forward.** `tasks.md:174–178` carries 13.3 as `[x]` with an inline annotation
   recording that every user-facing string was presented verbatim to the user on 2026-08-07 and
   **accepted as-is with no rewording**. The checkbox and its annotation agree; the annotation is
   authoritative. **71/71 stands**, verified by grep at archive time. Verify rev 3 reached the same
   conclusion independently.
2. **`apply-progress` recorded `cellarTests` at 139 `@Test` declarations; the final state is 146
   cases green.** These are different units — `@Test` declarations versus expanded test cases — so
   this is **not** a contradiction, and neither number is wrong for what it counts. The final case
   count is reported above.

No unrankable contradiction between sources was found during this phase.

---

## Specs synced

Three delta specs, three different merge shapes. Every merge was performed by mechanical shell
slicing and verified by byte-slicing the replaced ranges against the delta — never by model
transcription.

| Domain | Action | Delta | Main spec: before → after | Verification |
|---|---|---|---|---|
| `system-health` | **Created** (new capability) | ADDED-only, 11 req / 51 scen | *(did not exist)* → **11 req / 51 scen** | `cp` + `diff -r` empty, then body re-diffed byte-identical after promotion edits |
| `installed-inventory` | **Updated — DESTRUCTIVE** | 2 MODIFIED (II13, II14) | 14 req / 58 scen → **14 req / 64 scen** | whole-block byte-equality against the delta; every untouched requirement byte-identical |
| `local-package-metadata` | **Updated** | 2 MODIFIED (LPM4, LPM5), strict superset | 7 req / 22 scen → **7 req / 27 scen** | strict-superset byte-slicing to the slice-4 standard |

All counts above are **grep-derived** (`^### Requirement: ` / `^#### Scenario: `) on both the delta
side and the main-spec side after merge — not arithmetic. Both sides agree exactly.

### `system-health` — promotion of a new capability

Promoted to `openspec/specs/system-health/spec.md` following the convention established by
`m5-discover`, `m5-release-notes` and `m5-brewfile`: the file was copied mechanically with `cp`
(`diff -r` empty), then four surgical edits applied — the `# Delta for system-health` header became
`# system-health`, the delta-only "ADDED-only / nothing is MODIFIED" paragraph was dropped, the
`Traceability:` paragraph was relocated verbatim into Provenance, and `## ADDED Requirements` became
`## Requirements`. A promotion entry was appended to the capability's existing Provenance section.

**Verified after those edits**: the requirement and scenario bodies (delta lines 31–561 versus
promoted lines 13–543) are **byte-identical**, and the delta's own Provenance entries are a
**verbatim prefix** of the promoted Provenance. Both diffs empty.

### `installed-inventory` — the destructive merge

**`openspec/config.yaml` `rules.archive` ("Warn before merging destructive deltas") was triggered
and satisfied.** The orchestrator issued the config-required warning before this phase began and the
user directed the merge to proceed. The delta was **not** superset-verified — it cannot pass a
superset check, by design.

**Exactly five lines left the main spec, all inside II13:**

| # | Removed line | What it was |
|---|---|---|
| 1 | `upgrade and uninstall only; pin, unpin, snooze, favorite and note MUST offer no bulk affordance, and` | the **prohibition** itself |
| 2 | `#### Scenario: Only upgrade and uninstall are offered for a selection` | the scenario heading |
| 3 | `- GIVEN a non-empty selection` | its given |
| 4 | `- THEN upgrade and uninstall are present` | its then |
| 5 | `- AND no bulk pin, unpin, snooze, favorite or note control is present` | the assertion that pinned the prohibition |

**WHAT was removed**: the prohibition on bulk pin, bulk unpin and bulk snooze, and the scenario that
asserted it. Favorite and note **remain prohibited**.

**WHY**: bulk pin/unpin/snooze were deliberately narrowed out on 2026-08-02, and the shipped
Provenance recorded that narrowing as settled. It was a **scope decision, not an invariant**, and
the maintainer **reversed it** — decisions **D1**/**D2**, Engram `#7532`, so PRD §3.2's full bulk
vocabulary ships. The removal is the point of the change, not a merge accident.

**WHEN**: ruled 2026-08-07 (obs `#7532`); merged into the main spec 2026-08-07 by this phase.

**Verification actually performed** (in place of the impossible superset check):

- II13's rewritten whole block in the main spec (lines 490–603) was byte-compared against the
  delta's MODIFIED block (delta lines 38–151): **byte-identical**.
- II14's block (main 604–640 vs delta 153–189): **byte-identical**, *and* separately confirmed a
  **strict superset** — zero removals, requirement text unchanged, one scenario added.
- Every untouched requirement was byte-verified: main-spec lines 1–489 and 642–839 are
  **byte-identical before and after** the merge.
- `git diff -U0` over the whole file lists **exactly the five removals above and no others**.

**What the rewrite preserved, deliberately and byte-identically**: selection order, the
displayed-order rule for a multi-package add, the leave-the-inventory rule, and above all **"a bulk
control that cannot act on the current selection MUST be unavailable rather than inert"** — the
clause that forbids guessing on a mixed pinned/unpinned selection, and therefore the clause that
makes pin and unpin two independent verbs rather than one toggle. Four of the six pre-existing
scenarios are untouched.

The Provenance entry written into the main spec records all of the above, and additionally
supersedes the earlier "Multi-select … is untouched, and that is load-bearing" note for its
bulk-verb half: `service-management`'s guard survives with its **intent** intact but its assertion
rewritten (no *service* verb entered the package vocabulary, rather than the vocabulary being frozen
at two cases). Both pinning tests were **rewritten, never deleted**.

### `local-package-metadata` — strict-superset merge

LPM4 and LPM5 were spliced by line range and verified to the slice-4 standard: main lines 94–162 ==
delta 30–98, main 163–248 == delta 100–185, and the untouched head (1–93) and tail (250–358)
byte-identical before and after. `git diff -U0` shows **one** removed line for the whole file — the
LPM5 `(Previously: …)` annotation, which gained a closing sentence recording this revision. That is
a provenance annotation, not normative text, so **every normative sentence and all 22 pre-existing
scenarios survive byte-identically**; both blocks are strict supersets of what they replaced.

---

## Verify journey

Three revisions, all preserved on disk in `verify-report.md` (sha256
`47bdcb7f49bd749764aa74bb61910267141bc7ed37b9a3cf66234fb1f4f45dfe`, re-confirmed at archive time).
Each remediation was authorized against the failed evidence revision above it.

| Rev | Verdict | Req | Scen | CRIT | WARN | SUGG |
|---|---|---|---|---|---|---|
| 1 | **FAIL** — real defect | 13/15 | 77/80 | 1 | 2 | 2 |
| 2 | **FAIL** — zero defects, evidence completeness only | 14/15 | 79/80 | 0 | 1 | 3 |
| 3 | **PASS WITH WARNINGS** | **15/15** | **80/80** | **0** | 1 | 5 |

1. **Rev 1 FAIL — one CRITICAL, a genuine defect.** `HealthComposition.command(for:)` was referenced
   by no test at all, leaving SH11 sc3 uncovered and sc1 partial — the **confirmation seam** was
   unguarded. A WARNING also caught a stale D4 comment that a test was actively pinning.
2. **Remediation (user-authorized rescope, 197/200 lines).** `HealthRemediationTests` — five tests
   covering all five remediation→command mappings over `HealthRemediation.allCases`, confirmation
   ownership, and a comment-stripped source guard with a positive anchor and a violation control.
   **Non-vacuity was proven by temporary mutation**: the real-code tests were made to fail, then
   both files restored from backups and re-hashed identical, leaving zero production diff.
3. **Rev 2 FAIL — zero defects.** The only gap left was **evidence completeness**: 79/80, with SH4
   sc3 ("running doctor does not move the fetch marker") PARTIAL, because argv assertions cannot
   observe brew's internals. The validator admits `pass` only at 80/80. Two exits were offered — a
   maintainer ruling that probe U14 discharges it, or one integration test. **The user chose the
   test.**
4. **Remediation (rescope generation 6, 191/200 lines).** `DoctorIntegrationTests` — one test at the
   real-brew layer over the shipped `HomebrewRepositoryLocator`, `HomebrewUpdateReader` and
   `BrewDoctorSource`, asserting the `HOMEBREW_NO_AUTO_UPDATE` pin by composing the same expression
   `DoctorSource.swift:49–51` composes, with three explicit vacuity refusals. **Genuine RED**: the
   assertion was written inverted and failed after a real 2.4 s doctor spawn, then flipped and
   passed. Zero production lines.
5. **Rev 3 PASS WITH WARNINGS.** 0 CRITICAL, 0 blockers, 0 failing commands, 0 regressions. SH4 went
   3/4 → 4/4, taking the envelope to 15/15 and 80/80. Independently corroborated outside the test:
   `/opt/homebrew/.git/FETCH_HEAD` has survived ≥4 real doctor runs across two sessions unmoved, and
   `/opt/homebrew/Homebrew/.git/FETCH_HEAD` does not exist — so SH5's probe order is confirmed live
   as a bonus.

---

## Recorded exceptions

Both are **authorizations, not defects**, and both are recorded here so a later reader does not
mistake them for unaddressed process failures.

1. **`size:exception`, pre-accepted before apply started** (obs `#7532`, decision 2). The review
   workload budget is 400 changed lines per PR and this project's SDD budget was 5,000 authored
   lines; the delivered feat commit carries **~8,600 authored lines** (8,614 insertions / 94
   deletions across 61 files). `sdd-tasks` forecast this honestly and emitted the guard lines
   verbatim — `Decision needed before apply: No` / `Chained PRs recommended: Yes` /
   `400-line budget risk: High` — recommending chained PRs while recording that the maintainer had
   already accepted the exception, so tasks did not stop to re-ask. A two-batch cut was pre-agreed
   as a mid-apply contingency at Phase 9 and was **not needed**; the `installed-inventory` delta
   spanned both batches (II13 pin/unpin in Phase 8, the bulk-snooze clauses in Phase 11, the LPM5
   guard widening in 11.6), so the delta could not have been archived between two PRs — both batches
   landed in one, and archive is therefore safe.
2. **Two maintainer-authorized ledger resets, 2026-08-07** (obs `#7539`; mirrors the slice-3
   precedent, obs `#7513`). Both were issued for **accounting artifacts carrying zero source lines**:
   - **Reset 1** — a *measurement* artifact. `git add --intent-to-add` was run **mid-attempt** to
     satisfy the changed-candidate check, which made the whole ~11k-line uncommitted change visible
     to `git diff --numstat` between the begin and finish candidates. The real work-unit delta
     reconstructs to **191 lines**, inside its 200 bound, corroborated independently.
   - **Reset 2** — verify revision 3's own report rewrite: **520 lines of lifecycle markdown, zero
     source**.
   - **Lesson recorded for future slices**: `intent-to-add` untracked files **before** the first
     acquire so candidate identity includes them from the start (this is the slice-3 lesson
     re-learned the hard way), and budget verify acquires for their own report writes.

---

## User rulings recorded during the cycle

All from obs `#7532`, ruled 2026-08-07.

- **F7 — the weight tie stands.** `cache` 5/100 and `doctor` 5/100 remain tied; item 6.5 was
  reworded rather than the weights changed. SH10's ordering scenario requires doctor to be weighted
  *lightly* against the user's own packages, which the tie satisfies.
- **F13 — Browse remains the landing section.** This **corrects the D4 record**, which had claimed
  "Home stays the landing". That was **factually never true**: `Browse` has been the landing section
  since M1 and the shipped tests pin `.browse` literally. The corrected record is: **Home remains a
  section; Browse remains the landing; `.health` did not take the landing spot.** The stale comment
  in `cellar/Shell/AppSection.swift` that asserted otherwise was corrected under a real RED→GREEN
  cycle — the assertion was rewritten first and failed, then the comment was fixed. This correction
  is also written into the `system-health` main spec's Provenance, because two entries there say
  "Home stays" and a future reader must not read that as "Home is the landing".
- **All user-facing copy accepted as-is, no rewording** (task 13.3). Presented verbatim: the score
  surface including the "Nothing could be scored yet" empty state, the per-count caveat and
  "Answered weight {w} of 100"; the breakdown ("How this number was reached", "Every weight is shown
  so the number can be argued with…"); the eight signal names; the unknown-reason strings; the
  doctor copy ("Run doctor" re-measures and changes nothing, plus the de-emphasis quoting Homebrew's
  own "just used to help the Homebrew maintainers with debugging"); the rows and remediation labels;
  the summaries; and the bulk-snooze copy ("Snooze {count}" / "Hides the update badge for the
  selected packages until a different version is offered.").

---

## Carried follow-ups

None of these blocked archive. All are recorded so they are not rediscovered from scratch.

**Lint findings from verify rev 3 (1 WARNING, 5 SUGGESTION):**

| # | Item | Status |
|---|---|---|
| W1 | `cellarApp.swift:164` — initializer **156 lines** vs SwiftLint's default limit of 100 | **Pre-existing, verified not assumed.** Linting the `HEAD` (`7d48779`) copy showed the initializer already spanned **142** lines, the file already 462 (limit 400) and the struct body already 260 (limit 250). This change adds **+14**. *(There is **no `.swiftlint.yml`** in this repo — all thresholds are SwiftLint defaults. An earlier lint attempt against a non-existent config produced a false "clean at HEAD" and was corrected before reporting.)* |
| S4 | `cellar/Health/HealthCopy.swift:104` — cyclomatic complexity **11** vs 10 | **Change-created**, warning-level |
| S5 | `OperationCenterBulk.swift` — file_length **403** vs 400 | Measured **383 at HEAD**; this change pushed it over |
| S1 | **F12** — `DiskUsageSnapshot` non-deterministic encoding | Tracked follow-up, carried from an earlier slice |
| S2 | `ReleaseNotesUITests` — 4 cases / 7 failures | See below |
| S3 | `aCleanupRemediationKeepsItsOwnersConfirmation` — three entailed assertions want a comment naming which one carries the weight | Cosmetic |

**Other carried items:**

- **`ReleaseNotesUITests` (4 cases / 7 failures) — orchestrator-owned, and it is next.** This
  baseline is pre-existing, undiagnosed, and now **four slices old**. It was subtracted honestly at
  every gate (FULL failures at delivery were *exactly* this baseline and nothing else). Its
  diagnosis is **scheduled as the next small change**, immediately after this archive.
- **The false-zero `CompositionRequestSpy` (`SecurityCompositionSupport.swift:181`) is STILL live
  after three slices.** This slice was the likeliest yet to want it and deliberately did **not**
  adopt it: `HealthCompositionTests` uses a per-instance UUID-tagged ledger under `Mutex` instead,
  and **no `CompositionRequestSpy` call site was added anywhere**, batches 3 and 4 included. The
  underlying shape remains unfixed and is a standing trap for the next composition test author.
- **S4 catalog headroom is unconsumed.** No `CatalogPackage` field, cache file, schema version,
  `UserDefaults` key or Keychain item was introduced, so the ~2.4% footprint headroom is untouched
  and `CatalogFootprintTests.swift` measured a 0-line diff.
- **Spec-level assumptions left OPEN (both low)**: (2) the health rows are spec'd as **seven** while
  the proposal's "eight §3.4 signals" counts the score itself, which SH9/SH10 own separately; (3)
  snooze bulk eligibility is spec'd as "outdated members not already snoozed at the offered version",
  which the proposal did not state.
- **Design open questions, resolved not deferred**: HD7's weights stand as proposed (every one is
  visible in the breakdown, so disagreement is a constant change, not a redesign), and `.health`'s
  neighbour stands as *after `.cleanup`, before `.security`*. Both recorded in `design.md` under
  *Apply-Time Amendments*.

---

## Traceability — Engram observation IDs

Every artifact read by this phase, in lifecycle order.

| Obs | Topic | Artifact |
|---|---|---|
| `#7530` | `sdd/m5-health/explore` | Exploration |
| `#7531` | *(probes)* | Probes U10 / U11 / U12 / U14 — the measured facts the whole slice is written against |
| `#7532` | `sdd/m5-health/decisions` | Maintainer decisions D1–D7, the pre-accepted `size:exception`, task 13.3 closure, F7 and F13 rulings |
| `#7533` | `sdd/m5-health/proposal` | Proposal (Binding Invariants 1–4, D1–D7) |
| `#7534` | `sdd/m5-health/design` | Design (HD1–HD11) |
| `#7535` | `sdd/m5-health/spec` | Delta specs, **revision 2** (SH12 dropped; AppSection placement moved to `tasks.md` per precedent) |
| `#7536` | `sdd/m5-health/tasks` | Tasks — 14 phases, 71 tasks, guard lines |
| `#7537` | `sdd/m5-health/apply-progress` | Apply progress, **revision 4** (batches 1–4 merged) — *intermediate snapshot* |
| `#7538` | `sdd/m5-health/verify-report` | Verify report, **revision 3**, PASS WITH WARNINGS |
| `#7539` | `sdd/m5-health/verify-journey` | Verify journey + the two ledger-reset authorizations |
| `#7540` | `sdd/m5-health/delivery` | Delivery record — branch, two commits, PR #20 |
| *(this)* | `sdd/m5-health/archive-report` | This report |

**On-disk artifacts** are authoritative wherever they and an Engram copy differ; every artifact in
this change carried its full text on disk and the Engram observation is the summary/index. The
archived folder is the audit trail.

---

## Mechanical archive verification

Per the Mechanical Copy Contract, no artifact content passed through model Read/Write. Every copy
and move used `cp -R`, `cp`, `mv` or `git mv`, each with an independent `diff -r` readback.

- **Archive move**: pre-move recursive snapshot (9 files) → `git mv` → source directory confirmed
  gone → `diff -r snapshot archived` produced **empty output, exit status 0**. This report is
  additive and did not exist in the source snapshot, so it is excluded from that comparison.
- **`system-health` promotion**: `cp` → `diff -r` **empty** → surgical header/wrapper edits → body
  re-diffed **byte-identical**.
- **Both MODIFIED merges**: built by shell line-slicing, byte-verified block by block, with the
  untouched head and tail of each file proven byte-identical before and after.
- **Scope**: the other active change directories — `m5-pro-parity`, `m3-4`,
  `m3-services-cleanup-taps` — were confirmed **untouched** via scoped `git status`.
- **Archived `tasks.md`**: re-verified after the move — **71 checked, 0 unchecked**.

---

## SDD cycle complete

`m5-health` was explored, proposed, spec'd, designed, planned, applied under strict TDD across four
batches, verified across three revisions to PASS, delivered as PR #20 and merged, and is now
archived with its three delta specs merged into the source of truth.

**PRD milestone M5 "Pro-parity flows" is COMPLETE.**
