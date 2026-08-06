# Apply progress: `m4-security`

**Cumulative record — batches 1, 2, 3 and 4 of N.** Later batches MUST read this file and merge;
never overwrite. Batches 1–3 are preserved below verbatim; batch 4 is appended after them.

| Field | Value |
|---|---|
| Batches landed | 1 (Phases 0–2), 2 (Phases 3–6), 3 (Phases 7–10), 4 (Phases 11–13) |
| Mode | **Strict TDD** (no fallback taken in any batch) |
| Branch | `feature/m4-security` |
| Branch point | `5863f61` (**not** the planned `0bd1f72` — see Deviation 1) |
| Delivery | `single-pr` + user-recorded `size:exception` (Engram obs 7456) |
| Status | **78 / 108 tasks complete**, suite green, no blockers |
| Resumes at | **Phase 16, task 16.1** (`SecurityPresentation`) — Phases 14–15 follow it in the file but ship after |

---

# Batch 1 — Phases 0, 1, 2

| Field | Value |
|---|---|
| Batch | 1 — Phases 0, 1, 2 |
| Mode | **Strict TDD** (no fallback taken) |
| Branch | `feature/m4-security` |
| Branch point | `5863f61` (**not** the planned `0bd1f72` — see Deviation 1) |
| Delivery | `single-pr` + user-recorded `size:exception` (Engram obs 7456) |
| Attempt authority | acquired with the continuation token, ordinal 1, `proceed` |
| Status | **14 / 108 tasks complete**, suite green, no blockers |

---

## Tasks completed

| Task | What landed |
|---|---|
| 0.1 | Baseline recorded (on the corrected branch point) |
| 0.2 | Delivery decision recorded — single PR, `size:exception` |
| 1.1–1.3 | RED: three manifest-graph guards in `PackageGraphTests` |
| 1.4 | GREEN: `SecurityKit` target, product, test target, `Persistence` second edge |
| 1.5–1.6 | RED: subprocess and filesystem-write prohibition scans |
| 1.7 | GREEN: `Sources/SecurityKit/SecurityKit.swift`, the prohibitions documented where enforced |
| 2.1 | U1 re-captured to the Fixtures standard |
| 2.2 | **U2 gate closed** — both answers recorded; task 3.5 amended |
| 2.3 | **U5 gate closed** — corpus captured, split measured |
| 2.4 | `Fixtures/README.md` + `probe-manifest.txt` (21 files digested) |
| 2.5 | RED: `FixtureManifestTests`, both halves proven non-vacuous |

## Commits

| # | Hash | Subject |
|---|---|---|
| 1 | `6ba522a` | `chore(core): add the SecurityKit target behind its graph guard` |
| 2 | `306e9bc` | `test(security): capture the OSV, NVD and version fixtures` |

Neither pushed; no PR opened. The orchestrator owns the receipt-driven review lifecycle.

## Suite state

| Point | Tests | Suites | Result |
|---|---:|---:|---|
| Baseline (`5863f61`) | 811 | 120 | pass, 1 known issue |
| After batch 1 | **823** | **122** | pass, 1 known issue |

+12 tests, +2 suites: `EgressStructureTests` (5), `FixtureManifestTests` (4), `PackageGraphTests` (+3).

`swiftlint --quiet`: baseline **116** findings (105 warnings + 11 errors — all pre-existing, none
fixed here). After batch 1: 118 total / **72 authored**. The +2 delta is entirely in `.build/`
generated `resource_bundle_accessor.swift` for the new test target's resources. **Zero new authored
findings.** There is no `.swiftlint.yml`, so the tool scans `.build/` too; task 18.1 should compare
authored findings, not the raw total.

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 1.1 | `PackageGraphTests.swift` | Unit (structural) | 8/8 pre-existing green | ✅ failed on `graph["SecurityKit"] → nil` | ✅ | ✅ disjointness + declared edge | ➖ |
| 1.2 | `PackageGraphTests.swift` | Unit (structural) | ✅ | ⚠️ see Deviation 2 | ✅ | ✅ declared + reachable halves | ➖ |
| 1.3 | `PackageGraphTests.swift` | Unit (structural) | ✅ | ✅ failed on `["BrewClient"] != ["BrewClient","SecurityKit"]` | ✅ | ➖ single fact | ➖ |
| 1.5 | `EgressStructureTests.swift` | Unit (structural) | N/A (new) | ✅ failed on the positive anchor | ✅ | ✅ 8-case violation corpus + tool/C-function split | ✅ identifier-boundary scan extracted |
| 1.6 | `EgressStructureTests.swift` | Unit (structural) | N/A (new) | ✅ failed on the positive anchor | ✅ | ✅ shares the violation corpus | ✅ stated exhaustively, not as an allow-list |
| 2.5 | `FixtureManifestTests.swift` | Unit (integrity) | N/A (new) | ✅ corrupted digest ⇒ fail; stray file ⇒ fail; both restored | ✅ | ✅ permanent negative control + 8-case presence check | ➖ |

Tests written: 12. Passing: 12. Layers: Unit 12. Approval tests: none (no refactoring task).
Pure functions created: 1 (`String.containsIdentifier`).

## Fixtures captured

`Packages/CellarCore/Tests/SecurityKitTests/Fixtures/` — 21 files, every digest in
`probe-manifest.txt` and recomputed on every test run.

| Path | SHA-256 |
|---|---|
| `NVD/cveids-request.txt` | `666e8b06438dd30395a4741136e63266f221da371191d0ecf2fe1ca924c38691` |
| `NVD/cveids-response.json` | `10bf49ee10feb08a36a64bb56564fe6cbae401af87969fa1970761b983af456f` |
| `NVD/cveids-unrated-request.txt` | `a89ee0164784861e97940c6d5d9cd000b1d05b2978a407875c48546a22fc5f96` |
| `NVD/cveids-unrated-response.json` | `f2d5f4a39a55cb05f1a9834689891541de2af769c6253b98d21a85cacc430c98` |
| `NVD/ratelimited-response.body` | `e395ad55dd18b1bf23944d00b156714accfae4ec834df208053575542dfae602` |
| `NVD/ratelimited-response.headers` | `05cc35b131aa5cd15507b236194902a0d85c994aa5a66041678c7b0d5b1e6a14` |
| `OSV/querybatch-affected-request.json` | `2e4f7e94d8dac785661f28d9041066c7520394634bf951179510326d4dfc1c48` |
| `OSV/querybatch-affected-response.json` | `bafd3b3c2daff92b902e2feba88bcff8fcbb6e5cbbdd0e84c17ee976f7960d3a` |
| `OSV/querybatch-request.json` | `3950c6aa41f63b1d88763bda11cafe4d4799c6f795c14011e515f7e83845d8a2` |
| `OSV/querybatch-response.json` | `00a7a4ea40924a110461073f8d40d8fad7b0bed7cf6b8f079af3d461baaf4965` |
| `OSV/vulns-GHSA-4gg8-gxpx-9rph.json` | `d78486551c30b5f7c9c55d244b9926638280abde1de5de415fc469b1a2c4c2f3` |
| `OSV/vulns-GHSA-7gcm-g887-7qv7.json` | `2edb7ce74c808ff05bd028c5a259e615ba3e7e88e44c76be94edbddf472e26a7` |
| `OSV/vulns-GHSA-p24j-h477-76q3.json` | `862f822817bc1930f0ac65415286ccfd6afffa36b23a0a513f0df2115cbbce0a` |
| `OSV/vulns-PYSEC-2026-1805.json` | `c571b5f7c7790dc10f9d5dfeb008b428e63e68cf105c49ddcbd9a123d4e26bd2` |
| `OSV/vulns-PYSEC-2026-899.json` | `a433b649a6d60108ece067bedb7144c3a7d678ac7dba60fa571600312e0efbce` |
| `OSV/vulns-RUSTSEC-2020-0163.json` | `c52117fea845d2400f2804968c863d632980afd4b76ad53757c72a7c4eda1833` |
| `OSV/vulns-RUSTSEC-2021-0139.json` | `d26d985b42a00ab7dc102b9ba3cb34781be32a7b1c8b8da403506b3ab46d00fe` |
| `README.md` | `7f9ffce2c9012a6dada4e08273d2463d46d2a01676e67aafbfda15eb5ac13649` |
| `Versions/homebrew-pkg-version-spec-corpus.txt` | `5ad3d9634255a7c12fdd50db9e0ce91419b3a0ec034a35024dcc343d2c02471d` |
| `Versions/homebrew-version-spec-corpus.txt` | `d48114dd4482533893da5a98c87ba84dff2c9193db17145793e2331da19b99e2` |
| `Versions/installed-versions.txt` | `5bb9a8ff177d1c68c2aecca5366973288535d52ac2947ca0fdc66beac5222c11` |

---

## Probe gate answers — **binding on later phases**

### U2 (a): plural `cveIds` — **works**

Seven comma-separated identifiers, one request, HTTP 200, `totalResults: 7`. The design's batched
enrichment is confirmed against the live API. Task 7.3's `identifiersAreBatchedAtOneHundred` tests
real behaviour.

### U2 (b): vector-without-`baseScore` — **the answer stands, the premise does not**

A CVSS metric carrying a vector and no `baseScore` **does not occur**. Wherever a
`cvssMetricV2/V31/V40` entry exists, `cvssData.baseScore` is present; vector and score always travel
together. `.unrated` remains the design default, reached by two *different* real shapes, both
captured:

1. `metrics: {}` entirely, on a CVE at `vulnStatus: "Received"` — `cveids-unrated-response.json`.
2. A **non-CVSS** `metrics` entry: `ssvcV203` has no `cvssData` member and sits beside genuine v3.1
   scores on `CVE-2022-1941` and `CVE-2026-0994`. **This is a live decode hazard** — iterating
   `metrics` and assuming every entry is a CVSS score mis-tiers a properly scored record.

**Task 3.5 was amended in `tasks.md`**, not silently followed: `aVectorOnlyRecordFollowsTheU2Answer`
is struck and replaced by `aRecordWithNoCvssMetricStaysUnrated` and
`aNonCvssMetricEntryIsIgnoredRatherThanTiered`.

`CVE-2026-0994` is the real precedence fixture: it carries **both** v4.0 (8.2) and v3.1 (7.5), so
`theTierPrefersCVSSv4ThenV31ThenV30ThenV2` has a genuine case where the two disagree.

### U2 (c): the rate-limited body is **not JSON**

`429` returns **17 bytes of `text/plain`** — `error code: 1015`, a Cloudflare edge response — with
`retry-after: 0`. Decoding before classifying status would report a JSON failure for a rate limit.
This is direct evidence for the design's "status classified before decode" rule and constrains task
7.4. Reproduced by 40 requests at concurrency 20; 10 sequential requests all passed, so the limit is
concurrency-sensitive rather than a plain sliding window.

### U5: the measured split — **78.6%**

Over the real 159-formula inventory: **strict SemVer 125 (78.6%), strict SemVer + `_N` 9 (5.7%),
neither 25 (15.7%)**. Task 5.3 must record 78.6% — fix comparison runs over the *installed* string,
so the 9 revision rows are covered but not comparable, which is exactly the spec's `1.2.3_1` /
`1.2.4` scenario.

Rows later phases must not lose:

- `pcre2 10.47_1` (real) and `1.0.1e_1` (Homebrew) — `_N` on a **non-SemVer** upstream. The lexical
  split succeeds; strict SemVer then rejects the upstream. The version boundary in one row.
- `1.0_0`, `2.1.4_0` — revision **zero written explicitly**. `split` must report `0`, never `nil`.
- `zsh-autocomplete 26.08.04` — leading zeros, so not strict SemVer.
- `x264 r3222`, `ca-certificates 2026-07-16`, `tmux 3.7b`, `cliclick 5.1`.

### U1 re-capture: all seven mapped packages are **clean**

At their real installed versions, `querybatch-response.json` is `{"results":[{},{},{},{},{},{},{}]}`
— an **intentional** empty capture and the result U1 predicted (≈3–5% real coverage, and what is
covered is current). `querybatch-affected-*.json` at older versions of the same real packages
supplies 19 real advisories so the matcher has findings to work with.

---

## Deviations from plan

1. **Baseline commit corrected.** `tasks.md` names `0bd1f72`; `main` had advanced to **`5863f61`**
   (PR #14, `dc55e6c fix(cleanup): parse empty-directory dry-run lines as typed evidence`) between
   `sdd-tasks` and apply. The branch was cut from `5863f61` and the baseline measured there. Task
   18.1 must compare against 811/120 and 116 lint findings, not against numbers from `0bd1f72`.

2. **Task 1.2 could not be RED in the ordinary sense.** `brewClientCannotReachSecurityKit` asserts an
   **absence**, and the absence already held before `SecurityKit` existed, so the test passed on
   first run. It is a prohibition guard: its job starts the moment its subject exists, and it has
   been green with `SecurityKit` present ever since. Recorded rather than dressed up as a RED.

3. **Fixture naming.** `vulns-<OSV-ID>.json`, not task 2.1's `vulns-CVE-*.json`, because the records
   are OSV IDs (`GHSA-`, `PYSEC-`, `RUSTSEC-`). Their CVE aliases — what NVD enrichment consumes —
   are tabulated in the README. `CVE-*` would have misstated the file contents.

4. **Prohibition scan matches identifiers, not substrings.** Task 1.5 lists `xattr` as forbidden while
   the design *mandates* `getxattr`/`listxattr`. A substring scan would ban the mandated API and be
   satisfiable only by deleting the feature. The scan is identifier-boundary aware, so `xattr` the
   tool is forbidden and `getxattr` the C function is not; likewise `Process` does not match
   `ProcessInfo`. Triangulated in both directions.

5. **Extra fixtures beyond the task list**, all digested and documented: the `querybatch-affected-*`
   pair (task 2.1 would otherwise have only clean results to test against), two extra `Versions/`
   corpora from Homebrew's own Ruby tests (the orchestrator's U5 requirement), and a second unrated
   hydration for triangulation.

6. **Malformed-payload fixtures deliberately NOT built yet.** Task 3.1 needs a truncated envelope and
   a bad-record response. Their exact shape should be driven by the RED test that consumes them, so
   they belong to Phase 3. Adding them will grow the fixture tree and **`probe-manifest.txt` must be
   regenerated in the same commit**, or `FixtureManifestTests` fails — by design.

---

## What the next batch must know

1. **Read this file first and merge.** Do not overwrite it.
2. **Both gates are closed.** Phases 4, 5, 6 may proceed — U2 and U5 are answered above. **U3 is
   still open** and gates every Phase 14 inspector RED test (task 14.0).
3. **Task 3.5 is amended.** Implement the two replacement assertions, not the struck one.
4. **Adding or editing any fixture requires regenerating `probe-manifest.txt`** in the same commit.
   The digest guard is deliberate.
5. Fixtures are read through `Bundle.module.resourceURL/Fixtures/…` (`resources: [.copy("Fixtures")]`).
6. `SecurityKitSources` / `String.containsIdentifier` in `EgressStructureTests.swift` are the shared
   structural-scan helpers. **Task 7.6 extends that same file** with the two-constant-hosts scan.
7. `SecurityKit.advisoryCacheFileName` already exists for the Phase 16 `cellarApp` cache URL.
8. Prefer `swift test --filter <Suite>` for the inner loop; the full suite is ~16 s.
9. Pre-existing lint debt (11 errors, 105 warnings) is **not** this change's to fix.

---

# Batch 2 — Phases 3, 4, 5, 6

| Field | Value |
|---|---|
| Batch | 2 — Phases 3, 4, 5, 6 (work units 3–6) |
| Mode | **Strict TDD** (no fallback taken) |
| Attempt authority | acquired with the continuation token, `proceed` |
| Safety net | 823 tests / 122 suites green at `e88bc58` before any edit |
| Status | **38 / 108 tasks complete** cumulatively, suite green, no blockers |

## Tasks completed

| Task | What landed |
|---|---|
| 3.1 | RED: `OSVWireTests` — envelope, record, **and positional-result** rules |
| 3.2 | GREEN: `SecurityModels.swift` — the four-state vocabulary |
| 3.3 | GREEN: `ScanProvenance.swift` |
| 3.4 | GREEN: `OSVWire.swift` |
| 3.5 | RED: `NVDWireTests` + `SeverityTierTests`, both amended U2 assertions |
| 3.6 | GREEN: `NVDWire.swift` + the tiering function |
| 4.1–4.3 | RED: `EcosystemMappingTests` — shape, revision fingerprint, collisions, anchors |
| 4.4 | GREEN: `EcosystemMapping.swift` — 7 curated entries with per-entry provenance |
| 5.1 | RED: `HomebrewRevisionTests` incl. the no-comparison structural scan |
| 5.2 | GREEN: `HomebrewRevision.swift` |
| 5.3 | RED: `StrictSemVerTests` — 78.6% asserted row by row |
| 5.4 | GREEN: `StrictSemVer.swift` |
| 5.5–5.6 | RED: `FixVersionComparisonTests` — five cases + the no-`String` scan |
| 5.7 | GREEN: `FixVersionComparison.swift` |
| 6.1–6.2 | RED: `VersionBoundaryTests` — the three-column matrix and the spec scenario |
| 6.3–6.4 | RED: `CVEMatcherTests` — four states, kind, primary keg, no inference |
| 6.5, 6.7 | RED: `CoverageAggregationTests` — four counts, dismissal scoping |
| 6.6 | GREEN: `CVEMatcher.swift` + `AdvisoryQuery.swift` |

## Commits

| # | Hash | Subject |
|---|---|---|
| 3 | `14f1b1b` | `feat(security): decode advisory payloads tolerantly` |
| 4 | `d5304c3` | `feat(security): map formulae to ecosystems from curated data` |
| 5 | `fd7b5e8` | `feat(security): split revisions lexically and parse strict SemVer` |
| 6 | `c0398c7` | `feat(security): match advisories without inference` |

Not pushed; no PR opened. The orchestrator owns the receipt-driven review lifecycle.

## Suite state

| Point | Tests | Suites | Result |
|---|---:|---:|---|
| Baseline (`5863f61`) | 811 | 120 | pass, 1 known issue |
| After batch 1 | 823 | 122 | pass, 1 known issue |
| **After batch 2** | **912** | **132** | pass, 1 known issue |

+89 tests, +10 suites. `SecurityKitTests` alone is now **98 tests in 12 suites**.

`swiftlint --quiet`: **118 total, unchanged from batch 1's post-state**. Every finding in the new
files is in `.build/` generated `resource_bundle_accessor.swift`. **Zero authored findings** in
`Sources/SecurityKit/` or `Tests/SecurityKitTests/`. One was introduced and then removed: `case v2`
tripped `identifier_name`, silenced with a scoped `swiftlint:disable` and a written justification,
following the `HistoryRecording.swift` precedent.

Note for task 18.1: batch 1's record says "72 authored" after batch 1 while this batch measures 90
with the same `.build/`-excluding filter. The two numbers were produced by different filters; the
**total** (116 baseline → 118 after batch 1 → 118 after batch 2) is the comparable series, and it is
flat across this batch.

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 3.1 | `OSVWireTests.swift` | Unit (fixture) | 823/823 green | ✅ `cannot find 'OSVWire' in scope` | ✅ 11 tests | ✅ truncated + non-JSON envelope; record; positional result; both timestamp spellings | ✅ two `ISO8601DateFormatter`s replaced by one `Sendable` strategy |
| 3.2–3.4 | ↑ | Unit | ✅ | ✅ (same compile failure) | ✅ | ✅ shares 3.1's corpus | ➖ |
| 3.5 | `NVDWireTests` + `SeverityTierTests` | Unit (fixture) | ✅ | ✅ `cannot find 'CVSSVersion' in scope` | ✅ 15 tests | ✅ 7 real records × preference; 17 band rows; 9 advertised words; 2 unscored | ➖ |
| 3.6 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ➖ |
| 4.1–4.3 | `EcosystemMappingTests.swift` | Unit (structural + data) | ✅ | ✅ `cannot find 'EcosystemMapping'` | ✅ 11 tests | ✅ 7 collision names; 5 genuine matches; edited/grown/shrunken fingerprint | ✅ `sharedUpstream` de-schemed to protect task 7.6 |
| 4.4 | ↑ | Unit | ✅ | ✅ **the fingerprint guard failed on its own placeholder** | ✅ | ✅ | ➖ |
| 5.1 | `HomebrewRevisionTests.swift` | Unit (corpus + structural) | ✅ | ✅ `cannot find 'HomebrewRevision'` | ✅ 7 tests | ✅ 17 `_N` rows; 298 suffix-free corpus rows; 5-case scanner control | ➖ |
| 5.2 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ➖ |
| 5.3 | `StrictSemVerTests.swift` | Unit (corpus) | ✅ | ✅ `cannot find 'StrictSemVer'` | ✅ 8 tests | ✅ 25 accept/reject rows; 159 classified rows; 11 precedence pairs | ➖ |
| 5.4 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ➖ |
| 5.5–5.6 | `FixVersionComparisonTests.swift` | Unit (+ structural) | ✅ | ✅ `cannot find 'FixVersionComparator'` | ✅ 8 tests | ✅ all five verdicts distinct; 4-case scanner control | ➖ |
| 5.7 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ➖ |
| 6.1–6.2 | `VersionBoundaryTests.swift` | Unit (fixture + structural) | ✅ | ✅ `cannot infer contextual base` | ✅ 11 tests | ✅ 7 captured queries; 6 uninterpretable rows; 3 ordering controls | ➖ |
| 6.3–6.4 | `CVEMatcherTests.swift` | Unit (fixture + structural) | ✅ | ✅ `has no member 'isDismissed'` | ✅ 8 tests | ✅ 4 states; 4 error kinds; decoy prose; wrong ecosystem; 7 fix-selection rows | ➖ |
| 6.5, 6.7 | `CoverageAggregationTests.swift` | Unit | ✅ | ✅ (same) | ✅ 8 tests | ✅ mixed set; all-unanswerable set; 159 all-unmapped; version and package dismissal scoping | ➖ |
| 6.6 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ **fix selection proven by mutation** (see Deviation 11) | ✅ nested `Coverage` (Deviation 9) |

Tests written this batch: **89**. Passing: 89. Layers: Unit 89 (fixture-driven, corpus-driven and
structural). Approval tests: none — no refactoring task in this batch.
Pure functions created: `OSVWire.timestamp`, `SeverityTier.tiered`, `SeverityTier.preferredScore`,
`SeverityTier.tier(advertised:)`, `CVSSScore.tier`, `EcosystemMapping.fingerprint`,
`EcosystemMapping.lookup`, `HomebrewRevision.split`, `StrictSemVer.parse`,
`FixVersionComparator.compare`, `FixVersionComparator.resolve`,
`EcosystemVersionScheme.interprets`, `AdvisoryQueryPlanner.plan`, `CVEMatcher.match`,
`CoverageTotals.init(of:)` — 15.

## Work Unit Evidence

| Unit | Focused command | Result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| 3 | `swift test --filter "OSVWireTests\|NVDWireTests\|SeverityTierTests"` | 26 tests pass | N/A — fixture-provable, no runtime boundary | `SecurityModels/ScanProvenance/OSVWire/NVDWire.swift` + 4 derived fixtures + manifest |
| 4 | `swift test --filter EcosystemMappingTests` | 11 tests pass | N/A | `EcosystemMapping.swift` |
| 5 | `swift test --filter "HomebrewRevisionTests\|StrictSemVerTests\|FixVersionComparisonTests"` | 23 tests pass | N/A | `HomebrewRevision/StrictSemVer/FixVersionComparison.swift` |
| 6 | `swift test --filter "CVEMatcherTests\|VersionBoundaryTests\|CoverageAggregationTests"` | 27 tests pass | N/A | `CVEMatcher.swift` + `AdvisoryQuery.swift` |
| all | `swift test --package-path Packages/CellarCore` | **912 / 132 pass**, 1 known issue | N/A — no egress, no process, no disk write exists yet | the four commits above, revertible in order |

No runtime harness applies to this batch: every unit is a pure value transformation over captured
fixtures. The first runtime boundary is **MV-6** in phase 7, where a real request is issued.

## Fixtures added

Four **derived** payloads, each one documented edit away from a real capture, with
`probe-manifest.txt` regenerated in the same commit each time. Every pre-existing digest is
byte-unchanged, which is itself the evidence that no capture was touched.

| Path | SHA-256 | Derivation |
|---|---|---|
| `OSV/querybatch-truncated-response.json` | `4bb42795d679496f768d8240de02a0caa353c6753e5ce202ea9b36d1c16d2801` | the real bytes, cut at 180 |
| `OSV/querybatch-badrecord-response.json` | `fc3bea4e7cc2c7cf21c8edf52e14e40a329bc0f3060b79a030d2f9d55e40c00b` | real result #2, middle entry's `id` deleted |
| `OSV/querybatch-badresult-response.json` | `a4d1ebd09f41a98b852e843edbe3c5f17b2bf463a16c4cfbcd676dde1596b1b5` | real results #2–3 behind a string where an object belongs |
| `NVD/cveids-badrecord-response.json` | `96a176045629a13da4f0e1b6861e53f0b35fe410d127982d14619d54efeb8ddb` | the real 7-record capture, 4th record's `id` deleted |

The fixture tree is now **25 files**. `README.md` documents all four derivations, why the positional
one matters, and the phase-5 correction below.

---

## Deviations from plan — batch 2

Numbering continues from batch 1's list.

7. **OSV's `results` array is positional, and the plan's record rule alone would have been unsafe.**
   Entry *i* answers query *i*, and nothing inside an entry names the package it belongs to. Dropping
   a bad entry the way a lossy array drops a bad formula re-attributes every later answer to the
   wrong package — in the very fixture used, three real `llhttp` CVEs would be filed against
   whatever was query 0, with nothing left in the payload to catch it. A bad entry keeps its slot as
   `OSVQueryResult.unreadable`, and `.unreadable != .answered([])` is asserted. NVD gets the ordinary
   drop-and-count rule, because its records name themselves.

8. **`.covered(clean:)` needed a payload, so `CleanCoverage` exists.** Swift will not synthesise
   `Hashable` for a `Void` associated value, and the case needs one to be declarable at all. The
   payload was made useful rather than a placeholder: `answeredBy` and `queriedVersion`, so a clean
   result is not constructible without naming who was asked about what.

9. **`CVEScanOutcome` is nested one level — a hard language constraint, measured.** The design writes
   `.covered(findings:)` and `.covered(clean:)`. Swift **declares** two same-named cases and then
   **refuses to pattern-match them**: every `case .covered(…)` resolves to whichever was declared
   last, and the other is
   `error: tuple pattern element label 'findings' must be 'clean'`. Verified against the toolchain
   with a standalone reproduction before changing anything. `case covered(Coverage)` with
   `Coverage { findings, clean }` keeps the four states, their names, and the absence of any boolean
   shortcut. **Downstream phases must spell it `.covered(.findings(…))` / `.covered(.clean(…))`.**

10. **One extra source file: `Sources/SecurityKit/AdvisoryQuery.swift`.** The design's file table does
    not list it. The version boundary needs nothing from `BrewClient` — only a package identity and
    one version string — so it lives where `swift test` reaches it, and the app-side
    `SecurityQueryBuilder` (task 15) becomes a projection with no rules of its own. That is the thin
    composition point the placement decision was after, not a widening of it.

11. **Fix selection among several declared fixes was not in the plan, and was written after the
    code.** An advisory declares one `fixed` event per maintained branch; `PYSEC-2026-899` declares
    four. The relevant one is the earliest at or above the install, else the latest. Because the test
    followed the implementation rather than preceding it, it was **proven non-vacuous by mutation**:
    replacing the rule with the naive last-declared-fix fails six of seven cases and reports an
    up-to-date `3.20.2` install as still affected. Recorded as a strict-TDD gap that was closed, not
    as a clean cycle.

12. **Interpretability is per ecosystem, not strict SemVer everywhere.** The design says "interpretable
    in the mapped ecosystem's scheme" and the plan's examples are all SemVer. `protobuf 35.1` — in the
    phase-2 capture, answered by OSV — is two components: not SemVer, ordinary PEP 440. A single
    SemVer gate would have silently dropped a package real advisory data covers, and would have made
    task 7.1's byte-comparison unsatisfiable. `EcosystemVersionScheme` carries a deliberately
    conservative PEP 440 subset for PyPI; a version it rejects becomes an admitted gap rather than a
    coerced question.

13. **A phase-2 capture's commentary was wrong and is corrected in documentation, not in its bytes.**
    `Versions/homebrew-version-spec-corpus.txt`'s header lists `1.2.3-p2` among "non-SemVer prerelease
    spellings". It is valid SemVer 2.0.0 — `p2` is an ordinary alphanumeric prerelease identifier,
    structurally identical to the `1.2.3-rc.1+build` task 5.3 requires accepting, and to the real
    `luv 1.52.1-0`. Accepting it is also the safe direction: Homebrew reads `-p2` as a patch level
    *above* `1.2.3` while SemVer orders a prerelease *below* it, so an installed `1.2.3-p2` looks
    older than a fix at `1.2.3` — a visible false positive, never a silent false negative. The
    correction lives in `Fixtures/README.md` and is pinned by
    `StrictSemVerTests.aHyphenatedPatchLevelIsValidSemVer`; the capture's own bytes are left unchanged
    so its recorded digest still stands.

14. **`EcosystemMapping.revision` was given a fingerprint.** The plan asks only for "a monotonic
    constant". The advisory cache invalidates on it, which is worthless if the constant can go stale,
    so the table carries `revisionFingerprint`, recomputed on every run: editing an entry without
    bumping the revision fails the suite. It caught its own placeholder on the first run.

15. **Two curated entries are cross-language bindings, and say so in their own data.** PyPI/`protobuf`
    and npm/`llhttp` are bindings of the same upstream the C formulae build, so an advisory may apply
    to one language surface and not the other. Recorded in each entry's `provenance` field rather than
    dropped or hidden — they are in the phase-2 capture, and removing them would have made task 7.1's
    byte-comparison unsatisfiable.

16. **Provenance records `host/owner/repo`, not a URL.** A `https://` literal in the mapping table
    would force task 7.6's two-constant-host scan into an allow-list, or into distinguishing URLs that
    are requested from URLs that are merely cited. A string that is not a URL cannot become a request
    by accident.

---

## What the next batch must know

1. **Read this whole file first and merge.** Batch 1's record is above; do not overwrite either.
2. **Resume at Phase 7, task 7.1.** Phases 3–6 are complete and committed.
3. **`CVEScanOutcome` is `.covered(.findings(…))` / `.covered(.clean(…))`** — Deviation 9. The design's
   flat spelling does not compile.
4. **`AdvisoryQuery` already exists** in `Sources/SecurityKit/AdvisoryQuery.swift`, together with
   `AdvisoryQueryPlanner`, `AdvisoryQueryPlan` and `EcosystemVersionScheme`. Task 7.2's
   `AdvisorySource` protocol consumes `[AdvisoryQuery]` from there rather than declaring its own.
5. **Task 7.1's byte-comparison is already reachable.** `everyCapturedQueryIsStillProduced` holds all
   seven captured queries against the planner, so the request `OSVSource` must produce is one the
   table and planner can actually generate. The captured request body is canonical JSON — `sort_keys`,
   two-space indent, one trailing newline — per the Fixtures README.
6. **Task 7.6 depends on Deviation 16.** No `https://` literal exists anywhere in
   `Sources/SecurityKit/` yet, so the two base URLs `OSVSource`/`NVDSource` declare will be the only
   two, and the scan can stay an exact equality rather than an allow-list.
7. **`AdvisoryError` currently has five cases** — `malformedPayload`, `malformedRecord`, `offline`,
   `rateLimited`, `transportFailed`. Phase 7 adds `payloadTooLarge` (task 7.1) and phase 9 adds
   `blockedPendingConsent` (task 9.3); each should arrive with its own RED test rather than being
   added speculatively.
8. **`SeverityTier.tiered(from:advertised:)` is what enrichment feeds.** `NVDSource` produces
   `[String: SeverityTier]` keyed by CVE identifier for `CVEMatcher.match(severities:)`. Task 7.4's
   rate-limit test is satisfied by returning `.unanswered(.rateLimited)` from enrichment while
   discovery's answers stand: the matcher already leaves such findings `.unrated` and never flips an
   outcome to clean.
9. **Adding or editing any fixture still requires regenerating `probe-manifest.txt`** in the same
   commit. It caught two edits this batch, both times correctly.
10. **`SecurityKitSources` / `String.containsIdentifier`** in `EgressStructureTests.swift` remain the
    shared structural-scan helpers, and are now used by four suites. `Fixture` in `FixtureLoading.swift`
    is the shared fixture reader — it goes through the bundle copy, so anything it reads is a file the
    manifest already digested.
11. **U3 is still open** and gates every Phase 14 inspector RED test (task 14.0).
12. Pre-existing lint debt is **not** this change's to fix; the comparable series is the raw total
    (116 → 118 → 118).

---

# Batch 3 — Phases 7, 8, 9, 10

| Field | Value |
|---|---|
| Batch | 3 — Phases 7, 8, 9, 10 (work units 7–10) |
| Mode | **Strict TDD** (no fallback taken) |
| Attempt authority | acquired with the continuation token, `proceed` |
| Safety net | 912 tests / 132 suites green at `994c0bd` before any edit |
| Status | **60 / 108 tasks complete** cumulatively, suite green, no blockers |

## Tasks completed

| Task | What landed |
|---|---|
| 7.1 | RED: `OSVSourceTests` + `Fakes/RecordingURLProtocol.swift` (tagged per test) |
| 7.2 | GREEN: `AdvisorySource.swift` (roles + `AdvisorySession`) and `OSVSource.swift` |
| 7.3 | RED: `NVDSourceTests` — 159-formula inventory, batching at 100, the credential seam |
| 7.4 | RED: same file — the rate-limited enrichment scenario, both directions |
| 7.5 | GREEN: `NVDSource.swift` |
| 7.6 | RED: `EgressStructureTests.onlyTwoConstantHostsAppearInTheTarget` + its scanner control |
| 8.1–8.5 | RED: `AdvisoryCacheTests` — TTL, both invalidations, freshness, corruption, the ordinal |
| 8.6 | GREEN: `AdvisoryCache.swift` — `AdvisoryCaching`, `actor AdvisoryCache`, `SecurityScanRevision` |
| 9.1–9.2 | RED: `ScanConsentTests` — nothing before consent, off is fully off (landed with commit 10) |
| 9.3 | RED: same file — `blockedPendingConsent` rather than silence |
| 9.4 | GREEN: `ScanConsent.swift` — the value, its gate, and the provider seam |
| 9.5 | RED: `CredentialStoreTests` — round trip plus the no-defaults/no-logging structural scan |
| 9.6 | GREEN: `KeychainAdvisoryCredentialStore` (protocol half landed in commit 7 — Deviation 19) |
| 10.1 | RED: `SecurityScanEngineTests` — coalescing, drain-then-restart, the event stream |
| 10.2–10.3 | RED: `SecurityRefreshPolicyTests` — the wall-clock/monotonic split, retry and backoff |
| 10.4 | GREEN: `SecurityScanEngine.swift`, `SecurityScanEvents.swift`, `SecurityRefreshPolicy.swift` |

## Commits

| # | Hash | Subject |
|---|---|---|
| 7 | `ec953d5` | `feat(security): acquire advisories from two constant hosts` |
| 8 | `b6797c4` | `feat(security): cache advisory outcomes with two invalidations` |
| 9 | `af10993` | `feat(security): gate egress on recorded consent and a Keychain seam` |
| 10 | `a692b33` | `feat(security): schedule scans behind consent on a split clock` |

Not pushed; no PR opened. The orchestrator owns the receipt-driven review lifecycle.

## Suite state

| Point | Tests | Suites | Result |
|---|---:|---:|---|
| Baseline (`5863f61`) | 811 | 120 | pass, 1 known issue |
| After batch 1 | 823 | 122 | pass, 1 known issue |
| After batch 2 | 912 | 132 | pass, 1 known issue |
| **After batch 3** | **969** | **139** | pass, 1 known issue |

+57 tests, +7 suites: `OSVSourceTests` (11), `NVDSourceTests` (9), `AdvisoryCacheTests` (10),
`ScanConsentTests` (7), `CredentialStoreTests` (7), `SecurityScanEngineTests` (7),
`SecurityRefreshPolicyTests` (6), and `EgressStructureTests` (+2).

`swiftlint --quiet` from the repository root: **118 total, unchanged across batches 1, 2 and 3**.
**Zero authored findings** in `Sources/SecurityKit/` or `Tests/SecurityKitTests/`. Five were
introduced and all five removed rather than silenced: a cyclomatic-complexity violation in
`stripComments` (extracted into a `CommentStripper` state machine), two file-length violations
(`EgressStructureTests` split into `SecurityKitSourceScanning.swift`, `SecurityScanEngine` split into
`SecurityScanEvents.swift`), a nesting violation in `OSVSource`'s wire types (flattened), and two
function-body-length violations (`performScan` split into `enrichIfNeeded`/`settle`, two engine tests
onto a shared helper). One scoped `swiftlint:disable static_over_final_class` with a written
justification: `URLProtocol` declares `canInit` and `canonicalRequest` as class methods, so an
override cannot be `static`.

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 7.1 | `OSVSourceTests.swift` | Unit (transport, fixture) | 912/912 green | ✅ `cannot find 'OSVSource' in scope` | ✅ 11 tests | ✅ 8 MiB exactly vs +1; 429 / 503 / 200-with-same-bytes / no-response; count mismatch; empty list | ✅ wire types flattened |
| 7.2 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ shares 7.1's corpus | ➖ |
| 7.3 | `NVDSourceTests.swift` | Unit (transport, corpus) | ✅ | ✅ `cannot find type 'NVDSource'` | ✅ 9 tests | ✅ 101 vs exactly 100 vs 0 ids; keyed vs anonymous request; 159-name disjointness with a positive anchor | ➖ |
| 7.4 | ↑ | Unit (fixture) | ✅ | ✅ | ✅ | ✅ unrated under 429 / scored with enrichment / advertised word survives | ✅ fixture corrected (Deviation 25) |
| 7.5 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ➖ |
| 7.6 | `EgressStructureTests.swift` | Unit (structural) | ✅ | ✅ failed on the interpolation half | ✅ 2 tests | ✅ third host + interpolated host + commented-out host | ✅ `stripComments` extracted; escape pairs preserved (Deviation 22) |
| 8.1–8.5 | `AdvisoryCacheTests.swift` | Unit (+ real disk) | ✅ | ✅ `cannot find type 'AdvisoryCacheKey'` | ✅ 10 tests | ✅ TTL boundary both sides + future stamp; stale/newer/matching versions; modified −1/=/+1 and the nil case; absent/corrupt/foreign-schema/good file | ➖ |
| 8.6 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ➖ |
| 9.3–9.4 | `ScanConsentTests.swift` | Unit | ✅ | ✅ `cannot find 'ScanConsent'` | ✅ 4 tests | ✅ granted vs not vs revoked vs decoded | ➖ |
| 9.5–9.6 | `CredentialStoreTests.swift` | Unit (+ structural) | ✅ | ✅ `cannot find 'KeychainAdvisoryCredentialStore'` | ✅ 3 tests | ✅ 10 forbidden tokens × 5-case scanner control | ➖ |
| 9.1–9.2 | `ScanConsentTests.swift` | Unit (engine-level) | ✅ | ✅ `cannot find type 'SecurityScanEngine'` | ✅ 3 tests | ✅ blocked vs consented control; 6 poll granularities and two days after revocation; cache still readable | ➖ |
| 10.1 | `SecurityScanEngineTests.swift` | Unit (concurrency) | ✅ | ✅ (same compile failure) | ✅ 7 tests | ✅ join then vacate then re-scan; cancelled vs successor; enrichment skipped vs asked vs refused | ✅ `performScan` split; two tests onto one helper |
| 10.2–10.3 | `SecurityRefreshPolicyTests.swift` | Unit (clock) | ✅ | ✅ (same) | ✅ 6 tests | ✅ never/at/inside/past/future staleness; 3 attempts with 2 backoffs vs 3 non-retryable errors | ➖ |
| 10.4 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ✅ `SecurityScanEvents.swift` extracted |

Tests written this batch: **57**. Passing: 57. Layers: Unit 57 (transport-level through a
`URLProtocol` seam, fixture-driven, corpus-driven, structural, and clock-driven concurrency).
Approval tests: none — no refactoring task in this batch, and the one pre-existing helper that was
changed (`stripComments`) was changed to make a guard able to fail at all, with its own control test.

Pure functions created: `AdvisorySession.configuration`, `AdvisorySession.body`,
`OSVSource.isWellFormedIdentifier`, `NVDSource.isWellFormedCVEIdentifier`,
`AdvisoryCacheEntry.isValid`, `AdvisoryCacheEntry.age`, `SecurityScanRevision.next`,
`SecurityScanRevision.supersedes`, `ScanConsent.authorise`, `SecurityRefreshPolicy.isStale`,
`SecurityRefreshPolicy.backoff(beforeAttempt:)`, `SecurityRefreshPolicy.isWorthRetrying`,
`SecurityScanEngine.identifiers(in:)`, `SecurityKitSources.stringLiterals` — 14.

## Work Unit Evidence

| Unit | Focused command | Result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| 7 | `swift test --filter "OSVSourceTests\|NVDSourceTests\|EgressStructureTests"` | 28 tests pass | **MV-6 not run** — see Risks | `AdvisorySource/OSVSource/NVDSource/AdvisoryCredentialStoring.swift` + `Fakes/RecordingURLProtocol.swift` + 3 test files |
| 8 | `swift test --filter AdvisoryCacheTests` | 10 tests pass | N/A — real temporary files, no network boundary | `AdvisoryCache.swift` + the `Codable` conformances |
| 9 | `swift test --filter "ScanConsentTests\|CredentialStoreTests"` | 8 tests pass | **Keychain deliberately not exercised** — asserted by query, not by call | `ScanConsent.swift` + the Keychain half of `AdvisoryCredentialStoring.swift` |
| 10 | `swift test --filter "SecurityScanEngineTests\|SecurityRefreshPolicyTests\|ScanConsentTests"` | 20 tests pass | N/A — `TestClock` and an injected wall clock | `SecurityScanEngine/SecurityScanEvents/SecurityRefreshPolicy.swift` |
| all | `swift test --package-path Packages/CellarCore` | **969 / 139 pass**, 1 known issue | — | the four commits above, revertible in order |

**The runtime boundary is exercised at the transport, not at the origin.** Every acquisition test runs
through a `URLProtocol` beneath a real `URLSession` built from the shipped configuration, so the
request bytes, method, URL, headers and cache policy under assertion are the ones a real request would
carry. What is *not* exercised is a live request to `api.osv.dev` or `services.nvd.nist.gov` — that is
manual step MV-6, and it belongs to the app shell (phase 16) where consent can actually be granted.

## Deviations from plan — batch 3

Numbering continues from batch 2's list.

17. **`AdvisorySource` is two role protocols, not one.** The design names a single protocol exposing
    `discover` and `enrich`. Both shipped conformers implement exactly one half — OSV decides
    affectedness, NVD supplies severity, and neither is a fallback for the other — so one protocol
    would force each to carry a permanently unimplemented method and every call site would have to
    know which of them does anything. `AdvisoryDiscovering` and `AdvisoryEnriching` are declared in the
    design's own `AdvisorySource.swift`, with `AdvisorySource` kept as their composition for anything
    that needs both.

18. **The captured request is byte-compared as canonical JSON, not as raw bytes.** Measured before
    changing anything: Foundation's `JSONEncoder` with `.prettyPrinted` emits `"queries" : [` — a
    space before the colon — while the authored fixture is `"queries": [` with a trailing newline, and
    a real client sends compact JSON anyway. The three forms cannot be byte-equal. Both sides are
    therefore normalised through `JSONSerialization`, a serializer with no knowledge of this target's
    types, and the *canonical* bytes are compared. A dropped field, an added field or a reordered
    array all still fail. The Fixtures README's claim that the file is "the byte-comparison target"
    remains true of its content; it was never true of its whitespace.

19. **The `AdvisoryCredentialStoring` protocol landed in commit 7**, not commit 9. Task 7.3's
    `theApiKeyIsReadFromTheCredentialSeamAndNeverFromDefaults` cannot be written without the seam it
    names. The Keychain implementation landed in commit 9 exactly as planned.

20. **One shared request pipeline: `AdvisorySession`.** Not in the file table. The interesting property
    of the session is a *negative* one — no cache anywhere — and a duplicated negative is a negative
    that only half survives the next edit. `AdvisorySession.body(for:on:byteLimit:)` also owns the
    ordering both sources depend on: transport failure ⇒ `offline`, then status classified, then the
    byte guard, and only then a decode.

21. **`OSVSource` rejects a `results` count that disagrees with the query count.** Not in the plan.
    Batch 2's Deviation 7 established that a *dropped* result re-attributes every later answer to the
    wrong package; the same failure can arrive from the server side, and there is nothing in the
    payload to catch it. A length mismatch fails the whole request rather than filing somebody else's
    advisories against the first few packages.

22. **`stripComments` was silently deleting escape pairs, which made task 7.6's interpolation guard
    unable to fire.** The batch-1 implementation advanced past `\` and its successor without emitting
    either, so `"https://\(host)/v1"` reached the scanner as `https://host)/v1` and the
    no-interpolation assertion could never fail. Fixed to preserve both characters, with a control
    test that feeds the scanner a third host, an interpolated host and a commented-out host and
    requires exactly the first two.

23. **The recording network is tagged per test, and the first version was wrong.** `URLProtocol`
    registration is process-global and Swift Testing runs suites concurrently, so a single shared
    ledger let `OSVSourceTests` consume `NVDSourceTests`' stubs. It surfaced as three plausible-looking
    assertion failures — a malformed payload, a zero request count, one batch instead of two — none of
    which was a real defect. Each `RecordingNetwork` now stamps its session with a private header and
    only ever sees its own exchanges. Recorded because the failure mode was *convincing*: it looked
    exactly like production bugs.

24. **`AdvisoryError` gained the two planned cases and one doc correction.** `payloadTooLarge` (task
    7.1) and `blockedPendingConsent` (task 9.3) each arrived with their own RED test, as batch 2
    required. `transportFailed`'s documentation was widened to cover a non-success status that carries
    no advisory content, because that is now a second way to reach it.

25. **Task 7.4's advisory had to change, and the scenario is stronger for it.**
    `GHSA-p24j-h477-76q3` advertises `HIGH` in its own record, so it can never be `unrated` no matter
    what enrichment does — a test asserting otherwise would have been demanding that a *published*
    severity be discarded. The scenario is asserted with `PYSEC-2026-899`, which publishes no severity
    word anywhere and whose alias `CVE-2022-1941` is in the enrichment capture, so the same record runs
    down both paths. A companion test asserts the advertised word *does* survive a rate limit. The two
    together are what "does not fabricate severity" actually means: nothing is invented, and nothing
    published is thrown away.

26. **An entry or a scan stamped in the future is treated as invalid, not as eternally fresh.** Not in
    the plan. A clock that moved backwards makes an age negative, and a negative age is not an age —
    without this, one skewed clock freezes the cache and the schedule for as long as the skew lasts.

27. **`SecurityScanRevision` was introduced in phase 8 rather than phase 11.** Task 8.5 requires the
    ordinal guard "stated as a test", and the guard needs a type. It lives in `AdvisoryCache.swift`
    beside the persisted `revisionOrdinal`; phase 11's `SecurityStore` consumes it rather than
    declaring its own.

28. **`SecurityScanOutcome` rather than `Result`.** Cancellation is neither a result nor a failure:
    folding it into a failure reports a problem where the user simply navigated away, and folding it
    into a result presents a half-finished scan as an answer. Three cases —
    `completed` / `cancelled` / `failed` — keeps `AdvisoryError` free of a lifecycle concern.

29. **Tasks 9.1 and 9.2 landed with commit 10.** Both assert consent *through the scan engine*, which
    task 10.4 creates, so writing them at commit 9 would have left the suite unable to compile. They
    were written RED against the missing engine and turned green by 10.4, in `ScanConsentTests.swift`
    as the plan asks. Task 9.1 also names the *store*, which is phase 11 — that half is re-asserted
    there.

30. **`SecurityTimeSource` is declared locally, not borrowed from `Catalog`.** The two protocols are
    the same shape today and answer to different owners; `CatalogTimeSource` may change for catalog
    reasons. Mirroring a discipline is not the same as sharing a type.

31. **Retry is restricted to the two failures another attempt could fix.** `SecurityRefreshPolicy.isWorthRetrying`
    admits only `offline` and `transportFailed`. Retrying a rate limit immediately is the one thing
    guaranteed to make a rate limit worse; re-sending an oversized or undecodable payload sends the
    same bytes again; and consent does not change because it was asked twice.

32. **`Codable` was added across the outcome value tree** — `VulnerabilityFinding`, `CleanCoverage`,
    `CVEScanOutcome` and its nested `Coverage`, `AdvisoryError`, `FixVersionComparison`,
    `VersionScheme`. Purely additive, and required by "findings are readable offline": the cache
    persists the outcome itself, and `cachedOutcomesArePublishedAsCachedWithTheirAge` asserts the real
    findings survive the disk rather than merely that a file was written.

33. **Two files were split to stay under the 400-line rule**, both mechanical:
    `Tests/SecurityKitTests/SecurityKitSourceScanning.swift` (the shared source-scanning helpers, now
    used by five suites) and `Sources/SecurityKit/SecurityScanEvents.swift` (the scan's value types).

34. **Refresh-loop tests cancel without awaiting, and this is measured rather than stylistic.**
    `TestClock.sleep(until:)` suspends on a `CheckedContinuation` that only `advance(by:)` resumes, so
    it does not observe task cancellation: `loop.cancel()` followed by `await loop.value` hangs
    forever. The first version of both loop tests did exactly that and the run had to be killed. They
    now follow the shipped `SchedulerTests` pattern — `defer { loop.cancel() }`, never awaited.

---

## What the next batch must know

1. **Read this whole file first and merge.** Batches 1, 2 and 3 are above; do not overwrite any of them.
2. **Resume at Phase 11, task 11.1** (`SecurityStore`). Phases 7–10 are complete and committed.
3. **`SecurityScanRevision` already exists** in `Sources/SecurityKit/AdvisoryCache.swift`, with
   `next()` and `supersedes(_:)`. Task 11.1's ordinal guard consumes it; do not declare a second one.
   `SecurityScanResult` (`revision`, `entries`, `provenance`, `isPartial`) and `SecurityScanOutcome`
   live in `SecurityScanEvents.swift` and are what the store adopts.
4. **The engine already publishes what the store needs.** `SecurityScanEngine.events` is a one-observer
   `AsyncStream<SecurityScanEvent>` carrying `.status(…)` then `.settled(SecurityScanResult)`, and
   `loadCache()` runs before any network work and consults no consent — task 11.4's
   `loadCacheRunsBeforeAnyNetworkWorkAndAdoptsAtThePersistedOrdinal` composes those two.
5. **`isPartial` is already computed** (a refused enrichment, or any skipped OSV record). Task 11.3's
   `aPartialScanIsAdoptedAsPartialAndNeverAsComplete` reads it rather than re-deriving it.
6. **The fakes are in `Tests/SecurityKitTests/Fakes/`** and are the ones to reuse:
   `RecordingNetwork`/`RecordingURLProtocol` (tagged, transport-level), `RecordingAdvisorySource`
   (counts every call, holds discovery open on a `TestClock`), `MutableScanConsent`,
   `MutableTimeSource`, `InMemoryAdvisoryCache`, `InMemoryCredentialStore`.
7. **Never `await` a cancelled refresh loop** — Deviation 34. `defer { loop.cancel() }`.
8. **`CVEScanOutcome` is still `.covered(.findings(…))` / `.covered(.clean(…))`** — batch 2's
   Deviation 9.
9. **U3 is still open** and gates every Phase 14 inspector RED test (task 14.0).
10. **Adding or editing any fixture still requires regenerating `probe-manifest.txt`** in the same
    commit. No fixture was added or edited in this batch, so every recorded digest is byte-unchanged.
11. **Manual step MV-6 (a real request to the two hosts) has not been run.** It needs the app shell and
    a consent grant, so it belongs to phase 16.
12. Pre-existing lint debt is **not** this change's to fix; the comparable series is the raw total from
    the repository root (116 → 118 → 118 → 118).


---

# Batch 4 — Phases 11, 12, 13

| Field | Value |
|---|---|
| Batch | 4 — Phases 11, 12, 13 (work units 11–13) |
| Mode | **Strict TDD** (no fallback taken) |
| Attempt authority | acquired with the continuation token, `proceed` |
| Safety net | 969 tests / 139 suites green at `7c11a00` before any edit |
| Status | **78 / 108 tasks complete** cumulatively, suite green, no blockers |

## Tasks completed

| Task | What landed |
|---|---|
| 11.1 | RED: `SecurityStoreGuardTests` — the generation guard and the ordinal guard, moved independently |
| 11.2 | RED: same suite — the duplicate joins, the older returns without disarming the dedup |
| 11.3 | RED: `SecurityStoreLifecycleTests` — `lastGood` survives a failure, partial is never content |
| 11.4 | RED: same suite — the cache load precedes every request and adopts at the persisted ordinal |
| 11.5 | GREEN: `SecurityStore.swift`, plus persisted provenance/partiality in `AdvisoryCache` |
| 12.1 | RED: `MigrationTests` — the first real V1→V2 store, field by field, plus the entity comparison |
| 12.2 | GREEN: `SchemaV2.swift` — `DismissedCVE`, primitives only |
| 12.3 | GREEN: the `.lightweight` stage and the container opened at V2 |
| 12.4 | RED: `DismissalStoreTests` — exact scope, upgrade re-surfacing, enumerable, reversible |
| 12.5 | RED: same file — the value boundary, behaviourally and structurally |
| 12.6 | GREEN: `DismissalStore.swift` — the only `Persistence` file importing `SecurityKit` |
| 12.7 | RED: `LocalStoresTests.oneContainerStillServesEveryStore` + the shared-reason half |
| 13.1 | REFACTOR: `source(at:)` generalized to package-root-relative paths, suite re-run green first |
| 13.2 | RED: the comparator scan restated over the two `BrewClient` files, with its control |
| 13.3 | RED: `noSecurityComparatorIsReachableFromSnooze` over all six files, anchored per file |
| 13.4 | RED: `dismissalStoreIsTheOnlyPersistenceFileImportingSecurityKit` — whole-directory |
| 13.5 | RED: `snoozeBehaviourIsByteIdenticalToItsPreComparatorForm` |
| 13.6 | Nothing went red against shipped code — no earlier phase leaked, no production file changed |

## Commits

| # | Hash | Subject |
|---|---|---|
| 11 | `cf9ac04` | `feat(security): hold scan state behind generation and ordinal guards` |
| 12 | `f79bbe1` | `feat(persistence): add SchemaV2 and dismissals` |
| 13 | `67cda37` | `test(metadata): scope the no-comparator guard to reachability` |

Not pushed; no PR opened. The orchestrator owns the receipt-driven review lifecycle.

## Suite state

| Point | Tests | Suites | Result |
|---|---:|---:|---|
| Baseline (`5863f61`) | 811 | 120 | pass, 1 known issue |
| After batch 1 | 823 | 122 | pass, 1 known issue |
| After batch 2 | 912 | 132 | pass, 1 known issue |
| After batch 3 | 969 | 139 | pass, 1 known issue |
| **After batch 4** | **1004** | **143** | pass, 1 known issue |

+35 tests, +4 suites: `SecurityStoreGuardTests` (6), `SecurityStoreLifecycleTests` (8),
`DismissalStoreTests` (11), `SnoozeGuardTests` (7), `MigrationTests` (+3), `LocalStoresTests` (+1),
`SnoozeProjectionTests` (−1, moved to the guard suite).

`swiftlint --quiet` from the repository root: **118 total, unchanged across batches 1, 2, 3 and 4**.
**Zero authored findings.** Four were introduced and all four removed by splitting rather than
silencing: `SecurityStoreTests` (file + type body) split into `SecurityStoreTests` /
`SecurityStoreLifecycleTests` / `SecurityStoreArrangement`; `MigrationTests` (function body,
`identifier_name` on `v1`/`v2`, then file length) split into `MigrationTests` /
`MigrationFixtures`; `SnoozeProjectionTests` (file + type body) split into `SnoozeProjectionTests` /
`SnoozeGuardTests`.

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 11.1 | `SecurityStoreTests.swift` | Unit (main-actor concurrency) | 969/969 green | ✅ `cannot find type 'SecurityStore' in scope` | ✅ 6 tests | ✅ same ordinal, live vs superseded generation; ordinal 7 then 3 | ✅ suite split three ways |
| 11.2 | ↑ | Unit | ✅ | ✅ (same) | ✅ | ✅ concurrent duplicate, settled re-delivery, older-then-newer | ✅ join assertion rewritten (Deviation 37) |
| 11.3 | `SecurityStoreLifecycleTests.swift` | Unit | ✅ | ✅ (same) | ✅ 8 tests | ✅ partial vs complete control; failure with and without a last good | ➖ |
| 11.4 | ↑ | Unit (+ round trip) | ✅ | ✅ (same) | ✅ | ✅ absent cache vs populated; ordinal 11 refused after 12; live round trip | ➖ |
| 11.5 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ✅ `project` extracted off-main |
| 12.1 | `MigrationTests.swift` | Unit (real SQLite) | 983/983 green | ✅ `cannot find type 'DismissedCVE'` | ✅ 8 tests | ✅ three models field by field; entity sets; the unique key | ✅ fixture write extracted; throwaway moved out |
| 12.2–12.3 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ➖ |
| 12.4 | `DismissalStoreTests.swift` | Unit (real SQLite) | ✅ | ✅ `cannot find type 'DismissalStore'` | ✅ 11 tests | ✅ four key components moved one at a time; two unaliased advisories; alias appearing later | ➖ |
| 12.5 | ↑ | Unit (+ structural) | ✅ | ✅ | ✅ | ✅ values outlive their store; no public declaration names the model; `Sendable` at compile time | ➖ |
| 12.6 | ↑ | Unit | ✅ | ✅ | ✅ | ✅ | ➖ |
| 12.7 | `LocalStoresTests.swift` | Unit | ✅ | ✅ `no member 'dismissals'` | ✅ 1 test | ✅ available path and the shared-reason failure path | ➖ |
| 13.1 | `SnoozeProjectionTests.swift` | Unit (approval) | **11/11 green before and after** | ➖ refactor — approval, not RED | ✅ | ➖ | ✅ reader generalized |
| 13.2–13.5 | `SnoozeGuardTests.swift` | Unit (structural) | ✅ | ✅ `cannot find 'capabilitySources'` | ✅ 7 tests | ✅ 4-case comparator control, 4-case security control, import vs mention vs absence | ✅ split from the behavioural suite |

Tests written this batch: **35**. Passing: 35. Layers: Unit 35 (main-actor concurrency, real
SQLite through SwiftData, and structural).
Approval tests: **task 13.1** — the eleven existing snooze tests were run before the refactor,
unchanged during it, and green after, which is the whole of what that task asks for.
Pure functions created: `SecurityStore.project`, `AdvisoryCacheFile.scanResult`,
`DismissalIdentity.init(_:)`, `DismissalRecord.identity`, `SnoozeGuardTests.importsSecurityKit` — 5.

## Work Unit Evidence

| Unit | Focused command | Result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| 11 | `swift test --filter SecurityStore` | 14 tests pass | N/A — `TestClock` and an injected wall clock | `SecurityStore.swift` + the `AdvisoryCacheFile` provenance hunk + 3 test files |
| 12 | `swift test --filter "MigrationTests\|DismissalStoreTests\|LocalStoresTests"` | 22 tests pass | **MV-4 not run** — see Risks; the migration is exercised against a real on-disk SQLite store | `SchemaV2.swift` + `DismissalStore.swift` + the plan/container/`LocalStores` hunks |
| 13 | `swift test --filter Snooze` | 20 tests pass | N/A — structural | `SnoozeGuardTests.swift` + the `SnoozeProjectionTests` deletion hunk |
| all | `swift test --package-path Packages/CellarCore` | **1004 / 143 pass**, 1 known issue | — | the three commits above, revertible in order |

**Every guard in this batch was proven by mutation**, because all six are absence claims and an
absence passes for free when the code under it is missing:

| Mutation | Result |
|---|---|
| generation check dropped | 3 tests fail |
| ordinal check dropped | 9 tests fail |
| partial adopted as content | 4 tests fail |
| duplicate returns instead of joining | 2 tests fail (**after** the assertion was rewritten — it passed before) |
| dismissal identity keyed on the CVE | 9 of 11 fail |
| version dropped from the dismissal identity | 9 of 11 fail |
| the `.lightweight` stage removed | 1 test fails (the plan test — **not** the data test) |
| a second `import SecurityKit` in `Persistence` | 2 tests fail (13.3 and 13.4) |
| a behavioural snooze test renamed | 1 test fails (13.5) |

## Deviations from plan — batch 4

Numbering continues from batch 3's list.

35. **The advisory cache now persists `provenance` and `isPartial`; `schemaVersion` 1 → 2.** Task
    11.4 requires `loadCache` to publish a `SecurityScanResult`, and the only two fields a reader
    could not recover from the entries were exactly the two that say whether enrichment succeeded.
    Reconstructing them means telling an offline user that a scan whose severities never arrived was
    complete — the fabrication this whole capability exists to prevent. Both are non-optional and
    undefaulted, because there is no honest value to invent for them; the five existing test call
    sites go through `AdvisoryCacheFile.arranged(…)`, a factory whose name says the provenance is
    scenery rather than subject. Old files are discarded by the existing foreign-schema rule.

36. **Adoption's joinable work is the coverage projection.** `CatalogStore`'s duplicate-joins
    contract needs an adoption in flight to join, and `SecurityStore` needed one too. Counting the
    four coverage states over the inventory, off the main actor, is the honest analogue of building
    the search index: it scales with the inventory, it belongs off-main, and it is what makes "one
    materialization, one projection" a countable fact. Stated plainly in the doc comment that the
    work is small today.

37. **The duplicate-join test did not bite on its first writing, and this is recorded rather than
    quietly fixed.** It asserted the coverage *after* awaiting both adoptions, by which time the
    first has finished regardless — so the mutation "return instead of joining" passed. It now reads
    the coverage at the instant the duplicate's own call returns, which is the only moment the two
    behaviours differ, and the mutation fails. Found by running the mutation, not by review.

38. **Three test files where the plan implies one**, all under the 400-line rule and all mechanical:
    `SecurityStoreTests` (the two guards), `SecurityStoreLifecycleTests` (degradation, cache, event
    stream) and `SecurityStoreArrangement` (shared arrangement, so the two suites cannot drift into
    testing different stores). Likewise `Tests/PersistenceTests/MigrationFixtures.swift`.

39. **`DismissedCVE` is keyed on `advisoryID`, not on `cveID`.** The plan's four-part key
    `(cveID, kind, name, version)` is unsafe against the data this app receives: `GHSA-`, `RUSTSEC-`
    and `PYSEC-` records routinely publish **no CVE alias**, so every unaliased finding for one
    package at one version would be stored under the empty string and dismissing one would silence
    the rest — findings the user never answered, disappearing. `cveID` is still stored as an
    attribute because it is what the user sees and what enrichment is keyed by; it is simply not the
    identity. Still four-part, still primitives only, still `#Unique`.

40. **`DismissalIdentity` ignores `cveID` on lookup.** OSV adds CVE aliases to existing advisories
    over time. A snapshot keyed on `DismissalKey` — whose `Hashable` includes `cveID` — would
    silently revoke a dismissal the day an alias appeared upstream, and the user could not tell that
    apart from the re-surfacing an upgrade is *supposed* to cause.

41. **The pre-existing throwaway `SchemaV2` was retargeted to V3.** Its `versionIdentifier` was
    `2.0.0` and collided with the real `SchemaV2` the moment one existed: the store failed to load
    with *"Cannot use staged migration with an unknown model version"*. Its claim was always "the
    version *after* the one we ship costs a stage, not a rewrite", so it now sits above the shipped
    V2 and reuses the real `DismissedCVE` rather than adding a fourth redeclaration.

42. **The `.lightweight` stage is asserted by the plan test, not by the data test.** SwiftData
    performs implicit lightweight migration even with `stages: []`, so removing the stage does *not*
    fail `aStoreWrittenUnderV1OpensUnderV2WithEveryRowIntact` — it fails
    `theShippedPlanDeclaresTheV1ToV2Stage`. Recorded so nobody later reads the data test as proof
    that the stage exists.

43. **The snooze guards moved to `Tests/BrewClientTests/SnoozeGuardTests.swift`.** The combined file
    broke both the 400-line and the 250-line rules, and the split is the point rather than
    housekeeping: in this delta the guard grew and the behaviour did not, and one file made that
    impossible to see in a diff. Task 13.5 now reads the behavioural file **by path**, which is a
    stronger statement from outside than from within.

44. **A mention inside a comment is deliberately not a violation.** Every scan strips comments first,
    following the shipped `code(in:)` discipline, so a doc comment may explain the prohibition
    without breaking it. `theImportScannerDetectsASecondImport` pins all three cases — an import, a
    prose mention, and an absence — so the exclusion is a stated rule rather than an accident.

---

## What the next batch must know

1. **Read this whole file first and merge.** Batches 1–4 are above; do not overwrite any of them.
2. **Resume at Phase 16, task 16.1** (`SecurityPresentation`). Phases 11–13 are complete and
   committed. Phases 14–15 sit *above* 16 in `tasks.md` but ship after it.
3. **`SecurityStore` is `@MainActor @Observable`** in `Sources/SecurityKit/SecurityStore.swift`, with
   `state(for:)`, `coverage(for:)`, `scanStatus`, `isReady`, `start()`, `loadCache()`,
   `startScan(_:)`, `scanNow(_:)` and `cancelScan(_:)`. Task 16.5's composition wires it to the
   engine exactly as `CatalogStore` is wired: `Task { await store.start() }`, cancelled with the
   scene, never awaited.
4. **`AdvisoryCacheFile` now takes `provenance:` and `isPartial:`** and has no defaults for them
   (Deviation 35). In a test that is asserting something else, use `AdvisoryCacheFile.arranged(…)`.
   `AdvisoryCacheFile.scanResult` is the projection `loadCache` adopts.
5. **`SecurityScanState` is the five-case state** (`idle`, `loading(stale:)`, `content`, `partial`,
   `failed(_, stale:)`, `cancelled(stale:)`) with `result` / `staleResult` / `failure` accessors.
   Task 16.1's section projection reads `result`; the freshness label reads each entry's
   `freshness`, which is always `.cached(fetchedAt:)` for anything off the disk.
6. **Dismissal is `DismissalStore` in `Persistence`**, published as `DismissalSnapshot` keyed by
   `DismissalIdentity`, with `lookup: DismissalLookup` for the matcher, `records` for enumeration,
   `dismiss(_:note:at:)` and `restore(_:)`. Task 16.7's dismissal button calls `dismiss`; the
   undo calls `restore`. **The identity ignores `cveID`** (Deviation 40).
7. **`LocalStores` now has three stores on one container** — `metadata`, `history`, `dismissals`.
   The app composition root gets dismissals for free; it must not open a fourth container.
8. **`DismissalStore.swift` must remain the only `Sources/Persistence/` file importing `SecurityKit`**
   (task 13.4 scans the whole directory). A second importer fails the suite by design.
9. **The six-file security scan is anchored per file on its own name.** Renaming any of the six
   without updating `SnoozeGuardTests.capabilitySources` fails rather than passing vacuously.
10. **U3 is still open** and gates every Phase 14 inspector RED test (task 14.0).
11. **Adding or editing any fixture still requires regenerating `probe-manifest.txt`** in the same
    commit. No fixture was added or edited in this batch, so every recorded digest is byte-unchanged.
12. **Manual steps MV-4 (migration on a real store) and MV-6 (a real request) have not been run.**
    MV-4 needs a store written by a shipped build; MV-6 needs the app shell and a consent grant.
13. Pre-existing lint debt is **not** this change's to fix; the comparable series is the raw total
    from the repository root (116 → 118 → 118 → 118 → 118).
