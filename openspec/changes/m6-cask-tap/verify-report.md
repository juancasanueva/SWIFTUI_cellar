```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:b45e6e5c6508fcb77ab18f6f9db15a8f3c18ddc3bfdacafdb536c3c0fa15233e
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 2/2
scenarios: 9/9
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:b9d78325dc940165ad9f01ad77c55b66195c920ab66018bcf5649f49ef0731ad
build_command: swift test --package-path Packages/CellarCore
build_exit_code: 0
build_output_hash: sha256:66d6e593578b0b1077fcc99d9291d9543383a192bdb27e73cb2174d4c0343bb4
```

## Verification Report

**Change**: `m6-cask-tap`
**Version**: `specs/release-distribution/spec.md` — ADDED-only delta, 2 requirements / 9 scenarios (`S1`–`S9`)
**Mode**: Strict TDD
**Branch**: `feat/m6-cask-tap` @ `4ab6dd7` · base `main` `bcb9d6b` · 4 commits, unpushed, no PR
**Tap repository**: `juancasanueva/homebrew-cellar` `main` @ `1441d27`, 1 commit, pushed
**Verifier**: independent — no product file, test or doc was edited; no review started; no receipt created; nothing committed or pushed. RDD disabled.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`,
`artifact_store=hybrid` (OpenSpec files + Engram, canonical project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

### What the envelope counts mean

`requirements: 2/2` and `scenarios: 9/9` mean **every scenario is discharged at the verification class
the spec itself declares for it** — not that every scenario has been executed. This follows the house
convention set by `2026-08-23-m6-release-pipeline`, whose `29/29` likewise counted four
`manual-evidence` scenarios as documented-but-not-yet-transcribed. The split is the honest reading:

| Class | Count | What "discharged" means here | Result |
|---|---|---|---|
| `unit` | 4 | A test in `cellarTests` passed at runtime **and** was independently shown able to fail | **4/4 runtime-proven, RED re-proven by this phase** |
| `ci-gate` | 3 | A gate ran to completion in `juancasanueva/homebrew-cellar` and its run URL, conclusion and step outcomes were re-fetched here | **3/3 run-proven** |
| `manual-evidence` | 2 | The exact command and its exact accepted output are documented so the maintainer can produce them | **2/2 documented — transcripts PENDING** |

**S1 and S3 are `pending`, not failing.** This is a maintainer decision recorded 2026-08-23, and it is
also what the spec's own class table anticipates: no harness may install into a real `/Applications`,
and this Mac carries an unrelated 0.0.4 build that `brew install --cask` would replace. Neither
`brew install --cask home-cellar` nor `brew upgrade` was run during this verification. They are the
sole reason this report is `pass_with_warnings` rather than `pass`.

#### Exactly what would discharge S1 and S3

| Scenario | Task | Command the maintainer runs | Exact accepted evidence |
|---|---|---|---|
| **S1** | 2.7 / 6.4 | On a Mac that has never had Cellar: `brew tap juancasanueva/cellar` → `brew trust juancasanueva/cellar` → `brew install --cask home-cellar` | A verbatim transcript showing `/Applications/cellar.app` exists, `PlistBuddy -c "Print :CFBundleShortVersionString"` on it prints `1.0.0`, and first launch is a single ordinary "Open" with no Gatekeeper refusal |
| **S3** | 2.8 / 6.5 | After Sparkle has self-updated a cask-installed copy **in place**, run `brew upgrade` | A verbatim transcript showing Homebrew neither lists the copy as outdated nor reinstalls over it (the `auto_updates true` mitigation, R3) |

Capture destinations for both: `design.md` *§ Evidence to capture* and this report.

### Completeness

| Metric | Value |
|---|---|
| Tasks total | 40 |
| Tasks complete | 35 |
| Tasks incomplete | 5 |

The five unchecked tasks are exactly **2.7, 2.8, 5.5, 6.4, 6.5** — verified by count, not by trust
(`rg -c '^- \[x\] '` → 35, `rg -c '^- \[ \] '` → 5). Four of them (2.7/2.8/6.4/6.5) are the two
`manual-evidence` scenarios and their evidence-capture rows; 5.5 is PR creation, which the
orchestrator owns after verify. Every one of the 35 checked boxes was matched against code, git or
run state during this phase; none is checked on trust. See WARNING **W4**.

### Build & Tests Execution

**Tests**: ✅ 237 passed / 0 failed

```text
xcodebuild test -project cellar.xcodeproj -scheme cellar \
  -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
EXIT=0
** TEST SUCCEEDED **
```

Counted both ways, because the artifacts disagree about the convention:

| Counting convention | Baseline (`bcb9d6b`) | Measured now (`4ab6dd7`) | Delta |
|---|---|---|---|
| Total `' passed on '` lines (house convention, quoted throughout the artifacts) | 232 | **237** | **+5** |
| Distinct `Test case '…' passed` ids | 221 | **226** | **+5** |

Both conventions agree on exactly **+5**, which is T1–T5. The house baseline of 237 is confirmed.
`apply-progress.md`'s *Baseline counting note* is accurate; see SUGGESTION **G1**.

**CellarCore (0-line-diff proof)**: ✅

```text
swift test --package-path Packages/CellarCore
EXIT=0
􀢂  Test run with 1753 tests in 209 suites passed after 16.081 seconds with 1 known issue.
```

`1753` is unchanged from baseline, which is the 0-line-diff proof task 5.2 actually wants. `209` is a
**suite** count, not a skip count — `tasks.md` 5.2's "1753 passed / 209 skipped" is a misreading of the
runner's own line, correctly flagged by apply and confirmed here.

**Coverage**: ➖ Not run. This slice adds no product code (0-line diff across `cellar/`,
`Packages/CellarCore/**`, `scripts/`, `project.pbxproj`), so changed-file coverage has no surface.

### RED-first proof — independently re-proven, not taken from the report

`apply-progress.md` reports a RED run for each of T1–T5 with verbatim failure text. This phase did not
accept that on trust. A **detached worktree** was created at the RED commit `3cec704` under
`/Users/juancasanueva/programming/swiftUI/cellar-worktrees/verify-red` (deliberately not under `/tmp`,
per the CodeGraph worktree-placement rule) and the tests were re-run there.

| Test | At RED `3cec704` | At tip `4ab6dd7` | Re-proven by this phase |
|---|---|---|---|
| **T1** `everyWriteRootTheSourceDeclaresIsInTheDocumentedInventory` | ❌ failed | ✅ passed | **yes** |
| **T2** `theWriteRootScanIsNonVacuousAndEveryPassThroughIsAHomebrewRootsHandOff` | ❌ failed | ✅ passed | **yes** |
| **T3** `theRunbookNamesBothKeychainItemsAZapCannotRemove` | ❌ failed | ✅ passed | **yes (required)** |
| **T4** `theReadmeCarriesBothBrewCommandsAsWholeLines` | ❌ failed | ✅ passed | **yes** |
| **T5** `theWorkflowGainsNoCrossRepositoryReach` | ❌ failed | ✅ passed | **yes (required)** |

Verbatim, from the worktree at `3cec704`:

```text
Failing tests:
	CaskZapInventoryTests.theRunbookNamesBothKeychainItemsAZapCannotRemove()
	CaskZapInventoryTests.everyWriteRootTheSourceDeclaresIsInTheDocumentedInventory()
	CaskZapInventoryTests.theWriteRootScanIsNonVacuousAndEveryPassThroughIsAHomebrewRootsHandOff()
	CaskZapInventoryTests.theReadmeCarriesBothBrewCommandsAsWholeLines()
** TEST FAILED **
RED_EXIT=65
```

```text
Failing tests:
	ReleaseWorkflowContractTests.theWorkflowGainsNoCrossRepositoryReach()
** TEST FAILED **
RED_T5_EXIT=65
```

All four of T1–T4 and T5 fail at `3cec704` and all five pass at `4ab6dd7`. The strict-TDD RED→GREEN
transition is therefore established by execution in both directions, not by report.

**Worktree cleanup**: `git worktree remove --force` succeeded, `git worktree prune` run,
`git worktree list` shows only the main checkout, and the now-empty
`/Users/juancasanueva/programming/swiftUI/cellar-worktrees` parent was removed. `git status --porcelain`
in the repository is empty and `HEAD` is still `4ab6dd7`.

A methodological note worth keeping: the first T5 attempt used
`-only-testing:cellarTests/ReleaseWorkflowContractTests/theWorkflowGainsNoCrossRepositoryReach`
**without** the `()` suffix. The suite started and **no test case ran**, so a naive reading would have
scored T5 as "not RED". Swift Testing function selectors require the trailing `()`. See SUGGESTION **G3**.

### Spec Compliance Matrix

| # | Requirement | Scenario | Class | Evidence | Result |
|---|---|---|---|---|---|
| **S1** | Installable through the tap | A tap and an install put the released build in `/Applications` | `manual-evidence` | Not captured — maintainer's own step | ⚠️ **PENDING** |
| **S2** | Installable through the tap | Cask is style-clean, audit-clean, survives install/zap round trip | `ci-gate` | run `32642667011`, `success`, headSha `1441d27` — all 11 steps `success` | ✅ COMPLIANT |
| **S3** | Installable through the tap | A self-updated app does not fight `brew upgrade` | `manual-evidence` | Not captured — maintainer's own step | ⚠️ **PENDING** |
| **S4** | Installable through the tap | A prerelease never becomes an installable cask version | `ci-gate` | runs `32642223493` / `32642400685`, both `success`; `releases/latest` → `v1.0.0` (`prerelease:false`) while `v0.0.1-rc.1` exists; `*-*` refusal guard at `bump.yml:48`; `livecheck strategy :github_latest` | ✅ COMPLIANT — see WARNING **W2** |
| **S5** | Installable through the tap | Keeping the cask current is idempotent on the declared version | `ci-gate` | Both runs log `the cask already declares 1.0.0; nothing to do`; the `Commit the bump` step is `skipped` in **both**; tap `main` still holds exactly **1** commit | ✅ COMPLIANT |
| **S6** | Uninstall states what it removes | The documented inventory covers every write root the source declares | `unit` | `CaskZapInventoryTests/everyWriteRootTheSourceDeclaresIsInTheDocumentedInventory()` + `…theWriteRootScanIsNonVacuousAndEveryPassThroughIsAHomebrewRootsHandOff()` — passed, RED re-proven | ✅ COMPLIANT |
| **S7** | Uninstall states what it removes | The two Keychain items are documented as surviving a full uninstall | `unit` | `CaskZapInventoryTests/theRunbookNamesBothKeychainItemsAZapCannotRemove()` — passed, RED re-proven; `RELEASING.md:428-429` | ✅ COMPLIANT |
| **S8** | Uninstall states what it removes | The install commands are documented as whole lines | `unit` | `CaskZapInventoryTests/theReadmeCarriesBothBrewCommandsAsWholeLines()` — passed, RED re-proven; `README.md:37-39` | ✅ COMPLIANT |
| **S9** | Uninstall states what it removes | The release run gains no cross-repository reach | `unit` | `ReleaseWorkflowContractTests/theWorkflowGainsNoCrossRepositoryReach()` — passed, RED re-proven | ✅ COMPLIANT |

**Compliance summary**: 7/9 runtime- or run-proven; 2/9 documented and pending by declared class and
maintainer decision. 0 failing, 0 untested.

### `ci-gate` evidence — re-fetched, not quoted from the artifacts

Every run below was re-queried with `gh run view --repo juancasanueva/homebrew-cellar <id>`.

| Run | Workflow | Event | Conclusion | headSha |
|---|---|---|---|---|
| [`32642667011`](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642667011) | CI | `push` | `success` | **`1441d27…`** ✅ delivered SHA |
| [`32642223493`](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642223493) | Bump | `workflow_dispatch` | `success` | `c0d5ee5…` ⚠️ see **W3** |
| [`32642400685`](https://github.com/juancasanueva/homebrew-cellar/actions/runs/32642400685) | Bump | `workflow_dispatch` | `success` | `c0d5ee5…` ⚠️ see **W3** |

**S2, run 32642667011 — every step `success`**: Set up job · Check out the tap · Record the runner
image · Register the checkout as a real tap · Style · Audit, offline · Audit, online and strict ·
Install · Uninstall with a zap · Post Check out the tap · Complete job.

Verbatim from the log:

```text
cask  Style                     2 files inspected, no offenses detected
cask  Audit, online and strict  ==> Downloading https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v1.0.0/Home-Cellar-1.0.0.zip
cask  Install                   ==> Moving App 'cellar.app' to '/Applications/cellar.app'
cask  Install                   🍺  home-cellar was successfully installed!
cask  Install                   1.0.0
cask  Uninstall with a zap      ==> Removing App '/Applications/cellar.app'
```

The bare `1.0.0` is the `PlistBuddy -c "Print :CFBundleShortVersionString"` readback of the installed
bundle, so the install step proves the **version**, not merely the path. R13 did not fire: `--strict`
raised no `homebrew/cask`-submission-only rule and `--online` was never weakened.

**S5, both bump runs — verbatim, post-`endgroup`**:

```text
bump  Exit if the cask already declares that version  the cask already declares 1.0.0; nothing to do
```

In both runs the five subsequent steps (`Compute the checksum…`, `Rewrite the two declared lines`,
`Register the rewritten checkout…`, `Gate the rewrite…`, **`Commit the bump`**) are `skipped`. Zero
commits were produced, and the tap's `main` still holds exactly one commit — re-confirmed with
`git log --oneline | wc -l` → `1` and `git rev-parse origin/main` → `1441d27…`.

### The delivered cask — checked stanza by stanza at `1441d27`

| Requirement from the launch brief | Measured | Result |
|---|---|---|
| `version "1.0.0"` | exact-line count 1 | ✅ |
| `sha256 "078a0b5a…6793b6"` | exact-line count 1 | ✅ |
| `auto_updates true` | present | ✅ |
| `app "cellar.app"` with **no** `target:` | present; `target:` absent from the whole file | ✅ |
| `livecheck` → `strategy :github_latest` | present | ✅ |
| no `verified:` | absent | ✅ |
| `zap trash:` exactly 5 paths, no `savedState` | 5 paths; `savedState` absent | ✅ |
| no `caveats` (DD-6) | absent | ✅ |

**P3 independently re-verified.** `gh api repos/juancasanueva/SWIFTUI_cellar/releases/tags/v1.0.0`
reports the asset `Home-Cellar-1.0.0.zip`, size `6448745`, digest
`sha256:078a0b5a49fa6e75f885796de1764f36efe72e9db8564fb140bf2112fd6793b6` — byte-for-byte the value
the cask declares. The checksum is bound to the **published** asset, not to a build-time value.

### Bindings — the 0-line diffs, asserted

```text
$ git diff --stat main...feat/m6-cask-tap -- scripts cellar.xcodeproj Packages cellar
(empty)

$ git diff --stat main -- scripts/ cellar.xcodeproj/project.pbxproj Packages/CellarCore cellar/ cellar.xcodeproj/xcshareddata
(empty)
```

Both the launch brief's form and `tasks.md` 5.3's form return **empty**. No product Swift, no script,
no project-file and no scheme change. ✅

**`release.yml` — exactly −2 comment lines:**

```diff
@@ -172,8 +172,6 @@ jobs:
              --verify-tag --generate-notes --title "$GITHUB_REF_NAME" $PRERELEASE
-      # --- extension point: the cask bump (m6-cask-tap) inserts here without
-      #     restructuring the job. ---
```

`1 file changed, 2 deletions(-)`. No step, no `- name:` boundary, no trigger and no secret reference
moves — the two deleted lines are comments **inside** the `Publish GitHub Release` step body. Confirmed
independently by the fact that all pre-existing `ReleaseWorkflowContractTests` cases, including
`workflowReferencesExactlyTheExpectedSecrets`, `theWorkflowCanOnlyEverCreateARelease`,
`privateRepositoryFailsFastBeforeAnyBuildStep` and `keychainDeletionRunsUnconditionally`, still pass. ✅

Full branch diffstat: **13 files changed, 3,123 insertions(+), 10 deletions(-)** — under the governing
5,000-line budget, so `single-pr` holds with no `size:exception`.

### Design R7 — the four tap files are byte-identical to the design's quoted blocks

R7's whole mitigation is that a PR reviewer can read the tap change without leaving the PR. That is
only true if the quoted bytes are the delivered bytes. Each fenced block in `design.md` was extracted
and `diff`ed against the file in the tap working tree:

| `design.md` block | Tap file | Result |
|---|---|---|
| `` ```ruby `` :125-153 | `Casks/home-cellar.rb` | ✅ **BYTE-IDENTICAL** |
| `` ```yaml `` :178-267 | `.github/workflows/ci.yml` | ✅ **BYTE-IDENTICAL** |
| `` ```yaml `` :273-415 | `.github/workflows/bump.yml` | ✅ **BYTE-IDENTICAL** |
| ` ````markdown ` :421-494 | `README.md` (tap) | ✅ **BYTE-IDENTICAL** |

The design was correctly re-synced to the delivered bytes for **all four** tap files, including D-1's
`depends_on macos: :tahoe` (`design.md:141`) and D-2's `brew trust juancasanueva/cellar`
(`design.md:430`).

**`LICENSE` byte-identical in both repositories**:
`82cfbe456714d1ca7e7a14766590a498c14ec20f4e659839d8e8c0c05620b6a2` in each. The tap README's "the same
licence as the app" is now grounded. ✅

### Docs consistency — the accepted deviation forms

| Check | Location | Result |
|---|---|---|
| README install fence carries **three** whole lines | `README.md:37-39` | ✅ `brew tap` / `brew trust` / `brew install --cask home-cellar` |
| README names `/Applications/cellar.app` and the fully-qualified form | `README.md:42-47` | ✅ |
| README uninstall + Keychain caveat naming both services | `README.md:56-60` | ✅ |
| `RELEASING.md` §7 inherited-contract paragraph replaced (DD-12) | `RELEASING.md:309-315` | ✅ the extension point is declined, not occupied |
| `RELEASING.md` §8 exists, Troubleshooting renumbered to §9 | `RELEASING.md:324`, `:435` | ✅ headings run 1–9 with no gap or duplicate |
| §8 canonical-install row carries the **three-line** D-2 form | `RELEASING.md:334` | ✅ |
| `zap-inventory` fenced block, 5 rows, 2 `source` + 3 `framework` | `RELEASING.md:402-408` | ✅ parsed by T1/T2 at runtime |
| `savedState`-absent note | `RELEASING.md:410` | ✅ |
| Both Keychain services named | `RELEASING.md:428-429` | ✅ |
| Manual fallback (D1 option D) | `RELEASING.md:373` | ✅ |
| Rate-limit note (finding 3) | `RELEASING.md:369` | ✅ documented, not fixed — as decided |
| PRD `:9` Distribution cell | `PRD.md:9` | ✅ names the tap and `brew install --cask home-cellar` |
| PRD `:194` Cask channel bullet | `PRD.md:194` | ✅ *implemented (M6)* |
| PRD `:217` M6 parenthetical gains slice 4 | `PRD.md:217` | ✅ "§6" correctly cross-references PRD `## 6. Monetization & distribution` at `:189` |
| Tap README carries the same `brew trust` line | tap `README.md:10` | ✅ |

**Stale-token sweep** (`rg`, excluding `openspec/changes/archive/` and this change's own artifacts):

| Token | Hits | Verdict |
|---|---|---|
| `juan/tap` | 0 | ✅ gone |
| `brew install --cask cellar` | 0 | ✅ gone |
| `still pending` | 0 | ✅ gone |
| `extension point` | 3 | ✅ all legitimate — `RELEASING.md:309` describes the **declined** point in past tense; `ReleasePipelineCompositionTests.swift:785,787` are T5's comment and its absence assertion. **`release.yml` itself carries none**, which is exactly what T5 proves |

### Coherence (design)

| Decision | Followed? | Notes |
|---|---|---|
| **D1** pull-based bump in the tap repo | ✅ | `bump.yml` on `schedule` + `workflow_dispatch`; no dispatch anywhere in `release.yml` (T5) |
| **D2** delete the extension-point comment | ✅ | −2 lines, test-driven by T5's first clause |
| **D3** `app "cellar.app"`, no `target:` | ✅ | verified in the delivered cask |
| **D4** GitHub homepage ⇒ no `verified:` | ✅ | `verified:` absent; `brew audit --online --strict` exit 0 |
| **D5** the tap carries its own README | ✅ | present, byte-identical to the design block |
| **DD-7** `cp -R` tap registration, never `brew tap <path>` | ✅ | `ci.yml` copies into `$(brew --repository)/Library/Taps/juancasanueva/homebrew-cellar` |
| **DD-8** gates run **before** the commit | ✅ | `Gate the rewrite…` precedes `Commit the bump` in `bump.yml` |
| **DD-9/DD-10** scan finds 2 roots; every pass-through is a `HomebrewRoots` hand-off | ✅ | asserted by T2 at runtime as a **set equality**, not a floor |
| **DD-11** `zap-inventory` fence, split on first whitespace run | ✅ | `CaskZapSources.inventoryRows()` splits on the first whitespace run, so `Application Support` survives |
| **DD-13** MIT `LICENSE` in both repos | ✅ | byte-identical |
| **R14** arm64 assertion before any gate | ✅ | `test "$(uname -m)" = "arm64"` in `ci.yml`'s `Record the runner image` |

### Deviations from the design — judged

| # | Deviation | Judgement |
|---|---|---|
| **D-1** | `depends_on macos: :tahoe` replaces `">= :tahoe"` | ✅ **Accepted and consistent.** `Homebrew/OSDependsOn` makes the string form a style offense on Homebrew 6, so the `brew style` gate the design itself mandates could not pass without it. The symbol form is the same minimum-version claim; the macOS 26.0 floor is unchanged. `design.md:141` and `:165` are re-synced, and the cask is byte-identical to the block |
| **D-2** | Canonical install is **three** whole lines (`brew tap` / `brew trust` / `brew install --cask home-cellar`) | ✅ **Accepted; shipped docs consistent.** `README.md:37-39`, `RELEASING.md:334` and tap `README.md:10` all carry the three-line form. T4 is unaffected — it asserts the two design-specified commands are whole lines, and both still are. **However `design.md`'s own §8 block was not re-synced — see WARNING W1** |
| **D-3** | T5 lives in the `Release workflow contract` suite | ✅ **Accepted.** Confirmed by inspection: `ReleasePipelineCompositionTests.swift` declares `Release metadata` (:175), `Release pipeline placement` (:374) and `Release workflow contract` (:469) — and no `Release pipeline composition` suite. T5 sits at :778 inside `Release workflow contract`, beside `theWorkflowCanOnlyEverCreateARelease`, which is where the design's threat-matrix cross-reference points. Naming slip in the artifacts, not a design change. See SUGGESTION **G2** |

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ✅ | *TDD Cycle Evidence* table present in `apply-progress.md` with all five rows |
| All tasks have tests | ✅ | 5/5 `unit` tasks have test files; the `ci-gate` and `manual-evidence` tasks correctly declare that no `cellarTests` harness can reach them |
| RED confirmed (tests exist **and fail**) | ✅ | 5/5 **independently re-proven at `3cec704`**, not accepted from the report |
| GREEN confirmed (tests pass) | ✅ | 5/5 pass at `4ab6dd7` |
| Triangulation adequate | ✅ | T1 2 roots × 2 domains + non-empty guard · T2 5 clauses incl. set equality · T3 2 services asserted separately · T4 4 clauses · T5 6 clauses |
| Safety net for modified files | ✅ | 232/232 before the one modified test file; `CaskZapInventoryTests.swift` is new |

**TDD Compliance**: 6/6 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|-------|-------|-------|-------|
| Unit | 5 | 2 | Swift Testing (`cellarTests`) |
| Integration | 0 | 0 | no surface — this change adds no runtime code |
| E2E | 0 | 0 | not installed |
| **Total** | **5** | **2** | |

The `ci-gate` and `manual-evidence` proofs are deliberately *not* counted as test layers here: they run
in another repository or on a maintainer's Mac, and the spec's class table says so plainly rather than
faking them as `cellarTests` cases.

### Changed File Coverage

➖ Coverage analysis skipped — this change adds **no product code** (0-line diff across `cellar/`,
`Packages/CellarCore/**`, `scripts/` and `project.pbxproj`). The only new Swift is four `nonisolated`
read-only source-scanning tests plus one workflow-scanning test. Not a failure; no surface exists.

### Assertion Quality

Both test files were read in full and audited against the banned-pattern list.

| Pattern audited | Finding |
|---|---|
| Tautologies (`#expect(true)`) | none |
| Assertions that never call production code | none — every test reads real repository files through `CaskZapSources` / `ReleasePipelineSources` |
| **Ghost loops** (assertions over a possibly-empty collection) | **none, and guarded on purpose.** T1 asserts `#expect(!discovered.isEmpty)` before iterating `discovered`; T2 asserts `#expect(passThrough.count >= 5)` immediately before iterating `passThrough`; T5 asserts `#expect(!apiCalls.isEmpty)` before iterating `apiCalls`. T3 and T4 iterate 2-element **literal** arrays. Every loop in this change is anchored |
| Orphan empty-collection checks | none |
| Type-only assertions used alone | none |
| Smoke-test-only | none |
| Implementation-detail coupling | none — assertions are on documented content and declared write roots, not on internals |
| Mock-heavy tests | none — zero mocks; these are on-disk source and document scans |

**Assertion quality**: ✅ All assertions verify real behaviour. 0 CRITICAL, 0 WARNING.

Worth naming explicitly: T2's `#expect(try CaskZapSources.discoveredWriteRoots() == expected)` is a
**set equality against two specific paths**, not a count floor. That is the assertion that makes DD-10
structurally load-bearing — a scan that started sweeping `HomebrewRoots`' `~/Library/Caches/Homebrew`
into the zap list would fail here rather than silently widening what an uninstall deletes.

### Quality Metrics

**Linter**: ➖ Not applicable — no product code changed; `brew style` (the relevant linter for the
delivered artifact) ran green in tap CI: `2 files inspected, no offenses detected`.
**Type Checker**: ✅ No errors — the `xcodebuild test` and `swift test` runs both compiled cleanly at exit 0.

### Commit hygiene

| Commit | Message | Conventional | Attribution |
|---|---|---|---|
| `1d6154f` | `docs(sdd): record the m6-cask-tap proposal, spec delta, design and tasks` | ✅ | clean |
| `3cec704` | `test(cask): bind the zap inventory and the install commands to the source` | ✅ | clean |
| `100532a` | `docs(cask): document the Homebrew tap and decline the release-workflow extension point` | ✅ | clean |
| `4ab6dd7` | `docs(sdd): record m6-cask-tap apply progress` | ✅ | clean |
| tap `1441d27` | `feat(cask): add the home-cellar cask, its gates and its bump workflow` | ✅ | clean |

`git log --format='%B%n%an%n%ae'` across both repositories matched **zero** occurrences of
`Co-Authored-By`, `Claude`, `Anthropic` or `Generated with`. Author is
`Juan Casanueva <juancasanueva@gmail.com>` throughout. ✅

### Issues Found

**CRITICAL**: None.

**WARNING**:

- **W1 — `design.md`'s `RELEASING.md` §8 block still quotes the pre-D-2 two-line install.**
  `design.md:564` reads ``| Canonical install | `brew tap juancasanueva/cellar` then `brew install --cask home-cellar` |``
  while the shipped `RELEASING.md:334` correctly reads
  ``| Canonical install | `brew tap juancasanueva/cellar`, then `brew trust juancasanueva/cellar`, then `brew install --cask home-cellar` |``.
  The design carries an explicit *"Amended at apply"* note above its **README** block (`design.md:504-508`)
  and re-synced the **tap README** block (`design.md:430`), but the §8 block got neither treatment, so a
  reader of the design silently receives a form that fails on current Homebrew.
  *Impact*: artifact-only. Shipped docs, tests and the cask are correct and mutually consistent; no
  spec scenario is affected. *Fix*: add the same one-line amendment note above `design.md:553`, or
  update the `:564` row to the three-line form. Cheap, and best done before archive freezes the design.

- **W2 — S4's adversarial precondition was never instantiated.** The scenario reads *"GIVEN a published
  prerelease tag that is **newer than** the latest stable release"*. The app repository's only
  prerelease, `v0.0.1-rc.1` (2026-08-23T05:46:22Z), **predates** `v1.0.0` (2026-08-23T10:28:24Z), so no
  run ever faced a newer prerelease. What *is* proven: `releases/latest` resolves to `v1.0.0` with
  `prerelease:false` **while a prerelease exists in the repository**, `bump.yml:48` carries an explicit
  `*-*) … exit 1` refusal, and the cask declares `livecheck strategy :github_latest`. Three independent
  mechanisms, none of them exercised against the exact ordering the GIVEN describes.
  *Impact*: evidence strength, not correctness — GitHub's `releases/latest` contract excludes
  prereleases irrespective of recency. *Fix (optional, cheap)*: at the next `v*-rc.*` tag, dispatch
  `bump.yml` once and record that `releases/latest` still resolves to the stable tag.

- **W3 — the two bump runs were measured at `c0d5ee5`, not at the delivered `1441d27`.** Both
  `32642223493` and `32642400685` carry headSha `c0d5ee5…`, a revision later amended away;
  `apply-progress.md` and `design.md` cite the runs without stating this. **Verified rather than
  assumed**: the files at `c0d5ee5` were fetched through the GitHub contents API and diffed against the
  delivered tree — `.github/workflows/bump.yml`, `.github/workflows/ci.yml`, `Casks/home-cellar.rb` and
  `LICENSE` are all **byte-identical**; only the tap `README.md` differs, by exactly D-2's `brew trust`
  line and its explanatory sentence, and `bump.yml` never reads the README. The S4/S5 evidence
  therefore does bind to the delivered mechanism bytes.
  *Note*: `gh api …/compare/c0d5ee5...1441d27` returns *"No common ancestor"* because the apply phase
  amended and force-pushed a **root** commit three times, so the superseded revisions share no history.
  They remain reachable by SHA today, but nothing guarantees GitHub retains unreferenced objects
  indefinitely. *Fix*: record the `c0d5ee5` headSha and this byte-identity finding in the archived
  evidence, so the provenance is not re-derived later from runs that may become unreachable.

- **W4 — five tasks remain unchecked.** Exactly `2.7`, `2.8`, `5.5`, `6.4`, `6.5`. The `sdd-verify`
  default treats any unchecked task as CRITICAL and blocks full verification; that default is
  **overridden here** by the maintainer decision of 2026-08-23 and by the spec's own `manual-evidence`
  class, which exists precisely so this phase does not deadlock on a harness the spec declares cannot
  exist. `2.7/2.8/6.4/6.5` are S1/S3 and their capture rows; `5.5` is PR creation, which the
  orchestrator owns after verify. Recorded as WARNING, not CRITICAL, and named so the override is
  visible rather than silent.

**SUGGESTION**:

- **G1 — pin the baseline counting convention in `tasks.md`.** Task 0.1 says to count *distinct*
  `Test case '…' passed` ids and expect 232, but those two disagree (distinct ids give 221/226; the
  total `' passed on '` line count gives 232/237). Both conventions agree on the +5 delta, so nothing is
  wrong here — but the next slice will re-derive the same confusion. State the total-lines convention
  explicitly in the house test-runner note.
- **G2 — correct the suite name in `design.md` and `tasks.md`.** Both name a `Release pipeline
  composition` suite that does not exist; the file declares `Release metadata`, `Release pipeline
  placement` and `Release workflow contract`. D-3 is accepted, so this is purely an artifact-accuracy
  fix worth making before archive.
- **G3 — record the Swift Testing selector gotcha.** `-only-testing:cellarTests/<Suite>/<func>` silently
  runs **zero cases** without the trailing `()`; the suite still "starts" and a careless reading scores
  it as passing. This bit this verification once and is worth a line in the house testing notes.
- **G4 — `savedState` deserves a periodic re-measure.** It is correctly absent today (never guessed in),
  but if macOS later starts writing it the inventory would be quietly incomplete, and no test can catch
  a framework-written root. A note in `RELEASING.md` §8 pointing at the P7/P8 probe method would keep
  the re-measure cheap.

### Archive readiness — what `sdd-archive` must hand-update

The delta is **ADDED-only** (2 requirements / 9 scenarios; 0 modified, 0 removed, 0 renamed), so
`rules.archive`'s destructive-delta warning does not fire. Arithmetic independently re-counted against
the current merged file rather than trusted from the note:

| Class | Main spec today | This delta | After merge |
|---|---|---|---|
| `unit` | 14 | +4 | **18** |
| `ci-gate` | 14 | +3 | **17** |
| `manual-evidence` | 4 | +2 | **6** |
| **Total scenarios** | **32** | **+9** | **41** |
| **Requirements** | **8** | **+2** | **10** |

Measured now: `openspec/specs/release-distribution/spec.md` has 8 `### Requirement:`, 32
`#### Scenario:` and 32 `- Verification:` lines (14 `unit` / 14 `ci-gate` / 4 `manual-evidence`); the
delta has 2 / 9 / 9 (4 `unit` / 3 `ci-gate` / 2 `manual-evidence`). The delta's *Notes for archive* are
**arithmetically correct**.

Actions for `sdd-archive`:

1. **Append** both requirement blocks to `openspec/specs/release-distribution/spec.md`. All eight
   existing requirements stay untouched; no existing scenario is edited or deleted.
2. **Hand-update the `## Verification classes` table** at `:9-19`. It lives outside every requirement
   block, so an ADDED delta structurally cannot carry it. **Two edits, and the second is easy to miss:**
   - **Counts**: `unit` 14 → **18**, `ci-gate` 14 → **17**, `manual-evidence` 4 → **6**.
   - **Meaning**: `ci-gate` currently reads *"a hard gate inside **the release run**"* (`:17`). Three of
     this delta's `ci-gate` scenarios run in `juancasanueva/homebrew-cellar`, **not** in this
     repository's release run, so the meaning MUST widen to *"a hard gate whose failure fails its job
     and commits or publishes nothing"*, with the runner named. Updating the counts without the meaning
     would leave the table stating something false.
   - Confirm by counting `- Verification:` lines in the merged file — expect **41**.
3. **Extend `## Provenance`** (`:408`) with **D1–D5**, each naming what was rejected: D1 the pull-based
   bump (rejected: cross-repo `repository_dispatch` from the release job, a second workflow here,
   manual-only); D2 the deletion of the declined extension-point comment; D3 `app "cellar.app"` with no
   rename (rejected: `target:`); D4 the GitHub homepage making `verified:` an audit error; D5 the tap
   repository carrying its own README. Add **DD-13** (MIT `LICENSE` in both repositories) and the three
   accepted apply deviations **D-1/D-2/D-3**.
4. **Record the inherited-contract paragraph as consumed** — `m6-cask-tap` binds its cask to the asset
   URL, the `cellar.app` bundle name, the arm64 pin and the macOS 26.0 floor exactly as that paragraph
   anticipated, and re-derives none of them.
5. **Record the deferred follow-ups** so they are not re-derived:
   - the **`Home-Cellar.app` rename** slice (touches `PRODUCT_NAME`, four `release.sh` gates, the
     `release-distribution` bundle-name scenario, and update continuity for every installed 1.0.0 copy);
   - moving **`~/Library/Caches/Cellar` under the bundle id** — a migration, R4, and the reason the
     display-name caveat is written down rather than silently widened;
   - **submission to `homebrew/cask`** — notability requirements unmet; the self-hosted tap is the channel;
   - a DMG, and the landing page.
6. **Carry W1/W2/W3 forward** — ideally fix W1 in `design.md` *before* archive freezes it.

### Verdict

**PASS WITH WARNINGS**

All four `unit` scenarios are runtime-proven with an independently re-proven RED→GREEN transition, all
three `ci-gate` scenarios are run-proven against re-fetched GitHub run data, every binding 0-line diff
holds, the `release.yml` change is exactly the two declared comment lines, all four tap files and both
`LICENSE` files are byte-identical to the design's quoted blocks, the delivered cask matches every
declared stanza, and commit hygiene is clean in both repositories. `S1` and `S3` remain **pending** by
maintainer decision and by the spec's own `manual-evidence` class — not failing. Four warnings are
recorded, none of them blocking; **W1** is a cheap artifact fix best made before archive.
