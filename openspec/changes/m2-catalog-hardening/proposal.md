# Proposal: M2 Prelude — Catalog Hardening

Artifact store: hybrid — mirrored in Engram topic `sdd/m2-catalog-hardening/proposal`.
Source: `openspec/changes/m2-mutations-installed/explore.md` §6–§7. All defects re-verified against `main@cc373e8`.

## Intent

M2 slice 1 adds a second `@Observable` store that adopts a snapshot, a second single-flight refresh, and a third clock-driven test suite. Six M1 follow-ups are defects in exactly those exemplars. Fix them before they are copied three times.

## Scope

### In Scope

| # | Verified defect | Fix |
|---|---|---|
| 1 | `CatalogStore.adopt` builds `PackageSearchIndex` (~16k records) synchronously on `@MainActor` (`CatalogStore.swift:146`), violating M1 D2 | Build off-main via `@concurrent`, mirroring `CatalogDecoder.decode`; ordered adoption so a late older build cannot win |
| 2 | `refreshNow()` adopts directly (`:128`) *and* through the `.snapshot` event `succeed()` yields (`CatalogSyncEngine.swift:287`) — index built twice | At most one index build per snapshot |
| 3 | `sync()` (`:74`) and `BrewDetectionStore.refresh()` (`:43`) clear `inFlight` only after the creator resumes, and `cancel()` never vacates it — a later caller joins a settled/cancelled task and gets a stale answer presented as fresh | The task vacates its own slot before its value is observable; `cancel()` vacates immediately. Both sites, one exemplar |
| 6 | Nothing stops a zero-package snapshot being persisted as success (engine `:160`, `CatalogFileStore.persist`) | Refuse; the last good catalog survives, status `failed(.malformedPayload)` |
| 7 | A persisted zero-package snapshot decodes fine, so `revalidatable` stays true (`:128`), the origin answers 304, and the machine stays on an empty catalog forever | `loadSnapshot()` treats degenerate as no cache → unconditional re-download |
| 10 | Both `TestClock` copies suspend on a bare `CheckedContinuation` and never observe cancellation | Honour cancellation; extract one `CellarTestSupport` target with no `BrewProcess`/`Catalog` dependency (preserves CS1) |

### Out of Scope

- #4/#5 (payload cap) — later catalog-hardening change.
- #8/#9 (refresh-loop / scene ownership) — deferred to `m2-installed-inventory`, which introduces the second scene-lifetime loop; solve ownership once, there.
- All M2 feature work: installed inventory, mutations, SwiftData, FS watcher.
- No new user-facing UI, no new public product.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `catalog-sync`: MODIFIED — a degenerate (zero-package) snapshot MUST NOT be persisted as success and MUST be treated as no cache on load; a manual refresh MUST adopt a snapshot exactly once; a single-flight join MUST be satisfied only by work genuinely in flight.
- `brew-detection`: MODIFIED — "Detection is observable, re-evaluated state": a re-evaluation MUST NOT be satisfied by a settled or cancelled evaluation.
- `package-search`: ADDED — index construction MUST NOT run on the main actor; the 8 ms as-you-type ceiling and single-pass build requirement are unchanged.

## Approach

Behaviour-preserving hardening in CellarCore only, strict TDD, one failing test per defect first.

1. **Off-main index build.** `PackageSearchIndex` is already a `Sendable` struct, so a `@concurrent` factory returns it to `@MainActor` for assignment. `adopt` becomes async and carries an adoption ordinal so out-of-order completions are dropped, not installed.
2. **Single adoption ingress.** De-duplicate by snapshot identity so `loadCache()`, `refreshNow()` and the event stream cannot build the same index twice.
3. **Single-flight invariant, twice.** Same shape applied to `CatalogSyncEngine.sync()` and `BrewDetectionStore.refresh()`, so `InstalledStore` has one correct pattern to copy.
4. **Degenerate-snapshot guard at both ends.** Write side (#6) and read side (#7); the read-side guard reuses the existing CS6 `revalidatable` path, which already forces an unconditional re-download when no previous snapshot is readable.
5. **`CellarTestSupport`.** Cancellation-aware `TestClock` plus `TestPoll`, depended on by both test targets.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Sources/Catalog/CatalogStore.swift` | Modified | Async ordered adoption; single ingress |
| `Sources/Catalog/PackageSearchIndex.swift` | Modified | `@concurrent` build entry point |
| `Sources/Catalog/CatalogSyncEngine.swift` | Modified | Single-flight slot; degenerate-snapshot rejection |
| `Sources/Catalog/CatalogFileStore.swift` | Modified | Degenerate snapshot = no cache; write guard |
| `Sources/BrewProcess/BrewDetectionStore.swift` | Modified | Single-flight slot |
| `Tests/CellarTestSupport/` | New | Shared cancellation-aware `TestClock`, `TestPoll` |
| `Package.swift` | Modified | New test-support target wired into both test targets |
| `Tests/{CatalogTests,BrewProcessTests}/Fakes/TestClock.swift` | Removed | Replaced by the shared target |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Async adoption introduces a visible gap where results are stale during the swap | Med | Adopt atomically on main after the build; assert cached results are served throughout (existing catalog-sync scenario) |
| Ordering regression: an older snapshot's index installed after a newer one | Med | Adoption ordinal + a dedicated regression test with two overlapping builds |
| Degenerate guard rejects a legitimately empty catalog | Low | Homebrew's core dumps are never empty; guard is on the persisted snapshot only, not on in-memory cold-launch emptiness (CS8 unaffected) |
| Fixing the single-flight join changes join semantics an M1 test asserts | Med | Re-read `SyncEngineTests`/detection tests first; update assertions in the same commit with rationale |
| Test-support extraction accidentally links `Catalog` to `BrewProcess` | Low | `CellarTestSupport` depends on `Synchronization` only; CS1 asserted by the target graph |
| Dead `previousSnapshot ?? CatalogSnapshot(packages: [])` fallback (engine `:145`) can still yield an empty success | Low | Tighten in the same change; covered by the #6 test |

## Rollback Plan

Single PR, CellarCore-only, no persisted-format change and no schema-version bump. `git revert` the merge commit restores M1 behaviour exactly; a machine that re-downloaded its catalog under the #7 fix simply keeps the good snapshot. The `CellarTestSupport` target reverts with the same commit because both duplicate `TestClock` files return with it.

## Dependencies

- None external. Must merge before `m2-installed-inventory`, `m2-mutations-activity`, and `m2-local-metadata-history` start.

## Success Criteria

- [ ] No `PackageSearchIndex` construction happens on the main actor; a test proves the main actor stays responsive while a ~16k-record snapshot is adopted.
- [ ] Adopting one snapshot builds exactly one index, including on the `refreshNow()` path.
- [ ] `CatalogSyncEngine.sync()` and `BrewDetectionStore.refresh()` each start fresh work after the previous attempt settles or is cancelled; regression tests cover both.
- [ ] A zero-package snapshot is never persisted as success, and a pre-existing one on disk is treated as no cache and re-downloaded unconditionally.
- [ ] One `TestClock` exists, it honours cancellation, and both test targets consume it.
- [ ] Full suite green (214 `@Test` at M1 close, plus new regressions); no new public API on `Catalog`/`BrewProcess` products.
- [ ] Authored diff within the 1,500-line `single-pr` budget (forecast 450–700).
