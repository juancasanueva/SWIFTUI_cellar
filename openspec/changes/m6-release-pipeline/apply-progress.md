# Apply progress: Developer ID Release Pipeline (`m6-release-pipeline`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`
(no `size:exception` needed — forecast ~1,590–2,975 against the governing 5,000-line budget),
`chain_strategy=n/a`, `review_budget_lines=5000`, `strict_tdd=true`, RDD **disabled** (no review
started, no receipt created).

Mode: **Strict TDD**. Branch `feature/m6-release-pipeline`, base `e0b4803` (SDD artifacts only) on top
of `main` at `ec7b1c5`. Scope executed: **Phases 0–5 complete (35/35 tasks)**. Phase 6 (8 tasks) and the
maintainer checklist P1–P6 remain open, blocked on prerequisites that do not exist on this machine.

Test runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination
'platform=macOS,arch=arm64' -only-testing:cellarTests`. `cellarUITests` was never run — it is not part
of this slice. Counts below are **distinct** `Test case '…' passed` ids; the XCTest `Executed N tests`
line reads 0 for Swift Testing bundles and is never used as evidence.

## Task status

| Task | Status | Evidence |
|---|---|---|
| 0.1 tooling | ✅ | `actionlint 1.7.12`, `shellcheck 0.11.0`, both at `/opt/homebrew/bin` |
| 0.2 U29 baseline cited | ✅ | Cited, not re-run. See *Baseline discrepancy* below — the stated 141 does not reproduce |
| 1.1 RED T11 | ✅ | `ReleaseMetadataTests/appTargetsPinARM64()` **failed** before the pbxproj edit |
| 1.2 GREEN `ARCHS = arm64` | ✅ | `git diff --stat` → `1 file changed, 2 insertions(+)` |
| 1.3 GREEN-on-arrival T14 + T17a | ✅ | Both passed on their first run, as declared |
| 1.4 diff is exactly two lines | ✅ | Confirmed against `e0b4803`: `2 insertions(+)`, no other key moved |
| 2.1 RED T9 | ✅ | `stringCatalogIsTheOnlyCopyrightAuthority()` **failed** before the catalog edit |
| 2.2 RED T10 | ✅ | `bundleReportsCopyright()` **failed** before the catalog edit |
| 2.3 GREEN catalog | ✅ | `NSHumanReadableCopyright` set, `state: new` → `translated`; pbxproj untouched |
| 2.4 re-check | ✅ | Both green; pbxproj diff still exactly 2 lines |
| 3.1 RED T1 | ✅ | `releaseScriptAndExportOptionsExist()` **failed** before `scripts/` existed |
| 3.2 RED T7 | ✅ | `exportOptionsDeclareDeveloperIDDistribution()` **failed** |
| 3.3 RED T8 | ✅ | `releaseScriptCarriesTheWholeSequence()` + `stapleDeletesTheArchiveBeforeRepackaging()` **failed** |
| 3.4 RED T15a | ✅ | `releaseScriptCannotPublishOrSelectARepository()` **failed** |
| 3.5 RED T16a | ✅ | `releaseScriptNeverTracesCommands()` **failed** |
| 3.6 GREEN `ExportOptions.plist` | ✅ | `developer-id` / `automatic` / `Z3S5JK8E38` / `export` / `manageAppVersionAndBuildNumber false` |
| 3.7 GREEN `release.sh` | ✅ | Seven phases, `set -euo pipefail`, `chmod +x` (git mode `100755`) |
| 3.8 ci-gate G2 | ✅ | `shellcheck scripts/release.sh` → no findings, **exit 0** |
| 4.1 RED T2 | ✅ | `releaseWorkflowExists()` **failed** before `.github/` existed |
| 4.2 RED T3 | ✅ | `onlyAVersionTagTriggersTheWorkflow()` **failed** |
| 4.3 RED T19 | ✅ | `privateRepositoryFailsFastBeforeAnyBuildStep()` **failed** |
| 4.4 RED T4 | ✅ | `keychainDeletionRunsUnconditionally()` **failed** |
| 4.5 RED T5 | ✅ | `secretsAppearOnlyAsEnvironmentBindings()` **failed** |
| 4.6 RED T6 | ✅ | `workflowReferencesExactlyTheExpectedSecrets()` **failed** |
| 4.7 RED T15b | ✅ | `theWorkflowCanOnlyEverCreateARelease()` **failed** |
| 4.8 RED T16b | ✅ | `workflowNeverTracesCommands()` **failed** |
| 4.9 GREEN `release.yml` | ✅ | Tag-only trigger, `macos-26`, one named step per script phase, `if: always()` cleanup |
| 4.10 GREEN-on-arrival T12 + T13 | ✅ | Both passed on their first run, authored in the same commit as the files they guard |
| 4.11 ci-gate G1 | ✅ | `actionlint .github/workflows/release.yml` → no output, **exit 0** |
| 5.1 RED T17b | ✅ | `runbookRecordsTheVersionPolicyAndItsOverride()` **failed** before `RELEASING.md` |
| 5.2 RED T18 | ✅ | `runbookNamesTheAbsentEntitlements()` **failed** before `RELEASING.md` |
| 5.3 GREEN `RELEASING.md` | ✅ | §1–§8; §6 evidence block clearly marked as a placeholder pending U26/U28 |
| 5.4 GREEN PRD amendments | ✅ | :9, :157, :168, :187, :212, :224, :227 rewritten in place with the reason |
| 5.5 GREEN README | ✅ | `## Install` between Requirements and Building; `## Releasing` after Building |
| 5.6 ci-gate G4 | ✅ | **183 distinct passed / 0 failed**, `** TEST SUCCEEDED **`. CellarCore proved by 0-line diff, not re-run |
| 6.1–6.8, P1–P6 | ⛔ blocked | See *Blocked* below |

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 1.1/1.2 T11 | `cellarTests/ReleasePipelineCompositionTests.swift` | Unit | N/A (new file) | ✅ `appTargetsPinARM64()` failed | ✅ passed after the 2-line pbxproj edit | ✅ 3 cases — count is 2, one Debug, one Release | ➖ none needed |
| 1.3 T14 | same | Unit | ✅ 1/1 (T11 green) | ➖ declared GREEN-on-arrival | ✅ passed first run | ✅ equality plus a non-vacuity check that the compared set contains `ARCHS` | ➖ |
| 1.3 T17a | same | Unit | ✅ 2/2 | ➖ declared GREEN-on-arrival | ✅ passed first run | ✅ 4 settings × both blocks | ➖ |
| 2.1 T9 | same | Unit | ✅ 3/3 | ✅ failed | ✅ passed after the catalog edit | ✅ catalog value + state + both bundle-name keys + both pbxproj blocks | ➖ |
| 2.2 T10 | same | Unit | ✅ 3/3 | ✅ failed | ✅ passed | ✅ exact value + non-empty, read from `localizedInfoDictionary` | ➖ |
| 3.1 T1 | same | Unit | ✅ 5/5 | ✅ failed | ✅ passed | ✅ 2 files + the executable bit | ➖ |
| 3.2 T7 | same | Unit | ✅ 5/5 | ✅ failed | ✅ passed | ✅ 3 parsed keys | ➖ |
| 3.3 T8 | same | Unit | ✅ 5/5 | ✅ failed (both cases) | ✅ passed | ✅ 11 commands + 3 plutil keys + the enumeration guard + a positional ordering case | ✅ removed a dead helper from `release.sh`, gates re-run |
| 3.4 T15a | same | Unit | ✅ 5/5 | ✅ failed | ✅ passed | ✅ absence of `gh`/`git` **plus** presence of `xcodebuild` through the same matcher | ➖ |
| 3.5 T16a | same | Unit | ✅ 5/5 | ✅ failed | ✅ passed | ✅ 2 forms (`set -x`, `set -eux`) | ➖ |
| 4.1 T2 | same | Unit | ✅ 11/11 | ✅ failed | ✅ passed | ➖ single existence claim | ➖ |
| 4.2 T3 | same | Unit | ✅ 11/11 | ✅ failed | ✅ passed | ✅ 3 positives + 4 negatives in the trigger block + 3 file-wide negatives + 4 design pins | ✅ split the trigger-scoped and file-scoped negatives after the first draft built a malformed `branches::` needle |
| 4.3 T19 | same | Unit | ✅ 11/11 | ✅ failed | ✅ passed | ✅ gate exists **and** precedes every build step, with a non-empty build-step check | ➖ |
| 4.4 T4 | same | Unit | ✅ 11/11 | ✅ failed | ✅ passed | ✅ exactly one cleanup step, `if: always()`, and the `.p8` deletion | ➖ |
| 4.5 T5 | same | Unit | ✅ 11/11 | ✅ failed | ✅ passed | ✅ every reference matched against an anchored shape, plus non-vacuity | ✅ the first draft pinned an exact count of 6 lines, which contradicts the design's deliberate per-step repetition; corrected to a floor, with the reason in the test |
| 4.6 T6 | same | Unit | ✅ 11/11 | ✅ failed | ✅ passed | ➖ single set-equality claim (a seventh secret fails it) | ➖ |
| 4.7 T15b | same | Unit | ✅ 11/11 | ✅ failed | ✅ passed | ✅ one `gh` invocation, its prefix, no `git`, and 6 forbidden literals | ➖ |
| 4.8 T16b | same | Unit | ✅ 11/11 | ✅ failed | ✅ passed | ✅ 2 forms | ➖ |
| 4.10 T12 | same | Unit | ✅ 19/19 | ➖ declared GREEN-on-arrival | ✅ passed first run | ✅ 4 extensions + a non-vacuity check that the group was actually walked | ➖ |
| 4.10 T13 | same | Unit | ✅ 19/19 | ➖ declared GREEN-on-arrival | ✅ passed first run (0.36 s over ~870 files) | ✅ 5 credential extensions + PEM header regex + `CODE_SIGN_ENTITLEMENTS`, with a scanned-file floor | ➖ |
| 5.1 T17b | same | Unit | ✅ 21/21 | ✅ failed | ✅ passed | ✅ the `1.0.0 (1)` fact **and** a single line carrying both override settings | ➖ |
| 5.2 T18 | same | Unit | ✅ 21/21 | ✅ failed | ✅ passed | ✅ 5 literal names | ➖ |

### Test summary

- Tests written: **23** distinct Swift Testing cases in one new file, three suites.
- Tests passing: **183 distinct / 0 failed** across `cellarTests` (23 new, 160 pre-existing).
- Layers used: Unit (23). Integration (0), E2E (0) — this slice adds no runtime behaviour to exercise.
- Approval tests: none — nothing was refactored; every production file here is net-new except two
  pbxproj lines and one string-catalog value.
- Pure functions created: 6 helpers on `ReleasePipelineSources` (`buildConfigurationBlocks`,
  `commandInvocations`, `workflowSteps`, `topLevelBlock`, `repositoryFiles`, `functionBody`), all
  deterministic text-over-input functions.

## Work Unit Evidence

| Unit | Commit | Focused test command and result | Runtime harness and result | Rollback boundary |
|---|---|---|---|---|
| 1 — arm64 pin | `1d2117f` `build(project): pin ARCHS to arm64 in both app-target blocks` | `-only-testing:cellarTests/ReleaseMetadataTests` → 3/3 passed | `xcodebuild build -scheme cellar` → `** BUILD SUCCEEDED **` | Revert 2 pbxproj lines; delete T11/T14/T17a |
| 2 — copyright | `8c289bd` `fix(app): stamp the human-readable copyright from the string catalog` | same suite → 5/5 passed | Built bundle's `en.lproj/InfoPlist.strings` → `"NSHumanReadableCopyright" => "Copyright © 2026 Juan Casanueva. All rights reserved."` (what Finder's inspector and the About window read) | Revert `cellar/InfoPlist.xcstrings`; delete T9/T10 |
| 3 — release script | `41a7208` `ci(release): add the local release script and Developer ID export options` | `-only-testing:…/ReleasePipelinePlacementTests …/ReleaseWorkflowContractTests` → 6/6 passed | `shellcheck scripts/release.sh` exit 0; `bash -n` exit 0; CLI guards measured: no phase → exit 1, unknown phase → exit 1, missing `VERSION` → exit 1, `package` without an export → exit 1. Full pipeline run deferred to U26 | Delete `scripts/`, revert the `.gitignore` line; delete T1/T7/T8/T15a/T16a |
| 4 — workflow | `e74ba5c` `ci(release): add the tag-triggered Developer ID release workflow` | same two suites → 17/17 passed | `actionlint .github/workflows/release.yml` exit 0, no output. A pipeline run is G3, blocked on U26 | Delete `.github/`; delete T2/T3/T4/T5/T6/T12/T13/T19/T15b/T16b |
| 5 — documentation | `d7c19c8` `docs(release): document the release pipeline and amend PRD and README` | `-only-testing:cellarTests` → **183 distinct passed / 0 failed** | `RELEASING.md` §3 read end to end as a runbook; every command in it corresponds to a real phase of `scripts/release.sh` or a real step of `release.yml` | Delete `RELEASING.md`; revert `PRD.md` + `README.md`; delete T17b/T18 |

No unit was marked complete with a failing focused test or a failing gate.

## Deviations from the design (all four are reported, none absorbed silently)

1. **The S10 sandbox gate is written as an explicit branch, not as `! codesign … | grep -q`.**
   The design's re-validation record replaced `grep -qv` (which can never fail) with a negated
   pipeline. Measured here: under `set -euo pipefail`, a bare `! pipeline` is **exempt from `set -e` by
   definition**, so it cannot fail the script either — a four-line probe with `! echo hit | grep -q hit`
   ran to completion and exited 0. The implemented form is
   `if codesign -d --entitlements :- "$VERIFIED_APP" 2>&1 | grep -q 'com.apple.security.app-sandbox';
   then fail …; fi` — the same negation, and the only version of it that actually gates. The reason is
   recorded in a comment in `scripts/release.sh`. T8 is unaffected: it pins `--entitlements :-`.

2. **T13's PEM check matches a complete header, `-----BEGIN <TYPE>-----`, not the bare prefix.**
   The design's literal wording ("no `-----BEGIN` PEM header anywhere in the repo") is already false at
   `e0b4803`: `design.md` and `tasks.md` both quote that bare prefix while describing M10's log scan. A
   guard that fires on documentation about itself is a guard someone deletes, so the pattern was
   tightened to the shape a real key always has. It still matches every real PEM blob and is strictly
   more precise than a substring search. The reason is in the test's doc comment.

3. **`.gitignore` gained one entry, `build/`.** The design states in two places that the release output
   directory is gitignored, and the threat matrix relies on it ("the pipeline writes only to `build/`
   (gitignored)"), but the entry did not exist. Three lines, including a comment. Not in the design's
   File Changes table; recorded here rather than left implicit.

4. **T5 asserts a floor of six secret-referencing lines, not exactly six.** The design deliberately
   repeats the three App Store Connect bindings per step rather than using YAML anchors, so an exact
   count contradicts the design it was meant to protect. The shape of every reference is still asserted
   line by line, and set equality over the *names* is T6's job. The reason is in the test.

Everything else matches the design as written, including the two-line pbxproj change, the 0-line
`INFOPLIST_KEY_NSHumanReadableCopyright` diff, the phase CLI, the export options, the workflow shape,
and the `RELEASING.md` section outline.

## Baseline discrepancy (for `sdd-verify` — measured, not resolved here)

The U29 probe recorded **141 distinct** `cellarTests` cases at `ec7b1c5`. The full run after this slice
reports **183 distinct passed / 0 failed**, of which **23** are the new cases in
`ReleasePipelineCompositionTests.swift` — leaving **160** pre-existing, not 141.

This slice cannot account for the 19-case gap: it adds exactly one test file, and
`git diff --stat ec7b1c5 HEAD` shows **zero** changed lines in `Packages/`, in every `.swift` file under
`cellar/`, in `Package.swift`, in `THIRD-PARTY.md` and in `cellarTests/SecurityCompositionSupport.swift`.
The most likely explanation is that the probe's count was taken from truncated output. The honest
statement is therefore: **183 distinct green, 0 failures, 23 of them new, no test anywhere went red.**
The G4 acceptance ("141 + the new cases") is reported as measured rather than reconciled.

> **Reconciled by `sdd-verify` (W2, 2026-08-23):** the U29 probe's 141 was an orchestrator line-range
> truncation, and the 160/183 above is one short because xcodebuild tore a single
> `Test case '…' passed` line in half across concurrent output, which a line-oriented `sort -u` drops.
> Correct figures: **161 pre-existing + 23 new = 184 distinct test functions passed / 0 failed**, over
> 194 case executions (parameterized cases expand). Every "183"/"160" in this file should be read as
> 184/161.

CellarCore was **not** re-run: this slice adds no CellarCore code and the 0-line diff above is the
proof the design asked for. `swift test --package-path Packages/CellarCore` remains at its measured
1732/1732.

## Blocked — Phase 6 and the maintainer checklist

Re-measured at apply time: `security find-identity -v -p codesigning` lists exactly one identity,
`Apple Development: Juan Casanueva (A8EB4839B9)` — **1 valid identity found**. There is no Developer ID
Application certificate and no App Store Connect API key on this machine.

| Item | Reason |
|---|---|
| P1–P6 | Maintainer actions: the public flip, the certificate, the ASC key, the six secrets, Actions permissions |
| 6.1 gate | P1–P5 are not complete |
| 6.2 `U26` (M1–M4, M6, M7) | Blocked on P2 + P3 — no certificate, no ASC key |
| 6.3 Manual-signing fallback | **Must not be applied**: it requires an explicit maintainer approval *and* a measured U26 failure. Neither exists |
| 6.4 `U28` / M8, and `RELEASING.md` §6 evidence | Follows 6.2. §6 is committed as a clearly marked placeholder that asserts no unmeasured output |
| 6.5 ci-gate G3 (dry-run prerelease) | No tag may be pushed before 6.2 is green; also needs P1 and P4 |
| 6.6 M5 + M10 | Follow a real published run |
| 6.7 M9 | Deferred by definition — nothing to compare against before the second release |
| 6.8 Optional hardening | Carried as notes; the design records "none required" |

The Phases 1–5 PR may merge with all of this open — the pipeline is inert until a tag is pushed.

## Changed lines, by bucket, against the forecast

Against `main` (`ec7b1c5`), excluding this file:

| Bucket | Forecast (bottom-up) | Actual |
|---|---|---|
| `cellar.xcodeproj/project.pbxproj` | 2–4 | **2** |
| `.github/workflows/release.yml` | 160–260 | **125** |
| `scripts/release.sh` + `ExportOptions.plist` | 100–180 | **308** |
| `cellarTests/ReleasePipelineCompositionTests.swift` | 200–320 | **771** |
| Docs (`RELEASING.md` 247, README 19, PRD 14, `InfoPlist.xcstrings` 4, `.gitignore` 3) | 190–290 | **287** |
| **Authored subtotal** | 652–1,054 bottom-up → 1,240–2,425 corrected | **1,493** |
| In-repo SDD artifacts (`explore` 603, `design` 567, `proposal` 377, `spec` 373, `tasks` 284) | 350–550 | **2,204** |
| **PR total** | ~1,590–2,975 | **3,697** (3,688 insertions + 9 deletions) |

The authored total lands mid-band inside the corrected 1,240–2,425 forecast. The overshoot against the
PR-total ceiling is **entirely** the SDD artifact bucket, which was forecast at 350–550 and is 2,204 —
the forecast under-counted documents that were already written and committed at `e0b4803`, before this
phase started. Against the governing **5,000-line** budget the PR sits at 3,697 with ~1,300 lines of
headroom, so `single-pr` still holds and **no `size:exception` is needed**. Reviewer-facing authored
code and docs are 1,493 lines across 11 files, in five self-contained commits.

## Commits

| # | Hash | Message |
|---|---|---|
| 1 | `1d2117f` | `build(project): pin ARCHS to arm64 in both app-target blocks` |
| 2 | `8c289bd` | `fix(app): stamp the human-readable copyright from the string catalog` |
| 3 | `41a7208` | `ci(release): add the local release script and Developer ID export options` |
| 4 | `e74ba5c` | `ci(release): add the tag-triggered Developer ID release workflow` |
| 5 | `d7c19c8` | `docs(release): document the release pipeline and amend PRD and README` |

No push, no pull request, no review started, no receipt created. Conventional-commit subjects, no
co-authorship trailer and no automation attribution of any kind.
