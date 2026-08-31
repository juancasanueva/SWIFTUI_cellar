# release-distribution

This capability owns **what must be true of a build Cellar delivers to a stranger**: how a tag becomes
a downloadable asset, what that asset is named and where it lives, what the app inside it is stamped
with, what it is signed and hardened with, what Gatekeeper does with it on a machine that has never
seen it, what the repository is allowed to contain while producing it, and what a release run is never
allowed to do to the releases that came before it.

## Verification classes

Every scenario in this file declares exactly one verification class, and no requirement is written
that no test or gate could ever check:

| Class | Meaning | Count |
|---|---|---|
| `unit` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom (reads the repository or the test host's bundle information off disk), run by `xcodebuild test … -only-testing:cellarTests` in **this** repository | **18** |
| `ci-gate` | a hard gate whose failure fails its job and commits or publishes nothing. The runner is named per scenario: the release run in `.github/workflows/release.yml` **here**, or `ci.yml` / `bump.yml` in **`juancasanueva/homebrew-cellar`** on `macos-26` for the cask channel | **18** |
| `manual-evidence` | no harness can exist — no runner may install into a real `/Applications` or observe a self-updated app — so the maintainer's observed output is recorded verbatim in `design.md` and the verify report | **6** |

What stays **design-owned and is deliberately absent here**: the runner image and Xcode pinning, the
export/notarize/staple command sequence and its ordering rationale, the ephemeral-keychain mechanics,
`actionlint`, the dry-run prerelease rehearsal, and the `--generate-notes` release body. Those are
*how* the contract is met, and none of them is a property of a delivered build.

## Requirements

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

### Requirement: The tag is the version, and a mislabelled build never ships

The delivered bundle's `CFBundleShortVersionString` MUST equal the tag with its leading `v` removed,
and this MUST be asserted **before notarization** — a mismatch MUST fail the run rather than ship a
mislabelled release. `CFBundleVersion` MUST equal the release run number, and MUST strictly increase
across successive published releases, including re-cut tags for the same marketing version.

The checked-in project MUST NOT be bumped per release: version values MUST be supplied at build time,
and `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` MUST remain at `1.0.0` / `1` in the project file.
The consequence — a locally archived build reports `1.0.0 (1)` regardless of the current tag — MUST be
recorded in the repository as a documented fact together with the exact one-line override that
produces a correctly stamped local build. It MUST NOT be left as an undocumented trap for manual
testing.

#### Scenario: A version mismatch stops the run before Apple ever sees the build

- GIVEN an exported build whose `CFBundleShortVersionString` does not equal the tag minus `v`
- WHEN the version assertion runs
- THEN the run fails
- AND no notarization submission and no publication occurred
- Verification: `ci-gate`

#### Scenario: The tag and run number reach the delivered bundle

- GIVEN a run for tag `v1.0.0` with run number `N`
- WHEN the delivered bundle's information is read
- THEN `CFBundleShortVersionString` is `1.0.0` and `CFBundleVersion` is `N`
- Verification: `ci-gate`

#### Scenario: `CFBundleVersion` never goes backwards across releases

- GIVEN two successively published releases, including a re-cut tag for the same marketing version
- WHEN their `CFBundleVersion` values are compared
- THEN the later release's value is strictly greater than the earlier one's
- Verification: `manual-evidence` (checkable from the second published release onward)

#### Scenario: Releasing does not edit the project file, and the cost is documented

- GIVEN the repository after this change
- WHEN the project file and the release documentation are inspected
- THEN `MARKETING_VERSION` is `1.0.0` and `CURRENT_PROJECT_VERSION` is `1`, unchanged by any release
- AND the documentation states that a local archive reports `1.0.0 (1)` and carries the exact override
  command that corrects it
- Verification: `unit`

### Requirement: arm64 only, hardened, unsandboxed, and no entitlement added to get there

The delivered **application executable** MUST contain the `arm64` slice and no other. A prebuilt
third-party framework vendored into the bundle MAY carry additional architecture slices, because
thinning it would require either a sandboxed build phase or a post-export re-sign that takes signing
ownership away from the export step; that cost is not worth paying, and stating it is more honest than
implying a bundle-wide guarantee that has never been enforced. The delivered bundle MUST have the
hardened runtime enabled and the app sandbox disabled.
(Previously: "The delivered binary MUST contain the **`arm64` slice and no other**", which read as a
bundle-wide claim while only the application executable was ever checked.)

**No `.entitlements` file MUST exist in the repository**, and no entitlement MUST be added to make the
delivered build work. Specifically, `allow-jit`, `allow-unsigned-executable-memory` and
`disable-library-validation` MUST NOT be present: spawning `/opt/homebrew/bin/brew` as a separate
process is neither JIT nor foreign code loaded into Cellar's address space. The repository MUST carry
a written rationale for this posture, based on **measured** signing output from a notarized build
rather than on assumption, and that rationale MUST also explain what `ENABLE_USER_SELECTED_FILES` and
`REGISTER_APP_GROUPS` mean while the sandbox is disabled.

#### Scenario: The delivered application executable is single-architecture

- GIVEN the exported application executable
- WHEN its architectures are enumerated
- THEN `arm64` is the only one reported
- AND the run fails if any other slice is present in the application executable
- AND a vendored prebuilt framework carrying additional slices does not fail the run
- Verification: `ci-gate`

#### Scenario: The delivered bundle is hardened and unsandboxed

- GIVEN the app extracted from the published zip
- WHEN its code signature attributes are read
- THEN the hardened runtime flag is set
- AND no app-sandbox entitlement is present
- Verification: `ci-gate`

#### Scenario: No entitlements file exists anywhere in the repository

- GIVEN the repository tree after this change
- WHEN it is inspected structurally
- THEN no `.entitlements` file exists
- AND no build configuration references an entitlements file
- Verification: `unit`

#### Scenario: The rationale names what is absent and why

- GIVEN the release documentation in the repository
- WHEN it is read
- THEN it names `allow-jit`, `allow-unsigned-executable-memory` and `disable-library-validation` as
  deliberately absent, with the reason
- AND it explains `ENABLE_USER_SELECTED_FILES` and `REGISTER_APP_GROUPS` under a disabled sandbox
- Verification: `unit`

#### Scenario: A hardened, notarized, stapled build still drives Homebrew

- GIVEN the notarized, stapled build installed and launched on a real machine
- WHEN a real Homebrew mutation is performed from it
- THEN the mutation completes
- AND it completed with no entitlement added to reach that result
- Verification: `manual-evidence`

### Requirement: Gatekeeper accepts the artifact users actually download, offline

The app **extracted from the published zip** — not an intermediate build product — MUST be Developer ID
Application-signed under team `Z3S5JK8E38`, notarized, and **stapled**, such that Gatekeeper
assessment for installation and staple validation both accept it **with networking disabled**. These
checks MUST run as a hard gate before publication.

The stapled ticket MUST travel inside the published archive: an archive assembled before stapling MUST
NOT be the published asset, because first launch would then require network access to succeed.

#### Scenario: The published artifact passes assessment offline

- GIVEN the app extracted from the published zip into a temporary location, with networking disabled
- WHEN Gatekeeper install assessment and staple validation are run against it
- THEN both accept it
- AND the run fails, publishing nothing, if either does not
- Verification: `ci-gate`

#### Scenario: The signature is the expected Developer ID identity

- GIVEN the extracted app
- WHEN its signing information is read
- THEN it reports a Developer ID Application authority for team `Z3S5JK8E38`
- Verification: `ci-gate`

#### Scenario: A stranger's first launch is a single "Open"

- GIVEN the published zip downloaded through a browser onto a machine that has never seen the bundle,
  carrying the quarantine attribute
- WHEN it is unzipped, moved to `/Applications` and opened for the first time
- THEN the app launches after a single ordinary confirmation, with no Gatekeeper refusal and no
  right-click workaround
- Verification: `manual-evidence`

### Requirement: A release is all-or-nothing, and release history is never rewritten

If any gate fails — version assertion, architecture, notarization, assessment, or staple validation —
the run MUST fail **before publishing**, leaving no release, no asset, and no partially published
state. A rejected or delayed notarization MUST be surfaced with its diagnostic log rather than
silently retried past the gate.

Publication MUST occur only from the automated release run. A local execution of the release logic
MUST be a rehearsal that produces the same artifact and publishes nothing.

A release run MUST NOT delete, unpublish, retract, or change the flags of **any previously published
release or tag**. Withdrawing a bad release is a deliberate maintainer action, never an automatic side
effect of publishing the next one.

#### Scenario: A failed gate publishes nothing at all

- GIVEN a run in which notarization is rejected
- WHEN the run terminates
- THEN it failed, the notarization diagnostic log is present in the run output
- AND no release, asset, or draft exists for that tag
- Verification: `ci-gate`

#### Scenario: Prior releases survive the next one untouched

- GIVEN one or more previously published releases
- WHEN a new tag is published
- THEN every prior release and tag is still present, still published, and its prerelease/latest flags
  are unchanged
- Verification: `ci-gate`

#### Scenario: Nothing in the repository can retract a release

- GIVEN the release workflow and scripts
- WHEN they are inspected structurally
- THEN none of them deletes a release, deletes a tag, or edits a prior release's flags
- Verification: `unit`

#### Scenario: The local path rehearses but cannot publish

- GIVEN the release script in the repository
- WHEN it is inspected structurally
- THEN it carries the build, sign, notarize, staple and verify sequence
- AND it contains no release-publishing command; publication exists only in the automated workflow
- Verification: `unit`

### Requirement: Release infrastructure lives outside the shipped app sources

`cellar/` is a synchronized root group: any file placed inside it joins the app target and ships inside
the bundle. Release infrastructure MUST therefore live **outside** it — export options and release
scripts under `scripts/`, workflow definitions under `.github/` — and this placement MUST be enforced
by a test, not by a comment.

No release script, export options file, workflow definition, or signing configuration MUST appear
inside the delivered bundle's resources. The export configuration MUST declare the `developer-id`
distribution method and team `Z3S5JK8E38`.

#### Scenario: The infrastructure is where it belongs, and nowhere else

- GIVEN the repository tree after this change
- WHEN it is inspected structurally
- THEN `scripts/ExportOptions.plist`, `scripts/release.sh` and the release workflow under `.github/`
  all exist
- AND no export options file, release script, or workflow definition exists anywhere under `cellar/`
- Verification: `unit`

#### Scenario: The export configuration declares Developer ID distribution

- GIVEN `scripts/ExportOptions.plist`
- WHEN it is read
- THEN its distribution method is `developer-id` and its team identifier is `Z3S5JK8E38`
- Verification: `unit`

#### Scenario: None of it ships to the user

- GIVEN the app extracted from the published zip
- WHEN its bundled resources are enumerated
- THEN no release script, export options file, workflow definition, or signing configuration is
  present among them
- Verification: `ci-gate`

### Requirement: No credential material in the repository, and injected credentials die with the run

No signing certificate, private key, password, or API key MUST exist in the repository in any form —
not in source, scripts, configuration, build settings, generated property lists, or documentation. A
committed key header, archived certificate blob, or literal secret value MUST fail the build.

Credentials MUST be injected at run time from the platform's secret storage into storage created for
that run alone, and that storage MUST be destroyed **unconditionally at the end of the run, including
when the run fails**. No step handling a credential MUST enable shell command tracing, and no
credential value MUST ever be written to the run's log.

The set of repository secrets the release run may reference MUST be **closed and enumerated**: exactly
the **seven** named `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`,
`APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, and `SPARKLE_PRIVATE_KEY`.
Referencing a secret outside that set MUST fail a test. Adding one is allowed; adding one without
updating the enumerated set is not. The update-signing private key MUST be piped to the signing tool on
standard input, never written to disk and never echoed; its **public** counterpart is public by
construction, ships inside every copy of the app, and MUST NOT be handled as a secret.
(Previously: the requirement forbade credential material and mandated ephemeral, untraced injection,
but never stated that the referenced secret set is closed or which secrets it contains.)

#### Scenario: The repository carries no secret material

- GIVEN every file in the repository
- WHEN they are inspected for key headers, archived certificate blobs and literal credential values
- THEN none is present
- Verification: `unit`

#### Scenario: The referenced secret set is exactly the seven named ones

- GIVEN the release workflow
- WHEN every repository secret it references is collected
- THEN the collected set is exactly the seven named in this requirement, including
  `SPARKLE_PRIVATE_KEY`
- AND no eighth secret is referenced
- Verification: `unit`

#### Scenario: Credential cleanup cannot be skipped by a failure

- GIVEN the release workflow
- WHEN its steps are inspected structurally
- THEN the credential-storage deletion step is declared to run unconditionally, including after a
  failed step
- Verification: `unit`

#### Scenario: No step traces its own commands around a credential

- GIVEN the release workflow and scripts
- WHEN their executable lines are inspected
- THEN no line enables shell command tracing
- AND no line echoes, prints, or writes a credential value to output
- Verification: `unit`

#### Scenario: A completed run's log contains nothing sensitive

- GIVEN the full log of a completed release run
- WHEN it is read end to end
- THEN no certificate, key, password, or API key value appears in it
- Verification: `manual-evidence`

### Requirement: The delivered build states who made it

The delivered bundle MUST report a non-empty human-readable copyright string,
**`Copyright © 2026 Juan Casanueva. All rights reserved.`** A 1.0 that ships an empty copyright line is
a visible omission in the Finder inspector and in the About window.

The string catalog MUST remain the authority for that value, consistent with the two bundle-name keys
it already owns; the build setting MUST NOT be used to carry it, because two sources for one key drift.

#### Scenario: The copyright string is present and correct

- GIVEN the app bundle's information
- WHEN the human-readable copyright value is read
- THEN it is `Copyright © 2026 Juan Casanueva. All rights reserved.`
- AND it is not empty and not a placeholder
- Verification: `unit`

#### Scenario: The string catalog is the single authority for it

- GIVEN `cellar/InfoPlist.xcstrings` and the project's build settings
- WHEN both are inspected
- THEN the catalog carries the copyright value alongside the existing bundle-name keys
- AND the corresponding build setting carries no competing value
- Verification: `unit`

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
installs broken. A change to the delivered bundle's name MUST therefore reach the tap in **one atomic
commit that moves `version`, `sha256` and the `app` artifact together**, applied **after** the first
release whose published asset actually contains the renamed bundle — never ahead of that release, since
a cask naming a bundle its already-declared version lacks is the same violation in the other direction.
Across that window the automated bump MUST be paused, or its open pull request superseded, until that
commit lands: it moves `version` and `sha256` without the `app` artifact, re-opening the same mismatch.

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
it; the update-continuity, no-migration-mechanism and atomic-tap-commit ordering clauses did not exist.)

#### Scenario: A tap and an install put the released build in `/Applications`

- GIVEN a Mac with Homebrew that has never had Cellar installed
- WHEN the project's tap is added and its cask is installed
- THEN `/Applications/Home-Cellar.app` exists and reports the released version
- AND the app launches without a Gatekeeper refusal
- Verification: `manual-evidence`

#### Scenario: The cask is style-clean, audit-clean, and survives a real install/uninstall round trip

- GIVEN a cask commit that moves `version`, `sha256` and the `app` artifact together, against a release
  that is already published
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

## Provenance

- Established by change `m6-release-pipeline` (archived `2026-08-23`, PRD milestone **M6 "Ship"**,
  slice 2 of 3 — the tag-to-notarized-download pipeline), ADDED-only delta — **8 requirements /
  29 scenarios**, promoted from
  `openspec/changes/archive/2026-08-23-m6-release-pipeline/specs/release-distribution/spec.md`.
  This is the first main spec for the capability and the project's **21st**; nothing was modified,
  removed or renamed. This file adds the header, the `## Verification classes` heading with its one
  introductory sentence, the `## Requirements` wrapper and this provenance section — the requirement
  and scenario bodies are byte-identical to the delta's, and the class table and the design-owned
  paragraph are carried verbatim from it.
- **This capability owns what must be true of a delivered build, never how the build is produced.**
  The runner image, the Xcode pin, the export/notarize/staple command sequence, the ephemeral-keychain
  mechanics and the release body are design-owned and archived with the change, not specified here.
  It adds no `CellarCore` code and no SwiftUI view, so `rules.specs`' "CellarCore types" clause has no
  subject in it; the narrowing that replaces the clause is the per-scenario verification class above.
- **Execution status at promotion (2026-08-23).** The pipeline is *implemented and structurally
  verified*, not *proven end to end*. Per `verify-report` (Engram `#7669`, verdict
  `pass_with_warnings`, 0 blockers): 13/13 `unit` scenarios are runtime-compliant; 12/12 `ci-gate`
  scenarios are structurally verified but have never executed against a real signed build; 4/4
  `manual-evidence` scenarios are documented with the exact accepted output but not yet observed.
  **16 of the 29 scenarios have never run against a delivered artifact** and cannot until a Developer
  ID Application certificate, an App Store Connect API key, the six repository secrets and the public
  visibility flip exist. That is a deferred release checklist, recorded in the archive report, not an
  open defect in this spec.
- Traceability to the change's binding decisions (proposal Engram `#7662`, D1–D10 user-approved). Each
  names what was rejected, so a later change cannot reintroduce a rejected alternative as a fresh
  idea:
  - **D2** → "A pushed tag is the only thing that produces a downloadable release", specifically the
    fail-fast on a non-anonymously-readable repository. The repository goes public for 1.0 because a
    release asset on a private repository is not anonymously downloadable and macOS runner minutes
    bill at 10×. **Rejected:** publishing an asset nobody outside the account can fetch.
  - **D3** → "arm64 only, hardened, unsandboxed, and no entitlement added to get there". Probe `U27`
    measured the archive at `ec7b1c5` as universal `x86_64 arm64`, so the `ARCHS = arm64` pin is a
    **fix**, not a formality — the PRD's arm64-only claim was being contradicted by the build.
    **Rejected:** a universal binary, which doubles the download and the compile time for a slice
    nobody on this floor can run.
  - **D4 / D7** → the artifact-identity clauses: a zip produced by
    `ditto -c -k --keepParent --sequesterRsrc`, named `Home-Cellar-<version>.zip`, containing
    `cellar.app` with display name `Home-Cellar`. **Rejected/deferred:** a DMG, to the landing-page
    follow-up. *(Historical: that is what D4/D7 decided and what shipped through `v1.1.0`. Since
    `m8-bundle-rename` (`v1.2.0`) the bundle inside the zip is `Home-Cellar.app`; the zip's own name
    and the display name are unchanged.)*
  - **D5 / D9** → "Gatekeeper accepts the artifact users actually download, offline" and "No credential
    material in the repository". Notarization authenticates with an App Store Connect API key, which
    also serves `-allowProvisioningUpdates`, so `CODE_SIGN_STYLE` stays `Automatic` and the Debug and
    Release build blocks stay byte-identical. **Rejected:** an Apple ID plus app-specific password
    (2FA-prompting, not independently revocable, useless for provisioning). The Manual signing flip is
    pre-authored as a fallback and is applied **only** on a measured headless-export failure.
  - **D6** → "The tag is the version, and a mislabelled build never ships". The git tag is the version
    source of truth; the project file stays at `1.0.0` / `1` forever. **Rejected:** bumping two pbxproj
    blocks per release, a recurring two-block merge hazard. The accepted cost — a locally archived
    build reports `1.0.0 (1)` regardless of the tag — is a *specified* documentation obligation here,
    not a trap left for manual testing.
  - **D10** → "The delivered build states who made it" and the entitlements-rationale scenarios. One
    `RELEASING.md` carries both the runbook and the PRD:157 rationale. **Rejected:** a separate
    `ENTITLEMENTS.md` — one release document the maintainer actually opens beats two nobody does.
  - **D1** (slice per explore 8d-B) and **D8** (PRD/README amended in the same PR) are process
    decisions with no property of a delivered build behind them, so they are carried by the change's
    `proposal.md` and deliberately **not** by a requirement here. Recorded so a later reader does not
    read their absence as a gap.
- **"No entitlement is added to get there" is the spine of this capability, not a hardening note.**
  Every entitlement weakens the hardened runtime and is visible in the notarization audit trail, and
  the repository's sandbox-era settings (`ENABLE_USER_SELECTED_FILES`, `REGISTER_APP_GROUPS`) sit inert
  only for as long as no `.entitlements` file exists — introducing one would make them live and
  re-activate the export-write trap recorded in the tip-jar archive. The rationale the spec demands is
  therefore required to quote **measured** `codesign` output from a notarized build, never an
  assumption.
- **A release is all-or-nothing, and this spec forbids the pipeline from touching release history.**
  Withdrawing a bad release is a deliberate maintainer action; `CFBundleVersion` comes from the run
  number precisely so it keeps increasing across a re-cut tag, which is what the future
  `m6-sparkle-updates` comparison requires.
- **Contract inherited by the follow-up slices.** `m6-sparkle-updates` binds its `<enclosure url>` and
  `m6-cask-tap` binds its cask `url` to
  `https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v<version>/Home-Cellar-<version>.zip`;
  the cask's `app` stanza must name `Home-Cellar.app` exactly, its token is `home-cellar`, and the
  arm64 pin plus the macOS 15.0 floor become `depends_on arch: :arm64` and
  `depends_on macos: ">= :sequoia"`.
  Those slices inherit these facts from this spec rather than re-deriving them.
  *(Superseded in part by `m8-bundle-rename`: this clause read `cellar.app` when it was written, and
  it states a **live** requirement rather than a historical measurement, so it was updated in place
  to match the merged requirement. Updated in place again for v1.8.3, which lowered the deployment
  floor from macOS 26.0 to 15.0 — the floor and `depends_on macos` above read `26.0` / `:tahoe`
  before that release. Everything else in this paragraph is unchanged.)*
- **Amended by change `m6-sparkle-updates`** (archived `2026-08-23`, PRD milestone **M6 "Ship"**,
  slice 3 of 3 — Sparkle 2 in-app updates), MODIFIED-only delta — **3 requirements replaced in full,
  0 added, 0 removed, 0 renamed**, taking the capability from **8 requirements / 29 scenarios** to
  **8 requirements / 32 scenarios**, promoted from
  `openspec/changes/archive/2026-08-23-m6-sparkle-updates/specs/release-distribution/spec.md`. The
  three replaced blocks are *A pushed tag is the only thing that produces a downloadable release*,
  *arm64 only, hardened, unsandboxed, and no entitlement added to get there*, and *No credential
  material in the repository, and injected credentials die with the run*. The other five requirements
  are byte-identical to their `m6-release-pipeline` text, and no scenario was deleted.
  - **(a)** A **stable** tag now also publishes an update feed to GitHub Pages, and a **prerelease**
    tag publishes no feed entry. The feed is a *site artifact, not a release asset*, so the
    one-downloadable-asset rule is unaffected. **+2 scenarios**, both `ci-gate`.
  - **(b)** The arm64 claim now binds the **application executable** and explicitly allows a vendored
    prebuilt framework to carry additional slices (decision **D2**). This is the honest wording for
    what the `lipo` gate has always read, not a weakening: probe `U31` measured
    `Sparkle.framework` as `x86_64 arm64` while `Contents/MacOS/cellar` stayed `arm64`.
    *(The `U31` measurement is preserved exactly as taken. Since `m8-bundle-rename` that same
    executable is at `Contents/MacOS/Home-Cellar`; the architecture finding is unaffected by the
    rename, which moved names and no bits.)*
    **Rejected:** `lipo -thin`, which needs a sandboxed build phase or a post-export re-sign that
    takes signing ownership away from `-exportArchive`. 0 scenarios added; the architecture scenario
    was reworded to follow.
  - **(c)** The referenced repository-secret set is now stated as **closed and enumerated at seven**,
    gaining `SPARKLE_PRIVATE_KEY`. The update-signing private key is piped to the signing tool on
    standard input, never written to disk; its public counterpart ships inside every copy of the app
    and is not a secret. **+1 scenario**, `unit`.
- **The `## Verification classes` counts were hand-updated at archive**, from `unit` 13 / `ci-gate` 12
  / `manual-evidence` 4 (total 29) to `unit` **14** / `ci-gate` **14** / `manual-evidence` **4**
  (total **32**). The table lives outside every requirement block, so a MODIFIED delta structurally
  cannot carry it; the delta's *Notes for archive* stated the obligation and the archive step
  confirmed the arithmetic against the merged file by counting `- Verification:` lines rather than
  trusting the note.
- **The stowaway scenario was deliberately NOT touched.** A fourth MODIFIED block scoping
  *None of it ships to the user* to exclude `Contents/Frameworks/` was pre-authorised **only** if
  probe `U32` fired. It did not: the `find` sweep over the built bundle and again over the exported,
  notarized bundle both returned empty, so `release.sh`'s sweep is unchanged and the scenario stands
  as written.
- **Execution status at the amendment (2026-08-23).** The maintainer prerequisites this spec's
  original promotion listed as unmet are now **met**: the repository is public, the Developer ID
  certificate and App Store Connect key exist, all **seven** secrets are set, and `v0.0.1-rc.1` was
  published by a real release run whose notarization was `Accepted`
  (`593818bf-c3db-460d-b674-3db6078732b6`). Of the four change-owned scenarios, `RD-c` is
  runtime-proven and `RD-b` was re-measured locally and on the exported bundle; `RD-a1` and `RD-a2`
  are **structurally verified but never executed** — the feed URL returns `404` and will until the
  first stable tag. That is the pre-agreed shape of a publication path, not an open defect.
- **The inherited-contract paragraph above is now enforced from the release side.** `RD-a1` requires
  the feed entry's enclosure to be the run's own published `https` asset URL, so
  `m6-sparkle-updates`'s binding is a gate rather than a note.
- **Amended by change `m6-cask-tap`** (archived `2026-08-23`, PRD milestone **M6 "Ship"**, slice 4 of
  4 — the Homebrew tap and cask), ADDED-only delta — **2 requirements / 9 scenarios added, 0
  modified, 0 removed, 0 renamed**, taking the capability from **8 requirements / 32 scenarios** to
  **10 requirements / 41 scenarios**, promoted from
  `openspec/changes/archive/2026-08-23-m6-cask-tap/specs/release-distribution/spec.md`. Every one of
  the eight existing requirements is byte-identical to its prior text and no existing scenario was
  edited or deleted, so `rules.archive`'s destructive-delta warning did not fire. The two appended
  requirements are *The delivered build is installable through the project's Homebrew tap* (**+5
  scenarios**: 3 `ci-gate`, 2 `manual-evidence`) and *Uninstalling states exactly what it removes,
  and what it cannot* (**+4 scenarios**, all `unit`).
- **A tap is a second channel for the same delivered build, never a second artifact.** The cask
  installs the asset this capability already specifies; it authors no URL, no bundle name, no
  architecture pin and no OS floor. That is why `m6-cask-tap` added no capability of its own.
- **The `## Verification classes` table was hand-updated at archive**, from `unit` 14 / `ci-gate` 14
  / `manual-evidence` 4 (total 32) to `unit` **18** / `ci-gate` **17** / `manual-evidence` **6**
  (total **41**). Two edits were required, not one: the counts, **and** the `ci-gate` meaning, which
  read "a hard gate inside **the release run**" and is now "a hard gate whose failure fails its job
  and commits or publishes nothing". Three of the delta's `ci-gate` scenarios execute in
  `juancasanueva/homebrew-cellar` rather than in this repository's release run, so updating the
  counts alone would have left the table stating something false. The runner is now named per class.
  The arithmetic was confirmed against the merged file by counting `- Verification:` lines
  (18 / 17 / 6 = 41), not by trusting the delta's note.
- Traceability to `m6-cask-tap`'s binding decisions (proposal Engram `#7703`, **D1–D5**
  user-approved 2026-08-23). Each names what was rejected, so a later change cannot reintroduce a
  rejected alternative as a fresh idea:
  - **D1** → "Keeping the cask current MUST NOT require a manual step and MUST be idempotent on the
    declared version". The bump is a **pull** from a workflow in the tap repository, on a schedule
    plus `workflow_dispatch`, reading `releases/latest` anonymously. **Rejected:** a cross-repository
    `repository_dispatch` from the release job (which would put a cross-repo write PAT beside the
    Developer ID `.p12` and grow the closed seven-secret set to eight); a second workflow in this
    repository, unconstrained by `release.yml`'s file-scoped invariants; and manual-only bumping,
    kept only as the documented fallback. A missed dispatch is lost forever; a missed scheduled run
    is corrected by the next one.
  - **D2** → "The release run gains no cross-repository reach". The extension-point comment at
    `release.yml:175-176` was **deleted**, and its absence is asserted by a test. **Rejected:**
    leaving a promise the design declined, and deleting it without a test.
  - **D3** → "the installed bundle name is the one the zip already carries; this change MUST NOT
    rename it". The cask declares `app "cellar.app"` with no `target:`. **Rejected:**
    `target: "Home-Cellar.app"`, which splits the two install channels and perturbs Sparkle's
    in-place self-replacement. The `Home-Cellar.app` rename is logged as its own slice.
    *(That slice is `m8-bundle-rename`, landed 2026-08-23 in `v1.2.0`: it performed the rename D3
    deferred, so the cask now declares `app "Home-Cellar.app"`. **D3's rejection of `target:` still
    stands** and was not reopened — the cask names the new bundle **directly**, which is the
    opposite of the rejected alternative: both channels still install the same path under the same
    name, and Sparkle's in-place self-replacement is untouched.)*
  - **D4** → the checksum and audit clauses. `homepage` is the GitHub repository, so **no
    `verified:`** parameter is declared. **Rejected:** a landing-page homepage, which would make
    `verified:` mandatory; with matching domains `brew audit` raises *"the `verified` parameter is
    unnecessary"* as an **error**, not a courtesy.
  - **D5** → the user-facing half of "The install and uninstall instructions MUST be documented".
    The tap repository carries its own README. **Rejected:** a bare `Casks/` repository — `brew tap`
    users land on that page.
  - **DD-13** (MIT `LICENSE` in **both** repositories, maintainer decision 2026-08-23) is a process
    decision with no property of a delivered build behind it, so it is carried by the change's
    `design.md` and deliberately not by a requirement here. Recorded so a later reader does not read
    its absence as a gap. The same applies to the three accepted apply deviations **D-1**
    (`depends_on macos: :tahoe`, the current-syntax form of the same macOS 26.0 floor), **D-2** (the
    canonical documented install is **three** whole lines — `brew tap`, `brew trust`, `brew install
    --cask home-cellar` — because Homebrew 6 refuses short cask names from untrusted taps), and
    **D-3** (the test joined the `Release workflow contract` suite).
- **The inherited-contract paragraph above is now CONSUMED.** `m6-cask-tap` binds its cask `url` to
  `https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v<version>/Home-Cellar-<version>.zip`,
  its `app` stanza to `cellar.app`, its token to `home-cellar`, and its `depends_on` to
  `arch: :arm64` plus `macos: :tahoe` — exactly as that paragraph anticipated, re-deriving none of
  them. Both follow-up slices named there have now landed.
  *(Historical: `cellar.app` is what `m6-cask-tap` bound at the time. Since `m8-bundle-rename` the
  `app` stanza names `Home-Cellar.app`; the `url`, the token and the `depends_on` bindings recorded
  here are unchanged.)*
- **Execution status at the amendment (2026-08-23).** Of the nine scenarios this delta adds, **four
  `unit` are runtime-proven** in `cellarTests` with an independently re-proven RED→GREEN transition,
  **three `ci-gate` are run-proven** by `juancasanueva/homebrew-cellar` workflow runs on `macos-26`
  (`32642667011` style + both audits + a real install/zap round trip; `32642223493` and
  `32642400685` bump idempotence, zero commits), **one `manual-evidence` (a self-updated app does not
  fight `brew upgrade`) is observed and passing**, and **one `manual-evidence` (first install on a
  Mac that has never had Cellar) is WAIVED** by maintainer decision 2026-08-23, with the tap CI's
  install/zap round trip on a clean `macos-26` runner standing as the clean-machine evidence. That
  waiver is recorded in the archive report, not smoothed away here.
- **Deferred, recorded so they are not re-derived**: ~~the `Home-Cellar.app` rename (its own slice —
  `PRODUCT_NAME`, four `release.sh` gates, this spec's bundle-name scenario, and update continuity
  for every installed 1.0.0 copy)~~ — **LANDED** as `m8-bundle-rename` (2026-08-23, `v1.2.0`); its
  "update continuity for every installed 1.0.0 copy" clause is **closed by D1**, because the
  installed base was empty at the time of the rename, so no continuity work was ever owed and **no
  migration mechanism was built**. Still deferred: moving `~/Library/Caches/Cellar` under the bundle
  id (a migration); and submission to `homebrew/cask` (notability requirements unmet — the
  self-hosted tap is the channel).
- **Amended by change `m8-bundle-rename`** (archived `2026-08-23`, PRD milestone **M6 "Ship"**,
  specifically its cask-channel line `PRD.md:194`), MODIFIED-only delta — **3 requirements replaced
  in full, 0 added, 0 removed, 0 renamed**, taking the capability from **10 requirements / 41
  scenarios** to **10 requirements / 42 scenarios**, promoted from
  `openspec/changes/archive/2026-08-23-m8-bundle-rename/specs/release-distribution/spec.md`. The
  three replaced blocks are *A pushed tag is the only thing that produces a downloadable release*,
  *The delivered build is installable through the project's Homebrew tap*, and *Uninstalling states
  exactly what it removes, and what it cannot*. Because nothing is added, removed or renamed at the
  requirement level, `rules.archive`'s destructive-delta warning does not fire and **no capability
  count in any other spec changes**.
  - **What moved.** One user-visible name, everywhere a person can see it: the bundle inside the
    published zip, the installed path, the main executable and the cask's `app` artifact all became
    `Home-Cellar.app` / `Contents/MacOS/Home-Cellar`. The zip name `Home-Cellar-<version>.zip`, the
    cask token `home-cellar` and the display name `Home-Cellar` were already correct and did not
    move.
  - **What deliberately did not move, and is now requirement text rather than prose.** The bundle
    identifier `com.juancasanueva.cellar`. Every application-support root, cache root, Keychain item
    and update host-match derives from that identifier and from no product name, so **the rename
    moved no user data and required no migration**. `PRODUCT_MODULE_NAME` was pinned to `cellar`
    (**DD-1**) so the Swift module never became `Home_Cellar` and all 22 `@testable import cellar`
    files compiled with zero source edits; the product/module divergence is deliberate, and asserted
    in one test so it stays discoverable.
  - **D1 (binding, maintainer 2026-08-23)** — the app had no installed base beyond the maintainer's
    own Mac. **Rejected in consequence:** every migration mechanism (`target:`, a
    `/Applications/cellar.app` zap entry, `uninstall delete:`, `SUBundleName`), all old-name user
    guidance, and an in-app notice. A zap must not delete a bundle the cask never placed.
  - **D2** — all three proposal defaults accepted. `cellar.xcarchive` stays (**DD-4**, a build
    intermediate no user sees); the Xcode target and the `cellar/` source folder are **never**
    renamed (**rejected:** explore Approach 1, largest blast radius for the smallest visible gain);
    the product/module divergence is accepted and documented (**rejected:** 22 mechanical import
    edits to align them).
  - **+1 scenario** — *The rename ships no migration mechanism*, `ci-gate`, run by `ci.yml` in
    `juancasanueva/homebrew-cellar`. It asserts the **absence** of every migration mechanism rather
    than behaviour for an installed base of zero. This is the one deliberate divergence from the
    proposal's "counts are unchanged" line: the scenario count moves by one while the binding
    Capabilities contract — **zero ADDED requirements** — is honoured exactly.
  - **The ordering constraint is requirement text, not a note (R4).** A cask naming a bundle its
    declared asset does not contain **audits clean and installs broken**, because the automated bump
    path gates only on `brew style` and `brew audit` and neither extracts the archive nor resolves
    the `app` artifact. Both naive orderings break: tap-first misnames the already-published
    `v1.1.0` asset, and tag-first lets a scheduled bump land the new `version`/`sha256` against the
    old `app` stanza. Only **one atomic post-release commit** works. That is what shipped — see the
    archive report for the executed evidence.
- The archived delta specs are the verbatim audit trail.
