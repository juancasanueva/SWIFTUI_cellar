```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:166d32d305264176d6dc6dc9a79a5a918e1dce64ce3486fb6d770e24152bd4f7
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 10/10
scenarios: 35/35
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests && swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:5b4455e0ab41862aa7556b7788ef3812fc83504a1a3f85093efb0abf451a68b2
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/claude-501/-Users-juancasanueva-programming-swiftUI-cellar/0770b791-046f-4c28-82c2-6964882e5d7f/scratchpad/verify/dd CODE_SIGNING_ALLOWED=NO
build_exit_code: 0
build_output_hash: sha256:724ecedf5d03b20c878faabfbcd3bd671d3d24b91d7357a4c0c437292fb544ea
```

## Verification Report

**Change**: `m6-sparkle-updates`
**Version**: `specs/app-updates/spec.md` — ADDED-only, 7 requirements / 31 scenarios;
`specs/release-distribution/spec.md` — MODIFIED-only, 3 requirement blocks / 4 change-owned scenarios
**Mode**: Strict TDD
**Branch**: `feature/m6-sparkle-updates` @ `ab46446` · 15 commits ahead of `main` `215540b` · tree clean
**Verifier**: independent — no code was fixed, no review started, no receipt created, nothing
committed or pushed. RDD disabled clone-local. The only file written by this phase is this report.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`,
`artifact_store=hybrid` (OpenSpec files + Engram, canonical project `swiftui_cellar`),
`delivery_strategy=exception-ok` (ONE PR under `size:exception`), `review_budget_lines=5000`,
`strict_tdd=true`.

Native attempt ledger: `gentle-ai sdd-attempt acquire --change m6-sparkle-updates --work-unit verify`
with the orchestrator's token → `state: proceed`, zero ledger mutation. **Not settled by this executor.**

### What the envelope counts mean

`requirements: 10/10` and `scenarios: 35/35` follow the house precedent
(`archive/2026-08-23-m6-release-pipeline/verify-report.md`): they mean **every scenario is discharged
at the verification class the spec itself declares for it** — not that every scenario was executed.
The split is where the honesty lives:

| Class | Count | What "discharged" means here | Result |
|---|---|---|---|
| `unit-core` | 19 | A test in `Packages/CellarCore/Tests/UpdatesTests` passed at runtime | **19/19 runtime-proven** |
| `unit-app` | 11 | A test in `cellarTests` passed at runtime | **11/11 runtime-proven** |
| `manual-evidence` (app-updates) | 1 | AU-S16 — Sparkle ships no test harness; the exact commands are documented | **0/1 observed** — deferred to the first stable tag |
| `unit` (release-distribution) | 1 | RD-c passed at runtime | **1/1 runtime-proven** |
| `ci-gate` (release-distribution) | 3 | The gate exists and reads the property the scenario claims | **3/3 structurally verified**; RD-b additionally re-measured locally; RD-a1/RD-a2 execution pending the first tag |

**31 of 35 scenarios are runtime-proven by a test that passed during this verification.** The other
four (AU-S16, RD-a1, RD-a2, plus the workflow-execution half of RD-b) require a pushed tag that does
not exist. Per the spec's own verification-class contract those are **not failures**; they are the
pre-agreed shape of a slice whose publication half cannot fire before a release. They are also the
reason this report is `pass_with_warnings` and not `pass`.

**Scenario-count derivation.** `app-updates` contributes all 31 of its scenarios. The
`release-distribution` delta reproduces 16 scenarios because the OpenSpec MODIFIED convention requires
whole-block reproduction, but only **4** are change-owned (RD-a1, RD-a2, RD-b, RD-c); the other 12 are
verbatim carry-overs already discharged by the archived `m6-release-pipeline`. 31 + 4 = **35**, which
matches the scenario id map in `tasks.md` and the orchestrator's authoritative totals.

### Completeness

| Metric | Value |
|---|---|
| Tasks total | 69 |
| Tasks complete | 66 |
| Tasks incomplete | 3 (`B4.5`, `B4.6`, `B4.7`) |

Counted from `tasks.md`: `rg -c '^\s*- \[x\]'` → 66, `rg -c '^\s*- \[ \]'` → 3. Every checked task was
spot-checked against the code state on disk rather than taken on trust; the checks are recorded
throughout this report. The three incomplete tasks are all `manual-evidence` observations that
**cannot exist before a stable tag is pushed** — they are declared non-merge-blocking by `tasks.md`,
`design.md` and `apply-progress.md` alike. See WARNING W1.

### Build & Tests Execution

**Tests**: ✅ 216 app tests passed / 0 failed · 1,753 CellarCore tests in 209 suites passed / 0 failed
(1 known issue, pre-existing)

```text
$ xcodebuild test -project cellar.xcodeproj -scheme cellar \
    -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
** TEST SUCCEEDED **                                            exit 0
distinct "Test case '…' passed" ids: 215      distinct "… failed": 0

$ swift test --package-path Packages/CellarCore
􀢂 Test run with 1753 tests in 209 suites passed after 16.137 seconds with 1 known issue.
                                                                exit 0
```

**The 215-vs-216 gap is resolved, not assumed.** `apply-progress.md` attributed it generically to
`xcodebuild` tearing lines. This verification located the exact torn line and reconstructed it:

```text
line 365: Test case 'AutomaticUpdateChecksTests/thePreference2026-08-23 10:15:52.033 xcodebuild[…]
line 377: WritesExactlyOneKey()' passed on 'My Mac - cellar (68009)' (0.965 seconds)
```

`AutomaticUpdateChecksTests/thePreferenceWritesExactlyOneKey()` **passed**; its log line was split by
an interleaved `IDETestOperationsObserverDebug` block. The true app-test result is **216 passed, 0
failed**, which reconciles exactly with `rg -c '@Test' cellarTests/*.swift` = **216** at HEAD and
**184** at `main` (Δ **+32**, matching the corrected apply figure). No test is missing.

**Build**: ✅ Release, signing disabled

```text
$ xcodebuild build -project cellar.xcodeproj -scheme cellar -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath <scratch>/verify/dd \
    CODE_SIGNING_ALLOWED=NO
** BUILD SUCCEEDED **                                           exit 0
```

**Coverage**: ➖ Not measured — no coverage tool is configured for this project. Informational only.

### Runtime and structural checks beyond the test suites

Every row below is a command this phase executed, read-only, at `ab46446`.

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Partial plist content | `plutil -p Resources/Cellar-Info.plist` | Exactly two keys: `SUFeedURL` = `https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml`, `SUPublicEDKey` = `jqReS/…SAfZDVs=` ✅ |
| 2 | Key is a real 32-byte Ed25519 key | `base64 -d \| wc -c` | **32** ✅ — not a placeholder |
| 3 | Merge lands in the built bundle | `plutil -p <Release>/cellar.app/Contents/Info.plist` | `SUFeedURL`, `SUPublicEDKey`, `LSApplicationCategoryType = public.app-category.developer-tools` all present ✅ |
| 4 | No bundled key enables checking | same | `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SUScheduledCheckInterval` all **absent** ✅ (AU-S20) |
| 5 | Display name / copyright survive the merge | `plutil -p` on `Info.plist` and `en.lproj/InfoPlist.strings` | `CFBundleDisplayName = Home-Cellar`; localized strings carry `CFBundleName = Home-Cellar` and `NSHumanReadableCopyright = Copyright © 2026 Juan Casanueva…` ✅ — the pre-existing localized arrangement is intact |
| 6 | Sparkle is embedded | `ls <Release>/cellar.app/Contents/Frameworks/` | `Sparkle.framework` ✅ |
| 7 | Slices | `lipo -archs` | app executable `arm64`; `Sparkle.framework` `x86_64 arm64` ✅ — exactly what the RD-b reword describes |
| 8 | Stowaway sweep on the built bundle | `find … -name '*.sh' -o -name '*.yml' -o -name '*.yaml'` | **empty** ✅ — U32 stays withdrawn |
| 9 | Framework containment | `rg -l 'import Sparkle' --glob '*.swift' cellar/` | **1** file: `cellar/Updates/SparkleUpdateChecker.swift` ✅ |
| 10 | Updates target has no dependencies | `Package.swift:135-138` | `.target(name: "Updates", swiftSettings: [.swiftLanguageMode(.v6)])` — **no `dependencies:` key at all** ✅ |
| 11 | Secret set | `rg -o 'secrets\.[A-Z0-9_]+' .github/workflows/release.yml \| sort -u` | Exactly the **seven** named ✅ |
| 12 | Release-management containment | comment-stripped token count | `gh` = **1** (`gh release create`), `git` = **0** ✅ |
| 13 | Hyphen guards | `rg -n "contains\(github.ref_name"` | **4** occurrences, one per publication step ✅ |
| 14 | Job permissions + environment | `release.yml:30-33` | `contents: write`, `pages: write`, `id-token: write`; `environment: github-pages` ✅ |
| 15 | `shellcheck scripts/appcast.sh` | — | no findings, **exit 0** ✅ |
| 16 | `actionlint .github/workflows/release.yml` | — | no output, **exit 0** ✅ |
| 17 | No entitlements file | `fd -e entitlements` | **none** ✅ |
| 18 | pbxproj diff | `git diff main...HEAD --numstat` | **29 insertions, 0 deletions** — matches apply deviation 2, not the design's ≈28 |
| 19 | Binding untouched files | `git diff main...HEAD --stat` | `scripts/release.sh`, `scripts/ExportOptions.plist`, `cellar/Shell/AboutView.swift`, `cellar/InfoPlist.xcstrings` — all **0-line diffs** ✅ |

**Two apparent violations were run down and cleared** rather than reported as findings:

- A naive `rg '\bgh '` over `release.yml` returns **2**, and `rg 'set -x'` over `appcast.sh` returns
  **1**. Both matches are inside **comments** (`release.yml:26`, `appcast.sh:13`) that explain the very
  prohibition they name. The owning tests match *command tokens* over comment-stripped text and carry
  non-vacuity floors (`theWorkflowCanOnlyEverCreateARelease`, `theScriptNeverTracesItself` — the latter
  asserts a real `set` **is** visible so the reader cannot pass by seeing nothing). The prohibitions
  hold: `gh` = 1, `git` = 0, no executable trace line.

**No EdDSA key was generated or used by this phase.** `scripts/appcast.sh` was checked statically and
by `shellcheck` only; its signing path needs the repository secret and stays unexercised here, exactly
as `apply-progress.md` states.

### Spec Compliance Matrix — `app-updates` (AU-S1…S31)

| id | Scenario | Class | Test that discharges it | Result |
|---|---|---|---|---|
| AU-S1 | Version pair read from the bundle | unit-core | `App version > "The version pair is built from the bundle's two raw strings"` | ✅ COMPLIANT |
| AU-S2 | Higher marketing version is newer | unit-core | `App version > "Versions compare by marketing version, then prerelease, then build"` (4 cases) | ✅ COMPLIANT |
| AU-S3 | Rebuild of same marketing version is newer | unit-core | same, 4-case ordering table | ✅ COMPLIANT |
| AU-S4 | Prerelease sorts below its release | unit-core | `App version > "A prerelease suffix is parsed, not discarded"` | ✅ COMPLIANT |
| AU-S5 | Malformed version is a typed outcome | unit-core | `App version > "A malformed version throws its own named failure"` (5 cases) + `"An absent or unparseable pair yields no version"` (5 cases) | ✅ COMPLIANT |
| AU-S6 | Bundle carries the exact feed URL | unit-app | `BundleUpdateKeysTests/bundleCarriesTheFeedAndVerificationKey()` | ✅ COMPLIANT |
| AU-S7 | Bundle carries a well-formed key | unit-app | same (32-byte decode) | ✅ COMPLIANT |
| AU-S8 | Nothing can substitute feed or key | unit-app | `UpdateCompositionTests/nothingCanSubstituteADifferentFeedOrKey()` + `UpdateKeyMaterialTests/theOnlyKeyShapedLiteralIsTheBundledPublicKey()` | ✅ COMPLIANT |
| AU-S9 | A complete item validates | unit-core | `Appcast document > "A complete item validates and carries every field an update depends on"` | ✅ COMPLIANT |
| AU-S10 | Missing signature rejected | unit-core | `Appcast document > "A malformed appcast is rejected with its own named failure"` (13 cases) | ✅ COMPLIANT |
| AU-S11 | Missing/non-numeric length rejected | unit-core | same, 13-case rejection table | ✅ COMPLIANT |
| AU-S12 | Missing version/short version rejected | unit-core | same | ✅ COMPLIANT |
| AU-S13 | Non-https / non-github.com enclosure rejected | unit-core | same | ✅ COMPLIANT |
| AU-S14 | Wrong minimum system version rejected | unit-core | same (`expectedMinimumSystemVersion = "26.0"`, `AppcastDocument.swift:58`) | ✅ COMPLIANT |
| AU-S15 | Prerelease never in feed; merge keeps history | unit-core | `Appcast document > "A merged document keeps every item, newest first"` + the hyphenated-version rejection fixture | ✅ COMPLIANT |
| AU-S16 | Installed build replaces itself from the feed | **manual-evidence** | none can exist — Sparkle ships no harness | ⏸ **DEFERRED** to the first stable tag (task `B4.6`) |
| AU-S17 | Fresh install does not check automatically | unit-app | `AutomaticUpdateChecksTests/aFreshInstallReadsAsOff()` | ✅ COMPLIANT |
| AU-S18 | Choice survives a relaunch | unit-app | `AutomaticUpdateChecksTests/theChoiceSurvivesARelaunch()` + `turningItOffRecordsAStoredFalse()` | ✅ COMPLIANT |
| AU-S19 | Persisted preference written at launch | unit-core | `Update policy > "The persisted preference is written to the updater"` (2 cases) + `"An off run leaves automatic checking off"` | ✅ COMPLIANT |
| AU-S20 | No bundled default, no framework prompt | unit-app | `BundleUpdateKeysTests/partialPropertyListCarriesOnlyTheFeedAndTheKey()` + `UpdateCompositionTests/thePreferenceIsAppliedBeforeTheUpdaterStarts()`; corroborated by check 4 above | ✅ COMPLIANT |
| AU-S21 | Command present in the app menu | unit-app | `UpdateCompositionTests/theCommandIsAddedAfterTheAboutItem()` | ✅ COMPLIANT |
| AU-S22 | Command enabled while auto-checking off | unit-core | `Update policy > "Automatic checking does not decide the command's enablement"` | ✅ COMPLIANT |
| AU-S23 | Disabled only while a check is in flight | unit-core | `Update policy > "The command is enabled exactly while the updater can check"` (2 cases) | ✅ COMPLIANT |
| AU-S24 | Invoking starts exactly one check | unit-core | `App updating > "Each invocation starts exactly one check"` | ✅ COMPLIANT |
| AU-S25 | Never-checked app says so | unit-core | `Update check presentation > "A never-checked app says so, with no date in the text"` | ✅ COMPLIANT |
| AU-S26 | Checked app reports the date | unit-core | `Update check presentation > "A checked app reports its check, and the label follows the date"` | ✅ COMPLIANT |
| AU-S27 | Label follows the recorded date | unit-core | `Update check presentation > "The label changes when the recorded date arrives"` + `"The label is a pure function of the two dates"` | ✅ COMPLIANT |
| AU-S28 | Updates group renders nothing inert | unit-app | `UpdateCompositionTests/theUpdatesGroupDeclaresExactlyTwoRows()` (T25) | ✅ COMPLIANT |
| AU-S29 | Exactly one file imports the framework | unit-app | `UpdateCompositionTests/exactlyOneFileImportsTheUpdaterFramework()`; corroborated by check 9 | ✅ COMPLIANT |
| AU-S30 | No UI file names the framework's types | unit-app | `UpdateCompositionTests/onlyTheCheckerNamesTheFrameworksUpdaterTypes()` + `noSurfaceNamesTheConcreteChecker()` | ✅ COMPLIANT |
| AU-S31 | Update module declares no dependencies | unit-app | `UpdatePackageManifestTests/updatesTargetDeclaresNoDependencies()` + `updatesLibraryExposesTheUpdatesTarget()`; corroborated by check 10 | ✅ COMPLIANT |

**`app-updates` compliance: 30/31 runtime-proven; 1 deferred (AU-S16) at its declared class.**

### Spec Compliance Matrix — `release-distribution` (change-owned scenarios)

| id | Scenario | Class | Evidence | Result |
|---|---|---|---|---|
| RD-a1 | Stable tag publishes the feed, no push, no second release call | ci-gate | `AppcastWorkflowTests/theAppcastStepRunsAfterTheReleaseIsPublished()`, `allFourPublicationStepsCarryThePrereleaseGuard()`, `theReleaseJobDeclaresThePagesPermissionsAndEnvironment()`, `theSigningKeyIsBoundOnlyAsAnEnvironmentVariable()`, all 7 `AppcastScriptContractTests`, `ReleaseWorkflowContractTests/theWorkflowCanOnlyEverCreateARelease()` — all **passed** | ⏸ **Structurally verified; execution deferred** to the first stable tag (task `B4.5`/`B4.6`) |
| RD-a2 | Prerelease publishes a release and no feed entry | ci-gate | `AppcastScriptContractTests/aPrereleaseTagExitsBeforeWritingAnything()` **passed**; guard literal `case "$GITHUB_REF_NAME" in *-*) … exit 0` at `appcast.sh:36-41`; four `if: !contains(github.ref_name, '-')` guards | ⏸ **Structurally verified; execution deferred** (task `B4.7`) |
| RD-b | Delivered application executable is single-architecture | ci-gate | **Re-measured locally this phase**: `lipo -archs` → app executable `arm64`, `Sparkle.framework` `x86_64 arm64`. Attested by apply on the exported notarized bundle (M2) | ✅ **COMPLIANT** locally; CI gate itself fires on a tag |
| RD-c | Referenced secret set is exactly the seven named | unit | `ReleaseWorkflowContractTests/workflowReferencesExactlyTheExpectedSecrets()` and `secretsAppearOnlyAsEnvironmentBindings()` **passed**; corroborated by check 11 | ✅ COMPLIANT |

The stowaway scenario ("None of it ships to the user") was **not** amended, as `tasks.md` binds — and
it still passes: `ReleasePipelinePlacementTests/appSourcesCarryNoReleaseInfrastructure()` ✅, plus the
independent `find` sweep at check 8.

### Manual evidence — attested, not machine-checked

`apply-progress.md`'s validator trailer is correct and this phase does **not** upgrade it. `build/` is
untracked, so the exported-bundle observations cannot be re-derived here:

| # | Claim | Status |
|---|---|---|
| M1 / U30 | `scripts/release.sh all` → notarization `Accepted`, id `593818bf-c3db-460d-b674-3db6078732b6`; `codesign --verify --strict` green over all five nested Sparkle objects | **ATTESTED** — not machine-checked by this phase |
| M2 / U31 | `lipo -archs` on the *exported* framework → `x86_64 arm64` | **ATTESTED**; independently corroborated on a locally Release-built bundle (check 7) |
| M3 / U32 | `find` sweep on the *exported* bundle → empty | **ATTESTED**; independently corroborated on a locally Release-built bundle (check 8) |
| M4 / U33 | `curl -fsSI …/appcast.xml` → 200 | **NOT OBSERVED.** Re-run this phase: **HTTP 404** — expected, no stable tag has been published |
| M5 / M6 / M7 | rc→stable upgrade, Gatekeeper-offline relaunch, job-log key sweep | **NOT OBSERVED** — require a published stable tag |

### Maintainer prerequisites — re-measured, and one blocker is now clear

`apply-progress.md` deviation 1 reported the `github-pages` environment as excluding tag refs, calling
it a blocker for the first publishing tag. **That is no longer true**, verified this phase:

```text
$ gh api repos/juancasanueva/SWIFTUI_cellar/environments/github-pages/deployment-branch-policies
{"total_count":2,"branch_policies":[
  {"name":"main","type":"branch"},
  {"name":"v*","type":"tag"}]}
```

The `v*` **tag** rule now exists, so `deploy-pages` from a `v*` tag will be admitted. Remaining
prerequisite state, all re-measured:

| Prerequisite | State |
|---|---|
| Seven repository secrets incl. `SPARKLE_PRIVATE_KEY` | ✅ present (`gh secret list` → 7) |
| GitHub Pages, source = GitHub Actions | ✅ `has_pages: true`, `build_type: workflow` |
| `github-pages` admits `v*` tags | ✅ tag policy present |
| Repository public | ✅ `visibility: public` |
| Feed live | ❌ 404 — correctly awaiting the first stable tag |

`RELEASING.md` §2 prerequisite 6 **does** document the tag rule (lines 67-71: *"add a **tag** rule
matching `v*`… Without it the four…"*), so the runbook and the repository state now agree.

### Correctness (static evidence)

| Requirement | Status | Note |
|---|---|---|
| Version honesty and ordering | ✅ Implemented | `AppVersion.swift` — `Sendable, Hashable, Comparable`, typed `AppVersionParseFailure` |
| Feed fixed inside the bundle | ✅ Implemented | Build-time merge only; no delegate, no `feedURLString(for:)`, no runtime write |
| Appcast validity, offline | ✅ Implemented | `AppcastDocument.swift`, Foundation `XMLParser` only, `expectedHost = "github.com"`, `expectedMinimumSystemVersion = "26.0"` |
| Automatic checks off until asked | ✅ Implemented | `AutomaticUpdateChecks` (missing key ⇒ `false`), applied before `startUpdater()` |
| Explicit check always reachable | ✅ Implemented | `CommandGroup(after: .appInfo)`, enablement delegated to `UpdateCommandEnablement` |
| No untrue or inert surface | ✅ Implemented | Two rows, both with behaviour; no `Picker`, no channel wording |
| Updater reaches nothing but the updater | ✅ Implemented | One import; `Updates` target has no `dependencies:` key |
| RD (a) tag publishes the feed | ✅ Implemented | Four guarded steps after the publish step |
| RD (b) arm64 application executable | ✅ Implemented | Measured |
| RD (c) closed seven-secret set | ✅ Implemented | Measured |

### Coherence (design)

| Decision | Followed? | Notes |
|---|---|---|
| DD-1 dependency-free `Updates` target | ✅ Yes | `Package.swift:135-138`, no `dependencies:` key |
| DD-2 `AppUpdating: AnyObject, Observable`, `@MainActor` | ✅ Yes | `AppUpdating.swift:27` |
| DD-3 hand-built `Binding(get:set:)` | ✅ Yes | `UpdatesSettingsGroup.swift` |
| DD-5 value type over injected `UserDefaults` | ✅ Yes | `AutomaticUpdateChecks.swift` |
| DD-6 KVO bridged with `MainActor.assumeIsolated` | ✅ Yes | `SparkleUpdateChecker.swift:91-110`, invariant written into the file |
| DD-7 `CommandGroup(after: .appInfo)`, never `replacing:` | ✅ Yes | `CheckForUpdatesCommands.swift:25`; `AboutView.swift:155` keeps its own `replacing:` |
| DD-9 404 ⇒ synthesised empty channel | ✅ Yes | Exercised by apply's script harness |
| DD-10 tool pinned by version **and** sha256 | ✅ Yes | `appcast.sh:55-56` |
| DD-11 key on stdin only | ✅ Yes | `appcast.sh:99`, single `printf … \| sign_update --ed-key-file -` pipeline; never a `>` target |
| DD-12 one Ed25519-shaped literal | ✅ Yes | Residual gap (non-base64 key format) restated below |
| DD-15 policy types in `Sources/Updates` | ✅ Yes | `AutomaticUpdateChecksPolicy`, `UpdateCommandEnablement` in `UpdatePolicy.swift` |
| `startingUpdater: false`, preference before `startUpdater()` | ✅ Yes | `SparkleUpdateChecker.swift:46-56` — apply *then* start, in that order |
| Concurrency posture | ✅ Yes | `rg '@unchecked Sendable\|nonisolated\(unsafe\)\|Task.detached\|#available'` over `Sources/Updates` and `cellar/Updates` → **zero hits** |

Deviations 2, 5, 6, 7, 8, 9, 10, 11 in `apply-progress.md` are all **design-refining, spec-preserving**
and were reported rather than absorbed. Each was re-read against the code and none breaks a spec
requirement. Deviation 5 (`AppcastValidationFailure` gaining `.missingVersion`,
`.missingShortVersionString`, `.malformedDocument`) is required by AU-S12's "naming the missing field"
and is an improvement over the design's enumeration, not a drift.

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | `apply-progress.md` carries a 22-row TDD Cycle Evidence table |
| All tasks have tests | ✅ | 13 new test files; every `unit-core`/`unit-app` scenario maps to a named test |
| RED confirmed (test files exist) | ✅ | 13/13 test files verified present on disk |
| GREEN confirmed (tests pass) | ✅ | 22/22 rows re-executed and passing during this verification |
| Triangulation adequate | ✅ | Parameterized tables throughout: 13 appcast rejection fixtures, 5 malformed version shapes, 4-row ordering table, 5 raw pairs |
| Safety Net for modified files | ✅ | Every row records a pre-change count; the one exception (T15) is disclosed |

**TDD Compliance: 6/6 checks passed.** One honest self-report: apply's row for **T15**
(`secretsAppearOnlyAsEnvironmentBindings`) is marked ⚠️ **not RED** — the `>= 6 → >= 7` non-vacuity
floor was green on arrival because the workflow already carried 10 secret-reference lines. Apply
recorded this as deviation 4 rather than presenting it as a TDD cycle. **That is the correct
behaviour**, and it is the only non-RED row in the table.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (core, pure values) | 19 scenarios / 5 suites | 5 | Swift Testing |
| Unit (app, structural over sources & bundle) | 11 scenarios / 8 suites | 8 | Swift Testing + `#filePath` |
| Integration | 0 | 0 | not applicable to this slice |
| E2E / UI | 0 | 0 | deliberately none — a UI test may never construct `SparkleUpdateChecker` |
| **Total new** | **13 files** | **13** | |

Deliberate absence of UI tests is a **security property**, not a gap: `AppTestFixtures` routes
UI-test launches to an in-memory `AppTestUpdater`, so no UI test can start an updater, reach the feed,
or open a Sparkle window.

### Changed File Coverage

➖ Coverage analysis skipped — no coverage tool is configured for this project. Not a failure.

### Assertion Quality

Audited all 13 new test files (194 `#expect`/`#require` assertions):

- Tautologies (`#expect(true)`, `1 == 1`): **none**
- Assertions that never call production code: **none**
- Ghost loops over possibly-empty collections: **none** — the sweeping tests carry explicit
  non-vacuity floors: `UpdateKeyMaterialTests:115` `#expect(scanned > 100)`,
  `UpdateCompositionTests:44,80` `#expect(sources.count > 10)` / `#expect(surfaces.count > 10)`,
  `AppcastScriptContractTests:117` asserts a real `set` is visible
- Smoke-test-only: **none**
- Mock-heavy tests: **none** — `FakeAppUpdater` / `AppTestUpdater` are protocol conformers, not
  mocking-framework doubles; there is no mocking framework in the project
- Type-only assertions used alone: **none observed**

**Assertion quality: ✅ All assertions verify real behavior. 0 CRITICAL, 0 WARNING.**

One noteworthy strength: the sweeping tests assert **exact counts** rather than presence
(`exactly one` importer, `exactly two` rows, `exactly seven` secrets, `exactly one` key literal), which
is what makes a silent future addition fail rather than pass.

### Quality Metrics

**Linter (`shellcheck`)**: ✅ no findings, exit 0
**Workflow linter (`actionlint`)**: ✅ no output, exit 0
**Swift compiler**: ✅ Release build succeeded; `swift build --package-path Packages/CellarCore` clean
**swiftlint**: apply reports clean with one accepted `optional_data_string_conversion` warning in
`UpdateKeyMaterialTests`, matching the identical accepted warning at
`ReleasePipelineCompositionTests:448` for the same repository sweep — consistent precedent, not new debt.

### Budget and size honesty

```text
$ git diff main...HEAD --shortstat
 58 files changed, 6647 insertions(+), 24 deletions(-)
```

**6,671 changed lines** measured at `ab46446` — 3 lines above the 6,668 `apply-progress.md` recorded,
the difference being the validator-correction trailer appended to that artifact afterwards. Against
the governing **5,000**-line budget this is an overrun of **≈1,671 lines (≈33%)**, and against the
design's forecast ceiling of ≈6,411 an overrun of **≈260**. This sits **inside the accepted
`size:exception`** recorded in the `tasks.md` Q4 resolution block (maintainer decision, option (B),
2026-08-23), but it exceeds the ≈1,411-line overrun that decision anticipated. Recorded, not smoothed —
see WARNING W3.

Note also a preflight inconsistency: the three spec/tasks artifacts still carry
`delivery_strategy=single-pr` in their forwarded preflight headers, while the resolved strategy is
`exception-ok`. `tasks.md`'s own Q4 block states the resolution correctly. Cosmetic; see SUGGESTION S1.

### Issues Found

**CRITICAL**: None.

**WARNING**:

- **W1 — three tasks incomplete, all structurally undischargeable before a tag.** `B4.5` (M4/U33),
  `B4.6` (M5/M6/M7) and `B4.7` (RD-a2) require a published stable and prerelease tag. Re-measured this
  phase: the feed returns **404**, which is the correct state pre-tag. Declared non-merge-blocking by
  proposal, design and tasks alike. **Not a defect; a sequencing fact.**
- **W2 — four scenarios are not runtime-proven** (AU-S16, RD-a1, RD-a2, and the CI-execution half of
  RD-b). Each is discharged at its declared class, but no machine has observed the publication path
  end to end. The single highest residual risk is that the **real `sign_update` invocation has never
  run**: apply's harness stubbed exactly that line because the private key is a repository secret. A
  malformed signature would be discovered on the first stable tag, not before.
- **W3 — the `size:exception` overrun is larger than the one the maintainer accepted.** The recorded
  decision anticipated ≈1,411 lines over budget; the measured figure is **≈1,671**. Still within the
  granted exception in kind, but the maintainer should know the number moved.
- **W4 — `cellarUITests/ReleaseNotesUITests` remains unowned** since `m5-health`. Confirmed still
  present on disk and outside the `-only-testing:cellarTests` scope this slice runs. **Not this
  slice's defect**; stated rather than inherited silently, as `tasks.md` requires.
- **W5 — DD-12 residual gap stands.** A private key committed in a format that is **not** 44-character
  base64 evades both `UpdateKeyMaterialTests` and `repositoryCarriesNoCredentialMaterial`. Disclosed by
  design and apply; re-confirmed here, not closed.
- **W6 — Pages deploy is a full-site replacement.** `RELEASING.md` §7 risk 3 records it: any second
  workflow deploying to Pages would silently overwrite `appcast.xml` and strand every installed copy.
  The Pages site root is empty **by decision**; that decision is now load-bearing.
- **W7 — the private key is a one-way door.** Losing `SPARKLE_PRIVATE_KEY` permanently severs the
  update channel for every shipped copy, and re-landing after a revert **must reuse the same
  `SUPublicEDKey`**. Apply records the backup as done; this phase cannot verify an offline backup and
  does not claim to.

**SUGGESTION**:

- **S1** — the forwarded preflight header in `specs/app-updates/spec.md`,
  `specs/release-distribution/spec.md` and `tasks.md` still reads `delivery_strategy=single-pr`; the
  resolved value is `exception-ok`. Worth reconciling at archive so the promoted spec's provenance is
  self-consistent.
- **S2** — `apply-progress.md` attributes the 215/216 gap to generic log tearing. The exact torn line
  is now identified (this report, *Build & Tests Execution*); consider carrying that reconstruction
  into the archive note so the discrepancy is never re-litigated.
- **S3** — `T25` was added at the tasks phase to discharge AU-S28, which the design's
  requirement→check map left unbound. It is a genuine gap the tasks phase caught. Worth folding into
  the design's map at archive rather than leaving it as a tasks-phase annotation.
- **S4** — the design's arithmetic slip (≈28 vs the measured 29 pbxproj insertions, apply deviation 2)
  is harmless but should be corrected in the archived design so a future slice does not inherit the
  wrong baseline.

### Carried risks

1. The publication path merges **unexercised**. Everything upstream of `sign_update` has been run for
   real; the signing call itself and `deploy-pages` have not.
2. AU-S16 — the actual self-replacement — is the one scenario that proves the capability works. Until
   a stable tag exists, Cellar ships an update mechanism nobody has watched succeed.
3. A shipped build whose feed 404s: automatic checks are default-off, so nothing happens unprompted,
   but an explicit "Check for Updates…" before the first stable tag will surface Sparkle's own
   "could not check" path. That path is Tier 3 (no harness) and remains an **accepted, unverified**
   consequence.

### Verdict

**PASS WITH WARNINGS**

All 69 tasks are either complete (66) or structurally undischargeable before a published tag (3).
Both suites execute clean at `ab46446` — **216/216** app tests and **1,753/1,753** CellarCore tests,
zero failures, one pre-existing known issue — and the Release build succeeds with `Sparkle.framework`
embedded, the feed URL and a real 32-byte Ed25519 key merged into the bundle, and no key that could
enable automatic checking. 31 of 35 scenarios are runtime-proven; the remaining four are discharged at
the verification class the spec itself declares and are blocked only on a tag. Zero CRITICAL findings,
zero blockers, seven warnings — none of which blocks archive. The one blocker apply reported (the
`github-pages` tag-ref policy) has since been resolved and is verified resolved here.
