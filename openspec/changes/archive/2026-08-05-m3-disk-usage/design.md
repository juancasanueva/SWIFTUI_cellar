# Design: M3-3 Disk Usage

## Technical Approach

Add a GUI-free `DiskUsage` capability that scans validated Homebrew roots with metadata, streams package/version results off-main, and exposes them through a `@MainActor @Observable` store. The app adopts a matching complete cache immediately as stale, then revalidates without surrendering the last complete snapshot. U7’s 123,966 entries/2.55 s makes persistence, cancellation, generation rejection, and unit-level publication mandatory.

## Architecture Decisions

| Decision | Choice | Alternatives / rationale |
|---|---|---|
| Dependencies | Product/target `DiskUsage -> BrewProcess, Catalog`; `BrewClient -> BrewProcess, Catalog, DiskUsage`; `Persistence -> BrewClient`; app imports all; `DiskUsageTests -> DiskUsage, CellarTestSupport`. | Putting receipts in `DiskUsage` creates a reverse edge. `BrewClient/DiskUsageRefreshCoordinator.swift` alone maps its terminal/receipt types inward. |
| Roots | `HomebrewRoots` is the sole projection: canonical prefix is two parents above the validated executable; Cellar/Caskroom derive from it; cache derives through an injected user-cache provider. Identity is standardized root paths plus schema version. | No repeated path arithmetic or new `brew --prefix/--cache`; standard/custom installations share one validated path. Each missing root is an independent `.absent` empty area. |
| Accounting | A `DirectoryMeasuring: Sendable` seam uses sorted, iterative metadata traversal with allocated (`totalFileAllocatedSizeKey`) and logical observations; it opens no contents, does not traverse symlinks/aliases, and deduplicates resource identity per root. | `du` weakens cancellation, attribution, and errors. Permission/race failures become path/root warnings, never fabricated zeroes; raw path components determine formula/cask/version. |
| Concurrency | `DiskUsageEngine.scan` is explicitly `@concurrent`, serial within roots to avoid metadata storms, checks cancellation per entry/unit, and emits `started`, `version`, `package`, `warning`, `rootCompleted`, `completed`. | Main-actor work would stall. Progress counts discovered package/version/cache units, not inodes. Store-owned generation and task reject late events; incremental state is separate from the accepted snapshot. |
| Cache/adoption | A cache actor encodes schema, root identity, timestamp, root states, packages, versions, and observations; atomic file replacement occurs only after warning-free completion. | Cancelled/partial/mismatched/older scans neither persist nor replace the last complete snapshot. Successful units may overlay visible last-good data with warnings until a complete generation commits. |
| Link/invalidation | Add exact `linkedKeg: String?` to `InstalledPackage`; retain `primaryKeg` for existing Installed behavior and bridge to `FormulaLinkState`. Declare bit/domain/gate `.diskUsage`; package terminals scope by kind, force-untap scopes Cellar+Caskroom. | No inferred link state and no Installed refresh duplication. One stream per explicit-root FSEvents observer is consumed once: Cellar/Caskroom signals fan out to Installed+DiskUsage; cache signals go only to DiskUsage. |
| Presentation | Add `.cleanup`; `CleanupView` uses package IDs and `(PackageID, rawVersion)` child IDs, expandable package-first rows, separate cache, and allocated bytes labelled “on disk.” | Pure sorting is bytes descending, then kind/package/version ascending, preserving selection. Show stale/progress/cancel/warnings/empty/missing-install guidance; no actions, recommendations, reclaimable claims, or Installed size column. |

## Data Flow

```text
BrewInstallation -> HomebrewRoots -> @concurrent scanner -> unit events
                          |                               -> MainActor store -> CleanupView
                          +-> cache actor <--- complete snapshot only
FSEvents / BrewClient mutation bridge -> scoped invalidation --------^
```

## File Changes

| Action | Files |
|---|---|
| Create | `Sources/DiskUsage/{HomebrewRoots,DiskUsageModels,DirectoryMeasuring,DiskUsageEngine,DiskUsageCache,DiskUsageStore}.swift`; `Tests/DiskUsageTests/{RootsAccounting,EngineEvents,StoreCache}Tests.swift`; `Sources/BrewClient/{DiskUsageRefreshCoordinator,InstalledDiskUsageProjection}.swift`; `cellar/Cleanup/{CleanupView,CleanupRow}.swift` |
| Modify | `Packages/CellarCore/Package.swift`; `Sources/BrewClient/{BrewMutating,MutationRefreshReceipts,TapCommand,InstalledModels,InstalledDecoder,FSEventsInstalledObserver,InstalledChangeObserving}.swift`; `Tests/CatalogTests/PackageGraphTests.swift`; `Tests/BrewClientTests/{InstalledDerive,MutationGates,InstalledObserver,TapIntegration}Tests.swift`; `cellar/{cellarApp,ContentView}.swift`; `cellar/Shell/AppSection.swift`; `cellarUITests/cellarUITests.swift`; `cellar.xcodeproj/project.pbxproj` |

## Interfaces / Contracts

`DiskUsageSnapshot` is immutable `Codable & Sendable`; `DiskUsageEvent` and `FormulaLinkState` are `Sendable`. `DiskUsageStore` is explicitly `@MainActor`; scanner/cache protocols isolate FileManager access and are injectable.

## Testing Strategy

Strict TDD writes RED first. Unit coverage maps all 15 scenarios: DU1 independent roots, DU2 brew absence, DU3 accounting/link safety, DU4 attribution/link state, DU5 stable ordering, DU6 cache adoption, DU7 cancellation, DU8 partial recovery, DU9 scoped invalidation, DU10 read-only exclusions; II1 single keg, II2 multi-keg, II3 cask string, II4 tri-state auto-update, II5 absent/older linked keg. Temp-tree integration covers DU1/3/4/7/8 without fixed APFS byte assertions; app tests cover DU9 fan-out/receipts; XCUITest covers route, DU2/5/10 states. Manifest tests prove forbidden reverse edges.

## Threat Matrix

Local-route/root boundary: safe behavior is exhaustive `.cleanup` routing and scans only from detected-installation roots; failure shows guidance or scoped warnings. RED coverage: route UI test plus standard/custom/invalid/missing-root tests.

| Boundary | Applicability | Design response / RED |
|---|---|---|
| Documentation-like paths | N/A — no executable classification | None |
| Git repository selection | N/A — no VCS commands | None |
| Commit state | N/A — no commits | None |
| Push state | N/A — no pushes | None |
| PR commands | N/A — no PR automation | None |

## Migration / Rollout

No user-data migration. Cache schema v1 is disposable: mismatches are ignored and rebuilt. Rollback removes route/product/linkage, restores prior invalidation/link projection, and deletes or leaves the inert cache.

## Open Questions

None. The separate 2,000-line delivery-budget decision remains a tasks/apply risk, not a design blocker.
