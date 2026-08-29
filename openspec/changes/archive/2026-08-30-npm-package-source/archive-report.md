# Archive Report: `npm-package-source`

**Archived**: 2026-08-30 · **Milestone**: **closes PRD M13 — npm package source** (`PRD.md` §7,
:219-220), recorded per `rules.archive` ("record which PRD milestone the archived change closed").
This is the first archived change in this project to close a numbered milestone outright since M5;
`m10`, `m11` and `m12` were post-exit slices that closed none. M13's stated exit — *"a user with
Homebrew and npm sees and applies both sets of updates from one Updates list"* — is met.
**Status at close**: implemented in **three ordered work units** over one apply pass plus one
remediation, verified in **two verify rounds**, **committed and pushed as a single commit**, with
**PR #92 open against `main` and not merged**.
**Verify verdict**: **PASS WITH WARNINGS** (re-verification after the C1 remediation, canonical) ·
0 blockers · 0 CRITICAL · **24 requirements / 72 scenarios, all COMPLIANT** · 2 WARNING, 3 SUGGESTION.
Admitted by `gentle-ai sdd-verify-validate --requirements 24 --scenarios 72` → `{"valid": true,
"verdict": "pass"}`.
**Artifact store**: hybrid (OpenSpec canonical + Engram mirror, project `swiftui_cellar`).
**Review gate**: structurally **absent**. `gentle-ai review mode status` reports
`receipt-driven development: off (decided by clone_local)`, so receipt-driven development does not exist
for this candidate, zero review code ran, and there is no `reviewGate` key to read or block on. Delivery
follows ordinary repository policy. `gentle-ai sdd-status npm-package-source` reported
`dependencies.archive: ready`, `taskProgress 57/57 allComplete: true`, `applyState: all_done`,
`blockedReasons: []`, `actionContext.mode: repo-local` with `allowedEditRoots` = the repository root.
Every operation in this phase stayed inside that root.

This report is the terminal record of the cycle. It describes the state of the change **at close**, not
the state at any earlier point. `apply-progress.md` and `verify-report.md` are intermediate snapshots
archived alongside it; where either disagrees with the final state, the final state is recorded here and
the snapshot's claim is attributed to its own moment rather than restated as a current fact.

## 1. Facts that moved after the snapshots were written

| Fact | Snapshot claim | State at close |
|---|---|---|
| Verify verdict | the pre-remediation run reported **`fail`** on C1 (`brew-detection` BD-A1 scenario 2 shipped untested) | **Superseded.** The canonical report is the re-verification after remediation: **`pass_with_warnings`**, C1 closed. The superseded run's verdict is history, not current state |
| C1 | "**BD-A1 scenario 2 is uncovered**" | **Closed.** `NpmDetectionStoreTests.heldNpmEvaluationDoesNotCoupleToBrewDetection` (`:207`) passes at runtime in 2.167 s. **No production file was touched** by the remediation — task 1.11's *text* was the defect, and it now names both BD-A1 scenarios |
| CellarCore test count | 2127 tests / 244 suites (pre-remediation) | **2128 tests / 244 suites**, exit 0, 1 **pre-existing** known issue (`OperationCenterCancelTests.swift:195`). Up exactly one — the added C1 test |
| App unit count | "**328**" (`apply-progress.md`, Engram `#7975`) | **354 unique** (365 case executions), 0 failed, measured on the same tree in both verify rounds. A measurement-method difference, **not a regression** — recorded as S2 |
| UI count | 38 | **38, 0 failures** — unchanged |
| Working tree | "staged, **uncommitted**" (`tasks.md`, `apply-progress.md`) | **Committed and pushed** as `ef1000e`, one commit over `main`; **PR #92 open**, not merged |
| Budget standing | `tasks.md` says the cumulative tree is "**well past the accepted 8,000 budget** — flagged for the maintainer" | **Resolved by maintainer ruling, not absorbed.** Engram `#7968` (topic `sdd/npm-package-source/decisions`, 2026-08-30): the 8,000-line budget counts **production** lines. Production is **3,742**, measured again by this phase — **inside** the budget. Single PR stands with an explicit `size:exception` |

Two launch-brief facts were checked and **corroborated** by independent measurement: production lines at
**3,742** (`Packages/*/Sources` 2,874 + `cellar/` 868, recomputed here from `git diff --numstat
main...HEAD`, matching `verify-report.md` line for line), and **zero `.xcodeproj` paths** in the diff.

## 2. Specs synced

| Domain | Action | Delta applied | Requirements | Scenarios |
|---|---|---|---|---|
| `npm-source` | **Created** | new capability, 10 ADDED / 26 | `0 → 10` | `0 → 26` |
| `installed-inventory` | Updated | 3 ADDED (**II17–II19**) | `16 → 19` | `82 → 93` |
| `package-mutation` | Updated | 3 ADDED (**PM11–PM13**) + 1 MODIFIED (**PM7**) | `10 → 13` | `63 → 71` |
| `menu-bar` | Updated | 1 ADDED (**MB11**) + 1 MODIFIED (**MB1**) | `10 → 11` | `25 → 29` |
| `installation-history` | Updated | 1 ADDED (**IH10**) | `9 → 10` | `33 → 37` |
| `brew-execution` | Updated | 1 ADDED (**BE7**) | `6 → 7` | `22 → 25` |
| `operation-activity` | Updated | 1 ADDED (**OA7**) | `6 → 7` | `24 → 27` |
| `brew-detection` | Updated | 1 ADDED (**BD6**) | `5 → 6` | `17 → 19` |
| `system-health` | Updated | 1 ADDED (**SH12**) | `11 → 12` | `51 → 54` |

**Totals: 22 ADDED + 2 MODIFIED = 24 requirements, 72 scenarios** — matching the verified figures
exactly (`22` added requirement bodies carrying 61 scenarios, plus MB1's 5 and PM7's 6). Counts above are
**recounted mechanically from the merged files** (`### Requirement:` / `#### Scenario:` occurrences), not
trusted from any delta header.

**`rules.archive`'s destructive-delta warning did not fire.** Nothing was removed or renamed in any of
the nine specs: `0 REMOVED`, `0 RENAMED` across the whole change. Both MODIFIED blocks preserve **every**
shipped scenario byte-identical and only add:

- **MB1** — 6 lines replaced, 14 added, **4/4 shipped scenarios byte-identical**, 1 appended. The
  replaced text is two prose paragraphs: three pure inputs became **four** (adding npm outdated
  freshness), and "no freshness cue in this slice" became "the only freshness cue is the npm one".
- **PM7** — 6 lines replaced, 28 added, **4/4 shipped scenarios byte-identical**, 2 appended. The
  replaced text scopes the family rule to **Homebrew-sourced** families and adds the per-source
  availability paragraph.

**One historical note was superseded, and is recorded here rather than passed over.** PM7's earlier
`(Previously: the rule was written for package mutations only, …)` note is replaced by a new
`(Previously: …)` note describing the per-source split. That is the only non-additive text in the whole
merge beyond the two reworded paragraphs above. The superseded wording survives verbatim in this
archived delta and in the earlier change that wrote it, so nothing was lost.

## 3. Mechanical operations, with mandatory readbacks

Every promotion was performed with shell byte-slicing (`sed -n`, `cp`) and every move with `git mv`,
each verified by `diff`. **No artifact content was routed through a model Read/Write path.** Twenty-six
readbacks, **all empty, all exit 0**.

| # | Operation | Readback | Result |
|---|---|---|---|
| 1–6 | `brew-detection`, `brew-execution`, `installation-history`, `installed-inventory`, `operation-activity`, `system-health`: ADDED block spliced before `## Provenance` | `diff` promoted block in the build vs the delta slice | **all empty, exit 0** |
| 7–12 | the same six, additive-only check | `diff` pre vs build: **0 deleted lines** in every one (added 37 / 48 / 63 / 132 / 43 / 49) | **additive only** |
| 13–16 | `menu-bar`: MB1 replaced from delta `:44-105`, ADDED from `:11-40` | four `diff`s — MB1 bytes, untouched middle (MB2–MB10), ADDED bytes, prior `## Provenance` | **all empty, exit 0** |
| 17–20 | `package-mutation`: PM7 replaced from delta `:88-150`, ADDED from `:13-84` | four `diff`s — untouched head (PM1–PM6), PM7 bytes, untouched tail (PM8–PM10), ADDED bytes, prior `## Provenance` | **all empty, exit 0** |
| 21–22 | both MODIFIED files, deletion audit | `diff` pre vs build: exactly **6 deleted lines each**, all of them prose, **0 requirement and 0 scenario headings deleted** | **verified non-destructive** |
| 23 | `npm-source` created: authored header (30 lines) + `sed -n '18,325p'` of the delta + authored provenance | `diff` promoted body (new 32–339) vs delta 18–325 | **empty, exit 0** |
| 24 | install of all nine staged builds into `openspec/specs/` | nine `diff`s, staged build vs installed file | **all empty, exit 0** |
| 25 | `design.md` amended with the **Deviations** section | `diff` pre vs post: **0 deleted lines**, 35 added | **additive only** |
| 26 | Archive move `openspec/changes/npm-package-source` → `openspec/changes/archive/2026-08-30-npm-package-source` | **`diff -r` against a pre-move recursive snapshot** (15 files) | **empty, exit 0.** Source directory confirmed gone |

`git mv` succeeded — unlike `m12`, this change folder was already **tracked and committed** (in
`ef1000e`), so the move is recorded as a rename rather than a delete-plus-add. `archive-report.md` is
**additive** and excluded from the comparison because it did not exist in the source snapshot.

**Header prose is authored, requirement bodies are not.** Following the `m12-menu-bar` precedent, the
new `npm-source` main spec adds only a header, the `## Requirements` wrapper and a provenance section
around a byte-identical body; the delta's own delta-local session-preflight block stayed in the archived
delta and was not promoted.

## 4. Task completion

**57 of 57, all ticked, zero `[ ]`.** No archive-time reconciliation was performed and none was needed;
the Task Completion Gate passed on the persisted artifact exactly as `sdd-apply` left it, and
`gentle-ai sdd-status` independently reported `total: 57, completed: 57, pending: 0, allComplete: true`.

Three work units in dependency order: **Unit 1** (1.1–1.28, identity, detection, read-only inventory,
Settings, chip, tag) · **Unit 2** (2.1–2.18, mutations) · **Unit 3** (3.1–3.11, cadence and copy). Strict
TDD throughout — RED named before GREEN for every behavioural task.

## 5. Tests at close

| Suite | Command | Exit | Result |
|---|---|---|---|
| CellarCore | `swift test --package-path Packages/CellarCore` | **0** | **2128 tests / 244 suites passed**, 1 **pre-existing** known issue (`OperationCenterCancelTests.swift:195`) |
| App unit | `xcodebuild test -scheme cellar` (`cellarTests`) | **0** | **354 unique / 365 executions, 0 failed** |
| UI | `cellarUITests` | **0** | **38 tests, 0 failures** (incl. `NpmSourceToggleUITests`) |

`** TEST SUCCEEDED **`, zero failed cases in either suite. **Neither known load-dependent flake
recurred** — `CatalogFootprintTests` (footprint bound) and `MutationRefreshReceiptTests` (tap terminal)
both passed, so no isolation re-run was needed. Those two remain **known pre-existing flakes** and are
recorded as such, not as anything this change introduced.

## 6. Delivery footprint

`git diff --shortstat main...HEAD` → **129 files changed, 12,504 insertions, 174 deletions**, in a single
commit `ef1000e` `feat(npm): add npm global packages as a second package source`.

Insertions by bucket, recomputed by this phase:

| Bucket | Insertions |
|---|---|
| `Packages/*/Sources` | 2,874 |
| `cellar/` (app target) | 868 |
| **Production total** | **3,742** |
| `Packages/*/Tests` | 5,489 |
| `cellarTests` | 1,114 |
| `cellarUITests` | 161 |
| **Test/fixture total** | **6,764** |
| `openspec/` | 1,995 |
| `PRD.md` | 3 |

**3,742 production lines against the 8,000-line budget**, delivered as **one PR with an explicit
`size:exception`** by maintainer decision (Engram `#7968`): the budget counts **production** lines, not
tests, fixtures or specs, because strict TDD produced 6,764 test lines that reviewers weigh differently.
`openspec/config.yaml`'s `review_budget_lines` was raised **5000 → 8000** in this change, and its
`rules.proposal` milestone range widened **M1..M12 → M1..M13**.

**`cellar.xcodeproj/project.pbxproj` is not in the diff.** The rollback plan's central claim holds: no
project-file edit and no target-membership change were needed, because `cellar/` and `cellarTests/` are
`PBXFileSystemSynchronizedRootGroup`s. The change is revertible by `git revert` of a single commit, and
the three work units are revertible 3→2→1.

## 7. Design deviations — nine, all spec-driven, all accepted

`design.md` in this archive carries an appended **Deviations** section listing them in full. In summary:
namespaced `npmUpgrade`/`npmUninstall`; a new `MutationOutcome.networkUnavailable`; `[AnyBrewMutation]`
as the bulk return type; `HistoryRow` source badge **plus** command prefix; `HomeAttentionCopy`;
`InstalledEmptyState.isNpmEmptiness`; `InstalledBrowse.withNpmSource`; a Homebrew-only Health
denominator; and a sixth `MenuBarProjection` member for npm freshness.

**Every one is driven by delta spec text**, which outranks the design when the two disagree, and each was
located and accepted during verification. None is unreviewed drift. Four were recorded during apply in
Engram `#7973`; the remaining five were surfaced by unit 3 and by verification.

**One genuine defect, found late and fixed.** Unit 1's `DefaultNpmLocator` resolved symlinks before the
environment was composed, so the PATH prepend pointed at the resolved target instead of the selected
npm's own bin directory. Only unit 3's integration pass could surface it. The fix stores
`NpmEnvironment.binDirectory` and makes `DefaultNpmLocator.validate` take the **candidate** directory.
That is a bug fix, not a deviation, and it is why unit 3 came in at roughly twice its line estimate.

**Both design open questions were answered during apply.** A chain-queued item keeps
`queuePhase == .pending` and reads "Queued" with no explicit assignment in `perform`, so D13's fallback
was never written; `npm` and `corepack` are listed, as the default anticipated.

## 8. Carried warnings and suggestions (recorded, not fixed here)

- **W1 — TDD cycle-evidence tables cover 18 of 57 tasks.** `apply-progress.md`'s explicit RED/GREEN
  evidence table covers Batch 2 (unit 2, 18 tasks) only. Batch 1 (28 tasks) carries prose plus a
  **provider rate-limit note** — the unit-1 worker was interrupted mid-run — and Batch 3 (11 tasks)
  carries a narrative and a defect section with no table. **This is a documentation-hygiene gap, not a
  process gap**: verification independently confirmed the substance, all 29 RED-named test files exist
  and pass, and assertion quality was checked clean across all 32 changed test files. **Not backfilled
  at archive.** Reconstructing cycle tables from memory after the fact would manufacture evidence rather
  than record it; the honest record is that the tables are missing and the substance was verified
  another way.
- **W2 — a count discrepancy between the Engram spec mirror and the canonical file.** Engram `#7972`
  describes `npm-source` as "10 req / 24 sc"; the canonical delta has **26** scenarios, recounted here.
  The canonical file wins, verification counted 26, and the change totals (24/72) were validated against
  the canonical files throughout. **`#7972` was left uncorrected.** Rewriting a completed phase's own
  artifact after the fact would falsify the audit trail; the discrepancy is recorded here and in the new
  `openspec/specs/npm-source/spec.md` provenance instead.
- **S1 — 61 swiftlint default-rule findings on new code**, one of which (`vertical_whitespace` at
  `NpmDetectionStoreTests.swift:254`) arrived with the C1 remediation. **Informational only**: the
  repository has **no `.swiftlint.yml`**, swiftlint is in no build phase and in no CI job, so these are
  default-rule observations against a project that has never adopted them. **Not fixed at archive** —
  a `chore(sdd): archive` commit is not the place to edit a test file, and adopting swiftlint is a
  project decision, not an archive-time one.
- **S2 — app-unit count drift** (328 recorded during apply, 354 unique measured in both verify rounds on
  the same tree). Measurement-method difference; §1 records the measured figure.
- **S3 — footprint recorded, not a finding.** 3,742 production inside the accepted 8,000; 10,506 code +
  tests; 12,504 including `openspec/` and `PRD.md`.

## 9. Working tree at close — one unrelated modification, deliberately not committed

The archive commit contains **only** the spec merges, the archive move, the `design.md` amendment and
this report. Two files were left **unstaged and uncommitted**:

- **`cellar/InfoPlist.xcstrings`** — modified before this cycle began (mtime 2026-08-29 08:40), left
  alone by explicit instruction.
- **`cellar/Installed/InstalledFilterBar.swift`** — **a production edit this phase did not make and
  cannot attribute.** It appeared in the working tree with mtime **2026-08-30 01:22:58**, after the
  canonical verify run completed (00:53) and before this archive phase began. It moves the npm source
  chips onto their own row inside `InstalledFilterBar`, splitting `body` into a `kindRow` plus a
  conditional source row, apparently to stop the two filter dimensions wrapping mid-word.

  **It is recorded, not resolved.** No higher-ranked source corroborates it: it is in no task, no
  scenario, no commit and no verify run, and **the verification evidence in this archive does not cover
  it**. Committing it inside `chore(sdd): archive` would have smuggled unverified production code into
  PR #92 under a chore label, so it was left exactly where it was found. A maintainer should either
  commit it deliberately with its own verification or discard it.

## 10. Artifact traceability (Engram, project `swiftui_cellar`)

| Artifact | Engram observation | Topic | OpenSpec canonical (archived) |
|---|---|---|---|
| explore | `#7966` | `sdd/npm-package-source/explore` | `explore.md` |
| proposal | `#7969` | `sdd/npm-package-source/proposal` | `proposal.md` |
| spec (1 new + 8 deltas) | `#7972` | `sdd/npm-package-source/spec` | `specs/{npm-source,installed-inventory,package-mutation,menu-bar,installation-history,brew-execution,operation-activity,brew-detection,system-health}/spec.md` |
| design (amended at archive) | `#7971` | `sdd/npm-package-source/design` | `design.md` |
| tasks (revision 5) | `#7974` | `sdd/npm-package-source/tasks` | `tasks.md` |
| apply-progress | `#7975` | `sdd/npm-package-source/apply-progress` | `apply-progress.md` |
| verify-report (revision 2, canonical) | `#7976` | `sdd/npm-package-source/verify-report` | `verify-report.md` |
| decisions | `#7968` | `sdd/npm-package-source/decisions` | — (Engram only) |
| gate-notes | `#7973` | `sdd/npm-package-source/gate-notes` | — (Engram only) |
| **archive-report** | **`sdd/npm-package-source/archive-report`** | | **this file** |

All five required artifacts (`proposal`, `spec`, `design`, `tasks`, `verify-report`) were read **in
full** via `mem_get_observation` before any merge or move; `explore`, `decisions`, `gate-notes` and
`apply-progress` were located and read as supporting context. No review topics were read because
`reviewGate` is structurally absent and none exist.

**One traceability caveat.** `#7968` has been upserted **four** times on the `decisions` topic, and its
current revision records only the budget ruling. The seven product decisions the spec artifact cites it
for — one npm by priority, toggle default off, hybrid approach C, serialized cross-source FIFO,
`npm install -g <name>@latest`, Health copy-only, prefix display sufficient — were overwritten by later
revisions of the same topic. They survive verbatim in the archived `proposal.md` and in the `npm-source`
delta's own preamble, which is why this phase did not attempt to reconstruct them into the topic.

## 11. What this change actually settled

Cellar was a Homebrew client that assumed its package source was a fact rather than a parameter. The
mutation spine, the runner, the activity log, history and the inventory each hard-coded `brew` — in the
executable, in the environment, in the display prefix, in the identity. M13's real work was not "add
npm"; it was **turning one assumed source into a projected one** while proving brew's guarantees did not
weaken on the way. `PackageSource` on the shared abstraction, copied through `AnyBrewMutation`, is what
makes an erased npm command structurally incapable of rendering as brew, and `PackageTarget.init?`
rejecting npm identities is what makes a brew argv structurally incapable of naming an npm package —
enforced by a shipped scan, not by review.

It also closed a defect the shipped app already had. **Silence was being reported as health.** With a
second source that can be offline, "everything is up to date" needed a witness, so outdated state became
tri-state and `upToDateCopy` became a `String?` that is *absent* whenever a check has not completed. The
claim is now **unrepresentable** rather than merely discouraged — which is what fixed two live defects in
Home along the way: npm packages being counted as casks, and "Everything on this Mac is current."
appearing over an unreachable registry.

The third settlement is a boundary. Health takes npm as **copy**, not as a scored signal, because a score
that moves for reasons its own remediation control cannot fix is a worse number than a smaller honest
one. The row tells the truth about both sources; the score keeps meaning exactly what the button can act
on.

## 12. Note for anyone who runs `gentle-ai sdd-status npm-package-source` after this archive

It will fall back to the Engram topics and report figures that look wrong. **That is a fallback
artefact, not a regression.** With the change folder moved out of `openspec/changes/`, the status command
finds no OpenSpec change. Immediately **before** the move, with the OpenSpec artifacts still in place,
it reported `artifactStore: openspec`, `taskProgress 57/57 allComplete: true`, `applyState: all_done`,
`dependencies.archive: ready`, `nextRecommended: archive`, `blockedReasons: []`. That is the reading the
gates were evaluated against, and `openspec/changes/archive/2026-08-30-npm-package-source/tasks.md` — 57
ticked boxes, zero `[ ]` — is the durable evidence.

## 13. Delivery state at archive, and what remains

Branch `feat/npm-package-source` at `ef1000e` plus this archive commit, **pushed**, with **PR #92 open
against `main`** (`https://github.com/juancasanueva/SWIFTUI_cellar/pull/92`) and **not merged**. The nine
promoted main specs and this archived folder therefore describe behaviour that exists **on the branch
only** until that PR lands; every provenance entry written by this phase says so explicitly, so a future
reader cannot mistake a promoted spec for shipped `main` behaviour.

Remaining for the maintainer, in order: review and merge PR #92; decide what to do with the uncommitted
`InstalledFilterBar.swift` edit (§9); and optionally tag a release. None of that is an SDD phase, and
none of it is blocked by anything in this cycle.
