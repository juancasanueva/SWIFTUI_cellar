# Archive Report: `m9-per-package-trust`

**Archived**: 2026-08-24 · **Milestone**: PRD **M3 "Services, Cleanup & Taps"** §3.7 (:108), carried
forward as `2026-08-23-m7-tap-trust` follow-up item 1 — *a per-package trust surface*
**Status at close**: implemented, verified across two rounds, **merged to `main` in PR #73** at
`ddb9661`, archived
**Verify verdict**: **PASS WITH WARNINGS** · 0 blockers · 0 CRITICAL · **11 requirements / 55
scenarios, all discharged** · all four WARNINGs closed **after** the report was written, in `e561abf`
**Artifact store**: hybrid (OpenSpec + Engram, project `swiftui_cellar`)
**Review gate**: structurally **absent** — RDD disabled, no review started, delivery under ordinary
repository policy

This report is the terminal record of the cycle. It describes the state of the change **at close**, not
the state at any earlier point. `apply-progress.md` and `verify-report.md` are intermediate snapshots
archived alongside it; where either disagrees with the final state, the final state is recorded here and
the snapshot's claim is attributed to its own moment rather than restated as a current fact.

**Five facts moved after those snapshots were written**, and this report carries the later value in
each case:

| Fact | Snapshot claim | State at close |
|---|---|---|
| PT8.3's evidence clause | "the transcript **and the screenshot** … appear in the verify report" (`verify-report.md` W2, *a clause the archived record can never satisfy*) | Reworded in `e561abf` to name **only** the filed transcript; the screenshots were viewed live and **never archived**, and the transcript's addendum says so |
| The restoration commands | "the transcript's restoration block does not isolate the re-grant command" (W3) | A labelled **addendum** in `e561abf` names all three: `brew tap guria/tap`, then `brew trust --cask guria/tap/nehir`, then `brew trust --cask guria/tap/nehir@rc`. Re-tapping alone re-armed nothing |
| The restoration Homebrew build | "the RESTORED payload was read on 6.0.19, not the 6.0.18 the measurement ran on" (W4) | Recorded in the same addendum; the cascade finding predates the auto-update and the restored payload is content-identical to the fixture |
| Task tally | `apply-progress.md` "79 / 86" (W1) | Corrected to the mechanical **78 / 85** in `e561abf`; **85 / 85 at close** (8.7 by PR #73, 10.1–10.6 by this phase) |
| Tasks 8.7, 10.1–10.6 | open (`verify-report.md`, `apply-progress.md` "Remaining") | **All closed.** `apply-progress.md`'s "Remaining" section is a snapshot of its own moment and was deliberately left unedited |

`verify-report.md` closes with *"Fold WARNING-1 through WARNING-4 into the Phase 10 promotion."* Three of
the four were instead discharged **before** merge, in `e561abf`, and W1 with them. **None of the four is
open**, and none was folded into this phase as outstanding work.

---

## 1. Milestone linkage

- Closes **`m7-tap-trust` follow-up item 1**, recorded there as: *"a per-package trust surface — v1 shows
  tap-level state only, so a tap whose packages work through per-package grants still reads
  'Untrusted'."* That is exactly the defect this change removes.
- **The problem was a reconciliation failure, not a missing feature.** On the maintainer's Mac, 8 taps
  rendered **Untrusted** while `brew trust --json v1` listed 9 formulae and 4 casks granted
  individually — software that plainly works. The badge was correct *about the tap*; the user could not
  reconcile it, and Cellar showed nothing that could. Homebrew 6 grants trust at **two independent
  granularities** and Cellar read only one.
- **The change is best understood as one honest read, surfaced four ways**: a count line on the tap row
  and detail header (one projection value), a `Trusted individually` marker on tap-detail package rows,
  the same marker beside `PackageDetailView`'s Tap fact, and a dedicated **unattributed grants** section
  where nothing brew reported is ever dropped.
- **It grants and revokes nothing, and that is a mechanical constraint rather than a scoping
  preference.** Homebrew treats *naming* a `/`-qualified package to its trust machinery
  (`trust.rb#explicitly_allowed?`) **as the grant**, so a grant/revoke control needs a qualified token
  in argv — which `package-mutation` PM10 forbids everywhere, as an absence asserted by test.
- **This is the second change in the project to overturn one of its own binding beliefs mid-cycle**,
  and the first to overturn a belief **inherited from an already-archived change**. §7 tells that story
  in full.

## 2. Delivery references

| Item | Value |
|---|---|
| Base | `main` at `e03c58f` |
| PR | **#73** — https://github.com/juancasanueva/SWIFTUI_cellar/pull/73 |
| PR title | `feat(taps): read-only per-package trust surface (m9-per-package-trust)` |
| PR merged | **2026-08-24 15:32:42 UTC**, merge commit **`ddb9661`** on `main` — **11 commits** |
| Branch | `feat/m9-per-package-trust`, `28f4fbf` … `e561abf` |
| Size at close | **37 files, +6,390 / −18 = 6,408 changed lines** |
| Delivery strategy | `single-pr` with **`size:exception` recorded** (maintainer, obs `#7768`) against the governing 5,000-line budget |
| Archive branch | `docs/sdd-archive-m9-per-package-trust`, from `main` at `ddb9661` |

**Commits on `feat/m9-per-package-trust` (PR #73):**

| # | Commit | Subject |
|---|---|---|
| 1 | `28f4fbf` | **WU1** `docs(sdd): record the m9-per-package-trust proposal, spec deltas, design and tasks` |
| 2 | `ce74d83` | **WU2** `feat(taps): read the per-package trust report Homebrew already publishes` |
| 3 | `3055b72` | **WU3** `feat(taps): refresh the grant report alongside the tap snapshot` |
| 4 | `3dcc99d` | **WU4** `feat(taps): attribute per-package grants without ever splitting a token` |
| 5 | `349480b` | **WU5** `test(mutations): ban the per-package trust types from the mutation surface` |
| 6 | `7bf6be9` | **WU6** `feat(taps): show individual grants on the tap row, the detail and package detail` |
| 7 | `808171c` | **WU7** `docs(readme): describe qualified tokens without implying Cellar grants trust` |
| 8 | `72c9f9b` | `docs(sdd): record the m9-per-package-trust apply progress and task completions` |
| 9 | `cb3527d` | `test(taps): cover PT1.2 and correct the package-mutation delta arithmetic` (**discharge round 1**) |
| 10 | `5922e37` | `docs(sdd): amend PT8 to the measured ME2 reality` (**discharge round 2**) |
| 11 | `e561abf` | `docs(sdd): discharge the m9 round-2 verify warnings and record the verify report` |

No `Co-Authored-By` and no AI attribution on any of the 11 commits. All conventional.

**One honest note about the PR itself.** The `size:exception` was recorded as a maintainer decision
(obs `#7768`) and stated in the PR body's *Size* section, but **no `size:exception` label was applied on
GitHub** — `gh pr view 73 --json labels` returns an empty list at close. The exception is real and
audited; its GitHub projection is missing. Recorded rather than silently treated as applied.

**The PR body's own size figures are correct for a different moment.** It states *"3,266 authored
code+test lines; branch total 6,015"*. The code+test figure is exact at WU7 close (`808171c`:
+3,248 / −18 = 3,266). The branch total at close is **6,408**, measured here from
`git diff --shortstat e03c58f ddb9661`. §8 carries the measured numbers.

## 3. Review gate

`reviewGate` is **structurally absent** from this change's status, and that is the expected shape, not a
defect to investigate:

- Receipt-driven development is **disabled** for this repository (session preflight `RDD disabled`).
  With the kill switch off, zero review code ran for this candidate, so no transaction, ledger, receipt
  or gate context was ever created and none exists to read.
- There is therefore **no `disabled/unmanaged` value to check** and **no approval to fabricate**.
  Delivery of PR #73 proceeded under **ordinary repository policy**, and archive proceeds the same way —
  identical to every prior slice.
- Consequently the `sdd/m9-per-package-trust/review/*` Engram topics do not exist and were not read.

## 4. Task completion gate

**Gate PASSES at 85 / 85, after one authorized archive-time reconciliation of a single checkbox.**

| Task group | Items | Closed by |
|---|---|---|
| Phases 0–8 except 8.7, plus Phases 9, 11, 12 | 78 | `sdd-apply` during the cycle, ticked in the persisted artifact |
| `8.7` open the PR | 1 | **PR #73**, merged at `ddb9661` — ticked by this phase |
| `10.1`–`10.6` archive obligations | 6 | **this phase**, as it performed each one |

**The 8.7 reconciliation, stated exactly.** `sdd-apply` correctly left 8.7 unchecked: opening the PR is
not apply work, and `apply-progress.md` says so. The orchestrator's launch prompt supplied the
final-state fact — *PR #73 merged at `ddb9661`, verified via `gh`* — which this phase corroborated
directly against the repository (`gh pr view 73` → `mergedAt: 2026-08-24T15:32:42Z`,
`mergeCommit: ddb9661…`; `git log` shows `ddb9661` as the merge of `feat/m9-per-package-trust`). The
task's own text — *"Open the PR(s) … the body states up front (a)/(b)/(c)"* — is satisfied by the PR
body, which carries all three claims verbatim, including claim (b) in its **corrected** post-ME2 form.
This is a stale checkbox for completed work, not an incomplete task.

The whole `tasks.md` diff for this phase is **7 lines, checkbox-only** — verified by
`git diff -U0 … | grep -E '^[-+]' | grep -v '^[-+][-+][-+]'`, which returns exactly the seven
`- [ ]` → `- [x]` pairs and no prose change.

**`apply-progress.md` was deliberately not edited.** Its *"Remaining"* section still lists 8.7 and
10.1–10.6 as open. That is a true statement about the moment it was written and a false one about the
state at close; the correction lives here, in the terminal record, rather than being backdated into a
snapshot.

## 5. Spec sync

Four deltas promoted. **Final totals, recounted mechanically from the merged files** rather than
trusted from any delta header:

| Capability | Action | Delta | Before | **At close** |
|---|---|---|---|---|
| `package-trust` | **Created** | 8 ADDED / 33 sc (30 `unit`, 3 `manual-evidence`) | — (new) | **8 req / 33 sc** |
| `tap-management` | Updated | 1 MODIFIED (TM12): 7 sc replace 5 | 13 req / 55 sc | **13 req / 57 sc** |
| `package-mutation` | Updated | 1 MODIFIED (PM10): 11 sc replace 8 | 10 req / 60 sc | **10 req / 63 sc** |
| `package-detail` | Updated | 1 ADDED (PD8): 4 sc | 7 req / 26 sc | **8 req / 30 sc** |

Every total matches the end state its delta declared. **0 removed, 0 renamed across all four**, so
`rules.archive`'s destructive-delta warning did not fire anywhere.

`package-trust` is established as **PT1–PT8 in file order**, promoted byte-identical. It carries no
`<!-- PTn -->` markers because its delta carried none — only `tap-management` uses inline markers, and it
inherited them from its own `m3-taps` delta rather than gaining them at archive. The ordinal mapping and
the per-requirement scenario counts (4 · 6 · 3 · 5 · 4 · 4 · 3 · 4 = **33**) are pinned in that spec's
`## Provenance` so cross-capability references stay resolvable; each was recounted from the merged file.

### One delta-header claim that did not survive an independent check

The `tap-management` delta says its MODIFIED block *"is a strict superset of the text it replaces."*
Byte-sliced against a pre-merge copy, **six non-blank lines of the old TM12 were rewritten**, not merely
added to:

- the single-source clause — `A tap's trust state MUST be read …` became `A tap's **own** trust state
  MUST be read …` / `For that state, it MUST NOT require a second probe, …`;
- the copy-scoping clause — `Every user-facing string in this surface …` became
  `Every user-facing string **this capability** presents about trust …`.

**No rule was removed or weakened.** Both survive in scoped form, both are strengthened by the
`(Previously:)` note the block now carries, and the second gained a new sentence binding
`package-trust`'s positive-only strings from qualifying a tap-scoped one. The claim was "strict
superset"; the truth is "superset in rules, with two clauses rescoped". Recorded because the difference
is exactly the kind a future reader would otherwise assume away.

The `package-mutation` delta's identical claim **is** byte-true: the same check returns **zero non-blank
deletions**, and all eight shipped PM10 scenarios survive byte-identical.

### Hand-edits made outside the promoted blocks

Additive only, one `## Provenance` entry per capability, plus `package-trust`'s header prose and
`## Requirements` wrapper. Each append was verified additive by diffing the pre-append file against the
head of the post-append file — **all empty**. No existing provenance entry was edited, reordered or
removed.

## 6. What shipped

### Behaviour

- **A second read, with its own wire, source and store.** `BrewTrustGrantPayloadSource.command` is a
  `static let` compile-time constant, argv exactly `trust --json v1` — no package identity, no tap
  identity, no kind flag. No `trust.json` is ever read from disk on any path, including every failure
  path.
- **Three-valued state.** `granted` / `noGrantRecorded` / `unreported`, mirroring `TapTrustState`. A
  Homebrew with no `trust` verb **reports nothing**; it does not report zero. There is no
  "0 trusted individually" string anywhere.
- **Attribution by published identity, never by splitting.** Two conditions, both required (DD-5): the
  entry carries the exact `tap.name + "/"` prefix **and** `TapProjection.publishes(_:in:)` accepts its
  bare token. A URL-shaped `formulae` entry has four slashes and no owner/repo shape; every positional
  split misreads it. Anything the rule refuses is **surfaced**, never dropped.
- **A five-way partition where nothing is lost**: attributed · excluded (a `taps` entry for an installed
  tap — a *tap* grant, which must never feed a package count or badge) · orphan tap grants · unmatched
  package grants · other (every `commands` entry, and every unmodelled namespace). The totals sum to the
  decoded entry count, asserted equal to `ledger.entryCount`.
- **One projection value** (`TapGrantPresentation`) feeds the tap row, the detail header and the detail
  package rows, so the three cannot drift — the same one-projection rule TM12 applies to the badge.

### Binding 0-line diffs, held end to end

| Path | Requirement | Result at close |
|---|---|---|
| `MutationCommand.swift` | 0-line diff — any line means a gate or a new domain was added | ✅ empty |
| `BrewMutating.swift` `InvalidationScope` | no 5th member | ✅ 4 members |
| `TapCommand.swift`, `scripts/`, `.github/workflows/`, `project.pbxproj` | untouched | ✅ empty |
| C2 `noPackagePositionEverCarriesAQualifiedToken` | byte-identical | ✅ `sha256:1561832f…` on both sides |
| `MutationCommandTests.swift` | one hunk only (the C1 ban list + 2 new cases) | ✅ `rg -c '^@@'` → 1 |
| README canonical three-line install block | byte-identical | ✅ `sha256:858f3437…` on both sides |

The **one deliberate edit to a shipped guard** in the whole change is C1's ban list, extended with the
single prefix token `"TrustGrant"` (covering all five new type names) plus `"grantsIndividually"`. One
prefix is stronger and shorter than five entries.

## 7. Verification — and the measurement that overturned an archived belief

### Two rounds

| Round | Commit verified | Verdict |
|---|---|---|
| 1 | `72c9f9b` | **FAIL** on *evidence completeness only* — 0 blockers, 0 CRITICAL, both commands exit 0, 49/50 unit scenarios traced |
| 2 | `5922e37` | **PASS WITH WARNINGS** — 55/55 scenarios, 11/11 requirements, 0 blockers, 0 CRITICAL, 4 WARNING, 3 SUGGESTION |

Round 1's two gaps were discharged by maintainer-authorized `sdd-apply` units, not argued away:
PT1.2 gained a real covering test (`cb3527d`), and the `package-mutation` delta's header arithmetic was
corrected against an independent re-count — 7→**8** shipped scenarios, 10→**11** delta scenarios,
8→**9** `unit` — while the stated end state (60 − 8 + 11 = 63) was already right and never moved.

### ME2 — the measurement falsified the scenario it was written to confirm

PT8.3 originally asserted that a per-package grant **survives** TM7's untap flow, inherited from
`m7-tap-trust`'s **R7**. On 2026-08-24 the maintainer ran it live on Homebrew **6.0.18-182-ga963211**
(transcript filed at `evidence/me2-transcript.txt`, 4,954 bytes, committed at `5922e37`):

- **BEFORE** — `trust.json` `sha256:63ed7c9d…`, 14 entries, the same digest ME1 recorded and the same
  content as the `#7764` apply fixture.
- **The measurement** — `guria/tap` untapped from **inside** Cellar, so TM7's `brew untrust <tap>` ran
  behind the accepted removal. **AFTER**: both `guria/tap/nehir` and `guria/tap/nehir@rc` are gone from
  `casks`; digest `1150051f…`. **`brew untrust <tap>` cascades to that tap's per-package grants.**
- **The spec was amended to the measurement.** PT8.3 was rewritten to the **outside-Cellar** orphan it
  can actually evidence (`nkzw-tech/tap/codiff`, a grant no Cellar action ever touched), and **PT8.4 was
  added** for the measured cascade. **No code, no test and no other delta moved** — verified: the
  production diff across the amendment is empty. The implementation was never at fault; Cellar rendered
  exactly what the report said, refreshed through the `.taps` ride, as DD-3/DD-4 designed.

**The direction matters: this is a strengthening.** If TM7's flow removes per-package grants, the
in-Cellar path closes the dormant-grant hole **at package granularity too** — better than
`m7-tap-trust` recorded. That change's **R7** claim is **false for the in-Cellar path** and is now
marked as such in both this capability's and `tap-management`'s provenance, so it cannot be carried
forward unqualified.

**What was *not* measured, and must stay unmeasured in the record**: `brew untrust --cask <qualified>`.
The cascade says nothing about whether *naming* a qualified package to `untrust` registers a grant
through `explicitly_allowed?` before removing it. The cascade finding makes assuming that safe **more**
tempting, which is exactly why the deferral is restated in three places.

**Bonus evidence the transcript produced that no scenario claimed**, recorded because it is free
corroboration on real hardware and cheap to lose:
- `brew untap jnsahaj/lumen` was **refused** by Homebrew (installed formulae present) and Cellar
  surfaced exactly **one failed activity item** — the `m7` **D4** narrowing holding on a real refusal.
- The live one-projection count line appeared **identically** on the tap row and the detail header
  (`jnsahaj/lumen — 1 formula · 1 trusted individually`), with the `lumen` row carrying
  `Trusted individually` — PT5.1 and PT5.4 observed live.
- The "Other trusted packages" section already surfaced the orphan `nkzw-tech/tap/codiff` **and** the
  URL-shaped unattributed formula `https://github.com/cloudmanic/spice-edit/spice-edit` — PT8.1 and
  PT3.2 observed live.

### ME1 — PT4.5, observed 2026-08-24

`trust.json` was `sha256:63ed7c9d…`, 553 bytes, mtime unchanged **before and after two reads** — the
bare read granted nothing. The payload's 14 entries equal the count Cellar accounts for
(`ledger.entryCount == 14`, `accounting.total == ledger.entryCount`). Design **Open Question 2** was
cleared by measurement and must not be re-run as a gate. **Open Question 3** was answered
opportunistically: every entry in the real payload is qualified, so an unqualified entry stays
theoretical — no extra sentence, no code change.

### RED-first, and the one place there was no honest RED

RED was proved by execution for every behavioural task. Two exceptions are **disclosed rather than
dressed up**:

- **Task 6.1** — an absence guard over a surface deliberately given no control. The only RED would be
  adding the control. Anchored non-vacuously over 8 produced strings and two exact copies.
- **Task 11.1 (PT1.2)** — the behaviour was already correct, and the only RED would be inventing a
  package-level three-valued API the spec does not require and the focused unit was not authorized to
  add. Substituted by **two reverted production mutations**, each observed red
  (`grantsIndividually` forced to `false` → 2 failures; `TrustGrantState.entryCount` for `.unreported`
  forced to `0` → 1 failure), with production restored **byte-identical** afterwards. The test also
  pins **both halves as necessary**, so dropping either collapses the triple into the pair PT1 forbids.

### Warning disposition at close — all four closed

| WARNING | Closed by |
|---|---|
| **W1** `apply-progress.md` "79 / 86" vs the mechanical 78 / 85 | `e561abf` — corrected in place, with the prior prose tally named as such |
| **W2** PT8.3's evidence clause named an unfiled screenshot | `e561abf` — reworded to name **only** `evidence/me2-transcript.txt`; the transcript's addendum states the screenshots were viewed live and never archived |
| **W3** the restoration block did not isolate the re-grant commands | `e561abf` — labelled addendum names all three commands and records that **re-tapping alone re-armed nothing**, turning PT8.4's closing clause from an inference into evidence |
| **W4** the RESTORED payload was read on 6.0.19, not 6.0.18 | `e561abf` — same addendum; the cascade predates the auto-update and the restored payload is content-identical to the fixture |

SUGGESTIONs 1 and 2 are carried into the promoted provenance (§5, and the `package-trust` provenance).
SUGGESTION 3 is carried open in §11.

## 8. Test, gate and size state at close

| Gate | State |
|---|---|
| `swift test --package-path Packages/CellarCore` | ✅ **1,825 tests / 215 suites, 0 failures**, 1 pre-existing known issue (`OperationCenterCancelTests.swift:183`, `withKnownIssue`) — baseline 1,793 / 210, **+32** |
| `xcodebuild test … -only-testing:cellarTests` | ✅ **248 passing results**, `** TEST SUCCEEDED **` — baseline 247, **+1** |
| `xcodebuild test … -only-testing:cellarUITests/PerPackageTrustUITests` | ✅ green (three launches, one per report state) |
| `xcodebuild build` | ✅ `** BUILD SUCCEEDED **` |
| Review gate | ➖ structurally absent — RDD disabled (§3) |

### Size against the governing budget

| Bucket | Forecast | **Measured at close** | Miss |
|---|---|---|---|
| Code + tests (26 files) | 2,736 – 3,312 | **+3,313 / −18 = 3,331** | **+0.6%** over the ceiling |
| SDD artifacts + evidence (11 files) | 1,900 – 2,300 | **+3,077** | **+34%** over the ceiling |
| **Branch total (37 files)** | 4,636 – 5,612 | **+6,390 / −18 = 6,408** | **+14%** over the ceiling |

**The code+test forecast was almost exact; the artifact forecast was not.** This is the `m7` learning-E
follow-through working as intended — the artifact bucket was forecast and measured **separately**, so
the miss is attributable rather than smeared across the total. The overshoot is concentrated in three
files the forecast under-counted or did not carry: `tasks.md` at **576** lines (forecast ~350),
`verify-report.md` at **282**, and `apply-progress.md` at **395** — the last two together were
forecast as "~250–450 at verify time" for the verify report alone, with `apply-progress.md` not in the
forecast at all. **Actionable for the next forecast**: enumerate `apply-progress.md` *and* the verify
report as named artifact-bucket line items, and forecast `tasks.md` from the scenario count rather than
from a prior change's file size.

The `size:exception` (obs `#7768`) was taken against the **5,000-line** session budget after the Review
Workload Guard fired at 93%–112% of it. The maintainer explicitly **rejected** the recommended
WU1–WU3 / WU4–WU7 chained split, on the `m7` precedent.

### Attempt ledger

**All attempts settled; no attempt left open at close.** Three maintainer-authorized resets are audited
in the attempt authority:

| Reset | Scope | Lines |
|---|---|---|
| Apply | WU1–WU7 on one branch under the recorded `size:exception` | **5,718** |
| Amendment | discharge round 2 — the PT8 amendment forced by the live ME2 measurement | **164** |
| Hygiene | discharge of the round-2 WARNINGs, including the 282-line verify report | **297** |

Each reset is an authorized continuation of the same change, not a retry of failed work: the amendment
existed because a measurement contradicted a specification, and the hygiene unit existed because a
verification report named four record-level defects. Both were the correct response, and both are
visible as their own commits (`5922e37`, `e561abf`).

## 9. Decisions recorded, with what each rejected

| # | Decision | Rejected |
|---|---|---|
| **Scope** (obs `#7759`) | Full **read-only** per-package trust surface | Grant/revoke controls — blocked on the unmeasured `brew untrust <qualified>` probe and PM10's argv prohibition |
| **DD-2** | Own wire, source and store; constant argv `trust --json v1` | Extending `tap-info` (it does not publish per-package grants at all); reading `~/.homebrew/trust.json` from disk (location varies by configuration; the standing rule is to ask `brew`) |
| **DD-3** | **No new `InvalidationScope` member** — the grant read rides the existing `.taps` domain | A `.packageTrust` member declared across `MutationCommand`, `ServiceCommand`, `CleanupCommand`, `TapCommand`, `MutationGates.domain(for:)` and `RefreshDomain` — dead declaration surface on five families, since no Cellar command can mutate a per-package grant |
| **DD-4** | Both reads issued concurrently via `async let`; the **tap** read alone decides the refresh outcome | Sequential tap-then-grants (a full subprocess round trip added to every refresh); a second coordinator; letting a degraded grant read turn a successful tap refresh into a failed one |
| **DD-5** | Attribution = exact tap-name prefix **and** `publishes(_:in:)` | `split("/")` and positional reads; prefix alone; `publishes` alone |
| **DD-7** | `countLine` is `nil` for `.unreported` **and** for zero attributed grants | "0 trusted individually"; a "not individually trusted" marker — a verdict TM11 prohibits outright |
| **DD-9** | All four namespaces decoded; `commands` counted as **other**; `taps` decoded and **explicitly excluded** from package accounting, pinned by test | Ignoring `commands`; ignoring `taps`; letting the ledger's `taps` key feed a badge — precisely the second source of truth TM12 forbids |
| **DD-10** | `PackageDetailView` takes the store (its sixth), not a closure | The `m7` DD-12 closure idiom; a pre-computed `Bool` — neither re-renders on refresh |
| **DD-11** | C1's ban list gains the single prefix `"TrustGrant"` + `"grantsIndividually"`; **C2 byte-identical**; the read spine gets its own additive absence test | Five separate ban entries; widening C2 to cover the read (it enumerates `BrewMutating` conformers, so widening changes its meaning) |
| **DD-12** | TM12 modified **first**, in work unit 1, before any code | Shipping the code and amending the spec at archive — proposal risk **R1** |
| **Gate** (obs `#7766`) | PT2 aligned **to** DD-3 where spec and design conflicted | Adding the invalidation domain the spec draft implied |
| **Delivery** (obs `#7768`) | Single PR with `size:exception` | The recommended WU1–WU3 / WU4–WU7 chained split |

**Five binding reconciliations (B1–B5)** resolved in the **spec's** favour, plus one implementation
deviation (`TrustGrantLedger.isEmpty` is not package-scoped, because under B4 an orphan tap grant is its
own accounted **and shown** category), are recorded in full in `openspec/specs/package-trust/spec.md`
`## Provenance`. They exist so a future reader does not mistake `design.md`'s superseded copy and
three-category accounting for the shipped shape.

## 10. Archive integrity

### Mechanical operations, with mandatory readbacks

| Operation | Mechanism | Readback |
|---|---|---|
| `package-trust` created | `sed -n '58,487p'` of the delta, concatenated between authored header and provenance | **1 × `diff` — empty.** Promoted requirement bytes identical to the delta |
| `tap-management` TM12 replaced | `sed -n` byte-range splice (main 542–606 ← delta 34–143) | **4 × `diff` — all empty.** Preamble + TM1–TM11 (1–541); the new block vs the delta; TM13 + the whole prior provenance; and the provenance append verified additive-only |
| `package-mutation` PM10 replaced | `sed -n` byte-range splice (main 619–721 ← delta 34–184) | **4 × `diff` — all empty.** Same four checks |
| `package-detail` PD8 appended | `sed -n` byte-range insert (delta 41–96 after main line 291) | **4 × `diff` — all empty.** Same four checks |
| Archive move | `git mv openspec/changes/m9-per-package-trust → openspec/changes/archive/2026-08-24-m9-per-package-trust` | **`diff -r` against a pre-move recursive snapshot — empty, exit 0.** Source directory confirmed gone |

**No artifact content passed through a Read → Write path.** Empty diffs are the only passing evidence
and they are what was produced. Two further checks were run beyond the contract's minimum — the
strict-superset verification of the replaced TM12 and PM10 ranges (§5) — and one of them found a claim
that did not hold.

### Archive contents

```
2026-08-24-m9-per-package-trust/
├── explore.md
├── proposal.md
├── design.md
├── tasks.md              (85/85 complete)
├── apply-progress.md
├── verify-report.md      (round 2 — PASS WITH WARNINGS)
├── archive-report.md     (this file — additive, excluded from the readback)
├── evidence/
│   └── me2-transcript.txt   (with the labelled post-verify addendum)
└── specs/
    ├── package-trust/spec.md
    ├── tap-management/spec.md
    ├── package-mutation/spec.md
    └── package-detail/spec.md
```

### Hybrid-store parity — stated honestly

The Engram twins were byte-current with their OpenSpec files at their authoring phase. This phase then
edited `tasks.md` (seven checkboxes). **Obs `#7767` is therefore a point-in-time snapshot and no longer
byte-matches the archived `tasks.md`**; it was deliberately **not** re-saved, because doing so would
route artifact content back through model generation — precisely the truncation hazard the
mechanical-copy contract forbids. The same is true of `#7772` (`apply-progress`), whose *"Remaining"*
section this phase deliberately left unedited.

**After archive, the archived OpenSpec files under
`openspec/changes/archive/2026-08-24-m9-per-package-trust/` are the authoritative audit trail.** The
Engram twins remain useful for recovery and search, not for byte-comparison.

## 11. Carried follow-ups — recorded open, deliberately not closed here

| # | Item | Why it is open |
|---|---|---|
| 1 | **The `brew untrust --formula\|--cask <qualified>` probe** | Gates **any** future per-package mutation slice. It must answer whether the revocation *itself* registers a grant through `explicitly_allowed?` before removing it. The `m9` cascade finding says nothing about the qualified form and makes assuming it safe more tempting, not less |
| 2 | **`BrewfileDiff.isPresent` (R15)** | A separate ~1-line slice, deliberately excluded from this change so it does not ride an oversized PR |
| 3 | **Trust state for official taps** | `tap-management` TM4 keeps official sources non-mutable, so no control could appear for them anyway. Carried from `m7-tap-trust` unchanged |
| 4 | **PD8 renders nothing on today's shipped surface** | PD6 keeps third-party packages out of catalog detail and TM1 forbids a third-party fallback, while per-package grants exist only for third-party packages. PD8 exists so the bare-name hazard is **impossible to ship**; it becomes visible only when a third-party detail surface arrives. Not a defect — but it must not be mistaken for dead text and deleted |
| 5 | **A trust column in the Brewfile diff** | Carried from `m7-tap-trust`, still not scoped |
| 6 | **Stale change folders in `openspec/changes/`** | `m3-4`, `m3-services-cleanup-taps` and `m5-pro-parity` are pre-SDD-convention leftovers that are neither active nor archived. Cleaning them is a housekeeping slice of its own; this phase archived only its own change and touched nothing else |
| 7 | **Two pre-existing `cellarUITests` failures on `main`** | Open since `m8-bundle-rename`; unrelated to this change, and `PerPackageTrustUITests` is green |
| 8 | **The singular `1 trusted individually` form in the XCUITest** | `verify-report.md` SUGGESTION 4/3 — still optional, still not taken |
| 9 | **The missing `size:exception` GitHub label on PR #73** | The decision is audited (obs `#7768`) and stated in the PR body; only its label projection is absent. Recorded, not retro-applied |

## 12. Learnings worth carrying

1. **Forecasting the artifact bucket separately worked, and it is the only reason the miss is
   readable.** Code+tests came in at +0.6% over a 576-line-wide window; artifacts came in at +34%. Had
   they been forecast as one number, the accurate half would have hidden the inaccurate half. The next
   forecast should name `apply-progress.md` and the verify report as line items and size `tasks.md`
   from the scenario count.
2. **When a measurement contradicts a specification, amend the specification.** ME2 falsified PT8.3's
   premise. The spec moved, the transcript was filed in the repository rather than paraphrased, and no
   code, test or other delta was touched. The resulting change is *safer* than the one specified.
3. **A belief inherited from an archived change is still a belief, and archives must be correctable.**
   `m7-tap-trust`'s R7 was carried forward for a whole cycle before anyone measured it. Both this
   capability's provenance and `tap-management`'s now say plainly that R7 is false for the in-Cellar
   path — the archive is an audit trail, and an audit trail that cannot record "this earlier entry was
   wrong" is worth less than one that can.
4. **A "strict superset" claim is checkable, so check it.** The `package-mutation` delta's claim was
   byte-true; the `tap-management` delta's was not. Both took one `diff` to establish, and only the
   second one taught anything.
5. **Disclose the absence of an honest RED instead of manufacturing one.** Twice in this cycle the
   behaviour was already correct, and both times the tests were anchored positively and proven
   non-vacuous by reverted mutations rather than dressed as RED→GREEN. The verification report accepted
   both — because they were disclosed.

## 13. Artifact traceability (Engram observation IDs)

| Artifact | Topic key | Obs ID |
|---|---|---|
| Exploration | `sdd/m9-per-package-trust/explore` | **#7758** |
| Scope decisions (binding) | `sdd/m9-per-package-trust/scope-decisions` | **#7759** |
| Proposal | `sdd/m9-per-package-trust/proposal` | **#7760** |
| Design | `sdd/m9-per-package-trust/design` | **#7763** |
| Probe results (measured, ME1 fixture) | `sdd/m9-per-package-trust/probe-results` | **#7764** |
| Spec deltas (rev 2) | `sdd/m9-per-package-trust/spec` | **#7765** |
| Gate decisions | `sdd/m9-per-package-trust/gate-decisions` | **#7766** |
| Tasks | `sdd/m9-per-package-trust/tasks` | **#7767** |
| Delivery decision (`size:exception`) | `sdd/m9-per-package-trust/delivery-decision` | **#7768** |
| Apply progress | `sdd/m9-per-package-trust/apply-progress` | **#7772** |
| Verify report (round 2) | `sdd/m9-per-package-trust/verify-report` | **#7773** |
| ME2 measurement (rev 2) | `sdd/m9-per-package-trust/me2-measurement` | **#7775** |
| PR checkpoint | `sdd/m9-per-package-trust/pr-checkpoint` | **#7776** |
| Archive report | `sdd/m9-per-package-trust/archive-report` | *this document* |

All fourteen were read by this phase. Round 1's verify report was superseded in place by round 2 under
the same topic key — Engram upserts overwrite — which is why round 1's findings survive only in round
2's disposition table and in §7 above.

**No `sdd/m9-per-package-trust/review/*` topics exist**, because no review was ever started for this
candidate (§3).

---

## Final state

Cellar reads both of Homebrew's trust granularities and shows what it finds. A tap whose packages work
through individual grants no longer reads as an unexplained **Untrusted**: the badge still tells the
truth about the tap, and beside it a count line — from **one** projection value, on the row and the
header alike — tells the truth about the packages. Open the tap and it names which ones. Grants Cellar
cannot attribute to an installed tap are not counted quietly and not dropped: they get their own
section, including the `commands` namespace Cellar does not model and a URL-shaped formula entry no
positional split could ever parse.

Nothing on any of those surfaces grants, revokes or gates anything. `MutationCommand.swift` is a 0-line
diff, no argv element gained a second slash, and `InvalidationScope` still has four members.

And one belief this project carried since August 23rd is now known to be false: `brew untrust <tap>`
cascades, so Cellar's own untap already closes the dormant-grant hole at package granularity. That was
found by running the measurement instead of trusting the record — and the record was corrected to
match.

**Cycle complete.** Explored, proposed, specified, designed, implemented under strict TDD, verified
across two rounds, measured on real hardware, merged as PR #73, and archived.
