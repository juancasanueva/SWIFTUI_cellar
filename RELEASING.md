# Releasing Cellar

How a version of Cellar becomes something a stranger can download, and what is
true of that build by construction rather than by hope.

## 1. How a release happens

A pushed `v*` tag is the **only** thing that publishes. There is no manual step
between the push and the published asset, and no other trigger on the workflow:
it holds a Developer ID certificate and an App Store Connect key, so any trigger
a contributor could reach would hand both to whoever reached it.

Two files, split by ownership rather than by convenience:

| File | Owns |
|---|---|
| `.github/workflows/release.yml` | The runner, the secrets, the ephemeral keychain, cleanup, and publication — everything that only exists on CI |
| `scripts/release.sh` | The build sequence: archive → export → package → notarize → staple → verify |

`scripts/release.sh` is a **rehearsal path, not a publishing path**. It contains
no version-control and no release-management invocation of any kind, so it can
neither select a repository nor publish, tag, or retract anything, whatever
directory it is run from. Running it locally produces the same artifact and
publishes nothing — that is what makes the rehearsal a rehearsal rather than an
approximation of one.

The workflow invokes the script **one phase per named step**, so a job log has
one step per stage and a failure names the stage that failed.

## 2. Prerequisites

None of these block merging the pipeline. All of them block the first release.

1. **The repository must be public before the first tag.** Release assets are
   only anonymously downloadable from a public repository, and macOS runner
   minutes are billed at 10× on a private one. The workflow refuses to run on a
   private repository — it fails with an explicit message before any signing or
   notarization work, so it never produces an asset nobody can download.
2. **A Developer ID Application certificate**, exported as a `.p12` **with its
   private key**. Xcode → Settings → Accounts → Manage Certificates → **+** →
   Developer ID Application, then export from Keychain Access.
3. **An App Store Connect API key** (`.p8`), **Developer** role. Note its key id
   and issuer id. One credential serves both `notarytool` and `xcodebuild`'s
   `-authenticationKey*` flags, it is independently revocable, and it never
   prompts for two-factor confirmation — so automatic signing adds no new
   credential surface.
4. **Seven repository secrets**, named exactly:

   | Secret | Value |
   |---|---|
   | `BUILD_CERTIFICATE_BASE64` | `base64 -i DeveloperID.p12` |
   | `P12_PASSWORD` | The password used when exporting the certificate |
   | `KEYCHAIN_PASSWORD` | Any strong string; it protects the run's throwaway keychain |
   | `APPLE_API_KEY_P8` | The full contents of the App Store Connect `.p8` file |
   | `APPLE_API_KEY_ID` | The key id |
   | `APPLE_API_ISSUER_ID` | The issuer id |
   | `SPARKLE_PRIVATE_KEY` | The EdDSA private key printed by `generate_keys -x` (see 7) |

5. **Actions enabled**, with permission to write releases. The workflow declares
   `contents: write` and uses the run's own `GITHUB_TOKEN`; no personal token is
   involved.
6. **GitHub Pages enabled, with source = GitHub Actions.** Settings → Pages →
   Build and deployment → Source: **GitHub Actions**. This is what serves
   `https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml`, the feed every
   installed copy reads.

   The `github-pages` deployment environment must also allow the refs the
   release job runs on. It is created with a **branch** policy, and this job
   runs on **tag** refs (`v*`), so a deployment from a tag is rejected until a
   tag rule is added: Settings → Environments → `github-pages` → Deployment
   branches and tags → add a **tag** rule matching `v*`. Without it the four
   publication steps run and the deploy step fails at the end of an otherwise
   successful release.
7. **A Sparkle EdDSA key pair, generated once and backed up before anything
   else.** From the Sparkle 2.9.6 distribution:

   ```
   curl -fsSLO https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-2.9.6.tar.xz
   shasum -a 256 Sparkle-2.9.6.tar.xz    # 52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
   tar -xJf Sparkle-2.9.6.tar.xz
   ./bin/generate_keys                   # writes the private key to the login Keychain, prints the public key
   ./bin/generate_keys -x sparkle-private.key
   # move sparkle-private.key to offline storage or a password manager, then:
   rm -P sparkle-private.key
   ```

   **This is a one-way door.** Losing the private key permanently severs the
   update channel for every copy already installed: rotation requires shipping a
   new `SUPublicEDKey` through some channel that is not Sparkle. The public key
   is *not* a secret — it is compiled into every copy, in
   `Resources/Cellar-Info.plist` — and must never be handled as one.
8. **The exported private key stored as `SPARKLE_PRIVATE_KEY`.** Verify it once
   with `./bin/sign_update` against any zip before deleting the local copy.

The team identifier `Z3S5JK8E38` lives in the repository and is not a secret.

## 3. Tag-and-release runbook

**Preflight.** `main` up to date, the suite green, and the version you are about
to tag is the version you mean.

```sh
git tag -a v1.0.0 -m "Cellar 1.0.0"
git push origin v1.0.0
```

Then watch the run under the repository's Actions tab. The stages, in order:

| Stage | What it does | What stops the run |
|---|---|---|
| Private-repository gate | Refuses to publish an unreachable asset | The repository is not public |
| Distinct-commit gate | Asks the Pages deployments API whether this commit has already deployed the feed | This commit has deployed before (stable tags only) |
| Archive | Release archive stamped with the tag and the run number | Any build failure |
| Export | Developer ID export, then gates version and architecture | `CFBundleShortVersionString` ≠ the tag, or any slice other than `arm64` |
| Package | `ditto` into `Home-Cellar-<version>.zip` | — |
| Notarize | `notarytool submit --wait` | Apple rejects it; the diagnostic log is printed |
| Staple | Staples the ticket and repackages | Stapling fails |
| Verify | Eight gates against the copy extracted from the zip (the `spctl` assessment runs online here; the offline assessment is manual evidence M3 in §6) | Any gate |
| Publish | `gh release create --verify-tag --generate-notes` | — |
| Build the appcast | Signs the zip and writes the whole feed to a directory outside the checkout | Signing or emission fails (stable tags only) |
| Configure Pages / Upload | Uploads that directory as the `github-pages` artifact | — |
| Deploy to Pages | `actions/deploy-pages`, which deploys the artifact under this commit as its build version | The deployment reports a failure state, or its 10 minutes elapse |
| Cleanup | Deletes the keychain and the API key, always | — |

**Every stable release must be cut from its own commit.** GitHub Pages keys a
deployment by its *build version*, and the deployments API accepts only a build
version that is a commit in this repository — a `<commit>-<run number>` string
is rejected with a 404, and so is any invented SHA. The commit is therefore not
a default that could be improved on; it is the only value the API takes, and it
is exactly what `actions/deploy-pages` sends.

That leaves one hazard, and it is silent. Asking Pages to deploy a commit it has
already deployed does not fail: the request is accepted, the deployment reports
`succeed`, and the previously published site keeps being served. Two stable tags
can point at one commit — `v0.0.2` and `v0.0.3` both did — and on that path the
second tag publishes a release, uploads a correct feed, goes green, and leaves
every installed copy reading the older one.

The distinct-commit gate is what makes that impossible. It reads
`GET /repos/<owner>/<repo>/pages/deployments/<commit>` before anything is signed
or notarized. The endpoint answers `200` for any SHA, so the `status` in the
body is the discriminator: an empty string means the commit has never deployed
and the release may proceed; `succeed` means it has, and the run stops there —
before Apple is asked for a round trip and before a release exists on the tag.

**A failure publishes nothing.** Every gate runs before the publish step, so a
failed run leaves no release, no asset, and no draft. To retry, delete the
**tag** and tag again — on the same commit, which is fine here precisely because
the run never reached the deploy: no deployment exists for that commit yet, so
the distinct-commit gate still lets it through. Once a run *has* deployed the
feed, that commit is spent; the next version needs a new commit.

```sh
git push --delete origin v1.0.0
git tag -d v1.0.0
```

**Never delete or unflag a published release.** A future Sparkle appcast will
point at published assets, and unflagging one strands every installed copy that
trusted it. A bad release is withdrawn by cutting a new patch tag, and the
automation is structurally incapable of doing anything else: the only
release-management command in the workflow is `gh release create`.

A tag containing a hyphen (`v0.0.1-rc.1`) publishes as a **prerelease**, which
is how the pipeline is rehearsed against the real repository.

## 4. Version policy

**The tag is the source of truth.** The workflow supplies both values at build
time:

- `MARKETING_VERSION` ← the tag with its leading `v` removed
- `CURRENT_PROJECT_VERSION` ← `GITHUB_RUN_NUMBER`, which only increases — so
  `CFBundleVersion` is strictly greater on every later release, including a
  re-cut tag for the same marketing version. That monotonicity is what a future
  Sparkle comparison needs.

**The project file is never bumped per release.** `MARKETING_VERSION` stays
`1.0.0` and `CURRENT_PROJECT_VERSION` stays `1` in `project.pbxproj`, so a
release changes no tracked file and leaves no commit behind.

The cost, recorded rather than left as a trap: **a local Release build reports
`1.0.0 (1)` forever**, and the About window shows exactly that regardless of the
current tag. To produce a correctly stamped local build, override both on the
command line:

```sh
xcodebuild archive -project cellar.xcodeproj -scheme cellar -configuration Release -archivePath build/cellar.xcarchive MARKETING_VERSION=1.2.3 CURRENT_PROJECT_VERSION=42
```

## 5. Local rehearsal

```sh
# `all` includes `notarize`, so the App Store Connect key is required even for a rehearsal.
VERSION=1.0.0 BUILD_NUMBER=1 \
ASC_KEY_PATH=~/.private_keys/AuthKey_XXXXXXXXXX.p8 ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=<issuer-uuid> \
scripts/release.sh all

# Without the key, rehearse the phases that need none:
VERSION=1.0.0 BUILD_NUMBER=1 SIGNING_STYLE=manual scripts/release.sh archive
```

| Variable | Required for | Meaning |
|---|---|---|
| `VERSION` | all phases | Marketing version, e.g. `1.0.0` |
| `BUILD_NUMBER` | `archive`, `export`, `verify` | `CURRENT_PROJECT_VERSION` |
| `ASC_KEY_PATH` | `notarize`; also `archive`/`export` under automatic signing | Path to the App Store Connect `.p8` |
| `ASC_KEY_ID` | as above | App Store Connect key id |
| `ASC_ISSUER_ID` | as above | App Store Connect issuer id |
| `SIGNING_STYLE` | optional, default `automatic` | `automatic` adds `-allowProvisioningUpdates` and the three `-authenticationKey*` flags; `manual` omits them |
| `RELEASE_BUILD_DIR` | optional, default `build` | Output root; excluded from version control |

Phases: `archive`, `export`, `package`, `notarize`, `staple`, `verify`, and
`all`. Each can be run on its own, which is how a failing stage is reproduced
without repeating the ones before it.

## 6. Entitlements and hardened runtime

This section discharges the standing obligation recorded at `PRD.md:157`
("Entitlements kept minimal; document why in-repo for notarization sanity").

**The posture.** Hardened runtime **on**, app sandbox **off**. The sandbox denies
`file-read-data` on `/opt/homebrew` before `brew` can execute, and Cellar's
entire purpose is to drive `brew`. Both are pinned in the project file and
asserted by `cellarTests`, and the delivered bundle is re-checked at release
time: the run fails, publishing nothing, if the hardened-runtime flag is missing
or an app-sandbox entitlement is present.

**There is no `.entitlements` file in this repository, and none is added.** The
entitlements dictionary the delivered build carries is the one Xcode synthesises.
Three hardened-runtime exceptions that a Homebrew GUI might be assumed to need
are **deliberately absent**:

- `allow-jit`
- `allow-unsigned-executable-memory`
- `disable-library-validation`

None is required, because Cellar `posix_spawn`s `/opt/homebrew/bin/brew` as a
**separate process**, with its own signature and its own address space. That is
neither just-in-time compilation nor foreign code loaded into Cellar's address
space, so no hardened-runtime exception applies to it.

**`ENABLE_USER_SELECTED_FILES` and `REGISTER_APP_GROUPS`.** Both are set in the
project file (`readonly` and `YES`), and both are sandbox-era settings sitting
inert beside a disabled sandbox. The first one **does** emit an entitlement —
`com.apple.security.files.user-selected.read-only` is the single key the
notarized build carries (measured below) — but with `ENABLE_APP_SANDBOX = NO`
it grants nothing and costs nothing, because that entitlement is only
meaningful inside a sandbox. They matter only as a tripwire. Introducing **any**
`.entitlements` file would make them live and re-activate the export-write trap
recorded in `openspec/changes/archive/2026-08-22-m6-tip-jar/`, which is why the
absence of such a file is asserted by a test rather than left to discipline.

**The rule going forward.** No entitlement is added without a measured failure
that requires it, and every addition is visible in the notarization audit trail.

**Measured evidence — first notarized build, 2026-08-23.**

Rehearsed with `scripts/release.sh all` (§5) under automatic signing; no manual
fallback was needed. Notarization submission
`ee153168-e28f-495b-8d8e-4b70be89843e` returned `Accepted`, the ticket stapled,
and the Gatekeeper assessment of the bundle extracted from the zip was:

```
cellar.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Juan Casanueva (Z3S5JK8E38)
```

`codesign -dvv` on the same bundle: `Format=app bundle with Mach-O thin (arm64)`,
`flags=0x10000(runtime)`, `TeamIdentifier=Z3S5JK8E38`,
`Notarization Ticket=stapled`. Its complete entitlements dictionary, from
`codesign -d --entitlements - --xml`:

```xml
<dict>
  <key>com.apple.security.files.user-selected.read-only</key>
  <true/>
</dict>
```

No `com.apple.security.app-sandbox`, and none of the three hardened-runtime
exceptions named above.

**Homebrew mutation from that build.** The stapled bundle was copied to
`/Applications` and launched. From it, `sl` (not previously installed) was
installed and then uninstalled through Cellar's own mutation flow. Evidence:
Homebrew's download cache holds the `sl-5.02` bottle manifest fetched at
07:39 that day, one minute after launch, and `brew list --formula` no longer
lists `sl` afterwards. `brew` ran to completion as a child of the
hardened-runtime process with the entitlements above and nothing else — the
design's reasoning holds as measured.

## 7. The contract the follow-up slices inherit

`m6-sparkle-updates` and `m6-cask-tap` bind against these, and none of them may
change without a coordinated change there:

| Property | Value |
|---|---|
| Asset URL | `https://github.com/<owner>/<repo>/releases/download/v<version>/Home-Cellar-<version>.zip` |
| Asset name | `Home-Cellar-<version>.zip`, exactly one per release |
| Bundle inside it | `cellar.app`, display name `Home-Cellar` |
| Version stamping | `CFBundleShortVersionString` = tag minus `v`; `CFBundleVersion` = run number, strictly increasing |
| Signature | Developer ID Application, team `Z3S5JK8E38`, hardened runtime, notarized and stapled |
| Floor | Apple Silicon (`arm64` only) for the app executable; the embedded `Sparkle.framework` is universal, which does not change the floor |
| Update feed | `https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml`, republished by the same job on every **stable** tag; a prerelease publishes a release and no feed entry |

`release.yml` carries a named extension point immediately after the publish
step: appcast publication now occupies it, and the cask bump inserts after it
without restructuring the job.

**Risk 3 — a Pages deploy is a full-site replacement.** A Pages deployment
serves whatever the uploaded artifact contains and nothing else, so the release job is
the *only* thing that may deploy to Pages. If a landing page is ever wanted, it
must be built by this same job into the same artifact directory; a second
workflow deploying a site would silently overwrite `appcast.xml` and every
installed copy would stop finding updates.

## 8. Troubleshooting

**Notarization rejected.** The run prints `notarytool log` output for the failed
submission before it exits. The usual causes are an unsigned nested binary, a
missing hardened-runtime flag, or a signature made with the wrong identity.
Nothing was published; fix, delete the tag, tag again.

**Keychain import failed.** Either `BUILD_CERTIFICATE_BASE64` is not the base64
of a `.p12` exported **with its private key**, or `P12_PASSWORD` does not match
it. Re-export from Keychain Access and re-encode.

**Provisioning failed under automatic signing.** The pre-authored fallback is
manual signing: set `signingStyle` to `manual` in `scripts/ExportOptions.plist`,
add `SIGNING_STYLE: manual` to the workflow's build steps, and switch the
Release configuration to `CODE_SIGN_STYLE = Manual` with
`CODE_SIGN_IDENTITY = "Developer ID Application"`. That flip is a decision, not
an implementation detail: it breaks the Debug/Release parity that `cellarTests`
asserts, so the assertion must be **explicitly relaxed** — with the reason
recorded in the test — rather than deleted.

**The run stopped at the distinct-commit gate.** This commit has already
deployed the update feed, and Pages will not deploy it twice. Nothing is wrong
with the tag: put the new version on a new commit and tag that. There is no flag
to force the deployment, because forcing it is the failure — Pages would accept
the request, report `succeed`, and keep serving the old feed.

**The run is green but the feed still advertises the previous version.** The
gate makes the stale-feed case unreachable for a stable tag, so the remaining
explanation is the CDN: the deployment succeeded and the edge has not yet
purged. Compare `last-modified` on the feed URL before assuming otherwise. If
the feed really is stale, check that the run was a stable tag at all — a
hyphenated tag skips every publication step, the deploy included, by design.

**`spctl` accepts locally but a downloader sees a refusal.** The published
archive must be the post-staple one. `scripts/release.sh staple` deletes the
pre-notarization zip before repackaging precisely because `ditto` into an
existing archive path adds to it rather than replacing it.
