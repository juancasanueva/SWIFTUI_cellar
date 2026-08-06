# Apply progress: `m4-security`

**Cumulative record — batches 1 and 2 of N.** Later batches MUST read this file and merge; never
overwrite. Batch 1's record is preserved below verbatim; batch 2 is appended after it.

| Field | Value |
|---|---|
| Batches landed | 1 (Phases 0–2), 2 (Phases 3–6) |
| Mode | **Strict TDD** (no fallback taken in either batch) |
| Branch | `feature/m4-security` |
| Branch point | `5863f61` (**not** the planned `0bd1f72` — see Deviation 1) |
| Delivery | `single-pr` + user-recorded `size:exception` (Engram obs 7456) |
| Status | **38 / 108 tasks complete**, suite green, no blockers |
| Resumes at | **Phase 7, task 7.1** (advisory acquisition) |

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
