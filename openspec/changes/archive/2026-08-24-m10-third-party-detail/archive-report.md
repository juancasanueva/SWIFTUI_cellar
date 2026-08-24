# Archive Report: `m10-third-party-detail`

**Archived**: 2026-08-24 · **Milestone**: PRD **M1 "Core & Catalog"** (§7 :202) — the package-detail
promise of **§3.1** (:53, *"tap of origin"*) applied to the installed-only records of **§3.2** (:59)
delivered in M2. A post-M6 refinement slice; it also completes the surface `m9-per-package-trust`
recorded as PD8's missing anchor.
**Status at close**: implemented, verified across two rounds, **merged to `main` in PR #75** at
`4063ae3`, archived
**Verify verdict**: **PASS WITH WARNINGS** · 0 blockers · 0 CRITICAL · **3 requirements / 25 scenarios,
all COMPLIANT** · the single WARNING (task 6.7, the PR) discharged **after** the report was written
**Artifact store**: hybrid (OpenSpec canonical + Engram mirror, project `swiftui_cellar`)
**Review gate**: structurally **absent** — RDD disabled, no review started, delivery under ordinary
repository policy

This report is the terminal record of the cycle. It describes the state of the change **at close**, not
the state at any earlier point. `apply-progress.md` and `verify-report.md` are intermediate snapshots
archived alongside it; where either disagrees with the final state, the final state is recorded here and
the snapshot's claim is attributed to its own moment rather than restated as a current fact.

**Six facts moved after those snapshots were written**, and this report carries the later value in each
case:

| Fact | Snapshot claim | State at close |
|---|---|---|
| Task 6.7 (open the PR) | "**OPEN by instruction** — the one remaining WARNING" (`verify-report.md` W4); "51 / 52" (Engram tasks mirror `#7786`) | **Closed in `e93829b`** on the feature branch, before merge. `tasks.md` is **52 / 52** in the archived artifact; this phase reconciled nothing |
| The PR itself | "The PR is not opened and nothing is pushed" (`verify-report.md` W4) | **PR #75 opened, then merged** 2026-08-24 19:40:49 UTC at `4063ae3` |
| Branch size | "**3,894** changed lines / 5,000 (78 %)" (`verify-report.md`, measured at `7ee4c35`) | **3,904** at the merged tip — `git diff --shortstat 5a0860b 4063ae3` → `17 files changed, 3863 insertions(+), 41 deletions(-)`. `e93829b` added the 10-line difference. **78 %** either way |
| Commit count | "**10 commits** off `main`" (`verify-report.md`, round 2) | **12 commits** on the merged branch (`38f1f90` … `e93829b`) |
| Test counts | "CellarCore 1,825 → **1,837**; `cellarTests` 239 → **245**" (Engram tasks mirror `#7786`, written at apply time) | **CellarCore 1,838 / 216 suites**, **`cellarTests` 246** — round 2's own +143 test lines landed after that mirror was saved |
| DD-11's real diff | "**3 additions / 2 deletions**" (Engram tasks mirror `#7786`) | **`4+ / 3−`**, corrected in round 2 (verify S5) and measured again there |

Two verify SUGGESTIONs were assigned to this phase and are discharged here, in §5 and §6: **S1** (the
design's fact-inventory row order) and **S8** (sc12's positive copy anchor). The rest are carried open
in §11.

---

## 1. Milestone linkage

- **Closes the M1 §3.1 package-detail promise for records the catalog does not carry.** `Home-Cellar` —
  installed from the maintainer's own tap — opened to `ContentUnavailableView("No further details")`,
  and so did every tap-only, unpublished or locally-built package. The receipt Cellar **already
  decoded** held the version story, kegs, link state, pin state, auto-updates flag, homepage and tap of
  origin.
- **The defect was an unkept promise, not a missing feature.** `installed-inventory` **II7** already
  required such a package to be "listed with everything the snapshot knows about it". The list kept
  that promise; the detail surface was the one place it was broken. II15 extends the same promise to
  the detail surface **without touching II7's join rule**.
- **It also completes `m9-per-package-trust`.** That change's archive recorded PD8 as *"expected to
  render nothing on today's shipped surface, and that is the point … it becomes visible only when a
  third-party detail surface arrives. Not a defect — but it must not be mistaken for dead text and
  deleted."* m10 is that surface. PD8 was **activated, not amended**: m10 carries **no `package-trust`
  delta** at all.
- **The change acquires nothing.** No new brew invocation, no new store, no DI line, no routing change,
  no `Process`, no `await` in the render path. The whole detail is composed from data already resident.
- **Two facts were deliberately not rendered**, and both are recorded as blocked rather than forgotten:
  an install date (the decoder collapses a missing timestamp to the Unix epoch) and any "latest
  version" fact (the decoder falls the receipt's current-version value back to the installed keg's own).

## 2. Delivery references

| Item | Value |
|---|---|
| Base | `main` at `5a0860b` |
| PR | **#75** — https://github.com/juancasanueva/SWIFTUI_cellar/pull/75 |
| PR title | `feat(installed): detail a package the catalog does not carry from its receipt` |
| PR merged | **2026-08-24 19:40:49 UTC**, merge commit **`4063ae3`** on `main` — **12 commits** |
| Branch | `feat/m10-third-party-detail`, `38f1f90` … `e93829b` (deleted locally after merge) |
| Size at close | **17 files, +3,863 / −41 = 3,904 changed lines** — **78 %** of the governing 5,000 |
| Delivery strategy | `single-pr`, honoured as cached. **No `size:exception`, no chain** — the guard never fired against the governing budget |
| PR labels | none (`gh pr view 75 --json labels` → empty). None was required: no exception was taken |
| Archive branch | `docs/sdd-archive-m10-third-party-detail`, from `main` at `4063ae3` |

**Commits on `feat/m10-third-party-detail` (PR #75):**

| # | Commit | Subject |
|---|---|---|
| 1 | `38f1f90` | **WU1** `docs(sdd): record the m10-third-party-detail proposal, spec deltas, design and tasks` |
| 2 | `1aedbf7` | **WU2** `refactor(browse): share the detail header helpers across both panes` |
| 3 | `3d2527e` | **WU3** `feat(installed): derive a reduced detail from one installed receipt` |
| 4 | `e3cab43` | **WU4** `test(installed): pin that a receipt-backed detail never touches the catalog` |
| 5 | `65a65cb` | **WU5** `feat(browse): show a receipt-backed detail for packages the catalog does not carry` |
| 6 | `3545328` | `docs(sdd): record the m10-third-party-detail apply progress and TDD evidence` |
| 7 | `1b71d4c` | `docs(sdd): record the m10-third-party-detail round-1 verify report` |
| 8 | `d5f51e1` | `test(installed): assert the withheld-tap marker absence and drop a vacuous launcher` (**discharge W2/W3**) |
| 9 | `177fe85` | `test(browse): pin the grant marker to the inside of the tap guard` (**discharge S2**) |
| 10 | `7ee4c35` | `docs(sdd): correct the m10 line accounting and record the round-2 remediation` |
| 11 | `b6f8570` | `docs(sdd): record the m10-third-party-detail round-2 verify report and scope task 6.2 to the declared runners` |
| 12 | `e93829b` | `docs(sdd): close task 6.7 for m10-third-party-detail with PR #75` |

No `Co-Authored-By` and no AI attribution on any of the 12 commits. All conventional, one work unit per
behavioural commit.

## 3. Review gate

`reviewGate` is **structurally absent** from this change's status, and that is the expected shape, not a
defect to investigate:

- Receipt-driven development is **disabled** for this repository (session preflight `RDD disabled`).
  With the kill switch off, zero review code ran for this candidate, so no transaction, ledger, receipt
  or gate context was ever created and none exists to read.
- There is therefore **no `disabled/unmanaged` value to check** and **no approval to fabricate**.
  Delivery of PR #75 proceeded under **ordinary repository policy**, and archive proceeds the same way.
- Consequently the `sdd/m10-third-party-detail/review/*` Engram topics do not exist and were not read.

## 4. Task completion gate

**Gate PASSES at 52 / 52, with no archive-time reconciliation of any kind.**

| Task group | Items | Closed by |
|---|---|---|
| Phases 0–5, 7, and phase 6 except 6.7 | 51 | `sdd-apply` during the cycle, ticked in the persisted artifact |
| `6.7` open the PR | 1 | **PR #75** — ticked in `e93829b`, **on the feature branch, before the merge** |

This is the first change in the project where the delivery task closed itself inside the branch rather
than at archive. `sdd-archive` inspected `openspec/changes/m10-third-party-detail/tasks.md` and found
**52 `[x]` and zero `[ ]`**; the strict gate passed on the artifact as apply left it, so this phase
performed **no** stale-checkbox repair and none was authorized or needed.

**`apply-progress.md` was deliberately not edited.** Its round-2 section still lists W4 (task 6.7) as
"open, unchanged and by instruction". That is a true statement about the moment it was written and a
false one about the state at close; the correction lives here, in the terminal record, rather than being
backdated into a snapshot. The same applies to the Engram tasks mirror `#7787`/`#7786` — see §10.

## 5. Spec sync

Three deltas promoted. **Final totals, recounted mechanically from the merged files** rather than
trusted from any delta header:

| Capability | Action | Delta | Before | **At close** |
|---|---|---|---|---|
| `installed-inventory` | Updated | 1 ADDED (**II15**): 12 sc (7 `unit`, 5 `unit-app`) | 14 req / 67 sc | **15 req / 79 sc** |
| `package-detail` | Updated | 1 MODIFIED (**PD6**): 3 sc replace 2 | 8 req / 30 sc | **8 req / 31 sc** |
| `tap-management` | Updated | 1 MODIFIED (**TM5**): 10 sc replace 9 | 13 req / 57 sc | **13 req / 58 sc** |

Every total matches the end state its delta declared. **1 ADDED, 2 MODIFIED, 0 REMOVED, 0 RENAMED**, so
`rules.archive`'s destructive-delta warning did not fire anywhere and no confirmation prompt was owed.
`package-trust` received **no delta**: PD8, PT3, PT5, PT6 and PT7 were **activated**, not amended.

**No `## Verification classes` table was promoted.** None of the three main specs carries one today —
only `app-updates` and `release-distribution` do — so each delta's class table stayed delta-local
provenance in the archived change folder, and only the per-scenario inline `- Verification:` lines
promoted with their requirements. This follows the precedent `m7-tap-trust` recorded at
`openspec/specs/installed-inventory/spec.md:948`. Verified after the merge: `rg '^## Verification
classes'` matches **zero** lines in all three files.

### One delta-header claim that did not survive an independent check

Both MODIFIED deltas claim their block "is a strict superset of the text it replaces". Byte-sliced
against a pre-merge copy of the exact replaced range:

- **`package-detail` PD6 — byte-true.** The diff returns **additions only, zero deletions**. Both
  existing scenarios are byte-identical and the clause "MUST NOT appear in search results" is reproduced
  verbatim.
- **`tap-management` TM5 — not byte-true.** **Two non-blank lines were rewritten**, not merely added
  to: `…PD6 remains unchanged and selection MUST NOT create a third-party detail fallback.` became
  `…PD6 remains unchanged. Selecting a tap package MUST NOT create a **catalog** record for it and MUST
  NOT perform a tap-source read to complete a package detail — that is the whole of this prohibition.`
  The delta itself discloses the edit one sentence later ("the only edited sentence is the final one of
  the withheld-tap paragraph"), so the header contradicts itself rather than concealing anything.

**No rule was removed or weakened in either case.** TM5's prohibition survives in its stated meaning,
the old wording is preserved verbatim in the block's new `(Previously:)` note, and the clause gained an
explicit statement that it does not reach a detail composed exclusively from the installed receipt. The
claim was "strict superset"; the truth is "superset in rules, with one sentence rescoped". Recorded
because it is exactly the kind of difference a future reader would otherwise assume away — and because
`m9-per-package-trust` found the identical pattern in its own `tap-management` delta. **Twice now, the
`tap-management` delta's superset claim has failed the check while its sibling's held.**

### The m9 TM1 → TM5 mis-citation, corrected in provenance

`2026-08-24-m9-per-package-trust` states in at least three places (`archive-report.md:440`,
`tasks.md:72`, `specs/package-detail/spec.md:20`) that **TM1** forbids a third-party detail fallback.
That is a **mis-citation**:

- **TM1** — *"One structured snapshot supplies tap list and detail"* — is a one-invocation rule about
  acquiring **tap** detail from `brew tap-info --installed --json`. It contains no detail-fallback
  clause and was **not touched** by this change.
- The clause was **TM5's**, in its catalog paragraph, and m10 narrowed it to its meaning.

The correction is recorded in **both** `openspec/specs/tap-management/spec.md` and
`openspec/specs/package-detail/spec.md` provenance, each naming the m9 citation explicitly so it cannot
be carried forward unqualified. **TM1 does contribute a genuine constraint that m10 honours**: no
additional brew invocation may be introduced to complete a detail — asserted by II15 sc2 and TM5's added
scenario.

Following the `m9` precedent, **no existing provenance entry was edited, reordered or removed**. The m9
entries stand as the audit trail of what was believed; the new entries supersede their citation.

### Hand-edits made outside the promoted blocks

Additive only: one `## Provenance` entry per capability. Each append was verified additive by diffing the
pre-append file against the head of the post-append file — **all three empty**.

## 6. What shipped

### Behaviour

- **A pure value, and that is the load-bearing decision.** `InstalledDetailProjection` is a total,
  `nonisolated`, `Sendable`, `Hashable` derivation over **one** `InstalledPackage`: no catalog value, no
  store, no clock, no `Process`, no SwiftUI. That is what lets the whole requirement be asserted in the
  `swift test` inner loop, and what makes the pane cost no brew invocation at all.
- **The kind asymmetry is unrepresentable, not merely unwritten** (DD-2). `KindState` is a sum type, so
  a cask value has **no place to put** a link state and a formula value none for `auto_updates`. A later
  edit cannot break II15's "a fact only for the kind that can publish it" — only a deliberate type
  change can.
- **Absence is omission** (DD-3). No `""`, no `unknown`, no dash. `present(_:)` also treats a published
  empty string as absence, so a payload cannot re-collapse at the last hop the distinction
  `InstalledModels.swift` exists to preserve.
- **PD8 attaches without a marker field** (DD-4). `tapOfOrigin` is its own optional member; the view
  joins the marker under the **same** `if let tap = snapshot.tap` guard that produced the fact, so
  `tap == nil` yields no fact **and** no marker from one guard rather than two that could disagree. The
  copy comes from `TapProjection.grantMarker` — the pane composes none.
- **The verbs are the installed row's, byte-unchanged** (DD-8). `MutationMenu(center:entry:)` is not in
  the branch diff at all; `InstalledRow.swift:61` already rendered it for `catalog: nil` entries, so the
  confirmation rule, the argv validation and the unavailable-runner guidance arrive already proven.
  Risk **R4** (an upgrade tripping brew's interactive trust prompt) is therefore *inherited unchanged
  from the row it already ships on* — m10 neither creates nor widens it.
- **The file split had a compile-time consequence, and it was the whole point of DD-9.** Swift `private`
  is file-scoped, so five helpers dropped `private` and a new internal `factLink` was **extracted** from
  the catalog pane's inline homepage block — removing an existing duplication rather than adding one.
  `favoriteButton`, `statusBadge` and `factLabel` stayed private.
- **Two facts stay view-side by design** (DD-7). `Installed as` and `Size on disk` are joined at
  presentation from stores that already answer for the same `PackageID`, because both answers change
  between renders and a `Hashable` value must not carry them.

### Binding 0-line diffs, held end to end

| Path | Requirement | Result at close |
|---|---|---|
| `cellar.xcodeproj/project.pbxproj` | 0-line diff — `cellar/Browse/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup` roots | ✅ empty |
| `openspec/specs/**` | untouched until archive | ✅ empty pre-archive |
| `cellarUITests/` | untouched | ✅ empty across the whole branch |
| `MutationCommand.swift`, `TapCommand.swift`, `TapProjection.swift` | untouched | ✅ empty |
| `InstalledDecoder.swift`, `InstalledModels.swift` | untouched — the epoch defect is *not* fixed here | ✅ empty |
| `scripts/`, `.github/workflows/` | untouched | ✅ empty |

The rollback plan's condition — *"if a non-zero `project.pbxproj` diff appears, that is a defect, not a
rollback step"* — never triggered.

### Deviations from design, all recorded

| # | Deviation | Disposition |
|---|---|---|
| 1 | `orderedFacts` added to the projection | **Additive.** Without it, "the groups keep their order" would be an order the *test* assembles rather than one the *type* exposes — a weak assertion for II15 sc1's central clause |
| 2 | `PerPackageTrustCompositionTests.swift` edit is `4+ / 3−`, not DD-11's "exactly 2 lines" | **Reported, not absorbed.** The extra lines are a comma the preceding array element needs and one word in a comment that said "all three files" beside an assertion now naming four. Corrected from an earlier "3+ / 2−" claim at round 2 (verify S5) |
| 3 | Fact labels chosen where the spec pins only values | **Recorded.** All unique: `Type`, `Homepage`, `Tap`, `Version`, `Link state`, `Other versions`, `Pin state`, `Updates`. `Pin state` reuses `InstalledRow.swift:189`'s shipped copy so the two surfaces say the same thing |
| 4 | Install-state fact ordering: the pane renders `Version, Link state, Other versions, Pin state, Installed as, Size on disk`; the design's table listed the two view-side facts **first** | **The code stays; the document was corrected at archive — see below (verify S1)** |

### S1 — discharged: the design's fact-inventory table now matches its own prose

`verify-report.md` S1 asked for this correction at archive, and `apply-progress.md` recorded the
deviation so the correction would have a source. Both were right that the **document** was the thing to
move:

- DD-7's operative verb is "**appended** into the install-state group by the pane", which is what the
  code does (`PackageDetailView+Receipt.swift:116-128` — `ForEach(detail.installStateFacts)` first, then
  `Installed as`, then `Size on disk`). The design's table and its own prose disagreed; **the prose is
  the decision.**
- II15 mandates ordering only *between* the three groups (identity → origin → install state), never
  within one. No spec clause breaks either way.
- Aligning the code instead would have meant changing shipped rendering order to satisfy a table, with
  no requirement asking for it.

**The archived `design.md` fact-inventory table was corrected before the archive move**: the two rows
`Installed as` and `Size on disk` now sit **after** the kind-specific facts, with a labelled
*Archive-time correction* note directly beneath the table stating what moved, why, and that no code, no
test and no requirement moved with it. Only those two table rows were reordered. The correction was made
in the change folder **before** the recursive snapshot was taken, so the mechanical move readback in §10
is still an empty `diff -r`.

Task **7.4**'s open presentation question was closed in the same edit: `MutationMenu` sits in the
header's primary-button slot, **left of the heart** — the slot `EmptyView()` occupied, unchanged in
position (`PackageDetailView.swift:405` `primaryButton()`, then `:407` `favoriteButton(for: id)`). No
requirement depends on it. The design's `## Open Questions` checkbox is now `[x]` with the shipped answer
named, so the archived artifact carries no stale open question.

### S8 — recorded: sc12's positive anchor now leans on an unrelated line

`verify-report.md` S8 is **recorded here as an open follow-up, not closed**, because closing it would
mean editing a shipped test for a hazard that has not yet bitten:

- II15 sc12 (`theScopedCatalogMissCopyIsUnchanged`) asserts the footer sentence is present by scanning
  shipped source. Its positive anchor is `shipped.raw.contains(sentence)`.
- **WU5 removed the pane's own occurrence.** `PackageDetailView.swift` carried the catalog-miss sentence
  **twice** on `main`; `uncatalogedContent`'s `ContentUnavailableView` description was replaced by the
  new pane, leaving **one** occurrence — the pre-existing fallback at `PackageDetailView.swift:61`,
  which fires when there is **no installed record at all**. That is a different code path from the one
  sc12 is about.
- **The consequence, stated plainly**: correcting or rewording that unrelated fallback copy would fail
  sc12's test even though the receipt pane is entirely correct — and, conversely, deleting the pane's
  footer would *not* fail it. The assertion is currently satisfied by the wrong line. The pane's own copy
  is separately pinned byte-exact (the verifier hexdumped
  `PackageDetailView+Receipt.swift:170` → `43 65 6c 6c 61 72 e2 80 99 73`, U+2019 confirmed), so nothing
  is unguarded today; what is missing is that sc12's anchor is not **file-scoped to the pane**.
- **Follow-up**: re-anchor sc12's positive assertion to `PackageDetailView+Receipt.swift` specifically.
  Carried open in §11, item 3.

## 7. Verification

### Two rounds

| Round | Commit verified | Verdict |
|---|---|---|
| 1 | `1b71d4c` (branch @ `3545328`) | **FAIL** on *evidence completeness only* — 0 blockers, 0 CRITICAL, 4 WARNING, 7 SUGGESTION, 3/3 requirements, **24/25** scenarios |
| 2 | `b6f8570` (branch @ `7ee4c35`) | **PASS WITH WARNINGS** — 3/3 requirements, **25/25** scenarios, 0 blockers, 0 CRITICAL, 1 WARNING, 6 SUGGESTION |

Round 2 is canonical and supersedes round 1 in the archived `verify-report.md`; round 1's findings
survive only in round 2's disposition table and here. The Engram topic was upserted, so round 1's report
does not survive in Engram at all.

Round 1's two real gaps were discharged by maintainer-authorized `sdd-apply` units, not argued away:

- **W2** — II15 sc7's second THEN ("carries no per-package grant marker") had no covering assertion.
  Discharged in `d5f51e1` by `aWithheldTapCarriesNoGrantMarkerEither`, which proves the marker is
  **structurally unrepresentable** using `Mirror`, plus `177fe85`'s `unit-app`
  `theReceiptPaneResolvesTheMarkerOnlyUnderTheTapGuard`, which asserts brace-depth containment inside
  the one tap guard.
- **W3** — a vacuous `RecordingProcessLauncher` assertion pair. Discharged: no occurrence remains
  anywhere in the test file.

**No production line was written in round 2.** Both edits are test-side; the two production files
touched during the round were touched only as deliberate RED mutations and restored byte-identical
before anything was committed.

### The verifier's own mutation testing

The round-2 verifier independently mutation-tested both new assertions rather than trusting them:

| Mutation | Observed | Restoration |
|---|---|---|
| Added `public let grantMarkerNote: String? = nil` after `kindState` in `InstalledDetailProjection.swift` | `aWithheldTapCarriesNoGrantMarkerEither` **failed with 3 issues** | SHA-256 back to `19b03052…`, diff empty, test passed |
| Hoisted the marker call above the tap guard in `PackageDetailView+Receipt.swift` | the new case **failed**; **all six other cases passed**, sc10's included | SHA-256 back to `e9b3bf2d…`, tree clean, `** TEST SUCCEEDED **` |

The second row independently reproduces the exact gap S2 named: before `177fe85`, sc10's marker test did
not pin the binding, so hoisting the call out of the guard went undetected.

### The scoped-runner decision, and why it is not a concealment

Round 1's declared runner was the **full** `xcodebuild test -scheme cellar`, which exits **65** on two
`cellarUITests` cases — `testTapsNavigationOfficialSourcesAndAddConfirmation` (`cellarUITests.swift:209`)
and `testTapDetailFilteringInstalledHandoffAndForceDisclosure` (`:231`), both in the Taps section. Round
1 reproduced **both on unmodified `main` @ `5a0860b`** in a separate worktree, so they are pre-existing
and were red before m9 as well.

**Maintainer decision, applied as binding**: they are tracked for a **separate follow-up PR**, not fixed
here. For m10 the declared runners are therefore the scoped ones. Three things keep that honest rather
than convenient:

1. `cellarUITests/` holds a **zero-line diff** across the whole branch — neither case is on a surface
   m10 touches.
2. The failures are disclosed in `apply-progress.md`, in `verify-report.md`'s *Out-of-scope tracked
   items*, and **in the PR #75 body**.
3. `tasks.md:319` (task 6.2) still declares the full-scheme runner and is ticked — verify **S9** named
   this as stale text. It is recorded here as a stale artifact line rather than silently rewritten: the
   task was genuinely performed against that runner in round 1, and its result is the disclosure above.

## 8. Test, gate and size state at close

| Gate | State |
|---|---|
| `swift test --package-path Packages/CellarCore` (class `unit`) | ✅ **1,838 tests / 216 suites, 0 failures**, 1 pre-existing known issue (`OperationCenterCancelTests.swift:183`, `withKnownIssue`) |
| `xcodebuild test … -only-testing:cellarTests` (class `unit-app`) | ✅ `** TEST SUCCEEDED **`, **246 distinct tests**, 0 failures |
| `xcodebuild build … -scheme cellar` | ✅ `** BUILD SUCCEEDED **`, **0 compiler warnings** |
| `xcodebuild test … -scheme cellar` (full scheme) | ❌ exit **65** on two **pre-existing** `cellarUITests` Taps cases — tracked as its own PR (§7, §11 item 1) |
| Review gate | ➖ structurally absent — RDD disabled (§3) |

All 20 tests of the change were observed passing **by name** by the round-2 verifier: 13 `unit` (each
`@Test` display name matched to its own `passed after` line) and 7 `unit-app`.

The `cellarTests` figure is **246 distinct tests**. `m9`'s archive recorded "248 passing results" for the
same target — the two numbers count different things (distinct test cases vs. passing result rows) and
are **not directly comparable**; nothing regressed. `cellarTests` gained 6 cases and CellarCore gained 13
across the cycle.

### Size against the governing budget

| Bucket | Forecast | **Measured at close** | Miss |
|---|---|---|---|
| Code + tests (7 files) | 1,201 – 2,167 (bottom-up 632–942 × 1.9–2.3) | **+1,382 / −41 = 1,423** | **inside the band**, near its low end |
| SDD artifacts (10 files) | counted, band fixed at the high end by task 0.4 | **+2,481** | the larger bucket, as forecast |
| **Branch total (17 files)** | ~1,710 – 4,130 | **+3,863 / −41 = 3,904** | **78 %** of 5,000 — inside the band |

**The `m9` learning was applied and it worked.** m9 recorded: *"the next forecast should name
`apply-progress.md` and the verify report as line items and size `tasks.md` from the scenario count."*
m10's forecast did exactly that — artifacts were **counted, not estimated**, with `apply-progress.md`
(~270) and `verify-report.md` (+250–450) as named line items and **no code-derived correction applied to
the artifact bucket**. The result: the branch total landed inside the forecast band, against m9's +14 %
overshoot. No `size:exception` was needed and no chain was proposed.

The one accounting defect was caught and corrected **inside the cycle**, not at archive: round 1's line
table understated the branch because `apply-progress.md`'s own 256 lines were uncommitted when it
measured itself. Verify **S4** named it; round 2 re-measured and superseded the row totals.

### Attempt ledger

**All attempts settled; no attempt left open at close.** The attempt authority for this archive phase was
acquired in state `proceed` and is not settled by this phase.

## 9. Decisions recorded, with what each rejected

| # | Decision | Rejected |
|---|---|---|
| **Scope** (obs `#7780`) | Facts grouped identity → origin → install state; multi-keg formula shows its primary keg plus a count of the others; homepage as a **link**; the existing scoped copy stays as a **footer**; the surface never claims "third-party tap" | An "Installed on" fact; receipt-backed release notes; any trust control; any negative per-package copy |
| **Approach A** | A pure value in `BrewClient` + a view extension | **B** — `enum DetailSubject` in `Catalog` (inverts II7's asserted dependency) or in `BrewClient` (forces `case receipt` returning nothing across six catalog-only helpers — the empty-row shape PD1 forbids). **C** — synthesizing a `CatalogPackage` (falsifies PD6's covered-tap scenario, turns PD1's absence rows into false catalog claims, needs the very sentinel `InstalledModels.swift:39-47` exists to prevent). **D** — a standalone `InstalledOnlyDetailView` (splits the single detail entry point and re-passes five stores) |
| **DD-2** | The kind asymmetry is a **sum type** | Flat optional fields plus a build-time `switch`; two sibling types with no common parent |
| **DD-4** | `tapOfOrigin` as its own optional member; the marker joined under the same guard | A `marker: String?` field on the Tap fact; passing `TrustGrantState` into the init; finding the Tap fact by matching the label string `"Tap"` |
| **DD-5** | **No "Latest version" and no separate outdated fact** — the shared header owns the version story | Mirroring the catalog pane's `fact("Latest version", …)`, which on this branch would assert a published-version claim the receipt never made |
| **DD-6** | **No "Installed on" fact**, asserted as an absence by test | Rendering `installedAt`; fixing the decoder inside m10 |
| **DD-7** | `Installed as` and `Size on disk` stay **view-side**, appended by the pane | Passing them into the projection init (makes a `Hashable` value stale by construction); omitting `Size on disk` (withholds from this pane a measurement the catalog pane already shows) |
| **DD-8** | The header's primary-button slot takes `MutationMenu(center:entry:)` **byte-unchanged** | Re-implementing Upgrade/Uninstall as accent buttons |
| **DD-9** | Five helpers become internal; `factLink` **extracted** and shared by both panes | Putting the receipt pane in `PackageDetailView.swift`; duplicating the helpers in the extension |
| **DD-11** | Extend the shipped `PerPackageTrustSources.views()` list | A private second scanner in the new test file (a new surface outside the one list escapes the guard — risk **R3**) |
| **DD-12** | The scoped copy stays verbatim, U+2019 included, as a **footer** | Dropping it now that facts exist; rewording it to mention a third-party tap |
| **Sequencing** | The three deltas land **first**, in WU1, before any line of code | Shipping the code and amending the specs at archive — proposal risk **R1** |
| **Verification runners** (maintainer) | Scoped runners for m10; the two pre-existing UI failures tracked as their own PR | Blocking m10 on failures it did not cause and does not touch |

## 10. Archive integrity

### Mechanical operations, with mandatory readbacks

| Operation | Mechanism | Readback |
|---|---|---|
| `installed-inventory` II15 appended | `head -n 684` + `tail -n +37 delta \| head -n 196` + `tail -n +685` | **3 × `diff` — all empty.** Untouched prefix (II1–II14); promoted block vs the delta; untouched suffix (the whole prior provenance) |
| `package-detail` PD6 replaced | `head -n 231` + `tail -n +34 delta \| head -n 39` + `tail -n +250` | **3 × `diff` — all empty**, plus a 4th superset audit that **passed** (additions only) |
| `tap-management` TM5 replaced | `head -n 118` (keeps the `<!-- TM5 -->` marker) + `tail -n +34 delta \| head -n 128` + `tail -n +228` | **3 × `diff` — all empty**, plus a 4th superset audit that **found two rewritten lines** (§5) |
| Provenance appends (×3) | `cat >> file` | **3 × `diff` — all empty.** Pre-append file vs the head of the post-append file: additive only |
| Archive move | `git mv openspec/changes/m10-third-party-detail → openspec/changes/archive/2026-08-24-m10-third-party-detail` | **`diff -r` against a pre-move recursive snapshot — empty, exit 0.** Source directory confirmed gone |

**No artifact content passed through a Read → Write path.** Every promotion is a `head`/`tail` byte
slice of the exact delta bytes; every move is `git mv`. Empty diffs are the only passing evidence and
they are what was produced. The one authored edit in this phase — the `design.md` S1 correction and the
7.4 checkbox — was made **before** the recursive snapshot was taken, precisely so the move readback stays
an empty `diff -r` rather than being excused.

### Post-merge count verification

Recounted from the merged main specs after promotion, not trusted from any header:

```
installed-inventory: 15 requirements / 79 scenarios   (II15 contributes 12)
package-detail:       8 requirements / 31 scenarios   (PD6  contributes  3)
tap-management:      13 requirements / 58 scenarios   (TM5  contributes 10)
`## Verification classes` tables in all three:  0
```

### Archive contents

```
2026-08-24-m10-third-party-detail/
├── explore.md
├── proposal.md
├── design.md             (fact-inventory table corrected at archive — S1; OQ 2 closed — task 7.4)
├── tasks.md              (52/52 complete)
├── apply-progress.md     (rounds 1 and 2)
├── verify-report.md      (round 2 — PASS WITH WARNINGS; supersedes round 1)
├── archive-report.md     (this file — additive, excluded from the readback)
└── specs/
    ├── README.md
    ├── installed-inventory/spec.md
    ├── package-detail/spec.md
    └── tap-management/spec.md
```

### Hybrid-store parity — stated honestly

The Engram twins were byte-current with their OpenSpec files at their authoring phase and have drifted
since, in the ordinary way:

- `#7786` (`tasks`) is a **point-in-time snapshot** claiming 51/52, 6 commits, CellarCore 1,837,
  `cellarTests` 245, branch total 2,901 and DD-11 at `3+ / 2−`. Every one of those numbers moved
  afterwards (§0 table). It was deliberately **not** re-saved: doing so would route artifact content back
  through model generation, precisely the truncation hazard the mechanical-copy contract forbids.
- `#7787` (`apply-progress`) mirrors a file this phase deliberately left unedited.
- `#7788` (`verify-report`) holds round 2 only; round 1 was upserted away.

**After archive, the archived OpenSpec files under
`openspec/changes/archive/2026-08-24-m10-third-party-detail/` are the authoritative audit trail.** The
Engram twins remain useful for recovery and search, not for byte-comparison.

## 11. Carried follow-ups — recorded open, deliberately not closed here

| # | Item | Why it is open |
|---|---|---|
| 1 | **The two pre-existing `cellarUITests` Taps failures** (`cellarUITests.swift:209`, `:231`) | Red on `main` since before m9; reproduced on unmodified `main` @ `5a0860b`. **Maintainer decision: a separate follow-up PR.** Not an m10 defect — `cellarUITests/` holds a zero-line diff across the whole branch. This is the same item m9 carried as its follow-up 7, still open |
| 2 | **`InstalledDecoder` epoch collapse for `installedAt`** (deferred DD-6) | `date(_:)` maps a missing timestamp to `Date(timeIntervalSince1970: 0)`, so an install-date fact would print *1 January 1970*. **A follow-up delta against `installed-inventory`**, not a rendering choice. II15 forbids the fact until the decoder preserves the absence — nobody may "complete the grid" first |
| 3 | **Re-anchor II15 sc12's positive copy assertion** (verify S8) | Its `shipped.raw.contains(sentence)` anchor now resolves against the unrelated pre-existing fallback at `PackageDetailView.swift:61`, because WU5 removed the pane's own occurrence from that file. Correcting that unrelated copy would fail a correct pane. See §6 |
| 4 | **SwiftLint advisories** (verify S3) | SwiftLint 0.65.1 is installed but unwired (no `.swiftlint.yml`, no lint build phase), so these are default-rule advisories, not gate failures. `InstalledDetailProjectionTests.swift` is 544 lines (`file_length`/`type_body_length`). Wiring a linter is its own change with its own baseline decision |
| 5 | **Two design size estimates overrun** (verify S6) | `InstalledDetailProjectionTests.swift` 544 lines against a 240–360 estimate. The estimates were a planning aid, not a constraint any requirement rests on |
| 6 | **One cross-work-unit cosmetic spill in `65a65cb`** (verify S7) | Historical; rewriting a landed commit to move seven cosmetic lines costs more history than it buys clarity |
| 7 | **`tasks.md:319` (task 6.2) declares the full-scheme runner and is ticked** (verify S9) | Stale artifact text, not concealment: the task was performed against that runner in round 1 and its result is disclosed in three places. Left as the audit trail of what was run; the scoped-runner decision is recorded in §7 |
| 8 | **Receipt-backed release notes** | Explicit non-goal — `release-notes` **D4** territory, which requires an explicit entry point and egress consent |
| 9 | **`BrewfileDiff.isPresent` (R15)** | Carried unchanged from m9's follow-up 2. A separate ~1-line slice, still unscoped |
| 10 | **The `brew untrust --formula\|--cask <qualified>` probe** | Carried unchanged from m9's follow-up 1. Still gates any future per-package **mutation** slice; m10 is read-only and does not touch it |
| 11 | **Stale change folders in `openspec/changes/`** | `m3-4`, `m3-services-cleanup-taps` and `m5-pro-parity` are pre-SDD-convention leftovers, neither active nor archived. Carried unchanged from m9's follow-up 6; this phase archived only its own change and touched nothing else |

**Ship note**: m10 is **app-only**. It changes no release pipeline, no Sparkle appcast, no bundle
identity and no `scripts/`. It ships with the next release tag; **no tag was cut this cycle**.

## 12. Learnings worth carrying

1. **The `m9` forecasting learning paid off on its first use.** Counting the artifact bucket instead of
   estimating it, and naming `apply-progress.md` and the verify report as line items, moved the branch
   total from m9's +14 % overshoot to inside the band at 78 % of budget. Keep doing exactly this.
2. **A "strict superset" claim is checkable, so check it — and `tap-management` has now failed the check
   twice.** m9's `package-mutation` claim held while its `tap-management` claim did not; m10's
   `package-detail` claim held while its `tap-management` claim did not. Two cycles, the same
   capability, the same failure. Verify the claim rather than the pattern.
3. **A citation in an archive is a fact that can be wrong, and correcting it is cheap only while someone
   still remembers.** m9 cited TM1 for a clause that was TM5's, in three places, and the mis-citation
   was load-bearing enough to shape m10's whole R1 sequencing. The correction is now recorded in two
   capabilities' provenance rather than in one place a reader might miss.
4. **When a source-scanning test's anchor stops being file-scoped, it silently starts guarding the wrong
   line.** sc12 still passes, but it passes because of an unrelated fallback string in another code
   path. A green source-scan assertion proves nothing about *which* occurrence satisfied it.
5. **A green `xcodebuild` run proves nothing until the case is seen by name.** `-only-testing:` with a
   single Swift Testing case name silently ran nothing and still reported `** TEST SUCCEEDED **` — a RED
   attempt looked like a pass. Filter at the **suite** level.

## 13. Artifact traceability (Engram observation IDs)

| Artifact | Topic key | Obs ID |
|---|---|---|
| Exploration | `sdd/m10-third-party-detail/explore` | **#7781** |
| §8 probe results | referenced by `explore.md` and `design.md` | **#7782** |
| Scope / state decisions (binding), later upserted to the PR checkpoint | `sdd/m10-third-party-detail/state` | **#7780** |
| Proposal | `sdd/m10-third-party-detail/proposal` | **#7783** |
| Design (rev 2) | `sdd/m10-third-party-detail/design` | **#7784** |
| Spec deltas (rev 2) | `sdd/m10-third-party-detail/spec` | **#7785** |
| Tasks (rev 2) | `sdd/m10-third-party-detail/tasks` | **#7786** |
| Apply progress | `sdd/m10-third-party-detail/apply-progress` | **#7787** |
| Verify report (round 2) | `sdd/m10-third-party-detail/verify-report` | **#7788** |
| Archive report | `sdd/m10-third-party-detail/archive-report` | *this document* |

The five artifacts the archive phase is required to read — proposal, spec, design, tasks, verify-report —
were all read in full, from Engram (`#7783`, `#7785`, `#7784`, `#7786`, `#7788`) and from their canonical
OpenSpec files. Design and spec revisions are **rev 2** in both stores: both were corrected after an
orchestrator gate FAIL (narrow) during planning.

**No `sdd/m10-third-party-detail/review/*` topics exist**, because no review was ever started for this
candidate (§3).

---

## Final state

An installed package the catalog does not carry now opens to its own facts instead of "No further
details". `Home-Cellar` — the maintainer's own tap — shows its type, its homepage as a link, its tap of
origin, its primary keg's version and link state, a count of the other kegs, its pin state, how it was
installed and how much disk it takes, with the same Upgrade and Uninstall verbs its Installed row
already offered, from the same unchanged `MutationMenu`. A package whose receipt withholds its tap shows
no origin row and no marker, from one guard. Nothing on the surface grants, revokes or gates anything,
and nothing claims the package came from a third-party tap: the footer still says only what is true —
that Cellar's catalog does not carry it.

`m9-per-package-trust` shipped `Trusted individually` and archived the fact that it would render nowhere
until a third-party detail surface existed. It exists now, and PD8's marker sits where PD8 said it would,
resolved through the one projection that owns the copy — with **no `package-trust` delta** written to get
there. Requirements that are correctly specified activate; they do not need amending.

No new brew invocation. `project.pbxproj`: 0 lines. `InstalledDecoder`, `MutationCommand`, `TapCommand`,
`TapProjection` and `cellarUITests/`: 0 lines each.

**Cycle complete.** Explored, proposed, specified, designed, implemented under strict TDD across five
work units, verified across two rounds with independent mutation testing, merged as PR #75, and archived.
