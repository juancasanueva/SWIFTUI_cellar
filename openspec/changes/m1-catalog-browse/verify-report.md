```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:00fe5a76125b4541350e9a236743fe5adaa8979445fc58f0a29812730b3baf25
verdict: fail
blockers: 1
critical_findings: 1
requirements: 21/21
scenarios: 58/59
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:f94b39bc6e66db6c92229610334ab98797a878e7fa58697770f3119ae8f1eebf
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests
build_exit_code: 0
build_output_hash: sha256:c99990b31b6db959cc3fe38a551caa5b893a078c6817d279770f432bd91582de
```

## Verification Report

**Change**: m1-catalog-browse
**Version**: N/A (OpenSpec change deltas, unversioned)
**Mode**: Strict TDD
**Branch**: `feature/m1-catalog-browse` (10 commits off `main`, clean worktree)

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 71 |
| Tasks complete | 71 |
| Tasks incomplete | 0 |
| Requirements (spec files) | 21 (catalog-sync 9, package-search 6, package-detail 6) |
| Scenarios (spec files) | 59 (catalog-sync 26, package-search 16, package-detail 17) |

Counted directly from `openspec/changes/m1-catalog-browse/specs/**/spec.md`. Task counts from
`tasks.md`: 71 `- [x]`, 0 `- [ ]`.

### Build & Tests Execution

All three gates were re-run by this verification, not taken from the apply report.

| Gate | Command | Exit | Result |
|---|---|---|---|
| FAST | `swift test --package-path Packages/CellarCore` | 0 | **212 tests in 33 suites passed** (0.583 s) |
| REL | `swift test -c release --filter SearchLatency --package-path Packages/CellarCore` | 0 | **2 tests in 1 suite passed** (1.216 s) |
| FULL | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests` | 0 | **`** TEST SUCCEEDED **`** |

Release-gate detail: `p95 as-you-type latency stays under 8 ms on a realistic index` passed in
1.177 s; the companion `The latency fixture is the size and shape the ceiling is claimed for`
passed, so the ceiling is asserted against a fixture whose realism is itself asserted.

**Pre-existing `cellarUITests` failure — claim independently verified.** The apply report asserts the
4 `cellarUITests` failures (`Failed to activate application … (current state: Running Background)`)
pre-date this change. Verified structurally rather than by re-running `main`: `git diff --stat
main...HEAD` touches **zero** files under `cellarUITests/`, and the change adds no target, scheme, or
build-phase entry that reaches that bundle (the only `.pbxproj` edits are the four Catalog
product-link hunks; the only scheme edit is to `CellarCore.xcscheme`, which does not contain
`cellarUITests`). The failure is therefore not attributable to this diff. Not fixed, per instruction.

**Coverage**: ➖ Not available — no coverage tool configured for the SwiftPM package (no
`--enable-code-coverage` in the project's declared gates). Not a failure.

### Spec Compliance Matrix

Legend: ✅ COMPLIANT (covering test passed at runtime) · ⚠️ PARTIAL · ❌ UNTESTED/FAILING.
All cited tests are in `Packages/CellarCore/Tests/CatalogTests/`.

#### catalog-sync (9 requirements / 26 scenarios)

| Req | Scenario | Covering test | Result |
|---|---|---|---|
| CS1 Source seam | Sync succeeds while brew is absent | `SyncEngineTests > A sync succeeds with no brew present and asks each source exactly once` | ✅ |
| CS1 | Every network read goes through the seam | same test (fake records one request per source kind) | ✅ |
| CS2 Revalidation | Unchanged payload is not re-downloaded | `SyncEngineTests > Two unchanged sources read no body, write no snapshot, and still advance downloadedAt` | ✅ |
| CS2 | Changed payload replaces the snapshot | `SyncEngineTests > A changed payload replaces the snapshot and records the new validator verbatim` | ✅ |
| CS2 | First sync sends no validators | `SyncEngineTests > A first sync carries no validators at all` | ✅ |
| CS3 Full replace | A package absent from the new dump is gone | `FileStoreTests > A package absent from the new payload disappears entirely` | ✅ |
| CS3 | Interrupted write leaves previous snapshot readable | `FileStoreTests > A write that fails midway leaves the previous snapshot readable` | ✅ |
| CS4 Failure safety | Offline sync preserves the cached catalog | `SyncEngineTests > A transport error keeps a large cached catalog answering` | ✅ |
| CS4 | 503 is retried, 404 is not | `SyncEngineTests > 503 is retried to success, 404 is asked once` (+ `429 is retried like a 5xx`) | ✅ |
| CS4 | Malformed payload preserves the cached catalog | `SyncEngineTests > A non-JSON body fails as malformed and leaves the snapshot untouched` | ✅ |
| CS5 Tolerant decode | Cask name array yields a single display name | `DecodeTests > A cask name array collapses to a single display name` (+ `The first entry of a multilingual name array wins`) | ✅ |
| CS5 | Null description and caveats decode as absent | `DecodeTests > Null description and caveats decode as absent, not empty` | ✅ |
| CS5 | Mixed `uses_from_macos` elements decode | `DecodeTests > Mixed uses_from_macos elements both decode and the record survives` | ✅ |
| CS5 | Unknown keys are ignored | `DecodeTests > Keys the decoder does not model are discarded, not fatal` | ✅ |
| CS5 | One malformed record does not kill the payload | `DecodeTests > Three malformed records among a hundred cost three records, not the payload` | ✅ |
| CS6 Sidecar | State sidecar round-trips | `FileStoreTests > The state sidecar round-trips validators, downloadedAt and per-source counts` | ✅ |
| CS6 | Unknown schema version is treated as no cache | `FileStoreTests > A sidecar from a newer build reads as no cache, not as an error` | ✅ |
| CS7 Freshness | Fresh catalog does not sync on launch | `SchedulerTests > A catalog younger than a day issues no request on load` | ✅ |
| CS7 | Stale catalog refreshes silently | `SchedulerTests > A stale catalog refreshes in the background while still serving the cache` | ✅ |
| CS7 | Manual refresh ignores age | `SchedulerTests > A manual refresh syncs regardless of age` | ✅ |
| CS8 First run | Cold launch answers immediately with empty results | `SyncEngineTests > A cold launch answers with no cache while the status reports progress`; `CatalogStoreTests > A cold launch is ready immediately with zero results and a live status` | ✅ |
| CS8 | Results appear when the first sync lands | `CatalogStoreTests > A sync that lands while the store is running replaces the results` | ✅ |
| CS8 | Failed first sync is observable and non-fatal | `SyncEngineTests > A failed first sync is observable and throws nothing`; `CatalogStoreTests > A failed first sync publishes the failure and keeps answering` | ✅ |
| CS9 Analytics | Comma-grouped counts parse regardless of locale | `AnalyticsTests > Comma-grouped counts parse to the same integer whatever the locale` (parameterised) | ✅ |
| CS9 | Analytics failure leaves the catalog usable | `AnalyticsTests > A failed analytics fetch still produces a successful sync` | ✅ |
| CS9 | Missing analytics entry is absent, not zero | `AnalyticsTests > A package with no analytics entry has an absent count, not zero` (+ `A recorded zero is a count, an absent entry is not`) | ✅ |

#### package-search (6 requirements / 16 scenarios)

| Req | Scenario | Covering test | Result |
|---|---|---|---|
| PS1 Identity | Same name in both namespaces yields two results | `SearchIndexTests > The same name in both namespaces yields two distinct results` | ✅ |
| PS1 | Kind is exposed on every result | `SearchIndexTests > Every hit carries exactly one kind` | ✅ |
| PS2 Normalisation | Case-insensitive match | `PackageTextTests > Normalisation lowercases` + `A query and the text it should match normalise to the same bytes` | ⚠️ PARTIAL |
| PS2 | Diacritics fold to ASCII | `SearchIndexTests > Building the index normalises each record once, up front` asserts `index.search("cafe") == ["visual-studio-code"]` against desc `Café-friendly editor`; the `café`-query half via `PackageTextTests > A query and the text it should match normalise to the same bytes` | ✅ |
| PS3 Ranking | Match classes order the result set | `RankingTests > Match class orders the result set, strongest first` (+ `A record is ranked by its strongest class only`) | ✅ |
| PS3 | Install count breaks a class tie | `RankingTests > Install count breaks a class tie, descending` | ✅ |
| PS3 | Absent counts sort last within a class | `RankingTests > An absent count sorts after every present count in its class` | ✅ |
| PS3 | Full ties are broken deterministically | `RankingTests > A full tie breaks by name, then formula before cask, reproducibly` | ✅ |
| PS4 Filters | Deprecated included by default with badge data | `FilterTests > Deprecated packages are included by default, flag exposed for badging` | ✅ |
| PS4 | Deprecated packages can be filtered out | `FilterTests > excludeDeprecated removes only the deprecated matches` (+ `excludeDisabled removes only the disabled matches`) | ✅ |
| PS4 | Kind filter restricts the namespace | `FilterTests > A kind filter restricts the namespace` | ✅ |
| PS4 | No filter references installed state | `FilterTests > No declared filter refers to installed, not-installed or outdated state` (Mirror over `SearchFilters`) | ✅ |
| PS5 Edge queries | Empty query returns the full catalog | `FilterTests > An empty or whitespace-only query returns the whole filtered catalog` (args `""`, `"   "`, `"\t\n"`) | ✅ |
| PS5 | No match returns an empty set | `FilterTests > A query matching nothing returns an empty set and throws nothing` | ✅ |
| PS6 Latency | p95 stays under 8 ms on a realistic fixture | `SearchLatencyTests > p95 as-you-type latency stays under 8 ms on a realistic index` (release gate) | ✅ |
| PS6 | Index build is a single pass over the snapshot | `SearchIndexTests > Building the index normalises each record once, up front` | ✅ |

#### package-detail (6 requirements / 17 scenarios)

| Req | Scenario | Covering test | Result |
|---|---|---|---|
| PD1 Projection | Formula detail exposes every required field | `ProjectionTests > A formula projection carries every required detail field`; `DetailTests > The resolved detail carries every PD1 field for a real formula` | ✅ |
| PD1 | Cask detail exposes every required field | `ProjectionTests > A cask projection carries every required detail field` | ✅ |
| PD1 | Absent optional fields are absent, not empty | `DetailTests > Absent optional fields stay absent through detail resolution` | ✅ |
| PD1 | Unknown package is not-found, not an error | `DetailTests > An unknown package resolves to not-found without throwing` (+ `A name in the wrong namespace is a miss, not a silent cross-namespace hit`) | ✅ |
| PD2 Dependencies | Direct dependencies only | `ProjectionTests > Dependency lists stay flat, direct, ordered and un-deduplicated` | ✅ (see CRITICAL-1) |
| PD2 | A dependency outside the snapshot is still listed | `ProjectionTests > A dependency outside the snapshot is listed and marked unresolvable`; `CatalogModelsTests > A dependency absent from the snapshot is listed but marked unresolvable` | ✅ |
| PD3 Dependents | Inversion is symmetric | `DependentsTests > A runtime edge makes the dependant a dependent of its dependency`; `Inversion is complete and symmetric over the snapshot` | ✅ |
| PD3 | Build-only dependents are included | `DependentsTests > A build-only edge also produces a dependent` | ✅ |
| PD3 | A leaf package reports an empty dependents list | `DependentsTests > A leaf reports an empty dependents list, not an absent one` | ✅ |
| PD3 | Edges to absent packages create no dependents | `DependentsTests > An edge to a name outside the snapshot creates no dependents entry` | ✅ |
| PD4 Status | Deprecated package exposes reason and date | `ProjectionTests > A deprecated record exposes its flag, reason and date` | ✅ |
| PD4 | Disabled package exposes reason and date | `ProjectionTests > A disabled record exposes its flag, reason and date` | ✅ |
| PD4 | Healthy package reports both statuses false | `ProjectionTests > A healthy record reports both flags false with all four fields absent` (+ `A deprecated-but-enabled record hides the scheduled disable date`) | ✅ |
| PD5 Install count | Count exposed with window and lower-bound semantics | `AnalyticsTests > A formula count is published as a 365-day installs-on-request lower bound`; `A cask count is published as a 365-day installs lower bound` | ✅ |
| PD5 | Absent count is distinguishable from zero | `AnalyticsTests > A recorded zero is a count, an absent entry is not` | ✅ |
| PD6 Tap scope | Third-party tap package is a normal not-found | `DetailTests > A third-party tap package is an ordinary not-found after a successful sync` | ✅ |
| PD6 | Every snapshot record belongs to a covered tap | `ProjectionTests > Every projected record belongs to a covered tap` (+ `A third-party tap record is dropped without a decode failure`) | ✅ |

**Compliance summary**: **58/59 scenarios COMPLIANT, 1 PARTIAL, 0 UNTESTED.**
Every one of the 21 requirements has at least one passing covering test.

### Correctness (Static Evidence)

| Area | Status | Notes |
|---|---|---|
| Editorial delta `brew-execution` | ✅ Applied | `openspec/specs/brew-execution/spec.md` carries the four-outcome wording **verbatim** from the delta, plus a dated provenance note naming change `m1-catalog-browse`. Scenarios unchanged. |
| Editorial delta `brew-detection` | ✅ Applied | `openspec/specs/brew-detection/spec.md` THEN-block reconciled exactly as the delta specifies, plus a dated provenance note. No behavioural change. |
| `pbxproj` surface | ✅ Minimal | Exactly **4 hunks**, all Catalog product link (`PBXBuildFile` `…0004`, Frameworks phase entry, `packageProductDependencies` `…0005`, `XCSwiftPackageProductDependency`). No file references for the new UI files — they arrive through the filesystem-synchronised group, so 9 new Swift views cost **zero** pbxproj edits. |
| Scheme update | ✅ Correct | `CellarCore.xcscheme` gains one `BuildActionEntry` for `Catalog` and one `TestableReference` for `CatalogTests`. Nothing else touched. |
| `Item.swift` removal | ✅ Clean | File deleted; `rg` over `cellar/` finds no `SwiftData`, `ModelContainer`, or `Item` type reference. The single `ModelContainer` string is a doc comment in `cellarApp.swift` explaining its removal. |
| Fixtures | ✅ Truncated | 8 JSON files + README, largest 72 KB (`cask-slice.json`), total ~200 KB. Edge cases present: `cask-iterm2.json` (`[String]` name), null desc/caveats and mixed `uses_from_macos` in the slices, `formula-unknown-keys.json`, deprecated/disabled records exercised by `ProjectionTests`. The 40 MB memory-budget payload is **generated at runtime** in `CatalogMemoryTests`, not committed. |
| Scope discipline | ✅ Held | No Discover section (`AppSection` = `home`, `browse` only). No `keyboardShortcut` anywhere — search uses standard `.searchable(placement: .toolbar)`. No installed/outdated predicate in `SearchFilters` (asserted by test). No mutation actions: the only buttons are `Refresh catalog`, `Retry` (sync), and `.buttonStyle(.link)` navigation to dependencies. No CI files added. |

### Coherence (Design)

| Decision | Followed? | Evidence |
|---|---|---|
| D1 `Catalog` target independent of `BrewProcess` | ✅ Yes | `Package.swift` declares `.target(name: "Catalog")` with **no** `dependencies:`, with a comment citing CS1. `rg BrewProcess Sources/Catalog/` → no matches. |
| D1 `CatalogStore` is `@MainActor @Observable`, in the Catalog target | ✅ Yes | `Sources/Catalog/CatalogStore.swift:10-12`. Single main-isolated crossing point; engine and index stay `nonisolated`. |
| D2 Decode/index run off-main | ✅ Yes | `CatalogDecoder.decode(_:at:)` and `decodeAnalytics(at:kind:)` are `@concurrent` (`CatalogSyncEngine.swift:345,361`) with an in-code note that a plain `nonisolated func` would still run *on* the calling actor. |
| D3 Snapshot published before sidecar | ✅ Yes | `CatalogFileStore.persist` writes `catalog.json` then `catalog-state.json` in that order; the comment states the failure asymmetry. Asserted by `FileStoreTests > The snapshot is published before the sidecar that advertises it`. |
| D3 Atomic replace | ✅ Yes | `DefaultCatalogFileSystem.replaceItem` uses `FileManager.replaceItemAt`, with a `moveItem` fallback only when the destination does not exist yet (first sync); staged temp file removed on failure. |
| Failed sync preserves last-good | ✅ Yes | Closed `CatalogSyncError` (5 cases); three separate SyncEngine tests prove offline/malformed/persistence leave the prior snapshot loadable and served. |
| D7 Conditional requests: manual headers + cache bypass | ✅ Yes | `HTTPCatalogSource` sets `If-None-Match` / `If-Modified-Since` by hand, keeps `Last-Modified` as the **raw header string**, sets `configuration.urlCache = nil`, and sets `.reloadIgnoringLocalCacheData` on **both** the session config and each `URLRequest`. 304 is classified before the temp file is opened, so an empty 304 body can never decode as an empty catalog. |
| Full-replace snapshot semantics | ✅ Yes | `CatalogDecoder.link` builds a fresh `CatalogSnapshot` from the new payloads only; no merge or tombstone path exists. Proven by `FileStoreTests > A package absent from the new payload disappears entirely`. |
| Search ranking order | ✅ Yes | `MatchRank` = exactToken < namePrefix < nameSubstring < descriptionSubstring; `rank(_:)` returns the strongest class and short-circuits before the description scan. `precedes` = count desc (absent sorted **after** every present count, including zero) → normalised name asc → `formula` before `cask`. Total by construction since `(name, kind)` is unique. |
| No `@unchecked Sendable` | ✅ Yes | `rg "@unchecked Sendable"` over the whole repo → **zero** matches. |

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ✅ | 15-row "TDD Cycle Evidence" table in `sdd/m1-catalog-browse/apply-progress` |
| All tasks have tests | ✅ | 71/71 tasks complete; every phase row names a test file |
| RED confirmed (test files exist) | ✅ | 15/15 named test files exist on disk; each RED cell quotes a concrete compiler/assertion failure (e.g. `cannot find 'CatalogDecoder'`, `pcre2.dependents → []`) |
| GREEN confirmed (tests pass now) | ✅ | 18/18 Catalog test files pass in the re-run FAST gate; latency file passes in the re-run REL gate |
| Triangulation adequate | ✅ | 126 `@Test` declarations across 18 Catalog files, several parameterised; no requirement rests on a single case |
| Safety Net for modified files | ✅ | Reported safety-net runs escalate monotonically (8 → 12 → 32 → 44 → 192 → 201), consistent with a growing suite; `N/A (new)` cells correspond to files created in that same commit |

**TDD Compliance**: 6/6 checks passed.

### Test Layer Distribution

| Layer | Tests (`@Test` decls) | Files | Tools |
|-------|------|-------|-------|
| Unit | 92 | 13 | Swift Testing |
| Integration (fakes + real temp dirs, `@MainActor` store) | 28 | 3 | Swift Testing |
| Perf (release-gated latency, memory footprint) | 4 | 2 | Swift Testing + `mach` `phys_footprint` |
| E2E / UI | 0 | 0 | XCUITest present but pre-existing and skipped |
| **Total (Catalog)** | **126** | **18** | |

`BrewProcessTests` contributes a further 86 declarations; 126 + 86 = the 212 the FAST gate reports.

### Changed File Coverage

➖ Coverage analysis skipped — no coverage tool configured in the project's declared gates.
Not a failure.

### Assertion Quality

| File | Line | Assertion | Issue | Severity |
|------|------|-----------|-------|----------|
| `ProjectionTests.swift` | 136 | `#expect(pcre2.dependencies.isEmpty == false \|\| pcre2.dependencies.isEmpty)` | Tautology — reduces to `!X \|\| X`, true for every input; proves nothing | CRITICAL |

**Assertion quality**: 1 CRITICAL, 0 WARNING across 413 assertions in 18 files.

Ghost-loop and empty-collection checks came back clean:

- `DependentsTests.swift:39-50` loops over `where edge.isResolvable` — **not** a ghost loop: line 50
  asserts `checkedEdges > 20`, so an empty loop body fails the test.
- `PresentationTests.swift:102` loops over a 5-element literal array that cannot be empty, and
  line 107 additionally asserts all five sentences are distinct.
- Every `isEmpty` / `== []` assertion is either the literal text of a spec scenario (leaf dependents,
  no-match query, cold-launch results) or paired with a non-empty companion assertion in the same
  test. No orphan empty checks.
- No tautologies of the `#expect(true)` family; no assertion that fails to call production code.

### Quality Metrics

**Linter**: ⚠️ SwiftLint runs with no `.swiftlint.yml`; apply reports 1 warning on new code
(`succeeded(at:)` — the label is spec-mandated by CS8) plus pre-existing `cellarApp` type-name and
long-line findings carried from the template. Informational only.
**Type Checker**: ✅ No errors — all three gates compile clean under Swift 6 language mode
(`.swiftLanguageMode(.v6)` on all four targets).

### Issues Found

**CRITICAL**

1. **Tautological assertion** — `Packages/CellarCore/Tests/CatalogTests/ProjectionTests.swift:136`:
   ```swift
   #expect(pcre2.dependencies.isEmpty == false || pcre2.dependencies.isEmpty)
   ```
   This is `!X || X`: it is true for every possible value of `pcre2.dependencies` and can never fail.
   The comment above it claims to check "No transitive edge of pcre2 leaked into git's own lists",
   but that claim is actually carried by the *next* line (`isDisjoint(with: ["libedit", "bzip2"])`).
   Strict TDD classifies a tautology as CRITICAL and requires a rewrite.
   **Blast radius is one line.** Spec scenario PD2 "Direct dependencies only" remains genuinely
   covered by lines 127, 128 and 137 of the same test, so this is a dead assertion, not a false pass.
   Suggested fix: either delete line 136, or replace it with the assertion the comment describes,
   e.g. `#expect(pcre2.dependencies.map(\.name) == [])` if `pcre2` is a leaf in the fixture, or
   assert the concrete expected edge list.

**WARNING**

1. **PS2 "Case-insensitive match" is PARTIAL.** The scenario's THEN is a *search-level* claim ("the
   record matches"), but the only runtime assertions are unit-level on `PackageText`
   (`normalizedString("GH") == "gh"`, `normalize("GH") == normalize("gh")`). The composition is
   sound by inspection — `PackageSearchIndex` normalises names at build (`:98`) and the needle at
   query (`:168`) — and the *sibling* diacritics scenario **is** proven end-to-end
   (`index.search("cafe")` against desc `Café-friendly editor`). One extra line
   (`#expect(index.search("GH").map(\.id.name) == ["gh"])`) would close it.
2. **`apply-progress` test-count figures are wrong.** It states "Tests written: 212 in the `Catalog`
   module … repo total unchanged at 117 for `BrewProcess`". Actual: **126** declarations in
   `CatalogTests`, **86** in `BrewProcessTests`, summing to the 212 the FAST gate reports for the
   whole package. The gate numbers themselves are correct; only the attribution is. Worth correcting
   before archive so the historical record is accurate.
3. **`nonisolated(unsafe)` in test code** — `CatalogMemoryTests.swift:144`
   (`nonisolated(unsafe) let shared = self`). The invariant does hold: `Sampler` is a `final class`
   conforming to `Sendable` with all mutable state behind a `Mutex`, so the annotation appears
   redundant rather than dangerous. Per the concurrency skill it should carry a documented safety
   invariant or be removed. Test-only, non-blocking.

**SUGGESTION**

1. `CatalogFileStore.persistState` and `DefaultCatalogFileSystem.replaceItem` show no direct covering
   test in the call graph. Both are exercised transitively (the revalidation path and every real-disk
   `FileStoreTests` case), so this is coverage bookkeeping, not a gap.
2. Adding a `.swiftlint.yml` would silence the two template-inherited findings and the spec-mandated
   `succeeded(at:)` label, making future lint output signal-only. Explicitly out of scope here.
3. The origin emits **weak** ETags (`W/"…"`). Harmless for revalidation as shipped, but any future
   byte-range or strong-comparison logic must account for it.

### Deviation Assessment (as documented in apply-progress)

All four deviations flagged by the orchestrator were judged against the spec text, not against
surprise:

| # | Deviation | Verdict |
|---|---|---|
| 1 | `CatalogStore.syncStatus` instead of task 7.1's `syncState` | ✅ **Spec-conformant.** The spec names the enum `CatalogSyncStatus` (CS8). Naming the property after its type extends the "spec names win" rule the tasks already mandate. No spec text requires `syncState`. |
| 2 | `SearchFilters.excludeDeprecated` / `excludeDisabled` instead of the design's `include…` | ✅ **Spec-conformant.** PS4 literally names "`excludeDeprecated`, and `excludeDisabled`". The design draft was the outdated document; `FilterTests` pins the exact property set via `Mirror`. |
| 3 | `CatalogPresentation.swift` added beyond the design's file table | ✅ **Justified.** UI wording is domain vocabulary and `config.yaml` puts logic in CellarCore; the alternative was untested string literals in views. 9 tests cover it. Design coherence WARNING at most, and the design's file table is not normative. |
| 4 | Deprecation/disable dates gated on their flags | ✅ **Required by the spec.** PD4 says a package that is neither "MUST report both flags false with absent reasons and dates". Live payloads publish a *scheduled* `disable_date` on deprecated-but-enabled formulae (e.g. `aamath`), so ungated reporting would violate PD4. Pinned by `ProjectionTests > A deprecated-but-enabled record hides the scheduled disable date`. |

Deviations 5–8 in the apply report (computed `InstallCount`, link-time `isResolvable`,
`payloadTooLarge` → `.malformedPayload`, non-retried analytics) were also checked and none
contradicts spec text; `CatalogSyncError` is closed at five cases, so mapping an oversized body to
`.malformedPayload` is the only conforming option.

### Verdict

**FAIL** — not archive-ready.

Every functional signal is green: 71/71 tasks complete, all three gates re-run and passing
(212 / 2 / TEST SUCCEEDED), 21/21 requirements covered, 58/59 scenarios COMPLIANT with 0 UNTESTED,
every design invariant upheld, and all four documented deviations judged spec-conformant. The single
blocker is one tautological assertion (`ProjectionTests.swift:136`) that Strict TDD classifies as
CRITICAL and requires rewriting. It is a one-line remediation that leaves no spec scenario uncovered;
re-verification after the fix should return PASS.
