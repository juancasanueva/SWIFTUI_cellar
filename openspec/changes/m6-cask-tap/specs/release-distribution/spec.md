# Delta for release-distribution

Existing capability — `openspec/specs/release-distribution/spec.md` (**8 requirements / 32 scenarios**,
established by the archived `2026-08-23-m6-release-pipeline` and amended by
`2026-08-23-m6-sparkle-updates`). This delta is **ADDED-only**: **2 requirements / 9 scenarios added,
0 modified, 0 removed, 0 renamed**, taking the capability to **10 requirements / 41 scenarios**.

Nothing is removed and no existing scenario is deleted, so `rules.archive`'s destructive-delta warning
does not fire.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m6-cask-tap/` + Engram canonical project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**No new capability.** A tap is a second *channel* for the same delivered build, and this capability
already owns "what must be true of a build Cellar delivers to a stranger". The cask consumes the asset
URL, the bundle name, the arm64 pin and the macOS 26.0 floor this spec already fixes; it authors none
of them.

## Verification classes — with the runner named per class

Every scenario below declares exactly one verification class. This delta is the **first in the project
whose scenarios execute in a second repository**, so the runner is named per class rather than implied
(the precedent for stating it plainly is `app-updates`' own class table):

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion in `cellarTests`, in the shipped `#filePath` source-scan idiom; reads **only this repository** off disk and passes whether or not the tap exists | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`, **this repository** | **4** |
| `ci-gate` | a hard gate whose failure fails its job and commits or publishes nothing | `.github/workflows/ci.yml` (and the bump workflow) in **`juancasanueva/homebrew-cellar`**, on `macos-26`; evidence is the run URL and exit status, captured in `design.md` and the verify report | **3** |
| `manual-evidence` | no harness can exist — no runner may install into a real `/Applications` and observe a self-updated app — so the maintainer's observed output is recorded verbatim | the maintainer, on a real Mac running Homebrew 6.0.18; transcript captured in `design.md` and the verify report | **2** |

What stays **design-owned and is deliberately absent here**: the tap repository's name and layout, the
cask's Ruby stanza set and ordering, the bump workflow's triggers and cron cadence, whether CI taps the
checkout or audits it in place, the runner image pin, and the wording of either README. Those are *how*
the contract is met, and none is a property of a delivered build.

## ADDED Requirements

### Requirement: The delivered build is installable through the project's Homebrew tap

Cellar tells its users that Homebrew is the source of truth, so the delivered build MUST be installable
through Homebrew and not only by dragging a downloaded zip. The project MUST publish a Homebrew tap
whose cask installs **the same published asset this capability already specifies** — no second artifact,
no separately built binary, and no mirrored copy.

Adding the tap and installing the cask MUST place the delivered bundle at **`/Applications/cellar.app`**,
whose `CFBundleShortVersionString` equals the released version. The installed bundle name is the one the
zip already carries; this change MUST NOT rename it, so the cask channel and the direct-download channel
install the same path.

The cask MUST declare that the app **updates itself**, because Sparkle replaces the bundle in place: a
self-updated copy MUST NOT cause `brew` to report a mismatch or to reinstall over the newer app. The
declared checksum MUST equal the digest of the **published** asset, established by downloading that
asset rather than by trusting a value computed while building it. The cask MUST NOT offer a prerelease
version: only a release that the project publishes as its latest stable release MUST become an
installable cask version.

Keeping the cask current MUST NOT require a manual step and MUST be **idempotent on the declared
version** — an update attempt against a release the cask already declares MUST change nothing. The
channel therefore cannot manufacture a second commit, or a second release, from one published release,
which is what keeps it compatible with "one stable release per commit".

#### Scenario: A tap and an install put the released build in `/Applications`

- GIVEN a Mac with Homebrew that has never had Cellar installed
- WHEN the project's tap is added and its cask is installed
- THEN `/Applications/cellar.app` exists and reports the released version
- AND the app launches without a Gatekeeper refusal
- Verification: `manual-evidence`

#### Scenario: The cask is style-clean, audit-clean, and survives a real install/uninstall round trip

- GIVEN the cask as published in the tap repository
- WHEN the tap's CI runs style, offline audit, and online strict audit, then installs the cask and
  uninstalls it with a zap
- THEN every gate passes, the online audit confirms the declared checksum against the downloaded
  published asset, and the round trip completes
- AND a failing gate leaves nothing committed and nothing published
- Verification: `ci-gate`

#### Scenario: A self-updated app does not fight `brew upgrade`

- GIVEN a cask-installed copy that has since updated itself in place to a newer version
- WHEN an upgrade is requested through Homebrew
- THEN Homebrew does not report the installed copy as outdated or reinstall over it
- Verification: `manual-evidence`

#### Scenario: A prerelease never becomes an installable cask version

- GIVEN a published prerelease tag that is newer than the latest stable release
- WHEN the cask's version source is resolved
- THEN the cask still declares the latest **stable** released version
- AND no prerelease version is ever offered to a cask user
- Verification: `ci-gate`

#### Scenario: Keeping the cask current is idempotent on the declared version

- GIVEN a cask that already declares the latest published stable version
- WHEN the update mechanism runs again against that unchanged release
- THEN it exits successfully and produces no commit and no version change
- AND running it repeatedly produces at most one commit per published release
- Verification: `ci-gate`

### Requirement: Uninstalling states exactly what it removes, and what it cannot

An uninstall story that is quietly incomplete is worse than none. The repository MUST document the full
set of write roots a full uninstall removes, and that documented inventory MUST be **bound to the
source**: every application-support and cache root the shipped sources declare MUST appear in it, so a
cache file added by a later change fails a test in the repository where the write was introduced rather
than silently outliving the app on a user's disk. The inventory MUST list only paths that have been
observed on a real machine; a path nobody has seen MUST NOT be guessed into it.

The repository MUST also state what a full uninstall **cannot** remove: Homebrew's uninstall has no
Keychain facility, so the two generic-password items Cellar creates —
`com.juancasanueva.cellar.nvd-api-key` and `com.juancasanueva.cellar.github-pat` — survive it. Naming
them is the whole obligation; this change MUST NOT add code to delete them.

The install and uninstall instructions MUST be documented **in this repository** as whole,
copy-pasteable lines rather than as fragments a reader must assemble, and MUST state that the installed
bundle is `cellar.app`. The short install form is canonical, and the fully-qualified form MUST also be
documented as the unambiguous one, because an unqualified token can later be claimed elsewhere.

Adding this second channel MUST NOT widen what the release run reaches: the release workflow MUST NOT
declare a cross-repository dispatch and MUST NOT name any repository other than the one it runs in.
A channel documented here MUST NOT become a write target there.

#### Scenario: The documented inventory covers every write root the source declares

- GIVEN the shipped app and core sources
- WHEN every application-support and cache write root they declare is enumerated
- THEN each enumerated root appears in the uninstall inventory documented in the repository
- AND the enumeration is non-vacuous: the scan finds every root the source declares, and the documented inventory additionally lists every root measured on a real machine, including framework-written roots that no source file declares
- Verification: `unit`

#### Scenario: The two Keychain items are documented as surviving a full uninstall

- GIVEN the release documentation in the repository
- WHEN it is read
- THEN it names `com.juancasanueva.cellar.nvd-api-key` and `com.juancasanueva.cellar.github-pat` as
  items a full uninstall does not remove
- Verification: `unit`

#### Scenario: The install commands are documented as whole lines

- GIVEN the repository's README
- WHEN its install section is read
- THEN it carries each brew command as a complete line a reader can copy and run
- AND it states that the installed bundle is `cellar.app` and gives the fully-qualified form
- Verification: `unit`

#### Scenario: The release run gains no cross-repository reach

- GIVEN the release workflow
- WHEN it is inspected structurally
- THEN it declares no cross-repository dispatch
- AND it names no repository other than the one it runs in
- Verification: `unit`

## Notes for archive

- Both blocks above are **appended** to `openspec/specs/release-distribution/spec.md`. Every one of the
  eight existing requirements is untouched, and no existing scenario is edited or deleted.
- **Hand-update the `## Verification classes` table.** It lives outside every requirement block, so an
  ADDED delta structurally cannot carry it. Two edits are required, and the second is easy to miss:
  1. **Counts**: from `unit` **14** / `ci-gate` **14** / `manual-evidence` **4** (total 32) to
     `unit` **18** / `ci-gate` **17** / `manual-evidence` **6** (total **41**).
  2. **Meanings**: `ci-gate` currently reads "a hard gate inside **the release run**" and
     `manual-evidence` reads "no harness can exist". Three of this delta's `ci-gate` scenarios run in
     `juancasanueva/homebrew-cellar`, not in this repository's release run, so the `ci-gate` meaning
     MUST widen to "a hard gate whose failure fails its job and commits or publishes nothing", with the
     runner named. Updating the counts without the meaning would leave the table stating something
     false.
  Confirm the arithmetic against the merged file by counting `- Verification:` lines rather than
  trusting this note.
- Extend the provenance section with this change's binding decisions **D1–D5**, each naming what was
  rejected: D1 the pull-based bump in the tap repository (rejected: a cross-repository dispatch from
  the release job, a second workflow here, and manual-only bumping); D2 the deletion of the declined
  extension-point comment; D3 `app "cellar.app"` with no rename (rejected: `target:`, which would split
  the two channels and perturb in-place self-replacement); D4 the GitHub homepage, which makes a
  `verified:` parameter an audit error rather than a courtesy; D5 the tap repository carrying its own
  README.
- Record that the main spec's inherited-contract paragraph is now **consumed** — `m6-cask-tap` binds
  its cask to the asset URL, the `cellar.app` bundle name, the arm64 pin and the macOS 26.0 floor
  exactly as that paragraph anticipated, and re-derives none of them.
- Record the deferred follow-ups so they are not re-derived: the `Home-Cellar.app` rename, moving
  `~/Library/Caches/Cellar` under the bundle id (a migration), and submission to `homebrew/cask`
  (notability requirements unmet — the self-hosted tap is the channel).
