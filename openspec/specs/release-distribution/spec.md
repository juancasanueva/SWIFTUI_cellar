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
| `unit` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom (reads the repository or the test host's bundle information off disk) | **13** |
| `ci-gate` | a hard gate inside the release run; failing it fails the job and publishes nothing | **12** |
| `manual-evidence` | no harness can exist; the maintainer's observed output is recorded in `design.md` | **4** |

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
bundle inside it MUST be **`cellar.app`** with display name **`Home-Cellar`**.

An asset nobody can download is not a release: a run against a repository that is not anonymously
readable MUST fail fast, with an explicit message, **before** any signing or notarization work, and
MUST publish nothing.

#### Scenario: A tag produces one correctly named, anonymously reachable asset

- GIVEN a pushed tag `v1.0.0` on a publicly readable repository
- WHEN the release run completes
- THEN a GitHub Release for `v1.0.0` exists carrying exactly one asset named `Home-Cellar-1.0.0.zip`
- AND that asset is downloadable from the documented URL without authentication
- Verification: `ci-gate`

#### Scenario: The bundle inside the zip is the one the follow-up slices bind against

- GIVEN the published `Home-Cellar-<version>.zip`
- WHEN it is extracted
- THEN it contains exactly one application bundle, named `cellar.app`
- AND that bundle's display name is `Home-Cellar`
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

The delivered binary MUST contain the **`arm64` slice and no other**. The delivered bundle MUST have
the hardened runtime enabled and the app sandbox disabled.

**No `.entitlements` file MUST exist in the repository**, and no entitlement MUST be added to make the
delivered build work. Specifically, `allow-jit`, `allow-unsigned-executable-memory` and
`disable-library-validation` MUST NOT be present: spawning `/opt/homebrew/bin/brew` as a separate
process is neither JIT nor foreign code loaded into Cellar's address space. The repository MUST carry
a written rationale for this posture, based on **measured** signing output from a notarized build
rather than on assumption, and that rationale MUST also explain what `ENABLE_USER_SELECTED_FILES` and
`REGISTER_APP_GROUPS` mean while the sandbox is disabled.

#### Scenario: The delivered binary is single-architecture

- GIVEN the exported application binary
- WHEN its architectures are enumerated
- THEN `arm64` is the only one reported
- AND the run fails if any other slice is present
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

#### Scenario: The repository carries no secret material

- GIVEN every file in the repository
- WHEN they are inspected for key headers, archived certificate blobs and literal credential values
- THEN none is present
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
    follow-up.
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
  the cask's `app` stanza must name `cellar.app` exactly, its token is `home-cellar`, and the arm64 pin
  plus the macOS 26.0 floor become `depends_on arch: :arm64` and `depends_on macos: ">= :tahoe"`.
  Those slices inherit these facts from this spec rather than re-deriving them.
- The archived delta spec is the verbatim audit trail.
