# Proposal: Developer ID Release Pipeline (`m6-release-pipeline`)

Anchors PRD.md **M6 "Ship"** (:212) — the **second M6 slice** (the tip jar was the first, built then
removed). Delivers PRD :9 "Developer ID + notarized", :187 "notarization via `notarytool` in CI
(GitHub Actions on tags)", :227 "arm64-only", and discharges the still-unmet :157 obligation
("Entitlements kept minimal; document why in-repo for notarization sanity"). It also absorbs the debt
of PRD risk :224, whose mitigation ("set up CI pipeline in M1, not M6") was never taken: the repo has
**no `.github/`, no `scripts/`, no CI of any kind** today.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled (no reviews started).

Inputs: `openspec/changes/m6-release-pipeline/explore.md` (Engram topic
`sdd/m6-ship-pipeline/explore`, obs 7659, written for the umbrella change and then sliced) and the
maintainer's binding decisions at obs 7661 / 7660.

## Intent

Cellar is feature-complete through M5 and has **no way to reach a user**. Every build in existence is
a locally dev-signed archive on the maintainer's machine. A stranger who is handed a zip of it today
gets a Gatekeeper refusal, because the bundle is neither Developer ID-signed nor notarized nor
stapled.

The product outcome: **a tagged commit becomes a downloadable, double-clickable app.** Push `v1.0.0`,
and a GitHub Release appears carrying `Home-Cellar-1.0.0.zip` — arm64, hardened runtime, Developer ID
Application-signed, notarized, stapled, and verified by `spctl` before publication. A user downloads
it, unzips it, drags it to `/Applications`, and it opens on the first try, offline. Nothing about the
process depends on the maintainer's laptop, and nothing about it is a secret held in one person's
head.

This slice deliberately produces **no in-app behavior change**. It is infrastructure, and it is the
prerequisite that the two follow-up slices cannot be verified without.

## Binding Constraints

1. **Slice 1 of 3 (decision 1).** Sparkle is **out** — `m6-sparkle-updates` follows. The cask/tap is
   **out** — `m6-cask-tap` follows, in a different repository. Neither may be pulled in. What this
   slice owes them is recorded below under *Contract for the follow-up slices*, so nothing is
   re-derived later.
2. **No secret material in the repo.** swift-security invariant: nothing in `.xcconfig`,
   `Info.plist`, source, scripts, or logs. Ephemeral keychain per run, deleted in an `if: always()`
   step, no `set -x` around a secret, no secret echoed to a job log.
3. **Release-on-tag only (risk 11).** A lint job, a PR test matrix, coverage upload, and a build cache
   all *look* like they belong in the project's first workflow. They do not. Each is its own change.
4. **The repository must be public before the first tagged release** (decision 2, obs 7660). It is
   `PRIVATE` today (measured: anonymous REST API → 404). Release assets on a private repo are not
   anonymously downloadable, and macOS runner minutes bill at 10×.
5. **No entitlement is added speculatively (risk 5).** Each one weakens the hardened runtime and is
   visible in the notarization audit trail. The rationale doc records *measured* signing state, not
   assumptions.
6. **`cellar/` is a `PBXFileSystemSynchronizedRootGroup` (risk 7).** Any file dropped inside it joins
   the app target and ships in the bundle. `ExportOptions.plist` and every script therefore live in
   `scripts/`, outside `cellar/` — and that placement gets a test, not a comment.

## Scope

**In:** `ARCHS = arm64` pinned in `project.pbxproj`; `scripts/ExportOptions.plist`
(`method = developer-id`); `scripts/release.sh` carrying the archive→export→notarize→staple→verify
sequence so the same commands run locally (U26) and on CI; `.github/workflows/release.yml` triggered
on `push: tags: ['v*']`, `runs-on: macos-26`, Xcode pinned via `xcode-select`, publishing
`Home-Cellar-<version>.zip` to a GitHub Release; `cellarTests/ReleasePipelineCompositionTests.swift`
(the structural RED set); `RELEASING.md` including the PRD:157 hardened-runtime/entitlements
rationale; `NSHumanReadableCopyright` filled in `cellar/InfoPlist.xcstrings` (risk 12 — a 1.0 that
ships an empty copyright line is a visible omission); a new `release-distribution` capability;
README `## Install` + `## Releasing` sections; PRD :9 / :157 / :168 / :187 / :224 amendments.

**Out (non-goals — each recorded, not omitted):** **Sparkle** in every form — the SPM dependency,
`Package.resolved`, EdDSA keys, `SUFeedURL` / `SUPublicEDKey`, `generate_appcast`, the CellarCore
`Updates` target, the Settings "Updates" group, the About "Check for Updates…" command
(`m6-sparkle-updates`); the **Homebrew tap and cask** (`m6-cask-tap`, repo
`juancasanueva/homebrew-cellar`); **GitHub Pages / `gh-pages`** — no feed exists yet to host; a
**DMG** (decision 4 — deferred to the landing-page follow-up); a **PR/test CI workflow**, a lint job,
coverage upload, or a build cache; **SwiftLint adoption** (U21 measured 246 warnings + 20 errors with
no config — its own change); any **`.entitlements` file**; a **second scheme**; `THIRD-PARTY.md`
(no new dependency); **Xcode Cloud** or fastlane; the **landing page**; the actual GitHub visibility
flip and the actual first `v1.0.0` tag (both maintainer actions, see *Prerequisites*).

## Capabilities

- **New `release-distribution`** (ADDED-only — no destructive delta, so `rules.archive`'s warning
  does not fire): the observable contract of a *delivered build*, which is what the next two slices
  bind against. Requirement material: artifact name `Home-Cellar-<version>.zip`; the bundle inside is
  `cellar.app` with display name `Home-Cellar`; arm64-only; hardened runtime on, sandbox off, no
  added entitlements; Developer ID Application signature, notarized and stapled such that
  `spctl -a -vvv -t install` and `stapler validate` accept the **extracted** app **offline**;
  `CFBundleShortVersionString` equals the tag minus its leading `v`; `CFBundleVersion` strictly
  increases across releases; the asset URL follows
  `https://github.com/<owner>/<repo>/releases/download/v<version>/Home-Cellar-<version>.zip`.
  **Declared honestly:** these scenarios are verified by CI gates and recorded manual evidence, not by
  unit tests. `rules.specs`' "CellarCore types" clause does not apply — there is no CellarCore code in
  this slice.
- **Modified capabilities: None.** No shipped capability changes behavior.

## Approach

**Export shape 8b-A** — `xcodebuild archive -destination 'generic/platform=macOS'` →
`xcodebuild -exportArchive -exportOptionsPlist scripts/ExportOptions.plist` (`method = developer-id`)
→ `ditto -c -k --keepParent --sequesterRsrc` → `xcrun notarytool submit --wait` →
`xcrun stapler staple` → **re-`ditto`** → unzip to a temp dir → `spctl -a -vvv -t install` +
`stapler validate` on the *extracted* copy as a hard gate → `gh release create`. `-exportArchive`
re-signs the bundle inside-out in the correct order; `codesign --deep` is discouraged by Apple and
gets that order wrong. The staple-then-re-zip sequencing is not optional: `notarytool` accepts a zip
but `stapler` attaches the ticket to the `.app`, so the distributed archive must be built *after*
stapling or first launch becomes offline-hostile. Gating on the extracted copy — not on
`build/export/cellar.app` — is what proves the *artifact users download* is the one that passed.

**Pipeline logic in `scripts/`, secrets in YAML.** The workflow owns the runner, the ephemeral
keychain, the secret injection, and the `if: always()` cleanup; `scripts/release.sh` owns the build
sequence and takes everything else from environment variables. For a project whose first CI this is,
locally runnable release logic is worth more than YAML compactness — it is also exactly what makes
U26 a real rehearsal of the workflow rather than an approximation of it.

**Signing style: keep `CODE_SIGN_STYLE = Automatic`, add `-allowProvisioningUpdates`.** Chosen over
flipping Release to Manual with an explicit `CODE_SIGN_IDENTITY`, for three reasons: the App Store
Connect API key it requires is *already* a mandatory secret for `notarytool` (decision 5), so it adds
zero new credential surface; it keeps the Debug and Release build blocks byte-identical, an invariant
the pbxproj currently holds across all ~30 settings and which drift would quietly break; and it
avoids hardcoding a certificate common name that changes on renewal. **Accepted downside:** automatic
signing on a headless runner can create/refresh provisioning profiles in the team's ASC account as a
side effect, and it can fail in ways manual signing cannot. **This is exactly what U26 measures.** If
U26 shows headless automatic export failing, the fallback is the Manual flip
(`CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = "Developer ID Application"`,
`PROVISIONING_PROFILE_SPECIFIER = ""` in the Release block only) — a *separate, explicitly approved*
amendment with its own rollback note, never silently absorbed at apply time.

**Version stamping (decision 6, risk 13).** `MARKETING_VERSION=${GITHUB_REF_NAME#v}` and
`CURRENT_PROJECT_VERSION=${GITHUB_RUN_NUMBER}` are passed on the `xcodebuild` command line; the
pbxproj stays at `1.0.0` / `1` and is never bumped per release, which removes a recurring two-block
merge hazard. The cost is real and must not be left as a trap: **a locally archived build reports
`1.0.0 (1)` forever**, which `AboutView.version` will display verbatim during manual testing. Two
mitigations, both in scope: `RELEASING.md` states it as a documented fact with the one-line
`xcodebuild` override to produce a correctly stamped local build, and CI **asserts** the exported
`Info.plist`'s `CFBundleShortVersionString` equals the tag before notarizing — a mismatch fails the
job rather than shipping a mislabelled release.

**PRD:157 discharged in `RELEASING.md`, evidence-based.** No `.entitlements` file exists anywhere in
the repo and none is added. The doc must record, quoting real
`codesign -d --entitlements :- ` and `codesign -dvvv` output from the *notarized* build: what the app
is actually signed with; why `allow-jit`, `allow-unsigned-executable-memory`, and
`disable-library-validation` are **not** present (spawning `/opt/homebrew/bin/brew` as a separate
process is not JIT and does not load foreign code into Cellar's address space — U28 measures this on
a notarized build rather than assuming it); and what
`ENABLE_USER_SELECTED_FILES = readonly` / `REGISTER_APP_GROUPS = YES` mean while
`ENABLE_APP_SANDBOX = NO` — they are sandbox-era settings sitting inert beside a disabled sandbox,
and introducing any `.entitlements` file would make them live, re-activating the export-write trap
recorded in the tip-jar archive. A separate top-level `ENTITLEMENTS.md` was considered and rejected:
one release document the maintainer actually opens beats two nobody does.

| Area | Impact |
|---|---|
| `.github/workflows/release.yml` | **New** — tag-triggered, `macos-26`, `permissions: contents: write` |
| `scripts/release.sh`, `scripts/ExportOptions.plist` | **New** — outside `cellar/`, binding (risk 7) |
| `cellar.xcodeproj/project.pbxproj` | **Modified** — `ARCHS = arm64` only; **rollback plan below** (`rules.proposal`) |
| `cellar/InfoPlist.xcstrings` | **Modified** — `NSHumanReadableCopyright` filled |
| `cellarTests/ReleasePipelineCompositionTests.swift` | **New** — the structural RED set |
| `RELEASING.md` | **New** — pipeline runbook + PRD:157 entitlements rationale |
| `README.md` | **Modified** — `## Install` (download, arm64, first launch) + `## Releasing` |
| `PRD.md` :9, :157, :168, :187, :224 | **Modified** — rewritten in place, tip-jar precedent |
| `openspec/specs/release-distribution/spec.md` (ADDED-only delta) | **New** |
| `Packages/CellarCore/**`, `cellar/**` Swift sources, `cellar.xcscheme`, `THIRD-PARTY.md` | **Untouched — binding** |

## Contract for the follow-up slices

Recorded here so `m6-sparkle-updates` and `m6-cask-tap` inherit facts rather than re-deriving them:

| Contract | Value |
|---|---|
| Asset URL scheme | `https://github.com/juancasanueva/SWIFTUI_cellar/releases/download/v<version>/Home-Cellar-<version>.zip` — Sparkle's `<enclosure url>` and the cask's `url` |
| Artifact name | `Home-Cellar-<version>.zip`, produced by `ditto -c -k --keepParent --sequesterRsrc` **after** stapling (exactly the format Sparkle mandates) |
| Bundle on disk | `cellar.app` — the cask's `app` stanza must name it exactly; display name stays `Home-Cellar`; future cask token `home-cellar` |
| Version stamping | tag `vX.Y.Z` → `CFBundleShortVersionString`; `GITHUB_RUN_NUMBER` → `CFBundleVersion`, monotonically increasing across re-cut tags — which is precisely what Sparkle's comparison requires |
| Architecture / floor | arm64-only pin → cask `depends_on arch: :arm64`; `MACOSX_DEPLOYMENT_TARGET = 26.0` → `depends_on macos: ">= :tahoe"` |
| Extension point | the workflow ends with a named, commented publish step so `generate_appcast` and the cask bump insert without restructuring the job |

## Strict-TDD honesty split

`config.yaml` sets `strict_tdd: true` and `rules.tasks` demands RED before GREEN "for every
behavioral task". **Most of a ship pipeline is not behavior, and this slice adds no production Swift
at all.** A proposal with a near-zero RED set is acceptable for an infrastructure slice **when it is
declared**, which is what this section does. No Swift is invented merely to have something to test.

**Genuinely RED-first** — one new `cellarTests` file, in the `SecurityCompositionSupport` idiom
(reads the repo off disk via `#filePath`), each assertion false today and true after:

1. `scripts/ExportOptions.plist` and `scripts/release.sh` exist and **no** release-infrastructure file
   lives under `cellar/` — the only automated guard against the synchronized-root-group trap.
2. `ExportOptions.plist` declares `method = developer-id` and `teamID = Z3S5JK8E38`.
3. `.github/workflows/release.yml` exists; its keychain-deletion step carries `if: always()`; no
   `run:` line contains `set -x`; no PEM header, `.p12` blob, or literal secret value appears
   anywhere in the repo.

**GREEN-on-arrival pins (declared, not RED):** a `SecCodeCopySigningInformation` check that the
running app reports the hardened-runtime flag would pass today (`ENABLE_HARDENED_RUNTIME = YES`
already) — worth keeping only as a regression guard, design's call.

**Rejected as an unfaithful test:** asserting arm64 via `Bundle.main`'s Mach-O header from
`cellarTests`. The test host is built by `xcodebuild test`, not by `archive`, so it cannot prove what
the *release* binary contains. Architecture belongs to a CI `lipo -archs` gate on the exported binary.

**CI-evidence-only (verification evidence, never a spec scenario):** `actionlint` over the workflow;
one dry-run prerelease tag on a throwaway version, published as a prerelease and then deleted.

**Manual-only, and must be recorded as such in `design.md` with the maintainer's observed output:**
the notarization verdict; Gatekeeper first launch of the *downloaded, quarantined* zip on a machine
that has never seen the bundle; and a real `brew` mutation executed by the notarized, stapled build
(U28). No harness exists for any of these.

## Probes

**U24 is not needed in this slice** — no Sparkle Info.plist keys are written, so
`INFOPLIST_KEY_SU*` is not exercised. **U25 (Sparkle SPM) likewise defers** to `m6-sparkle-updates`.

- **U26 — a local Developer ID export + notarize round-trip.** *Gates the workflow YAML.* Proves the
  certificate and ASC key exist and work, and settles the automatic-vs-manual signing question above
  before a line of YAML is written. Cheapest possible de-risking; run first.
- **U27 — `lipo -archs` on the binary from the current `xcodebuild archive`.** Establishes whether
  `ARCHS_STANDARD` is already producing x86_64, i.e. whether the `ARCHS = arm64` pin is a fix or a
  formality.
- **U28 — does a hardened-runtime, notarized, stapled build still exec `/opt/homebrew/bin/brew` and
  complete a real mutation?** Expected yes; must be *measured*, because it is the evidence base for
  the PRD:157 rationale and the reason no entitlement is added.
- **U29 — suite baseline at `ec7b1c5`**, including `cellarUITests/ReleaseNotesUITests` ownership
  (recorded as failing and unowned at `7d48779`, skipped at U21). Run before tasks; the shared
  scheme's `TestAction` includes the UI tests, so any CI or verify gate must not inherit that failure
  silently (risk 10).

## Prerequisites (maintainer actions, outside this repo)

Not tasks. The PR can merge without them; the first release cannot happen without them.

1. Flip `juancasanueva/SWIFTUI_cellar` to **public** before the first tagged release.
2. Export the **Developer ID Application** certificate *with its private key* as a `.p12`.
3. Create an **App Store Connect API key** (`.p8`) with the **Developer** role; note the key ID and
   issuer ID. Serves both `notarytool` and `-allowProvisioningUpdates` (decision 5).
4. Set six GitHub repository secrets — explore §4.3 minus `SPARKLE_PRIVATE_KEY`:
   `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_API_KEY_P8`,
   `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`. The Apple ID + app-specific password fallback is
   **not** used. `DEVELOPMENT_TEAM = Z3S5JK8E38` is already in the repo and is not a secret.
5. Confirm Actions is enabled and `GITHUB_TOKEN` may write releases (the workflow declares
   `permissions: contents: write` explicitly rather than relying on the repository default).

## Risks

Carried from explore §10; Sparkle-specific risks (2, 6, 8, 14) are dropped as out of slice.

| # | Risk | L | Mitigation |
|---|---|---|---|
| 1 | Repo still **private** when the first tag is pushed — assets not anonymously downloadable, runner minutes at 10× | **High** | Prerequisite 1; the workflow fails fast on `github.event.repository.private == true` with an explicit message rather than publishing an unreachable asset |
| 3 | Developer ID `.p12` mishandled on CI | **High** | Ephemeral keychain, `security set-key-partition-list`, unconditional `if: always()` deletion, no `set -x`, no secret echo; asserted structurally by the RED set |
| 4 | `CODE_SIGN_STYLE = Automatic` fails headless, or mutates ASC provisioning state | Med | U26 measures it *before* any YAML; Manual flip pre-authored as the fallback with its own rollback note |
| 5 | An entitlement added speculatively weakens the hardened runtime | Med | No `.entitlements` file, binding; U28 measures the real requirement; rationale doc quotes actual `codesign` output |
| 9 | `ARCHS` unset ⇒ a universal archive contradicting PRD:227, doubling zip size and CellarCore compile time | Med | U27 measures, pbxproj pins `arm64`, CI gates with `lipo -archs` on the exported binary |
| 10 | The shared scheme's `TestAction` includes `cellarUITests`, which has a known unowned failure | Med | The release workflow runs **no** test action; U29 re-baselines before tasks; the gap is stated, not silently inherited |
| 11 | Scope creep — this is the project's first CI and everything looks adjacent | **High** | Release-on-tag only, listed as an explicit non-goal set; a PR-test workflow is its own change |
| 12 | Empty `NSHumanReadableCopyright` ships in 1.0 | Low | Filled in `cellar/InfoPlist.xcstrings` (the catalog is the authority, not the build setting) |
| 13 | Local Release builds report `1.0.0 (1)` forever and confuse manual testing | Med | Documented in `RELEASING.md` with the override command; CI asserts the exported `CFBundleShortVersionString` matches the tag before notarizing |
| 15 | PRD ships a contradiction (a CI pipeline in the repo beside a PRD that says it does not exist) | Med | PRD :9/:157/:168/:187/:224 amended **in the same PR**, rewritten in place with the reason |
| — | Notarization queue latency or an Apple-side rejection blocks a release | Med | `notarytool submit --wait`; on rejection the job fails before `gh release create`, so no partial release is ever published; `notarytool log` fetched into the job output |

## Rollback Plan

`rules.proposal` mandates this because `project.pbxproj` is touched.

- **A single `git revert` of the slice PR restores everything.** The change adds no runtime code, no
  cache file, no schema version, no Keychain item, and no migration — a revert orphans nothing.
- **`project.pbxproj` carries exactly one change: `ARCHS = arm64`.** Reverting restores the implicit
  `ARCHS_STANDARD`. `CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`, `DEVELOPMENT_TEAM`,
  `ENABLE_HARDENED_RUNTIME`, `ENABLE_APP_SANDBOX`, `MARKETING_VERSION`, and
  `CURRENT_PROJECT_VERSION` are **expected at 0-line diffs — binding**. The Debug and Release blocks
  must remain byte-identical afterwards. If apply time forces the Manual signing fallback, that is
  reported before merge and rolled back by the same revert, never absorbed quietly.
- **`Packages/CellarCore/Package.swift`, `Package.resolved`, and `cellar.xcscheme` are expected at
  0-line diffs — binding.** No package, no dependency, no scheme edit.
- **`.github/`, `scripts/`, and `RELEASING.md` are net-new.** Deleting them removes the pipeline
  entirely with zero effect on the app.
- **A code revert does not unpublish a release.** A bad release is handled by deleting the GitHub
  Release and its tag and cutting a new patch tag; because `CURRENT_PROJECT_VERSION` comes from
  `GITHUB_RUN_NUMBER`, it keeps increasing across a re-cut — which matters for the future Sparkle
  slice, where a non-increasing `CFBundleVersion` would strand installed copies.
- **Secrets and the public-visibility flip survive a revert.** Undoing them is a maintainer action.
- Post-revert checks: `swift build --package-path Packages/CellarCore` and
  `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.

## Delivery Forecast

Budget **5,000** lines (`config.yaml` and the session preflight agree), `single-pr`, strict TDD, RDD
disabled.

| Bucket | Bottom-up lines |
|---|---|
| `project.pbxproj` (`ARCHS` only) | 2–6 |
| `.github/workflows/release.yml` | 160–260 |
| `scripts/` (`release.sh`, `ExportOptions.plist`) | 60–140 |
| `cellarTests/ReleasePipelineCompositionTests.swift` | 80–150 |
| Docs (`RELEASING.md`, README, PRD amendments, `InfoPlist.xcstrings`) | 140–230 |
| **Bottom-up subtotal** | **440–790** |

The house's measured **1.9–2.3×** correction (established across M5 slices 3–5, recorded at
`openspec/changes/archive/2026-08-22-m6-tip-jar/tasks.md:14`) gives **~840–1,800 corrected authored
lines**, matching explore §9's post-split estimate of ~900–1,700. Add the in-repo SDD artifacts
themselves (`proposal.md`, `design.md`, `tasks.md`, the `release-distribution` delta ≈ 350–550 lines,
written once and not subject to the iteration multiplier) for a **PR total of roughly 1,200–2,350
lines**.

- Against the 400 default: **High**.
- Against the 5,000 budget: **Low** — better than half the budget even at the ceiling. `single-pr`
  holds with **no `size:exception`**, which was 8d-B's strongest argument.

`sdd-tasks` MUST reuse the 1.9–2.3× correction rather than re-deriving it, and MUST emit the exact
guard lines (`Decision needed before apply: Yes|No`, `Chained PRs recommended: Yes|No`,
`400-line budget risk: Low|Medium|High`).

## Success Criteria

- [ ] Pushing a `v*` tag produces a GitHub Release carrying `Home-Cellar-<version>.zip`, with no
      manual step between the push and the published asset.
- [ ] The app inside that zip is **arm64-only** (`lipo -archs` gate), hardened-runtime, sandbox-off,
      Developer ID Application-signed, notarized, and stapled.
- [ ] `spctl -a -vvv -t install` and `stapler validate` pass on the app **extracted from the published
      zip**, with networking disabled — and the job fails, publishing nothing, if they do not.
- [ ] `CFBundleShortVersionString` equals the tag minus `v`, asserted by CI *before* notarization;
      `CFBundleVersion` equals `GITHUB_RUN_NUMBER`.
- [ ] `RELEASING.md` documents the pipeline end to end **and** discharges PRD:157, quoting real
      `codesign -d --entitlements :-` output and explaining `ENABLE_USER_SELECTED_FILES` /
      `REGISTER_APP_GROUPS` under a disabled sandbox.
- [ ] No `.entitlements` file exists in the repo, and no entitlement was added to reach U28's green.
- [ ] `ReleasePipelineCompositionTests` proves no release-infrastructure file lives under `cellar/`,
      the keychain cleanup is `if: always()`, and no secret material is committed.
- [ ] `actionlint` passes; one dry-run prerelease tag completed the full pipeline end to end.
- [ ] Gatekeeper first launch of the downloaded, quarantined zip on a clean machine is a single
      "Open", not a refusal — recorded as manual evidence.
- [ ] A `brew` mutation succeeds from the notarized, stapled build (U28).
- [ ] `project.pbxproj` shows a diff of `ARCHS = arm64` and nothing else; `Package.swift`,
      `Package.resolved`, `cellar.xcscheme`, and every Swift source under `cellar/` and
      `Packages/CellarCore/` show 0-line diffs.
- [ ] `cellarTests` remains green at its U29 baseline plus the new file.
- [ ] PRD :9/:157/:168/:187/:224 and README are amended in this PR, rewritten in place with reasons.

## Resolved Decisions (binding)

Taken by the maintainer (obs 7661, 7660). Specs and design derive from these and MUST NOT reopen them.

- **D1 — Slice per explore 8d-B**: `m6-release-pipeline` → `m6-sparkle-updates` → `m6-cask-tap`.
  **Rejected: 8d-A** (one change, 2,540–4,780 lines and ~220 lines of headroom at the ceiling — not a
  margin), **8d-C** (CI only, Sparkle abandoned), **8d-D** (Sparkle with manual local releases — the
  exact debt PRD:224 warned about, deepened).
- **D2 — The repository goes public for 1.0.** Unblocks anonymous asset download, free Pages hosting
  for the later appcast, the cask, and normal-rate runner minutes.
- **D3 — arm64-only**, `ARCHS = arm64` pinned (PRD:227). **Rejected:** universal.
- **D4 — zip via `ditto`.** **Rejected/deferred:** DMG, to the landing-page follow-up.
- **D5 — App Store Connect API key** for `notarytool`. **Rejected:** Apple ID + app-specific password
  (2FA-prompting, not independently revocable, and does not serve `-allowProvisioningUpdates`).
- **D6 — git tag is the version source of truth**; the pbxproj stays `1.0.0` / `1`.
  **Rejected:** bumping two pbxproj blocks per release (a recurring merge hazard).
- **D7 — Naming**: user-facing `Home-Cellar`, artifact `Home-Cellar-<version>.zip`, bundle
  `cellar.app`, future cask token `home-cellar`.
- **D8 — PRD and README amended in this PR**, rewritten in place with reasons (tip-jar precedent).
- **D9 (this proposal) — `CODE_SIGN_STYLE` stays `Automatic`** with `-allowProvisioningUpdates` and
  the ASC key. **Rejected:** flipping Release to Manual — held as the pre-authored fallback if U26
  measures headless automatic signing failing.
- **D10 (this proposal) — one `RELEASING.md`** carries both the runbook and the PRD:157 entitlements
  rationale. **Rejected:** a separate `ENTITLEMENTS.md`.

## Open Questions (non-blocking)

1. **Release notes body.** `gh release create --generate-notes` (commit-derived) versus a curated
   `CHANGELOG.md`. Recommend `--generate-notes` for 1.0; the Sparkle appcast description is a
   `m6-sparkle-updates` concern. Settle at design.
2. **Is a `v1.0.0-rc.1` dry run published on the real repository, or on a throwaway one?** The real
   repo is cheaper and exercises the true secret set; it also leaves a deletable prerelease in a repo
   about to go public. Recommend the real repo, deleted immediately after.
3. **`cellarUITests/ReleaseNotesUITests` still has no owner** (carried from m5-health through the
   tip-jar slice). Not this slice's defect, but U29 must state its status rather than let a release
   gate inherit it.
4. **Icon and copyright string.** `NSHumanReadableCopyright` gets a value here; PRD §9 Q1 (final name
   and icon) remains open and is a 1.0 blocker outside this slice.
