# Tasks: Sparkle 2 In-App Updates (`m6-sparkle-updates`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m6-sparkle-updates/` + Engram canonical project
`swiftui_cellar`), `delivery_strategy=single-pr`, `chain_strategy=n/a (single-pr)`,
`review_budget_lines=5000`, `strict_tdd=true`. RDD disabled clone-local.

Inputs: `specs/app-updates/spec.md` (7 req / **31** scenarios; `unit-core` 19 / `unit-app` 11 /
`manual-evidence` 1), `specs/release-distribution/spec.md` (3 MODIFIED blocks, +3 scenarios),
`design.md` (DD-1…DD-15, T1–T24, M1–M7, *Size Forecast*, *Probe addendum*), `proposal.md`
(pbxproj list is **ten** items after D-1 approval, 2026-08-23). Engram obs 7683 (spec), 7684 (design),
7681 (decisions Q1/Q4), 7682 (proposal).

Test runners: `app_unit_command` = `xcodebuild test -project cellar.xcodeproj -scheme cellar
-destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`;
`core_package_command` = `swift test --package-path Packages/CellarCore`.

Size note: this artifact exceeds the generic 530-word phase budget, matching the house precedent
(`archive/2026-08-23-m6-release-pipeline/tasks.md`, `archive/2026-08-22-m6-tip-jar/tasks.md`).
Nothing is padded.

## Verification-class honesty (read before verifying)

`unit-core` and `unit-app` scenarios are RED→GREEN test tasks. `ci-gate` and `manual-evidence` tasks
are **not** test tasks and cannot be discharged by a test runner: each carries its exact command and
its exact accepted output. `sdd-verify` MUST NOT deadlock waiting for a harness the spec itself says
cannot exist (Sparkle ships no test harness — design Tier 3).

**Maintainer checkpoints are STOP tasks.** Apply MUST pause, report, and wait. It MUST NOT synthesise
a key, invent a secret, or proceed past a STOP on an assumption.

## Scenario id map (assigned here — the specs use titles, not numbers)

`app-updates`, in document order:

| id | Scenario | Class |
|---|---|---|
| AU-S1 | The version pair is read from the running bundle | unit-core |
| AU-S2 | A higher marketing version is newer | unit-core |
| AU-S3 | A rebuild of the same marketing version is newer | unit-core |
| AU-S4 | A prerelease sorts below its own release | unit-core |
| AU-S5 | A malformed version is a typed outcome, not a crash | unit-core |
| AU-S6 | The bundle carries the exact feed URL | unit-app |
| AU-S7 | The bundle carries a well-formed verification key | unit-app |
| AU-S8 | Nothing in the app can substitute a different feed or key | unit-app |
| AU-S9 | A complete item validates | unit-core |
| AU-S10 | A missing signature is rejected | unit-core |
| AU-S11 | A missing or non-numeric length is rejected | unit-core |
| AU-S12 | A missing version or short version string is rejected | unit-core |
| AU-S13 | An enclosure that is not an https github.com URL is rejected | unit-core |
| AU-S14 | A wrong minimum system version is rejected | unit-core |
| AU-S15 | A prerelease never appears in the feed, and a merge keeps history | unit-core |
| AU-S16 | An installed build actually replaces itself from the published feed | manual-evidence |
| AU-S17 | A fresh install does not check automatically | unit-app |
| AU-S18 | The user's choice survives a relaunch | unit-app |
| AU-S19 | The persisted preference is written to the updater at launch | unit-core |
| AU-S20 | No bundled default and no framework prompt can enable checking | unit-app |
| AU-S21 | The command is present in the app menu | unit-app |
| AU-S22 | The command is enabled while automatic checking is off | unit-core |
| AU-S23 | The command is disabled only while a check is in flight | unit-core |
| AU-S24 | Invoking the command starts exactly one check | unit-core |
| AU-S25 | A never-checked app says so | unit-core |
| AU-S26 | A checked app reports the date it checked | unit-core |
| AU-S27 | The label follows the updater's recorded date | unit-core |
| AU-S28 | The Updates group renders nothing inert | unit-app |
| AU-S29 | Exactly one file imports the updater framework | unit-app |
| AU-S30 | No user-interface file names the framework's types | unit-app |
| AU-S31 | The update module declares no dependencies | unit-app |

`release-distribution` delta (the four scenarios this change touches):

| id | Scenario | Class |
|---|---|---|
| RD-a1 | A stable tag also publishes the update feed, without a push and without a second release call | ci-gate |
| RD-a2 | A prerelease tag publishes a release and no feed entry | ci-gate |
| RD-b | The delivered application executable is single-architecture (reworded for the universal framework) | ci-gate |
| RD-c | The referenced secret set is exactly the seven named ones | unit |

## Binding constraints carried into every task

- **pbxproj is exactly the ten proposal items — ≈28 lines measured.** Any eleventh key is a deviation
  to report before merge, never to absorb. The Debug (`BCDBE99F…`) and Release (`BCDBE9A0…`)
  app-target blocks stay byte-identical modulo `name` (`ReleasePipelineCompositionTests:213-229`).
  **No `PBXCopyFilesBuildPhase`** — U25(a) measured 0.
- **Untouched, 0-line diffs, binding:** `scripts/release.sh`, `scripts/ExportOptions.plist`,
  `cellar/Shell/AboutView.swift`, `cellar/InfoPlist.xcstrings`, `release.sh:252-254` (U32 does not
  fire), the `release-distribution` stowaway scenario, `theWorkflowCanOnlyEverCreateARelease`
  (`gh == 1`, `git == 0`, **unamended**), `repositoryCarriesNoCredentialMaterial` (DD-12).
- **Nothing new under `cellar/` except `.swift`** — it is a `PBXFileSystemSynchronizedRootGroup`; a
  `.plist`/`.sh`/`.yml` dropped there ships signed in the bundle
  (`appSourcesCarryNoReleaseInfrastructure:409-417`).
- **Probes.** U25 / U31 / U32 / `sign_update` stdin are **RESOLVED by measurement** (design *Probe
  addendum*) — cite, do not re-run. **U30** is apply-owned and is the first verification step of
  Phase 3b. **U33** is a maintainer prerequisite, deferred to the first stable tag. Action major
  versions (`configure-pages@v5`, `upload-pages-artifact@v3`, `deploy-pages@v4`) are an **apply-time
  confirmation** (W11), never a design claim.

## Threat matrix — applicable rows, each with its RED test

| Boundary | RED task |
|---|---|
| Documentation-like paths (a `.plist`/`.sh` inside `cellar/`) | A3.2, B1.1 + `appSourcesCarryNoReleaseInfrastructure` green-on-arrival |
| Executable classification (`appcast.sh` is a new executable) | B1.1 |
| Secret exposure (`SPARKLE_PRIVATE_KEY`) | B1.1, B2.3, B2.4, B4.6 (M7) |
| Subprocess integrity (tampered `sign_update`) | B1.1 (pinned sha256 literal), B4.3 (M1) |
| Update-channel integrity (attacker-served feed) | A3.1, A4.5 |
| Egress consent (a check leaves the machine unasked) | A4.11, A6.1, A3.2 |
| Git repository selection / commit state / PR commands | **N/A — asserted**, pinned by `theWorkflowCanOnlyEverCreateARelease` (unamended) at B2.6 |

---

## Review Workload Forecast

Reused from `design.md` *Size Forecast* — **not re-derived**. House correction **1.9–2.3×**
(`archive/2026-08-22-m6-tip-jar/tasks.md:14`).

| Field | Value |
|---|---|
| Bottom-up, Phase 3a (app-side) | **1,245–1,785** |
| Bottom-up, Phase 3b (publication) | **315–530** |
| Bottom-up total | 1,560–2,315 (design: 1,527–2,314; the ≤35-line delta at the floor is T25, added below) |
| Corrected authored, Phase 3a | **≈2,370–4,105** |
| Corrected authored, Phase 3b | **≈600–1,220** |
| **Corrected authored total (design figure, authoritative)** | **≈2,901–5,322** |
| Spec deltas already on disk (counted, not forecast) | **639** (`app-updates` 383 + `release-distribution` 256) |
| **PR total, one PR (design figure)** | **≈3,840–6,411** |
| PR total, 3a alone (383 spec + SDD artifacts 300–450) | **≈3,050–4,940** |
| PR total, 3b alone as `m6-appcast-publication` (256 spec + its own artifacts 250–400) | **≈1,105–1,875** |
| Governing budget | **5,000** (session preflight and `config.yaml` agree) |
| Risk vs governing budget, one PR | **Exceeded** — authored ceiling 5,322 alone is over; PR total is over across most of its range and by ≈1,411 at the ceiling |
| Risk vs governing budget, 3a alone | **Inside, barely** — ≈60 lines of headroom at the ceiling |
| Risk vs governing budget, 3b alone | **Low** |
| Chain strategy | **pending — maintainer decision required (Q4)** |
| Delivery strategy | single-pr |

```
**Q4 RESOLVED — maintainer decision 2026-08-23: option (B), ONE PR under `size:exception`.**
Recorded overrun: up to ≈1,411 authored lines (≈28%) over the 5,000 budget at the forecast ceiling;
PR total ≈3,840–6,411. Rationale accepted by the maintainer: keep the feed live in the same PR that
ships the app and avoid re-cutting the `release-distribution` delta and paying a second SDD cycle.
Consequence: `delivery_strategy` for this change resolves to `exception-ok`; Phase 3b merges with its
publication path unexercised until the maintainer prerequisites (Pages, `generate_keys`, seventh
secret) exist, and U33 is discharged by the first stable tag, not by this PR.

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: n/a (single PR under size:exception)
400-line budget risk: High
```

`400-line budget risk: High` is the literal guard value against the 400 **default**; that default does
not govern this change. **Against the governing 5,000-line budget the single-PR plan does not fit**:
the corrected authored ceiling is 5,322 and the PR total reaches ≈6,411, of which 639 lines are
already on disk and will not shrink. This is the material difference from the two prior M6 slices,
both of which fitted with headroom.

### Q4 — binding: this phase MUST NOT split and MUST NOT record a `size:exception`

Per obs 7681 Q4, the maintainer is asked first. Two options, each with its concrete consequence:

**(A) Split.** Phase 3a ships as this change's single PR (`m6-sparkle-updates`). Phase 3b becomes a
new SDD change `m6-appcast-publication`.

- Carries over to the new change: the publication half of `design.md` (`scripts/appcast.sh`,
  `release.yml` extension point, DD-9/DD-10/DD-11/DD-13/DD-14, T14–T19, M4–M7), maintainer
  checkpoints 5–6, probes U30 and U33, and `release-distribution` MODIFIED edits **(a)** and **(c)**.
- **Costs re-cutting the `release-distribution` delta.** Edit **(b)** (the arm64 reword) becomes true
  the moment 3a embeds the universal `Sparkle.framework`, so it must stay with 3a; edits (a) and (c)
  move. One 256-line delta becomes two smaller MODIFIED deltas, each re-paying the OpenSpec
  block-reproduction scaffolding. That is real added work, not a rounding error.
- Until 3b lands, the shipped app carries a feed URL that **404s**. Automatic checks are default-off
  (D1), so nothing happens unprompted. An explicit "Check for Updates…" against a missing feed is
  expected to surface Sparkle's own "could not check" path rather than anything destructive — but
  Sparkle's user driver is Tier 3 (no harness, design), so this is an **accepted, unverified**
  consequence, not a proven no-op. It should be stated in the 3a PR body.
- **`SUPublicEDKey` must still be real in 3a** (checkpoints 1–4 stay in 3a). A placeholder passes
  A3.1's 32-byte decode and is indistinguishable at review, yet strands every copy shipped with it.
- `THIRD-PARTY.md` and the `RELEASING.md:251-254` follow-up deletion move into 3a; PRD :9/:188 keep
  saying "pending" until 3b, which is honest because publication is not live.

**(B) One PR under `size:exception`.** Recorded overrun: PR total ≈3,840–6,411 against the 5,000
budget — over by up to ≈1,411 lines (≈28%) at the ceiling, with the corrected authored figure alone
exceeding the budget by ≈322. Nothing is re-cut, the `release-distribution` delta ships intact, the
feed is live in the same PR that ships the app, and no second SDD cycle is paid for.

**Recommendation: (A) split.** The reason is not the line count alone — it is that Phase 3b cannot be
*exercised* by anyone at merge time. 3b's evidence set (M4/U33, M5, M6, M7) is blocked on
GitHub Pages being enabled, `generate_keys` having been run and backed up, and the seventh secret —
none of which exist today (orchestrator correction 2026-08-23: the Developer ID certificate, the ASC
API key and the public flip DO exist as of this morning, and `v0.0.1-rc.1` was published by CI, so
**U30 is runnable locally now** via `scripts/release.sh all`; it is the Pages/EdDSA prerequisites that
remain). Merging 3b inside this PR therefore adds ≈1,220 authored lines whose publication path no test
and no maintainer observation can validate until those prerequisites exist, while pushing the PR over
its governing budget. 3a is fully verifiable at merge (30 of 31 `app-updates` scenarios run from the merge
commit), fits inside 5,000, and has a clean revert boundary. (B) remains reasonable if the maintainer
would rather pay reviewer load once than run a second SDD cycle.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| A1 | App category (pbxproj item 6) | 3a | `… -only-testing:'cellarTests/UpdateProjectFileTests'` | `xcodebuild build -scheme cellar` | Revert 2 pbxproj lines; delete the two tests |
| A2 | Sparkle SPM dependency (items 1–5) + `Package.resolved` | 3a | `… -only-testing:'cellarTests/UpdateProjectFileTests'` | `xcodebuild build -scheme cellar` succeeds and embeds `Sparkle.framework` | Revert 18 pbxproj lines; delete `Package.resolved` |
| A3 | `Resources/Cellar-Info.plist` + item 7 + the real key | 3a | `… -only-testing:'cellarTests/BundleUpdateKeysTests'` | Launch; `plutil -p` the built bundle's Info.plist | Delete `Resources/`; revert 2 pbxproj lines |
| A4 | CellarCore `Updates` target | 3a | `swift test --package-path Packages/CellarCore --filter UpdatesTests` | N/A — pure values, no runtime | Delete `Sources/Updates`, `Tests/UpdatesTests`, 3 manifest entries |
| A5 | `Updates` product linkage (items 8–10, D-1) | 3a | `… -only-testing:'cellarTests/UpdateProjectFileTests'` | `xcodebuild build -scheme cellar` resolves `import Updates` | Revert ≈6 pbxproj lines |
| A6 | `cellar/Updates/*`, Settings group, command, DI | 3a | `… -only-testing:cellarTests` | Launch: Settings → Updates card; app menu → "Check for Updates…" | Delete `cellar/Updates/`; revert 3 app files |
| A7 | `THIRD-PARTY.md` + 3a suite run | 3a | `… -only-testing:cellarTests` and `swift test …` | Read the Sparkle entry | Revert one doc file |
| B1 | `scripts/appcast.sh` | 3b | `… -only-testing:'cellarTests/AppcastScriptContractTests'` | `shellcheck scripts/appcast.sh` (ci-gate) | Delete `scripts/appcast.sh` + its test |
| B2 | `release.yml` steps, permissions, seven secrets | 3b | `… -only-testing:'cellarTests/AppcastWorkflowTests'` and `…/ReleasePipelineCompositionTests` | `actionlint .github/workflows/release.yml` (ci-gate) | Revert the workflow hunk; revert T14/T15 |
| B3 | `RELEASING.md`, `PRD.md`, `README.md` | 3b | `… -only-testing:cellarTests` | Read `RELEASING.md` §2 and §7 end to end | Revert three doc files |
| B4 | Checkpoints, rehearsal, manual evidence | 3b | N/A — `manual-evidence` | `scripts/release.sh all`, then a stable tag | Not code; nothing to revert |

**Parallelism.** Sequential, one writer, no parallel worktrees. A4 (CellarCore) is content-independent
of A1–A3, and B1 is content-independent of B2, but every unit in 3a converges on
`cellar.xcodeproj/project.pbxproj` and on shared `cellarTests` files, and A5 depends on A4.2 having
created the product. Within every unit the order is strictly RED → GREEN → next.

---

## Phase 3a — app-side (independently deliverable)

### A0 Preflight (no repo edits)

- [x] **A0.1** Capture the pre-slice baseline with both runners and record the counts as distinct
      `Test case '…' passed` ids (`Executed 0 tests` is meaningless for Swift Testing bundles). Any
      pre-existing failure is **reported, not fixed**. *deps: none; ~0 lines*
- [x] **A0.2** Cite U25 / U31 / U32 / `sign_update` stdin from the design *Probe addendum*. **Do not
      re-run them.** *deps: none; ~0 lines*

### A1 App category — the cheapest independently revertible step (pbxproj item 6)

- [x] **A1.1 RED** Create `cellarTests/UpdateProjectFileTests.swift` with a **self-contained**
      `#filePath`-anchored repo-root helper (the `SecurityCompositionSupport.swift:42-69` idiom,
      **copied not imported**, so rollback is one deletion). Suite `UpdateProjectFileTests`, **T12(a)**:
      both app-target blocks carry
      `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.developer-tools";` (**two**
      matches) and `GENERATE_INFOPLIST_FILE = YES;` still holds twice. *spec: design-owned pin (no
      `app-updates` scenario); ~55–80 lines; deps: A0*
- [x] **A1.2 RED** Create `cellarTests/BundleUpdateKeysTests.swift`, **T11**: `Bundle.main.infoDictionary`
      (**not** `localizedInfoDictionary` — U24 Build 2; the copyright precedent at `:297-313` is the
      opposite case) carries `LSApplicationCategoryType == "public.app-category.developer-tools"`.
      *spec: design-owned pin; ~25–40 lines; deps: A1.1*
- [x] **A1.3 GREEN** `cellar.xcodeproj/project.pbxproj` item 6: insert the key in **both** blocks,
      alphabetically between `INFOPLIST_KEY_CFBundleDisplayName` (`:431`/`:465`) and
      `INFOPLIST_KEY_NSHumanReadableCopyright`. Confirm
      `git diff --stat cellar.xcodeproj/project.pbxproj` → `2 insertions(+)`. *~2 lines; deps: A1.2*
- [x] **A1.4 GREEN-on-arrival** `appTargetConfigurationsAreIdenticalModuloName` (`:213-229`) must pass
      unchanged. Run `app_unit_command`. *~0 lines; deps: A1.3*

### A2 Sparkle SPM dependency (pbxproj items 1–5) + `Package.resolved`

- [x] **A2.1 RED** `UpdateProjectFileTests`, **T12(b)**: exactly one `XCRemoteSwiftPackageReference`
      for `https://github.com/sparkle-project/Sparkle` with `kind = exactVersion; version = 2.9.6;`;
      exactly one `PBXBuildFile` `Sparkle in Frameworks`; one app-target `PBXFrameworksBuildPhase`
      entry; one `XCSwiftPackageProductDependency` with `productName = Sparkle;`; and the
      `PBXCopyFilesBuildPhase` count is **0** (U25(a) pinned, so a future Embed phase cannot arrive
      silently). *spec: design-owned pin; ~45–65 lines; deps: A1.4*
- [x] **A2.2 GREEN** Add pbxproj items 1–5 — **18 lines measured**, five hunks (1 `PBXBuildFile`,
      1 frameworks entry, 1 `packageReferences` entry, 11 for the new
      `XCRemoteSwiftPackageReference` section, 5 for the product dependency). **No Embed Frameworks
      phase.** `LD_RUNPATH_SEARCH_PATHS` already carries `@executable_path/../Frameworks` — 0-line
      diff. *~18 lines; deps: A2.1*
- [x] **A2.3 GREEN** Commit
      `cellar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (measured: 387
      bytes, `version: 3`, `sparkle` @ 2.9.6, revision `ac2def28…`). Confirm the path is **not**
      gitignored — no `.gitignore` edit is needed. *~18–20 lines; deps: A2.2*
- [x] **A2.4** `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination
      'platform=macOS,arch=arm64'` succeeds and `cellar.app/Contents/Frameworks/Sparkle.framework`
      is present. Cumulative pbxproj diff: 20 insertions. *~0 lines; deps: A2.3*

### A3 The partial plist, the real key, and the key-material guard (pbxproj item 7) — contains STOPs

- [x] **A3.1 RED** `BundleUpdateKeysTests`, **T10**: `Bundle.main.infoDictionary["SUFeedURL"]` is
      exactly `https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml` with scheme `https`, and
      `SUPublicEDKey` base64-decodes to **exactly 32 bytes**. Stays RED through A3.3 — the placeholder
      cannot satisfy it, by design. *spec: AU-S6, AU-S7; ~35–50 lines; deps: A2.4*
- [x] **A3.2 RED** `BundleUpdateKeysTests`, **T22 (bundle half)**: `Resources/Cellar-Info.plist` parses
      via `PropertyListSerialization` and contains **exactly** `SUFeedURL` and `SUPublicEDKey` — no
      `SUEnableAutomaticChecks`, no `SUAutomaticallyUpdate`, no `SUScheduledCheckInterval` — and the
      generated `Bundle.main.infoDictionary` carries none of those three either. *spec: AU-S20;
      ~30–45 lines; deps: A3.1*
- [x] **A3.3 GREEN (partial)** Create `Resources/Cellar-Info.plist` with the two keys, the real feed
      URL, and `<string><!-- set during apply: real SUPublicEDKey, maintainer checkpoint 4 --></string>`
      as a **clearly marked placeholder**. Add pbxproj item 7 (`INFOPLIST_FILE =
      Resources/Cellar-Info.plist;` in **both** blocks; `GENERATE_INFOPLIST_FILE` stays `YES`).
      A3.2 goes green here; **A3.1 stays RED until A3.5**. *~10–12 plist + 2 pbxproj lines; deps: A3.2*
- [x] **A3.4 🛑 MAINTAINER CHECKPOINT 1–3 — STOP AND REPORT.** Apply pauses. Maintainer:
      `curl -fsSLO https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-2.9.6.tar.xz`,
      verify `shasum -a 256`, `tar -xJf`; `./bin/generate_keys`; then **back it up before anything
      else** — `./bin/generate_keys -x sparkle-private.key`, move the file to offline storage or a
      password manager, `rm -P sparkle-private.key`. **One-way door:** losing this key permanently
      severs the update channel for every installed copy. *manual; ~0 lines; deps: A3.3*
- [x] **A3.5 🛑 MAINTAINER CHECKPOINT 4 — STOP.** Paste the printed 44-character base64 public key
      into `Resources/Cellar-Info.plist`, replacing the placeholder. **No placeholder may reach the
      merge commit** (obs 7681 Q1): a well-formed placeholder passes A3.1 unchanged and ships builds
      that can never update themselves. A3.1 goes GREEN here. *manual; ~1 line; deps: A3.4*
- [x] **A3.6 RED** Create `cellarTests/UpdateKeyMaterialTests.swift`, **T20** (DD-12): across the
      repository (excluding `.git`, `build`, `.build`) **exactly one** 44-character base64
      Ed25519-shaped literal exists, and it is the `SUPublicEDKey` value in
      `Resources/Cellar-Info.plist`; non-vacuity — the scan saw **>100** files. Written before A3.5 it
      is RED (zero literals); it goes GREEN on the real key. Order it here so it is authored while the
      key is in hand. *spec: AU-S8 (key-material half); ~55–75 lines; deps: A3.5*
- [x] **A3.7** Run `app_unit_command`: T10, T11, T12, T20, T22(bundle) green.
      `repositoryCarriesNoCredentialMaterial` (`:433-461`) unchanged and green.
      **Residual gap, recorded not hidden (DD-12):** a private key committed in a format that is not
      44-char base64 is not caught. *~0 lines; deps: A3.6*

### A4 CellarCore `Updates` target (DD-1, DD-15) — RED→GREEN pairs

- [x] **A4.1 RED** Create `cellarTests/UpdatePackageManifestTests.swift`, **T24**: parse
      `Packages/CellarCore/Package.swift` as text, isolate `.target(name: "Updates"`, assert it
      contains **no `dependencies:` key at all**, and assert the `Updates` `.library` exists listing
      exactly `["Updates"]`. *spec: AU-S31; ~45–65 lines; deps: A3.7*
- [x] **A4.2 GREEN** `Packages/CellarCore/Package.swift`: `+1 .library(name: "Updates", targets:
      ["Updates"])` (7 → 8 products), `+1 .target(name: "Updates", swiftSettings:
      [.swiftLanguageMode(.v6)])` with **no `dependencies:` key** and a doc comment stating that the
      absence *is* the guarantee, `+1 .testTarget("UpdatesTests", resources: [.copy("Fixtures")])`
      following `ReleaseNotesTests` (`Package.swift:114-119`). *~12–18 lines; deps: A4.1*
- [x] **A4.3 RED** Create `Packages/CellarCore/Tests/UpdatesTests/AppVersionTests.swift` — **T1**
      (parameterized ordering table: `1.0.1 > 1.0.0`; `1.0.0 (2) > 1.0.0 (1)`; `0.0.1-rc.1 < 0.0.1`;
      `1.0.0-rc.2 > 1.0.0-rc.1`), **T2** (each malformed shape `""`, `"1.0"`, `"1.0.x"`, `"v1.0.0"`,
      non-numeric build → its named `AppVersionParseFailure` case), **T7a** (`init?(shortVersionString:
      buildNumber:)` builds the pair from raw strings, returns `nil` for absent/unparseable, never
      substitutes a placeholder). *spec: AU-S1, AU-S2, AU-S3, AU-S4, AU-S5; ~130–180 lines; deps: A4.2*
- [x] **A4.4 GREEN** Create `Packages/CellarCore/Sources/Updates/AppVersion.swift` —
      `public struct AppVersion: Sendable, Hashable, Comparable` with `Prerelease`, typed
      `AppVersionParseFailure`. Ordering: triple, then prerelease < release, then build number.
      *~70–100 lines; deps: A4.3*
- [x] **A4.5 RED** Create `Tests/UpdatesTests/AppcastDocumentTests.swift` + hand-authored
      `Tests/UpdatesTests/Fixtures/*.xml` (DD-14) — **T3** (valid fixture parses: non-empty
      `edSignature`, numeric `length`, `sparkle:version`, `shortVersionString`, `https` `github.com`
      enclosure, `minimumSystemVersion == "26.0"`), **T4** (one fixture per failure case → its exact
      typed error, including the hyphenated-version rejection), **T5** (two-item merged fixture keeps
      both items in descending order and drops neither). *spec: AU-S9, AU-S10, AU-S11, AU-S12, AU-S13,
      AU-S14, AU-S15; ~165–230 lines incl. fixtures; deps: A4.4*
- [x] **A4.6 GREEN** Create `Sources/Updates/AppcastDocument.swift` — validator over XML text
      (`XMLParser`, Foundation only; **no** Sparkle, **no** third-party XML) with the enumerated
      `AppcastValidationFailure` cases. *~100–140 lines; deps: A4.5*
- [x] **A4.7 RED** Create `Tests/UpdatesTests/UpdateCheckPresentationTests.swift` — **T6**: `nil` ⇒
      `"Never checked"` with no date, no placeholder date, no epoch; a `Date` ⇒ a `"Last checked …"`
      label deterministic under an injected `now`; the label changes when the recorded date changes
      from absent to present. *spec: AU-S25, AU-S26, AU-S27; ~45–65 lines; deps: A4.6*
- [x] **A4.8 GREEN** Create `Sources/Updates/UpdateCheckPresentation.swift`. *~30–45 lines; deps: A4.7*
- [x] **A4.9 RED** Create `Tests/UpdatesTests/AppUpdatingTests.swift` with `FakeAppUpdater` (an
      `@Observable` conformer **in the test target, never shipped**) — **T7**: `checkForUpdates()`
      records **exactly one** call per invocation, `automaticallyChecksForUpdates` round-trips,
      `canCheckForUpdates` gates. *spec: AU-S24; ~60–85 lines; deps: A4.8*
- [x] **A4.10 GREEN** Create `Sources/Updates/AppUpdating.swift` —
      `@MainActor public protocol AppUpdating: AnyObject, Observable` (DD-2) with the four members.
      *~25–40 lines; deps: A4.9*
- [x] **A4.11 RED** Create `Tests/UpdatesTests/UpdatePolicyTests.swift` — **T7b**
      (`AutomaticUpdateChecksPolicy.apply(preference:to:)` writes `false` when off, `true` when on,
      **exactly once**; an off run leaves `automaticallyChecksForUpdates == false`) and **T7c**
      (table-driven `UpdateCommandEnablement.isEnabled(canCheckForUpdates:)` is `true` iff the updater
      can check). *spec: AU-S19, AU-S22, AU-S23; ~55–80 lines; deps: A4.10*
- [x] **A4.12 GREEN** Create `Sources/Updates/UpdatePolicy.swift` (DD-15) —
      `@MainActor public enum AutomaticUpdateChecksPolicy` and `public enum UpdateCommandEnablement`
      (`nonisolated`, pure). *~30–45 lines; deps: A4.11*
- [x] **A4.13** Run `core_package_command`. All `UpdatesTests` green; the pre-slice CellarCore count is
      unchanged plus the new cases. No `nonisolated(unsafe)`, no `@unchecked Sendable`, no
      `Task.detached`, no `#available` in the new target. *~0 lines; deps: A4.12*

### A5 `Updates` product linkage — pbxproj items 8–10 (D-1, approved 2026-08-23)

- [x] **A5.1 RED** `UpdateProjectFileTests`, **T12(c)**: one `PBXBuildFile` `Updates in Frameworks`,
      one app-target `PBXFrameworksBuildPhase` entry for it, one `XCSwiftPackageProductDependency`
      with `productName = Updates;`. *spec: design-owned pin (D-1); ~25–35 lines; deps: A4.13*
- [x] **A5.2 GREEN** Add pbxproj items 8–10 (≈6 lines). Cumulative pbxproj diff ≈**28 insertions, 0
      deletions**; the two blocks stay byte-identical modulo `name`. Any further key is a deviation to
      report. *~6 lines; deps: A5.1*

### A6 App-side files, Settings group, menu command, DI

- [x] **A6.1 RED** Create `cellarTests/AutomaticUpdateChecksTests.swift`, **T13**: against a scratch
      `UserDefaults(suiteName:)` — a missing key reads `false`; set/read round-trips across a fresh
      reader over the same suite; **nothing else in the suite is written**. *spec: AU-S17, AU-S18;
      ~50–70 lines; deps: A5.2*
- [x] **A6.2 GREEN** Create `cellar/Updates/AutomaticUpdateChecks.swift` (DD-5) — value type over an
      injected `UserDefaults`, `static let key = "updates.automaticChecksEnabled"`,
      `var isEnabled: Bool { get nonmutating set }`, missing ⇒ `false`. *~35–50 lines; deps: A6.1*
- [x] **A6.3 RED** Create `cellarTests/UpdateCompositionTests.swift` over `AppSecuritySources.load()`
      (comment-stripped) — **T8** (`import Sparkle` in **exactly one** file, and that file is
      `SparkleUpdateChecker.swift`), **T9** (no other file under `cellar/` references `SPUUpdater`,
      `SPUStandardUpdaterController` or `SUUpdater`; `SparkleUpdateChecker` is not named in any
      `View`/`Commands` file), **T21** (no file references `SPUUpdaterDelegate`, `feedURLString(for:)`,
      `setFeedURL` or `updater.feedURL`, and no file writes `SUFeedURL`/`SUPublicEDKey` into
      `UserDefaults` or any mutable dictionary at runtime), **T22 (structural half)** (in
      `SparkleUpdateChecker.swift` the `AutomaticUpdateChecksPolicy.apply(` call appears **before**
      `startUpdater()`, so Sparkle's second-launch prompt is unreachable). *spec: AU-S8, AU-S20,
      AU-S29, AU-S30; ~110–150 lines; deps: A6.2*
- [x] **A6.4 GREEN** Create `cellar/Updates/SparkleUpdateChecker.swift` — the **only** `import Sparkle`
      in the repository. `SPUStandardUpdaterController(startingUpdater: false, …)`, then
      `AutomaticUpdateChecksPolicy.apply(preference:to:)`, then `controller.startUpdater()` in that
      order; two `NSKeyValueObservation`s bridged with `MainActor.assumeIsolated` (DD-6, invariant
      written into the file); writing `automaticallyChecksForUpdates` writes Sparkle's property then
      Cellar's key, in that order. *~90–130 lines; deps: A6.3*
- [x] **A6.5 RED** `UpdateCompositionTests`, **T23**: `cellarApp.swift`'s `.commands { … }` body names
      `CheckForUpdatesCommands`, and `CheckForUpdatesCommands.swift` contains
      `CommandGroup(after: .appInfo)` and **not** `CommandGroup(replacing: .appInfo)` (DD-7 — it can
      never displace `AboutCommands`). *spec: AU-S21; ~30–45 lines; deps: A6.4*
- [x] **A6.6 GREEN** Create `cellar/Updates/CheckForUpdatesCommands.swift` over `let updater: any
      AppUpdating`, applying `UpdateCommandEnablement.isEnabled(canCheckForUpdates:)` to `.disabled`.
      The rule lives in `Updates`; this file only applies it. *~25–40 lines; deps: A6.5*
- [x] **A6.7 RED** `UpdateCompositionTests`, **T25 — added at this phase.** The design's
      requirement→check map leaves **AU-S28** ("The Updates group renders nothing inert") unbound;
      every other scenario has a named T. Assert structurally over `UpdatesSettingsGroup.swift`: it
      declares exactly two rows, carrying `accessibilityIdentifier("updates-automatic-toggle")` and
      `accessibilityIdentifier("updates-last-checked")`, and contains **no** `Picker` and no
      `sparkle:channel`/channel-picker wording (`SettingsView.swift:9-15` forbids inert rows).
      **Report to design if contested** — this is a tasks-phase addition, not a design decision.
      *spec: AU-S28; ~35–50 lines; deps: A6.6*
- [x] **A6.8 GREEN** Create `cellar/Updates/UpdatesSettingsGroup.swift` (the `"Updates"` card, DD-3
      hand-built `Binding(get:set:)`, the two rows and their identifiers) and insert it in
      `cellar/Settings/SettingsView.swift` after `"Interface"` (`:62-73`) using the existing private
      `group(_:rows:)` / `row(label:sub:accessory:)` shapes. *~70–100 lines; deps: A6.7*
- [x] **A6.9 GREEN** `cellar/cellarApp.swift`: in `init`, after the release-notes block (`:313-344`),
      build `AutomaticUpdateChecks` over `.standard` or a
      `UserDefaults(suiteName: "cellar-ui-updates-\(UUID().uuidString)")` under the UI-test launch, then
      `_updater = State(initialValue: AppTestFixtures.isUpdatesEnabled ? AppTestUpdater() :
      SparkleUpdateChecker(automaticChecks:))` typed `any AppUpdating`; add
      `.environment(\.appUpdater, updater)` beside `:456-465`; change `:506` to
      `.commands { AboutCommands(); CheckForUpdatesCommands(updater: updater) }`. *~30–50 lines;
      deps: A6.8*
- [x] **A6.10 GREEN** `cellar/AppTestFixtures.swift`: `isUpdatesEnabled` for `--ui-testing-m6-updates`
      (added to the `isEnabled` disjunction at `:20-29`) and `AppTestUpdater`, an `@Observable`
      in-memory `AppUpdating`. **No UI-test launch may construct `SparkleUpdateChecker`** — a UI test
      can never start an updater, reach the feed, or open a Sparkle window. *~40–70 lines; deps: A6.9*
- [x] **A6.11** Run `app_unit_command` and `xcodebuild build …`. All new suites green;
      `appSourcesCarryNoReleaseInfrastructure` (`:409-417`) and
      `appTargetConfigurationsAreIdenticalModuloName` still green. *~0 lines; deps: A6.10*

### A7 Attribution and the 3a close-out

- [x] **A7.1 GREEN** `THIRD-PARTY.md`: add `## Sparkle` — project URL, version **2.9.6**, Sparkle
      Project contributors / Andy Matuschak, **full MIT text** (D7: sole attribution surface; About is
      untouched, binding). *~30–45 lines; deps: A6.11*
- [x] **A7.2 GREEN** `RELEASING.md` §7: delete the `LSApplicationCategoryType` known-follow-up at
      `:251-254`, now discharged by A1. **Under option (B) this moves into B3.1 with the rest of the
      runbook edit; under option (A) it stays here**, because the follow-up is discharged by 3a.
      *~4 lines; deps: A7.1*
- [x] **A7.3** Full 3a suite: `app_unit_command` and `core_package_command`. Accepted: 0 failures,
      the pre-slice counts plus the new distinct cases, asserted as counts — never `TEST SUCCEEDED`
      alone. `swift build --package-path Packages/CellarCore` clean. *~0 lines; deps: A7.2*
- [x] **A7.4** Confirm the final `project.pbxproj` diff is **exactly the ten items, ≈28 insertions, 0
      deletions**, and that Debug/Release remain byte-identical modulo `name`. Any other line is a
      deviation to report before merge. *~0 lines; deps: A7.3*

---

## Phase 3b — publication (independently deliverable; ships as `m6-appcast-publication` under option A)

> **Sequencing gate.** B4.3 (`U30`, `scripts/release.sh all` locally) is the **first verification
> step** of this phase and runs before any tag. **U33 is deferred to the first stable tag.**

### B1 `scripts/appcast.sh`

- [x] **B1.1 RED** Create `cellarTests/AppcastScriptContractTests.swift`, **T18**: `scripts/appcast.sh`
      exists and `FileManager.default.isExecutableFile(atPath:)` is true; contains `set -euo pipefail`;
      contains **no** `set -x`, **no** `git `, **no** `gh `; contains `2.9.6` and a 64-hex sha256
      literal; `SPARKLE_PRIVATE_KEY` appears **only** inside a `printf '%s' "$SPARKLE_PRIVATE_KEY" |`
      pipeline and **never** as a `>` redirection target. *Threat rows: documentation-like paths,
      executable classification, secret exposure, subprocess integrity. spec: RD-a1 (script half);
      ~70–100 lines; deps: A7.4*
- [x] **B1.2 RED** `AppcastScriptContractTests`, **T19** (DD-14's textual bridge, honest about being
      textual): the script contains every name the validator requires — `sparkle:edSignature`,
      `length=`, `sparkle:version`, `sparkle:shortVersionString`, `sparkle:minimumSystemVersion`,
      `26.0`, `<enclosure`. It proves the emitter and the validator agree on **names**, not on bytes.
      *spec: AU-S9 (emitter half), RD-a1; ~30–45 lines; deps: B1.1*
- [x] **B1.3 GREEN** Create `scripts/appcast.sh`, `chmod +x`. Six phases per design: **guard**
      (`case "$GITHUB_REF_NAME" in *-*) … exit 0` — the same literal as `release.yml:110`), **fetch**
      (`curl` the live feed; 404 ⇒ synthesised empty `<channel>`, DD-9), **tool** (pinned
      `Sparkle-2.9.6.tar.xz`, `shasum -a 256 -c -` against the script's literal, `tar -xJf`, DD-10),
      **sign** (`printf '%s' "$SPARKLE_PRIVATE_KEY" | bin/sign_update --ed-key-file - "$ZIP_PATH"`,
      DD-11), **merge** (prepend one `<item>`, preserve every prior item and its order), **emit**
      (`"$OUTPUT_DIR/appcast.xml"`; nothing enters the repository tree). Environment contract:
      `VERSION`, `GITHUB_REF_NAME`, `ASSET_URL`, `ZIP_PATH`, `FEED_URL`, `OUTPUT_DIR`,
      `SPARKLE_PRIVATE_KEY` (stdin only). *~90–170 lines; deps: B1.2*
- [x] **B1.4 ci-gate** — command: `shellcheck scripts/appcast.sh`. Accepted: **no findings, exit 0**.
      Not a test task. *~0 lines; deps: B1.3*

### B2 `release.yml` — extension point, permissions, the seventh secret

- [x] **B2.1 RED** Create `cellarTests/AppcastWorkflowTests.swift`, **T16**: splitting the workflow on
      `- name:`, the step whose body contains `appcast.sh` appears **after** the step containing
      `gh release create`; and **all four** appcast/Pages steps carry
      `if: ${{ !contains(github.ref_name, '-') }}`. *spec: RD-a1, RD-a2; ~55–80 lines; deps: B1.4*
- [x] **B2.2 RED** `AppcastWorkflowTests`, **T17**: the `release` job declares `pages: write`,
      `id-token: write` **and** `contents: write` (a job-level `permissions` block **replaces** the
      workflow-level one, so `contents: write` must be restated or `gh release create` silently loses
      its token), and `environment: github-pages`. *spec: RD-a1; ~30–45 lines; deps: B2.1*
- [x] **B2.3 RED** Amend `cellarTests/ReleasePipelineCompositionTests.swift`
      `workflowReferencesExactlyTheExpectedSecrets` (`:701-722`) to the **seven**-name set, under the
      test's own authorising comment (`:699-700`: *"Adding one is allowed; adding one without touching
      this list is not"*). The doc comment records **why** the seventh arrived. *Threat row: secret
      exposure. spec: RD-c; ~5–9 lines; deps: B2.2*
- [x] **B2.4 RED** Amend `secretsAppearOnlyAsEnvironmentBindings` (`:668-692`) non-vacuity floor
      `>= 6` → `>= 7`. The per-line `^[A-Z0-9_]+: \$\{\{ secrets\.[A-Z0-9_]+ \}\}$` shape assertion is
      **unchanged** and must still pass for `SPARKLE_PRIVATE_KEY`. *spec: RD-c; ~3–5 lines; deps: B2.3*
- [x] **B2.5 GREEN** `.github/workflows/release.yml`: insert the four steps at the named extension
      point (`:118-119`), **after** the publish step, each with the hyphen guard — *Build the appcast*
      (`env: SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}`, `run: scripts/appcast.sh`),
      `actions/configure-pages`, `actions/upload-pages-artifact` (`path: ${{ runner.temp }}/site`),
      `actions/deploy-pages`. Add job-level `permissions: { contents: write, pages: write, id-token:
      write }` and `environment: github-pages`. **W11: confirm the current action majors before
      writing** (`@v5`/`@v3`/`@v4` are carried from the proposal and unverified); a bumped major is a
      one-token edit, not a re-plan. *~25–40 lines; deps: B2.4*
- [x] **B2.6 GREEN-on-arrival** `theWorkflowCanOnlyEverCreateARelease` (`:733-748`) must pass
      **unamended**: `gh` stays at exactly one `gh release create`, `git` stays at zero. `curl` and
      `uses:` are neither. This is the property that made this hosting design the only viable one.
      *~0 lines; deps: B2.5*
- [x] **B2.7 ci-gate** — command: `actionlint .github/workflows/release.yml`. Accepted: **no output,
      exit 0**. Not a test task. *~0 lines; deps: B2.6*

### B3 Documentation

- [x] **B3.1 GREEN** `RELEASING.md` §2: add prerequisites 6–8 — enable Pages with **source = GitHub
      Actions**; run `generate_keys` **and back the private key up offline**; add the
      `SPARKLE_PRIVATE_KEY` secret — and change "Six repository secrets" → **"Seven"**. §7: add the
      appcast/feed row to the contract, and record risk 3 (Pages is a **full-site replacement**, so a
      future landing page must be built by the **same** job or it silently overwrites the feed).
      *spec: RD-a1, RD-c; ~55–90 lines; deps: B2.7*
- [x] **B3.2 GREEN** `PRD.md` :9 (Distribution line — Sparkle no longer "pending"), :124 (the update
      **channel picker is amended away**, with the reason: D4, and `SettingsView.swift:9-15` forbids an
      inert row), :168 (the appcast host decision is settled: GitHub Pages), :188, :212 — rewritten in
      place with reasons, per the tip-jar/pipeline precedent. *~50–90 lines; deps: B3.1*
- [x] **B3.3 GREEN** `README.md`: state that the app updates itself via Sparkle from the published
      appcast, that automatic checks are **off by default**, and where the manual command lives. The
      runbook is **not** duplicated here. *~25–35 lines; deps: B3.2*
- [x] **B3.4** Run `app_unit_command`. All 3b suites green; the 3a suites unchanged. *~0 lines;
      deps: B3.3*

### B4 Maintainer checkpoints, rehearsal and manual evidence (not test tasks, not merge blockers)

> **Prerequisite status (orchestrator correction, 2026-08-23).** The `m6-release-pipeline`
> prerequisites P1–P5 are now MET: Developer ID Application certificate installed, ASC API key
> `GF2PP6LZ22` in `~/.private_keys`, six secrets set, repository public, and `v0.0.1-rc.1` published
> by run 32621064288. **`U30` can run locally today** (`scripts/release.sh all`). Still unmet for 3b:
> GitHub Pages (source = GitHub Actions), `generate_keys` + offline backup, `SPARKLE_PRIVATE_KEY`.
> The PR may merge without those; the first appcast-publishing tag cannot.

- [x] **B4.1 🛑 MAINTAINER CHECKPOINT 5 — STOP.** Repository → Settings → Secrets →
      `SPARKLE_PRIVATE_KEY` = the exported private key. Verify once with `./bin/sign_update` against
      any zip **before** deleting the local copy. *manual; deps: B3.4*
- [x] **B4.2 🛑 MAINTAINER CHECKPOINT 6 — STOP.** Repository → Settings → Pages → **Source: GitHub
      Actions** (measured `has_pages: false`). Confirm no `github-pages` environment protection rule
      excludes tag refs; if one does, **DD-13's second-job fallback applies** and is a reported
      deviation, not a silent swap. *manual; deps: B4.1*
- [x] **B4.3 manual-evidence M1 / `U30` — the FIRST verification step of this phase.** Run
      `scripts/release.sh all` **locally**, never discover this on a tag. Accepted:
      `codesign --verify --strict --verbose=2` (`release.sh:214`) passes over `Sparkle.framework`,
      `Autoupdate`, `Updater.app` and **both** `.xpc`. Failure ⇒ the integration shape is wrong;
      **re-plan, never relax the gate**. *manual; deps: B4.2*
- [x] **B4.4 manual-evidence M2 / M3 — re-checks on the *exported* bundle.** M2:
      `lipo -archs build/verify/cellar.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle`
      → `x86_64 arm64` (accepted under D2; the addendum measured a **Debug** build, which does not
      license a claim about the export). M3:
      `find build/verify/cellar.app/Contents \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' \)
      -print` → **empty**. If M3 fires, the withdrawn U32 deviation is **reopened, never absorbed**.
      *spec: RD-b; manual; deps: B4.3*
- [ ] **B4.5 manual-evidence M4 / `U33` — deferred to the first stable tag.**
      `curl -fsSI https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml` → `200` with an XML
      `content-type`, after the first `deploy-pages` run. *spec: RD-a1; manual; deps: B4.4*
- [ ] **B4.6 manual-evidence M5 / M6 / M7.** M5: install the `v0.0.1-rc.1` build into `/Applications`,
      publish a **stable** tag, let Cellar find it — the update installs and relaunches (**rc → rc is
      impossible under D4**; the rehearsal must be rc-installed → stable-published). M6: Gatekeeper
      after the swap with **networking disabled** — first launch of the replaced bundle succeeds with
      no "cannot be opened" dialog. M7: job-log sweep after the first appcast run (M10's precedent) —
      **zero** occurrences of the key's value; `SPARKLE_PRIVATE_KEY` appears only as `***`.
      *spec: AU-S16, RD-a1, RD-c; manual; deps: B4.5*
- [ ] **B4.7 manual-evidence RD-a2.** A prerelease tag publishes a release and **no** feed entry: the
      four guarded steps are skipped and the live feed is unchanged. *spec: RD-a2; manual; deps: B4.6*

---

## Carried forward, recorded not inherited silently

- **AU-S16** is the single `manual-evidence` scenario and cannot be observed until a Developer ID
  certificate, the seven secrets, GitHub Pages and a stable tag all exist. The other 30 `app-updates`
  scenarios run from the merge commit (3a alone covers all 30 under option A).
- **DD-12 residual gap:** a private key committed in a format that is **not** 44-char base64 evades
  T20 and `repositoryCarriesNoCredentialMaterial`. Stated, not smoothed.
- **T25 is a tasks-phase addition** discharging AU-S28, which the design's requirement→check map left
  unbound. Report it to design if contested.
- **`cellarUITests/ReleaseNotesUITests` is still unowned** since m5-health. Not this slice's defect;
  `sdd-verify` must state its status rather than inherit it silently.
- **Release-notes presentation** (`<description>` / `sparkle:releaseNotesLink`) is deferred out of v1:
  Sparkle's window simply shows no notes. Populating it crosses the existing release-notes consent
  gate and belongs to its own change.
