# Archive Report: `m12-menu-bar`

**Archived**: 2026-08-26 · **Milestone**: **no PRD milestone closed.** `PRD.md` §7 (:199) enumerates
**M1–M6 only**. This change delivers the **first named item of M6 "Ship"** (:217, *"Menu bar extra"*)
and the **first bullet of §3.8** (:113) — M6's **fifth slice**, after the tip jar (built, then removed
by decision), the CI signing/notarization pipeline, Sparkle 2 in-app updates and the self-hosted tap,
all four of which M6's own parenthetical records. Recorded this way per `rules.archive` ("record which
PRD milestone the archived change closed"), following the `m10`/`m11` precedent for post-exit slices.
**Status at close**: implemented in **one apply batch** over **six work-unit commits**, verified in
**two verify rounds**, **archived on the branch — not pushed, no PR opened, not merged**.
**Verify verdict**: **PASS WITH WARNINGS** (re-verified at `270f41e`, canonical) · 0 blockers ·
0 CRITICAL · **12 requirements / 33 scenarios, all COMPLIANT** · 2 WARNING, 5 SUGGESTION. Admitted by
`gentle-ai sdd-verify-validate --requirements 12 --scenarios 33`.
**Artifact store**: hybrid (OpenSpec canonical + Engram mirror, project `swiftui_cellar`).
**Review gate**: structurally **absent** — receipt-driven development is disabled (user-owned switch),
no review was ever started for this candidate, so delivery follows ordinary repository policy. There is
no `reviewGate` key to read and none to block on; `gentle-ai sdd-status` reported
`dependencies.archive: ready`, `taskProgress 26/26 allComplete: true`, `blockedReasons: []`.

This report is the terminal record of the cycle. It describes the state of the change **at close**, not
the state at any earlier point. `apply-progress.md` and `verify-report.md` are intermediate snapshots
archived alongside it; where either disagrees with the final state, the final state is recorded here and
the snapshot's claim is attributed to its own moment rather than restated as a current fact.

## 1. Facts that moved after the snapshots were written

| Fact | Snapshot claim | State at close |
|---|---|---|
| Task tally | "**29/29 tasks complete**" (`apply-progress.md:8`, Engram `#7896`) | **26/26.** `tasks.md` carries **26** checkboxes, **all ticked, none `[ ]`** — confirmed mechanically and by `gentle-ai sdd-status` (`total: 26, completed: 26, pending: 0`). The prose "29" counted TDD sub-steps, not checkboxes; `verify-report.md` raised the discrepancy as **W1**. **This phase reconciled nothing** — no checkbox was edited, because none was stale |
| Verify verdict | the `22516eb` run reported **`fail`** on a red `unit` command (C1) | **Superseded.** The canonical report is the re-verification at `270f41e`: **`pass_with_warnings`**, C1 resolved. The superseded run's verdict is history, not current state |
| The two `TapShippingProofTests.swift:617` failures | "blocking" in the `22516eb` run | **Pass at `270f41e`** after the one-line copy fix in that commit |
| UI failure count | "8 failures" (`apply-progress.md:104`) | **7 at `270f41e`**, same suite, no relevant change between the runs — `testCleanupCO7…` passed the second time. The Cleanup set is **flaky, not deterministic** |
| App-unit row count | "274" (recorded in apply) | **285 passed / 0 failed**, measured in both re-runs (`verify-report.md` **S3**) |
| Branch tip | `22516eb`, six commits (`apply-progress.md:5`) | **`270f41e`, seven commits** over `main` @ `f2efbdd`. The seventh is the tap copy fix described in §7 |

Two launch-brief facts were checked and **corroborated**: the seven-commit list and `270f41e`'s minimal
one-file diff, and the binding 0-line-diff set (§6).

## 2. Specs synced

| Domain | Action | Details |
|---|---|---|
| `menu-bar` | **Created** | New capability. 10 ADDED requirements / 25 scenarios promoted byte-identical. `0 → 10 req`, `0 → 25 sc` |
| `installed-inventory` | **Updated** | 1 ADDED (**II16**), 0 modified, 0 removed, 0 renamed. `15 → 16 req`, `79 → 82 sc` |
| `service-management` | **Updated** | 1 MODIFIED (**SM3**), 0 added, 0 removed, 0 renamed. `12 req` unchanged, `40 → 41 sc` |

Counts above are **recounted mechanically from the merged files** (`### Requirement:` / `#### Scenario:`
occurrences), not trusted from any delta header: `menu-bar` 10/25, `installed-inventory` 16/82,
`service-management` 12/41. All three agree with the delta arithmetic in `specs/README.md`.

**`rules.archive`'s destructive-delta warning did not fire.** Nothing was removed or renamed anywhere,
and the one MODIFIED block is a **strict superset** of the text it replaced (§3).

**`package-mutation` was activated, not changed** — no delta. `MutationCommand.upgradeAll` already
lowers to bare `brew upgrade` and already requires no confirmation.

## 3. Mechanical operations, with mandatory readbacks

Every promotion was performed with shell byte-slicing (`sed -n`, `cp`, `mv`) and verified by `diff`.
**No artifact content was routed through a model Read/Write path.** Thirteen readbacks, all empty.

| # | Operation | Readback | Result |
|---|---|---|---|
| 1 | `menu-bar` created: authored header (19 lines) + `sed -n '49,406p'` of the delta + authored provenance | `diff` promoted bytes (new 20–377) vs delta 49–406 | **empty, exit 0** |
| 2 | installed to `openspec/specs/menu-bar/spec.md` | `diff` staged build vs installed file | **empty, exit 0** |
| 3–5 | `installed-inventory`: pre 1–909 + delta 45–94 + blank + pre 910–1257 + provenance | three `diff`s — preamble/II1–II15 preserved; II16 bytes vs delta 45–94; prior `## Provenance` untouched | **all empty, exit 0** |
| 6 | additive-only check | `diff` pre vs post: **0 deleted lines**, 86 added | **additive only** |
| 7 | installed to `openspec/specs/installed-inventory/spec.md` | `diff` staged build vs installed file | **empty, exit 0** |
| 8–10 | `service-management`: pre 1–99 + delta 40–108 + blank + pre 143–520 + provenance | three `diff`s — SM1–SM2 preserved; SM3 bytes vs delta 40–108; SM4–SM12 + prior `## Provenance` untouched | **all empty, exit 0** |
| 11 | additive-only check | `diff` pre vs post: **0 deleted lines**, 60 added | **strict superset** |
| 12 | installed to `openspec/specs/service-management/spec.md` | `diff` staged build vs installed file | **empty, exit 0** |
| 13 | Archive move `openspec/changes/m12-menu-bar` → `openspec/changes/archive/2026-08-26-m12-menu-bar` | **`diff -r` against a pre-move recursive snapshot** | **empty, exit 0.** Source directory confirmed gone |

`git mv` was attempted first and declined: the change folder was **untracked** (it appears in this
commit for the first time), so `mv` performed the move. The archived tree carries all ten pre-existing
artifacts; `archive-report.md` is **additive** and excluded from the comparison because it did not exist
in the source snapshot.

**Independent check on the one MODIFIED block.** Diffing the *shipped* SM3 block (main 100–142) against
the *promoted* block (delta 40–108) produces exactly two additive hunks — the secondary-surface
paragraph with its `(Previously: …)` note, and the new scenario. **Every other line, including all four
shipped scenarios, is byte-identical**, and those four still carry no `- Verification:` line, exactly as
before. The delta's byte-identical claim is therefore corroborated, not merely repeated.

## 4. Task completion

**26 of 26, all ticked, zero `[ ]`.** No archive-time reconciliation was performed and none was needed;
the Task Completion Gate passed on the persisted artifact as `sdd-apply` left it. **W1 is a prose tally
discrepancy in `apply-progress.md`, not a stale checkbox** — the checkbox artifact was always complete.

Six work units, one commit each, in dependency order: 1 D1 badge alignment (`d507258`) · 2
`MenuBarProjection` (`0acdb10`) · 3 services core deltas (`962360f`) · 4 preference + Settings
(`445f9ac`) · 5 popover view (`e0e6ffd`) · 6 scene wiring (`22516eb`). Strict TDD throughout — RED
recorded before every GREEN, with a named safety net per cycle.

## 5. Tests at close (`270f41e`)

| Suite | Command | Exit | Result |
|---|---|---|---|
| CellarCore | `swift test --package-path Packages/CellarCore` | **0** | **1891 / 1891 passed**, 219 suites, 1 known issue |
| App unit | `xcodebuild test … -only-testing:cellarTests` | **0** | **285 passed, 0 failed** |
| Full incl. UI | `xcodebuild test …` | 65 | **314 passed, 7 failed** — all pre-existing `cellarUITests` Cleanup rows (**W2**) |

All 19 m12-delivered rows (7 `unit` + 12 `unit-app`) are green. No failure outside `cellarUITests`
Cleanup in either verify round.

## 6. Delivery footprint

`git diff --shortstat f2efbdd 270f41e` → **16 files changed, 1,636 insertions, 8 deletions** (1,644
authored lines against the project's 5,000-line budget, `single-pr` with a recorded `size:exception`).

**Binding 0-line diffs re-verified empty at `270f41e`** — none of these files appears in
`git diff --stat`: `cellar.xcodeproj/project.pbxproj`, `cellar/Shell/AppSection.swift`,
`cellar/ContentView.swift`, `cellarTests/AppSectionPlacementTests.swift`,
`cellar/Services/ServicesListView.swift`, `cellar/Services/ServiceRow.swift`, and the whole
`cellarUITests/`. The pbxproj stayed untouched because `cellar/` and `cellarTests/` are
`PBXFileSystemSynchronizedRootGroup`s, so the new `cellar/MenuBar/` directory joined the target with no
project-file edit — the rollback plan's central claim, confirmed.

## 7. Commit `270f41e` — outside m12 spec scope, archived in the same branch

`fix(taps): point the official-source pane at the Search section by its real name` —
`cellar/Taps/TapDetailView.swift` only, **1 insertion / 1 deletion**, one string literal at `:82`. It
implements no m12 requirement, is referenced by no m12 scenario, and touches no file in the binding
0-line-diff set. It was included by **maintainer decision** to clear a pre-existing red suite inherited
from PR #89.

**Recorded for accuracy**: the commit message calls "the Search section" the AppSection's *real* title,
implying the previous copy was wrong. It is not that simple. `AppSection` ships **two** user-visible
names for the same section — `title` is `Search` (:114) and `sidebarTitle` is `Search catalog` (:144).
The old copy named the sidebar wording and was **not factually inaccurate**; the new copy is equally
accurate *and* clears `TapShippingProofTests`' substring exclusion. It is a copy adjustment that clears
a textual proof, not the correction of a factual error.

## 8. Open questions closed during apply (task 6.4, observation only)

- **`shippingbox` exists in this SDK.** The `cube.box` fallback was never needed.
- **`MenuBarExtra`'s `.task` under `.menuBarExtraStyle(.window)` fires once per presentation and never
  at insertion.** R10 anticipated the opposite risk (that it might *not* re-fire); the observed
  behaviour is strictly better for the one-refresh-on-open contract, and no speculative fallback was
  written.

## 9. Tracked follow-ups (recorded, not fixed here)

- **W2 — `cellarUITests` Cleanup rows are window-frame-dependent.** At the app's own
  `.defaultSize(width: 1440, height: 900)` the sidebar's `ScrollView` ends near y≈1126 while
  `sidebar-cleanup` sits at y≈1161, so `openCleanup(in:)`'s click never lands and every later
  `cleanup-*` identifier is absent. **Pre-existing**, but m12 *unmasks* it: `id: "main"` on the
  `WindowGroup` resets the AppKit frame-autosave key that had been hiding it on this machine. The set is
  **flaky** (8 failures at `22516eb`, 7 at `270f41e`, no relevant change between). **Fix**: scroll the
  sidebar before clicking in `cellarUITests`. Out of m12 scope by maintainer decision.
- **S5 — `TapShippingProofTests`' exclusion sweep is a whole-file substring scan**, so it cannot
  distinguish *offering* a capability from *mentioning* it in prose. That is what PR #89 tripped and what
  `270f41e` worked around by rewording. **Fix**: scope the sweep to control labels — the suite already
  asserts controls separately via `staticButtonLabels(in:)` and its `Button {` ban — or the next
  legitimate cross-reference trips it again.
- **S1** — the popover ships copy the spec's copy table does not pin (`Everything is up to date`,
  `Nothing is waiting for an update.`, `outdated`, the `Updates`/`Services` headers). No requirement is
  violated; pin it if the copy is ever localized.
- **S2** — `UserDefaults(suiteName:) ?? .standard` would write real defaults under UI test. Unreachable
  in practice (the suite name is a compile-time constant), so it is a robustness note only.
- **S3** — the app-unit row count recorded during apply (274) is stale; 285 is the measured figure.
- **S4** — the specs declare 14 `unit` + 15 `unit-app`; the 19 delivered rows carry all 33 scenarios.
  Rows and scenarios are not 1:1 by design, so this is a bookkeeping note, not a coverage gap.

## 10. Delivery state at archive, and what remains

The archive was performed **on the branch by maintainer instruction**: `feat/m12-menu-bar` at `270f41e`,
**not pushed**, **no PR opened**, **not merged**, **no release tag**. The three promoted main specs and
this archived folder therefore describe behaviour that exists **on the branch only** until that branch
lands. Every provenance entry written by this phase says so explicitly, so a future reader cannot mistake
a promoted spec for shipped `main` behaviour.

Remaining for the maintainer, in order: push the branch, open the PR, merge, and (optionally) tag. None
of that is an SDD phase, and none of it is blocked by anything in this cycle.

## 11. Artifact traceability (Engram, project `swiftui_cellar`)

| Artifact | Engram observation | OpenSpec canonical (archived) |
|---|---|---|
| explore | `#7819` | `explore.md` |
| proposal | `#7820` | `proposal.md` |
| spec (3 deltas + index) | `#7821` | `specs/README.md`, `specs/{menu-bar,installed-inventory,service-management}/spec.md` |
| design (revision 2) | `#7822` | `design.md` |
| tasks | `#7893` | `tasks.md` |
| apply-progress | `#7896` | `apply-progress.md` |
| verify-report (revision 2, canonical) | `#7898` | `verify-report.md` |
| **archive-report** | **`sdd/m12-menu-bar/archive-report`** | **this file** |

All five required artifacts (`proposal`, `spec`, `design`, `tasks`, `verify-report`) were read in full
via `mem_get_observation` before any merge or move. The Engram `tasks` mirror `#7893` still shows its
checkboxes **unticked**: it is the **pre-apply** mirror, saved by `sdd-tasks` and never re-saved by
`sdd-apply`. The canonical `tasks.md` in this archive is the completion record — 26/26 — and it is what
the Task Completion Gate was evaluated against. The mirror was left untouched rather than back-filled,
because rewriting a phase's own artifact after the fact would falsify the audit trail.

## 12. What this change actually settled

Cellar could already compute how many packages are outdated — snooze-aware, self-updating-cask-aware,
app-level — but only while its window was open. The missing piece was a **surface**, not a mechanism, so
the change adds **no store, no refresh loop, no brew invocation and no `Process`**.

It also settled a disagreement the shipped app already had with itself. The Updates list, the Updates
lens, the bulk-upgrade label and Health all read the snooze-aware
`InstalledBrowse.outdatedIDs(metadata:)`, while the sidebar badge and the Home attention card read
`packages.filter(\.isOutdated).count` — **non-compliant with II12's shipped text**, which already
forbade a snoozed package contributing to "the outdated count **or badge**". Adding a third consumer
without fixing that would have shipped a menu bar contradicting either the sidebar or the spec. II16 is
the generalisation that makes the third consumer structurally safe: **agreement between count-bearing
surfaces is now a property of a value, not a coincidence between call sites**, and an app-wide scan
scoped to collection-derivation shapes fails if a fourth surface ever computes its own number.

## 13. Note for anyone who runs `gentle-ai sdd-status m12-menu-bar` after this archive

It will report `artifactStore: engram`, `taskProgress 0/26`, `applyState: ready`,
`nextRecommended: apply` and `archive: blocked`. **That is a fallback artefact, not a regression.** With
the change folder moved out of `openspec/changes/`, the status command finds no OpenSpec change and
falls back to the Engram topics — where the `tasks` mirror `#7893` is the **pre-apply** copy whose
checkboxes were never re-saved (§11). Immediately **before** the move, with the OpenSpec artifacts still
in place, the same command reported `artifactStore: openspec`, `taskProgress 26/26 allComplete: true`,
`dependencies.archive: ready`, `nextRecommended: archive`, `blockedReasons: []`. That is the reading the
gate was evaluated against, and `openspec/changes/archive/2026-08-26-m12-menu-bar/tasks.md` — 26 ticked
boxes, zero `[ ]` — is the durable evidence.
