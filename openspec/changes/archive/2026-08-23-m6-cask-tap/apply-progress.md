# Apply progress: Homebrew Tap and Cask (`m6-cask-tap`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`
(**no `size:exception`** — 2,767 changed lines against the governing 5,000-line budget),
`chain_strategy=n/a (no chain)`, `review_budget_lines=5000`, `strict_tdd=true`, RDD **disabled**
(no review started, no receipt created).

Mode: **Strict TDD**. Branch `feat/m6-cask-tap`, base `main` at `bcb9d6b`. Scope executed:
**Phases 0–5 complete except the two `manual-evidence` tasks and PR creation — 35/40 tasks**.
Two repositories were touched, and only one of them is in the reviewed diff.

| Repository | State |
|---|---|
| `juancasanueva/SWIFTUI_cellar` (this) | `feat/m6-cask-tap`, four commits, **not pushed** — the orchestrator owns delivery after verify |
| `juancasanueva/homebrew-cellar` (new, public) | `main` at `1441d27d185c2411b2bd4ae42da4d1d24c169c23`, one commit, **pushed**, CI green |

Test runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination
'platform=macOS,arch=arm64' -only-testing:cellarTests`. `cellarUITests` was never run — not part of
this slice. See *Baseline counting note* for which counting convention yields the stated 232.

## Task status

| Task | Status | Evidence |
|---|---|---|
| P1 public-repo confirmation | ✅ | Maintainer authorisation granted 2026-08-23 and forwarded in the launch brief |
| P2 Mac with Homebrew 6.0.18 | ✅ | `brew --version` → `Homebrew 6.0.18-157-gaad366f`. The two transcripts it enables remain open (2.7/2.8) |
| P3 v1.0.0 latest stable, digest unchanged | ✅ | `brew audit --cask --online --strict` re-verified the declared `078a0b5a…93b6` against the downloaded published asset, locally **and** on `macos-26`; `bump.yml` read `releases/latest` → `1.0.0` |
| 0.1 green baseline | ✅ | **232 passed / 0 failed**, `** TEST SUCCEEDED **` |
| 0.2 four design anchors | ✅ | `release.yml:175-176` ✓ · `RELEASING.md:309-311` ✓ · `RELEASING.md:320` `## 8. Troubleshooting` ✓ · `README.md:32` `## Install` ✓ — none moved |
| 1.1 GATE P1 | ✅ | Not proceeded until the authorisation was in hand |
| 1.2 `gh repo create` | ✅ | Exit 0; `gh repo view --json visibility` → `PUBLIC`; `https://github.com/juancasanueva/homebrew-cellar` |
| 2.1 one commit, five files | ✅ | `1441d27` `feat(cask): add the home-cellar cask, its gates and its bump workflow` — cask, `ci.yml`, `bump.yml`, `README.md`, `LICENSE` |
| 2.2 cask copied, not re-derived | ✅ | `version "1.0.0"` / `sha256 "078a0b5a…93b6"` verbatim; DD-3/DD-4/DD-5/DD-6 honoured; five `zap trash:` paths, `…savedState` absent. **One line corrected — see Deviation D-1** |
| 2.3 `cp -R` tap registration + arm64 assert | ✅ | `ci.yml` copies into `$(brew --repository)/Library/Taps/juancasanueva/homebrew-cellar`; `test "$(uname -m)" = "arm64"` runs before every gate |
| 2.4 **ci-gate S2** | ✅ | [run 32642667011](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642667011) `success`, 42s. Style, offline audit, online strict audit, install, zap — every step exit 0. **R13 did not fire** |
| 2.5 **ci-gate S4** | ✅ | [run 32642223493](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642223493) `success`, `VERSION: 1.0.0` — the stable tag; the `*-*` prerelease refusal branch never taken |
| 2.6 **ci-gate S5** | ✅ | Runs 32642223493 and [32642400685](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642400685), both `success`, both `the cask already declares 1.0.0; nothing to do`, `bump=no`. `git log origin/main` → **1 commit**, zero produced |
| 2.7 **manual-evidence S1** | ⛔ open | Maintainer's own step. A harness may not install into a real `/Applications`, and this Mac carries an unrelated 0.0.4 build |
| 2.8 **manual-evidence S3** | ⛔ open | Same. Requires a Sparkle self-update to have happened on a cask-installed copy |
| 3.1 RED scaffold | ✅ | `cellarTests/CaskZapInventoryTests.swift`, self-contained `CaskZapSources` with its own `#filePath` anchor; `zap-inventory` rows split on the **first** whitespace run |
| 3.2 RED T1 | ✅ | `everyWriteRootTheSourceDeclaresIsInTheDocumentedInventory()` **failed**: `(documented → []).contains("~/Library/Caches/Cellar")` |
| 3.3 RED T2 | ✅ | `theWriteRootScanIsNonVacuousAndEveryPassThroughIsAHomebrewRootsHandOff()` **failed**: `(rows.count → 0) >= 5` and `(source count → 0) >= 2` |
| 3.4 RED T3 | ✅ | `theRunbookNamesBothKeychainItemsAZapCannotRemove()` **failed** on the runbook text |
| 3.5 RED T4 | ✅ | `theReadmeCarriesBothBrewCommandsAsWholeLines()` **failed** on both whole-line clauses |
| 3.6 RED T5 | ✅ | `theWorkflowGainsNoCrossRepositoryReach()` **failed** at `!(workflow.contains("extension point"))` — the first clause only, exactly as DD-2 requires |
| 3.7 all five RED, commit | ✅ | `EXIT=65`, five named failures, each for its stated reason. `3cec704` `test(cask): bind the zap inventory and the install commands to the source` |
| 4.1 GREEN `RELEASING.md` §8 | ✅ | New §8 before Troubleshooting; `## 8. Troubleshooting` → `## 9.` (one heading line). Tokens table, three deliberate properties, manual fallback, the `zap-inventory` fence with 5 rows (2 `source`, 3 `framework`), the `…savedState` note, the display-name caveat, both Keychain services |
| 4.2 GREEN DD-12 §7 | ✅ | Inherited-contract paragraph replaced with the design's text — the extension point is declined, not occupied |
| 4.3 GREEN T4 `README.md` | ✅ | `## Install` replaced with the design's section. **One line added — see Deviation D-2** |
| 4.4 GREEN T5 `release.yml` | ✅ | `git diff --stat` → `1 file changed, 2 deletions(-)`. No step, `- name:` boundary, trigger or secret moved |
| 4.5 GREEN DD-13 `LICENSE` | ✅ | MIT, `Copyright (c) 2026 Juan Casanueva`. `shasum -a 256` identical in both repositories: `82cfbe456714d1ca7e7a14766590a498c14ec20f4e659839d8e8c0c05620b6a2` |
| 4.6 GREEN `PRD.md` ×3 | ✅ | :9, :194, :217 replaced with the design's exact text. No `juan/tap`, no bare `cellar` token, no "still pending" |
| 4.7 T1–T5 green, commit | ✅ | All five pass. `100532a` `docs(cask): document the Homebrew tap and decline the release-workflow extension point` |
| 5.1 full suite | ✅ | **237 passed / 0 failed**, `** TEST SUCCEEDED **` — 232 + the 5 new cases |
| 5.2 CellarCore 0-diff proof | ✅ | `Test run with 1753 tests in 209 suites passed after 16.640 seconds with 1 known issue.` — unchanged. See *Baseline counting note* |
| 5.3 bindings proof | ✅ | `git diff --stat main -- scripts/ cellar.xcodeproj/project.pbxproj Packages/CellarCore cellar/ cellar.xcodeproj/xcshareddata` → **empty** |
| 5.4 runbook read-through | ✅ | §8 read end to end; the three README install lines extracted and lines 1–2 executed. Line 3 is the maintainer's S1 step and was deliberately not run |
| 5.5 open the PR | ⛔ deferred | The orchestrator owns delivery after verify. The branch is committed and unpushed |
| 6.1 `ci.yml` evidence | ✅ | Captured in `design.md` *§ Evidence to capture* |
| 6.2 bump idempotence evidence | ✅ | Same |
| 6.3 bump stable-tag evidence | ✅ | Same |
| 6.4 S1 transcript | ⛔ open | Blocked by 2.7 |
| 6.5 S3 transcript | ⛔ open | Blocked by 2.8 |
| 6.6 archive obligation recorded | ✅ | Recorded here and in the delta's *Notes for archive*. Performing the hand-update is `sdd-archive`'s action, not this phase's |

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 3.2/4.1 T1 | `cellarTests/CaskZapInventoryTests.swift` | Unit | ✅ 232/232 | ✅ failed — `documented → []` for both roots | ✅ passed after the `zap-inventory` block landed | ✅ 2 roots × 2 domains (caches and application-support), plus a non-empty guard on the scan | ➖ none needed |
| 3.3/4.1 T2 | same | Unit | ✅ 232/232 | ✅ failed — `rows.count → 0` and `source → 0` | ✅ passed | ✅ 5 cases — set equality, appending ≥ 7, pass-through ≥ 5, per-occurrence `HomebrewRoots(`, inventory floors. The scan clauses were green at RED, which is the DD-9/DD-10 measurement confirming itself | ➖ |
| 3.4/4.1 T3 | same | Unit | ✅ 232/232 | ✅ failed | ✅ passed | ✅ 2 cases — one Keychain service each, asserted separately so a half-documented runbook fails | ➖ |
| 3.5/4.3 T4 | same | Unit | ✅ 232/232 | ✅ failed on both whole-line clauses | ✅ passed | ✅ 4 cases — two whole lines, the fully-qualified form, the bundle name | ➖ |
| 3.6/4.4 T5 | `cellarTests/ReleasePipelineCompositionTests.swift` | Unit | ✅ 232/232 | ✅ failed at `!contains("extension point")` **only** | ✅ passed after the 2-line deletion | ✅ 6 cases — the comment, two dispatch tokens, an anchored non-empty API-call list with a per-line owner check, two foreign repository names | ➖ |

No production Swift was written in this change, so there is no implementation to refactor. The
`Comment?` compile error at `CaskZapInventoryTests.swift:280` (a `String` built with `+` where Swift
Testing wants a literal or interpolation) was fixed **inside** the RED step, before any test executed.

### Test summary

- **Total tests written**: 5 (T1–T5)
- **Total tests passing**: 237 in `cellarTests` (232 baseline + 5), 0 failing
- **Layers used**: Unit (5). Integration and E2E have no surface — this change adds no runtime code
- **Approval tests**: none — no refactoring task
- **Pure functions created**: 6 in `CaskZapSources` (`inventoryRows`, `swiftFiles`,
  `searchDomainOccurrences`, `discoveredWriteRoots`, `window`, `writeRoot`), all read-only

## Work Unit Evidence

| WU | Focused test command and exact result | Runtime harness command/scenario and exact result | Rollback boundary |
|---|---|---|---|
| **WU0** | n/a — no `cellarTests` reach | `gh repo view juancasanueva/homebrew-cellar --json visibility` → `PUBLIC`, exit 0 | Delete the repository |
| **WU1** | n/a — no `cellarTests` reach | `ci.yml` [run 32642667011](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642667011) `success`; local `brew style` / `brew audit` / `brew audit --online --strict` all exit 0 on Homebrew 6.0.18-157 | `git revert 1441d27`; or disable `bump.yml` in the Actions UI; or delete the repository |
| **WU2** | `xcodebuild test … -only-testing:cellarTests/CaskZapInventoryTests -only-testing:cellarTests/ReleaseWorkflowContractTests` → `EXIT=65`, five named failures | N/A — read-only source and document scan, no runtime boundary exists | Delete `cellarTests/CaskZapInventoryTests.swift`; revert the 40-line addition to `ReleasePipelineCompositionTests.swift` |
| **WU3** | `xcodebuild test … -only-testing:cellarTests` → **237 passed / 0 failed**, `** TEST SUCCEEDED **` | `RELEASING.md` §8 read end to end; README install lines 1–2 executed from the file (`Trusted tap: juancasanueva/cellar`, then `brew info --cask home-cellar` → `home-cellar (Home-Cellar, Cellar): 1.0.0 (auto_updates)`) | `git revert 100532a` — `release.yml` regains two comment lines, docs and `LICENSE` disappear |

## Deviations from the design (three, all reported, none absorbed silently)

### D-1 — `depends_on macos: ">= :tahoe"` is a style offense on Homebrew 6

**Design**: `Casks/home-cellar.rb` line 17 reads `depends_on macos: ">= :tahoe"`.
**Measured**: identical failure on `macos-26` and on the maintainer's Mac:

```
Taps/juancasanueva/homebrew-cellar/Casks/home-cellar.rb:17:21: C: [Correctable] Homebrew/OSDependsOn: Use depends_on macos: :tahoe.
  depends_on macos: ">= :tahoe"
```

**Applied**: `depends_on macos: :tahoe`.
**Why this is not a weakening**: `rubocops/os_depends_on.rb#autocorrect_macos_comparison_strings` maps
`>=` to `macos:` and `<=` to `maximum_macos:`, so the symbol form **is** the minimum-version claim in
current syntax. The macOS 26.0 floor is byte-for-byte the same requirement. The design's stated
rationale (`:tahoe` → `"26"`, matching `MACOSX_DEPLOYMENT_TARGET`) is untouched. Without this the
`brew style` gate the design itself mandates cannot pass at all.

### D-2 — Homebrew 6 requires tap trust, so the documented short install form fails

**Design**: both READMEs and `RELEASING.md` §8 publish a two-line install —
`brew tap juancasanueva/cellar`, then `brew install --cask home-cellar`.
**Measured**, same machine, both forms:

```
$ brew info --cask home-cellar
Error: Refusing to load cask juancasanueva/cellar/home-cellar from untrusted tap juancasanueva/cellar.
Run `brew trust --cask juancasanueva/cellar/home-cellar` or `brew trust juancasanueva/cellar` to trust it.

$ brew info --cask juancasanueva/cellar/home-cellar
==> home-cellar (Home-Cellar, Cellar): 1.0.0 (auto_updates)
```

`trust.rb#explicitly_allowed?` grants the load when the tap name or the fully-qualified cask appears
in `ARGV`. That is why every command in `ci.yml`, `bump.yml` and the runbook's manual fallback already
works untouched, and why the **short** form — the one the READMEs make canonical — does not.

**Applied**: `brew trust juancasanueva/cellar` added as a third line to the install fence in
`README.md` and to `RELEASING.md` §8's canonical-install row, each with one sentence saying why.
`homebrew-cellar/README.md` carries the same line. Verified after the change:

```
$ brew trust juancasanueva/cellar
Trusted tap: juancasanueva/cellar
$ brew info --cask home-cellar
==> home-cellar (Home-Cellar, Cellar): 1.0.0 (auto_updates)
Not installed
```

**Why the design's text was not shipped verbatim**: this change exists so the documentation stops
quietly becoming a lie. Publishing an install sequence that errors out on the current Homebrew is
exactly that lie, and scenario S8 requires "a complete line a reader can copy and run". T4 is
unaffected — it asserts the two design-specified lines exist as whole lines, and both still do.
**If the maintainer prefers the design's two-line form, the correction is the deletion of one line
in three files.**

### D-3 — the suite T5 joins is `Release workflow contract`, not `Release pipeline composition`

`design.md` and `tasks.md` name a `Release pipeline composition` suite. The file
`cellarTests/ReleasePipelineCompositionTests.swift` declares three suites — `Release metadata`,
`Release pipeline placement` and `Release workflow contract` — and no suite by that name. T5 was
placed in `Release workflow contract`, beside `theWorkflowCanOnlyEverCreateARelease`, which is the
suite the design's *file* reference and its threat-matrix cross-reference both point at. Naming slip
in the artifacts, not a design change.

## Findings recorded but not acted on

**The anonymous `releases/latest` read is rate-limited.** A second `workflow_dispatch` fired 17
seconds after the first failed with `curl: (56) The requested URL returned error: 403`
([run 32642235551](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642235551)). At
`17 */6 * * *` this is unreachable, and the failure is inert by construction — nothing is committed and
the next run recomputes the same answer from scratch, which is DD-1's stated trade. `bump.yml` is
therefore left anonymous exactly as designed; the behaviour is documented in `RELEASING.md` §8 rather
than fixed. A retried dispatch ([32642400685](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642400685))
succeeded and supplied the clean second no-op S5 needs.

**Three revisions exist in the tap's reflog, one in its history.** The first push (`a33f194`) carried
the un-corrected `depends_on` line and failed CI ([run 32641848424](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32641848424));
the second (`c0d5ee5`) fixed it and went green; the third (`1441d27`) added D-2's `brew trust` line to
the tap README. Each was an **amend and force-push**, not a fix commit, so WU1 remains the single
commit the launch brief specified and the recorded S2 evidence describes the delivered bytes rather
than a superseded revision. `main` is `1441d27`, its CI is
[run 32642667011](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642667011), `success`.
Nobody else had a clone, so no published history was rewritten under a collaborator.

## Baseline counting note (for `sdd-verify` — measured, not resolved here)

`tasks.md` 0.1 says to count **distinct** `Test case '…' passed` ids and expect **232**. Measured on
`bcb9d6b`, those two do not agree:

| Counting convention | Baseline | After this change |
|---|---|---|
| Total `' passed on '` lines (each parameterised case counted once) | **232** | **237** |
| Distinct `Test case '…' passed` ids | 221 | 226 |

The stated 232 is the **total-lines** convention; three parameterised tests contribute 13 lines from 3
ids. Both conventions agree on the delta of exactly **+5**, so the guard is satisfied either way, and
232 → 237 is the figure quoted throughout this document.

`tasks.md` 5.2 says CellarCore is "1753 passed / 209 skipped". The runner's own line is
`Test run with 1753 tests in 209 suites passed` — 209 is a **suite** count, not a skip count. The 1753
is unchanged, which is the 0-line-diff proof the task actually wants.

## Blocked — the two `manual-evidence` tasks

| Task | Scenario | Why no harness can discharge it |
|---|---|---|
| 2.7 / 6.4 | S1 | Requires `brew install --cask` into a real `/Applications` on a Mac that has never had Cellar. The maintainer's Mac carries an unrelated 0.0.4 build that an install would replace, and no CI runner's `/Applications` is a real user's |
| 2.8 / 6.5 | S3 | Requires an installed cask copy that Sparkle has already self-updated in place, then `brew upgrade`. There is no way to manufacture that state without waiting for a real update |

Both are the maintainer's own steps. The spec declares them `manual-evidence` precisely so `sdd-verify`
does not deadlock waiting for a runner that cannot exist. Their capture destinations are `design.md`
*§ Evidence to capture* and the verify report.

## Changed lines, by bucket, against the forecast

`git diff --stat main...feat/m6-cask-tap` → **12 files changed, 2,757 insertions(+), 10 deletions(-)**.

| Bucket | Forecast | Actual |
|---|---|---|
| `CaskZapInventoryTests.swift` | 90–160 | 337 |
| `ReleasePipelineCompositionTests.swift` | 15–30 | 40 |
| `README.md` | 12–20 | 23 |
| `RELEASING.md` | 60–100 | 123 |
| `PRD.md` | 3–6 | 6 |
| `release.yml` | −2 | −2 |
| `LICENSE` | ≈21 | 21 |
| **Authored subtotal** | 201–341 bottom-up → ≈380–785 corrected | **552** — mid-band |
| SDD artifacts | ≈700–1,100 | 2,215 (`explore.md` at 454 was not in the bottom-up table) |
| **PR total** | ≈1,080–1,890 | **2,767** |

Above the forecast band, **well under the governing 5,000-line budget** (55 %), so `single-pr` holds
and **no `size:exception` is required**. The overshoot is entirely SDD artifacts and the test file:
`CaskZapInventoryTests.swift` carries the five-step scan algorithm the design specified in prose, and
its comments are the reason DD-10 stays true after the next cache file lands.

## Commits

| # | SHA | Message | Contents |
|---|---|---|---|
| 1 | `1d6154f` | `docs(sdd): record the m6-cask-tap proposal, spec delta, design and tasks` | the untracked openspec change folder, as-is |
| 2 | `3cec704` | `test(cask): bind the zap inventory and the install commands to the source` | RED — T1–T4 in a new file, T5 in the existing suite |
| 3 | `100532a` | `docs(cask): document the Homebrew tap and decline the release-workflow extension point` | GREEN — `README.md`, `RELEASING.md` §7+§8+renumber, `PRD.md` ×3, `release.yml` −2, `LICENSE` |
| 4 | this | `docs(sdd): record m6-cask-tap apply progress` | this file, the checked `tasks.md`, the measured `design.md` evidence |

Tap repository, one commit: `1441d27`
`feat(cask): add the home-cellar cask, its gates and its bump workflow`.

Branch is **not pushed** and **no PR is open** — the orchestrator owns delivery after `sdd-verify`.
