<!--
Hybrid artifact mirror. Canonical Engram record: topic_key `sdd/m6-sparkle-updates/explore`,
observation #7680 (project `swiftui_cellar`, 2026-08-23). Written to OpenSpec by the orchestrator
because the sdd-explore executor ran without a write tool — the same arrangement as
`archive/2026-08-22-m6-tip-jar/explore.md`. Probe U24 is measured separately (see the U24 addendum
at the end of this file).
-->

# Exploration: `m6-sparkle-updates` — Sparkle 2 auto-updates (M6 slice 3)

Session preflight (forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m6-sparkle-updates/` + Engram canonical project
`swiftui_cellar`), `delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`.
RDD disabled clone-local — no review started.

Read at clean `main` (session start `215540b`; `git log` head `c3ee46c`).

**Harness limitation, stated up front.** This executor was launched without a shell tool and
without a write tool. Consequences, both explicit rather than inferred:

1. **Probe U24 could not be measured** (§Q2). It needs an `xcodebuild` run. The exact command is
   given so the next phase can run it. Nothing below assumes an answer.
2. **This OpenSpec copy must be written by the orchestrator.** Same arrangement as
   `openspec/changes/archive/2026-08-22-m6-tip-jar/explore.md:1-5` and `2026-08-23-m6-release-pipeline/explore.md`.

Everything else below is measured from files on disk or from network sources cited inline.

---

## 0. Context read (not re-derived)

- Engram **#7659** `sdd/m6-ship-pipeline/explore` — the umbrella. Sparkle 2.9.6 SPM binaryTarget,
  EdDSA keys, appcast-on-Pages, probe list U23–U29, slice split 8d-B. Built on, not repeated.
- Engram **#7673** resume pointer, **#7678** G3 dry-run result.
- `RELEASING.md` §4 (version policy), §6 (entitlements evidence), §7 (inherited contract + the
  named extension point at `.github/workflows/release.yml:118-119`), §8.
- `.github/workflows/release.yml`, `scripts/release.sh`, `cellar.xcodeproj/project.pbxproj`,
  `Packages/CellarCore/Package.swift`, `cellarTests/ReleasePipelineCompositionTests.swift`,
  `cellar/Settings/SettingsView.swift`, `cellar/Shell/AboutView.swift`, `cellar/cellarApp.swift`,
  `cellarTests/SecurityCompositionSupport.swift`, `THIRD-PARTY.md`, `PRD.md`,
  `openspec/config.yaml`, `openspec/specs/release-distribution/spec.md`.

**New measurement, 2026-08-23:** `GET https://api.github.com/repos/juancasanueva/SWIFTUI_cellar`
now returns `private: false`, `visibility: public`, `default_branch: main`, **`has_pages: false`**,
`homepage: null`. The public flip is done; **GitHub Pages is not yet enabled** — a maintainer
prerequisite for this slice, exactly as the six secrets were for the last one.

---

## Q1 — Integration shape: Sparkle 2.9.6 via SPM

**Sparkle 2.9.6 is still the latest release** (`tag_name: "2.9.6"`, published 2026-08-17; assets
`Sparkle-2.9.6.tar.xz`, `Sparkle-for-Swift-Package-Manager.zip`). Its `Package.swift` at that tag is
`swift-tools-version:5.3`, `platforms: [.macOS(.v10_13)]`, one library product `Sparkle` backed by a
**`binaryTarget`** at
`https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip`,
checksum `8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606` — identical to the value
recorded in #7659 §3, so that record is confirmed rather than restated.

**Existing package references, measured.** `project.pbxproj:219-221` — `packageReferences` holds
exactly one entry, `XCLocalSwiftPackageReference "Packages/CellarCore"` (`:605-610`). There is **no
remote package reference anywhere in the project**, and no `Package.resolved` exists
(`Grep XCRemoteSwiftPackageReference|Package.resolved` returns only archived prose). Sparkle would be
the project's first remote dependency.

**Exact pbxproj footprint** (`objectVersion = 77`):

| Section | Today | After |
|---|---|---|
| `PBXBuildFile` (`:9-16`) | 6 entries, all CellarCore products | +1 `Sparkle in Frameworks` |
| `PBXFrameworksBuildPhase` app target (`:59-72`) | 6 entries | +1 |
| `packageReferences` (`:219-221`) | 1 local | +1 `XCRemoteSwiftPackageReference` |
| `XCRemoteSwiftPackageReference` | absent | new section, ~7 lines |
| `XCSwiftPackageProductDependency` (`:612-637`) | 6 entries | +1 (~5 lines) |
| App-target build settings (`:416-483`) | 25 settings ×2 blocks | +3 keys **×2** = 6 lines |
| `PBXCopyFilesBuildPhase` (Embed Frameworks) | **absent** | expected still absent — probe U25 |

`LD_RUNPATH_SEARCH_PATHS` already contains `@executable_path/../Frameworks`
(`:433-436`, `:467-470`), which is what an embedded framework needs. Nothing else is required.

**Hard constraint discovered — the byte-identity test.**
`cellarTests/ReleasePipelineCompositionTests.swift:213-229`
(`appTargetConfigurationsAreIdenticalModuloName`) asserts the Debug and Release app-target blocks are
**identical modulo `name`**, and its doc comment forbids deletion. Verified by reading `:416-483`:
the two blocks carry the same 25 settings. **Every `INFOPLIST_KEY_*` this slice adds must be added to
both blocks.** That is why the plist keys cost 6 lines, not 3.

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **A** | **SPM remote dependency, app target only** | Xcode resolves, embeds and re-signs the XCFramework; version pinned in `Package.resolved`; upgrade is a one-line bump; matches Sparkle's own documented instructions | First remote dependency; new `Package.resolved` in-diff; network at resolve time | **Low** |
| B | Vendored `Sparkle.xcframework` in-tree | No resolve-time network | ~15 MB binary in git; manual Embed-and-Sign phase; manual upgrades; a `.framework` inside `cellar/` would join the synchronized group | Medium |
| C | No Sparkle; cask-only updates | Zero dependency | Abandons `PRD.md:188` and every direct-download user | Low |

**Recommend A**, on the **app target only, never CellarCore** — `Package.swift` declares seven
products with test-enforced edge discipline, and a binary dependency there would be visible to
`swift test` and to every target.

---

## Q2 — Probe U24: do `INFOPLIST_KEY_SU*` reach the generated Info.plist?

### NOT MEASURED by the executor. See the U24 addendum at the end of this file for the orchestrator's measurement.

Do not treat any statement below as a measurement. What is established:

- `GENERATE_INFOPLIST_FILE = YES` in both app-target blocks (`:430`, `:464`); there is no
  `Info.plist` file and no `INFOPLIST_FILE` setting anywhere in the project.
- **Measured last slice** (Engram #7673, and pinned by `ReleasePipelineCompositionTests.swift:266-295`):
  an **empty** `INFOPLIST_KEY_*` value is *dropped* from the generated plist, and catalog-sourced keys
  reach `localizedInfoDictionary` only, never `infoDictionary`.
- Web research was **inconclusive** on whether the generator accepts arbitrary non-Apple keys. Apple's
  own forum guidance points at the Info tab's "Custom Target Properties", which in some Xcode versions
  creates a real `Info.plist` file rather than an `INFOPLIST_KEY_*` setting. This must be measured, not
  argued.

**Command for the next phase** (scratch derived data, tracked files untouched):

```sh
SCRATCH=/private/tmp/claude-501/-Users-juancasanueva-programming-swiftUI-cellar/0770b791-046f-4c28-82c2-6964882e5d7f/scratchpad
xcodebuild build -project cellar.xcodeproj -scheme cellar \
  -destination 'platform=macOS,arch=arm64' -configuration Debug \
  -derivedDataPath "$SCRATCH/dd" \
  INFOPLIST_KEY_SUFeedURL=https://example.invalid/appcast.xml \
  INFOPLIST_KEY_SUPublicEDKey=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= \
  INFOPLIST_KEY_LSApplicationCategoryType=public.app-category.developer-tools
plutil -p "$SCRATCH/dd/Build/Products/Debug/cellar.app/Contents/Info.plist" \
  | rg 'SUFeedURL|SUPublicEDKey|LSApplicationCategoryType'
```

Three outcomes, each with a pre-costed branch:

1. **All three land** → the cheapest path. 6 pbxproj lines, no new file. Proceed as planned.
2. **`LSApplicationCategoryType` lands, `SU*` do not** → the generator honours only known keys.
   Fallback: **set `INFOPLIST_FILE` to a partial plist outside `cellar/` while keeping
   `GENERATE_INFOPLIST_FILE = YES`**, so Xcode merges the file with the generated keys. The plist
   **must not** live under `cellar/`: it is a `PBXFileSystemSynchronizedRootGroup` (`:41-46`) and
   `ReleasePipelinePlacementTests.appSourcesCarryNoReleaseInfrastructure` (`:409-417`) fails on any
   `.plist` under it. Put it at `Resources/Cellar-Info.plist` or repository root.
3. **Nothing lands** → full `GENERATE_INFOPLIST_FILE = NO` with a hand-authored plist. Largest blast
   radius: it changes how `InfoPlist.xcstrings` supplies `CFBundleDisplayName` / `CFBundleName` /
   `NSHumanReadableCopyright`, and both copyright tests (`:266-313`) plus the
   `release-distribution` "delivered build states who made it" requirement bind to that arrangement.
   **Avoid; treat as a genuine re-plan trigger, not an implementation detail.**

**`SUPublicEDKey` has no runtime escape hatch** — Sparkle reads it from the host bundle's Info.plist
by design, because a key supplied at runtime is a key an attacker can supply. `SUFeedURL` *does* have
one (`SPUUpdaterDelegate.feedURLString(for:)`), so at most one custom key is strictly unavoidable.

---

## Q3 — Hardened runtime, nested signing, and the eight verify gates

**Non-sandboxed means Sparkle's XPC services are not needed.** Sparkle's sandboxing guide opens: *"If
you do not sandbox your application, you should skip this guide unless you are interested in Removing
the XPC Services."* `SUEnableInstallerLauncherService` and `SUEnableDownloaderService` are
sandbox-only. `ENABLE_APP_SANDBOX = NO` (`:426`, `:460`) is therefore a **simplification**.

They are nevertheless **present in the framework**: recent Sparkle 2 ships
`Sparkle.framework/Versions/B/XPCServices/{Installer.xpc,Downloader.xpc}` plus the `Autoupdate`
command-line tool and `Updater.app`. Removing them needs a build-phase script — and
`ENABLE_USER_SCRIPT_SANDBOXING = YES` is set project-wide, so such a phase would be sandboxed and
likely fail on the framework path. **Recommend leaving them in.** Cost is bundle size only.

**Signing path.** `scripts/release.sh:138-142` uses `xcodebuild -exportArchive` with
`scripts/ExportOptions.plist` (`developer-id`, `signingStyle: automatic`, team `Z3S5JK8E38` — asserted
at `ReleasePipelineCompositionTests.swift:479-488`). That is the inside-out re-signing path; the
hand-rolled alternative that community write-ups document (sign `Installer.xpc`, then `Downloader.xpc`
with `--preserve-metadata=entitlements`, then `Autoupdate`, then the framework, then the app) is
exactly what `-exportArchive` exists to avoid. **No change to the signing path is proposed.**

**Gate-by-gate impact** (`scripts/release.sh:204-261`):

| Gate | Line | Effect of Sparkle |
|---|---|---|
| `spctl -a -vvv -t install` | :212 | Unchanged if nested code is signed. |
| `stapler validate` | :213 | Unchanged. |
| `codesign --verify --strict --verbose=2` | :214 | **Newly load-bearing.** It now recursively verifies `Sparkle.framework`, `Autoupdate`, `Updater.app` and both `.xpc`. This is the gate that fails if `-exportArchive` mis-signs nested code. **Probe U30.** |
| runtime flag / authority / team grep | :219-221 | Unchanged (app bundle only). |
| no-app-sandbox entitlement | :229-233 | Unchanged (app bundle only; the `.xpc` entitlements are not read). |
| `lipo -archs .../MacOS/cellar` | :235-237 | **Passes, but the claim narrows.** It reads only the main executable. Sparkle's XCFramework macOS slice is prebuilt **universal** (`macos-arm64_x86_64`), so the bundle would carry x86_64 code inside `Frameworks/`. **Probe U31.** |
| version / build / display-name triple | :238-246 | Unchanged. |
| stowaway sweep (`*.yml *.yaml *.sh ExportOptions*.plist` under `Contents/`) | :251-258 | **Could newly fail.** If any file inside `Sparkle.framework` matches — most plausibly a `.sh` — the release aborts. **Probe U32.** The fix, if needed, is to scope the `find` to exclude `Contents/Frameworks/`, which touches the `release-distribution` "None of it ships to the user" scenario. |

**Spec impact.** `openspec/specs/release-distribution/spec.md:119` says *"The delivered **binary** MUST
contain the `arm64` slice and no other"*, and its scenario (`:130-136`) enumerates *"the exported
application binary"*. A universal vendored framework does **not** violate that text as written, but it
does make `RELEASING.md:245` (*"Floor: Apple Silicon (`arm64` only)"*) ambiguous. Recommend a
**MODIFIED delta** that says the *app executable* is arm64-only and that a vendored prebuilt framework
may carry additional slices — honest over silent.

Thinning is possible in principle (`lipo -thin arm64` on the framework binaries) but only *before*
export signing, which means a build phase (blocked by script sandboxing) or a post-export re-sign
(which destroys the "`-exportArchive` owns all signing" property). **Recommend accept + document.**

---

## Q4 — Appcast hosting, and the constraint nobody has noticed yet

Feed URL, confirmed against the live repo name:
`https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml`. Pages is **not enabled today**.

### The blocking structural constraint

Two existing tests fence the release workflow, and the obvious appcast implementations break both:

- `theWorkflowCanOnlyEverCreateARelease` (`ReleasePipelineCompositionTests.swift:733-748`):
  `gh` invocations **== 1**, `git` invocations **== 0**, and the literals `git push`, `git tag`,
  `git commit`, `git add`, `gh release delete`, `gh release edit` must be absent.
- `workflowReferencesExactlyTheExpectedSecrets` (`:701-722`): **set equality** on exactly the six
  secrets. Adding `SPARKLE_PRIVATE_KEY` **fails this test**. Its own comment authorises the change:
  *"Adding one is allowed; adding one without touching this list is not."* Treat that edit as a
  first-class RED→GREEN task, not a fix-up.

So: committing `appcast.xml` to `gh-pages` or to `docs/` on main needs `git push` — **forbidden by an
existing test**, and it also breaks `RELEASING.md:117-119` ("a release changes no tracked file and
leaves no commit behind"). Uploading the appcast as a release asset needs a second `gh` invocation —
**forbidden**, and it contradicts `release-distribution` `:30-31` ("exactly one downloadable asset").

| # | Host | Mechanism | Verdict |
|---|---|---|---|
| **a** | **Pages via Actions artifact** | `actions/configure-pages` → `upload-pages-artifact` → `deploy-pages`. **No `git`, no `gh`.** | **Recommended.** The only option that satisfies both tests unchanged. Requires Pages source = "GitHub Actions" and `pages: write` + `id-token: write`. |
| b | `gh-pages` branch | `git push` | Blocked by test; mutates the repo per release. |
| c | `docs/` on `main` | `git push` | Same, worse. |
| d | Release asset `releases/latest/download/appcast.xml` | 2nd `gh` invocation | Blocked by test; and a prerelease is never `latest`, so the feed vanishes in an rc-only state. |
| e | `juancasanueva.vercel.app` | external deploy hook | Viable fallback, and the landing page (`PRD.md:190`) will live there anyway. Adds an off-GitHub deploy credential. |

### Where the job runs, and how many credential-holding workflows exist

| # | Placement | Pros | Cons |
|---|---|---|---|
| **A** | **Extension point inside `release.yml`** (`:118-119`, already named for this) | One credential-holding workflow; trigger surface stays `v*` tags only; one job, one log | The job token gains `pages: write` + `id-token: write` alongside the Developer ID cert |
| B | New `appcast.yml` on `release: [published]` | Signing cert and EdDSA key never coexist in one job; `release.yml` byte-frozen | A **second** workflow holding the most dangerous secret in the project; a second trigger surface to reason about; two logs |

**Recommend A.** The extension point was authored for exactly this, and B's apparent isolation is
illusory: an attacker who can reach the EdDSA key can ship arbitrary code to every installed copy,
so a second workflow does not reduce the blast radius, it doubles the surface guarding it.

### Building the feed — the real design problem

`generate_appcast` builds enclosure URLs as `--download-url-prefix` **+ filename**, a *single* prefix
for every archive in the folder. Cellar's assets live at per-tag paths
(`.../releases/download/v<version>/Home-Cellar-<version>.zip`, `RELEASING.md:240`), so **one prefix
cannot produce correct URLs for more than one version**. That rules out the "download every past asset
and regenerate" shape unless the URLs are rewritten afterwards.

Its confirmed options (from `generate_appcast/main.swift` at 2.9.6): `--ed-key-file` (*"If not
specified, the private EdDSA key will be read from the Keychain instead"* — pass `-` for stdin so the
key never touches disk and never prompts a headless runner), `--download-url-prefix`, `--channel`,
`--maximum-versions`, `--link`, `--versions`, `-o/--output-path`, `--maximum-deltas`,
`--auto-prune-update-files`, `--release-notes-url-prefix`, `--embed-release-notes`.

| # | Feed construction | Pros | Cons | Effort |
|---|---|---|---|---|
| **A** | **`sign_update` on the one new zip, then merge one `<item>` into the appcast fetched by `curl` from the live Pages URL** | Correct per-tag URLs; preserves history; `curl` trips no test; the produced XML is validated by a CellarCore unit test against a fixture | Hand-assembled XML — mitigated by making `AppcastDocument` the RED test that owns its shape | **Medium** |
| B | Latest-only single-item appcast | Simplest; functionally complete for updating | Loses per-version release notes for users who skip versions | Low |
| C | `generate_appcast` over a folder of all past assets | Sparkle owns the XML | Single-prefix limitation forces URL rewriting; re-downloads every asset each release | Medium-High |

**Recommend A**, with B as the accepted degraded state on the very first run (no existing feed to
merge into). `sign_update <zip>` prints the `sparkle:edSignature="…" length="…"` fragment directly.

The tool itself must be obtained in CI: `bin/generate_appcast` and `bin/sign_update` live inside the
resolved SPM artifact (`.../SourcePackages/artifacts/sparkle/Sparkle/bin/`), which is a fragile
DerivedData path. **Recommend downloading `Sparkle-2.9.6.tar.xz` from the Sparkle release in the
workflow step and using its `bin/`**, with the version pinned to the same 2.9.6 the app links.

### Prereleases

`v0.0.1-rc.1` already exists and is published (`CFBundleVersion = 1`; the next run is 2, so it can
never out-rank a later stable). Sparkle 2 supports `<sparkle:channel>`, but its docs warn channels
*"can only be used when all of your users downloading your appcast are running a version of Sparkle
that supports them"*, and this slice ships **no channel picker** (`PRD.md:124` notwithstanding —
`SettingsView.swift:9-15` forbids inert rows).

**Recommend: hyphenated tags produce no appcast item at all in v1.** The publish step already
distinguishes them (`release.yml:110`, `case "$GITHUB_REF_NAME" in *-*)`), so the appcast step reuses
the same one-line test. Prereleases stay downloadable from the Releases page and invisible to the
updater. Channels become a later, additive change.

---

## Q5 — EdDSA key lifecycle

`bin/generate_keys` creates the Ed25519 keypair, stores the private key in the login Keychain and
prints the base64 public key for `SUPublicEDKey`.

Per the `swift-security` invariants, and matching the posture `release-distribution:285-294` already
mandates for the Developer ID material:

- The private key is a **7th repository secret, `SPARKLE_PRIVATE_KEY`**, injected as
  `NAME: ${{ secrets.NAME }}` only (the shape `secretsAppearOnlyAsEnvironmentBindings` at
  `:668-692` enforces), piped on **stdin** (`--ed-key-file -`), never written to disk, never traced.
- **Never in the repository** in any form. `repositoryCarriesNoCredentialMaterial` (`:433-461`) scans
  every file for `-----BEGIN <TYPE>-----`; note that a raw base64 Ed25519 private key carries **no PEM
  header**, so that scan would **not** catch it. Worth naming as a residual gap rather than assuming
  coverage.
- **`SUPublicEDKey` is public by construction** — it ships inside every copy of the app. It is not a
  secret and must not be handled as one.
- **Backup is the whole risk.** Losing the private key permanently severs the update channel for every
  installed copy; there is no recovery except telling users to re-download by hand. It must be backed
  up **outside** the login Keychain — offline or in a password manager — **before the first tag that
  publishes an appcast**. Rotation requires shipping a build carrying the new `SUPublicEDKey` through
  a non-Sparkle channel first, so it is effectively a one-way door.
- Keychain access on the maintainer Mac should use the data-protection keychain semantics the skill
  prescribes; in practice `generate_keys` owns that and the maintainer step is "generate once, back up
  immediately, paste into the GitHub secret, verify with `sign_update`".

Recommended maintainer prerequisite list for `RELEASING.md` §2, mirroring the existing six:
enable Pages (source = GitHub Actions), run `generate_keys`, back the key up offline, add
`SPARKLE_PRIVATE_KEY`, record `SUPublicEDKey` in the project file.

---

## Q6 — App surface

**Settings.** `cellar/Settings/SettingsView.swift` is a `ScrollView` of private `group(_:rows:)` cards
— today exactly `"Homebrew"` (`:28-60`) and `"Interface"` (`:62-73`) plus `freeCard` (`:160-175`). Its
doc comment (`:9-15`) is binding: *"Only rows with something real behind them are rendered… Rows the
design sketches for capabilities Cellar does not have… are deliberately absent rather than
present-but-inert."* An `"Updates"` group slots in after `"Interface"` with **zero `AppSection`
churn** — Settings is an `AppSection` inside the custom shell, not a SwiftUI `Settings` scene, so
there is no scene work. Accessibility identifiers follow the house form (`accent-\(name)` at `:156`);
new controls need their own.

**Sparkle's defaults, measured from its customization docs:** `SUEnableAutomaticChecks` unset →
**Sparkle prompts the user on 2nd launch**; `SUAutomaticallyUpdate` defaults `NO`;
`SUScheduledCheckInterval` defaults `86400`; `SUShowReleaseNotes` `YES`; `SUEnableJavaScript` `NO`.
Info.plist keys are *defaults*; the runtime properties (`automaticallyChecksForUpdates`) are the
user's answer and are persisted by Sparkle in `UserDefaults`.

**Architectural recommendation with a house precedent.** An unstyled system prompt on 2nd launch is
wrong for a dark-only, custom-shell app — and more importantly, an update check is **network egress**,
which Cellar already gates behind explicit consent everywhere else (`releaseNotesConsent`,
`securityConsent`, both wired at `cellarApp.swift:463-465`). So:

- **Default off.** Cellar's own persisted setting is the authority; the app writes
  `updater.automaticallyChecksForUpdates` from it at startup. This also **sidesteps the
  `INFOPLIST_KEY_*` boolean-encoding question entirely** — no `SUEnableAutomaticChecks` key is needed.
- **One toggle** in the new `"Updates"` group, plus a "Last checked …" sub-label from
  `lastUpdateCheckDate`.
- **"Check for Updates…" is always available** — an explicit user action is its own consent.

**Menu item.** `cellar/Shell/AboutView.swift:151-159` defines `AboutCommands` as
`CommandGroup(replacing: .appInfo)`; `cellarApp.swift:506` is `.commands { AboutCommands() }`.
Sparkle's own SwiftUI example uses `CommandGroup(after: .appInfo) { CheckForUpdatesView(updater:) }`,
where the view holds an `SPUUpdater` and disables itself on `canCheckForUpdates`.

**Cellar cannot use that view as written** — it would make a second file import Sparkle. The app must
define its own command view over the CellarCore protocol (§Q7). Cost ≈ 60 lines, and it is the reason
`SparkleUpdateChecker` must expose `canCheckForUpdates` observably.

**About window.** `AboutView.version` (`:142-147`) already renders `CFBundleShortVersionString
(CFBundleVersion)` — precisely the two keys Sparkle compares — so the About window is already the
honest display of what the updater reasons about. No change strictly required; a "Check for Updates"
button there is optional and probably redundant with the menu item.

---

## Q7 — Architecture, and what strict TDD can honestly cover

`openspec/config.yaml` `rules.design`: *"Keep all logic in Packages/CellarCore; the app target holds
views, scenes, and DI wiring only"* and *"Define protocol boundaries for every external dependency"*.
Per `swift-architecture`, this is an existing Clean-ish boundary enforced by the **build graph**, not
by discipline — the `ReleaseNotes` precedent (`Package.swift:109-119`: depends on `Catalog` alone,
*"nothing depends back on it"*).

**Recommended shape.**

- New **dependency-free** `Updates` target + `.library` in `Packages/CellarCore` (7 → 8 products).
  Declaring **no dependencies** makes "the updater cannot reach brew, the catalog, or SwiftData" a
  compile-time fact.
- `cellar/Updates/SparkleUpdateChecker.swift` — the **only** file in the repository that
  `import Sparkle`. `cellar/` is a synchronized root group (`:41-46`), so new files there cost
  **0 pbxproj lines**.

What belongs in CellarCore, and what each RED test proves:

| Type | Unit-testable claim |
|---|---|
| `AppVersion` | parses `CFBundleShortVersionString` + `CFBundleVersion`; orders `1.0.1 > 1.0.0`, `1.0.0 (2) > 1.0.0 (1)`; **`0.0.1-rc.1` parses as a prerelease** and sorts below `0.0.1`; malformed input is a typed case, never a crash |
| `AppcastDocument` | a **validator, not a client**: parses the XML the CI step emits and asserts `sparkle:edSignature`, `length`, `sparkle:version`, `sparkle:shortVersionString`, `enclosure url` scheme `https`, host `github.com`, and `sparkle:minimumSystemVersion == "26.0"`. **No Sparkle dependency.** This is the test that catches a broken release script before users see it, and it is the reason approach Q4-A is acceptable. |
| `UpdateCheckPresentation` | "Never checked" / "Last checked …" phrasing from an optional `Date` |
| `AppUpdating` protocol | `canCheckForUpdates`, `automaticallyChecksForUpdates` (get/set), `lastUpdateCheckDate`, `checkForUpdates()` — driven in tests by a fake, never by Sparkle |

`UpdateChannel` from #7659 §6 is **dropped for v1** (no picker, no channel in the appcast).
`UpdateCheckOutcome` is **also dropped**: `SPUStandardUpdaterController` owns the entire check UX
through its standard user driver, so there is no outcome for Cellar to observe or present. Modelling
one would be an inert type — the same rule `SettingsView.swift:9-15` applies to rows.

In `cellarTests`:

- `UpdateCompositionTests` — the `AppSecuritySources` idiom (`SecurityCompositionSupport.swift:42-69`,
  comment-stripped source of every `.swift` under `cellar/`): `import Sparkle` appears in **exactly
  one** file; no view file references `SPUUpdater` / `SPUStandardUpdaterController`.
- `BundleUpdateKeysTests` — reads `Bundle.main.infoDictionary` and asserts `SUFeedURL` is an `https`
  URL and `SUPublicEDKey` decodes to **32 bytes**. This is the RED test that pins the pbxproj change
  and the only automated proof that whatever U24 resolves to **stays** true. Note the copyright
  precedent (`:297-313`): if the fallback plist route is taken, check the right dictionary.
- Amendments to `ReleasePipelineCompositionTests`: the secrets set → seven; new assertions that the
  appcast step runs **after** publish and that the hyphen guard is present.

**Not testable at all:** `SPUStandardUpdaterController` behaviour. Sparkle ships no test harness. Same
honesty the tip-jar slice stated about StoreKit, and the reason the seam lives in CellarCore.

**Manual evidence only:** an end-to-end upgrade from build N-1 to N with the app in `/Applications`;
Gatekeeper first launch of the Sparkle-replaced bundle; the appcast actually served by Pages.

**Concurrency.** `SPUUpdater` is `@MainActor`; the app already sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`:443`, `:477`) with `SWIFT_VERSION = 6.0`. The one
friction point is KVO on `canCheckForUpdates`: `NSKeyValueObservation` handlers are nonisolated and
need an explicit hop. Rule, not code: **the updater and its delegate never leave the main actor.**

**Spec plan.** 21 capabilities today. Add **one** — `app-updates`, ADDED-only — covering version
display, the check-for-updates command, the Settings group, the consent-shaped default-off rule, and
"no update surface lies about state". Plus a small **MODIFIED** delta on `release-distribution` for
the arm64 wording (§Q3) and, if U32 fires, the stowaway scenario. The CI appcast step has no runtime
observable behaviour and belongs in `design.md` + `tasks.md`.

---

## Q8 — `LSApplicationCategoryType`

**Already measured, last slice.** `RELEASING.md:251-254`: *"`xcodebuild archive` warns 'No App
Category is set for target cellar'. Setting `LSApplicationCategoryType` belongs to
`m6-sparkle-updates`, which touches the project file anyway."* I did not re-measure it — no shell —
and re-measuring a warning already recorded in a tracked file would add nothing.

**Cost: 2 lines, not 1** — `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.developer-tools";`
in **both** app-target blocks, per the byte-identity test (§Q1).

**This is the low-risk half of U24.** `LSApplicationCategoryType` is a first-class Xcode build setting
("Application Category" in the Build Settings UI), so it is expected to work even if arbitrary custom
keys do not. It should be sequenced **first** in tasks: it is independently valuable, independently
revertible, and its outcome is a free partial read on the U24 mechanism.

---

## Q9 — Attribution

`THIRD-PARTY.md` exists (37 lines) and carries exactly one entry — the CaskHub data files, MIT, with
the full licence text reproduced. **Sparkle is MIT.** The house precedent is unambiguous: add a
`## Sparkle` section naming the project, the version, the copyright holders (Sparkle Project
contributors / Andy Matuschak), and the reproduced MIT text.

**The About window shows no licences** (`AboutView.swift:70-88`: Credits card = three names; Links
card = web page and email). Two options: leave `THIRD-PARTY.md` as the sole attribution surface
(consistent with today, and CaskHub is already handled that way), or add an "Acknowledgements" link
row. **Recommend the former** — changing the attribution surface for Sparkle but not for CaskHub would
be inconsistent, and a licences window is its own change.

---

## Q10 — Risks

1. **U24 unmeasured.** §Q2. Outcome 3 is a re-plan trigger. Measure before the proposal is written.
2. **Nested-signing verification (U30).** `codesign --verify --strict` (`release.sh:214`) becomes
   recursive over Sparkle's helpers. Discover this locally via `scripts/release.sh all`, never for the
   first time on a tag.
3. **Universal framework vs the arm64 claim (U31).** §Q3. Needs a spec wording delta or a measured
   contradiction of the RELEASING.md §7 contract.
4. **Stowaway gate (U32).** A `.sh` inside `Sparkle.framework` aborts the release at the last gate.
5. **The seventh secret breaks a passing test by design.** `:701-722` is set-equality. Plan it as
   RED→GREEN; do not let it surface as an unexplained test edit at apply time.
6. **`git`/`gh` prohibition shapes the whole appcast design.** §Q4. Any implementation reaching for
   `git push` or a second `gh` call is already wrong.
7. **EdDSA key loss is unrecoverable.** §Q5. Back up before the first appcast-publishing tag.
8. **No PEM header on an Ed25519 private key**, so the existing credential sweep would not catch one
   committed by accident. Consider extending the scan in this slice.
9. **Pages is not enabled** (`has_pages: false`, measured). Maintainer prerequisite; also decide the
   Pages source is "GitHub Actions" — the artifact deployment path requires it.
10. **The appcast is a full-site replacement.** `deploy-pages` publishes the whole artifact. When the
    landing page (`PRD.md:190`) arrives it must be built by the same job, or it will silently
    overwrite the feed. Record this now.
11. **Sparkle + cask coexistence.** `PRD.md:189` already specifies `auto_updates true`, which is the
    correct mitigation and must be in the cask from day one of `m6-cask-tap`. A cask-installed app is
    user-owned, so Sparkle can replace it without an admin prompt — but the on-disk version then
    diverges from what `brew` recorded. A drag-installed app in `/Applications` may prompt for admin
    authorization on first update.
12. **Gatekeeper after the swap.** Sparkle validates that the update's code-signing identity matches
    the running app's, and the downloaded zip is stapled, so first launch of the replaced bundle needs
    no network. Contingent on the pipeline continuing to staple — which `release.sh:188-199` and
    `stapleDeletesTheArchiveBeforeRepackaging` (`:536-547`) already guarantee.
13. **Cosmetic.** The app is dark-only (`.preferredColorScheme(.dark)`, `cellarApp.swift:462`) with
    `.windowStyle(.hiddenTitleBar)`. Sparkle's standard update window is a plain AppKit window in the
    system appearance and will not match. Accept for v1, or note it as a v1.1 item. **`LSUIElement` is
    not set** (verified absent from the project file), so there is no accessory-app problem.
14. **Testing the real flow needs two real releases.** The `v0.0.1-rc.1` prerelease is the natural test
    vehicle — install it, publish `v0.0.1-rc.2` or `v1.0.0`, and watch the update land. But under the
    recommended rule (§Q4) prereleases produce no appcast item, so the rehearsal must be
    rc-installed → stable-published, not rc → rc.
15. **PRD drift.** `PRD.md:9`, `:124`, `:168`, `:212` all still say "pending". They must be amended in
    the same PR, matching the precedent both prior M6 slices set.

---

## Probes for the proposal/design round

| Probe | Question | Gate |
|---|---|---|
| **U24** | Do `INFOPLIST_KEY_SUFeedURL` / `SUPublicEDKey` / `LSApplicationCategoryType` reach the generated Info.plist? | **Before proposal** — it selects the integration shape |
| **U25** | Does Xcode auto-embed and re-sign `Sparkle.framework` from the SPM binaryTarget with **no** Embed Frameworks phase, and does `SPUStandardUpdaterController` compile clean under Swift 6 + MainActor default with zero concurrency warnings? | During design |
| **U30** | Does `codesign --verify --strict` pass on an exported bundle containing Sparkle? (`scripts/release.sh all` locally) | During design |
| **U31** | `lipo -archs` on `Sparkle.framework/Versions/B/Sparkle` inside the exported app | During design |
| **U32** | `find` the exported bundle for `*.sh` / `*.yml` — does the stowaway gate fire? | During design |
| **U33** | Does `deploy-pages` work on this repository with the Pages source set to GitHub Actions? | Before the first appcast tag |

---

## Size forecast against the 5,000-line budget

| Bucket | Lines |
|---|---|
| `project.pbxproj` (remote ref, product dep, build file, frameworks entry, 3 keys ×2 blocks) | 25–35 |
| `Package.resolved` (new, generated, in-diff) | 10–20 |
| `Packages/CellarCore/Package.swift` | 10–15 |
| CellarCore `Updates` sources (`AppVersion`, `AppcastDocument`, `UpdateCheckPresentation`, seams) | 220–320 |
| CellarCore `UpdatesTests` + appcast fixtures | 300–450 |
| `cellar/Updates/` (`SparkleUpdateChecker`, KVO bridge, `UpdatesSettingsGroup`, command view) | 200–300 |
| `SettingsView`, `cellarApp`, `AboutView`/commands, `AppTestFixtures` | 60–110 |
| `cellarTests` (composition, bundle keys, secrets-set amendment, workflow ordering) | 180–280 |
| `.github/workflows/release.yml` appcast steps | 70–140 |
| `scripts/appcast.sh` | 80–160 |
| Docs (`RELEASING.md` §2/§7/new §, `THIRD-PARTY.md`, `PRD.md` ×4, `README.md`) | 150–250 |
| **Bottom-up** | **1,305–2,080** |

House correction **1.9–2.3×** (`archive/2026-08-22-m6-tip-jar/tasks.md:14`):

**Forecast: 2,480–4,780 authored lines against the 5,000 budget.**

- Against the 400 default: **High**.
- Against the 5,000 session budget: **Medium at the low end, High at the top** — the upper bound
  leaves ~220 lines of headroom, which is not a margin.

**Recommendation:** keep one slice, but plan `tasks.md` in two independently deliverable phases —
**(3a)** app-side (Sparkle dependency, `LSApplicationCategoryType`, `Updates` target, surfaces, plist
keys) and **(3b)** publication (Pages, seventh secret, appcast step, docs). If the tasks-phase
forecast lands above **~4,200**, split 3b into `m6-appcast-publication` rather than take a
`size:exception` against `single-pr`.

---

## Recommended approach — summary

1. Sparkle **2.9.6 via SPM**, app target only, pinned by `Package.resolved`.
2. `LSApplicationCategoryType` and the two `SU*` keys as `INFOPLIST_KEY_*` in **both** app-target
   blocks — **contingent on U24**; partial-`INFOPLIST_FILE` outside `cellar/` is the pre-costed
   fallback.
3. Dependency-free **`Updates`** target in CellarCore; `AppUpdating` protocol; **exactly one** app file
   imports Sparkle, proven by an `AppSecuritySources`-style composition sweep.
4. Settings **"Updates"** group, **default off** (consent-shaped, matching the release-notes and
   security-scan precedent), plus an always-available "Check for Updates…" in
   `CommandGroup(after: .appInfo)`. **No channel picker.**
5. Appcast on **GitHub Pages via the Actions artifact path**, inside the existing extension point in
   `release.yml`, with **`SPARKLE_PRIVATE_KEY`** as the seventh secret piped on stdin.
6. `sign_update` + merge-into-fetched-feed; **hyphenated tags produce no appcast item** in v1.
7. `THIRD-PARTY.md` gains a Sparkle MIT entry; About stays as it is.
8. One new spec capability **`app-updates`** (ADDED-only) plus a small **MODIFIED** delta on
   `release-distribution` for the arm64 wording.

## Open questions for the proposal round

1. **U24's answer** — blocking; it selects the integration shape.
2. **Automatic checks: default off (consent-shaped) or default on?** Recommended off; this is a
   product decision, not a technical one.
3. **Pages source and enablement** — maintainer action; also whether the future landing page shares
   the deployment.
4. **Accept a universal Sparkle framework inside an "arm64-only" bundle**, or attempt thinning?
   Recommended: accept and reword the spec.
5. **Appcast history:** merge-into-fetched-feed (recommended) or latest-only?
6. **Does the `v0.0.1-rc.1` prerelease appear in the feed?** Recommended no.
7. **Sub-split 3a/3b if the tasks forecast exceeds ~4,200 lines?**

## Ready for Proposal

**Yes, once U24 is measured.** Everything else is either settled by existing convention or is a named
product decision with a recommendation attached. The two genuine discoveries this exploration
contributes beyond the umbrella are: the **Debug/Release byte-identity test** doubling every build
setting's cost, and the **`git`/`gh` prohibition plus six-secret set-equality** test pair, which
together eliminate three of the four obvious appcast-hosting designs before any code is written.

---

## U24 addendum — measured by the orchestrator, 2026-08-23

Two scratch Debug builds (`-derivedDataPath` under the session scratchpad, `CODE_SIGNING_ALLOWED=NO`,
no tracked file touched), each followed by `plutil -p` on the built `cellar.app/Contents/Info.plist`.

**Build 1 — `INFOPLIST_KEY_*` overrides only** (`INFOPLIST_KEY_SUFeedURL`, `INFOPLIST_KEY_SUPublicEDKey`,
`INFOPLIST_KEY_LSApplicationCategoryType`), exit 0:

```
"LSApplicationCategoryType" => "public.app-category.developer-tools"
```

`SUFeedURL` and `SUPublicEDKey` are **absent**. The generator honours known keys only — **outcome 2**
of §Q2. The "No App Category" warning did not appear in the build log.

**Build 2 — fallback: partial `INFOPLIST_FILE` with `GENERATE_INFOPLIST_FILE = YES` left as is.**
A two-key plist (`SUFeedURL`, `SUPublicEDKey`) outside `cellar/` passed as `INFOPLIST_FILE=<path>`,
plus the same `INFOPLIST_KEY_LSApplicationCategoryType`. Exit 0. Generated plist: 26 keys, including

```
"CFBundleDisplayName"       => "Home-Cellar"
"CFBundleIdentifier"        => "com.juancasanueva.cellar"
"CFBundleShortVersionString"=> "1.0.0"
"CFBundleVersion"           => "1"
"LSApplicationCategoryType" => "public.app-category.developer-tools"
"LSMinimumSystemVersion"    => "26.0"
"SUFeedURL"                 => "https://example.invalid/appcast.xml"
"SUPublicEDKey"             => "U24PROBEKEY"
```

and `en.lproj/InfoPlist.strings` still carries the catalog-sourced `CFBundleDisplayName`,
`CFBundleName` and `NSHumanReadableCopyright` — the `InfoPlist.xcstrings` arrangement both copyright
tests bind to is **unaffected**.

**Selected integration shape:** `LSApplicationCategoryType` as `INFOPLIST_KEY_*` (2 pbxproj lines);
`SUFeedURL` + `SUPublicEDKey` in a small partial plist **outside `cellar/`** referenced by
`INFOPLIST_FILE` (2 pbxproj lines + one new ~12-line file). Outcome 3 (hand-authored full plist) is
**not** needed. `BundleUpdateKeysTests` reads `Bundle.main.infoDictionary` (not
`localizedInfoDictionary`) for the two `SU*` keys.
