# Design: Developer ID Release Pipeline (`m6-release-pipeline`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled (no reviews started).

Inputs: `proposal.md` (Engram obs 7662, ACCEPTED — D1–D10 binding),
`specs/release-distribution/spec.md` (**the authority for what must be true of a delivered build**;
scenario ids `S1`–`S29` below follow its own order), `explore.md`, decisions obs 7661.

`next_recommended: sdd-tasks`

Probes are **orchestrator-owned and were not run by this phase**. `[[U27]]` and `[[U29]]` are now
**resolved** and their measured wording is inlined below; `[[U26]]` and `[[U28]]` remain open and still
carry their tokens. See *Probe results* at the end. No probe outcome is invented anywhere.

> Size note: this document exceeds the 800-word default design budget by explicit launch-brief
> instruction (items 1–6). Density is preserved by tables; nothing is padded.

## Technical Approach

Export shape **8b-A**, split across two artifacts by ownership rather than by convenience:

- `.github/workflows/release.yml` owns **the runner, the secrets, and the cleanup** — everything that
  only exists on CI. It is the **only** publishing path (decision 4, obs 7661).
- `scripts/release.sh` owns **the build sequence** — archive → export → package → notarize → staple →
  verify — reading everything else from environment variables, so the identical commands run locally
  for the U26 rehearsal. It never publishes, never touches a keychain, and never touches git.

The workflow invokes the script **once per phase as a named step**, so a job log has one step per stage
and a failure names the stage, while the logic itself stays in one reviewable, locally runnable file.

Both files live **outside `cellar/`**, because `cellar/` is a `PBXFileSystemSynchronizedRootGroup`: any
`.plist`, `.sh` or `.yml` dropped inside it silently joins the app target and ships signed inside the
bundle. That placement is enforced by a test, not by a comment.

No production Swift is added. `rules.design`'s "keep all logic in CellarCore" and "protocol boundaries
for every external dependency" clauses have no surface here — the external dependency in this slice is
the **toolchain**, and its boundary is the `scripts/release.sh` environment contract below.

## Architecture Decisions

| # | Decision | Rejected alternative | Rationale |
|---|---|---|---|
| DD-1 | Workflow owns secrets/keychain/cleanup; `scripts/release.sh` owns the build sequence, invoked **one phase per named step** | All logic inline in YAML; or one opaque `release.sh all` step | Named steps keep failure attribution; one script keeps the U26 rehearsal a real rehearsal rather than an approximation. For the project's first CI, locally runnable release logic outranks YAML compactness |
| DD-2 | `release.sh <phase>` CLI: `archive export package notarize staple verify all` | Six separate scripts | One file, one env contract, one `set -euo pipefail`; `all` is the local rehearsal entry point |
| DD-3 | Version/arch gates run **twice**: on `build/export/cellar.app` before notarizing, then again on the copy **extracted from the published zip** | Gate once, at the end | The pre-notarize gate refuses to spend an Apple round trip on a mislabelled build; the post-extract gate is the only one that proves *the artifact users download* passed |
| DD-4 | ASC API key serves **three** consumers: `notarytool`, `xcodebuild -authenticationKey*` (D9), and nothing else | Apple ID + app-specific password for notarization | D5/D9: one credential, independently revocable, never prompts 2FA, and is exactly what `-allowProvisioningUpdates` needs — automatic signing therefore adds **zero** new credential surface |
| DD-5 | `SIGNING_STYLE` env var (`automatic` default) selects whether the `-allowProvisioningUpdates -authenticationKey*` flags are passed | Hardcode the flags | Makes the U26 fallback a two-line change instead of a workflow rewrite, and lets the local rehearsal skip provisioning updates against the login keychain |
| DD-6 | The ASC `.p8` is written to `$RUNNER_TEMP/asc.p8`, `chmod 600`, deleted in the `if: always()` step | Keep the key in an env var | `notarytool --key` and `xcodebuild -authenticationKeyPath` both take a **path**; there is no stdin form. The swift-security invariant is honoured by scope (runner temp, never the repo, never a log) and by unconditional deletion, not by pretending a file is avoidable |
| DD-7 | Prerelease flag derived from the tag: a `-` in `${GITHUB_REF_NAME}` adds `--prerelease` | A workflow input or a second workflow | Makes the `v0.0.1-rc.1` dry run (decision 2) a normal run of the real pipeline, which is the entire point of the rehearsal |
| DD-8 | The workflow contains **no** `gh release delete`, `gh release edit`, `git push`, `git tag`, or `git commit` — asserted by test | Auto-unflag the previous "latest" release | Decision 5, obs 7661: never delete or unflag a prior release. A future Sparkle appcast points at published assets; unflagging one strands installed copies |
| DD-9 | `ARCHS = arm64` is set in **both** app-target blocks | Release block only | The Debug/Release byte-identity invariant (currently true across all ~30 settings) is worth more than a marginally smaller diff, and a Debug build that differs in architecture from Release is a trap |
| DD-10 | The pre-authored Manual-signing fallback is a **separate, explicitly approved amendment** with its own rollback, marked conditional below | Absorb it silently at apply time if U26 fails | `rules.proposal`: pbxproj changes need a rollback plan, and a signing-style flip is a decision, not an implementation detail |

## Data Flow

    git tag vX.Y.Z ──push──► release.yml (macos-26, Xcode 26.6 pinned)
                                │
                                ├─ gate: repository is public ──fail fast──► (nothing published)
                                ├─ ephemeral keychain ← BUILD_CERTIFICATE_BASE64 / P12_PASSWORD
                                ├─ $RUNNER_TEMP/asc.p8 ← APPLE_API_KEY_P8
                                │
                                └─► scripts/release.sh  (VERSION, BUILD_NUMBER, ASC_*)
                                        archive ─► build/cellar.xcarchive
                                        export  ─► build/export/cellar.app
                                                   ├─ plutil: CFBundleShortVersionString == VERSION
                                                   └─ lipo -archs == arm64          ── fail ─► stop
                                        package ─► build/Home-Cellar-$VERSION.zip   (ditto)
                                        notarize─► notarytool submit --wait          ── fail ─► notarytool log ─► stop
                                        staple  ─► stapler staple .app ─► rm zip ─► re-ditto
                                        verify  ─► ditto -x to build/verify
                                                   spctl -a -vvv -t install
                                                   stapler validate
                                                   codesign -dvvv / --entitlements :-
                                                   lipo / plutil ×3 / Contents/ scan ── fail ─► stop
                                │
                                ├─► gh release create "$GITHUB_REF_NAME" <zip> --generate-notes
                                │      └── named extension point: appcast (m6-sparkle-updates), cask bump (m6-cask-tap)
                                └─► if: always() ─ delete keychain, rm asc.p8

## Workflow Architecture — `.github/workflows/release.yml`

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: write

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false        # never cancel a run mid-notarization

jobs:
  release:
    runs-on: macos-26
    timeout-minutes: 90
    steps:
      - name: Refuse to publish from a private repository
        if: ${{ github.event.repository.private }}
        run: |
          echo "::error::Repository is private; release assets are not anonymously downloadable."
          exit 1

      - uses: actions/checkout@v4

      - name: Pin Xcode
        run: sudo xcode-select -s /Applications/Xcode_26.6.app

      - name: Derive version from tag
        run: |
          set -euo pipefail
          echo "VERSION=${GITHUB_REF_NAME#v}" >> "$GITHUB_ENV"
          echo "BUILD_NUMBER=${GITHUB_RUN_NUMBER}" >> "$GITHUB_ENV"

      - name: Create ephemeral keychain and import Developer ID certificate
        env:
          BUILD_CERTIFICATE_BASE64: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
          P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
          APPLE_API_KEY_P8: ${{ secrets.APPLE_API_KEY_P8 }}
        run: |
          set -euo pipefail                       # never -x, never echo a secret
          KEYCHAIN="$RUNNER_TEMP/cellar-release.keychain-db"
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          security set-keychain-settings -lut 21600 "$KEYCHAIN"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
          printf '%s' "$BUILD_CERTIFICATE_BASE64" | base64 --decode -o "$RUNNER_TEMP/cert.p12"
          security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" \
            -T /usr/bin/codesign -T /usr/bin/security -f pkcs12
          security set-key-partition-list -S apple-tool:,apple:,codesign: \
            -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
          security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
          rm -f "$RUNNER_TEMP/cert.p12"
          printf '%s' "$APPLE_API_KEY_P8" > "$RUNNER_TEMP/asc.p8"
          chmod 600 "$RUNNER_TEMP/asc.p8"
          security find-identity -v -p codesigning "$KEYCHAIN"   # identity names only

      # The three ASC bindings are repeated verbatim per step rather than shared through a YAML
      # anchor (&asc / *asc): GitHub Actions does not support anchors reliably across all workflow
      # contexts, and a silently dropped alias would strip the credentials from a step. Six repeated
      # lines are cheaper than that failure mode.
      - name: Archive
        env:                                       # ids are not secret material; the .p8 is a path
          ASC_KEY_PATH: ${{ runner.temp }}/asc.p8
          ASC_KEY_ID: ${{ secrets.APPLE_API_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}
        run: scripts/release.sh archive

      - name: Export and gate version + architecture
        env:
          ASC_KEY_PATH: ${{ runner.temp }}/asc.p8
          ASC_KEY_ID: ${{ secrets.APPLE_API_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}
        run: scripts/release.sh export            # plutil == $VERSION, lipo -archs == arm64

      - name: Package (ditto)
        run: scripts/release.sh package

      - name: Notarize
        env:
          ASC_KEY_PATH: ${{ runner.temp }}/asc.p8
          ASC_KEY_ID: ${{ secrets.APPLE_API_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.APPLE_API_ISSUER_ID }}
        run: scripts/release.sh notarize          # notarytool submit --wait; log fetched on failure

      - name: Staple and repackage
        run: scripts/release.sh staple

      - name: Verify the extracted artifact
        run: scripts/release.sh verify            # S2 S6 S10 S14 S15 S23 gates, on the extracted copy

      - name: Record signing evidence
        run: codesign -dvvv --entitlements :- "build/export/cellar.app" 2>&1   # RELEASING.md source

      - name: Publish GitHub Release
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          PRERELEASE=""
          case "$GITHUB_REF_NAME" in *-*) PRERELEASE="--prerelease" ;; esac
          gh release create "$GITHUB_REF_NAME" "build/Home-Cellar-${VERSION}.zip" \
            --verify-tag --generate-notes --title "$GITHUB_REF_NAME" $PRERELEASE
      # --- extension point: appcast publication (m6-sparkle-updates) and cask bump
      #     (m6-cask-tap) insert here without restructuring the job. ---

      - name: Delete ephemeral keychain and API key
        if: always()
        run: |
          security delete-keychain "$RUNNER_TEMP/cellar-release.keychain-db" 2>/dev/null || true
          rm -f "$RUNNER_TEMP/asc.p8" "$RUNNER_TEMP/cert.p12"
```

**Secret discipline (binding).** Exactly six secrets: `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`,
`KEYCHAIN_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`. Every
`${{ secrets.* }}` reference appears **only** as the right-hand side of an `env:` binding — never inside
a `run:` line, never interpolated into a command. No `set -x`, no `set -eux`, no `echo` of a secret
value. `DEVELOPMENT_TEAM = Z3S5JK8E38` stays in the repo and is not a secret.

## `scripts/release.sh` — parity/rehearsal only

**Not a publishing path** (decision 4). It contains no `gh`, no `git`, and no `security` invocation; it
cannot publish, tag, or mutate credentials even if run by hand. It resolves the repository root from its
own location (`cd "$(dirname "$0")/.."`), never from `$PWD`.

| Env var | Required for | Meaning |
|---|---|---|
| `VERSION` | all phases | Marketing version — CI passes `${GITHUB_REF_NAME#v}`; locally e.g. `1.0.0` |
| `BUILD_NUMBER` | `archive`, `export` | `CURRENT_PROJECT_VERSION` — CI passes `${GITHUB_RUN_NUMBER}`; locally any increasing integer |
| `ASC_KEY_PATH`, `ASC_KEY_ID`, `ASC_ISSUER_ID` | `notarize`, and `archive`/`export` when `SIGNING_STYLE=automatic` | App Store Connect API key (path + ids) |
| `SIGNING_STYLE` | optional, default `automatic` | `automatic` adds `-allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID`; `manual` omits them (U26 fallback, and the quieter local rehearsal) |
| `RELEASE_BUILD_DIR` | optional, default `build` | Output root; gitignored |

Phase bodies (exact command shapes; `set -euo pipefail`, never `set -x`):

```sh
archive:  xcodebuild archive -project cellar.xcodeproj -scheme cellar -configuration Release \
            -destination 'generic/platform=macOS' -archivePath "$BUILD/cellar.xcarchive" \
            ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
            MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" $SIGN_FLAGS
export:   xcodebuild -exportArchive -archivePath "$BUILD/cellar.xcarchive" \
            -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$BUILD/export" $SIGN_FLAGS
          plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist"   # == $VERSION
          lipo -archs "$APP/Contents/MacOS/cellar"                                    # == arm64
package:  ditto -c -k --keepParent --sequesterRsrc "$APP" "$BUILD/Home-Cellar-$VERSION.zip"
notarize: xcrun notarytool submit "$BUILD/Home-Cellar-$VERSION.zip" \
            --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
            --wait --output-format json     # on failure: xcrun notarytool log <id>, then exit 1
staple:   xcrun stapler staple "$APP"
          rm -f "$BUILD/Home-Cellar-$VERSION.zip"     # the published archive is unambiguously
          <package again, same zip path>              # post-staple: never an overwrite-in-place
verify:   ditto -x -k "$BUILD/Home-Cellar-$VERSION.zip" "$BUILD/verify"
          V="$BUILD/verify/cellar.app"
          spctl -a -vvv -t install "$V"                                   # accepted / Notarized  S14
          xcrun stapler validate "$V"                                     #                       S14
          codesign --verify --strict --verbose=2 "$V"
          codesign -dvvv "$V" 2>&1 | tee "$BUILD/codesign.txt"            # asserted below
            grep -q 'flags=0x10000(runtime)'                              #                       S10
            grep -q 'Authority=Developer ID Application'                  #                       S15
            grep -q 'TeamIdentifier=Z3S5JK8E38'                           #                       S15
          ! codesign -d --entitlements :- "$V" 2>&1 \
            | grep -q 'com.apple.security.app-sandbox'                    # sandbox absent        S10 (negated match — never grep -qv)
          lipo -archs "$V/Contents/MacOS/cellar"                          # == arm64              S9
          plutil -extract CFBundleShortVersionString raw "$V/Contents/Info.plist"  # == $VERSION
          plutil -extract CFBundleVersion raw "$V/Contents/Info.plist"    # == $BUILD_NUMBER      S6
          plutil -extract CFBundleDisplayName raw "$V/Contents/Info.plist"  # == Home-Cellar      S2
          find "$V/Contents" \( -name '*.yml' -o -name '*.yaml' -o -name '*.sh' \
            -o -name 'ExportOptions*.plist' \) -print | <must be empty>   # nothing shipped       S23
```

Each `verify` assertion is a hard gate: a mismatch exits non-zero, the publish step never runs, and
nothing is published (S17). The gates run on `$BUILD/verify` — the copy **extracted from the published
zip** — not on `build/export`, which is what makes them statements about the artifact users download.

`scripts/ExportOptions.plist` — complete content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>                          <string>developer-id</string>
    <key>signingStyle</key>                    <string>automatic</string>
    <key>teamID</key>                          <string>Z3S5JK8E38</string>
    <key>destination</key>                     <string>export</string>
    <key>manageAppVersionAndBuildNumber</key>  <false/>
</dict>
</plist>
```

## pbxproj Changes (exact) and Rollback

**Exactly one setting** (proposal :154/:267/:334 binds `project.pbxproj` to a single change), in
**both** app-target blocks — `BCDBE99F301E2D420013A38D /* Debug */` (:416-448) and
`BCDBE9A0301E2D420013A38D /* Release */` (:449-481). **Two changed lines total.**

| Setting | Before | After | Placement |
|---|---|---|---|
| `ARCHS` | absent (implicit `ARCHS_STANDARD`) | `ARCHS = arm64;` | first key in `buildSettings` (alphabetical, before `ASSETCATALOG_*`) — :419 and :452 |

**The copyright does not touch the pbxproj (S29).** `INFOPLIST_KEY_NSHumanReadableCopyright` stays at
`""` on :431 and :464 — a **0-line diff, binding**. The value goes **only** into
`cellar/InfoPlist.xcstrings`, whose `NSHumanReadableCopyright` moves `state: new` → `translated` with
the string `Copyright © 2026 Juan Casanueva. All rights reserved.`, joining the two bundle-name keys
the catalog already owns. Under `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` the catalog is the
**single authority**; two sources for one key drift, which is exactly what S29 forbids. U27 measured
that an empty `INFOPLIST_KEY_*` value is **dropped, not emitted** — the generated Info.plist at
`ec7b1c5` has no `NSHumanReadableCopyright` key at all — so the empty build setting carries no
competing value and needs no edit. Consequence for the tests: T9 asserts the **catalog** value and T10
asserts the bundle's **`localizedInfoDictionary`**; neither asserts pbxproj bytes, and neither may fall
back to the raw `infoDictionary`, which does not carry catalog-sourced keys.

**Rollback (`rules.proposal`).** Revert those two lines to restore implicit `ARCHS_STANDARD`; nothing
else in the file moves. `CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`, `DEVELOPMENT_TEAM`,
`ENABLE_HARDENED_RUNTIME`, `ENABLE_APP_SANDBOX`, `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`,
`INFOPLIST_KEY_NSHumanReadableCopyright`, and every `INFOPLIST_KEY_*` are **0-line diffs — binding**,
and the Debug/Release blocks stay byte-identical (T14). `.github/`, `scripts/`, `RELEASING.md` are net-new: deleting them removes the pipeline
with zero effect on the app. `Package.swift`, `Package.resolved`, `cellar.xcscheme` and every Swift
source: **0-line diffs — binding**. A `git revert` of the PR orphans nothing (no runtime code, no cache,
no schema, no Keychain item, no migration). A revert does **not** unpublish a release: a bad release is
handled by cutting a new patch tag, never by deleting or unflagging a published one (DD-8).
Post-revert checks: `swift build --package-path Packages/CellarCore` and the config `build_command`.

## Conditional — pre-authored U26 fallback (Manual signing flip)

**Applies only if `[[U26]]` measures headless automatic Developer ID export failing.** Not authorized
in advance to be applied silently: it is a separate, explicitly approved amendment (proposal, D9).

| File | Change |
|---|---|
| `project.pbxproj`, **Release block only** (`BCDBE9A0…`) | `CODE_SIGN_STYLE = Automatic;` → `= Manual;`; add `CODE_SIGN_IDENTITY = "Developer ID Application";`; add `PROVISIONING_PROFILE_SPECIFIER = "";` |
| `scripts/ExportOptions.plist` | `signingStyle` → `manual` |
| `scripts/release.sh` invocation | `SIGNING_STYLE=manual` in the workflow `env:` (drops `-allowProvisioningUpdates` and the three `-authenticationKey*` flags; the ASC key stays — `notarytool` still needs it) |
| `ReleaseMetadataTests` byte-identity assertion | Must be **explicitly relaxed** to compare the two blocks modulo exactly those three keys, with the reason in the test's doc comment. Silently deleting the assertion is not an option |

Fallback rollback: revert those edits; the byte-identity assertion returns to strict; nothing else moves.

## Testing Strategy

`strict_tdd: true`. This slice adds **no production Swift**, so the honest split is declared rather than
manufactured. One new file: `cellarTests/ReleasePipelineCompositionTests.swift`, self-contained
(its own `#filePath`-anchored repo-root helper) so rollback is a single file deletion, in the
`SecurityCompositionSupport` idiom — reads the repository off disk and asserts over text.

### Tier 1 — RED-first, mandatory (false today, true after)

| # | Suite | Assertion | Spec |
|---|---|---|---|
| T1 | `ReleasePipelinePlacementTests` | `scripts/ExportOptions.plist` exists; `scripts/release.sh` exists **and** `FileManager.isExecutableFile` | S21 |
| T2 | `ReleasePipelinePlacementTests` | `.github/workflows/release.yml` exists | S21 |
| T3 | `ReleaseWorkflowContractTests` | **Positives (S3):** the only trigger is `push:` → `tags:` containing `'v*'`. **Negatives (S3):** the workflow contains no `pull_request:`, no `schedule:`, no `workflow_dispatch:`, no `branches:` key under `push:`, and no `xcodebuild test`. **Design-owned pins (not spec coverage):** `runs-on: macos-26`, `contents: write`, `concurrency:`, `xcode-select -s /Applications/Xcode_26.6.app` | S3 |
| T4 | `ReleaseWorkflowContractTests` | Split the workflow on `- name:` step boundaries; the step whose body contains `security delete-keychain` **also** contains `if: always()` (position-independent, not a bare substring pair) | S25 |
| T5 | `ReleaseWorkflowContractTests` | Every `${{ secrets.X }}` occurrence sits on a line matching `^[A-Z0-9_]+: \$\{\{ secrets\.[A-Z0-9_]+ \}\}$` — i.e. only in `env:` bindings | S26 |
| T6 | `ReleaseWorkflowContractTests` | The set of referenced secret names **equals** the six expected names (set equality, so a seventh secret fails too) | S26 |
| T7 | `ReleaseWorkflowContractTests` | `ExportOptions.plist` parses via `PropertyListSerialization` and `method == "developer-id"`, `signingStyle == "automatic"`, `teamID == "Z3S5JK8E38"` | S22 |
| T8 | `ReleaseWorkflowContractTests` | `release.sh` contains every stage command: `xcodebuild archive`, `-exportArchive`, `ditto -c -k --keepParent --sequesterRsrc`, `notarytool submit`, `--wait`, `stapler staple`, `rm -f` before the re-`ditto`, `stapler validate`, `spctl -a -vvv -t install`, `codesign -dvvv`, `--entitlements :-`, `lipo -archs`, all three `plutil -extract` keys read in `verify` (`CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleDisplayName`), the `Contents/` enumeration guard, `set -euo pipefail` | S20 |
| T9 | `ReleaseMetadataTests` | `cellar/InfoPlist.xcstrings` parses as JSON and `NSHumanReadableCopyright` == `Copyright © 2026 Juan Casanueva. All rights reserved.` **and** neither app-target pbxproj block carries a non-empty `INFOPLIST_KEY_NSHumanReadableCopyright` — one authority, no competing value | S29 |
| T10 | `ReleaseMetadataTests` | `Bundle.main.localizedInfoDictionary?["NSHumanReadableCopyright"] as? String` **equals** the exact string above. The **localized** dictionary is pinned deliberately: catalog-sourced keys land in `InfoPlist.strings`, and U27 measured the raw key absent from the generated Info.plist, so a fallback to `infoDictionary` would assert on a key that does not exist | S28 |
| T11 | `ReleaseMetadataTests` | pbxproj: the **two** `XCBuildConfiguration` blocks containing `PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;` each contain `ARCHS = arm64;` (exactly two matches; the trailing `;` excludes `cellarTests`) | — (D3/DD-9) |
| T17 | `ReleaseMetadataTests` | Both app-target blocks still carry `MARKETING_VERSION = 1.0.0;` and `CURRENT_PROJECT_VERSION = 1;` (two matches each), and — design-owned pin closing the S10 gate's blast radius — `ENABLE_APP_SANDBOX = NO;` and `ENABLE_HARDENED_RUNTIME = YES;` (two matches each), **and** `RELEASING.md` contains the literal `1.0.0 (1)` together with an override line carrying both `MARKETING_VERSION=` and `CURRENT_PROJECT_VERSION=` | S8 |
| T18 | `ReleaseMetadataTests` | `RELEASING.md` names all five: `allow-jit`, `allow-unsigned-executable-memory`, `disable-library-validation`, `ENABLE_USER_SELECTED_FILES`, `REGISTER_APP_GROUPS` | S12 |
| T19 | `ReleaseWorkflowContractTests` | A workflow step exists whose body contains `github.event.repository.private` **and** `exit 1`, and it appears **before** every step referencing `scripts/release.sh` — the private-repo fail-fast, pinned structurally because G3 runs on a public repository and can never exercise it | S4 |

### Tier 2 — GREEN-on-arrival regression pins (declared, not RED)

| # | Assertion | Why it is kept | Spec |
|---|---|---|---|
| T12 | No file under `cellar/` (recursive) has extension `plist`, `yml`, `yaml`, or `sh` | The only automated guard against the synchronized-root-group trap; true today, and the trap is a *future* mistake | S21 |
| T13 | No `-----BEGIN` PEM header and no `.p12` / `.p8` / `.cer` / `.mobileprovision` file anywhere in the repo (excluding `.git`, `build`, `.build`); **and (S11)** no `.entitlements` file anywhere in the repo **and** no `CODE_SIGN_ENTITLEMENTS` key in `project.pbxproj` | A committed key is unrecoverable once pushed, and a `.entitlements` file appearing later would make `ENABLE_USER_SELECTED_FILES` / `REGISTER_APP_GROUPS` live. Both already hold at `ec7b1c5`, so both are **GREEN-on-arrival** — the pin must predate the mistake | S24, S11 |
| T14 | The two app-target `buildSettings` blocks are equal after whitespace normalization (modulo the `name = Debug/Release;` line) | **Design-owned pin, not spec coverage.** The invariant D9/DD-9 leans on; would be silently lost otherwise | — |
| T15 | Workflow contains no `gh release delete`, `gh release edit`, `git push`, `git tag`, `git commit`, `git add`; the only `gh ` invocation is `gh release create`. **And (S20):** `release.sh` contains **no `gh ` and no `git `** at all — it cannot publish, tag, or select a repository | Decision 5, DD-8, and the threat-matrix rows below | S19, S20 |
| T16 | Workflow contains no `set -x` / `set -eux`; `release.sh` likewise | swift-security invariant, structurally enforced | S26 |

**Rejected as an unfaithful test** (carried from the proposal): asserting arm64 from `Bundle.main`'s
Mach-O header in `cellarTests`. The test host is built by `xcodebuild test`, not by `archive`, so it
cannot prove what the release binary contains. Architecture belongs to the CI `lipo -archs` gate.

### Tier 3 — `ci-gate` (verification evidence, never a spec scenario)

| Gate | Command | Expected |
|---|---|---|
| G1 | `brew install actionlint && actionlint .github/workflows/release.yml` | no output, exit 0 |
| G2 | `brew install shellcheck && shellcheck scripts/release.sh` | no findings, exit 0 |
| G3 | Dry-run prerelease on the real repository (decision 2): `git tag v0.0.1-rc.1 && git push origin v0.0.1-rc.1` | full pipeline green; a **prerelease** carrying `Home-Cellar-0.0.1-rc.1.zip`; deleted **manually** afterwards (`gh release delete v0.0.1-rc.1 --cleanup-tag`) — the workflow never deletes anything |
| G4 | Suite at the U29 baseline plus the new file | U29 measured at `ec7b1c5`: CellarCore **1732/1732** passed, `cellarTests` **141 distinct** Swift Testing cases / 0 failures. `cellarUITests/ReleaseNotesUITests` is **owned and fixed** (PR #21, `b2c440f`) — the "unowned/failing" note inherited from the tip-jar exploration is stale. So the baseline is 1732 + 141 distinct green with **no inherited failure**, and the new file must leave both counts green (141 → 141 + the new cases). Count distinct `Test case '…' passed` ids; the XCTest `Executed 0 tests` line is meaningless for Swift Testing bundles |

### Tier 4 — `manual-evidence` (exact command + exact expected output the verifier must accept)

| # | Command | Accepted output | Probe / Spec |
|---|---|---|---|
| M1 | `xcrun notarytool submit … --wait` | `status: Accepted` in the job log | `[[U26]]` |
| M2 | `xcrun notarytool log <submission-id> --key … --key-id … --issuer …` | `"status": "Accepted"`, `"issues": null` | `[[U26]]` |
| M3 | `spctl -a -vvv -t install <extracted>/cellar.app` **with networking disabled** | `…: accepted` and `source=Notarized Developer ID` | `[[U26]]` |
| M4 | `xcrun stapler validate <extracted>/cellar.app` | `The validate action worked!` | `[[U26]]` |
| M5 | Download the published zip in a browser on a machine that has never seen the bundle; `xattr -p com.apple.quarantine cellar.app` before launch; unzip in Finder, drag to `/Applications`, double-click | quarantine attribute present beforehand; first launch shows a single **"Open"** dialog — **not** "cannot be opened because Apple cannot check it for malicious software" | `[[U26]]` |
| M6 | `codesign -dvvv --entitlements :- /Applications/cellar.app` | `Authority=Developer ID Application: … (Z3S5JK8E38)`, `TeamIdentifier=Z3S5JK8E38`, `flags=0x10000(runtime)`, and an entitlements dict containing **no** `com.apple.security.cs.*` key | `[[U26]]` |
| M7 | `lipo -archs /Applications/cellar.app/Contents/MacOS/cellar` | exactly `arm64`. **Load-bearing:** U27 measured the current Release archive at `ec7b1c5` as **universal (`x86_64 arm64`)**, so the `ARCHS = arm64` pin is a **fix, not a formality** — this is the check that proves the fix took | U27 (resolved), S9 |
| M8 | Launch the **notarized, stapled** build from `/Applications`; run a real mutation in-app (install then uninstall a small formula); confirm with `brew list --formula` | mutation completes, streamed log ends successfully, `brew list` reflects it — with **no** entitlement added to get there | `[[U28]]`, S13 |
| M9 | On the **second and every later** release: download both the previous and the new `Home-Cellar-<version>.zip`, extract each, and run `plutil -extract CFBundleVersion raw <app>/Contents/Info.plist` on both | the newer release's value is **strictly greater**, including across a re-cut tag for the same marketing version (`GITHUB_RUN_NUMBER` only increases). **Explicitly checkable from the second published release onward** — at the first release there is nothing to compare against, and that is not a failure | S7 |
| M10 | After a completed run: `gh run view <run-id> --log > "$TMPDIR/release-run.log"`, then `rg -n -e '-----BEGIN' -e 'PRIVATE KEY' -e 'AuthKey_' -e '^MI[A-Za-z0-9+/]{40,}' "$TMPDIR/release-run.log"` (the bare token `p12` is deliberately **not** in the pattern set: GitHub Actions echoes every `run:` body into the step header, so `cert.p12` appears in every honest log — the check targets secret *values*, not file names), then read the keychain/notarize step output end to end, then `rm -f "$TMPDIR/release-run.log"` | **zero matches**; every secret-derived value appears only as GitHub's `***` mask; no certificate, key, password or API-key value anywhere in the log. The downloaded log is deleted afterwards so the check does not become the leak | S27 |

M6 and M8 together are the evidence base for the PRD:157 rationale in `RELEASING.md`: the doc quotes
real output rather than asserting a belief.

### Spec coverage map (`specs/release-distribution/spec.md`, its own scenario order)

S1 publish step + G3 · **S2** `verify` `CFBundleDisplayName` · **S3** T3 · **S4** fail-fast step + T19 ·
S5 `export` version gate · **S6** `verify` `CFBundleVersion` · **S7** M9 · **S8** T17 · S9 `export`
+ `verify` `lipo` + M7 · **S10** `verify` `codesign` flags + no app-sandbox · **S11** T13 · **S12** T18 ·
S13 M8 · S14 `verify` `spctl` + `stapler validate` · **S15** `verify` `Authority` + `TeamIdentifier` ·
S16 M5 · S17 notarize failure path + every `verify` gate · S18 DD-8 + T15 · **S19** T15 · **S20** T15 +
T8 · S21 T1 + T12 · S22 T7 · **S23** `verify` `Contents/` enumeration · S24 T13 · S25 T4 · S26 T5 + T6
+ T16 · **S27** M10 · S28 T10 · **S29** T9 + the pbxproj 0-line binding.

All 29 scenarios carry a named check. Design-owned pins that are **not** spec coverage: T3's
runner/Xcode/`concurrency:` positives, T11, T14, G1, G2.

## Threat Matrix

Applicable — this design adds shell commands, subprocesses, VCS-adjacent automation and an
executable-file classification boundary.

| Boundary | Adversarial case | Applicability | Design response | Planned RED test |
|---|---|---|---|---|
| Documentation-like paths | A `.plist`, `.yml` or `.sh` dropped inside `cellar/` joins the app target and ships **signed inside the bundle**; `release.sh` is an executable outside any source dir | **Applicable** | All release infrastructure lives in `scripts/` and `.github/`, never `cellar/`; `release.sh` is the only executable file added and it is `+x`-checked | T1, T12 |
| Git repository selection | `release.sh` run from an arbitrary `$PWD`, or against another checkout via `git -C` | **Applicable** | The script resolves the repo root from `$(dirname "$0")/..` and contains **no** `git` and **no** `gh` invocation at all — it can neither select a repository nor publish (S20) | T15 (extended: `release.sh` contains no `git ` and no `gh `) |
| Commit state | The pipeline stages or commits generated artifacts | **N/A — asserted, not assumed**: the pipeline writes only to `build/` (gitignored) | No `git add` / `git commit` anywhere | T15 |
| Push state | The workflow pushes a branch or a tag it created | **N/A — asserted**: tags are maintainer-created; the workflow is a consumer of `GITHUB_REF_NAME` | No `git push` / `git tag`; `--verify-tag` makes `gh` refuse a tag that does not already exist | T15 |
| PR commands | `gh` used with composed arguments or an unexpected subcommand | **Applicable** | The only `gh` invocation is `gh release create` with a fixed argument list; `GH_TOKEN` comes from `github.token` under `permissions: contents: write`; no `gh release delete`/`edit` | T15 |
| Secret exposure (project row) | A secret interpolated into a `run:` line, echoed, or captured by `set -x` | **Applicable** | Secrets only as `env:` right-hand sides; no `set -x`; `.p12` and `.p8` deleted in `if: always()` | T5, T6, T13, T16 |

Every applicable row carries into `tasks.md` unchanged, with the RED test written before the file it
guards.

## Documentation Design

### `RELEASING.md` (new, top level — D10: one document, not two)

| § | Content |
|---|---|
| 1 | **How a release happens** — CI is the *only* publishing path (decision 4); `scripts/release.sh` is parity/rehearsal and cannot publish |
| 2 | **Prerequisites** — repository **public** before the first tag (why: anonymous asset download, 10× runner billing); Developer ID Application `.p12` exported *with* its private key; ASC API key `.p8`, Developer role, key id + issuer id; the six repository secrets, named; Actions enabled with `contents: write` |
| 3 | **Tag-and-release runbook** — preflight (green suite, `main` up to date), `git tag -a vX.Y.Z -m … && git push origin vX.Y.Z`, what each workflow stage does, where to watch, and: **a failure publishes nothing**; to retry, delete the *tag* and re-tag — never delete or unflag a published release |
| 4 | **Version policy** — tag is the source of truth; `MARKETING_VERSION = ${tag#v}`, `CURRENT_PROJECT_VERSION = GITHUB_RUN_NUMBER` (monotonic across re-cut tags, which is what a future Sparkle comparison needs); the pbxproj stays `1.0.0 / 1`; **a local Release build reports `1.0.0 (1)` forever** and `AboutView.version` will show exactly that — with the one-line override: `xcodebuild … MARKETING_VERSION=1.2.3 CURRENT_PROJECT_VERSION=42` |
| 5 | **Local rehearsal** — the `scripts/release.sh` env table, `SIGNING_STYLE`, and the phase list |
| 6 | **Entitlements & hardened runtime — discharges PRD:157** — see below |
| 7 | **Contract inherited by `m6-sparkle-updates` and `m6-cask-tap`** — asset URL scheme, artifact name, on-disk bundle `cellar.app`, version stamping, arm64 + macOS 26 floor, and the named extension point in `release.yml` |
| 8 | **Troubleshooting** — notarization rejection (`notarytool log`), keychain import failure, provisioning failure under automatic signing → pointer to the Manual fallback |

**§6 content contract** (the PRD:157 obligation, evidence-based, not asserted):

- What the app is actually signed with — quoted `codesign -dvvv --entitlements :-` output from the
  **notarized** build (`[[U26]]`, M6).
- **There is no `.entitlements` file in the repository and none is added.** The quoted entitlements dict
  is what Xcode synthesises; `allow-jit`, `allow-unsigned-executable-memory` and
  `disable-library-validation` are absent because Cellar `posix_spawn`s `/opt/homebrew/bin/brew` as a
  **separate process** with its own signature and its own address space — that is neither JIT nor
  loading foreign code into Cellar's address space. Evidence: `[[U28]]` (M8), a real mutation completed
  by the notarized, stapled build with no entitlement added.
- **All five names must appear literally** (T18 asserts exactly this): `allow-jit`,
  `allow-unsigned-executable-memory`, `disable-library-validation`, `ENABLE_USER_SELECTED_FILES`,
  `REGISTER_APP_GROUPS`.
- **`ENABLE_USER_SELECTED_FILES = readonly` and `REGISTER_APP_GROUPS = YES` beside
  `ENABLE_APP_SANDBOX = NO`**: sandbox-era settings sitting inert next to a disabled sandbox. They cost
  nothing today. Introducing **any** `.entitlements` file would make them live and re-activate the
  export-write trap recorded in `openspec/changes/archive/2026-08-22-m6-tip-jar/`.
- **The rule going forward:** no entitlement is added without a measured failure that requires it, and
  each addition is visible in the notarization audit trail.

### PRD amendments (rewritten in place with the reason — tip-jar precedent, D8)

| Line | Amendment |
|---|---|
| :9 | Distribution row: direct download is now **delivered by CI** (`.github/workflows/release.yml`); "Sparkle updates" marked as pending `m6-sparkle-updates` |
| :157 | Append: obligation **discharged** — rationale in `RELEASING.md` §6, quoting real `codesign` output; no `.entitlements` file exists |
| :168 | Only if the row's wording implies the feed exists: note that the release **asset URL scheme** now exists and the appcast host decision moves to `m6-sparkle-updates`. No other edit |
| :187 | Rewritten: implemented — `notarytool` + ASC API key, GitHub Actions on `v*` tags, arm64, `Home-Cellar-<version>.zip`; pointer to `RELEASING.md` |
| :212 | M6 line: record the **second** slice landed (CI signing/notarization pipeline), matching how the tip-jar slice annotated it |
| :224 | Risk rewritten: the "set up CI in M1" mitigation was **not** taken; the debt is absorbed here at M6; residual risk is notarization latency, mitigated by `--wait` and fail-before-publish |
| :227 | Record that `ARCHS = arm64` is now **pinned**. U27 measured the Release archive at `ec7b1c5` as **universal (`x86_64 arm64`)** under the implicit `ARCHS_STANDARD`, so the wording is "the arm64-only claim was being contradicted by the build — Cellar was shipping universal by accident until the pin landed", not "a formality" |

### README

- **`## Install`** (new, between `## Requirements` and `## Building`): download the latest
  `Home-Cellar-<version>.zip` from Releases, unzip, drag `cellar.app` to `/Applications`; Apple Silicon
  + macOS 26 only; first launch is a single "Open" because the build is notarized and stapled.
- **`## Releasing`** (new, after `## Building`): three lines — tag-triggered CI, arm64 Developer ID
  notarized zip, pointer to `RELEASING.md`. The runbook is **not** duplicated here.

## File Changes

| File | Action | Description |
|---|---|---|
| `.github/workflows/release.yml` | Create | Tag-triggered pipeline; owns runner, secrets, keychain, cleanup, publication |
| `scripts/release.sh` | Create | `archive export package notarize staple verify all`; executable; no `git`, no `gh`, no `security` |
| `scripts/ExportOptions.plist` | Create | `developer-id` / `automatic` / `Z3S5JK8E38` |
| `cellar.xcodeproj/project.pbxproj` | Modify | **2 lines**: `ARCHS = arm64` in both app-target blocks. Nothing else — `INFOPLIST_KEY_*` included, 0-line diff |
| `cellar/InfoPlist.xcstrings` | Modify | `NSHumanReadableCopyright` value + `state: translated` — the **single** authority for the copyright |
| `cellarTests/ReleasePipelineCompositionTests.swift` | Create | T1–T19, three suites plus a self-contained repo-root helper |
| `RELEASING.md` | Create | Runbook + version policy + PRD:157 rationale + follow-up contract |
| `README.md` | Modify | `## Install`, `## Releasing` |
| `PRD.md` :9, :157, :168, :187, :212, :224, :227 | Modify | Rewritten in place with reasons |
| `openspec/specs/release-distribution/spec.md` | Create (ADDED-only delta) | Owned by `sdd-spec` |
| `Packages/CellarCore/**`, `cellar/**` Swift, `cellar.xcscheme`, `Package.resolved`, `THIRD-PARTY.md`, `cellarTests/SecurityCompositionSupport.swift` | **Untouched — binding** | 0-line diffs |

## Migration / Rollout

No migration, no feature flag, no phased rollout, no in-app behavior change. Rollout is: merge → the
maintainer completes the prerequisites (public flip, secrets) → G3 dry-run prerelease → delete it →
first real `v1.0.0` tag. Nothing in the app changes for an existing user of a locally built copy.

## Size Forecast

| Bucket | Bottom-up lines |
|---|---|
| `project.pbxproj` (**2 lines**, 2 blocks) | 2–4 |
| `.github/workflows/release.yml` | 160–260 |
| `scripts/release.sh` + `ExportOptions.plist` (verify now carries eight gates) | 100–180 |
| `cellarTests/ReleasePipelineCompositionTests.swift` (T1–T19 + helper) | 200–320 |
| Docs (`RELEASING.md`, README, PRD ×7 lines, `InfoPlist.xcstrings`) | 190–290 |
| **Bottom-up subtotal** | **652–1,054** |

House correction **1.9–2.3×** (measured across M5 slices 3–5, recorded at
`openspec/changes/archive/2026-08-22-m6-tip-jar/tasks.md:14`) → **~1,240–2,425 corrected authored
lines**. Plus in-repo SDD artifacts (`proposal.md`, `design.md`, `tasks.md`, the `release-distribution`
delta ≈ 350–550, written once, not multiplied) → **PR total ≈ 1,590–2,975 lines**.

This is above the proposal's 1,200–2,350 estimate: the test bucket grew (T1–T19 with precise structural
assertions rather than three substring checks), the `verify` phase grew to eight gates so that every
`ci-gate` scenario is actually checked by the gate that claims it, and the docs bucket grew
(`RELEASING.md` §6 is evidence-quoting). Stated rather than smoothed.

- Against the 400 default: **High**.
- Against the 5,000 budget: **Low** — ≈2,000 lines of headroom even at the ceiling. `single-pr` holds
  with **no `size:exception`**.

`sdd-tasks` MUST reuse this corrected forecast rather than re-deriving it, and MUST emit the exact guard
lines (`Decision needed before apply: Yes|No`, `Chained PRs recommended: Yes|No`,
`400-line budget risk: Low|Medium|High`).

## Risks

| # | Risk | Mitigation in this design |
|---|---|---|
| R1 | Repo still private at first tag | Fail-fast step on `github.event.repository.private`; prerequisite in `RELEASING.md` §2 |
| R2 | `.p12` / `.p8` leaking into a log or the repo | Secrets only as `env:` values; no `set -x`; `chmod 600` on the `.p8`; `if: always()` deletion of both; T5/T6/T13/T16 |
| R3 | Headless automatic signing fails or mutates ASC provisioning state | `[[U26]]`; DD-5 + the pre-authored Manual fallback above, as a separately approved amendment |
| R4 | A non-numeric `MARKETING_VERSION` from an `rc` tag (`0.0.1-rc.1`) is rejected by `xcodebuild` or notarization | Surfaces in G3, the dry run, before any real release. Fallback: dry-run with `v0.0.1` and let DD-7's hyphen rule govern only genuine prereleases. **Open question below** |
| R5 | Notarization latency or Apple-side rejection | `--wait`; `notarytool log` fetched on failure; the publish step is skipped on failure, so no partial release ever exists |
| R6 | `xcode-select` pin drifts when the runner image drops Xcode 26.6 | The step fails loudly (path missing) rather than silently compiling with another toolchain; the pin is a single line to bump |
| R7 | Scope creep — this is the project's first CI | Release-on-tag only; no lint job, no PR matrix, no coverage upload, no cache. U29's measured baseline (1732 + 141 distinct green, `ReleaseNotesUITests` owned and fixed in PR #21) is **stated**, not gated on: the release workflow runs no test action at all (T3 asserts no `xcodebuild test`) |
| R8 | `ditto`/`stapler` ordering mistake ships an offline-hostile zip | `staple` **deletes** the pre-notarization zip before re-`ditto`, so the published archive can only be post-staple; `verify` then gates the **extracted** copy with networking disabled (M3) |
| R9 | The `©` character round-tripping through pbxproj encoding | Moot by design: the pbxproj never carries the copyright (S29). T9 asserts the catalog JSON, T10 the bundle's `localizedInfoDictionary` |

## Open Questions

- [ ] **R4** — is `MARKETING_VERSION=0.0.1-rc.1` accepted end to end? Settled by G3, the dry run; it does
      not block tasks, and the fallback is one tag name.
- [ ] `[[U26]]` — **blocked on a maintainer prerequisite** (no Developer ID Application certificate on the build Mac; see *Probe results*). Automatic vs Manual signing. Design is correct under D9; the fallback is pre-authored
      above and requires explicit approval before it is applied.
- [x] `[[U27]]` — **resolved, a fix**: the current Release archive is universal (`x86_64 arm64`). See *Probe results* below.
- [ ] `[[U28]]` — the brew-mutation evidence for `RELEASING.md` §6. If it fails, **no entitlement is
      added by default**: the failure is reported and the entitlement question reopened as a decision.
- [x] `[[U29]]` — **resolved, green**: CellarCore 1732/1732, `cellarTests` 141 distinct cases / 0 failures at `ec7b1c5`; `ReleaseNotesUITests` is owned and fixed (PR #21). See *Probe results* below.

---

## Probe results (orchestrator-amended, 2026-08-22, main `ec7b1c5`)

Measured by the orchestrator after this design was written; Engram topic `sdd/m6-release-pipeline/probes`
(obs 7663). Tokens above resolve as follows.

| Probe | Result | Effect on this design |
|---|---|---|
| `[[U26]]` | **Blocked — prerequisite missing.** `security find-identity -v -p codesigning` lists exactly one identity: `Apple Development: Juan Casanueva (A8EB4839B9)`. No **Developer ID Application** certificate exists on the build Mac and no `notarytool` credentials are stored (`notarytool 1.1.2 (41)` is installed). | D9 stands unmeasured. The maintainer must create the Developer ID Application certificate (Xcode → Accounts → Manage Certificates → + → Developer ID Application) and an App Store Connect API key (Developer role) before U26 can run. U26 is a **tasks-phase gate**: the workflow YAML may be authored against D9, but no tag may be pushed and the Manual fallback is not applied until U26 has a measured result. |
| `[[U27]]` | **Universal.** `xcodebuild archive -configuration Release -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO` at `ec7b1c5` → `lipo -archs` = `x86_64 arm64`; bundle 16 MB. Generated Info.plist: `CFBundleShortVersionString 1.0.0`, `CFBundleVersion 1`, `NSHumanReadableCopyright` **absent** (an empty `INFOPLIST_KEY_*` value is dropped, not emitted). xcodebuild also warns *"No App Category is set for target 'cellar'"*. | The `ARCHS = arm64` pin is a **fix, not a formality** — PRD:227 wording: "was shipping universal by accident". M7 and the pre-notarization `lipo` gate are load-bearing. The copyright fix must assert the catalog value and the bundle's `localizedInfoDictionary`, never the pbxproj bytes — and, per S29 and the proposal's one-pbxproj-change binding, the build setting stays at `""` (the measured drop of an empty `INFOPLIST_KEY_*` is precisely why no edit is needed). The `No App Category` archive warning is recorded as a follow-up for `m6-sparkle-updates`, which touches the pbxproj anyway; not in this slice. |
| `[[U28]]` | **Pending** — depends on U26 producing a notarized, stapled build. | Unchanged: no entitlement is added by default; M8 runs as soon as U26 yields an artifact. |
| `[[U29]]` | **Green.** `swift test --package-path Packages/CellarCore` → 1732 tests in 204 suites passed. `xcodebuild test -only-testing:cellarTests` → `** TEST SUCCEEDED **`, **141 distinct** Swift Testing case ids, 0 failures (counted by distinct `Test case '…' passed` ids — the XCTest line reads `Executed 0 tests` for Swift Testing bundles and must not be used). `cellarUITests/ReleaseNotesUITests`: the "unowned/failing" note inherited from the tip-jar exploration is **stale** — fixed in PR #21 (`b2c440f`, 2026-08-07), full suite incl. UI 38/38 green at that commit. UI tests were not re-run for U29. | G4 baseline is stated: 1732 + 141 distinct, no inherited failures. The release workflow runs **no** test action (R7 holds); a PR-test workflow remains a separate change. |

## Re-validation record (orchestrator, 2026-08-22)

Fresh-context validator: round 1 **FAIL** (CRITICAL pbxproj/copyright drift + orchestrator-introduced `LSApplicationCategoryType`); design re-run once with itemised feedback; round 2 **PASS-WITH-WARNINGS**. Post-round-2 orchestrator edits to this file: (A) the S10 sandbox-absence gate rewritten as `! codesign … | grep -q` (a `grep -qv` never fails); (B) M10's pattern set drops the bare `p12` token (would match the echoed `run:` body on every honest run); (F) T17 additionally pins `ENABLE_APP_SANDBOX = NO` / `ENABLE_HARDENED_RUNTIME = YES`. Validator suggestions C (S1 post-publish `curl -fsSI` reachability gate — optional hardening for tasks), D (S14 offline assessment is M3 only; the CI `spctl` runs online) and E (anchor rationale wording) are recorded here for `sdd-tasks` and not otherwise acted on.
