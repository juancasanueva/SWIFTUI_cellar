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

- **The `v1.2.0` tag push → WU5's merge (R4 — binding spec text, not a note). CORRECTED after
  verify-report C1; the earlier "tap merges first" edge was unsatisfiable.** `v1.1.0`'s published asset
  contains `cellar.app`, so merging `app "Home-Cellar.app"` against that declared version breaks fresh
  installs and red-lights the tap's own install job. Tag-first alone is no better: `bump.yml` runs
  `17 */6 * * *`, rewrites only `version`/`sha256`, and gates on `brew style` + `brew audit` —
  **neither extracts the archive nor resolves the `app` stanza** — so it lands the renamed version
  against `app "cellar.app"`. Only **atomic and post-release** works: publish the renamed asset, pause
  `bump.yml`'s schedule (or supersede its open PR), land **one** tap commit moving `version`, `sha256`
  and `app` together, restore the schedule. Any edit to `bump.yml`'s content reopens R4.
- **WU1 → WU2 / WU3 / WU4 (soft, single-writer).** No compile dependency: the four app-repo units
  touch disjoint files. They share `cellarTests/BundleNamingTests.swift` (WU1 creates it with tests
  1, 2 and 4; WU2 appends test 3; WU3 appends test 5), so they execute **sequentially, one writer**.
  No parallel worktrees.
- **WU1 is atomic and MUST NOT be split.** `PRODUCT_NAME`, `PRODUCT_MODULE_NAME`, the product
  reference and **both** `TEST_HOST` lines land in one commit. A `PRODUCT_NAME` change without
  `TEST_HOST` leaves the test host pointing at a bundle that no longer exists and the whole
  `cellarTests` bundle fails to launch — an intermediate state that is not merely red, it is
  unrunnable.
- **WU5 ∥ WU1–WU4.** Different repository, different PR, no shared file. Prepare it alongside them, but
  **hold its merge until after the renamed release publishes** — R4 is satisfied by the atomicity of
  that one post-release commit, not by landing the tap early.
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
- [x] 0.5 **Done** — branch `feat/m8-bundle-rename` cut from `main f0a5817`; artifact commit
      `c1f5898`. `git checkout -b feat/m8-bundle-rename main`, then commit the SDD artifacts **first** so the
      reviewed diff opens with the reasoning:
      `docs(sdd): record the m8-bundle-rename proposal, spec delta, design and tasks`.

## Phase 1: WU5 — the tap change is *prepared*, not merged (R4)

**RESTRUCTURED after verify-report C1.** This phase originally read "the tap goes first", which cannot
be satisfied while `v1.1.0`'s published asset still contains `cellar.app`. Preparing the branch stays
here; **merging it moved to Phase 7** — post-release, as one atomic `version`+`sha256`+`app` commit.
Tasks 1.1–1.4 are unaffected: the edits they made are correct and stay `[x]`.

Executed in `/Users/juancasanueva/programming/swiftUI/homebrew-cellar`, on branch
`feat/m8-bundle-rename`. **No RED/GREEN pair exists here**: the tap repo has no test harness (design
verified: no test directory, `ci.yml` + `bump.yml` only) and per **DD-8** no app-repo test reaches
into it. A test reading a sibling checkout would be green or red depending on whether the maintainer
happens to have cloned it.

- [x] 1.1 **Done** (`home-cellar.rb:20` now reads `app "Home-Cellar.app"`; `rg -n 'target:' Casks/`
      → zero hits). `Casks/home-cellar.rb:20` — `app "cellar.app"` → `app "Home-Cellar.app"`. **Declare no
      `target:`** (D1, and the delta's *The rename ships no migration mechanism* scenario).
- [x] 1.2 **Done** — all three lines now read `Home-Cellar.app` at the same `:77` / `:79` / `:90`.
      `.github/workflows/ci.yml` `:77` `test -d "/Applications/cellar.app"`, `:79`
      `"/Applications/cellar.app/Contents/Info.plist"`, `:90` `test ! -d "/Applications/cellar.app"`
      → `Home-Cellar.app` in all three.
- [x] 1.3 **Done** — `:14` installed path renamed; `:16` collapsed to "The bundle is named
      `Home-Cellar.app` in both channels." with the "presents itself as" caveat deleted; `:29`
      heading and `:32` collision quote renamed. Case-sensitive `rg -n 'cellar\.app' .` over the whole
      tap clone returns **zero hits**. `README.md` `:14` installed path → `Home-Cellar.app`; `:16` **collapse** "`cellar.app` in
      both channels; the app presents itself as **Home-Cellar**" to one name — the "presents itself
      as" caveat is exactly what this slice deletes; `:29` heading and `:32` collision quote →
      `Home-Cellar.app`.
- [x] 1.4 **Confirmed untouched** — `git diff --stat` on the tap branch names exactly
      `ci.yml` (6), `home-cellar.rb` (2), `README.md` (10); `git diff --stat -- .github/workflows/bump.yml`
      is empty, and the `livecheck`, `auto_updates` and `zap trash:` stanzas are outside the diff.
      No `/Applications/cellar.app` entry was added to the zap inventory.
      **Bindings — do not touch**: `Casks/home-cellar.rb` `:11-14` `livecheck`, `:16`
      `auto_updates true`, `:22-28` `zap trash:` (no data root moves, and **no
      `/Applications/cellar.app` entry may be added** — a zap must not delete a bundle the cask never
      placed), and `.github/workflows/bump.yml` in its entirety (any edit reopens R4).
- [x] 1.5 **DONE (remediation) — branch rebased onto `origin/main` and held.** It was based on `f9e7428`,
      two `bump.yml` commits behind `origin/main` (`5e02b96`), so it still declared `version "1.0.0"` and
      a merge or fast-forward would have regressed the published cask (verify-report W1). Rebased: the
      branch now carries `version "1.1.0"` / `sha256 a6d5c68…` with only the three intended files changed
      (`ci.yml` 6, `home-cellar.rb` 2, `README.md` 10). New head **`7c50ee6`**.
      **Shape chosen: one atomic commit, HOLD + four-step merge procedure in its message** — not a
      two-commit "safe pre-tag" / "post-release" split, because `ci.yml`'s install job asserts
      `/Applications/Home-Cellar.app` right after `brew install --cask`, so a commit carrying `ci.yml`
      without the `app` stanza would still red-light CI. Nothing here is safe to merge earlier.
      Re-captured after the rebase: `brew style` → `no offenses detected`; `rg 'cellar\.app'` → 0 hits.
- [x] 1.6 **MOVED to Phase 7 (7.3–7.5), and discharged there.** Pushing, opening and merging the tap PR
      are **post-release** actions now, so they no longer belong to a phase that runs before the tag.
      Closed at archive: 7.3–7.5 all executed (tap PR #1 merged as `5b4b83c`, 2026-08-23T21:48:53Z).
      This entry carries no residual work.

## Phase 2: WU1 — the product is renamed, the module is pinned

Runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests/BundleNamingTests`

- [x] 2.1 **RED — new file `cellarTests/BundleNamingTests.swift`.** Declare
      `nonisolated enum BundleNamingSources` anchoring the repository root off `#filePath`, **never**
      the working directory, and re-declare (do **not** import) the block-splitting approach from
      `UpdateProjectSources` — the house idiom keeps rollback to one file
      (`UpdateProjectFileTests.swift:9-33`, `CaskZapInventoryTests.swift:9-45`, both citing the same
      reason).
- [x] 2.2 **RED — unit 1.** `bothAppTargetConfigurationsNameTheProductAndPinTheModule` over
      `project.pbxproj`: blocks filtered by `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;`
      — **the trailing `;` is load-bearing**, it excludes `…cellarTests` — number **exactly 2**;
      `PRODUCT_NAME = "Home-Cellar";` appears in **exactly 2**; `PRODUCT_MODULE_NAME = cellar;`
      appears in **exactly 2**. Asserted in **one** test so the deliberate name/module divergence is
      discoverable in one place (DD-1). **RED because** neither line exists today.
- [x] 2.3 **RED — unit 2.** `theTestHostResolvesThroughTheRenamedBundle`:
      `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Home-Cellar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Home-Cellar";`
      occurs **exactly twice**, and the string `cellar.app` occurs **exactly zero** times in the whole
      file. **RED because** `:510`/`:531` still say `cellar.app/…/cellar`.
- [x] 2.4 **RED — unit 4.** `theSharedSchemeBuildsTheRenamedBundle` over `cellar.xcscheme`:
      `BuildableName = "Home-Cellar.app"` occurs **exactly 3** times; `BuildableName = "cellar.app"`
      **exactly 0**; and the anti-overreach half — `BlueprintName = "cellar"` still occurs **exactly
      3** times, so the rename never leaked into the blueprint. `:39`/`:50`
      (`cellarTests.xctest`, `cellarUITests.xctest`) are untouched.
- [x] 2.5 **R6 — count, never widen.** Every assertion in 2.2–2.4 is an **exact count**, not
      `contains`, and never case-insensitive. `"Home-Cellar.app"` *contains* `"Cellar.app"` but does
      **not** contain `"cellar.app"`; a substring assertion in either direction is the trap. The
      capital `C` is the assertion.
- [x] 2.6 **Prove RED.** Run the focused command; 2.2–2.4 MUST each fail for its stated reason. A
      green test here is a defect in the test, not an early win.

      **RED PROVEN** — `** TEST FAILED **`, all three cases failed. Verbatim expectation messages
      from the `.xcresult`:
      `Expectation failed: try BundleNamingSources.appTargetBlocksDeclaring(Self.productName) == 2` ·
      `Expectation failed: try BundleNamingSources.appTargetBlocksDeclaring(Self.moduleName) == 2` ·
      `Expectation failed: (occurrences(of: Self.testHost, in: project) → 0) == 2` ·
      `Expectation failed: (occurrences(of: "cellar.app", in: project) → 6) == 0` ·
      `Expectation failed: (occurrences(of: "BuildableName = \"Home-Cellar.app\"", in: scheme) → 0) == 3` ·
      `Expectation failed: (occurrences(of: "BuildableName = \"cellar.app\"", in: scheme) → 3) == 0`.
      `blocks.count == 2` and `BlueprintName = "cellar"` == 3 passed from the start — the helper and
      the anti-overreach guard were never the thing failing.
- [x] 2.7 **GREEN — `cellar.xcodeproj/project.pbxproj`, one atomic edit.**
      `:38` product `PBXFileReference` → `path = "Home-Cellar.app";` and its `/* … */` comment;
      `:107` and `:142` comments follow; `:446` and `:482` `PRODUCT_NAME = "$(TARGET_NAME)";` →
      `PRODUCT_NAME = "Home-Cellar";`; **insert** `PRODUCT_MODULE_NAME = cellar;` after `:445` and
      after `:481` — **between `PRODUCT_BUNDLE_IDENTIFIER` and `PRODUCT_NAME`** (DD-6: build-setting
      dictionaries are alphabetically sorted; any other slot is reordered on the next Xcode save);
      `:510` and `:531` `TEST_HOST` → `Home-Cellar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Home-Cellar`.
- [x] 2.8 **GREEN — quoting (DD-5).** Every value containing a hyphen is quoted
      (`path = "Home-Cellar.app";`, `PRODUCT_NAME = "Home-Cellar";`); `PRODUCT_MODULE_NAME = cellar;`
      stays **bare**. Xcode's OpenStep-plist serializer quotes tokens outside `[A-Za-z0-9_$./]`, and
      the repo has no existing hyphenated pbxproj path to copy — writing them bare invites a spurious
      rewrite-diff on the next Xcode save.
- [x] 2.9 **GREEN — both blocks, identically (DD-7, not optional).**
      `ReleasePipelineCompositionTests.appTargetConfigurationsAreIdenticalModuloName` (`:213-229`)
      already requires the two app-target blocks to be line-identical modulo `name = `. A Debug-only
      or Release-only edit, or a differing insertion order, turns an existing green guard RED. That
      shipped test is free enforcement of 2.2's "both blocks" clause.
- [x] 2.10 **GREEN — `cellar.xcodeproj/xcshareddata/xcschemes/cellar.xcscheme`.** `:19` (Build),
      `:73` (Test/macroExpansion), `:104` (Launch/Profile): `BuildableName = "cellar.app"` →
      `"Home-Cellar.app"`. `BlueprintIdentifier = "BCDBE97A301E2D410013A38D"`,
      `BlueprintName = "cellar"` and the **filename** `cellar.xcscheme` are unchanged.
- [x] 2.11 **BLOCKING — R5 post-probe (design's "work unit 0"). Run immediately after 2.7–2.10, before
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

      **RUN 2026-08-23 on `feat/m8-bundle-rename` after 2.7-2.10. Verbatim output:**

      ```
      EXECUTABLE_NAME = Home-Cellar
      FULL_PRODUCT_NAME = Home-Cellar.app
      PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar
      PRODUCT_MODULE_NAME = cellar
      PRODUCT_NAME = Home-Cellar
      ```

      Line-by-line diff against the Phase 0.1 pre-change block: `EXECUTABLE_NAME` `cellar` →
      `Home-Cellar` (allowed) · `FULL_PRODUCT_NAME` `cellar.app` → `Home-Cellar.app` (allowed) ·
      `PRODUCT_BUNDLE_IDENTIFIER` **byte-identical** · `PRODUCT_MODULE_NAME` **byte-identical** ·
      `PRODUCT_NAME` `cellar` → `Home-Cellar` (allowed). **Exactly the three permitted lines moved.
      R5 is closed on both sides; the phase proceeds.**
- [x] 2.12 **CONFIRMED — 22, unchanged, zero source edits.** `git grep -l '@testable import cellar' main -- cellarTests/`
      → **22**; the same count on the branch (the 23rd `rg` hit is the literal inside
      `BundleNamingTests.swift`'s own doc comment, not an import). The focused run's device line reads
      `My Mac - Home-Cellar` — the renamed test host launched and every one of those files was linked
      into it. **Import proof.** All **22** `@testable import cellar` files under `cellarTests/` compile
      with **zero** source edits. Implied by the focused run; stated so it is checked, because it is
      exactly what Approach 2 would have broken (`Home-Cellar:c99extidentifier` = `Home_Cellar`).
- [x] 2.13 Focused command green, **and `ReleasePipelineCompositionTests` `:94` / `:213-229` and
      `UpdateProjectFileTests:68` still green**; commit WU1.

      **GREEN** — `-only-testing:cellarTests/BundleNamingTests` → `** TEST SUCCEEDED **`, 3/3 passed.
      Guards: `-only-testing:` `ReleasePipelineCompositionTests` + `UpdateProjectFileTests` +
      `CaskZapInventoryTests` → `** TEST SUCCEEDED **`, so DD-7 byte-identity (`:213-229`), the
      bundle-identifier guards (`:94`, `:68`) and the adopt-line guard all held.
      **Runtime harness**: `xcodebuild build …` → `** BUILD SUCCEEDED **`;
      `Build/Products/Debug/Home-Cellar.app/Contents/MacOS/Home-Cellar` exists and is executable, and
      `Build/Products/Debug/cellar.app` does not exist. Commit **`f95b9d6`**.

## Phase 3: WU2 — the product name stops impersonating the scheme name

Runner: `xcodebuild test … -only-testing:cellarTests/BundleNamingTests/theReleaseScriptSeparatesTheProductFromTheScheme`

- [x] 3.1 **RED — unit 3.** `theReleaseScriptSeparatesTheProductFromTheScheme` over
      `scripts/release.sh`: `readonly PRODUCT="Home-Cellar"` present; `-scheme "$SCHEME"` **still**
      present; `$SCHEME.app` occurs **zero** times; `MacOS/$SCHEME` occurs **zero** times;
      `$PRODUCT.app` occurs **exactly twice**; `MacOS/$PRODUCT` occurs **exactly twice**. **RED
      because** one constant serves four roles today, which is why this is not a `sed` (DD-3).
- [x] 3.2 **RED PROVEN** (`** TEST FAILED **`, 5 expectations: `contains("readonly PRODUCT=…")` false ·
      `$SCHEME.app` → 2 ≠ 0 · `MacOS/$SCHEME` → 2 ≠ 0 · `$PRODUCT.app` → 0 ≠ 2 · `MacOS/$PRODUCT` → 0 ≠ 2;
      the `-scheme "$SCHEME"` anti-overreach half passed from the start). **GREEN**: add `readonly PRODUCT="Home-Cellar"` after `:31`; `:48`
      `APP="$EXPORT_DIR/$PRODUCT.app"`; `:50` `VERIFIED_APP="$VERIFY_DIR/$PRODUCT.app"`; `:148`
      `lipo -archs "$APP/Contents/MacOS/$PRODUCT"`; `:236`
      `lipo -archs "$VERIFIED_APP/Contents/MacOS/$PRODUCT"`. **Four substitutions, not five** — the
      design measured `$SCHEME` at exactly `:31, :46, :48, :50, :118, :148, :236`.
- [x] 3.3 **Confirmed — exactly 2 `$SCHEME` sites remain**, `rg -n '\$SCHEME' scripts/release.sh` →
      `:51 ARCHIVE_PATH="$BUILD/$SCHEME.xcarchive"` and `:123 -scheme "$SCHEME"`.
      **Kept on `SCHEME` deliberately**: `:46` `ARCHIVE_PATH="$BUILD/$SCHEME.xcarchive"` (DD-4 —
      `cellar.xcarchive` stays; a build intermediate no user sees, closing R8 by decision rather than
      omission) and `:118` `-scheme "$SCHEME"`.
- [x] 3.4 **Confirmed untouched** — `:31 readonly SCHEME="cellar"`, `:250-251` the
      `plutil -extract CFBundleDisplayName raw` == `Home-Cellar` gate, `:280`
      `ZIP="$BUILD/Home-Cellar-$VERSION.zip"` (line numbers shifted by the 5 inserted lines; content
      byte-identical). `ReleasePipelineCompositionTests` and `ReleasePipelinePlacementTests` both green.
      **Bindings — do not touch**: `:31` `readonly SCHEME="cellar"`, `:245-246` the
      `plutil -extract CFBundleDisplayName raw` == `Home-Cellar` gate, `:275`
      `ZIP="$BUILD/Home-Cellar-$VERSION.zip"`.
      `ReleasePipelineCompositionTests:519-521` (the script still reads `CFBundleDisplayName`) MUST
      stay green.
- [x] 3.5 **GREEN** — `-only-testing:` the focused test + `ReleasePipelineCompositionTests` +
      `ReleasePipelinePlacementTests` → `** TEST SUCCEEDED **`. `bash -n scripts/release.sh` OK and
      `shellcheck scripts/release.sh` clean. Commit **`7ae6c89`**.

## Phase 4: WU3 — the workflow inspects the path that now exists

Runner: `xcodebuild test … -only-testing:cellarTests/BundleNamingTests/theWorkflowInspectsTheRenamedExportPath`

- [x] 4.1 **RED — unit 5.** `theWorkflowInspectsTheRenamedExportPath` over
      `.github/workflows/release.yml`: `build/export/Home-Cellar.app` present;
      `build/export/cellar.app` **absent**. **RED because** `:159` is hardcoded to the old path.
- [x] 4.2 **RED PROVEN** (`** TEST FAILED **`; both halves failed — `contains("build/export/Home-Cellar.app")`
      false and `!contains("build/export/cellar.app")` false). Then **GREEN**: `:159`
      `codesign -dvvv --entitlements :- "build/export/Home-Cellar.app" 2>&1`.
- [x] 4.3 **Confirmed** — `rg -n 'homebrew-cellar|juancasanueva/cellar|repository_dispatch' .github/workflows/release.yml`
      → **zero hits**; `ReleasePipelineCompositionTests` (including `:808`) green; the diff for this
      unit is one line. **Bindings — do not touch**: `:173`, `:190`, `:191` already name
      `Home-Cellar-${VERSION}.zip`. `ReleasePipelineCompositionTests:808` (the app repo names no other
      repository — DD-8, and the delta's *The release run gains no cross-repository reach* scenario)
      MUST stay green, and **no cross-repository dispatch may be added** to reach the tap.
- [x] 4.4 **GREEN** — focused test + `ReleasePipelineCompositionTests` → `** TEST SUCCEEDED **`.
      Commit **`63b48a9`**.

## Phase 5: WU4 — one name in the prose, and the assertion that proves it (U4, R6)

Runner: `xcodebuild test … -only-testing:cellarTests/CaskZapInventoryTests`

- [x] 5.1 **RED — deliberate update of a shipped assertion.** `CaskZapInventoryTests.swift:335`
      `#expect(readme.contains("cellar.app"))` → `#expect(readme.contains("Home-Cellar.app"))`, and
      rewrite the doc comment at `:338-342` ("A direct-download copy already sits at
      `/Applications/cellar.app`…") to name `Home-Cellar.app` and to drop the pre-tap-era framing
      (D1). **RED because** the README still says `cellar.app`.
      **This MUST NOT be "fixed" by lowercasing, by `caseInsensitiveCompare`, or by widening the
      substring.** The capital `C` is the assertion.
- [x] 5.2 **RED PROVEN** — `rg -c 'Home-Cellar\.app' README.md` → **0** before the edit, and
      `-only-testing:cellarTests/CaskZapInventoryTests` → `** TEST FAILED **` with exactly one case
      failing, `theReadmeCarriesBothBrewCommandsAsWholeLines()`; the adopt-line guard stayed green.
      No case-insensitive comparison and no widened substring was used — the literal is
      `"Home-Cellar.app"` in full. Then **GREEN — `README.md`**: `:42` "That installs
      `/Applications/Home-Cellar.app`"; `:49-60` rewrite the "Already have `cellar.app` in
      `/Applications`?" block for `Home-Cellar.app` only, covering the **direct-download → cask**
      path; `:63` "drag `Home-Cellar.app` to `/Applications`".
      **`:54`, the fenced `brew install --cask --adopt home-cellar` line, stays byte-identical** —
      `CaskZapInventoryTests:344-354` (`theReadmeCarriesTheAdoptCommandAsAWholeLine`) MUST stay green.
- [x] 5.3 **GREEN — `RELEASING.md`**: `:265` sample `spctl` output → `Home-Cellar.app: accepted`;
      `:303` "Bundle inside it" → `Home-Cellar.app`, display name `Home-Cellar`; `:336` "Installed
      path" → `/Applications/Home-Cellar.app`; `:348-356` rewrite the "A direct-download copy blocks a
      plain install" paragraph naming `Home-Cellar.app` only.
- [x] 5.4 **GREEN — `PRD.md:194`**: "installs `/Applications/Home-Cellar.app`".
- [x] 5.5 **SWEEP CLEAN** — `rg -n --case-sensitive 'cellar\.app' README.md RELEASING.md PRD.md`
      returns **zero hits**. The only surviving `migrat` matches in those files are pre-existing and
      unrelated to the bundle name: `RELEASING.md:431` (moving the cache under the bundle id, an
      explicitly deferred item), `PRD.md:121` (Apple's Migration Assistant) and `PRD.md:151`
      (SwiftData migrations). No migration paragraph was added.
      **No migration paragraph anywhere (D1, binding).** Explore §2.G's "plus a new migration
      paragraph" and §4's migration mechanisms are superseded by the proposal and MUST NOT be
      reintroduced. Sweep: `rg -n 'cellar\.app' README.md RELEASING.md PRD.md` MUST return **zero**
      hits. Use a case-**sensitive** pattern — a case-insensitive sweep matches every
      `Home-Cellar.app` and tells you nothing.
- [x] 5.6 **Confirmed** — `git diff -U0 -- README.md RELEASING.md` matches no inventory root and
      neither Keychain item, and `README.md:54` still carries
      `brew install --cask --adopt home-cellar` as a byte-identical whole line, so
      `theReadmeCarriesTheAdoptCommandAsAWholeLine` never moved.
      **U2 / U3 stay green untouched**: the uninstall inventory and the two Keychain items
      (`com.juancasanueva.cellar.nvd-api-key`, `com.juancasanueva.cellar.github-pat`) derive from the
      bundle identifier, not the product name, so **no inventory entry is added, removed or
      repointed** by this change.
- [x] 5.7 **GREEN** — `-only-testing:cellarTests/CaskZapInventoryTests` → `** TEST SUCCEEDED **`.
      Commit **`8e01341`** (PRD 2, README 11, RELEASING 16, CaskZapInventoryTests 18 changed lines).

## Phase 6: Verification and bindings (design gates 1–6)

- [x] 6.1 **PASS — `1793 tests in 210 suites passed … with 1 known issue`, identical to the Phase 0.2
      baseline.** Run 6 times; 5 runs matched the baseline exactly and 1 run reported one extra
      intermittent issue that did not reproduce on any retry. `git diff --stat main -- Packages/CellarCore/`
      is **empty**, so the flake has a zero-line causal surface in this change; recorded, not chased.
      **Gate 1 — core package**: `swift test --package-path Packages/CellarCore` → the Phase 0.2
      baseline, **0 failures**. Must be entirely unaffected; no `Packages/CellarCore` source is
      touched. Assert counts, never a bare success line.
- [x] 6.2 **PASS — `** BUILD SUCCEEDED **`**, and
      `Build/Products/Debug/Home-Cellar.app/Contents/MacOS/Home-Cellar` exists and is executable while
      `Build/Products/Debug/cellar.app` does not exist. **Gate 2 — build**:
      `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      → succeeds, and the built product is `Home-Cellar.app` with `Contents/MacOS/Home-Cellar`.
- [x] 6.3 **PASS — `-only-testing:cellarTests` → `** TEST SUCCEEDED **`, 247 executed cases, 247 Passed,
      0 failures** = the 242 baseline plus exactly the five new `BundleNamingTests` cases.
      The unrestricted full-suite run additionally executes `cellarUITests`, where
      `testTapDetailFilteringInstalledHandoffAndForceDisclosure()` and
      `testTapsNavigationOfficialSourcesAndAddConfirmation()` fail. **Both were verified to fail
      identically at `main f0a5817` with none of this change applied** (checked out and re-run), so
      they are pre-existing and outside this slice; the app launched normally in both runs
      (`Application, pid: …, title: 'Home-Cellar'`), so the rename is not implicated.
      No `-scheme`, `-only-testing:` or `TEST_TARGET_NAME` argument changed.
      **Gate 3 — full suite**:
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      → Phase 0.2 baseline plus the five new `BundleNamingTests` cases, 0 failures.
      **No `-scheme`, `-only-testing:` or `TEST_TARGET_NAME` argument anywhere may change** — the
      scheme, the target and the test target are frozen by construction.
- [x] 6.4 **Confirmed** — the verbatim post-change block is recorded under task 2.11 above, next to the
      Phase 0.1 pre-change block, so the three-line diff is auditable rather than asserted.
      **Gate 4 — the post-probe is already recorded** (task 2.11). Confirm the verbatim block is
      in the verify report alongside the Phase 0.1 pre-change block, so the three-line diff is
      auditable rather than asserted.
- [x] 6.5 **Confirmed unmodified** — `git diff main -- scripts/release.sh | rg 'CFBundleDisplayName'`
      returns nothing, so neither line of the gate is in the diff. It now sits at `:250-251` because
      five lines were inserted above it; the content is byte-identical.
      **Gate 6 — display-name gate unmodified.** `release.sh:245-246` still reads
      `CFBundleDisplayName` == `Home-Cellar`; it was already correct before this slice and MUST pass
      unchanged at the next release run.
- [x] 6.6 **BOTH PASS.** `git diff --stat main -- Packages/CellarCore/ cellar/ .github/workflows/bump.yml`
      → **empty**. The second command as written also matches unchanged *context* lines, so it was run
      in its precise form — `git diff main -- cellar.xcodeproj/project.pbxproj | rg '^[-+]' | rg 'PRODUCT_BUNDLE_IDENTIFIER|TEST_TARGET_NAME|remoteInfo|productName'`
      → **empty**. The three hits the literal command returns are context lines proving those keys sit
      unchanged beside the edit, which is the invariant, not a violation of it.
      **Bindings proof.**
      `git diff --stat main -- Packages/CellarCore/ cellar/ .github/workflows/bump.yml`
      → **empty output** for `Packages/` and `cellar/` (no Swift source in either is touched;
      `bump.yml` does not exist in this repo and the pattern simply matches nothing).
      `git diff main -- cellar.xcodeproj/project.pbxproj | rg 'PRODUCT_BUNDLE_IDENTIFIER|TEST_TARGET_NAME|remoteInfo|productName'`
      → **empty output**. A deviation is reported before merge, never absorbed.
- [x] 6.7 **MEASURED: 2,064 insertions + 35 deletions = 2,099 authored lines** across 14 files.
      Against the forecast's **~955–1,330** this is a **+58 % overshoot**, concentrated entirely in the
      SDD artifacts: explore 358 + proposal 289 + design 313 + spec delta 322 + tasks 493 = **1,775**
      against a forecast of ~700–900 (tasks.md grew further because this phase appended verbatim
      evidence to it). The **code + docs + tests** total is **324** — `release.yml` 2 · `PRD.md` 2 ·
      `README.md` 11 · `RELEASING.md` 16 · `project.pbxproj` 16 · `cellar.xcscheme` 6 ·
      `BundleNamingTests.swift` 240 · `CaskZapInventoryTests.swift` 18 · `release.sh` 13 — which lands
      inside the forecast's own **~240–380** band. Against the governing **5,000**-line budget the
      branch is at **42 %**: still **Low**, so `single-pr` holds with **no `size:exception`**.
      `git diff --stat main` for the whole branch — record the authored total and compare it with
      the forecast (**~955–1,330**). A large miss is information for the next forecast, not a failure.
- [x] 6.8 **DONE — maintainer action, executed after apply.** App-repo PR **#71** was opened from
      `feat/m8-bundle-rename` and **merged as `c7f9f0f`** (2026-08-23T21:39:39Z); `main` is clean.
      Recorded at archive; `sdd-apply` correctly deferred it.
      *(Original task text follows.)* **DEFERRED — maintainer action.** `sdd-apply` never pushes and never opens PRs. The branch is
      left ready at `8e01341` with six commits; the PR body content required below is drafted in
      `apply-progress.md`. Open the app-repo PR from `feat/m8-bundle-rename`: title
      `feat(release): name the delivered bundle Home-Cellar.app`, and a body that states up front
      (a) that `bump.yml`'s schedule is paused **before** the tag and the tap PR merges **after** the
      renamed release publishes, as one atomic `version`+`sha256`+`app` commit (R4 — corrected from the
      unsatisfiable "tap first" ordering); (b) that `PRODUCT_MODULE_NAME` is pinned to `cellar` **on purpose**
      (DD-1), so the Swift module and all 22 `@testable import cellar` lines are untouched; and
      (c) that **D1 makes this update-safe with no migration** — the installed base is empty, so no
      `target:`, no zap entry for the old path, and no user-facing old-name guidance exists anywhere.
      This repository defines no `type:*` labels, so apply none.

## Phase 7: Post-tag — the atomic tap landing, then `manual-evidence` (maintainer's Mac)

**RESTRUCTURED after verify-report C1.** The tap merge moved here from Phase 1: it is **post-release**,
and it must be **one commit** moving `version`, `sha256` and `app` together (R4). Everything below is
unreachable until `v1.2.0` ships; the rename **rides the next tag** (D1). Capture each transcript
**verbatim into the verify report**.

- [x] 7.1 **DONE — executed in the prescribed order.** `bump.yml` was **disabled before the `v1.2.0` tag
      was pushed** (race-safe ordering: the pause precedes the tag, exactly as R4 requires) and
      **re-enabled immediately after the tap merge** (see 7.5). Only the workflow's *schedule state*
      was touched; `bump.yml`'s content was never edited, so R4 was not reopened.
      *(Original task text follows.)* **DEFERRED — pre-tag maintainer gate. Pause the automated bump.** Before pushing `v1.2.0`,
      disable `bump.yml`'s `17 */6 * * *` schedule in `juancasanueva/homebrew-cellar` (or supersede any
      open bump PR). It rewrites `version`/`sha256` **without** touching the `app` stanza, so an unpaused
      bump against the renamed release lands exactly the mismatch R4 forbids. Restore it in 7.5, not
      before, and do **not** edit `bump.yml`'s content — only its schedule state.
- [x] 7.2 **DONE — the asset proof holds; the stop condition did not fire.** `v1.2.0` was tagged on
      `c7f9f0f`; release run **32668275745** succeeded and published
      **`Home-Cellar-1.2.0.zip`** (6,469,774 bytes),
      `sha256 3e2b5c89dd02449756d38f9f2c7001414063ab0adf2c0f85cbfe88184dcfe259` — the digest of the
      **downloaded** asset, which is what fed 7.3. Verified by the orchestrator via `unzip -Z1`: the
      archive contains `Home-Cellar.app/` and **zero** lowercase `cellar.app` entries. The renamed
      bundle is genuinely inside the published zip, so 7.3 was unblocked.
      *(Original task text follows.)* **DEFERRED — post-tag asset proof (the pre-condition for 7.3).** Once `v1.2.0` publishes,
      download `Home-Cellar-1.2.0.zip` and prove it carries the renamed bundle **before** touching the
      tap: `unzip -Z1 Home-Cellar-1.2.0.zip | head -2` must print `Home-Cellar.app` and
      `Home-Cellar.app/Contents/MacOS/Home-Cellar`. Record `shasum -a 256` of that **downloaded** file —
      not a build-time value — as the `sha256` for 7.3. If it still contains `cellar.app`, **stop**.
- [x] 7.3 **DONE — the atomic commit exists and is genuinely atomic.** `7c50ee6` was amended into
      **`35fd080`**, which moves `version "1.2.0"`, the 7.2 `sha256`
      (`3e2b5c89dd02449756d38f9f2c7001414063ab0adf2c0f85cbfe88184dcfe259`) and
      `app "Home-Cellar.app"` **together in that one commit**. `brew style` → clean. Pushed and
      opened as tap PR **#1**. **This is the discharge of verify-report W4**: the held commit is no
      longer merely *prepared*, and the mechanism the amended R4 prescribes executed exactly as
      written.
      *(Original task text follows.)* **DEFERRED — maintainer action. The atomic tap commit.** Amend `7c50ee6` on
      `feat/m8-bundle-rename` in `/Users/juancasanueva/programming/swiftUI/homebrew-cellar` so
      `version "1.2.0"`, the 7.2 `sha256`, and `app "Home-Cellar.app"` all move in **that one commit**;
      the four-step procedure is already written into its message. Push and open the tap PR. Its CI is
      the verification: `brew style`, `brew audit --cask --online --strict`, and the install/uninstall
      job resolving the `app` artifact against `/Applications/Home-Cellar.app` — only passable once 7.2 holds.
- [x] 7.4 **DONE — tap PR #1 merged as `5b4b83c`** (2026-08-23T21:48:53Z). The tap's default branch now
      carries `version`, `sha256` and `app` all describing the **same** published release (`v1.2.0` /
      `Home-Cellar-1.2.0.zip` / `Home-Cellar.app`), which is the state R4 mandates and the state
      Phase 1 alone could not reach.
      *(Original task text follows.)* **DEFERRED — maintainer gate.** The tap PR is **merged** and its CI install round trip is
      green. Confirm by reading `Casks/home-cellar.rb` on the tap's **default** branch: `version`,
      `sha256` and `app` must all describe the same published release. Do not trust Phase 1.
- [x] 7.5 **DONE — schedule restored immediately after the tap merge.** Both tap workflows (**Bump** and
      **CI**) are active again. The pause window was therefore exactly the interval between the tag
      and the atomic commit, which is the minimum R4 permits.
      **Carried forward, not claimed**: the bump's *next scheduled run* had not yet fired at archive
      time, so the delta scenario *Keeping the cask current is idempotent on the declared version*
      remains `ci-gate`-pending by declared class, as it is for every release. Restoring the schedule
      is what this task owed; observing the no-op is the gate's job, not this change's.
- [x] 7.6 **DONE — ME1 observed on the maintainer's Mac, 2026-08-23.** Every clause of the scenario was
      met: `brew uninstall --cask home-cellar` removed `/Applications/cellar.app`, then
      `brew install --cask home-cellar` installed **`/Applications/Home-Cellar.app`** with
      `CFBundleShortVersionString` **1.2.0** and `CFBundleIdentifier` **`com.juancasanueva.cellar`**
      (unchanged — the invariant held across the rename). `brew list --cask --versions` →
      `home-cellar 1.2.0`. `spctl -a -vv` → **accepted, source=Notarized Developer ID**, so there was
      no Gatekeeper refusal. The maintainer launched the app and confirmed **all data was present**,
      which is the bundle-id-keyed persistence carrying over exactly as D1 predicted.
      **Observed deviation, recorded not smoothed:** the uninstall receipt showed stale **1.0.0**
      metadata (the `Homebrew/brew#22993` shape). Artifact removal still worked; this is a known brew
      receipt defect, not a defect in this change.
      *(Original task text follows.)* **DEFERRED — post-tag `manual-evidence`, maintainer's Mac.** Unreachable until 7.4 holds.
      **ME1 — "A tap and an install put the released build in `/Applications`."**
      `brew uninstall --cask home-cellar` → `brew install --cask home-cellar` →
      `/Applications/Home-Cellar.app` exists and reports the released version, `codesign -dvvv` reads
      the new path, `Contents/MacOS/Home-Cellar` is present, and the app launches with no Gatekeeper
      refusal.
- [ ] 7.7 **STAYS OPEN at archive — deliberately, with a reason that has not expired.** ME2 needs a
      Sparkle self-update of a **cask-installed copy of the renamed build**. `v1.2.0` *is* that build
      and it is now installed (7.6), but no newer stable release exists for it to update **to**, so
      the precondition is still unreachable — the same reason as before the tag, not a skipped step.
      This is a `manual-evidence` scenario that the **next** release discharges; it is recorded in the
      archive report as an open follow-up rather than being marked done on an untested inference.
      Note the m6-cask-tap precedent: that slice observed ME2 for `cellar.app` and archived with it
      passing, but that observation binds the **old** bundle name and is not evidence for this one.
      *(Original task text follows.)* **DEFERRED — post-tag `manual-evidence`, maintainer's Mac.** Requires a Sparkle self-update of
      a cask-installed copy of the renamed build, which cannot exist before the tag. The
      `--dry-run` binding below stands. **ME2 — "A self-updated app does not fight `brew upgrade`."** After a Sparkle self-update in
      place, Homebrew does not report the copy as outdated and does not reinstall over it, and exactly
      one bundle exists at the original path.
      **BINDING — never run `brew upgrade` without `--dry-run` on the maintainer's Mac** (Engram
      `#7724`). Use `brew upgrade --cask --dry-run home-cellar`. This applies to every retry.
- [x] 7.8 **DISCHARGED by the round-2 verify report** (`sdd/m8-bundle-rename/verify-report`, obs
      **#7752**), which carries the honesty statement verbatim and explicitly states: *"This report
      does not claim `release.sh` is verified end-to-end, and does not claim the pipeline is
      verified."* It classified 9 `ci-gate` and 2 `manual-evidence` scenarios as execution-pending by
      declared class rather than counting them as run.
      *(Original task text follows.)* **DEFERRED to `sdd-verify`** — this is an obligation on the verify report, which this phase
      does not author. Stated here for the record: the five `BundleNamingTests` cases prove the
      pipeline is **composed** to produce `Home-Cellar.app`; `release.sh` and `release.yml` are
      **unexercised** until the `v1.2.0` run, and the three tap `ci-gate` scenarios until the tap CI
      runs. **Composition-only honesty.** Record in the verify report that the nine `ci-gate` scenarios
      are proven **composed** (RED units 1–5 plus the tap's own `ci.yml`) and **exercised** only by the
      `v1.2.0` run and the tap CI. `sdd-verify` MUST NOT claim `release.sh` is verified end-to-end.

## Phase 8: Archive obligations (recorded now so they are not re-derived at `sdd-archive`)

- [x] 8.1 **DONE at archive — all six passages hand-edited.** `:567`→`m6-release-pipeline` D4/D7,
      `:601`→the inherited-contract stanza, `:619`→the `U31` probe, `:686-688`→`m6-cask-tap` D3,
      `:706`→the "now CONSUMED" paragraph, `:718-720`→the deferred-slice list. (Line numbers had
      drifted by the merge; each was re-located by content.) **The `:619` probe rule was applied
      throughout**: the five historical passages keep their recorded measurement or decision verbatim
      and carry an annotation that the path has since moved — none was silently rewritten. **`:601`
      was the exception and was updated in place**, because it states a *live* requirement in the
      present tense ("the cask's `app` stanza must name … exactly") and left alone it would have
      contradicted the merged requirement in the same file. `:686-688` records that D3's rejection of
      `target:` **still stands**; `:718-720` moves the rename from *deferred* to *landed* with its
      update-continuity clause marked **closed by D1**, and leaves the other two deferred items
      deferred.
      *(Original task text follows.)* **DEFERRED to `sdd-archive` by design** — the obligation is recorded, not executed here;
      `openspec/specs/release-distribution/spec.md` is only edited at archive time. **R7 — six provenance passages sit outside every requirement block and a MODIFIED delta
      structurally cannot carry them** (three added by remediation, W2). `sdd-archive` MUST hand-edit
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
      **`:567`** (`m6-release-pipeline` D4/D7, "containing `cellar.app`") and **`:706`** (the "now
      CONSUMED" paragraph, "its `app` stanza to `cellar.app`") are historical: keep each fact, mark the
      path as since moved. **`:601`** is **the urgent one** — it says the cask's `app` stanza "must name
      `cellar.app` exactly" in the **present tense**, so left alone it directly contradicts the merged
      requirement; record that `m8-bundle-rename` superseded it.
- [x] 8.2 **DONE at archive, and the arithmetic was confirmed against the merged file, not the note.**
      Counted `- Verification:` lines in `openspec/specs/release-distribution/spec.md`: **42 total —
      `unit` 18, `ci-gate` 18, `manual-evidence` 6**, matching 42 `#### Scenario:` headings and 10
      `### Requirement:` headings. Only the `ci-gate` cell needed editing (**17 → 18**); `unit` and
      `manual-evidence` were already correct at 18 and 6. The note's predicted counts and the measured
      counts agree.
      *(Original task text follows.)* **DEFERRED to `sdd-archive`.** **Hand-update the `## Verification classes` table** (outside every requirement block, as its
      counts were hand-updated at `:627-632`). This delta adds **one** scenario (*The rename ships no
      migration mechanism*, `ci-gate`): `unit` 18 / `ci-gate` 17 / `manual-evidence` 6 (41) →
      `unit` **18** / `ci-gate` **18** / `manual-evidence` **6** (**42**). **Confirm the arithmetic by
      counting `- Verification:` lines in the merged file**, not by trusting this note.
- [x] 8.3 **DONE — recorded in the merged spec's `## Provenance` and in the archive report.** The delta
      is **3 MODIFIED / 0 added / 0 removed / 0 renamed**, so `rules.archive`'s destructive-delta
      warning **did not fire** and no capability count in any other spec changed. The deliberate
      divergence from the proposal's "counts are unchanged" line is recorded verbatim: the scenario
      count moved 41 → 42 (one added `ci-gate` scenario, *The rename ships no migration mechanism*)
      while the binding Capabilities contract — **zero ADDED requirements** — was honoured exactly.
      *(Original task text follows.)* **DEFERRED to `sdd-archive`.** Record that the delta is **3 MODIFIED / 0 added / 0 removed / 0 renamed**, so
      `rules.archive`'s destructive-delta warning does not fire and no capability count in any other
      spec changes. Record the deliberate divergence from the proposal's "counts are unchanged" line:
      the scenario count moves by one while the binding Capabilities contract (zero ADDED
      requirements) is honoured exactly.
- [x] 8.4 **DONE — recorded in the merged spec's `## Provenance` and in the archive report**, satisfying
      `config.yaml` `rules.archive`'s "record which PRD milestone the archived change closed". Closes
      **M6 "Ship"** (`PRD.md:216-217`), specifically its cask-channel line `:194`, which promised
      `/Applications/cellar.app` and now names `/Applications/Home-Cellar.app` — the last of the four
      names collapsed into one. **D1** and **D2** are both recorded with what each rejected, and the
      two surviving deferred follow-ups (the cache directory under the bundle identifier; the
      `homebrew/cask` submission) are carried forward explicitly as still deferred.
      *(Original task text follows.)* **DEFERRED to `sdd-archive`.** Record the PRD milestone this closes: **M6 "Ship"** (`PRD.md:216-217`), specifically the
      cask-channel line `:194`. Record **D1** (no installed base, no migration mechanism anywhere) and
      **D2** (all three defaults accepted: `cellar.xcarchive` unchanged; no target/folder rename; the
      product/module divergence accepted), with what each rejected. Record the deferred follow-ups
      that remain: the cache directory under the bundle identifier, and the `homebrew/cask`
      submission.
