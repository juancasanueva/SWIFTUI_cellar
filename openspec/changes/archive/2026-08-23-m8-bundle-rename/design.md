# Design: One Name on Disk — `cellar.app` → `Home-Cellar.app` (`m8-bundle-rename`)

Implements **explore Approach 3 without the 3b `EXECUTABLE_NAME` pin**, as accepted in
`proposal.md` (2026-08-23, all three defaults taken, D1 binding).

> **Size note.** This document exceeds the generic 800-word phase budget deliberately. The slice is
> a line-by-line rename across two repositories; a design that does not carry the exact lines forces
> `sdd-tasks` and `sdd-apply` to re-derive the inventory that `explore.md` §2 already measured.
> House precedent: `archive/2026-08-23-m7-tap-trust/design.md`.

## R5 probe — MEASURED (pre-change), 2026-08-23

The proposal (:134-139) and explore (:285-289) require the pre-change probe. It was run on the
maintainer's machine against the pre-change tree at `main f0a5817`. Verbatim output of
`xcodebuild -project cellar.xcodeproj -target cellar -showBuildSettings 2>/dev/null | rg 'PRODUCT_MODULE_NAME|PRODUCT_NAME|EXECUTABLE_NAME|FULL_PRODUCT_NAME|PRODUCT_BUNDLE_IDENTIFIER'`:

```
EXECUTABLE_NAME = cellar
FULL_PRODUCT_NAME = cellar.app
PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar
PRODUCT_MODULE_NAME = cellar
PRODUCT_NAME = cellar
```

**R5 is closed on the pre-change side.** `PRODUCT_MODULE_NAME = cellar` is confirmed to be the
*resolved* value today, produced by the undeclared default `$(PRODUCT_NAME:c99extidentifier)` —
which is why 22 `@testable import cellar` files compile now, and exactly what breaks under
Approach 2 once `PRODUCT_NAME` becomes `Home-Cellar` (`Home-Cellar:c99extidentifier` = `Home_Cellar`).
The measurement, not the documentation, is now the basis for DD-1.

Corroborating source evidence measured this phase:

| Fact | Evidence |
|---|---|
| `PRODUCT_NAME = "$(TARGET_NAME)"` in both app-target blocks | `project.pbxproj:446`, `:482` |
| Target name is `cellar`; product ref `path = cellar.app` | `project.pbxproj:38` |
| `PRODUCT_MODULE_NAME` appears **nowhere** in the repository | repo-wide grep: 0 hits outside `openspec/changes/m8-bundle-rename/*.md` |
| `EXECUTABLE_NAME` / `FULL_PRODUCT_NAME` appear **nowhere** | same grep, 0 hits |
| `@testable import cellar` count | **22** files under `cellarTests/` (24 grep hits − 2 SDD docs) |

The three probed names are therefore *resolved defaults*, declared in no file — the condition
Approach 3 replaces with two explicit pins.

**Post-change probe — still owed, apply-phase verification step.** `sdd-tasks` carries the
post-edit re-probe as work unit 0. Same command; expected after the pbxproj edit:

```
EXECUTABLE_NAME = Home-Cellar
FULL_PRODUCT_NAME = Home-Cellar.app
PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar
PRODUCT_MODULE_NAME = cellar
PRODUCT_NAME = Home-Cellar
```

`PRODUCT_BUNDLE_IDENTIFIER` and `PRODUCT_MODULE_NAME` must read **identically** before and after;
those two unchanged lines are the whole invariant this slice rests on.

## Technical approach

Two settings in the pbxproj carry the whole change; everything else is a path that must follow them.
The Xcode **target**, the **scheme**, `TEST_TARGET_NAME`, the `cellar/` folder and
`PRODUCT_BUNDLE_IDENTIFIER` are frozen, so the Swift module, all 22 `@testable import cellar` lines
and every documented `-scheme cellar` command are untouched by construction.

```
PRODUCT_NAME = "Home-Cellar"  ──┬──→ EXECUTABLE_NAME  ──→ Contents/MacOS/Home-Cellar
                                └──→ FULL_PRODUCT_NAME ──→ Home-Cellar.app
                                          │
PRODUCT_MODULE_NAME = cellar  ──X─────────┘   (severs the $(PRODUCT_NAME:c99extidentifier)
                                               default; module stays `cellar`)

    pbxproj ──→ scheme BuildableName ──→ release.sh $PRODUCT ──→ release.yml:159
                                              └──→ Home-Cellar-<v>.zip (already correct)
                                                        │
                                              tap Casks/home-cellar.rb: app "Home-Cellar.app"
```

## Architecture decisions

| # | Decision | Alternatives rejected | Rationale |
|---|---|---|---|
| DD-1 | Pin `PRODUCT_MODULE_NAME = cellar` alongside `PRODUCT_NAME = "Home-Cellar"`, asserted together in one test | Approach 1 (rename the target): drags `TEST_TARGET_NAME`, `remoteInfo`, `BlueprintName`, every `-scheme` command, and still breaks 22 imports. Approach 2 (`PRODUCT_NAME` alone): the module silently becomes `Home_Cellar` and 22 files fail to compile | Smallest change that makes every user-visible name agree. The divergence is internal and never rendered anywhere a person looks |
| DD-2 | Let `EXECUTABLE_NAME` follow to `Home-Cellar` | Approach 3b (pin `EXECUTABLE_NAME = cellar`): saves 4 changed lines | `Contents/MacOS/cellar` is what Activity Monitor and `codesign -dvvv` print. Pinning it re-creates the exact inconsistency this slice exists to delete |
| DD-3 | Split `release.sh`'s `SCHEME` into `SCHEME` (scheme + archive) and `PRODUCT` (bundle + executable) | Keep one constant and rename it | One constant serving four roles is why the rename is not a sed. The split makes the two axes independently correct and is itself the assertion RED unit 3 makes |
| DD-4 | `cellar.xcarchive` stays (`ARCHIVE_PATH` keeps `$SCHEME`) | Rename it to `Home-Cellar.xcarchive` | Proposal Q1 default, accepted. A build intermediate no user sees; renaming adds `RELEASING.md` churn for zero visible gain. Closes **R8** deliberately rather than by omission |
| DD-5 | Quote every pbxproj value containing a hyphen (`path = "Home-Cellar.app";`, `PRODUCT_NAME = "Home-Cellar";`), leave `PRODUCT_MODULE_NAME = cellar;` bare | Write the hyphenated values bare | Xcode's OpenStep-plist serializer quotes tokens outside `[A-Za-z0-9_$./]`. Writing them bare invites a spurious rewrite-diff the next time Xcode saves the project. The repo has **no** existing hyphenated pbxproj path to copy, so this is stated rather than inherited |
| DD-6 | Insert `PRODUCT_MODULE_NAME` between `PRODUCT_BUNDLE_IDENTIFIER` and `PRODUCT_NAME` in both blocks | Append anywhere in the block | Build-setting dictionaries are alphabetically sorted; any other position is reordered on the next Xcode save. Also required by DD-7 |
| DD-7 | Both app-target blocks receive both settings, in identical order | Debug-only or Release-only, or differing order | **Not optional**: `ReleasePipelineCompositionTests.appTargetConfigurationsAreIdenticalModuloName` (`:213-229`) already requires the two blocks to be line-identical modulo `name = `. A one-sided edit turns an existing green guard RED. This existing test is free enforcement of RED unit 1's "both blocks" clause |
| DD-8 | Tap edits carry **no** app-repo test | Add a scanning test that reads `../homebrew-cellar` | `ReleasePipelineCompositionTests:808` asserts the app repo must **not** name `homebrew-cellar`. No app-repo test reads the tap clone today (verified: single grep hit, and it is that negative assertion). A test reading a sibling checkout would be green or red depending on whether the maintainer happens to have cloned it |

`config.yaml` `rules.design`: the CellarCore/app-target split, protocol boundaries, actor isolation
and `#available` rules are **not applicable** — no Swift source file in `cellar/` or
`Packages/CellarCore/` is touched.

## Edit plan

### 1. `cellar.xcodeproj/project.pbxproj` — 5 changed, 2 added, 3 comments

| Line | From | To |
|---|---|---|
| :38 | `… /* cellar.app */ = {isa = PBXFileReference; … path = cellar.app; sourceTree = BUILT_PRODUCTS_DIR; };` | `… /* Home-Cellar.app */ = {isa = PBXFileReference; … path = "Home-Cellar.app"; sourceTree = BUILT_PRODUCTS_DIR; };` (DD-5) |
| :107 | `BCDBE97B… /* cellar.app */,` | `/* Home-Cellar.app */` |
| :142 | `productReference = BCDBE97B… /* cellar.app */;` | `/* Home-Cellar.app */` |
| :446 (Debug) | `PRODUCT_NAME = "$(TARGET_NAME)";` | `PRODUCT_NAME = "Home-Cellar";` |
| :482 (Release) | `PRODUCT_NAME = "$(TARGET_NAME)";` | `PRODUCT_NAME = "Home-Cellar";` |
| after :445 | — | **ADD** `PRODUCT_MODULE_NAME = cellar;` (DD-6) |
| after :481 | — | **ADD** `PRODUCT_MODULE_NAME = cellar;` (DD-6) |
| :510, :531 | `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/cellar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/cellar";` | `…/Home-Cellar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Home-Cellar";` |

**Unchanged — binding**: `:445`/`:481` `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;`
(0-line diff), `:504`/`:525`/`:544`/`:563` test-target `PRODUCT_NAME = "$(TARGET_NAME)"`,
`:550`/`:569` `TEST_TARGET_NAME = cellar;`, `:132`/`:141` `name`/`productName`, `:26`/`:33`
`remoteInfo`.

### 2. `cellar.xcodeproj/xcshareddata/xcschemes/cellar.xcscheme` — 3 lines

`:19` (Build), `:73` (Test/macroExpansion), `:104` (Launch/Profile):
`BuildableName = "cellar.app"` → `BuildableName = "Home-Cellar.app"`.
`BlueprintIdentifier = "BCDBE97A301E2D410013A38D"`, `BlueprintName = "cellar"` and the filename
`cellar.xcscheme` are **unchanged** — `:39`/`:50` (`cellarTests.xctest`, `cellarUITests.xctest`) are
untouched.

### 3. `scripts/release.sh` — 1 added, 4 changed

| Line | From | To |
|---|---|---|
| after :31 | — | **ADD** `readonly PRODUCT="Home-Cellar"` |
| :48 | `APP="$EXPORT_DIR/$SCHEME.app"` | `APP="$EXPORT_DIR/$PRODUCT.app"` |
| :50 | `VERIFIED_APP="$VERIFY_DIR/$SCHEME.app"` | `VERIFIED_APP="$VERIFY_DIR/$PRODUCT.app"` |
| :148 | `lipo -archs "$APP/Contents/MacOS/$SCHEME"` | `…/MacOS/$PRODUCT"` |
| :236 | `lipo -archs "$VERIFIED_APP/Contents/MacOS/$SCHEME"` | `…/MacOS/$PRODUCT"` |

**Kept on `SCHEME`** (2 uses): `:46` `ARCHIVE_PATH="$BUILD/$SCHEME.xcarchive"` (DD-4) and `:118`
`-scheme "$SCHEME"`. **Unchanged — binding**: `:31` `readonly SCHEME="cellar"`, `:245-246` the
`plutil -extract CFBundleDisplayName raw` == `Home-Cellar` gate, `:275`
`ZIP="$BUILD/Home-Cellar-$VERSION.zip"`.

> Correction to the orchestrator brief: there are **four** product/executable substitutions in
> `release.sh`, not five. The proposal's five `release.sh` lines (`:31, :48, :50, :148, :236`) count
> the constant-declaration site plus the four substitutions. The fifth *path* substitution is
> `release.yml:159`, in the other file. Measured directly: `$SCHEME` occurs at exactly
> `:31, :46, :48, :50, :118, :148, :236`.

### 4. `.github/workflows/release.yml` — 1 line

`:159` `codesign -dvvv --entitlements :- "build/export/cellar.app" 2>&1` →
`"build/export/Home-Cellar.app"`. `:173`, `:190`, `:191` already name
`Home-Cellar-${VERSION}.zip` — unchanged.

### 5. App-repo docs (D1: new name only, no migration copy anywhere)

| File:line | Current | Action |
|---|---|---|
| `README.md:42` | "That installs `/Applications/cellar.app`" | → `Home-Cellar.app` |
| `README.md:49-60` | "**Already have `cellar.app` in `/Applications`?**" + the collision quote + adopt paragraph | Rewrite for `Home-Cellar.app` only, for the **direct-download → cask** path. The fenced `brew install --cask --adopt home-cellar` line at `:54` stays **byte-identical** (keeps `theReadmeCarriesTheAdoptCommandAsAWholeLine` green) |
| `README.md:63` | "drag `cellar.app` to `/Applications`" | → `Home-Cellar.app` |
| `RELEASING.md:265` | `cellar.app: accepted` (sample `spctl` output) | → `Home-Cellar.app: accepted` |
| `RELEASING.md:303` | \| Bundle inside it \| `cellar.app`, display name `Home-Cellar` \| | → `Home-Cellar.app`, display name `Home-Cellar` |
| `RELEASING.md:336` | \| Installed path \| `/Applications/cellar.app` … \| | → `/Applications/Home-Cellar.app` |
| `RELEASING.md:348-356` | "A direct-download copy blocks a plain install" paragraph | Rewrite naming `Home-Cellar.app` only |
| `PRD.md:194` | "installs `/Applications/cellar.app`" | → `/Applications/Home-Cellar.app` |

**No** migration paragraph is added anywhere (D1). Explore §2.G's "plus a new migration paragraph"
and §4's migration mechanisms are superseded by the proposal and MUST NOT be reintroduced.

### 6. Tap repo `/Users/juancasanueva/programming/swiftUI/homebrew-cellar` — ordered first

| File:line | Current | Action |
|---|---|---|
| `Casks/home-cellar.rb:20` | `app "cellar.app"` | `app "Home-Cellar.app"` |
| `.github/workflows/ci.yml:77` | `test -d "/Applications/cellar.app"` | → `Home-Cellar.app` |
| `.github/workflows/ci.yml:79` | `"/Applications/cellar.app/Contents/Info.plist"` | → `Home-Cellar.app` |
| `.github/workflows/ci.yml:90` | `test ! -d "/Applications/cellar.app"` | → `Home-Cellar.app` |
| `README.md:14` | "installs `/Applications/cellar.app`" | → `Home-Cellar.app` |
| `README.md:16` | "`cellar.app` in both channels; the app presents itself as **Home-Cellar**" | Collapse to one name — the "presents itself as" caveat is exactly what this slice deletes |
| `README.md:29` | "### Already have `cellar.app` in `/Applications`?" | Rewrite for `Home-Cellar.app` |
| `README.md:32` | collision quote `'/Applications/cellar.app'` | → `Home-Cellar.app` |

**Unchanged — binding**: `Casks/home-cellar.rb:11-14` `livecheck`, `:16` `auto_updates true`,
`:22-28` `zap trash:` (no data root moves), `.github/workflows/bump.yml` (any edit reopens R4).

## Test design (strict TDD)

Pattern followed: the house's **source-scanning test** idiom — a `nonisolated enum …Sources` that
anchors the repository root off `#filePath` (never the working directory) and reads files as text.
Each slice redeclares its own anchor rather than importing another's, so rollback is one file
(`UpdateProjectFileTests.swift:9-33`, `CaskZapInventoryTests.swift:9-45`, both citing the same
reason).

**New file: `cellarTests/BundleNamingTests.swift`** — one net-new file, deletable on rollback.
It declares `nonisolated enum BundleNamingSources` with the `#filePath` anchor and reuses
`UpdateProjectSources`' block-splitting *approach* (re-declared, not imported, per the idiom).

| # | Test | Reads | Asserts | RED because |
|---|---|---|---|---|
| 1 | `bothAppTargetConfigurationsNameTheProductAndPinTheModule` | `project.pbxproj` | Blocks filtered by `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;` (trailing `;` is load-bearing — it excludes `…cellarTests`) number **2**; `PRODUCT_NAME = "Home-Cellar";` in **2**; `PRODUCT_MODULE_NAME = cellar;` in **2**. Asserted in one test so the divergence is deliberate and discoverable (DD-1) | Neither line exists today |
| 2 | `theTestHostResolvesThroughTheRenamedBundle` | `project.pbxproj` | `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Home-Cellar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Home-Cellar";` occurs **twice**; the string `cellar.app` occurs **zero** times in the file | Says `cellar.app/…/cellar` |
| 3 | `theReleaseScriptSeparatesTheProductFromTheScheme` | `scripts/release.sh` | `readonly PRODUCT="Home-Cellar"` present; `-scheme "$SCHEME"` still present; `$SCHEME.app` absent; `MacOS/$SCHEME` absent; `$PRODUCT.app` occurs twice; `MacOS/$PRODUCT` occurs twice | `SCHEME` is conflated across four roles |
| 4 | `theSharedSchemeBuildsTheRenamedBundle` | `cellar.xcscheme` | `BuildableName = "Home-Cellar.app"` occurs **3** times; `BuildableName = "cellar.app"` **0**; `BlueprintName = "cellar"` still **3** (the anti-overreach half) | Nothing pins the scheme |
| 5 | `theWorkflowInspectsTheRenamedExportPath` | `.github/workflows/release.yml` | `build/export/Home-Cellar.app` present; `build/export/cellar.app` absent | `:159` is hardcoded to the old path |

Counts are asserted as **exact numbers**, not `contains`, because `"Home-Cellar.app"` *contains*
`"Cellar.app"` but not `"cellar.app"` — substring assertions in either direction are the R6 trap.

**Existing test to update deliberately (R6).** `CaskZapInventoryTests.swift:335`
`#expect(readme.contains("cellar.app"))` → `#expect(readme.contains("Home-Cellar.app"))`, and the
doc comment at `:338-342` ("A direct-download copy already sits at `/Applications/cellar.app`…") is
rewritten to name `Home-Cellar.app` and to drop the pre-tap-era framing (D1). **It MUST NOT be
"fixed" by lowercasing, by `caseInsensitiveCompare`, or by widening the substring.** The capital `C`
is the assertion.

**Existing tests that MUST stay green, untouched** — they are the proof the invariants held:

| Test | Why it matters here |
|---|---|
| `ReleasePipelineCompositionTests:94`, `UpdateProjectFileTests:68` | `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;` — 0-line diff. **These two lines are block-selection `.filter`s inside `appTargetBuildConfigurationBlocks()`, not assertions** (verify-report S2): they *select* the two app-target blocks by the identifier, so if the identifier moved they would select 0 blocks and every dependent `blocks.count == 2` assertion would fail. Load-bearing as a filter, not as a guard |
| `ReleasePipelineCompositionTests:213-229` byte-identity | Enforces DD-7; a one-sided pbxproj edit turns it RED |
| `ReleasePipelineCompositionTests:519-521` | `release.sh` still reads `CFBundleDisplayName` |
| `ReleasePipelineCompositionTests:808` | The app repo still names no other repository (DD-8) |
| `CaskZapInventoryTests:344-354` | The adopt command line is unchanged |

**Tap repo has no test harness** (verified: no test directory; `ci.yml` + `bump.yml` only), and per
DD-8 no app-repo test reaches into it. Tap edits are verified by the tap's own `ci.yml`
install/uninstall job, `brew style`, `brew audit --cask --online --strict`, and the manual clean-machine
install in the verification plan.

## Verification plan

| Order | Gate | Command / check |
|---|---|---|
| 0 | **R5 pre-probe** | **DONE** — measured 2026-08-23 at `main f0a5817`; output recorded verbatim above |
| 1 | Core package | `swift test --package-path Packages/CellarCore` (must be unaffected) |
| 2 | Build | `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` |
| 3 | Full suite | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` — **no** `-scheme`, `-only-testing:` or `TEST_TARGET_NAME` argument may change |
| 4 | **R5 post-probe (blocking, tasks work unit 0)** | Same command. Expect `PRODUCT_NAME = Home-Cellar`, `PRODUCT_MODULE_NAME = cellar`, `EXECUTABLE_NAME = Home-Cellar`, `FULL_PRODUCT_NAME = Home-Cellar.app`, `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar`. Diff against the pre-change output above: only `PRODUCT_NAME`, `EXECUTABLE_NAME` and `FULL_PRODUCT_NAME` may move |
| 5 | Import proof | All 22 `@testable import cellar` files compile with zero source edits (implied by gate 3, stated so it is checked) |
| 6 | Display-name gate | `release.sh:245-246` `plutil` check — **unmodified**, must still pass at the next release run |
| 7 | Tap CI | Tap PR: `brew style`, `brew audit --cask --online --strict`, and the `ci.yml` install/uninstall job against `/Applications/Home-Cellar.app` |
| 8 | Manual, post-tag | `brew uninstall --cask home-cellar` → `brew install --cask home-cellar` → `/Applications/Home-Cellar.app` exists, `codesign -dvvv` reads the new path, `Contents/MacOS/Home-Cellar` is present |

**`release.sh` runs end-to-end only at the next tag.** Gates 1-5 prove the build settings; the
script's own product/executable paths are proven statically by RED unit 3 and only exercised for
real by the `v1.2.0` release run (gate 8). `sdd-verify` MUST NOT claim the pipeline is verified —
it is *composed* correctly and *unexercised* until the tag.

## Delivery design

```
  ┌─ tap repo  feat/m8-bundle-rename ─┐          ┌─ app repo feat/m8-bundle-rename ─┐
  │  home-cellar.rb :20               │          │  pbxproj · scheme · release.sh   │
  │  ci.yml :77,:79,:90               │  MUST    │  release.yml · docs · tests      │
  │  README.md :14,:16,:29,:32        │  MERGE   │  spec delta                      │
  └───────────────┬───────────────────┘  FIRST   └────────────────┬─────────────────┘
                  │                                               │
                  ▼ (R4)                                          ▼
        tap PR merged ─────────────────────────────────→ app PR merged ──→ v1.2.0 tag pushed
```

- **App repo**: one PR on `feat/m8-bundle-rename` (`single-pr`, cached strategy). ~310-380 authored
  lines: **Low** against the governing 5,000-line budget, **Medium** against the default 400-line
  reviewer guard.
- **Tap repo**: one PR on a branch of the same name, ~14 lines.
- **R4 ordering dependency (binding, explicit)**: the tap PR MUST be merged **before** the app's
  `v1.2.0` tag is pushed. `bump.yml` runs `17 */6 * * *`, rewrites only `version`/`sha256`, and gates
  on `brew style` + `brew audit` — **none of which extracts the archive or resolves the `app`
  stanza**. A tag pushed against `app "cellar.app"` produces a cask that audits clean and installs
  broken. `sdd-tasks` MUST model this as an ordering edge between work units, not a note.
  Fallback if the tap PR cannot land first: pause `bump.yml` across the window.
- The rename **rides the next tag** — no rename-only release (D1).

### Rollback

| Order | Step | Effect |
|---|---|---|
| 1 | Revert the tap commit | `app "cellar.app"` returns; `bump.yml` untouched, so nothing else drifts |
| 2 | Revert the app-repo merge | `PRODUCT_NAME` → `$(TARGET_NAME)`, `PRODUCT_MODULE_NAME` disappears; **the module name is `cellar` either way** — that is what the pin buys |
| 3 | If a tag already shipped | Revert the tap **first**, then re-point it at the last `cellar.app` asset. A reverted app repo against a `Home-Cellar.app` cask is R4 inverted |

Post-revert checks: gates 1 and 2 above. No schema, cache file, Keychain item, dependency or
user-data path changes, so a revert orphans nothing on any machine.

## Threat matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | **N/A** — no file's executable/documentation classification changes. The `.md` edits are prose that is never executed; `scripts/release.sh` keeps its shebang, mode and location, already guarded by `ReleasePipelinePlacementTests` T1/T12 | — | None |
| Git repository selection | **Applicable** — the slice spans two repositories | No new `git -C`, cwd selector or cross-repository reach is introduced. `release.sh` still resolves its root from `$0` (`:35-39`), never from the working directory. The app repo must continue to name no other repository | None new — `ReleasePipelineCompositionTests:808` is the existing regression boundary and MUST stay green; a duplicate would be ceremony (DD-8) |
| Commit state | **N/A** — the slice adds and changes no index/commit automation. `release.yml` is tag-triggered and creates no commit; `bump.yml`, which does commit, is untouched | — | None |
| Push state | **Applicable** — the `v1.2.0` tag push is the trigger, and pushing it early is R4 | Tap PR merges first; modelled as a task-level ordering edge. Fallback: pause `bump.yml` | None in-repo — the boundary is a cross-repository sequencing fact, not a code path. Enforced by the tap's `ci.yml` install/uninstall job (verification gate 7) and the pre-tag checklist item (gate 8) |
| PR commands | **N/A** — no PR automation is added or changed. `gh release create` (`release.yml:173`) already names `Home-Cellar-${VERSION}.zip` and is not edited | — | None |

## Migration / rollout

**No migration.** D1 is binding: the installed base is empty, so R1 (Sparkle keeps a self-updating
copy at its old path), R2 (duplicate bundles for direct-download users) and R3 (Homebrew/brew#22993
orphans the old bundle) are recorded facts in `explore.md` §3-4 and non-issues for this slice. No
`target:` stanza, no `zap trash:` entry for the old path, no `uninstall delete:`, no `SUBundleName`,
no in-app notice, no user-facing old-name guidance anywhere. The maintainer reinstalls their own Mac
by hand: `brew uninstall --cask home-cellar` then `brew install --cask home-cellar`.

## Open questions

- [x] **R5 pre-change probe** — **measured 2026-08-23** at `main f0a5817`; output verbatim above.
      `PRODUCT_MODULE_NAME = cellar` is confirmed as a resolved default, not an assumption.
      The post-change re-probe stays as `sdd-tasks` work unit 0.
- [x] Q1 `cellar.xcarchive` — resolved by DD-4 (leave it), closing R8.
- [x] Q2 target/folder rename — never; out of scope, not planned.
- [x] Q3 product/module divergence — accepted and documented (DD-1), pinned by RED unit 1.
- [ ] **R7 (for `sdd-spec`/`sdd-archive`, not this phase)**: `openspec/specs/release-distribution/spec.md:619`
      (`Contents/MacOS/cellar` in Provenance prose) and `:686-688` / `:718-720` (this rename recorded
      as the deferred slice) sit outside every requirement block. The delta's *Notes for archive*
      must carry the hand-update obligation, as the verification-class counts were hand-updated at
      `:627-632`.
