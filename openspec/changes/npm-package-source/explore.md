# Exploration: npm as a second package source (`npm-package-source`)

Repository evidence read at `main` e8a8fd7 (v1.7.4). Scope v1: global packages only (`npm -g`). Artifact store: hybrid (Engram `sdd/npm-package-source/explore`, obs #7966).

## 1. Current Homebrew coupling (queue / history / confirmation / activity spine)

| Type | Where | How brew-specific | Minimal seam for a second source |
|---|---|---|---|
| `BrewCommand` | `Packages/CellarCore/Sources/BrewProcess/BrewCommand.swift` | argv + `.read/.mutate` + `Set<BrewEnvironment.CommandOverride>`. Only the override type is brew-named. | Reusable as-is; the override set is empty for npm. |
| `BrewExit` / `LogLine` / `ProcessSpec` / `ProcessLaunching` | `BrewProcess/` | Generic POSIX exit + verbatim lines. | Reuse unchanged. |
| `BrewEnvironment` | `BrewProcess/BrewEnvironment.swift` | Pins `HOMEBREW_NO_AUTO_UPDATE/NO_COLOR/NO_EMOJI`; inherits only `PATH`,`HOME`. | Add sibling `NpmEnvironment.compose` (same allow-list discipline); `BrewRunner.start` must stop calling `BrewEnvironment.current` directly. |
| `BrewRunner` (actor) | `BrewProcess/BrewRunner.swift:19,149-230` | Reads only `installation.executableURL` (L151, L212); composes env via `BrewEnvironment.current` (L153, L214). FIFO gate, SIGINT→SIGTERM cancel, log pump: generic. | Generalize init to `(executableURL:, environment: @Sendable (Set<CommandOverride>) -> [String:String], launcher:)`; keep `BrewInstallation` convenience init. ~20 lines. |
| `DefaultBrewLocator` / `BrewDetectionState` / `BrewDetectionStore` | `BrewProcess/BrewLocation.swift`, `DefaultBrewLocator.swift`, `BrewDetectionStore.swift` | Candidate list, `--version` probe, configured path never falls through (D6). `ExecutableProbing` seam. | Mirror as `NpmLocator` + `NpmDetectionState`; do not widen brew's types. |
| `BrewMutating` protocol | `BrewClient/BrewMutating.swift:66-156` | **Two hard brew couplings**: extension default `displayCommand = "brew " + argv` (L135) and `brewCommand` (L142). | Add `var source: PackageSource { get }` with default `.homebrew`; `displayCommand` derives prefix from `source`. `AnyBrewMutation` (L178) must copy `source` or an erased npm command renders as `brew npm ...`. |
| `MutationCommand` | `BrewClient/MutationCommand.swift` | `vector(naming:)` switches on `PackageKind` for `--formula/--cask` (L329-335). `PackageTarget` gates `MutationName.isSafe` only (L44). | Do not add npm cases. New family `NpmCommand: BrewMutating` in its **own top-level file** `Sources/BrewClient/NpmCommand.swift` (structural scan is non-recursive, `MutationCommandTests.swift:384-400`). |
| `MutationOutcome.classify` | `BrewClient/MutationOutcome.swift:86-120` | Brew stderr signatures; `message(for:)` says "Homebrew exited with status…" (L196-201). | Per-family `classify` override exists (D4). `NpmCommand.classify` maps `EACCES/EPERM` → `.needsPrivileges`, network errors → `.failed`. `message(for:)` and `HistoryPresentation.outcomeLabel` need source-aware wording. |
| `InvalidationScope` / `MutationGates` / `RefreshDomain` | `BrewMutating.swift:36-51, 259-320`; `MutationRefreshReceipts.swift:13-16` | Four bits. | Add `.npmInventory` bit + `RefreshDomain.npmInventory` + one more `InstalledMutationGate` wired in `cellarApp.swift:465-470`. |
| `OperationCenter` | `BrewClient/OperationCenter.swift:79-160, 313-366` | Single `runner: BrewRunner?`, `launcherFactory: (BrewInstallation) -> ProcessLaunching`; `unavailableGuidance` names Homebrew. | Hold `runners: [PackageSource: BrewRunner]`; add `attach(npm:)`; `run` picks `runners[command.source]`; `isAvailable(for:)`. Separate FIFO per source is a design decision. |
| `ActivityItem` | `BrewClient/ActivityItem.swift:72,114-126` | Stores `AnyBrewMutation`. | Follows `AnyBrewMutation.source`. |
| `OperationCenterBulk.submitUpgrades`, `BulkSelection` | `OperationCenterBulk.swift`, `BulkSelection.swift:98` | Build `MutationCommand` from `PackageID`s. | `PackageTarget.init?` rejects non-Homebrew ids so `MutationCommand.naming` returns nil (affordance unavailable, never wrong argv). |
| History (SchemaV3 `HistoryEntry`) | `Persistence/SwiftDataHistoryRecorder.swift:41-57`, `SchemaV1.swift:215-222` | Stored as `kindRaw: String`; decoded via `PackageKind(rawValue:)`. | `"npm"` round-trips with **no schema migration**; same for `PackageMeta`, `Snooze`, `DismissedCVE`. History rows should show a source badge. |
| Structural argv tests | `BrewClientTests/MutationCommandTests.swift:289-360`, `InstalledArgvTests.swift` | Every top-level `*Command.swift`: `arguments` body may not contain `\(`, `joined(`, `+ " "`; must contain `MutationName.isSafe`. | `NpmCommand.swift` covered automatically; `name@latest` cannot be interpolated — use `npm update -g <name>` or a validated `spec` token on the wrapper. |
| `MutationName.isSafe` | `MutationCommand.swift:129-134` | Rejects empty, leading `-`, whitespace. | Scoped names (`@scope/name`) pass; keep the single gate. |

## 2. Where `PackageID.kind` is switched on

- CellarCore: ~45 sites in 22 files. Exhaustive switches (compile-breaking): `MutationCommand.vector` (L330), `InstalledModels.isOutdated` (L128), `InstalledDetailProjection` (L187, L133/145), `DiscoveryRoster.contains` (L72), `DiscoveryRosterDiff` (L67), `AnalyticsIndex` (L100), `CaskRelationsWire` (L34), `CatalogSyncSupport` (L16, L45). Two-kind ternaries: `TapCommand:160`, `DiskUsageEngine:92`, `InstalledDiskUsageProjection:5`, `BrewMutating:347`, `CleanupCommand:85`, `TapProjection:233,328`, `EcosystemMapping:273` (npm → `.notCovered(.kindUnsupported)`, correct), `InstalledModels.precedes:195`, `DiskUsageModels:127`, `TapPackageSearch:461`, `PackageSearchIndex:109`, `CatalogModels:161`, `FormulaBrowseProjection:34`, `CaskBrowseProjection:53`, `CatalogSyncEngine:351`, `BulkSelection:98`.
- App: ~38 sites in 16 files. Exhaustive: `Security/ArtifactLocator:86`, `Home/HomebrewUpdateNeed:112`, `Taps/BrewfileImportSheet:269,280`, `Browse/CatalogFilterBar:107`. Others: `CleanupRow:37`, `InstalledRow:76`, `InstalledFilterBar:32,36`, `HomeView:205,301`, `CleanupView:83,92` (npm rows silently excluded — desired), `PackageDetailView:465,607,614`, `PackageRow.KindTag:131`, `CaskIconView:89,97`, `PackageDetailView+TapInventory:118`, `BrewfileSectionView:90-91`, `TapDetailView:203-269`.
- `PackageKind` is declared in the brew-free `Catalog` target (`CatalogModels.swift:5`).

Net: ~13 exhaustive switches to extend, ~70 sites to audit.

## 3. Updates / Installed / Health / Cleanup UI

- `cellar/Installed/InstalledListView.swift`: three lenses (L32-44). Rows: `InstalledBrowse.entries(...)` → kind filter (L303) → under `.updates` intersect `outdatedIDs` (L306-309) → query. Bulk bars call `operations.submitUpgrades(for:in:)`.
- `InstalledFilterBar.swift`: chips All / Formulae / Casks / Dependencies. **Source chip slots here.** Disabled when `state == .brewAbsent` — npm needs its own disabled reason.
- Dependencies filter: npm globals are all `installedOnRequest = true`, so the toggle is a no-op for them.
- `outdatedIDs` consumers that must agree: `SidebarView:226-228`, `HomeView:202-203`, `HealthComposition:71`, `MenuBarProjection:54-56`, `InstalledListView:307,346`. A merged inventory satisfies all for free.
- `InstalledEmptyState` + `BrewAbsentGuidance`: copy must cover "brew up to date, npm not checked (offline)".
- `PackageRow.KindTag` draws a CASK pill only; an NPM pill in the same slot is the "Source column".
- Cleanup and Health disk signals are brew-only; no npm involvement in v1.

## 4. Process layer

- `SystemProcess`, cancellation (SIGINT→SIGTERM), `LineSplitter`: all reusable.
- **npm is `npm-cli.js` with `#!/usr/bin/env node`**; a GUI app's PATH has no `node`. `NpmEnvironment` must prepend the resolved npm bin dir to `PATH`; keep `HOME` (`~/.npmrc`).
- Pins: `NO_COLOR=1`, `npm_config_color=false`, `npm_config_progress=false`, `npm_config_update_notifier=false`, `npm_config_fund=false`, `npm_config_audit=false`, `npm_config_loglevel=warn`.
- Discovery candidates (validate with `npm --version`): configured path → `/opt/homebrew/bin/npm` → `/usr/local/bin/npm` → Volta `~/.volta/bin/npm` → fnm `~/Library/Application Support/fnm/aliases/default/bin/npm` → nvm `~/.nvm/versions/node/*/bin/npm` (`~/.nvm/alias/default`) → mise `~/.local/share/mise/installs/node/*/bin/npm`. asdf shims unsupported unless configured. Per-Node-version globals: v1 must display which npm/prefix it reads (`npm prefix -g`).
- Verified against npm/cli `latest`: `npm outdated` sets exit 1 whenever any package is outdated, **also with `--json`**. JSON per package: `current, wanted, latest, dependent, location`. Adapter must accept exit 0 or 1 with parseable stdout.
- `npm ls -g --json --depth=0`: `name, version, path, dependencies{...}`; throws `ELSPROBLEMS` (exit 1) on missing/invalid while stdout JSON may still be complete. Probe needed.
- `npm install -g <name>@latest` / `npm update -g <name>` / `npm uninstall -g <name>`: `EACCES` → `needsPrivileges`; `ENOTFOUND/ETIMEDOUT` → failed. `npm outdated -g` requires network; refresh cadence must be independent of app activation; offline → "not checked", never "up to date".

## 5. Settings / onboarding

- Brew absence surfaces in `InstalledEmptyState`/`BrewAbsentGuidance`, `OperationCenter.unavailableGuidance`, `SettingsView` (L18-98, from `BrewDetectionStore`).
- npm needs `NpmDetectionStore` (`state`, `configuredPath`, `isEnabled` via `@AppStorage`), a Settings "npm" group with an enable toggle (default **off** in v1), detected path/version/prefix, "npm not detected" note. Source chip disabled with help text when npm is off/absent.

## 6. Testing capabilities

- Doubles: `FakeProcessLauncher` + `FakeProcess`, `RecordingProcessLauncher` with `ScriptedRun`, `SpyProcessLauncher`, `FakeBrewLocator`, `FakeExecutableProbe`, `FakeInstalledPayloadSource`, `InstalledFixture`, `OperationCenterHarness`, `ProbeMutation`. App: `cellar/AppTestFixtures.swift`.
- Fixture convention: `Tests/*/Fixtures/<Area>/` + `README.md` + `probe-manifest.txt`.
- npm fixtures: `BrewClientTests/Fixtures/Npm/` with `version.stdout`, `ls-g-depth0.json`, `ls-g-problems.{stdout,stderr}`, `outdated-g.json` (exit 1), `outdated-g-none.stdout`, `install-g.stdout`, `install-g-eacces.stderr`, `uninstall-g.stdout`, `prefix-g.stdout`. Decoder tests pure; runner tests via `FakeProcessLauncher`; argv tests mirror `InstalledArgvTests`; env test mirrors `BrewEnvironment` tests.

## 7. Approaches

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| A. `PackageKind.npm` + derived `PackageSource`; npm packages in the one `InstalledInventory`; `PackageTarget` rejects `.npm` | Favorites, snooze, history, all counts, Source filter work with zero merge plumbing; no migration | `PackageKind` in brew-free `Catalog`; ~13 switches + ~70 sites; `InstalledPackage` carries brew-only fields | Medium-High (~4.5–6k lines) |
| B. Parallel `PackageSource` protocol, separate `NpmInventory`, source-agnostic `OperationCenter`, app-level unified row model | Zero blast radius on Catalog; npm model fits npm fields | Every unified surface needs explicit union code and a second identity; a discriminator reappears anyway | High (~6–7.5k lines) |
| C. Hybrid (**recommended**): identity as A, execution as B (source-keyed runners, `source` projection, per-source env/locator/payload source, `NpmStore` feeding a merged read-model) | Cheap identity + clean execution seam; sliceable | Still touches the 13 switches; `PackageKind` ownership debt must be recorded | Medium-High (~4.5–6k lines) |

**Recommendation**: C. Every cross-cutting surface is already keyed on `PackageID`; the execution spine was designed for another family to enter through the shared abstraction (PM1). The one dishonest point (`displayCommand`/`brewCommand` hard-coding `brew`) becomes a `source` projection.

**Slice 1 (read-only, ~1.8–2.4k lines)**: `NpmLocator` + `NpmDetectionState/Store` + `NpmEnvironment` + `NpmPayloadSource` + `NpmInventory` decoder + `PackageKind.npm` + Settings toggle (default off) + Source chip + NPM pill + rows/counts. `PackageTarget` guard makes brew verbs unavailable for npm rows.
**Slice 2**: runner generalization, source-keyed `OperationCenter`, `NpmCommand` (upgrade/uninstall, `.packageRemoval` confirmation), `classify`, `.npmInventory` gate + refresh coordinator, history/activity wording.
**Slice 3**: menu bar, Home card copy, Health signal decision, offline "not checked" states.

## Affected areas

- Catalog: `CatalogModels.swift`, `DiscoveryRoster.swift`, `DiscoveryRosterDiff.swift`, `AnalyticsIndex.swift`, `CatalogSyncSupport.swift`, `Wire/CaskRelationsWire.swift`
- BrewProcess: `BrewRunner.swift`, `BrewEnvironment.swift`, new `NpmEnvironment.swift`, `NpmLocation.swift`, `DefaultNpmLocator.swift`, `NpmDetectionStore.swift`
- BrewClient: `BrewMutating.swift`, `MutationCommand.swift`, new `NpmCommand.swift`, `MutationOutcome.swift`, `OperationCenter.swift`, `OperationCenterBulk.swift`, `BulkSelection.swift`, `InstalledModels.swift`, `InstalledFilterMode.swift`, `InstalledDetailProjection.swift`, `MutationRefreshReceipts.swift`, new `NpmPayloadSource.swift`, `NpmDecoder.swift`, `NpmStore.swift`
- Persistence: `HistoryPresentation.swift`
- App: `cellarApp.swift`, `Installed/InstalledFilterBar.swift`, `InstalledListView.swift`, `InstalledRow.swift`, `InstalledEmptyState.swift`, `Browse/PackageRow.swift`, `Settings/SettingsView.swift`, `Shell/SidebarView.swift`, `Home/HomeView.swift`, `Home/HomebrewUpdateNeed.swift`, `Health/HealthComposition.swift`, `Security/ArtifactLocator.swift`, `Taps/BrewfileImportSheet.swift`, `Browse/CatalogFilterBar.swift`
- OpenSpec: new capability `npm-source`; deltas to `installed-inventory`, `package-mutation`, `brew-execution`, `operation-activity`, `installation-history`, `brew-detection`.

## Risks

- PRD anchor: `openspec/config.yaml` requires proposals to name a PRD milestone; npm is not in PRD.md.
- `npm outdated` needs network and can be slow; must not share the activation-triggered cadence; offline is never "up to date".
- Exit-code semantics differ from brew; `InstalledPayload`'s "non-zero is an error" cannot be reused.
- PATH: npm cannot launch without `node`; env composition must be tested structurally.
- Per-Node-version globals (nvm/fnm) make "global" ambiguous.
- `PackageKind` in `Catalog` becomes source-bearing; catalog paths must treat `.npm` as never-present.
- Two FIFO runners allow brew and npm mutations to overlap — product decision.
- `npm update -g <name>` semantics for globals (majors?) need a probe.
- Full feature ~4.5–6k lines vs 8,000 budget; slice 1 alone is comfortably under.

## Ready for Proposal

Yes, conditioned on adding a PRD milestone for npm and accepting hybrid approach C with slice 1 as the first deliverable.
