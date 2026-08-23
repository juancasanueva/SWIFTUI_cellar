# Design: Homebrew Tap and Cask (`m6-cask-tap`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled (no reviews started).

Inputs: `proposal.md` (Engram obs `#7703`, **D1–D5 binding**), `explore.md` (obs `#7700`),
orchestrator probes obs `#7699` and `#7701`, `specs/release-distribution/spec.md` (this change's
ADDED-only delta, **2 requirements / 9 scenarios**), and the inherited contract at `RELEASING.md` §7.

`next_recommended: sdd-tasks`

> **Size note.** This document exceeds the 800-word default design budget by explicit launch-brief
> instruction: risk **R7** requires all four tap-repository files to be quoted verbatim here, because
> they never appear in this repository's reviewed diff. Density is preserved by tables; nothing is
> padded. The archived `m6-release-pipeline` design carries the same note for the same reason.

## Technical Approach

Two repositories, split by **who owns the failure**, not by convenience:

- **`juancasanueva/homebrew-cellar`** (new, public) owns the cask, its gates and its currency. Four
  files, quoted complete in *§ The tap repository* below.
- **This repository** owns the *documentation* of the channel and the *tests that keep it honest*. It
  gains no workflow, no secret, no Swift product code, and no behavioural change to `release.yml`.

The cask is a **consumer of already-decided facts**. The asset URL, the `cellar.app` bundle name, the
arm64 pin and the macOS 26.0 floor are fixed by the promoted `release-distribution` spec and by passing
tests; the cask re-derives none of them. Its only authored values are the two the bump workflow
rewrites — `version` and `sha256` — and both are computed from the **published** bytes.

`rules.design`'s "keep all logic in `Packages/CellarCore`" and "protocol boundaries for every external
dependency" clauses have **no surface here**: this change adds no Swift product code at all. The
external dependency in this slice is Homebrew's own tooling, and its boundary is the tap CI's command
set. "No `#available` branches" and "document actor isolation" are likewise `N/A` — the only new Swift
is four `nonisolated` source-scanning tests.

The engineering content of this change is not the Ruby file. It is **T1/T2**: the test that stops the
uninstall story from quietly becoming a lie.

## Architecture Decisions

| # | Decision | Rejected alternative | Rationale |
|---|---|---|---|
| **DD-1** | The bump lives in the **tap** repository and **pulls** `releases/latest` on a schedule | A `repository_dispatch` sent from `release.yml`; a second workflow here; manual-only | D1. Zero new secrets; a missed dispatch is lost forever while a missed scheduled run is corrected by the next one. A cross-repo write PAT beside the Developer ID `.p12` is the wrong trade for a non-release-critical feature |
| **DD-2** | The declined extension-point comment at `release.yml:175-176` is **deleted**, and its deletion is **test-driven** by T5 | Leaving a promise the design declined; deleting it without a test | D2. A comment inviting an insertion the suite refuses is worse than no comment. Asserting its absence is what makes the deletion RED-first rather than incidental (see *§ Strict TDD*) |
| **DD-3** | `app "cellar.app"`, no `target:` | `target: "Home-Cellar.app"` | D3. A rename splits the two install channels and perturbs Sparkle's in-place self-replacement, which nobody here has measured. Logged as its own slice |
| **DD-4** | `homepage` is the GitHub repository, so **no `verified:`** | A landing-page homepage | D4. `brew audit` raises *"the `verified` parameter is unnecessary"* when the url and homepage domains match — adding it would be an audit **error**, not a courtesy |
| **DD-5** | Two `name` stanzas: `name "Home-Cellar"` first, `name "Cellar"` second | A single `name "Cellar"` | Token derivation is checked against the **first** `name`: `Home-Cellar` → lowercase, hyphen-collapse → `home-cellar`, which is exactly the agreed token. `Cellar` alone would derive `cellar` and leave the token needing an exception it does not need |
| **DD-6** | The Keychain caveat is **documentation only** — no `caveats` stanza in the cask | A `caveats` stanza | Proposal default for open question 2. `caveats` prints on **every** install and upgrade, turning a one-time uninstall fact into permanent noise. It belongs where a user reads it when uninstalling: both READMEs and `RELEASING.md` |
| **DD-7** | Tap CI registers the checkout as a real tap with **`cp -R`** into `$(brew --repository)/Library/Taps/juancasanueva/homebrew-cellar` | `brew tap juancasanueva/cellar "$GITHUB_WORKSPACE/…"` (git-clones the checkout); a symlink; auditing the loose `.rb` path | R9. `brew tap <path>` **clones**, and a clone resolves the source repository's HEAD — which `actions/checkout` leaves **detached** — so CI would audit a second git resolution instead of the exact bytes under review. A copy is byte-identical and has no symlink-traversal semantics to depend on. A loose path is the known "passes locally, fails for a user" trap |
| **DD-8** | The bump runs **`brew style` + both audits before it commits** | Commit, then let `ci.yml` catch it | A push made with `GITHUB_TOKEN` **does not trigger other workflows** (GitHub's loop prevention), so `ci.yml` would never run on a bump commit. Gating before the commit is therefore not belt-and-braces — it is the *only* gate that bump commit ever gets |
| **DD-9** | T1's source scan discovers **2** roots, not 5. The documented inventory is split into `source` and `framework` classes, and each class is asserted differently | Asserting the scan finds all five measured paths | **Measured**: only `~/Library/Caches/Cellar` and `~/Library/Application Support/com.juancasanueva.cellar` are written by shipped source. The Sparkle cache, `HTTPStorages` and the preferences plist are written by *frameworks* and appear in no source file — a scan cannot find them, and a test demanding it would be unsatisfiable. See *§ Reconciling T2 with the spec* |
| **DD-10** | The scan classifies each search-domain use as **appending** or **pass-through**, and every pass-through must construct `HomebrewRoots(` | Treating every `.cachesDirectory` use as a Cellar write root | Five of the ten `.cachesDirectory` uses hand the bare directory to `HomebrewRoots`, whose cache root is `~/Library/Caches/**Homebrew**`. A naive scan would demand Homebrew's own download cache enter a `zap trash:` list — it would delete every user's bottle cache on uninstall. The classification is what makes that structurally impossible |
| **DD-11** | The zap inventory lives in `RELEASING.md` inside a fenced block with the info string `zap-inventory`, one `<class><space><path>` row per line | A prose list; a markdown table | A test must parse it deterministically. The class token contains no spaces, so splitting on the first whitespace run is unambiguous even though `Application Support` does not |
| **DD-12** | `RELEASING.md` §7's inherited-contract paragraph is **corrected** in the same change | Leaving it claiming an extension point the file no longer carries | Not in the proposal's file list, found at design: `RELEASING.md:309-311` states the cask bump "inserts after it without restructuring the job". D2 deletes that point, so the sentence becomes false the moment the workflow changes |

## Data Flow

    THIS REPOSITORY                              juancasanueva/homebrew-cellar
    ───────────────                              ─────────────────────────────
    git tag vX.Y.Z ──► release.yml
                          ├─ gh release create  ──►  releases/latest ─┐
                          └─ appcast ──► Pages                        │
                                                                      │  anonymous
                                                          bump.yml ◄──┘  read, no token
       (no dispatch, no PAT, no eighth secret)                 │
                                                               ├─ exit 0 if version unchanged
                                                               ├─ curl the PUBLISHED asset
                                                               ├─ shasum -a 256
                                                               ├─ rewrite version + sha256
                                                               ├─ style + audit --online --strict
                                                               └─ commit chore(cask): …
                                                                        │
                                                                        ▼
                                                          Casks/home-cellar.rb
                                                                        │
                        brew tap juancasanueva/cellar ◄─────────────────┘
                        brew install --cask home-cellar ──► /Applications/cellar.app
                                                                        │
                                                          Sparkle updates it in place
                                                          (auto_updates true, so brew
                                                           never fights the newer copy)

    cellarTests (this repository, passes with or without the tap existing)
       CaskZapInventoryTests ── scans cellar/ + CellarCore/Sources ──► write roots
                             └─ compares against the RELEASING.md zap-inventory block

## File Changes

### This repository — the reviewed PR

| File | Action | Description |
|---|---|---|
| `cellarTests/CaskZapInventoryTests.swift` | **Create** | T1–T4. Self-contained `#filePath` anchor, per the house single-file-rollback convention |
| `cellarTests/ReleasePipelineCompositionTests.swift` | Modify | +1 test (T5). Reuses `ReleasePipelineSources`; adds no helper API |
| `README.md` (`## Install`, ~:32-39) | Modify | brew path above the direct download; whole-line commands; `cellar.app`; uninstall + Keychain caveat |
| `RELEASING.md` §7 (~:309-311) | Modify | DD-12 — the extension point is declined, not occupied |
| `RELEASING.md` §8 (new), §8 → §9 | Modify | Tap section; `Troubleshooting` renumbers 8 → 9 (one heading line) |
| `PRD.md` :9, :194, :217 | Modify | Exact replacement text below |
| `.github/workflows/release.yml` :175-176 | Modify | **−2 comment lines.** No step, trigger, secret or `- name:` boundary touched |
| `LICENSE` | **Create** | MIT (maintainer decision 2026-08-23, DD-13). The repository had no licence file; the tap README's "same licence as the app" is only true once this exists. Copyright line: `Copyright (c) 2026 Juan Casanueva` |
| `openspec/changes/m6-cask-tap/specs/release-distribution/spec.md` | Created by `sdd-spec` | ADDED-only delta |

### `juancasanueva/homebrew-cellar` — outside the reviewed diff (R7)

| File | Action | Description |
|---|---|---|
| `Casks/home-cellar.rb` | Create | The cask |
| `.github/workflows/ci.yml` | Create | style + both audits + install/zap round trip on `macos-26` |
| `.github/workflows/bump.yml` | Create | Scheduled pull-based currency, idempotent on `version` |
| `README.md` | Create | D5 — the page `brew tap` users land on |
| `LICENSE` | Create | MIT — identical text to the app repository's new `LICENSE` (DD-13) |

---

# The tap repository — all four files, verbatim

**These files are ready to commit as-is.** They are quoted complete because they never appear in this
repository's PR diff, which is risk R7 and the reason this section exists.

## 1. `Casks/home-cellar.rb`

```ruby
cask "home-cellar" do
  version "1.0.0"
  sha256 "078a0b5a49fa6e75f885796de1764f36efe72e9db8564fb140bf2112fd6793b6"

  url "https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v#{version}/Home-Cellar-#{version}.zip"
  name "Home-Cellar"
  name "Cellar"
  desc "Native GUI for the Homebrew package manager"
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
  ]
end
```

| Stanza | Why exactly this |
|---|---|
| `version` / `sha256` | The measured digest of the **published** v1.0.0 asset (obs `#7699`, 6,448,745 bytes). These are the only two lines `bump.yml` ever rewrites |
| `url` with `#{version}` | Inherited verbatim from `release-distribution`. Carrying no literal version is what makes the rewrite rules of `bump.yml` unambiguous — there is no second line either substitution could match |
| no `verified:` | DD-4 |
| `name` ×2 | DD-5 — `Home-Cellar` derives the token; `Cellar` is the product name users search for |
| `desc` | 43 characters, does not start with an article or the token, and names no platform — the three things `brew audit` checks |
| `livecheck :github_latest` | `releases/latest` never points at a prerelease, so the `v*-rc.*` tags this pipeline can publish are skipped for free — the same guard `appcast.sh` applies to the feed |
| `auto_updates true` | **The whole mitigation for archive design risk 11.** Sparkle replaces the bundle in place; without this, every `brew upgrade` reports a mismatch and offers to reinstall over a newer app |
| `depends_on macos: ">= :tahoe"` | `:tahoe` → `"26"`, matching `MACOSX_DEPLOYMENT_TARGET = 26.0` |
| `depends_on arch: :arm64` | Matches the `ARCHS = arm64` pin, and is what makes a single flat `sha256` correct with no `on_arm` block |
| `app "cellar.app"` | DD-3, and `cellar.app` sits at the zip root (`ditto --keepParent`, measured) |
| `zap trash:` | The **five measured** paths (obs `#7701`). `…savedState` is dropped: explore §9's rule is that what a real machine does not show is removed, never guessed in |
| no `caveats` | DD-6 |

Stanza order follows Homebrew's canonical sequence (`version`, `sha256`, `url`, `name`, `desc`,
`homepage`, `livecheck`, `auto_updates`, `depends_on`, artifacts, `zap`), and the multiline array
carries a trailing comma, both of which `brew style` enforces.

## 2. `.github/workflows/ci.yml`

```yaml
name: CI

# Every gate this tap has. A cask that installs is the only proof that a cask
# installs, so the round trip runs on a real runner rather than being argued for
# in a review.

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  cask:
    runs-on: macos-26
    timeout-minutes: 30
    steps:
      - name: Check out the tap
        uses: actions/checkout@v5
        with:
          path: homebrew-cellar

      - name: Record the runner image
        run: |
          set -euo pipefail
          sw_vers
          brew --version
          uname -m
          # `depends_on arch: :arm64` makes the install step unreachable on an
          # Intel image, and an unreachable gate that reports success is worse
          # than no gate. So the architecture is asserted, not assumed.
          test "$(uname -m)" = "arm64"

      - name: Register the checkout as a real tap
        run: |
          set -euo pipefail
          # `brew style` and `brew audit` behave differently against a loose
          # `.rb` path than against a tapped cask, and the loose path is the
          # known source of "passes in CI, fails for a user".
          #
          # A copy, not `brew tap juancasanueva/cellar "$GITHUB_WORKSPACE/..."`:
          # that form git-clones the checkout, and a clone resolves the source's
          # HEAD, which `actions/checkout` leaves detached. CI would then audit a
          # second resolution of the commit instead of the exact bytes under
          # review.
          TAPS="$(brew --repository)/Library/Taps/juancasanueva"
          mkdir -p "$TAPS"
          cp -R "$GITHUB_WORKSPACE/homebrew-cellar" "$TAPS/homebrew-cellar"
          brew tap

      - name: Style
        run: brew style juancasanueva/cellar

      - name: Audit, offline
        run: brew audit --cask juancasanueva/cellar/home-cellar

      - name: Audit, online and strict
        # The gate that matters: it downloads the url and verifies the declared
        # sha256 against the bytes GitHub actually serves, which is the one
        # failure a user would otherwise meet first.
        #
        # `--new` is deliberately absent. It enforces homebrew/cask *submission*
        # house rules that a third-party tap is entitled to ignore, and this tap
        # is the channel precisely because submission is deferred.
        run: brew audit --cask --online --strict juancasanueva/cellar/home-cellar

      - name: Install
        run: |
          set -euo pipefail
          brew install --cask juancasanueva/cellar/home-cellar
          test -d "/Applications/cellar.app"
          /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "/Applications/cellar.app/Contents/Info.plist"

      - name: Uninstall with a zap
        run: |
          set -euo pipefail
          # The zap paths are only syntactically exercised here — a runner has
          # never launched the app, so it has nothing to delete. What this
          # proves is that the stanza is well-formed and that the uninstall
          # completes, not that the inventory is complete. Completeness is
          # bound to the source by CaskZapInventoryTests in the app repository.
          brew uninstall --cask --zap juancasanueva/cellar/home-cellar
          test ! -d "/Applications/cellar.app"
```

## 3. `.github/workflows/bump.yml`

```yaml
name: Bump

# Keeps the cask current by pulling, never by being pushed to. The app
# repository sends nothing, holds no credential for this one, and cannot fail
# because of this workflow: a missed run costs at most one cron interval,
# because the next run recomputes the same answer from scratch.

on:
  schedule:
    - cron: "17 */6 * * *"      # four times a day
  workflow_dispatch:            # the maintainer's immediate path

permissions:
  contents: write

concurrency:
  group: bump
  cancel-in-progress: false

jobs:
  bump:
    runs-on: macos-26
    timeout-minutes: 30
    steps:
      - name: Check out the default branch
        uses: actions/checkout@v5
        with:
          ref: main
          path: homebrew-cellar

      - name: Read the latest published release
        id: release
        run: |
          set -euo pipefail
          # Anonymous on purpose: this reads a public release of a public
          # repository, so it needs no token, no secret, and no cross-repository
          # grant anywhere.
          TAG="$(curl -fsSL \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2022-11-28" \
            "https://api.github.com/repos/juancasanueva/SWIFTUI_cellar/releases/latest" \
            | jq -r '.tag_name // ""')"
          test -n "$TAG"
          VERSION="${TAG#v}"
          # `releases/latest` never points at a prerelease. This is belt and
          # braces: a hyphenated version must never become a cask version.
          case "$VERSION" in
            *-*) echo "::error::refusing to bump to prerelease ${VERSION}"; exit 1 ;;
          esac
          echo "version=${VERSION}" >> "$GITHUB_OUTPUT"

      - name: Exit if the cask already declares that version
        id: guard
        working-directory: homebrew-cellar
        env:
          VERSION: ${{ steps.release.outputs.version }}
        run: |
          set -euo pipefail
          # Idempotence is the whole point. Four scheduled runs a day must
          # produce at most one commit per published release, which is also what
          # keeps this compatible with "one stable release per commit" in the
          # app repository.
          if grep -qx "  version \"${VERSION}\"" "Casks/home-cellar.rb"; then
            echo "the cask already declares ${VERSION}; nothing to do"
            echo "bump=no" >> "$GITHUB_OUTPUT"
          else
            echo "bump=yes" >> "$GITHUB_OUTPUT"
          fi

      - name: Compute the checksum of the published asset
        if: steps.guard.outputs.bump == 'yes'
        id: asset
        env:
          VERSION: ${{ steps.release.outputs.version }}
        run: |
          set -euo pipefail
          # Downloaded from the documented URL rather than handed over by the
          # release job. This proves the URL a stranger will use serves exactly
          # these bytes; a digest computed on the build runner proves only that
          # the build was built.
          URL="https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v${VERSION}/Home-Cellar-${VERSION}.zip"
          curl -fsSL -o "${RUNNER_TEMP}/asset.zip" "$URL"
          SHA="$(shasum -a 256 "${RUNNER_TEMP}/asset.zip" | awk '{print $1}')"
          test "${#SHA}" -eq 64
          echo "sha256=${SHA}" >> "$GITHUB_OUTPUT"

      - name: Rewrite the two declared lines
        if: steps.guard.outputs.bump == 'yes'
        working-directory: homebrew-cellar
        env:
          VERSION: ${{ steps.release.outputs.version }}
          SHA: ${{ steps.asset.outputs.sha256 }}
        run: |
          set -euo pipefail
          CASK="Casks/home-cellar.rb"
          # Fail closed BEFORE editing: each stanza must occur exactly once, at
          # the start of its own line. `url` interpolates `#{version}` and
          # carries no literal version, so there is no second line either
          # substitution could reach.
          test "$(grep -c '^  version "' "$CASK")" -eq 1
          test "$(grep -c '^  sha256 "' "$CASK")" -eq 1
          /usr/bin/sed -i '' \
            -e "s|^  version \"[^\"]*\"\$|  version \"${VERSION}\"|" \
            -e "s|^  sha256 \"[^\"]*\"\$|  sha256 \"${SHA}\"|" \
            "$CASK"
          # And fail closed AFTER: the file now declares exactly what was
          # measured, or this run stops before any gate and before any commit.
          grep -qx "  version \"${VERSION}\"" "$CASK"
          grep -qx "  sha256 \"${SHA}\"" "$CASK"
          git --no-pager diff --stat

      - name: Register the rewritten checkout as a real tap
        if: steps.guard.outputs.bump == 'yes'
        run: |
          set -euo pipefail
          TAPS="$(brew --repository)/Library/Taps/juancasanueva"
          mkdir -p "$TAPS"
          cp -R "$GITHUB_WORKSPACE/homebrew-cellar" "$TAPS/homebrew-cellar"

      - name: Gate the rewrite before anything is committed
        if: steps.guard.outputs.bump == 'yes'
        run: |
          set -euo pipefail
          # A push made with GITHUB_TOKEN does not trigger other workflows, so
          # ci.yml will never run on the commit this job is about to make.
          # These are therefore not a second opinion — they are the only gates
          # a bump commit ever gets, and they run while nothing is committed.
          brew style juancasanueva/cellar
          brew audit --cask juancasanueva/cellar/home-cellar
          brew audit --cask --online --strict juancasanueva/cellar/home-cellar

      - name: Commit the bump
        if: steps.guard.outputs.bump == 'yes'
        working-directory: homebrew-cellar
        env:
          VERSION: ${{ steps.release.outputs.version }}
        run: |
          set -euo pipefail
          git config user.name "github-actions[bot]"
          git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
          git add Casks/home-cellar.rb
          git commit -m "chore(cask): home-cellar ${VERSION}"
          git push origin main
```

## 4. `README.md` (tap repository)

````markdown
# homebrew-cellar

The Homebrew tap for [Cellar](https://github.com/juancasanueva/SWIFTUI_cellar), a native macOS GUI
for Homebrew.

## Install

```sh
brew tap juancasanueva/cellar
brew install --cask home-cellar
```

That installs `/Applications/cellar.app` — the same notarized, stapled build the project's
[Releases](https://github.com/juancasanueva/SWIFTUI_cellar/releases) page serves. The bundle is named
`cellar.app` in both channels; the app presents itself as **Home-Cellar**.

If another tap ever claims the `home-cellar` token, this fully-qualified form is unambiguous:

```sh
brew install --cask juancasanueva/cellar/home-cellar
```

## Requirements

- macOS 26 (Tahoe) or later
- Apple Silicon (`arm64`)

## Updates

Cellar updates itself with [Sparkle](https://sparkle-project.org) from an EdDSA-signed appcast, so the
cask declares `auto_updates true`. Homebrew will not report a self-updated copy as outdated and will
not reinstall over it. `brew upgrade` and Cellar's own updater do not fight.

## Uninstall

```sh
brew uninstall --cask home-cellar
```

To remove Cellar's caches, catalog, local metadata and preferences as well:

```sh
brew uninstall --cask --zap home-cellar
```

**A zap cannot remove Keychain items.** Homebrew's uninstall has no Keychain facility, so these two
generic-password items survive it, and they are the only things that do:

- `com.juancasanueva.cellar.nvd-api-key`
- `com.juancasanueva.cellar.github-pat`

Both exist only if you supplied those optional credentials. Delete them in **Keychain Access** if you
want them gone.

Untapping or deleting this tap does **not** uninstall anything. An installed copy keeps working and
keeps updating itself through Sparkle; it simply stops being managed by `brew`.

## How this tap stays current

`.github/workflows/bump.yml` reads the app repository's latest published release four times a day,
downloads the published asset, computes its checksum from those bytes, and commits the two-line bump
only after `brew style` and `brew audit --cask --online --strict` both pass. It makes no commit when
the cask already declares the published version, so at most one commit exists per release. The app
repository sends nothing to this one and holds no credential for it.

## Licence

MIT, the same licence as the app. A cask is a build recipe, not the application.
````

---

# This repository — exact replacement text

## `README.md` — replace the `## Install` section (~:32-39)

````markdown
## Install

With Homebrew:

```sh
brew tap juancasanueva/cellar
brew install --cask home-cellar
```

That installs `/Applications/cellar.app`, the same notarized build the releases
page serves. If another tap ever claims the `home-cellar` token, the
fully-qualified `brew install --cask juancasanueva/cellar/home-cellar` is the
unambiguous form.

Or download the latest `Home-Cellar-<version>.zip` from
[Releases](../../releases), unzip it, and drag `cellar.app` to `/Applications`.

The build is notarized and stapled, so the first launch is a single ordinary
"Open" confirmation — no right-click workaround, and no network access needed to
get past Gatekeeper. Apple Silicon and macOS 26 only.

To remove a cask install, `brew uninstall --cask --zap home-cellar` also deletes
Cellar's caches, catalog, metadata and preferences. It cannot delete the two
Keychain items Cellar creates — `com.juancasanueva.cellar.nvd-api-key` and
`com.juancasanueva.cellar.github-pat` — because Homebrew's uninstall has no
Keychain facility. Remove those in Keychain Access if you want them gone.
````

## `RELEASING.md` §7 — replace the extension-point paragraph (~:309-311)

```markdown
`release.yml` carried a named extension point immediately after the publish step.
Appcast publication now occupies it, and the cask bump **declined** it: the tap
is kept current by a scheduled workflow in `juancasanueva/homebrew-cellar` that
pulls this repository's `releases/latest` (§8). The release job therefore gains
no cross-repository write, no eighth secret, and no way for a successful,
notarized release to report failure because of a channel that is not on the
critical path. The comment is gone, and a test keeps it gone.
```

## `RELEASING.md` — new §8, inserted before Troubleshooting (which becomes §9)

````markdown
## 8. The Homebrew tap

The second delivery channel. It publishes **no second artifact**: the cask points
at the same `Home-Cellar-<version>.zip` §7 specifies.

| Thing | Value |
|---|---|
| Tap repository | `juancasanueva/homebrew-cellar` (public) |
| Tap name | `juancasanueva/cellar` |
| Cask token | `home-cellar` |
| Canonical install | `brew tap juancasanueva/cellar` then `brew install --cask home-cellar` |
| Unambiguous form | `brew install --cask juancasanueva/cellar/home-cellar` |
| Installed path | `/Applications/cellar.app` — the same bundle name the zip carries |

Four files live there: `Casks/home-cellar.rb`, `.github/workflows/ci.yml`,
`.github/workflows/bump.yml`, and a user-facing `README.md`.

### How the cask stays current

`bump.yml` runs on a schedule (`17 */6 * * *`) and on `workflow_dispatch`. It
**pulls**: it reads this repository's `releases/latest` anonymously, exits 0 when
the cask already declares that version, downloads the published asset, computes
the checksum from those bytes, rewrites `version` and `sha256`, runs `brew style`
and both audits, and only then commits `chore(cask): home-cellar <version>`.

Three properties are deliberate:

1. **Nothing here pushes to it.** `release.yml` names no other repository and
   holds no credential for one. A missed scheduled run is corrected by the next;
   a missed dispatch would have been lost forever.
2. **The checksum comes from the published asset**, not from the build runner.
   That proves the URL a stranger will use serves exactly those bytes.
3. **It is idempotent on `version`**, so four runs a day produce at most one
   commit per release. It never tags, never releases here, and never touches
   Pages, so it cannot interact with the distinct-commit gate of §3.

### Manual fallback

If the tap's Actions are down, the bump is two lines and one command:

```sh
gh release view --repo juancasanueva/SWIFTUI_cellar --json tagName --jq .tagName
curl -fsSLO https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v<version>/Home-Cellar-<version>.zip
shasum -a 256 Home-Cellar-<version>.zip
# edit version and sha256 in Casks/home-cellar.rb, then, from a checkout tapped
# into $(brew --repository)/Library/Taps/juancasanueva/homebrew-cellar:
brew style juancasanueva/cellar
brew audit --cask --online --strict juancasanueva/cellar/home-cellar
git commit -am "chore(cask): home-cellar <version>" && git push
```

Never commit a checksum that the online audit has not verified.

### The zap inventory

`brew uninstall --cask --zap home-cellar` removes exactly these roots. The block
is machine-checkable: `cellarTests/CaskZapInventoryTests.swift` parses it and
fails if the shipped sources declare a write root that is missing from it.

`source` rows are declared by shipped Swift and are bound to it by that test.
`framework` rows are written by AppKit, Foundation and Sparkle rather than by
Cellar's own code, so no source scan can find them; they are here because they
were **measured on a real machine** (probes P7/P8), and they are the reason the
test asserts scan-coverage rather than list-equality.

```zap-inventory
source     ~/Library/Application Support/com.juancasanueva.cellar
source     ~/Library/Caches/Cellar
framework  ~/Library/Caches/com.juancasanueva.cellar
framework  ~/Library/HTTPStorages/com.juancasanueva.cellar
framework  ~/Library/Preferences/com.juancasanueva.cellar.plist
```

`~/Library/Saved Application State/com.juancasanueva.cellar.savedState` is
**deliberately absent**: it was measured and does not exist, and a path nobody
has observed is never guessed into a list of things to delete.

`~/Library/Caches/Cellar` is a **display-name** directory rather than a
bundle-id one, which is a slightly broader claim than it looks — "Cellar" is
also Homebrew's own word for `/opt/homebrew/Cellar`. It is correct today
(Homebrew's user cache is `~/Library/Caches/Homebrew`, which this list must
never contain), and moving Cellar's cache under the bundle id is a deferred
migration, not this change.

### What a zap cannot remove

Homebrew's `zap` offers `trash:`, `delete:`, `rmdir:`, `signal:`, `launchctl:`,
`quit:`, `pkgutil:`, `script:` and `login_item:` — and **nothing for the
Keychain**. Cellar creates two generic-password items, and both survive
"uninstall everything":

- `com.juancasanueva.cellar.nvd-api-key`
- `com.juancasanueva.cellar.github-pat`

Naming them is the whole obligation. No code is added to delete them: an app
that silently reaches into the Keychain during uninstall is a worse trade than
an honest sentence in two READMEs.
````

## `PRD.md` — the three lines

**:9** — replace the `**Distribution**` cell value with:

```
Direct download, delivered by CI (`.github/workflows/release.yml`: Developer ID + notarized, on `v*` tags — see [`RELEASING.md`](RELEASING.md)); Sparkle 2 in-app updates from an EdDSA-signed appcast published to GitHub Pages by the same job (`m6-sparkle-updates`); Homebrew cask from the self-hosted tap `juancasanueva/cellar` — `brew install --cask home-cellar` (`m6-cask-tap`)
```

**:194** — replace the `**Cask channel**` bullet with:

```markdown
- **Cask channel — implemented (M6).** Self-hosted tap `juancasanueva/homebrew-cellar`: `brew tap juancasanueva/cellar && brew install --cask home-cellar` installs `/Applications/cellar.app`, the same notarized asset the releases page serves. The cask declares `auto_updates true`, so `brew upgrade` never fights Sparkle's in-place self-replacement — casks and Sparkle coexist fine, and this is the one line that makes that true. Submission to `homebrew/cask` stays deferred until notability requirements (stars/press) are met; the self-hosted tap is the channel until then. A scheduled workflow **in the tap repository** keeps the cask current by pulling `releases/latest`, so the release job gains no cross-repository reach and no new secret. `brew uninstall --cask --zap` removes the documented write roots but cannot remove Cellar's two Keychain items — see [`RELEASING.md`](RELEASING.md) §8.
```

**:217** — replace the M6 parenthetical's closing so the line ends:

```
… Sparkle 2 in-app updates landed as the third — `openspec/specs/app-updates/`. The self-hosted Homebrew tap landed as the fourth — `juancasanueva/homebrew-cellar`, §6.) *Exit: 1.0 public release.*
```

---

# Strict TDD — the test design

Runner:
`xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
`swift test --package-path Packages/CellarCore` runs as a 0-line-diff regression sanity only.

**Every one of T1–T5 is RED before its documentation or deletion lands, and none depends on the tap
repository existing.** That is what allows WU2 to be developed and merged independently of WU0/WU1.

## `cellarTests/CaskZapInventoryTests.swift` (new)

A self-contained `CaskZapSources` enum with its own `#filePath` repository anchor, matching
`UpdateProjectFileTests`, `BundleUpdateKeysTests` and `AppcastScriptContractTests`, all of which
redeclare `repositoryRoot` so a slice rolls back by deleting one file.

### The scan algorithm — specified so apply cannot drift

Scanned roots: every `*.swift` under `cellar/` and `Packages/CellarCore/Sources/`.

**Step 1 — find every search-domain use.** Regex, applied per file:

```
FileManager\.default\.urls\(for: \.(cachesDirectory|applicationSupportDirectory), in: \.userDomainMask\)
```

Capture group 1 is the domain. **Measured today: 12 occurrences** — 10 `cachesDirectory`,
2 `applicationSupportDirectory`.

**Step 2 — classify each occurrence** using the match's line index `i`:

| Class | Rule | Meaning |
|---|---|---|
| **appending** | the **forward** window `lines[i ... i+3]` contains `.appendingPathComponent(` | the expression names a Cellar-owned root |
| **pass-through** | it does not | the bare directory is handed to something else |

The forward window is 4 lines because the widest shipped shape spans exactly that:
`CatalogStore.swift:122-125` (`urls(...)` / `.first ?? …` / `return support` /
`.appendingPathComponent(bundleIdentifier…)`) and `PersistenceContainer.swift:16-19` (the same
four-line shape). Every other appending site spans 3. Do not narrow the window to 3.

**Step 3 — extract the root from an appending occurrence.** Take the **first**
`.appendingPathComponent(` in the window and read its first argument:

| First argument | Root component | Occurs at |
|---|---|---|
| a string literal | the substring before the first `/` — so `"Cellar/disk-usage-v1.json"` and `"Cellar"` both yield `Cellar` | `cellarApp.swift:224, 234, 327, 383`, `CaskIconLoader.swift:127` |
| the identifier `bundleIdentifier` | `com.juancasanueva.cellar`, the shipped default that same declaration spells | `CatalogStore.swift:125`, `PersistenceContainer.swift:19` |

Interpolation is safe by construction: `"Cellar/\(SecurityKit.advisoryCacheFileName)"` has a literal
first component.

**Step 4 — map to a path.** `cachesDirectory` → `~/Library/Caches/<component>`;
`applicationSupportDirectory` → `~/Library/Application Support/<component>`.

Discovered set today, **exactly two**:

- `~/Library/Caches/Cellar`
- `~/Library/Application Support/com.juancasanueva.cellar`

**Step 5 — every pass-through must be a `HomebrewRoots` hand-off.** For each pass-through, the
**symmetric** window `lines[i-3 ... i+3]` MUST contain `HomebrewRoots(`. The window is symmetric
because at three of the five sites the constructor opens *above* the match (`cellarApp.swift:568`,
`:621`, `HealthView.swift:309`) while at the other two it closes below (`cellarApp.swift:604`,
`CleanupView.swift:327`).

This is DD-10, and it is the most important line of the whole test: `HomebrewRoots` derives
`~/Library/Caches/**Homebrew**` and `/opt/homebrew/Cellar`, which are **Homebrew's**, not Cellar's. A
scan that treated them as Cellar write roots would push Homebrew's bottle cache into a `zap trash:`
list and delete it on every uninstall.

### The four tests

| # | Test name | Asserts | RED because |
|---|---|---|---|
| **T1** | `everyWriteRootTheSourceDeclaresIsInTheDocumentedInventory` | every root from step 4 appears as a `source` row of the `zap-inventory` block in `RELEASING.md` | no `zap-inventory` block exists in `RELEASING.md` today, so the parse yields nothing and every root is missing |
| **T2** | `theWriteRootScanIsNonVacuousAndEveryPassThroughIsAHomebrewRootsHandOff` | the discovered root set **equals** the two paths above; appending occurrences ≥ 7; pass-through occurrences ≥ 5 and **every** one satisfies step 5; the parsed inventory has **≥ 5** rows of which ≥ 2 are `source` | same — the inventory is absent, and the equality/floor clauses stop an empty scan or an empty parse from passing trivially |
| **T3** | `theRunbookNamesBothKeychainItemsAZapCannotRemove` | `RELEASING.md` contains `com.juancasanueva.cellar.nvd-api-key` and `com.juancasanueva.cellar.github-pat` | neither is documented today |
| **T4** | `theReadmeCarriesBothBrewCommandsAsWholeLines` | some line of `README.md` trims to exactly `brew tap juancasanueva/cellar`, another to exactly `brew install --cask home-cellar`; the file also contains `juancasanueva/cellar/home-cellar` and `cellar.app` | neither command is in `README.md` today |

T4 asserts **whole lines** rather than substrings for the reason
`runbookRecordsTheVersionPolicyAndItsOverride` already gives: *a reader who has to assemble the command
from two paragraphs has not been given a command.*

### Reconciling T2 with the spec (DD-9)

The delta's scenario (spec.md:132) reads *"the enumeration is non-vacuous: the scan finds every root
the source declares, and the documented inventory additionally lists every root measured on a real
machine, including framework-written roots that no source file declares."* The spec already encodes the
split, because a reading of *"the source scan must find all five measured paths"* would be
**unsatisfiable** — three of the five are written by frameworks and appear in no source file. The
design honours the split as follows:

- the **scan** must be non-vacuous and exact (2 source-derived roots, 5 accounted-for pass-throughs);
- the **documented inventory** must be non-vacuous against the real-machine measurement (≥ 5 rows).

Direction matters: the test asserts **scan ⊆ inventory**, never the reverse. A framework path in the
inventory that no source declares is correct and must not fail.

## `cellarTests/ReleasePipelineCompositionTests.swift` — T5 (one added test)

Placed in the existing `Release pipeline composition` suite and reusing `ReleasePipelineSources`
(`text(_:)` + `workflowPath`) rather than re-parsing the workflow. No helper API is added.

```swift
/// D1/D2: the release run gains no cross-repository reach.
///
/// A `curl` to a dispatch endpoint would pass `gh == 1 / git == 0`, because the
/// Pages guard already establishes `curl` plus a bearer token as an accepted
/// shape. Passing the letter is not the point — this asserts the decision
/// itself, so "we chose not to insert here" stays chosen.
@Test("The release workflow gains no cross-repository reach")
func theWorkflowGainsNoCrossRepositoryReach() throws {
    let workflow = try ReleasePipelineSources.text(ReleasePipelineSources.workflowPath)

    // The declined extension point is gone, rather than standing as an
    // invitation the suite would refuse.
    #expect(!workflow.contains("extension point"))

    for token in ["repository_dispatch", "dispatches"] {
        #expect(!workflow.contains(token), "the workflow must not carry: \(token)")
    }

    let apiCalls = workflow
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
        .filter { $0.contains("api.github.com/repos/") }
    // Anchored: the distinct-commit gate really does call the API, so the loop
    // below is not empty for the wrong reason.
    #expect(!apiCalls.isEmpty)
    for call in apiCalls {
        #expect(
            call.contains("api.github.com/repos/${GITHUB_REPOSITORY}")
                || call.contains("api.github.com/repos/${{ github.repository }}"),
            "a GitHub API call names a repository that is not this one: \(call)"
        )
    }

    for name in ["homebrew-cellar", "juancasanueva/cellar"] {
        #expect(!workflow.contains(name), "the workflow must not name \(name)")
    }
}
```

**Verified against the current file, byte by byte:**

| Clause | Today | After WU2 |
|---|---|---|
| `!contains("extension point")` | **fails** — `release.yml:175` | passes |
| `repository_dispatch` / `dispatches` | absent | absent |
| `api.github.com/repos/` | one line, `:64`, already `${GITHUB_REPOSITORY}` | unchanged |
| `homebrew-cellar` | absent | absent |
| `juancasanueva/cellar` | absent — `:194` holds `juancasanueva.github.io/SWIFTUI_cellar`, which does not contain that substring | absent |

So T5 is **genuinely RED on arrival** through its first clause, and D2's two-line deletion is what turns
it green. Without that clause T5 would be green before the change, which strict TDD forbids (DD-2).

**The deletion is inert for every existing test.** `workflowSteps(in:)` splits on lines whose trimmed
form starts with `- name:`; lines 175-176 are comments inside the `Publish GitHub Release` step's body.
No `- name:` line moves, no step is created or removed, and the only two consumers of `workflowSteps`
(`privateRepositoryFailsFastBeforeAnyBuildStep`, `keychainDeletionRunsUnconditionally`) select other
steps by content. `theWorkflowCanOnlyEverCreateARelease`'s `gh == 1 / git == 0` reads the whole file and
is unaffected.

## Testing Strategy

| Layer | What | Approach | Runner |
|---|---|---|---|
| Unit | zap inventory bound to source; Keychain caveat; README commands; no cross-repo reach | source + document scan, `#filePath` anchored | `cellarTests`, **this repository** |
| CI gate | style, offline audit, online strict audit, install/zap round trip; prerelease never becomes a version; idempotent bump | real Homebrew on a real runner | `ci.yml` / `bump.yml`, **`juancasanueva/homebrew-cellar`**, `macos-26` |
| Manual evidence | tap + install on a real Mac; `auto_updates true` after a Sparkle self-update | maintainer transcript, captured verbatim into this file and the verify report | maintainer, Homebrew 6.0.18 |
| Regression | 0-line-diff sanity | `swift test --package-path Packages/CellarCore` | local |

## Threat Matrix

Applicable: this design adds shell commands, subprocess invocations and VCS/PR automation — in the tap
repository.

| Boundary | Adversarial case | Applicability | Design response | Planned RED test |
|---|---|---|---|---|
| Documentation-like paths | an executable file added to the tap; `Casks/*.rb` is Ruby that `brew` evaluates | **Applicable** | The tap holds exactly four files plus a licence. The cask is data-shaped: no `preflight`, `postflight`, `uninstall script:` or `installer manual:` stanza, so nothing in it executes arbitrary code at install time. `brew style` + `brew audit` run on every push and PR | `ci-gate`: style + both audits, tap repository. Not RED-able in `cellarTests` — stated, not faked |
| Git repository selection | the bump writing to the wrong repository; CI auditing a different tree than the one under review | **Applicable** | Every git operation is `working-directory: homebrew-cellar`, on `ref: main`, pushed as `git push origin main`. CI copies the **checked-out bytes** into the tap path rather than re-cloning them (DD-7) | `ci-gate`; and **T5** pins the complement here — `release.yml` names no other repository and declares no dispatch |
| Commit state | the bump committing an unaudited or partially rewritten file | **Applicable** | `git add` names exactly `Casks/home-cellar.rb`; never `commit -a`. The rewrite fails closed before **and** after `sed`, and all three gates run before the commit exists (DD-8) | `ci-gate`: a bump run whose audit fails commits nothing |
| Push state | a bump commit racing another, or looping | **Applicable** | `concurrency: group: bump, cancel-in-progress: false`; explicit `git push origin main`; idempotent on `version`, so a re-run of an unchanged release pushes nothing. `GITHUB_TOKEN` pushes do not trigger workflows, so no loop is reachable | `ci-gate`: run twice against an unchanged `releases/latest` → zero commits the second time |
| PR commands | composed `gh` invocations gaining reach | **N/A** | Neither tap workflow invokes `gh`, and `release.yml` keeps its single `gh release create` | Covered by the existing `theWorkflowCanOnlyEverCreateARelease` |

Nothing in **this** repository crosses a routing, shell, subprocess or PR boundary: the change is
documentation plus four `nonisolated` read-only tests.

## Work Units, Sequencing and Delivery

Order is **tap first**, and the reason is asymmetric rollback: merging a README that publishes
`brew install --cask home-cellar` before the tap exists ships a public command that 404s for every
reader of `main` in the interval. Nothing forces the reverse — T1–T5 assert *documentation content*, so
they are green with or without the tap.

| WU | Repository | Content | Verification | Rollback boundary |
|---|---|---|---|---|
| **WU0** | `juancasanueva/homebrew-cellar` | `gh repo create juancasanueva/homebrew-cellar --public` | repository exists and is public | Delete the repository. **Outward-facing: the orchestrator confirms with the maintainer before apply (R11)** |
| **WU1** | tap | The four files above + `LICENSE`, one commit | `ci.yml` green **including** the install/zap round trip; maintainer's local `brew tap` + install transcript captured below | `git revert`, or disable `bump.yml` from the Actions UI, or delete the repository |
| **WU2** | this repository | **RED**: `CaskZapInventoryTests.swift` (T1–T4) + T5 | the five tests fail for the stated reasons | delete one new file, revert one test |
| **WU3** | this repository | **GREEN**: `README.md`, `RELEASING.md` §7 correction + new §8, `PRD.md` ×3, and the two-line `release.yml` deletion | T1–T5 green; `cellarTests` green at baseline + 5 | revert the docs commit; `release.yml` regains two comment lines |

WU2 and WU3 are one PR on `feat/m6-cask-tap` (`^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)/[a-z0-9._-]+$` ✓),
`delivery_strategy = single-pr`, no `size:exception` needed against the 5,000-line budget.

Conventional commits, **no `Co-Authored-By` and no AI attribution**:

| WU | Message |
|---|---|
| WU1 | `feat(cask): add the home-cellar cask, its gates and its bump workflow` |
| WU2 | `test(cask): bind the zap inventory and the install commands to the source` |
| WU3 | `docs(cask): document the Homebrew tap and decline the release-workflow extension point` |

WU3 carries the `release.yml` deletion because that deletion is what turns T5's first clause green —
tests travel with the behaviour they verify.

**Nothing in WU2 or WU3 depends on WU0 or WU1.** The five tests read only this repository off disk.

## Bindings — files with a 0-line diff, and this is asserted

`scripts/release.sh`, `scripts/appcast.sh`, `cellar.xcodeproj/project.pbxproj`,
`Packages/CellarCore/**`, every `.swift` under `cellar/`, `cellar.xcscheme`, and **every step, trigger
and secret reference in `.github/workflows/release.yml`**. This change adds no Swift product code.

`project.pbxproj` needs no edit even for the new test file: `cellarTests/` is a
`PBXFileSystemSynchronizedRootGroup`, so the file joins the target by existing.

## Migration / Rollout

**No migration.** No runtime code, no cache file, no schema version, no Keychain item, no dependency,
no preference key. A user on the direct-download channel is unaffected; a user who later installs the
cask over an existing `/Applications/cellar.app` gets the same bundle path and keeps every preference,
because nothing is renamed (DD-3).

## Rollback

**This repository** — one `git revert` of the PR. It restores two comment lines in `release.yml` and
removes documentation and tests; it orphans nothing. Post-revert:
`swift build --package-path Packages/CellarCore` and
`xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.

**The tap repository** — three independent levers, cheapest first: revert the cask commit to pin the
previous version; disable `bump.yml` from the Actions UI; delete the repository.

**What rollback does NOT do:** untapping or deleting the tap **does not uninstall anything**. An
already cask-installed `/Applications/cellar.app` keeps working and keeps self-updating through
Sparkle; it simply stops being brew-managed. `brew uninstall --cask` before the tap disappears is the
clean exit, and it still cannot remove the two Keychain items.

## Risk Register

| # | Risk | L | Design-level mitigation |
|---|---|---|---|
| **R1** | The zap list rots — every M-slice so far added a cache file under `~/Library/Caches/Cellar` | **High** | T1 + T2. The scan is bound to `.cachesDirectory`/`.applicationSupportDirectory` uses, so a sixth cache file fails the suite **in the repository where the write was introduced** |
| **R2** | A zap cannot delete Keychain items | **High** | T3 asserts both service names in `RELEASING.md`; both READMEs state it in the uninstall section; DD-6 keeps it out of `caveats` where it would become noise |
| **R3** | Sparkle/brew version divergence (archive design risk 11) | **High** | `auto_updates true`, non-negotiable, plus a `manual-evidence` transcript proving `brew upgrade` does not fight a self-updated copy |
| **R4** | `~/Library/Caches/Cellar` is a display-name directory, a broader claim than it looks | Med | Stated explicitly in `RELEASING.md` §8, including that `~/Library/Caches/Homebrew` must never enter the list. DD-10 makes it structurally unreachable |
| **R5** | Token collision — `homebrew/cask` could later gain `home-cellar` | Low | Measured free (obs `#7699`). Both READMEs document the fully-qualified form; T4 asserts this repository carries it |
| **R6** | The tap could publish a version whose asset was deleted | Med | `bump.yml` **downloads the asset before committing**, and `brew audit --online --strict` re-verifies both the URL and the digest |
| **R7** | Most of the change is outside the reviewed diff | **High** | All four files quoted complete above, ready to commit as-is |
| **R8** | A second workflow **here** would be unconstrained by `release.yml`'s file-scoped invariants | Low | D1 adds no workflow here; T5 pins it. A future one must arrive with its own trigger/secret/blast-radius tests |
| **R9** | `brew audit --cask` behaves differently on an untapped path | Med | DD-7 — the checkout is copied into the real tap directory, and the clone form is rejected for a named reason |
| **R10** | The delta's cask scenarios execute in another repository | Med | The delta's class table names the runner per class; evidence is a run URL + exit status captured below and in the verify report |
| **R11** | Creating a public repository is an outward-facing action the pipeline cannot take unilaterally | Med | WU0 is maintainer-confirmed before apply, and nothing in this PR depends on it |
| **R12** | The main spec's class-count table cannot be carried by an ADDED delta | Low | The delta states the hand-update obligation under *Notes for archive*; archive counts `- Verification:` lines rather than trusting the note |
| **R13** *(new)* | `brew audit --strict` may raise a rule written for `homebrew/cask` submissions that a third-party tap need not satisfy | Med | If it fires, record the exact rule and decide explicitly. **Never** drop `--online`: that is the checksum gate. `--new` is already excluded for exactly this reason |
| **R14** *(new)* | `macos-26` resolving to an Intel image would make the install step unreachable while still reporting success | Low | `ci.yml` asserts `uname -m = arm64` before any gate, so an unreachable gate fails loudly instead of passing vacuously |

## Open Questions — all resolved at design

| # | Question | Resolution |
|---|---|---|
| 1 | Cron cadence | `17 */6 * * *`, four times a day (proposal default). `workflow_dispatch` covers the impatient case |
| 2 | Does the tap get a `LICENSE`? | Yes — MIT. The validator found this repository had **no** licence file, so "mirror the app" was ungrounded; the maintainer chose MIT for **both** repositories (DD-13, 2026-08-23). The app repository's `LICENSE` is added in this PR; the tap's is byte-identical. MIT matches Sparkle and CaskHub in `THIRD-PARTY.md` |
| 3 | Who owns canonical uninstall instructions? | `RELEASING.md` §8 owns the maintainer view; the tap README owns the user view. The Keychain caveat is **repeated in both**, not cross-linked — the user never reads `RELEASING.md` |
| 4 | Short vs fully-qualified install form | Short form canonical, fully-qualified documented as the unambiguous fallback (R5). Both asserted by T4 |

No open question blocks `sdd-tasks`.

## Evidence to capture at apply/verify

Placeholders, not results. **No probe outcome is invented here.**

| Evidence | Class | Where it lands |
|---|---|---|
| `ci.yml` run URL + exit status (style, both audits, install, zap) | `ci-gate` | this section + verify report |
| `bump.yml` run twice against an unchanged `releases/latest` → zero commits the second time | `ci-gate` | same |
| `bump.yml` `workflow_dispatch` run log showing `releases/latest` resolving to the stable tag (never a `v*-rc.*` tag), or the `*-*` prerelease refusal branch exiting 0 with no commit | `ci-gate` | same (scenario S4) |
| `brew tap juancasanueva/cellar && brew install --cask home-cellar` transcript showing `/Applications/cellar.app` at the released version | `manual-evidence` | verbatim transcript, this section |
| `brew upgrade` against a Sparkle-self-updated copy, showing no reinstall | `manual-evidence` | verbatim transcript, this section |
