# Tasks: Developer ID Release Pipeline (`m6-release-pipeline`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`chain_strategy=n/a (single-pr)`, `review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

Inputs: `specs/release-distribution/spec.md` (8 req / 29 scenarios, `S1`–`S29`), `design.md`
(PASS-WITH-WARNINGS; T1–T19 / G1–G4 / M1–M10, *Probe results*, *Re-validation record*),
`proposal.md` (D1–D10 binding), Engram obs 7661 / 7663.

**Verification-class honesty (read before verifying).** Only the `unit` class is a test task. `ci-gate`
and `manual-evidence` tasks are **not** RED/GREEN tasks and cannot be discharged by a test runner: each
carries the exact command and the exact accepted output the verifier must accept as evidence.
`sdd-verify` MUST NOT deadlock waiting for a harness that the spec itself declares cannot exist.
Test runners: `fast_unit_command` (`-only-testing:cellarTests`) for every `unit` task;
`core_package_command` runs once as a 0-diff proof — **this slice adds no CellarCore code**.

**Threat matrix: applicable** (shell commands, subprocesses, VCS-adjacent automation, executable-file
classification). All five applicable rows carry into the RED tasks below: documentation-like paths
(T1, T12), git repository selection (T15a), PR commands (T15b), secret exposure (T5, T6, T13, T16).
The two `N/A — asserted` rows (commit state, push state) are still pinned by T15b rather than assumed.

**Not-touched binding — 0-line diffs, report any deviation before merge:** `Packages/CellarCore/**`,
every `.swift` under `cellar/`, `cellar.xcscheme`, `Package.swift`, `Package.resolved`,
`THIRD-PARTY.md`, `cellarTests/SecurityCompositionSupport.swift`. Nothing new under `cellar/` except
the `InfoPlist.xcstrings` edit — `cellar/` is a `PBXFileSystemSynchronizedRootGroup` and any `.plist`,
`.yml` or `.sh` dropped inside it ships signed in the bundle.

**pbxproj is exactly two lines:** `ARCHS = arm64;` in both app-target blocks (`BCDBE99F…` Debug :419,
`BCDBE9A0…` Release :452), Debug/Release byte-identical. No copyright, **no app category**, no
signing-style edit in this slice.

**Probes.** `U27` **resolved** (the Release archive at `ec7b1c5` is universal `x86_64 arm64` — the pin
is a *fix*) and `U29` **resolved** (baseline 1732 CellarCore + **141 distinct** `cellarTests` green;
`ReleaseNotesUITests` owned and fixed in PR #21). Cite both; do **not** re-run them. `U26` is
**BLOCKED on a maintainer prerequisite** (no Developer ID Application certificate on the build Mac, no
ASC API key) and is an explicit gate in Phase 6 — **no tag may be pushed and the Manual fallback may
not be applied before U26 has a measured result**. `U28` follows `U26`.

Size note: this artifact exceeds the generic 530-word phase budget, matching the house precedent at
`openspec/changes/archive/2026-08-22-m6-tip-jar/tasks.md` and the density this slice's spec/design
already carry. Nothing is padded.

## Maintainer prerequisites (not code tasks — a checklist, blocking Phase 6 only)

- [ ] P1 Flip `juancasanueva/SWIFTUI_cellar` to **public** before the first tag (D2; blocks S1/S4).
- [ ] P2 Create + export the **Developer ID Application** certificate *with its private key* as `.p12`.
- [ ] P3 Create an **App Store Connect API key** (`.p8`, **Developer** role); note key id + issuer id.
- [ ] P4 Set the six repository secrets, exactly: `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`,
      `KEYCHAIN_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`.
- [ ] P5 Confirm Actions is enabled and `GITHUB_TOKEN` may write releases (`contents: write`).
- [ ] P6 The PR may merge without P1–P5; the first release cannot happen without them.

## Review Workload Forecast

Reused from `design.md` *Size Forecast* — **not re-derived**.

| Field | Value |
|---|---|
| Bottom-up lines | 652–1,054 (pbxproj 2–4 · workflow 160–260 · scripts 100–180 · tests 200–320 · docs 190–290) |
| House correction | **1.9–2.3×** (measured, M5 slices 3–5, `archive/2026-08-22-m6-tip-jar/tasks.md:14`) |
| Corrected authored lines | **~1,240–2,425** |
| Estimated changed lines (PR total, incl. in-repo SDD artifacts ≈350–550, written once) | **~1,590–2,975** |
| Governing budget | **5,000** (`config.yaml` and session preflight agree) |
| Risk vs governing budget | **Low** — ≈2,000 lines of headroom even at the ceiling |
| Chained PRs recommended | No — one PR, five internal work units |
| Suggested split | Single PR, 5 work-unit commits |
| Delivery strategy | single-pr |
| Chain strategy | pending (n/a — no chain) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

`400-line budget risk` is the literal guard value against the 400 **default**; that default does not
govern this change. Against the governing 5,000-line budget the risk is **Low**, so `single-pr` holds
with **no `size:exception`** and no decision blocks apply — exactly the tip-jar precedent.

### Suggested Work Units (one PR, five reviewable commits — `work-unit-commits`)

| Unit | Goal | Commit (Conventional, no AI attribution) | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | arm64 pin + pbxproj invariant guards (Phase 1) | `build(project): pin ARCHS to arm64 in both app-target blocks` | `xcodebuild test … -only-testing:'cellarTests/ReleaseMetadataTests'` | `xcodebuild build -scheme cellar` still succeeds | Revert 2 pbxproj lines; delete T11/T14/T17a |
| 2 | Copyright from the string catalog (Phase 2) | `fix(app): stamp the human-readable copyright from the string catalog` | `xcodebuild test … -only-testing:'cellarTests/ReleaseMetadataTests'` | Launch the app, Finder inspector + About window show the string | Revert `cellar/InfoPlist.xcstrings`; delete T9/T10 |
| 3 | Release script + export options (Phase 3) | `ci(release): add the local release script and Developer ID export options` | `xcodebuild test … -only-testing:'cellarTests/ReleaseWorkflowContractTests'` | `shellcheck scripts/release.sh` (G2); full run deferred to U26 | Delete `scripts/`; delete T1/T7/T8/T15a/T16a |
| 4 | Tag-triggered workflow (Phase 4) | `ci(release): add the tag-triggered Developer ID release workflow` | `xcodebuild test … -only-testing:'cellarTests/ReleaseWorkflowContractTests'` | `actionlint .github/workflows/release.yml` (G1); pipeline run is G3 | Delete `.github/`; delete T2/T3/T4/T5/T6/T19/T15b/T16b |
| 5 | Runbook + PRD/README amendments (Phase 5) | `docs(release): document the release pipeline and amend PRD and README` | `xcodebuild test … -only-testing:cellarTests` | Read `RELEASING.md` §3 end to end as a runbook | Delete `RELEASING.md`; revert `PRD.md` + `README.md`; delete T17b/T18 |

Parallelism: units **1, 2** and **3, 4** and **5** are content-independent, but all RED tests live in the
single file `cellarTests/ReleasePipelineCompositionTests.swift`, so **one writer, sequential** — no
parallel worktrees. Within a unit, tasks are strictly sequential (RED → GREEN).

## Phase 0: Preflight (sequential; no repo edits)

- [ ] 0.1 `brew install actionlint shellcheck` — local tooling for G1/G2. Not a repo change.
- [ ] 0.2 Cite the U29 baseline (CellarCore **1732/1732**, `cellarTests` **141 distinct** cases, 0
      failures at `ec7b1c5`) as the G4 starting point. **Do not re-run it.** Count distinct
      `Test case '…' passed` ids; `Executed 0 tests` is meaningless for Swift Testing bundles.

## Phase 1: arm64 pin — Work unit 1 (S9 via D3/DD-9, S8)

- [ ] 1.1 **RED** Create `cellarTests/ReleasePipelineCompositionTests.swift` with its **self-contained**
      `#filePath`-anchored repo-root helper (the `SecurityCompositionSupport` idiom, copied not imported,
      so rollback is one file deletion) and suite `ReleaseMetadataTests` carrying **T11**: exactly two
      `XCBuildConfiguration` blocks contain `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;` and
      each also contains `ARCHS = arm64;` (trailing `;` excludes `cellarTests`). Fails today.
- [ ] 1.2 **GREEN** `cellar.xcodeproj/project.pbxproj`: add `ARCHS = arm64;` as the first `buildSettings`
      key (alphabetical, before `ASSETCATALOG_*`) at :419 (Debug) and :452 (Release). **Two lines, no
      other key** — `INFOPLIST_KEY_*`, `CODE_SIGN_*`, `ENABLE_*`, `MARKETING_VERSION`,
      `CURRENT_PROJECT_VERSION` are 0-line diffs, binding.
- [ ] 1.3 **GREEN-on-arrival** (declared, not RED) in `ReleaseMetadataTests`: **T14** the two app-target
      `buildSettings` blocks are equal after whitespace normalisation modulo `name = Debug/Release;`
      (design-owned pin, not spec coverage); **T17a** both blocks carry `MARKETING_VERSION = 1.0.0;`,
      `CURRENT_PROJECT_VERSION = 1;`, `ENABLE_APP_SANDBOX = NO;`, `ENABLE_HARDENED_RUNTIME = YES;`
      (two matches each) — S8, plus the S10 gate's blast radius. Must pass on the first run.
- [ ] 1.4 Confirm the diff is exactly two insertions: `git diff --stat cellar.xcodeproj/project.pbxproj`
      → `1 file changed, 2 insertions(+)`. Any other line is a deviation to report, not to absorb.

## Phase 2: Copyright — Work unit 2 (S28, S29)

- [ ] 2.1 **RED** **T9** in `ReleaseMetadataTests`: `cellar/InfoPlist.xcstrings` parses as JSON and
      `NSHumanReadableCopyright` == `Copyright © 2026 Juan Casanueva. All rights reserved.`, **and**
      neither app-target pbxproj block carries a non-empty `INFOPLIST_KEY_NSHumanReadableCopyright`
      (one authority, no competing value) — S29.
- [ ] 2.2 **RED** **T10** in `ReleaseMetadataTests`:
      `Bundle.main.localizedInfoDictionary?["NSHumanReadableCopyright"] as? String` equals that exact
      string — S28. The **localized** dictionary is pinned deliberately: U27 measured the raw key
      **absent** from the generated Info.plist, so a fallback to `infoDictionary` would assert on a key
      that does not exist. Never fall back.
- [ ] 2.3 **GREEN** `cellar/InfoPlist.xcstrings`: set `NSHumanReadableCopyright` to the exact string and
      move `state: new` → `translated`, beside the two bundle-name keys the catalog already owns.
      `INFOPLIST_KEY_NSHumanReadableCopyright` stays `""` — **0-line pbxproj diff, binding** (S29).
- [ ] 2.4 Re-run `fast_unit_command`; T9 + T10 green; re-confirm the pbxproj diff is still 2 lines.

## Phase 3: Release script and export options — Work unit 3 (S20, S21, S22)

- [ ] 3.1 **RED** suite `ReleasePipelinePlacementTests` — **T1**: `scripts/ExportOptions.plist` exists;
      `scripts/release.sh` exists **and** `FileManager.default.isExecutableFile(atPath:)` is true (S21).
      *Threat row: documentation-like paths / executable classification.*
- [ ] 3.2 **RED** suite `ReleaseWorkflowContractTests` — **T7**: `ExportOptions.plist` parses via
      `PropertyListSerialization` with `method == "developer-id"`, `signingStyle == "automatic"`,
      `teamID == "Z3S5JK8E38"` (S22).
- [ ] 3.3 **RED** **T8**: `release.sh` contains every stage command — `xcodebuild archive`,
      `-exportArchive`, `ditto -c -k --keepParent --sequesterRsrc`, `notarytool submit`, `--wait`,
      `stapler staple`, `rm -f` before the re-`ditto`, `stapler validate`, `spctl -a -vvv -t install`,
      `codesign -dvvv`, `--entitlements :-`, `lipo -archs`, all three `verify` `plutil -extract` keys
      (`CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleDisplayName`), the `Contents/`
      enumeration guard, and `set -euo pipefail` (S20).
- [ ] 3.4 **RED** **T15a**: `release.sh` contains **no `gh `** and **no `git `** at all — it can neither
      select a repository nor publish (S19, S20). *Threat rows: git repository selection, commit state,
      push state.* (T15 is split from the design's single row so no test spans two work units.)
- [ ] 3.5 **RED** **T16a**: `release.sh` contains no `set -x` and no `set -eux` (S26).
      *Threat row: secret exposure.*
- [ ] 3.6 **GREEN** Create `scripts/ExportOptions.plist` with the design's complete content
      (`developer-id` / `automatic` / `Z3S5JK8E38` / `destination export` /
      `manageAppVersionAndBuildNumber false`).
- [ ] 3.7 **GREEN** Create `scripts/release.sh` per design: `archive export package notarize staple
      verify all`; `set -euo pipefail`, never `set -x`; repo root from `$(dirname "$0")/..`, never
      `$PWD`; env contract `VERSION`, `BUILD_NUMBER`, `ASC_KEY_PATH/ID/ISSUER_ID`, `SIGNING_STYLE`
      (default `automatic`), `RELEASE_BUILD_DIR` (default `build`, gitignored). `staple` **deletes** the
      pre-notarization zip before re-`ditto`. `verify` runs its eight gates on `$BUILD/verify` — the copy
      extracted from the published zip — including the **negated** sandbox check
      `! codesign -d --entitlements :- "$V" 2>&1 | grep -q 'com.apple.security.app-sandbox'`
      (never `grep -qv`, which cannot fail). `chmod +x scripts/release.sh`.
- [ ] 3.8 **ci-gate G2** — command: `shellcheck scripts/release.sh`. Accepted output: **no findings,
      exit 0**. Not a test task.

## Phase 4: Release workflow — Work unit 4 (S3, S4, S19, S21, S24, S25, S26)

- [ ] 4.1 **RED** **T2** in `ReleasePipelinePlacementTests`: `.github/workflows/release.yml` exists (S21).
- [ ] 4.2 **RED** **T3**: positives — the only trigger is `push:` → `tags:` containing `'v*'`; negatives —
      no `pull_request:`, no `schedule:`, no `workflow_dispatch:`, no `branches:` under `push:`, and no
      `xcodebuild test`; design-owned pins (not spec coverage) — `runs-on: macos-26`,
      `contents: write`, `concurrency:`, `xcode-select -s /Applications/Xcode_26.6.app` (S3).
- [ ] 4.3 **RED** **T19**: a step whose body contains `github.event.repository.private` **and** `exit 1`
      exists and appears **before** every step referencing `scripts/release.sh` — pinned structurally
      because G3 runs on a public repo and can never exercise it (S4).
- [ ] 4.4 **RED** **T4**: split the workflow on `- name:` step boundaries; the step whose body contains
      `security delete-keychain` **also** contains `if: always()` (position-independent, not a bare
      substring pair) (S25).
- [ ] 4.5 **RED** **T5**: every `${{ secrets.X }}` occurrence sits on a line matching
      `^[A-Z0-9_]+: \$\{\{ secrets\.[A-Z0-9_]+ \}\}$` — only as `env:` right-hand sides (S26).
      *Threat row: secret exposure.*
- [ ] 4.6 **RED** **T6**: the set of referenced secret names **equals** the six expected names (set
      equality, so a seventh secret fails too) (S26).
- [ ] 4.7 **RED** **T15b**: the workflow contains no `gh release delete`, `gh release edit`, `git push`,
      `git tag`, `git commit`, `git add`; the only `gh ` invocation is `gh release create` (S18, S19).
      *Threat row: PR commands.*
- [ ] 4.8 **RED** **T16b**: the workflow contains no `set -x` and no `set -eux` (S26).
- [ ] 4.9 **GREEN** Create `.github/workflows/release.yml` exactly per the design's YAML: private-repo
      fail-fast → checkout → Xcode pin → version derivation → ephemeral keychain + `$RUNNER_TEMP/asc.p8`
      (`chmod 600`) → one named step per `release.sh` phase (ASC env repeated verbatim per step, **no**
      YAML anchors) → record signing evidence → `gh release create … --verify-tag --generate-notes`
      with the hyphen-derived `--prerelease` and the named extension point comment → `if: always()`
      keychain + key deletion.
- [ ] 4.10 **GREEN-on-arrival** (declared, not RED, and authored in this commit so the pin predates the
      mistake): **T12** no file under `cellar/` recursively has extension `plist`, `yml`, `yaml` or `sh`
      (S21); **T13** no `-----BEGIN` PEM header and no `.p12` / `.p8` / `.cer` / `.mobileprovision` file
      anywhere in the repo (excluding `.git`, `build`, `.build`), **and** no `.entitlements` file and no
      `CODE_SIGN_ENTITLEMENTS` key in `project.pbxproj` (S24, S11). Must pass on the first run — they
      prove the new files did not land inside the synchronized root group.
- [ ] 4.11 **ci-gate G1** — command: `actionlint .github/workflows/release.yml`. Accepted output:
      **no output, exit 0**. Not a test task.

## Phase 5: Documentation — Work unit 5 (S8, S12)

- [ ] 5.1 **RED** **T17b** in `ReleaseMetadataTests`: `RELEASING.md` contains the literal `1.0.0 (1)`
      together with an override line carrying both `MARKETING_VERSION=` and `CURRENT_PROJECT_VERSION=`
      (S8). (Split from T17 so the pbxproj half of that row cannot stay red across a commit boundary.)
- [ ] 5.2 **RED** **T18**: `RELEASING.md` names all five literally — `allow-jit`,
      `allow-unsigned-executable-memory`, `disable-library-validation`, `ENABLE_USER_SELECTED_FILES`,
      `REGISTER_APP_GROUPS` (S12).
- [ ] 5.3 **GREEN** Create top-level `RELEASING.md` §1–§8 per the design table: CI is the only publishing
      path; prerequisites P1–P5 named; tag-and-release runbook (a failure publishes nothing; retry by
      deleting the **tag**, never a published release); version policy incl. the `1.0.0 (1)` fact and the
      one-line override; local rehearsal env table; **§6 the PRD:157 entitlements rationale**;
      the contract inherited by `m6-sparkle-updates` / `m6-cask-tap`; troubleshooting.
      §6's quoted `codesign` / brew-mutation evidence is a **clearly marked evidence placeholder** until
      6.4 lands — the doc must not assert unmeasured output.
- [ ] 5.4 **GREEN** `PRD.md` :9, :157, :168, :187, :212, :224, :227 — rewritten in place with the reason
      (D8, tip-jar precedent), using the design table's exact wording; :227 says the arm64-only claim
      *"was being contradicted by the build — Cellar was shipping universal by accident until the pin
      landed"* (U27), not "a formality". :168 only if its wording implies the feed already exists.
- [ ] 5.5 **GREEN** `README.md`: `## Install` between `## Requirements` and `## Building` (download,
      unzip, drag to `/Applications`; Apple Silicon + macOS 26; a single "Open" because the build is
      notarized and stapled) and `## Releasing` after `## Building` (three lines + pointer). The runbook
      is **not** duplicated here.
- [ ] 5.6 **ci-gate G4** — commands: `xcodebuild test -project cellar.xcodeproj -scheme cellar
      -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` and
      `swift test --package-path Packages/CellarCore`. Accepted output: CellarCore **1732** passed
      (unchanged — 0-diff proof) and `cellarTests` **141 + the new cases**, 0 failures, counted as
      **distinct** `Test case '…' passed` ids. Assert counts, never `TEST SUCCEEDED` alone.

## Phase 6: Gates and evidence (`ci-gate` / `manual-evidence` — not test tasks, and not merge blockers)

Sequential and hard-gated: 6.2 blocks 6.3–6.6. The PR of Phases 1–5 may merge before any of this.

- [ ] 6.1 **Gate** Confirm maintainer prerequisites P1–P5 are complete. **`U26` is BLOCKED until P2+P3
      exist**: `security find-identity -v -p codesigning` currently lists only
      `Apple Development: Juan Casanueva (A8EB4839B9)`. No tag may be pushed before 6.2 is green.
- [ ] 6.2 **manual-evidence `U26`** — local Developer ID export + notarize round trip via
      `scripts/release.sh all`. Record **M1** `notarytool submit --wait` → `status: Accepted`; **M2**
      `notarytool log <id>` → `"status": "Accepted"`, `"issues": null`; **M3** `spctl -a -vvv -t install
      <extracted>/cellar.app` **with networking disabled** → `…: accepted`, `source=Notarized Developer
      ID`; **M4** `stapler validate` → `The validate action worked!`; **M6** `codesign -dvvv
      --entitlements :-` → `Authority=Developer ID Application: … (Z3S5JK8E38)`,
      `TeamIdentifier=Z3S5JK8E38`, `flags=0x10000(runtime)`, entitlements dict with **no**
      `com.apple.security.cs.*` key; **M7** `lipo -archs …/Contents/MacOS/cellar` → exactly `arm64`
      (load-bearing — proves the U27 fix took). Spec: S9, S10, S14, S15.
- [ ] 6.3 **Conditional — requires explicit maintainer approval; apply only if 6.2 measures headless
      automatic Developer ID export failing.** The pre-authored Manual fallback (DD-5, D9): pbxproj
      **Release block only** → `CODE_SIGN_STYLE = Manual;`, add `CODE_SIGN_IDENTITY = "Developer ID
      Application";` and `PROVISIONING_PROFILE_SPECIFIER = "";`; `ExportOptions.plist` `signingStyle` →
      `manual`; `SIGNING_STYLE=manual` in the workflow `env:`; and **T14 explicitly relaxed** to compare
      the two blocks modulo exactly those three keys, with the reason in the test's doc comment —
      silently deleting the assertion is not an option. Never absorbed at apply time.
- [ ] 6.4 **manual-evidence `U28` / M8** — launch the notarized, stapled build from `/Applications`;
      install then uninstall a small formula in-app; confirm with `brew list --formula`. Accepted:
      the mutation completes with **no entitlement added**. Then fill `RELEASING.md` §6 with the quoted
      M6 + M8 output as a follow-up commit `docs(release): record measured signing evidence`. If M8
      fails, **no entitlement is added by default**: report it and reopen the question as a decision (S13).
- [ ] 6.5 **ci-gate G3** — dry-run prerelease on the real repository (D2 decision 2):
      `git tag v0.0.1-rc.1 && git push origin v0.0.1-rc.1`. Accepted: the full pipeline is green and a
      **prerelease** carries `Home-Cellar-0.0.1-rc.1.zip` at the documented URL. Delete it **manually**
      afterwards (`gh release delete v0.0.1-rc.1 --cleanup-tag`) — the workflow never deletes anything.
      Watch R4: a non-numeric `MARKETING_VERSION` may be rejected; fallback is the tag name `v0.0.1`.
      Spec: S1, S2, S5, S6, S17, S23.
- [ ] 6.6 **manual-evidence M5 + M10** — M5: download the published zip in a browser on a machine that
      has never seen the bundle, `xattr -p com.apple.quarantine cellar.app` before launch, unzip in
      Finder, drag to `/Applications`, double-click → quarantine present beforehand and a single
      **"Open"** dialog, not "cannot be opened…" (S16). M10: `gh run view <run-id> --log > "$TMPDIR/
      release-run.log"`, then `rg -n -e '-----BEGIN' -e 'PRIVATE KEY' -e 'AuthKey_' -e
      '^MI[A-Za-z0-9+/]{40,}' "$TMPDIR/release-run.log"` → **zero matches**, every secret masked as
      `***`; then `rm -f "$TMPDIR/release-run.log"` so the check is not itself the leak (S27).
- [ ] 6.7 **manual-evidence M9 — deferred by definition, not a failure.** From the **second** published
      release onward: extract both zips and compare `plutil -extract CFBundleVersion raw
      <app>/Contents/Info.plist`; the newer value must be strictly greater, including across a re-cut
      tag (S7). At the first release there is nothing to compare against.
- [ ] 6.8 **Optional hardening** (validator suggestions C/D/E, carried as notes, none required):
      (C) add a post-publish `curl -fsSI` reachability assertion on the documented asset URL to close S1
      in CI rather than by observation; (D) state in `RELEASING.md` that the CI `spctl` runs **online**
      and the offline claim of S14 rests on M3; (E) the YAML-anchor rationale already sits as a comment
      in the workflow — leave the wording as authored.
