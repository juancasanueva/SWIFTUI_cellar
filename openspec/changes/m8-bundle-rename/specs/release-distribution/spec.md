# Delta for release-distribution

Existing capability — `openspec/specs/release-distribution/spec.md` (**10 requirements / 41
scenarios**). This delta is **3 MODIFIED, 0 added, 0 removed, 0 renamed**: **16 scenarios** replace the
15 the three modified blocks carry today, taking the capability to **10 requirements / 42 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. Each MODIFIED block is a whole-block replacement copied from the main spec and then edited;
the seven untouched requirements stay byte-identical.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m8-bundle-rename/` + Engram canonical project
`swiftui_cellar`), `delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD
disabled clone-local.

**One name on disk.** The delivered bundle is named `cellar.app` while the cask token, the release
asset, and the display name all say `Home-Cellar`. This delta collapses those to one user-visible
name and pins, as requirement text, the identity that must not move with it: the bundle identifier
`com.juancasanueva.cellar`. The rename is a rename of *delivered names*, never of *identity*, and it
moves no user-data path.

## Verification classes — with the runner named per class

Every scenario below declares exactly one verification class, using the meanings already established
by the capability's own `## Verification classes` table.

| Class | Runner | Count |
|---|---|---|
| `unit` | `xcodebuild test … -only-testing:cellarTests` in **this** repository | **5** |
| `ci-gate` | the release run in `.github/workflows/release.yml` **here**, or `ci.yml` / `bump.yml` in **`juancasanueva/homebrew-cellar`** — named per scenario | **9** |
| `manual-evidence` | the maintainer's observed output, recorded verbatim in `design.md` and the verify report | **2** |

## MODIFIED Requirements

### Requirement: A pushed tag is the only thing that produces a downloadable release

Publication MUST be reachable only from a pushed tag matching `v*`, with **no manual step between the
push and the published asset**. A published release for tag `vX.Y.Z` MUST carry exactly one
downloadable asset, named **`Home-Cellar-<version>.zip`**, where `<version>` is the tag with its
leading `v` removed. The asset MUST be reachable at
`https://github.com/<owner>/<repo>/releases/download/v<version>/Home-Cellar-<version>.zip`, and the
bundle inside it MUST be **`Home-Cellar.app`** with display name **`Home-Cellar`** and main executable
**`Contents/MacOS/Home-Cellar`**.

The delivered bundle's identifier MUST remain **`com.juancasanueva.cellar`**. The name a person reads
changes; the identity the machine binds to does not. Every application-support root, cache root,
Keychain item and update host-match already derives from that identifier and from no product name, so
renaming the bundle MUST move no user data and MUST require no migration of any kind.

An asset nobody can download is not a release: a run against a repository that is not anonymously
readable MUST fail fast, with an explicit message, **before** any signing or notarization work, and
MUST publish nothing.

A run for a **stable** tag — one whose version carries no hyphen — MUST additionally publish an update
feed describing that release, served over `https` from the project's GitHub Pages site. The feed is a
**site artifact, not a release asset**, so the one-asset rule above is unaffected: the published release
still carries exactly one downloadable asset. Publishing the feed MUST NOT require a version-control
push and MUST NOT require a second release-management invocation beyond the single one that creates the
release; it MUST reuse the run's already-published asset URL. A run for a **prerelease** tag — one whose
version contains a hyphen — MUST publish the release and MUST NOT publish any feed entry for it, so that
an installed copy of the app is never offered a prerelease.
(Previously: the requirement covered only the single downloadable release asset and its reachability; a
stable tag published no update feed, and prereleases had no stated feed consequence; and the bundle
inside the asset was `cellar.app`, with neither the executable name nor the bundle identifier stated
here.)

#### Scenario: A tag produces one correctly named, anonymously reachable asset

- GIVEN a pushed tag `v1.0.0` on a publicly readable repository
- WHEN the release run completes
- THEN a GitHub Release for `v1.0.0` exists carrying exactly one asset named `Home-Cellar-1.0.0.zip`
- AND that asset is downloadable from the documented URL without authentication
- Verification: `ci-gate`

#### Scenario: The bundle inside the zip is the one the follow-up slices bind against

- GIVEN the published `Home-Cellar-<version>.zip`
- WHEN it is extracted
- THEN it contains exactly one application bundle, named `Home-Cellar.app`
- AND that bundle's display name is `Home-Cellar` and its main executable is `Contents/MacOS/Home-Cellar`
- AND its bundle identifier is `com.juancasanueva.cellar`
- Verification: `ci-gate`

#### Scenario: Nothing but a version tag can trigger a release

- GIVEN the repository's workflow definitions
- WHEN their triggers are inspected structurally
- THEN the release workflow is triggered only by a pushed tag matching `v*`
- AND no pull-request, schedule, or branch-push trigger and no test action is declared on it
- Verification: `unit`

#### Scenario: A private repository fails fast instead of publishing an unreachable asset

- GIVEN a release run on a repository that is not publicly readable
- WHEN the run starts
- THEN it fails with an explicit message before any signing or notarization step executes
- AND no release, tag asset, or partial artifact is published
- Verification: `ci-gate`

#### Scenario: A stable tag also publishes the update feed, without a push and without a second release call

- GIVEN a pushed stable tag `v1.0.0` whose release and asset have been published
- WHEN the run completes
- THEN the update feed served from the project's GitHub Pages site carries an entry for `1.0.0` whose
  enclosure is the run's published `https` asset URL
- AND the run performed no version-control push and no release-management invocation beyond the single
  one that created the release
- AND every entry published by an earlier stable tag is still present in the feed
- Verification: `ci-gate`

#### Scenario: A prerelease tag publishes a release and no feed entry

- GIVEN a pushed tag `v0.0.1-rc.1`
- WHEN the run completes
- THEN the release and its single asset are published
- AND the update feed contains no entry for `0.0.1-rc.1`
- AND the feed is left exactly as the previous stable tag published it
- Verification: `ci-gate`

### Requirement: The delivered build is installable through the project's Homebrew tap

Cellar tells its users that Homebrew is the source of truth, so the delivered build MUST be installable
through Homebrew and not only by dragging a downloaded zip. The project MUST publish a Homebrew tap
whose cask installs **the same published asset this capability already specifies** — no second artifact,
no separately built binary, and no mirrored copy.

Adding the tap and installing the cask MUST place the delivered bundle at
**`/Applications/Home-Cellar.app`**, whose `CFBundleShortVersionString` equals the released version and
whose bundle identifier is `com.juancasanueva.cellar`. The installed bundle name is the one the zip
already carries, so the cask channel and the direct-download channel install **the same path under the
same name**. The cask MUST NOT rename what it installs and MUST NOT declare a `target:`, because a
`target:` would make the two channels disagree again.

The rename of the delivered bundle is **update-safe, not update-migrating**, and MUST stay that way. A
fresh install through either channel MUST produce `Home-Cellar.app`. An update delivered to an
already-installed copy MUST be installed at that copy's **existing** bundle path — located by display
name or, failing that, by bundle identifier — so no update ever fails because the delivered bundle's
name changed, and the app MUST NOT declare an update-time bundle-name override to force a different
path. Because there is no installed base at the time of this change, **no migration mechanism MUST
exist anywhere**: no `target:` stanza, no `/Applications/cellar.app` entry in the cask's zap inventory,
no `uninstall delete:` naming it, and no migration instruction in the repository or in the app. A zap
MUST NOT delete a bundle the cask never placed.

A cask's `app` artifact MUST name the bundle that the version it declares actually contains. The
automated bump path gates only on style and audit, and **neither extracts the archive nor resolves the
`app` artifact**, so a cask naming a bundle its declared asset does not contain audits clean and
installs broken. A change to the delivered bundle's name MUST therefore reach the tap **before** the tag
that publishes the renamed asset is pushed.

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
(Previously: the installed bundle was `/Applications/cellar.app` and the requirement forbade renaming
it; the update-continuity, no-migration-mechanism and tap-before-tag ordering clauses did not exist.)

#### Scenario: A tap and an install put the released build in `/Applications`

- GIVEN a Mac with Homebrew that has never had Cellar installed
- WHEN the project's tap is added and its cask is installed
- THEN `/Applications/Home-Cellar.app` exists and reports the released version
- AND the app launches without a Gatekeeper refusal
- Verification: `manual-evidence`

#### Scenario: The cask is style-clean, audit-clean, and survives a real install/uninstall round trip

- GIVEN the cask as published in the tap repository
- WHEN the tap's CI runs style, offline audit, and online strict audit, then installs the cask and
  uninstalls it with a zap
- THEN every gate passes, the online audit confirms the declared checksum against the downloaded
  published asset, and the round trip completes
- AND the install resolves the cask's `app` artifact against a bundle the downloaded asset actually
  contains, rather than passing on audit alone
- AND a failing gate leaves nothing committed and nothing published
- Verification: `ci-gate` — `ci.yml` in `juancasanueva/homebrew-cellar`

#### Scenario: The rename ships no migration mechanism

- GIVEN the cask as published in the tap repository
- WHEN its artifact stanzas are inspected
- THEN its `app` artifact names `Home-Cellar.app` and declares no `target:`
- AND neither its zap inventory nor any `uninstall delete:` names `/Applications/cellar.app`, so a zap
  can only remove what the cask itself placed
- Verification: `ci-gate` — `ci.yml` in `juancasanueva/homebrew-cellar`

#### Scenario: A self-updated app does not fight `brew upgrade`

- GIVEN a cask-installed copy that has since updated itself in place to a newer version
- WHEN an upgrade is requested through Homebrew
- THEN Homebrew does not report the installed copy as outdated or reinstall over it
- AND the self-update replaced the bundle at its existing path rather than creating a second bundle
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

Renaming the delivered bundle MUST NOT change that inventory. Every documented write root derives from
the bundle identifier `com.juancasanueva.cellar` or from a literal the sources already carry, and none
derives from the product name, so no data root moves and no inventory entry is added, removed, or
repointed by this change.

The repository MUST also state what a full uninstall **cannot** remove: Homebrew's uninstall has no
Keychain facility, so the two generic-password items Cellar creates —
`com.juancasanueva.cellar.nvd-api-key` and `com.juancasanueva.cellar.github-pat` — survive it. Naming
them is the whole obligation; this change MUST NOT add code to delete them.

The install and uninstall instructions MUST be documented **in this repository** as whole,
copy-pasteable lines rather than as fragments a reader must assemble, and MUST state that the installed
bundle is `Home-Cellar.app`. Exactly one bundle name MUST appear across those instructions: no
alternative name, no "formerly known as" caveat, and no migration guidance. The short install form is
canonical, and the fully-qualified form MUST also be documented as the unambiguous one, because an
unqualified token can later be claimed elsewhere.

Adding this second channel MUST NOT widen what the release run reaches: the release workflow MUST NOT
declare a cross-repository dispatch and MUST NOT name any repository other than the one it runs in.
A channel documented here MUST NOT become a write target there.
(Previously: the documented installed bundle was `cellar.app`, one name was documented without an
exclusivity clause, and the inventory's independence from the bundle name was unstated.)

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
- AND it states that the installed bundle is `Home-Cellar.app` and gives the fully-qualified form
- AND no other bundle name and no migration instruction appears in that section
- Verification: `unit`

#### Scenario: The release run gains no cross-repository reach

- GIVEN the release workflow
- WHEN it is inspected structurally
- THEN it declares no cross-repository dispatch
- AND it names no repository other than the one it runs in
- Verification: `unit`

## Notes for archive

- **R7 — Provenance prose must be hand-updated; a MODIFIED delta structurally cannot carry it.** Three
  places in `openspec/specs/release-distribution/spec.md` sit **outside every requirement block** and
  will still name the old bundle after these three blocks are merged. `sdd-archive` MUST edit them by
  hand, exactly as the verification-class counts were hand-updated at `:627-632`:
  - `:619` — the `m6-sparkle-updates` provenance paragraph reads `Contents/MacOS/cellar` as the probe
    `U31` measurement. This is a **historical measurement**: keep the recorded fact, and mark that the
    path is now `Contents/MacOS/Home-Cellar` rather than silently rewriting what was measured.
  - `:686-688` — `m6-cask-tap` **D3** records "this change MUST NOT rename it", `app "cellar.app"` with
    no `target:`, and the rejection of `target: "Home-Cellar.app"`. Record that `m8-bundle-rename`
    performed the rename D3 deferred, and that the rejection of `target:` **still stands** — the cask
    now names `Home-Cellar.app` directly, which is not the rejected alternative.
  - `:718-720` — the deferred-slice list names "the `Home-Cellar.app` rename (its own slice —
    `PRODUCT_NAME`, four `release.sh` gates, this spec's bundle-name scenario, and update continuity
    for every installed 1.0.0 copy)". That entry MUST move from *deferred* to *landed*, and the
    "update continuity for every installed 1.0.0 copy" clause MUST be recorded as **closed by D1**: the
    installed base was empty, so no continuity work was owed. The other two deferred items (cache dir
    under the bundle id; `homebrew/cask` submission) stay deferred.
- **The `## Verification classes` table MUST be hand-updated.** The table lives outside every
  requirement block. This delta adds **one** scenario (*The rename ships no migration mechanism*,
  `ci-gate`), so the counts move from `unit` 18 / `ci-gate` 17 / `manual-evidence` 6 (total 41) to
  `unit` **18** / `ci-gate` **18** / `manual-evidence` **6** (total **42**). Confirm the arithmetic
  against the merged file by counting `- Verification:` lines, not by trusting this note.
- **This diverges from the proposal's "counts are unchanged" line, deliberately.** The proposal derived
  from D1 that explore §2.H's new update-continuity scenario was dropped. It is instead carried here as
  a scenario **inside** the existing tap requirement, adapted to D1 so it asserts the *absence* of every
  migration mechanism rather than behaviour for an installed base of zero. The proposal's binding
  Capabilities contract — three MODIFIED requirements, **zero ADDED requirements**, zero removed, zero
  renamed — is honoured exactly; only the scenario count moves.
- **The ordering constraint (R4) is requirement text, not only a note.** "A change to the delivered
  bundle's name MUST therefore reach the tap **before** the tag that publishes the renamed asset is
  pushed" is now binding spec text, because a cask that audits clean and installs broken is a property
  of the delivered build. `sdd-tasks` MUST still carry it as an explicit ordering dependency between
  work units, and `bump.yml` itself is untouched by this change.
- **The bundle identifier is now requirement text, not prose.** `com.juancasanueva.cellar` appears in
  the first and second MODIFIED blocks. `ReleasePipelineCompositionTests.swift:94` and
  `UpdateProjectFileTests.swift:68` already guard it and MUST stay green untouched — they are the
  proof the invariant held across the rename.
- **No requirement is added, removed, or renamed**, so no capability count in any other spec changes,
  and `rules.archive`'s destructive-delta warning does not fire.
