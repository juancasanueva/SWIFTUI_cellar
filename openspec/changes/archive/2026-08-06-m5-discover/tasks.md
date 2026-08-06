# Tasks: M5 Discover

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | **2,000–2,900** authored source+tests (~650 CellarCore source, ~180 curated JSON, ~180 modified CellarCore, ~320 app, ~1,300–1,700 tests + fixtures) |
| Session review budget | **5,000** lines (session override of `config.yaml`'s 2,000) |
| 5,000-line budget risk | Low–Medium |
| 2,000-line budget risk | High |
| 400-line budget risk | High |
| Chained PRs recommended | No |
| Suggested split | Single PR; **Phase 9 (app layer, D4)** is the pre-agreed cut point if the diff overruns |
| Delivery strategy | single-pr |
| Chain strategy | pending |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

Resolution of the budget lines: `400-line budget risk: High` is the mandatory default-budget guard
line and is honestly High — the forecast exceeds 400 several times over. The budget actually
governing this session is **5,000**, and 2,000–2,900 fits inside it, so no `size:exception` and no
chain are required and apply may start unblocked. This estimate is **above** the proposal's
700–1,200 forecast: the delta is the curated seed content (~180 lines the proposal did not cost),
the sidecar fixture set, and the fact that the design closed with 13 RED-first test layers rather
than the proposal's implied handful. If the real diff crosses 5,000, cut **Phase 9** into a
follow-up PR: it is presentation-only, nothing in Phases 1–8 depends on it, and the CellarCore
slice alone already satisfies every `package-discovery` and `catalog-sync` requirement.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | CellarCore: ladders, curated list + resource, roster/arrivals sidecars, diff + retention, sync integration, projection, bounds and egress guards (Phases 1–8) | PR 1 | `FAST --filter "DiscoverRanking\|CuratedDiscovery\|DiscoveryRoster\|DiscoverProjection\|DiscoverySidecarFootprint\|FileStore\|SyncEngine\|AcquisitionScope\|CatalogFootprint"` | Delete `~/Library/Application Support/<bundle id>/Catalog/catalog-roster.json` and `catalog-arrivals.json`, launch and sync twice: first sync re-seeds and reports **zero** arrivals, second reports only genuinely unseen packages, and the directory holds exactly the four files | `git revert` the merge; `Package.swift` loses one `resources:` line, the two orphaned sidecars are inert and never read by the reverted build |
| 2 | App layer: `.discover` section, its three section views and the honest-phrasing guard (Phase 9) | PR 1 (or PR 2 if cut) | `APP --only-testing:cellarTests/DiscoverCompositionTests` | Launch: Discover sits between Home and Browse, both ladders and the curated list render, and a first-run profile shows the "measured from this sync onward" explanation rather than a spinner | Delete `cellar/Discover/`, the `.discover` case and the two `ContentView` switch arms; no pbxproj edit to undo (synchronized root group) |

If cut, PR 2 base = PR 1 branch (feature-branch-chain).

### Legend

- Paths under `Packages/CellarCore/` unless prefixed with `cellar/`, `cellarTests/`, `cellarUITests/` or `openspec/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `APP` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
- Spec tags — `package-discovery` (ADDED-only, 6 req / 23 sc): **PD-R1** two separate ladders / absent is not zero, **PD-R2** Discover costs no new acquisition, **PD-R3** curated list ships with the build and decodes tolerantly, **PD-R4** an unresolvable curated entry is skipped and counted, **PD-R5** new to you = first observed by this machine within 30 days, **PD-R6** typed section state / Discover never opens empty.
- Spec tags — `catalog-sync` (14 req / 51 sc → 16 / 66): **CS-M1** slim persisted projection with a state sidecar (MODIFIED, 9 sc), **CS-M2** inspection data costs no new acquisition (MODIFIED, 3 sc), **CS-A1** durable known-package roster (ADDED, 6 sc), **CS-A2** dated arrivals log retains thirty days (ADDED, 5 sc).
- Threat-matrix rows — **TM1** network egress and subprocess (by prohibition), **TM2** filesystem write during a read (by prohibition), **TM3** untrusted on-disk input (both sidecars are locally attacker-writable), **TM4** catalog-published text into UI. Routing, VCS/PR automation and executable-file classification are `N/A` and have no task.
- **No Phase 0.** Slice 1 needed one because it widened the wire and had to capture pre-widening decode counts. This slice widens nothing — `CatalogPackage`, `CatalogSnapshot` and `currentSchemaVersion` are frozen — so the only regression gate is re-running `CatalogFootprintTests` unchanged (task 8.2), which asserts against a recorded bound and needs no captured baseline. The `@Test` count check lives in 10.1.
- Strict TDD: every `RED` task lands a failing test; the following `GREEN` task makes it pass. No production line without a red test.
- Binding: sidecars carry **their own** `DiscoverySchema.currentVersion = 1` and gate against it, never against `CatalogSnapshot.currentSchemaVersion` — a snapshot bump must not erase a user's 30-day arrivals history. Arrivals are written **before** the roster. An absent roster **seeds** and records zero arrivals.
- Binding: arrivals do **not** inherit D3's deprecated/disabled exclusion — that ruling is ladder-scoped, so a newly-arrived deprecated package still appears in "new to you". Pruning site is an implementation choice; the spec pins only the observable outcomes.

---

## Phase 1: Fixtures (test data only, no production code)

- [x] 1.1 Create `Tests/CatalogTests/Fixtures/Discovery/curated-tolerant.json`: entries carrying keys the decoder does not model, plus one entry with no blurb, one with a blank blurb, one with no token, one with no kind, and one with an unknown kind — five distinct malformed shapes beside well-formed entries (**PD-R3** *Unknown fields and malformed entries are tolerated*).
- [x] 1.2 Create `Fixtures/Discovery/curated-duplicate.json` (token `ripgrep` declared in two categories) and `Fixtures/Discovery/curated-unsorted.json` (categories and entries deliberately not alphabetical) (**PD-R3** *A duplicate token resolves once*, *Declared order survives decoding*).
- [x] 1.3 Create the hostile sidecar fixtures: `Fixtures/Discovery/roster-corrupt.json` (bytes that are not valid JSON), `roster-wrong-version.json` (a version other than `DiscoverySchema.currentVersion`), `arrivals-corrupt.json`, `arrivals-wrong-version.json`, and `arrivals-undatable.json` (one entry with no readable date beside two well-formed entries) (**CS-A1** sc3, **CS-A2** sc4/sc5, **TM3**).
- [x] 1.4 Register the new fixtures in `Tests/CatalogTests/Fakes/Fixtures.swift` and document each one's role in `Tests/CatalogTests/Fixtures/README.md`. Leave every slice-1 fixture **byte-identical** — several are the T5 decode control.

## Phase 2: Ranked ladders (**PD-R1**)

- [x] 2.1 RED create `Tests/CatalogTests/DiscoverRankingTests.swift`: a snapshot whose highest-counted cask outranks every formula yields a formula ladder of only formulae and a cask ladder of only casks, with no entry appearing in both, each ranking on the metric matching its kind (`installsOnRequest` vs `installs`) (**PD-R1** sc1); formula `obscure` with an absent install count appears **nowhere**, and no ladder entry reports a count of `0` derived from an absent count (sc2); the two highest-counted formulae being deprecated and disabled respectively makes both ineligible and the ladder starts at the highest-counted formula that is neither (sc3).
- [x] 2.2 RED same file: exactly 7 eligible casks yields exactly 7 entries with nothing padded to reach 50 (**PD-R1** sc4); 51 eligible packages yields exactly 50 and the 51st is absent; three formulae with equal counts produce the same entries in the same order across two runs from the same snapshot (sc5); a snapshot carrying counts forward from a revalidated sync still ranks on them and is non-empty (sc6).
- [x] 2.3 GREEN create `Sources/Catalog/DiscoverRanking.swift`: `RankedPackage { rank (1-based), package, installs: InstallCount }` and `enum DiscoverRanking` with `ladderDepth = 50` and a `nonisolated static func ladder(_ kind:in:depth:)`. Eligible = matching kind, not deprecated, not disabled, `installCount365d != nil`. Order = count descending, then name ascending (total, `(name, kind)` unique). Every type explicitly `Sendable`.
- [x] 2.4 RED structural guard in `DiscoverRankingTests`: a `#filePath`-rooted read of `DiscoverRanking.swift` finds no `defaultOrder` reference and no `?? 0` coercion of an install count. `PackageSearchIndex.defaultOrder` sorts absent counts **last** — correct for search, wrong for a ranking where unmeasured must not appear at all.

## Phase 3: The curated list (**D1**, **PD-R3**, **PD-R4**)

- [x] 3.1 RED create `Tests/CatalogTests/CuratedDiscoveryTests.swift`: decoding `curated-tolerant.json` discards the unmodelled keys, skips **and counts** each of the five malformed shapes in `skippedRecordCount`, decodes every other entry, and throws nothing — one bad entry never costs the file (**PD-R3** sc2). A blurb never falls back to the package's own `desc`.
- [x] 3.2 RED same file: `curated-duplicate.json` exposes `ripgrep` exactly once, in the category that declared it **first**, with the redundant declaration counted (**PD-R3** sc3); `curated-unsorted.json` exposes categories and entries in the order the resource declared them, never re-sorted (sc4).
- [x] 3.3 GREEN create `Sources/Catalog/CuratedDiscovery.swift`: `CuratedEntry { kind, token, blurb }`, `CuratedCategory { id, title, entries }`, `CuratedDiscoveryList { categories, skippedRecordCount }` with `@concurrent` on its **own line before** `public static func decode(_:)` over `Data`, plus `shipped(from: Bundle = .module)`. `Decodable` only — encoding is not needed. Use `decodeIfPresent` and skip; never substitute a value. All types explicitly `Sendable`.
- [x] 3.4 RED `CuratedDiscoveryTests`, resolution against a snapshot: a curated resource naming formula `gone` against a snapshot without it exposes no entry for `gone` and reports an unresolved count of `1` (**PD-R4** sc1); a fully resolving list reports `0`, not absent (sc2); a category whose every token is absent disappears from the result rather than being exposed empty, with the other categories unaffected (sc3); a snapshot reporting 3 skipped records beside 2 unresolvable tokens keeps the two counts distinct — `2` and `3` (sc4).
- [x] 3.5 GREEN extend `CuratedDiscovery.swift` with resolution by `(kind, name)` against the adopted snapshot, keeping **two distinct counters**: `skippedRecordCount` (a malformed entry in the shipped file — a shipping bug) and `unresolvedEntryCount` (a valid entry with no catalog match — catalog drift). Different facts, different owners; slice 1 already paid for conflating a remainder with `skippedRecordCount`.
- [x] 3.6 Author `Sources/Catalog/Discovery/curated-discovery.json` — the v1 seed content. 3–5 named categories, 20–30 entries; each entry is kind + token + a short blurb in Cellar's voice saying *why you might want this*, never the package's `desc`. Every token must exist in the published catalog. This task authors **content**, not code; its shape is proven by 3.7 and its picks are surfaced for review in 10.3.
- [x] 3.7 RED then GREEN the shipping path: RED in `CuratedDiscoveryTests` — `CuratedDiscoveryList.shipped()` under `FAST` decodes with 3–5 categories, 20–30 entries and `skippedRecordCount == 0` (**PD-R3** sc1). It fails until GREEN adds exactly `resources: [.copy("Discovery")]` to the existing `Catalog` target in `Packages/CellarCore/Package.swift` — **one line**, matching the shipped `.copy("Fixtures")` convention. No new target, product or dependency edge.

## Phase 4: Sidecar schema, types and the file-store gate (**CS-A1**, **CS-A2**, **CS-M1**)

- [x] 4.1 RED create `Tests/CatalogTests/DiscoveryRosterTests.swift`: an encoded `KnownPackageRoster` carries identities **only** — assert no date, count or per-record payload key appears anywhere in its JSON (**CS-A1** "identities only") — and `contains(_:)` answers per kind.
- [x] 4.2 GREEN create `Sources/Catalog/DiscoveryRoster.swift`: `DiscoverySchema.currentVersion = 1` as its **own** constant, `KnownPackageRoster { schemaVersion, formulae: [String], casks: [String]; contains(_ id: PackageID) }`, `PackageArrival { kind, name, firstSeenAt }` (first observation **by this machine**, never a publication date), and `PackageArrivalsLog { retentionWindow = 30 days, retentionLimit = 1_000, schemaVersion, arrivals }`. Every type explicitly `Sendable`.
- [x] 4.3 RED (**TM3**) `DiscoveryRosterTests`: each of a missing file, `roster-corrupt.json` and `roster-wrong-version.json` reads as "seen nothing" **independently**, with nothing thrown and no failure status (**CS-A1** sc3); the same three shapes for the arrivals log each yield "no arrivals" (**CS-A2** sc4); `arrivals-undatable.json` returns its two well-formed entries with the undatable one absent and nothing thrown (**CS-A2** sc5).
- [x] 4.4 RED (**TM2**) same file: a recording `FakeCatalogFileSystem` proves each rejecting read wrote, replaced and removed **nothing** — the gate never mutates the file it rejects.
- [x] 4.5 RED `Tests/CatalogTests/FileStoreTests.swift`, independence in **both** directions: a roster and arrivals log recorded at `DiscoverySchema.currentVersion`, beside a snapshot and state sidecar at a `schemaVersion` this build no longer expects, still read as present and readable while the snapshot and state sidecar are classified as no cache (**CS-M1** *A snapshot schema bump does not invalidate an independently versioned sidecar*); and a sidecar whose own version differs in either direction is classified absent without rejecting the snapshot, nothing thrown, neither rewritten nor deleted (**CS-M1** *An additional sidecar is gated on exactly the same terms*).
- [x] 4.6 GREEN `Sources/Catalog/CatalogFileStore.swift`: add `rosterURL`/`arrivalsURL` (`catalog-roster.json`, `catalog-arrivals.json`), `loadRoster()`, `loadArrivals()` and `persistDiscovery(roster:arrivals:)`. Generalise the existing `schemaVersion(of:)` probe to take an **expected version** rather than reading `expectedSchemaVersion` implicitly, and publish through the same atomic `publish(_:to:stagedAs:)` path already used for the snapshot and sidecar. Arrivals is staged and replaced **before** the roster.

## Phase 5: Diff and retention — pure, over an injected clock (**CS-A1**, **CS-A2**)

- [x] 5.1 RED `DiscoveryRosterTests`: `advance(roster: nil, …)` is the **seeding** pass — the returned roster holds every identity in the snapshot and the arrivals log gains **zero** entries (**CS-A1** sc1, D5). This is also the corruption-recovery path: a 15,000-package snapshot after a lost roster reports `0` arrivals, never 15,000. That structural unreachability is the point of the rule.
- [x] 5.2 RED same: a second pass over a seeded roster records exactly the one identity the roster did not hold, and the roster afterwards holds every identity in the new snapshot (**CS-A1** sc2); a name removed from the catalog and later re-published does **not** re-arrive (the roster is a monotone union and never subtracts — subtraction resurrects newness); re-observing an already-logged identity keeps the earliest `firstSeenAt` and adds no second entry (**CS-A2** sc2).
- [x] 5.3 GREEN create `Sources/Catalog/DiscoveryRosterDiff.swift`: `enum DiscoveryRosterDiff` of `nonisolated static` pure functions, `advance(roster:arrivals:observing:now:) -> (roster, arrivals)`. `roster == nil` seeds and records nothing; the roster unions and never removes.
- [x] 5.4 RED `DiscoveryRosterTests` retention, driven by an injected `now` and never by `Date()`: an entry 29 d 23 h old is listed and one 30 d 1 h old is gone (**CS-A2** sc3); 1,001 entries cap to 1,000 dropping the **oldest** first (an entry the cap drops is by construction closest to expiry, so cap and window agree); `pruned(now:)` is idempotent; read-time pruning alone yields the 30-day answer with no sync having run.
- [x] 5.5 GREEN add `PackageArrivalsLog.pruned(now:)` in `DiscoveryRoster.swift`, applied at **both** read and write: read-time pruning makes the 30-day rule true regardless of sync cadence, write-time pruning bounds the file. `now` is a parameter — no `Date()` inside the logic. Reuse the shipped `CatalogTimeSource` at the call site; introduce no second date-provider protocol.

## Phase 6: Sync integration (**CS-A1**, **CS-A2**, **CS-M2**)

- [x] 6.1 RED `Tests/CatalogTests/SyncEngineTests.swift`: a sync that publishes a **new** snapshot writes both sidecars, and the recording file system proves arrivals was replaced **before** the roster. This is the crash-order choice: a crash between the two costs a repeated arrival deduped by earliest-`firstSeenAt`, while the reverse order loses the arrival permanently.
- [x] 6.2 RED same: a sync whose payloads all revalidated (304) writes **neither** sidecar, leaves both byte-identical and records no arrivals (**CS-A1** sc5). Diffing on a revalidated sync is a guaranteed no-op costing a roster read and a 16k compare.
- [x] 6.3 RED same: a file store whose roster write fails while the snapshot and state writes succeed still reports the sync **successful**, with the snapshot persisted and served and the state sidecar intact (**CS-A1** sc4); repeat for an arrivals write failure. A roster failure costs newness for one sync, never the sync.
- [x] 6.4 GREEN `Sources/Catalog/CatalogSyncEngine.swift`: add `arrivals()` mirroring `cachedSnapshot()`, and a never-fatal `recordArrivals(in:at:)` invoked after a successful `persist` on the new-snapshot path of `performSync` only, using `timeSource.now`. Wrap it so no failure can reach the sync's result.
- [x] 6.5 RED (**TM1**, **PD-R2**) `Tests/CatalogTests/AcquisitionScopeTests.swift`: with a recording `FakeCatalogSource` and a recording process launcher, a sync that updates the roster and records arrivals issues exactly the payload and analytics requests the previous build issued — no additional resource, no per-package request, zero brew spawns (**CS-M2** sc3); and the catalog directory afterwards holds exactly `catalog.json`, `catalog-state.json`, `catalog-roster.json` and `catalog-arrivals.json`, nothing else (**CS-M2** sc2).

## Phase 7: Projection and typed section states (**PD-R2**, **PD-R5**, **PD-R6**)

- [x] 7.1 RED create `Tests/CatalogTests/DiscoverProjectionTests.swift`: an arrivals log recording formula `newpkg` first observed 3 days ago, against a snapshot containing it, projects `newpkg` carrying that first-observed date (**PD-R5** sc1); an entry 31 days old is not projected (sc2); an entry 5 days old naming a package the snapshot no longer contains is dropped with nothing thrown (sc3); entries are ordered newest first; a log exceeding `arrivalDisplayLimit` (30) yields the exact `hiddenArrivalCount`.
- [x] 7.2 RED same file, honest phrasing as a **test** (**PD-R5** sc4): the explanatory copy CellarCore supplies for the arrivals section — in both its populated and empty forms — describes the packages as first seen by this Mac, and contains none of `published`, `release date`, `added to Homebrew`, `new on Homebrew`, `recently added`, `newly released`. The copy lives in CellarCore precisely so a test owns it rather than a view.
- [x] 7.3 RED same file (**PD-R6**): each section exposes a **typed** state — populated, empty-with-a-named-reason, or awaiting-catalog — never an empty collection paired with an empty string, never a failure, never pending while the catalog is available. First run: arrivals reports the empty "measured from this sync onward" state while both ladders and the curated list are populated (sc1). A snapshot in which every install count is absent: each ranked section reports "no eligible ranked package" with a count of `0`, and curated is still populated (sc2). No adopted snapshot: every section reports awaiting-catalog, nothing thrown, no failure (sc3). No result may have every section empty with none explaining itself.
- [x] 7.4 GREEN create `Sources/Catalog/DiscoverContent.swift`: `ArrivalRow { package, firstSeenAt }`, the typed per-section state, `DiscoverContent { topFormulae, topCasks, curated, curatedSkippedRecordCount, curatedUnresolvedCount, newToYou, hiddenArrivalCount, .empty }`, and `enum DiscoverProjection` with `nonisolated static func content(snapshot:curated:arrivals:now:arrivalDisplayLimit: = 30)`. **Design amendment to record, not absorb:** the design's flat field list does not name the typed states **PD-R6** requires; the spec governs, so the typed state lands here and the widening is written into `design.md` in task 10.2.
- [x] 7.5 RED `Tests/CatalogTests/CatalogAdoptionTests.swift`: after `adopt`, `CatalogStore.discover` is populated in the **same** main-actor assignment as `index`, so there is no observable state in which the index is new and `discover` is stale; a duplicate or older revision costs no second projection, inheriting the existing revision-ordinal dedup.
- [x] 7.6 GREEN `Sources/Catalog/CatalogStore.swift`: one new `private(set) var discover: DiscoverContent`, projected **off** the main actor inside the existing adoption `Task` and assigned alongside `index` and `packageCount`. No new store, no new actor, no second `events` iterator — the engine's stream supports exactly one.

## Phase 8: Bounds, egress and structural guards (**CS-M1**, **CS-A1**, **CS-A2**)

- [x] 8.1 RED create `Tests/CatalogTests/DiscoverySidecarFootprintTests.swift` over the shipped synthetic corpus (7,684 casks + 8,530 formulae): the encoded roster is `<= 0.06×` the encoded snapshot **and** `<= 512 KB`; a full 1,000-entry arrivals log is `<= 64 KB`. Ratios as well as absolutes, for machine independence, as slice 1 recorded.
- [x] 8.2 RED regression (**CS-M1** *New durable state does not move the snapshot bound*): `Tests/CatalogTests/CatalogFootprintTests.swift` runs **unchanged** — no edited bound, no re-based value, a zero-line diff — and passes beside a build that persists both sidecars. Do not touch that file; the 1.56× against 1.6× headroom is the gate this slice is checked against.
- [x] 8.3 RED structural (**CS-A1** *The snapshot is untouched*): assert `CatalogPackage`'s stored-property set is unchanged, that `Sources/Catalog/CatalogModels.swift` contains no `firstSeen`/`arrival`/`roster`/`seenness` identifier, and that `CatalogSnapshot.currentSchemaVersion` is still `2`.
- [x] 8.4 RED structural: the discovery sources contain no `CatalogSnapshotRevision` reference — newness must never derive from a process-local ordinal that restarts at 1 on every launch, which is the mechanism correction this slice exists to honour.

## Phase 9: App layer — the `.discover` section (**D4**, presentation only)

- [x] 9.1 RED create `cellarTests/DiscoverCompositionTests.swift`: `CuratedDiscoveryList.shipped()` resolves from the **built** `.app`, returning the same 3–5 categories and 20–30 entries `FAST` saw. This is the gate that catches a SwiftPM resource bundle which passes `swift test` and is missing at runtime.
- [x] 9.2 RED same file (**TM4**): a `#filePath`-rooted scan of `cellar/Discover/` and the Catalog discovery sources — comments stripped first, per the shipped `SecurityCompositionSupport` idiom — finds none of `published`, `release date`, `added to Homebrew`, `new on Homebrew`, `recently added`; and no `Link`, no bare `URL(string:)` over catalog text, and no shell interpolation.
- [x] 9.3 RED same file: the row and section models are plain `nonisolated` value types testable without a view — they emit a row per **resolved** entry only, carry 1-based ranks, and label each ladder with the metric matching its kind.
- [x] 9.4 GREEN `cellar/Shell/AppSection.swift`: add `case discover` **between** `.home` and `.browse`, title `"Discover"`, `systemImage` `sparkles`. Update both `switch` bodies — the enum is switched exhaustively by design.
- [x] 9.5 GREEN `cellar/ContentView.swift`: add the `.discover` content-column case (beside the existing `case .home` / `case .browse` arms, ~line 81) and join `.discover` to the existing detail-column `case .browse, .installed` (~line 181). `cellar/cellarApp.swift` needs **no** change — `catalog` is already constructed and injected. Scope reduction against the proposal's file table, recorded rather than absorbed.
- [x] 9.6 GREEN create `cellar/Discover/{DiscoverView,DiscoverLadderSection,DiscoverCuratedSection,DiscoverNewToYouSection}.swift`: presentation only, reading `CatalogStore.discover`. Names and descriptions render as `Text` exactly as Browse does. The empty arrivals state renders the CellarCore-supplied copy — never a spinner, never a hidden section (**D5**).
- [x] 9.7 Confirm the Xcode project needs **no** edit: `cellar/` is a `PBXFileSystemSynchronizedRootGroup`, so `cellar/Discover/` joins the target by existing on disk (slice 1 confirmed this for `cellar/Browse/`). Run `FULL` to prove it compiled into the app target. If the group turns out not to cover it, add a file reference only — no target-membership, build-setting or scheme edit.
- [x] 9.8 RED then GREEN in `cellarUITests`: `.discover` sits between Home and Browse in the sidebar; all three sections render; a first-run profile shows the explanation rather than a spinner or an empty screen.

## Phase 10: Close-out

- [x] 10.1 Run `FAST`, `APP`, `FULL` green. Confirm the `@Test` count is strictly above the pre-change count and that no pre-existing assertion was deleted or weakened — `git diff -U0` over `Tests/` and `cellarTests/` must remove no assertion line, and `CatalogFootprintTests.swift` must show a **zero-line** diff.
- [x] 10.2 Document where the next reader looks: the new fixtures in `Tests/CatalogTests/Fixtures/README.md`; a doc comment on `DiscoverySchema.currentVersion` stating **why** it is independent of the snapshot's (a snapshot bump must never erase a user's 30-day history); and, in `design.md` under *Apply-Time Amendments*, the typed-section-state widening from 7.4 plus any other evidence-forced change — recorded, never absorbed silently.
- [x] 10.3 Surface the curated seed list authored in 3.6 to the user for a content review before the PR opens. Task 3.7 proves well-formedness and completeness; it does not prove the picks are good. This is the design's first Open Question and it closes here, not at verify. — User reviewed the 25 entries / 5 categories on 2026-08-06 and approved as-is.
