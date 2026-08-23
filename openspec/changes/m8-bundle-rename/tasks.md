# Tasks: One Name on Disk — `cellar.app` → `Home-Cellar.app` (`m8-bundle-rename`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`chain_strategy=n/a (single-pr)`, `review_budget_lines=5000`, `strict_tdd=true`, RDD disabled
clone-local.

Inputs: `design.md` (R5 pre-probe **MEASURED**, DD-1…DD-8, the five-section edit plan with exact
lines, RED units 1–5, the verification plan's gates 0–8, delivery and rollback), the delta
`specs/release-distribution/spec.md` (**3 MODIFIED requirements / 16 scenarios** — `unit` 5,
`ci-gate` 9, `manual-evidence` 2), `proposal.md`, `explore.md`, and Engram `#7746` (**D1** no
installed base / no migration, **D2** all three defaults accepted). Nothing below re-litigates them.

Size note: this artifact exceeds the generic 530-word phase budget, matching the house precedent at
`openspec/changes/archive/2026-08-23-m7-tap-trust/tasks.md:15`. The slice is a line-by-line rename
across two repositories; re-deriving the inventory would cost more than carrying it.

## Scenario map and what each class can actually prove

**`unit` — 5.** **U1** nothing but a version tag triggers a release · **U2** the documented inventory
covers every source-declared write root · **U3** the two Keychain items are documented as surviving ·
**U4** the install commands are whole lines, name `Home-Cellar.app`, and carry **no other bundle name
and no migration instruction** · **U5** the release run names no other repository. Only **U4** moves
(WU4). **U1, U2, U3, U5 are already-green guards that MUST stay green untouched** — they are the
proof this rename changed neither the trigger surface, nor the uninstall inventory, nor the app
repo's reach.

**`ci-gate` — 9.** Asset name and anonymous reachability · the bundle inside the zip is
`Home-Cellar.app` with executable `Contents/MacOS/Home-Cellar` and identifier
`com.juancasanueva.cellar` · private-repo fail-fast · stable-tag feed · prerelease publishes no feed ·
cask style/offline audit/online strict audit/install-uninstall round trip · **the rename ships no
migration mechanism** · a prerelease never becomes a cask version · bump idempotence. Six run in
`.github/workflows/release.yml` **here** and are reachable only at the next tag; three run in
`juancasanueva/homebrew-cellar`'s `ci.yml` / `bump.yml`.

**`manual-evidence` — 2.** A tap and install put `/Applications/Home-Cellar.app` in place · a
self-updated copy does not fight `brew upgrade`. Both are post-tag, on the maintainer's Mac.

**Honesty binding (design's verification plan, verbatim intent).** The five new tests in
`cellarTests/BundleNamingTests.swift` are **composition proof**, not scenario runners: they prove the
pipeline is *composed* to produce `Home-Cellar.app`. `release.sh` runs end-to-end only at the next
tag. `sdd-verify` MUST report the nine `ci-gate` and two `manual-evidence` scenarios as **composed,
unexercised** and MUST NOT claim the pipeline is verified.

## Review Workload Forecast

| Field | Value |
|---|---|
| Bottom-up lines | **~955–1,330** authored — pbxproj ~20 · scheme ~6 · `release.sh` ~9 · `release.yml` ~2 · app docs ~60 · new `BundleNamingTests.swift` ~130 · `CaskZapInventoryTests` edit ~12 (**code+docs+tests ~240–380**, matching `design.md` *Delivery design*) · spec delta ~180 · SDD artifacts (explore, proposal, design, tasks) ~700–900 |
| Tap repo (separate PR, separate review) | **~14** authored lines — not part of the app-repo total |
| Governing budget | **5,000** (`config.yaml:8` and session preflight agree) |
| Risk vs governing budget | **Low** — ≤27 % at the ceiling |
| Chained PRs recommended | No — one app-repo PR of five work-unit commits plus one artifact commit |
| Suggested split | Single PR on `feat/m8-bundle-rename`. If the maintainer later prefers slices, the natural cut is **WU1** (pbxproj + scheme, the only unit that can break the build) then **WU2–WU4** (scripts, workflow, docs) |
| Sizing label | None. `single-pr` holds without `size:exception`; the forecast sits comfortably inside the governing budget, unlike `m7-tap-trust` |
| Delivery strategy | single-pr |
| Chain strategy | pending (n/a — no chain) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

`400-line budget risk` is the literal guard value against the 400 **default**; that default does not
govern this repository. Against the governing 5,000-line budget the risk is **Low**, so `single-pr`
holds with no `size:exception`, matching the `m6-release-pipeline` / `m6-cask-tap` precedent rather
than `m7-tap-trust`'s post-apply exception.

**App-repo branch**: `feat/m8-bundle-rename`
(`^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)/[a-z0-9._-]+$` ✓).
**App-repo PR title**: `feat(release): name the delivered bundle Home-Cellar.app`.
**Tap-repo branch**: `feat/m8-bundle-rename`.
**Tap-repo PR title**: `fix(cask): install Home-Cellar.app, the bundle the asset now carries`.

### Suggested Work Units (`work-unit-commits`; conventional commits, **no `Co-Authored-By`, no AI attribution**)

RED and GREEN may be separate commits inside a unit (house precedent); tests never leave the unit
whose behaviour they verify.

| Unit | Goal | Commit | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| **WU1** | `project.pbxproj` (`PRODUCT_NAME`, `PRODUCT_MODULE_NAME`, product ref, `TEST_HOST` ×2) + `cellar.xcscheme` `BuildableName` ×3, **plus the blocking R5 post-probe (design's "work unit 0")** | `feat(build): rename the product to Home-Cellar and pin the module name` | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests/BundleNamingTests` | `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` then confirm `build/…/Build/Products/Debug/Home-Cellar.app/Contents/MacOS/Home-Cellar` exists | Revert this one commit: `PRODUCT_NAME` returns to `$(TARGET_NAME)`, `PRODUCT_MODULE_NAME` disappears, and **the module is `cellar` either way** — that is what the pin buys. WU2–WU4 keep compiling because they touch no Swift source |
| **WU2** | `scripts/release.sh` — add `readonly PRODUCT="Home-Cellar"`, move `:48`, `:50`, `:148`, `:236` off `$SCHEME` | `fix(release): separate the product name from the scheme name` | `xcodebuild test … -only-testing:cellarTests/BundleNamingTests/theReleaseScriptSeparatesTheProductFromTheScheme` | N/A — `release.sh` runs end-to-end only at the next tag (design verification plan). Static composition proof is the whole in-repo harness | Revert the commit; `SCHEME` reabsorbs all four roles. No other file references `$PRODUCT` |
| **WU3** | `.github/workflows/release.yml:159` export path | `fix(ci): inspect the renamed export path` | `xcodebuild test … -only-testing:cellarTests/BundleNamingTests/theWorkflowInspectsTheRenamedExportPath` | N/A — tag-triggered workflow, unreachable before the tag | One-line revert |
| **WU4** | `README.md` `:42`, `:49-60`, `:63` · `RELEASING.md` `:265`, `:303`, `:336`, `:348-356` · `PRD.md:194`, **and the deliberate `CaskZapInventoryTests.swift:335` + `:338-342` update (R6)** | `docs(release): document Home-Cellar.app as the one installed bundle` | `xcodebuild test … -only-testing:cellarTests/CaskZapInventoryTests` | N/A — passive documentation plus one source-scanning assertion | Revert the commit; the docs and the assertion move back together, so the test never disagrees with the prose |
| **WU5** | **Tap repo** `/Users/juancasanueva/programming/swiftUI/homebrew-cellar`: `Casks/home-cellar.rb:20`, `.github/workflows/ci.yml` `:77`, `:79`, `:90`, `README.md` `:14`, `:16`, `:29`, `:32` | `fix(cask): install Home-Cellar.app, the bundle the asset now carries` | **None in this repository (DD-8)** — no app-repo test reads the tap clone; `ReleasePipelineCompositionTests:808` asserts the app repo names no other repository and MUST stay green | The tap's own `ci.yml`: `brew style`, `brew audit --cask --online --strict`, and the install/uninstall job against `/Applications/Home-Cellar.app` | Revert the tap commit alone; `app "cellar.app"` returns and `bump.yml` is untouched, so nothing else drifts |

**Ordering edges.**

- **WU5 → the `v1.2.0` tag push (R4 — binding spec text, not a note).** The tap PR MUST be **merged
  before** any `v*` tag that publishes a renamed asset. `bump.yml` runs `17 */6 * * *`, rewrites only
  `version`/`sha256`, and gates on `brew style` + `brew audit` — **neither extracts the archive nor
  resolves the `app` stanza** — so a tag pushed against `app "cellar.app"` yields a cask that audits
  clean and installs broken. **Fallback if the tap PR cannot land first: pause `bump.yml` across the
  window** (disable the schedule, restore it after the tap merges). `bump.yml` itself is otherwise
  untouched; any edit to it reopens R4.
- **WU1 → WU2 / WU3 / WU4 (soft, single-writer).** No compile dependency: the four app-repo units
  touch disjoint files. They share `cellarTests/BundleNamingTests.swift` (WU1 creates it with tests
  1, 2 and 4; WU2 appends test 3; WU3 appends test 5), so they execute **sequentially, one writer**.
  No parallel worktrees.
- **WU1 is atomic and MUST NOT be split.** `PRODUCT_NAME`, `PRODUCT_MODULE_NAME`, the product
  reference and **both** `TEST_HOST` lines land in one commit. A `PRODUCT_NAME` change without
  `TEST_HOST` leaves the test host pointing at a bundle that no longer exists and the whole
  `cellarTests` bundle fails to launch — an intermediate state that is not merely red, it is
  unrunnable.
- **WU5 ∥ WU1–WU4.** Different repository, different PR, no shared file. Schedule it first so R4 is
  satisfied by construction rather than by a checklist item at tag time.
- **Inside every unit**: RED before GREEN, `strict_tdd: true`. Never negotiable.
- **Rollback order** is the reverse: WU5 → WU4 → WU3 → WU2 → WU1. If a tag already shipped, revert
  the **tap first** and re-point it at the last `cellar.app` asset — a reverted app repo against a
  `Home-Cellar.app` cask is R4 inverted.

## Phase 0: Preflight (sequential; no behaviour changes)

- [x] 0.1 **R5 pre-probe — DONE, do not re-run.** `design.md` records the verbatim output measured
      2026-08-23 at `main f0a5817`: `EXECUTABLE_NAME = cellar`, `FULL_PRODUCT_NAME = cellar.app`,
      `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar`, `PRODUCT_MODULE_NAME = cellar`,
      `PRODUCT_NAME = cellar`. That block is the diff baseline for task 1.9.
- [x] 0.2 Measure and **record** the green baseline; do not re-derive it later.
      **MEASURED 2026-08-23 at `main f0a5817`**: `swift test --package-path Packages/CellarCore` →
      `Test run with 1793 tests in 210 suites passed … with 1 known issue`. `xcodebuild test …
      -only-testing:cellarTests` → `** TEST SUCCEEDED **`, **242 distinct test ids, 242 Passed,
      0 failures** (counted from the `.xcresult` via `xcrun xcresulttool get test-results tests`,
      not from a summary line).
      `swift test --package-path Packages/CellarCore` and
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
      Count **distinct** passing test ids — `Executed 0 tests` is meaningless for Swift Testing
      bundles. A different number from any earlier slice is the new baseline, not a defect.
- [x] 0.3 **All anchors confirmed at `main f0a5817`; zero drift.** Confirm every anchor the design pins is still where it says (all were at `main f0a5817`):
      `project.pbxproj` `:38` / `:107` / `:142` / `:446` / `:482` / `:510` / `:531`, and the binding
      unchanged lines `:445` / `:481` / `:504` / `:525` / `:544` / `:563` / `:550` / `:569` ·
      `cellar.xcscheme` `:19` / `:73` / `:104` · `scripts/release.sh` `:31` / `:46` / `:48` / `:50` /
      `:118` / `:148` / `:236` / `:245-246` / `:275` · `.github/workflows/release.yml:159` ·
      `README.md` `:42` / `:49-60` / `:54` / `:63` · `RELEASING.md` `:265` / `:303` / `:336` /
      `:348-356` · `PRD.md:194` · `CaskZapInventoryTests.swift` `:335` / `:338-342` / `:344-354` ·
      `ReleasePipelineCompositionTests.swift` `:94` / `:213-229` / `:519-521` / `:808` ·
      `UpdateProjectFileTests.swift:68`. A moved anchor is a deviation to report, not to absorb.
- [x] 0.4 **Confirmed** — `project.pbxproj:49-53` declares `cellarTests` as a
      `PBXFileSystemSynchronizedRootGroup` and the string `cellarTests/` appears **0** times in the
      pbxproj, so `BundleNamingTests.swift` needs no file-reference edit. Confirm `cellarTests/` is still a `PBXFileSystemSynchronizedRootGroup`, so
      `BundleNamingTests.swift` needs **no** `project.pbxproj` file-reference edit (m7 precedent,
      `archive/2026-08-23-m7-tap-trust/tasks.md:292`). This matters here: RED unit 2 asserts
      `cellar.app` occurs **zero** times in the pbxproj, and an unrelated file reference would be
      noise in that same file.
- [ ] 0.5 `git checkout -b feat/m8-bundle-rename main`, then commit the SDD artifacts **first** so the
      reviewed diff opens with the reasoning:
      `docs(sdd): record the m8-bundle-rename proposal, spec delta, design and tasks`.

## Phase 1: WU5 — the tap goes first (R4)

Executed in `/Users/juancasanueva/programming/swiftUI/homebrew-cellar`, on branch
`feat/m8-bundle-rename`. **No RED/GREEN pair exists here**: the tap repo has no test harness (design
verified: no test directory, `ci.yml` + `bump.yml` only) and per **DD-8** no app-repo test reaches
into it. A test reading a sibling checkout would be green or red depending on whether the maintainer
happens to have cloned it.

- [ ] 1.1 `Casks/home-cellar.rb:20` — `app "cellar.app"` → `app "Home-Cellar.app"`. **Declare no
      `target:`** (D1, and the delta's *The rename ships no migration mechanism* scenario).
- [ ] 1.2 `.github/workflows/ci.yml` `:77` `test -d "/Applications/cellar.app"`, `:79`
      `"/Applications/cellar.app/Contents/Info.plist"`, `:90` `test ! -d "/Applications/cellar.app"`
      → `Home-Cellar.app` in all three.
- [ ] 1.3 `README.md` `:14` installed path → `Home-Cellar.app`; `:16` **collapse** "`cellar.app` in
      both channels; the app presents itself as **Home-Cellar**" to one name — the "presents itself
      as" caveat is exactly what this slice deletes; `:29` heading and `:32` collision quote →
      `Home-Cellar.app`.
- [ ] 1.4 **Bindings — do not touch**: `Casks/home-cellar.rb` `:11-14` `livecheck`, `:16`
      `auto_updates true`, `:22-28` `zap trash:` (no data root moves, and **no
      `/Applications/cellar.app` entry may be added** — a zap must not delete a bundle the cask never
      placed), and `.github/workflows/bump.yml` in its entirety (any edit reopens R4).
- [ ] 1.5 Open the tap PR. Its CI is the verification: `brew style`, `brew audit --cask --online
      --strict`, and the install/uninstall job resolving the `app` artifact against
      `/Applications/Home-Cellar.app`.
- [ ] 1.6 **Gate.** The tap PR is **merged**. If it cannot merge before the app repo is ready, pause
      `bump.yml`'s schedule and record that in the app PR body. Do not push a `v*` tag until one of
      the two holds.

## Phase 2: WU1 — the product is renamed, the module is pinned

Runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests/BundleNamingTests`

- [ ] 2.1 **RED — new file `cellarTests/BundleNamingTests.swift`.** Declare
      `nonisolated enum BundleNamingSources` anchoring the repository root off `#filePath`, **never**
      the working directory, and re-declare (do **not** import) the block-splitting approach from
      `UpdateProjectSources` — the house idiom keeps rollback to one file
      (`UpdateProjectFileTests.swift:9-33`, `CaskZapInventoryTests.swift:9-45`, both citing the same
      reason).
- [ ] 2.2 **RED — unit 1.** `bothAppTargetConfigurationsNameTheProductAndPinTheModule` over
      `project.pbxproj`: blocks filtered by `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;`
      — **the trailing `;` is load-bearing**, it excludes `…cellarTests` — number **exactly 2**;
      `PRODUCT_NAME = "Home-Cellar";` appears in **exactly 2**; `PRODUCT_MODULE_NAME = cellar;`
      appears in **exactly 2**. Asserted in **one** test so the deliberate name/module divergence is
      discoverable in one place (DD-1). **RED because** neither line exists today.
- [ ] 2.3 **RED — unit 2.** `theTestHostResolvesThroughTheRenamedBundle`:
      `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Home-Cellar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Home-Cellar";`
      occurs **exactly twice**, and the string `cellar.app` occurs **exactly zero** times in the whole
      file. **RED because** `:510`/`:531` still say `cellar.app/…/cellar`.
- [ ] 2.4 **RED — unit 4.** `theSharedSchemeBuildsTheRenamedBundle` over `cellar.xcscheme`:
      `BuildableName = "Home-Cellar.app"` occurs **exactly 3** times; `BuildableName = "cellar.app"`
      **exactly 0**; and the anti-overreach half — `BlueprintName = "cellar"` still occurs **exactly
      3** times, so the rename never leaked into the blueprint. `:39`/`:50`
      (`cellarTests.xctest`, `cellarUITests.xctest`) are untouched.
- [ ] 2.5 **R6 — count, never widen.** Every assertion in 2.2–2.4 is an **exact count**, not
      `contains`, and never case-insensitive. `"Home-Cellar.app"` *contains* `"Cellar.app"` but does
      **not** contain `"cellar.app"`; a substring assertion in either direction is the trap. The
      capital `C` is the assertion.
- [ ] 2.6 **Prove RED.** Run the focused command; 2.2–2.4 MUST each fail for its stated reason. A
      green test here is a defect in the test, not an early win.
- [ ] 2.7 **GREEN — `cellar.xcodeproj/project.pbxproj`, one atomic edit.**
      `:38` product `PBXFileReference` → `path = "Home-Cellar.app";` and its `/* … */` comment;
      `:107` and `:142` comments follow; `:446` and `:482` `PRODUCT_NAME = "$(TARGET_NAME)";` →
      `PRODUCT_NAME = "Home-Cellar";`; **insert** `PRODUCT_MODULE_NAME = cellar;` after `:445` and
      after `:481` — **between `PRODUCT_BUNDLE_IDENTIFIER` and `PRODUCT_NAME`** (DD-6: build-setting
      dictionaries are alphabetically sorted; any other slot is reordered on the next Xcode save);
      `:510` and `:531` `TEST_HOST` → `Home-Cellar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Home-Cellar`.
- [ ] 2.8 **GREEN — quoting (DD-5).** Every value containing a hyphen is quoted
      (`path = "Home-Cellar.app";`, `PRODUCT_NAME = "Home-Cellar";`); `PRODUCT_MODULE_NAME = cellar;`
      stays **bare**. Xcode's OpenStep-plist serializer quotes tokens outside `[A-Za-z0-9_$./]`, and
      the repo has no existing hyphenated pbxproj path to copy — writing them bare invites a spurious
      rewrite-diff on the next Xcode save.
- [ ] 2.9 **GREEN — both blocks, identically (DD-7, not optional).**
      `ReleasePipelineCompositionTests.appTargetConfigurationsAreIdenticalModuloName` (`:213-229`)
      already requires the two app-target blocks to be line-identical modulo `name = `. A Debug-only
      or Release-only edit, or a differing insertion order, turns an existing green guard RED. That
      shipped test is free enforcement of 2.2's "both blocks" clause.
- [ ] 2.10 **GREEN — `cellar.xcodeproj/xcshareddata/xcschemes/cellar.xcscheme`.** `:19` (Build),
      `:73` (Test/macroExpansion), `:104` (Launch/Profile): `BuildableName = "cellar.app"` →
      `"Home-Cellar.app"`. `BlueprintIdentifier = "BCDBE97A301E2D410013A38D"`,
      `BlueprintName = "cellar"` and the **filename** `cellar.xcscheme` are unchanged.
- [ ] 2.11 **BLOCKING — R5 post-probe (design's "work unit 0"). Run immediately after 2.7–2.10, before
      any other unit.**
      `xcodebuild -project cellar.xcodeproj -target cellar -showBuildSettings 2>/dev/null | rg 'PRODUCT_MODULE_NAME|PRODUCT_NAME|EXECUTABLE_NAME|FULL_PRODUCT_NAME|PRODUCT_BUNDLE_IDENTIFIER'`.
      Expected, and diffed line-by-line against the Phase 0.1 pre-change block:
      `EXECUTABLE_NAME = Home-Cellar` · `FULL_PRODUCT_NAME = Home-Cellar.app` ·
      `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar` · `PRODUCT_MODULE_NAME = cellar` ·
      `PRODUCT_NAME = Home-Cellar`.
      **Only `PRODUCT_NAME`, `EXECUTABLE_NAME` and `FULL_PRODUCT_NAME` may differ.**
      `PRODUCT_BUNDLE_IDENTIFIER` and `PRODUCT_MODULE_NAME` MUST be **byte-identical** before and
      after — those two unchanged lines are the whole invariant this slice rests on. Record the
      output **verbatim** for the verify report. **Any other line moving STOPS the phase**: report the
      deviation, do not proceed to WU2, do not "fix it forward".
- [ ] 2.12 **Import proof.** All **22** `@testable import cellar` files under `cellarTests/` compile
      with **zero** source edits. Implied by the focused run; stated so it is checked, because it is
      exactly what Approach 2 would have broken (`Home-Cellar:c99extidentifier` = `Home_Cellar`).
- [ ] 2.13 Focused command green, **and `ReleasePipelineCompositionTests` `:94` / `:213-229` and
      `UpdateProjectFileTests:68` still green**; commit WU1.

## Phase 3: WU2 — the product name stops impersonating the scheme name

Runner: `xcodebuild test … -only-testing:cellarTests/BundleNamingTests/theReleaseScriptSeparatesTheProductFromTheScheme`

- [ ] 3.1 **RED — unit 3.** `theReleaseScriptSeparatesTheProductFromTheScheme` over
      `scripts/release.sh`: `readonly PRODUCT="Home-Cellar"` present; `-scheme "$SCHEME"` **still**
      present; `$SCHEME.app` occurs **zero** times; `MacOS/$SCHEME` occurs **zero** times;
      `$PRODUCT.app` occurs **exactly twice**; `MacOS/$PRODUCT` occurs **exactly twice**. **RED
      because** one constant serves four roles today, which is why this is not a `sed` (DD-3).
- [ ] 3.2 **Prove RED**, then **GREEN**: add `readonly PRODUCT="Home-Cellar"` after `:31`; `:48`
      `APP="$EXPORT_DIR/$PRODUCT.app"`; `:50` `VERIFIED_APP="$VERIFY_DIR/$PRODUCT.app"`; `:148`
      `lipo -archs "$APP/Contents/MacOS/$PRODUCT"`; `:236`
      `lipo -archs "$VERIFIED_APP/Contents/MacOS/$PRODUCT"`. **Four substitutions, not five** — the
      design measured `$SCHEME` at exactly `:31, :46, :48, :50, :118, :148, :236`.
- [ ] 3.3 **Kept on `SCHEME` deliberately**: `:46` `ARCHIVE_PATH="$BUILD/$SCHEME.xcarchive"` (DD-4 —
      `cellar.xcarchive` stays; a build intermediate no user sees, closing R8 by decision rather than
      omission) and `:118` `-scheme "$SCHEME"`.
- [ ] 3.4 **Bindings — do not touch**: `:31` `readonly SCHEME="cellar"`, `:245-246` the
      `plutil -extract CFBundleDisplayName raw` == `Home-Cellar` gate, `:275`
      `ZIP="$BUILD/Home-Cellar-$VERSION.zip"`.
      `ReleasePipelineCompositionTests:519-521` (the script still reads `CFBundleDisplayName`) MUST
      stay green.
- [ ] 3.5 Focused command green; commit WU2.

## Phase 4: WU3 — the workflow inspects the path that now exists

Runner: `xcodebuild test … -only-testing:cellarTests/BundleNamingTests/theWorkflowInspectsTheRenamedExportPath`

- [ ] 4.1 **RED — unit 5.** `theWorkflowInspectsTheRenamedExportPath` over
      `.github/workflows/release.yml`: `build/export/Home-Cellar.app` present;
      `build/export/cellar.app` **absent**. **RED because** `:159` is hardcoded to the old path.
- [ ] 4.2 **Prove RED**, then **GREEN**: `:159`
      `codesign -dvvv --entitlements :- "build/export/Home-Cellar.app" 2>&1`.
- [ ] 4.3 **Bindings — do not touch**: `:173`, `:190`, `:191` already name
      `Home-Cellar-${VERSION}.zip`. `ReleasePipelineCompositionTests:808` (the app repo names no other
      repository — DD-8, and the delta's *The release run gains no cross-repository reach* scenario)
      MUST stay green, and **no cross-repository dispatch may be added** to reach the tap.
- [ ] 4.4 Focused command green; commit WU3.

## Phase 5: WU4 — one name in the prose, and the assertion that proves it (U4, R6)

Runner: `xcodebuild test … -only-testing:cellarTests/CaskZapInventoryTests`

- [ ] 5.1 **RED — deliberate update of a shipped assertion.** `CaskZapInventoryTests.swift:335`
      `#expect(readme.contains("cellar.app"))` → `#expect(readme.contains("Home-Cellar.app"))`, and
      rewrite the doc comment at `:338-342` ("A direct-download copy already sits at
      `/Applications/cellar.app`…") to name `Home-Cellar.app` and to drop the pre-tap-era framing
      (D1). **RED because** the README still says `cellar.app`.
      **This MUST NOT be "fixed" by lowercasing, by `caseInsensitiveCompare`, or by widening the
      substring.** The capital `C` is the assertion.
- [ ] 5.2 **Prove RED**, then **GREEN — `README.md`**: `:42` "That installs
      `/Applications/Home-Cellar.app`"; `:49-60` rewrite the "Already have `cellar.app` in
      `/Applications`?" block for `Home-Cellar.app` only, covering the **direct-download → cask**
      path; `:63` "drag `Home-Cellar.app` to `/Applications`".
      **`:54`, the fenced `brew install --cask --adopt home-cellar` line, stays byte-identical** —
      `CaskZapInventoryTests:344-354` (`theReadmeCarriesTheAdoptCommandAsAWholeLine`) MUST stay green.
- [ ] 5.3 **GREEN — `RELEASING.md`**: `:265` sample `spctl` output → `Home-Cellar.app: accepted`;
      `:303` "Bundle inside it" → `Home-Cellar.app`, display name `Home-Cellar`; `:336` "Installed
      path" → `/Applications/Home-Cellar.app`; `:348-356` rewrite the "A direct-download copy blocks a
      plain install" paragraph naming `Home-Cellar.app` only.
- [ ] 5.4 **GREEN — `PRD.md:194`**: "installs `/Applications/Home-Cellar.app`".
- [ ] 5.5 **No migration paragraph anywhere (D1, binding).** Explore §2.G's "plus a new migration
      paragraph" and §4's migration mechanisms are superseded by the proposal and MUST NOT be
      reintroduced. Sweep: `rg -n 'cellar\.app' README.md RELEASING.md PRD.md` MUST return **zero**
      hits. Use a case-**sensitive** pattern — a case-insensitive sweep matches every
      `Home-Cellar.app` and tells you nothing.
- [ ] 5.6 **U2 / U3 stay green untouched**: the uninstall inventory and the two Keychain items
      (`com.juancasanueva.cellar.nvd-api-key`, `com.juancasanueva.cellar.github-pat`) derive from the
      bundle identifier, not the product name, so **no inventory entry is added, removed or
      repointed** by this change.
- [ ] 5.7 Focused command green; commit WU4.

## Phase 6: Verification and bindings (design gates 1–6)

- [ ] 6.1 **Gate 1 — core package**: `swift test --package-path Packages/CellarCore` → the Phase 0.2
      baseline, **0 failures**. Must be entirely unaffected; no `Packages/CellarCore` source is
      touched. Assert counts, never a bare success line.
- [ ] 6.2 **Gate 2 — build**:
      `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      → succeeds, and the built product is `Home-Cellar.app` with `Contents/MacOS/Home-Cellar`.
- [ ] 6.3 **Gate 3 — full suite**:
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      → Phase 0.2 baseline plus the five new `BundleNamingTests` cases, 0 failures.
      **No `-scheme`, `-only-testing:` or `TEST_TARGET_NAME` argument anywhere may change** — the
      scheme, the target and the test target are frozen by construction.
- [ ] 6.4 **Gate 4 — the post-probe is already recorded** (task 2.11). Confirm the verbatim block is
      in the verify report alongside the Phase 0.1 pre-change block, so the three-line diff is
      auditable rather than asserted.
- [ ] 6.5 **Gate 6 — display-name gate unmodified.** `release.sh:245-246` still reads
      `CFBundleDisplayName` == `Home-Cellar`; it was already correct before this slice and MUST pass
      unchanged at the next release run.
- [ ] 6.6 **Bindings proof.**
      `git diff --stat main -- Packages/CellarCore/ cellar/ .github/workflows/bump.yml`
      → **empty output** for `Packages/` and `cellar/` (no Swift source in either is touched;
      `bump.yml` does not exist in this repo and the pattern simply matches nothing).
      `git diff main -- cellar.xcodeproj/project.pbxproj | rg 'PRODUCT_BUNDLE_IDENTIFIER|TEST_TARGET_NAME|remoteInfo|productName'`
      → **empty output**. A deviation is reported before merge, never absorbed.
- [ ] 6.7 `git diff --stat main` for the whole branch — record the authored total and compare it with
      the forecast (**~955–1,330**). A large miss is information for the next forecast, not a failure.
- [ ] 6.8 Open the app-repo PR from `feat/m8-bundle-rename`: title
      `feat(release): name the delivered bundle Home-Cellar.app`, and a body that states up front
      (a) the tap PR's merge status and that **no `v*` tag may be pushed until it is merged or
      `bump.yml` is paused** (R4); (b) that `PRODUCT_MODULE_NAME` is pinned to `cellar` **on purpose**
      (DD-1), so the Swift module and all 22 `@testable import cellar` lines are untouched; and
      (c) that **D1 makes this update-safe with no migration** — the installed base is empty, so no
      `target:`, no zap entry for the old path, and no user-facing old-name guidance exists anywhere.
      This repository defines no `type:*` labels, so apply none.

## Phase 7: Post-tag `manual-evidence` (maintainer's Mac — not merge blockers, not test tasks)

Both scenarios are unreachable until `v1.2.0` ships. The rename **rides the next tag**; there is no
rename-only release (D1). Capture each transcript **verbatim into the verify report**.

- [ ] 7.1 **Gate — R4 re-check immediately before the tag push.** `Casks/home-cellar.rb` on the tap's
      default branch reads `app "Home-Cellar.app"`, **or** `bump.yml`'s schedule is paused. Confirm by
      reading the merged tap branch, not by trusting Phase 1.6.
- [ ] 7.2 **ME1 — "A tap and an install put the released build in `/Applications`."**
      `brew uninstall --cask home-cellar` → `brew install --cask home-cellar` →
      `/Applications/Home-Cellar.app` exists and reports the released version, `codesign -dvvv` reads
      the new path, `Contents/MacOS/Home-Cellar` is present, and the app launches with no Gatekeeper
      refusal.
- [ ] 7.3 **ME2 — "A self-updated app does not fight `brew upgrade`."** After a Sparkle self-update in
      place, Homebrew does not report the copy as outdated and does not reinstall over it, and exactly
      one bundle exists at the original path.
      **BINDING — never run `brew upgrade` without `--dry-run` on the maintainer's Mac** (Engram
      `#7724`). Use `brew upgrade --cask --dry-run home-cellar`. This applies to every retry.
- [ ] 7.4 **Composition-only honesty.** Record in the verify report that the nine `ci-gate` scenarios
      are proven **composed** (RED units 1–5 plus the tap's own `ci.yml`) and **exercised** only by the
      `v1.2.0` run and the tap CI. `sdd-verify` MUST NOT claim `release.sh` is verified end-to-end.

## Phase 8: Archive obligations (recorded now so they are not re-derived at `sdd-archive`)

- [ ] 8.1 **R7 — three provenance passages sit outside every requirement block and a MODIFIED delta
      structurally cannot carry them.** `sdd-archive` MUST hand-edit
      `openspec/specs/release-distribution/spec.md`:
      **`:619`** — the `m6-sparkle-updates` provenance reads `Contents/MacOS/cellar` as the `U31`
      measurement; that is a **historical measurement**, so keep the recorded fact and mark that the
      path is now `Contents/MacOS/Home-Cellar` rather than silently rewriting what was measured.
      **`:686-688`** — `m6-cask-tap` **D3** ("this change MUST NOT rename it", `app "cellar.app"`, and
      the rejection of `target: "Home-Cellar.app"`): record that `m8-bundle-rename` performed the
      rename D3 deferred and that **the rejection of `target:` still stands** — the cask now names
      `Home-Cellar.app` directly, which is not the rejected alternative.
      **`:718-720`** — move the `Home-Cellar.app` rename entry from *deferred* to *landed*, and record
      its "update continuity for every installed 1.0.0 copy" clause as **closed by D1** (the installed
      base was empty, so no continuity work was owed). The other two deferred items (cache dir under
      the bundle id; `homebrew/cask` submission) **stay deferred**.
- [ ] 8.2 **Hand-update the `## Verification classes` table** (outside every requirement block, as its
      counts were hand-updated at `:627-632`). This delta adds **one** scenario (*The rename ships no
      migration mechanism*, `ci-gate`): `unit` 18 / `ci-gate` 17 / `manual-evidence` 6 (41) →
      `unit` **18** / `ci-gate` **18** / `manual-evidence` **6** (**42**). **Confirm the arithmetic by
      counting `- Verification:` lines in the merged file**, not by trusting this note.
- [ ] 8.3 Record that the delta is **3 MODIFIED / 0 added / 0 removed / 0 renamed**, so
      `rules.archive`'s destructive-delta warning does not fire and no capability count in any other
      spec changes. Record the deliberate divergence from the proposal's "counts are unchanged" line:
      the scenario count moves by one while the binding Capabilities contract (zero ADDED
      requirements) is honoured exactly.
- [ ] 8.4 Record the PRD milestone this closes: **M6 "Ship"** (`PRD.md:216-217`), specifically the
      cask-channel line `:194`. Record **D1** (no installed base, no migration mechanism anywhere) and
      **D2** (all three defaults accepted: `cellar.xcarchive` unchanged; no target/folder rename; the
      product/module divergence accepted), with what each rejected. Record the deferred follow-ups
      that remain: the cache directory under the bundle identifier, and the `homebrew/cask`
      submission.
