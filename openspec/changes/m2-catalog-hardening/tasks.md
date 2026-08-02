# Tasks: M2 Prelude — Catalog Hardening

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 800–950 authored (D1–D4 + D6 ≈ 550; D5 ≈ 380 of pure file movement) |
| Session review budget | 1,500 lines (`review_budget_lines`) |
| 1,500-line budget risk | Low |
| 400-line budget risk | High |
| Chained PRs recommended | No |
| Suggested split | Single PR; D5 (Phase 5) is the pre-agreed cut point if the diff overruns |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

Resolution of the two budget lines: `400-line budget risk: High` is the mandatory
default-budget guard line and is honestly High — the forecast exceeds 400. The budget
actually accepted for this session is **1,500**, and 800–950 fits inside it, so no
`size:exception` and no chain are required and apply may start unblocked. If the real
diff crosses 1,500, cut **Phase 5 (D5, `CellarTestSupport`)** into a follow-up PR: it is
pure test infrastructure, nothing in Phases 1–4 depends on it, and existing tests already
tear `start()` down with `Task.cancel()` rather than by awaiting the loop.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Production hardening: D3 single-flight, D2 identity, D1 off-main ordered adoption, D4 degenerate guards (Phases 0–4, 6) | PR 1 | `FAST --filter "SyncEngine\|CatalogStore\|FileStore\|SearchIndex\|BrewDetection"` | Plant a zero-package `catalog.json` in `Application Support/<bundle id>/Catalog`, launch the app: it must re-download unconditionally and stay typeable during adoption | `git revert` the merge; no persisted-format change, `schemaVersion` stays 1, a re-downloaded catalog is simply kept |
| 2 | `CellarTestSupport` extraction + cancellation-aware `TestClock` (Phase 5) | PR 1 (or PR 2 if cut) | `FAST` both targets | N/A — test-only target, absent from `products:`, no runtime surface | Delete `Tests/CellarTestSupport/**`, restore both `Fakes/TestClock.swift` copies, revert `Package.swift` |

If cut, PR 2 base = PR 1 branch (feature-branch-chain).

### Legend

- Requirement tags: `CSA1..CSA4` (catalog-sync ADDED, delta-file order), `BD1` (brew-detection MODIFIED), `PSA1` (package-search ADDED).
- Defect numbers `#1 #2 #3 #6 #7 #10` are the proposal's verified-defect table.
- Paths under `Packages/CellarCore/` unless prefixed with `openspec/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `REL` = `swift test --package-path Packages/CellarCore -c release --filter SearchLatency`.
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests`.
- Strict TDD: every `RED` task lands a failing test; the following `GREEN` task makes it pass. No production line without a red test.
- D6 policy: an M1 assertion changes **only** when it encodes one of the six defects, in the same commit as its fix, with the defect number in the commit body. No M1 assertion is deleted. A `packages: []` convenience fixture becoming a one-record fixture is a fixture change and needs no rationale.

---

## Phase 0: Baseline (blocking, no production change)

- [x] 0.1 Record the green baseline on `main`: `FAST`, `REL`, `FULL`. Capture the `@Test` count (214 at M1 close) so Phase 6 can prove nothing was deleted.

## Phase 1: Single-flight invariant (D3, defect #3 — CSA2, BD1)

- [x] 1.1 **RED, assumption probe (design risk #3, blocks 1.3).** New `Tests/CatalogTests/SingleFlightRecipeTests.swift`: a bare `Task { defer { vacated = true }; return value }` observed from a joiner — assert `vacated == true` at the instant `await task.value` returns. This is the compiler assumption the whole D3 recipe rests on. If it fails under the project toolchain, **stop and report**: the recipe needs another shape and D3 must be redesigned before any production edit. No production code in this task.
- [x] 1.2 RED `Tests/CatalogTests/SyncEngineTests.swift`: with the source gated, two callers join one `sync()` (exactly one acquisition, same result — CSA2 scenario 1); after both resume, a third `sync()` against a source now serving `P2` performs a **second** acquisition and returns `P2` (CSA2 scenario 2).
- [x] 1.3 GREEN `Sources/Catalog/CatalogSyncEngine.swift`: replace `inFlight: Task<…>?` (`:24`) with a token-keyed slot `(token, task, isCancelled)`; `Task { defer { vacate(token) }; return await performSync() }`; creation and slot assignment in the same actor turn, no suspension between them, so a task can only vacate its own entry.
- [x] 1.4 RED `SyncEngineTests`: `sync()` gated → `cancel()` → `sync()` returns a fresh result, never `.cancelled` from the previous attempt (CSA2 scenario 3); and via the `FakeCatalogFileSystem` recorder, the cancelled run's staging purge is recorded **before** the successor's `prepareStaging()` (mark-and-drain amendment).
- [x] 1.5 GREEN `CatalogSyncEngine`: `cancel()` (`:91`) marks the slot cancelled *and* cancels the task; `sync()` drains a cancelled slot with `_ = await current.task.value` before starting fresh work, so the successor cannot have its download deleted by the dying task's `defer { store.purgeStaging() }`. Verify: `FAST --filter SyncEngine`.
- [x] 1.6 D6 audit for #3: confirm `SchedulerTests.manualRefreshIsSingleFlight` (a genuine in-flight join still joins) and `SyncEngineTests`' cancel path (`sync()` → `cancel()` → `.cancelled`) stay green **unchanged** — design verified both as non-breaking. Any assertion that must change lands in the 1.5 commit citing defect #3.
- [x] 1.7 RED `Tests/BrewProcessTests/BrewDetectionStoreTests.swift`: a `refresh()` issued after the first settled re-probes (`FakeBrewLocator.callCount == 2`, BD1 scenario 4); a caller whose task is cancelled mid-`refresh()` does not poison the next `refresh()`, which observes the newest state (BD1 scenario 5); two concurrent callers still coalesce onto one probe (BD1 scenario 6).
- [x] 1.8 GREEN `Sources/BrewProcess/BrewDetectionStore.swift` (`:41-51`): same token slot, `defer` inside the task body with `[weak self]` so the task still does not retain the store. No drain — detection has no `cancel()` and no staging. Verify: `FAST --filter BrewDetection`.

## Phase 2: Snapshot identity (D2, prerequisite for 3.6)

- [x] 2.1 RED `Tests/CatalogTests/CatalogModelsTests.swift`: `CatalogSnapshotRevision.next()` is unique and monotonic across concurrent callers; two decodes of the same bytes receive **distinct** revisions; the encoded JSON is byte-identical to the pre-change encoding (no `revision` key). GREEN `Sources/Catalog/CatalogModels.swift`: `CatalogSnapshotRevision` over a `Synchronization.Atomic` counter; `public let revision` on `CatalogSnapshot`, excluded from `CodingKeys`, assigned `.next()` in an explicit `init(from:)`. `schemaVersion` stays 1.
- [x] 2.2 RED `SyncEngineTests`: the snapshot handed back by `cachedSnapshot()` and by a 304-only `performSync` for the same on-disk file carries the **same** revision (without the pin the 15-minute poll re-emits a fresh identity and rebuilds a 16k index forever). GREEN `CatalogSyncEngine`: a `diskRevision` pin, set to the new snapshot's revision on successful persist and to `nil` on failed persist so a crash between `catalog.json` and its sidecar cannot leave a stale pin. Verify: `FAST --filter "CatalogModels\|SyncEngine"`.

## Phase 3: Off-main, ordered, single adoption (D1, defects #1/#2 — PSA1, CSA1)

- [x] 3.1 RED `Tests/CatalogTests/SearchIndexTests.swift`: main-actor work submitted after a build over a ~15,500-record fixture starts runs to completion **before** the build finishes (PSA1 scenario 1). GREEN `Sources/Catalog/PackageSearchIndex.swift`: `@concurrent public static func build(from snapshot: CatalogSnapshot) async -> PackageSearchIndex` wrapping the existing init unchanged — the attribute must **precede** the modifier (M1 apply-time finding).
- [x] 3.2 RED: the off-main-built index answers the documented ranking, filter and empty-query fixtures identically and in the same order to a synchronously built one, and each record is still normalised exactly once (PSA1 scenarios 2+3). GREEN: no production change expected; a failure here means the build stopped being single-pass.
- [x] 3.3 RED `Tests/CatalogTests/CatalogStoreTests.swift` (`@MainActor`): count `Task.yield()` turns completed on the main actor across one adoption of a ~15,500-record snapshot — assert `> 0`, which a synchronous build makes impossible (defect #1). GREEN `Sources/Catalog/CatalogStore.swift`: `adopt` (`:146`) becomes `async` and awaits `PackageSearchIndex.build(from:)`; `loadCache()`, `refreshNow()` and `handle(_:)` await it. `isReady` still flips after `loadCache()`'s adoption completes.
- [x] 3.4 RED `CatalogStoreTests`: with 15,000 cached records resident, every query issued while an adoption is in progress returns the previous non-empty results and none observes an empty set caused by the swap (CSA1 scenario 3). GREEN: install is one main-actor assignment after the `await`; `rerank()` stays synchronous against the **installed** index and is deliberately unaware of the build (M1 D4).
- [x] 3.5 RED `CatalogStoreTests`: two overlapping adoptions of older `A` and newer `B` where `B` completes first — the catalog serves `B`, and `A`'s late build is discarded, not installed (CSA1 scenario 2). GREEN: a monotonic `adoptionSequence` stamped before the `await`; install admitted only while the ordinal still exceeds `installedSequence`.
- [x] 3.6 RED `CatalogStoreTests`: with `start()` running and the event stream observed, `refreshNow()` completing a sync that produces `S` builds the index **exactly once** for `S` (instrumented build counter), and the served record count and results are `S`'s (CSA1 scenario 1, defect #2). GREEN: revision guard in `adopt` — drop the adoption when `snapshot.revision` equals the installed revision. `refreshNow()` keeps its contract and its ingress (Q4).
- [x] 3.7 D6 audit for #1/#2: re-run `CatalogStoreTests`, `DetailTests`, `SchedulerTests`; every changed assertion cites defect #1 or #2 in its commit body; `packages: []` convenience fixtures move to one-record fixtures without rationale. Verify: `FAST`, then `REL` to confirm the p95 8 ms ceiling still holds over a built index.

## Phase 4: Degenerate-snapshot guards (D4, defects #6/#7 — CSA3, CSA4)

- [x] 4.1 RED `Tests/CatalogTests/FileStoreTests.swift` (real temp directory): a zero-package `catalog.json` at the current `schemaVersion` reads as `nil` and throws nothing; a one-package snapshot still reads as a usable cache (CSA4 scenarios 1+3). GREEN `Sources/Catalog/CatalogFileStore.swift` `loadSnapshot()` (`:33`): return `nil` after decode when `packages.isEmpty`. The poisoned file is **left in place** — a read path must not mutate the store.
- [x] 4.2 RED `FileStoreTests`: `persist(_:state:)` with a zero-package snapshot throws `.malformedPayload` — **not** `.persistence` — and writes neither `catalog.json` nor its sidecar. GREEN `CatalogFileStore.persist` (`:59`): guard placed **outside** the `do` block, which rewrites every throw to `.persistence`.
- [x] 4.3 RED `SyncEngineTests`: a well-formed payload yielding zero packages, against a persisted 15,000-record snapshot, fails `.malformedPayload`; the `FakeCatalogFileSystem` recorder shows no snapshot and no sidecar write; the 15,000 records are still served (CSA3 scenario 1). GREEN `CatalogSyncEngine.performSync`: semantic guard before `store.persist` (`:160`) so `succeed()` is never reached — no snapshot event, no adoption.
- [x] 4.4 RED `SyncEngineTests`: with no readable snapshot and every payload resource answering "unchanged", the sync does not succeed, publishes no snapshot, and status is `failed(.malformedPayload)`; a degenerate first sync throws nothing, returns zero results, and leaves no snapshot on disk (CSA3 scenarios 2+3). GREEN: restructure `:134-149` from `guard acquired.changed || previousSnapshot == nil` plus the `previousSnapshot ?? CatalogSnapshot(…, packages: [])` fallback into `if !acquired.changed, let previousSnapshot { … }`, deleting the unreachable empty-snapshot construction rather than commenting it.
- [x] 4.5 RED `SyncEngineTests`: a payload yielding exactly one package succeeds, persists and is served — the threshold is exactly zero, no plausibility floor (CSA3 scenario 4). GREEN: no change expected.
- [ ] 4.6 RED `SyncEngineTests`: given a poisoned zero-package snapshot plus a sidecar holding validators for both sources, the next sync's recorded requests carry neither `If-Modified-Since` nor `If-None-Match`, and a successful response replaces the poisoned snapshot and serves its records (CSA4 scenario 2, defect #7). GREEN: this must fall out of 4.1 through the existing `revalidatable: previousSnapshot != nil` path (`:128`) — assert it, do not add a branch. Confirm the cold-launch status stays the ordinary progression, never `failed` (Q1).
- [ ] 4.7 D6 audit for #6/#7: migrate `packages: []` convenience fixtures in `FileStoreTests`, `SyncEngineTests` and `AnalyticsTests` to one-record fixtures; any assertion encoding defect #6 or #7 changes in its fix's commit citing the number. Verify: `FAST`.

## Phase 5: `CellarTestSupport` (D5, defect #10) — designated cut point

- [ ] 5.1 Add to `Packages/CellarCore/Package.swift`: `.target(name: "CellarTestSupport", path: "Tests/CellarTestSupport", swiftSettings: [.swiftLanguageMode(.v6)])` with **no** `dependencies:` and absent from `products:` — CS1 is enforced structurally by the target graph. Add it to both test targets' `dependencies`. Verify: `FAST` compiles with the target empty.
- [ ] 5.2 Move `TestClock`, `TestPoll` and `FakeTimeSource` into `Tests/CellarTestSupport/{TestClock,TestPoll,FakeTimeSource}.swift` as `public`; delete `Tests/CatalogTests/Fakes/TestClock.swift` and `Tests/BrewProcessTests/Fakes/TestClock.swift`; re-home `extension FakeTimeSource: CatalogTimeSource` in `CatalogTests` as a retroactive conformance. Behaviour-identical move. Verify: `FAST`, both targets.
- [ ] 5.3 RED (a suite in each test target consuming the shared clock): a task cancelled **before** `clock.sleep(until:)` parks throws `CancellationError`; a task cancelled **after** `waitForSleepers()` also throws promptly under a `.timeLimit` and does not hang. GREEN `Tests/CellarTestSupport/TestClock.swift`: `try Task.checkCancellation()` first, sleeper id allocated *before* suspending, `withTaskCancellationHandler` around `withCheckedThrowingContinuation`, and a `cancelledIDs` set consulted under the same lock that parks the sleeper (`.due` / `.alreadyCancelled` / `.parked`). Continuations are always resumed **outside** `withLock`, matching `advance(by:)`.
- [ ] 5.4 RED `Tests/CatalogTests/SchedulerTests.swift`: `CatalogStore.start()`'s task group actually finishes when its task is cancelled, so `defer { loop.cancel() }` stops something. GREEN: falls out of 5.3 — assert under a `.timeLimit`, do not change production code. Verify: `FAST`.

## Phase 6: Gate

- [ ] 6.1 Full gate: `FAST` green with the M1 `@Test` count from 0.1 intact plus the new regressions (none deleted), `REL` green, `FULL` green, `swiftlint` clean on changed files. Record every command and its exact result in the apply report.
- [ ] 6.2 Scope guard: `git diff --stat main` touches only the files in design "File Changes"; no new public API on the `Catalog` or `BrewProcess` products; `CatalogSnapshot.currentSchemaVersion` still 1 and persisted JSON byte-identical; nothing from follow-ups #4/#5/#8/#9 or any M2 feature work is present.
