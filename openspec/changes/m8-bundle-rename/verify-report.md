```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:9e05ac7002a4802ea24a423c6027eb7b4b1d10e10b6743c0c1f5b4460c0533e3
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 3/3
scenarios: 16/16
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:2871e44d8d57ce193fdb7db2fc68293800e7a6d1b03296b3f24dd9b468643ad2
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:dee60b246a4c649a7ca3d7cb0a7acf8505f4852787fb8f9921c6d4eaffadb702
```

## Verification Report — Round 2 (re-verification)

**Change**: `m8-bundle-rename`
**Version**: delta for `release-distribution` — 3 MODIFIED / 16 scenarios
**Mode**: Strict TDD
**Verifier**: independent, fresh context. Every claim below was re-derived from the tree, the
runners, the published release and git. Nothing was accepted on the word of `sdd-apply` or of the
remediation, with one declared exception (UI-test pre-existence, noted in *Suite Evidence*).
App repo `feat/m8-bundle-rename` @ `f50becf`; tap repo `feat/m8-bundle-rename` @ `7c50ee6`.
Supersedes round 1 (`sha256:31506165…0b23b33d`, FAIL).

**Verdict: PASS WITH WARNINGS — 0 CRITICAL, 1 WARNING, 2 SUGGESTION.**

Round 1's blocker is genuinely closed, not papered over. The amended R4 prescribes an ordering that
is achievable, and I confirmed it is consistent with all four things it has to agree with: the
published `v1.1.0` asset (re-downloaded and re-measured), `bump.yml`'s schedule and gates, the held
tap commit's content and message, and Phase 7's procedure. All three warnings and both suggestions
from round 1 are resolved or explicitly dispositioned. The one remaining warning is a hand-off
hazard for `sdd-archive`, not a defect in the change.

---

## Round-1 Findings Closure

| # | Round-1 finding | Status | Evidence (file:line / measurement) |
|---|---|---|---|
| **C1** | R4's "tap before the tag" ordering unsatisfiable — published `v1.1.0` asset contains `cellar.app` | ✅ **CLOSED** | `specs/release-distribution/spec.md:147-152` now reads "one atomic commit that moves `version`, `sha256` and the `app` artifact together … applied **after** the first release whose published asset actually contains the renamed bundle", with the bump "paused, or its open pull request superseded, until that commit lands". Consistency proof in the four rows below. |
| **W1** | Tap branch based on stale `main` (`f9e7428`), would regress cask 1.1.0 → 1.0.0 | ✅ **CLOSED** | `git merge-base --is-ancestor origin/main HEAD` → true. `7c50ee6` sits directly on `origin/main 5e02b96`. Cask now declares `version "1.1.0"` / `sha256 "a6d5c68d…fe9e95"`. `git diff --stat origin/main` → exactly `ci.yml` 6, `home-cellar.rb` 2, `README.md` 10 (9 insertions / 9 deletions). |
| **W2** | R7 archive list named 3 passages; 3 more out-of-block hits unlisted | ✅ **CLOSED** | Delta `spec.md:294-312` now names **six**: `:619`, `:686-688`, `:718-720`, `:567`, `:706`, `:601` (the last flagged "the urgent one" — present-tense contradiction). Independently swept: `## Provenance` starts at `openspec/specs/release-distribution/spec.md:528`; every old-name reference at or after `:528` is at `567`, `601`, `619`, `686`, `706` — **all five named, zero unnamed**. |
| **W3** | Scenario 2 counted as compliant though only build-verified, not zip-verified | ✅ **CLOSED** | This report classifies scenario 2 as **structurally verified, execution pending — build-verified, not zip-verified**, so the runtime-proven count reads **5/16** rather than round 1's 6/16. No scenario regressed; the change is exactly the correction W3 asked for. Built-bundle evidence strengthened, see *Invariants*. |
| **S1** | Test-count unit unstated ("247" vs "237") | ✅ **ACCEPTED, verified** — residue noted as S3 | Independently measured from `.xcresult`: `passedTests: 237` (test-node level), `passedTests: 247` (device level), `statistics: "3 tests ran with dynamic parameters" / "13 test runs"`. 237 − 3 + 13 = 247. `apply-progress.md:25-26` states this correctly. |
| **S2** | `…Tests:94` / `:68` described as "guards", are helper filters | ✅ **DECLINED with a genuine reason** — carry-forward noted as S4 | `apply-progress.md:27`: the wording lives in `design.md`, outside the scoped remediation's edit surface; recorded for `sdd-archive`. `design.md:216` still carries the original phrasing, consistent with a decline. |

### C1 consistency proof — the amended R4 against reality

| Must agree with | Independently measured | Verdict |
|---|---|---|
| **(a) the published `v1.1.0` asset** | Re-downloaded from the release URL. `shasum -a 256` → `a6d5c68d38eb6a9166e5eb06c6e0521f582415da74b6e372b558822507fe9e95`, which **equals the cask's declared `sha256` byte-for-byte**. `unzip -Z1 \| head -3` → `cellar.app/`, `cellar.app/Contents/`, `cellar.app/Contents/CodeResources`. `gh release list` confirms `v1.1.0` is still `Latest`. | ✅ The premise still holds. The amended clause is written **because** of this fact, not against it: it is precisely why the tap must wait. |
| **(b) `bump.yml`'s schedule and gates** | `git diff --stat origin/main -- .github/workflows/bump.yml` → **empty** (untouched, so R4 is not reopened). Schedule `cron: "17 */6 * * *"` at `:9-10`. Its rewrite is a `sed` over anchored `^  version "` / `^  sha256 "` only (`:102-105`). Gates at `:128-130` are `brew style`, `brew audit --cask`, `brew audit --cask --online --strict`. Zero hits for `unzip`, `ditto`, `tar`, `app "`, `Applications`. | ✅ The requirement's assertion that the bump path "neither extracts the archive nor resolves the `app` artifact" is **provably true of this file**, which is exactly what makes pausing it necessary and sufficient. |
| **(c) the held tap commit** | `7c50ee6`, author `Juan Casanueva <juancasanueva@gmail.com>`. Message line 2: "**HOLD — DO NOT MERGE before the renamed release publishes.**" Carries a four-step procedure: (1) prove the asset via `unzip -Z1`, (2) pause the `17 */6 * * *` schedule, (3) amend so `version`, `sha256` and `app` move together, (4) merge, let `ci.yml` run the round trip, restore the schedule. Explains why `ci.yml`/`README.md` ride in the same commit (the install job asserts `/Applications/Home-Cellar.app` immediately after install, so a split "safe" commit would still red-light CI). | ✅ The commit's own message encodes the atomic post-release mechanism. See **W4** for the one caveat. |
| **(d) `tasks.md` Phase 7** | `tasks.md:490` (7.1 pause the bump before the tag) → `:495` (7.2 `unzip -Z1 Home-Cellar-1.2.0.zip \| head -2` must print `Home-Cellar.app` and `Home-Cellar.app/Contents/MacOS/Home-Cellar`, plus `shasum -a 256` of the **downloaded** file, "if it still contains `cellar.app`, **stop**") → `:500` (7.3 the atomic amend) → `:506` (7.4 verify on the tap's **default** branch, "do not trust Phase 1") → `:509` (7.5 restore the schedule). | ✅ The `unzip -Z1` asset check is present and is correctly positioned as the **pre-condition for 7.3**, with an explicit stop condition. |

**Conclusion**: the ordering R4 now mandates is achievable, self-consistent, and correctly
decomposed into the task ledger. C1 is closed on the merits.

---

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 60 |
| Tasks complete `[x]` | 46 |
| Tasks incomplete `[ ]` | 14 |

Recounted from the file, not from the artifact's own claim: `rg -c '^- \[[ x]\] '` → 60,
`^- \[x\]` → 46, `^- \[ \]` → 14. This matches `apply-progress.md`'s "46 of 60 tasks executed,
14 explicitly deferred".

Every one of the 14 carries a genuine, phase-external reason — I read each:

| Task | Deferral reason | Genuine? |
|---|---|---|
| 1.6 | Moved to Phase 7 (7.3–7.5) — pushing/opening/merging the tap PR became post-release actions | ✅ structural consequence of the C1 fix |
| 6.8 | Open the app-repo PR — maintainer action; `sdd-apply` never pushes | ✅ |
| 7.1 | Pause `bump.yml`'s schedule before the tag — maintainer, another repository | ✅ |
| 7.2 | Post-tag asset proof — requires `v1.2.0` to exist | ✅ unreachable |
| 7.3–7.5 | Atomic tap commit, its PR/merge, schedule restore — post-release maintainer actions | ✅ unreachable |
| 7.6–7.7 | ME1 / ME2 on the maintainer's Mac — both post-tag | ✅ unreachable |
| 7.8 | Composition-only honesty statement — an obligation on **this** report | ✅ discharged below |
| 8.1–8.4 | Archive obligations — the capability spec is edited only at `sdd-archive` | ✅ by design |

No task is silently skipped. Zero unchecked tasks describe work that was reachable from the apply phase.

---

### Build & Tests Execution

**Build**: ✅ Passed
```text
xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
** BUILD SUCCEEDED **   (exit 0)
```

**Fast unit suite (`cellarTests`)**: ✅ Passed
```text
xcodebuild test … -only-testing:cellarTests
** TEST SUCCEEDED **   (exit 0)
From the .xcresult:  passedTests 237 (test nodes) · passedTests 247 (device) ·
                     failedTests 0 · skippedTests 0 · expectedFailures 0 ·
                     statistics: "3 tests ran with dynamic parameters" / "13 test runs"
Reconciliation:      237 distinct functions − 3 parameterized + 13 runs = 247 executed cases
```

**Core package (`CellarCore`)**: ✅ Passed
```text
swift test --package-path Packages/CellarCore
Test run with 1793 tests in 210 suites passed after 16.737 seconds with 1 known issue.   (exit 0)
```
Identical to the Phase 0.2 baseline. `git diff --stat main -- Packages/CellarCore/` is empty, so this
change has a zero-line causal surface in that package.

**UI tests (`cellarUITests`)**: not re-run this round. Two failures
(`testTapDetailFilteringInstalledHandoffAndForceDisclosure`,
`testTapsNavigationOfficialSourcesAndAddConfirmation`) were **proven pre-existing at `main f0a5817`**
by round 1 and by `sdd-apply` (both checked out `main` and reproduced them with none of this change
applied). **This report accepts that pre-existence from recorded round-1 evidence rather than
re-deriving it** — declared explicitly so the acceptance is auditable. The rename is not implicated:
the app launched normally in both runs (`Application, pid: …, title: 'Home-Cellar'`).

**Coverage**: threshold is `0` in `openspec/config.yaml`; no coverage gate applies. Not run.

---

### Spec Compliance Matrix

All 16 scenarios of the 3 MODIFIED requirements, re-classified against this round's runtime evidence.

| # | Requirement | Scenario | Class | Covering test / runner | Result |
|---|---|---|---|---|---|
| 1 | Tag → release | A tag produces one correctly named, anonymously reachable asset | `ci-gate` | `release.yml` at the next tag | ⚠️ Structurally verified, execution pending |
| 2 | Tag → release | The bundle inside the zip is the one the follow-up slices bind against | `ci-gate` | `release.yml` at the next tag | ⚠️ Structurally verified, execution pending — build-verified, not zip-verified |
| 3 | Tag → release | Nothing but a version tag can trigger a release | `unit` | `ReleaseWorkflowContractTests/onlyAVersionTagTriggersTheWorkflow()` | ✅ COMPLIANT |
| 4 | Tag → release | A private repository fails fast instead of publishing an unreachable asset | `ci-gate` | `release.yml` at the next tag | ⚠️ Structurally verified, execution pending |
| 5 | Tag → release | A stable tag also publishes the update feed | `ci-gate` | `release.yml` at the next tag | ⚠️ Structurally verified, execution pending |
| 6 | Tag → release | A prerelease tag publishes a release and no feed entry | `ci-gate` | `release.yml` at the next tag | ⚠️ Structurally verified, execution pending |
| 7 | Homebrew tap | A tap and an install put the released build in `/Applications` | `manual-evidence` | maintainer's Mac, post-tag (task 7.6) | ⚠️ PENDING — declared class, maintainer's step |
| 8 | Homebrew tap | The cask is style-clean, audit-clean, survives an install/uninstall round trip | `ci-gate` | `ci.yml` in `juancasanueva/homebrew-cellar` | ⚠️ Structurally verified, execution pending |
| 9 | Homebrew tap | The rename ships no migration mechanism | `ci-gate` | `ci.yml` in `juancasanueva/homebrew-cellar` | ⚠️ Structurally verified, execution pending — statically proven in the tap clone |
| 10 | Homebrew tap | A self-updated app does not fight `brew upgrade` | `manual-evidence` | maintainer's Mac, post-tag (task 7.7) | ⚠️ PENDING — declared class, maintainer's step |
| 11 | Homebrew tap | A prerelease never becomes an installable cask version | `ci-gate` | `bump.yml` in the tap repo | ⚠️ Structurally verified, execution pending |
| 12 | Homebrew tap | Keeping the cask current is idempotent on the declared version | `ci-gate` | `bump.yml` in the tap repo | ⚠️ Structurally verified, execution pending |
| 13 | Uninstall docs | The documented inventory covers every write root the source declares | `unit` | `CaskZapInventoryTests/everyWriteRootTheSourceDeclaresIsInTheDocumentedInventory()` + `…/theWriteRootScanIsNonVacuousAndEveryPassThroughIsAHomebrewRootsHandOff()` | ✅ COMPLIANT |
| 14 | Uninstall docs | The two Keychain items are documented as surviving a full uninstall | `unit` | `CaskZapInventoryTests/theRunbookNamesBothKeychainItemsAZapCannotRemove()` | ✅ COMPLIANT |
| 15 | Uninstall docs | The install commands are documented as whole lines | `unit` | `CaskZapInventoryTests/theReadmeCarriesBothBrewCommandsAsWholeLines()` | ✅ COMPLIANT |
| 16 | Uninstall docs | The release run gains no cross-repository reach | `unit` | `ReleaseWorkflowContractTests/theWorkflowGainsNoCrossRepositoryReach()` (`ReleasePipelineCompositionTests.swift:781-811`) | ✅ COMPLIANT |

**Compliance summary**: **5/16 runtime-proven** (every `unit`-class scenario, each with a covering
test confirmed passed in this round's run) · **9/16 structurally verified, execution pending** (the
`ci-gate` scenarios — the gate exists in `release.yml` / `release.sh` / the tap's `ci.yml` and reads
the property the scenario claims) · **2/16 pending by declared class** (`manual-evidence`, the
maintainer's own step). **0 failing, 0 untested.**

**What the envelope's `16/16` means, and why it is not a rounding-up.** This capability declares a
`## Verification classes` taxonomy that assigns every scenario exactly one class and one named
runner. The house convention — set by `m6-release-pipeline` (envelope `scenarios: 29/29`,
`verdict: pass_with_warnings`, with **12** `ci-gate` rows marked "Structurally verified, execution
pending" because no Developer ID certificate existed on that machine) and by `m6-cask-tap` (envelope
`scenarios: 9/9` with **2** `manual-evidence` rows marked PENDING) — is that a scenario counts toward
the envelope total when it has been verified **to the standard its declared class permits at this
point in the lifecycle**, with the honest per-scenario status carried in this matrix. This report
follows that convention exactly. It does **not** assert that eleven unrun scenarios passed.

**Round 1 recorded 6/16 in its matrix; this round records 5/16 runtime-proven.** That is W3's
correction, not a regression: round 1 counted scenario 2 as compliant and then flagged its own
rounding-up. Scenario 2 asserts a property of the **extracted published zip**, and `ditto`, export
and notarization sit between the build and that zip. No scenario moved from proven to unproven.

**Honesty statement (task 7.8, discharged).** The five `BundleNamingTests` cases prove the pipeline
is **composed** to produce `Home-Cellar.app`. They are not scenario runners. `release.sh` and
`release.yml` run end-to-end only at the `v1.2.0` tag, and the three tap `ci-gate` scenarios only
when the tap's own `ci.yml` runs on the merged PR. **This report does not claim `release.sh` is
verified end-to-end, and does not claim the pipeline is verified.**

---

### Correctness (Static + Runtime Evidence)

| Requirement | Status | Notes |
|------------|--------|-------|
| R1 — a pushed tag is the only thing that produces a downloadable release | ✅ Implemented | `release.yml:159` inspects `build/export/Home-Cellar.app`; `release.sh:280` emits `Home-Cellar-$VERSION.zip`; trigger surface unchanged and unit-proven. |
| R2 — the delivered build is installable through the tap | ⚠️ Implemented; landing pending | Every in-repo obligation is met (no `target:`, no old-path zap entry, no migration text anywhere). Satisfaction requires the post-release atomic tap commit — Phase 7 by design, not an omission. |
| R3 — uninstalling states exactly what it removes, and what it cannot | ✅ Implemented | All four scenarios unit-proven this round; inventory and both Keychain items unmoved. |

**Requirements: 3/3 addressed.** All three are implemented and verified to their declared classes.
R2's *landing* edge — the atomic post-release tap commit — is Phase 7 by design, exactly as
`m6-cask-tap` deferred its two `manual-evidence` steps while recording `requirements: 2/2`. That
deferral is tracked as **W4**, not as an unmet requirement.

---

### Coherence (Design)

Spot-checked against `design.md`, not assumed.

| Decision | Followed? | Evidence |
|----------|-----------|----------|
| DD-1 — pin `PRODUCT_MODULE_NAME = cellar` so the Swift module never becomes `Home_Cellar` | ✅ Yes | `PRODUCT_MODULE_NAME = cellar;` ×2 in `project.pbxproj`; `PRODUCT_NAME = "Home-Cellar";` ×2. 22 real `@testable import cellar` lines under `cellarTests/` (the 23rd `rg` hit is the doc comment at `BundleNamingTests.swift:118`) — unchanged, zero Swift source edits. |
| DD-4 — `cellar.xcarchive` deliberately stays on `SCHEME` | ✅ Yes | `release.sh:51` `ARCHIVE_PATH="$BUILD/$SCHEME.xcarchive"`; `:123` `-scheme "$SCHEME"`. Exactly two `$SCHEME` sites remain. |
| DD-5 — hyphenated values quoted, `PRODUCT_MODULE_NAME` bare | ✅ Yes | `PRODUCT_NAME = "Home-Cellar";` quoted; `PRODUCT_MODULE_NAME = cellar;` bare. |
| DD-7 — both app-target blocks edited identically | ✅ Yes | `ReleaseMetadataTests/appTargetConfigurationsAreIdenticalModuloName()` passed this round. |
| DD-8 — no cross-repository reach from the app repo | ✅ Yes | `rg 'homebrew-cellar\|repository_dispatch' .github/workflows/release.yml` → zero hits; `theWorkflowGainsNoCrossRepositoryReach()` passed. |
| Product/scheme separation in `release.sh` | ✅ Yes | `:36 readonly PRODUCT="Home-Cellar"`; `:53`, `:55` use `$PRODUCT.app`; `:153`, `:241` use `MacOS/$PRODUCT`. |
| Display-name gate untouched | ✅ Yes | `release.sh:250-251` still asserts `CFBundleDisplayName` == `Home-Cellar`; absent from the diff. |
| Deviation: `release.sh` gained 5 lines, not 1 (rationale comment) | ⚠️ Accepted | Cosmetic, matches the file's existing comment density; breaks no spec. |
| Deviation: Xcode re-serialized the scheme's three `BuildableName` lines | ⚠️ Accepted | Resulting bytes are exactly what design §2 specifies; `BlueprintName = "cellar"` ×3 intact. |

---

### R5 Probe — Re-run Independently by This Phase

```text
$ xcodebuild -project cellar.xcodeproj -target cellar -showBuildSettings | rg '…'
EXECUTABLE_NAME = Home-Cellar
FULL_PRODUCT_NAME = Home-Cellar.app
PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar
PRODUCT_MODULE_NAME = cellar
PRODUCT_NAME = Home-Cellar
```

Byte-identical to the block `tasks.md:445-451` records. Against the Phase 0.1 pre-change baseline,
exactly the three permitted lines moved (`EXECUTABLE_NAME`, `FULL_PRODUCT_NAME`, `PRODUCT_NAME`);
`PRODUCT_BUNDLE_IDENTIFIER` and `PRODUCT_MODULE_NAME` are unchanged. **R5 closed independently.**

---

### Invariants

| Invariant | Measurement | Verdict |
|---|---|---|
| Bundle identifier never moves | `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;` ×2 in pbxproj; built `Info.plist` `CFBundleIdentifier` → `com.juancasanueva.cellar` | ✅ HELD |
| Swift module name never moves | `PRODUCT_MODULE_NAME = cellar;` ×2; 22 `@testable import cellar` files unchanged | ✅ HELD |
| Zero `CellarCore` / app-source diff | `git diff --stat main -- Packages/CellarCore/ cellar/` → **empty** | ✅ HELD |
| pbxproj identity keys untouched | `git diff main -- …project.pbxproj \| rg '^[-+]' \| rg 'PRODUCT_BUNDLE_IDENTIFIER\|TEST_TARGET_NAME\|remoteInfo\|productName'` → **empty** | ✅ HELD |
| Case-sensitive `cellar.app` sweep — app repo | pbxproj **0** · scheme **0** · `README.md`/`RELEASING.md`/`PRD.md` **0** | ✅ HELD |
| Case-sensitive `cellar.app` sweep — tap clone | whole clone → **0 hits** | ✅ HELD |
| Built product identity | `Home-Cellar.app/Contents/MacOS/Home-Cellar` present and executable; `CFBundleDisplayName` / `CFBundleExecutable` / `CFBundleName` all `Home-Cellar`; no `cellar.app` in the same Debug products directory | ✅ HELD |
| No migration mechanism | `rg 'target:' Casks/` → 0; zap inventory carries no `/Applications/cellar.app`; no migration prose in either repo | ✅ HELD |
| `bump.yml` untouched | `git diff --stat origin/main -- .github/workflows/bump.yml` → empty | ✅ HELD |
| Out-of-scope files untouched | Branch diff is exactly 15 files: `release.yml`, `PRD.md`, `README.md`, `RELEASING.md`, `project.pbxproj`, `cellar.xcscheme`, `BundleNamingTests.swift`, `CaskZapInventoryTests.swift`, `release.sh`, and 6 SDD artifacts. No Swift source, no `CellarCore` | ✅ HELD |

---

### Hybrid Store Integrity

Engram twins hashed directly out of the observation store and compared with the OpenSpec files.

| Artifact | OpenSpec file `sha256` | Engram `sha256` | Match |
|---|---|---|---|
| `specs/release-distribution/spec.md` (#7748) | `da81a80b3c9d3ae5…5d13ea0f` | `da81a80b3c9d3ae5…5d13ea0f` | ✅ byte-identical |
| `tasks.md` (#7750) | `d6ab3938026d51c6…9a6849be` | `d6ab3938026d51c6…9a6849be` | ✅ byte-identical |
| `apply-progress.md` (#7751) | `3f276381e6eba985…aefa26c18` | `3f276381e6eba985…aefa26c18` | ✅ byte-identical |

Hybrid mode is intact; neither side has drifted.

---

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ✅ | `apply-progress.md` carries a complete TDD Cycle Evidence table |
| All tasks have tests | ✅ | 6/6 behavioural tasks (2.2, 2.3, 2.4, 3.1, 4.1, 5.1) |
| RED confirmed (test files exist) | ✅ | `BundleNamingTests.swift` (240 lines, new) and `CaskZapInventoryTests.swift` (18 changed lines) both present |
| GREEN confirmed (tests pass now) | ✅ | All 5 `BundleNamingTests` cases and all `CaskZapInventoryTests` cases passed in this round's run |
| RED proven by runner output | ✅ | 13 verbatim expectation messages recorded, pulled from the `.xcresult` rather than the console summary |
| Triangulation adequate | ✅ | Every absence assertion is paired with a presence assertion in the same test |
| Safety net for modified files | ✅ | 242/242 baseline recorded before the first edit; guard suites re-run at each unit |

**TDD Compliance**: 7/7 checks passed.

---

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|-------|-------|-------|-------|
| Unit (source-scanning) | 5 new + 1 updated | 2 | swift-testing |
| Integration | 0 new | — | swift-testing (none applicable to build-system composition) |
| E2E | 0 new | — | XCUITest (exists; no new cases) |
| **Total new/changed** | **6** | **2** | |

No integration or E2E layer exists for build-system composition. The `xcodebuild build` +
built-bundle inspection is the higher layer that does exist, and it ran.

---

### Assertion Quality

Audited every assertion in both changed test files.

| Pattern checked | Found | Notes |
|---|---|---|
| Tautologies (`#expect(true)`) | 0 | — |
| Assertions with no production-code read | 0 | Every assertion reads a real repository file through `BundleNamingSources.text(_:)` |
| Orphan absence assertions | 0 | Each `== 0` is paired with a presence assertion in the same test: `:154`↔`:153`, `:177`↔`:176`, `:212-213`↔`:215-216`, `:238`↔`:237` |
| Type-only assertions | 0 | All are exact counts or literal `contains` |
| Ghost loops | 0 | No loop-scoped assertions over possibly-empty collections in the new file |
| Case-insensitive widening | 0 | `:94` is a doc comment explaining why `caseInsensitiveCompare` is deliberately **not** used; the capital `C` is the assertion (task 2.5, R6) |
| Anti-overreach guards | 3 | `blocks.count == 2`, `BlueprintName = "cellar"` ×3, `-scheme "$SCHEME"` present — each catches a rename that leaked too far |

**Assertion quality**: ✅ All assertions verify real behaviour. 0 CRITICAL, 0 WARNING.

---

### Quality Metrics

**Linter** (`swiftlint 0.65.0`, no `.swiftlint.yml`): 2 warnings in `CaskZapInventoryTests.swift`
(`:279` line_length, `:270` trailing_comma). Both are **pre-existing** — reproduced identically at
`main` on the same line numbers — and lie outside this change's edited ranges (`334-349`).
`BundleNamingTests.swift` is clean. **No new lint warnings.**

**Type checker**: compiler-enforced; `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **` cover it.

---

### Commit Hygiene

| Check | App repo | Tap repo |
|---|---|---|
| Nothing pushed | ✅ `git ls-remote --heads origin feat/m8-bundle-rename` → 0; no upstream configured | ✅ → 0 |
| `main` untouched | ✅ still `f0a5817` | ✅ `origin/main` still `5e02b96` |
| Working tree clean | ✅ only the untracked `verify-report.md` | ✅ clean |
| Conventional commits | ✅ 7 commits: `docs(sdd)` ×3, `feat(build)`, `fix(release)`, `fix(ci)`, `docs(release)` | ✅ 1 commit: `fix(cask)` |
| No `Co-Authored-By` | ✅ zero | ✅ zero |
| No AI attribution | ✅ zero (`claude`, `anthropic`, `generated with` all absent) | ✅ zero |
| Author | ✅ `Juan Casanueva <juancasanueva@gmail.com>` | ✅ same |

---

## Issues Found

### CRITICAL

**None.** Round 1's C1 is closed on the merits; see the consistency proof above.

### WARNING

**W4 — The held tap commit is *prepared*, not yet *atomic*. `sdd-archive` must not treat `7c50ee6`
as already satisfying R4.**

`Casks/home-cellar.rb` on `feat/m8-bundle-rename` currently reads `version "1.1.0"`,
`sha256 "a6d5c68d…"` and `app "Home-Cellar.app"`. Those three do **not** describe the same release:
the v1.1.0 asset contains `cellar.app`, which I re-measured. As it stands, the branch head is
precisely the "audits clean, installs broken" cask that R4 forbids.

This is **not** a defect in the remediation — it is the correct intermediate state, and it is well
guarded: the branch is unpushed, the commit message's second line is "HOLD — DO NOT MERGE before the
renamed release publishes", and `tasks.md:500` (7.3) mandates amending the commit so `version`,
`sha256` and `app` move together.

The hazard is a hand-off one. Round 1's remediation is described in several places as "the atomic
tap commit", and `apply-progress.md` lists task 1.5 as `[x] DONE`. A reader who merges or
fast-forwards `7c50ee6` as-is, on the strength of that phrasing, reproduces C1 exactly. Archive
should record R4's text as *not yet discharged by the tap*, and keep 7.1–7.5 open.

### SUGGESTION

**S3 — S1's accepted reconciliation did not propagate to three sites that still say "247 distinct
ids".** `apply-progress.md:25-26` states it correctly ("237 distinct functions / 247 executed
cases"). But `apply-progress.md:119` ("247/247 in `cellarTests`"), `apply-progress.md:144` and
`tasks.md:424` ("247 distinct ids, 247 Passed") retain the imprecise phrasing, and "247 distinct
ids" is measurably wrong — I counted **237** distinct test-case identifiers from the `.xcresult`
tree. Harmless today, but these artifacts are about to be archived as the audit trail, and the next
slice's baseline comparison is exactly where a false discrepancy would surface. A one-word fix at
each of the three sites.

**S4 — S2's decline is recorded in `apply-progress.md:27` but not in `tasks.md` Phase 8, which is
the list `sdd-archive` actually reads.** The decline itself is legitimate (the wording lives in
`design.md`, outside a scoped remediation's edit surface). But Phase 8 enumerates the archive
obligations (8.1 R7, 8.2 the verification-class table, 8.3 the delta shape, 8.4 the PRD milestone)
and carries no entry for the `design.md:216` "guard" → "filter" rewording. Adding an 8.5 would keep
the deferral from evaporating between phases.

---

## Verdict

**PASS WITH WARNINGS** — the implementation is correct, complete and design-conformant; the suites
and the build are green; every invariant holds; the hybrid store is byte-consistent; and round 1's
blocker is genuinely resolved by a mechanism I verified against the published asset, `bump.yml`, the
held commit and the task ledger rather than against the remediation's own claims.

Round-1 closure: **1/1 CRITICAL closed · 3/3 WARNING closed · 2/2 SUGGESTION dispositioned**
(S1 accepted and independently confirmed, S2 declined with a genuine reason).

Archive-ready, with three things carried forward for `sdd-archive`:

1. **W4 — do not treat `7c50ee6` as discharging R4.** Keep Phase 7 (7.1–7.7) open. The tap commit is
   prepared and correctly held, but it is not yet the atomic `version`+`sha256`+`app` commit the
   requirement mandates; that amend is task 7.3.
2. **S3, S4** — two artifact-hygiene items in the about-to-be-archived audit trail.
3. **The R7 hand-edits** (`:567`, `:601`, `:619`, `:686-688`, `:706`, `:718-720`) and the
   `## Verification classes` table update to `unit` 18 / `ci-gate` 18 / `manual-evidence` 6 (total
   **42**), confirmed by counting `- Verification:` lines in the merged file rather than trusting the
   note. `:601` is the urgent one — it contradicts the merged requirement in the present tense.

Nine `ci-gate` and two `manual-evidence` scenarios remain execution-pending by declared class. They
are discharged by the `v1.2.0` release run and the tap CI, not by this report. **This report does not
claim `release.sh` is verified end-to-end, and does not claim the pipeline is verified.**
