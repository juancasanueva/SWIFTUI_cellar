# Archive Report: `m7-tap-trust`

**Archived**: 2026-08-23 · **Milestone**: PRD **M3 "Services, Cleanup & Taps"** §3.7 (:108), delivered
during **M6 "Ship"** because Cellar's own distribution channel is a third-party tap
**Status at close**: implemented, verified, re-verified, **merged to `main` in two PRs**, archived —
PR **#68** at `3018fe4`, follow-up PR **#69** at `5fffb89`
**Verify verdict**: PASS WITH WARNINGS · 0 blockers · 0 CRITICAL · validator-admitted · **14 requirements /
90 scenarios, all discharged**
**Artifact store**: hybrid (OpenSpec + Engram, project `swiftui_cellar`)
**Review gate**: structurally **absent** — RDD disabled, no review started, delivery under ordinary
repository policy

This report is the terminal record of the cycle. It describes the state of the change **at close**, not
the state at any earlier point. `apply-progress.md` and `verify-report.md` are intermediate snapshots
archived alongside it; where either disagrees with the final state, the final state is recorded here and
the snapshot's claim is attributed to its own moment rather than restated as a current fact.

**Four facts moved after those snapshots were written**, and this report carries the later value in each
case:

| Fact | Snapshot claim | State at close |
|---|---|---|
| The untap command order | `untrust` **then** `untap` (D1, everywhere in proposal/design/first verify) | `untap` **then** `untrust`, and only behind a removal Homebrew accepted — **D4**, `5fffb89` |
| Tasks | 72/79, Phase 9 open (`apply-progress`, first verify) | **79/79**, Phase 9 transcribed |
| `manual-evidence` | 4 specified, 0 transcribed | **4/4 transcribed** on the maintainer's Mac |
| Tests | CellarCore 1785/209, `cellarTests` 242 | CellarCore **1793 / 210 suites / 1 known issue**, `cellarTests` **242 / 0** |

---

## 1. Milestone linkage

- Closes the **PRD §3.7 (:108) obligation** — *"Warning copy when adding third-party taps (untrusted
  code)"* — which M3's `m3-taps` slice satisfied only nominally. It also completes the
  **M3 taps manager** (PRD :207-208) by giving the capability the one verb Homebrew 6 split out of
  `brew tap`.
- **It was delivered during M6 "Ship" for a concrete reason.** M6 made Cellar's own distribution channel
  a third-party Homebrew tap, so a new user's very first action is adding a tap they must separately
  trust — and Cellar told them the wrong story about what had just happened. The add confirmation said
  *"Adding \<tap\> trusts third-party formulae and casks that can distribute code."* On Homebrew 6
  `brew tap` grants nothing; the tap it added was **inert**.
- **The change is best understood as four honesty repairs, not one feature**: the add copy stops claiming
  a grant it never made; a tap's real trust state becomes visible; the grant becomes explicitly
  answerable and revocable; and an installed package whose tap Homebrew withholds stops reading
  "Not installed." on a Mac where it is plainly installed.
- **This is the first change in the project to reverse one of its own binding decisions mid-cycle.** D1
  fixed revoke-then-remove; **D4** reversed it after Phase 9 manual evidence found the loop it created.
  §7 and §10 record both states rather than presenting the final one as if it were always the plan.

## 2. Delivery references

| Item | Value |
|---|---|
| Base | `main` at `349a47f` |
| PR #1 | **#68** — https://github.com/juancasanueva/SWIFTUI_cellar/pull/68 |
| PR #1 title | `feat(taps): make Homebrew tap trust visible, explicit and revocable` |
| PR #1 merged | **2026-08-23**, merge commit `3018fe4` on `main` — 12 commits |
| PR #1 size at close | **49 files, +6,954 / −119 = 7,073 changed lines** (see §8 for why the ledger recorded 6,555) |
| PR #2 | **#69** — https://github.com/juancasanueva/SWIFTUI_cellar/pull/69 |
| PR #2 title | `fix(taps): remove the tap before revoking its trust` |
| PR #2 merged | **2026-08-23**, merge commit `5fffb89` on `main` — 3 commits |
| PR #2 size | **15 files, +716 / −143 = 859 changed lines** |
| Both PRs together | `349a47f...5fffb89` — **51 files, +7,529 / −121 = 7,650 changed lines** |
| Delivery strategy | `single-pr` with **`size:exception` recorded** (maintainer, 2026-08-23) against the governing 5,000-line budget |
| Archive branch | `docs/sdd-archive-m7-tap-trust`, from `main` at `5fffb89`, carrying `f178494` |

**Commits on `feat/m7-tap-trust` (PR #68):**

| # | Commit | Subject |
|---|---|---|
| 1 | `66941fa` | `docs(sdd): record the m7-tap-trust exploration, proposal, spec deltas, design and tasks` |
| 2 | `a842d5e` | **WU1** `feat(taps): read and show the trust state Homebrew already reports` |
| 3 | `ff8e2bb` | **WU2** `fix(taps): stop claiming that adding a tap trusts it` |
| 4 | `7bb141e` | **WU3** `fix(installed): a withheld tap is absent, not empty` |
| 5 | `7665d9d` | **WU4** `feat(taps): grant and revoke tap trust as explicit answers` |
| 6 | `583ba8d` | **WU5** `fix(taps): revoke the grant before removing the tap` |
| 7 | `d78d8b1` | **WU6** `feat(activity): explain an untrusted-tap refusal and offer the only safe recovery` |
| 8 | `0d13513` | **WU7** `fix(brewfile): install the bare token a qualified entry names` |
| 9 | `34af13f` | `docs(sdd)` — apply-progress |
| 10 | `3307241` | `docs(sdd)` — `size:exception` recorded in the forecast table |
| 11 | `c5d4b67` | `docs(sdd)` — verify report, **closing W1–W5** |
| 12 | `a3f4419` | `docs(sdd)` — PR task ticked |

**Commits on `fix/untap-remove-then-revoke` (PR #69):**

| # | Commit | Subject |
|---|---|---|
| 1 | `34d6736` | `test(taps): require untap to remove first and revoke only after a successful removal` (**RED**) |
| 2 | `bc087b1` | `fix(taps): remove the tap before revoking its trust, and only after brew accepts the removal` (**GREEN**) |
| 3 | `bdff5c8` | `docs(sdd): record the m7-tap-trust Phase 9 manual evidence and close the formula-refusal gate` |

**Commit on the archive branch before this phase:** `f178494`
`docs(sdd): record the m7-tap-trust re-verification and close the formula-refusal claims` — **closes
W6, W7 and W8**.

No `Co-Authored-By` and no AI attribution on any of the 16 commits. All conventional.

## 3. Review gate

`reviewGate` is **structurally absent** from this change's status, and that is the expected shape, not a
defect to investigate:

- Receipt-driven development is **disabled** for this repository (session preflight `RDD disabled`). With
  the kill switch off, zero review code ran for this candidate, so no transaction, ledger, receipt or
  gate context was ever created and none exists to read.
- There is therefore **no `disabled/unmanaged` value to check** and **no approval to fabricate**.
  Delivery of PR #68 and PR #69 proceeded under **ordinary repository policy**, and archive proceeds the
  same way — identical to every prior slice.
- Consequently the `sdd/m7-tap-trust/review/*` Engram topics do not exist and were not read.

## 4. Task completion gate

**Gate PASSES.** The archived `tasks.md` carries **79 checked** items and **0 unchecked**
(`rg -c '^\s*- \[x\]'` → 79, `rg -c '^\s*- \[ \]'` → 0). **No archive-time stale-checkbox reconciliation
was performed**; every box was closed by a commit on `main` before this phase started, and `tasks.md`
was archived unmodified by this phase.

| Task group | Items | Closed by |
|---|---|---|
| Phases 0–8 except 8.7, plus Phase 10 | 72 | `sdd-apply` during the cycle |
| `8.7` open the PR | 1 | PR #68, ticked at `a3f4419` |
| **Phase 9** manual evidence `9.1`–`9.6` | 6 | `bdff5c8` — all six observed on the maintainer's Mac (§7) |

**Superseded snapshot claims, recorded rather than echoed.** `apply-progress.md` states "72/79" and lists
`8.7` and `9.1`–`9.6` under *Tasks left unchecked*; the first `verify-report` verdict states "72 checked,
7 unchecked". Both were accurate **when written**. All seven closed afterwards, in the commits named
above. Neither snapshot was edited.

**One obligation closed outside the task count, recorded so the pattern is visible.** `design.md:1034`
carried an unchecked `- [ ]` obligation box — *"Formula refusal wording — unmeasured (R6)"* — that
`tasks.md` reaching 79/79 did **not** cover, because the box lives in a different artifact. It was
measured on 2026-08-23 (obs `#7738`) and marked `[x]` at `f178494`. A "complete" task list is not
evidence that every recorded obligation is closed.

## 5. Spec sync

| Domain | Action | Details |
|---|---|---|
| `tap-management` | **Updated** | 6 MODIFIED / 2 ADDED — **11 req / 34 sc → 13 req / 55 sc** |
| `package-mutation` | **Updated** | 2 MODIFIED / 1 ADDED — **9 req / 48 sc → 10 req / 60 sc** |
| `brewfile-management` | **Updated** | 2 MODIFIED / 0 ADDED — **9 req / 38 sc → 9 req / 40 sc** |
| `installed-inventory` | **Updated** | 1 MODIFIED / 0 ADDED — **14 req / 64 sc → 14 req / 67 sc** |

- **No destructive delta anywhere.** `rules.archive`'s "warn before merging destructive deltas" clause
  **did not fire** in any of the four: 11 MODIFIED, 3 ADDED, **0 removed, 0 renamed**. Every requirement
  no delta named is byte-identical to its prior text, proved by diffing the merged file's preserved
  regions against a pre-merge copy (§14).
- **The counts were re-derived from the merged files, not copied from the delta headers**, and all four
  agree exactly (§14). The delta headers were right.
- **The three ADDED requirements**: `tap-management` **TM12** *Tap trust is read from the tap snapshot and
  shown as a three-valued state* (+5 sc) and **TM13** *Trust is granted and revoked only by an explicit
  answer, and never implicitly* (+6 sc); `package-mutation` **PM10** *A refusal to load from an untrusted
  tap is a typed outcome, and no argv ever becomes the grant* (+8 sc).
- **No `## Verification classes` table exists in any of the four target specs** — confirmed by direct
  count (`0` occurrences in each), as `apply-progress` 10.1 and both verify runs predicted. Unlike the
  `m6-sparkle-updates` / `m6-cask-tap` precedent there was **nothing to hand-update**. This change is the
  first to annotate these four capabilities with inline `- Verification:` lines; the annotations travel
  with the promoted blocks and the untouched requirements deliberately keep none. That asymmetry is
  **recorded in each spec's provenance rather than "fixed"** by annotating blocks this change never
  reviewed.

### Hand-edits made outside the promoted blocks

Three were mandated by verify (W2 and archive-readiness item 2) and all three were made:

1. **`brewfile-management` header prose (`:7`)** — *"silently defeated the tapTrust requirement below"* now
   names the `ConfirmationDisclosure.tapAdd` case with the dated **D2** rename note. Out of every block, so
   a byte-correct promotion structurally could not reach it.
2. **`brewfile-management` provenance, the `m5-brewfile` **D4** entry (pre-merge `:510`)** — *"still raises
   `ConfirmationDisclosure.tapTrust` with identical text"* now names the tap-add confirmation and carries
   the dated rename note. The rule it records is unchanged; only the case name moved.
3. **`tap-management` provenance (pre-merge `:355`)** — recorded `m3-taps` as *"11 requirements /
   **33** scenarios"* while the file has carried **34** `#### Scenario:` headings since the day it was
   written. **Corrected to 34**, recounted directly from the file, with the correction and its reason
   stated inline. A pre-existing transcription defect, not a lost scenario.

Each of the four specs' `## Provenance` sections was then extended with this change's decisions (**D1,
D2, D3, D4**), what each rejected, the batch-disclosure resolution, the replaced/extended `(Previously:)`
notes, the class-table asymmetry, and the deferred follow-ups.

### `rg 'tapTrust'` does not return zero, and that is correct

The archive brief and the `brewfile-management` delta both asked for **zero** hits across
`openspec/specs/` after promotion. **Ten remain, and every one is deliberate.** Reporting them rather
than deleting them:

| Where | Why it stays |
|---|---|
| `brewfile-management` BF5 `:247` and BF7 `:373` | The `(Previously:)` rolling notes the **delta itself wrote**. They name the old case precisely to record that the rename happened. Deleting them would erase the reason the rename exists, and would break the delta↔main byte identity §14 proves. |
| `brewfile-management` `:8`, `:561` | The two hand-edits above. Each now *names* `tapTrust` as the former name inside a dated rename note. |
| `brewfile-management` `:594-595`, `:613-617`; `tap-management` `:711-712` | The archive provenance entries recording **D2** and this very sweep. |
| `tapTrustGrant` (2 hits) | The **new** case. Always correct. |

The useful invariant is not "the string is absent" but "**no requirement still asserts the old case as
current**", and that holds: every surviving mention is explicitly historical. `rg '\.tapTrust\('` and
`rg 'case tapTrust\b'` over `cellar/` and `Packages/` return **0** — the sweep that actually governs
source.

## 6. What shipped

**Against `349a47f`, both PRs together: 51 files, +7,529 / −121.** Of that, **41 files / 3,265 lines** are
authored product, test and documentation change; the remaining **10 files / 4,385 lines** are the SDD
artifacts.

### Behaviour, capability by capability

| Area | Change |
|---|---|
| **Trust is readable** | `TapWire` decodes the per-tap `trusted` boolean Homebrew 6 already publishes in `brew tap-info --installed --json`. **No second probe, no second store, no new invalidation domain.** It decodes into a **three-valued** `TapTrustState { trusted, untrusted, unreported }`: absent or null is `unreported`, never `untrusted` — the same rule this codebase already applies to a cask's tri-state `auto_updates`, and the whole of the Homebrew-version-drift mitigation. |
| **Trust is visible** | One projection feeds both the tap list row and the tap detail header, so they cannot drift. `untrusted` → the exact badge `Untrusted` plus a **Trust** control; `trusted` → no badge, an **Untrust** control; `unreported` → no badge and **neither** control, neither of which builds or spawns anything. |
| **The add copy stops lying** | `ConfirmationDisclosure.tapTrust` → `.tapAdd(TapName)`, whose exact text is *"Adding \<tap\> clones a third-party repository. Homebrew will not load its formulae or casks until you trust it, and Cellar does not trust it for you."* |
| **The grant is an explicit answer** | New `.trustTap` / `.untrustTap` commands with argv exactly `trust user/repo` and `untrust user/repo`, built from literal verbs and the validated typed tap identity. **Trust is confirmed** with `.tapTrustGrant`, whose text names what a grant actually is: third-party code running as you, with your permissions. **Untrust is not confirmed** — revocation only reduces authority. |
| **The grant does not outlive the tap** | Untap and Force Untap submit two ordered commands. After **D4**: the removal **first**, and the revocation only behind a removal Homebrew accepted (§10). |
| **A refusal is explained** | `MutationOutcome.refusedUntrustedTap`, classified from **stderr only** on one structural phrase over the shipped tail window, with **nothing extracted from the payload**. The recovery derives its tap from Cellar's own tap-info snapshot and offers the ordinary Trust confirmation — never a re-run with a qualified name. |
| **A withheld tap is absent, not empty** | `InstalledPackage.tap` became `String?` and the decoder stopped collapsing `tap: null` into `""`. The tap inventory gained a third state — *"Installed. Homebrew withholds its tap while this tap is untrusted."* — which still offers **Show in Installed**, because that handoff selects by exact `PackageID`. |
| **No path grants trust implicitly** | Not the add, not a Brewfile import, not refusal recovery, not a retry. **D3**: a `/`-qualified Brewfile entry is applied by its **bare token**, because Homebrew 6 reads a qualified token on the command line as a per-package grant — so forwarding the file's token would let its author grant trust on the importing user's Mac. |

### Binding 0-line diffs held, end to end

```
git diff --stat 349a47f...5fffb89 -- \
  Packages/CellarCore/Sources/BrewClient/MutationCommand.swift scripts .github \
  Packages/CellarCore/Sources/Catalog cellar.xcodeproj/project.pbxproj
```

→ **empty**, re-run at archive against `HEAD` and still empty. `MutationCommand.swift` is byte-identical
across the whole change **including the D4 correction**, which is what makes **DD-8** ("no `/` gate on
`PackageTarget.init?` or `MutationName.isSafe`") a checkable claim rather than an assertion. Narrowing
that gate would have made every `TapName` unconstructible, because `TapName.init?` is expressed over the
same gate and a tap name *is* `owner/repo`.

`cellarTests/` and the CellarCore test targets are `PBXFileSystemSynchronizedRootGroup`s, so the new test
files needed no `project.pbxproj` edit.

## 7. Verification

**Verdict: PASS WITH WARNINGS**, twice — a first verdict at `3307241` and a scoped **re-verification at
`5fffb89`** after D4. Envelope `gentle-ai.verify-result/v1`, verdict `pass_with_warnings`, **0 blockers,
0 CRITICAL**, requirements **14/14**, scenarios **90/90**, `test_exit_code 0`, `build_exit_code 0`.
Admitted by `gentle-ai sdd-verify-validate --requirements 14 --scenarios 90` → `valid: true`. Evidence
revision `sha256:79417b7745a350e282b57c31a4e0f6f4af357b0ea96b107b1ebd1a36c33ab82e`.

**`90/90` is fully discharged at close, not partly deferred:**

| Class | Count | State at close |
|---|---|---|
| `unit` / `e2e` | **86** | 86/86 runtime-proven; RED independently re-proven for WU1, WU5, WU6, WU7 **and** for the D4 commit |
| `manual-evidence` | **4** | **4/4 transcribed** on the maintainer's Mac (Homebrew 6.0.18-167) — TM13.5, TM13.6, PM10.7, PM10.8 |

### Phase 9 — the four manual-evidence scenarios, all observed

Captured 2026-08-23, 20:11–20:48, against the Xcode Debug build. `/Applications/cellar.app` was never
touched and **no `brew upgrade` ran without `--dry-run`** — the binding held on every attempt.

| # | Task | Scenario | Result |
|---|---|---|---|
| 9.1 | ME1 | **TM13.5** — the grant is an explicit answer; `brew trust --json v1` lists the tap afterwards and the badge clears with no manual reload | **PASS** |
| 9.2 | ME2 | **PM10.8** — a refusal launched from inside Cellar renders `.refusedUntrustedTap` with brew's own `brew trust …` line visible in the untruncated log | **PASS** |
| 9.3 | ME3 | **TM13.6** — full cycle on a throwaway tap (`oven-sh/bun`, cleaned up afterwards): untap from inside Cellar removes the grant, and re-tapping comes back untrusted | **PASS** |
| 9.4 | ME5 | **PM10.7** — the **formula** refusal wording, the one phrase never measured before | **PASS** — `Refusing to load formula agavra/tap/tuicr from untrusted tap agavra/tap.` Same structural phrase, so the classifier covers formulae and **risk R6 is CLOSED** (obs `#7738`) |
| 9.5 | — | supporting: withheld-tap copy and **Show in Installed** land on the right record | **PASS** |
| 9.6 | — | supporting: Homebrew < 6 degradation is not reproducible on this machine | Recorded as limitation **R5**, covered by the `.unreported` decode test |

### RED-first was re-proven by execution, not accepted from the report

The verifier reconstructed RED in detached worktrees under
`~/programming/swiftUI/cellar-worktrees/` (deliberately outside `/tmp`, per the CodeGraph
worktree-placement rule), then removed and pruned them.

- **WU1, WU5, WU6** failed to compile at their parents with the exact missing members
  `apply-progress` recorded.
- **WU7** failed at **runtime**, reproducing the recorded failure string character for character:
  `(qualified.installs.first?.arguments → ["install","--formula","acme/tap/thing"]) ==
  ["install","--formula","thing"]`. **The D1 absence assertion genuinely caught the real defect** — it is
  not a test that could only ever pass.
- **The D4 commit** (`34d6736`) fails to **compile**, which is the strongest RED available for a missing
  seam: 12 errors dominated by `value of type 'OperationCenter' has no member 'submitDependentSequence'`.
  The same filter at `5fffb89` returns `Test run with 27 tests in 3 suites passed`.

### Warning disposition at close — all eight closed

| # | Warning | State at close |
|---|---|---|
| **W1** | PM10.5's non-vacuity clause did not cover `ServiceCommand` / `CleanupCommand` | ✅ **CLOSED in `c5d4b67`** |
| **W2** | The `brewfile-management` archive note would raise a false alarm about `tapTrust` hits | ✅ **CLOSED in `c5d4b67`**, and acted on in this archive — §5 |
| **W3** | `cellar/AppTestFixtures.swift` (+15) was in neither the design's *File Changes* table nor the deviation list | ✅ **CLOSED in `c5d4b67`** — recorded as **D-8** at `apply-progress.md:203` |
| **W4** | Four stale `tapTrust` doc comments in source and tests | ✅ **CLOSED in `c5d4b67`** — reworded to `.tapAdd` |
| **W5** | `size:exception` recorded self-contradictorily across `tasks.md` and `apply-progress.md` | ✅ **CLOSED in `c5d4b67`** |
| **W6** | The `package-mutation` delta still called the formula refusal wording *unmeasured* — **and it sat inside a delta block, so archive would have promoted a false statement into the main spec** | ✅ **CLOSED in `f178494`** before promotion |
| **W7** | R6 in `design.md:981`/`:1034` and `proposal.md:309` carried the same stale claim; `:1034` was an unchecked obligation box | ✅ **CLOSED in `f178494`** — marked `[x]` and cited to obs `#7738` |
| **W8** | The `tap-management` delta header claimed post-merge `13 / 54`; D4 made it `13 / 55` | ✅ **CLOSED in `f178494`** |

**Two SUGGESTIONS carried, not closed.** **S1** — six `file:line` citations into TM7 (across tests,
source and `design.md`) drifted when D4 rewrote the block; the *claims* are all still correct, only the
anchors are stale. Accepted as-is. **S2** — CodeGraph reports "no covering tests" for `onSettle` and
`submitDependentSequence` because both are reached through a `@MainActor` closure it cannot trace;
coverage is real (`OperationCenterDependentSequenceTests` exercises both), so this is an index artifact,
recorded so a future reader does not read it as a gap.

### Assertion quality

Audited on both verify runs. **No tautologies, no assertion that never calls production code, no ghost
loops, no smoke-only tests, no implementation-detail coupling, no mock-heavy imbalance.** The D4 suite is
the strongest example: every negative case is asserted **twice over** — once on the queue
(`items.count`) and once at the process boundary (`launchCount`, and no recorded spec containing
`"untrust"`) — which is what makes "no phantom queue item" and "nothing was spawned" separable facts
rather than one restated claim. Triangulation is genuine: the lead's outcome is varied across refused,
cancelled and succeeded, and the trust state across `trusted` / `untrusted` / `unreported`.

## 8. Test, gate and size state at close

| Measure | Value at close | Superseded value (and its source) |
|---|---|---|
| CellarCore | **1,793 tests / 210 suites passed, 1 known issue** | `apply-progress` and the first verify record **1,785 / 209** — correct at `3307241`, before PR #69 added the `OperationCenterDependentSequenceTests` suite (+1 suite, +8 tests). Baseline at `349a47f` was **1,754 / 209**; Δ **+39**. |
| `cellarTests` | **242 passed / 0 failed** | Baseline **238**; Δ **+4**. Unchanged by PR #69. |
| `cellarUITests/TapTrustUITests` | **1 passed / 0 failed** | |
| Known issue | `OperationCenterCancelTests · theHarnessReportsAMissingProcess` — **pre-existing and unchanged** | Present identically in the `349a47f` baseline |
| `swift test --package-path Packages/CellarCore` | exit 0 | |
| `xcodebuild test … -only-testing:cellarTests` | `** TEST SUCCEEDED **`, exit 0 | |
| Bindings | `MutationCommand.swift`, `scripts/`, `.github/`, Catalog module, `project.pbxproj` — **byte-empty diff** | Re-run at archive against `HEAD`; still empty |
| Coverage | ➖ threshold is 0 in `config.yaml`; not gated | |

**Counting-convention note.** `xcodebuild` emits no per-test count line for this Swift Testing target.
The authoritative figure comes from `xcrun xcresulttool get test-results summary`, whose
`devicesAndConfigurations[0]` block reports **242** while the top-level rollup reports **232** —
parameterized cases counted differently. The pass/fail verdict is identical in both, and 242 is the
figure the apply phase recorded, so it is the one used throughout.

### Size against the governing budget

| Measure | Value |
|---|---|
| Authored product, test and docs change (both PRs) | **41 files, 3,265 changed lines** |
| SDD artifacts | **10 files, 4,385 lines** (4,611 on disk at close, after `f178494`) |
| PR #68 at close | **7,073 changed lines**, 49 files |
| PR #69 | **859 changed lines**, 15 files |
| Both PRs | **7,650 changed lines**, 51 files |
| Governing budget | **5,000** — **`size:exception` recorded** by maintainer decision, 2026-08-23, with the ledger objective reset under that reason |
| Forecast vs actual | `tasks.md` forecast **~2,885–3,567**; apply measured **6,555** at `34af13f`; the merged figure is **7,650** |

**The `size:exception` figure and the final figure differ, and both are reported.** The exception was
granted against **6,555 lines** (2,680 code+tests / 3,760 SDD docs), measured at `3307241`. That
measurement was taken **before** the verify report itself (`c5d4b67`, ~500 lines) was committed to the
branch, and before PR #69 existed. The ledger figure is correct for its moment and is what the maintainer
decided against; **7,650** is the state at close. Neither number is wrong; they answer different
questions.

**The overrun is almost entirely the SDD-artifact bucket, and by a wide margin.** It was forecast at
**600–900 lines** and landed at **4,385** — a 5–7× miss, dominated by `design.md` (1,047 lines),
`verify-report.md` (797) and four delta specs totalling 1,387. The code+test bucket was forecast at
1,815–2,197 and landed at ~3,265: a 1.5–1.8× overshoot on an estimate that had already had the house
1.9–2.3× correction applied. **The correction is being applied to the wrong bucket** (§12).

**Attempt ledger:**

| Attempt | State |
|---|---|
| apply | complete — 72/79 at its own snapshot; the remaining seven closed afterwards (§4) |
| verify (1) | complete — `pass_with_warnings` at `3307241`, validator-admitted |
| verify (2) | complete — scoped re-verification at `5fffb89` after D4, `pass_with_warnings`, validator-admitted |
| archive | this phase |

## 9. Still open at close — the exact remaining checklist

**None of these blocked merge or archive.**

| # | Item | Discharged by |
|---|---|---|
| 1 | **Per-package trust grants are invisible in v1.** All 8 of the maintainer's other third-party taps show **Untrusted** while their installed packages keep working through per-package grants (`brew trust --json v1`: **9 formulae, 4 casks**). The badge is accurate and the omission is the proposal's declared non-goal — but a user reads "Untrusted" beside a tap whose packages upgrade fine. | A follow-up surfacing *"N packages trusted individually"* from `brew trust --json v1`. Not a defect; a completeness gap the first real Mac made visible. |
| 2 | **`README.md:44` recommends a qualified token to users** — `brew install --cask juancasanueva/cellar/home-cellar`, presented as "the unambiguous form". On Homebrew 6 that **is** a per-package trust grant: the exact mechanism D3 exists to keep out of Cellar's own argv. Pre-existing and outside this branch's diff, and safe as a deliberate user action — but it now sits beside a product that treats the same token shape as a threat. | A follow-up sweep of the install documentation. |
| 3 | **S1 — six TM7 line anchors drifted** when D4 rewrote the block (`TapCommandTests.swift:218,:236`, `TapCommand.swift:206`, `OperationCenterBulk.swift:136`, `design.md:56,:57`). Every claim is still correct; only the anchors are stale. | Refresh or drop them the next time those files are touched. |
| 4 | **Homebrew < 6 degradation was never reproduced** (9.6). On such a Homebrew, every untap that succeeds shows a visibly *failed* `untrust` beside it. D4 narrowed this: a refused removal now shows **one** failed item instead of two. | A machine with Homebrew 5, if one is ever available. Covered meanwhile by the `.unreported` decode test. |
| 5 | **R15 — a qualified Brewfile entry keeps its qualified identity for diffing**, so it always projects as "missing" even when the bare package is installed. Accepted for v1; D3 fixed the *argv*, not the *diff*. | A follow-up on the Brewfile diff projection. |

## 10. Accepted deviations from the design

### D4 — the one decision this cycle reversed

**Maintainer decision, 2026-08-23, taken after the first verify verdict and delivered as PR #69.**

- **What D1 originally fixed**: the untap action submitted `untrust` **then** `untap`, unconditionally.
  The reasoning was sound in isolation — revoke while the tap still resolves, and never leave a dormant
  grant a later re-tap could silently re-arm.
- **What Phase 9 found on a real Mac**: Homebrew **refuses** to untap a tap that still owns installed
  packages — *"Refusing to untap juancasanueva/cellar because it contains the following installed
  casks: …"*, exit 1. So the revocation succeeded and the removal was refused. That left the user on a
  tap that was now untrusted, still installed, and whose **Force Untap was hidden** — because Force Untap
  is offered only for a tap whose packages Homebrew will still name, and Homebrew withholds them while a
  tap is untrusted. **A dead end whose only signposted exit was the removal that had just failed.**
- **What D4 does**: the removal leads; the revocation is armed only on `outcome.isSuccess`. A refused
  removal submits **no revocation at all** — no phantom queue item for a command that never ran — and
  carries Homebrew's own reason. `brew untrust` after a successful `brew untap` was **measured** at
  exit 0, so nothing is lost by waiting.
- **New seams, all RED-first**: `ActivityItem.onSettle`, `OperationCenterBulk.submitDependentSequence`,
  `ConfirmationRequest.dependsOnLead`. `submitSequence` keeps its unconditional fan-out for every other
  caller, and `request(_:)` forwards `dependsOnLead: false`, so **no existing caller changed behaviour**.
- **The footer copy was corrected with it**, so the UI stops implying an exit that does not exist.
- **Rejected**: submitting both commands unconditionally (the state D4 exists to remove); suppressing the
  revocation's own failure.

### Deviations D-1 … D-8, each checked against the relevant scenario

All eight were declared at apply or verify time; verification re-read each against the delivered bytes
and judged them **design-refining and spec-preserving**.

| # | Substance | Verdict |
|---|---|---|
| **D-1** | Four more shipped sites asserted the old add sentence and moved with the D2 rename; `TapCommandTests:111` re-anchored on `"clones a third-party repository"` because the new copy says "formulae **or** casks" | ✅ violates nothing |
| **D-2** | The rename sweep is zero over **source**, not over this change's own artifacts — three hits remained in `design.md` / `tasks.md`, which are the written *instruction* to perform the rename | ✅ accepted (and W2/W4 handled the rest) |
| **D-3** | `TapProjection.publishes` moved WU3 → WU6, because it had no caller until `UntrustedTapRecovery` and adding it earlier would have shipped untested production code under `strict_tdd` | ✅ correct call |
| **D-4** | The two tap controls submit through `operations` directly rather than a `ContentView` closure; DD-12's closure is still used where it is genuinely required (`ActivityDrawer`, which holds no `TapStore`) | ✅ violates nothing |
| **D-5** | Unit 7's fixtures are the identities Cellar actually types plus the Brewfile qualified path — deliberately **not** a demand for a `/` gate DD-8 forbids | ⚠️ raised **W1**, closed in `c5d4b67` |
| **D-6** | `SwiftDataHistoryRecorder.classify` gained `case .refusedUntrustedTap: ("refusedUntrustedTap", nil)`; the `nil` status is honest because the command never ran | ✅ violates nothing |
| **D-7** | Per-surface badge accessibility identifiers, and the badge must not be uppercased — `.textCase(.uppercase)` rendered `UNTRUSTED` while TM12 pins the exact copy `Untrusted` | ✅ correct fix, found by the UI test |
| **D-8** | `cellar/AppTestFixtures.swift` (+15) changed but appeared in neither the design's *File Changes* table nor D-1…D-7 | ✅ recorded at verify, same class as D-6 |

**Design decisions honoured without deviation**: **D1, D2, D3** (proposal and obs `#7730`), **DD-1…DD-14**
(design revision 2), and the five open questions all resolved to their stated defaults (obs `#7727`).

## 11. Carried follow-ups (recorded open, deliberately not closed here)

**Owned by this slice's decisions:**

- **A per-package trust surface.** The single most visible v1 gap (§9 item 1). `brew trust --json v1`
  already keys taps, formulae, casks and commands, so the data is one read away — but v1 deliberately
  built **no pre-launch gate**, because a per-package grant makes a tap-state gate block what brew itself
  allows. Any per-package surface must keep that constraint.
- **A trust column in the Brewfile diff.** Deferred with **R15**.
- **Trust state for official taps.** TM4 keeps them non-mutable, so no control could appear anyway; only
  the state would be shown.
- **The `README.md:44` qualified-install recommendation** (§9 item 2).
- **Refresh or drop the six drifted TM7 line anchors** (S1).

**Open, recorded, not owned by this slice:**

- The `Home-Cellar.app` rename, the `~/Library/Caches/Cellar` migration, the landing page →
  `homepage` interaction, W2 of `m6-cask-tap` (the newer-prerelease ordering) and submission to
  `homebrew/cask` all remain open from M6.
- A DMG, a PR/test CI workflow, SwiftLint adoption and PRD §9 Q1 remain open from earlier slices.
  `cellarUITests/ReleaseNotesUITests` is still unowned since `m5-health`.

## 12. Learnings worth carrying

**A. A decision that is correct in isolation can still be wrong in sequence — and only a real machine
finds out.** D1's revoke-then-remove was defensible on every ground the proposal, the design and the
first verification examined: revoke while the tap still resolves, never leave a dormant grant. It took
one maintainer, one real Homebrew and one tap that still owned an installed cask to expose that brew
refuses that removal, and that the resulting state is a **dead end with its only exit hidden**. Neither
the spec review nor 86 passing tests could have found it, because every one of them modelled a removal
that succeeds. **Phase 9 is not paperwork.** It is the only step in this pipeline that runs the product
against a machine that does not share the product's assumptions.

**B. Stale prose inside a delta block is a different class of defect from stale prose anywhere else.**
Three of this cycle's warnings (W6, W8, and the archive-time finding in §14) share one shape: a sentence
that was true when written, superseded by a later decision, and sitting **inside a block archive will
promote verbatim into the source of truth**. A stale line in a report is a footnote; the same line inside
a MODIFIED block becomes a rule. The cheap defence is the one the re-verification used: after any
post-verify correction, re-read the delta blocks for statements the correction invalidated — the count in
the header is not the only thing that moves.

**C. The Homebrew 6 tap/trust split is not cosmetic, and Cellar was describing the old world.**
`brew tap` clones and grants nothing (obs `#7721`); `brew trust` / `brew untrust` are separate,
idempotent, and persisted in `~/.homebrew/trust.json` (obs `#7722`); per-package grants are independent
of tap grants and a per-package grant **restores** the withheld `tap` field (obs `#7724`); and naming a
`/`-qualified package on the command line **is** a per-package grant, which is why the obvious "fix" for
a refusal is the security hole (`trust.rb#explicitly_allowed?`). Every one of those was measured before a
line was written, and the last one is the reason D1's argv prohibition is asserted as an **absence over
the whole surface** rather than left to review.

**D. Three tooling gotchas worth a house note.** (1) Making a property optional in Swift is often **not**
a compile-error migration: `String? == String` promotes, so every reader keeps compiling and stays
semantically correct — the readers need a *test* to pin them, not the compiler, which is why
`InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch` exists. (2) Swift Testing's
`-only-testing:` selector silently runs zero cases without the trailing `()`, and the suite still
"starts". (3) Source-scanning guards read comments as well as code, so a rename that is clean over
`rg '\.tapTrust\('` can still leave four doc comments describing a case that no longer exists (W4).

**E. Forecast the artifact bucket separately, and stop applying the code correction to it.** The house
1.9–2.3× correction is applied to code and tests on the stated grounds that spec buckets are enumerated
requirement-by-requirement and are not subject to discovery drift. This cycle: code+tests overshot its
**corrected** estimate by 1.5–1.8×, and the SDD-artifact bucket overshot 600–900 → **4,385**, five to
seven times. The artifact bucket is where the entire budget miss lives, in this cycle and in
`m6-cask-tap` before it. A change with four delta specs, a validator-retried design and two verification
passes has an artifact cost that is predictable from those facts alone.

## 13. Artifact traceability (Engram observation IDs)

Every artifact was retrieved in full via `mem_get_observation` or read from its canonical file, never
from a search preview. **In hybrid mode the OpenSpec file is canonical**; the Engram observation is a
mirror.

| Artifact | Engram obs | Topic | Archived file |
|---|---|---|---|
| explore | **`#7723`** | `sdd/m7-tap-trust/explore` | `explore.md` |
| orchestrator probes (Homebrew 6 trust behaviour measured) | **`#7721`** | — | — (Engram only) |
| probes 2 (`tap-info` exposes `trusted`; per-package entries; idempotence) | **`#7722`** | — | — (Engram only) |
| probes 3 (a per-package grant restores `tap`) | **`#7724`** | — | — (Engram only) |
| decisions **D1**, **D2** | **`#7725`** | — | — (Engram only) |
| proposal | **`#7726`** | `sdd/m7-tap-trust/proposal` | `proposal.md` |
| five open questions resolved to defaults | **`#7727`** | — | — (Engram only) |
| spec (delta set, revision 2 after the design's eight amendments) | **`#7728`** | `sdd/m7-tap-trust/spec` | `specs/*/spec.md` (4 files) |
| design (revision 2) | **`#7729`** | `sdd/m7-tap-trust/design` | `design.md` |
| decision **D3** (Brewfile bare token) | **`#7730`** | — | — (Engram only) |
| design validation pass 2 | **`#7731`** | — | — (Engram only) |
| tasks | **`#7732`** | `sdd/m7-tap-trust/tasks` | `tasks.md` |
| apply-progress | **`#7733`** | `sdd/m7-tap-trust/apply-progress` | `apply-progress.md` |
| apply done + **`size:exception`** | **`#7734`** | — | — (Engram only) |
| verify-report (revision 2, re-verification at `5fffb89`) | **`#7735`** | `sdd/m7-tap-trust/verify-report` | `verify-report.md` |
| PR #68 opened | **`#7736`** | — | — (Engram only) |
| decision **D4** | **`#7737`** | — | — (Engram only) |
| PM10.7 measured — formula refusal wording | **`#7738`** | — | — (Engram only) |
| Phase 9 complete, 79/79 | **`#7740`** | — | — (Engram only) |
| **archive-report** | *this file* | `sdd/m7-tap-trust/archive-report` | `archive-report.md` |

**Known-lossy mirrors — the archived file is authoritative:**

- **`#7726` (proposal)** predates **D4**. It states D1's untap order as "untrust THEN untap" and its
  Approach §4 calls that order load-bearing. That was true when written and is **superseded**; §10 above
  and the archived `proposal.md` (whose R6 row was updated at `f178494`) carry the record.
- **`#7728` (spec)** and **`#7729` (design)** record **89** scenarios and `tap-management` **13 / 54**.
  Both are pre-D4 figures. The archived files and this report carry **90** and **13 / 55**.
- **`#7732` (tasks)** is the authoring-time snapshot, so its checkboxes read unchecked and it records
  76 tasks. The archived `tasks.md` carries the final **79/79** and is the authority for §4.
- **`#7733` (apply-progress)** is an intermediate snapshot: its "72/79", "1785 tests" and "Phase 9 is
  the maintainer's" claims were true when written and are superseded here.
- **`#7735` (verify-report)** is revision 2 and is current, but the *canonical* file carries the first
  verdict and the Phase 9 addendum verbatim as well; the file is the authority.

`review/*` topics do not exist — see §3.

## 14. Archive integrity

**Mechanical copy contract satisfied.** No artifact byte passed through a model read/write path. Every
requirement body was extracted with `sed -n` and concatenated by the shell; the move used `git mv`; the
archive report is the only authored file, and it is additive.

| Operation | Mechanism | Readback | Result |
|---|---|---|---|
| `tap-management` — 6 MODIFIED blocks promoted | `sed -n` slices from the delta | `diff` merged vs delta, per block | **empty** ×6 |
| `tap-management` — 2 ADDED blocks appended after TM11 | same | `diff` merged vs delta, per block | **empty** ×2 |
| `tap-management` — preserved header, TM1–TM4, TM10, the seven `<!-- TMn -->` markers, provenance | `sed -n` from the pre-merge copy | `diff` merged vs pre-merge | **empty** ×9 |
| `package-mutation` — PM1, PM3 promoted; PM10 appended | `sed -n` slices | `diff` merged vs delta | **empty** ×3 |
| `package-mutation` — preserved header, PM2, PM4–PM9, provenance | `sed -n` from the pre-merge copy | `diff` merged vs pre-merge | **empty** ×4 |
| `brewfile-management` — BF5, BF7 promoted | `sed -n` slices | `diff` merged vs delta | **empty** ×2 |
| `brewfile-management` — preserved header, BF1–BF4, BF6, BF8–BF9, provenance | `sed -n` from the pre-merge copy | `diff` merged vs pre-merge | **empty** ×3 |
| `installed-inventory` — II2 promoted | `sed -n` slice | `diff` merged vs delta | **empty** |
| `installed-inventory` — preserved header, II1, II3–II14, provenance | `sed -n` from the pre-merge copy | `diff` merged vs pre-merge | **empty** ×2 |
| **All 11 promoted blocks re-checked after the move and after every hand-edit** | — | `diff` merged main vs **archived** delta | **empty** ×11 |
| Change folder → archive | **`git mv`** | `diff -r` vs a pre-move recursive `cp -R` snapshot | **empty**, exit status **0** |
| Rename fidelity | — | `git diff --cached -M --name-status` | **10 files: 9 × `R100`, 1 × `R099`** |

The single `R099` is `specs/tap-management/spec.md`, and it is exactly the one-line archive-time
correction recorded below. Every other artifact moved byte-identical.

**Counts re-derived from the merged files, not copied from the delta headers:**

```
                       ### Requirement:   #### Scenario:   - Verification:
tap-management                13               55            41 (39 unit · 2 manual-evidence)
package-mutation              10               60            30 (28 unit · 2 manual-evidence)
brewfile-management            9               40            11 (11 unit)
installed-inventory           14               67             8 ( 8 unit)
```

All four match their delta headers exactly. The `- Verification:` totals (41+30+11+8 = **90**) match the
delta scenario counts, and cover only the promoted blocks — the untouched requirements carry none, by
design.

### One archive-time correction, recorded because it was not mechanical

**Finding A1 — a stale pre-D4 command order survived inside a block archive would have promoted.**

`tap-management` TM9's scenario *"An untap action's inventory refresh comes from its revocation"* opened:

```
- GIVEN an untap action submitting `untrust acme/tools` then `untap acme/tools`
```

That is the **pre-D4** order. It contradicts TM7 two requirements above it in the same file, and it
contradicts its own covering test: `MutationRefreshReceiptTests ·
anUntapActionsInventoryRefreshComesFromItsRevocation` asserts
`["untap","acme/tools"]` then `["untrust","acme/tools"]`. Neither verify run caught it — the
re-verification's scenario map covered the scenarios D4 *changed or added*, and this one was neither.

It is the same class of defect as **W6**, and it was treated the same way the verify report prescribed
for W6: **corrected before promotion, in the delta**, so the archived delta and the main spec stay
byte-identical and the audit trail stays coherent. The GIVEN clause now reads
`` `untap acme/tools` then `untrust acme/tools` ``. **No count changed, no rule moved, and no other
statement in any of the four deltas carries the pre-D4 order** — a targeted sweep for `untrust` near
ordering words returned this one line and no other.

### Final state

- Main specs **updated** (staged diff **+833 / −79** across four files):
  `openspec/specs/tap-management/spec.md` 356 → **739** lines;
  `openspec/specs/package-mutation/spec.md` 753 → **963**;
  `openspec/specs/brewfile-management/spec.md` 536 → **625**;
  `openspec/specs/installed-inventory/spec.md` 881 → **953**.
- Change folder archived: `openspec/changes/archive/2026-08-23-m7-tap-trust/` — **10 artifacts** plus
  this additive report.
- `openspec/changes/m7-tap-trust/` no longer exists.
- `tasks.md` was archived **unmodified by this phase**; no checkbox was reconciled at archive time,
  because all 79 were already closed on `main` (§4).
- No archived change was deleted or modified. The archive is an audit trail.
- `rules.archive` satisfied: the destructive-delta warning did not fire (0 removed, 0 renamed, §5), and
  the closed PRD milestone is recorded (**M3 §3.7**, delivered during **M6 "Ship"** — §1).
