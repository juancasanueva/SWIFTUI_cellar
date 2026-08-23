# Proposal: Homebrew Tap and Cask (`m6-cask-tap`)

Anchors PRD.md **M6 "Ship"** (:217, "self-hosted tap") — the **fourth and final M6 shipping slice**,
after the tip jar (built then removed), `m6-release-pipeline` and `m6-sparkle-updates`. Delivers
PRD :194's cask channel and closes PRD :9's "Homebrew cask still pending".

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled (no reviews started).

Inputs: `openspec/changes/m6-cask-tap/explore.md` (Engram `sdd/m6-cask-tap/explore`, obs `#7700`),
orchestrator probes obs `#7699` and `#7701`, the maintainer's decisions D1–D5 (below), and the
inherited contract in `openspec/specs/release-distribution/spec.md` `## Provenance`.

## Intent

Cellar 1.0.0 is downloadable and self-updating, but it is **not installable the way its own users
install everything else**. Cellar's entire product thesis is that Homebrew is the source of truth;
shipping it as a zip you drag from a browser is the one workflow the app tells people to stop doing.

The product outcome: `brew install --cask juancasanueva/cellar/home-cellar` puts
`/Applications/cellar.app` on the machine at the released version, and `brew uninstall --zap` takes
it off again while stating honestly what it cannot remove. A user who lives in `brew` never leaves it.

This slice adds **no Swift product code and no in-app behaviour change**. Its engineering content is
not the Ruby file — it is the test that stops the uninstall story from quietly becoming a lie (§*Strict
TDD*), because every M-slice so far added a cache file under `~/Library/Caches/Cellar` and nothing
today would notice a sixth one appearing while the cask still lists five.

## Resolved Decisions (binding — taken by the maintainer 2026-08-23, MUST NOT be reopened)

| # | Decision | Rejected |
|---|---|---|
| **D1** | Bump mechanism = explore §6 **option B**: a workflow in the *tap* repo on `schedule:` + `workflow_dispatch:` that pulls the app repo's `releases/latest`. **Zero new secrets. `release.yml` behaviour unchanged.** | **A** (cross-repo `repository_dispatch` + PAT stored beside the Developer ID `.p12`); **C** (a second workflow here, unconstrained by `release.yml`'s file-scoped invariants); **D** (manual only — kept as the documented fallback, not the mechanism) |
| **D2** | **Delete** the extension-point comment at `.github/workflows/release.yml:175-176`. Nothing else in that file changes. | Leaving a promise the design declined |
| **D3** | `app "cellar.app"`, **no `target:`** | `target: "Home-Cellar.app"` — splits the two install channels and interacts with Sparkle's in-place replacement in a way nobody has measured. The `Home-Cellar.app` rename is logged as its own follow-up slice |
| **D4** | `homepage "https://github.com/juancasanueva/SWIFTUI_cellar"` — therefore **no `verified:`** on `url` | A landing-page homepage, which would make `verified:` mandatory (`brew audit` errors with "the `verified` parameter is unnecessary" when the two domains match) |
| **D5** | The tap repo carries **its own README** (install, uninstall, Keychain caveat, fully-qualified token form) | A bare `Casks/` repo — `brew tap` users land on that page |

## Measured facts this change consumes (probes, not assumptions)

| Fact | Value | Source |
|---|---|---|
| v1.0.0 asset `sha256` | `078a0b5a49fa6e75f885796de1764f36efe72e9db8564fb140bf2112fd6793b6` (6,448,745 bytes) | obs `#7699`, computed from the **published** asset |
| Zip layout | `cellar.app/` at the archive root, no wrapper (`ditto --keepParent`) | obs `#7699` |
| Token collision | `brew info --cask cellar` / `home-cellar` → no such cask; `brew search --cask cellar` → only `clarc` (Homebrew 6.0.18) | obs `#7699` |
| Tap repo | `juancasanueva/homebrew-cellar` **does not exist** | obs `#7699` |
| Zap inventory (on-disk) | **EXISTS**: `~/Library/Caches/Cellar`, `~/Library/Caches/com.juancasanueva.cellar`, `~/Library/Application Support/com.juancasanueva.cellar`, `~/Library/HTTPStorages/com.juancasanueva.cellar`, `~/Library/Preferences/com.juancasanueva.cellar.plist`. **ABSENT**: `…/Saved Application State/com.juancasanueva.cellar.savedState` | obs `#7701` |

**The `savedState` path is dropped from the cask**, per explore §9's rule: what a real machine does not
show is removed, never guessed in.

## Scope

### In scope — this repository (the reviewed PR)

- `README.md` `## Install` — the two brew commands **above** the direct download; states that the
  installed bundle is `cellar.app`.
- `RELEASING.md` — new tap section: the tap and cask tokens, the pull-based bump workflow, the zap
  inventory, the two Keychain items a zap **cannot** remove, and the manual fallback (D1's option D).
- `PRD.md` :9 / :194 / :217 — `juan/tap` → `juancasanueva/cellar`, `cellar` → `home-cellar`,
  "still pending" → shipped, M6 gains slice 4.
- `.github/workflows/release.yml` — **delete two comment lines** (D2), no step touched.
- `cellarTests/CaskZapInventoryTests.swift` (**new**) and one assertion added to
  `cellarTests/ReleasePipelineCompositionTests.swift`.
- `openspec/changes/m6-cask-tap/specs/release-distribution/spec.md` — ADDED-only delta.

### In scope — `juancasanueva/homebrew-cellar` (a different repository, **outside the reviewed diff**)

Four files, ~130 lines: `Casks/home-cellar.rb`, `.github/workflows/ci.yml`,
`.github/workflows/bump.yml`, `README.md`.

> **Risk R7, stated up front.** The cask, its CI and its bump automation never appear in this
> repository's PR. A reviewer reading the PR sees only the documentation half, and the 5,000-line
> budget measures only that half. **Mitigation, binding on `sdd-design`: `design.md` MUST quote all
> four tap-repo files verbatim**, so the whole change is readable without leaving the PR.

### Out of scope (non-goals — recorded, not omitted)

- **No `target:` rename.** `/Applications/cellar.app` stays lowercase; the `Home-Cellar.app` rename is
  a separate slice touching `PRODUCT_NAME`, four `release.sh` gates, the `release-distribution`
  bundle-name scenario, and the update continuity of every installed 1.0.0 copy.
- **No submission to `homebrew/cask`.** Notability requirements are unmet (PRD :194); the self-hosted
  tap is the channel.
- **No new secret anywhere** — not here, not in the tap repo. The seven-secret set stays closed.
- **No second workflow in this repository**, and **no behavioural change to `release.yml`**.
- **No `brew audit --cask --new`** in tap CI — it enforces `homebrew/cask` submission house rules that
  a third-party tap is entitled to ignore.
- **Untouched, binding 0-line diffs**: `scripts/release.sh`, `scripts/appcast.sh`,
  `cellar.xcodeproj/project.pbxproj`, `Packages/CellarCore/**`, every `.swift` under `cellar/`,
  `cellar.xcscheme`. This change adds **no Swift product code**.
- Deferred follow-ups, recorded so they are not re-derived: the `Home-Cellar.app` rename; moving
  `~/Library/Caches/Cellar` under the bundle id (a migration, R4); a DMG; the landing page.

## Capabilities

- **New capabilities: None.** A tap is a second channel for the *same delivered build*, and
  `release-distribution` already owns "what must be true of a delivered build".
- **Modified capability: `release-distribution`** — ADDED-only delta, **2 requirements** (~5
  scenarios; the exact count is `sdd-spec`'s):

| Requirement | Scenario material | Class → runner |
|---|---|---|
| The delivered build is installable through the project's Homebrew tap | tap + install yields `/Applications/cellar.app` at the released version; the cask declares `auto_updates true` so `brew upgrade` never fights Sparkle; a prerelease tag never becomes a cask version | `ci-gate` → **the tap repo's** `ci.yml` on `macos-26`; `manual-evidence` → maintainer transcript recorded in `design.md` |
| Uninstalling states exactly what it removes, and what it cannot | the documented zap inventory covers every path the app writes; the two Keychain items are documented as surviving a zap | `unit` → `cellarTests`, this repository |

> **`sdd-spec` obligations.** (1) The delta's verification-class table MUST name the **runner** per
> class, because the `ci-gate` and `manual-evidence` scenarios execute in a *different repository* — a
> first for this project; `app-updates`' class table is the precedent for stating it plainly. (2) The
> main spec's `## Verification classes` counts (currently `unit` 14 / `ci-gate` 14 /
> `manual-evidence` 4) live **outside** every requirement block, so an ADDED delta structurally cannot
> carry them; the delta MUST state the hand-update obligation under *Notes for archive*, exactly as
> `m6-sparkle-updates` did.

## Approach

**1 — The cask** (`Casks/home-cellar.rb`), per explore §5.2, with the measured `sha256` and the
trimmed five-path zap list:

| Stanza | Value | Why |
|---|---|---|
| `url` | `.../releases/download/v#{version}/Home-Cellar-#{version}.zip` | inherited verbatim from `release-distribution` |
| no `verified:` | — | D4: `homepage` is on the same domain, so `verified:` is an **audit error**, not a courtesy |
| `livecheck` | `url :url`, `strategy :github_latest` | `releases/latest` never points at a prerelease, matching `appcast.sh`'s prerelease guard for free |
| `auto_updates true` | — | **the whole mitigation for archive design risk 11** (cask/Sparkle version divergence): Sparkle replaces the bundle in place, so without it every `brew upgrade` reports a mismatch |
| `depends_on` | `macos: ">= :tahoe"`, `arch: :arm64` | `:tahoe` → `"26"` matches `MACOSX_DEPLOYMENT_TARGET`; the arch pin makes a single flat `sha256` correct |
| `app "cellar.app"` | no `target:` | D3, and the zip root holds `cellar.app` (measured) |
| `zap trash:` | the five measured paths | obs `#7701`; `savedState` dropped |

**2 — Tap CI** (`ci.yml`, on `pull_request` + `push` to default): `brew style --cask`,
`brew audit --cask`, `brew audit --cask --online --strict` (**the gate that matters** — it downloads
the url and verifies the `sha256`), and a real `brew install --cask` → `brew uninstall --cask --zap`
round trip on `macos-26`. Gotcha carried from explore §7 (risk R9): the checkout MUST be **tapped**,
not audited as a loose path, or CI and local behaviour diverge.

**3 — The bump** (`bump.yml`, `schedule:` four times a day + `workflow_dispatch:`, `contents: write`
with the tap's own `GITHUB_TOKEN`): read `releases/latest` anonymously → **exit 0 if the cask already
declares that version** → download the asset → `shasum -a 256` → rewrite two lines → run the same
gates → commit. Downloading the published asset (rather than accepting a digest handed over from the
release job) is load-bearing: it proves *the URL a stranger will use serves exactly those bytes*.

**Why the pull model, and why the named extension point is declined.** A `curl` to a cross-repo
dispatch endpoint would technically pass `ReleasePipelineCompositionTests`' `gh == 1 / git == 0`
assertion — the Pages guard already established `curl` + bearer token as an accepted shape. It is
still wrong: it puts a cross-repo write PAT in the job that holds the Developer ID `.p12`, it grows
`workflowReferencesExactlyTheExpectedSecrets` from seven names to eight (that test is set equality *on
purpose*), and it adds a way for a successful, notarized release to report failure for a feature that
is not release-critical. A missed dispatch is lost forever; a missed scheduled run is corrected by the
next one.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `README.md` (`## Install`, ~:32-39) | Modified | brew path above the direct download; names `cellar.app` |
| `RELEASING.md` | Modified | tap section: tokens, bump workflow, zap inventory, Keychain caveat, manual fallback |
| `PRD.md` :9 / :194 / :217 | Modified | rewritten in place with reasons (D8 precedent from the pipeline slice) |
| `.github/workflows/release.yml` :175-176 | Modified | **−2 comment lines**; no step, no trigger, no secret |
| `cellarTests/CaskZapInventoryTests.swift` | **New** | the RED set (§*Strict TDD*) |
| `cellarTests/ReleasePipelineCompositionTests.swift` | Modified | +1 assertion: no cross-repo dispatch, no foreign repository named |
| `openspec/changes/m6-cask-tap/specs/release-distribution/spec.md` | **New** | ADDED-only delta, 2 requirements |
| `scripts/**`, `project.pbxproj`, `Packages/CellarCore/**`, `cellar/**.swift`, `cellar.xcscheme` | **Untouched — binding** | no product code, no project-file edit |
| `juancasanueva/homebrew-cellar` (4 files) | **New repository** | outside the reviewed diff — R7 |

## Strict TDD plan

`config.yaml` sets `strict_tdd: true` and `rules.tasks` requires RED before GREEN for every behavioural
task. Most of this change is a file in another repository; **naming the split honestly is the point,
and no test is invented to pretend otherwise.**

**Genuinely RED-able here** — runner
`xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`:

| # | File | Assertion | RED because |
|---|---|---|---|
| T1 | `cellarTests/CaskZapInventoryTests.swift` (new) | scan `cellar/` and `Packages/CellarCore/Sources/` for every `applicationSupportDirectory` / `cachesDirectory` write root and every `"Cellar/…"` literal; each discovered root MUST appear in the zap inventory documented in `RELEASING.md` | no zap inventory exists in `RELEASING.md` today |
| T2 | same | non-vacuity floor: the scan finds **at least** the five measured roots | guards T1 against an empty scan passing trivially |
| T3 | same | `RELEASING.md` names both Keychain services a zap cannot remove (`com.juancasanueva.cellar.nvd-api-key`, `com.juancasanueva.cellar.github-pat`) | not documented today |
| T4 | same | `README.md` carries `brew tap juancasanueva/cellar` and `brew install --cask home-cellar` as **whole lines**, not two loose substrings | not documented today |
| T5 | `ReleasePipelineCompositionTests.swift` | `release.yml` declares no cross-repository dispatch and names no repository other than `${{ github.repository }}` | turns D1/D2 from a decision into something that stays decided |

Precedent for the idiom is already in the tree:
`Packages/CellarCore/Tests/ReleaseNotesTests/ReleaseNotesEgressStructureTests.swift:248-253` enumerates
writers by scanning source, and `ReleasePipelineCompositionTests.swift:326-361` already asserts the
content of `RELEASING.md`. T1 composes the two, and it stays valuable forever: the day someone adds a
sixth cache file, this suite goes red **in the repository where the write was introduced**.

`swift test --package-path Packages/CellarCore` is run as a 0-line-diff regression sanity only.

**Not testable here, and the tasks MUST say so.** The cask file, `brew style`, `brew audit` and the
install round trip live in `juancasanueva/homebrew-cellar` and `cellarTests` cannot reach them:

| Proof | Class | Runner | Evidence capture |
|---|---|---|---|
| `brew style --cask` + `brew audit --cask` + `brew audit --cask --online --strict` | `ci-gate` | tap repo `ci.yml`, `macos-26` | run URL + exit status pasted into `design.md` and the verify report |
| `brew install --cask` → `brew uninstall --cask --zap` round trip | `ci-gate` | tap repo `ci.yml`, `macos-26` | same |
| `brew tap` + install on the maintainer's Mac showing `/Applications/cellar.app` at the released version | `manual-evidence` | maintainer, Homebrew 6.0.18 | verbatim transcript in `design.md` |
| `auto_updates true` prevents a `brew upgrade` fight after a Sparkle self-update | `manual-evidence` | maintainer | verbatim transcript in `design.md` |

## Delivery

`single-pr` in this repository, on `feat/m6-cask-tap` (branch-pr skill: `^(feat|…)/[a-z0-9._-]+$`).
The tap repository's commits are a **separate, sequenced work unit** in a repository this PR does not
contain.

**Order: the tap repository goes first. Recommended, and the reason is asymmetric rollback.**

1. **WU0 — create `juancasanueva/homebrew-cellar` (public).** An outward-facing action; the
   orchestrator confirms it with the maintainer before apply.
2. **WU1 — tap repo**: cask + `ci.yml` + `bump.yml` + README; green CI including the install round
   trip; maintainer's local `brew install --cask` transcript captured.
3. **WU2–WU4 — this repository**: RED tests → docs (README, `RELEASING.md`, PRD) → spec delta and the
   two-line `release.yml` deletion. One PR.

Docs-first was considered and rejected: merging a README that publishes
`brew install --cask juancasanueva/cellar/home-cellar` before the tap exists ships a **public command
that 404s** for every reader of `main` in the interval. Nothing forces the other order — T1–T5 assert
*documentation content*, never tap behaviour, so they are green with or without the tap existing.
Tap-first costs nothing and removes the only window in which the repository can lie.

**Compatibility with "one stable release per commit".** The bump workflow lives in the tap repo, pushes
only to the tap repo, never pushes a `v*` tag here, and never touches a Pages deployment — so it cannot
trigger `release.yml` and cannot reach the guard at `release.yml:56-86`. It is **idempotent on
`version`**: it exits 0 whenever the cask already declares the published version, so running it four
times a day forever produces at most one commit per published release.

### Size forecast

| Bucket | Bottom-up lines (this repo) |
|---|---|
| `cellarTests/CaskZapInventoryTests.swift` | 90–160 |
| `ReleasePipelineCompositionTests.swift` (+1 assertion) | 15–30 |
| `README.md` `## Install` | 12–20 |
| `RELEASING.md` tap section | 60–100 |
| `PRD.md` (3 lines) | 3–6 |
| `.github/workflows/release.yml` | −2 |
| **Bottom-up subtotal** | **180–320** |

The house's measured **1.9–2.3×** correction (reused, not re-derived — established across M5 slices 3–5
and reconfirmed by `m6-release-pipeline`, whose 1,502 authored lines landed mid-band) gives
**≈340–740 corrected authored lines**. Add the SDD artifacts (`proposal.md`, `design.md` **including
the four tap files quoted verbatim**, `tasks.md`, the spec delta) at ≈700–1,100, for a **PR total of
roughly 1,050–1,850 lines**.

- Against the 400 default: **High**.
- Against the governing **5,000** budget: **Low** — under 40 % at the ceiling. `single-pr` holds with
  **no `size:exception`**.

`sdd-tasks` MUST reuse the 1.9–2.3× correction and MUST emit the exact guard lines
(`Decision needed before apply: Yes|No`, `Chained PRs recommended: Yes|No`,
`400-line budget risk: Low|Medium|High`).

## Risks

Carried from explore §12 (R1–R10), plus two this proposal adds.

| # | Risk | L | Mitigation |
|---|---|---|---|
| **R1** | **The zap list rots** — every M-slice so far added a cache file under `~/Library/Caches/Cellar` | **High** | T1/T2, the source-scan test. The single most valuable artifact of this change |
| **R2** | **A zap cannot delete Keychain items**, so `…nvd-api-key` and `…github-pat` survive "uninstall everything" | **High** | Documented in both READMEs and `RELEASING.md`; asserted by T3 |
| **R3** | **Sparkle/brew version divergence** (archive design risk 11) — a self-updated app makes brew's recorded version stale | **High** | `auto_updates true` from day one; non-negotiable |
| **R4** | `~/Library/Caches/Cellar` is a **display-name** directory, not bundle-id-scoped — a broader zap claim than it looks | Med | State it in the cask and the runbook; do not silently widen it. Moving the cache under the bundle id is a follow-up migration, not this slice |
| **R5** | **Token collision** — if `homebrew/cask` ever gains `home-cellar`, the unqualified command silently resolves to theirs | Low | Measured free today (obs `#7699`); both READMEs document the fully-qualified `juancasanueva/cellar/home-cellar` form as the unambiguous one |
| **R6** | The tap could publish a version whose asset was later deleted, because it trusts `releases/latest` | Med | The bump **downloads the asset before committing**; `brew audit --online` re-verifies |
| **R7** | **Most of the change is outside the reviewed diff** | **High** | Named here; `design.md` MUST quote all four tap-repo files verbatim |
| **R8** | A second workflow **here** would be unconstrained by `release.yml`'s file-scoped invariants | Low | D1 adds no workflow here; T5 pins that. A future one must arrive with its own trigger/secret/blast-radius tests |
| **R9** | `brew audit --cask` behaves differently on an untapped path than on a real tap | Med | Tap the checkout in CI (explore §7 gotcha) |
| **R10** | The delta's cask scenarios execute in **another repository** — no prior verification class here has done that | Med | The class table names the runner per class, following `app-updates`' precedent |
| **R11** | **Creating a public repository is an outward-facing action** the SDD pipeline cannot take unilaterally | Med | WU0 is maintainer-confirmed before apply; nothing in this repo's PR depends on it |
| **R12** | The main spec's class-count table cannot be carried by an ADDED delta | Low | The delta states the hand-update obligation under *Notes for archive*; archive counts `- Verification:` lines rather than trusting the note |

## Rollback Plan

`rules.proposal` mandates one for anything touching the Xcode project file or target membership.
**`cellar.xcodeproj/project.pbxproj` is a binding 0-line diff in this change** — `cellarTests/` is a
`PBXFileSystemSynchronizedRootGroup`, so the new test file needs **no** project-file edit. The plan is
recorded anyway because the two repositories roll back differently.

**This repository** — a single `git revert` of the PR restores everything. The change adds no runtime
code, no cache file, no schema version, no Keychain item, no migration and no dependency, so a revert
orphans nothing. It restores two comment lines in `release.yml` and removes docs and tests.
Post-revert checks: `swift build --package-path Packages/CellarCore` and
`xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.

**The tap repository** — three independent levers, cheapest first: (1) `git revert` the cask commit to
pin the previous version; (2) disable `bump.yml` (a scheduled workflow, disableable from the Actions
UI) if the bump misbehaves; (3) delete the repository outright, which removes the channel entirely.

**What rollback does NOT do, and must be documented as such**: untapping or deleting the tap **does not
uninstall anything**. An already cask-installed `/Applications/cellar.app` keeps working and keeps
self-updating through Sparkle; it simply stops being brew-managed. `brew uninstall --cask` before the
tap disappears is the clean exit, and it still cannot remove the two Keychain items (R2).

## Success Criteria

- [ ] `brew tap juancasanueva/cellar && brew install --cask home-cellar` puts
      `/Applications/cellar.app` at the released version on a machine that has never seen Cellar.
- [ ] The cask's `sha256` equals the digest of the **published** asset, verified by
      `brew audit --cask --online --strict` in the tap repo's CI, not by a locally computed value.
- [ ] The cask declares `auto_updates true`, `depends_on arch: :arm64` and
      `depends_on macos: ">= :tahoe"`, and `app "cellar.app"` with no `target:`.
- [ ] `brew uninstall --cask --zap home-cellar` completes in tap CI, and the zap list is exactly the
      five measured paths — `savedState` absent.
- [ ] T1–T5 are RED before the docs land and GREEN after; `cellarTests` stays green at its current
      baseline plus the new file.
- [ ] `RELEASING.md` names both Keychain services that survive a zap, and `README.md` carries both
      brew commands as whole lines.
- [ ] `.github/workflows/release.yml` shows a **−2-line diff and nothing else**; the seven-secret set
      is unchanged; `gh == 1` / `git == 0` still holds.
- [ ] `project.pbxproj`, `scripts/**`, `Packages/CellarCore/**` and every `.swift` under `cellar/`
      show **0-line diffs**.
- [ ] The bump workflow, run twice against an unchanged `releases/latest`, produces **zero** commits
      the second time (idempotence on `version`).
- [ ] PRD :9 / :194 / :217 no longer claim `juan/tap`, `cellar`, or "still pending".

## Open Questions (non-blocking — settle at design)

1. **Cron cadence.** Explore proposes `17 */6 * * *` (four times a day). A daily run is cheaper and a
   release is not urgent; `workflow_dispatch` covers the impatient case either way.
2. **Does the tap repo get a `LICENSE`?** A cask file is a build recipe, not the app. Recommend
   mirroring this repository's licence for consistency.
3. **Does `RELEASING.md` or the tap README own the canonical uninstall instructions?** Recommend
   `RELEASING.md` owns the maintainer view and the tap README owns the user view, with the Keychain
   caveat repeated in both rather than cross-linked — the user never reads `RELEASING.md`.
