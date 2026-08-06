# Apply progress: `m4-security`

**Genesis write — batch 1 of N.** Later batches MUST read this file and merge; never overwrite.

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
