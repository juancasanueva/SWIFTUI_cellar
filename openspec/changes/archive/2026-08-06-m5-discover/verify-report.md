```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:fcc103c71f223024146482078c2d6bf0b4124088440c8e231b05c06082cf9c25
verdict: pass
blockers: 0
critical_findings: 0
requirements: 10/10
scenarios: 46/46
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
test_exit_code: 0
test_output_hash: sha256:1ba6c29a4e111d7b0fbf473e4cb8b9ff92d1bad4f4c110dfdef835f80a607c93
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:fbcbe0db27118c9457d00a892417dfccfd276142be03ac9b38bd9153a74e93a1
```

## Verification Report

**Change**: m5-discover (M5 slice 2 of 5 — Discover tab)
**Version**: package-discovery ADDED-only (6 req / 23 sc); catalog-sync delta 2 MODIFIED + 2 ADDED (4 req / 23 sc)
**Mode**: Strict TDD
**Pass**: verify-2 (re-verification after the CS-A2 sc3 remediation; the verify-1 pass returned FAIL on that one scenario)
**Artifacts read**: proposal (obs 7492), spec (obs 7494), design (obs 7495), tasks (obs 7496), apply-progress (obs 7497), plus the on-disk `openspec/changes/m5-discover/` copies.

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 52 |
| Tasks complete | 52 |
| Tasks incomplete | 0 |

`openspec/changes/m5-discover/tasks.md` carries 52 `- [x]` and zero `- [ ]`. Task 10.3 closes with the recorded user content approval of the 25 curated picks (2026-08-06). The Engram `tasks` artifact now also reads 52/52 (revision 3) and records the remediation.

### Build & Tests Execution

**Build**: PASSED — `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`, exit 0, `** BUILD SUCCEEDED **`, zero `error:` and zero `warning:` lines.

**Tests** — all three suites re-run independently by this phase, not taken from the apply report:

| Command | Result | Exit |
|---|---|---|
| `swift test --package-path Packages/CellarCore` | **1213 tests in 162 suites passed**, 1 known issue (was 1212 — the remediation test is the +1) | 0 |
| `xcodebuild test … -only-testing:cellarTests` | **56 test cases passed, 0 failed** (49 distinct `@Test`; 10 are `DiscoverCompositionTests`) | 0 |
| `xcodebuild test …` (FULL, incl. `cellarUITests`) | **`** TEST SUCCEEDED **`**, 23 XCUITest cases, 0 failures, 0 activation errors | 0 |

The single known issue is pre-existing: `OperationCenterCancelTests.swift:183` ("Finishing a call that never launched fails this test instead of crashing the suite"). That file is untouched by this change (`git status` clean for it), so it is not a regression introduced here.

Independent count reconciliation: apply reported 57 `cellarTests` cases; this phase measured 56 passing case invocations. The Discover contribution is exactly the 10 apply claimed. The 1-case delta is a counting-method difference (parameterized cases expand to 5 and 4 invocations respectively), not a missing or failing test. Recorded as a SUGGESTION rather than treated as evidence contradiction.

**Coverage**: `-enableCodeCoverage YES` is available per `openspec/config.yaml` with `threshold: 0`. Not run — a zero threshold makes it non-blocking, and the full suite already costs ~5 minutes. Reported as skipped rather than claimed.

### Spec Compliance Matrix — package-discovery (6 req / 23 sc)

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| PD-R1 Two separate ladders | Formulae and casks rank on separate ladders | `DiscoverRankingTests > Formulae and casks rank on separate ladders, each on its own metric` | COMPLIANT |
| PD-R1 | A package with no analytics entry is absent, not last | `DiscoverRankingTests > A package with no analytics entry is absent from the ladder, not last` + `A zero published count is a measurement and still ranks` | COMPLIANT |
| PD-R1 | Deprecated and disabled packages are ineligible | `DiscoverRankingTests > Deprecated and disabled packages are ineligible for either ladder` | COMPLIANT |
| PD-R1 | A short catalog yields a short ladder | `DiscoverRankingTests > A short catalog yields a short ladder rather than a padded one` | COMPLIANT |
| PD-R1 | Equal counts order deterministically | `DiscoverRankingTests > Equal counts order deterministically across runs` | COMPLIANT |
| PD-R1 | Carried-forward counts still rank | `DiscoverRankingTests > Counts carried forward by a revalidated sync still rank` | COMPLIANT |
| PD-R2 Discover costs no acquisition | Opening Discover issues no request | `DiscoverProjectionTests > Producing every projection issues no request and reads no new file` | COMPLIANT |
| PD-R2 | Discover resolves offline and without brew | `AcquisitionScopeTests > The discovery sources cannot reach a subprocess at all` + `DiscoveryStructuralGuardTests` (no `BrewProcess` import, no `URLSession`/`URLRequest`/`Process(` in any discovery source) | COMPLIANT |
| PD-R3 Curated ships and decodes tolerantly | The shipped resource loads through the shipping accessor | `DiscoverCompositionTests > The curated list resolves from the built application bundle` (loaded from the built `.app`, 3–5 categories / 20–30 entries / `skippedRecordCount == 0`) + `CuratedDiscoveryTests > The shipped curated list decodes through the accessor the app uses` | COMPLIANT |
| PD-R3 | Unknown fields and malformed entries are tolerated | `CuratedDiscoveryTests > Unknown fields are discarded and every malformed entry is skipped and counted` + `A blank blurb is skipped rather than filled in from somewhere else` | COMPLIANT |
| PD-R3 | A duplicate token resolves once | `CuratedDiscoveryTests > A duplicate token resolves once, in the category that declared it first` | COMPLIANT |
| PD-R3 | Declared order survives decoding | `CuratedDiscoveryTests > Declared category and entry order survives decoding` | COMPLIANT |
| PD-R4 Unresolved entries skipped and counted | A removed token never becomes a dead row | `CuratedDiscoveryTests > A token the snapshot no longer holds is skipped, counted, and never a dead row` | COMPLIANT |
| PD-R4 | A fully resolving list counts zero skips | `CuratedDiscoveryTests > A fully resolving list reports zero unresolved, not absent` | COMPLIANT |
| PD-R4 | A category emptied by skips disappears | `CuratedDiscoveryTests > A category emptied by skips disappears while its siblings are unaffected` | COMPLIANT |
| PD-R4 | Curated skips are their own count | `CuratedDiscoveryTests > Curated skips are their own count, distinct from the snapshot's` + `DiscoverProjectionTests > A curated list whose every token is unresolvable names its own reason` | COMPLIANT |
| PD-R5 New to you, 30 days | A package first seen inside the window is listed with its date | `DiscoverProjectionTests > A package first seen inside the window is projected with its first-observed date` | COMPLIANT |
| PD-R5 | An entry beyond the window is not projected | `DiscoverProjectionTests > An entry beyond the thirty-day window is not projected` | COMPLIANT |
| PD-R5 | A package that left the catalog is not projected | `DiscoverProjectionTests > An arrival whose package left the catalog is dropped and nothing is thrown` | COMPLIANT |
| PD-R5 | The shipped explanation claims first observation, not publication | `DiscoverProjectionTests > The arrivals copy claims first observation by this Mac, never publication` (both states, 6 forbidden claims) + `DiscoverCompositionTests > No Discover source claims a package is new to Homebrew` + `DiscoverSectionUITests > testAFirstRunExplainsItselfRatherThanSpinningOrBlanking` (same rule against rendered pixels) | COMPLIANT |
| PD-R6 Typed states, never opens empty | First run explains the empty arrivals section and still shows the rest | `DiscoverProjectionTests > First run explains the empty arrivals section and still shows the rest` + `DiscoverSectionUITests > testDiscoverShowsEverySectionOnAFirstRun` | COMPLIANT |
| PD-R6 | An empty section names its reason rather than blanking | `DiscoverProjectionTests > An empty ranked section names its reason and reports a count of zero` + `No section is ever an empty collection without a stated reason` | COMPLIANT |
| PD-R6 | No usable catalog is awaiting, not failed | `DiscoverProjectionTests > No adopted snapshot is awaiting-catalog, not a failure` | COMPLIANT |

**package-discovery: 23/23 compliant.**

### Spec Compliance Matrix — catalog-sync delta (4 req / 23 sc)

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| CS-M1 Slim projection + state sidecar (9 sc) | State sidecar round-trips | `FileStoreTests` (carried forward byte-identical, re-run green) | COMPLIANT |
| CS-M1 | Unknown schema version is treated as no cache | `FileStoreTests` (carried forward) | COMPLIANT |
| CS-M1 | A snapshot written by the previous schema is a cold start | `FileStoreTests` (carried forward) | COMPLIANT |
| CS-M1 | A sidecar written by the previous schema is rejected independently | `FileStoreTests` (carried forward) | COMPLIANT |
| CS-M1 | Rollback is symmetric | `FileStoreTests` (carried forward) | COMPLIANT |
| CS-M1 | The full-catalog footprint stays within its recorded bound | `CatalogFootprintTests` 2/2, **zero-line diff vs HEAD proven by `git diff --numstat` returning nothing and the file being absent from `git status`** | COMPLIANT |
| CS-M1 | New durable state does not move the snapshot bound | `CatalogFootprintTests` unchanged and green in the same build that persists both sidecars, plus `DiscoverySidecarFootprintTests` carrying the two new bounds separately | COMPLIANT |
| CS-M1 | An additional sidecar is gated on exactly the same terms | `FileStoreTests > A sidecar whose own version differs, either way, is absent without costing the snapshot` (both `currentVersion − 1` and `+ 1`) + `DiscoveryRosterTests > Rejecting a sidecar writes, replaces and removes nothing` | COMPLIANT |
| CS-M1 | **A snapshot schema bump does not invalidate an independently versioned sidecar** | `FileStoreTests > A snapshot schema bump does not invalidate an independently versioned sidecar` — snapshot and state classified as no cache while the roster and the 30-day arrivals log stay readable | COMPLIANT |
| CS-M2 Inspection costs no acquisition (3 sc) | Inspection fields resolve offline and without brew | `AcquisitionScopeTests` (carried forward) | COMPLIANT |
| CS-M2 | The widened sync issues no additional request | `AcquisitionScopeTests` — the directory listing assertion now reads exactly `["catalog-arrivals.json", "catalog-roster.json", "catalog-state.json", "catalog.json"]` | COMPLIANT |
| CS-M2 | Deriving newness issues no request | `AcquisitionScopeTests > A sync that records arrivals issues no additional request and spawns no process` | COMPLIANT |
| CS-A1 Durable roster (6 sc) | The first sync seeds the roster and reports no arrivals | `SyncEngineTests > A sync that publishes a new snapshot writes arrivals before the roster` + `DiscoveryRosterTests > An absent roster seeds and records no arrival at all` + `A lost roster re-seeds against a full catalog and still reports zero arrivals` (14,999 packages, zero arrivals) | COMPLIANT |
| CS-A1 | The second sync reports only what the roster had not seen | `SyncEngineTests > A second sync records only the package the roster had not seen` + `DiscoveryRosterTests > A second sync records exactly the identity the roster did not hold` | COMPLIANT |
| CS-A1 | A missing, corrupt or mismatched roster means "seen nothing" | `DiscoveryRosterTests > A missing, corrupt or mismatched roster all mean 'seen nothing'` + `Rejecting a sidecar writes, replaces and removes nothing` (recording `FakeCatalogFileSystem`: `operations.isEmpty`) | COMPLIANT |
| CS-A1 | A roster write failure does not fail the sync | `SyncEngineTests > A roster write failure leaves the sync successful and the snapshot served` | COMPLIANT |
| CS-A1 | An unchanged sync produces no arrivals | `SyncEngineTests > A fully revalidated sync writes neither sidecar and leaves both byte-identical` | COMPLIANT |
| CS-A1 | The snapshot is untouched and stays within its bound | `DiscoveryStructuralGuardTests > The snapshot gained no newness field and did not move its schema version` (22-label `Mirror` reflection, 4 forbidden identifiers in `CatalogModels.swift`, `currentSchemaVersion == 2`) + `DiscoverySidecarFootprintTests > The roster stays within its own recorded bound at full catalog scale` | COMPLIANT |
| CS-A2 Dated arrivals log (5 sc) | A newly observed package is dated on first observation | `SyncEngineTests > A second sync records only the package the roster had not seen` (`firstSeenAt == harness.time.now`) | COMPLIANT |
| CS-A2 | A re-observed package keeps its original date | `DiscoveryRosterTests > Re-observing a logged arrival keeps the earliest date and adds no second entry` | COMPLIANT |
| CS-A2 | An entry beyond the window is pruned on the next write | Read half: `DiscoveryRosterTests > Read-time pruning alone gives the thirty-day answer with no sync having run` + `SyncEngineTests > The engine serves the arrivals log already pruned to the window` + `The window keeps an entry at 29d 23h and drops one at 30d 1h`. **Write half now covered** by `SyncEngineTests > An expired arrival is removed from the file by the next write` — seeds the persisted log with a 31-day-old and a 2-day-old entry, asserts the stale one is really in the bytes first, syncs on the diffing path, then re-reads `store.arrivalsURL` and asserts it is gone while `freshpkg` and the newly arrived `newpkg` remain. | COMPLIANT |
| CS-A2 | An unreadable log means "no arrivals" | `DiscoveryRosterTests > A missing, corrupt or mismatched arrivals log all mean 'no arrivals'` + `The roster and the arrivals log are gated independently of each other` | COMPLIANT |
| CS-A2 | An undatable entry is dropped, not fatal | `DiscoveryRosterTests > An undatable arrival is dropped while its well-formed siblings survive` | COMPLIANT |

**catalog-sync delta: 23/23 compliant.**

**Compliance summary: 46/46 scenarios compliant, 0 partial, 0 untested, 0 failing.**

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| `CatalogPackage` / `CatalogSnapshot` frozen | Implemented | `git diff --numstat -- CatalogModels.swift` returns nothing; the file is absent from `git status`. 22 stored properties, `currentSchemaVersion == 2`. |
| `CatalogFootprintTests` zero-line diff | Implemented | Independently confirmed: no numstat output, not listed in `git status`, suite green. |
| pbxproj unchanged | Implemented | `git diff --numstat -- cellar.xcodeproj/project.pbxproj` returns nothing. `cellar/Discover/` is a synchronized root group. |
| Independent sidecar versioning | Implemented | `DiscoverySchema.currentVersion = 1` is its own constant; `CatalogFileStore.records(_:in:)` takes the expected version as a parameter, so snapshot, state sidecar and both newness sidecars share one gate while answering different schemas. |
| Arrivals written before roster | Implemented | `persistDiscovery` publishes `catalog-arrivals.json` then `catalog-roster.json`; asserted as an ordered `publishedPaths` list by the recording file system. |
| Absent roster seeds with zero arrivals | Implemented | `DiscoveryRosterDiff.advance`'s `guard let roster else` branch has no path to an appended arrival — structurally unreachable, and proven at 14,999 packages. |
| Absent install count never coerced | Implemented | One `guard let installs = package.installCount else { return nil }`; no `?? 0`, no `defaultOrder` reuse (asserted textually). |
| Zero egress | Implemented | No `URLSession`, `URLRequest`, `Process(`, `launchctl`, `/opt/homebrew` or `import BrewProcess` in any of the five discovery sources; `Catalog` has no `BrewProcess` dependency edge. |
| Curated bounds (D1) | Implemented | `curated-discovery.json`: **5 categories, 25 entries**, all 25 `(kind, token)` pairs unique, every entry carries exactly `kind`/`token`/`blurb`, no blank blurb. |
| Curated tokens resolve | Implemented | Independently re-verified live via `brew info --json=v2` for all 25 tokens: **18/18 formulae and 7/7 casks resolve, zero deprecated, zero disabled**. |

### Coherence (Design) — the 8 apply-time amendments adjudicated

| # | Amendment | Verdict |
|---|---|---|
| 1 | Typed per-section state replaces the flat `DiscoverContent` field list | **Consistent with spec.** PD-R6 requires a typed value naming why a section is empty; the design's bare-collection sketch could not satisfy it. The spec correctly governed over the design. `snapshot:` becoming optional follows from PD-R6's awaiting-catalog scenario. |
| 2 | `shipped(from: Bundle = .module)` split into two overloads | **Consistent with spec.** Compiler-forced — SwiftPM emits `Bundle.module` as `internal`, which cannot be a `public` default argument. No behavioural change; PD-R3's "the accessor the app uses" is still one call, and the built-`.app` test exercises it. |
| 3 | `CuratedDiscoveryList` is `Decodable`, not `Codable` | **Consistent with spec.** Nothing encodes a curated list; `Encodable` would be an unused conformance. Matches the `swift-codable` guidance to prefer `Decodable` for read-only resources. |
| 4 | `loadRoster()`/`loadArrivals()`/`recordArrivals` non-throwing by signature | **Consistent with spec, and stronger than required.** CS-A1/CS-A2 say classification MUST NOT be reported as an error; a non-throwing signature makes the violation unrepresentable rather than merely untested. |
| 5 | `DiscoverProjection.build` (`@concurrent`) added beside pure `content` | **Consistent with spec.** Mirrors the shipped `PackageSearchIndex.build`; every unit test still calls the pure `content`, so the purity the design promised is preserved. |
| 6 | `CatalogSyncEngine.now` exposed | **Consistent with spec.** Keeps `CatalogTimeSource` the single clock seam; the alternative was a second, untestable notion of now in the app layer. |
| 7 | `cellarApp.swift` changed after all — one line, a UI-test seam | **Consistent with spec, correctly recorded rather than absorbed.** The design's claim was "no *wiring* change", and that still holds: `catalog` is constructed and injected exactly as before. The edit routes the catalog directory through `AppTestFixtures.catalogDirectory`, which returns `CatalogStore.defaultDirectory()` unless `--ui-testing-m5-discover` is present. It follows the M3/M4 fixture convention already in that file and is the only way a UI test can reach a genuine first run. Not a defect; see SUGGESTION 5 for the residual note. |
| 8 | Sidebar rows gained accessibility identifiers | **Consistent with spec.** A pure testability affordance (`.accessibilityIdentifier("sidebar-\(item.rawValue)")` on the existing `Label`), and the fix for the label/navigation-title collision that made the first UI-test draft unable to assert. |

No amendment requires a spec amendment; none is a defect.

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | Yes | "TDD Cycle Evidence" table present in `apply-progress` (obs 7497), 46 rows |
| All tasks have tests | Yes | Every behavioural task names a test file; all named files exist on disk |
| RED confirmed (tests exist) | Partial | Every row of the TDD Cycle Evidence table records an observed RED except one. Task **6.5** honestly records "not separately observed" (guard written after its subject). Adjudicated below. |
| GREEN confirmed (tests pass) | Yes | Every named test file executed and passed in this phase's own runs |
| Triangulation adequate | Yes | Multi-case triangulation on every multi-scenario requirement (5 malformed curated shapes, 6 hostile sidecar shapes, 3 shapes × 2 files, both version directions, 4 retention cases) |
| Safety Net for modified files | Yes | Every modified file row records a pre-modification pass count; `N/A (new)` rows correspond to genuinely new files |

**Task 6.5 adjudication (the honestly flagged soft spot).** The guard is **anchored and would fail on the violation it polices**, so the unobserved RED is a process deviation and not a hole:

- The four-file directory assertion is an exact `==` against a sorted list. A fifth persisted artefact, a missing sidecar, or a retained raw payload each fail it. It replaced a two-file assertion that would necessarily have failed against the new build — the RED existed, it simply was not captured as a separate step.
- `derivingNewnessIssuesNoRequest` carries two **positive controls before** its silence assertions: `#expect(harness.store.loadRoster() != nil, "the roster was not seeded, so nothing diffed")` and `#expect(harness.store.loadArrivals()?.arrivals.map(\.name) == ["newpkg"])`. The diffing branch is therefore proven to have run, so the request-count silence is the silence of work that happened.
- `discoverySourcesCannotSpawnAProcess` loops a hardcoded five-name array through `CatalogSources.code(of:)`, which throws on a missing file, and calls `assertAnchored(code, expecting: "public")` — an empty or moved read fails rather than passing vacuously.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (CellarCore) | 60 new `@Test` across the 5 new suites (9 + 13 + 20 + 13 + 5) plus additions to `FileStoreTests` and `CatalogAdoptionTests` | 5 new + 3 modified | swift-testing |
| Integration (sync engine, acquisition scope) | 8 new `@Test` | 2 modified | swift-testing |
| App target | 10 cases | 1 new | swift-testing (`cellarTests`) |
| E2E | 3 cases | 1 new | XCUITest (`cellarUITests`) |
| **Total (whole repo, after)** | **1212 core + 56 app + 23 UI** | | |

### Assertion Quality

Audited all seven new/modified Discover test files (278 `#expect`/`XCTAssert` sites).

- Tautologies: **none**. No `#expect(true)`, `#expect(1 == 1)` or `XCTAssertTrue(true)`.
- Ghost loops: **none**. Every `for` loop iterates a hardcoded literal array (3 or 5 elements) whose element construction `throw`s on a missing fixture, so an empty collection fails instead of silently passing.
- Orphan empty checks: **none unpaired**. Every `isEmpty` / `== 0` assertion has a companion non-empty assertion in the same test — e.g. `absentRosterSeedsWithZeroArrivals` asserts the full roster (`["git","wget"]`, `["iterm2"]`) *before* asserting zero arrivals; `lostRosterDoesNotReportTheWholeCatalogAsNew` asserts `roster.formulae.count == 14_999` beside the empty arrivals.
- Type-only assertions used alone: **none**.
- Smoke-test-only: **none**. The XCUITest cases assert frame ordering, sentence content, forbidden-claim absence and `progressIndicators.count == 0`, not mere existence.
- Structural/textual guards: all four carry an explicit positive anchor (`CatalogSources.assertAnchored`, `sources.contains { $0.code.contains("DiscoverView") }`, `#expect(sources.isEmpty == false)`), which is precisely the defence against a prohibition scan that passes by reading nothing.

**Assertion quality: 0 CRITICAL, 0 WARNING — all assertions verify real behaviour.**

Two flagged soft spots re-checked and cleared:

1. **The previously vacuous UI test now genuinely asserts.** `testAFirstRunExplainsItselfRatherThanSpinningOrBlanking` queries `discover-section-note` by identifier, reads `note.value` (falling back to `label`), and then asserts non-emptiness, membership in the two `DiscoverCopy` sentences, zero progress indicators, and absence of all five forbidden claims. The earlier `XCUIElementQuery.containing` form filtered by descendants rather than labels and matched nothing; `matching(identifier:).firstMatch` plus `waitForExistence` cannot pass without a real element.
2. **The arrivals footprint bound is tight but not flaky.** The corpus is fully deterministic — 1,000 entries, alternating kinds, names built by `String(format: "%07d"/"%012d")` to the live-measured means (8 and 13 characters), dates at fixed 60-second offsets, `.secondsSince1970` encoding. There is no randomness, so ~63 KB against the 64 KB ceiling cannot flake; it can only break deterministically if `PackageArrival` gains a field or the date strategy changes. The test additionally asserts its own generator (`allSatisfy { $0.count == realFormulaNameLength }`, `formulaNames.count == 500`), so a silently shortened corpus fails rather than flattering the bound. Recorded as WARNING 2 for future brittleness only.

### Quality Metrics

**Linter**: 1 warning — `cellar/Discover/DiscoverSectionModels.swift:9:1 orphaned_doc_comment`. SwiftLint 0.65.0 with default rules (the repo carries no `.swiftlint.yml`).
**Type Checker**: no errors — `xcodebuild build` exit 0 with zero `error:` and zero `warning:` lines.

### Review Workload

| Measurement | Lines |
|---|---|
| Tracked modifications (14 files) | 699 added + 13 deleted = **712** (was 650; +62 is the remediation test) |
| New untracked source, tests, fixtures and curated JSON (26 files) | **3,745** |
| **Authored source + tests total** | **4,457** — within the 5,000 session budget |
| SDD lifecycle artifacts under `openspec/changes/m5-discover/` (5 files, excl. this report) | 1,202 |
| Grand total including lifecycle artifacts | 5,659 |

Authored source+tests is the figure the guard measures and it is inside budget with ~540 lines of headroom. The grand total including the lifecycle documents exceeds 5,000; recorded honestly as SUGGESTION 4 rather than silently netted out. No `size:exception` is required.

### Remediation verification (verify-1's CRITICAL)

The verify-1 pass returned FAIL on one scenario: catalog-sync CS-A2 sc3's write half — "the file afterwards holds only the 2-day-old entry" — had no covering test. That is now closed.

**Scope of the delta, independently confirmed.** `git diff --numstat` shows one changed file since my verify-1 evidence: `SyncEngineTests.swift` at 204 added lines against 142 before, exactly +62. Every other tracked file's add/delete counts are byte-for-byte identical to what I recorded in verify-1 (`Package.swift` 1+, `CatalogFileStore` 71+/6−, `CatalogStore` 37+, `CatalogSyncEngine` 46+, `AppTestFixtures` 23+, `ContentView` 13+/3−, `AppSection` 10+, `cellarApp` 6+/1−), and the untracked authored total is unchanged at 3,745 lines across the same 26 files. **No production code changed.** The only other movement is the two artifact tidy-ups I asked for: `design.md` +4 lines ticking the curated-content Open Question with a closure note, and the Engram `tasks` topic revised to 52/52.

**The test does what the scenario asks.** `SyncEngineTests > An expired arrival is removed from the file by the next write`:

- Observes the **file**, not the projection. It reads raw `Data(contentsOf: harness.store.arrivalsURL)` and inspects the bytes as a string. It never calls `store.loadArrivals()` or `engine.arrivals()` — both of which prune on read and would have masked a missing write-side prune entirely. This is precisely the distinction verify-1 flagged.
- Carries a **positive control before** the assertion: `#expect(before.contains("stalepkg"))` proves the expired entry really was in the persisted bytes, so the later assertion is about a removal rather than an absence that was always there.
- Takes the **diffing path, not the seeding path** — a first sync seeds the roster, so the sync under test enters `advance`'s non-seeding branch, which is where the prune being policed lives. Had it taken the seeding branch it would have exercised a different line and caught nothing.
- **Distinguishes pruning from truncation**: `reloaded.arrivals.map(\.name).sorted() == ["freshpkg", "newpkg"]` requires the in-window entry to survive *and* the genuinely new package to be recorded. A write that simply cleared the file would pass a bare "stalepkg is gone" check and fail this one.

**The mutation claim holds up.** I am read-only, so I assessed it statically rather than re-running it. Removing `.pruned(now:)` from `advance`'s non-seeding branch would persist `previous.arrivals + newpkg` unpruned, so `stalepkg` would survive into the file — failing exactly three assertions in this test: the raw-bytes `contains(...) == false`, the sorted-names equality, and the decoded `contains { $0.name == "stalepkg" } == false`. The reported count of **3 issues** matches the number of post-write assertions exactly, which is not a number that falls out by chance. "And no other test" also checks out: every other `DiscoveryRosterDiff.advance` call site in the suite passes `nil`, `.empty`, a freshly-derived log, or a 10-day-old entry — none an expired one — and every engine-level arrivals assertion reads through a pruning-on-read path. So this test is the only thing standing between the codebase and a silently unbounded arrivals file, which is what makes it load-bearing and which vindicates raising the gap as a blocker rather than a note.

Both branches of `advance` still call `.pruned(now: now)` (lines 37 and 55), confirming the mutation was reverted.

### Issues Found

**CRITICAL**: None. The verify-1 blocker is resolved and independently re-checked — see "Remediation verification" above.

**WARNING**:

1. **The XCUITest suite has a non-deterministic app-activation failure mode, unrelated to this change.** My first re-verification run of the declared full command exited **65**, with **17 of 23** UI tests failing — including M3/M4 tests this change never touches (`testLaunchPerformance`, the whole `testCleanupCO7*` family, `SecurityIdentityUITests`). Every failure was the identical XCTest infrastructure error, `Failed to activate application 'com.juancasanueva.cellar' (current state: Running Background)`, each timing out at ~61.6 s; not one was an assertion failure. The tests that passed were the alphabetically *last* ones, so the condition afflicted the start of the run and cleared partway through — a transient foreground-focus problem on the host, not a code fault. I confirmed non-reproducibility rather than assuming it: an immediate `-only-testing:cellarUITests` re-run passed **23/23, exit 0, zero activation errors, in 204 s** (against 1,112 s of timeouts), and a full re-run of the declared command then passed **23/23, exit 0**, which is the run recorded in the envelope. `cellarTests` was 56/56 in the failed run too, and CellarCore was unaffected throughout. Nothing here indicts the change, but the flake is worth knowing about before it is met in CI and misread as a regression: budget for a retry, or pin the runner's foreground state.
2. **The arrivals footprint bound has ~1 KB of headroom** (~63 KB measured against the recorded 64 KB ceiling). Deterministic, so not a flake risk, but any future field on `PackageArrival` or a change of date-encoding strategy will break it. The apply phase recorded the mitigation it deliberately did not take (grouping arrivals by kind, ~30% headroom) and why. Carry this forward as a known constraint on `PackageArrival`'s shape.
3. **Task 6.5's RED was not separately observed.** Honestly self-reported by apply. Adjudicated above as anchored and non-vacuous — the guard carries positive controls and would fail on its violation — so it is a process deviation rather than a coverage hole. No action required beyond the record.

**SUGGESTION**:

1. `apply-progress` names `DiscoveryStructuralGuardTests` as though it were its own file; the suite actually lives at the bottom of `DiscoverySidecarFootprintTests.swift`. The suite exists and passes 3/3 — a labelling imprecision only.
2. The `cellarTests` case count differs by one between the apply report (57) and this phase's measurement (56 passing invocations, 49 distinct `@Test`). The Discover contribution matches exactly at 10. Counting-method difference, not a missing test.
3. Counting the 1,202 lines of `openspec/changes/m5-discover/` lifecycle artifacts, the change totals 5,659 lines against a 5,000 budget. Authored source+tests (4,457) is what the guard measures and is inside budget; the distinction is worth stating explicitly in the PR description.
4. One SwiftLint default-rule warning (`orphaned_doc_comment`) in `DiscoverSectionModels.swift:9`.
5. `AppTestFixtures.catalogDirectory` puts a launch-argument branch on a production code path. It follows the convention `cellar/AppTestFixtures.swift` already established for M3 and M4, and the branch is narrow (it moves a path and changes no behaviour), so this is consistency-with-precedent rather than a new risk. Worth one line in the PR so a reviewer meets it deliberately.
6. Code coverage was not measured. `openspec/config.yaml` sets `threshold: 0`, which makes it non-blocking; running it would add another full-suite pass.

### Verdict

**PASS**

All 10 delta requirements are implemented and **all 46 scenarios** now have a covering test that passed at runtime in this phase's own execution. Every declared command is green on the current tree: `swift test` **1213 tests / 162 suites, exit 0**; the full `xcodebuild test` **TEST SUCCEEDED, 23 UI cases, 56 `cellarTests`, exit 0**; `xcodebuild build` **BUILD SUCCEEDED, exit 0** with zero warnings.

The verify-1 blocker is genuinely closed rather than argued away: the new test observes the persisted bytes rather than the projection, carries a positive control, takes the branch that matters, and is corroborated by a mutation check whose failure count matches its assertions exactly. No production code changed to achieve it, which is the right outcome — the code was correct; the proof was missing.

Three warnings remain, none blocking: a host-side XCUITest activation flake that is unrelated to this change and was proven non-reproducible, the ~1 KB of headroom on the arrivals footprint bound, and task 6.5's unobserved RED (adjudicated as anchored). Ready for archive.
