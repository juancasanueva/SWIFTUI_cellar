# Exploration: `m6-cask-tap` — `brew install --cask home-cellar` via a self-hosted tap (M6 "Ship", slice 4 of 4)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled (no reviews started).

Repository evidence read at clean `main` `bcb9d6b`. **The exploration executor has no write tool in
this harness, so the OpenSpec copy at `openspec/changes/m6-cask-tap/explore.md` must be persisted by
the orchestrator** — the same arrangement recorded verbatim in
`openspec/changes/archive/2026-08-23-m6-release-pipeline/explore.md:7-10`. Everything below marked
*measured* was read out of this repository or fetched from a public API during the phase; everything
marked *probe* is an orchestrator-owned command listed in §9, because this executor has no shell.

Prior artifacts read in full: Engram `#7673` (resume pointer), `#7659` (umbrella exploration
`sdd/m6-ship-pipeline/explore`), `#7671` (`sdd/m6-release-pipeline/archive-report`), plus
`openspec/specs/release-distribution/spec.md`, `openspec/specs/app-updates/spec.md`,
`.github/workflows/release.yml`, `scripts/release.sh`, `scripts/appcast.sh`,
`cellarTests/ReleasePipelineCompositionTests.swift`, `cellarTests/AppcastWorkflowTests.swift`,
`RELEASING.md`, `README.md`, `PRD.md`.

---

## 1. The recommendation in one page

| Question | Answer | § |
|---|---|---|
| Where does the cask live? | A **separate repository** `juancasanueva/homebrew-cellar`, file `Casks/home-cellar.rb`. It is the source of truth; nothing in this repository renders or mirrors it. | §5 |
| Where does the bump automation live? | **In the tap repository, pulling** — a workflow on `schedule:` + `workflow_dispatch:` that reads the app repo's `releases/latest` anonymously, downloads the asset, computes its `sha256`, and commits the two-line bump with the tap's own `GITHUB_TOKEN`. | §6 |
| Does `release.yml` change? | **No.** Not one line of behaviour. The named extension point at `.github/workflows/release.yml:175-176` is *declined*, and the comment is deleted as part of this change. | §6.1 |
| New secrets anywhere? | **Zero.** The pull model needs no cross-repo PAT, and no eighth secret in this repository. | §6 |
| Does the tap repo get CI? | Yes — `brew style` + `brew audit --cask --online --strict` + a real `brew install --cask` / `brew uninstall --zap` round trip on `macos-26`. | §7 |
| What is TDD-able **here**? | The zap inventory, bound by a source scan to the paths Cellar actually writes, plus the documented install commands. Both in `cellarTests/`, both genuinely RED-able. | §8 |
| Spec impact | ADDED-only delta on `release-distribution` (2 requirements). No new capability. | §8.4 |
| `app "cellar.app", target: "Home-Cellar.app"`? | **No `target:` in v1.** | §5.3 |
| Blocking decisions | Five, listed in §10. All product-level, none technical. | §10 |

**Sizing.** Authored lines in *this* repository are small — roughly 120–260 (docs, one test file, one
spec delta), 300–650 after the house 1.9–2.3× multiplier, plus SDD artifacts. The tap repository's
files (~130 lines) are **outside the reviewed diff**, which is itself a finding: see risk R7.

---

## 2. What the repository already fixes, and cannot be renegotiated here

Every one of these is *measured*, and every one is already asserted by a passing test. The cask slice
inherits them rather than choosing them.

| Fact | Where it is fixed | Test that would fail if it drifted |
|---|---|---|
| Asset URL is `https://github.com/<owner>/<repo>/releases/download/v<version>/Home-Cellar-<version>.zip` | `openspec/specs/release-distribution/spec.md:30-34` | `ci-gate` (never yet run against a delivered artifact) |
| The zip contains exactly one bundle, named **`cellar.app`**, display name **`Home-Cellar`** | same spec, `:59-65`; enforced by `scripts/release.sh:244-246` | `releaseScriptCarriesTheWholeSequence` |
| `ditto -c -k --keepParent --sequesterRsrc "$APP" "$ZIP"` — so `cellar.app` sits at the **zip root** | `scripts/release.sh:157` | same test (asserts the exact flag string) |
| arm64 only | `scripts/release.sh:122,148-149,235-237`; `ARCHS = arm64` in both app-target configs | `appTargetsPinARM64` |
| macOS floor 26.0 | `MACOSX_DEPLOYMENT_TARGET = 26.0`; appcast `<sparkle:minimumSystemVersion>26.0` | `scripts/appcast.sh:59` |
| Bundle id `com.juancasanueva.cellar` | `PRODUCT_BUNDLE_IDENTIFIER` in both app-target blocks | `appTargetBuildConfigurationBlocks` filters on the exact literal, trailing `;` included |
| Sparkle owns updates; feed `https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml` | `.github/workflows/release.yml:194` | `theSigningKeyIsBoundOnlyAsAnEnvironmentVariable`, `BundleUpdateKeysTests` |
| One stable release per commit | `release.yml:56-86` (Pages deployments guard) | `aGuardRefusesASecondFeedDeploymentFromOneCommit` |

Live facts given by the orchestrator and consistent with the above: v1.0.0 asset at
`.../v1.0.0/Home-Cellar-1.0.0.zip`, 6,448,745 bytes, `CFBundleVersion` 7, repository public, feed live.

---

## 3. The hard constraint on `release.yml`, stated exactly

`cellarTests/ReleasePipelineCompositionTests.swift:743-758` asserts, over
`.github/workflows/release.yml` only:

```swift
let gh = ReleasePipelineSources.commandInvocations(of: "gh", in: workflow)
#expect(gh.count == 1)
#expect(gh.allSatisfy { $0.hasPrefix("gh release create") })
#expect(ReleasePipelineSources.commandInvocations(of: "git", in: workflow).isEmpty)
```

Three consequences the proposal must not get wrong:

1. **A second `gh` call or any `git` call in `release.yml` fails the suite.** The extension-point
   comment at `:175-176` was written before this test existed in its current form and is now
   misleading — it promises an insertion the suite refuses.
2. **`curl` is not forbidden.** The Pages-deployment guard already reaches the GitHub API with `curl`
   and a bearer token (`release.yml:62-86`), and `theGuardReachesTheAPIWithCurlAndNotGh` pins that
   shape deliberately. So a `curl`-driven `repository_dispatch` or Contents-API write *would* pass
   `gh==1 / git==0`. **Passing the letter is not the point** — see §6.1 for why it is still the wrong
   design.
3. **The prohibitions are file-scoped.** `onlyAVersionTagTriggersTheWorkflow`,
   `workflowReferencesExactlyTheExpectedSecrets` (set equality over exactly seven names) and the two
   above all read `ReleasePipelineSources.workflowPath` — a literal. A *new* workflow file in this
   repository is unconstrained by every one of them. That is a gap, not a permission: if the proposal
   ever adds a second workflow here, it must arrive with its own contract tests (§6.1, option C).

---

## 4. What Cellar actually writes on disk — the measured zap inventory

Assembled by reading the source, not by guessing. The app is **not sandboxed**, so there is no
`~/Library/Containers/com.juancasanueva.cellar`.

| Path | Written by | Evidence |
|---|---|---|
| `~/Library/Application Support/com.juancasanueva.cellar/Catalog/` | catalog snapshot + sidecar | `Packages/CellarCore/Sources/Catalog/CatalogStore.swift:119-127` |
| `~/Library/Application Support/com.juancasanueva.cellar/Metadata/Metadata.store` (+ SwiftData `-wal`, `-shm`) | favorites, notes, history, dismissals | `Packages/CellarCore/Sources/Persistence/PersistenceContainer.swift:13-27` |
| `~/Library/Caches/Cellar/disk-usage-v1.json` | disk-usage cache | `cellar/cellarApp.swift:224` |
| `~/Library/Caches/Cellar/security-advisories-v1.json` | advisory cache | `cellarApp.swift:234` + `SecurityKit.swift:50` |
| `~/Library/Caches/Cellar/release-notes-v1.json` | release-notes cache | `cellarApp.swift:327` + `ReleaseNotes.swift:51` |
| `~/Library/Caches/Cellar/cask-charts-v1.json`, `formula-charts-v1.json` | Discover charts | `cellarApp.swift:378-399`, `CaskChartsStore.swift:51` |
| `~/Library/Caches/Cellar/cask-icons/` | Discover icon cache (incl. miss stamps) | `cellar/Casks/CaskIconLoader.swift:113-128` |
| `~/Library/Preferences/com.juancasanueva.cellar.plist` | theme, both consent grants, `updates.automaticChecksEnabled`, `casks.viewMode`, `formulae.viewMode`, `casks.recentWindow`, per-section sidebar keys — **and every Sparkle `SU*` key** | `ThemeStore.swift:18-27`, `SecurityConsentPreference.swift:27`, `ReleaseNotesConsentPreference.swift:29`, `cellar/Updates/AutomaticUpdateChecks.swift:24`, `ContentView.swift:101-116` |
| `~/Library/Caches/com.juancasanueva.cellar/` | Sparkle's own download/installer cache (`org.sparkle-project.Sparkle/`) | *probe P7* — inferred from Sparkle 2's local-cache layout, not read from this repository |
| `~/Library/HTTPStorages/com.juancasanueva.cellar*` | `URLSession` (OSV, NVD, GitHub, formulae.brew.sh, charts) | standard for any networked app; *probe P8* |
| `~/Library/Saved Application State/com.juancasanueva.cellar.savedState/` | AppKit window restoration | standard; *probe P8* |

**Three findings that matter more than the list itself:**

1. **The caches directory is `~/Library/Caches/Cellar`, not `~/Library/Caches/com.juancasanueva.cellar`.**
   Measured in five places (`cellarApp.swift:224/234/327/383`, `CaskIconLoader.swift:127`). It is a
   *display-name* directory, not a bundle-id one, and "Cellar" is also Homebrew's own word for
   `/opt/homebrew/Cellar`. A `zap trash:` on `~/Library/Caches/Cellar` is therefore a slightly broader
   claim than the bundle-id form would be. It is still correct today (Homebrew's own cache is
   `~/Library/Caches/Homebrew`), but it should be *stated* in the cask, not silently assumed.
2. **A cask `zap` cannot remove Keychain items.** Homebrew's zap stanza offers
   `trash:/delete:/rmdir:/signal:/launchctl:/quit:/pkgutil:/script:/login_item:` and nothing for the
   Keychain. Cellar creates two generic-password items —
   `com.juancasanueva.cellar.nvd-api-key` (`AdvisoryCredentialStoring.swift:54`) and
   `com.juancasanueva.cellar.github-pat` (`ReleaseNotesCredentialStoring.swift:66`). They **survive
   `brew uninstall --zap`**. That is an honest documentation obligation, not a bug: the tap README and
   `RELEASING.md` must say so and name both items.
3. **The zap list will rot.** Every M-slice so far added a cache file to `~/Library/Caches/Cellar`.
   Nothing today would notice a sixth one being added while the cask still lists five. §8.1 turns that
   into the change's one genuinely valuable RED test.

---

## 5. Cask design

### 5.1 Naming, measured

- Homebrew requires a third-party tap repository to be named `homebrew-<name>`. So
  `juancasanueva/homebrew-cellar` → `brew tap juancasanueva/cellar` →
  `brew install --cask juancasanueva/cellar/home-cellar`.
- Token derivation from the display name `Home-Cellar`: lowercase, non-alphanumeric-or-hyphen deleted,
  hyphen runs collapsed → **`home-cellar`**. The agreed token is also the *derived* token — no
  exception to justify.
- **Neither `cellar` nor `home-cellar` exists in `homebrew/cask` today.** *Measured*:
  `https://formulae.brew.sh/api/cask/cellar.json` → HTTP 404 and
  `https://formulae.brew.sh/api/cask/home-cellar.json` → HTTP 404 (that API serves `homebrew/core` +
  `homebrew/cask`). Confirm locally with probe P3 before writing the file, because a token that later
  collides with a core cask silently loses the unqualified `brew install --cask home-cellar` form to
  `homebrew/cask`.
- **The PRD is stale.** `PRD.md:194` still says self-hosted tap `juan/tap` so `brew install --cask
  cellar` works day one. Both halves are wrong against the agreed parameters, and `PRD.md:9` still ends
  "Homebrew cask still pending". Both lines are in-scope edits.

### 5.2 The stanza set, with the reason for each

```ruby
cask "home-cellar" do
  version "1.0.0"
  sha256 "<computed from the published asset, probe P1>"

  url "https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v#{version}/Home-Cellar-#{version}.zip"
  name "Cellar"
  desc "Native macOS GUI for Homebrew"
  homepage "https://github.com/juancasanueva/SWIFTUI_cellar"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :tahoe"
  depends_on arch: :arm64

  app "cellar.app"

  zap trash: [
    "~/Library/Application Support/com.juancasanueva.cellar",
    "~/Library/Caches/Cellar",
    "~/Library/Caches/com.juancasanueva.cellar",
    "~/Library/HTTPStorages/com.juancasanueva.cellar",
    "~/Library/Preferences/com.juancasanueva.cellar.plist",
    "~/Library/Saved Application State/com.juancasanueva.cellar.savedState",
  ]
end
```

| Stanza | Why this value |
|---|---|
| `url` **without** `verified:` | *Measured rule*: `brew audit` requires `verified:` only when the url's domain differs from the homepage's, and raises **"the `verified` parameter is unnecessary"** when they match. With `homepage` on `github.com`, adding `verified:` is an audit **error**, not a courtesy. If §10-D4 moves the homepage to the vercel landing page, `verified: "github.com/juancasanueva/SWIFTUI_cellar/"` becomes *mandatory*. The two decisions are coupled. |
| `desc` | Must be < 80 chars and must not start with the app name or an article. |
| `livecheck :github_latest` | Reads the repo's `releases/latest`, which GitHub never points at a prerelease — so the `v*-rc.*` tags the pipeline can publish are skipped for free, matching `appcast.sh`'s prerelease guard. |
| `auto_updates true` | Sparkle replaces the bundle in place, so `brew` would otherwise report a version mismatch on every `brew upgrade`. This is design risk 11 (cask/Sparkle divergence) from the release-pipeline archive, and this one line is its whole mitigation. It also matches Homebrew's own rule — the app has a real "Check for Updates…" menu item (`app-updates` spec, "An explicit update check is always reachable"). |
| `depends_on macos: ">= :tahoe"` | *Measured*: `:tahoe` → `"26"` in `Homebrew/brew` `Library/Homebrew/macos_version.rb`. Matches `MACOSX_DEPLOYMENT_TARGET = 26.0`. |
| `depends_on arch: :arm64` | Matches the `ARCHS = arm64` pin. With this present, a single flat `sha256` is correct — no `on_arm` block. |
| `app "cellar.app"` | The zip root holds `cellar.app` (`--keepParent`). See §5.3. |

### 5.3 `target: "Home-Cellar.app"` — recommend **no**

The argument for it is real: `/Applications/cellar.app` is a lowercase, generic name next to
`Home-Cellar` in the menu bar and the About window.

Three arguments against, and they win for v1:

1. **It splits the two channels.** README tells direct-download users to drag `cellar.app`
   (`README.md:34-35`), and `release-distribution` *specifies* the bundle name inside the zip. A cask
   user would end up with `/Applications/Home-Cellar.app` and a drag user with
   `/Applications/cellar.app` — two names for one app, and `brew uninstall --cask` would silently
   leave a drag-installed copy behind.
2. **It interacts with Sparkle in a way nobody here has measured.** Sparkle installs the update over
   the *host bundle's own path*, so a renamed install stays renamed — probably. "Probably" is not a
   basis for renaming the thing that self-replaces itself.
3. **The real fix is a different change.** Renaming `PRODUCT_NAME` so the bundle is `Home-Cellar.app`
   everywhere touches `project.pbxproj`, four `release.sh` gates, the `release-distribution` spec's
   bundle-name scenario, and the update continuity of every already-installed 1.0.0 copy. That is its
   own slice with its own rollback plan (`rules.proposal` demands one for pbxproj), and it must not be
   smuggled in behind a cask stanza.

Recommendation: ship `app "cellar.app"`, record the naming inconsistency as a follow-up, and let the
tap README say plainly that the installed bundle is `cellar.app`.

---

## 6. Where the bump automation lives — the central decision

| # | Approach | Secrets needed | Failure mode | Effort | Verdict |
|---|---|---|---|---|---|
| **A** | Tap-repo workflow on cross-repo `repository_dispatch`, sent from `release.yml` with `curl` | **1 new**: a fine-grained PAT with `contents:write` on the tap, stored in *this* repo | Dispatch fires before the asset is fully propagated; a failed dispatch is silent; PAT expiry breaks it months later with no signal | Medium | No — see §6.1 |
| **B** | **Tap-repo workflow on `schedule:` + `workflow_dispatch:`, pulling from the app repo's `releases/latest`** | **0** — the tap's own `GITHUB_TOKEN` commits to its own repo | Bump is late by at most the cron interval; `workflow_dispatch` makes it immediate on demand | Low | **Recommended** |
| C | A **second workflow in this repo** on `release: published` that clones the tap and pushes | 1 new PAT, sitting in the repo that holds the Developer ID cert | Widens this repo's automation surface; needs its own trigger/secret/blast-radius tests (§3.3) that do not exist yet | Medium-High | No |
| D | Manual runbook step (`RELEASING.md`: after the release, edit two lines in the tap) | 0 | Human forgets; the tap silently serves an old version while the appcast serves the new one | Low | No — but keep it documented as the fallback for when B's CI is down |

### 6.1 Why the named extension point is declined

`.github/workflows/release.yml:175-176` says the cask bump "inserts here without restructuring the
job". It can, technically: a `curl` to `repos/juancasanueva/homebrew-cellar/dispatches` passes
`gh==1 / git==0` because the guard step already establishes `curl` + bearer token as an accepted shape.
Four reasons not to:

1. **The credential asymmetry is the wrong trade.** Adding a cross-repo write PAT to the job that holds
   the Developer ID `.p12` and the App Store Connect key widens the blast radius of the repository's
   most sensitive job for a feature that is not on the critical path.
2. **`workflowReferencesExactlyTheExpectedSecrets` would go from seven names to eight.** That test is
   set equality *on purpose* — "A release pipeline that quietly grows a new credential is a release
   pipeline whose blast radius nobody re-reviewed." Growing it is allowed, but it should be paid for by
   something that needs it. The cask does not.
3. **The cask bump is not release-critical.** If it fails, the zip still downloads and Sparkle still
   updates every installed copy. Putting a non-critical action *after* `gh release create` in a job
   that has already spent an Apple notarization round trip only adds a way for a successful release to
   report failure.
4. **The pull model is self-healing.** A missed dispatch is lost forever; a missed scheduled run is
   corrected by the next one, and the run is idempotent by construction (it compares the published tag
   to the cask's current `version` and exits 0 when they match).

**Therefore this change deletes the extension-point comment** rather than leaving a promise the design
declined. That deletion is two comment lines in `release.yml` and touches no step — it does not disturb
any step-index assertion in `AppcastWorkflowTests` or `ReleasePipelineCompositionTests`, both of which
split on `- name:` boundaries.

### 6.2 Shape of the recommended tap workflow

```
on:
  schedule: [{ cron: "17 */6 * * *" }]     # four times a day
  workflow_dispatch:                       # the maintainer's immediate path
permissions: { contents: write }
runs-on: macos-26
steps:
  1. read https://api.github.com/repos/juancasanueva/SWIFTUI_cellar/releases/latest  (anonymous curl)
  2. TAG=$(… .tag_name); VERSION=${TAG#v}
  3. exit 0 if the cask already declares VERSION            # idempotent, the whole point
  4. curl -fsSLO the asset at the documented URL            # also proves it is anonymously reachable
  5. SHA=$(shasum -a 256 … )
  6. rewrite the two lines, brew style + brew audit (§7)
  7. commit "chore(cask): home-cellar <version>" with the run's own GITHUB_TOKEN
```

Step 4 is load-bearing and is why the checksum is *not* passed from the release job: computing the
digest from the **published** asset proves the URL a stranger will use serves exactly those bytes.
A digest computed on the runner's local build proves only that the build was built.

---

## 7. Tap-repo CI — the minimal honest gate

| Gate | Command | What it actually proves | Keep? |
|---|---|---|---|
| Style | `brew style --cask Casks/home-cellar.rb` | RuboCop-clean Ruby, house stanza ordering | Yes — free |
| Audit, offline | `brew audit --cask Casks/home-cellar.rb` | stanza set, token derivation, `depends_on` symbols resolve | Yes |
| Audit, online + strict | `brew audit --cask --online --strict Casks/home-cellar.rb` | **downloads the url and verifies the sha256** — catches a wrong checksum before a user does; checks `homepage` reachability and the `verified:` rule of §5.2 | **Yes — this is the gate that matters** |
| Install round trip | `brew install --cask …` then `brew uninstall --cask --zap …` | the cask genuinely installs `cellar.app` into `/Applications` on a clean machine, and the zap paths are syntactically acceptable | Yes — the only end-to-end proof, ~7 MB and a couple of runner minutes, free on a public repo |
| `--new` | `brew audit --cask --new` | rules written for *submissions to `homebrew/cask`* | **No** — it enforces homebrew-cask house rules that do not apply to a third-party tap, and would fail on things this cask is entitled to do |

**Gotcha for the proposal**: `brew audit`/`brew style` need the tap to be *tapped*, not merely checked
out. The workflow must either `brew tap juancasanueva/cellar "$GITHUB_WORKSPACE"` or check out into
`$(brew --repository)/Library/Taps/juancasanueva/homebrew-cellar`. Auditing a loose `.rb` path in a
scratch directory behaves differently and is a known source of "works locally, fails in CI".

Triggers: `pull_request`, `push` to the default branch, and — because the bump workflow commits
directly — the bump workflow should run the same gates *before* it commits, so a bad checksum never
lands.

---

## 8. Strict TDD: what is honestly testable, and where

`openspec/config.yaml` sets `strict_tdd: true` and `rules.tasks` requires "RED before GREEN for every
behavioral task". Most of this change is a file in another repository. Naming the split honestly is the
point.

### 8.1 The one genuinely valuable RED test — `cellarTests/CaskZapInventoryTests.swift` (new)

Precedent is exact and already in the tree:
`Packages/CellarCore/Tests/ReleaseNotesTests/ReleaseNotesEgressStructureTests.swift:248-253` already
enumerates *writers* by scanning source, and
`cellarTests/ReleasePipelineCompositionTests.swift:326-361` already asserts the **content of
`RELEASING.md`**. Compose the two:

> Scan `cellar/` and `Packages/CellarCore/Sources/` for every `applicationSupportDirectory` /
> `cachesDirectory` write root and every `"Cellar/…"` path literal, and assert each discovered root
> appears in the zap inventory documented in `RELEASING.md`. Then assert non-vacuity: the scan found at
> least the five roots of §4.

RED on arrival is genuine — no zap inventory exists in `RELEASING.md` today, so the test fails before
the doc is written. It stays valuable forever: the day someone adds `~/Library/Caches/Cellar/foo-v1.json`
without touching the cask, this suite goes red in *this* repository, which is where the write was
introduced. That is the only place the drift can be caught early.

### 8.2 Documentation-contract tests (same file or `ReleaseMetadataTests`)

- README carries the exact two commands (`brew tap juancasanueva/cellar` and
  `brew install --cask home-cellar`), asserted as **whole lines**, not two loose substrings — the
  reason `runbookRecordsTheVersionPolicyAndItsOverride` gives: "a reader who has to assemble the
  command from two paragraphs has not been given a command".
- `RELEASING.md` names both Keychain services that a zap **cannot** remove (§4 finding 2).

### 8.3 Workflow-invariant test (only if the design keeps `release.yml` untouched — it does)

Add one assertion to `ReleasePipelineCompositionTests`: the workflow declares **no cross-repository
dispatch and no second repository target** — i.e. `release.yml` contains no `dispatches` and names no
repository other than `${{ github.repository }}`. This is what turns "we decided not to insert here"
into something that stays decided.

### 8.4 Spec impact — ADDED-only delta on `release-distribution`

No new capability. `release-distribution` already owns "what must be true of a delivered build"; a tap
is a second channel for the same delivered build. Proposed delta, 2 requirements:

| Requirement | Scenarios | Class |
|---|---|---|
| "The delivered build is installable through the project's Homebrew tap" | tap + install produces `/Applications/cellar.app` at the released version; the cask declares `auto_updates true` so `brew upgrade` never fights Sparkle; a prerelease tag never becomes a cask version | `manual-evidence` / `ci-gate`, both executing in the **tap repository** |
| "Uninstalling states exactly what it removes and what it cannot" | the documented zap inventory covers every path the app writes; the two Keychain items are documented as surviving | `unit` (both — §8.1 / §8.2) |

The verification-class table must name the exact runner for each class, because the `manual-evidence`
and `ci-gate` scenarios execute in a *different repository* — a first for this project, and something
`app-updates`' own class table sets the precedent for stating plainly.

### 8.5 Not testable here, and the proposal must say so

The cask file itself, `brew audit`, `brew style`, and the install round trip all live in the other
repository. `cellarTests` cannot reach them. Do not invent a test that pretends otherwise.

**Exact runner commands for the app-repo half**:

```sh
xcodebuild test -project cellar.xcodeproj -scheme cellar \
  -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
swift test --package-path Packages/CellarCore    # unaffected — no CellarCore change expected
```

---

## 9. Orchestrator probes (this executor has no shell)

| # | Command | Why it gates the proposal |
|---|---|---|
| **P1** | `curl -fsSLO https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v1.0.0/Home-Cellar-1.0.0.zip && shasum -a 256 Home-Cellar-1.0.0.zip` | the cask's `sha256`, computed from the **published** asset; also proves anonymous reachability |
| **P2** | `unzip -l Home-Cellar-1.0.0.zip \| head -20` | confirms `cellar.app/` at the zip root and shows whether `--sequesterRsrc` left a `__MACOSX/` sibling (harmless to Homebrew, but the `app` stanza must be written knowing) |
| **P3** | `brew info --cask cellar; brew info --cask home-cellar` | local confirmation of the measured 404s — expect "No available cask" for both |
| **P4** | `brew --version; brew audit --help \| rg -- '--cask'; brew style --help \| head -3` | audit/style availability and Homebrew version on the dev machine |
| **P5** | `gh api repos/juancasanueva/homebrew-cellar --jq .name` | expect **404** — the tap repository does not exist yet and creating it is a task-0 step (`gh repo create juancasanueva/homebrew-cellar --public`) |
| **P6** | `gh api repos/juancasanueva/SWIFTUI_cellar/releases/latest --jq '.tag_name, (.assets[] \| .browser_download_url, .size)'` | confirms the exact URL shape the `livecheck`/bump workflow will parse |
| **P7** | `defaults read com.juancasanueva.cellar \| head -40; ls -la ~/Library/Caches/com.juancasanueva.cellar` | grounds the Sparkle half of the zap list in real writes rather than in framework documentation |
| **P8** | `ls -ld ~/Library/Caches/Cellar ~/Library/Application\ Support/com.juancasanueva.cellar ~/Library/HTTPStorages/com.juancasanueva.cellar* ~/Library/Saved\ Application\ State/com.juancasanueva.cellar.savedState` | measures the full inventory on a machine that has actually run Cellar; anything absent gets dropped from the cask rather than guessed into it |

P1, P2, P5 gate the proposal. P3, P4, P6 can run during design. P7 and P8 must run **before** the zap
stanza is written — §8.1's test compares documentation against the source scan, but only a real machine
proves the Sparkle and system-owned paths.

---

## 10. Product decisions required before the proposal

| # | Decision | Recommendation |
|---|---|---|
| **D1** | Bump mechanism — §6 A/B/C/D | **B** (tap-repo pull, scheduled + `workflow_dispatch`, zero new secrets) |
| **D2** | Delete the `release.yml` extension-point comment, leaving `release.yml` otherwise untouched? | **Yes** — a declined promise in a file is worse than no comment |
| **D3** | `app "cellar.app"` with no `target:`? | **Yes** for v1; log the `Home-Cellar.app` rename as its own slice |
| **D4** | `homepage` — the GitHub repo, or the vercel landing page? | **The GitHub repo**, until a landing page exists. Moving it later makes `verified:` mandatory (§5.2) and is a one-line follow-up |
| **D5** | Does the tap repo carry its own README with install/uninstall/Keychain caveats? | **Yes** — it is the page `brew tap` users land on |

---

## 11. Files this change touches

**In this repository:**

| Path | Change | Note |
|---|---|---|
| `README.md` (`## Install`, ~:32-39) | Modified | Add the brew path *above* the direct download; state that the installed bundle is `cellar.app` |
| `RELEASING.md` | Modified | New section: the tap, the bump workflow, the zap inventory, the two Keychain items a zap cannot remove, and the manual fallback (§6 option D) |
| `PRD.md:9`, `PRD.md:194`, `PRD.md:217` | Modified | `juan/tap` → `juancasanueva/cellar`; `cellar` → `home-cellar`; "still pending" → shipped; M6 milestone line gains slice 4 |
| `.github/workflows/release.yml:175-176` | Modified | Delete the declined extension-point comment (2 lines, no step) |
| `openspec/changes/m6-cask-tap/specs/release-distribution/spec.md` | New | ADDED-only delta, 2 requirements (§8.4) |
| `cellarTests/CaskZapInventoryTests.swift` | New | §8.1 + §8.2 |
| `cellarTests/ReleasePipelineCompositionTests.swift` | Modified | §8.3, one assertion |

**Not touched (a binding):** `scripts/release.sh`, `scripts/appcast.sh`, `cellar.xcodeproj/project.pbxproj`,
`Packages/CellarCore/**`, every `cellar/` source file. This change adds no Swift product code at all.

**In `juancasanueva/homebrew-cellar` (new repository, outside the reviewed diff):**
`Casks/home-cellar.rb`, `.github/workflows/ci.yml`, `.github/workflows/bump.yml`, `README.md`.

---

## 12. Risks

| # | Risk | Mitigation |
|---|---|---|
| **R1** | **The zap list rots.** Every M-slice so far added a cache file under `~/Library/Caches/Cellar`. | §8.1's source-scan test — the single most valuable artifact of this change. |
| **R2** | **A zap cannot delete Keychain items**, so `com.juancasanueva.cellar.nvd-api-key` and `com.juancasanueva.cellar.github-pat` survive an "uninstall everything". | Document it in both READMEs and `RELEASING.md`; assert the documentation exists (§8.2). |
| **R3** | **Sparkle/brew version divergence** — a self-updated app makes `brew`'s recorded version stale (archive design risk 11). | `auto_updates true`, from day one. It is why the stanza is non-negotiable. |
| **R4** | **`~/Library/Caches/Cellar` is a display-name directory**, not bundle-id-scoped — a broader zap claim than it looks. | State it in the cask and the runbook; do not silently widen it. Consider a follow-up that moves the cache under the bundle id (a migration, not this slice). |
| **R5** | **Token collision.** If `homebrew/cask` ever gains `home-cellar`, the unqualified install command silently resolves to theirs. | P3 now; document the fully-qualified `juancasanueva/cellar/home-cellar` form as the unambiguous one. |
| **R6** | **A tap bump can publish a version whose asset was later deleted**, because the tap trusts `releases/latest`. | The bump downloads the asset before committing (§6.2 step 4); `brew audit --online` re-verifies. |
| **R7** | **Most of the change is outside the reviewed diff.** The cask, its CI and its bump workflow never appear in this repository's PR, so the 5,000-line budget and any review sees only the documentation half. | Name it explicitly in the proposal; require the tap repo's four files to be quoted verbatim in `design.md` so a reviewer can read them without leaving the PR. |
| **R8** | **A second workflow in this repo would be unconstrained** by `release.yml`'s file-scoped invariants (§3.3). | Option B adds no workflow here. If a later change adds one, it must arrive with its own trigger/secret/blast-radius tests. |
| **R9** | **`brew audit --cask` behaves differently on an untapped path** than on a real tap. | Tap the checkout in CI (§7 gotcha). |
| **R10** | **The `release-distribution` delta's cask scenarios execute in another repository**, which no prior verification class in this project has done. | The delta's verification-class table must name the runner per class, following `app-updates`' precedent. |

---

## 13. Ready for proposal

**Yes**, after D1–D5 (§10) and probes P1, P2, P5 (§9).

Nothing here is architecturally open. The asset URL, the bundle name, the arch pin, the OS floor and
the update mechanism are all already fixed by the promoted `release-distribution` spec and by passing
tests, so the cask is a *consumer* of decided facts rather than an author of new ones. The two genuinely
open questions are both product-shaped: where the bump runs (§6, recommend B) and whether the installed
bundle keeps its lowercase name (§5.3, recommend yes for v1).

The change's real engineering content is not the Ruby file — it is §8.1, the test that stops the
uninstall story from quietly becoming a lie.
