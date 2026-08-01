# Tasks: M1 — Catalog sync, package search, Browse UI

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 2,500–3,500 authored (excl. fixtures/goldens) |
| Project review budget | 800 lines (`openspec/config.yaml`) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (sync/decode) → PR 2 (index/search/detail) → PR 3 (Browse UI + pbxproj) |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

`single-pr` + High risk ⇒ apply MUST NOT start until the user either accepts an explicit
`size:exception` or picks a chain strategy (stacked-to-main or feature-branch-chain).

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | `Catalog` target: wire decode, persistence, sync engine, analytics (Phases 0–4) | PR 1 | `swift test --package-path Packages/CellarCore --filter Catalog` | `curl -sI` validator probe (task 0.3); no app UI yet | Delete `Sources/Catalog/**` + `Tests/CatalogTests/**` + revert `Package.swift`; app target untouched |
| 2 | Search index, ranking, detail projection, `CatalogStore` (Phases 5–7) | PR 2 | `swift test --package-path Packages/CellarCore --filter "Search\|Detail\|Store"` + release latency run | `swift test -c release --filter SearchLatency` | Delete `PackageSearchIndex.swift`, `PackageText.swift`, `CatalogStore.swift` + their suites; Unit 1 still ships |
| 3 | Browse UI, pbxproj/scheme link, editorial spec deltas (Phases 8–10) | PR 3 | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` | Launch app: cold sync, search, detail, first-run banner | `git checkout main -- cellar.xcodeproj/project.pbxproj cellar.xcodeproj/xcshareddata/xcschemes/CellarCore.xcscheme` + delete `cellar/Browse/**`; core package unaffected |

Feature-branch-chain bases if chosen: PR 1 → `feature/m1-catalog-browse`; PR 2 → PR 1 branch; PR 3 → PR 2 branch.

### Legend

- Requirement tags: `CS1..CS9` (catalog-sync), `PS1..PS6` (package-search), `PD1..PD6` (package-detail), in spec-file order.
- Paths under `Packages/CellarCore/` unless prefixed with `cellar/` or `openspec/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `REL` = `swift test --package-path Packages/CellarCore -c release --filter SearchLatency`.
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
- Strict TDD: every `RED` task lands a failing test; the following `GREEN` task makes it pass. Never write production code without a red test.

---

## Phase 0: Preflight, scaffold, fixtures (blocking for everything)

- [x] 0.1 Add `Catalog` product + `Catalog` target + `CatalogTests` target to `Package.swift` (`.swiftLanguageMode(.v6)`, **no** `BrewProcess` dependency). Verify: `FAST` compiles with an empty target.
- [x] 0.2 **Toolchain probe (D2)**: compile a throwaway `nonisolated @concurrent func` in `Sources/Catalog/`. If it fails under Swift 6.3.3 / tools-version 6.0, record the fallback `Task.detached(priority: .utility)` decision inline in `design.md` Open Questions and use it everywhere `@concurrent` was planned. Verify: `FAST`.
- [x] 0.3 **Validator probe (D7/CS2)**: run `curl -sI https://formulae.brew.sh/api/formula.json` and the cask/analytics endpoints; record whether `ETag` is present. If absent, drop `If-None-Match` and ship `If-Modified-Since` only. Record the result in `design.md` Open Questions.
- [x] 0.4 Capture fixtures into `Tests/CatalogTests/Fixtures/`: full `wget`, `git`, `iterm2` records; a ~50-record formula slice + ~50-record cask slice; an unknown-key mutated variant; flat 365d analytics excerpts for formula and cask. Commit excerpts only (kilobytes) — never the 40 MB dumps. Script the capture in `Tests/CatalogTests/Fixtures/README.md`.
- [x] 0.5 Port `TestClock` from `Tests/BrewProcessTests/Fakes/TestClock.swift` into `Tests/CatalogTests/Fakes/TestClock.swift` (separate test targets cannot share it) plus `FakeTimeSource`. Verify: `FAST`.
- [x] 0.6 Create `Sources/Catalog/CatalogErrors.swift` with the closed taxonomy **named per spec**: `CatalogSyncError { offline, httpStatus(Int), malformedPayload, persistence, cancelled }` and `CatalogSyncStatus { idle, downloading(fractionCompleted: Double?), decoding, succeeded(at: Date), failed(CatalogSyncError) }`. Reconcile design's `CatalogError`/`CatalogSyncState` naming to the spec wording before any consumer exists. Verify: `FAST`.

## Phase 1: Domain models + tolerant decode (CS5, PD1, PD4, PD5, PD6)

- [x] 1.1 RED `Tests/CatalogTests/CatalogModelsTests.swift`: `PackageID` equality/hashing distinguishes `(formula, docker)` from `(cask, docker)` (PS1). GREEN: `Sources/Catalog/CatalogModels.swift` — `PackageKind`, `PackageID`, `CatalogPackage`, `CatalogSnapshot`, `CatalogState`. Verify: `FAST --filter CatalogModels`.
- [x] 1.2 Extend `CatalogPackage` beyond design to satisfy PD4 and PD2: add `deprecationDate: Date?`, `disableDate: Date?`, and model each dependency entry so it can be marked unresolvable when absent from the snapshot. RED test first in `CatalogModelsTests`.
- [x] 1.3 RED `Tests/CatalogTests/DecodeTests.swift`: cask `name: ["iTerm2"]` → display name `iTerm2` (CS5). GREEN: `Sources/Catalog/Wire/CaskWire.swift`.
- [x] 1.4 RED: `"desc": null` and `"caveats": null` decode as absent, not empty string (CS5, PD1). GREEN: `Sources/Catalog/Wire/FormulaWire.swift` with `decodeIfPresent` throughout.
- [x] 1.5 RED: `uses_from_macos: ["curl", {"llvm": ["build"]}]` decodes both elements and retains the record (CS5). GREEN: `Sources/Catalog/Wire/Lossy.swift` — `UsesFromMacOS` either-type.
- [x] 1.6 RED: a record carrying unmodelled keys decodes successfully (CS5). GREEN: confirm wire types declare only the ~18 projected keys.
- [x] 1.7 RED: a 100-record payload with 3 malformed records yields 97 records and `skippedRecordCount == 3` (CS5). GREEN: `Sources/Catalog/Wire/Lossy.swift` — `LossyArray`.
- [x] 1.8 RED: a payload with zero usable records throws `.malformedPayload`; an unreadable envelope throws too (CS5/D6). GREEN: `Sources/Catalog/CatalogDecoder.swift` zero-record guard.
- [x] 1.9 RED `Tests/CatalogTests/ProjectionTests.swift`: formula `wget` projection reports desc/homepage/license/version/tap/kind and all flag fields (PD1); cask `iterm2` reports display name/kind/version/homepage/tap `homebrew/cask` (PD1). GREEN: projection in `CatalogDecoder.swift`.
- [x] 1.10 RED: deprecated record exposes flag + reason + date; disabled likewise; healthy record reports both flags false and all four reason/date fields absent (PD4). GREEN.
- [x] 1.11 RED: every persisted record's tap is `homebrew/core` or `homebrew/cask`; a third-party-tap name is a plain not-found and no error (PD6). GREEN: tap filter in projection.
- [x] 1.12 RED: build and runtime dependency lists are flat, direct, declaration-ordered, not deduped across lists; a dependency absent from the snapshot is listed by name and marked unresolvable (PD2). GREEN.
- [x] 1.13 RED `Tests/CatalogTests/CatalogMemoryTests.swift`: generate a synthetic 40 MB `formula.json` into a temp dir, measure `phys_footprint` via `task_info(TASK_VM_INFO)` around decode; assert peak delta ≤ 300 MB and retained delta ≤ 40 MB (D8). GREEN: `mappedIfSafe` + sequential per-resource scopes + `autoreleasepool` + immediate raw-download deletion. Verify: `FAST --filter CatalogMemory`.

## Phase 2: Persistence (CS3, CS6)

- [x] 2.1 RED `Tests/CatalogTests/FileStoreTests.swift`: a write failing midway leaves the previous snapshot readable and reports `.persistence` (CS3). GREEN: `Sources/Catalog/CatalogFileSystem.swift` (protocol + `DefaultCatalogFileSystem`) and `Sources/Catalog/CatalogFileStore.swift` using `replaceItemAt`.
- [x] 2.2 RED: `FakeCatalogFileSystem` records write order — `catalog.json` MUST be replaced before `catalog-state.json` (D3). GREEN. Add `Tests/CatalogTests/Fakes/FakeCatalogFileSystem.swift` with injectable write/replace failures.
- [x] 2.3 RED: state sidecar round-trips per source `schemaVersion`, validators (`etag`, `lastModified`), `downloadedAt`, `recordCount` for 7,000 formulae / 8,500 casks (CS6). GREEN — rename design's `fetchedAt` to `downloadedAt` to match the spec.
- [x] 2.4 RED: a sidecar with a higher `schemaVersion` reports no usable cache, throws nothing, and schedules a full sync (CS6). GREEN: schema-version gate.
- [x] 2.5 RED: a package present in the old snapshot but absent from the new payload disappears from lookup and search; no tombstones or merging (CS3). GREEN: full-replace persist path. Verify: `FAST --filter FileStore`.

## Phase 3: Sync engine (CS1, CS2, CS4, CS7, CS8)

- [x] 3.1 Add `Tests/CatalogTests/Fakes/FakeCatalogSource.swift` — scripted `CatalogFetchOutcome` per resource, records every request and its validators. GREEN with `Sources/Catalog/CatalogSource.swift` protocol.
- [x] 3.2 RED `Tests/CatalogTests/SyncEngineTests.swift`: sync completes with brew absent, no brew process spawned; exactly one request per source kind, transport never touched directly (CS1). GREEN: `Sources/Catalog/CatalogSyncEngine.swift` actor skeleton + staging lifecycle.
- [x] 3.3 RED: first sync (no persisted state) sends neither `If-Modified-Since` nor `If-None-Match` (CS2). GREEN.
- [x] 3.4 RED: both sources unchanged ⇒ no body read, no new snapshot, previous snapshot still served, `downloadedAt` advanced (CS2). GREEN: check `statusCode == 304` before touching the temp file (D7).
- [x] 3.5 RED: changed payload with validator `V2` persists a new snapshot recording `V2`; `lastModified` round-trips as the **raw header string**, never through a `DateFormatter` (CS2/D7). GREEN.
- [x] 3.6 GREEN-only: `Sources/Catalog/CatalogSource.swift` `HTTPCatalogSource` sets `configuration.urlCache = nil` **and** `request.cachePolicy = .reloadIgnoringLocalCacheData` (D7), uses `download(for:)` (CS1 streaming), and enforces the 128 MB `payloadTooLarge` cap.
- [x] 3.7 RED: transport error with a 15,000-record cache ⇒ `.offline`, cache still answers queries (CS4). GREEN.
- [x] 3.8 RED: `503` retried twice then succeeds (3 requests); `404` requested once and reports `.httpStatus(404)`; `429` is retried (CS4). GREEN: `Sources/Catalog/CatalogRefreshPolicy.swift` retry/backoff values.
- [x] 3.9 RED: non-JSON body ⇒ `.malformedPayload`, persisted snapshot unchanged (CS4). GREEN.
- [x] 3.10 RED: cancellation mid-sync reports `.cancelled` and purges the staging directory; staging is also purged on success and on failure. GREEN.
- [x] 3.11 RED `Tests/CatalogTests/SchedulerTests.swift` on `TestClock` + `FakeTimeSource`: snapshot 2 h old ⇒ no request on load; 30 h old ⇒ background sync starts while cached records keep being served, replaced only on success (CS7). GREEN: poll-and-compare loop at 15 min `pollGranularity` (D5).
- [x] 3.12 RED: manual refresh with a 2 h-old snapshot issues a sync; a second manual refresh during an in-flight sync joins it rather than starting a second (CS7, single-flight). GREEN.
- [x] 3.13 RED: wake-from-sleep — advancing the fake time source by 30 h across a paused clock triggers exactly one sync (D5). GREEN.
- [x] 3.14 RED: cold launch with no cache resolves immediately to zero results without blocking, status is `downloading` or `decoding`; on success status becomes `succeeded(at:)` and results are non-zero; a failed first sync reports `failed(.offline)` and throws nothing (CS8). GREEN: status publication through every phase. Verify: `FAST --filter "SyncEngine\|Scheduler"`.

## Phase 4: Analytics join (CS9, PD5)

- [x] 4.1 RED `Tests/CatalogTests/AnalyticsTests.swift`: `"count": "2,808,879"` parses to `2808879` under a locale using `.` as group separator (CS9). GREEN: `Sources/Catalog/AnalyticsIndex.swift` — strip `,`, no `NumberFormatter`.
- [x] 4.2 RED: formula vs cask item keys resolve to the right namespace; a package with no entry has an absent count distinct from `0` (CS9, PD5). GREEN.
- [x] 4.3 RED: payload sync succeeds while analytics fetch fails ⇒ sync reports success, snapshot persists, every record has an absent count (CS9). GREEN: analytics join is non-fatal.
- [x] 4.4 RED: the projection exposes the count together with window = 365 days, metric (installs-on-request for formulae / installs for casks), and a lower-bound flag; never as an absolute total (PD5). GREEN. Verify: `FAST --filter Analytics`.

**Unit 1 gate**: `swift test --package-path Packages/CellarCore` all green; record the measured slim-projection size ratio in `design.md` Open Questions.

## Phase 5: Search index, ranking, latency (PS1–PS6)

- [ ] 5.1 RED `Tests/CatalogTests/PackageTextTests.swift`: `normalize` lowercases, folds diacritics, and collapses non-alphanumerics to a single `0x20`; `GH` matches `gh`; `cafe` and `café` both match a `café` description (PS2). GREEN: `Sources/Catalog/PackageText.swift`.
- [ ] 5.2 RED `Tests/CatalogTests/SearchIndexTests.swift`: index build normalises each record exactly once and the built index answers queries (PS6 second scenario). GREEN: `Sources/Catalog/PackageSearchIndex.swift` struct-of-arrays (`names: [UInt8]` + `nameRanges`, `descs` + ranges, `installCounts: [Int32]`, `kinds: [UInt8]`, `flags: [UInt8]`), `Sendable` by composition, no `@unchecked`.
- [ ] 5.3 RED: formula `docker` and cask `docker` yield two distinct results, each exposing its kind (PS1). GREEN.
- [ ] 5.4 RED `Tests/CatalogTests/RankingTests.swift`: query `wget` orders `wget`, `wget2`, `libwget`, `curl`; a record is ranked by its strongest class only (PS3). GREEN: one-pass four-bucket scan, `continue` on a name hit.
- [ ] 5.5 RED: within a class, install count descending (`node` before `nodenv`); absent counts sort after every present count; full ties break by normalised name ascending then `formula` before `cask`, stable across two runs (PS3). GREEN: `(rank asc, installCount desc, name asc, kind)` ordering.
- [ ] 5.6 RED `Tests/CatalogTests/FilterTests.swift`: deprecated included by default with flag exposed; `excludeDeprecated` removes it while other matches remain; kind filter restricted to `cask` returns exactly one `docker`; enumerating the filter set contains no installed/not-installed/outdated predicate (PS4). GREEN: `SearchFilters`.
- [ ] 5.7 RED: empty/whitespace query returns the whole filtered catalog ordered by install count desc; `zzzzznotapackage` returns zero results and throws nothing (PS5). GREEN.
- [ ] 5.8 RED `Tests/CatalogTests/SearchLatencyTests.swift` gated `@Test(.enabled(if: BuildConfiguration.isRelease))`: seeded generator builds ~15,500 records with the live length distribution; 5 warm-up passes, then 1,000 samples (50 progressive 1–5 char prefixes of 10 real names × 20 runs) measured with `ContinuousClock`, excluding build time; assert p95 < 8 ms (PS6). GREEN: lazy bucket sort that stops once `limit` is filled. Verify: `REL`.
- [ ] 5.9 If 5.8 fails, escalate strictly in order — char-bitmask pre-gate, then trigrams, then an off-main hop (D4). Do not weaken the assertion.

## Phase 6: Dependents inversion + detail resolution (PD3, PD1)

- [ ] 6.1 RED `Tests/CatalogTests/DependentsTests.swift`: `git` → `pcre2` runtime edge makes `git` a dependent of `pcre2` (PD3). GREEN: inversion pass in `CatalogDecoder.swift`, run once at sync time.
- [ ] 6.2 RED: build-only edge (`wget` → `pkgconf`) also produces a dependent (PD3). GREEN.
- [ ] 6.3 RED: a leaf (cask `iterm2`) reports an empty dependents list, not absent; an edge to a name absent from the snapshot creates no dependents entry and the sync still succeeds (PD3). GREEN.
- [ ] 6.4 RED `Tests/CatalogTests/DetailTests.swift`: detail lookup for `(formula, nosuchpackage)` returns not-found and throws nothing (PD1). GREEN: `PackageSearchIndex.package(_:)`. Verify: `FAST --filter "Dependents\|Detail"`.

## Phase 7: CatalogStore façade (CS7, CS8)

- [ ] 7.1 RED `Tests/CatalogTests/CatalogStoreTests.swift` (`@MainActor`): `start()` loads a cached snapshot then runs the refresh loop; `isReady` and `syncState` publish transitions (CS8). GREEN: `Sources/Catalog/CatalogStore.swift` `@MainActor @Observable`.
- [ ] 7.2 RED: setting `query` or `filters` reranks synchronously on the main actor with no async hop and no stale out-of-order result (D4). GREEN.
- [ ] 7.3 RED: `refreshNow()` joins an in-flight sync (single-flight, mirroring `BrewDetectionStore`) (CS7). GREEN. Verify: `FAST --filter CatalogStore`.

**Unit 2 gate**: `FAST` all green **and** `REL` green.

## Phase 8: Browse UI (no pbxproj edits — file-system-synchronized groups)

- [ ] 8.1 Create `cellar/Shell/AppSection.swift` (sections enum) and extract the existing detection summary verbatim into `cellar/Home/BrewDetectionSummary.swift` + `cellar/Home/HomeView.swift`.
- [ ] 8.2 Rewrite `cellar/ContentView.swift` as the `NavigationSplitView` shell (sidebar → Browse list → detail).
- [ ] 8.3 Create `cellar/Browse/BrowseView.swift` + `cellar/Browse/PackageRow.swift` — searchable list bound to `CatalogStore.results`, badging deprecated/disabled (PS4).
- [ ] 8.4 Create `cellar/Browse/CatalogFilterBar.swift` — kind, `excludeDeprecated`, `excludeDisabled` (PS4).
- [ ] 8.5 Create `cellar/Browse/PackageDetailView.swift` — every PD1 field, both dependency lists, dependents, deprecation/disabled reasons and dates, install count rendered with its 365-day lower-bound caption; absent count renders "not reported" (PD1–PD5).
- [ ] 8.6 Create `cellar/Browse/SyncBanner.swift` — first-run/empty-cache banner and `failed(...)` state, with cached results still visible (CS8).
- [ ] 8.7 Modify `cellar/cellarApp.swift`: drop `Schema([Item.self])` and the `ModelContainer`, own a `CatalogStore`, `.task { await catalog.start() }`. Delete `cellar/Item.swift`.

## Phase 9: Xcode project link (atomic unit)

- [ ] 9.1 Apply all four `cellar.xcodeproj/project.pbxproj` hunks as **one commit**: `PBXBuildFile` `Catalog in Frameworks` (`BC0000010000000000000004`), append to `PBXFrameworksBuildPhase` `BCDBE978…` `files`, append to target `cellar` `packageProductDependencies`, and `XCSwiftPackageProductDependency` `productName = Catalog` (`BC0000010000000000000005`). Never split across PR slices. Rollback: `git checkout main -- cellar.xcodeproj/project.pbxproj`.
- [ ] 9.2 Modify `cellar.xcodeproj/xcshareddata/xcschemes/CellarCore.xcscheme`: build entry for `Catalog`, testable entry for `CatalogTests`. Verify: `FULL` builds and links.

## Phase 10: Editorial deltas + verification gate

- [ ] 10.1 Apply the `brew-execution` MODIFIED requirement (four terminal outcomes) to `openspec/specs/brew-execution/spec.md`, scenarios carried over verbatim.
- [ ] 10.2 Apply the `brew-detection` MODIFIED requirement (`configuredPathMissing` vs `invalid(notExecutable)` THEN block) to `openspec/specs/brew-detection/spec.md`.
- [ ] 10.3 Manual apply-time integration checklist: real cold sync against the live endpoints, observed peak RSS, and the recorded `curl -sI` validator result from 0.3. Record outcomes in the apply report.
- [ ] 10.4 Final gate: `FAST` green, `REL` green, `FULL` green, `swiftlint` clean on new files. Record every command and its exact result.
