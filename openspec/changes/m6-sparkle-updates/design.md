# Design: Sparkle 2 In-App Updates (`m6-sparkle-updates`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m6-sparkle-updates/` + Engram canonical project
`swiftui_cellar`), `delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`.
RDD disabled clone-local — no review started.

Inputs, in binding order: `proposal.md` (Engram obs **7682**, ACCEPTED — D1–D7 and the **literal
pbxproj change list** are binding), decisions obs **7681** (Q1–Q4 accepted as assumed), `explore.md`
including the **U24 addendum**, and the house precedent
`openspec/changes/archive/2026-08-23-m6-release-pipeline/design.md`.

`next_recommended: sdd-tasks`

> **Size note.** This document exceeds the 800-word default design budget by explicit launch-brief
> instruction. Density is preserved by tables; nothing is padded.

> **Probe status — read this before anything else.** This design was first written without a shell
> tool. An orchestrator-owned build worker has since **measured `[[U25]]`, `[[U31]]` and `[[U32]]`**;
> the *Probe addendum* at the end of this file is **authoritative** and the body has been reconciled
> to it. Summary: U25(a) Sparkle auto-embeds with **zero** `PBXCopyFilesBuildPhase` — **no Embed
> Frameworks phase**; U25(b) **zero** Sparkle warnings under Swift 6 + MainActor default; U25(c)
> `Package.resolved` lands at the workspace path and is not gitignored; U31 every Sparkle binary is
> `x86_64 arm64` (D2's allowance is exercised, not theoretical); U32 the stowaway sweep is **empty**,
> so the third `release-distribution` edit **does not fire**. `sign_update --ed-key-file -` reads
> stdin, confirmed from its help text. **Still open:** `[[U30]]` (apply-owned) and `[[U33]]`
> (maintainer prerequisite), plus the action major versions. No probe outcome is invented anywhere.

> **Gate warning carried forward.** The `m6-release-pipeline` design gate failed round 1 on a
> pbxproj key introduced beyond the proposal's list (that design's *Re-validation record*, :568).
> Every pbxproj line below maps 1:1 to one of the proposal's seven items. One structurally required
> edit is **outside** that list; it is raised as **Deviation D-1** and is **not authorized by this
> design**.

---

## Technical Approach

Three layers, separated by what can be tested and by what may import what.

1. **`Packages/CellarCore/Sources/Updates`** — a new **dependency-free** target and library
   (7 → 8 products). It owns the four types the proposal names and nothing else. Declaring no
   dependencies makes "the updater cannot reach brew, the catalog, SwiftData or the network" a fact
   of the build graph, exactly as `ReleaseNotes` does with `Catalog` alone
   (`Packages/CellarCore/Package.swift:109-119`). Everything here is `swift test`-covered.
2. **`cellar/Updates/`** — `SparkleUpdateChecker.swift` is the **only** file in the repository that
   says `import Sparkle`; two view files and one persistence value type sit beside it. `cellar/` is a
   `PBXFileSystemSynchronizedRootGroup` (`project.pbxproj:41-46`), so new files there cost **0
   pbxproj lines**.
3. **Publication** — `scripts/appcast.sh` owns the feed sequence and runs identically by hand;
   `.github/workflows/release.yml` owns the credential, the Pages permissions and the deploy, at the
   named extension point (`:118-119`). No `git`, no second `gh`.

The build-time facts (`SUFeedURL`, `SUPublicEDKey`) reach the bundle through the U24-selected shape:
a two-key partial plist at `Resources/Cellar-Info.plist` merged by `INFOPLIST_FILE` while
`GENERATE_INFOPLIST_FILE` stays `YES`. `LSApplicationCategoryType` goes in as an ordinary
`INFOPLIST_KEY_*`, because U24 measured that the generator honours known keys only.

---

## Architecture Decisions

| # | Decision | Rejected alternative | Rationale |
|---|---|---|---|
| DD-1 | New **dependency-free** `Updates` target + `.library` in CellarCore holding `AppVersion`, `AppcastDocument`, `UpdateCheckPresentation`, `AppUpdating` | Put the types in the app target; or fold them into an existing linked target such as `BrewProcess` | `openspec/config.yaml:49` — all logic in CellarCore. Zero dependencies is the same compile-time guarantee `ReleaseNotes` buys (`Package.swift:92-113`); folding into `BrewProcess` would give the updater an edge to subprocess execution and give `BrewProcess` an edge to update types, for the sole benefit of saving three pbxproj lines (see **D-1**) |
| DD-2 | `AppUpdating` is `@MainActor public protocol AppUpdating: AnyObject, Observable` | A `nonisolated` protocol; or a generic view constrained to `AppUpdating & Observable` | The app target compiles under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`:443`, `:477`) and `SPUUpdater` is main-actor by construction, so a `nonisolated` requirement could not be satisfied by a `@MainActor` conformer. Refining `Observable` lets views read `any AppUpdating` and still re-render: Observation registers at the **accessor**, so tracking survives the existential. A generic view cannot work here because DI picks the concrete type at runtime (real vs. UI-test fake) and `.commands { }` needs one static type |
| DD-3 | Two-way controls build their `Binding` by hand (`Binding(get:set:)`) rather than `@Bindable` | `@Bindable var updater` | `@Bindable` requires a concrete `@Observable` type; DD-2 deliberately keeps the existential. One explicit four-line binding is cheaper than re-introducing a generic view |
| DD-4 | Cellar's own `UserDefaults` key `updates.automaticChecksEnabled` (missing ⇒ **false**) is the authority; the app writes `SPUUpdater.automaticallyChecksForUpdates` from it at startup | Let Sparkle's own `SUEnableAutomaticChecks` default govern | Unset, Sparkle **prompts the user on second launch** with a system alert (`explore.md:324-328`). D1 is default-off and an update check is network egress, which Cellar gates behind explicit consent everywhere else (`SecurityConsentPreference.swift:10-20`, `cellarApp.swift:463-465`). Owning the value also removes any need for a boolean `INFOPLIST_KEY_*`, which U24 showed would not land anyway |
| DD-5 | The persisted flag lives in `cellar/Updates/AutomaticUpdateChecks.swift`, a small value type over an injected `UserDefaults`, keyed `updates.automaticChecksEnabled` | An `@AppStorage` in the Settings view; a fifth public CellarCore protocol | Mirrors `SecurityConsentPreference.swift:27-53` (injected `UserDefaults`, missing key reads as *not granted*, no default that reads as consent), which is what makes it testable from `cellarTests` against a scratch suite. `@AppStorage` in a view cannot be read at startup by the DI wiring. A fifth public protocol would exceed the API surface the proposal fixed |
| DD-6 | `SparkleUpdateChecker` bridges `SPUUpdater.canCheckForUpdates` with `NSKeyValueObservation` + `MainActor.assumeIsolated` | `Task { @MainActor in … }` in the KVO handler; polling | Sparkle mutates `canCheckForUpdates` on the main thread, so the assumption is documented and true; a `Task` hop would make the menu item briefly enabled during a check. Per `swift-concurrency` rule 5 the invariant is written into the file, and the whole type is `@MainActor` so nothing else can observe the gap |
| DD-7 | `CheckForUpdatesCommands` uses `CommandGroup(after: .appInfo)` and coexists with `AboutCommands`' `CommandGroup(replacing: .appInfo)` | Add the item inside `AboutCommands`; add a button to `AboutView` | `replacing:` substitutes the *content* of the `.appInfo` group; `after:` inserts a **new** group positioned behind it. They compose, which is exactly the arrangement Sparkle's own SwiftUI sample uses. Keeping them separate keeps the About window's ownership intact and keeps the update command revertible on its own |
| DD-8 | `AppcastDocument` is a **validator over XML text**, not a client and not a builder | Generate the appcast XML from CellarCore and have the script call it; use Sparkle's `generate_appcast` | The CI step cannot link CellarCore, and `generate_appcast`'s single `--download-url-prefix` cannot express Cellar's per-tag asset URLs (`explore.md:240-244`). A validator is the only shape that puts the XML's contract under `swift test` while the emitter stays a shell heredoc |
| DD-9 | Feed history is preserved by `curl`-fetching the live feed and merging **one** `<item>`; the first run with no feed degrades to a single-item document | Regenerate the whole feed each release; latest-only forever | D3. Merging keeps per-version release notes for users who skip versions; a first-run 404 is a designed state, not an error |
| DD-10 | The Sparkle CLI comes from the pinned `Sparkle-2.9.6.tar.xz` release asset, verified by a **sha256 literal in the script**, not from the resolved SPM artifact path | `.../SourcePackages/artifacts/sparkle/Sparkle/bin/` | That DerivedData path is not a contract and changes between Xcode versions. A pinned tarball plus a checked digest is the same discipline the binaryTarget itself uses |
| DD-11 | `SPARKLE_PRIVATE_KEY` is the **seventh** repository secret, bound only as `NAME: ${{ secrets.NAME }}` and piped on **stdin**; it is never written to a file, never traced, never echoed | `--ed-key-file <path>` with a temp file, as the ASC `.p8` does | **Confirmed by measurement** (addendum): `sign_update --ed-key-file -` reads the key from standard input — *"'-' can be used to echo the EdDSA key from a 'secret' environment variable to the standard input stream"* — and the older `-s <private-key>` argument form is deprecated. Unlike `notarytool` there is no API forcing a file, so the `swift-security` invariant is satisfied **by construction rather than by cleanup**, and no `$RUNNER_TEMP` fallback exists or is needed |
| DD-12 | The PEM-less credential-sweep extension is **dropped**, and replaced by a **narrower** guard: the repository contains **exactly one** 44-character base64 Ed25519-shaped literal, and it is the `SUPublicEDKey` value in `Resources/Cellar-Info.plist` | Extend `repositoryCarriesNoCredentialMaterial` with a base64 pattern | A raw Ed25519 **private** key is 44 base64 characters with no header — byte-shape-identical to the **public** key this change commits on purpose. Any pattern broad enough to catch one catches the other, and a filename allow-list is a guard that passes because it was told to. The exact-count form is false-positive-free *and* strictly stronger: a second key appearing anywhere fails it. The proposal explicitly permitted dropping the broad sweep "with the gap recorded" — the residual gap is a private key committed in a format that is not 44-char base64 |
| DD-13 | The appcast job runs **inline at the extension point** (`release.yml:118-119`) with job-level `permissions` and `environment: github-pages` | A second `appcast:` job with `needs: release` that re-`curl`s the published asset | The proposal binds the extension point. The second job is otherwise attractive (release job untouched, no environment override) and is recorded here as the pre-costed fallback if the `github-pages` environment turns out to carry protection rules incompatible with the release job |
| DD-14 | The `AppcastDocument` fixtures are **hand-authored** in `Tests/UpdatesTests/Fixtures/`, and a separate `cellarTests` structural test pins `scripts/appcast.sh` to the element and attribute names the validator requires | Generate the fixture by running `appcast.sh` inside a test | Running the script from a test needs `sign_update`, a private key and network egress inside `swift test` — three things this project forbids. The textual bridge is honest about being textual: it proves the emitter and the validator agree on **names**, not on bytes. That limitation is stated rather than smoothed |
| **DD-15** | **Two decisions that the spec classes as unit-core move into `Sources/Updates` as pure functions, leaving only the call site in the app:** `AutomaticUpdateChecksPolicy.apply(preference:to: any AppUpdating)` (what to write to the updater at launch) and `UpdateCommandEnablement.isEnabled(canCheckForUpdates:)` (whether the menu item is live) | **(rejected)** Leave both in `cellarApp.init` and `CheckForUpdatesCommands` and downgrade the two scenarios to structural-only coverage — i.e. accept a **spec-class deviation** where a requirement the spec calls unit-testable is in fact only greppable | The spec classes these scenarios as unit-core, and a scenario whose only evidence is a source sweep is a scenario nobody can actually fail on purpose. Both are *decisions* (a `Bool` in, a `Bool` out) with no framework in them, so nothing forces them into the app target; `openspec/config.yaml:49` already says logic belongs in CellarCore. Splitting decision from effect makes each testable against `FakeAppUpdater` (T7b, T7c) while the app keeps exactly one line each — DI wiring and a view modifier, which is what the app target is allowed to hold. The rejected alternative was considered and refused because it would leave the spec claiming coverage the tests do not provide |

---

## Data Flow

    ── build time ──────────────────────────────────────────────────────────────
    Resources/Cellar-Info.plist ──INFOPLIST_FILE──┐
    INFOPLIST_KEY_LSApplicationCategoryType ──────┼─► generated Info.plist
    GENERATE_INFOPLIST_FILE = YES ────────────────┘     SUFeedURL, SUPublicEDKey,
                                                        LSApplicationCategoryType

    ── runtime ─────────────────────────────────────────────────────────────────
    UserDefaults[updates.automaticChecksEnabled]  (missing ⇒ false, DD-4/DD-5)
              │ read once at launch
              ▼
    cellarApp.init ─► SparkleUpdateChecker(automaticChecks:)   ── the ONLY import Sparkle
              │            │
              │            ├─ SPUStandardUpdaterController(startingUpdater: true, …)
              │            ├─ updater.automaticallyChecksForUpdates ← persisted flag
              │            └─ KVO canCheckForUpdates ─MainActor.assumeIsolated─► @Observable
              │
              ├─ .environment(updater as any AppUpdating)
              │        └─► UpdatesSettingsGroup   (toggle + UpdateCheckPresentation label)
              └─ .commands { AboutCommands(); CheckForUpdatesCommands(updater:) }
                                                   └─► updater.checkForUpdates()
                                                        └─ Sparkle's own UI owns the rest

    ── publication (tag vX.Y.Z) ────────────────────────────────────────────────
    gh release create  ──(published asset)──┐
                                            ▼
    scripts/appcast.sh   fetch ─ curl https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml
                                   │ 404 ⇒ empty channel (first run, DD-9)
                         tool  ─ curl Sparkle-2.9.6.tar.xz ─► shasum -a 256 -c ─► tar -xJf
                         sign  ─ printf '%s' "$SPARKLE_PRIVATE_KEY" | bin/sign_update --ed-key-file -
                         merge ─ new <item> prepended; every prior item preserved, order kept
                         emit  ─ "$RUNNER_TEMP/site/appcast.xml"
                                            │
    configure-pages ─► upload-pages-artifact ─► deploy-pages ─► Pages serves the feed
    (all four steps skipped when GITHUB_REF_NAME contains '-', D4)

---

## CellarCore `Updates` — files and API surface

`Packages/CellarCore/Package.swift`: `+1 .library(name: "Updates", targets: ["Updates"])`,
`+1 .target(name: "Updates", swiftSettings: [.swiftLanguageMode(.v6)])` with **no `dependencies:`
key at all** (its absence is the guarantee, and the doc comment says so), `+1 .testTarget` with
`resources: [.copy("Fixtures")]` following `ReleaseNotesTests` (`Package.swift:114-119`).

| File | Type | Surface |
|---|---|---|
| `Sources/Updates/AppVersion.swift` | `public struct AppVersion: Sendable, Hashable, Comparable` | `init?(shortVersionString:buildNumber:)`, `init(parsing:) throws`, `major/minor/patch: Int`, `prerelease: Prerelease?`, `buildNumber: Int?`. `Prerelease: Sendable, Comparable` (identifier + ordinal). Ordering: version triple, then **prerelease < release** (`0.0.1-rc.1 < 0.0.1`), then build number. Malformed input throws `AppVersionParseFailure` — a typed case, never a crash, never a silent `0.0.0` |
| `Sources/Updates/AppcastDocument.swift` | `public struct AppcastDocument: Sendable` + `public enum AppcastValidationFailure: Error, Sendable, Hashable` | `static func validate(_ xml: String) throws -> AppcastDocument`; `items: [Item]` in document order. `Item` carries `version`, `shortVersionString`, `enclosureURL`, `edSignature`, `length: Int`, `minimumSystemVersion`. Failures are enumerated, not stringly: `.missingChannel`, `.missingSignature(item:)`, `.nonNumericLength(item:)`, `.insecureEnclosure(item:)`, `.unexpectedHost(item:expected:)`, `.wrongMinimumSystemVersion(item:found:)`, `.hyphenatedVersion(item:)`, `.itemsOutOfOrder`. Parsed with `XMLParser` (Foundation) — **no** Sparkle, **no** third-party XML |
| `Sources/Updates/UpdateCheckPresentation.swift` | `public struct UpdateCheckPresentation: Sendable, Hashable` | `init(lastCheck: Date?, now: Date)` → `label: String`: `"Never checked"` when `nil`, otherwise `"Last checked …"` from a `RelativeDateTimeFormatter`. Deterministic because `now` is injected |
| `Sources/Updates/AppUpdating.swift` | `@MainActor public protocol AppUpdating: AnyObject, Observable` | `var canCheckForUpdates: Bool { get }`, `var automaticallyChecksForUpdates: Bool { get set }`, `var lastUpdateCheckDate: Date? { get }`, `func checkForUpdates()` |
| `Sources/Updates/UpdatePolicy.swift` | `@MainActor public enum AutomaticUpdateChecksPolicy` + `public enum UpdateCommandEnablement` | **DD-15.** `AutomaticUpdateChecksPolicy.apply(preference: Bool, to updater: any AppUpdating)` — the *decision* of what to write at launch, one write, no side effect beyond the seam. `UpdateCommandEnablement.isEnabled(canCheckForUpdates: Bool) -> Bool` — `nonisolated`, pure. Both exist so the two spec-class-unit scenarios have real unit tests (T7b, T7c) instead of a source sweep |

**Concurrency posture.** CellarCore uses SwiftPM's `nonisolated` default (`config.yaml:15`), so
`AppVersion`, `AppcastDocument` and `UpdateCheckPresentation` are `nonisolated`, `Sendable` value
types with no shared state — nothing crosses an isolation domain, so nothing needs `@unchecked` or
`@preconcurrency`. `AppUpdating` is the single `@MainActor` declaration, for the reason in DD-2. The
`Updates` target adds **no** `nonisolated(unsafe)`, no `@unchecked Sendable`, no `Task.detached`.
No `#available` branches (`config.yaml:52`).

**Coverage plan (`swift test --package-path Packages/CellarCore`).** `AppVersion`: ordering table
(parameterized), prerelease-below-release, build-number tiebreak, each malformed shape → its typed
case. `AppcastDocument`: one valid fixture plus one fixture per failure case, and a two-item fixture
asserting descending order is preserved and that validation of a merged document does not drop the
older item. `UpdateCheckPresentation`: `nil` and three offsets. `AppUpdating`: driven by
`FakeAppUpdater` (an `@Observable` conformer **in `Tests/UpdatesTests`**, never shipped).

---

## App side — `cellar/Updates/` (0 pbxproj lines)

| File | Contents |
|---|---|
| `SparkleUpdateChecker.swift` | `@MainActor @Observable final class SparkleUpdateChecker: AppUpdating`. **The only `import Sparkle` in the repository.** Holds `SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)`, then calls `AutomaticUpdateChecksPolicy.apply(preference:to:)` (DD-15) and **only then** `controller.startUpdater()` — that order is what makes Sparkle's second-launch prompt unreachable (T22), and it is why the controller does not start itself; mirrors `canCheckForUpdates` and `lastUpdateCheckDate` through two `NSKeyValueObservation`s under DD-6; `checkForUpdates()` forwards to `controller.updater.checkForUpdates()`. Writing `automaticallyChecksForUpdates` writes **both** Sparkle's property and Cellar's key, in that order, so a crash between them leaves Cellar's authority as the survivor |
| `AutomaticUpdateChecks.swift` | `struct AutomaticUpdateChecks` over an injected `UserDefaults`; `static let key = "updates.automaticChecksEnabled"`; `var isEnabled: Bool { get nonmutating set }`; a missing key reads `false` (DD-4/DD-5) |
| `UpdatesSettingsGroup.swift` | The `"Updates"` card, rendered by `SettingsView` after `"Interface"` (`SettingsView.swift:62-73`) using the same private `group(_:rows:)`/`row(label:sub:accessory:)` shapes. Row 1: `Toggle` bound by DD-3, `label: "Check for updates automatically"`, `sub:` naming the egress plainly, `accessibilityIdentifier("updates-automatic-toggle")`. Row 2 (separator above): the `UpdateCheckPresentation` label, `accessibilityIdentifier("updates-last-checked")`. No inert rows — `SettingsView.swift:9-15` is binding |
| `CheckForUpdatesCommands.swift` | `struct CheckForUpdatesCommands: Commands` with `CommandGroup(after: .appInfo) { Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!UpdateCommandEnablement.isEnabled(canCheckForUpdates: updater.canCheckForUpdates)) }`, over `let updater: any AppUpdating`. The enablement **rule** lives in `Updates` (DD-15); this file only applies it |

**Wiring** (`cellar/cellarApp.swift`). In `init`, after the release-notes block (`:313-344`) and
following the same fixture idiom: build `AutomaticUpdateChecks` over `.standard`, or over
`UserDefaults(suiteName: "cellar-ui-updates-\(UUID().uuidString)")` under the UI-test launch; then
`_updater = State(initialValue: AppTestFixtures.isUpdatesEnabled ? AppTestUpdater() :
SparkleUpdateChecker(automaticChecks:))`, typed `any AppUpdating`. In `body`, add
`.environment(\.appUpdater, updater)` beside the existing `.environment(...)` calls (`:456-465`), and
change `:506` to `.commands { AboutCommands(); CheckForUpdatesCommands(updater: updater) }`.

**UI-test fixture.** `AppTestFixtures.swift` gains `isUpdatesEnabled` for
`--ui-testing-m6-updates` (added to the `isEnabled` disjunction at `:20-29`) and
`AppTestUpdater`, an `@Observable` in-memory `AppUpdating`. **No UI-test launch may construct
`SparkleUpdateChecker`**, so a UI test can never start an updater, never reach the feed, and never
open a Sparkle window. This is the same reason `AppTestReleaseNotesProtocol` exists.

---

## Build configuration

### The seven pbxproj items — 1:1 against the proposal's binding list

Both app-target blocks are `BCDBE99F301E2D420013A38D /* Debug */` (`:416-449`) and
`BCDBE9A0301E2D420013A38D /* Release */` (`:450-483`). They are byte-identical modulo `name`
(`ReleasePipelineCompositionTests.swift:213-229`), so **every build setting costs two lines**.

| # | Proposal item | Exact edit | Placement |
|---|---|---|---|
| 1 | `XCRemoteSwiftPackageReference` | New section after `XCLocalSwiftPackageReference` (`:610`): `sparkle-project/Sparkle`, `requirement = { kind = exactVersion; version = 2.9.6; }` | ~7 lines |
| 2 | `packageReferences` entry | `+1` line inside `:219-221`, after the `XCLocalSwiftPackageReference` entry | 1 line |
| 3 | `XCSwiftPackageProductDependency` | `+1` entry in `:612-637` with `productName = Sparkle;` and a `package` back-reference to item 1 | ~5 lines |
| 4 | `PBXBuildFile` | `+1` line in `:9-16`: `… /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = … /* Sparkle */; };` | 1 line |
| 5 | `PBXFrameworksBuildPhase` entry | `+1` line in the app target's phase `:63-70`, after `ReleaseNotes in Frameworks` | 1 line |
| 6 | `INFOPLIST_KEY_LSApplicationCategoryType` | `INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.developer-tools";` in **both** blocks, alphabetically between `INFOPLIST_KEY_CFBundleDisplayName` (`:431`/`:465`) and `INFOPLIST_KEY_NSHumanReadableCopyright` | 2 lines |
| 7 | `INFOPLIST_FILE` | `INFOPLIST_FILE = Resources/Cellar-Info.plist;` in **both** blocks, alphabetically between `GENERATE_INFOPLIST_FILE` (`:430`/`:464`) and `INFOPLIST_KEY_CFBundleDisplayName` | 2 lines |

**Total = 22 lines, measured** (addendum): 18 for the Sparkle dependency alone (1 `PBXBuildFile`,
1 frameworks entry, 1 `packageReferences` entry, **11** for the new `XCRemoteSwiftPackageReference`
section — the project had none, so its header and footer are new too — and 5 for the product
dependency), plus 2 + 2 for items 6 and 7. **≈28 lines if D-1 is approved.**
`GENERATE_INFOPLIST_FILE` stays `YES` — U24 Build 2 measured the merge, and 26
keys including the catalog-sourced `CFBundleDisplayName`/`CFBundleName`/`NSHumanReadableCopyright`
arrangement both copyright tests bind to. `INFOPLIST_FILE` is a **path setting**: it needs no
`PBXFileReference` and no build-phase membership, which is why item 7 is two lines and not five.
Nothing else in `project.pbxproj` moves. `ARCHS`, `CODE_SIGN_STYLE`, `ENABLE_APP_SANDBOX`,
`ENABLE_HARDENED_RUNTIME`, `LD_RUNPATH_SEARCH_PATHS`, `MARKETING_VERSION`,
`CURRENT_PROJECT_VERSION`, `SWIFT_*`: **0-line diffs — binding.**

### 🔴 Deviation D-1 — the `Updates` product linkage is NOT in the proposal's list

The proposal's Scope IN mandates a **new CellarCore product** (7 → 8), but its literal pbxproj list
contains no entry for linking it. That linkage is structurally required and mechanically entailed:
`SecurityKit` is importable today without an explicit entry only because `Persistence` depends on it
(`Package.swift:127-131`) and `Persistence` **is** linked; `Updates` is dependency-free by design
(DD-1), so nothing pulls it in transitively.

| Missing item | Cost |
|---|---|
| `PBXBuildFile` `Updates in Frameworks` | 1 line |
| `PBXFrameworksBuildPhase` entry | 1 line |
| `XCSwiftPackageProductDependency` `productName = Updates;` | ~4 lines |

**This design does not authorize those six lines.** They are reported for an explicit decision
before apply, with the alternatives pre-costed:

- **(a) Approve D-1** — add the three entries (≈6 lines). Preserves DD-1's zero-dependency guarantee.
  Recommended.
- **(b) Give an already-linked target a dependency on `Updates`** — 0 pbxproj lines, but it inverts
  the graph (`Persistence`, the outermost node, would gain an outward edge, and SwiftData code would
  see the updater). Rejected on architecture grounds.
- **(c) Fold the four types into `BrewProcess`** — 0 pbxproj lines; destroys the compile-time
  isolation that is DD-1's entire justification. Rejected.

### `Resources/Cellar-Info.plist` — exact contents

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>SUFeedURL</key>
	<string>https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string><!-- 44-char base64, generated by the maintainer DURING apply (obs 7681 Q1) --></string>
</dict>
</plist>
```

Two keys, nothing else — every other key stays owned by the generator or by
`cellar/InfoPlist.xcstrings`. D6 binds the path: not under `cellar/` (the synchronized root group
would ship it and fail `appSourcesCarryNoReleaseInfrastructure`, `:409-417`), not under `scripts/`
(which means "never ships"), not the repository root.

### Workflow job header — in scope, and **not** a pbxproj matter (W9)

Recorded here so it is never mistaken for an eighth pbxproj item or discovered at apply. The
`release` job in `.github/workflows/release.yml` gains exactly two things:

| Addition | Exact value | Why |
|---|---|---|
| A **job-level** `permissions:` block | `contents: write`, `pages: write`, `id-token: write` | `pages: write` and `id-token: write` are what `deploy-pages` needs. A job-level block **replaces** the workflow-level one rather than extending it, so `contents: write` **must be restated** or `gh release create` silently loses its token. The workflow-level `permissions: contents: write` (`release.yml:13-14`) stays as it is, for any future job |
| `environment: github-pages` | on the `release` job | GitHub requires Pages deployments to target the `github-pages` environment; `actions/deploy-pages@v4` creates the deployment against it. Assumed required, settled by `[[U33]]`; if it turns out not to be, the job header shrinks by one line. If the environment carries a protection rule that excludes tag refs, DD-13's second-job fallback applies |

Both are workflow additions inside the change's declared scope. Neither touches
`cellar.xcodeproj/project.pbxproj`, and neither affects the seven bound items or D-1.

### `Package.resolved` — location and commitment

`cellar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (the workspace path an
`.xcodeproj` uses; there is no `.xcworkspace` bundle in this repo). **It is committed.** Cellar's
first remote dependency is a **binary** artifact fetched at resolve time; the resolved file pins the
Sparkle tag's revision so CI, the maintainer's Mac and any future contributor resolve the same bytes
rather than whatever `exactVersion 2.9.6` happens to point at. Not committing it would make the
release pipeline's inputs unpinned in the one place it matters most. **Measured** (addendum, U25c):
the file is created at exactly that path, 387 bytes, `version: 3`, pinning `sparkle` @ 2.9.6 at
revision `ac2def28…`; the directory exists and the path is **not** covered by `.gitignore`, so no
`.gitignore` edit is needed.

---

## Publication — `scripts/appcast.sh` and `release.yml`

`scripts/appcast.sh` is a new executable outside `cellar/`, `set -euo pipefail`, **never `set -x`**,
containing **no `git` and no `gh`** so it cannot publish, tag or select a repository. Environment
contract: `VERSION`, `GITHUB_REF_NAME`, `ASSET_URL`, `ZIP_PATH`, `FEED_URL`, `OUTPUT_DIR`,
`SPARKLE_PRIVATE_KEY` (stdin only).

| Phase | Shape |
|---|---|
| guard | `case "$GITHUB_REF_NAME" in *-*) echo "prerelease: no appcast item"; exit 0 ;; esac` — the same literal as `release.yml:110` (D4) |
| fetch | `curl -fsSL "$FEED_URL" -o "$WORK/current.xml" \|\| : ` then, if absent or empty, synthesise an empty `<channel>` (DD-9, first run) |
| tool | `curl -fsSL -o "$WORK/sparkle.tar.xz" https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-2.9.6.tar.xz`; `printf '%s  %s\n' "$SPARKLE_TARBALL_SHA256" "$WORK/sparkle.tar.xz" \| shasum -a 256 -c -`; `tar -xJf`. `SPARKLE_TARBALL_SHA256` is a **literal in the script** (DD-10) |
| sign | `FRAGMENT="$(printf '%s' "$SPARKLE_PRIVATE_KEY" \| "$WORK/bin/sign_update" --ed-key-file - "$ZIP_PATH")"` — prints `sparkle:edSignature="…" length="…"` |
| merge | Prepend one `<item>` to `<channel>`, preserving every prior item and their order. Item template: `<title>`, `<pubDate>`, `<sparkle:version>$BUILD_NUMBER</sparkle:version>`, `<sparkle:shortVersionString>$VERSION</…>`, `<sparkle:minimumSystemVersion>26.0</…>`, `<enclosure url="$ASSET_URL" $FRAGMENT type="application/octet-stream"/>` |
| emit | `"$OUTPUT_DIR/appcast.xml"`, where CI passes `$RUNNER_TEMP/site` — **nothing is written into the repository tree**, so no `.gitignore` change and no new stowaway surface |

**`release.yml` at the extension point (`:118-119`).** Four steps inserted **after** the publish
step, each carrying `if: ${{ !contains(github.ref_name, '-') }}` so a prerelease never reaches
`deploy-pages` with an empty artifact and blanks the live feed:

```yaml
      - name: Build the appcast
        if: ${{ !contains(github.ref_name, '-') }}
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: scripts/appcast.sh
      - name: Configure Pages
        if: ${{ !contains(github.ref_name, '-') }}
        uses: actions/configure-pages@v5
      - name: Upload the site artifact
        if: ${{ !contains(github.ref_name, '-') }}
        uses: actions/upload-pages-artifact@v3
        with: { path: ${{ runner.temp }}/site }
      - name: Deploy to Pages
        if: ${{ !contains(github.ref_name, '-') }}
        uses: actions/deploy-pages@v4
```

Plus, on the `release` job: `permissions: { contents: write, pages: write, id-token: write }` and
`environment: github-pages`. A job-level `permissions` block **replaces** the workflow-level one, so
`contents: write` must be restated or `gh release create` loses its token. `deploy-pages` targets the
`github-pages` deployment environment; the job must declare it.

> **W11 — these three action major versions are an apply-time confirmation, never a design claim.**
> `configure-pages@v5`, `upload-pages-artifact@v3` and `deploy-pages@v4` are carried from the
> proposal and were **not** verified by this design. Apply MUST confirm the current majors before
> the first tag. A bumped major is a one-token edit, not a re-plan; no decision above depends on
> which major is current.

`gh` stays at **exactly one** invocation and `git` at **zero** — `curl` and `uses:` are neither, so
`theWorkflowCanOnlyEverCreateARelease` (`:733-748`) stays green **unamended**, which is the property
that made this hosting design the only viable one (`explore.md:204-224`).

---

## Testing Strategy

`strict_tdd: true`. Every behavioural row below is RED before its implementation exists.

### Tier 1 — CellarCore `UpdatesTests` (`swift test`), all RED-first

| # | Suite | Assertion |
|---|---|---|
| T1 | `AppVersionTests` | `1.0.1 > 1.0.0`; `1.0.0 (2) > 1.0.0 (1)`; **`0.0.1-rc.1 < 0.0.1`**; `1.0.0-rc.2 > 1.0.0-rc.1`; parameterized ordering table |
| T2 | `AppVersionTests` | Each malformed shape (`""`, `"1.0"`, `"1.0.x"`, `"v1.0.0"`, non-numeric build) throws its named `AppVersionParseFailure` case — never a crash, never a silent zero |
| T3 | `AppcastDocumentTests` | The valid fixture parses; `edSignature` non-empty, `length` numeric, `sparkle:version`/`shortVersionString` present, enclosure scheme `https`, host `github.com`, `minimumSystemVersion == "26.0"` |
| T4 | `AppcastDocumentTests` | One fixture per failure case → its exact typed error (missing signature, non-numeric length, `http://`, wrong host, missing/other `minimumSystemVersion`, hyphenated `shortVersionString`) |
| T5 | `AppcastDocumentTests` | The two-item merged fixture keeps both items in descending order and drops neither — the property DD-9 depends on |
| T6 | `UpdateCheckPresentationTests` | `nil` ⇒ `"Never checked"`; a `Date` ⇒ a `"Last checked …"` label, deterministic under an injected `now` |
| T7 | `AppUpdatingTests` | `FakeAppUpdater` drives the contract: `checkForUpdates()` records a call, `automaticallyChecksForUpdates` round-trips, `canCheckForUpdates` gates |
| T7a | `AppVersionTests` | **W5** — "The version pair is read from the running bundle": `AppVersion.init?(shortVersionString:buildNumber:)` builds the pair from the two raw strings `Bundle.main.infoDictionary` supplies, returns `nil` for either being absent or unparseable, and never substitutes a placeholder. Driven by literal string pairs, so it is a pure unit test with no bundle in it — the app-side read is one line of DI and is covered structurally by T11 |
| T7b | `AutomaticUpdateChecksPolicyTests` | **W7 / DD-15** — `AutomaticUpdateChecksPolicy.apply(preference:to:)` writes `false` to a `FakeAppUpdater` when the preference is off, `true` when on, and writes **exactly once**; a policy run with the preference off leaves `automaticallyChecksForUpdates == false`. This is the scenario "The persisted preference is written to the updater at launch", now genuinely unit-core |
| T7c | `UpdateCommandEnablementTests` | **W7 / DD-15** — `UpdateCommandEnablement.isEnabled(canCheckForUpdates:)` is `true` iff the updater can check. Table-driven; the view merely applies the returned `Bool` |

### Tier 2 — `cellarTests` structural (`xcodebuild test -only-testing:cellarTests`)

| # | Suite | Assertion |
|---|---|---|
| T8 | `UpdateCompositionTests` | Over `AppSecuritySources.load()` (comment-stripped, `SecurityCompositionSupport.swift:42-69`): `import Sparkle` appears in **exactly one** file, and that file is `SparkleUpdateChecker.swift` |
| T9 | `UpdateCompositionTests` | No file under `cellar/` other than `SparkleUpdateChecker.swift` references `SPUUpdater`, `SPUStandardUpdaterController` or `SUUpdater`; and `SparkleUpdateChecker` is not referenced by name in any `View`/`Commands` file |
| T10 | `BundleUpdateKeysTests` | `Bundle.main.infoDictionary` (**not** `localizedInfoDictionary` — U24 Build 2 put both keys in the raw dictionary; the copyright precedent at `:297-313` is the opposite case and must not be copied) carries `SUFeedURL` as an `https` URL equal to the feed constant, and `SUPublicEDKey` whose base64 decodes to **exactly 32 bytes** |
| T11 | `BundleUpdateKeysTests` | The generated bundle carries `LSApplicationCategoryType == "public.app-category.developer-tools"` |
| T12 | `UpdateProjectFileTests` | Both app-target blocks contain `INFOPLIST_FILE = Resources/Cellar-Info.plist;` and `INFOPLIST_KEY_LSApplicationCategoryType = …;` (**two matches each**), and `GENERATE_INFOPLIST_FILE = YES;` still holds twice |
| T13 | `AutomaticUpdateChecksTests` | Against a scratch `UserDefaults(suiteName:)`: a missing key reads `false`; set/read round-trips; nothing else in the suite is written |
| T14 | `ReleasePipelineCompositionTests` **(amend)** | `workflowReferencesExactlyTheExpectedSecrets` (`:701-722`) → the **seven**-name set. First-class RED→GREEN task under the test's own authorising comment (`:699-700`); the doc comment records why the seventh arrived |
| T15 | `ReleasePipelineCompositionTests` **(amend)** | `secretsAppearOnlyAsEnvironmentBindings` (`:668-692`) non-vacuity floor `>= 6` → `>= 7`; the per-line `NAME: ${{ secrets.NAME }}` shape assertion is unchanged and must still pass for `SPARKLE_PRIVATE_KEY` |
| T16 | `AppcastWorkflowTests` (new) | Splitting the workflow on `- name:`, the step whose body contains `appcast.sh` appears **after** the step containing `gh release create`; and all four appcast/Pages steps carry the `!contains(github.ref_name, '-')` guard |
| T17 | `AppcastWorkflowTests` | The job declares `pages: write`, `id-token: write` **and** `contents: write`, and `environment: github-pages` |
| T18 | `AppcastScriptContractTests` (new) | `scripts/appcast.sh` exists and `FileManager.isExecutableFile`; contains `set -euo pipefail`; contains **no** `set -x`, **no** `git `, **no** `gh `; contains `2.9.6` and a 64-hex sha256 literal; `SPARKLE_PRIVATE_KEY` appears only inside a `printf '%s' "$SPARKLE_PRIVATE_KEY" \|` pipeline and never as a `>` redirection target |
| T19 | `AppcastScriptContractTests` | DD-14's textual bridge: the script contains every name the validator requires — `sparkle:edSignature`, `length=`, `sparkle:version`, `sparkle:shortVersionString`, `sparkle:minimumSystemVersion`, `26.0`, `<enclosure` |
| T20 | `UpdateKeyMaterialTests` (new) | DD-12: across the repository (excluding `.git`, `build`, `.build`), exactly **one** 44-character base64 Ed25519-shaped literal exists, and it is the `SUPublicEDKey` value in `Resources/Cellar-Info.plist`. Non-vacuity: the scan saw >100 files |
| T21 | `UpdateCompositionTests` | **W6(a) — "Nothing in the app can substitute a different feed or key."** T20 covers only the key-*material* half. Over the comment-stripped `cellar/` sources: no file references `SPUUpdaterDelegate`, `feedURLString(for:)`, `setFeedURL`, or `updater.feedURL`, and no file writes `SUFeedURL` or `SUPublicEDKey` into `UserDefaults` or any mutable dictionary at runtime. The feed and the key are build-time facts with **no runtime escape hatch**, which is the entire security argument for compiling the key in (`explore.md:145-147`) |
| T22 | `BundleUpdateKeysTests` | **W6(b) — "No bundled default and no framework prompt can enable checking."** `Resources/Cellar-Info.plist` parses via `PropertyListSerialization` and contains **exactly** `SUFeedURL` and `SUPublicEDKey` — no `SUEnableAutomaticChecks`, no `SUAutomaticallyUpdate`, no `SUScheduledCheckInterval`; the generated `Bundle.main.infoDictionary` likewise carries none of those three keys. Paired structural half: in `SparkleUpdateChecker.swift` the `AutomaticUpdateChecksPolicy.apply(…)` call appears **before** the `startUpdater()` call, so the framework can never reach its own second-launch prompt (DD-4) |
| T23 | `UpdateCompositionTests` | **W6(c) — "The command is present in the app menu."** `cellarApp.swift`'s `.commands { … }` body names `CheckForUpdatesCommands`, and `CheckForUpdatesCommands.swift` contains `CommandGroup(after: .appInfo)` and **not** `CommandGroup(replacing: .appInfo)` — so it can never displace `AboutCommands` (DD-7) |
| T24 | `UpdatePackageManifestTests` (new) | **W6(d) — "The update module declares no dependencies."** Parse `Packages/CellarCore/Package.swift` as text, isolate the `.target(name: "Updates"` declaration, and assert it contains **no `dependencies:` key at all**; assert the `Updates` `.library` product exists and lists exactly `["Updates"]`. This is the compile-time isolation DD-1 is entirely built on, so it is pinned rather than trusted |

**Green-on-arrival, must not regress:** `appTargetConfigurationsAreIdenticalModuloName` (`:213-229`)
— both new settings land in both blocks; `theWorkflowCanOnlyEverCreateARelease` (`:733-748`) —
`gh == 1`, `git == 0`, unamended; `appSourcesCarryNoReleaseInfrastructure` (`:409-417`) —
`Resources/` and `scripts/` are outside `cellar/`; `repositoryCarriesNoCredentialMaterial`
(`:433-461`) — unchanged, see DD-12.

### Tier 3 — not testable, stated rather than faked

`SPUStandardUpdaterController` behaviour, Sparkle's user driver, and the actual download/replace
flow. Sparkle ships no test harness. This is the same honesty the tip-jar slice applied to StoreKit,
and it is precisely why the seam lives in CellarCore.

### Tier 4 — manual evidence (exact command, exact accepted output)

| # | Evidence | Accepted |
|---|---|---|
| M1 | `[[U30]]` rehearsal: `scripts/release.sh all` locally with Sparkle linked | `codesign --verify --strict --verbose=2` (`release.sh:214`) passes over `Sparkle.framework`, `Autoupdate`, `Updater.app` and both `.xpc` |
| M2 | `[[U31]]` **re-check on the exported bundle**: `lipo -archs build/verify/cellar.app/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle` | `x86_64 arm64` — already measured on a Debug build (addendum) and **accepted** under D2. This row survives because the addendum measured a Debug build and the claim in `release-distribution` is about the *exported, notarized* one |
| M3 | `[[U32]]` **re-check on the exported bundle**: `find build/verify/cellar.app/Contents \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' \) -print` | Empty — already measured empty on the Debug build, so the gate is expected to stay silent. Same reason as M2: the Debug measurement does not license a claim about the export. If it ever fires, the withdrawn U32 deviation is reopened, never absorbed |
| M4 | `[[U33]]`: first `deploy-pages` run after Pages is enabled with source = GitHub Actions | `curl -fsSI https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml` → `200`, `content-type` XML |
| M5 | End-to-end upgrade: install the `v0.0.1-rc.1` build into `/Applications`, publish a stable tag, let Cellar find it | The update installs and relaunches. **rc → rc is impossible under D4** — the rehearsal must be rc-installed → stable-published |
| M6 | Gatekeeper after the swap, networking **disabled** | First launch of the replaced bundle succeeds with no "cannot be opened" dialog (the update zip is stapled) |
| M7 | Job-log sweep after the first appcast run, following M10's precedent | Zero occurrences of the private key's value; `SPARKLE_PRIVATE_KEY` appears only as `***` |

### Spec-requirement → check map (for `sdd-spec` and `sdd-tasks` to bind against)

| Requirement (`app-updates`) | Primary checks |
|---|---|
| **Honest version display** — all five scenarios, including "The version pair is read from the running bundle" | **W5: unit-core → T1, T2, T7a.** Parsing, ordering and the bundle-pair constructor are pure `AppVersion` tests. `AboutView.version` (`:142-147`) is unchanged and renders the same two raw keys, so it needs no new test; T11 covers the bundle side structurally |
| Default-off consent | T13, T7b, **T22** + DD-4 |
| Always-available explicit check | T7, T7c, **T23** + DD-7 |
| No surface lies about state | T6, T7, T7c, T9 |
| Feed and key fixed at build time, no runtime override | T10, T12, T20, **T21**, **T22** |
| The offered update is a signed notarized artifact with the exact item shape | T3, T19 + M1 |
| Prereleases never offered | T4 (hyphenated version), T16, D4 |
| Published items never removed | T5 + DD-9 |
| The update module reaches nothing | **T24** + DD-1 |
| `release-distribution` edit (a) — arm64 wording | **RESOLVED by U31**: every Sparkle binary is `x86_64 arm64`, so the reword is load-bearing → M2 |
| `release-distribution` edit (a), publication half — **W8**: "a stable tag publishes a feed item; a prerelease publishes none" | **T16** (appcast step ordered after publish; all four steps carry the hyphen guard) + **T17** (permissions and environment present) + manual **M4** (the feed is actually served) and **M5** (rc-installed → stable-published) |
| `release-distribution` closing note — seven secrets | T14 |
| `release-distribution` stowaway scenario | **DOES NOT FIRE** — U32 measured empty; the third edit is withdrawn |

---

## Threat Matrix

**Applicable** — this design adds shell commands, a subprocess-invoking CI step, an
executable-file classification boundary, and a network-reachable publication path.

| Boundary | Adversarial case | Applicability | Design response | RED test |
|---|---|---|---|---|
| Documentation-like paths | A `.plist`, `.sh` or `.yml` dropped inside `cellar/` joins the app target and ships **signed inside the bundle** | **Applicable** | `Resources/Cellar-Info.plist` and `scripts/appcast.sh` both live outside `cellar/`; the plist is merged by `INFOPLIST_FILE`, never copied as a resource | `appSourcesCarryNoReleaseInfrastructure` (green-on-arrival), T18 |
| Executable classification | `appcast.sh` is a new executable in the repository | **Applicable** | Exactly one new executable, `+x`-checked, no `git`/`gh`, no `set -x` | T18 |
| Git repository selection | The appcast step reaching for `git -C` or a second checkout | **N/A — asserted, not assumed** | `appcast.sh` contains no `git`; the workflow's `git` count stays 0 | `theWorkflowCanOnlyEverCreateARelease` (unamended) |
| Commit / push state | Committing the feed to `gh-pages` or `docs/` | **N/A — asserted** | The feed is an Actions artifact written to `$RUNNER_TEMP/site`; nothing enters the repository tree | Same test |
| PR / release commands | A second `gh` call to attach or edit the feed | **N/A — asserted** | `gh` stays at exactly one `gh release create` | Same test |
| Secret exposure | `SPARKLE_PRIVATE_KEY` in a `run:` line, a file, a trace, or a log | **Applicable** | `env:` binding only; stdin only; no file; no `set -x`; the key is never an argument | T14, T15, T18, M7 |
| Subprocess integrity | A tampered `sign_update` binary signs the release with an attacker's key | **Applicable** | The tool comes from the pinned 2.9.6 release asset verified against a sha256 literal in the script; failure aborts before signing | T18 (digest literal present); M1 |
| Update-channel integrity | An attacker who reaches the feed serves a malicious zip | **Applicable** | `SUPublicEDKey` is compiled into every copy, so an unsigned or wrongly-signed item is rejected client-side regardless of the feed's contents; the enclosure host is asserted to be `github.com` over `https` | T3, T4, T10 |
| Egress consent | An update check leaves the machine without the user asking | **Applicable** | DD-4: default off, Cellar's key is the authority, applied at startup before the updater can schedule anything; the explicit menu command is its own consent | T13, T7 |

Every applicable row carries into `tasks.md` unchanged, with the RED test written before the file it
guards.

---

## File Changes

| File | Action | Description |
|---|---|---|
| `Packages/CellarCore/Package.swift` | Modify | +1 `.library(Updates)`, +1 dependency-free `.target`, +1 `.testTarget` with `Fixtures` |
| `Packages/CellarCore/Sources/Updates/{AppVersion,AppcastDocument,UpdateCheckPresentation,AppUpdating,UpdatePolicy}.swift` | Create | DD-1; zero dependencies. `UpdatePolicy.swift` is DD-15 |
| `Packages/CellarCore/Tests/UpdatesTests/**` + `Fixtures/*.xml` | Create | T1–T7, T7a–T7c, `FakeAppUpdater` |
| `cellar/Updates/{SparkleUpdateChecker,AutomaticUpdateChecks,UpdatesSettingsGroup,CheckForUpdatesCommands}.swift` | Create | 0 pbxproj lines |
| `cellar/Settings/SettingsView.swift` | Modify | `"Updates"` group after `"Interface"` (`:73`) |
| `cellar/cellarApp.swift` | Modify | DI in `init`, `.environment`, `.commands { AboutCommands(); CheckForUpdatesCommands(…) }` (`:506`) |
| `cellar/AppTestFixtures.swift` | Modify | `--ui-testing-m6-updates`, `AppTestUpdater` |
| `Resources/Cellar-Info.plist` | Create | Two keys; real `SUPublicEDKey` committed at apply |
| `cellar.xcodeproj/project.pbxproj` | Modify | **The seven items only — 22 lines, measured.** D-1's ≈6 further lines are separate and unauthorized |
| `cellar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` | Create | Committed; pins Sparkle 2.9.6 |
| `scripts/appcast.sh` | Create | Executable; no `git`, no `gh`, no `set -x` |
| `.github/workflows/release.yml` | Modify | Job `permissions` + `environment`; four steps at `:118-119` |
| `cellarTests/{UpdateCompositionTests,BundleUpdateKeysTests,UpdateProjectFileTests,AutomaticUpdateChecksTests,AppcastWorkflowTests,AppcastScriptContractTests,UpdateKeyMaterialTests,UpdatePackageManifestTests}.swift` | Create | T8–T13, T16–T24 |
| `cellarTests/ReleasePipelineCompositionTests.swift` | Modify | T14, T15 only |
| `THIRD-PARTY.md` | Modify | `## Sparkle` — project, version 2.9.6, Sparkle Project contributors / Andy Matuschak, full MIT text (D7: sole attribution surface; About unchanged) |
| `RELEASING.md` §2, §7 | Modify | §2 gains prerequisites 6–8 (enable Pages source = Actions; `generate_keys` + offline backup; `SPARKLE_PRIVATE_KEY`) and "Six" → "Seven repository secrets"; §7 gains the appcast/feed row and **deletes** the `LSApplicationCategoryType` known-follow-up at `:251-254`, now discharged |
| `PRD.md` :9, :124, :168, :188, :212 · `README.md` | Modify | Rewritten in place with reasons (tip-jar precedent) |
| `scripts/release.sh`, `scripts/ExportOptions.plist`, `cellar/Shell/AboutView.swift`, `cellar/InfoPlist.xcstrings` | **Untouched — binding** | 0-line diffs |

---

## Maintainer checkpoints inside apply (obs 7681 Q1 — the key is real, generated during apply)

Sequenced. Checkpoint 4 **blocks** the commit that creates `Resources/Cellar-Info.plist`; 1–3 and 5–6
block only the first appcast-publishing tag.

| # | Step | Exact action |
|---|---|---|
| 1 | Obtain the tools | `curl -fsSLO https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-2.9.6.tar.xz`, verify `shasum -a 256`, `tar -xJf` |
| 2 | Generate the keypair | `./bin/generate_keys` — writes the private key to the login Keychain and prints the base64 public key |
| 3 | **Back it up before anything else** | `./bin/generate_keys -x sparkle-private.key`, move the file to offline storage or a password manager, then `rm -P sparkle-private.key`. **This is a one-way door:** losing the key permanently severs the update channel for every copy already installed, and rotation requires shipping a new `SUPublicEDKey` through a non-Sparkle channel first |
| 4 | Commit the **real** public key | Paste the printed value into `Resources/Cellar-Info.plist`. **No placeholder** — a well-formed placeholder passes T10 unchanged and ships builds that can never update themselves, and it is indistinguishable at review (obs 7681 Q1) |
| 5 | Add the seventh secret | Repository → Settings → Secrets → `SPARKLE_PRIVATE_KEY` = the exported private key. Verify once with `./bin/sign_update` against any zip before deleting the local copy |
| 6 | Enable Pages | Repository → Settings → Pages → **Source: GitHub Actions**. Measured `has_pages: false` (`explore.md:43-47`). Confirm no `github-pages` environment protection rule excludes tag refs, or DD-13's fallback applies |

**Security posture.** The private key never touches the repository, never touches a runner disk,
never appears as a command argument, and is never traced (`set -x` is prohibited and asserted, T18).
`SUPublicEDKey` is **public by construction** — it ships inside every copy of the app — and must not
be handled as a secret. The residual gap DD-12 names is stated, not hidden.

---

## Probe status and fallbacks

| Probe | Status | Branch |
|---|---|---|
| `[[U25]]` **SPM auto-embed + Swift 6 MainActor compile** | **RESOLVED — measured** (addendum, rows U25 a/b/c) | **(a)** `cellar.app/Contents/Frameworks/Sparkle.framework` is present (2.8 MB) and the `PBXCopyFilesBuildPhase` count is **0** ⇒ **no Embed Frameworks phase**, the pre-costed ~10-line deviation is **withdrawn**, and the seven bound items stand unchanged. `LD_RUNPATH_SEARCH_PATHS` already carried `@executable_path/../Frameworks` (`:433-436`, `:467-470`) and needed no edit. **(b)** `SPUStandardUpdaterController(startingUpdater:updaterDelegate:userDriverDelegate:)`, `canCheckForUpdates`, `lastUpdateCheckDate` and `checkForUpdates()` compiled from a `@MainActor` context under `-swift-version 6 -default-isolation=MainActor` with **zero** Sparkle-related diagnostics ⇒ no `@preconcurrency`, no re-plan; DD-6's `assumeIsolated` remains a correctness choice, not a warning workaround. **(c)** `Package.resolved` was created at `cellar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (387 bytes, `version: 3`, `sparkle` @ 2.9.6, revision `ac2def28…`), the directory exists and is not gitignored ⇒ the commit decision above is executable as written |
| `[[U31]]` **`lipo -archs` on the framework** | **RESOLVED — measured** | `Sparkle`, `Autoupdate`, `Updater`, `Downloader.xpc`, `Installer.xpc` and `bin/sign_update` are each **`x86_64 arm64`**. D2's allowance is **exercised, not theoretical**: the `release-distribution` reword (:117-136 and its scenario :130-136) is load-bearing, and the app executable's own `arm64`-only claim is unaffected because `release.sh:236` reads `Contents/MacOS/cellar` only |
| `[[U32]]` **stowaway `.sh`/`.yml` inside the bundle** | **RESOLVED — measured, does not fire** | The `find Contents \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' -o -name 'ExportOptions*.plist' \)` sweep over the built bundle returned **empty**. `release.sh:252-254` is **unchanged** and the **third `release-distribution` edit (stowaway scenario :278-283) does NOT fire** — the `release-distribution` delta stays at the two edits the proposal authorised |
| `[[U30]]` **`codesign --verify --strict` over nested Sparkle code** | Owned by apply, deliberately | Run `scripts/release.sh all` locally as the **first** rehearsal step, before any tag. Failure ⇒ re-plan; never relax the gate. Cost if it fails: the `-exportArchive` inside-out signing path (`release.sh:138-142`, `ExportOptions.plist` `signingStyle: automatic`) is the mechanism that is supposed to make this work, so a failure means the integration shape is wrong, not the gate |
| `[[U33]]` **`deploy-pages` on this repository** | Deferred to the maintainer prerequisite | Failure ⇒ DD-13's second-job fallback first; if Pages itself is unusable, Vercel is a re-plan, not an implementation detail |
| `sign_update` stdin | **RESOLVED — measured** | `--ed-key-file <private-key-file>`: *"'-' can be used to echo the EdDSA key from a 'secret' environment variable to the standard input stream"*; `-s <private-key>` is deprecated. **DD-11 holds exactly as written** — the key is never a file and never an argument |
| Action major versions | **Apply-time confirmation, never a design claim** (W11) | `configure-pages@v5`, `upload-pages-artifact@v3`, `deploy-pages@v4` are carried from the proposal and were **not** verified by this design. Apply MUST confirm the current majors before the first tag; a bumped major is a one-token edit and is not a re-plan |

---

## Rollback and Deviation Protocol

**Rollback.** One `git revert` of the PR restores the code exactly: the seven pbxproj items back out
together, `Resources/` and `scripts/appcast.sh` are net-new deletions, and the `Updates` product
disappears with its target. Orphaned residue after a revert, all inert: Cellar's
`updates.automaticChecksEnabled` key, Sparkle's own `SU*` `UserDefaults` keys, and the resolved
package cache. Post-revert checks: `swift build --package-path Packages/CellarCore` and the config
`build_command`.

A revert does **not** unpublish an appcast. A bad release is corrected by publishing a **higher**
version, never by deleting a feed item — deleting one strands every copy that already saw it. The
private key, the repository secret and the Pages setting all survive a revert, and **the key MUST be
retained**: re-landing this change must reuse the same `SUPublicEDKey` or it strands every copy
shipped in between.

**Deviation protocol.** Of the three deviations this design originally carried, **two are now
withdrawn by measurement** and **one remains open**:

| Deviation | State |
|---|---|
| **D-1** — the `Updates` product-linkage entries (≈6 lines, 22 → ≈28) | **OPEN. The single unresolved decision in this design.** Reported, not authorized; the maintainer has not answered. Options (a)/(b)/(c) above stand unchanged |
| **U25(b)** — a `PBXCopyFilesBuildPhase` Embed & Sign phase | **WITHDRAWN.** Measured: Sparkle auto-embeds with a `PBXCopyFilesBuildPhase` count of 0 |
| **U32** — a `Contents/Frameworks/` exclusion in `release.sh` plus a third `release-distribution` edit | **WITHDRAWN.** Measured: the stowaway sweep is empty; `release.sh:252-254` and the stowaway scenario (:278-283) are untouched |

Should any new deviation appear at apply, the rule is unchanged: report before merge, never apply
silently — that is what the `m6-release-pipeline` gate failure taught.

## Migration / Rollout

No data migration, no feature flag, no schema change. Rollout: merge → maintainer checkpoints 1–6 →
`[[U30]]` local rehearsal → a stable tag publishes the first appcast item → M5's rc-installed →
stable-published upgrade proves the loop. Existing users of a locally built copy see one new
Settings card and one new menu item, both inert until they act.

---

## Size Forecast (bottom-up by file, house correction 1.9–2.3×)

| Bucket | Lines |
|---|---|
| `project.pbxproj` (seven items **measured at 22**; 28 with D-1) | 22–28 |
| `Package.resolved` (new, generated — **measured 387 bytes**) | 18–20 |
| `Packages/CellarCore/Package.swift` | 12–18 |
| `Sources/Updates/*` (**5** files — `UpdatePolicy.swift` added by DD-15) | 255–360 |
| `Tests/UpdatesTests/*` + XML fixtures (T1–T7, **T7a–T7c**) | 355–510 |
| `cellar/Updates/*` (4 files) | 210–300 |
| `SettingsView`, `cellarApp`, `AppTestFixtures` | 70–120 |
| `cellarTests` new files (T8–T13, T16–**T24**) | 330–470 |
| `cellarTests/ReleasePipelineCompositionTests.swift` (T14, T15) | 8–14 |
| `Resources/Cellar-Info.plist` | 10–12 |
| `scripts/appcast.sh` | 90–170 |
| `.github/workflows/release.yml` | 25–40 |
| Docs (`THIRD-PARTY.md`, `RELEASING.md` §2/§7, `PRD.md` ×5, `README.md`) | 160–260 |
| **Bottom-up subtotal (authored code, docs and tests)** | **1,527–2,314** |

Corrected **1.9–2.3×** → **≈ 2,901–5,322 authored lines**.

**Artifacts already on disk, counted at their real size rather than estimated** (W10):

| Artifact | Lines | Note |
|---|---|---|
| `openspec/specs/release-distribution/` **delta — already written** | **256** | **Recorded overrun.** The proposal forecast an "honest count ~6-10 changed lines, nothing destructive" for two edits. The delta as written is **256 lines**, roughly **~34 changed lines** of actual requirement/scenario text plus the surrounding MODIFIED-block scaffolding OpenSpec requires. The forecast was of *changed prose*; the artifact is a *full delta document*. Stated, not smoothed. U32's withdrawal means it stays at two edits and does **not** grow a third |
| `openspec/.../app-updates/spec.md` — **already written** | **383** | Counted, not estimated |
| `proposal.md`, `design.md`, `tasks.md` | 300–450 | `tasks.md` still to be written; the other two exist |

**PR total ≈ 3,840–6,411 lines.** Both spec deltas were counted off disk (256 + 383 = 639), not
forecast, so this figure is firmer at its base than the corrected code estimate above it.

- Against the 400 default: **High**.
- Against the 5,000 session budget: **High, and the ceiling now exceeds it outright.** The corrected
  authored ceiling alone is 5,322; the PR total exceeds the budget across nearly its whole range,
  and 639 of those lines are already on disk and therefore not going to shrink. This is
  above the proposal's 2,480–4,780 for four named reasons: the `cellarTests` bucket grew (T8–T24 is
  **seventeen** structural tests, not the proposal's four groups); `Sources/Updates` grew (typed
  failure enumerations rather than `Bool` returns, plus DD-15's `UpdatePolicy.swift`); the
  `UpdatesTests` bucket grew with T7a–T7c; and the `release-distribution` delta is 256 real lines
  against a ~6–10 forecast.

**Q4 trigger fires — harder than at first pass.** The proposal's re-split threshold is ~4,200
authored lines; the corrected midpoint is ~4,112 and the ceiling is 5,322, so the threshold now sits
*inside* the likely range rather than near its top. Per obs 7681 Q4, `sdd-tasks` **MUST ASK the maintainer
before splitting** — it must not split automatically and must not silently take a `size:exception`.
`sdd-tasks` MUST reuse this forecast rather than re-deriving it, MUST plan phases **3a** (app-side;
`LSApplicationCategoryType` sequenced first as the cheapest independently revertible step) and **3b**
(publication) as independently deliverable, and MUST emit the exact guard lines.

Provisional guard lines for `sdd-tasks` to confirm or correct:

    Decision needed before apply: Yes
    Chained PRs recommended: Yes
    400-line budget risk: High

---

## Open Questions

**The single open decision is D-1.** Everything else below is either resolved, apply-owned, or a
maintainer prerequisite.

- [x] **D-1 — APPROVED by the maintainer 2026-08-23 (option a).** Proposal list amended to ten items (8–10). Formerly: Approve the three `Updates` product-linkage pbxproj entries
      (≈6 lines, taking the file from 22 to ≈28), or choose alternative (b)/(c). **Blocks apply of
      the CellarCore target.** Unauthorized until the maintainer answers.
- [x] `[[U25]]` — **RESOLVED.** Auto-embed confirmed with zero `PBXCopyFilesBuildPhase`; zero Swift 6
      / MainActor diagnostics; `Package.resolved` at the workspace path, not gitignored. The Embed
      Frameworks deviation is **withdrawn**.
- [x] `[[U31]]` — **RESOLVED.** Every Sparkle binary is `x86_64 arm64`; D2's reword is load-bearing.
- [x] `[[U32]]` — **RESOLVED.** Stowaway sweep empty; the third `release-distribution` edit does not
      fire and `release.sh:252-254` is untouched.
- [x] `sign_update` stdin — **RESOLVED.** `--ed-key-file -` reads the key from standard input
      (help text quoted in the addendum). DD-11 holds as written; there is **no** `$RUNNER_TEMP`
      fallback and no weakening.
- [ ] `[[U30]]` — apply owns it, as the first rehearsal step (`scripts/release.sh all` locally,
      before any tag).
- [ ] `[[U33]]` — maintainer prerequisite. Also settles whether `actions/deploy-pages@v4` requires
      `environment: github-pages` on the job (assumed yes, W9); if not, the job header shrinks by
      one line.
- [ ] Action major versions — **apply-time confirmation** (W11), never a design claim.
- [ ] Release-notes presentation (link the GitHub release body vs. embedded HTML) — **deferred out
      of v1**: `SUShowReleaseNotes` defaults `YES` and Sparkle renders `<description>`, which this
      design does not populate, so the update window simply shows no notes. Populating it would
      cross the existing release-notes consent gate and belongs to its own change.
- [ ] `cellarUITests/ReleaseNotesUITests` ownership — unrelated to this slice, still unowned since
      m5-health, recorded so it is not rediscovered.

---

## Probe addendum — measured by an orchestrator-owned build worker, 2026-08-23

Scratch copy of the repository (rsync, no `.git`) with the Sparkle 2.9.6 SPM dependency added to the
`cellar` app target only; `xcodebuild build -configuration Debug -destination 'platform=macOS,arch=arm64'
CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`. No tracked file touched (`git status` = only the
untracked change directory).

| Probe | Result | Consequence |
|---|---|---|
| **U25 (a)** auto-embed | `cellar.app/Contents/Frameworks/Sparkle.framework` present (2.8 MB); `PBXCopyFilesBuildPhase` count in pbxproj = **0** | **No Embed Frameworks phase.** The pbxproj list stands as bound (plus D-1). |
| **U25 (b)** Swift 6 + MainActor | Probe file using `SPUStandardUpdaterController(startingUpdater:updaterDelegate:userDriverDelegate:)`, `updater.canCheckForUpdates`, `lastUpdateCheckDate`, `checkForUpdates()` from a `@MainActor enum` compiled with `-swift-version 6 -default-isolation=MainActor` and the three upcoming features: **zero** Sparkle-related warnings or errors (the only warnings in the log are pre-existing `AppTestFixtures.swift:551` and the AppIntents metadata notice) | No `@preconcurrency`, no re-plan. |
| **U25 (c)** `Package.resolved` | Created at `cellar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` (387 bytes, `version: 3`, pin `sparkle` @ `2.9.6`, revision `ac2def288cbff5cfc7df3ffef6abdf45b72bcb0a`) | Committed, as DD-x already says; 18 lines. |
| **U31** `lipo -archs` | `Sparkle`, `Autoupdate`, `Updater`, `Downloader.xpc`, `Installer.xpc`, `bin/sign_update`: **`x86_64 arm64`** each | The accepted D2 allowance is exercised, not unused. `release-distribution` reword stands. |
| **U32** stowaway sweep | `find Contents \( -name '*.sh' -o -name '*.yml' -o -name '*.yaml' -o -name 'ExportOptions*.plist' \)` → **empty** | Gate does not fire. **No third `release-distribution` edit.** `release.sh:252-254` unchanged. |
| `sign_update` stdin | `--ed-key-file <private-key-file>`: *"'-' can be used to echo the EdDSA key from a 'secret' environment variable to the standard input stream"*; `-s <private-key>` is **deprecated** | DD-11 holds as written; the `$RUNNER_TEMP` weakening is not needed. |
| Resolve | `Resolved source packages: Sparkle @ 2.9.6`; artifact checksum in `workspace-state.json` = `8d5fb41d…e7606` (matches) | — |

**Measured pbxproj cost of the Sparkle dependency alone: 18 added / 0 removed lines**, in five hunks:
1 `PBXBuildFile`, 1 `PBXFrameworksBuildPhase` entry, 1 `packageReferences` entry, 11 for the new
`XCRemoteSwiftPackageReference` section (the project had none, so the section header/footer are new),
5 for the `XCSwiftPackageProductDependency`. With `INFOPLIST_KEY_LSApplicationCategoryType` ×2 and
`INFOPLIST_FILE` ×2 the seven bound items cost **22 lines**; with D-1's three `Updates` linkage
entries, **≈28 lines**.

Resolved artifact also exposes `bin/generate_keys`, `bin/sign_update`, `bin/generate_appcast` under
`<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/` — useful for the maintainer's local
`generate_keys` step (DD-10 still sources the CI copy from the pinned tarball).

**Remaining open probes:** U30 (nested `codesign --verify --strict`, apply-owned first rehearsal step)
and U33 (`deploy-pages` on this repository, maintainer prerequisite). Action major versions still to
be confirmed at apply.
