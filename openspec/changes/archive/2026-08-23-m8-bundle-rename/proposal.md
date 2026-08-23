# Proposal: One Name on Disk — `cellar.app` → `Home-Cellar.app` (`m8-bundle-rename`)

Anchors PRD.md **M6 "Ship"** (:216-217) and specifically its cask-channel line **:194**, which
still promises that `brew install --cask home-cellar` installs `/Applications/cellar.app`. M6's
exit is a 1.0 public release; the product shipped with four names for one app, and this slice is
the cheapest moment to collapse them — the installed base is still empty (D1).

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled clone-local.

Inputs: `openspec/changes/m8-bundle-rename/explore.md` (Engram `sdd/m8-bundle-rename/explore`,
obs `#7745`) and maintainer decision **D1** (Engram `sdd/m8-bundle-rename/decisions`, obs `#7746`).
This document exceeds the generic 450-word phase budget deliberately: `openspec/config.yaml`
`rules.proposal` and the house precedent (`archive/2026-08-23-m7-tap-trust/proposal.md`) govern shape.

## Intent

The app answers to four different names depending on where you look. Finder and the cask show
`Home-Cellar`, the release asset is `Home-Cellar-<version>.zip`, but the bundle on disk is
`cellar.app`, the process in Activity Monitor is `cellar`, and the tap's cask stanza says
`app "cellar.app"`. A user who taps, installs, then looks in `/Applications` finds a bundle whose
name matches neither the thing they typed nor the thing the app calls itself.

**Product outcome.** One name, everywhere a person can see it: `/Applications/Home-Cellar.app`,
`Contents/MacOS/Home-Cellar`, `Home-Cellar-<version>.zip`, display name `Home-Cellar`, cask token
`home-cellar`. The documentation describes exactly one install path with no "but it is actually
called…" caveat, and the tap's `app` stanza resolves against the asset the release job publishes.

**What must not move.** `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar` is the identity every
user-data path, Keychain item and Sparkle host-match already depends on. Verified in explore §1.2:
Application Support derives from `Bundle.main.bundleIdentifier`, caches use the literal `"Cellar"`,
and nothing derives a path from the product name. **The rename therefore moves no user data.**

## Resolved decision (binding — maintainer, 2026-08-23; MUST NOT be reopened)

**D1 — the app has no users yet.** v1.0.0 and v1.1.0 are public tags and the tap is live, but
nobody has installed it besides the maintainer's own Mac. Consequences, all binding:

- **No migration instruction, no migration copy, no in-app notice.** Explore §9 Q1 → option (a).
- The `--adopt` block in `README.md:49-60` / `RELEASING.md:350-351` is rewritten to reference
  **`Home-Cellar.app` only**, for the direct-download → cask path. No old-name guidance survives.
- Explore risks **R1** (Sparkle keeps a self-updating copy at its old path forever), **R2**
  (duplicate bundles for direct-download users) and **R3** (Homebrew/brew#22993 orphans the old
  bundle on `--greedy`) are **recorded as facts in `explore.md` and are non-issues for this slice**,
  because the installed base they describe does not exist. They are not mitigated, not documented
  to users, and not re-derived by later phases.
- The maintainer reinstalls their own Mac by hand after release:
  `brew uninstall --cask home-cellar` then `brew install --cask home-cellar`.
- **R4 still applies in full** — see *Delivery*.

**Derived from D1 (stated so `sdd-spec` does not re-derive it):** explore §2.H's proposed *new
update-continuity scenario* is **dropped**. It would specify behaviour for an installed base of
zero. The delta carries three MODIFIED requirements and no ADDED requirement.

## Scope

### In scope

1. **`cellar.xcodeproj/project.pbxproj`** — `PRODUCT_NAME = "Home-Cellar"` and a new pin
   `PRODUCT_MODULE_NAME = cellar` in **both** the Debug and Release app-target blocks; the product
   `PBXFileReference` path; `TEST_HOST` ×2. `TEST_TARGET_NAME`, `name`, `productName`, `remoteInfo`
   and `PRODUCT_BUNDLE_IDENTIFIER` are **unchanged**.
2. **`cellar.xcscheme`** — three `BuildableName` values. `BlueprintName = "cellar"` and the scheme
   filename stay, so every `-scheme cellar` command in `openspec/config.yaml` keeps working.
3. **`scripts/release.sh`** — split the overloaded `SCHEME` constant: a new `PRODUCT="Home-Cellar"`
   feeds the export path, the verify path and the two `lipo` executable paths; `-scheme` keeps
   `SCHEME`. The `CFBundleDisplayName` gate at `:245-246` is already correct and **MUST NOT change**.
4. **`.github/workflows/release.yml:159`** — the hardcoded `codesign -dvvv` export path.
5. **Tap repo** (`juancasanueva/homebrew-cellar`) — `Casks/home-cellar.rb:20` `app` stanza;
   `.github/workflows/ci.yml:77,79,90`; `README.md:14,16,29,32`. The `zap trash:` block and
   `livecheck` are **unchanged** — no data path moves.
6. **App-repo docs** — `README.md:42,49-63`, `RELEASING.md:265,303,336,350-351`, `PRD.md:194`.
7. **New RED tests** pinning what nothing pins today, plus the deliberate update of
   `cellarTests/CaskZapInventoryTests.swift:335` and its doc comment.
8. **One spec delta** against `release-distribution` (below).

### Out of scope (non-goals — recorded, not omitted)

- **The bundle identifier.** `com.juancasanueva.cellar` stays. `ReleasePipelineCompositionTests.swift:94`
  and `UpdateProjectFileTests.swift:68` already guard it and stay green untouched.
- **Renaming the Xcode target, the `cellar/` folder, or the Swift module.** Explore Approach 1's
  blast radius (22 `@testable import cellar` files, `TEST_TARGET_NAME`, `remoteInfo`, every
  documented `-scheme` command) buys nothing a user can see. Never planned — see Q5.
- **`cellar.xcarchive`.** Local-rehearsal cosmetics only — see Q4.
- **Migration of any kind** (D1): no `target:` stanza, no `zap trash:` entry for the old path, no
  `uninstall delete:`, no `SUBundleName`. Explore §4 records why each is unacceptable *and* why the
  question is moot here.
- **The "cache dir under bundle id" follow-up.** Orthogonal (explore §1.2), and folding it in would
  make a zero-data-movement change into a data-migration change.
- **Any behaviour change inside the app.** No CellarCore source file is touched.

## Capabilities

> Contract with `sdd-spec`. Requirement names below are the **exact** headings in
> `openspec/specs/release-distribution/spec.md`.

### New Capabilities

**None.** The bundle's name on disk is already a `release-distribution` concern.

### Modified Capabilities

- **`release-distribution`** — three MODIFIED, zero ADDED, zero REMOVED.

| Requirement (exact heading) | Lines | Delta |
|---|---|---|
| A pushed tag is the only thing that produces a downloadable release | :27, :34, :59-65 | **MODIFIED** — "the bundle inside it MUST be `cellar.app`" → `Home-Cellar.app`; the scenario's "named `cellar.app`" follows |
| The delivered build is installable through the project's Homebrew tap | :408, :415-418, :436 | **MODIFIED** — the delivered bundle's installed path becomes `/Applications/Home-Cellar.app`, and the "this change MUST NOT rename it" clause is replaced by the new invariant |
| Uninstalling states exactly what it removes, and what it cannot | :473, :489, :517 | **MODIFIED** — the documented installed bundle becomes `Home-Cellar.app`; the zap inventory itself is unchanged because no data root moves |

> **`sdd-spec` obligations.** (1) `spec.md:619` names `Contents/MacOS/cellar` inside a **Provenance**
> narrative paragraph, and `:686-688` / `:718-720` record this exact rename as the deferred slice.
> None sits inside a requirement block, so a MODIFIED delta cannot carry them — state the
> hand-update obligation under *Notes for archive*, exactly as the verification-class counts were
> hand-updated at `:627-632` (**R7**). (2) `## Verification classes` counts are unchanged: no
> requirement is added or removed.

## Approach

**Explore Approach 3, without the 3b `EXECUTABLE_NAME` pin.**

Keep the Xcode target named `cellar`; set `PRODUCT_NAME = "Home-Cellar"`; **pin
`PRODUCT_MODULE_NAME = cellar`** so the Swift module does not silently become `Home_Cellar` and
break 22 `@testable import cellar` files. Let `EXECUTABLE_NAME` follow `PRODUCT_NAME` to
`Home-Cellar`, because `Contents/MacOS/cellar` is visible in Activity Monitor and in
`codesign -dvvv` output — pinning it would re-create the exact inconsistency this slice exists to
remove, to save four changed lines.

Rejected and recorded: **Approach 1** (rename the target) has the largest blast radius for the
smallest gain; **Approach 2** (`PRODUCT_NAME` alone) is a trap — `PRODUCT_MODULE_NAME` defaults to
`$(PRODUCT_NAME:c99extidentifier)` and is pinned nowhere in this repo today.

**Mandatory design-phase probe (R5).** `sdd-design` MUST run, before and after the pbxproj edit:

```sh
xcodebuild -project cellar.xcodeproj -target cellar -showBuildSettings \
  | rg 'PRODUCT_MODULE_NAME|PRODUCT_NAME|EXECUTABLE_NAME|FULL_PRODUCT_NAME'
```

The `PRODUCT_MODULE_NAME` default is Apple's documented behaviour, but it is load-bearing for 22
files and must be **measured**, not inherited from documentation.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `cellar.xcodeproj/project.pbxproj` :38, :107, :142, :446, :482, :510, :531 | Modified | product name, module-name pin, product file reference, `TEST_HOST` ×2 |
| `cellar.xcodeproj/xcshareddata/xcschemes/cellar.xcscheme` :19, :73, :104 | Modified | three `BuildableName` |
| `scripts/release.sh` :31, :48, :50, :148, :236 | Modified | `PRODUCT` constant; scheme/product/executable split |
| `.github/workflows/release.yml` :159 | Modified | export path in `codesign -dvvv` |
| `README.md` :42, :49-63 · `RELEASING.md` :265, :303, :336, :350-351 · `PRD.md` :194 | Modified | one install path; `--adopt` block rewritten for the new name only (D1) |
| `cellarTests/CaskZapInventoryTests.swift` :335, :338-342 | Modified | **R6** — deliberate, case-sensitive |
| `cellarTests/` — new pins | New | pbxproj pins, `release.sh` split, scheme `BuildableName`, README name |
| `openspec/changes/m8-bundle-rename/specs/release-distribution/spec.md` | New | one delta, three MODIFIED |
| **Tap repo** `Casks/home-cellar.rb` :20 · `.github/workflows/ci.yml` :77, :79, :90 · `README.md` :14, :16, :29, :32 | Modified | second repository, ordered first |
| `PRODUCT_BUNDLE_IDENTIFIER`, `zap trash:`, `livecheck`, `bump.yml`, all CellarCore sources, all `cellarUITests` | **Untouched — binding** | UI tests use bare `XCUIApplication()` via `TEST_TARGET_NAME = cellar` (explore §1.3) |

## Delivery

`single-pr` per the cached strategy — but on **two repositories**, and the order is a hard
constraint, not a preference.

> **Ordering constraint (R4, binding).** The tap PR (cask `app` stanza + `ci.yml` + `README.md`)
> **MUST be merged before the app's `v1.2.0` tag is pushed.** `homebrew-cellar/.github/workflows/bump.yml`
> runs `17 */6 * * *`, rewrites only `version` and `sha256`, and gates on `brew style` +
> `brew audit --cask [--online --strict]` — **none of which extracts the archive or resolves the
> `app` stanza**. A tag pushed while the cask still says `app "cellar.app"` produces a cask that
> audits clean and installs broken. Alternative: pause `bump.yml` across the window.
> `sdd-tasks` MUST carry this as an explicit ordering dependency between work units, not a comment.

The rename **rides the next tag** (D1) — no standalone rename-only release. App-repo branch
`feat/m8-bundle-rename`; tap-repo branch of the same name.

### Strict TDD

`config.yaml` sets `strict_tdd: true`. Explore §2.F verified that **nothing** currently pins the
product name, the export path, the zip name or the scheme's `BuildableName` — grep across
`cellarTests/` returns zero matches. This slice must therefore **add** the missing RED tests before
touching the files they describe:

| # | RED unit | RED because |
|---|---|---|
| 1 | `project.pbxproj` declares `PRODUCT_NAME = "Home-Cellar"` **and** `PRODUCT_MODULE_NAME = cellar` in both build configurations, asserted together | neither line exists today |
| 2 | `project.pbxproj`'s `TEST_HOST` resolves through `Home-Cellar.app/.../Home-Cellar` | says `cellar.app/.../cellar` |
| 3 | `release.sh` uses a product constant distinct from `SCHEME`, and still passes `-scheme cellar` | `SCHEME` is conflated across four roles |
| 4 | `cellar.xcscheme` carries `BuildableName = "Home-Cellar.app"` in all three places, `BlueprintName` unchanged | nothing pins the scheme |
| 5 | `README.md` names `Home-Cellar.app` | :335 pins the old name |

**R6 — `CaskZapInventoryTests.swift:335` goes RED for a deliberate reason.**
`"Home-Cellar.app".contains("cellar.app")` is `false` because of the capital `C`. It MUST be updated
to assert the new name, **never** "fixed" by lowercasing or relaxing the comparison.
`theReadmeCarriesTheAdoptCommandAsAWholeLine` (:344-354) stays green: the adopt *command* line is
unchanged; only the paragraph above it is rewritten.

`ReleasePipelineCompositionTests.swift:519-521` (release.sh reads `CFBundleDisplayName`) and the two
bundle-identifier guards stay green untouched — they are the proof the invariant held.

### Size forecast

| Bucket | Lines |
|---|---|
| `project.pbxproj`, scheme, `release.sh`, `release.yml` | ~24 |
| Tap repo (`home-cellar.rb`, `ci.yml`, `README.md`) | ~14 |
| App-repo docs (`README.md`, `RELEASING.md`, `PRD.md`) | ~40 |
| Existing test update (`CaskZapInventoryTests`) | ~8 |
| New RED tests (units 1-5) | ~80-110 |
| Spec delta (3 MODIFIED blocks reproduced in full) | ~140-180 |
| **Total authored** | **~310-380** |

This slice is almost entirely enumerated line-by-line from source, so the house's 1.9-2.3×
discovery correction does **not** apply. Against the governing **5,000**-line budget: **Low**
(≤8 %). Against the default 400-line reviewer guard: **Medium** — near the ceiling, and split across
two repositories, which is itself the natural cut. `sdd-tasks` MUST emit the exact guard lines
`Decision needed before apply: Yes|No`, `Chained PRs recommended: Yes|No`, and
`400-line budget risk: Low|Medium|High`.

## Risks

| # | Risk | L | Mitigation |
|---|---|---|---|
| **R4** | **`bump.yml` ordering race.** A tap bumped before its `app` stanza flips ships a cask that audits clean and installs broken | **High** | Tap PR merges first; stated as a task-level ordering dependency. Still live under D1 — it harms the *next* user, not an existing one |
| **R5** | **`PRODUCT_MODULE_NAME` default is assumed, not measured.** 22 test files depend on it | Med | `sdd-design` runs the `-showBuildSettings` probe before and after; RED unit 1 pins both lines together |
| **R6** | **`CaskZapInventoryTests:335` is a case-sensitive substring assertion** that goes RED for a wrong-looking reason | Low | Named here and in the task; updated deliberately, never relaxed |
| **R7** | **Provenance prose sits outside every requirement block** (`spec.md:619`, `:686-688`, `:718-720`) and cannot ride a MODIFIED delta | Med | Delta's *Notes for archive* carries the hand-update obligation; `sdd-archive` executes it |
| **R8** | **`cellar.xcarchive` not renamed** — decided by omission rather than deliberately | Low | Q4 below; default is an explicit "leave it" |
| R1/R2/R3 | Installed-base split, duplicate bundles, brew#22993 orphan | — | **Closed by D1** — the installed base is empty. Recorded as facts in `explore.md`; not mitigated, not documented to users |

## Rollback Plan

`rules.proposal` mandates one for anything touching the Xcode project file. This change is a pure
rename of build outputs and prose: **no schema, no cache file, no Keychain item, no dependency and
no user-data path changes**, so a revert orphans nothing on any machine.

Reversible in this order:

1. **Tap repo** — revert the cask/CI/README commit. `bump.yml` is untouched, so nothing else drifts.
2. **App repo** — revert the `feat/m8-bundle-rename` merge. `PRODUCT_NAME` returns to
   `$(TARGET_NAME)`, `PRODUCT_MODULE_NAME` disappears, and the module name is unchanged either way
   (that is the point of the pin).
3. **If a tag already shipped**, the tap must be reverted *first* and then re-pointed at the last
   `cellar.app` asset; a reverted app repo with a `Home-Cellar.app` cask is the same broken state
   R4 describes, inverted.

Post-revert checks: `swift build --package-path Packages/CellarCore` and
`xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.

## Success Criteria

- [ ] `xcodebuild -showBuildSettings` reports `PRODUCT_NAME = Home-Cellar`, `EXECUTABLE_NAME = Home-Cellar`,
      `FULL_PRODUCT_NAME = Home-Cellar.app` and `PRODUCT_MODULE_NAME = cellar` (R5 probe, measured).
- [ ] `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar` shows a **0-line diff**, and both
      existing guard tests stay green untouched.
- [ ] All 22 `@testable import cellar` files compile unchanged; `xcodebuild test … -scheme cellar`
      is green with no scheme, `TEST_TARGET_NAME` or `-only-testing:` argument changed.
- [ ] `scripts/release.sh` exports `Home-Cellar.app`, `lipo`s `Contents/MacOS/Home-Cellar`, still
      passes `-scheme cellar`, and its `CFBundleDisplayName == Home-Cellar` gate is unmodified.
- [ ] A release run publishes `Home-Cellar-<version>.zip` containing `Home-Cellar.app`, notarized
      and stapled, with `codesign -dvvv` reading the new export path.
- [ ] The tap PR is merged **before** the app tag is pushed; the tap's `ci.yml` install/uninstall job
      passes against `/Applications/Home-Cellar.app`.
- [ ] `brew tap juancasanueva/cellar && brew trust juancasanueva/cellar && brew install --cask home-cellar`
      places `/Applications/Home-Cellar.app` on a clean machine.
- [ ] `README.md`, `RELEASING.md` and `PRD.md:194` name exactly one bundle, with **no** old-name or
      migration guidance anywhere (D1).
- [ ] RED units 1-5 each fail before their implementation and pass after; `CaskZapInventoryTests:335`
      asserts `Home-Cellar.app` with case intact.
- [ ] The `release-distribution` delta lands with the three requirement headings named above, and the
      Provenance hand-update obligation (R7) is written under *Notes for archive*.

## Proposal question round

Three product questions remain open. Each carries a proposed default, and each default is safe to
proceed on — `sdd-spec` and `sdd-design` may start now. Correct any of them and the proposal is
updated in place; none changes the approach, only what gets written down.

1. **Rename `cellar.xcarchive` too?** (`release.sh:46`, cosmetic, local rehearsals + `RELEASING.md`.)
   *Proposed default:* **no — leave it `cellar.xcarchive`, explicitly out of scope.** It is a build
   intermediate no user ever sees, and renaming it adds `RELEASING.md` churn for zero visible gain.
2. **Will the Xcode target and the `cellar/` source folder ever be renamed?**
   *Proposed default:* **no — explicitly out of scope and not planned.** Recorded here so it is not
   re-derived as an open question in a later slice.
3. **Accept the product-name / module-name divergence** (`Home-Cellar` product, `cellar` module),
   or spend 22 mechanical import edits to align them?
   *Proposed default:* **accept it and document it.** The module name is internal, never user-visible,
   and pinning it is what keeps this slice's blast radius at build settings instead of source files.
   RED unit 1 asserts both lines together so the divergence is deliberate and discoverable.

*Would you like to correct any of these, or run a second question round before `sdd-spec`?*
