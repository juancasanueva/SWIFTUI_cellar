```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:0f201710ff612a3505036eef0e4d1ea7547ba4955f5adac7ae7ef517cc26c9fe
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 21/21
scenarios: 59/59
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:e5dfb8ee8a01ff18978f7149568d1294abf14929ea8f98e5fd7b9b9696581f0d
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests
build_exit_code: 0
build_output_hash: sha256:367bca62c38cf6fcd76767e87500f429150eb7ee423a282927755b43e90b1771
```

## Verification Report

**Change**: m1-catalog-browse
**Version**: N/A (OpenSpec change deltas, unversioned)
**Mode**: Strict TDD
**Branch**: `feature/m1-catalog-browse` (11 commits off `main`, clean worktree, HEAD `1c5331c`)

> **This report supersedes the FAIL verification dated 2026-08-01 (evidence_revision
> `sha256:00fe5a76…`).** That report raised exactly two things that stood between the change and a
> PASS: one CRITICAL tautological assertion and one PARTIAL spec scenario (PS2 case-insensitive
> match). Commit `1c5331c` addresses both. This is a **focused re-verification**: the fix diff was
> inspected line by line and all three gates were re-run end to end; the 59-scenario compliance trace
> is carried forward from the superseded report and amended only where the fix changes the verdict.

### Re-verification Scope

| Item | Finding |
|---|---|
| Fix commit | `1c5331c` — `test(catalog): replace tautological assertion and prove case-insensitive search end-to-end` |
| Files touched | `ProjectionTests.swift` (1 line changed), `SearchIndexTests.swift` (1 line added), `openspec/changes/m1-catalog-browse/verify-report.md` (302 lines added — the superseded report itself) |
| Production code touched | **None.** `git show --stat 1c5331c` shows zero files under `Sources/`, zero project/scheme edits. The fix is test-only, so no spec scenario can regress. |
| Unexpected content in the diff | **None.** The only third file is the prior verify-report, which is expected SDD bookkeeping. |

### Fix 1 — CRITICAL tautology removed

```diff
-        #expect(pcre2.dependencies.isEmpty == false || pcre2.dependencies.isEmpty)
+        #expect(pcre2.dependencies.isEmpty)
```

`ProjectionTests.swift:136`. The old form was `!X || X`, true for every possible value. The
replacement is **concrete and falsifiable**, and I verified the fixture rather than taking the claim
on trust: in `Tests/CatalogTests/Fixtures/formula-slice.json`, `pcre2` carries
`"dependencies": []` and `"build_dependencies": []`. The assertion therefore fails if the projection
or the linker ever fabricates an edge on a leaf record — exactly the regression the surrounding
comment describes. The companion claim ("no transitive edge of pcre2 leaked into git's own lists")
is still carried by line 137's `isDisjoint(with: ["libedit", "bzip2"])`, which remains untouched.

`git.dependencies` is asserted as `["pcre2", "gettext"]` on line 127, so PD2's "direct dependencies
only" is now proven from both directions: the dependant's list is exact, and the leaf it points at
contributes nothing.

### Fix 2 — PS2 proven end to end

```diff
         #expect(index.search("openssl").map(\.id.name) == ["openssl@3"])
+        #expect(index.search("OpenSSL").map(\.id.name) == ["openssl@3"])
         #expect(index.search("cafe").map(\.id.name) == ["visual-studio-code"])
```

`SearchIndexTests.swift:24`, inside `Building the index normalises each record once, up front`. The
gap in the superseded report was that PS2's THEN is a **search-level** claim while the only runtime
assertions were unit-level on `PackageText`. This new line closes it exactly: a **mixed-case query**
(`"OpenSSL"`) is passed through the public `search(_:)` entry point against a record whose stored
name is lower-case `openssl@3`, and the full result set is asserted by equality — not by
`contains`, so a false positive on the sibling `visual-studio-code` record would also fail it. The
assertion exercises build-time normalisation and query-time normalisation in composition, which is
the same shape as the already-passing diacritics assertion on the next line.

PS2 therefore moves **PARTIAL → COMPLIANT**, matching its sibling scenario's evidence standard.

### Build & Tests Execution

All three gates were re-run by this re-verification against HEAD `1c5331c`. Nothing is inherited
from the apply report or from the superseded verification.

| Gate | Command | Exit | Result |
|---|---|---|---|
| FAST | `swift test --package-path Packages/CellarCore` | 0 | **212 tests in 33 suites passed** (0.580 s) |
| REL | `swift test -c release --filter SearchLatency --package-path Packages/CellarCore` | 0 | **2 tests in 1 suite passed** (1.240 s) |
| FULL | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -skip-testing:cellarUITests` | 0 | **`** TEST SUCCEEDED **`** |

The count stays at 212 because the fix added an assertion, not a test — consistent with a test-only
hardening commit. Both amended tests were confirmed to have actually executed in this run, not merely
compiled:

- `Test "Dependency lists stay flat, direct, ordered and un-deduplicated" passed after 0.030 seconds.`
- `Test "Building the index normalises each record once, up front" passed after 0.029 seconds.`

Release-gate detail: `p95 as-you-type latency stays under 8 ms on a realistic index` passed in
1.202 s, and the companion `The latency fixture is the size and shape the ceiling is claimed for`
passed, so the ceiling is still asserted against a fixture whose realism is itself asserted.

**Pre-existing `cellarUITests` failure — unchanged and still not attributable to this diff.**
`git diff --stat main...HEAD` touches zero files under `cellarUITests/`, and the fix commit touches
no project, scheme, or build-phase entry at all. Not fixed, per the strict-TDD safety-net rule.

**Coverage**: ➖ Not available — no coverage tool configured for the SwiftPM package. Not a failure.

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 71 |
| Tasks complete | 71 |
| Tasks incomplete | 0 |
| Requirements (ADDED spec files) | 21 (catalog-sync 9, package-search 6, package-detail 6) |
| Scenarios (ADDED spec files) | 59 (catalog-sync 26, package-search 16, package-detail 17) |

Re-counted from `openspec/changes/m1-catalog-browse/specs/**/spec.md` at HEAD; `tasks.md` still reads
71 `- [x]` and 0 `- [ ]`. The two MODIFIED editorial deltas (`brew-execution`, `brew-detection`) add
2 requirements / 5 carried scenarios on top and are verified as applied under Correctness below.
Task state matches code state: no task claims work the diff does not contain, and the fix commit
introduced no new task.

### Spec Compliance Matrix

Legend: ✅ COMPLIANT (covering test passed at runtime) · ⚠️ PARTIAL · ❌ UNTESTED/FAILING.
All cited tests are in `Packages/CellarCore/Tests/CatalogTests/`. Rows are carried from the
superseded report; the two rows the fix changes are marked **(re-verified)**.

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
| PS2 Normalisation | Case-insensitive match | `SearchIndexTests > Building the index normalises each record once, up front` asserts `index.search("OpenSSL").map(\.id.name) == ["openssl@3"]`; unit-level `PackageTextTests > Normalisation lowercases` remains as the lower layer | ✅ **(re-verified — was ⚠️ PARTIAL)** |
| PS2 | Diacritics fold to ASCII | same test asserts `index.search("cafe") == ["visual-studio-code"]` against desc `Café-friendly editor`; the `café`-query half via `PackageTextTests > A query and the text it should match normalise to the same bytes` | ✅ |
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
| PD2 Dependencies | Direct dependencies only | `ProjectionTests > Dependency lists stay flat, direct, ordered and un-deduplicated` — now backed by the falsifiable `#expect(pcre2.dependencies.isEmpty)` on a fixture leaf, plus the exact list equality on line 127 and the disjointness check on line 137 | ✅ **(re-verified — CRITICAL-1 resolved)** |
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

**Compliance summary**: **59/59 scenarios COMPLIANT, 0 PARTIAL, 0 UNTESTED.**
All 21 requirements have at least one covering test that passed at runtime in this run.

### Correctness (Static Evidence)

Carried from the superseded report; the fix commit touches none of these surfaces, and the branch
diff against `main` was re-checked at HEAD.

| Area | Status | Notes |
|---|---|---|
| Editorial delta `brew-execution` | ✅ Applied | `openspec/specs/brew-execution/spec.md` carries the four-outcome wording verbatim from the delta, plus a dated provenance note naming change `m1-catalog-browse`. Scenarios unchanged. |
| Editorial delta `brew-detection` | ✅ Applied | `openspec/specs/brew-detection/spec.md` THEN-block reconciled exactly as the delta specifies, plus a dated provenance note. No behavioural change. |
| `pbxproj` surface | ✅ Minimal | Exactly 4 hunks, all Catalog product link. No file references for the new UI files — they arrive through the filesystem-synchronised group. |
| Scheme update | ✅ Correct | `CellarCore.xcscheme` gains one `BuildActionEntry` for `Catalog` and one `TestableReference` for `CatalogTests`. Nothing else touched. |
| `Item.swift` removal | ✅ Clean | File deleted; no `SwiftData`, `ModelContainer`, or `Item` type reference remains outside one explanatory doc comment. |
| Fixtures | ✅ Truncated | 8 JSON files + README, largest 72 KB, total ~200 KB. The 40 MB memory-budget payload is generated at runtime, not committed. |
| Scope discipline | ✅ Held | No Discover section, no `keyboardShortcut`, no installed/outdated predicate in `SearchFilters`, no mutation actions, no CI files. |

### Coherence (Design)

Unchanged by the fix (test-only diff). All decisions verified in the superseded report remain
satisfied: D1 `Catalog` target has no `BrewProcess` dependency; D2 decode/index run off-main via
`@concurrent`; D3 snapshot published before sidecar with atomic replace; D7 manual conditional
headers with URL cache bypassed; full-replace snapshot semantics with no merge path; the four-class
ranking order with a total tiebreak; and zero `@unchecked Sendable` in the repository.

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ✅ | 15-row "TDD Cycle Evidence" table in `sdd/m1-catalog-browse/apply-progress` |
| All tasks have tests | ✅ | 71/71 tasks complete; every phase row names a test file |
| RED confirmed | ✅ | 15/15 named test files exist on disk; each RED cell quotes a concrete compiler/assertion failure |
| GREEN confirmed | ✅ | 18/18 Catalog test files pass in the re-run FAST gate; latency file passes in the re-run REL gate |
| Triangulation adequate | ✅ | 126 `@Test` declarations across 18 Catalog files, several parameterised |
| Safety Net for modified files | ✅ | Reported safety-net runs escalate monotonically (8 → 12 → 32 → 44 → 192 → 201) |

**TDD Compliance**: 6/6 checks passed.

### Assertion Quality

| File | Line | Assertion | Issue | Severity |
|------|------|-----------|-------|----------|
| — | — | — | No tautological, unfalsifiable, or production-free assertion found | — |

**Assertion quality**: **0 CRITICAL, 0 WARNING** across 415 assertion lines (`#expect` / `#require`)
in 18 Catalog test files.

The single CRITICAL from the superseded report is resolved at source. Re-checked and still clean:

- `ProjectionTests.swift:136` is now `#expect(pcre2.dependencies.isEmpty)` — falsifiable against a
  fixture record that genuinely declares `"dependencies": []`.
- `SearchIndexTests.swift:24` asserts full-result equality, not `contains`, so it cannot pass on a
  wrong-but-non-empty result set.
- `DependentsTests.swift:39-50` loops over `where edge.isResolvable` but line 50 asserts
  `checkedEdges > 20`, so an empty loop body fails the test — not a ghost loop.
- `PresentationTests.swift:102` loops over a 5-element literal array and line 107 asserts all five
  sentences are distinct.
- Every `isEmpty` / `== []` assertion is either the literal text of a spec scenario or paired with a
  non-empty companion assertion in the same test.
- No `#expect(true)`-family tautologies; no assertion that fails to call production code.

### Quality Metrics

**Linter**: ⚠️ SwiftLint runs with no `.swiftlint.yml`; 1 warning on new code (`succeeded(at:)` — the
label is spec-mandated by CS8) plus pre-existing template findings. Informational only.
**Type Checker**: ✅ No errors — all three gates compile clean under Swift 6 language mode.

### Issues Found

**CRITICAL**

None. The one CRITICAL raised by the superseded report (`ProjectionTests.swift:136` tautology) is
**RESOLVED** in commit `1c5331c` and re-verified above.

**WARNING**

1. ~~**PS2 "Case-insensitive match" is PARTIAL.**~~ **RESOLVED** in commit `1c5331c` — a search-level
   assertion with a mixed-case query now covers the scenario end to end. Recorded here for the audit
   trail; it no longer counts against the change.
2. **`apply-progress` test-count figures are wrong.** It states "Tests written: 212 in the `Catalog`
   module … repo total unchanged at 117 for `BrewProcess`". Re-measured at HEAD: **126** `@Test`
   declarations in `CatalogTests`, **86** in `BrewProcessTests`, summing to the 212 the FAST gate
   reports for the whole package. The gate numbers are correct; only the attribution is wrong. Worth
   correcting during archive so the historical record is accurate. **Carried forward unchanged — did
   not block.**
3. **`nonisolated(unsafe)` in test code** — `CatalogMemoryTests.swift:144`
   (`nonisolated(unsafe) let shared = self`), confirmed still present at HEAD. The invariant does
   hold: `Sampler` is a `final class` conforming to `Sendable` with all mutable state behind a
   `Mutex`, so the annotation is redundant rather than dangerous. It should carry a documented safety
   invariant or be removed. Test-only, non-blocking. **Carried forward unchanged — did not block.**

Note for the record: the superseded report listed 3 WARNINGs, of which WARNING-1 *was* the PS2
PARTIAL. With PS2 resolved, **2 WARNINGs remain open** (items 2 and 3 above). Item 1 is retained
struck through rather than deleted so the delta between the two verifications is auditable.

**SUGGESTION** (all 3 carried forward unchanged — none blocked)

1. `CatalogFileStore.persistState` and `DefaultCatalogFileSystem.replaceItem` show no direct covering
   test in the call graph. Both are exercised transitively, so this is coverage bookkeeping, not a gap.
2. Adding a `.swiftlint.yml` would silence the two template-inherited findings and the spec-mandated
   `succeeded(at:)` label. Explicitly out of scope here.
3. The origin emits **weak** ETags (`W/"…"`). Harmless for revalidation as shipped, but any future
   byte-range or strong-comparison logic must account for it.

### Deviation Assessment

Unchanged from the superseded report. All eight documented deviations were judged against spec text
and none contradicts it: `syncStatus` over `syncState` (spec names the type `CatalogSyncStatus`),
`excludeDeprecated`/`excludeDisabled` (PS4 names the exclusion form literally),
`CatalogPresentation.swift` beyond the design's non-normative file table (UI wording is domain
vocabulary and is tested), deprecation/disable dates gated on their flags (required by PD4 given
scheduled `disable_date` on deprecated-but-enabled formulae), computed `InstallCount`, link-time
`isResolvable`, `payloadTooLarge` → `.malformedPayload` (the error enum is closed at five cases), and
non-retried analytics.

### Verdict

**PASS WITH WARNINGS** — archive-ready.

Both blockers from the superseded FAIL are closed by a two-line, test-only commit that touches no
production code and therefore cannot regress any scenario. All three gates were re-run at HEAD and
are green (212 / 2 / TEST SUCCEEDED), 71/71 tasks remain complete and consistent with the code state,
and the compliance matrix is now **21/21 requirements and 59/59 scenarios COMPLIANT with 0 PARTIAL
and 0 UNTESTED**. The remaining 2 WARNINGs (an inaccurate test-count attribution in `apply-progress`,
a redundant `nonisolated(unsafe)` in one test helper) and 3 SUGGESTIONs are documentation- and
hygiene-level, did not block the previous verification, and do not block archive. Correcting the
`apply-progress` figures during archive is recommended so the historical record is accurate.
