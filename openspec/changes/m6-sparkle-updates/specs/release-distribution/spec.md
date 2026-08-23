# Delta for release-distribution

Existing capability — `openspec/specs/release-distribution/spec.md` (8 requirements / 29 scenarios,
established by the archived `2026-08-23-m6-release-pipeline`). This delta is **MODIFIED-only**:
**3 requirements modified, 0 added, 0 removed, 0 renamed**, taking the capability to
**8 requirements / 32 scenarios**.

Nothing is removed and no existing scenario is deleted, so `rules.archive`'s destructive-delta warning
does not fire on a deletion. It *does* apply in its weaker sense — three requirement blocks are
replaced wholesale — so each block below is reproduced **in full**, every unchanged scenario included
verbatim, per the OpenSpec MODIFIED convention. Anything not reproduced here is untouched.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m6-sparkle-updates/` + Engram canonical project
`swiftui_cellar`), `delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`.
RDD disabled clone-local.

## Scope of the three edits, and the honest changed-line count

| # | Requirement | Edit | Why |
|---|---|---|---|
| a | *A pushed tag is the only thing that produces a downloadable release* | one paragraph added to the requirement text; **2 scenarios added**; 4 existing scenarios unchanged | A stable tag now also publishes an update feed. That is a second published output of the same run, so the requirement that owns "what a tag produces" must say so, or the feed becomes an unspecified side effect. |
| b | *arm64 only, hardened, unsandboxed, and no entitlement added to get there* | first sentence reworded to bind the **application executable**; the architecture scenario follows; 4 existing scenarios unchanged | Decision **D2**: the vendored prebuilt updater framework is universal. The existing architecture gate already reads only the app executable, so this is the honest wording for what is actually enforced — not a weakening. |
| c | *No credential material in the repository, and injected credentials die with the run* | one paragraph added naming the secret set as closed and enumerated; **1 scenario added**; 4 existing scenarios unchanged | A **seventh** secret arrives. The capability already forbids credential material in the repository but never said the injected set is closed; without that, adding an eighth secret later is invisible to the spec. |

**Honest changed-line count against the main spec: ~34 lines** (≈6 reworded, ≈28 added). This is
materially higher than the proposal's "~6–10 changed lines" estimate, which counted edit (b) only and
booked the seventh secret as a one-word provenance fix rather than as requirement material. Edits (a)
and (c) as scoped here are requirement-and-scenario work, and the proposal's estimate was not written
for that. Recorded as a deviation rather than absorbed silently. No requirement is removed and no
existing scenario is deleted, so the increase is additive.

**Explicitly NOT touched — binding.** The stowaway-sweep scenario ("None of it ships to the user",
under *Release infrastructure lives outside the shipped app sources*) is **unchanged**. Scoping it to
exclude `Contents/Frameworks/` is pre-authorised **only** if probe **U32** fires during design or
apply; if U32 does not fire, that edit must not happen, and if it does fire it arrives as an explicit
fourth MODIFIED block, never as a quiet amendment to this file.

**Archive-time obligation on the class table.** The main spec's `## Verification classes` table lives
outside every requirement block, so a MODIFIED delta cannot carry it. On archive, its counts MUST be
updated from `unit` **13** / `ci-gate` **12** / `manual-evidence` **4** (total 29) to `unit` **14** /
`ci-gate` **14** / `manual-evidence` **4** (total 32): the two new publish scenarios are `ci-gate`, the
new secret-set scenario is `unit`. Stated here so the archive step does not have to infer it.

## MODIFIED Requirements

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

A run for a **stable** tag — one whose version carries no hyphen — MUST additionally publish an update
feed describing that release, served over `https` from the project's GitHub Pages site. The feed is a
**site artifact, not a release asset**, so the one-asset rule above is unaffected: the published release
still carries exactly one downloadable asset. Publishing the feed MUST NOT require a version-control
push and MUST NOT require a second release-management invocation beyond the single one that creates the
release; it MUST reuse the run's already-published asset URL. A run for a **prerelease** tag — one whose
version contains a hyphen — MUST publish the release and MUST NOT publish any feed entry for it, so that
an installed copy of the app is never offered a prerelease.
(Previously: the requirement covered only the single downloadable release asset and its reachability; a
stable tag published no update feed, and prereleases had no stated feed consequence.)

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

## Notes for archive

- Each block above replaces the identically named requirement in
  `openspec/specs/release-distribution/spec.md` in full. The five requirements not reproduced here —
  *The tag is the version…*, *Gatekeeper accepts the artifact users actually download, offline*,
  *A release is all-or-nothing…*, *Release infrastructure lives outside the shipped app sources*, and
  *The delivered build states who made it* — are untouched.
- Update the `## Verification classes` counts as stated above (`unit` 14, `ci-gate` 14,
  `manual-evidence` 4, total **32**), and extend the provenance section with this change's D2 (the
  arm64 rewording), D3/D4 (feed history and prereleases) and the seventh secret.
- The inherited-contract paragraph in the main spec's provenance already binds `m6-sparkle-updates`'s
  enclosure URL to the published asset URL; the new publish scenarios now enforce it from the release
  side rather than leaving it as a note.
