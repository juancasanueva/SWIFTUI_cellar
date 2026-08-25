# Archive Report: `m11-tap-search`

**Archived**: 2026-08-25 · **Milestone**: **none closed.** `PRD.md` §7 (:199) enumerates **M1–M6
only**, and all six were closed before this slice began. `m11-tap-search` is a **post-M6 refinement
slice** anchored to a PRD *feature*, not a milestone: the search promise of **§3.1** (:52, *"Instant,
as-you-type local search"*) applied to the tap inventory of **§3.7** (:108, *"show packages per
tap"*) that M3 delivered. Recorded this way per `rules.archive` ("record which PRD milestone the
archived change closed") and following the `m10-third-party-detail` precedent; the proposal's own
header phrasing — *"Anchors PRD.md M1 'Core & Catalog'"* — describes the **feature lineage**, not a
milestone this change closes.
**Status at close**: implemented over **nine apply rounds**, verified over **eleven verify rounds**,
**merged to `main` in PR #77** at `2d96b1d`, archived.
**Verify verdict**: **PASS WITH WARNINGS** (round 11, canonical) · 0 blockers · 0 CRITICAL ·
**5 requirements / 56 scenarios, all COMPLIANT** · 3 WARNING, 13 SUGGESTION. The one delivery WARNING
(`6′.7`, the PR) was **discharged after the report was written**.
**Artifact store**: hybrid (OpenSpec canonical + Engram mirror, project `swiftui_cellar`)
**Review gate**: structurally **absent** — RDD disabled, no review started for this candidate,
delivery under ordinary repository policy. No `reviewGate` key to read and none to block on.

This report is the terminal record of the cycle. It describes the state of the change **at close**,
not the state at any earlier point. `apply-progress.md` and `verify-report.md` are intermediate
snapshots archived alongside it; where either disagrees with the final state, the final state is
recorded here and the snapshot's claim is attributed to its own moment rather than restated as a
current fact.

## Facts that moved after the snapshots were written

| Fact | Snapshot claim | State at close |
|---|---|---|
| Task `6′.7` (push + open the PR) | "the branch's **ONE open delivery box**, deferred by instruction" (Engram tasks mirror `#7799`); "**W1** `6′.7` open" (`verify-report.md`) | **Closed at `49c0f59`** on the feature branch, before merge. `tasks.md` in this archive is **285 of 286**, and the single remaining `[ ]` is round-1 `6.7`, **VOID by design** (see §4). This phase reconciled nothing |
| The PR itself | "not opened" (round-2 tasks ledger, carried forward through round 9) | **PR #77 opened and merged** — *feat(taps): search and install packages from your third-party taps* — `2026-08-25T14:23:07Z` at `2d96b1d`; branch `feat/m11-tap-search` deleted |
| Branch tip | `925ccf9`, "**56 commits** off `main`" (`verify-report.md`, round 11) | **`49c0f59`, 58 commits** off the merge base `edda9a5`. The two commits after `925ccf9` are the round-11 verify report (`31317da`) and the `6′.7` closure (`49c0f59`) |
| Branch size | "33 files, +11,060 / −93 = **11,153**" (`verify-report.md`, measured at `925ccf9`) | **33 files, +11,023 / −93 = 11,116** — `git diff --shortstat edda9a5 49c0f59`, corroborated by the GitHub PR record (`additions: 11023`, `deletions: 93`, `changedFiles: 33`). The report commit *replaced* the superseded round-10 body, so the total fell rather than rose |
| Delta block count | the orchestrator's launch brief said "**5 MODIFIED** blocks across 4 capabilities" | **4 MODIFIED blocks** — PD6, TM5, TM11, II15 — plus **1 ADDED** (PS8), across **4 capabilities**. Counted mechanically from the four archived delta files. `specs/README.md:111` already recorded "1 ADDED, 4 MODIFIED blocks across 3 capabilities", counting only the capabilities that carry a MODIFIED block. Both descriptions of the *capability* count are defensible; the **block** count is 4, not 5 |
| Release tag | the launch brief said "release v1.4.0 pending (m11 ships with the next tag); none cut yet" | **Overtaken during the archive, recorded with the final state.** A **lightweight** tag `v1.4.0` points at **`2d96b1d` — this change's own merge commit** — so m11 is *inside* v1.4.0. The first `Release` run for that tag failed at its `Archive` step (Apple certificate quota, see §11); after the maintainer revoked the CI-minted certificates the same run was re-run and **succeeded**: `Home-Cellar-1.4.0.zip` is published and notarized, the appcast serves 1.4.0, and the tap cask is bumped to 1.4.0 (`c9ab082`). m11 shipped in **v1.4.0** on 2026-08-25 |

Two facts in the launch brief were checked and **corroborated**: PR #77 merged at `2d96b1d` with 58
commits, and the two pre-existing `cellarUITests` Taps failures at `:209` and `:231` — those line
numbers land inside `testTapsNavigationOfficialSourcesAndAddConfirmation` (`:190`) and
`testTapDetailFilteringInstalledHandoffAndForceDisclosure` (`:215`) respectively.

---

## 1. Milestone linkage

- **No PRD milestone closed.** M1–M6 were all closed before this change; §7 defines no M7+. Recording
  a milestone here would invent one.
- **What it closed instead is a broken promise inside a shipped feature.** Searching `gentle-ai`
  found nothing, although the maintainer's own tap (`gentleman-programming/tap`) was installed and
  publishes it. `PackageSearchIndex` is built from the `CatalogSnapshot` alone — `homebrew/core` +
  `homebrew/cask` — so **every third-party tap package was invisible to search**. The only path was
  Taps → tap detail → its filter field, i.e. the user had to already know which tap publishes the
  package they want.
- **The data was already resident and the argv was already correct.** `TapStore.inventory` holds the
  inventory from the shipped `brew tap-info --installed --json` refresh (TM1), and PM10 already
  mandates the bare, unqualified install token. The missing piece was an **entry point**, not a
  mechanism — which is why the change adds **no brew invocation, no store, no DI line, no `Process`
  and no `await` in the render path**.
- **It also completes a shape m10 started.** m10 gave a catalog-less installed package a
  receipt-backed detail (II15); m11 gives a catalog-less *tap* package a way to be **found** in the
  first place, and — from round 6 — a name-only pane when it is not installed at all.

## 2. Delivery references

| | |
|---|---|
| Branch | `feat/m11-tap-search` (deleted after merge) |
| Merge base | `edda9a5` — *Merge pull request #76 from juancasanueva/docs/sdd-archive-m10-third-party-detail* |
| Branch tip | `49c0f59` — *docs(sdd): close task 6′.7 for m11-tap-search with PR #77* |
| PR | **#77** — *feat(taps): search and install packages from your third-party taps* |
| Merged | `2026-08-25T14:23:07Z` at **`2d96b1d`**, base `main` |
| Commits | **58**, all Conventional Commits, **no AI attribution anywhere** |
| Size | **33 files, +11,023 / −93 = 11,116 changed lines** |
| Labels | **none on GitHub.** The `size:exception` was a **maintainer session decision (2026-08-25)**, not a repository label. Recorded here because a future reader looking for the label will not find one |
| Archive branch | `docs/sdd-archive-m11-tap-search` (this commit) — **not pushed, no PR opened**, by instruction |

**Ship note.** The change is **app-only**: 23 source/test files under `Packages/CellarCore/` and
`cellar/` + `cellarTests/`, and 10 files under `openspec/`. It touches **no** `.github/` workflow, no
`RELEASING.md`, no packaging and no Sparkle appcast. See §11 for the v1.4.0 release state, which is a
pipeline matter and not an m11 defect.

## 3. Review gate

`reviewGate` is **structurally absent**. RDD is globally disabled for this repository, so zero review
code ran for this candidate: there is no `disabled/unmanaged` value to check for, no receipt to
validate, and nothing to block on. Delivery proceeded under **ordinary repository policy** — the
scoped test runners, the build, and the maintainer's own review of PR #77. Its absence is not a
defect to investigate and was not treated as one.

## 4. Task completion gate

`tasks.md` carries **286 checkboxes across nine appended rounds**: **285 `[x]`** and **one `[ ]`**.

The single unchecked box is **round-1 task `6.7`**, and it is **VOID by design, not stale**. Its own
text (`tasks.md:430-431`) says so in the artifact itself:

> `6.7` **VOID — never performed, superseded by task 6′.7.** Its "no `size:exception`" premise is
> false as of 2026-08-25 and its body text describes a Browse section that no longer exists. Kept
> only so the supersession is visible rather than silently rewritten. Original text follows.

**No archive-time reconciliation was performed and none was needed.** This is not the stale-checkbox
exception the strict policy allows under proof; it is a deliberately preserved supersession record,
left unchecked precisely *because* checking it would assert that a superseded plan was executed.
`sdd-apply` marked every box it actually completed, including `6′.7` at `49c0f59`. Round-by-round:
59 (round 1, `6.7` void) · 56 · 24 · 22 · 19 · 25 · 24 · 26 · 24 = **279**… and the ledger in the
Engram tasks mirror foots to 279 for the rounds it enumerates, against 286 boxes in the file. The
mirror's round-6 sub-ledger was already recorded as not footing (verify **S11**) and is carried open
in §11; **the file is authoritative** and was counted mechanically here.

**One nuance in that 285.** Round 2's **Phase 7′ (Archive obligations)** — five boxes, `7′.1`–`7′.5` —
was marked `[x]` during apply, but those boxes are **instructions to this phase**, not work apply
performed, and their stated arithmetic is **round-2-era and stale**: `7′.1` asks for "PS8 with its
**17** scenarios (→ 8 req / 36 sc)" and "13 req / 60 sc" for `tap-management`, figures that rounds 3–9
moved to **23 / 42** and **61**. This phase promoted the **files'** final counts (§5), recounted
mechanically, and ignored the pre-checked figures. The obligations themselves were honoured and each
is discharged in §5: `7′.2` (the marker drift, the "activated, not changed" records), `7′.3` (the
withdrawn `From your taps` and the void rev-2 decisions), `7′.4` — which independently states
**"PRD milestone: none closed. `PRD.md` §7 ends at M6; the m7–m11 labels are session shorthand"** and
explicitly corrects round 1's task `7.4` for claiming "M11" — and `7′.5` (the deferrals, of which the
**name-only pane is no longer one**: it was delivered in round 6, corrected in `specs/README.md` at
round 7).

## 5. Spec sync

Four delta files promoted into **four** capabilities. **Final totals, recounted mechanically from the
merged files** rather than trusted from any delta header:

| Capability | Action | Delta | Before | **At close** |
|---|---|---|---|---|
| `package-search` | Updated | **1 ADDED (PS8)**: 23 sc (14 `unit`, 9 `unit-app`) | 7 req / 19 sc | **8 req / 42 sc** |
| `package-detail` | Updated | **1 MODIFIED (PD6)**: 6 sc replace 3 | 8 req / 31 sc | **8 req / 34 sc** |
| `tap-management` | Updated | **2 MODIFIED (TM5, TM11)**: 12 sc replace 10, 3 sc replace 2 | 13 req / 58 sc | **13 req / 61 sc** |
| `installed-inventory` | Updated | **1 MODIFIED (II15)**: 12 sc replace 12 | 15 req / 79 sc | **15 req / 79 sc** |

**1 ADDED, 4 MODIFIED, 0 REMOVED, 0 RENAMED.** `rules.archive`'s destructive-delta warning therefore
**did not fire** anywhere and no confirmation prompt was owed. Every total matches the end state
`specs/README.md:104-109` declared.

`installed-inventory`'s **+0** is deliberate, not an oversight: round 8 changed how II15's verbs are
*presented*, and the scenario that owned that claim was amended **in place** rather than joined by a
second one restating it.

**Per-splice readbacks — every one empty.** Each promoted block was byte-sliced against its delta
source, and every untouched region was byte-sliced against a pre-merge copy:

| Splice | Main range replaced | Delta source | Block readback | Surrounding-text readback |
|---|---|---|---|---|
| PS8 (ADDED) | inserted after `:178`, before `## Provenance` | `package-search/spec.md:132-728` | **empty** | head `1-178` **empty**, tail from `## Provenance` **empty** |
| PD6 | `232-270` | `package-detail/spec.md:38-152` | **empty** | head `1-231` **empty**, tail from PD7 **empty** |
| TM5 | `119-246` (under its existing `<!-- TM5 -->`) | `tap-management/spec.md:47-223` | **empty** | head `1-118` **empty** |
| TM11 | `533-558` (under its existing `<!-- TM11 -->`) | `tap-management/spec.md:225-273` | **empty** | middle `TM6…TM10` + the TM11 marker **empty**, tail from `<!-- TM12 -->` **empty** |
| II15 | `685-880` | `installed-inventory/spec.md:39-252` | **empty** | head `1-684` **empty**, **trailing `## Provenance` + archive notes empty** |

All **13** `<!-- TM# -->` markers were re-counted after the merge and are intact and in order.

**The II15 splice was the one with a real trap, and it was handled.** II15 is the **last requirement
in its file**, followed immediately by a 300-line `## Provenance` section carrying every prior
change's archive notes. A block replacement that terminated at end-of-file instead of at the block
boundary would have silently swallowed all of it. The splice was cut at `:880` (`- Verification:
unit-app`) with `:881` blank and `:882` `## Provenance`, and readback 3 above — diffing the entire
pre-merge tail against the post-merge tail — is the proof that nothing was lost.

### Superset claims, checked independently rather than trusted

| Block | Delta's claim | Independent byte check |
|---|---|---|
| **PD6** | strict superset | **byte-true** — additions only, **zero deletions** |
| **TM5** | strict superset | **byte-true** — additions only, **zero deletions** |
| **TM11** | strict superset | **byte-true** — additions only, **zero deletions** |
| **II15** | *not* claimed a superset; claimed "11 of 12 scenarios byte-identical, the twelfth amended in place" | **exactly as claimed** — one scenario heading changed, two regions rewritten (the verb clause, 3 lines → 14; the verb scenario, 3 lines → 9 + a 4-line `(Previously:)` note), each carrying its own `(Previously: …)` line |

**This breaks a two-change pattern, and that is worth recording.** `m9-per-package-trust` and
`m10-third-party-detail` *each* found this repository's `tap-management` delta failing its own
"strict superset" claim while its sibling's held — twice in a row, enough that the m10 archive
recorded it as a habit to watch. **This time both `tap-management` blocks came back byte-true.** The
pattern was becoming a rule of thumb; it is not one, and the check is what tells the difference.

### No verification-class table promoted

None of the four main specs carries a `## Verification classes` table today — only `app-updates` and
`release-distribution` do — so each delta's class table stayed **delta-local provenance** in this
archived folder, and only the per-scenario inline `- Verification:` lines promoted with their
requirements. This follows the `m7-tap-trust` precedent. Verified after the merge: `rg '^##
Verification classes'` matches **zero** lines in all four promoted files.

### Hand-edits made outside the promoted blocks

Additive only: **one `## Provenance` entry per capability**, four in total. Each append was verified
additive by diffing the pre-append file against the head of the post-append file — **all four empty**.
No existing provenance entry was edited, reordered or removed, following the m9/m10 precedent: prior
entries stand as the audit trail of what was believed at their time.

### Provenance recorded, by obligation

- **TM11/TM12 ordinal drift**, recorded once in `tap-management`'s entry. `explore.md` and
  `proposal.md` call the adjacent-capabilities requirement **TM10** and the trust-presentation
  requirement **TM11**, by narrative count. This file's markers — the only marker comments in the
  repository, and therefore authoritative — are **`<!-- TM11 -->`** and **`<!-- TM12 -->`**. Where the
  decision record says "TM11 untouched" it means the file's **TM12**, and it *is* untouched: no
  `Untrusted` badge, no trust control, no trust-state read anywhere on the new surface.
- **The m9 TM1 → TM5 mis-citation** stands corrected. m10 recorded that m9 cited **TM1** (a
  one-invocation rule about acquiring *tap* detail from `brew tap-info`) for a clause that is
  **TM5's**. m11's deltas cite TM5 throughout, and both the `tap-management` and `package-detail`
  entries state that the correction holds and was not re-litigated.
- **`Installed.` / `Not installed.` / `From your taps` — pinned by this change, then withdrawn by
  it**, recorded in `package-search`'s entry. `From your taps` named a Browse section the scope change
  deleted before it shipped. The two state sentences were the row's copy until round 3 replaced them
  with the shared status pill. **None reaches `openspec/specs/**`**: PS8 is an ADDED requirement whose
  first appearance in the main specs is this merge, so the withdrawal needed no MODIFIED block and
  fired no destructive-delta warning. Both strings remain **live in TM5** for the tap-detail rows it
  governs, and round 6 put `Not installed.` back on the **name-only pane** as TM5's exact string.
- **PS8's version prohibition became "no *published* version"**, recorded with the reason: round 4
  gave an installed hit an offered version derived from **this machine's own receipt** under II4's
  outdated rule, so the ban was narrowed to the *published* value rather than dropped, and the fact
  ceiling moved from five to six. A reader who takes the clause as "no version at all" mis-scopes it.
- **The Outdated-control rationale was rewritten and the rule survived**, recorded in the same entry.
  The original reason — "a tap hit carries no version, so the control could never change what is
  visible" (II8) — went **literally false** for the installed-and-outdated minority at round 4. It was
  replaced rather than quietly kept: an Outdated chip here would not filter the listing so much as
  **replace** it, collapsing every published package this machine does not have. Same rule, honest
  reason. Recorded because a rule whose stated justification has gone false is exactly the text a
  later reader deletes after checking the justification and not the rule.

## 6. What shipped, and how it changed shape nine times

The honest story of this change is that **its view half was rebuilt from scratch once and then
adjusted eight times by the maintainer looking at the running app**, while its core — a pure
projection and its 26 unit rows — landed in round 1 and never moved.

| Round | What the maintainer saw | What changed |
|---|---|---|
| **1** | — | `TapPackageSearch` projection + a **"From your taps" section inside Browse**, rendered only for a non-empty query |
| **2** | the surface belongs beside Search catalog, not inside it | **Scope change (binding).** Browse reverts to a **zero-line diff vs `main`**; the surface becomes its own sidebar section `Search our taps`; an **empty query lists everything** the taps publish; the Outdated chip disappears rather than being restated |
| **3** | tap rows carried a third text line where catalog rows carry a pill | **`StatusPill` extracted** from `PackageRow`'s `private func statusPill(…)`. PS8 asks for the *same* pill, not one that looks the same, and Swift `private` is file-scoped — "same" was **unrepresentable without extraction**. `Installed.` / `Not installed.` withdrawn |
| **4** | an outdated tap package read as merely installed | the **shared UPDATE pill**, after the Installed pill, fed an offered version derived from the installed receipt. No brew invocation added |
| **5** | the `⋯` menu on an installed tap row offered only Install | the projection resolves the **installed record** by the tap-aware handoff and the row hands it over, so the menu takes its installed branch. No verb re-implemented |
| **6** | a not-installed hit was a dead end | **Reversal of a 2026-08-24 decision (a).** An unambiguous not-installed hit becomes selectable and opens a **name-only pane** composed exclusively from the resident inventory + one pinned footer |
| **7** | a colliding row named a package and offered no way to see it | **Reversal of round 6's collision half.** A colliding hit routes to the **catalog's own** pane — through the shipped catalog-first resolution, so **no routing branch was added**. The collision note is unchanged and still required |
| **8** | two tap-backed panes hung the `⋯` menu in the header slot | both panes adopt the **catalog pane's shared Actions section**, placed last, header primary slots empty. **This is why II15 had to be MODIFIED**: its clause pinned the *list row's* menu |
| **9** | tap rows opened with text; every other package row opens with an icon | the **shared `PackageIconTile`**, same argument shape, same pipeline. The component needed **no edit** |

**Two decisions were reversed mid-flight, both by the maintainer, and both are recorded rather than
rewritten away**: "not-installed rows are non-selectable" (round 6) and "a colliding hit is
non-selectable" (round 7). The **only** inert row left is a **duplicate `PackageID` among the emitted
hits** — two third-party taps publishing one name, neither of them the catalog's — which nothing can
disambiguate. `specs/README.md`'s decision table carries every superseded row with strikethrough
instead of deleting it, and round 7 went back and corrected an exclusion the round-6 landing had
missed.

### The load-bearing engineering decisions

- **`RowID`, not `PackageID`, for row identity (DD-2).** A tap hit colliding with a catalog record
  would otherwise resolve to a *different* package than the row chosen. This is also why round 9's
  mutation **MY** (`id: hit.id`) was **type-impossible** — the compiler caught it.
- **Composed above the index, never in it.** The projection is a `nonisolated`, `Sendable` value in
  `BrewClient` — the target that already owns `TapInventory` and already imports `Catalog`. Explore's
  Approach C (ingesting tap names into `PackageSearchIndex`) was **rejected**: it falsifies PD6, it
  contradicts TM5, and it would make `Catalog` depend on `BrewProcess`, which II7 asserts against.
- **Exactly one catalog read, deciding exactly one fact** — membership, for the collision note.
  Since round 7 it decides nothing else; routability is uniqueness among the emitted hits.
- **No trust gate, asserted as an absence.** PM10 already forbids pre-blocking the untrusted-tap
  refusal and already mandates the bare argv. A source-scanning assertion, **retargeted** from the
  deleted `TapSearchSection` to `TapSearchView`, keeps it enforced — a scan still pointed at the old
  file would have passed **vacuously**.
- **`EmptyResults` was duplicated where `StatusPill` was extracted (DD-10 vs DD-18).** Not
  inconsistency: `EmptyResults` is a `private struct` in `BrowseView.swift`, which the zero-diff
  constraint forbids editing, while `statusPill` lived in `PackageRow.swift`, which it does not.

### Binding zero-diffs, re-verified at the merged tip

Measured with `git diff --numstat edda9a5 49c0f59 -- <path>`, **0 changed files** for every one:

`cellar/Browse/BrowseView.swift` · `cellar.xcodeproj/project.pbxproj` · `cellar/Casks/**` (including
`CaskIconView.swift`, where the tile lives) · `Packages/CellarCore/Sources/Catalog/**` (including
`CaskIconURL.swift`) · `cellar/Browse/MutationMenu.swift` ·
`Packages/CellarCore/Sources/BrewClient/TapProjection.swift` · `cellarUITests/**` ·
`openspec/specs/**` (untouched until this archive commit).

`cellar/Browse/PackageRow.swift` is **+6 / −27** — DD-18's deliberate extraction, from exactly one
commit — and is the only file under an invariant that moved at all.

## 7. Verification

**Eleven rounds.** Round 11 is canonical and **supersedes rounds 1–10**; the archived
`verify-report.md` is that round's body. Verdict **PASS WITH WARNINGS**, **0 blockers, 0 CRITICAL**,
**5/5 requirements**, **56/56 scenarios** (package-search 23 · package-detail 6 · tap-management 15 ·
installed-inventory 12).

**Non-vacuity by mutation, round 9's set**, restored SHA-verified with a clean tree afterward:

| Mutation | Observed |
|---|---|
| tile → `Image(systemName:)` | ❌ the one new test only; the other 15 passed |
| same component, `assets: nil` (second pipeline) | ❌ same single test — **compiles and still draws a tile** |
| tile moved after the kind chip | ❌ same single test |
| `id: hit.id` | **type-impossible** — `RowID` ≠ `PackageID`, caught at compile time |

The `assets: nil` mutation is the valuable one: **only the pipeline changed**, which a type-name
substring search would have missed entirely.

**The verifier's best methodological catch of the whole change** (round-9 deviation 2): a prohibition
placed **after** `try #require` is **unreachable under the very mutation it targets**, because the
`#require` throws first. Moving it above turned a vacuous assertion into a live one. That is a
finding about how to write assertions, not about this change, and it generalises.

**One precision the verifier volunteered against its own earlier claim (S13).** "A tap cask does no
network" would have been **wrong**. `PackageIconTile` skips CaskFlow for an unknown token, but
`CaskIconURL.candidateURLs` still **appends App-Fair** — so a not-installed tap cask attempts **one**
App-Fair request, 404s, and stamps a **24-hour** miss (against 15 minutes for a known token). "No
CaskFlow rungs" is exact; "no network" would not be. Carried open in §11.

## 8. Test, gate and size state at close

| | |
|---|---|
| CellarCore | **1,879 tests / 218 suites**, 1 known issue — `swift test --package-path Packages/CellarCore` |
| Release latency gate | **36 tests**, green for the **10th** consecutive round — `swift test -c release` |
| App target | **262 distinct test ids**, `TEST SUCCEEDED` on two independent runs, union 262 — `xcodebuild test … -only-testing:cellarTests` |
| Build | **SUCCEEDED** — `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` |
| Id progression | 257 → 258 → 259 → 260 → 261 → 261 → 261 → 261 → **262** across the nine rounds |

**The scoped-runner decision, stated plainly rather than buried.** Verification used the **scoped**
runners (`swift test` for CellarCore, `-only-testing:cellarTests` for the app target) rather than
`config.yaml`'s full `-scheme cellar` runner. This is **not** concealment and it is not new: the full
scheme drags in `cellarUITests`, whose two pre-existing Taps failures (`:209` in
`testTapsNavigationOfficialSourcesAndAddConfirmation`, `:231` in
`testTapDetailFilteringInstalledHandoffAndForceDisclosure`) **predate m11** and are tracked for a
separate PR by maintainer decision. `cellarUITests/**` carries a **zero diff** across this change, so
m11 could neither cause nor fix them.

**Round 10's S12 remedy worked and is now a standing rule**: never co-schedule `swift test` with
`xcodebuild`. `CatalogFootprintTests` measures resident memory and produced a *negative* reading under
co-scheduling; run alone and first, it passed first try.

### Size against the governing budget

`review_budget_lines: 5000`. Final: **11,116 changed lines — 222 % of budget.** The
`size:exception` was raised by `sdd-tasks` **before** apply round 2 started, as the proposal's R8
demanded, and **accepted by the maintainer on 2026-08-25**. It was not discovered at verification.
The overrun is overwhelmingly **artifact text**, not code: nine appended rounds of `tasks.md` (1,612
lines), `apply-progress.md` (1,281), the four delta specs (1,552) and their README (271), against 23
source and test files. **This is the honest cost of nine rounds of in-flight UI feedback landing as
amended artifacts before amended code**, and it is the number the next forecast should start from.

## 9. Archive integrity

### Mechanical operations, with mandatory readbacks

Every promotion and the folder move used **shell commands only** — `sed`/`diff` slicing for the
splices, `cat >>` heredoc for the additive provenance appends, `git mv` for the move. **No artifact
content passed through a model Read → Write path at any point.**

- **Five spec splices**, each with a block readback against its delta source and a readback of every
  untouched region — **all empty** (§5).
- **Four provenance appends**, each verified additive by diffing the pre-append file against the head
  of the post-append file — **all empty** (§5).
- **The folder move**: a recursive `cp -R` snapshot taken **before** the move, `git mv`, a check that
  the source path no longer exists, then `diff -r snapshot → archived`. **Exit status 0, empty
  output.** The snapshot was removed by an `EXIT` trap after the readback.

```
$ diff -r "$snapshot_root/source" "openspec/changes/archive/2026-08-25-m11-tap-search"
$ echo $?
0
```

An empty `diff -r` is the only passing evidence, and it is what was observed. `archive-report.md`
(this file) is **additive** and excluded from that comparison — it did not exist in the source
snapshot.

### Post-merge count verification

| File | Requirements | Scenarios | Lines |
|---|---|---|---|
| `openspec/specs/package-search/spec.md` | 7 → **8** | 19 → **42** | 206 → 866 |
| `openspec/specs/package-detail/spec.md` | **8** (unchanged) | 31 → **34** | 482 → 593 |
| `openspec/specs/tap-management/spec.md` | **13** (unchanged) | 58 → **61** | 875 → 994 |
| `openspec/specs/installed-inventory/spec.md` | **15** (unchanged) | **79** (unchanged) | 1,185 → 1,247 |

Every figure matches `specs/README.md`'s declared end state.

### Archive contents

`openspec/changes/archive/2026-08-25-m11-tap-search/`

- `explore.md` ✅ (572 lines) · `proposal.md` ✅ (209) · `design.md` ✅ (675) · `tasks.md` ✅ (1,612,
  **285/286**, the one open box VOID by design) · `apply-progress.md` ✅ (1,281) ·
  `verify-report.md` ✅ (282, round 11 canonical) · `archive-report.md` ✅ (this file)
- `specs/README.md` ✅ + `specs/{package-search,package-detail,tap-management,installed-inventory}/spec.md` ✅
- **No `state.yaml`** — the DAG state lived in Engram (`#7795`) for this change, not on disk. Recorded
  so its absence is not read as a loss.
- `openspec/changes/` no longer contains `m11-tap-search` ✅

**Pre-existing, unrelated**: `openspec/changes/` still holds three stale non-SDD folders — `m3-4`,
`m3-services-cleanup-taps`, `m5-pro-parity`. They predate this change and were **not** touched.

### Hybrid-store parity — stated honestly

The OpenSpec files are **canonical**; Engram holds **mirrors**. The mirrors were written at various
points during the cycle and several are **older than the artifacts they mirror** — the tasks mirror
`#7799` was re-mirrored at round 9's phase `6⁸.5` and still describes `6′.7` as open, and the spec
mirror `#7798` is **revision 4** against the files' **revision 10**, so its arithmetic (19 → 36
scenarios) is superseded by the files' 19 → 42. **Do not read the Engram mirrors as current.** This
archive report is mirrored to `sdd/m11-tap-search/archive-report` and is the one Engram artifact
written at close.

## 10. Decisions recorded, with what each rejected

| Decision | Rejected alternative, and why |
|---|---|
| Compose above the index (Approach A) | **Approach C** — ingest tap names into `PackageSearchIndex`. Falsifies PD6's "MUST be absent from the snapshot", contradicts TM5, and inverts the `Catalog` → `BrewProcess` dependency II7 forbids |
| Its own sidebar section | A **section inside Browse** (round 1, built and then reverted). Catalog and tap search answer different questions over different data; mixing them forced the catalog surface to absorb a second source's empty states, ranking and copy |
| `RowID` for row identity | `PackageID`. Catalog-first resolution would open or install a **different package** than the row chosen |
| Extract `StatusPill` | Duplicate a lookalike pill. PS8 requires the **same** component; Swift `private` is file-scoped, so "same" was unrepresentable without extraction |
| Duplicate `TapSearchEmptyState` | Extract `EmptyResults` — impossible without editing `BrowseView.swift`, which the zero-diff constraint forbids |
| No Outdated control | An inert or partial Outdated chip. II8 forbids an enabled control that cannot change the visible results, and here it would **replace** the listing rather than filter it |
| No trust gate, no badge | A pre-launch block or an `Untrusted` badge. PM10 forbids the gate; TM12 owns trust presentation and stays untouched |
| No `package-mutation` delta | A MODIFIED block restating PM10. PM10 already says the right thing; it was **activated, not changed** |
| Name-only pane for unambiguous not-installed hits | Leaving them inert (the 2026-08-24 decision), **reversed by the maintainer at round 6**. A row that names a package and refuses to show it is a dead end |
| Colliding hits route to the catalog pane | Leaving them inert (round 6), **reversed at round 7**. The shipped catalog-first order already resolves them, so the route costs no branch and agrees with the note the row already prints |

## 11. Carried follow-ups — recorded open, deliberately not closed here

1. **The `v1.4.0` release pipeline needs a durable signing fix** (shipped, but fragile). The first
   `Release` run for the tag (`32859294035`) failed at its **`Archive`** step: *"Your account has
   reached the maximum number of certificates … No signing certificate 'Mac Development' found"*.
   Cause: `scripts/release.sh` archives with automatic signing, and each ephemeral runner mints a new
   "Created via API" Mac Development certificate whose private key never persists, so every release
   since v1.0.0 consumed one of Apple's ten. The maintainer revoked the ten CI-minted certificates in
   the developer portal and the **re-run succeeded** — v1.4.0 is published, notarized and served by the
   appcast, and the tap cask is at 1.4.0. **Not an m11 defect** (zero `.github/`, packaging and
   `project.pbxproj` diff). Follow-up: archive with `SIGNING_STYLE=manual` using the Developer ID
   certificate the workflow already imports, so no per-run certificate is created.
2. **Two pre-existing `cellarUITests` Taps failures**, `:209` and `:231`, **tracked for a separate PR**
   by maintainer decision. `cellarUITests/**` is zero-diff across m11.
3. **A not-installed tap cask still makes one App-Fair icon request** (verify **S13**): unknown tokens
   skip CaskFlow but `CaskIconURL.candidateURLs` appends App-Fair regardless, so the request 404s and
   caches a **24-hour** miss. Worth a deliberate decision — "no network at all for tap hits" is a
   defensible product rule that this change did not take and did not claim to.
4. **Rename drift in the artifacts (S8, four tests).** `design.md` and `tasks.md` still cite four
   renamed test functions by their pre-rename names. Archived as-is: the artifacts are the audit trail
   of what was planned, and silently rewriting them would falsify that.
5. **`specs/README.md`'s totals history.** The summary line was re-footed once at round 5 (a
   correction it records in place) and the round-6-to-9 amendments moved the table above it again. The
   **table** is authoritative and matches the promoted files; the prose totals should be read with the
   correction note beside them.
6. **The Engram tasks mirror's round-6 sub-ledger does not foot (S11).** The file is authoritative.
7. **`cellarUITests.swift:226` asserts `"Not installed."`** — that assertion belongs to **tap detail**
   (TM5's surface), which still owns the string, not to the tap search rows that withdrew it. **Left
   deliberately.** A future reader chasing the round-3 withdrawal will find this line and must not
   "fix" it.
8. **m10's S8 anchor.** The `installed-inventory` sc12 positive anchor still leans on an unrelated
   line; carried from the m10 archive, untouched here.
9. **`InstalledDecoder` collapses a missing install timestamp to the Unix epoch**, so II15 still
   reports no install date. Carried from m10.
10. **SwiftLint advisories** remain unaddressed; no `.swiftlint.yml` exists in the repository and the
    linter is not wired into any gate.
11. **PS8 sc17's zero-diff claim needs CI (S3).** `BrowseView.swift`'s byte-identity to `main` has been
    hand-verified **eleven** times. That is exactly the kind of check that should stop being manual.
12. **`AppSection.tapSearch.title` is unreachable (S2)** — the sidebar uses `sidebarTitle`. Harmless,
    but it is dead text that reads as live.
13. **The archive settle will likely exceed the cumulative line cap** and need an audited reset, as it
    did for m10. That is the orchestrator's call, not this phase's; recorded here so it is expected
    rather than discovered.

## 12. Learnings worth carrying

- **"The same component" is a testable claim, and Swift's `private` decides whether it is even
  representable.** PS8 asked two surfaces to draw the *same* pill. Because `statusPill` was a
  file-scoped `private func`, no assertion could have distinguished "same" from "identical-looking"
  without extracting it first. The spec wording forced a real refactor — and the sibling case
  (`EmptyResults`, unextractable behind a zero-diff constraint) shows the decision was situational,
  not dogmatic.
- **A prohibition placed after `try #require` can be unreachable under the exact mutation it targets.**
  The `#require` throws first, the prohibition never runs, and the assertion passes vacuously while
  looking rigorous. Put prohibitions **above** the requires.
- **Retarget absence-scanners when the file they scan is deleted.** Round 2 deleted
  `TapSearchSection.swift`; a trust-gate scan still pointed at it would have passed **vacuously**
  forever. Deleting a file can silently disarm the assertion that guarded it.
- **When a rule's stated reason goes false, replace the reason, not the rule — and say you did.** The
  Outdated control's original justification stopped being true at round 4. Keeping it would have left
  a rule defended by a falsehood, which the next reader deletes after checking the defence.
- **Reversed decisions belong in the record, struck through, not erased.** Two 2026-08-24 decisions
  were reversed mid-apply. `specs/README.md` keeps both with strikethrough and the reason, and round 7
  went back to correct an exclusion round 6 had left stale. An exclusion list is only useful if it
  records **why** something stopped being excluded.
- **Verify the delta's own claims by byte-slicing, every time.** Two consecutive changes found
  `tap-management`'s superset claim failing; this one found it holding. A habit is not a proof.

## 13. Artifact traceability (Engram observation IDs)

| Artifact | Topic | Obs ID | Note |
|---|---|---|---|
| explore | `sdd/m11-tap-search/explore` | **#7794** | base `main` @ v1.3.0 |
| state / decisions | `sdd/m11-tap-search/state` | **#7795** | maintainer scope decisions; upserted at close to the PR-merged record |
| proposal | `sdd/m11-tap-search/proposal` | **#7796** | revision 2 |
| design | `sdd/m11-tap-search/design` | **#7797** | revision 3 + round-3 amendment (mirror lags the file's later rounds) |
| spec | `sdd/m11-tap-search/spec` | **#7798** | **revision 4 — superseded by the files' revision 10** |
| tasks | `sdd/m11-tap-search/tasks` | **#7799** | round-9 index; still shows `6′.7` open |
| apply-progress | `sdd/m11-tap-search/apply-progress` | **#7800** | round 9 |
| verify-report | `sdd/m11-tap-search/verify-report` | **#7801** | round 11, canonical |
| **archive-report** | `sdd/m11-tap-search/archive-report` | *this file's mirror* | written at close |

All five artifacts the archive phase is required to read — proposal, spec, design, tasks,
verify-report — were retrieved in full via `mem_get_observation`, not from search previews.

## Final state

`m11-tap-search` is **closed**. Its five requirement blocks are promoted into `openspec/specs/**`,
its change folder is archived byte-identically, and its one open checkbox is a preserved supersession
record rather than unfinished work. Thirteen follow-ups are carried open above; **none** blocks the
close; the release-pipeline signing fix (§11 item 1) is the most useful next step and belongs to the
release pipeline, not to this change.

The SDD cycle is complete: explored, proposed, specified, designed, planned, applied over nine
rounds, verified over eleven, delivered in PR #77, and archived.
