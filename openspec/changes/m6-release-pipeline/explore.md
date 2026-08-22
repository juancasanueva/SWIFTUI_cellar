# Exploration: `m6-ship-pipeline` → sliced as `m6-release-pipeline` (this change) + `m6-sparkle-updates` + `m6-cask-tap` — Developer ID signing, notarization, Sparkle 2, CI release pipeline, self-hosted tap (M6)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled (no reviews started).

Repository evidence read at clean `main` `ec7b1c5`. The exploration executor ran read-only and has no
write tool in this harness, so **this OpenSpec copy was persisted by the orchestrator** — the same
arrangement recorded verbatim in `openspec/changes/archive/2026-08-22-m6-tip-jar/explore.md:1-5`. The
Engram copy lives at topic `sdd/m6-ship-pipeline/explore` (observation 7659).

Orchestrator verification after the phase returned: `gh repo view juancasanueva/SWIFTUI_cellar --json
visibility` → `PRIVATE`; anonymous `api.github.com/repos/juancasanueva/SWIFTUI_cellar` → HTTP 404.
§4.4 / §10.1 / U23 are confirmed, not inferred.

Out of scope for this slice (per the launch brief): menu bar extra, background checks/notifications
(SMAppService), Spanish localization, accessibility pass, landing page. Mac App Store is definitively
off the table (PRD.md:186, U22 spike).

---

## 1. PRD scope, and every line this slice lands on

| PRD line | Text (abridged) | Effect |
|---|---|---|
| 9 | "**Distribution** \| Direct download (Developer ID + notarized, Sparkle updates) **and** Homebrew cask" | this slice *is* that line |
| 124 | "**Settings**: … appearance, **Sparkle update channel**." | surface requirement — see §2.3, §12.4 |
| 157 | "**Sandbox: off.** Hardened runtime on… Entitlements kept minimal; **document why in-repo for notarization sanity**." | an in-repo entitlement/rationale doc is a named PRD obligation, still unmet |
| 168 | "Cellar! update feed \| Sparkle appcast (**static XML on GitHub Pages/Releases**) \| none" | feed host, blocked on §11 U23 |
| 187 | "**Signing**: Developer ID Application cert, hardened runtime, notarization via `notarytool` in CI (GitHub Actions on tags)." | the pipeline shape is already decided by the PRD |
| 188 | "**Sparkle 2**: EdDSA-signed appcast hosted on GitHub Pages; delta updates later. In-app 'Check for updates'." | delta updates explicitly deferred |
| 189 | "**Cask channel**: … self-hosted tap `juan/tap` … mark cask `auto_updates true` so `brew upgrade` skips it by default." | tap — recommend follow-up slice (§8d, §5) |
| 212 | "**M6 — Ship** … Sparkle integration; CI signing/notarization pipeline; self-hosted tap; landing page." | this is M6's second slice (tip jar was the first) |
| 224 | Risk: "Notarization + no-sandbox friction … **Set up CI pipeline in M1, not M6**; test notarized builds early" | **the mitigation was not taken.** There is no CI at all. This slice absorbs that debt in full. |
| 225 | Risk: "Cask notability rejection … Self-hosted tap from day one" | tap is a discoverability hedge, not a 1.0 blocker |
| 227 | "macOS 26+ / **arm64-only** floor … simpler CI" | conflicts with the *measured* build settings — see §2.1 ARCHS |

---

## 2. Current state, measured

### 2.1 Signing, entitlements, Info.plist, versions

All from `cellar.xcodeproj/project.pbxproj` (app target `cellar`, Debug block :416-448, Release
:449-481 — the two blocks are byte-identical for every setting below):

    CODE_SIGN_STYLE = Automatic;            (:421, :454)
    DEVELOPMENT_TEAM = Z3S5JK8E38;          (:424, :457)
    ENABLE_APP_SANDBOX = NO;                (:425, :458)
    ENABLE_HARDENED_RUNTIME = YES;          (:426, :459)
    ENABLE_USER_SELECTED_FILES = readonly;  (:428, :461)
    GENERATE_INFOPLIST_FILE = YES;          (:429, :462)
    INFOPLIST_KEY_CFBundleDisplayName = "Home-Cellar";  (:430, :463)
    INFOPLIST_KEY_NSHumanReadableCopyright = "";        (:431, :464)
    LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");
    MARKETING_VERSION = 1.0.0;              (:436, :469)
    CURRENT_PROJECT_VERSION = 1;            (:423, :456)
    PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.cellar;
    PRODUCT_NAME = "$(TARGET_NAME)";        → the bundle on disk is `cellar.app`
    REGISTER_APP_GROUPS = YES;
    SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;  (:442, :475)
    SWIFT_APPROACHABLE_CONCURRENCY = YES;
    SWIFT_VERSION = 6.0;

Project-level (`:300-415`): `MACOSX_DEPLOYMENT_TARGET = 26.0`, `SDKROOT = macosx`,
`ENABLE_USER_SCRIPT_SANDBOXING = YES`, `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` (Release),
`ONLY_ACTIVE_ARCH = YES` (Debug only), `SWIFT_COMPILATION_MODE = wholemodule` (Release).

Findings that matter for the slice:

1. **There is no `Info.plist` file and no `.entitlements` file anywhere under `cellar/`.** Verified by
   glob: the only plist-family files in the repo are `cellar/InfoPlist.xcstrings`, two
   `xcschememanagement.plist` under `xcuserdata`, and one inside `Packages/CellarCore/.build`. The
   Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`), so `SUFeedURL` and `SUPublicEDKey` must
   arrive either as `INFOPLIST_KEY_SUFeedURL` / `INFOPLIST_KEY_SUPublicEDKey` build settings, or by
   introducing a real `Info.plist`. **Whether the `INFOPLIST_KEY_*` generator accepts non-Apple keys is
   not established here — probe U24.**
2. **`cellar/InfoPlist.xcstrings`** carries `CFBundleDisplayName` = `CFBundleName` = **"Home-Cellar"**
   and an **empty** `NSHumanReadableCopyright` (`extractionState: extracted_with_value`, value `""`).
   `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` + `SWIFT_EMIT_LOC_STRINGS = YES` means the catalog is
   the authority for those three keys, not the build setting. A shipping 1.0 with an empty copyright is
   a real gap (§10.12).
3. **Three names are in play**: bundle file `cellar.app`, display name `Home-Cellar`, PRD's promised
   cask invocation `brew install --cask cellar` (PRD:189). A cask `app` stanza must name the on-disk
   bundle exactly. **Decision required (§12.5).**
4. **`ARCHS` is never set.** `ONLY_ACTIVE_ARCH = YES` exists only in the project-level Debug block, so a
   Release `xcodebuild archive` falls back to `ARCHS_STANDARD` for the macOS 26 SDK, which may include
   `x86_64`. PRD:227 promises arm64-only. `config.yaml` records "arm64". **Measured mismatch, probe U27,
   decision §12.7.**
5. **`ENABLE_USER_SELECTED_FILES = readonly` sits inert beside `ENABLE_APP_SANDBOX = NO`** — the latent
   trap already recorded in `openspec/changes/archive/2026-08-22-m6-tip-jar/explore.md:142-145`.
   `REGISTER_APP_GROUPS = YES` is likewise inert. Neither blocks Developer ID, but PRD:157's "document
   why in-repo" obligation should cover both.
6. **`CODE_SIGN_STYLE = Automatic`** means a CI Developer ID export needs either
   `-allowProvisioningUpdates` plus an App Store Connect API key, or the Release config flipped to
   Manual with an explicit `CODE_SIGN_IDENTITY = "Developer ID Application"`. `config.yaml`
   `rules.proposal` makes a **rollback plan mandatory for anything touching `project.pbxproj`**.
7. **Versions live in the pbxproj, duplicated across Debug and Release**, with no `.xcconfig` anywhere
   in the repo. A tag-driven release can override on the command line
   (`xcodebuild ... MARKETING_VERSION=1.0.1 CURRENT_PROJECT_VERSION=$RUN_NUMBER`) without editing the
   file. Sparkle compares `CFBundleVersion`, which **must strictly increase** — `CURRENT_PROJECT_VERSION = 1`
   today.
8. **No `Embed Frameworks` phase.** The app target's `PBXFrameworksBuildPhase` (`:59-72`) carries only
   the six local CellarCore products (BrewProcess, Catalog, BrewClient, Persistence, DiskUsage,
   ReleaseNotes) via `XCSwiftPackageProductDependency`. `LD_RUNPATH_SEARCH_PATHS` already contains
   `@executable_path/../Frameworks`, which is what an embedded `Sparkle.framework` needs. **Probe U25.**
9. **`ENABLE_USER_SCRIPT_SANDBOXING = YES`** — if this slice adds any run-script build phase (version
   stamping, appcast staging), it will be sandboxed and will fail on unexpected file access. Sparkle
   itself needs no build phase; keep it that way.

### 2.2 How the app is built today

- **Schemes**: exactly two shared — `cellar.xcscheme` and `CellarCore.xcscheme`
  (`cellar.xcodeproj/xcshareddata/xcschemes/`). `cellar.xcscheme` has
  `ArchiveAction buildConfiguration = "Release"` (:113-116), `BuildActionEntry buildForArchiving = "YES"`,
  and a `TestAction` (Debug) that includes **both** `cellarTests` and `cellarUITests`
  (:32-55) with `shouldUseLaunchSchemeArgsEnv = "YES"`. So a plain `xcodebuild test -scheme cellar`
  runs XCUITests; a release workflow must not gate on that (§10.10).
- **Commands** — the five in `openspec/config.yaml` are the whole build surface. There is
  **no `.github/`, no `scripts/`, no `Makefile`, no `Brewfile`, no `.swiftlint.yml`** (verified by
  glob: the only top-level non-directory files are `README.md`, `PRD.md`, `THIRD-PARTY.md`).
- **Quality tooling** is installed-but-unwired per `config.yaml:37-40`: `swiftlint 0.65.0` binary with
  no config file in the repo, `xcbeautify 3.2.1` for log formatting only, no formatter. Per the
  swiftlint skill's decision tree, an Xcode project with SwiftPM would use the `SwiftLintPlugins` build
  tool plugin — but adopting lint in the same slice as the ship pipeline is scope creep; if CI lints at
  all, it should be `brew install swiftlint && swiftlint --strict` in a **separate** workflow, with a
  baseline, and that is its own change.
- **Package graph**: only `XCLocalSwiftPackageReference "Packages/CellarCore"` (`:603-608`). Adding
  Sparkle creates the project's **first remote package dependency**, which means a new
  `cellar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` file plus
  `XCRemoteSwiftPackageReference` + `XCSwiftPackageProductDependency` + `PBXBuildFile` entries in the
  pbxproj.
- **`cellar/` is a `PBXFileSystemSynchronizedRootGroup`** (`:41-57`) — any file dropped inside `cellar/`
  joins the app target automatically. This gives **0-line pbxproj diffs for new `cellar/<Group>/`
  directories**, and it is a trap for non-source artifacts (§10.7).

### 2.3 Settings / About / version seams

- **`cellar/Settings/SettingsView.swift`** — a `ScrollView` of private `group(_:rows:)` cards. Today
  exactly two groups exist ("Homebrew" :28-60, "Interface" :62-73) plus `freeCard` (:160-175). The file's
  own doc comment (:9-15) states the binding rule: *"Only rows with something real behind them are
  rendered… Rows the design sketches for capabilities Cellar does not have… are deliberately absent
  rather than present-but-inert."* An "Updates" group belongs here, with **zero `AppSection` churn**.
  Accessibility identifier `settings-section` (:82) is the XCUITest anchor; new controls need their own
  (house forms: `accent-\(name)`, `sidebar-\(rawValue)`).
- **`cellar/Shell/AboutView.swift`** — `AppIdentity.name` (:10-17) reads `CFBundleDisplayName` then
  `CFBundleName`, and `version` (:142-147) reads `CFBundleShortVersionString` + `CFBundleVersion` and
  renders `"1.0.0 (1)"`. **Those are precisely the two keys Sparkle compares**, so the About window is
  already the honest display of what the updater reasons about. `AboutCommands` (:151-159) replaces
  `CommandGroup(replacing: .appInfo)`.
- **`cellar/cellarApp.swift`** — `body: some Scene` at :422; `.commands { AboutCommands() }` at **:506**;
  a separate `Window("About …", id: "about")` at :508. A "Check for Updates…" menu item is a
  `CommandGroup(after: .appInfo)` added at :506. The file owns every store as `@State`, builds seams in
  `init()`, swaps fakes via `AppTestFixtures`, and runs long-lived loops through `LoopOwner`
  (`loops.start("catalog") { … }`). A Sparkle updater needs **none** of the loop machinery — Sparkle
  owns its own scheduling; the closest precedent is `ReleaseNotesStore`, "a store with no cadence at
  all, whose only caller is a button".
- Settings is **not** a SwiftUI `Settings` scene: `SettingsView` is an `AppSection` rendered inside the
  custom shell. Adding an update row therefore costs no scene work.

### 2.4 Seam and test idioms this slice must copy

Recorded and verified in the m6-tip-jar archive, still current:

- **Protocol-in-CellarCore, conformer-in-app**: `BrewfileDestinationChoosing` / `BrewfileSourceChoosing`
  (`Packages/CellarCore/Sources/BrewClient/BrewfilePublication.swift:15-21`), conformed by `nonisolated
  Sendable` structs in `cellar/Taps/BrewfilePanels.swift` that hop to `@MainActor` internally. `config.yaml`
  `rules.design` makes this binding: *"Define protocol boundaries for every external dependency."*
- **Structural composition tests**: `cellarTests/SecurityCompositionSupport.swift:42-69` reads `cellar/`
  off disk via `#filePath`, strips comments, and asserts what the app target does *not* contain.
  `cellarApp.swift:268-272` records the intent. An `UpdateCompositionTests` asserting `import Sparkle`
  appears in **exactly one** file under `cellar/` is the only honest proof the seam holds.
- **A dependency-free CellarCore target** as a hard build-graph boundary — the `ReleaseNotes` /
  `TipJar` precedent (`Package.swift`, 7 library products with test-enforced edge discipline).

---

## 3. Sparkle 2 — measured facts (versions cited)

- **Latest release: Sparkle `2.9.6`, published 2026-08-17.** Its notes are security-only (symlink
  installer fix, a root-process privilege-escalation fix affecting `sparkle-cli`, rejecting
  package-based installs when signing validation fails). Nothing about Swift 6 or macOS 26.
- **SwiftPM shape** (`Package.swift` at tag 2.9.6): `swift-tools-version 5.3`, `platforms: [.macOS(.v10_13)]`,
  one library product `Sparkle` backed by a **`binaryTarget`** —
  `https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-for-Swift-Package-Manager.zip`,
  checksum `8d5fb41d960b43f4a68aa14126bf62b098544ec8d191cdcc73eb14e63a8e7606`. Because it is a binary
  XCFramework target, Xcode embeds and re-signs it into the app bundle automatically when added as a
  package product dependency — **no manual Embed Frameworks phase**, which is exactly why the SPM route
  is preferred over a vendored XCFramework. (Confirm with U25.)
- **Concurrency**: `SPUUpdater` is annotated `@MainActor` in its Swift interface, and
  `SPUStandardUpdaterController` is the documented convenience wrapper around it. The app target already
  runs `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + `SWIFT_APPROACHABLE_CONCURRENCY = YES` under
  `SWIFT_VERSION = 6.0`, so the updater sits on the actor the app already defaults to. Expected friction
  is limited to `SPUUpdaterDelegate` methods if anything ever reaches them from a nonisolated context —
  the mitigation is a rule, not code: **the updater and its delegate never leave the main actor**, and
  the seam protocol that CellarCore declares is `@MainActor`-agnostic (`func checkForUpdates()`),
  conformed in the app target exactly like `BrewfileSourceChoosing`.
- **Info.plist keys**: required `SUFeedURL` (https), `SUPublicEDKey` (base64 Ed25519 public key), and a
  correctly-formatted, strictly-incrementing `CFBundleVersion`. Optional/relevant: `SUEnableAutomaticChecks`,
  `SUScheduledCheckInterval`, `SUAllowsAutomaticUpdates`, `SURequireSignedFeed`,
  `SUVerifyUpdateBeforeExtraction`.
- **Sandbox**: *"Non-sandboxed apps require no additional steps."* Cellar's `ENABLE_APP_SANDBOX = NO` is
  therefore a **simplification**, not a problem: no `SUEnableInstallerLauncherService` /
  `SUEnableDownloaderService` XPC entitlement dance, and the XPC services may optionally be stripped to
  shrink the bundle. This is the one place where the sandbox-off constraint that killed the MAS pivot
  actively helps.
- **Tooling**: `bin/generate_keys` creates the EdDSA keypair, stores the private key in the login
  Keychain and prints the public key for Info.plist. `bin/generate_appcast` produces the feed,
  signatures and (later) deltas from a folder of archives; `bin/sign_update` signs one archive.
- **CI key handling (the important detail)**: pass the private key on stdin so it never touches disk and
  never triggers a Keychain prompt that would stall a headless runner —
  `echo "$SPARKLE_PRIVATE_KEY" | ./bin/generate_appcast --ed-key-file -`. Writing the key to a file and
  deleting it later is the commonly-published alternative and is strictly worse.
- **Archive format**: both zip and DMG are supported. For zip the docs mandate `ditto` (Finder-equivalent);
  for DMG, APFS with lzfse. The appcast `<enclosure url>` must be a **direct** link to the hosted archive.
- **Deltas**: explicitly deferred by PRD:188. `generate_appcast` produces them automatically once more
  than one archive sits in the folder — which means the CI step must download prior release archives if
  deltas are ever wanted. Not in this slice.

---

## 4. Notarization and CI

### 4.1 Runner — verified

`actions/runner-images` `macos-26-arm64` image `20260728.0273.1`: macOS **26.5.2 (25F84)**, Darwin
25.5.0, **ARM64**, Xcode Command Line Tools 26.6.0. Installed Xcodes: **26.6 (default, 17F113)**, 26.5,
26.4.1, 26.3, 26.2, 26.1.1, 26.0.1. `macos-26` went generally available for GitHub-hosted runners in
Feb 2026 and runs on Apple M4.

That is an exact match for the project's local Xcode 26.6 / macOS 26 / arm64 stack — no toolchain
divergence to manage. Pin it anyway (`sudo xcode-select -s /Applications/Xcode_26.6.app`) so a runner
image bump cannot silently change the compiler.

### 4.2 Two export shapes

| | Shape | Notes |
|---|---|---|
| **A** | `xcodebuild archive -destination 'generic/platform=macOS'` → `xcodebuild -exportArchive -exportOptionsPlist` with `method = developer-id` → `notarytool submit --wait` → `stapler staple` | The documented, conventional path. `-exportArchive` re-signs the whole bundle **inside-out in the right order**, including nested XPC services and `Autoupdate.app` inside `Sparkle.framework` — which is exactly what a hand-rolled `codesign --deep` gets wrong. Apple discourages `--deep`. |
| **B** | `xcodebuild build` → manual `codesign --force --options runtime --timestamp --sign "Developer ID Application: …"` per nested binary → zip → notarytool → stapler | More control, more rope. Every Sparkle helper must be enumerated by hand and re-signed bottom-up. |

**Recommend A.** It is also what PRD:187 implies ("notarization via `notarytool` in CI").

Sequencing gotcha: **staple the `.app`, then re-zip.** `notarytool` accepts a zip, but `stapler` must
attach the ticket to the app bundle; the distributed archive has to be created *after* stapling, or
first-launch is offline-hostile.

### 4.3 Secrets a GitHub Actions runner needs

| Secret | Purpose |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application `.p12`, base64 |
| `P12_PASSWORD` | to import it |
| `KEYCHAIN_PASSWORD` | ephemeral keychain created per run, deleted in an `if: always()` step |
| `APPLE_API_KEY_P8` + `APPLE_API_KEY_ID` + `APPLE_API_ISSUER_ID` | App Store Connect API key for `notarytool --key/--key-id/--issuer` — **recommended** |
| *(alt.)* `APPLE_ID` + `APP_SPECIFIC_PASSWORD` + `TEAM_ID` | `notarytool --apple-id/--password/--team-id` fallback |
| `SPARKLE_PRIVATE_KEY` | EdDSA signing key, piped to `generate_appcast --ed-key-file -` |

`DEVELOPMENT_TEAM = Z3S5JK8E38` is already in the repo and is not a secret.

**Recommend the ASC API key** over Apple ID + app-specific password: it is independently revocable,
never prompts for 2FA, and is the same credential that `-allowProvisioningUpdates` needs if
`CODE_SIGN_STYLE = Automatic` is kept (§2.1.6).

Per the swift-security invariant set: no signing material in `.xcconfig`, `Info.plist`, source, or logs;
never `set -x` around a secret; delete the temporary keychain unconditionally.

### 4.4 Feed host — **the blocking discovery**

`https://api.github.com/repos/juancasanueva/SWIFTUI_cellar` returns **HTTP 404**. `origin` is
`git@github.com:juancasanueva/SWIFTUI_cellar.git` (`.git/config:9`). An anonymous 404 on the REST API
means the repository is **private** (or renamed). Consequences, each independently fatal to this slice
as specified:

1. Release assets on a private repo are **not anonymously downloadable** — Sparkle's `<enclosure url>`
   would 404 for every user.
2. GitHub Pages served from a private repo is a paid-plan feature — `SUFeedURL` on Pages is not
   available for free.
3. A Homebrew cask cannot fetch an authenticated URL, so the tap is impossible too.
4. GitHub-hosted **macOS runner minutes bill at 10×** on private repositories, so even the build is
   materially more expensive.

**The repository's visibility is therefore a gating product decision (U23), not an implementation
detail.** Everything downstream — feed URL, cask URL, workflow cost — depends on it.

Assuming public, three feed options:

| | Host | Verdict |
|---|---|---|
| **a** | `gh-pages` branch / Pages site → `https://juancasanueva.github.io/<repo>/appcast.xml` | **Recommended.** One immutable `SUFeedURL`, regenerable in full by `generate_appcast`, no API rate limit, decoupled from any single release. |
| **b** | `https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml` | Works — `latest/download` is a stable alias — but it couples the feed to whichever release is flagged "latest", and un-flagging or deleting that release breaks every installed copy. |
| **c** | The existing `juancasanueva.vercel.app` site (already linked from `AboutView.swift:82-83`) | Viable, and it is also where PRD:190's landing page will live. Adds a second deploy target to the release job. |

In all three, the `<enclosure url>` points at the **release asset zip**, not at Pages. No
`NSAppTransportSecurity` keys exist in the project and none are needed — all three are https.

### 4.5 Workflow shape (tag-triggered)

`on: push: tags: ['v*']`, `runs-on: macos-26`:

1. `actions/checkout`
2. `sudo xcode-select -s /Applications/Xcode_26.6.app`
3. create temp keychain, import the Developer ID `.p12`, `security set-key-partition-list`
4. `xcodebuild archive -project cellar.xcodeproj -scheme cellar -configuration Release
   -destination 'generic/platform=macOS' -archivePath build/cellar.xcarchive
   MARKETING_VERSION=${GITHUB_REF_NAME#v} CURRENT_PROJECT_VERSION=${GITHUB_RUN_NUMBER}`
5. `xcodebuild -exportArchive -archivePath … -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export`
6. `ditto -c -k --keepParent --sequesterRsrc build/export/cellar.app build/Cellar.zip`
7. `xcrun notarytool submit build/Cellar.zip --key … --key-id … --issuer … --wait`
8. `xcrun stapler staple build/export/cellar.app` → **re-`ditto`** the distributable zip
9. `spctl -a -vvv -t install build/export/cellar.app` as a hard gate (this is also exactly what
   `SecurityKit`'s artifact-integrity code already knows how to read for *other* apps)
10. `generate_appcast` with `--ed-key-file -`
11. `gh release create "$GITHUB_REF_NAME" build/Cellar.zip`, publish `appcast.xml` to the feed host
12. *(follow-up slice)* bump the cask in the tap repo

Cleanup step with `if: always()` deleting the temporary keychain.

---

## 5. Self-hosted tap

- **Repo naming is fixed by Homebrew**: a third-party tap repository must be named `homebrew-<tapname>`.
  `juancasanueva/homebrew-cellar` → `brew tap juancasanueva/cellar` →
  `brew install --cask juancasanueva/cellar/<token>`. Cask files live under `Casks/<first-letter>/<token>.rb`.
- **Token rules**: lowercase, spaces/underscores → hyphens, `+` → `-plus-`, non-alphanumerics stripped,
  runs of hyphens collapsed. `Home-Cellar` → `home-cellar`; PRD:189 promises `cellar`. The `app` stanza
  must name the on-disk bundle exactly — `app "cellar.app"` — independently of the token.
- **Stanzas needed**: `version`, `sha256`, `url` (release asset, `#{version}`-interpolated), `name`,
  `desc` (<80 chars), `homepage`, `app "cellar.app"`, `auto_updates true` (PRD:189 — makes `brew upgrade`
  skip a Sparkle-updated app by default), `depends_on macos: ">= :tahoe"`, `depends_on arch: :arm64`
  (PRD:227), `livecheck` (github-latest strategy), and a `zap trash:` inventory.
  The `zap` list must be assembled from what Cellar actually writes: the `com.juancasanueva.cellar`
  defaults domain, the catalog directory (`AppTestFixtures.catalogDirectory` under Application Support),
  the SwiftData store, and the Keychain items the NVD/GitHub credential stores create.
- **Naming collision risk**: the repo is `SWIFTUI_cellar`, the tap would be `homebrew-cellar`, and
  "Cellar" is also Homebrew's own term for `/opt/homebrew/Cellar`. Worth a deliberate decision, not a
  drift.

**Recommendation: out of this slice.** The tap lives in a *different repository*, produces zero diff
here, cannot be TDD'd, and depends on (a) a public repo, (b) one real notarized release with a stable
URL scheme, and (c) a settled token/display name. Make it `m6-cask-tap`, a follow-up, and have this
slice's docs record the intended stanza set so nothing is re-derived.

---

## 6. Testability under strict TDD

`config.yaml` `testing.strict_tdd: true` and `rules.tasks` "RED before GREEN for every behavioral task".
Most of a ship pipeline is not behavior. Naming the honest split is the point.

**Unit-testable in CellarCore** (a new dependency-free `Updates` target — the `ReleaseNotes` / `TipJar`
build-graph precedent, so "the updater cannot reach brew, the catalog, or SwiftData" is a compile-time
fact):

| Seam | RED test |
|---|---|
| `AppVersion` — parse and order `CFBundleShortVersionString` + `CFBundleVersion` | `1.0.1 > 1.0.0`; `1.0.0 (2) > 1.0.0 (1)`; malformed input is a typed case, not a crash |
| `UpdateChannel` (`stable` / `prerelease`) → feed URL or Sparkle channel name | round-trip through a defaults-backed preference; unknown stored value falls back to `stable` |
| `UpdateCheckOutcome` enum (`upToDate` / `available(version)` / `failed(reason)` / `unavailable(reason)`) | every arm reachable from a fake `UpdateChecking` |
| `AppcastDocument` — a **validator**, not a client | parse the `appcast.xml` fixture the CI script emits and assert `sparkle:edSignature`, `sparkle:version`, `sparkle:shortVersionString`, `enclosure url` scheme == https, and `sparkle:minimumSystemVersion == "26.0"` are all present. This is a genuine failing-first test with **no Sparkle dependency**, and it is what catches a broken release script before users see it. |

**Testable in `cellarTests` (app target)**:

- `UpdateCompositionTests` — the `SecurityCompositionSupport` idiom: `import Sparkle` appears in exactly
  one file under `cellar/`; no view file references `SPUUpdater` / `SPUStandardUpdaterController`.
- **An Info.plist assertion test** — read `Bundle.main.infoDictionary` and assert `SUFeedURL` is an https
  URL and `SUPublicEDKey` decodes to 32 bytes of base64. This is the RED test that pins the pbxproj
  build-setting change, and it is the only automated proof that U24 stayed true.
- A settings-structure test in the existing house style for the new "Updates" group.

**CI-only** (no unit test possible): the workflow YAML itself. Best available checks are `actionlint`
and one dry-run tag on a throwaway prerelease. Treat as verification evidence, not as a spec scenario.

**Manual-only, must be declared as such in design**: the notarization verdict, `spctl -a -vvv -t install`
on the produced bundle, Gatekeeper first-launch of the downloaded (quarantined) zip, and an actual
end-to-end Sparkle upgrade from build N-1 to N with the app in `/Applications`.

**Not testable at all**: `SPUStandardUpdaterController` behavior. Sparkle offers no test harness
equivalent to `SKTestSession`. This is the same honesty the tip-jar slice had to state about its
StoreKit conformer, and it is the reason the seam protocol must live in CellarCore.

**Spec capabilities**: `openspec/specs/` currently holds **20** capabilities. This slice adds one —
`app-updates` (ADDED-only, no destructive delta) covering the user-observable behavior: version display,
check-for-updates command, the Settings group, and the "no update surface lies about state" rules. The
CI pipeline itself has **no runtime observable behavior** and should live in `design.md` + `tasks.md`,
not in a spec capability.

---

## 7. Affected areas

- **New** `Packages/CellarCore/Sources/Updates/` — `AppVersion.swift`, `UpdateChannel.swift`,
  `UpdateCheckOutcome.swift`, `UpdateSeams.swift`, `AppcastDocument.swift`. **No dependencies.**
- **New** `Packages/CellarCore/Tests/UpdatesTests/` — fake-driven coverage plus the appcast fixture.
- `Packages/CellarCore/Package.swift` — one `.library` + `.target` + `.testTarget`. **Rollback plan required.**
- **New** `cellar/Updates/` — `SparkleUpdateChecker.swift` (the only app file importing Sparkle) and
  `UpdatesSettingsGroup.swift`. Free pbxproj diff (synchronized root group).
- `cellar/Settings/SettingsView.swift` — an "Updates" `group`.
- `cellar/Shell/AboutView.swift` — "Check for Updates…" via `CommandGroup(after: .appInfo)`.
- `cellar/cellarApp.swift` — `@State` updater seam, construction in `init()`, fixture swap at `:506` commands.
- `cellar/AppTestFixtures.swift` — a no-network fake checker.
- `cellar/InfoPlist.xcstrings` — `NSHumanReadableCopyright`.
- **New** `cellarTests/UpdateCompositionTests.swift`, `cellarTests/BundleUpdateKeysTests.swift`.
- `cellar.xcodeproj/project.pbxproj` — Sparkle package reference + product dependency + build file,
  `INFOPLIST_KEY_SUFeedURL`, `INFOPLIST_KEY_SUPublicEDKey`, possibly `ARCHS`, possibly signing style.
  **Rollback plan mandatory** (`config.yaml` `rules.proposal`).
- **New (generated)** `cellar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- **New** `.github/workflows/release.yml`.
- **New** `scripts/ExportOptions.plist` — **must live outside `cellar/`** (§10.7).
- **New** `RELEASING.md` (or a README section) + PRD §6/§4.3 amendments + `THIRD-PARTY.md` Sparkle MIT entry.
- **New** `openspec/specs/app-updates/spec.md` via an ADDED-only delta.
- **Not touched** (a binding): `cellar/Shell/AppSection.swift`, `cellar/ContentView.swift`,
  `cellarTests/AppSectionPlacementTests.swift`, `cellar.xcodeproj/xcshareddata/xcschemes/*` — no new
  section, no scheme edit. (The tip-jar slice held the same binding and verified it at 0 lines.)

---

## 8. Approaches

### 8a. Sparkle integration

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **A** | **SPM remote dependency on the app target**, `sparkle-project/Sparkle` from `2.9.6` | Xcode auto-embeds and re-signs the XCFramework; version pinned in `Package.resolved`; upgrades are one bump | First remote dependency in the project; new resolved file; pbxproj churn | Low |
| B | Vendored `Sparkle.xcframework` checked into the repo | No network at build time | ~10 MB binary in git; manual Embed-and-Sign phase; manual upgrades | Medium |
| C | No Sparkle — rely on the Homebrew cask for updates | Zero new dependency | Abandons PRD:188 and every direct-download user; a GUI app with no in-app update path in 2026 is a defect | Low |

**Recommend A.**

### 8b. Signing and export in CI

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| **A** | `archive` + `-exportArchive -exportOptionsPlist (developer-id)` + `notarytool --wait` + `stapler` | Correct inside-out re-signing of Sparkle's nested helpers; the documented path; matches PRD:187 | An `ExportOptions.plist` to maintain; automatic signing needs `-allowProvisioningUpdates` + ASC key | Medium |
| B | Manual `codesign` per binary + zip + notarize | Full control | Must enumerate Sparkle's XPC services and `Autoupdate.app` by hand; `--deep` is discouraged and gets order wrong | High |
| C | fastlane (`gym` + `notarize`) | Batteries included | A whole Ruby toolchain and a `Gemfile` for one workflow; another version surface | Medium |
| D | DMG via `create-dmg`, notarize the DMG | Nicer first-run experience; PRD-compatible | Sparkle prefers zip for updates; would need **both** artifacts | Medium |

**Recommend A**, zip for the Sparkle enclosure. A DMG is a good 1.0 follow-up for the landing page.

### 8c. Feed host

See §4.4 — **recommend (a) Pages/`gh-pages`**, conditional on U23 resolving the repo to public.
Fallback (c) `juancasanueva.vercel.app`, which the landing page will need anyway.

### 8d. Slice boundary — **the decision that governs everything else**

| # | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| A | Everything in one change: signing + notarization + CI + Sparkle + tap | One PR, one story | ~3,500–5,500 lines after the house multiplier; the tap lives in another repo and cannot be verified here | High |
| **B** | **Split: `m6-release-pipeline` (signing/notarize/CI/zip/docs) → then `m6-sparkle-updates` (dependency, keys, model, surfaces, appcast step) → then `m6-cask-tap` (follow-up, other repo)** | Correct dependency order — Sparkle cannot be *verified* until a notarized release exists at a real URL, and `SUFeedURL` cannot be written until §4.4 is settled. Each slice independently deliverable and each fits the 5,000 budget with headroom. | Two SDD cycles instead of one | Medium ×2 |
| C | CI signing/notarization only; Sparkle deferred to a later milestone | Smallest | Leaves PRD:188 and Settings:124 open; ships a 1.0 with no update path | Low |
| D | Sparkle only, no CI (manual local releases) | Fast first release | The exact debt PRD:224 warned about, deepened; secrets on a laptop; unrepeatable | Low |

**Recommend B.** It is also the only option that keeps `delivery_strategy: single-pr` honest without a
`size:exception` (§9).

---

## 9. Size forecast

Bottom-up authored-line estimate (additions + deletions):

| Bucket | Lines |
|---|---|
| `project.pbxproj` (package ref, product dep, build file, 2×`INFOPLIST_KEY_SU*`, possibly `ARCHS`, possibly signing style) | 25–45 |
| `Package.resolved` (new, generated but in-diff) | 10–20 |
| `Packages/CellarCore/Package.swift` | 10–15 |
| CellarCore `Updates` sources | 250–350 |
| CellarCore `UpdatesTests` (+ appcast fixture) | 300–450 |
| App target (`SparkleUpdateChecker`, `UpdatesSettingsGroup`, `SettingsView`, `AboutView`/commands, `cellarApp`, `AppTestFixtures`) | 250–350 |
| `cellarTests` (composition sweep, bundle-keys, settings structure) | 150–250 |
| `.github/workflows/release.yml` | 160–260 |
| `scripts/` (`ExportOptions.plist`, helper shell) | 60–140 |
| Docs (`RELEASING.md`, README section, PRD §6/§4.3, `THIRD-PARTY.md`) | 120–200 |
| **Bottom-up total** | **1,335–2,080** |

The house correction recorded in `openspec/changes/archive/2026-08-22-m6-tip-jar/tasks.md:14` is
**1.9–2.3×** (measured across M5 slices 3–5). Applied:

**Forecast: 2,540–4,780 authored lines against the 5,000 budget.**

- Against the 400 default: **High**.
- Against the 5,000 session/config budget: **Medium at the low end, High at the top** — the upper bound
  leaves only ~220 lines of headroom, which is not a margin.

Under 8d-B the split becomes roughly `m6-release-pipeline` ≈ 900–1,700 and `m6-sparkle-updates`
≈ 1,650–3,100 — both comfortably inside 5,000 with real headroom, and neither needs a `size:exception`
against the `single-pr` strategy. **This is the strongest argument for 8d-B.**

---

## 10. Risks

1. **The repository is private** (`api.github.com/repos/juancasanueva/SWIFTUI_cellar` → 404). Blocks
   anonymous release-asset download, free Pages hosting, and the cask; and bills macOS runner minutes at
   10×. **Gating decision, not an implementation detail.**
2. **Losing the EdDSA private key permanently severs the update channel** for every installed copy — no
   recovery except telling users to re-download by hand. It must be backed up **outside** the login
   Keychain (offline / password manager) *before* the first release, and stored as a GH secret. Rotating
   it later means shipping a build with the new `SUPublicEDKey` through a non-Sparkle channel first.
3. **Developer ID `.p12` handling on CI**: ephemeral keychain, unconditional deletion, no `set -x`, no
   secret echo. swift-security invariant: never in `.xcconfig`, `Info.plist`, source, or logs.
4. **`CODE_SIGN_STYLE = Automatic` on a headless runner** needs `-allowProvisioningUpdates` + an ASC API
   key, or the Release config must be flipped to Manual. Either way `project.pbxproj` changes and
   `config.yaml` `rules.proposal` demands a rollback plan.
5. **Hardened runtime entitlements**: the currently-installed dev-signed Release build already execs
   `/opt/homebrew/bin/brew` under `ENABLE_HARDENED_RUNTIME = YES`, so `allow-unsigned-executable-memory`,
   `allow-jit`, and `disable-library-validation` are almost certainly **not** needed and must **not** be
   added speculatively — each one weakens the runtime and is visible to the notarization audit trail.
   Must be *measured* (U28), not assumed. Note the asymmetry: if a `.entitlements` file is ever
   introduced, `ENABLE_USER_SELECTED_FILES = readonly` and `REGISTER_APP_GROUPS = YES` become live and
   the export-write trap recorded in the tip-jar archive activates.
6. **`INFOPLIST_KEY_*` may not carry non-Apple keys.** If U24 fails, the slice must introduce a real
   `Info.plist` — a larger pbxproj change that also changes how `InfoPlist.xcstrings` applies to
   `CFBundleDisplayName`/`CFBundleName`. Budget and rollback plan must allow for it.
7. **`cellar/` is a `PBXFileSystemSynchronizedRootGroup`** — `ExportOptions.plist`, the appcast fixture,
   and any release artifact dropped inside `cellar/` would silently join the app target and ship inside
   the bundle. Same trap the tip-jar slice recorded for `Cellar.storekit`. Keep them in `scripts/` and
   `Packages/CellarCore/Tests/`.
8. **Sparkle + Homebrew cask coexistence.** A cask-installed app is user-owned and Sparkle can replace it
   without an admin prompt — but then the on-disk version diverges from what `brew` recorded, and
   `brew upgrade` will report a mismatch. PRD:189's `auto_updates true` is the correct mitigation and
   must be in the cask from day one. An app in `/Applications` installed by drag-and-drop may prompt for
   admin authorization on first update. A downloaded zip carries `com.apple.quarantine`; a **stapled**
   ticket turns first launch into a single "Open" instead of a hard refusal.
9. **arm64 vs universal.** `ARCHS` is unset, so a Release archive may build `x86_64` too, contradicting
   PRD:227 and doubling both the zip size and the CellarCore compile time on every release. Measure (U27),
   then pin.
10. **The shared scheme's `TestAction` includes `cellarUITests`.** A release workflow must not run the
    full `-scheme cellar` test action; and the tip-jar exploration recorded `ReleaseNotesUITests` as
    failing and unowned at `7d48779`. Re-baseline at `ec7b1c5` (U29) before any CI gate is written.
11. **This slice is also the project's first CI.** Scope creep is the obvious failure mode: a lint job, a
    PR test matrix, coverage upload, and a caching strategy all *look* like they belong. They do not.
    Release-on-tag only; a PR-test workflow is its own change.
12. **`NSHumanReadableCopyright` is empty** in both the build setting (`:431`, `:464`) and the string
    catalog. A 1.0 that ships without a copyright line is a small but visible omission.
13. **Version source of truth.** Overriding `MARKETING_VERSION` from the git tag keeps the repo clean but
    makes a local Release build report `1.0.0` forever, which will confuse manual testing. The
    alternative — bumping the pbxproj in two blocks per release — is a recurring merge hazard. Decide
    explicitly.
14. **`THIRD-PARTY.md` must gain Sparkle's MIT entry** (house precedent: the CaskHub attribution).
15. **PRD drift**: §6 and §4.3 must be amended in the same PR that settles the feed host and the tap
    name, or the repo ships a contradiction — exactly the failure the tip-jar slice had to fix.

---

## 11. Probes required before design (U-gates)

- **U23 — is the repository public, and will it be made public for 1.0?** *The gate.* Determines the
  feed host, the cask URL, and the CI bill. Nothing downstream can be specified until this is answered.
- **U24 — does `INFOPLIST_KEY_SUFeedURL` reach the generated Info.plist?** Throwaway build, then
  `plutil -p "$BUILT_PRODUCTS_DIR/cellar.app/Contents/Info.plist"`. Decides build-setting vs real
  `Info.plist` (risk 6).
- **U25 — Sparkle 2.9.6 via SPM into this app target**: does Xcode auto-embed and re-sign
  `Sparkle.framework` with **no** Embed Frameworks phase, and does `SPUStandardUpdaterController`
  compile clean under `SWIFT_VERSION = 6.0` + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` with zero
  concurrency warnings?
- **U26 — does a Developer ID export + notarize round-trip succeed *locally*?** Proves the cert and ASC
  key actually exist and work before a line of YAML is written. Cheapest possible de-risking.
- **U27 — what does `xcodebuild archive` currently produce?** `lipo -archs` on the exported binary.
- **U28 — does a hardened-runtime, notarized, stapled build still exec `/opt/homebrew/bin/brew` and
  complete a real mutation?** Expected yes (the installed dev-signed build already does), must be
  measured before any entitlement is even considered.
- **U29 — baseline suite state at `ec7b1c5`**, including `ReleaseNotesUITests` ownership.

U23 and U26 gate the proposal. U24, U25, U27, U28 can run during design. U29 should run before tasks.

---

## 12. Product decisions required before proposal

1. **Repository visibility** — public for 1.0? (§10.1, U23). *Everything depends on this.*
2. **Slice boundary** — 8d-B recommended: `m6-release-pipeline` → `m6-sparkle-updates` → `m6-cask-tap`.
   This is what keeps `single-pr` honest without a `size:exception`.
3. **Feed host and the literal `SUFeedURL` string** — 8c-a (Pages) recommended, 8c-c (vercel) fallback.
4. **Does 1.0 need an update *channel* picker at all?** PRD:124 names one. Sparkle 2 supports channels
   natively and adding one later is cheap. Recommend: one stable feed plus an "automatically check for
   updates" toggle in the new Settings group; hold the channel picker until there is a prerelease channel
   to point it at. Otherwise `SettingsView`'s own no-inert-rows rule is violated on day one.
5. **Naming** — `cellar.app` / display name `Home-Cellar` / promised cask token `cellar`. Recommend
   settling on **one** user-facing name for 1.0 and making the cask token match it.
6. **Zip or DMG** for the download (zip is required for the Sparkle enclosure either way).
7. **arm64-only or universal** (§10.9).
8. **ASC API key or Apple ID + app-specific password** for `notarytool` — API key recommended.
9. **Does this change amend `PRD.md` (§6, §4.3) and `README.md`?** Recommend yes, same PR,
   rewritten-in-place, matching the tip-jar precedent.

---

## 13. Ready for Proposal

**Yes, after U23 (repository visibility) and decision §12.2 (slice boundary).** U26 should run before
any workflow YAML is authored. U24/U25/U27/U28 can run during design.

Architecture is largely settled by existing convention: the CellarCore-protocol / app-conformer seam,
the dependency-free target, and the structural composition sweep are all house idioms with working
precedents. The genuinely open questions are distribution ones — where the feed lives, what the app is
called, and whether the repository users would download from is public.

Sizing: **2,540–4,780** as one change (Medium-to-High against 5,000); **~900–1,700 + ~1,650–3,100** if
split per 8d-B, which is the recommendation.
