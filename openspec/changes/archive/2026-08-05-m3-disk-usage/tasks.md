# Tasks: M3-3 Disk Usage

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | 3,200–4,400 vs 2,000 budget; 13 new + 17 modified files |
| Actual apply changed lines | 2,264, excluding unrelated `openspec/config.yaml` and preserved M3 taps artifacts |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | WU1 → WU2 → WU3 → WU4 → WU5 → WU6; superseded by accepted `size:exception` |
| Delivery strategy | single-pr with accepted `size:exception` |
| Chain strategy | N/A — explicit size exception |

Decision needed before apply: No — the apply authority selected one bounded delivery with `size:exception`.
Chained PRs recommended: Yes, but superseded by the accepted exception for this apply.
Chain strategy: N/A — explicit size exception
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | Graph/roots/links | 1 | `swift test --package-path Packages/CellarCore --filter 'PackageGraphTests|RootsAccountingTests|InstalledDeriveTests'` | Temp roots | Manifest/roots/links |
| 2 | Accounting/events | 2 | `swift test --package-path Packages/CellarCore --filter EngineEventsTests` | Temp link tree | Measurer/engine |
| 3 | Cache/store | 3 | `swift test --package-path Packages/CellarCore --filter StoreCacheTests` | Temp cache/paused scan | Cache/store |
| 4 | Invalidation | 4 | `swift test --package-path Packages/CellarCore --filter 'MutationGatesTests|InstalledObserverTests|TapIntegrationTests'` | Fake streams | Watcher/coordinator |
| 5 | App/linkage | 5 | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarUITests` | Fixture launches | Route/views/project |
| 6 | Integration | 6 | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` | Read-only Homebrew | M3-3 |

## Phase 1: Graph, Roots, Links

- [x] 1.1 **RED:** Add `Packages/CellarCore/Tests/CatalogTests/PackageGraphTests.swift`, `Packages/CellarCore/Tests/DiskUsageTests/RootsAccountingTests.swift`, and `Packages/CellarCore/Tests/BrewClientTests/InstalledDeriveTests.swift` failures: graph edges; DU1 standard/custom/invalid/missing roots; II1–II5 keg/cask/tri-state/link cases.
- [x] 1.2 **GREEN:** Update `Packages/CellarCore/Package.swift`; add `Packages/CellarCore/Sources/DiskUsage/{HomebrewRoots,DiskUsageModels}.swift` and `Packages/CellarCore/Sources/BrewClient/InstalledDiskUsageProjection.swift`; preserve `linkedKeg` in `Packages/CellarCore/Sources/BrewClient/{InstalledModels,InstalledDecoder}.swift`.
- [x] 1.3 **SAFETY-NET:** Keep providers `Sendable`; run WU1 tree/edge proof.

## Phase 2: Accounting and Events

- [x] 2.1 **RED:** In `Packages/CellarCore/Tests/DiskUsageTests/{RootsAccounting,EngineEvents}Tests.swift`, fail DU3–DU4 metadata allocation, hardlink dedupe, unfollowed links, attribution, warnings, and events.
- [x] 2.2 **GREEN:** Add `Packages/CellarCore/Sources/DiskUsage/{DirectoryMeasuring,DiskUsageEngine}.swift` with sorted traversal, `@concurrent` scanning, cancellation, and unit progress.
- [x] 2.3 **SAFETY-NET:** Bound seams/events; run WU2 without fixed APFS bytes.

## Phase 3: Cache and Store

- [x] 3.1 **RED:** In `Packages/CellarCore/Tests/DiskUsageTests/StoreCacheTests.swift`, fail DU5–DU8 stable order/identity, adoption, generation rejection, cancellation, last-good warnings, and recovery.
- [x] 3.2 **GREEN:** Add `Packages/CellarCore/Sources/DiskUsage/{DiskUsageCache,DiskUsageStore}.swift`; persist only warning-free snapshots and separate accepted/incremental state.
- [x] 3.3 **SAFETY-NET:** Run WU3 for monotonic progress, late-event rejection, overlays, and replacement.

## Phase 4: Invalidation

- [x] 4.1 **RED:** Extend `Packages/CellarCore/Tests/BrewClientTests/{MutationGates,InstalledObserver,TapIntegration}Tests.swift` for DU9 area fan-out, package/force-untap terminals, and no disk-triggered Installed refresh.
- [x] 4.2 **GREEN:** Update `Packages/CellarCore/Sources/BrewClient/{BrewMutating,MutationRefreshReceipts,TapCommand,FSEventsInstalledObserver,InstalledChangeObserving,DiskUsageRefreshCoordinator}.swift`.
- [x] 4.3 **SAFETY-NET:** Run WU4 proving one root stream and scoped receipts.

## Phase 5: App Surface

- [x] 5.1 **RED:** Extend `cellarUITests/cellarUITests.swift` for route threat and DU2/DU5/DU8/DU10 absence, stale/progress, warning/recovery, stable expansion/sorting, “on disk,” and read-only/Installed-column exclusions.
- [x] 5.2 **GREEN:** Add `cellar/Cleanup/{CleanupView,CleanupRow}.swift`; update `cellar/Shell/AppSection.swift`, `cellar/{ContentView,cellarApp}.swift`, and `cellar.xcodeproj/project.pbxproj` for product/target linkage and routing.
- [x] 5.3 **SAFETY-NET:** Preserve IDs/sorting; run WU5 across all states.

## Phase 6: Verification and Rollback

- [x] 6.1 Run configured/read-only harnesses; record all 15 scenarios in `openspec/changes/m3-disk-usage/tasks.md`.
- [x] 6.2 Record rollback boundaries in `openspec/changes/m3-disk-usage/tasks.md`; confirm disposable cache and excluded features.

## TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 1.1–1.3 | Compile/test failures for missing `DiskUsage`, root identity, `linkedKeg`, and formula link projection. | WU1: 26 tests in 3 suites passed. | Kept graph one-way and root arithmetic in `HomebrewRoots`. |
| 2.1–2.3 | Missing engine/events and later stream-type compile failures proved batch publication was insufficient. | WU2: 2 engine-event tests passed. | Replaced buffered arrays with `AsyncThrowingStream`; retained sorted serial traversal and `@concurrent` production. |
| 3.1–3.3 | Missing cache/store APIs; store-owned scan test failed because `startScan` did not exist. | WU3: 4 cache/store tests passed. | Store now owns generation plus scan task; cancel terminates the producer and preserves accepted data. |
| 4.1–4.3 | Invalidation tests failed before `.diskUsage`, area scopes, fan-out, and receipts existed. | WU4: 13 tests in 3 suites passed. | Reused one root stream; cache-only signals do not refresh Installed. |
| 5.1–5.3 | Cleanup UI tests failed first for the absent route, then for package/disclosure accessibility semantics. | WU5: 3 focused UI tests passed. | Queries now assert semantic static text/disclosure behavior without debug printing. |
| 6.1 | Full package suite exposed 14 obsolete invalidation expectations. | 772 tests in 113 suites passed; one pre-existing known issue remained. Full Xcode command succeeded with 12 UI tests and 2 app tests visible. | Updated safety-net expectations to the intended disk invalidation contract. |
| 6.2 | N/A — documentation-only rollback evidence. | Rollback and exclusions recorded below. | Cache remains schema-versioned and disposable. |

## Work Unit Evidence

| Unit | Focused test command and exact result | Runtime harness command/scenario and exact result | Rollback boundary |
|---|---|---|---|
| WU1 | `swift test --package-path Packages/CellarCore --filter 'PackageGraphTests|RootsAccountingTests|InstalledDeriveTests'` — exit 0; 26 tests/3 suites. | Same command uses temporary standard/custom/missing root projections and exact installed payload fixtures — passed. | Revert package manifest, root/model files, installed decoder/model projection, and their tests. |
| WU2 | `swift test --package-path Packages/CellarCore --filter EngineEventsTests` — exit 0; 2 tests/1 suite. | Temporary Cellar/Caskroom/cache tree with real metadata traversal — passed; no fixed APFS byte assumption. | Revert `DirectoryMeasuring.swift`, `DiskUsageEngine.swift`, and engine/accounting tests. |
| WU3 | `swift test --package-path Packages/CellarCore --filter StoreCacheTests` — exit 0; 4 tests/1 suite. | In-memory cache plus controlled live stream exercises partial data, late generations, and producer cancellation — passed. | Revert cache/store files and `StoreCacheTests.swift`. |
| WU4 | `swift test --package-path Packages/CellarCore --filter 'MutationGatesTests|InstalledObserverTests|TapIntegrationTests'` — exit 0; 13 tests/3 suites. | Fake mutation terminals and one fake root stream exercise scoped fan-out/receipts — passed. | Revert disk invalidation bits/areas, refresh coordinator, observer fan-out, and associated test expectations. |
| WU5 | Focused `xcodebuild test ...` selecting the three Cleanup tests — exit 0; 3 tests, 0 failures. | Fixture launches covered valid, absent, warning, expansion, stale, and Installed exclusion states — passed. | Revert Cleanup views/route, fixtures/UI tests, app wiring, and Xcode `DiskUsage` linkage. |
| WU6 | `swift test --package-path Packages/CellarCore` — exit 0; 772 tests/113 suites, 1 known issue. `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` — exit 0; full command succeeded. | Full package run included the read-only Real Homebrew integration suite; full app run executed 12 UI tests plus 2 app tests with no failure. | Revert the complete M3-3 file set only; leave M3 taps and unrelated OpenSpec configuration untouched. |

## Scenario Evidence

| ID | Scenario | Evidence | Result |
|---|---|---|---|
| DU1 | Validated roots remain independent | `RootsAccountingTests`, `EngineEventsTests` temporary roots | Pass |
| DU2 | Brew is unavailable | `testCleanupAbsenceWarningsAndReadOnlyBoundary` absent fixture | Pass |
| DU3 | Accounting remains safe and honest | Metadata allocation, hard-link dedupe, symlink non-following tests plus read-only UI assertions | Pass |
| DU4 | Attribution is exact | `EngineEventsTests` formula/cask/version/link-state assertions | Pass |
| DU5 | Incremental rows remain deterministic | Snapshot sorting plus Cleanup expansion/identity UI test | Pass |
| DU6 | Cache adoption is complete and atomic | `StoreCacheTests.cacheAdoptionMatchesRoots` and completion persistence test | Pass |
| DU7 | Cancellation stays responsive | Store-owned controlled stream cancellation, monotonic progress, late-generation rejection | Pass |
| DU8 | Failure and recovery are explicit | Partial snapshot/recovery store test and warning fixture UI test | Pass |
| DU9 | Invalidation stays scoped | Mutation gates, installed observer fan-out, and tap integration tests | Pass |
| DU10 | Storage remains read-only | Cleanup warning/read-only and Installed no-size-column UI tests | Pass |
| II1 | A single-keg formula decodes | `InstalledDeriveTests` carried single-keg fixture | Pass |
| II2 | A multi-keg formula keeps every keg | `InstalledDeriveTests` multi-keg fixture | Pass |
| II3 | A cask string installed version decodes | `InstalledDeriveTests` cask fixture | Pass |
| II4 | Auto-update declaration remains tri-state | `InstalledDeriveTests` true/null/absent assertions | Pass |
| II5 | Linked-keg absence remains unlinked | Exact absent/older-linked-keg projection assertions | Pass |

## Rollback and Exclusion Confirmation

- The autonomous rollback boundary is the M3-3 files listed in WU1–WU6; no M3 taps artifact or unrelated `openspec/config.yaml` content is part of it.
- Removing `.cleanup`, app linkage, `DiskUsage` product/target, and the inward BrewClient invalidation bridge restores the prior product behavior.
- The cache is schema-v1 derived data; rollback may delete it or leave it inert with no user-data migration.
- The shipped surface remains read-only: no cleanup action, recommendation, dry-run interpretation, reclaimable claim, or Installed size column was added.
