# Apply Progress — npm-package-source

## Batch 1 — Unit 1 (tasks 1.1–1.28) — complete 2026-08-29

- Branch: `feat/npm-package-source` (uncommitted working tree).
- All 28 unit-1 tasks marked complete in `tasks.md` (fixtures, `PackageKind.npm` + `PackageSource`, switch arms + audit, `NpmEnvironment`, npm locator/detection/store, payload source + decoders, `NpmStore` → `InstalledStore`, `PackageTarget` rejection, Settings toggle default off, Source chip, NPM tag, empty states).
- Verification (orchestrator re-run): `swift test --package-path Packages/CellarCore` → 2037 tests in 232 suites passed, 1 known issue (pre-existing).
- App-target xcodebuild tests: not yet run in that batch; scheduled with task 3.11.
- No `cellar.xcodeproj` edits.
- Note: the apply worker was interrupted by a provider rate limit after reporting green; this file was written by the orchestrator from on-disk state.

## Batch 2 — Unit 2 (tasks 2.1–2.18) — complete 2026-08-29

Mode: **Strict TDD** (RED → GREEN → TRIANGULATE → REFACTOR per task).
Delivery: `single-pr` with accepted **size:exception** (8,000-line budget).
Baseline safety net before starting: 2037 tests / 232 suites passing, 1 known issue.

### TDD cycle evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 2.1 / 2.2 | `BrewProcessTests/RunnerGeneralisationTests.swift` | Unit | 162/162 BrewProcess | Written (compile failure: no such init) | Passed 6/6 | 6 cases (read, mutate, overrides, brew convenience, two distinct runners, source scan) | None needed |
| 2.3 / 2.4 | `BrewClientTests/NpmCommandTests.swift` | Unit | N/A (new file) | Written | Passed 11/11 | 7 rejected name shapes + scoped-name case | None needed |
| 2.5 / 2.6 | `BrewClientTests/NpmClassificationTests.swift` | Unit | N/A (new file) | Written | Passed 9/9 | 4 network codes, 2 privilege codes, 4 brew signatures, both containment directions | None needed |
| 2.7 / 2.8 | `BrewClientTests/MutationSourceProjectionTests.swift` | Unit | 2070/2070 | Written | Passed 10/10 | 6 erased families + brew/npm outcome copy | None needed |
| 2.9 / 2.10 | `BrewClientTests/NpmInvalidationTests.swift` | Unit | 2080/2080 | Written | Passed 6/6 | 3 terminal outcomes + the brew mirror image | None needed |
| 2.11 / 2.12 | `BrewClientTests/OperationCenterSourceRoutingTests.swift` | Unit | 2062/2062 | Written | Passed 8/8 | both attach/detach directions, both missing-runner directions | None needed |
| 2.13 / 2.14 | `BrewClientTests/CrossSourceFIFOTests.swift` | Unit | 2080/2080 | Written (7 behavioural failures) | Passed 7/7 | both orders, 3-way chain, cancel mid-chain, reads unblocked | Shipped cancel-race test restated |
| 2.15 / 2.16 | `BrewClientTests/NpmBulkSelectionTests.swift` | Unit | 2093/2093 | Written (12 failures) | Passed 7/7 | upgrade + uninstall fan-out, both entry points, eligible sets, grouped upgrade | None needed |
| 2.17 / 2.18 | `PersistenceTests/NpmHistoryTests.swift` | Unit | 2100/2100 | Written | Passed 8/8 | npm vs brew presentation, 5 search terms, unknown kind | None needed |

### Work unit evidence

| Evidence | Value |
|---|---|
| Focused test command and result | `swift test --package-path Packages/CellarCore` → **2108 tests in 241 suites passed**, 1 known issue (the same pre-existing one) |
| Runtime harness command and result | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` → **306 tests passed, 0 failed**; `xcodebuild build` clean |
| Rollback boundary | Delete `Sources/BrewClient/NpmCommand.swift` and the ten new test files; revert the ten touched source files. The `BrewRunner(installation:)` convenience initializer keeps every caller compiling, removing the fifth gate entry restores four domains, and `BulkSelection.upgradable` returns to its shipped filter. No schema, no `.xcodeproj`, no migration. |

### What each task delivered

- **2.1 / 2.2** — `BrewRunner` generalised over `executableURL` plus an injected `@Sendable (Set<BrewEnvironment.CommandOverride>) -> [String: String]` composer; the four spawn sites read them. `init(installation:)` preserved as a delegating initializer, and the structural test pins that `BrewEnvironment.current(` is reached exactly once in the file.
- **2.3 / 2.4** — `Sources/BrewClient/NpmCommand.swift` at the top level, so the shipped structural argv scan covers it. `NpmPackageTarget` is failable on `kind == .npm`, `MutationName.isSafe` and the `@`-only-at-index-0 rule; `latestSpec` is built once in that initializer, so the `arguments` body carries no interpolation. Vectors are `install -g <spec>` and `uninstall -g <name>`. Added `InvalidationScope.npmInventory` (`1 << 4`) and `BrewMutating.source` (default `.homebrew`).
- **2.5 / 2.6** — `NpmCommand.classify` reads npm's own codes on the stderr tail only: `EACCES`/`EPERM` → `.needsPrivileges`, the four network codes → `.networkUnavailable`, everything else `.failed(status:)`. Faults, cancellation and exit 0 are decided before any prose.
- **2.7 / 2.8** — `AnyBrewMutation` stores and copies `source`; `displayCommand` derives its prefix from `source.commandName`; `MutationOutcome.message(for:)` names the source through the new `PackageSource.displayName`; `ActivityItem.source`.
- **2.9 / 2.10** — `RefreshDomain.npmInventory` and its `MutationGates.domain(for:)` arm; `cellarApp.swift` registers the fifth `InstalledMutationGate` (`npmMutations`) and calls `operations.attach(npm:)` beside `attach(installation:)`.
- **2.11 / 2.12** — `OperationCenter` holds `runners: [PackageSource: BrewRunner]` and `executables: [PackageSource: URL]`; `attach(npm:)`; `launcherFactory` re-keyed to `(URL) -> any ProcessLaunching`; `isAvailable(for:)` / `unavailableGuidance(for:)` per source, with the shipped source-free properties still answering for Homebrew alone.
- **2.13 / 2.14** — centre-level `mutationTail` chain: one mutation at a time across sources, in submission order. `ActivityItem.isChainQueued` distinguishes "waiting at the centre" from "start in flight", so cancelling a chain-queued item settles `.cancelled` at once and never spawns. **The D13 open question is answered: a chained item keeps `queuePhase == .pending` and reads as "Queued" without any explicit assignment in `perform`**, because the centre writes phases only for ids a runner snapshot carries. The fallback was not needed.
- **2.15 / 2.16** — `commands(for:over:)` now returns `[AnyBrewMutation]` and expands upgrade and uninstall **by source** in selection order; `submitUpgrades(for:)` does the same. Pin and unpin stay formula-only by construction. `BulkSelection.upgradable` excludes npm (maintainer decision: npm applies per package / select-all under the Updates lens); `uninstallable` deliberately does not. The grouped `upgradeAll` is untouched — one item, argv `["upgrade"]`, no npm fan-out.
- **2.17 / 2.18** — `HistoryRecord.source` (derived from the stored `kindRaw`), `sourceLabel`, `displayCommand`, and a source-aware `outcomeLabel` in exactly the two places the source changes the meaning (`failed`, `needsPrivileges`); Homebrew's wording is byte-identical. `HistoryRow` renders the badge and the prefixed command, and copies the prefixed command.

### Order deviation

2.11/2.12 were implemented **before** 2.7/2.8 because the source-projection suite asserts an npm `ActivityItem`'s copy text while pending *and* terminal, which needs `attach(npm:)` to exist. Both pairs kept their own RED → GREEN cycle.

### Design deviations recorded

1. **npm verbs are namespaced.** Design D14 says `verb` is `"upgrade"`/`"uninstall"`; the `installation-history` delta requires `npmUpgrade`/`npmUninstall`. The spec won. Search still matches the bare terms because `localizedStandardContains` is a case-insensitive substring test.
2. **`MutationOutcome.networkUnavailable` is a new case.** D14 routes the network path to `.failed(status:)`, but `npm-source` requires a *message* that names a network reason, and this type builds every message from Cellar's own vocabulary rather than from subprocess bytes — so the classification has to carry the fact. Ripple: `isFailure`, `summaryLabel`, `message(for:)`, `SwiftDataHistoryRecorder.classify` (`"networkUnavailable"`, no status) and `HistoryRecord.outcomeLabel` ("No network").
3. **`commands(for:over:)` returns `[AnyBrewMutation]`** rather than `[MutationCommand]`. A return type naming brew's enum could only have dropped npm members silently. All shipped call sites read `.verb`/`.arguments`, which the erased type carries.
4. **`HistoryRow` was touched** (an app-target view) so the npm prefix and badge actually reach a person. Brew rows now read `brew upgrade --formula wget` instead of the bare argv, which matches what the Activity surface has always copied.

### Shipped-test changes (deliberate, each annotated in place)

- `MutationCommandTests` — the spine's command-family census now includes `NpmCommand.swift`.
- `TrustGrantRefreshTests` — `InvalidationScope` has five members; the brew-only union is still `0b1111`.
- `OperationCenterCancelTests` — the cancel-racing-submission test now asserts the stronger property the chain gives it: the item settles immediately and spawns nothing, instead of being replayed.

### Gotcha discovered

SwiftPM incremental builds in this package do **not** reliably rebuild dependent modules after a layout-affecting change (adding a stored property to an actor, adding an enum case, changing a closure's parameter type). Symptoms seen: `SIGBUS`/`SIGSEGV` in the test host, an undefined-symbol link failure, and a `switch` mapping `.cancelled` to `"noChange"`. Run `rm -rf Packages/CellarCore/.build` before verifying any such change.

### Known flake (pre-existing, not this change)

`CatalogFootprintTests/"The full-catalog footprint stays within its recorded bound"` measured `residentBytes → -186658960` once under full-suite parallel load and passed alone immediately after. Unrelated to this unit.

## Batch 3 — Unit 3 (tasks 3.1–3.11) — complete 2026-08-30

Mode: **Strict TDD**. Delivery: `single-pr` with an accepted `size:exception`. Chain strategy: `none`.
Branch `feat/npm-package-source`, uncommitted. All 11 unit-3 tasks ticked; **0 tasks remain in
`tasks.md`** across all three units.

### Delivered

- **3.1 / 3.2 — the cadence.** `BrewClient/NpmRefreshCoordinator.swift`: two cadences on one injected
  `Clock`. `ls -g` runs on detection, on every npm terminal and on app activation; `outdated -g` runs on
  detection, on npm terminals, on an explicit refresh and on a one-hour floor — **never** on activation.
  A check in flight absorbs overlapping requests (`outdatedCheck` task, niled on settlement, so a later
  request runs fresh); a failed check is left failed until the next tick, so nothing retries in a loop.
  App wiring in `cellarApp.swift`: a fifth `loops.start("npm")` terminals consumer, an
  `onChange(of: npmDetection.state, initial: true)` that is the only thing starting or stopping the
  cadence, and `refreshNpm()` pushing the stored preference into `NpmDetectionStore` at launch —
  previously nothing did, so an enabled source stayed dark until Settings was opened.
- **3.3 / 3.4 — the copy.** `BrewClient/NpmFreshnessCopy.swift`: `NpmOutdatedState.notCheckedCopy`
  (absent on `fresh`, and one sentence per non-answer, each carrying the literal `npm not checked`),
  `NpmInventoryError.notCheckedReason` (never the subprocess's own bytes), and on
  `InstalledUpdatesSummary`: `upToDateLabel`, `upToDateCopy` (**absent** whenever it may not be said),
  `npmNotCheckedCopy`, `npmUpgradeScopeNote`/`npmUpgradeScopeCopy`.
- **3.5 / 3.6 — the menu bar.** MB1's fourth pure input landed as
  `MenuBarProjection(browse:metadata:services:npmFreshness:)`, defaulted so every brew-only call site is
  unchanged. It stores the `InstalledUpdatesSummary` and exposes `upToDateCopy`, `npmNotCheckedCopy` and
  `npmUpgradeDisclosure`. `MenuBarPopoverView` no longer owns the literal `"Everything is up to date"`;
  it reads the projection and renders the disclosure beside `Upgrade all`. MB4 is untouched: the verb is
  still bare `brew upgrade` with no fan-out.
- **3.7 / 3.8 — Health, copy only.** `HealthComposition.outdated(browse:metadata:npmFreshness:)` scores
  over **Homebrew identities only** in both numerator and denominator, while the row announces the merged
  count plus npm's disclosure. `HealthCopy.outdatedSummary` gained two absent-by-default clauses and
  `HealthCopy.inputName(.outdated)` became `"Outdated Homebrew packages"` so the breakdown entry says what
  the points are about. The remediation is untouched and asserted to claim nothing about npm.
- **3.9 / 3.10 — Home and the empty list.** `BrewClient.OutdatedKindBreakdown` counts by kind with an
  explicit arm each and no `default:`. `cellar/Home/HomeAttentionCopy.swift` (new) owns the outdated
  card's title and subtitle and the greeting's currency claim; `HomeView` now reads both. Two live
  defects closed: the card counted formulae and called **everything else a cask** (an npm global was
  announced as a cask), and the greeting claimed "Everything on this Mac is current." from an empty
  attention list even with an unreachable npm registry. `InstalledEmptyState.isNpmEmptiness(...)` extracts
  the branch from `body` so it is provable without a window.
- **3.11 — integration and UI.** `NpmIntegrationTests` in `BrewProcessTests/BrewIntegrationTests.swift`:
  read-only, `.enabled(if: hasRealNpm)`, `.tags(.realNpm)`, covering detection's real triple, a real
  `ls -g --json --depth=0` decode with no ESC byte, and `/bin/echo` rejection. `outdated -g` is
  deliberately excluded — it is the one read needing the network. The five shipped
  `BrewIntegrationTests` are unchanged. `cellarUITests/NpmSourceToggleUITests.swift` drives the whole
  chain: off → chip and tag absent; on → Settings reports a detected npm, the Source chip appears, a row
  carries the NPM tag; off again → both vanish. It skips when `/opt/homebrew/bin/npm` is absent and
  leaves the preference off.

### Defect found and fixed by the integration pass (unit-1 code)

The UI flow failed at the first hop: a GUI-launched Cellar reported **"npm not detected"** on a Mac with
npm plainly installed.

- **Cause.** `DefaultNpmLocator` resolves symlinks before validating, and on a Homebrew `node` install
  `/opt/homebrew/bin/npm` resolves two hops to `lib/node_modules/npm/bin/npm-cli.js`. `NpmEnvironment`
  derived `binDirectory` from `executableURL`, so the `PATH` prepend prepended
  `…/npm/bin` — a directory containing no `node`. npm is a `#!/usr/bin/env node` script, so both
  validation probes failed for any process whose inherited `PATH` lacks `node`. Reproduced outside the
  app: `env -i PATH=…/npm/bin:/usr/bin …/npm-cli.js --version` → `env: node: No such file or directory`.
- **Fix.** `NpmEnvironment.binDirectory` is now **stored**, exactly as design D5 lists it, and defaults to
  the executable's own directory. `DefaultNpmLocator.validate` takes it explicitly and both call sites
  pass the **candidate's** directory (the one the user's shell resolves `node` from), so identity still
  follows the symlink and the launch directory does not. Both validation probes run under that `PATH`.
- **Evidence.** Two RED tests in `NpmLocatorTests` (`aSymlinkedCandidateKeepsItsLaunchDirectory`,
  `aPlainCandidateKeepsItsOwnDirectory`) failed with
  `binDirectory.path → "/opt/homebrew/lib/node_modules/npm/bin"` before the fix. The UI flow passes after it.
- **Spec conformance.** NS4's scenario expects `PATH` to begin with the *candidate's* directory
  (`/Users/u/.volta/bin:`); the fix restores that, and D5 lists `binDirectory` as a member rather than a
  derivation. Neither spec nor design ever asked for symlink resolution to feed the environment.

### Deviations from design

1. `HomeAttentionCopy` and `InstalledEmptyState.isNpmEmptiness` are new app-target extraction points D16
   does not name. D16 says the app layer is "view wiring only"; two user-visible *claims* were literals
   inside `body` and therefore untestable, so the decisions moved out and the rendering stayed.
2. `InstalledBrowse.withNpmSource(_:)` was added so `cellarApp`, `HomeView` and `HealthView` keep the
   one browse expression `MenuBarCompositionTests` T7 pins across surfaces while still carrying npm
   availability. No call site's literal changed.
3. `HealthComposition.outdated` denominator is Homebrew-only as well as the numerator. The spec says the
   score's outdated input is Homebrew-only; scoring `homebrewOutdated / mergedInstalled` would still have
   let npm move the number, which the "ignores npm in both directions" scenario forbids.
4. `MenuBarProjection` stores an `updates` summary, so MB1's Mirror-based roster test grew a sixth
   member. Restated in place, not relaxed: the sweep proving no member is a store/launcher/session/clock
   is unchanged.

### Shipped tests changed (annotated in place)

- `MenuBarProjectionTests` — the stored-property roster gained `updates` (MB1 is *modified* by this
  delta into a strict superset).
- `BrewIntegrationTests` — no shipped assertion changed; the npm suite was appended.

### Verification

| Command | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **2127 tests / 244 suites passed**, 1 known issue (baseline 2108 / 241) |
| `xcodebuild test … -scheme cellar` | `** TEST SUCCEEDED **` — cellarTests **328 passed / 0 failed** (baseline 306); cellarUITests `Executed 38 tests, with 0 failures`, including `NpmSourceToggleUITests` (37.3 s) |
| `swiftlint` on changed files | No project config exists; the codebase already violates many defaults. Two findings introduced by this batch were fixed (`HomeView` type-body length back under the error ceiling via a `private extension`; one 121-character line). Nothing else new. |

New app suites: `MenuBarNpmCompositionTests` (8), `HealthNpmCompositionTests` (6),
`HomeNpmCompositionTests` (8). New package suites: `npm refresh cadence` (7), `npm freshness copy` (7),
`Real npm integration` (3), plus 2 in `npm detection`.

### Localization

No `Localizable.xcstrings` exists. The only catalog is `cellar/InfoPlist.xcstrings`, which holds three
Info.plist keys in **English only** — there is no Spanish UI localization to extend. Every UI string in
this app is a Swift literal, and the new ones follow that convention. **No catalog entries are needed.**

### Size

`git diff --cached --shortstat` over the whole change: **127 files, 11,890 insertions, 174 deletions**.
Excluding `openspec/` artifacts (1,447): **10,443 insertions** of code, tests and fixtures. Unit 3
contributed roughly **2,060** of those. The cumulative tree is therefore **well past the accepted 8,000
budget**; unit 3 alone is ~2× its ~950-line forecast, largely from the three appended app-test suites and
the defect fix. Flagged for the maintainer rather than absorbed.

### Rollback boundary

Unit 3 reverts to a working units 1+2 by deleting `NpmRefreshCoordinator.swift`, `NpmFreshnessCopy.swift`,
`HomeAttentionCopy.swift`, `NpmRefreshCoordinatorTests.swift`, `NpmFreshnessCopyTests.swift` and
`NpmSourceToggleUITests.swift`, and reverting the `npmFreshness`/`withNpmSource` arguments (all defaulted,
so every call site compiles without them). The `NpmEnvironment.binDirectory` fix should **not** be
reverted with it: without it the source cannot be detected from a GUI launch at all.

### Index state

`git add -A` staged the change (matching what units 1–2 did with their new files). `PRD.md` and
`cellar/InfoPlist.xcstrings` were unstaged again — both were modified before this change and are not
part of it. Nothing was committed.

## Remediation — C1 (verify blocker) — complete 2026-08-30

**Blocker**: verify-report C1 — `brew-detection` BD-A1 **scenario 2** ("The two evaluations do not
couple") had no covering test. Scenario 1 was covered; the non-coupling claim was not exercised anywhere.
Work unit `remediate-c1-bd-a1-scenario-2`, attempt authority acquired (`state: proceed`), not settled here.

**Scope**: one additive unit test plus the `tasks.md` wording that let the gap through. **No production
change** — none was needed, and none was made.

### What was added

`Packages/CellarCore/Tests/BrewProcessTests/NpmDetectionStoreTests.swift` gains
`heldNpmEvaluationDoesNotCoupleToBrewDetection` — *"A held npm evaluation neither delays a brew
transition nor republishes brew when released"* — plus a private `brewDetected` fixture. The test:

1. Starts an npm evaluation against a **gated** `FakeNpmLocator` and waits until the probe is genuinely
   in flight (`waitForCalls(atLeast: 1)`); the gate stays shut.
2. Registers `withObservationTracking` on `brew.state`, runs `brew.refresh()` against a separate
   `FakeBrewLocator`, and asserts brew reached `.detected` with **exactly one** observed transition —
   while `npmLocator.callCount == 1` and `npm.state == .disabled` prove the npm evaluation had still not
   answered. That is the "brew observers receive their transition before the npm evaluation is
   released" half.
3. Registers a **second** tracking closure (`withObservationTracking` is single-shot, so a fresh
   registration is required for the second phase), releases the npm gate, awaits the npm evaluation, and
   asserts npm published its own transition while brew saw **zero** republications and `brewLocator`
   was never called again. That is the "releasing npm republishes no brew state" half.

The fixture is built locally rather than shared with `BrewDetectionStoreTests` on purpose: the claim
under test is that the two detections stay strangers, and a shared fixture is the first thing that would
quietly tie them together.

`tasks.md` task 1.11 previously read "brew detection vocabulary untouched", which tagged BD-A1 but named
only scenario 1 — the gap traced back to the task text, so the text now names both scenarios explicitly.

### TDD cycle evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| C1 (task 1.11) | `BrewProcessTests/NpmDetectionStoreTests.swift` | Unit | 11/11 green before the edit | Approval test — see note | 12/12 focused, 2128/244 full | 2 phases (held / released) | None needed |

**RED note.** This is the `strict-tdd.md` **Approval Testing** path, not a new-behaviour cycle: the
production code was already correct, so an honest first run is GREEN and forcing a synthetic RED would
have required inventing coupling in production that the change never had. Instead the assertions were
proved non-vacuous by a **teeth check**: the four load-bearing expectations were temporarily inverted and
the suite re-run, producing exactly four failures with the real observed values —
`brewTransitionsWhileNpmIsHeld → 1`, `npmLocator.callCount → 1`, `npm.state → .disabled`,
`brewRepublicationsAfterRelease → 0`. The file was then restored byte-for-byte from a scratchpad copy and
re-run green. Every assertion is therefore determined by production execution, not by a setup that never
ran the code path.

### Work unit evidence

| Evidence | Result |
|---|---|
| Focused test command | `swift test --package-path Packages/CellarCore --filter NpmDetectionStoreTests` → **12 tests in 1 suite passed** (was 11) |
| Full package suite | `swift test --package-path Packages/CellarCore` → **2128 tests in 244 suites passed**, 1 known issue (pre-existing) |
| Runtime harness | N/A — the scenario's verification is `unit`, and both stores are pure in-process observables with injected locators; no process boundary is crossed |
| Rollback boundary | Delete `heldNpmEvaluationDoesNotCoupleToBrewDetection` and the `brewDetected` fixture, and revert the task 1.11 wording. Nothing else depends on either |

### Flakes observed (pre-existing, not caused by this test)

Two full-suite runs each failed one *different* load-dependent test, and both passed in isolation
immediately after: `CatalogFootprintTests` "The full-catalog footprint stays within its recorded bound"
(already recorded as a known flake in Batch 2) and `MutationRefreshReceiptTests` "Every tap terminal
refreshes its declared domains exactly once". A third full run passed clean at 2128/244. Neither suite
is touched by this remediation, which only adds a `BrewProcessTests` case.

### Index state

`Packages/CellarCore/Tests/BrewProcessTests/NpmDetectionStoreTests.swift`,
`openspec/changes/npm-package-source/tasks.md` and this file were staged with `git add`. `PRD.md` and
`cellar/InfoPlist.xcstrings` remain unstaged. Nothing was committed.

## Remaining

None. All 57 tasks across units 1-3 are ticked in `tasks.md`, and verify blocker C1 is remediated.
Next phase: `sdd-verify` (re-run against the corrected candidate).
