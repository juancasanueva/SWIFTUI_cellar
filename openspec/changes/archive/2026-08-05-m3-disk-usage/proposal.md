# Proposal: M3-3 Disk Usage

## Intent

Deliver PRD milestone **M3-3** storage visibility: a package-first, expandable view with version detail and allocated bytes labelled **“on disk.”** U7 measured 123,966 entries and 6.66 GB in 2.55 s (Cellar: 2.46 s), requiring caching, incremental progress, and cancellation.

## Scope

### In Scope
- Measure Cellar packages/versions, Caskroom, and cache from metadata.
- Show the last complete snapshot immediately as stale, revalidate incrementally, and replace it only with a complete scan.
- Preserve trustworthy completed and last-good results on partial failures, with warnings.
- Add a disk-only Cleanup section and mutation/FSEvents invalidation.

### Out of Scope
- Cleanup recommendations/actions, brew dry-run parsing, or reclaimable-byte claims (M3-4).
- Health score, treemap, Brewfile, or Installed-list size column (M5).

## Capabilities

### New Capabilities
- `disk-usage`: Native accounting, cache lifecycle, progress/cancellation, partial-failure semantics, and package/version storage presentation.

### Modified Capabilities
- `installed-inventory`: Preserve the payload’s optional linked-keg state instead of collapsing an unlinked formula to its newest keg.

## Approach

Add testable `DiskUsage` and `DiskUsageTests` targets. `DiskUsage` depends only on `BrewProcess` and `Catalog`, never `BrewClient`, `Persistence`, or the app. `BrewClient` bridges mutation receipts inward.

Use native traversal behind `DirectoryMeasuring`: lead with `totalFileAllocatedSizeKey`, never read contents or follow links/aliases, and deduplicate hard links per root. Publish at package/version boundaries, cancel off-main, and persist only complete snapshots atomically.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Packages/CellarCore/Package.swift`, `Sources/DiskUsage/`, `Tests/DiskUsageTests/` | New | Product, engine, cache, store, tests |
| `Sources/BrewClient/` | Modified | Link state, invalidation domain, watcher and receipt bridge |
| `cellar/Cleanup/`, app routing, `cellar.xcodeproj/project.pbxproj` | Modified | Disk-only user surface and linkage |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Multi-second scans or stale data | High | Stale-while-revalidate, progress, cancellation, scoped invalidation |
| Races, permissions, APFS attribution | High | Partial warnings; “on disk,” never “reclaimable”; deterministic link rules |
| Forecast 3,000–4,200 lines vs 2,000 budget | High | Record for later delivery planning; do not alter proposal scope mechanically |

## Rollback Plan

Remove the Cleanup route/linkage and `DiskUsage` targets, then restore BrewClient invalidation and installed-link projection; cached data is disposable.

## Dependencies

- Validated `BrewInstallation`, installed snapshot link state, FSEvents invalidation, and mutation refresh receipts.

## Success Criteria

- [ ] A complete cached snapshot appears immediately as stale and only a complete revalidation replaces it.
- [ ] U7-scale progress and cancellation remain responsive without blocking the main actor.
- [ ] Package/version rows lead with allocated “on disk” bytes and make no reclaimable claim.
- [ ] Missing roots and partial failures preserve valid data with explicit warnings.
- [ ] Dependency-graph tests prove no reverse dependency from `DiskUsage`.
