# Proposal: Sparkle 2 In-App Updates (`m6-sparkle-updates`)

Anchors PRD.md **M6 "Ship"** (:212) — the **third M6 slice** (tip jar built then removed; release
pipeline merged and archived as `2026-08-23-m6-release-pipeline`). Delivers PRD :188 ("Sparkle 2:
EdDSA-signed appcast hosted on GitHub Pages… In-app 'Check for updates'"), completes the :9
Distribution line ("Sparkle updates pending `m6-sparkle-updates`"), and resolves the :168 external-service
row ("the appcast host decision moves to `m6-sparkle-updates`").

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m6-sparkle-updates/` + Engram canonical project
`swiftui_cellar`), `delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`.
RDD disabled clone-local.

Inputs: `openspec/changes/m6-sparkle-updates/explore.md` (Engram `sdd/m6-sparkle-updates/explore`,
obs 7680) **including its measured U24 addendum**; the maintainer's four accepted product decisions
(Engram `sdd/m6-sparkle-updates/decisions`, obs 7681); the archived
`m6-release-pipeline` proposal (obs 7662) for shape and for the *Contract for the follow-up slices*
this slice consumes.

## Intent

A tagged commit already becomes a downloadable, notarized app. **Nothing tells the user a newer one
exists.** Every copy installed by direct download is frozen at whatever version its owner happened to
fetch, and the only upgrade path is "notice on your own, return to the Releases page, download, unzip,
drag, replace".

That is acceptable for a prerelease with one user. It is not acceptable for `v1.0.0`, because 1.0 is
the first build strangers install — and a security-scanning Homebrew GUI that cannot ship its own
security fix to the people running it has the problem backwards. The cask channel (`m6-cask-tap`) will
serve `brew`-installed users; direct-download users have no channel at all until this slice exists.

The product outcome: **the app knows when it is out of date, and says so only when the user has asked
it to look.** A user opens Settings → Updates and turns on automatic checks, or picks
"Check for Updates…" from the app menu whenever they like. When a newer release exists, Sparkle offers
it, verifies the EdDSA signature against a public key baked into the running bundle, and replaces the
app in place. Publication is automatic: the same tag push that produces `Home-Cellar-<version>.zip`
also signs it and adds an item to the appcast served from GitHub Pages.

Update checking stays **off until asked**, because an update check is network egress and Cellar gates
every other egress behind explicit consent (`releaseNotesConsent`, `securityConsent`,
`cellarApp.swift:463-465`).

## Binding Constraints

1. **Slice 3 of 3.** `m6-cask-tap` follows, in a different repository. Nothing from it may be pulled
   in — but PRD :189's `auto_updates true` is already the recorded mitigation for cask/Sparkle
   coexistence and stays that slice's obligation.
2. **The Debug and Release app-target blocks stay byte-identical modulo `name`.**
   `ReleasePipelineCompositionTests.appTargetConfigurationsAreIdenticalModuloName` (`:213-229`)
   asserts it and its doc comment forbids deletion. Every build setting this slice adds costs **two**
   lines, not one.
3. **The release workflow may still invoke `gh` exactly once and `git` exactly zero times.**
   `theWorkflowCanOnlyEverCreateARelease` (`:733-748`) is binding and is **not** amended. Any appcast
   design reaching for `git push`, `gh release edit`, or a second `gh` call is already wrong.
4. **`cellar/` is a `PBXFileSystemSynchronizedRootGroup`.** No `.plist`, `.yml`, `.yaml` or `.sh` may
   be added under it — `appSourcesCarryNoReleaseInfrastructure` (`:409-417`) fails on any. The partial
   Info.plist therefore lives outside it (see *pbxproj change list*).
5. **No secret material in the repository.** `SPARKLE_PRIVATE_KEY` is a repository secret injected as
   an environment binding and piped on **stdin** (`--ed-key-file -`); it is never written to disk,
   never echoed, never traced. `SUPublicEDKey` is **public by construction** — it ships inside every
   copy of the app — and MUST NOT be handled as a secret.
6. **Exactly one file in the repository may `import Sparkle`**, proven by a composition sweep, not by
   convention.
7. **`INFOPLIST_KEY_SU*` does not work** (U24, measured 2026-08-23): Xcode's generator honours known
   keys only. The shape below is the *measured* fallback, not a guess.

## Scope

**In:** Sparkle **2.9.6** as an SPM **remote** dependency on the **app target only** — the project's
first remote dependency, so a new
`cellar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` appears in the diff;
`LSApplicationCategoryType = public.app-category.developer-tools` via `INFOPLIST_KEY_*` in **both**
app-target blocks (also silences the archive-time "No App Category" warning recorded at
`RELEASING.md:251-254`); `SUFeedURL = https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml` and
`SUPublicEDKey` in a **new partial plist at `Resources/Cellar-Info.plist`** referenced by
`INFOPLIST_FILE` in **both** blocks with `GENERATE_INFOPLIST_FILE` left at `YES`; a **dependency-free
`Updates` target and `.library`** in `Packages/CellarCore` (7 → 8 products) holding `AppVersion`,
`AppcastDocument`, `UpdateCheckPresentation` and the `AppUpdating` protocol;
`cellar/Updates/SparkleUpdateChecker.swift` as the **only** file importing Sparkle; a Settings
**"Updates"** group (one toggle, default **off**, plus a last-checked label); **"Check for Updates…"**
in `CommandGroup(after: .appInfo)` via a Cellar-owned command view over `AppUpdating`; appcast
publication inside the **existing named extension point** at `.github/workflows/release.yml:118-119`
(`actions/configure-pages` → `upload-pages-artifact` → `deploy-pages`, job permissions gaining
`pages: write` + `id-token: write`), driven by a new `scripts/appcast.sh` that obtains Sparkle's `bin/`
from the pinned **2.9.6** release tarball, runs `sign_update` on the published zip, and merges one
`<item>` into the feed fetched by `curl` from the live Pages URL, guarded by the same hyphen test the
publish step already uses (`release.yml:110`); a **seventh** repository secret `SPARKLE_PRIVATE_KEY`;
a Sparkle **MIT** entry in `THIRD-PARTY.md`; `RELEASING.md` §2 prerequisites and §7 contract
amendments plus an appcast section; PRD :9 / :124 / :168 / :188 / :212 amendments; README.

**Out (non-goals — recorded, not omitted):** a **channel picker** and `sparkle:channel` in any form
(PRD :124's "Sparkle update channel" is amended, not implemented — `SettingsView.swift:9-15` forbids
inert rows); **delta updates** (`--maximum-deltas`); any **custom styling** of Sparkle's update window;
**removing Sparkle's XPC services** (`Installer.xpc`, `Downloader.xpc`) — sandbox-only, and
`ENABLE_USER_SCRIPT_SANDBOXING = YES` would fight a stripping build phase; **thinning** the universal
`Sparkle.framework` to arm64; an **Acknowledgements/licences window** in About (`THIRD-PARTY.md`
remains the sole attribution surface, as it already is for CaskHub); a **DMG**; the **landing page**
(PRD :190); the **Homebrew tap and cask** (`m6-cask-tap`); enabling Pages, generating the key,
adding the secret, and cutting the **`v1.0.0` tag itself** — all maintainer actions (see
*Prerequisites*); any change to `scripts/release.sh`'s archive→export→notarize→staple→verify sequence
or to `scripts/ExportOptions.plist`.

## pbxproj change list — LITERAL and BINDING

The design gate FAILED last slice on a pbxproj edit outside its proposal's list. This list is the
whole permitted diff to `cellar.xcodeproj/project.pbxproj`:

| # | Change | Lines |
|---|---|---|
| 1 | One `XCRemoteSwiftPackageReference` for `https://github.com/sparkle-project/Sparkle`, requirement **`exactVersion = 2.9.6`** (new section) | ~7 |
| 2 | One entry appended to `packageReferences` (`:219-221`) | 1 |
| 3 | One `XCSwiftPackageProductDependency` for product `Sparkle` (`:612-637`) | ~5 |
| 4 | One `PBXBuildFile` — `Sparkle in Frameworks` (`:9-16`) | 1 |
| 5 | One entry in the app target's `PBXFrameworksBuildPhase` (`:59-72`) | 1 |
| 6 | `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.developer-tools";` in **both** app-target blocks | 2 |
| 7 | `INFOPLIST_FILE = Resources/Cellar-Info.plist;` in **both** app-target blocks | 2 |
| 8 | One `XCSwiftPackageProductDependency` for CellarCore product `Updates` (`:612-637`) — **D-1, approved 2026-08-23** | ~4 |
| 9 | One `PBXBuildFile` — `Updates in Frameworks` (`:9-16`) — **D-1** | 1 |
| 10 | One entry in the app target's `PBXFrameworksBuildPhase` for `Updates` (`:59-72`) — **D-1** | 1 |

**Amendment (D-1, 2026-08-23).** Items 8–10 were added after the design phase raised Deviation D-1:
the list mandated an eighth CellarCore product but omitted the three entries that link it. Six of the
seven existing products are linked explicitly (`:615-635`); `SecurityKit` reaches the app only
transitively through `Persistence` (`Package.swift:129`), and a dependency-free `Updates` target has
no such path. The maintainer approved option (a). Measured cost of items 1–7 is **22 lines** (design
probe addendum: the Sparkle dependency alone is 18, because the `XCRemoteSwiftPackageReference`
section is new); with items 8–10, **≈28 lines**. U25 is measured: **no Embed Frameworks phase is
needed**, so the paragraph below about U25 is now a closed branch.

**Nothing else.** Explicitly at 0-line diffs and binding: `GENERATE_INFOPLIST_FILE` stays **`YES`** in
both blocks; `ARCHS`, `LD_RUNPATH_SEARCH_PATHS` (already carries `@executable_path/../Frameworks`),
`ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME`, `ENABLE_USER_SCRIPT_SANDBOXING`, `CODE_SIGN_STYLE`,
`DEVELOPMENT_TEAM`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`, `SWIFT_VERSION`,
`SWIFT_DEFAULT_ACTOR_ISOLATION`, and every other existing setting are untouched; the local
`Packages/CellarCore` package reference is untouched; **no `PBXCopyFilesBuildPhase` (Embed Frameworks)
is added** — Xcode is expected to embed and re-sign the XCFramework from the SPM product dependency.

**If U25 proves an Embed Frameworks phase is necessary**, that is a **recorded deviation**: reported
before merge with its measured evidence, added to this list by an explicit amendment, never absorbed
silently at apply time.

`Resources/Cellar-Info.plist` is a new ~12-line partial plist carrying exactly `SUFeedURL` and
`SUPublicEDKey`. It is deliberately **not** placed in `scripts/` (that directory means "release
infrastructure that never ships", and this file's contents ship in every bundle) and **not** under
`cellar/` (constraint 4).

## Capabilities

### New Capabilities

- **`app-updates`** (ADDED-only, ~6–8 requirements): the observable contract of Cellar's update
  surface. Requirement material: the app reports its own version honestly; automatic checking is
  **off** until the user enables it and the app's own persisted setting — not an Info.plist default —
  is the authority; an explicit "Check for Updates…" action is always reachable and disables itself
  only when a check genuinely cannot run; no update row or label states something untrue (a
  never-checked app says so rather than showing a fabricated date); the feed the app trusts is fixed
  at build time (an `https` feed URL and a 32-byte EdDSA public key in the bundle, with no runtime
  override); an offered update is a signed, notarized release artifact whose appcast item carries
  `sparkle:edSignature`, `length`, `sparkle:version`, `sparkle:shortVersionString`, an `https`
  `github.com` enclosure matching the published asset URL scheme, and
  `sparkle:minimumSystemVersion == "26.0"`; **prereleases are never offered**; and a published
  version's item is never removed from the feed by a later release.

### Modified Capabilities

- **`release-distribution`**: two non-destructive edits, no requirement or scenario removed.
  (a) *"arm64 only, hardened, unsandboxed…"* (`:117-136`) — `"The delivered binary MUST contain the
  arm64 slice and no other"` is reworded to bind the **app executable**, with an explicit allowance
  that a vendored prebuilt framework may carry additional slices, and the scenario at `:130-136`
  follows. This is the honest wording for a universal `Sparkle.framework` (decision D2), not a
  weakening: the `lipo` gate at `release.sh:235-237` already reads only `Contents/MacOS/cellar`.
  (b) The closing note at `:373` ("the six repository secrets") becomes **seven**.
  **Honest count: ~6–10 changed lines.** If **U32** fires, a third edit scopes the stowaway scenario
  (`:278-283`) to exclude `Contents/Frameworks/`; if U32 does not fire, that edit **must not** happen.

## Approach

**Integration shape, selected by measurement.** U24 (orchestrator-measured, two scratch Debug builds)
established that `INFOPLIST_KEY_SUFeedURL` and `INFOPLIST_KEY_SUPublicEDKey` are **dropped** by Xcode's
Info.plist generator while `INFOPLIST_KEY_LSApplicationCategoryType` **lands**. The selected shape —
a partial `INFOPLIST_FILE` merged with `GENERATE_INFOPLIST_FILE = YES` — was then measured working:
26 keys in the generated plist including both `SU*` keys, with `en.lproj/InfoPlist.strings` still
carrying the catalog-sourced `CFBundleDisplayName` / `CFBundleName` / `NSHumanReadableCopyright` that
both copyright tests bind to. **Outcome 3 (a hand-authored full plist) is not needed and is not taken.**
`SUPublicEDKey` has no runtime escape hatch by design — Sparkle reads it from the host bundle because
a key supplied at runtime is a key an attacker can supply.

**Architecture: the seam is the point.** `config.yaml` `rules.design` requires logic in CellarCore and
a protocol boundary for every external dependency. A **dependency-free** `Updates` target makes "the
updater cannot reach brew, the catalog, or SwiftData" a **compile-time fact** rather than a review
comment — the `ReleaseNotes` precedent (`Package.swift:109-119`). `SparkleUpdateChecker` in the app
target adapts `SPUStandardUpdaterController` to `AppUpdating`; every view, the Settings group, and the
command view speak only to the protocol and are driven in tests by a fake.
`UpdateChannel` and `UpdateCheckOutcome` from the umbrella exploration are **dropped**:
`SPUStandardUpdaterController` owns the whole check UX through its standard user driver, so both would
be inert types — the rule `SettingsView.swift:9-15` already applies to rows.

**Concurrency.** `SPUUpdater` is `@MainActor`; the app sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
with `SWIFT_VERSION = 6.0`. The one friction point is KVO on `canCheckForUpdates`
(`NSKeyValueObservation` handlers are nonisolated and need an explicit hop). Rule, not code:
**the updater and its delegate never leave the main actor.**

**Publication: the only design the existing tests permit.** Committing the feed to `gh-pages` or
`docs/` needs `git push`; publishing it as a release asset needs a second `gh` call and contradicts
`release-distribution:30-31` ("exactly one downloadable asset"). Both are forbidden. The **Pages
artifact path** (`configure-pages` → `upload-pages-artifact` → `deploy-pages`) uses neither binary and
is the only option that leaves `theWorkflowCanOnlyEverCreateARelease` untouched. It runs **inside
`release.yml`** at the extension point authored for it, not in a second workflow: an attacker holding
the EdDSA key can ship arbitrary code to every installed copy, so a second credential-holding workflow
does not halve the blast radius, it doubles the surface guarding it.

**Feed construction: `sign_update` + merge, not `generate_appcast`.** `generate_appcast` builds
enclosure URLs as a **single** `--download-url-prefix` plus filename, but Cellar's assets live at
per-tag paths, so one prefix cannot produce correct URLs for more than one version. Instead:
`sign_update <zip>` emits the `sparkle:edSignature="…" length="…"` fragment, and one `<item>` is merged
into the feed fetched by `curl` from the live Pages URL — history preserved (decision D3), correct
per-tag URLs, no `git`, no second `gh`. Hand-assembled XML is the accepted cost, and it is bought back
by making `AppcastDocument` a **validator** in CellarCore that the CI output must satisfy: the unit
test that catches a broken release script before a user's updater does. Latest-only is the accepted
**degraded first run** — there is no feed to merge into yet.

**The seventh secret breaks a passing test by design.** `workflowReferencesExactlyTheExpectedSecrets`
(`:701-722`) is set-equality over six, and its own comment authorises the change: *"Adding one is
allowed; adding one without touching this list is not."* That edit is a first-class **RED→GREEN task**,
never an unexplained fix-up at apply time.

| Area | Impact |
|---|---|
| `cellar.xcodeproj/project.pbxproj` | **Modified** — exactly the 7 changes listed above; rollback below |
| `.../xcshareddata/swiftpm/Package.resolved` | **New** (generated, in-diff) — pins Sparkle 2.9.6 |
| `Resources/Cellar-Info.plist` | **New** — `SUFeedURL` + `SUPublicEDKey`, outside `cellar/` |
| `Packages/CellarCore/Package.swift` | **Modified** — `Updates` target + `.library`, **no dependencies** |
| `Packages/CellarCore/Sources/Updates/**`, `Tests/UpdatesTests/**` | **New** |
| `cellar/Updates/**` | **New** — `SparkleUpdateChecker` (only `import Sparkle`), KVO bridge, command view, settings group (0 pbxproj lines: synchronized group) |
| `cellar/Settings/SettingsView.swift`, `cellar/cellarApp.swift` | **Modified** — "Updates" group after "Interface"; DI wiring + `.commands` |
| `cellar/Shell/AboutView.swift` | **Untouched — binding** (it already renders the exact version pair Sparkle compares) |
| `cellarTests/` | **New** `UpdateCompositionTests`, `BundleUpdateKeysTests`; **amended** `ReleasePipelineCompositionTests` |
| `.github/workflows/release.yml` | **Modified** — appcast + Pages steps at `:118-119`, `pages`/`id-token` permissions |
| `scripts/appcast.sh` | **New**; `scripts/release.sh` and `ExportOptions.plist` **untouched — binding** |
| `RELEASING.md`, `THIRD-PARTY.md`, `README.md`, `PRD.md` :9/:124/:168/:188/:212 | **Modified** |
| `openspec/specs/app-updates/spec.md` (ADDED) · `release-distribution` (MODIFIED delta) | **New / Modified** |

## Strict-TDD obligations

`strict_tdd: true`. Unlike the pipeline slice, this one adds **real production Swift**, so the RED set
is substantial rather than declared-thin.

**CellarCore `UpdatesTests` (RED first, `swift test --package-path Packages/CellarCore`):**

| Type | Claim proven |
|---|---|
| `AppVersion` | parses `CFBundleShortVersionString` + `CFBundleVersion`; `1.0.1 > 1.0.0`; `1.0.0 (2) > 1.0.0 (1)`; **`0.0.1-rc.1` parses as a prerelease and sorts below `0.0.1`**; malformed input is a typed case, never a crash |
| `AppcastDocument` | validates the XML the CI step emits against fixtures: `sparkle:edSignature`, numeric `length`, `sparkle:version`, `sparkle:shortVersionString`, `https` `github.com` enclosure matching the asset URL scheme, `sparkle:minimumSystemVersion == "26.0"`; **rejects** a feed with a missing signature; a merge preserves prior items in descending version order; **no hyphenated version ever appears** |
| `UpdateCheckPresentation` | "Never checked" vs "Last checked …" from an optional `Date` |
| `AppUpdating` | driven by a fake — `canCheckForUpdates`, `automaticallyChecksForUpdates` (get/set), `lastUpdateCheckDate`, `checkForUpdates()` |

**`cellarTests` (RED first, `-only-testing:cellarTests`):**

1. `UpdateCompositionTests` — the `AppSecuritySources` idiom
   (`SecurityCompositionSupport.swift:42-69`): `import Sparkle` appears in **exactly one** file, and no
   view file references `SPUUpdater` / `SPUStandardUpdaterController`.
2. `BundleUpdateKeysTests` — reads **`Bundle.main.infoDictionary`** (not `localizedInfoDictionary` —
   the copyright precedent at `:297-313` is about catalog-sourced keys and does not apply here):
   `SUFeedURL` is the exact `https` Pages URL, and `SUPublicEDKey` base64-decodes to **32 bytes**. This
   is the only automated proof that the U24 arrangement **stays** true.
3. `ReleasePipelineCompositionTests` amendments — the secrets set becomes **seven**; the appcast step
   runs **after** the publish step; the hyphen guard is present in the appcast step. The existing
   `gh == 1` / `git == 0` assertions and the Debug/Release byte-identity assertion **must remain green
   unchanged — binding**.
4. **Credential-sweep extension (in scope, droppable at design):** a raw base64 Ed25519 private key
   carries **no PEM header**, so `repositoryCarriesNoCredentialMaterial` (`:433-461`) would not catch
   one committed by accident. Acceptance: the extended sweep rejects a PEM-less key-shaped blob bound
   to a `SPARKLE`-like name with **zero false positives on the repository as it stands**. If design
   cannot make it false-positive-free cheaply, it is dropped and the residual gap is **recorded**, not
   silently inherited.

**Not testable at all:** `SPUStandardUpdaterController` behaviour and Sparkle's update UI. Sparkle
ships no test harness — the same honesty the tip-jar slice stated about StoreKit, and precisely why
the seam lives in CellarCore.

**Manual evidence only** (recorded in `design.md` / the verify report with observed output, never as a
spec scenario verified by unit tests): an end-to-end **rc-installed → stable-published** upgrade with
the app in `/Applications` (rc → rc cannot work: prereleases produce no appcast item); **Gatekeeper
first launch** of the Sparkle-replaced bundle, offline; and the appcast **actually served** by Pages at
the feed URL.

## Probes (owned by design/apply)

| Probe | Question | Gate | Fallback |
|---|---|---|---|
| **U25** | Does Xcode auto-embed and re-sign `Sparkle.framework` from the SPM binaryTarget with **no** Embed Frameworks phase, and does `SPUStandardUpdaterController` compile clean under Swift 6 + MainActor default? | **Before any pbxproj edit is finalised** | Embed Frameworks phase as a **recorded deviation** amending the change list; concurrency warnings resolved by explicit main-actor hops, never by `@unchecked` |
| **U30** | Does `codesign --verify --strict --verbose=2` (`release.sh:214`) pass on an exported bundle containing Sparkle's framework, `Autoupdate`, `Updater.app` and both `.xpc`? | **Before the first tag**; run `scripts/release.sh all` locally, never discover this on a tag | If it fails, the export path is wrong — re-plan; do **not** relax the gate |
| **U31** | `lipo -archs Sparkle.framework/Versions/B/Sparkle` inside the exported app | During design | Expected universal → confirms the `release-distribution` rewording is required, not optional |
| **U32** | Does the stowaway sweep (`*.sh`/`*.yml`/`*.yaml`/`ExportOptions*.plist` under `Contents/`, `release.sh:251-258`) fire on Sparkle's framework? | During design | If yes: scope the `find` to exclude `Contents/Frameworks/` **and** add the third `release-distribution` edit. If no: neither happens |
| **U33** | Does `deploy-pages` succeed on this repository with the Pages source set to GitHub Actions? | **Before the first appcast-publishing tag** | Fallback host is Vercel (`PRD.md:190`'s landing-page domain), which adds an off-GitHub deploy credential — a re-plan, not a silent swap |

## Prerequisites (maintainer actions — deferred to release, NOT blocking merge)

Mirrors the six-secret precedent: the PR can merge without 1–4; the first appcast-publishing tag
cannot happen without them.

1. **Enable GitHub Pages** with source = **GitHub Actions** (measured 2026-08-23: `has_pages: false`).
2. Run `bin/generate_keys` from the Sparkle 2.9.6 tarball.
3. **Back the private key up offline** — password manager or offline media — **before the first tag
   that publishes an appcast**. This is the one-way door: losing it severs the update channel for every
   installed copy, with no recovery except telling users to re-download by hand.
4. Add the seventh repository secret **`SPARKLE_PRIVATE_KEY`**.

**5. `SUPublicEDKey` in `Resources/Cellar-Info.plist` is different — it is in-repo and must land in the
PR.** Recommendation: the maintainer runs step 2 **during apply**, before the plist task, and the
**real** public key is committed. A well-formed placeholder is worse than no feature: it satisfies
`BundleUpdateKeysTests`' 32-byte decode and is indistinguishable from a real key at review, yet a build
carrying the wrong public key can **never** be updated by Sparkle — every signature fails verification
and the only fix is a manual re-download by every user. See *Proposal question round*.

## Risks

| # | Risk | L | Mitigation |
|---|---|---|---|
| 1 | **EdDSA key loss is unrecoverable** — a one-way door; rotation requires shipping the new key through a non-Sparkle channel first | **High** | Prerequisite 3, before the first appcast tag; recommendation 5 puts key generation inside apply so the backup happens while attention is on it |
| 2 | Nested-signing verification (**U30**) newly recursive over Sparkle's helpers; a mis-sign aborts the release at gate 3 | **High** | Discover locally via `scripts/release.sh all` during design, never first on a tag |
| 3 | **Pages is a full-site replacement** — `deploy-pages` publishes the whole artifact, so a future landing page (PRD :190) built by a different job would silently overwrite the feed | Med | Recorded here and in `RELEASING.md`; the landing-page change inherits the obligation to build both in the same job |
| 4 | The **seventh secret breaks a passing test by design** | Med | Planned as an explicit RED→GREEN task with the test's own authorising comment quoted |
| 5 | **Universal framework inside an "arm64-only" bundle** contradicts `RELEASING.md:245` if left unsaid | Med | Accepted (D2) and reworded in the spec + runbook — honest over silent; no thinning, which would require a sandboxed build phase or a post-export re-sign that destroys `-exportArchive`'s ownership of signing |
| 6 | **Stowaway gate (U32)** aborts the release at the last gate | Med | Probed during design; scoped exclusion pre-authorised **only** if it fires |
| 7 | **rc-only degenerate state** — the feed has no items until the first stable tag, and the rehearsal must be rc-installed → stable-published | Med | Stated as the accepted first-run behaviour; the manual-evidence plan is written for it |
| 8 | **PEM-less Ed25519 key evades the credential sweep** | Med | Sweep extension in scope with a false-positive bar; if dropped, the gap is recorded |
| 9 | Sparkle's standard update window is **plain AppKit in the system appearance**, mismatching a dark-only `.hiddenTitleBar` app | Low | Accepted for v1; custom driver styling is a v1.1 item and is explicitly out of scope. `LSUIElement` is not set, so there is no accessory-app problem |
| 10 | **Cask/Sparkle divergence** — a Sparkle-replaced cask install diverges from what `brew` recorded | Low | PRD :189's `auto_updates true` is `m6-cask-tap`'s day-one obligation, not this slice's |
| 11 | **PRD drift** — :9/:124/:168 still say "pending" and :124 promises a channel picker this slice does not build | Med | Amended in the same PR, rewritten in place with reasons (both prior M6 slices set the precedent) |
| 12 | Scope creep toward channels, deltas, or a custom updater UI | Med | Each is an explicit non-goal; each is additive later |

## Rollback Plan

`rules.proposal` mandates this because `project.pbxproj` is touched.

- **A single `git revert` of the slice PR restores the code.** Reverting removes the remote package
  reference, `Package.resolved`, `INFOPLIST_FILE`, `Resources/Cellar-Info.plist`, the `Updates` target,
  every new source and test, and the workflow steps. Post-revert checks:
  `swift build --package-path Packages/CellarCore` and
  `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`,
  plus `xcodebuild test … -only-testing:cellarTests`.
- **`project.pbxproj` reverts to exactly the 7 changes listed above and nothing else**, and the Debug
  and Release blocks must remain byte-identical afterwards. If apply time forces the Embed Frameworks
  deviation, it is reported before merge and rolled back by the same revert — never absorbed quietly.
- **A revert leaves Sparkle's `UserDefaults` keys orphaned** in the app's domain
  (`SUEnableAutomaticChecks`, `SULastCheckTime`, `SUSkippedVersion`). They are inert without the
  framework and harmless; no migration is needed, and no cache, schema version, or Keychain item is
  touched.
- **A revert does not unpublish an appcast.** A feed already served by Pages stays served until the
  next `deploy-pages` run. A bad release is corrected by publishing a **higher** version, never by
  deleting an item from the feed — Sparkle clients that already downloaded a signed item cannot be
  recalled.
- **The private key, the repository secret, and the Pages setting survive a revert.** Undoing them is a
  maintainer action; the key must be *retained*, not deleted, because a future re-landing of this slice
  must reuse the same `SUPublicEDKey` or strand every copy shipped in between.

## Delivery Forecast

Budget **5,000** lines, `single-pr`, strict TDD, RDD disabled. Restated from explore §"Size forecast"
(bottom-up **1,305–2,080**, house correction **1.9–2.3×** per
`archive/2026-08-22-m6-tip-jar/tasks.md:14`):

**Forecast: 2,480–4,780 authored lines against the 5,000 budget.**

- Against the 400 default: **High**.
- Against the 5,000 budget: **Medium at the low end, High at the top** — the upper bound leaves ~220
  lines of headroom, which is not a margin.

**Delivery plan:** one PR, `tasks.md` structured as **two independently deliverable phases** —
**(3a) app-side** (Sparkle dependency, `LSApplicationCategoryType` first as the cheapest independently
revertible step, `Resources/Cellar-Info.plist`, the `Updates` target, Settings group, menu command) and
**(3b) publication** (Pages, seventh secret, `scripts/appcast.sh`, workflow steps, docs).
**Re-split trigger:** if the tasks-phase forecast lands above **~4,200 authored lines**, split 3b into
a separate `m6-appcast-publication` change rather than take a `size:exception` against `single-pr`.

`sdd-tasks` MUST reuse the 1.9–2.3× correction rather than re-deriving it, and MUST emit the exact
guard lines (`Decision needed before apply: Yes|No`, `Chained PRs recommended: Yes|No`,
`400-line budget risk: Low|Medium|High`).

## Success Criteria

- [ ] `project.pbxproj` shows **exactly** the 7 changes listed above and nothing else; the Debug and
      Release app-target blocks remain byte-identical modulo `name`.
- [ ] The built app's `Bundle.main.infoDictionary` carries `SUFeedURL` (the exact `https` Pages URL) and
      a `SUPublicEDKey` that decodes to 32 bytes, asserted by `BundleUpdateKeysTests`.
- [ ] Exactly one file in the repository contains `import Sparkle`, asserted by a composition sweep;
      no view references `SPU*`.
- [ ] The CellarCore `Updates` target declares **no dependencies** and its tests pass under
      `swift test --package-path Packages/CellarCore`.
- [ ] Settings shows an "Updates" group whose toggle is **off** on a fresh install, with a truthful
      last-checked label; "Check for Updates…" is present under the app menu and reachable at any time.
- [ ] `release.yml` still invokes `gh` exactly once and `git` exactly zero times; the referenced secret
      set is exactly seven; the appcast step runs after publish and is skipped for hyphenated tags.
- [ ] A stable tag publishes an appcast at `https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml`
      whose new `<item>` satisfies `AppcastDocument` validation, with every prior item preserved.
- [ ] A prerelease tag publishes a release and **no** appcast item.
- [ ] `codesign --verify --strict`, `spctl`, `stapler validate`, the `lipo` gate and the stowaway sweep
      all still pass on the exported bundle containing Sparkle (U30–U32 recorded).
- [ ] An rc-installed build upgrades itself to a stable published build end to end, and the replaced
      bundle passes Gatekeeper first launch offline — recorded as manual evidence.
- [ ] `THIRD-PARTY.md` carries a Sparkle MIT entry; `RELEASING.md` §2 and §7 are amended; PRD
      :9/:124/:168/:188/:212 and README are amended **in this PR**, rewritten in place with reasons.
- [ ] `cellarTests` and `cellarUITests` are green at their pre-slice baseline plus the new files.

## Resolved Decisions (binding)

Accepted by the maintainer (Engram obs 7681) before this proposal. Specs and design derive from these
and MUST NOT reopen them.

- **D1 — Automatic update checks default OFF**, consent-shaped, matching `releaseNotesConsent` /
  `securityConsent`; the app's persisted setting is the authority and is written to
  `automaticallyChecksForUpdates` at startup. "Check for Updates…" is always available because an
  explicit action is its own consent. **Rejected:** Sparkle's default second-launch system prompt
  (unstyled, and network egress without the consent gate every other egress has).
- **D2 — Accept the universal `Sparkle.framework`** inside the arm64-only bundle; the
  `release-distribution` delta rewords the arm64 claim to bind the app **executable**. **Rejected:**
  `lipo -thin` (needs a sandboxed build phase or a post-export re-sign) and silence.
- **D3 — The appcast keeps history**: `sign_update` on the new zip, merged into the feed fetched by
  `curl`. **Rejected:** latest-only (accepted **only** as the degraded first run) and
  `generate_appcast` over all past assets (single-prefix URL limitation).
- **D4 — Hyphenated/prerelease tags produce no appcast item in v1**; no channel picker, no
  `sparkle:channel`. **Rejected:** channels (Sparkle's own docs warn they require every user to already
  run a channel-aware version, and `SettingsView.swift:9-15` forbids an inert picker).
- **D5 (settled by explore + U24) — Sparkle 2.9.6 via SPM, app target only**, pinned `exactVersion`;
  `LSApplicationCategoryType` via `INFOPLIST_KEY_*`; `SU*` via a partial `INFOPLIST_FILE` outside
  `cellar/`; appcast on Pages via the Actions artifact path inside the `release.yml` extension point;
  `SPARKLE_PRIVATE_KEY` on stdin; dependency-free `Updates` target; exactly one file imports Sparkle.
- **D6 (this proposal) — the partial plist is `Resources/Cellar-Info.plist`.** **Rejected:**
  `scripts/` (that directory means "never ships"; this file's contents ship in every bundle) and the
  repository root (unowned clutter beside eight top-level docs).
- **D7 (this proposal) — `THIRD-PARTY.md` remains the sole attribution surface.** **Rejected:** an
  About "Acknowledgements" row — changing the attribution surface for Sparkle but not for CaskHub
  would be inconsistent, and a licences window is its own change.

## Proposal question round

Interactive mode. Four product decisions were already taken (D1–D4, obs 7681); these are the
questions that remain genuinely open, each with the assumption this proposal makes if no answer comes.
Answer, correct the framing, skip, or ask for a second round.

1. **`SUPublicEDKey` at merge time.** Do you want to run `generate_keys` **during apply** so the real
   public key is committed (recommended, prerequisite 5), or merge with a placeholder and amend later?
   *Assumption if unanswered:* real key during apply — a well-formed placeholder is indistinguishable
   from a real key at review and produces builds that can never update themselves.
2. **The partial plist path.** `Resources/Cellar-Info.plist` (D6) creates a new top-level directory.
   Acceptable, or do you prefer a different location outside `cellar/`?
   *Assumption if unanswered:* `Resources/Cellar-Info.plist`.
3. **Pages and the future landing page.** Should this slice's `deploy-pages` job be written now to
   accommodate a landing page later (risk 3), or is the feed alone correct for v1 and the landing page
   inherits the merge obligation? *Assumption if unanswered:* feed alone; the obligation is recorded in
   `RELEASING.md` and inherited by the landing-page change.
4. **The re-split trigger.** If `sdd-tasks` forecasts above ~4,200 authored lines, do you want the
   automatic split into `m6-appcast-publication`, or to be asked first?
   *Assumption if unanswered:* you are asked first, since `delivery_strategy=single-pr` is a cached
   session decision and re-slicing changes it.

## Open Questions (non-blocking, settle at design)

1. **Release-notes presentation.** `SUShowReleaseNotes` defaults `YES` and the appcast item can carry a
   `<description>` or a `sparkle:releaseNotesLink`. Recommend linking the GitHub release body rather
   than embedding HTML — Cellar already has a release-notes consent gate for a reason.
2. **Where the "Updates" toggle persists.** `@AppStorage` versus the existing Settings model. Both are
   present in the codebase; design picks one and states why.
3. **`cellarUITests/ReleaseNotesUITests` still has no owner** (carried since m5-health). Not this
   slice's defect; the verify gate must state its status rather than inherit it silently.
