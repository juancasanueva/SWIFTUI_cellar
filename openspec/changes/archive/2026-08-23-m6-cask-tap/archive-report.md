# Archive Report: `m6-cask-tap`

**Archived**: 2026-08-23 · **Milestone**: PRD **M6** "Ship", **slice 4 of 4** — the Homebrew tap and cask
**Status at close**: implemented, verified, **merged to `main` in two PRs**, archived — PR **#64** at `4f005e1`, follow-up PR **#65** at `608881b`
**Verify verdict**: PASS WITH WARNINGS · 0 blockers · 0 CRITICAL · validator-admitted
**Artifact store**: hybrid (OpenSpec + Engram, project `swiftui_cellar`)
**Review gate**: structurally **absent** — RDD disabled, no review started, delivery under ordinary repository policy

This report is the terminal record of the cycle. It describes the state of the change **at close**,
not the state at any earlier point. `apply-progress.md` and `verify-report.md` are intermediate
snapshots archived alongside it; where either disagrees with the final state, the final state is
recorded here and the snapshot's claim is attributed to its own moment rather than restated as a
current fact. Two facts in particular moved after those snapshots were written: **S3 is now observed
and passing**, and **every task is now checked** — including S1, which is checked *as waived*, not as
observed.

---

## 1. Milestone linkage

- Closes the **FOURTH AND FINAL slice of PRD milestone M6 "Ship"** (PRD.md :217). It delivers
  PRD :194's cask channel and settles PRD :9's Distribution line, which had read
  "Homebrew cask still pending". A stale-token sweep at close returns **zero** hits for `juan/tap`,
  `brew install --cask cellar` and "still pending" outside the archive.
- **M6 is now closed.** Slice 1 was the tip jar (built, then removed —
  `openspec/changes/archive/2026-08-22-m6-tip-jar/`); slice 2 the release pipeline
  (`.../2026-08-23-m6-release-pipeline/`); slice 3 Sparkle updates
  (`.../2026-08-23-m6-sparkle-updates/`); this is slice 4. The landing page (PRD :190) remains open
  and is **not** an M6 shipping slice.
- **This slice adds no Swift product code and no in-app behaviour.** Its whole engineering content in
  this repository is a test that stops the uninstall story from quietly becoming a lie, plus the
  documentation that test binds. The cask itself lives in a second repository.
- **It is the first change in this project whose scenarios execute in another repository.** Three
  `ci-gate` scenarios run in `juancasanueva/homebrew-cellar`, which is why the merged main spec's
  class table now names the runner per class rather than implying one.

## 2. Delivery references

| Item | Value |
|---|---|
| Base | `main` at `bcb9d6b` |
| PR #1 | **#64** — https://github.com/juancasanueva/SWIFTUI_cellar/pull/64 |
| PR #1 title | `feat(release): Homebrew tap and cask for home-cellar` |
| PR #1 merged | **2026-08-23T13:56:49Z**, merge commit `4f005e1` on `main` |
| PR #1 size | **14 files, +3,661 / −10** |
| PR #2 | **#65** — https://github.com/juancasanueva/SWIFTUI_cellar/pull/65 |
| PR #2 title | `docs(cask): adopt an existing cellar.app with brew install --adopt` |
| PR #2 merged | **2026-08-23**, merge commit `608881b` on `main` |
| PR #2 size | **5 files, +93 / −2** |
| Second repository | `juancasanueva/homebrew-cellar` (public, created 2026-08-23T13:15:16Z), `main` at **`f9e7428`** |
| Delivery strategy | `single-pr` — **no `size:exception`**; both PRs are far under the governing 5,000-line budget |
| Archive branch | `docs/sdd-archive-m6-cask-tap`, from `main` at `608881b` |

**Commits on `feat/m6-cask-tap` (PR #64):**

| # | Commit | Subject |
|---|---|---|
| 1 | `1d6154f` | `docs(sdd): record the m6-cask-tap proposal, spec delta, design and tasks` |
| 2 | `3cec704` | `test(cask): bind the zap inventory and the install commands to the source` (**RED**) |
| 3 | `100532a` | `docs(cask): document the Homebrew tap and decline the release-workflow extension point` (**GREEN**) |
| 4 | `4ab6dd7` | `docs(sdd): record m6-cask-tap apply progress` |
| 5 | `d0a2cc3` | `docs(sdd): record the m6-cask-tap verify report and align the design install row with D-2` (**closes W1**) |
| 6 | `ccb2a95` | `docs(sdd): mark the m6-cask-tap PR task complete (#64)` |

**Commits on `docs/cask-adopt-existing-install` (PR #65):**

| # | Commit | Subject |
|---|---|---|
| 1 | `d4d41d9` | `test(cask): require the README to carry the brew adopt command for existing installs` (**RED**) |
| 2 | `cd7367b` | `docs(cask): tell direct-download users to adopt the existing app with brew install --adopt` (**GREEN**) |
| 3 | `656c5e4` | `docs(sdd): record the S3 manual evidence for m6-cask-tap` |

**Commit on `main` before archive:** `f31bc71`
`docs(sdd): waive the S1 manual-evidence task for m6-cask-tap by maintainer decision`.

**Commits in `juancasanueva/homebrew-cellar`:**

| Commit | Subject |
|---|---|
| `1441d27` | `feat(cask): add the home-cellar cask, its gates and its bump workflow` |
| `f9e7428` | `docs(readme): tell direct-download users to adopt the existing app with brew install --adopt` |

## 3. Review gate

`reviewGate` is **structurally absent** from this change's status, and that is the expected shape, not
a defect to investigate:

- Receipt-driven development is **disabled** for this repository (session preflight `RDD disabled`).
  With the kill switch off, zero review code ran for this candidate, so no transaction, ledger,
  receipt or gate context was ever created and none exists to read.
- There is therefore **no `disabled/unmanaged` value to check** and **no approval to fabricate**.
  Delivery of PR #64 and PR #65 proceeded under **ordinary repository policy**, and archive proceeds
  the same way — identical to every prior slice.
- Consequently the `sdd/m6-cask-tap/review/*` Engram topics do not exist and were not read.

## 4. Task completion gate

**Gate PASSES.** The archived `tasks.md` carries **40 checked** items and **0 unchecked** items
(`rg -c '^\s*- \[x\]'` → 40, `rg -c '^\s*- \[ \]'` → 0). **No archive-time stale-checkbox
reconciliation was performed**; every box was closed by a commit on `main` before this phase started,
and `tasks.md` was archived unmodified by this phase.

| Task group | Items | Closed by |
|---|---|---|
| P1–P3 prerequisites, 0.1–0.2, 1.1–1.2, 2.1–2.6, 3.1–3.7, 4.1–4.7, 5.1–5.4, 6.1–6.3, 6.6 | 33 | `sdd-apply` during the cycle (35/40 at the apply snapshot) |
| `5.5` open the PR | 1 | `ccb2a95` — PR #64 exists and is merged |
| `2.8` / `6.5` **S3 manual evidence** | 2 | `656c5e4` — observed on the maintainer's Mac (§7) |
| `2.7` / `6.4` **S1 manual evidence** | 2 | `f31bc71` — **WAIVED** by maintainer decision, annotated inline in `tasks.md` (§7) |

**Superseded snapshot claims, recorded rather than echoed.** `verify-report.md` states "Tasks
complete 35 / incomplete 5" and names `2.7, 2.8, 5.5, 6.4, 6.5`; `apply-progress.md` states 35/40 and
marks 2.7/2.8/6.4/6.5 "⛔ open". Both were accurate **when written**. All five closed afterwards, in
the commits named above. Neither snapshot was edited; the archive records the final state and
attributes the older claim to its own moment.

**One discrepancy is recorded, not resolved silently.** Task `5.5` requires the PR to carry "exactly
one `type:feature` label". PR #64 carries **no labels**, and `gh label list` shows the repository has
never defined a `type:*` label set — only GitHub's nine defaults. The task is checked because the PR
was opened and merged; the label clause was **unsatisfiable as written** and was not satisfied. Stated
here so a later reader does not infer a labelling convention this repository does not have.

## 5. Spec sync

| Domain | Action | Details |
|---|---|---|
| `release-distribution` | **Updated** | ADDED-only — **2 requirements / 9 scenarios added**, 0 modified, 0 removed, 0 renamed. **8 req / 32 sc → 10 req / 41 sc**. |

- **No destructive delta.** `rules.archive`'s "warn before merging destructive deltas" clause **did
  not fire**: nothing was modified, removed or renamed, and every one of the eight pre-existing
  requirements is byte-identical to its prior text (proved by diffing the merged file's preserved
  regions against a pre-merge copy — §14).
- **The two appended requirements**: *The delivered build is installable through the project's
  Homebrew tap* (+5 scenarios: 3 `ci-gate`, 2 `manual-evidence`) and *Uninstalling states exactly
  what it removes, and what it cannot* (+4 scenarios, all `unit`).
- **The `## Verification classes` table was hand-updated — both edits, not just the counts.** The
  table lives outside every requirement block, so an ADDED delta structurally cannot carry it.
  1. **Counts**: `unit` 14 → **18**, `ci-gate` 14 → **17**, `manual-evidence` 4 → **6** (32 → **41**).
  2. **Meaning**: `ci-gate` read *"a hard gate inside **the release run**"*. Three of this delta's
     `ci-gate` scenarios run in `juancasanueva/homebrew-cellar` on `macos-26`, **not** in this
     repository's release run, so the meaning was widened to *"a hard gate whose failure fails its
     job and commits or publishes nothing"*, with the runner named per class. Updating the counts
     alone would have left the table stating something false. `manual-evidence` was widened the same
     way ("no runner may install into a real `/Applications` or observe a self-updated app").
- **The arithmetic was verified, not trusted.** `- Verification:` lines were counted in the merged
  file: **18 `unit` / 17 `ci-gate` / 6 `manual-evidence` = 41**, alongside `rg -c '^### Requirement:'`
  → 10 and `rg -c '^#### Scenario:'` → 41. The delta's *Notes for archive* and the verify report's
  *Archive readiness* table were both arithmetically correct.
- **`## Provenance` was extended** with: the amendment record (8/32 → 10/41); the "a tap is a second
  channel, never a second artifact" rationale for adding no capability; the class-table hand-update
  with its two edits; **D1–D5** each naming what was rejected; **DD-13** and the three accepted apply
  deviations **D-1/D-2/D-3** recorded as process decisions deliberately not carried by a requirement;
  the **inherited-contract paragraph marked CONSUMED**; the execution status at the amendment
  (4 `unit` runtime-proven, 3 `ci-gate` run-proven, 1 `manual-evidence` observed, 1 **waived**); and
  the deferred follow-ups.
- The archived delta spec under
  `openspec/changes/archive/2026-08-23-m6-cask-tap/specs/release-distribution/spec.md` remains the
  verbatim audit trail.

## 6. What shipped

**Against `bcb9d6b`, both PRs together: 14 files, +3,752 / −10.** Of that, **7 files / 595 lines** are
authored product, test and documentation change; the remaining **3,167 lines** are the seven SDD
artifacts.

### This repository

| Path | Change |
|---|---|
| `cellarTests/CaskZapInventoryTests.swift` | **New**, 355 lines. A self-contained `CaskZapSources` enum with its own `#filePath` anchor (copied, not imported, so rollback is one file deletion) and a `zap-inventory` fence parser splitting each row on the **first** whitespace run. Six pure read-only functions. Carries T1–T4 plus the post-merge adopt test. |
| `cellarTests/ReleasePipelineCompositionTests.swift` | **Modified**, +40. T5 `theWorkflowGainsNoCrossRepositoryReach` added to the **`Release workflow contract`** suite (deviation D-3), reusing `ReleasePipelineSources` — no helper API added. |
| `RELEASING.md` | **Modified**, +131 / −4. New **§8 "The Homebrew tap"** (tokens table, "How the cask stays current", the D1-option-D manual fallback, the fenced ` ```zap-inventory ` block with 5 rows — 2 `source`, 3 `framework` — the `…savedState`-absent note, the `~/Library/Caches/Cellar` display-name caveat, "What a zap cannot remove" naming both Keychain services, the rate-limit note, and the `--adopt` note added by PR #65); `## 8. Troubleshooting` renumbered to `## 9.`; §7's inherited-contract paragraph replaced (DD-12). |
| `README.md` | **Modified**, +35 / −1. `## Install` replaced: the **three**-line brew fence above the direct download (D-2), `/Applications/cellar.app` named, the fully-qualified `juancasanueva/cellar/home-cellar` form (R5), the uninstall + Keychain caveat, and PR #65's "Already have `cellar.app`?" block carrying `brew install --cask --adopt home-cellar`. |
| `.github/workflows/release.yml` | **Modified — exactly −2 lines**, the extension-point comment inside the `Publish GitHub Release` step body (D2). No step, `- name:` boundary, trigger or secret reference moved. |
| `PRD.md` | **Modified**, 3 lines rewritten in place with their reasons: `:9` Distribution, `:194` Cask channel → *implemented (M6)*, `:217` M6 gains slice 4. |
| `LICENSE` | **New**, 21 lines. MIT, `Copyright (c) 2026 Juan Casanueva` (DD-13). The repository had **no** licence file before this change. `sha256 82cfbe456714d1ca7e7a14766590a498c14ec20f4e659839d8e8c0c05620b6a2`, byte-identical to the tap's. |

**Binding 0-line diffs held.** `git diff --stat main -- scripts/ cellar.xcodeproj/project.pbxproj
Packages/CellarCore cellar/ cellar.xcodeproj/xcshareddata` returns **empty**. No product Swift, no
script, no project-file edit, no scheme change. `cellarTests/` is a
`PBXFileSystemSynchronizedRootGroup`, so the new test file needed no pbxproj line.

### `juancasanueva/homebrew-cellar` — outside both reviewed diffs

| Path | Content |
|---|---|
| `Casks/home-cellar.rb` | `version "1.0.0"`; `sha256 "078a0b5a49fa6e75f885796de1764f36efe72e9db8564fb140bf2112fd6793b6"` (the **published** asset's digest); `auto_updates true`; `app "cellar.app"` with **no** `target:`; `livecheck` `strategy :github_latest`; `depends_on arch: :arm64` and `macos: :tahoe`; no `verified:`; no `caveats`; `zap trash:` with exactly the **five measured** paths — `…savedState` absent. |
| `.github/workflows/ci.yml` | On `pull_request` + `push`, `macos-26`. Asserts `test "$(uname -m)" = "arm64"` before any gate, registers the checkout as a real tap with `cp -R` into `$(brew --repository)/Library/Taps/…` (DD-7), then `brew style`, `brew audit --cask`, `brew audit --cask --online --strict`, `brew install --cask` with a `PlistBuddy` version readback, and `brew uninstall --cask --zap`. |
| `.github/workflows/bump.yml` | `schedule: 17 */6 * * *` + `workflow_dispatch`, `contents: write` with the tap's own `GITHUB_TOKEN`. Reads `releases/latest` anonymously, **exits 0 when the cask already declares that version**, refuses any `*-*` prerelease tag, downloads the asset, recomputes `shasum -a 256`, rewrites two lines, re-runs all three gates **before** committing (DD-8). |
| `README.md` | Install (three lines incl. `brew trust`), requirements, updates, uninstall + the Keychain caveat, how the tap stays current, licence. PR-#65 counterpart adds the `--adopt` guidance. |
| `LICENSE` | MIT, byte-identical to this repository's. |

All four `design.md`-quoted blocks were `diff`ed against the delivered tap files at verification and
were **byte-identical** — which is what makes R7's mitigation (a reviewer can read the whole change
without leaving the PR) actually true rather than nominal.

## 7. Verification

**Verdict: PASS WITH WARNINGS.** Envelope `gentle-ai.verify-result/v1`, verdict
`pass_with_warnings`, **0 blockers, 0 CRITICAL**, requirements 2/2, scenarios 9/9,
`test_exit_code 0`, `build_exit_code 0`. Admitted by
`gentle-ai sdd-verify-validate --requirements 2 --scenarios 9` → `valid: true`. Evidence revision
`sha256:b45e6e5c6508fcb77ab18f6f9db15a8f3c18ddc3bfdacafdb536c3c0fa15233e`.

**Compliance by declared verification class — final state at close:**

| # | Scenario | Class | State at close |
|---|---|---|---|
| **S1** | A tap and an install put the released build in `/Applications` | `manual-evidence` | ⚠️ **WAIVED** — see below |
| **S2** | Cask is style-clean, audit-clean, survives an install/zap round trip | `ci-gate` | ✅ **run-proven** — run `32642667011`, `success`, headSha `1441d27`, all 11 steps `success` |
| **S3** | A self-updated app does not fight `brew upgrade` | `manual-evidence` | ✅ **OBSERVED AND PASSING** — see below |
| **S4** | A prerelease never becomes an installable cask version | `ci-gate` | ✅ run-proven — see **W2** for what was *not* instantiated |
| **S5** | Keeping the cask current is idempotent on the declared version | `ci-gate` | ✅ run-proven — both bump runs logged `the cask already declares 1.0.0; nothing to do`, `Commit the bump` `skipped` in both, zero commits |
| **S6** | The documented inventory covers every write root the source declares | `unit` | ✅ runtime-proven, RED independently re-proven at `3cec704` |
| **S7** | The two Keychain items are documented as surviving a full uninstall | `unit` | ✅ runtime-proven, RED re-proven |
| **S8** | The install commands are documented as whole lines | `unit` | ✅ runtime-proven, RED re-proven |
| **S9** | The release run gains no cross-repository reach | `unit` | ✅ runtime-proven, RED re-proven |

**8 of 9 scenarios are proven at close. 0 failing, 0 untested.**

### S3 — observed and passing (2026-08-23, after PR #64 merged)

Captured on the maintainer's Mac (Homebrew 6.0.18, macOS 26) against a copy Sparkle had **already
self-updated in place** from 0.0.4 to 1.0.0 (`CFBundleVersion` 7) before `brew` ever managed it —
the exact situation the scenario describes. After `brew install --cask --adopt home-cellar`, the
Caskroom records `home-cellar 1.0.0` through the symlink `cellar.app -> /Applications/cellar.app`;
`brew upgrade`, `brew upgrade --cask home-cellar` and `brew outdated --cask --greedy` are all no-ops;
and the bundle on disk is untouched (`1.0.0` / `7`, Developer ID `Z3S5JK8E38`). **The `auto_updates
true` mitigation for archive design risk 11 (R3) is now observed, not inferred.** Full transcript in
the archived `verify-report.md` *Addendum*.

The first attempt of that capture is itself the finding that produced PR #65: plain
`brew install --cask home-cellar` against a directly-downloaded copy fails with
*"It seems there is already an App at '/Applications/cellar.app'"*. Homebrew skips the bundle-version
check on `--adopt` for `auto_updates` casks (`cask/artifact/moved.rb`, `unless auto_updates`), so
`--adopt` is the correct migration path for every existing direct-download user. That path is now
documented in `README.md`, in `RELEASING.md` §8, in the tap README, and bound by a test.

### S1 — WAIVED, with the substitute evidence named

**S1 was not observed. It is checked in `tasks.md` as waived, not as passed**, and this report records
it as a waiver so no future reader mistakes the checkbox for a transcript.

- **Decision**: maintainer, 2026-08-23 — *"archive with S1 pending"*. No Mac that had never seen
  Cellar was available; the only candidate machine carried an existing install.
- **Substitute evidence accepted**: the tap CI's real `brew install --cask` →
  `brew uninstall --cask --zap` round trip on a **clean `macos-26` runner** — runs `32642667011`
  (headSha `1441d27`) and `32644277515` (headSha `f9e7428`), both `success`. That runner's
  `/Applications` is genuinely empty of Cellar, and the install step reads back
  `CFBundleShortVersionString` → `1.0.0`, so the version claim is proven even though the *first-launch
  Gatekeeper* half of S1's THEN clause is not.
- **What remains unobserved**: the "app launches without a Gatekeeper refusal" clause on a
  never-seen-Cellar Mac. Gatekeeper acceptance of the same notarized bundle is independently proven by
  the `release-distribution` scenarios already discharged in `m6-release-pipeline`, but not through a
  cask install.

### Warning disposition at close

| # | Warning (per `verify-report`, Engram `#7713`, written at `4ab6dd7`) | State at close |
|---|---|---|
| **W1** | `design.md`'s `RELEASING.md` §8 block still quoted the pre-D-2 two-line install | ✅ **FIXED in `d0a2cc3`**, before archive froze the design. `design.md:564` now reads the three-line form with the D-2 note inline. The verify report's "best done before archive" recommendation was taken. |
| **W2** | S4's adversarial GIVEN — *a prerelease **newer than** the latest stable* — was never instantiated | **OPEN and carried.** The only prerelease, `v0.0.1-rc.1` (05:46:22Z), predates `v1.0.0` (10:28:24Z). Three independent mechanisms hold (`releases/latest` excludes prereleases by contract; `bump.yml:48` carries an explicit `*-*) … exit 1` refusal; the cask declares `livecheck strategy :github_latest`), none exercised against that exact ordering. Discharge at the next `v*-rc.*` tag by dispatching `bump.yml` once. |
| **W3** | Both bump runs were measured at headSha `c0d5ee5`, a superseded revision | **RECORDED, as the verify report asked.** `c0d5ee5`'s `bump.yml`, `ci.yml`, `Casks/home-cellar.rb` and `LICENSE` were fetched through the contents API and are **byte-identical** to the delivered `1441d27`; only the tap `README.md` differs, by exactly D-2's `brew trust` line, and `bump.yml` never reads the README. `gh api …/compare/c0d5ee5...1441d27` returns *"No common ancestor"* because apply amended and force-pushed a **root** commit three times, so the superseded revisions share no history and may not stay reachable. The byte-identity finding is preserved here so the provenance never needs re-deriving from runs that could disappear. |
| **W4** | Five tasks unchecked (`2.7`, `2.8`, `5.5`, `6.4`, `6.5`) | ✅ **CLOSED.** All five closed in `ccb2a95`, `656c5e4` and `f31bc71` (§4). `2.7`/`6.4` closed **as waived**, which is why S1 is reported above as waived rather than passed. |

**Four SUGGESTIONS, none required, all carried rather than back-edited into frozen artifacts.**
**G1** (pin the baseline counting convention — `tasks.md` 0.1 says *distinct* ids and expects 232, but
distinct ids give 221/226 while the total-`' passed on '`-line convention gives 232/237; both agree on
the +5 delta) is recorded in §8. **G2** (`design.md` and `tasks.md` name a `Release pipeline
composition` suite that does not exist) is recorded as deviation D-3 in §10. **G3** (Swift Testing's
`-only-testing:` selector silently runs **zero** cases without the trailing `()`, and the suite still
"starts") is carried into §12. **G4** (`savedState` deserves a periodic re-measure) is carried into
§11 as an open follow-up.

**RED-first was re-proven by execution, not accepted from the report.** The verifier created a
detached worktree at the RED commit `3cec704` (deliberately outside `/tmp`, per the CodeGraph
worktree-placement rule), re-ran the suites there, and observed all five tests fail — T1–T4 with
`RED_EXIT=65`, T5 with `RED_T5_EXIT=65` — then pass at `4ab6dd7`. The worktree was removed and pruned.

**Assertion quality audited across both test files**: zero tautologies, zero assertions that never
call production code, **zero ghost loops** — every iteration is anchored by a prior non-vacuity
assertion (`!discovered.isEmpty`, `passThrough.count >= 5`, `!apiCalls.isEmpty`), and T3/T4 iterate
literal arrays. The load-bearing one is T2's
`#expect(try CaskZapSources.discoveredWriteRoots() == expected)` — a **set equality against two
specific paths**, not a count floor. That is what makes DD-10 structurally load-bearing: a scan that
started sweeping `HomebrewRoots`' `~/Library/Caches/Homebrew` into the zap list fails there rather
than silently widening what an uninstall deletes.

## 8. Test, gate and size state at close

| Measure | Value at close | Superseded value (and its source) |
|---|---|---|
| `cellarTests` | **238 passed / 0 failed** | `apply-progress.md` and `verify-report.md` both record **237** — correct at `4ab6dd7`, before PR #65 added `theReadmeCarriesTheAdoptCommandAsAWholeLine`. Baseline at `bcb9d6b` was **232**; Δ **+6** (T1–T5 plus the adopt test). |
| Counting convention | total `' passed on '` lines (the house convention quoted throughout the artifacts) | The *distinct `Test case '…' passed` ids* convention gives 221 → 226 at `4ab6dd7`. Both agree on the delta; `tasks.md` 0.1 names the wrong one (SUGGESTION **G1**). |
| CellarCore | **1,753 tests in 209 suites passed**, 1 known issue (pre-existing) | Unchanged from baseline — the 0-line-diff proof. `209` is a **suite** count; `tasks.md` 5.2's "209 skipped" is a misreading of the runner's own line. |
| `xcodebuild test … -only-testing:cellarTests` | `** TEST SUCCEEDED **`, exit 0 | |
| `swift test --package-path Packages/CellarCore` | exit 0 | |
| Coverage | ➖ not run — **no product code changed**, so changed-file coverage has no surface | |
| Linter | ➖ not applicable here; `brew style` (the linter for the delivered artifact) ran green in tap CI: `2 files inspected, no offenses detected` | |
| Tap CI | `32642667011` (`1441d27`) `success`; `32644277515` (`f9e7428`) `success` | |
| Tap bump | `32642223493` and `32642400685` `success`, **zero commits**; `32642235551` `failure` (anonymous rate limit — inert by design, §12) | |

**Size against the governing budget:**

| Measure | Value |
|---|---|
| Authored product, test and docs change (both PRs) | **595 changed lines** across 7 files |
| SDD artifacts | **3,167 lines** across 7 files |
| PR #64 total | **3,671 changed lines** (3,661+ / 10−), 14 files |
| PR #65 total | **95 changed lines** (93+ / 2−), 5 files |
| Governing budget | **5,000** — PR #64 sits at **≈73 %**; `single-pr` holds with **no `size:exception`** |
| Forecast vs actual | `tasks.md` forecast ≈1,080–1,890; apply measured 2,767 at `4ab6dd7`; **the merged figure is 3,671**. Reported at each step rather than rounded back to the first estimate. |

The overshoot is entirely SDD artifacts plus the test file: `explore.md` (454 lines) was never in the
bottom-up table, `design.md` reached 1,069 lines because R7 required all four tap files quoted
verbatim, and `CaskZapInventoryTests.swift` carries the five-step scan algorithm the design specified
in prose.

**Attempt ledger:**

| Attempt | State |
|---|---|
| apply | complete — 35/40 at its own snapshot; the remaining five closed afterwards (§4) |
| verify | complete — `pass_with_warnings`, validator-admitted |
| archive | this phase |

## 9. Still open at close — the exact remaining checklist

**None of these blocked merge or archive.** They are the difference between "shipped" and "proven end
to end".

| # | Item | Discharged by |
|---|---|---|
| 1 | **S1's first-launch clause on a never-seen-Cellar Mac** | A borrowed or fresh Mac: `brew tap juancasanueva/cellar` → `brew trust juancasanueva/cellar` → `brew install --cask home-cellar`, then a first launch with no Gatekeeper refusal. The waiver stands until then; the tap CI round trip is the accepted substitute (§7). |
| 2 | **W2 — S4's newer-prerelease ordering** | At the next `v*-rc.*` tag, dispatch `bump.yml` once and record that `releases/latest` still resolves to the stable tag. One dispatch, one log line. |
| 3 | **The scheduled bump has never fired on its own cron** | Every bump run so far was a `workflow_dispatch`. `17 */6 * * *` will fire on its own; the first scheduled run is worth a glance. |
| 4 | **A real version bump has never been executed** | Every bump run so far took the idempotent early-exit branch (`the cask already declares 1.0.0`). The rewrite, re-gate and commit path is structurally verified but has **never run against a genuinely newer release**. It executes for the first time at the next stable tag — and that is the single highest residual risk in this slice. |

## 10. Accepted deviations from the design

Three were declared at apply time; verification re-read each against the delivered bytes and judged
them **design-refining and spec-preserving**.

1. **D-1 — `depends_on macos: :tahoe` replaces `">= :tahoe"`.** Homebrew 6's
   `Homebrew/OSDependsOn` cop makes the string form a **[Correctable] style offense**, measured
   identically on `macos-26` and on the maintainer's Mac, so the `brew style` gate the design itself
   mandates could not pass without the change. `rubocops/os_depends_on.rb#autocorrect_macos_comparison_strings`
   maps `>=` to `macos:` and `<=` to `maximum_macos:`, so the symbol form **is** the minimum-version
   claim in current syntax — the macOS 26.0 floor is byte-for-byte the same requirement. `design.md`
   was re-synced at `:141` and `:165`.
2. **D-2 — the canonical documented install is THREE whole lines, not two.** Homebrew 6 refuses to
   load a cask from an untrusted tap by its short name:
   `Error: Refusing to load cask juancasanueva/cellar/home-cellar from untrusted tap`.
   `trust.rb#explicitly_allowed?` grants the load only when the tap name or the fully-qualified cask
   appears in `ARGV` — which is why every command in `ci.yml`, `bump.yml` and the manual fallback
   already worked and the **short** form, the one the READMEs make canonical, did not.
   `brew trust juancasanueva/cellar` was added as a third line in `README.md`, `RELEASING.md` §8 and
   the tap README, each with one sentence saying why. Accepted by the maintainer (Engram `#7712`).
   S8 is unaffected: it requires whole copy-runnable lines, and all three are.
3. **D-3 — T5 lives in the `Release workflow contract` suite.** `design.md` and `tasks.md` name a
   `Release pipeline composition` suite; the file declares `Release metadata`, `Release pipeline
   placement` and `Release workflow contract`, and no suite by that name. T5 sits beside
   `theWorkflowCanOnlyEverCreateARelease`, which is where the design's own threat-matrix
   cross-reference points. **A naming slip in the artifacts, not a design change** (SUGGESTION G2).

**Design decisions honoured without deviation**: D1–D5 (proposal), DD-1…DD-13 (design). Verification
checked each against the delivered bytes: the pull-based bump with no dispatch anywhere in
`release.yml`; the deleted extension point, test-driven; `app "cellar.app"` with no `target:`; no
`verified:` with `brew audit --online --strict` at exit 0; the tap's own README; `cp -R` tap
registration; gates before the commit; the 2-root scan with every pass-through a `HomebrewRoots`
hand-off; the `zap-inventory` fence split on the first whitespace run; the corrected §7 paragraph;
MIT `LICENSE` byte-identical in both repositories; and the `arm64` assertion before any gate.

**Probes, all measured, none assumed**: the v1.0.0 asset digest computed from the **published** file
and re-verified through `gh api …/releases/tags/v1.0.0` (`sha256:078a0b5a…6793b6`, 6,448,745 bytes);
the zip layout (`cellar.app` at the archive root, no wrapper); token availability
(`brew search --cask cellar` → only `clarc`); and the on-disk zap inventory, where
`…/Saved Application State/com.juancasanueva.cellar.savedState` was **absent** and therefore
**dropped from the cask rather than guessed in**.

## 11. Carried follow-ups (recorded open, deliberately not closed here)

**Owned by this slice's decisions:**

- **The `Home-Cellar.app` rename** — its own slice. It touches `PRODUCT_NAME`, four `release.sh`
  gates, the `release-distribution` bundle-name scenario, and **update continuity for every installed
  1.0.0 copy**. D3 declined `target:` precisely because a rename splits the two install channels and
  perturbs Sparkle's in-place self-replacement, which nobody has measured.
- **Move `~/Library/Caches/Cellar` under the bundle id** — a migration (R4). The current directory is
  a *display-name* directory, a broader zap claim than it looks, which is why the caveat is written
  down in `RELEASING.md` §8 rather than silently widened.
- **The landing page → `homepage` interaction.** D4 chose the GitHub repository as `homepage`
  specifically so `verified:` stays absent. If the landing page ever becomes the `homepage`, the url
  and homepage domains stop matching and **`verified:` becomes mandatory on the cask url** — that is
  an audit change, not a cosmetic one.
- **Discharge W2 at the next `v*-rc.*` tag** — one `bump.yml` dispatch, one recorded resolution (§9).
- **Re-measure `savedState` periodically** (SUGGESTION G4). It is correctly absent today, never
  guessed in, but no test can catch a framework-written root that macOS starts writing later. The
  P7/P8 probe method makes the re-measure cheap.
- **Submission to `homebrew/cask`** — deferred until notability requirements (stars/press) are met.
  The self-hosted tap is the channel until then.

**Open, recorded, not owned by this slice:**

- **Never rewrite a tap's history once any machine has tapped it** — a lesson, and a live constraint
  on the tap repository from now on (§12).
- A DMG, a PR/test CI workflow, SwiftLint adoption, and PRD §9 Q1 (final name and icon) remain open
  from earlier slices. `cellarUITests/ReleaseNotesUITests` is still unowned since `m5-health`.

## 12. Learnings worth carrying

**A. A documentation test earns its keep the day someone else adds a file.** The whole engineering
content of this slice in this repository is a test that scans the shipped sources for every
application-support and cache write root and demands each one appear in the documented uninstall
inventory. Every M-slice so far added a cache file under `~/Library/Caches/Cellar`, and nothing would
have noticed a sixth appearing while the cask still listed five. The test goes red **in the repository
where the write is introduced**, not on a user's disk after an uninstall that quietly left files
behind.

**B. Classify before you sweep, or the sweep deletes someone else's data.** Five of the ten
`.cachesDirectory` uses in the sources hand the bare directory to `HomebrewRoots`, whose cache root is
`~/Library/Caches/**Homebrew**`. A naive "every caches use is a Cellar write root" scan would have
demanded Homebrew's own bottle cache enter a `zap trash:` list — deleting every user's downloads on
uninstall. DD-10's appending-vs-pass-through classification, asserted per occurrence, makes that
structurally impossible rather than merely unlikely.

**C. Never rewrite a tap's history once any machine has tapped it.** Apply amended and force-pushed
the tap's **root** commit three times (`a33f194` → `c0d5ee5` → `1441d27`). Two consequences followed:
the maintainer's brew-managed clone at
`/opt/homebrew/Library/Taps/juancasanueva/homebrew-cellar` ended up with **conflict markers inside the
cask** (`Cask 'home-cellar' is unreadable … syntax errors found`), fixed only by
`git reset --hard origin/main`; and the recorded S4/S5 evidence points at a headSha that shares **no
common ancestor** with the delivered tree, so the provenance had to be re-established by byte-diffing
the superseded files through the contents API (W3). A fix commit would have cost one extra line of
history and neither problem.

**D. The channel a change ships is not the same as the channel its users are already on.** The cask
was correct and its CI was green, and the first real-world install still failed —
*"It seems there is already an App at '/Applications/cellar.app'"* — because every existing user has a
direct-download copy. Homebrew's `--adopt` is the migration path, and it works here specifically
because the cask declares `auto_updates true` (`cask/artifact/moved.rb` skips the bundle-version check
`unless auto_updates`). **Shipping a new install channel means documenting the migration from the old
one**, and PR #65 exists because that was found by running the install, not by reading the cask.

**E. Two verification-tooling gotchas worth a house note.** Swift Testing's
`-only-testing:cellarTests/<Suite>/<func>` silently runs **zero cases** without the trailing `()` —
the suite still "starts", so a careless reading scores a RED test as passing. And the `cellarTests`
baseline has two defensible counting conventions that disagree by 11 (total `' passed on '` lines vs
distinct `Test case '…' passed` ids); they agree on the delta, which is the only figure a guard should
ever assert on.

## 13. Artifact traceability (Engram observation IDs)

Every artifact was retrieved in full via `mem_get_observation` or read from its canonical file, not
from a search preview. **In hybrid mode the OpenSpec file is canonical**; the Engram observation is a
mirror.

| Artifact | Engram obs | Topic | Archived file |
|---|---|---|---|
| explore | **`#7700`** | `sdd/m6-cask-tap/explore` | `explore.md` |
| orchestrator probes (sha256, zip layout, token collision, tap repo) | **`#7699`** | — | — (Engram only) |
| zap-path probes P7/P8 (measured on-disk inventory) | **`#7701`** | — | — (Engram only) |
| decisions D1–D5 (maintainer-accepted) | **`#7702`** | — | — (Engram only) |
| proposal | **`#7703`** | `sdd/m6-cask-tap/proposal` | `proposal.md` |
| spec (delta, pre-revision mirror) | **`#7704`** | `sdd/m6-cask-tap/spec` | `specs/release-distribution/spec.md` |
| spec revision (zap-inventory scenario aligned with DD-9) | **`#7706`** | — | — (Engram only; the file carries the revision) |
| design | **`#7705`** | `sdd/m6-cask-tap/design` | `design.md` |
| licence decision (MIT both repos, DD-13) | **`#7707`** | — | — (Engram only) |
| tasks | **`#7708`** | `sdd/m6-cask-tap/tasks` | `tasks.md` |
| apply authorization (full scope incl. public tap repo creation) | **`#7709`** | — | — (Engram only) |
| apply-progress | **`#7710`** | `sdd/m6-cask-tap/apply-progress` | `apply-progress.md` |
| D-2 accepted (three-line canonical install) | **`#7712`** | — | — (Engram only) |
| verify-report | **`#7713`** | `sdd/m6-cask-tap/verify-report` | `verify-report.md` |
| tap-clone conflict gotcha | *(topic `cellar/tap-clone-conflict-gotcha`)* | — | — (Engram only) |
| **archive-report** | *this file* | `sdd/m6-cask-tap/archive-report` | `archive-report.md` |

**Known-lossy mirrors — the archived file is authoritative:**

- **`#7704` (spec)** is the **pre-revision** mirror. The zap-inventory scenario's last AND clause was
  corrected afterwards (obs `#7706`); the archived delta file carries the corrected text.
- **`#7708` (tasks)** is the authoring-time snapshot, so its checkboxes read unchecked. The archived
  `tasks.md` carries the final 40/40 state, including the S1 waiver annotation, and is the authority
  for §4.
- **`#7710` (apply-progress)** and **`#7713` (verify-report)** are intermediate snapshots. Their
  "35/40", "237 tests" and "S1/S3 pending" claims were true when written and are superseded here.
- **`#7705` (design)** is condensed against Engram's truncation limit; `design.md` is 1,069 lines and
  is the authority — including the W1 fix at `:564`, which landed after the mirror was written.

`review/*` topics do not exist — see §3.

## 14. Archive integrity

**Mechanical copy contract satisfied.** No artifact byte passed through a model read/write path. Every
requirement body was extracted with `sed` and every move used `git mv`; the archive report is the only
authored file, and it is additive.

| Operation | Mechanism | Readback | Result |
|---|---|---|---|
| `release-distribution` — requirement + scenario bodies appended | `sed -n '39,157p'` from the delta | `diff` merged `408,526` vs delta `39,157` | **empty**, exit 0 |
| Same, **re-run after** the class-table and provenance hand-edits | — | `diff` merged `408,526` vs delta `39,157` | **empty**, exit 0 |
| `release-distribution` — preserved header (before the class table) | `head`/`sed` from the pre-merge copy | `diff` merged `1,13` vs pre-merge `1,13` | **empty**, exit 0 |
| `release-distribution` — preserved requirements 1–8 | same | `diff` merged `19,406` vs pre-merge `19,406` | **empty**, exit 0 |
| `release-distribution` — preserved provenance (pre-existing text) | same | `diff` merged `528,647` vs pre-merge `408,527` | **empty**, exit 0 |
| Change folder → archive | `git mv` | `diff -r` vs a pre-move recursive `cp -R` snapshot | **empty**, exit status **0** |
| Rename fidelity | — | `git diff --cached -M --name-status` | **7 files, all `R100`** |

Counts were **re-derived from the merged file**, not copied from the delta's note:

```
rg -c '^### Requirement: '  → 10
rg -c '^#### Scenario: '    → 41
rg -c '^- Verification: '   → 41
  18 unit · 17 ci-gate · 6 manual-evidence
```

- Main spec **updated**: `openspec/specs/release-distribution/spec.md`, 529 → **723 lines**;
  staged diff **+197 / −3**. The three deletions are exactly the three class-table rows rewritten in
  place; the insertions are 119 lines of requirement and scenario bodies (byte-identical to the
  delta), their two surrounding blank lines, the three replacement class-table rows, and 73 lines of
  provenance.
- Change folder archived: `openspec/changes/archive/2026-08-23-m6-cask-tap/` — **7 artifacts** plus
  this additive report.
- `openspec/changes/m6-cask-tap/` no longer exists.
- `tasks.md` was archived **unmodified by this phase**; no checkbox was reconciled at archive time,
  because all 40 were already closed on `main` (§4).
- No archived change was deleted or modified. The archive is an audit trail.
- `rules.archive` satisfied: the destructive-delta warning did not fire (ADDED-only, §5), and the
  closed PRD milestone is recorded (**M6 "Ship"**, slice 4 of 4 — §1).
