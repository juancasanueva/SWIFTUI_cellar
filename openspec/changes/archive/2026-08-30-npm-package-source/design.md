# Design: npm as a second package source (`npm-package-source`)

Inputs: `proposal.md` (obs #7969), `explore.md` (obs #7966), decisions (obs #7968). Approach C (hybrid): identity through `PackageKind.npm`, execution through source-keyed runners. Evidence read at `main` e8a8fd7. Size note: this artifact exceeds the 800-word default because the orchestrator asked for per-switch handling, a per-unit TDD plan and estimates.

## Technical Approach

- **Identity is cheap**: `PackageKind.npm` joins the enum in `Catalog`; `PackageID` already keys favourites, snooze, history, counts and filters, so nothing migrates.
- **Execution is separate**: npm gets its own environment, locator, detection store, payload source, decoder and store. Only `BrewRunner`'s constructor and the `BrewMutating` protocol are generalised; both keep source-compatible defaults.
- **One read model**: `NpmStore` contributes `[InstalledPackage]` into `InstalledStore`, which recomposes `inventory`. The six `outdatedIDs` consumers (`SidebarView`, `HomeView`, `HealthComposition`, `MenuBarProjection`, `InstalledListView` x2) read the same property they read today and need no change.
- **Everything gated**: every npm surface is behind `NpmDetectionStore.state == .detected`, which is only reachable when the toggle (default off) is on.

Isolation: `NpmEnvironment`, `NpmInventory`, decoders, `DefaultNpmLocator`, `NpmPayloadSource` are `Sendable` values living in SwiftPM's nonisolated default. `NpmDetectionStore`, `NpmStore`, `NpmRefreshCoordinator` are `@MainActor @Observable` like their brew siblings. `BrewRunner` stays an actor; its new `environment` closure is `@Sendable`.

## Architecture Decisions

| # | Decision | Choice | Rejected | Rationale |
|---|---|---|---|---|
| D1 | Source type | `public enum PackageSource: String, Codable, Sendable, Hashable, CaseIterable { case homebrew, npm }` in `Catalog/CatalogModels.swift`; `PackageKind.npm`; `extension PackageKind { var source: PackageSource }` (formula/cask → `.homebrew`). `commandName` ("brew"/"npm") lives in a `BrewClient` extension. | Separate `NpmPackageID` (approach B) | Derived source keeps one identity; `"npm"` round-trips through every existing `kindRaw` column with no schema change. Ownership debt: `Catalog` now carries a non-brew kind (recorded, accepted). |
| D2 | Exhaustive switches | Extended exactly as listed in the table below; catalog paths treat `.npm` as never present. | `default:` arms | A `default:` would hide the next kind; each arm states the npm fact explicitly. |
| D3 | `PackageTarget` guard | `PackageTarget.init?` adds `guard id.kind.source == .homebrew`. `MutationCommand.vector` gets `case .npm: preconditionFailure(...)` (unreachable by construction; asserted by test). | Making `vector` return `[name]` for npm | Brew argv must never name an npm package; failing the init makes the affordance unavailable rather than wrong (BulkSelection, submitUpgrades). |
| D4 | Runner generalisation | `BrewRunner.init(executableURL: URL, environment: @Sendable (Set<BrewEnvironment.CommandOverride>) -> [String: String], launcher:, policy:, clock:, retainedTerminalRecords:)`. Existing `init(installation:...)` becomes a convenience forwarding `installation.executableURL` and `BrewEnvironment.current(commandOverrides:)`. Lines 151/178/212/279 read `executableURL`. | Second `NpmRunner` actor | The FIFO, cancel escalation, pump and retention are generic; duplicating them doubles the test surface. Name `BrewRunner` retained (rename debt). |
| D5 | Environment | `NpmEnvironment: Sendable, Equatable` in `BrewProcess/NpmEnvironment.swift`: `executableURL`, `binDirectory`, `version: String`, `prefix: URL`, `origin: NpmOrigin`. `processEnvironment(inheriting:)` builds `PATH = binDirectory + ":" + parent PATH`, keeps `HOME`, pins `NO_COLOR=1`, `npm_config_color=false`, `npm_config_progress=false`, `npm_config_update_notifier=false`, `npm_config_fund=false`, `npm_config_audit=false`, `npm_config_loglevel=warn`. | Reusing `BrewEnvironment.compose` | npm is `npm-cli.js` with `#!/usr/bin/env node`; a GUI `PATH` has no `node`. Same allow-list discipline, different pins. |
| D6 | Detection | `NpmLocating` protocol; `NpmDetectionState { detected(NpmEnvironment), invalid(URL, NpmValidationError), configuredPathMissing(URL), absent, disabled }`; `DefaultNpmLocator(probe: ExecutableProbing, directories: DirectoryEnumerating, launcher:, homeDirectory:)`. Candidates in priority: configured → `/opt/homebrew/bin/npm` → `/usr/local/bin/npm` → `~/.volta/bin/npm` → fnm default alias → newest `~/.nvm/versions/node/*/bin/npm` → newest `~/.local/share/mise/installs/node/*/bin/npm`. Validation runs `npm --version` then `npm prefix -g` under `NpmEnvironment`. Configured path never falls through (brew D6). `NpmDetectionStore` mirrors `BrewDetectionStore` (single-flight, request-keyed) plus `isEnabled`; disabled publishes `.disabled` without probing. | Widening `BrewDetectionState`; reading nvm `alias/default` | Brew types stay untouched. A new two-method `DirectoryEnumerating` protocol avoids widening `ExecutableProbing` and its fake. nvm/mise alias files can name symbolic targets (`lts/*`); newest-version selection is deterministic and displayed in Settings (decision 4: prefix display is sufficient). |
| D7 | Payload + exit codes | `NpmPayloadSourcing { installed(using:) ; outdated(using:) }` returning `Data`, `throws(NpmInventoryError)`. `NpmPayload.installed` accepts exit 0, and exit 1 when stdout parses (`ELSPROBLEMS`). `NpmPayload.outdated` accepts exit 0 and 1; blank stdout on 0 → empty set. Any other exit → `.commandFailed`; stderr tail matching `ENOTFOUND`/`ETIMEDOUT`/`EAI_AGAIN`/`ECONNREFUSED` → `.networkUnavailable`. Each call builds a read `BrewRunner` from the `NpmEnvironment` (as `BrewInfoPayloadSource` does). | Reusing `InstalledPayload` | Its "non-zero is an error" rule is wrong for npm; the exit-code contract is a first-class, tested adapter. |
| D8 | Tri-state freshness | `NpmInventory { packages: [NpmGlobalPackage]; outdated: NpmOutdatedState }` with `NpmOutdatedState = .fresh([String: NpmOutdatedRecord], at: Date) | .notChecked(NpmNotCheckedReason) | .failed(NpmInventoryError)`. Projection `installedPackages() -> [InstalledPackage]`: `kind: .npm`, one keg (`installedOnRequest: true`), `catalogVersion = latest` when fresh else current, `snapshotOutdated = fresh && current != latest`, `tap/linkedKeg/declaresAutoUpdates = nil`, `isPinned = false`. | Boolean `isOffline` | Offline must never render as up to date; the three states are distinct copy in unit 3. |
| D9 | Merge point | `InstalledStore` gains a private `brewInventory` and `contributions: [PackageSource: [InstalledPackage]]`; `inventory` is recomposed (`InstalledInventory(packages: brew + contributions)`) in `adopt`, `clear` and a new `adopt(_ packages: [InstalledPackage], from: .npm)`. `clear` (brew absent) keeps npm contributions. `precedes` becomes rank-based (formula 0, cask 1, npm 2). `NpmStore(installed:source:clock:)` pushes on every adoption and clears on absence/disable. | App-level union model; separate `NpmInventory` in views | Every consumer of `inventory.outdatedIDs` stays byte-identical; approach B's duplicated identity is what C avoids. |
| D10 | Cadence | `NpmRefreshCoordinator` owns two clocks: `ls -g` on detection change, enable, `.npmInventory` terminals and app activation; `outdated -g` on `.npmInventory` terminals, explicit user refresh, and a minimum-interval timer (`minimumOutdatedInterval`, default 1 h, injected `Clock`). Activation never triggers `outdated`. | Sharing `InstalledRefreshCoordinator` | Network cost is the risk the proposal names; local `ls` and remote `outdated` must not share a trigger. |
| D11 | Invalidation | `InvalidationScope.npmInventory = 1 << 4`; `RefreshDomain.npmInventory`; `MutationGates.domain(for:)` maps it; `cellarApp` registers a fifth `InstalledMutationGate` (`npmMutations`) and wires it to `NpmRefreshCoordinator` with the shared `MutationRefreshRegistry`. | Reusing `.installedInventory` | A `brew` re-snapshot cannot observe an npm change and vice versa; PM6 "exactly one refresh per declared domain" stays true. |
| D12 | `source` projection | `BrewMutating` gains `var source: PackageSource { get }` with default `.homebrew`; `displayCommand` = `source.commandName + " " + arguments.joined(" ")`. `AnyBrewMutation` stores and copies `source` (equality widens deliberately). `MutationOutcome.message(for:)` and `HistoryPresentation.outcomeLabel` read the source (history derives it from `PackageKind(rawValue: kindRaw)?.source`). | Deriving source from `packageID` | `upgradeAll` has no package; the projection must be explicit. |
| D13 | Source-keyed runners, single FIFO | `OperationCenter` holds `runners: [PackageSource: BrewRunner]` and `executables: [PackageSource: URL]`; `attach(installation:)` writes `.homebrew`; new `attach(npm: NpmEnvironment?)` writes `.npm` (`launcherFactory` becomes `(URL) -> any ProcessLaunching`). `perform` picks `runners[command.source]`; a missing runner settles `.launchFailed` as today. Cross-source serialisation: a centre-level chain (`mutationTail: Task`) awaits the previous item's terminal before `run`; `cancel` on a chain-queued item settles `.cancelled` immediately and `run` guards on `outcome == nil`. `unavailableGuidance(for:)` and `isAvailable(for:)` are per source. | Two independent FIFOs; one runner with per-mutation executable | Decision 1 requires one mutation at a time across sources; the chain gives that without teaching `BrewRunner` about sources. Trade-off: chain-queued brew items are absent from the runner's `QueueSnapshot` until their turn (queue phase stays at its initial value; verified by test). |
| D14 | `NpmCommand` | Top-level `Sources/BrewClient/NpmCommand.swift`: `NpmPackageTarget` (`init?(_ id: PackageID)` requires `kind == .npm`, `MutationName.isSafe`, no `@` after index 0; exposes `name` and `latestSpec = name + "@latest"` built in the wrapper's init) and `enum NpmCommand { case upgrade(NpmPackageTarget), uninstall(NpmPackageTarget) }`. `arguments` are fixed vectors: `[Verb.install, Flag.global, target.latestSpec]` and `[Verb.uninstall, Flag.global, target.name]`. `verb` "upgrade"/"uninstall", `requiresConfirmation` uninstall only (`.packageRemoval`), `invalidates [.npmInventory]`, `diskAreas []`, `source .npm`. `classify`: default ordering (fault, cancel, success), then stderr tail `EACCES`/`EPERM` → `.needsPrivileges`; else `.failed(status)`. | `npm update -g <name>` | Decision 2: reach the version the row shows, majors included. No interpolation in `arguments`, so the structural scan (`MutationCommandTests:289-360`) covers the file automatically. |
| D15 | Settings | App `@AppStorage("npm.sourceEnabled")` (default false) and `@AppStorage("npm.configuredPath")` pushed into `NpmDetectionStore`; Settings "npm" group shows toggle, path field, detected path/version/prefix/origin, "npm not detected" note. Logic (state derivation) stays in `NpmDetectionStore`. | Persisting in `MetadataStore` | Mirrors how the brew path is configured today; no SwiftData involvement. |
| D16 | App layer | View wiring only: Source chip (All/Homebrew/npm) in `InstalledFilterBar` with its own disabled reason; `PackageRow.KindTag` NPM pill; three-way branches in `InstalledRow:76`, `CaskIconView:89,97`, `PackageDetailView:465,607,614` (npm detail: version, latest, location; no pin/reinstall/zap/tap sections); `InstalledEmptyState` and Home/menu bar/Health copy read `NpmStore.inventory.outdated`. `InstalledBrowse.isAvailable` = brew loaded or npm contributing. | Per-source view models | The store already exposes everything; views only branch. |

### Exhaustive `PackageKind` switch handling (13)

| Site | `.npm` arm |
|---|---|
| `MutationCommand.vector` L330 | `preconditionFailure` (unreachable: D3) |
| `InstalledModels.isOutdated` L128 | `snapshotOutdated` |
| `InstalledDetailProjection` L133/145/187 | no keg list, no link state, single version row |
| `DiscoveryRoster.contains` L72 | `false` |
| `DiscoveryRosterDiff` L67 | skip (empty) |
| `AnalyticsIndex` L100 | `nil` |
| `CaskRelationsWire` L34 | skip |
| `CatalogSyncSupport` L16, L45 | never present (`nil` / `false`) |
| `InstalledInventory.precedes` L195 | rank order formula < cask < npm |
| `Security/ArtifactLocator` L86 | `nil` (not covered) |
| `Home/HomebrewUpdateNeed` L112 | excluded (brew-only need) |
| `Taps/BrewfileImportSheet` L269/280 | skipped row |
| `Browse/CatalogFilterBar` L107 | `false` (never a catalog kind) |

Audit (not exhaustive, must be read): every `kind == .formula ? a : b` ternary in `explore.md` §2, and any `PackageKind.allCases` iteration in the app target (must not render an npm chip in catalog surfaces).

## Data Flow

    @AppStorage toggle/path ─▶ NpmDetectionStore ─▶ DefaultNpmLocator (probe, dirs, launcher)
                                     │ .detected(NpmEnvironment)
                                     ▼
    NpmRefreshCoordinator ─▶ NpmStore ─▶ NpmPayloadSource ─▶ BrewRunner(executableURL:environment:)
         ▲   (ls / outdated)     │ decode → NpmInventory
         │                       ▼ installedPackages()
    npmMutations gate     InstalledStore.adopt(_:from: .npm) ─▶ inventory (merged) ─▶ outdatedIDs consumers
         ▲
    OperationCenter.finish ◀── NpmCommand ─▶ runners[.npm] ─▶ npm install -g name@latest

## File Changes

| File | Action | Description |
|---|---|---|
| `Catalog/CatalogModels.swift` | Modify | `PackageSource`, `PackageKind.npm`, `kind.source` |
| `Catalog/{DiscoveryRoster,DiscoveryRosterDiff,AnalyticsIndex,CatalogSyncSupport,Wire/CaskRelationsWire}.swift` | Modify | `.npm` arms |
| `BrewProcess/BrewRunner.swift` | Modify | executable + environment init (D4) |
| `BrewProcess/{NpmEnvironment,NpmLocation,DefaultNpmLocator,NpmDetectionStore,DirectoryEnumerating}.swift` | Create | D5, D6 |
| `BrewClient/{NpmPayloadSource,NpmDecoder,NpmModels,NpmStore,NpmRefreshCoordinator,NpmCommand}.swift` | Create | D7, D8, D9, D10, D14 |
| `BrewClient/InstalledStore.swift`, `InstalledModels.swift` | Modify | contributions, rank order, `.npm` arm |
| `BrewClient/{BrewMutating,MutationCommand,MutationOutcome,MutationRefreshReceipts,OperationCenter,OperationCenterBulk,BulkSelection,InstalledDetailProjection,InstalledFilterMode}.swift` | Modify | D3, D11, D12, D13; Source filter |
| `Persistence/HistoryPresentation.swift` | Modify | source-aware outcome label |
| `cellar/cellarApp.swift` | Modify | stores, coordinator, fifth gate, `attach(npm:)` |
| `cellar/Installed/*`, `Browse/PackageRow.swift`, `Settings/SettingsView.swift`, `Home/*`, `Shell/SidebarView.swift`, `Health/HealthComposition.swift`, menu bar | Modify | view wiring (D15, D16) |
| `Tests/BrewClientTests/Fixtures/Npm/` | Create | fixtures + `README.md` + `probe-manifest.txt` |

No `cellar.xcodeproj` edit is expected (new files are SwiftPM). If an app-target file is needed, isolate it in one commit.

## Interfaces / Contracts

```swift
public protocol NpmLocating: Sendable { func detect(configuredPath: URL?) async -> NpmDetectionState }
public protocol DirectoryEnumerating: Sendable { func subdirectories(of url: URL) -> [URL] }
public protocol NpmPayloadSourcing: Sendable {
    func installed(using env: NpmEnvironment) async throws(NpmInventoryError) -> Data
    func outdated(using env: NpmEnvironment) async throws(NpmInventoryError) -> Data
}
public enum NpmInventoryError: Error, Sendable, Equatable {
    case npmUnavailable, commandFailed(status: Int32, message: String), malformedPayload, networkUnavailable, cancelled
}
```

## Testing Strategy (strict TDD; RED before GREEN per task)

Fixtures `BrewClientTests/Fixtures/Npm/`: `version.stdout`, `prefix-g.stdout`, `ls-g-depth0.json`, `ls-g-problems.{stdout,stderr}` (exit 1), `outdated-g.json` (exit 1), `outdated-g-none.stdout` (exit 0), `outdated-g-offline.stderr`, `install-g.stdout`, `install-g-eacces.stderr`, `uninstall-g.stdout`; `probe-manifest.txt` records npm version and command per fixture.

| Unit | Layer | Tests |
|---|---|---|
| 1 | Catalog | `PackageSource` mapping; `PackageID(kind: .npm)` codable round-trip; roster/analytics/sync treat `.npm` as absent |
| 1 | BrewProcess | `NpmEnvironment` structural test (PATH prepend, HOME kept, pins exact, nothing else inherited); `DefaultNpmLocator` with `FakeExecutableProbe` + `FakeDirectoryEnumerator` + `FakeProcessLauncher`: priority order, configured never falls through, newest nvm/mise, `.disabled` without probe; `NpmDetectionStore` single-flight and request keying |
| 1 | BrewClient | `NpmPayload` exit matrix (0, 1+parseable, 1+garbage, 2, cancelled, offline stderr); decoders on fixtures; `installedPackages()` projection (fresh/notChecked/failed → `snapshotOutdated`); `InstalledStore` recomposition (brew absent keeps npm, ordering rank, `outdatedIDs` union); argv tests for `ls`/`outdated` mirror `InstalledArgvTests`; `PackageTarget(.npm) == nil`; `BulkSelection` excludes npm from `upgradable` |
| 1 | App | `InstalledFilterBar` Source chip disabled reasons; Settings group hidden state (`cellarTests`) |
| 2 | BrewProcess | `BrewRunner(executableURL:environment:)` uses the closure and URL; convenience init byte-identical to today (existing suites unchanged) |
| 2 | BrewClient | `NpmCommand` argv exactness, `latestSpec` validation (scoped names pass, `@`-in-name rejected), structural scan passes; `classify` EACCES/EPERM; `AnyBrewMutation` copies `source`; `displayCommand` prefix; `OperationCenter` picks runner by source, missing npm runner → `.launchFailed`, cross-source chain order, cancel of chain-queued item; `.npmInventory` gate opens/ends once; history draft carries npm kind; `HistoryPresentation` label |
| 3 | BrewClient/App | `NpmRefreshCoordinator` cadence with fake `Clock` (activation never runs `outdated`; interval honoured); copy projections for `.notChecked`/`.failed` never equal "up to date"; Home/menu bar/Health copy tests |
| all | Integration | Existing brew integration suites unchanged; optional npm smoke test skipped when `/opt/homebrew/bin/npm` is absent |

## Threat Matrix

| Boundary | Cases | Applicability | Design response | Planned RED tests |
|---|---|---|---|---|
| Documentation-like paths | — | N/A: no file classification or execution of user files | — | — |
| Git repository selection | — | N/A: no VCS automation | — | — |
| Commit state | — | N/A | — | — |
| Push state | — | N/A | — | — |
| PR commands | — | N/A | — | — |
| Argument composition (added) | scoped name, `-flag` name, whitespace, `name@1` from a hostile `ls` payload | Applicable | `NpmPackageTarget` failable init; fixed argv vectors; no interpolation in `arguments` | one test per rejected shape; structural scan |
| Environment composition (added) | GUI PATH without node; leaked parent vars | Applicable | `NpmEnvironment.processEnvironment` allow-list | structural env test |
| Exit-code semantics (added) | exit 1 with JSON, exit 1 without, exit 2 | Applicable | `NpmPayload` adapter | exit matrix test |
| Untrusted subprocess payload (added) | stderr interleaved, truncated JSON, unknown keys | Applicable | decoders throw `.malformedPayload`; stderr never enters the document | decoder fixture tests |

## Work Units, Estimates, Rollback

| Unit | Scope | Est. changed lines | Rollback |
|---|---|---|---|
| 1 Read-only inventory | D1, D2, D3, D5–D9, D15 toggle/path, chip, pill | 2,000–2,400 | Revert unit commits; `"npm"` history rows decode to nil and hide; toggle default off means no runtime change for existing users |
| 2 Mutations | D4, D11–D14, history/activity wording | 1,600–2,000 | Revert; `BrewRunner` convenience init keeps every caller compiling; gate entry removal restores four domains |
| 3 Copy and offline states | D10 cadence, Home/menu bar/Health/empty-state copy | 600–900 | Revert; unit 1+2 remain functional with brew-only copy |

Total 4,200–5,300 lines against the 8,000 budget the orchestrator set (config still says 5,000; tasks must forecast against both).

## Migration / Rollout

No migration. Feature is dark until the Settings toggle is on and npm is detected.

## Open Questions

- [ ] Initial `ActivityItem.queuePhase` for a chain-queued item (D13): confirm it renders as "queued" without a runner snapshot; otherwise set it explicitly in `perform`.
- [ ] Whether `npm` and `corepack` themselves should be listed (default: listed; they are global packages).

## Deviations (appended at archive, 2026-08-30)

Nine decisions in this document were superseded during apply. **Every one of them was driven by the
delta spec text**, which is authoritative over the design when the two disagree; each was located and
accepted during verification, and none is an unreviewed drift. Recorded here so a future reader of the
archived design is not misled by a decision the shipped code does not implement.

| # | Design said | Shipped instead | Driven by |
|---|---|---|---|
| 1 | D12/D14 bare history verbs `upgrade`/`uninstall` | namespaced `npmUpgrade` / `npmUninstall` | `installation-history` delta requires namespaced verbs |
| 2 | D7 network stderr maps onto an existing failure | new `MutationOutcome.networkUnavailable` case | `npm-source` NS9 requires network errors to be their own classified outcome |
| 3 | bulk expansion returns concrete commands | `commands(for:over:)` returns `[AnyBrewMutation]` | `package-mutation` PM12 fans out **per package by source**, which needs the erased form |
| 4 | history presentation carries a source badge only | badge **plus** an `npm` prefix on the command line | `installation-history` delta requires a source-aware `displayCommand` |
| 5 | Home copy composed inline | new `cellar/Home/HomeAttentionCopy.swift` | `installed-inventory` II19 — the inline version could not express "brew clean, npm not checked" |
| 6 | empty state keyed off inventory emptiness | `InstalledEmptyState.isNpmEmptiness` | II18's typed-reason rule: an npm-shaped emptiness must say why |
| 7 | Browse projection gains a source predicate | `InstalledBrowse.withNpmSource` | II18 makes the Source filter a `CellarCore` projection, not a view-level filter |
| 8 | D-level Health wording only | Health score denominator is **Homebrew-only** in both directions | `system-health` SH12 states the score counts Homebrew identities only |
| 9 | MB1 keeps three pure inputs | `MenuBarProjection` gains a **sixth** member for npm freshness | `menu-bar` MB1 as modified by this change requires the npm freshness input |

**One defect in unit 1 was found and fixed by unit 3's integration pass**, not by a spec change:
`DefaultNpmLocator` resolved symlinks before composing the environment, so the PATH prepend pointed at
the resolved target rather than the selected npm's own bin directory. The fix stores
`NpmEnvironment.binDirectory` and makes `DefaultNpmLocator.validate` take the **candidate** directory.
This is a genuine bug fix, not a design deviation, and it is the reason unit 3 came in at roughly twice
its line estimate.

**The two open questions above were answered during apply.** A chain-queued item keeps
`queuePhase == .pending` and reads "Queued" with no explicit assignment in `perform`, so D13 needed no
fallback. `npm` and `corepack` are listed, as the default anticipated.

**The line estimate was wrong in both directions.** Unit 1's production estimate held; unit 2 came in
far under (~415 changed production lines) because the shared spine absorbed npm through existing seams;
unit 3 came in at roughly 2x. Final staged production total: **3,742 lines**, inside the 8,000 budget
under the maintainer's production-only ruling (Engram `#7968`).
