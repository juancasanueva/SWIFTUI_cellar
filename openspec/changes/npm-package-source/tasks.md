# Tasks: npm as a second package source (`npm-package-source`)

Inputs: spec (obs #7972, 9 capability files), design (obs #7971, D1–D16), gate notes (obs #7973), decisions (obs #7968).
Strict TDD: every behavioural task is a RED task followed by its GREEN task. Package tests run with
`swift test --package-path Packages/CellarCore`; app tests with
`xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
Size note: this artifact exceeds the 530-word default because the orchestrator asked for per-task test
files, requirement links, production files and estimates. The Review Workload Forecast is the last block.

## Requirement ID map

Spec headings carry no short IDs; these IDs are used below and follow file order.

| ID | Requirement |
|---|---|
| NS1–NS10 | `specs/npm-source`: 1 opt-in/off, 2 priority, 3 detected state, 4 environment, 5 `ls -g`, 6 outdated tri-state, 7 cadence, 8 commands/argv, 9 classification, 10 gated mutations |
| II-A1–A3 | `specs/installed-inventory`: 1 one inventory, 2 Source filter + npm tag, 3 per-source summary |
| PM-A1–A3, PM7 | `specs/package-mutation`: A1 source projection, A2 no brew argv names npm, A3 one FIFO, PM7 (MODIFIED) availability per source |
| BE-A1 | `specs/brew-execution`: runner generalised |
| OA-A1 | `specs/operation-activity`: items carry source |
| IH-A1 | `specs/installation-history`: npm entries and presentation |
| BD-A1 | `specs/brew-detection`: sibling detection, brew vocabulary unchanged |
| MB-A1, MB1 | `specs/menu-bar`: A1 count + not-checked copy, MB1 (MODIFIED) pure inputs |
| SH-A1 | `specs/system-health`: outdated row copy, score Homebrew-only |

---

## Phase 1 — Unit 1: identity, detection, read-only inventory, Settings, chip, tag (PR 1)

- [x] 1.1 Capture npm fixtures into `Packages/CellarCore/Tests/BrewClientTests/Fixtures/Npm/`: `version.stdout`, `prefix-g.stdout`, `ls-g-depth0.json`, `ls-g-problems.{stdout,stderr}` (exit 1), `outdated-g.json` (exit 1), `outdated-g-none.stdout` (exit 0), `outdated-g-offline.stderr`, `install-g.stdout`, `install-g-eacces.stderr`, `uninstall-g.stdout`, plus `README.md` and `probe-manifest.txt` recording npm version, exact command and exit code per fixture. Read-only probes only; no production code. [NS5, NS6, NS9] ~120
- [x] 1.2 RED `CatalogTests/PackageSourceTests.swift`: `PackageSource` cases; `PackageKind.npm.source == .npm`; formula/cask → `.homebrew`; `PackageID(kind: .npm, name:)` round-trips through `kindRaw`. [II-A1] ~50
- [x] 1.3 GREEN `Catalog/CatalogModels.swift`: add `PackageSource`, `PackageKind.npm`, `kind.source`; `commandName` in a `BrewClient` extension. [II-A1] ~40
- [x] 1.4 RED `CatalogTests/NpmKindExhaustivenessTests.swift`: roster/diff/analytics/sync treat `.npm` as never present (`DiscoveryRoster.contains == false`, `AnalyticsIndex` → `nil`); `InstalledInventory.precedes` ranks formula < cask < npm; `InstalledModels.isOutdated` reads `snapshotOutdated` for npm. [II-A1] ~60
- [x] 1.5 GREEN add explicit `.npm` arms to the 10 compile-breaking switches (no `default:`): `MutationCommand.vector` (`preconditionFailure`), `InstalledModels.isOutdated`, `InstalledDetailProjection:187`, `DiscoveryRoster.contains`, `DiscoveryRosterDiff`, `AnalyticsIndex`, `InstalledInventory.precedes`, `Security/ArtifactLocator`, `Home/HomebrewUpdateNeed`, `Taps/BrewfileImportSheet`. [II-A1, PM-A2] ~80
- [x] 1.6 AUDIT (not compile-breaking, per gate notes): read `Catalog/CatalogSyncSupport.swift:16,45`, `Catalog/Wire/CaskRelationsWire.swift:33` and `cellar/Browse/CatalogFilterBar.swift:97,104` — they switch on other types. Confirm `.all` still returns `[.formula, .cask]` literally and that no `PackageKind.allCases` iteration renders an npm chip in catalog surfaces. Record findings in the PR body; add an arm only if the audit proves one is needed. [II-A2] ~10
- [x] 1.7 RED `BrewProcessTests/NpmEnvironmentTests.swift`: `PATH` = bin directory + `:` + inherited PATH; `HOME` kept; the seven pins exact (`NO_COLOR`, `npm_config_color/progress/update_notifier/fund/audit/loglevel`); nothing else inherited; no `HOMEBREW_*`. [NS4] ~60
- [x] 1.8 GREEN `BrewProcess/NpmEnvironment.swift`. [NS4] ~70
- [x] 1.9 RED `BrewProcessTests/NpmLocatorTests.swift` with `FakeExecutableProbe`, a new `FakeDirectoryEnumerator` and `FakeProcessLauncher`: priority configured → `/opt/homebrew/bin/npm` → `/usr/local/bin/npm` → Volta → fnm → newest nvm → newest mise; configured path never falls through (`invalid(notExecutable|notNpm)`, `configuredPathMissing`); `absent` is soft; only `--version` and `prefix -g` are spawned. [NS2, NS3, BD-A1] ~130
- [x] 1.10 GREEN `BrewProcess/{NpmLocation,DefaultNpmLocator,DirectoryEnumerating}.swift`. [NS2, NS3] ~170
- [x] 1.11 RED `BrewProcessTests/NpmDetectionStoreTests.swift`: while off, `.disabled` is published with zero spawns; enabling starts detection without relaunch; disabling clears state and stops the cadence; single-flight and request keying; BD-A1 scenario 1 — brew's detection vocabulary untouched; BD-A1 scenario 2 — a held npm evaluation neither delays a brew transition nor republishes brew state when released. [NS1, NS3, BD-A1] ~90
- [x] 1.12 GREEN `BrewProcess/NpmDetectionStore.swift`. [NS1, BD-A1] ~100
- [x] 1.13 RED `BrewClientTests/NpmPayloadTests.swift`: exit matrix — 0; 1 with parseable stdout (ELSPROBLEMS); 1 with garbage; 2; cancelled; offline stderr → `.networkUnavailable`. Stdout only; stderr never enters the document; unparseable non-zero is a failed acquisition, never empty. [NS5, NS6] ~110
- [x] 1.14 GREEN `BrewClient/NpmPayloadSource.swift` + `NpmInventoryError`. [NS5, NS6] ~100
- [x] 1.15 RED `BrewClientTests/NpmDecodeTests.swift` over the 1.1 fixtures: `dependencies` keys → `(npm, name)`; outdated iff `current != latest`; truncated JSON and unknown keys → `.malformedPayload`. [NS5, NS6] ~90
- [x] 1.16 GREEN `BrewClient/{NpmDecoder,NpmModels}.swift` including `NpmInventory` and the `NpmOutdatedState` tri-state. [NS5, NS6] ~130
- [x] 1.17 RED `BrewClientTests/NpmArgvTests.swift` (mirrors `InstalledArgvTests`): exactly one `ls -g --json --depth=0` and one `outdated -g --json`, no extra flags, brew JSON trio untouched. [NS5, NS6] ~40
- [x] 1.18 GREEN fix the two read argv vectors in `BrewClient/NpmPayloadSource.swift`. [NS5, NS6] ~15
- [x] 1.19 RED `BrewClientTests/NpmProjectionTests.swift`: `installedPackages()` → kind `.npm`, one keg with `installedOnRequest: true`, `catalogVersion = latest` when fresh, `snapshotOutdated` only when fresh and `current != latest`, `tap/linkedKeg/declaresAutoUpdates` nil, `isPinned` false. [II-A1, NS6] ~80
- [x] 1.20 GREEN projection in `BrewClient/NpmModels.swift`. [II-A1] ~60
- [x] 1.21 RED `BrewClientTests/NpmInstalledStoreTests.swift`: `adopt(_:from: .npm)` recomposition; brew `clear` keeps npm contributions; rank ordering; `outdatedIDs` union unchanged for the six existing consumers; per-source failure isolation; npm off omits npm rows. [II-A1, II-A3] ~100
- [x] 1.22 GREEN `BrewClient/InstalledStore.swift` (`contributions`) + `BrewClient/NpmStore.swift`. [II-A1] ~120
- [x] 1.23 RED `BrewClientTests/NpmSourceFilterTests.swift`: Source filter projection (all/Homebrew/npm) with typed unavailable reason (disabled/absent/invalid) and inert behaviour when unavailable; NPM tag derived from kind; per-source updates summary (brew count, npm count + freshness); total equals `InstalledBrowse.outdatedCount(metadata:)`. [II-A2, II-A3] ~85
- [x] 1.24 GREEN `BrewClient/InstalledFilterMode.swift` + the per-source summary value. [II-A2, II-A3] ~90
- [x] 1.25 RED `cellarTests/NpmSettingsCompositionTests.swift`: npm Settings group hidden/disabled derivation and detected path/version/prefix/origin copy come from `NpmDetectionStore`; the view holds no state logic. [NS1, NS3] ~60
- [x] 1.26 GREEN `cellar/Settings/SettingsView.swift` with `@AppStorage("npm.sourceEnabled")` (default false) and `@AppStorage("npm.configuredPath")` pushed into `NpmDetectionStore`; store wiring in `cellar/cellarApp.swift`. [NS1, NS3] ~100
- [x] 1.27 RED `cellarTests/NpmInstalledChromeTests.swift`: Source chip disabled reasons; `PackageRow.KindTag` NPM pill; `InstalledBrowse.isAvailable` is brew loaded OR npm contributing — a one-liner over store state (gate note: it lives in the app target at `InstalledListView.swift:286`). [II-A2] ~65
- [x] 1.28 GREEN `cellar/Installed/InstalledFilterBar.swift`, `cellar/Browse/PackageRow.swift`, `cellar/Installed/InstalledListView.swift:286`, `InstalledRow.swift:76`, `CaskIconView.swift:89,97`, `PackageDetailView.swift:465,607,614` (npm detail: version, latest, location; no pin/reinstall/zap/tap sections). [II-A2] ~140

## Phase 2 — Unit 2: mutations through the shared queue, activity and history (PR 2)

- [x] 2.1 RED `BrewProcessTests/RunnerGeneralisationTests.swift`: `BrewRunner(executableURL:environment:launcher:policy:clock:retainedTerminalRecords:)` spawns that URL under that composer; `init(installation:)` stays byte-identical so existing suites are untouched; runner source holds no direct brew-env reference outside the convenience init. [BE-A1] ~70
- [x] 2.2 GREEN `BrewProcess/BrewRunner.swift` (lines 151/178/212/279 read `executableURL`). [BE-A1] ~90
- [x] 2.3 RED `BrewClientTests/NpmCommandTests.swift`: argv exactness `install -g <name>@latest` and `uninstall -g <name>`; `latestSpec` is one argv element with no interpolation; scoped `@scope/name` passes; `@` after index 0, `-flag`, whitespace and `name@1` are rejected; `PackageTarget.init?` returns nil for npm; the `MutationCommand.vector` npm arm is unreachable; the structural argv scan (`MutationCommandTests:289-360`) covers the new top-level file. [NS8, PM-A2] ~150
- [x] 2.4 GREEN `BrewClient/NpmCommand.swift` (`NpmPackageTarget`, upgrade, uninstall) + the `PackageTarget.init?` guard. [NS8, PM-A2] ~150
- [x] 2.5 RED `BrewClientTests/NpmClassificationTests.swift`: exit 0 = success; EACCES/EPERM → `needsPrivileges` echoing the exact `npm …` line; ENOTFOUND/ETIMEDOUT/ECONNREFUSED/EAI_AGAIN → `failed(network)`; brew signatures never apply; the message says npm, not Homebrew. [NS9] ~90
- [x] 2.6 GREEN `classify` in `BrewClient/NpmCommand.swift`. [NS9] ~70
- [x] 2.7 RED `BrewClientTests/MutationSourceProjectionTests.swift`: `BrewMutating.source` defaults to `.homebrew`; `AnyBrewMutation` copies it through the erased type; `displayCommand` prefix is `brew`/`npm`; uninstall confirmation shows `npm uninstall -g <name>`; `MutationOutcome.message(for:)` is source-aware; an erased npm item never renders as brew; idle copy is not brew-only. [PM-A1, OA-A1, NS8] ~110
- [x] 2.8 GREEN `BrewClient/{BrewMutating,MutationCommand,MutationOutcome}.swift` + activity item source. [PM-A1, OA-A1] ~120
- [x] 2.9 RED `BrewClientTests/NpmInvalidationTests.swift`: `InvalidationScope.npmInventory` (`1 << 4`), `RefreshDomain.npmInventory`, `MutationGates.domain(for:)` mapping, exactly one open/end per npm terminal, and an npm terminal producing exactly one `ls` plus one `outdated` with zero brew re-snapshot. [NS7, NS8] ~100
- [x] 2.10 GREEN `BrewClient/MutationRefreshReceipts.swift`, `MutationGates`, `InvalidationScope`, and the fifth `InstalledMutationGate` (`npmMutations`) in `cellar/cellarApp.swift`. [NS7] ~110
- [x] 2.11 RED `BrewClientTests/OperationCenterSourceRoutingTests.swift`: `runners[.npm]` and `attach(npm:)`; a missing npm runner settles `.launchFailed` with exactly one history entry; `isAvailable(for:)`/`unavailableGuidance(for:)` are per source with npm guidance when off/absent/invalid, and brew is never gated on npm. [PM7, NS10] ~120
- [x] 2.12 GREEN `BrewClient/OperationCenter.swift` (`runners`, `executables`, `launcherFactory`). [PM7, NS10] ~130
- [x] 2.13 RED `BrewClientTests/CrossSourceFIFOTests.swift`: one FIFO across sources in submission order; reads stay unblocked during a mutation; cancelling a chain-queued item settles `.cancelled` immediately and it never runs; **and one test confirming a brew item chained at the centre reads as `queued` in `ActivityItem.queuePhase` before its turn** (D13 open question — if it does not, set `queuePhase` explicitly in `perform` and keep the test). [PM-A3, OA-A1] ~120
- [x] 2.14 GREEN the centre-level `mutationTail` chain in `BrewClient/OperationCenter.swift`. [PM-A3] ~120
- [x] 2.15 RED `BrewClientTests/NpmBulkSelectionTests.swift`: bulk expands per package by source in selection order; pin/unpin/reinstall exclude npm; grouped upgrade-all stays bare `brew upgrade` with no npm fan-out; `BulkSelection.upgradable` excludes npm (decision: npm applies per package / select-all in the Updates lens). [PM-A2, PM-A3] ~90
- [x] 2.16 GREEN `BrewClient/{BulkSelection,OperationCenterBulk}.swift`. [PM-A2, PM-A3] ~90
- [x] 2.17 RED `PersistenceTests/NpmHistoryTests.swift`: verbs `npmUpgrade`/`npmUninstall`; identity kind npm via `kindRaw`; from/to versions; argv display-only; source badge, `npm` prefix and npm-worded outcome labels; search matches npm/upgrade/uninstall/name/argv; an unknown kind decodes to absent. [IH-A1] ~120
- [x] 2.18 GREEN `Persistence/HistoryPresentation.swift` + the source-aware history draft. [IH-A1] ~110

## Phase 3 — Unit 3: cadence, Home / menu bar / Health copy, offline states (PR 3)

- [x] 3.1 RED `BrewClientTests/NpmRefreshCoordinatorTests.swift` with a fake `Clock`: `ls -g` on detection change, enable, npm terminals and activation; `outdated -g` only on terminals, explicit refresh and the minimum-interval timer (1 h); activation never triggers `outdated`; coalesced; no tight retry. [NS7] ~120
- [x] 3.2 GREEN `BrewClient/NpmRefreshCoordinator.swift` + `cellar/cellarApp.swift` wiring. [NS7] ~130
- [x] 3.3 RED `BrewClientTests/NpmFreshnessCopyTests.swift`: `.notChecked(reason)` and `.failed` never read as "up to date"; brew clean plus npm not-checked is not "up to date"; npm off omits npm from the summary entirely. [II-A3, NS6] ~70
- [x] 3.4 GREEN the summary/copy projection in `BrewClient`. [II-A3] ~60
- [x] 3.5 RED extend `cellarTests/MenuBarCompositionTests.swift`: count includes npm by delegation; `npm not checked` (+reason) replaces "up to date"; a disclosure line beside `Upgrade all` says npm packages update from the Updates list; MB4's bare `brew upgrade` and no-fan-out rule unchanged; npm off is byte-identical; MB1's four pure inputs include npm freshness. [MB-A1, MB1] ~90
- [x] 3.6 GREEN the menu-bar projection and view in `cellar/`. [MB-A1, MB1] ~80
- [x] 3.7 RED extend `cellarTests/HealthCompositionTests.swift`: the outdated row announces the merged count plus npm not-checked copy; the score's outdated input stays Homebrew-only and the breakdown says so; remediation stays brew upgrade-all and its copy does not claim npm; npm off is identical. [SH-A1] ~70
- [x] 3.8 GREEN `cellar/Health/HealthComposition.swift` + remediation copy. [SH-A1] ~60
- [x] 3.9 RED extend `cellarTests/HomeCompositionTests.swift` and cover `InstalledEmptyState`: Home's outdated card shows the merged count and the npm freshness cue; empty state distinguishes npm on with zero globals from npm off. [II-A3, NS1] ~70
- [x] 3.10 GREEN `cellar/Home/*`, `cellar/Installed/InstalledEmptyState.swift`, `cellar/Shell/SidebarView.swift`. [II-A3] ~80
- [x] 3.11 Final integration and UI pass: add an npm smoke test to `BrewProcessTests/BrewIntegrationTests.swift`, skipped when `/opt/homebrew/bin/npm` is absent (read-only `--version`, `prefix -g`, `ls -g`); confirm the existing brew integration suites are unchanged; add one `cellarUITests` flow that toggles npm on in Settings and asserts the Source chip and NPM pill appear, then vanish when toggled off. Run `swift test --package-path Packages/CellarCore` and the full `xcodebuild test` command. [NS1, II-A2, all] ~120

---

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~5,275 total (Unit 1 ≈ 2,365 · Unit 2 ≈ 1,960 · Unit 3 ≈ 950) |
| 400-line budget risk | High |
| 8,000-line project budget risk (`openspec/config.yaml`) | Medium — ~66% consumed, no single unit above 2,400 |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (Unit 1) → PR 2 (Unit 2) → PR 3 (Unit 3) |
| Delivery strategy | single-pr |
| Chain strategy | pending — `single-pr` resolves to `size-exception` only once a maintainer accepts it |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | npm identity, detection, read-only global inventory, Settings group, Source chip, NPM tag (D1–D3, D5–D9, D15, D16 read surfaces) | PR 1 | `swift test --package-path Packages/CellarCore --filter Npm` then `xcodebuild test … -only-testing:cellarTests` | Launch the app, enable the npm toggle, confirm globals list and that `probe-manifest.txt` matches the local npm version | Revert unit commits; `"npm"` history rows decode to nil and hide; toggle default off means zero runtime change for existing users |
| 2 | npm mutations through the shared runner, single cross-source FIFO, activity and history wording (D4, D11–D14) | PR 2 | `swift test --package-path Packages/CellarCore --filter 'Npm\|OperationCenter\|Mutation'` | Optional and reversible: upgrade then uninstall one small global package with the app, watch Activity ordering against a concurrent brew mutation | Revert; the `BrewRunner` convenience init keeps every caller compiling; removing the fifth gate restores four domains |
| 3 | Cadence, offline/not-checked states, Home / menu bar / Health / empty-state copy (D10, remaining D16) | PR 3 | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` | Run with networking disabled and npm enabled; confirm the menu bar and Health say "npm not checked" and never "up to date" | Revert; Units 1 and 2 stay functional with brew-only copy |

Base boundaries if the maintainer picks a chain instead of `size:exception`: PR 1 base = tracker branch,
PR 2 base = PR 1 branch, PR 3 base = PR 2 branch. If a child diff shows earlier slices, retarget or rebase first.
