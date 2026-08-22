```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:fb03271f044c6391dad81f28589d97f55d67a1509066663412d91db1c1e36fd8
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 8/8
scenarios: 29/29
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:5bd6d8fe08323e2c6bbca649b07e60c99a745de14cc8bc65b039c20c00b92fec
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -quiet
build_exit_code: 0
build_output_hash: sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

## Verification Report

**Change**: `m6-release-pipeline`
**Version**: `specs/release-distribution/spec.md` — ADDED-only delta, 8 requirements / 29 scenarios
**Mode**: Strict TDD
**Branch**: `feature/m6-release-pipeline` @ `f993ecf` · base `e0b4803` (SDD artifacts only) on `main` `ec7b1c5`
**Verifier**: independent — no code was fixed, no review started, no receipt created, nothing committed. RDD disabled.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`,
`artifact_store=hybrid` (OpenSpec files + Engram, canonical project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

### What the envelope counts mean

`requirements: 8/8` and `scenarios: 29/29` mean **every scenario is discharged at the verification
class the spec itself declares for it** — not that every scenario has been executed. The spec declares
three classes and this slice is infrastructure, so the split matters more than the total:

| Class | Count | What "discharged" means here | Result |
|---|---|---|---|
| `unit` | 13 | A test in `cellarTests` passed at runtime, and was shown able to fail | **13/13 runtime-proven** |
| `ci-gate` | 12 | The gate exists in `release.sh` / `release.yml` and reads the property the scenario claims | **12/12 structurally verified, execution pending U26/G3** |
| `manual-evidence` | 4 | The exact command and its exact accepted output are documented so a maintainer can produce them | **4/4 documented, evidence pending** |

The 12 `ci-gate` scenarios cannot be executed on this machine: there is no Developer ID Application
certificate and no App Store Connect API key. Re-measured independently during this verification —
`security find-identity -v -p codesigning` returns exactly one identity,
`Apple Development: Juan Casanueva (A8EB4839B9)`, `1 valid identities found`. Per the spec's own
verification-class contract those are **not failures**; they are the declared, pre-agreed shape of an
infrastructure slice. They are also the reason this report is `pass_with_warnings` and not `pass`.

### Completeness

| Metric | Value |
|---|---|
| Tasks total (Phases 0–5) | 35 |
| Tasks complete (Phases 0–5) | 35 |
| Tasks incomplete (Phase 6) | 8 |
| Maintainer prerequisites incomplete | 6 (P1–P6) |

Phases 0–5 are 35/35 checked and every checked task matches the code state on disk — verified
item by item, not taken on trust. Phase 6 and P1–P6 are unchecked **by design**: proposal, spec,
design and tasks all declare them non-merge-blocking and blocked on maintainer prerequisites that do
not exist on this machine. See WARNING W3.

### Build & Tests Execution

**Build**: ✅ Passed — exit `0`, no output under `-quiet`.

```text
xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -quiet
BUILD_EXIT=0
```

**Tests**: ✅ **184 distinct test functions passed / 0 failed** (194 total case executions).

```text
xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
** TEST SUCCEEDED **   exit 0
```

`cellarUITests` was not run, as instructed. `swift test --package-path Packages/CellarCore` was not
re-run: `git diff --name-only ec7b1c5 HEAD -- Packages/` is empty, which is the 0-diff proof the
design asked for. CellarCore remains at its measured 1732/1732.

**Coverage**: ➖ Not available — no coverage tool configured for this project.

#### Baseline reconciliation — the ±1 is resolved, and 161 is the right number

The launch brief asked for the ±1 between `git grep -c '@Test' main -- cellarTests` (161) and apply's
"160 pre-existing" to be reconciled. It is, and the cause is a **counting hazard, not a missing test**.

| Measurement | Value | Method |
|---|---|---|
| `@Test` declarations on `main` (`cellarTests`) | **161** | `git grep -c '@Test' main -- cellarTests`, summed; independently re-derived as 161 line-anchored `^\s*@Test` declarations across 16 files, with **zero** duplicate suite/function ids |
| Distinct pre-existing ids observed in this run | 160 | naive line-oriented `rg -o … \| sort -u` |
| Distinct pre-existing ids actually present | **161** | byte-oriented regex over the whole log, ignoring line boundaries |
| New ids in `ReleasePipelineCompositionTests.swift` | **23** | 23 `@Test` declarations, 23 observed |
| **Total distinct test functions after this slice** | **184** | 161 + 23 |
| **Total case executions** | **194** | 3 parameterized functions expand to 13 cases (4 + 5 + 4) |

The missing id is `BrewfileExportCompositionTests/aFailedDumpNeverOpensAPanelAndNeverWrites()`. Its
output line was **torn in half by interleaved xcodebuild logging** — the log literally contains
`Test case 'BrewfileExportCompositionTests/aF`, then several `IDETestOperationsObserverDebug` lines,
the `.xcresult` path and `** TEST SUCCEEDED **`, and only then
`ailedDumpNeverOpensAPanelAndNeverWrites()' passed`. A line-oriented counter drops it; a byte-oriented
one finds it. The test ran and passed.

So: **161 is right**, apply's 160 was one short for the same reason U29's 141 was twenty short
(orchestrator obs 7668 already corrected 141 → 161 by full-log recount). The three counts now agree.
The parameterized expansion (194 executions vs 184 functions) is the second reason raw
`Test case` occurrence counts drift; both hazards are recorded in W2.

### Static gates

| Gate | Command | Exit | Output |
|---|---|---|---|
| G1 | `actionlint .github/workflows/release.yml` (`actionlint 1.7.12`) | **0** | none |
| G2 | `shellcheck scripts/release.sh` (`ShellCheck 0.11.0`) | **0** | none |
| — | `bash -n scripts/release.sh` | **0** | none |
| G4 | `xcodebuild test … -only-testing:cellarTests` | **0** | `** TEST SUCCEEDED **`, 184/0 |
| G3 | dry-run prerelease tag | — | **not run** — blocked on U26 + P1 + P4 |

### Spec Compliance Matrix

`R#` = requirement. `Class` = the verification class the spec declares. Test ids are in
`cellarTests/ReleasePipelineCompositionTests.swift` unless noted.

| R | Scenario | Class | Evidence | Result |
|---|---|---|---|---|
| 1 | S1 A tag produces one correctly named, anonymously reachable asset | `ci-gate` | `release.yml:116-117` `gh release create "$GITHUB_REF_NAME" "build/Home-Cellar-${VERSION}.zip"` — exactly one asset; `VERSION=${GITHUB_REF_NAME#v}` at `:40`. No CI reachability assertion (see SUGGESTION G1) | ⚠️ Structurally verified, execution pending U26/G3 |
| 1 | S2 The bundle inside the zip is `cellar.app` / `Home-Cellar` | `ci-gate` | `release.sh:244-246` `plutil -extract CFBundleDisplayName raw` == `Home-Cellar`; the zip is `ditto --keepParent "$APP"` with `APP=build/export/cellar.app` (`:48`) | ⚠️ Structurally verified, execution pending |
| 1 | S3 Nothing but a version tag can trigger a release | `unit` | `onlyAVersionTagTriggersTheWorkflow()` ✅ — asserts `push:`/`tags:`/`'v*'` inside the `on:` block, and the absence of `pull_request:`, `schedule:`, `workflow_dispatch:`, `branches:` and `xcodebuild test`. **Mutation-proven**: injecting `workflow_dispatch:` made it fail | ✅ COMPLIANT |
| 1 | S4 A private repository fails fast | `ci-gate` (+ `unit` T19) | `release.yml:25-29` is step 1, `if: ${{ github.event.repository.private }}` → `exit 1`. `privateRepositoryFailsFastBeforeAnyBuildStep()` ✅ proves it precedes **every** step referencing `scripts/release.sh`, with a non-empty build-step check | ✅ Structurally COMPLIANT; runtime unreachable by design |
| 2 | S5 A version mismatch stops the run before Apple sees the build | `ci-gate` | `release.sh:144-146` `expect_equal … CFBundleShortVersionString == $VERSION` inside `phase_export`, which `main` orders strictly before `phase_notarize` (`:284-291`) | ⚠️ Structurally verified, execution pending |
| 2 | S6 The tag and run number reach the delivered bundle | `ci-gate` | `release.sh:238-243` both `plutil -extract` checks against `$VERIFY_DIR` (the copy extracted from the published zip); `release.yml:40-41` supplies `VERSION` and `BUILD_NUMBER=${GITHUB_RUN_NUMBER}` | ⚠️ Structurally verified, execution pending |
| 2 | S7 `CFBundleVersion` never goes backwards | `manual-evidence` | M9 documented in `design.md` and `tasks.md:6.7`; mechanism stated in `RELEASING.md` §4. Checkable only from the second published release | ⚠️ Evidence pending (deferred by definition) |
| 2 | S8 Releasing does not edit the project file, and the cost is documented | `unit` | `appTargetsKeepCheckedInVersionAndRuntimePosture()` ✅ (`MARKETING_VERSION = 1.0.0;`, `CURRENT_PROJECT_VERSION = 1;` — 2 matches each) + `runbookRecordsTheVersionPolicyAndItsOverride()` ✅ (`1.0.0 (1)` literal and a **single line** carrying both overrides). **Mutation-proven**: removing the `1.0.0 (1)` literal made T17b fail | ✅ COMPLIANT |
| 3 | S9 The delivered binary is single-architecture | `ci-gate` | `release.sh:147-149` (pre-notarize) and `:235-237` (post-extract) `lipo -archs` == `arm64`. Cause pinned by `appTargetsPinARM64()` ✅ | ⚠️ Structurally verified, execution pending (M7) |
| 3 | S10 The delivered bundle is hardened and unsandboxed | `ci-gate` | `release.sh:219` `grep -q 'flags=0x10000(runtime)'`; `:229-233` sandbox-absence as an explicit `if` branch over captured output. Blast radius pinned by `appTargetsKeepCheckedInVersionAndRuntimePosture()` ✅ (`ENABLE_APP_SANDBOX = NO;`, `ENABLE_HARDENED_RUNTIME = YES;`) | ⚠️ Structurally verified, execution pending |
| 3 | S11 No entitlements file exists anywhere in the repository | `unit` | `repositoryCarriesNoCredentialMaterial()` ✅. Independently re-swept: `fd -H -e entitlements` → none; `CODE_SIGN_ENTITLEMENTS` absent from `project.pbxproj` | ✅ COMPLIANT |
| 3 | S12 The rationale names what is absent and why | `unit` | `runbookNamesTheAbsentEntitlements()` ✅ — all five literals. Independently read: `RELEASING.md` §6 names `allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation` with the `posix_spawn`-separate-process reason, and explains `ENABLE_USER_SELECTED_FILES` / `REGISTER_APP_GROUPS` under a disabled sandbox | ✅ COMPLIANT |
| 3 | S13 A hardened, notarized, stapled build still drives Homebrew | `manual-evidence` | M8 documented (`design.md` Tier 4, `tasks.md:6.4`). `RELEASING.md` §6 carries a **clearly marked placeholder** that asserts no unmeasured output | ⚠️ Evidence pending (blocked on U26) |
| 4 | S14 The published artifact passes assessment offline | `ci-gate` | `release.sh:212-213` `spctl -a -vvv -t install` + `xcrun stapler validate`, both against `$VERIFIED_APP`. The **offline** half is not established by CI (see WARNING W4) | ⚠️ Structurally verified; offline property rests on M3 |
| 4 | S15 The signature is the expected Developer ID identity | `ci-gate` | `release.sh:220-221` `grep -q 'Authority=Developer ID Application'` and `grep -q "TeamIdentifier=$TEAM_ID"` with `TEAM_ID="Z3S5JK8E38"` (`:30`) | ⚠️ Structurally verified, execution pending |
| 4 | S16 A stranger's first launch is a single "Open" | `manual-evidence` | M5 documented (`design.md` Tier 4, `tasks.md:6.6`) incl. the `xattr -p com.apple.quarantine` precondition | ⚠️ Evidence pending |
| 5 | S17 A failed gate publishes nothing at all | `ci-gate` | Every gate is a `fail`/`exit 1` under `set -euo pipefail` (`release.sh:28`), and every gate step precedes `Publish GitHub Release` (`release.yml:104`). Notarization failure surfaces `notarytool log` to stderr then fails (`release.sh:175-185`) | ⚠️ Structurally verified, execution pending |
| 5 | S18 Prior releases survive the next one untouched | `ci-gate` | Only `gh release create` exists; `theWorkflowCanOnlyEverCreateARelease()` ✅ asserts exactly one `gh` invocation with that prefix and none of the six forbidden literals | ✅ Structurally COMPLIANT (unit-pinned) |
| 5 | S19 Nothing in the repository can retract a release | `unit` | `theWorkflowCanOnlyEverCreateARelease()` ✅ + `releaseScriptCannotPublishOrSelectARepository()` ✅ | ✅ COMPLIANT |
| 5 | S20 The local path rehearses but cannot publish | `unit` | `releaseScriptCarriesTheWholeSequence()` ✅ (11 commands + 3 `plutil` keys + the `Contents/` guard + `set -euo pipefail`), `stapleDeletesTheArchiveBeforeRepackaging()` ✅ (**positional**: staple < `rm -f` < repackage), `releaseScriptCannotPublishOrSelectARepository()` ✅. **Mutation-proven**: inserting `git status --porcelain` into `release.sh` made T15a fail, and correctly did **not** disturb the workflow-scoped test | ✅ COMPLIANT |
| 6 | S21 The infrastructure is where it belongs, and nowhere else | `unit` | `releaseScriptAndExportOptionsExist()` ✅ (incl. `isExecutableFile`; git mode confirmed `100755`), `releaseWorkflowExists()` ✅, `appSourcesCarryNoReleaseInfrastructure()` ✅ (with a non-vacuity floor). Independently: the only file changed under `cellar/` is `InfoPlist.xcstrings` | ✅ COMPLIANT |
| 6 | S22 The export configuration declares Developer ID distribution | `unit` | `exportOptionsDeclareDeveloperIDDistribution()` ✅ — **parsed** via `PropertyListSerialization`, not grepped: `developer-id` / `automatic` / `Z3S5JK8E38` | ✅ COMPLIANT |
| 6 | S23 None of it ships to the user | `ci-gate` | `release.sh:251-258` `find "$VERIFIED_APP/Contents" \( -name '*.yml' -o -name '*.yaml' -o -name '*.sh' -o -name 'ExportOptions*.plist' \)` → non-empty result exits 1. Presence of the guard unit-pinned by T8 | ⚠️ Structurally verified, execution pending |
| 7 | S24 The repository carries no secret material | `unit` | `repositoryCarriesNoCredentialMaterial()` ✅ (`scanned > 100` non-vacuity floor). Independently re-swept: no `.p12`/`.p8`/`.cer`/`.mobileprovision` anywhere; zero complete PEM headers in the tree | ✅ COMPLIANT |
| 7 | S25 Credential cleanup cannot be skipped by a failure | `unit` | `keychainDeletionRunsUnconditionally()` ✅ — exactly one step contains `security delete-keychain`, and **that step** also contains `if: always()` and `asc.p8` (step-scoped, not a bare substring pair) | ✅ COMPLIANT |
| 7 | S26 No step traces its own commands around a credential | `unit` | `secretsAppearOnlyAsEnvironmentBindings()` ✅ (every one of the 10 `secrets.` lines matches the anchored `^[A-Z0-9_]+: \$\{\{ secrets\.[A-Z0-9_]+ \}\}$` shape), `workflowReferencesExactlyTheExpectedSecrets()` ✅ (**set equality** over the six names), `releaseScriptNeverTracesCommands()` ✅, `workflowNeverTracesCommands()` ✅ | ✅ COMPLIANT |
| 7 | S27 A completed run's log contains nothing sensitive | `manual-evidence` | M10 documented with its exact `rg` pattern set and the `rm -f` afterwards so the check is not itself the leak (`design.md` Tier 4, `tasks.md:6.6`) | ⚠️ Evidence pending |
| 8 | S28 The copyright string is present and correct | `unit` | `bundleReportsCopyright()` ✅ reads `Bundle.main.localizedInfoDictionary`. **Independently confirmed against the built bundle**: `plutil -p …/cellar.app/Contents/Resources/en.lproj/InfoPlist.strings` → `"NSHumanReadableCopyright" => "Copyright © 2026 Juan Casanueva. All rights reserved."`, and `plutil -extract NSHumanReadableCopyright raw …/Contents/Info.plist` → **no value at that key path**, exactly as U27 measured. **Mutation-proven**: blanking the catalog value made the test fail | ✅ COMPLIANT — genuinely runtime-verified |
| 8 | S29 The string catalog is the single authority for it | `unit` | `stringCatalogIsTheOnlyCopyrightAuthority()` ✅ — catalog value + `state: translated` + both bundle-name keys still present + **both** pbxproj blocks carry exactly `INFOPLIST_KEY_NSHumanReadableCopyright = "";`. **Mutation-proven** | ✅ COMPLIANT |

**Compliance summary**: 13/13 `unit` COMPLIANT · 12/12 `ci-gate` structurally verified (execution
pending U26/G3) · 4/4 `manual-evidence` documented (evidence pending). **0 UNTESTED, 0 FAILING.**

### Failability spot-checks (mutation testing)

The brief asked for at least three. Seven assertions were checked, in two runs, by mutating a scratch
copy of the implementation and observing which tests turn red. **Every mutation produced exactly the
expected failure and no collateral failure.** The working tree was restored to clean after each run
(`git status --porcelain` empty, `git diff --stat` empty).

| # | Mutation | Expected to fail | Observed |
|---|---|---|---|
| A1 | Add `workflow_dispatch:` to the `on:` block | `onlyAVersionTagTriggersTheWorkflow()` | ✅ failed; 18 others passed |
| A2 | Replace the `1.0.0 (1)` literal in `RELEASING.md` | `runbookRecordsTheVersionPolicyAndItsOverride()` | ✅ failed |
| A3 | Insert `git status --porcelain` into `release.sh` | `releaseScriptCannotPublishOrSelectARepository()` | ✅ failed — and `theWorkflowCanOnlyEverCreateARelease()` correctly did **not**, because it is workflow-scoped |
| B1 | Delete `ARCHS = arm64;` from the **Release** block only | `appTargetsPinARM64()` | ✅ failed |
| B2 | (same mutation) | `appTargetConfigurationsAreIdenticalModuloName()` | ✅ failed — the Debug/Release identity pin is live |
| B3 | Blank the catalog copyright value | `stringCatalogIsTheOnlyCopyrightAuthority()` | ✅ failed |
| B4 | (same mutation) | `bundleReportsCopyright()` | ✅ failed — **the catalog → compiled `InfoPlist.strings` → `localizedInfoDictionary` path is real**, not a constant compared to itself |

B4 is the important one: it is the only proof that S28 is a statement about a delivered value rather
than about a string literal appearing twice in the same file.

### Correctness (static evidence)

| Requirement | Status | Notes |
|---|---|---|
| R1 tag → downloadable release | ✅ Implemented | Tag-only trigger, single correctly named asset, private-repo fail-fast as step 1 |
| R2 tag is the version | ✅ Implemented | Both values injected at build time; pbxproj stays `1.0.0 / 1`; cost documented with a working override |
| R3 arm64, hardened, unsandboxed, no entitlement | ✅ Implemented | Pin in both blocks; two `lipo` gates; no `.entitlements` anywhere; written rationale |
| R4 Gatekeeper accepts the downloaded artifact | ✅ Implemented | Gates run on the copy extracted from the published zip; staple precedes repackage |
| R5 all-or-nothing, history never rewritten | ✅ Implemented | Every gate precedes publish; only `gh release create` exists |
| R6 infrastructure outside the shipped sources | ✅ Implemented | `scripts/`, `.github/`, `RELEASING.md` at repo root; enforced by test, not comment |
| R7 no credential material, injected credentials die with the run | ✅ Implemented | Six secrets, env-binding-only, `chmod 600`, `if: always()` deletion of keychain **and** `.p8` |
| R8 the build states who made it | ✅ Implemented | Catalog is the single authority; confirmed in the built bundle |

### Requested structural checks (1–10 from the launch brief)

| # | Check | Result |
|---|---|---|
| 1 | pbxproj diff is exactly two `ARCHS = arm64;` insertions | ✅ `git diff ec7b1c5 HEAD -- …/project.pbxproj` → `2 insertions(+)`, nothing else moved. Debug/Release `buildSettings` are 28 keys each with an **empty symmetric difference**. `INFOPLIST_KEY_NSHumanReadableCopyright = "";` unchanged at both `:432` and `:466`. No `.entitlements`, no `CODE_SIGN_ENTITLEMENTS` |
| 2 | Copyright only in `cellar/InfoPlist.xcstrings`; T10 reads `localizedInfoDictionary` | ✅ Confirmed, and independently verified against a real build (see S28 row). Raw `Info.plist` key is absent, so the `localizedInfoDictionary` choice is load-bearing rather than stylistic |
| 3 | Nothing changed under `cellar/` except the xcstrings; nothing under `Packages/` | ✅ Only `cellar/InfoPlist.xcstrings`. `Packages/`, `Package.swift`, `THIRD-PARTY.md`, `cellarTests/SecurityCompositionSupport.swift`, `cellar.xcodeproj/xcshareddata` and every `.swift` under `cellar/` are 0-line diffs. `scripts/`, `.github/`, `RELEASING.md` at repo root; `.gitignore` gained `build/` |
| 4 | `release.sh` shape and the sandbox gate | ✅ `set -euo pipefail` at `:28`; seven phases; **zero** `gh`/`git` command tokens; `rm -f "$ZIP"` at `:197` strictly between `stapler staple` and the re-`ditto`; the sandbox gate captures into `entitlements` at `:230` **then** greps inside an `if` at `:231`. Mode `100755` |
| 5 | `release.yml` shape | ✅ `push:`/`tags: ['v*']` only · `permissions: contents: write` · `concurrency` with `cancel-in-progress: false` · private-repo fail-fast first · `xcode-select -s /Applications/Xcode_26.6.app` · ephemeral keychain · `if: always()` cleanup of keychain **and** `.p8` **and** `.p12` · exactly six secret names, all as `env:` right-hand sides · no YAML anchors (only the comment explaining their absence) · no `set -x` · `gh release create … --verify-tag --generate-notes` |
| 6 | `RELEASING.md` contents | ✅ §2 prerequisites incl. the public flip and all six secrets named · §3 runbook · §4 version policy with the literal `1.0.0 (1)` and a single-line override · §6 entitlements rationale naming all five settings · §7 follow-up contract for `m6-sparkle-updates` / `m6-cask-tap` · §7 `No App Category` follow-up · §5 rehearsal example now carries the ASC vars for `all` **and** a key-free `archive`-only variant (added by `f993ecf`) |
| 7 | PRD/README amendments match the design's line table | ✅ All seven PRD lines (`:9`, `:157`, `:168`, `:187`, `:212`, `:224`, `:227`) rewritten in place with the reason, using the design's wording — including the required `:227` phrasing "was being contradicted by the build … shipping universal by accident". No contradiction with PRD §6 (the tip-jar bullet is byte-identical; Cellar stays free with no payment surface) or with §4.3 (the appcast row gains a pointer only). README gains `## Install` between Requirements and Building, and `## Releasing` after Building |
| 8 | Declared deviations judged | ✅ Five judged below — all justified, one follow-up |
| 9 | Size | ✅ Authored **1,502** changed lines (1,493 + / 9 −) across 10 files, mid-band inside the corrected 1,240–2,425 forecast. SDD artifacts 2,422. **PR total 3,924 vs the governing 5,000 budget — 1,076 lines of headroom.** `single-pr` holds, no `size:exception` |
| 10 | Open risks carried | ✅ Listed below |

### Coherence (design)

| Decision | Followed? | Notes |
|---|---|---|
| DD-1 workflow owns secrets; script owns the build, one phase per named step | ✅ Yes | 14 named steps, six of them exactly one per `release.sh` phase |
| DD-2 `release.sh <phase>` CLI incl. `all` | ✅ Yes | Unknown or missing phase → usage + `exit 1` |
| DD-3 gates run twice (pre-notarize and post-extract) | ✅ Yes | `phase_export:144-149` and `phase_verify:235-246` |
| DD-4 ASC key serves `notarytool` + `xcodebuild` | ✅ Yes | `configure_signing()` |
| DD-5 `SIGNING_STYLE` selects the flags | ✅ Yes | Default `automatic`; invalid value fails loudly |
| DD-6 `.p8` at `$RUNNER_TEMP`, `chmod 600`, `if: always()` deletion | ✅ Yes | `release.yml:62-63`, `:121-125` |
| DD-7 prerelease derived from a hyphen in the tag | ✅ Yes | `release.yml:110` |
| DD-8 no delete/edit/push/tag/commit | ✅ Yes | Unit-asserted |
| DD-9 `ARCHS` in **both** blocks | ✅ Yes | Identity invariant preserved and now pinned |
| DD-10 Manual fallback is a separate approved amendment | ✅ Yes | **Not applied** — correctly, since U26 has no measured result |
| Design's `verify` pseudo-code for the S10 sandbox gate | ⚠️ **Deviated, correctly** | See deviation 1 and WARNING W1 |

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | Full "TDD Cycle Evidence" table in `apply-progress.md`, 23 rows |
| All tasks have tests | ✅ | Every `unit` task maps to a named test that exists |
| RED confirmed (tests exist) | ✅ | 23/23 test functions present in the single new file |
| GREEN confirmed (tests pass) | ✅ | 23/23 pass on independent re-execution |
| RED was real (can the tests fail?) | ✅ | 7 assertions mutation-proven failable; 0 false greens found |
| Triangulation adequate | ✅ | Every claimed count re-derived and correct; multi-case suites carry non-vacuity floors |
| Safety Net for modified files | ✅ | Two production files modified (pbxproj, xcstrings); both carry a passing prior suite in the recorded chain |
| GREEN-on-arrival declarations honest | ✅ | T12, T13, T14, T17a were true at `ec7b1c5` and are authored in the same commit as the files they guard |

**TDD Compliance**: 8/8 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit | 23 | 1 | Swift Testing |
| Integration | 0 | 0 | not applicable — this slice adds no runtime behaviour |
| E2E | 0 | 0 | not applicable |
| **Total (new)** | **23** | **1** | |

Whole-suite context: 184 distinct functions / 194 case executions across `cellarTests`, all Swift Testing.

### Changed File Coverage

Coverage analysis skipped — no coverage tool detected for this project. The two production files
changed are a `.pbxproj` and a `.xcstrings`; neither is executable code, and both are asserted
directly by tests that were shown able to fail.

### Assertion Quality

Every assertion in `cellarTests/ReleasePipelineCompositionTests.swift` was audited against the banned
patterns. **No tautologies, no assertion that never touches the thing it claims about, no ghost loops,
no smoke-test-only cases, no mocks at all (0 mocks / 83 assertion calls — 66 `#expect`, 17 `#require`).**

Notably, the file goes *beyond* the bar in four places, each of which defeats a specific way a
structural test can silently stop testing:

| Guard | Where | What it prevents |
|---|---|---|
| Non-vacuity on an equality | `appTargetConfigurationsAreIdenticalModuloName()` `:228` | Two empty lists comparing equal |
| Non-vacuity on a directory walk | `appSourcesCarryNoReleaseInfrastructure()` `:416` (`files.count > 10`) | A scan that found nothing because it walked nothing |
| Non-vacuity on a repo-wide sweep | `repositoryCarriesNoCredentialMaterial()` `:457` (`scanned > 100`) | An absence proved by reading zero files |
| Positive control on an absence matcher | `releaseScriptCannotPublishOrSelectARepository()` `:565` | A broken regex "proving" that `gh`/`git` are absent — the same matcher is required to *find* `xcodebuild` |

`commandInvocations(of:in:)` also deserves a note: it matches command **tokens** (start-of-line or
after `[\s;|&(]`, followed by whitespace or end-of-line), not substrings, so it does not fire on
`through`, `enough` or `gitignored`. That is why the prohibition survived a `RELEASING.md` and a
`release.sh` header that both discuss git and gh in prose.

**Assertion quality**: ✅ All assertions verify real behaviour. 0 CRITICAL, 0 WARNING.

### Quality Metrics

**Linter (shell)**: ✅ `shellcheck 0.11.0` — no findings, exit 0
**Linter (workflow)**: ✅ `actionlint 1.7.12` — no output, exit 0
**Syntax**: ✅ `bash -n scripts/release.sh` — exit 0
**Type checker**: ✅ `xcodebuild build` — exit 0, no warnings surfaced under `-quiet`

### Deviations from the design — judged

| # | Deviation | Judgement |
|---|---|---|
| 1 | The S10 sandbox gate is an explicit `if` branch over captured output, not `! codesign … \| grep -q` | **JUSTIFIED — and strictly better than the design.** Three separate defects, all real: (a) `grep -qv PATTERN` returns 0 as soon as *any single line* fails to match, and multi-line `codesign` output guarantees one, so that form can never fail; (b) bash's `set -e` **explicitly exempts** a command whose status is inverted by `!`, so `! pipeline` cannot terminate the script either — the apply agent measured this with a four-line probe; (c) even as a bare pipeline, `grep -q` closes the pipe on its first match, so under `pipefail` a **real** match becomes SIGPIPE/141 and the gate reads as a pass. Capturing into `entitlements` first (`f993ecf`) removes (c); the `if` branch removes (a) and (b). This is the only one of the four forms that actually gates. **Follow-up required**: `design.md:246-247` and its *Re-validation record* item (A) still prescribe the broken form — see WARNING W1 |
| 2 | T13 matches a complete PEM header `-----BEGIN <TYPE>-----`, not the bare prefix | **JUSTIFIED.** Independently confirmed: `design.md` and `tasks.md` both quote the bare prefix while describing M10, so the design's literal wording was unsatisfiable the moment it was written. The tightened pattern still matches every real key blob and is strictly more precise. Verified: zero complete PEM headers in the tree |
| 3 | `.gitignore` gained `build/` (3 lines incl. a comment) | **JUSTIFIED — and it was required, not optional.** The design's own threat matrix rates the *commit state* row "N/A — asserted, not assumed: the pipeline writes only to `build/` (gitignored)", and that entry did not exist. Without it the first local rehearsal would offer a 16 MB `.app` to `git add`. The only fault is bookkeeping: it belonged in the design's File Changes table |
| 4 | T5 asserts a floor of six secret-referencing lines, not exactly six | **JUSTIFIED.** Measured: there are **10** such lines, because DD-1 deliberately repeats the three ASC bindings per step instead of using YAML anchors. An exact count of six would have failed the very design it was written to protect. The *shape* of all 10 is still asserted line by line against an anchored regex, and exactness over the **names** is T6's job, which uses set equality |
| 5 | The `actions/checkout@v4` step was given a name ("Check out the tagged commit") | **JUSTIFIED (minor).** `workflowSteps(in:)` splits on `- name:` boundaries; an unnamed step is silently absorbed into the previous step's body, which would make step-scoped assertions quietly weaker. Naming it keeps the split honest. No behavioural change |

### Issues Found

**CRITICAL**: None.

**WARNING**

- **W1 — `design.md` still prescribes a shell pattern now known not to gate.** `design.md:246-247`
  and its *Re-validation record* item (A) both present `! codesign -d --entitlements :- "$V" 2>&1 |
  grep -q 'com.apple.security.app-sandbox'` as the **corrected** S10 gate. It is not corrected; it is
  the second of the three broken forms in deviation 1. The shipped `release.sh` is right and the
  design is wrong. This does not affect the delivered artifact, but archiving would promote a design
  document that teaches a non-gating idiom to the next slice that copies it.
  **Recommended action at archive**: amend `design.md` to the implemented `if` form and record the
  `set -e`/`!` exemption and the `pipefail`/SIGPIPE hazard as the reason.
- **W2 — the recorded test baseline is one short, and the counting method is fragile.**
  `apply-progress.md` records "183 distinct passed / 160 pre-existing". Measured here: **161**
  pre-existing + 23 new = **184 distinct functions**, over **194 case executions**. Two independent
  hazards produce the drift: a torn stdout line (documented above) and parameterized-test expansion.
  Nothing is wrong with the code; the number in the artifact is.
  **Recommended action at archive**: record 184 distinct / 194 executions / 0 failed, and note that
  distinct-id counting must be byte-oriented rather than line-oriented.
- **W3 — Phase 6 (8 tasks) and the maintainer checklist P1–P6 are unchecked.** Normally unchecked
  tasks are CRITICAL. They are downgraded here because all four upstream artifacts declare them
  non-merge-blocking and blocked on prerequisites that provably do not exist on this machine —
  re-measured independently: one identity, `Apple Development`, no Developer ID Application
  certificate, no ASC key. The consequence must not be softened: **12 `ci-gate` and 4
  `manual-evidence` scenarios — 16 of 29 — have never been executed against a real build.** This
  change is safe to merge and is **not** safe to treat as a proven release pipeline.
- **W4 — S14's "offline" property is not established by the gate that claims it.** The CI `spctl -a
  -vvv -t install` runs on a networked runner, so it can be satisfied by an online Gatekeeper lookup;
  only manual evidence M3 (networking disabled) proves the stapled-offline claim. The design's
  validator already raised this as suggestion (D) and `tasks.md:6.8` carries it as *optional*
  hardening, which is why it is a warning rather than a defect. `RELEASING.md` §3 currently says
  "Eight gates" with no such caveat.
  **Recommended action**: state in `RELEASING.md` that the CI assessment runs online and that S14's
  offline claim rests on M3.

**SUGGESTION**

- **G1 — close S1 in CI rather than by observation.** S1 claims the asset is "downloadable from the
  documented URL without authentication"; nothing asserts it. A post-publish
  `curl -fsSI "https://github.com/$GITHUB_REPOSITORY/releases/download/$GITHUB_REF_NAME/Home-Cellar-${VERSION}.zip"`
  is two lines and converts the last observation-only half of R1 into a gate. Already carried as
  optional hardening (C) in `tasks.md:6.8`.
- **G2 — `release.sh` header comment overstates one requirement.** Line 20 documents `BUILD_NUMBER`
  as needed for `archive/export/verify`, but `phase_export` calls `require_env VERSION` only. Either
  the comment or the check should move; the comment is the cheaper fix.
- **G3 — "Eight gates" in `RELEASING.md` §3 is now stale.** `phase_verify` performs twelve distinct
  gates. Harmless today, and the kind of number that quietly stops being true.
- **G4 — consider a `plutil -lint scripts/ExportOptions.plist` gate.** T7 parses it in the test
  suite, which is good; a one-line CI check would also catch it in the release run itself, before
  `xcodebuild -exportArchive` fails late.

### Carried risks

| # | Risk | State |
|---|---|---|
| U26 | Developer ID export + notarize round trip | **BLOCKED — re-measured this session.** `security find-identity -v -p codesigning` → `1 valid identities found`, `Apple Development: Juan Casanueva (A8EB4839B9)`. No Developer ID Application certificate, no ASC key. Blocks M1–M4, M6, M7 |
| U28 | Real Homebrew mutation from the notarized build (M8) | **Pending** — strictly follows U26. `RELEASING.md` §6 correctly carries a marked placeholder rather than unmeasured output |
| G3 | Dry-run prerelease on the real repository | **Not run** — needs U26, P1 and P4 |
| R4 | `MARKETING_VERSION=0.0.1-rc.1` may be rejected by `xcodebuild` or notarization | **Open.** Surfaces in G3, before any real release. Fallback is a `v0.0.1` tag name. Note the interaction: DD-7 derives `--prerelease` from the hyphen, so the fallback tag also loses the prerelease flag — that is acceptable for a rehearsal that is deleted afterwards, but it should be a conscious choice, not a surprise |
| R8 | SIGPIPE / `!`-pipeline pattern | **Fixed in `release.sh`** (`f993ecf`), **still wrong in `design.md`** — W1 |
| R6 | `Xcode_26.6.app` pin drifts off the runner image | Open, by design: the step fails loudly rather than compiling with another toolchain |
| — | `No App Category` archive warning | Deferred to `m6-sparkle-updates`; recorded in `RELEASING.md` §7 |

### What remains before the first tagged release

Strictly ordered; nothing below is a merge blocker for this PR.

1. **P1** — flip `juancasanueva/SWIFTUI_cellar` to **public** (blocks S1 and S4).
2. **P2** — create and export the **Developer ID Application** certificate *with its private key* as `.p12`.
3. **P3** — create an **App Store Connect API key** (`.p8`, Developer role); note key id and issuer id.
4. **P4** — set exactly six repository secrets: `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`,
   `KEYCHAIN_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`.
5. **P5** — confirm Actions is enabled and `GITHUB_TOKEN` may write releases.
6. **6.1** — gate: confirm P1–P5 complete. No tag may be pushed before 6.2 is green.
7. **6.2 / U26** — local `scripts/release.sh all` round trip; record M1, M2, M3, M4, M6, M7.
   Discharges S9, S10, S14, S15.
8. **6.3** — *conditional only*: apply the pre-authored Manual-signing fallback **only** if 6.2
   measures headless automatic export failing **and** the maintainer explicitly approves. If applied,
   T14 must be explicitly relaxed with the reason in its doc comment — never deleted.
9. **6.4 / U28** — M8 brew mutation from the notarized build; then fill `RELEASING.md` §6 with the
   quoted M6 + M8 output as `docs(release): record measured signing evidence`. Discharges S13.
   If M8 fails, **no entitlement is added by default** — report and reopen as a decision.
10. **6.5 / G3** — dry-run prerelease `v0.0.1-rc.1`; delete it manually with
    `gh release delete v0.0.1-rc.1 --cleanup-tag`. Discharges S1, S2, S5, S6, S17, S23. Watch R4.
11. **6.6** — M5 (quarantined first launch on a clean machine) and M10 (log secret sweep).
    Discharges S16, S27.
12. **First real `v1.0.0` tag.**
13. **6.7 / M9** — from the **second** release onward, compare `CFBundleVersion` across zips.
    Discharges S7.

Also recommended before archive, from this report: **W1** (amend `design.md`'s S10 gate) and **W2**
(correct the baseline to 184/194).

### Verdict

**PASS WITH WARNINGS** — all 35 Phase 0–5 tasks are complete and match the code; all 13 `unit`
scenarios pass at runtime and seven of them were proven able to fail; all 12 `ci-gate` scenarios have
a gate that exists and reads the property it claims; all 4 `manual-evidence` scenarios carry a
documented command and expected output. Zero CRITICAL findings and zero blockers. Four warnings, none
of which affects the delivered artifact: a design document that still prescribes a non-gating shell
idiom the implementation correctly rejected, a test-count baseline that is one short, sixteen
scenarios that remain unexecuted because no Developer ID certificate exists on this machine, and an
"offline" claim carried by manual evidence rather than by the CI gate that appears to make it.
