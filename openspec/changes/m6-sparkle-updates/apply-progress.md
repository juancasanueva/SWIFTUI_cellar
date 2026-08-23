# Apply progress: `m6-sparkle-updates`

Batch 1 (and only batch). Executor: `sdd-apply`. Branch `feature/m6-sparkle-updates` from `main`
`215540b`. Mode: **Strict TDD** (`strict_tdd=true`, no fallback taken). Artifact store `hybrid`.
Delivery `exception-ok` — **one PR under `size:exception`**, per the Q4 block in `tasks.md`.
RDD disabled clone-local; no review started.

Native attempt ledger: `gentle-ai sdd-attempt acquire --work-unit apply-3a-3b` with the
orchestrator's token → `state: proceed`, zero ledger mutation. **Not settled by this executor.**

**66 of 69 tasks complete.** The three that remain (`B4.5`, `B4.6`, `B4.7`) are `manual-evidence`
observations that cannot exist before a tag is pushed. They are not merge blockers.

---

## Test counts

| Runner | Before | After | Δ | Failures |
|---|---|---|---|---|
| `xcodebuild … -only-testing:cellarTests` | **183** distinct `Test case '…' passed` | **215** | **+32** | 0 |
| `swift test --package-path Packages/CellarCore` | **1732** tests / 204 suites (1 known issue) | **1753** / 209 suites (1 known issue) | **+21** / +5 suites | 0 |

Counted byte-oriented from the raw `xcodebuild` log (`rg -o "Test case '[^']+' passed" | sort -u | wc -l`),
because `xcodebuild` tears lines and the `Executed 0 tests` lines are XCTest noise. The one CellarCore
known issue is pre-existing and unrelated.

`swift build --package-path Packages/CellarCore`: clean.
`xcodebuild build -scheme cellar`: `** BUILD SUCCEEDED **`.

---

## TDD Cycle Evidence

Every row's RED was **executed and observed failing** before its implementation existed, and every
GREEN was **executed and observed passing**. Layer `unit-app` = `cellarTests`, `unit-core` =
`Packages/CellarCore/Tests/UpdatesTests`.

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| A1.1 T12(a) | `cellarTests/UpdateProjectFileTests.swift` | unit-app | 183/183 | ✅ observed `appTargetsDeclareTheApplicationCategory()` **failed** | ✅ passed after item 6 | ➖ count==2 over both blocks is the second case | ➖ |
| A1.2 T11 | `cellarTests/BundleUpdateKeysTests.swift` | unit-app | N/A (new) | ✅ observed `bundleReportsApplicationCategory()` **failed** | ✅ passed | ➖ single exact value | ➖ |
| A2.1 T12(b) | `UpdateProjectFileTests` | unit-app | ✅ 2/2 | ✅ observed `projectLinksThePinnedSparklePackage()` **failed** | ✅ passed after items 1–5 | ✅ 5 independent counts + the `PBXCopyFilesBuildPhase == 0` pin | ✅ extracted `section`/`objectBlocks`/`occurrences` |
| A3.3 T12(7) | `UpdateProjectFileTests` | unit-app | ✅ 3/3 | ✅ item 7 **reverted** to author the pin, observed `appTargetsMergeThePartialPropertyList()` **failed**, then re-applied | ✅ passed | ➖ paired with `GENERATE_INFOPLIST_FILE` | ➖ |
| A3.1 T10 | `BundleUpdateKeysTests` | unit-app | ✅ 1/1 | ✅ observed `bundleCarriesTheFeedAndVerificationKey()` **failed** (and stayed red across A3.3, by design) | ✅ passed on the real key at A3.5 | ✅ exact feed string + scheme + 32-byte decode | ➖ |
| A3.2 T22 (bundle) | `BundleUpdateKeysTests` | unit-app | ✅ 2/2 | ✅ observed `partialPropertyListCarriesOnlyTheFeedAndTheKey()` **failed** | ✅ passed at A3.3 | ✅ exact key set + three absent framework keys + bundle-identity non-vacuity | ➖ |
| A3.6 T20 | `cellarTests/UpdateKeyMaterialTests.swift` | unit-app | ✅ 3/3 | ✅ observed **failed** with zero literals (placeholder deliberately not base64-shaped) | ✅ passed on the real key | ➖ exact-count form is the whole assertion | ➖ |
| A4.1 T24 | `cellarTests/UpdatePackageManifestTests.swift` | unit-app | ✅ 205/205 (app) | ✅ observed both **failed** | ✅ passed once the target compiled (A4.4) | ✅ `ReleaseNotes` counter-example proves the reader can see a real `dependencies:` | ➖ |
| A4.3 T1/T2/T7a | `Tests/UpdatesTests/AppVersionTests.swift` | unit-core | N/A (new target) | ✅ target empty → package failed to build | ✅ 5 tests / 14 cases passed | ✅ 4-row ordering table, 5 malformed shapes, 5 raw pairs | ✅ replaced two 3-member tuples with `MalformedShape`/`RawPair` (swiftlint `large_tuple`), tests re-run green |
| A4.5 T3/T4/T5 | `Tests/UpdatesTests/AppcastDocumentTests.swift` | unit-core | ✅ 5/5 | ✅ observed `cannot infer contextual base in reference to member …` for every failure case | ✅ 3 tests / 15 cases passed | ✅ 13 rejection fixtures + 1 valid + 1 merged-history | ➖ |
| A4.7 T6 | `Tests/UpdatesTests/UpdateCheckPresentationTests.swift` | unit-core | ✅ 8/8 | ✅ observed `'nil' requires a contextual type` | ✅ 4 tests passed | ✅ 3 offsets → 3 distinct labels, plus purity and absent→present | ➖ |
| A4.9 T7 | `Tests/UpdatesTests/AppUpdatingTests.swift` | unit-core | ✅ 12/12 | ✅ observed `cannot find type 'AppUpdating' in scope` | ✅ 4 tests passed | ✅ 4 behaviours, each with its counter-case | ✅ `FakeAppUpdater` gained a write counter for A4.11 |
| A4.11 T7b/T7c | `Tests/UpdatesTests/UpdatePolicyTests.swift` | unit-core | ✅ 16/16 | ✅ observed `cannot find 'AutomaticUpdateChecksPolicy' in scope` | ✅ 5 tests / 7 cases passed | ✅ both preference directions, the idempotent case, both enablement values | ➖ |
| A5.1 T12(c) | `UpdateProjectFileTests` | unit-app | ✅ 3/3 | ✅ observed `projectLinksTheUpdatesProduct()` **failed** | ✅ passed after items 8–10 | ✅ 3 counts + the "no `package =` back-reference" distinction from Sparkle | ➖ |
| A6.1 T13 | `cellarTests/AutomaticUpdateChecksTests.swift` | unit-app | ✅ 205/205 | ✅ observed `cannot find 'AutomaticUpdateChecks' in scope` | ✅ 4 tests passed | ✅ fresh/round-trip/stored-false/exact-one-key | ➖ |
| A6.3 T8/T9/T21/T22(struct) | `cellarTests/UpdateCompositionTests.swift` | unit-app | ✅ 209/209 | ✅ observed 4 of 5 **failed** (T21 green-on-arrival, stated) | ✅ all passed after A6.4 | ✅ per-type sweeps + checker counter-assertions | ➖ |
| A6.5 T23 | `UpdateCompositionTests` | unit-app | ✅ 5/5 | ✅ observed `theCommandIsAddedAfterTheAboutItem()` **failed** | ✅ passed after A6.9 | ✅ asserts `after:` present, `replacing:` absent, and `AboutCommands` keeps its own `replacing:` | ➖ |
| A6.7 T25 | `UpdateCompositionTests` | unit-app | ✅ 6/6 | ✅ observed `theUpdatesGroupDeclaresExactlyTwoRows()` **failed** | ✅ passed after A6.8 | ✅ identifier **count**, not just presence, plus no `Picker`/no channel wording | ➖ |
| B1.1/B1.2 T18/T19 | `cellarTests/AppcastScriptContractTests.swift` | unit-app | ✅ 215/215 | ✅ observed **all 7 failed** | ✅ all 7 passed | ✅ 7 independent properties over the script | ✅ trace prohibition moved to command-token matching |
| B2.1/B2.2 T16/T17 | `cellarTests/AppcastWorkflowTests.swift` | unit-app | ✅ 7/7 | ✅ observed **all 4 failed** | ✅ all 4 passed | ✅ ordering, all four guards, job header, secret binding shape | ➖ |
| B2.3 T14 | `cellarTests/ReleasePipelineCompositionTests.swift` | unit-app | ✅ 12/12 | ✅ observed `workflowReferencesExactlyTheExpectedSecrets()` **failed** on the six-name set | ✅ passed on seven | ➖ set equality | ➖ |
| B2.4 T15 | `ReleasePipelineCompositionTests` | unit-app | ✅ 12/12 | ⚠️ **not RED** — see deviation 4 | ✅ passes | ➖ | ➖ |

### Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused test command / result | `xcodebuild test … -only-testing:cellarTests` → **215 passed, 0 failed**; `swift test --package-path Packages/CellarCore` → **1753 passed / 209 suites, 0 failed** |
| Runtime harness / result | **U30** `scripts/release.sh all` → notarization **Accepted**, `codesign --verify --strict` green over the whole nested Sparkle tree (below). **Appcast script harness** → guard, fetch-404, digest-verify, extract, merge and emit all exercised for real (below). **`shellcheck scripts/appcast.sh`** → no findings, exit 0. **`actionlint .github/workflows/release.yml`** → no output, exit 0. `xcodebuild build` → BUILD SUCCEEDED with `Sparkle.framework` embedded |
| Rollback boundary | `git revert` of the PR. The ten pbxproj items back out together; `Resources/`, `scripts/appcast.sh`, `cellar/Updates/`, `Packages/CellarCore/{Sources,Tests}/Updates*` are net-new deletions; three app files and three docs revert in place. Orphaned and inert afterwards: the `updates.automaticChecksEnabled` key, Sparkle's own `SU*` defaults, the resolved package cache. **The private key must be retained** — re-landing must reuse the same `SUPublicEDKey` or it strands every copy shipped in between |

---

## Manual evidence

| # | Command | Result |
|---|---|---|
| **M1 / U30** | `VERSION=1.0.0 BUILD_NUMBER=1 ASC_KEY_PATH=… scripts/release.sh all` | **PASS.** `** ARCHIVE SUCCEEDED **`, `** EXPORT SUCCEEDED **`, notarization `{"status":"Accepted","id":"593818bf-c3db-460d-b674-3db6078732b6"}`, staple validated, `build/verify/cellar.app: accepted / source=Notarized Developer ID`, `valid on disk`, `satisfies its Designated Requirement`. `codesign --verify --strict --verbose=2` re-run explicitly over each nested object: `Versions/B/Sparkle`, `Versions/B/Autoupdate`, `Versions/B/Updater.app`, `Versions/B/XPCServices/Downloader.xpc`, `Versions/B/XPCServices/Installer.xpc` — **all five** *satisfy their Designated Requirement*. The gate was not relaxed |
| **M2 / U31** | `lipo -archs build/verify/cellar.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle` | `x86_64 arm64` on the **exported, notarized** bundle. `lipo -archs …/Contents/MacOS/cellar` → `arm64`. The `release-distribution` reword is load-bearing; the app executable's own arm64 claim is unaffected |
| **M3 / U32** | `find build/verify/cellar.app/Contents \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' \) -print` | **Empty** on the exported bundle. U32 stays withdrawn; `release.sh:252-254` untouched |
| **B4.1** | `gh secret list` | `SPARKLE_PRIVATE_KEY` present (2026-08-23T07:33:58Z). Seven secrets total. Private key backed up offline by the maintainer |
| **B4.2** | `gh api repos/juancasanueva/SWIFTUI_cellar --jq .has_pages` | `true`; `build_type: workflow`; site `https://juancasanueva.github.io/SWIFTUI_cellar/`. **Deployment-branch policy is a blocker — see deviation 1** |
| **W11** | `gh api repos/actions/<action>/releases/latest` | `configure-pages` **v6.0.0**, `upload-pages-artifact` **v5.0.0**, `deploy-pages` **v5.0.0`. Written as v6/v5/v5, not the proposal's unverified v5/v3/v4 |
| **U25 / sign_update stdin** | — | Not re-run. Cited from the design *Probe addendum* as instructed |

### Appcast script runtime harness

Run against a copy of the real script with **only** the signing line stubbed, because the private key
is not available to this executor and never will be.

- Guard: `GITHUB_REF_NAME=v0.0.1-rc.2 … scripts/appcast.sh` → `prerelease v0.0.1-rc.2: no appcast item`, exit 0, **no output directory created**.
- First run (no live feed): `curl` 404 → empty channel synthesised; tarball digest `52bf9e88…e192` verified `OK`; one item emitted.
- Second run (feed = the first run's output): **two items, `1.1.0` then `1.0.0`**, newest first, nothing dropped — the property `AppcastDocument` validation requires and DD-9 depends on.
- The emitted document is byte-shaped exactly like `Tests/UpdatesTests/Fixtures/valid-merged-history.xml`, which the offline validator accepts.

**Unexercised locally, stated rather than smoothed:** the real `sign_update` invocation. It needs the
private key, which is a repository secret only. M5/M6/M7 cover it at the first stable tag.

---

## Deviations and discoveries — reported, not absorbed

1. **🔴 BLOCKS THE FIRST PUBLISHING TAG — the `github-pages` environment excludes tag refs.**
   `gh api …/environments` shows `github-pages` with `custom_branch_policies: true` and exactly one
   policy: `{"name":"main","type":"branch"}`. The release job runs on **tag** refs (`v*`), so
   `deploy-pages` will be rejected. This is the condition `B4.2` was told to check for. **DD-13's
   second-job fallback does not fix it** — a second job on the same tag ref hits the same policy; the
   fallback addresses protection *rules* on the release job, not a *ref* policy. The fix is a
   repository settings change, not code: Settings → Environments → `github-pages` → Deployment
   branches and tags → add a **tag** rule matching `v*`. Recorded in `RELEASING.md` §2 prerequisite 6
   and left for the maintainer. Everything else in the publication path is in place.
2. **pbxproj is 29 insertions, not the design's ≈28.** The ten items are exactly the ten items, no
   eleventh key, both app-target blocks byte-identical modulo `name`. The design's own itemisation of
   the Sparkle dependency sums to **19** (1 + 1 + 1 + 11 + 5) while its prose says 18; the measured
   diff is 19, so the totals become 21 after item 6, 23 after item 7, and **29** with D-1's six. An
   arithmetic slip in the design, not a scope change.
3. **Xcode rewrote `project.pbxproj` on first build.** It quotes `INFOPLIST_FILE = "Resources/Cellar-Info.plist";`
   (the value contains a hyphen) and sorts `XCSwiftPackageProductDependency` by object identifier.
   The canonical serialisation was adopted and the test pins the **quoted** form; pinning the
   unquoted one would have passed exactly once. Net line count unchanged.
4. **T15 (`secretsAppearOnlyAsEnvironmentBindings`) was green on arrival.** The design's `>= 6 → >= 7`
   bump is a non-vacuity floor, and the workflow already carried **10** secret-reference lines (11
   now) because the App Store Connect bindings repeat per step. The bump was made as specified; it
   was never RED, and this is recorded rather than presented as a TDD cycle.
5. **`AppcastValidationFailure` gained two cases the design's enumeration omitted.**
   `.missingVersion(item:)` and `.missingShortVersionString(item:)`. Spec scenario AU-S12 requires
   validation to fail "naming the missing field" and the design's case list had no case for it.
   `.malformedDocument` was also added for XML that does not parse at all. Absent and unreadable share
   `.missingShortVersionString`, pinned explicitly by its own fixture so the sharing is a decision.
6. **The design's placeholder plist does not parse.** `<string><!-- … --></string>` fails
   `PropertyListSerialization` with *"Encountered improper CDATA opening"*. The comment was moved
   outside the `<string>` element and the placeholder value made deliberately non-base64. Moot now
   that the real key has landed, but it would have blocked the build as written.
7. **BSD `awk -v` rejects a newline inside a value.** Found by *running* `appcast.sh`, not by reading
   it. The design's merge shape would have failed on the first real tag, on the macOS runner. The item
   now goes through a file and is read with `getline`.
8. **`appcast.sh` now checks the signing tool's output shape.** T19 requires the literals
   `sparkle:edSignature` and `length=` in the script, but with the `$FRAGMENT` approach neither
   appears — both come from `sign_update`. Rather than satisfy the test with a comment, the script
   asserts both attributes are present in the fragment and aborts otherwise. A tool whose output shape
   changed would otherwise publish an item every installed copy rejects.
9. **`UpdatesSettingsGroup` reproduces `SettingsView`'s card shape instead of borrowing it.**
   `group(_:rows:)` and `row(label:sub:accessory:)` are `private` to `SettingsView`. Reproducing ~25
   lines keeps the rollback boundary at one file plus one line; the alternative was making the helpers
   internal, which widens the blast radius on an existing file.
10. **`AppVersion`'s two initialisers are `init(parsing:buildNumber:)` and
    `init?(shortVersionString:buildNumber:)`.** The design listed `init(parsing:) throws`; the build
    number is defaulted rather than split into a third initialiser, so the surface still has exactly
    two and the non-numeric-build shape gets its own named failure case as T2 requires.
11. **AU-S1 is discharged as the version triple plus the build number**, not as a `marketingVersion`
    string, because the design fixed the API surface at `major/minor/patch/prerelease/buildNumber`.
    Same claim, no surface growth.
12. **`AppTestUpdater` carries no dedicated T.** "No UI-test launch may construct
    `SparkleUpdateChecker`" is asserted inside `noSurfaceNamesTheConcreteChecker` as a green-on-arrival
    pin over `AppTestFixtures.swift`, following the house precedent for `appSourcesCarryNoReleaseInfrastructure`.
13. **PR size.** `git diff main --stat` → **6,436 insertions, 24 deletions = 6,460 changed lines**,
    against the forecast ceiling of ≈6,411 and the 5,000 budget. Within the accepted
    `size:exception`, overrun ≈1,460 lines rather than the recorded ≈1,411.
14. **`A7.2` moved into `B3.1`**, as `tasks.md` specifies under option (B). The
    `LSApplicationCategoryType` follow-up at `RELEASING.md:251-254` is deleted there.

### Binding constraints, verified

- **Untouched, 0-line diffs:** `scripts/release.sh`, `scripts/ExportOptions.plist`,
  `cellar/Shell/AboutView.swift`, `cellar/InfoPlist.xcstrings` — confirmed by
  `git diff main --stat` returning nothing for all four.
- `theWorkflowCanOnlyEverCreateARelease` passes **unamended**: `gh == 1`, `git == 0`.
- `appTargetConfigurationsAreIdenticalModuloName`, `appSourcesCarryNoReleaseInfrastructure`,
  `repositoryCarriesNoCredentialMaterial` all still green.
- Nothing new under `cellar/` except `.swift`.
- `Updates` target concurrency posture: no `nonisolated(unsafe)`, no `@unchecked Sendable`, no
  `Task.detached`, no `#available` (swept, zero hits).
- swiftlint clean on every new file. One accepted warning class: `optional_data_string_conversion` in
  `UpdateKeyMaterialTests`, matching the identical accepted warning in
  `ReleasePipelineCompositionTests:448` for the same repository sweep.

---

## Commits

| SHA | Subject |
|---|---|
| `b5bb0fc` | `docs(sdd): plan m6-sparkle-updates` |
| `9332ffe` | `build(app): declare the developer-tools application category` |
| `53720aa` | `build(app): link Sparkle 2.9.6 as a pinned package dependency` |
| `ae9aa14` | `build(app): merge a partial property list carrying the update feed` |
| `85807be` | `test(updates): pin the repository to one Ed25519-shaped literal` |
| `7481b4e` | `build(app): commit the real Sparkle public verification key` |
| `b355ef4` | `feat(updates): add a dependency-free Updates target to CellarCore` |
| `8d0b7d1` | `build(app): link the CellarCore Updates product` |
| `2725b7a` | `feat(updates): add the Updates settings card, menu command and wiring` |
| `3ef89c9` | `docs(third-party): attribute the embedded Sparkle framework` |
| `b7ea75a` | `feat(release): add the appcast build script` |
| `0c96f4c` | `ci(release): publish the appcast to GitHub Pages on a stable tag` |
| `b893c54` | `docs(release): document the update feed, its key and its prerequisites` |

Not pushed. No PR opened. No `Co-Authored-By` or AI-attribution trailers. `build/` never staged.

---

## Remaining

| Task | Why it cannot be done here |
|---|---|
| `B4.5` — M4 / U33 | `curl -fsSI …/appcast.xml` → 200 requires a completed `deploy-pages` run, which requires a pushed stable tag **and** deviation 1 resolved |
| `B4.6` — M5 / M6 / M7 | rc-installed → stable-published upgrade, Gatekeeper-offline relaunch, and the job-log key sweep all require a published stable tag |
| `B4.7` — RD-a2 | requires a pushed prerelease tag to observe the four steps being skipped |

`next_recommended: sdd-verify`.
