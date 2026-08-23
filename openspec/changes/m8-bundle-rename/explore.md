# Exploration: m8-bundle-rename — cellar.app → Home-Cellar.app

Scope: rename the on-disk app bundle to `Home-Cellar.app` so the bundle, the zip
(`Home-Cellar-<version>.zip`), the display name (`Home-Cellar`) and the cask
(`home-cellar`) agree. `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar` MUST NOT change.

Artifact-store note: this file is the OpenSpec half of the hybrid store; the Engram twin is
topic `sdd/m8-bundle-rename/explore` (observation 7745, project `swiftui_cellar`). The explore
executor had no file-writing tool, so the orchestrator materialized this copy from that record.

## 1. Current state (verified)

### 1.1 The three names in play
| Name | Value today | Source |
|---|---|---|
| Bundle on disk | `cellar.app` | `PRODUCT_NAME = "$(TARGET_NAME)"`, target `cellar` |
| Executable | `Contents/MacOS/cellar` | `EXECUTABLE_NAME` defaults to `$(PRODUCT_NAME)` |
| Display name | `Home-Cellar` | `INFOPLIST_KEY_CFBundleDisplayName` + `cellar/InfoPlist.xcstrings` |
| Swift module | `cellar` | `PRODUCT_MODULE_NAME` defaults to `$(PRODUCT_NAME:c99extidentifier)`; **not pinned anywhere** |
| Bundle id | `com.juancasanueva.cellar` | pinned, unchanged by this slice |
| Zip asset | `Home-Cellar-<version>.zip` | `release.sh:275` |
| Cask token | `home-cellar` | derived from first `name "Home-Cellar"` |

### 1.2 No code derives a path from the product name
Verified: `Packages/CellarCore/Sources/Persistence/PersistenceContainer.swift:14,24` and
`Packages/CellarCore/Sources/Catalog/CatalogStore.swift:120` derive Application Support from
`Bundle.main.bundleIdentifier ?? "com.juancasanueva.cellar"`. Caches use the **literal**
`"Cellar"` (`cellar/cellarApp.swift:383`), never the product name.
`cellar/Shell/AboutView.swift:10-16` (`AppIdentity.name`) reads `CFBundleDisplayName` →
`CFBundleName` → `"Cellar"`. **Conclusion: the rename touches no user-data path, no Keychain
service, no cache root.** The queued "cache dir under bundle id" follow-up is orthogonal and
must not be folded into this slice.

### 1.3 UI tests are name-agnostic
All seven `cellarUITests` files use a bare `XCUIApplication()`, resolved through
`TEST_TARGET_NAME = cellar` (`project.pbxproj:550,569`). No UI test hardcodes a bundle name.

### 1.4 CI surface
The app repo has exactly **one** workflow, `.github/workflows/release.yml`. There is no app-repo
`ci.yml`; tests run locally. The tap repo has `ci.yml` and `bump.yml`.

## 2. Complete inventory of references to change

### A. `cellar.xcodeproj/project.pbxproj`
| Line | Current | Action |
|---|---|---|
| :38 | `path = cellar.app; sourceTree = BUILT_PRODUCTS_DIR` | → `Home-Cellar.app` |
| :38, :107, :142 | `/* cellar.app */` comments | cosmetic, follow the rename |
| :446, :482 | `PRODUCT_NAME = "$(TARGET_NAME)";` (Debug/Release) | → `PRODUCT_NAME = "Home-Cellar";` |
| :446, :482 (adjacent) | — | **ADD** `PRODUCT_MODULE_NAME = cellar;` in both blocks |
| :510, :531 | `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/cellar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/cellar";` | → `Home-Cellar.app/.../Home-Cellar` |
| :550, :569 | `TEST_TARGET_NAME = cellar;` | UNCHANGED (target name is not renamed) |
| :132, :141 | `name = cellar; productName = cellar;` | UNCHANGED |

### B. `cellar.xcodeproj/xcshareddata/xcschemes/cellar.xcscheme`
`:19`, `:73`, `:104` — `BuildableName = "cellar.app"` → `"Home-Cellar.app"`.
`BlueprintName = "cellar"` and the scheme filename stay, so `xcodebuild -scheme cellar` and every
documented `test_command` in `openspec/config.yaml:22-25,65,67-68` keep working unchanged.

### C. `scripts/release.sh` — the scheme/product conflation
`:31` `readonly SCHEME="cellar"` is currently used for **four different things**:
- `:46` `ARCHIVE_PATH="$BUILD/$SCHEME.xcarchive"` (archive name — cosmetic, may stay `cellar`)
- `:48` `APP="$EXPORT_DIR/$SCHEME.app"` → must become the **product** name
- `:50` `VERIFIED_APP="$VERIFY_DIR/$SCHEME.app"` → product name
- `:117` `-scheme "$SCHEME"` (scheme — must stay `cellar`)
- `:148` `lipo -archs "$APP/Contents/MacOS/$SCHEME"` → **executable** name
- `:236` `lipo -archs "$VERIFIED_APP/Contents/MacOS/$SCHEME"` → executable name

The fix is to introduce a second constant (e.g. `readonly PRODUCT="Home-Cellar"`) and split the
five product/executable uses from the two scheme uses. ~6 changed + 1 added line.
`:245-246` (`plutil -extract CFBundleDisplayName raw` == `Home-Cellar`) is already correct and
must NOT change — it is the gate that already asserts the target name.
`:275` `ZIP="$BUILD/Home-Cellar-$VERSION.zip"` already correct.

### D. `.github/workflows/release.yml`
`:159` `codesign -dvvv --entitlements :- "build/export/cellar.app"` — hardcoded, not derived from
the script. → `build/export/Home-Cellar.app`. (1 line.)
`:173`, `:190`, `:191` reference `Home-Cellar-${VERSION}.zip` — already correct.

### E. Tap repo `/Users/juancasanueva/programming/swiftUI/homebrew-cellar`
| File:line | Current | Action |
|---|---|---|
| `Casks/home-cellar.rb:20` | `app "cellar.app"` | → `app "Home-Cellar.app"` |
| `.github/workflows/ci.yml:77` | `test -d "/Applications/cellar.app"` | → `Home-Cellar.app` |
| `.github/workflows/ci.yml:79` | `"/Applications/cellar.app/Contents/Info.plist"` | → `Home-Cellar.app` |
| `.github/workflows/ci.yml:90` | `test ! -d "/Applications/cellar.app"` | → `Home-Cellar.app` |
| `README.md:14,16,29,32` | `/Applications/cellar.app`, "`cellar.app` in both channels", the "Already have `cellar.app`?" heading | rewrite + migration note |
| `Casks/home-cellar.rb:22-28` | `zap trash:` (five bundle-id/`Caches/Cellar` paths) | UNCHANGED — no data path moves |
| `.github/workflows/bump.yml` | rewrites only `version` / `sha256` | **no edit needed, but see §5 race** |
| `Casks/home-cellar.rb:11-14` `livecheck` | `url :url`, `strategy :github_latest` | UNCHANGED |

### F. Tests in the app repo
- `cellarTests/CaskZapInventoryTests.swift:335` — `#expect(readme.contains("cellar.app"))`. **This
  fails after the rename**: `"Home-Cellar.app".contains("cellar.app")` is `false` (capital `C`).
- `cellarTests/CaskZapInventoryTests.swift:338-342` — doc comment naming `/Applications/cellar.app`.
- No test binds the zip name, the export path, `PRODUCT_NAME`, `TEST_HOST`, or the scheme's
  `BuildableName`. Grep for `Home-Cellar` / `ZIP_PATH` / `ASSET_URL` / `build/export` across
  `cellarTests/` returns **zero** matches. Under strict TDD this slice must **add** the missing
  RED tests (pbxproj `PRODUCT_NAME` + `PRODUCT_MODULE_NAME`, `release.sh` product/executable split,
  scheme `BuildableName`, README `Home-Cellar.app`).
- `cellarTests/ReleasePipelineCompositionTests.swift:519-521` asserts `release.sh` still reads
  `CFBundleDisplayName` — unaffected.
- `cellarTests/ReleasePipelineCompositionTests.swift:94` and `UpdateProjectFileTests.swift:68`
  assert `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;` — these are the guard that the
  identifier does not move. Unaffected, and they are the reason the invariant is safe.

### G. Docs in the app repo
- `README.md:42` `/Applications/cellar.app`; `:49,:51` the "Already have `cellar.app`?" block;
  `:63` "drag `cellar.app` to `/Applications`". Plus a new migration paragraph.
- `RELEASING.md:265` sample `spctl` output; `:303` "Bundle inside it | `cellar.app`";
  `:336` "Installed path | `/Applications/cellar.app`"; `:350-351` the adopt paragraph.
  §8 needs a migration subsection.
- `PRD.md:194` "installs `/Applications/cellar.app`".

### H. Spec deltas (`openspec/changes/m8-bundle-rename/specs/release-distribution/spec.md`)
Three MODIFIED requirements against `openspec/specs/release-distribution/spec.md`:
1. **"A pushed tag is the only thing that produces a downloadable release"** — `:34` "the bundle
   inside it MUST be **`cellar.app`**" and scenario `:59-65` "named `cellar.app`".
2. **"The delivered build is installable through the project's Homebrew tap"** — `:415-418`
   "MUST place the delivered bundle at **`/Applications/cellar.app`** … this change MUST NOT
   rename it"; scenario `:436`.
3. **"Uninstalling states exactly what it removes, and what it cannot"** — `:489` "MUST state that
   the installed bundle is `cellar.app`"; scenario `:517`.
Plus a **new** update-continuity scenario (see §4).
Note `:619` mentions `Contents/MacOS/cellar` inside a *Provenance* narrative paragraph, and
`:686-688` / `:718-720` record this exact rename as the deferred slice. Provenance is not a
requirement block; a MODIFIED delta cannot carry it, so the archive step must hand-update it the
same way the verification-class counts were hand-updated at `:627-632`.

## 3. Sparkle in-place update — finding with evidence

**Finding: an already-installed copy will update successfully to a zip containing
`Home-Cellar.app`, but its on-disk name stays `cellar.app` forever.**

Evidence, from Sparkle's own source (the project pins Sparkle 2.9.6 at `scripts/appcast.sh:55`):

1. **Locating the app inside the extracted archive** —
   `Sparkle/SUInstaller.m`, `+installSourcePathInUpdateFolder:forHost:isPackage:isGuided:`:
   ```objc
   *bundleFileName = [[host bundlePath] lastPathComponent],
   *alternateBundleFileName = [[host name] stringByAppendingPathExtension:[[host bundlePath] pathExtension]];
   ...
   if ([currentFilename isEqualToString:bundleFileName] ||
       [currentFilename isEqualToString:alternateBundleFileName]) // We found one!
   ...
   } else {
       // Try matching on bundle identifiers in case the user has changed the name of the host app
       NSBundle *incomingBundle = [NSBundle bundleWithPath:currentPath];
       NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
       if (incomingBundle && [incomingBundle.bundleIdentifier isEqualToString:hostBundleIdentifier]) { ... }
   }
   ```
   `Sparkle/SUHost.m`, `- (NSString *)name` resolves `SUBundleName` → `CFBundleDisplayName` →
   `CFBundleName` → Finder display name. Cellar 1.0.0/1.1.0 already ship
   `CFBundleDisplayName = "Home-Cellar"` (`project.pbxproj:437,473`, gated by `release.sh:245-246`),
   so for an installed `cellar.app` the `alternateBundleFileName` is **already `Home-Cellar.app`**.
   The rename therefore hits the *first* match arm, and the bundle-identifier fallback is a second,
   independent safety net because `com.juancasanueva.cellar` does not move. `SUBundleName` is
   **not needed**.

2. **Where it installs** — `Sparkle/SUInstaller.m`,
   `+installerForHost:fileOperationToolPath:updateDirectory:error:`:
   ```objc
   NSString *normalizedInstallationPath = nil;
   if (SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME) {
       normalizedInstallationPath = [self normalizedInstallationPathForHost:host];
   }
   NSString *installationPath;
   if (normalizedInstallationPath != nil &&
       ![[NSFileManager defaultManager] fileExistsAtPath:normalizedInstallationPath]) {
       installationPath = normalizedInstallationPath;
   } else {
       installationPath = host.bundlePath;
   }
   ```
   `SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME` is a **compile-time** flag of the Sparkle
   framework, defaulting to 0. Cellar consumes Sparkle as a prebuilt SPM XCFramework
   (`project.pbxproj:16,72` — `Sparkle in Frameworks`, no `PBXCopyFilesBuildPhase`), so the app
   **cannot** flip it. Therefore `installationPath = host.bundlePath` and every self-updating copy
   stays at `/Applications/cellar.app`.

3. **Corroborating GitHub issues**: sparkle-project/Sparkle
   [#1442](https://github.com/sparkle-project/Sparkle/issues/1442) (rename remains unresolved even
   with `SUBundleName` + the normalize flag), [#55](https://github.com/sparkle-project/Sparkle/issues/55)
   ("SUPlainInstaller always uses the name of the bundle that was updated"),
   [#264](https://github.com/sparkle-project/Sparkle/issues/264).

**Consequence:** the rename is *update-safe* (nobody's updater breaks) but *not update-migrating*.
The installed-base split is permanent and unavoidable through Sparkle.

## 4. Cask / Homebrew migration — finding with evidence

Today: cask `home-cellar` declares `app "cellar.app"` with no `target:`, `auto_updates true`
(`Casks/home-cellar.rb:16,20`). The Caskroom records the install through a symlink
`cellar.app -> /Applications/cellar.app`
(`openspec/changes/archive/2026-08-23-m6-cask-tap/archive-report.md:225`).

After `app "Home-Cellar.app"` ships:

| Path | Outcome |
|---|---|
| Fresh `brew install --cask home-cellar` | `/Applications/Home-Cellar.app`. Correct. |
| Existing cask install + `brew upgrade` | **Skipped.** `auto_updates true` excludes it without `--greedy`. Nothing moves. |
| Existing cask install + `brew upgrade --greedy` / `brew reinstall` | Uninstall phase reads the *installed* caskfile (`app "cellar.app"`) and should remove `/Applications/cellar.app`, then install `/Applications/Home-Cellar.app`. **This is the only clean migration path — and it is currently broken.** |
| Existing cask install + `brew uninstall --cask` | Removes `/Applications/cellar.app` via the installed caskfile. Same #22993 caveat. |
| Direct-download user drags the new zip | Gets `/Applications/Home-Cellar.app` **beside** their old `/Applications/cellar.app`. Two bundles, one bundle id. LaunchServices picks arbitrarily. No automatic fix exists. |

**The Homebrew defect**: [Homebrew/brew#22993](https://github.com/homebrew/brew/issues/22993) —
since Homebrew **6.0.8** (PR #22952, "Store cask metadata as JSON more often"), a third-party-tap
cask's installed JSON snapshot records `url_specs` but **no artifacts**; the upgrade path never
writes/refreshes `INSTALL_RECEIPT.json`. `load_from_installed_caskfile` then reconstructs zero
artifacts, `start_upgrade → uninstall_artifacts` removes nothing, and the new App artifact install
collides with `It seems there is already an App at '/Applications/<App>.app'`. Official
`homebrew/cask` casks are shielded by pre-existing receipts. Workaround: `brew reinstall --force`
writes the receipt permanently; `brew upgrade --force` works once. `juancasanueva/cellar` is
exactly the affected shape (third-party tap, no API metadata), and the m6-cask-tap evidence was
recorded on **Homebrew 6.0.18**.

With the rename this defect degrades from "collides and reverts" to "**silently leaves an orphaned
`/Applications/cellar.app`**", because the new name does not collide with the un-removed old one.

**Rejected migration mechanisms** (named so they are not re-derived):
- `app "Home-Cellar.app", target: "cellar.app"` — keeps everyone on the old path; defeats the slice.
- Adding `/Applications/cellar.app` to `zap trash:` — a zap would delete a live direct-download
  copy the cask never placed. Unacceptable.
- `uninstall delete: "/Applications/cellar.app"` — fires on every uninstall, including for users
  who never had the old name, and can delete a bundle Homebrew does not own. Unacceptable.
- Homebrew offers **no** supported "rename the artifact in place" migration hook.

## 5. Release-ordering race (must not be missed)

`homebrew-cellar/.github/workflows/bump.yml` runs `17 */6 * * *` and rewrites only `version` and
`sha256` (`:100-109`). Its gates are `brew style` + `brew audit --cask [--online --strict]`
(`:128-130`) — **none of which extracts the archive or verifies the `app` stanza resolves**.

So if the `v1.2.0` tag is pushed while the cask still says `app "cellar.app"`, bump.yml will
happily commit a cask that points at a zip containing `Home-Cellar.app`, all three audits will
pass, and the next user's `brew install --cask home-cellar` will fail on a missing app source.

**Required sequencing:** land the tap cask + tap CI change **before** the app tag is pushed, or
pause `bump.yml` across the window. This constraint belongs in `tasks.md` as an explicit ordering
dependency, not in a comment.

## 6. Approaches

### Approach 1 — Rename the Xcode **target** to `Home-Cellar`, keep `PRODUCT_NAME = "$(TARGET_NAME)"`
- Pros: one source of truth; the `$(TARGET_NAME)` idiom survives; `PRODUCT_NAME` line untouched.
- Cons: `TARGET_NAME` feeds the default `PRODUCT_MODULE_NAME`, so the Swift module becomes
  `Home_Cellar` and **22 files** in `cellarTests/` that do `@testable import cellar` break.
  Also drags `TEST_TARGET_NAME = cellar` (`:550,:569`), `remoteInfo = cellar` (`:26,:33`),
  the scheme's `BlueprintName`, and every documented `-scheme cellar` command in
  `openspec/config.yaml`. Largest blast radius for the smallest gain.
- Effort: **High**.

### Approach 2 — Keep target `cellar`, set `PRODUCT_NAME = "Home-Cellar"`, change nothing else
- Pros: two changed lines in the pbxproj.
- Cons: **silently broken.** `PRODUCT_MODULE_NAME` defaults to
  `$(PRODUCT_NAME:c99extidentifier)` = `Home_Cellar`, and it is **not pinned anywhere** in this
  project (grep for `PRODUCT_MODULE_NAME` across the repo returns zero hits). All 22
  `@testable import cellar` lines fail to compile. Either they all change, or the module is pinned
  — Approach 2 as stated does neither.
- Effort: **Medium** (Medium only because the 22 import edits are mechanical), but it is a trap
  rather than a real option.

### Approach 3 — Keep target `cellar`; `PRODUCT_NAME = "Home-Cellar"` + pin `PRODUCT_MODULE_NAME = cellar`
- Pros: the product, the executable, the zip, the display name and the cask all agree; the Swift
  module, the target, the scheme, `TEST_TARGET_NAME` and all 22 test imports are untouched; the
  pinned module name is entirely internal and never user-visible. Smallest change that achieves
  the stated goal.
- Cons: introduces a deliberate product-name / module-name divergence that a reader must be told
  about (a comment in the delta spec's design rationale, and a test that pins both lines together).
- Effort: **Low–Medium**.
- Variant 3b — additionally pin `EXECUTABLE_NAME = cellar`: saves 4 changed lines
  (`TEST_HOST` ×2, `release.sh` ×2) but preserves `Contents/MacOS/cellar`, which is visible in
  Activity Monitor and in `codesign -dvvv` output. **Rejected**: it re-creates exactly the naming
  inconsistency this slice exists to remove, for four lines.

### Recommendation: **Approach 3** (without the 3b `EXECUTABLE_NAME` pin)

`PRODUCT_NAME = "Home-Cellar"` + `PRODUCT_MODULE_NAME = cellar` in **both** the Debug and Release
app-target blocks; let `EXECUTABLE_NAME` follow to `Home-Cellar`; update `TEST_HOST`, the scheme's
three `BuildableName`s, the product `PBXFileReference`, `release.sh`'s scheme/product split, and
`release.yml:159`.

**Mandatory design-phase probe (could not be run from this executor — no shell):**
`xcodebuild -project cellar.xcodeproj -target cellar -showBuildSettings | rg 'PRODUCT_MODULE_NAME|PRODUCT_NAME|EXECUTABLE_NAME|FULL_PRODUCT_NAME'`
before and after the pbxproj edit. The claim that `PRODUCT_MODULE_NAME` defaults to
`$(PRODUCT_NAME:c99extidentifier)` is Apple's documented default, but it is load-bearing for 22
files and must be **measured**, not inherited from documentation.

## 7. Estimated changed-line count (authored, additions + deletions)

| Area | Lines |
|---|---|
| `project.pbxproj` (5 changed + 2 added + 3 comments) | ~12 |
| `cellar.xcscheme` | 3 |
| `scripts/release.sh` | ~8 |
| `.github/workflows/release.yml` | 1 |
| Tap repo (`home-cellar.rb`, `ci.yml`, `README.md`) | ~14 |
| App-repo docs (`README.md`, `RELEASING.md`, `PRD.md`) | ~40 |
| Existing test fixes (`CaskZapInventoryTests`) | ~8 |
| **New** RED tests (pbxproj pins, `release.sh` split, scheme, README) | ~80–110 |
| **Code + docs + tests subtotal** | **~170–200** |
| Spec delta (3 MODIFIED requirement blocks reproduced in full + 1 new scenario) | ~140–180 |
| **Total authored** | **~310–380** |

Comfortably inside the session's 5000-line review budget; above the 400-line default guard only
if SDD artifacts are counted, which they are not. `single-pr` is appropriate — but note the tap
repo is a **second repository**, so this is one PR here plus one PR there, ordered (§5).

## 8. Risks

1. **R1 — Permanent installed-base split.** Every existing copy stays `/Applications/cellar.app`
   (Sparkle, §3). Only new installs get `Home-Cellar.app`. There is no automated migration.
2. **R2 — Duplicate bundles for direct-download users.** Dragging the new zip creates a second
   bundle with the same identifier alongside the old one. LaunchServices resolution becomes
   non-deterministic. Highest user-visible harm.
3. **R3 — Homebrew/brew#22993.** On a third-party tap, `brew upgrade --greedy` / `reinstall` may
   remove nothing and orphan `/Applications/cellar.app`. Homebrew ≥6.0.8; unfixed as of the
   issue's last state.
4. **R4 — bump.yml ordering race** (§5): a tap that is bumped before its `app` stanza is flipped
   ships a cask that audits clean and installs broken.
5. **R5 — `PRODUCT_MODULE_NAME` default is assumed, not measured.** 22 test files depend on it.
   Must be probed before apply.
6. **R6 — `CaskZapInventoryTests.swift:335` is a case-sensitive substring assertion** that will go
   RED for the wrong-looking reason (`"Home-Cellar.app"` does not contain `"cellar.app"`). It must
   be updated deliberately, not "fixed" by relaxing the case.
7. **R7 — Provenance text in the main spec** (`spec.md:619,686-688,718-720`) sits outside every
   requirement block and cannot be carried by a MODIFIED delta. It must be hand-updated at archive,
   with the obligation stated in the delta's *Notes for archive*.
8. **R8 — The archive is not renamed.** `release.sh:46` `$SCHEME.xcarchive` stays `cellar.xcarchive`
   unless deliberately changed; decide explicitly rather than by omission.

## 9. Open product questions for the maintainer

1. **Do existing users get a migration instruction at all?** Options: (a) say nothing and let the
   old name persist; (b) README + release-notes note telling users to
   `brew reinstall --force home-cellar` or to delete `/Applications/cellar.app` and re-drag;
   (c) a one-time in-app notice. (c) is a separate slice.
2. **Is `brew install --cask --adopt home-cellar` still the documented answer?** After the rename
   it adopts nothing, because `/Applications/Home-Cellar.app` does not exist for old users. The
   README/RELEASING §8 "Already have `cellar.app`?" block needs a different answer, and
   `CaskZapInventoryTests.swift:344-354` pins the current one as a whole line.
3. **Ship the rename in the same release as other work, or as a standalone version?** A standalone
   `v1.2.0` whose release notes are only about the rename makes the split explainable.
4. **Rename `cellar.xcarchive` too?** Cosmetic, affects only local rehearsals and `RELEASING.md`.
5. **Should the Xcode target and the repository folder `cellar/` be renamed later?** Explicitly out
   of scope here; recording the answer prevents it being re-derived.
6. **Accept the product-name / module-name divergence** (`Home-Cellar` product, `cellar` module),
   or spend 22 mechanical import edits to align them?

## 10. Ready for proposal

**Yes.** Scope, inventory, mechanism and the three approaches are established from source. The one
unmeasured claim (R5, `PRODUCT_MODULE_NAME` default) is a single-command probe that `sdd-design`
must run. Questions 1, 2 and 3 in §9 are product decisions the maintainer should answer before
`sdd-spec`, because they change the requirement text for
*"Uninstalling states exactly what it removes, and what it cannot"*.
