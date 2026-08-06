# Tasks: M4 — Security (`m4-security`)

Sources: `proposal.md`; `design.md` (validated after one corrective round — **authoritative**);
`specs/` (3 files — `vulnerability-scanning` ADDED 8 req / 14 sc, `artifact-integrity` ADDED 6 req /
8 sc, `local-package-metadata` 1 MODIFIED req / 6 sc). Probe input: U1 (obs 7451); design gate and
apply carry-forwards (obs 7454); closed product decisions (obs 7448, 7450). Baseline: `main` @
`0bd1f72`. Artifact store: hybrid — **this file wins**; Engram `sdd/m4-security/tasks` is an index.

**Strict TDD is active.** Every behavioural task is preceded by its RED test task. Inner loop:
`swift test --package-path Packages/CellarCore`. The three **app-owned** composition points
(`SecurityQueryBuilder`, `ArtifactLocator`, `SecurityRefreshCoordinator`) cannot live in CellarCore —
no CellarCore target may import both `BrewClient` and `SecurityKit` — so their RED tests run in
`cellarTests` under `xcodebuild test`. That is a slower loop and a named cost of the design's
placement decision, not an excuse to skip them.

**This file is deliberately long.** The generic SDD 530-word cap is overridden by the project
precedent (`archive/2026-08-03-m3-services/.../tasks.md`, `archive/2026-08-03-m3-hardening-prelude/`)
and by ruling #7180 c, which requires every manual check to be *written before apply, not improvised
at verify*.

**Probe gates are binding orderings, not suggestions** (design "Probe Deviation"): **U2 and U5 land in
Phase 2, before the matcher, version-boundary and comparator RED tests (Phases 4–6). U3 lands in
task 14.0, before any inspector RED test.** A gate task that is skipped invalidates every test
downstream of it, because the fixture *is* the test input.

---

## Review Workload Forecast

> Forecast against **5,000** — this session's declared `review_budget_lines`. The `400-line budget
> risk` line is the SDD default metric, not this project's budget.

| Field | Value |
|-------|-------|
| Estimated changed lines | **~11,600–14,600** (arithmetic below) |
| Against session budget (5,000) | **2.3×–2.9× over** |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | **PR 1 M4-1 acquisition+matcher (Phases 0–8) → PR 2 M4-2 view+schema (Phases 9–13, 16) → PR 3 M4-3 integrity (Phases 14–15, 17–18)** |
| Delivery strategy | single-pr |
| Chain strategy | pending — **user decision owed** |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

**Why a decision is owed.** `single-pr` means apply MUST NOT start without a recorded
`size:exception`. My recommendation is that the exception should **not** be granted at this size: a
~12,000-line single candidate is 2.4× the budget the user themself set for this session, and this
project has now under-priced three slices in a row (M2-0 1.67×, M2-1 1.82×, M3-1's test bucket
2.1–2.8×), so the true number is more likely the top of my band than the bottom. The three-way split
below follows the design's own M4-1/M4-2/M4-3 boundaries and leaves each slice at or under budget.
Grant `size:exception` only if the user explicitly prefers one PR after reading this.

### Arithmetic

| Bucket | Lines | Basis |
|---|---|---|
| `Sources/SecurityKit/` (23 files) | 3,000–3,400 | sized against shipped models: store ≈ `CleanupStore`+`CatalogStore.adopt` (250), engine ≈ `CatalogSyncEngine` (230), cache ≈ `DiskUsageCache` (200), matcher (200), two inspectors (380), two wire decoders (300) |
| `Sources/Persistence/` | 300–400 | `SchemaV2` (120), `DismissalStore` (180), plan/container/`LocalStores` hunks (45) |
| `cellar/` (app target) | 1,100–1,400 | 4 views (760) + 3 composition points (430) + `AppSection`/`ContentView`/`cellarApp` (92) |
| Tests | **6,400–8,500** | ~125 test functions at this suite's **measured 45–55 lines each** (M3-1 task 17.3 lesson — do NOT price at 20–25), plus 5 new fakes (~400) and captured fixture bodies (~600–1,200) |
| `tasks.md` + verify report | 800–900 | this file plus the verify report, which M3-0 proved must sit inside the budget |
| **Total** | **11,600–14,600** | |

**Where I disagree with the design.** The design forecast 4,600–6,400 source+tests. That prices tests
at roughly parity with sources; this suite's measured ratio in M3-1 was **1.6× sources**, and M4 is
test-heavier still because coverage honesty is asserted as an exhaustive four-state matrix and
because three threat-matrix rows are proven *by prohibition*, which costs a structural scan plus a
positive anchor each. Use my number.

**Drop-first order if the candidate must shrink** (a contingency, not a plan): drop **Phase 14–15**
(the whole integrity half — it is a separate capability with its own spec file and its own rollback
boundary) before anything else; then **Phase 16's `ArtifactIntegrityPanel`**. **Never drop Phase 6,
8, 12 or 13**: Phase 6 is the coverage honesty the feature exists for, Phase 8 is the offline promise,
Phase 12 is the only schema migration, and Phase 13 is the guard `local-package-metadata` requires as
a condition of the comparator existing at all.

### Suggested Work Units

| Unit | Commit | Goal | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| 1 | `chore(core): add the SecurityKit target behind its graph guard` | manifest edges asserted | `swift test --package-path Packages/CellarCore --filter PackageGraphTests` | N/A — manifest-provable | `Package.swift` hunk + `PackageGraphTests` |
| 2 | `test(security): capture the OSV, NVD and version fixtures` | U1/U2/U5 at the Cleanup bar | `swift test --package-path Packages/CellarCore --filter FixtureManifestTests` | **MV-0** (live capture) | `Tests/SecurityKitTests/Fixtures/` |
| 3 | `feat(security): decode advisory payloads tolerantly` | envelope fails, record skips and counts | `swift test --package-path Packages/CellarCore --filter "OSVWireTests\|NVDWireTests\|SeverityTierTests"` | N/A — fixture-provable | `SecurityModels/ScanProvenance/OSVWire/NVDWire.swift` |
| 4 | `feat(security): map formulae to ecosystems from curated data` | unmapped ⇒ `notCovered(.unmapped)` | `swift test --package-path Packages/CellarCore --filter EcosystemMappingTests` | N/A | `EcosystemMapping.swift` |
| 5 | `feat(security): split revisions lexically and parse strict SemVer` | no ordering in the split | `swift test --package-path Packages/CellarCore --filter "HomebrewRevisionTests\|StrictSemVerTests\|FixVersionComparisonTests"` | N/A | `HomebrewRevision/StrictSemVer/FixVersionComparison.swift` |
| 6 | `feat(security): match advisories without inference` | four states, four counts | `swift test --package-path Packages/CellarCore --filter "CVEMatcherTests\|VersionBoundaryTests\|CoverageAggregationTests"` | N/A | `CVEMatcher.swift` |
| 7 | `feat(security): acquire advisories from OSV and NVD` | volume follows findings | `swift test --package-path Packages/CellarCore --filter "OSVSourceTests\|NVDSourceTests\|EgressStructureTests"` | **MV-6** | `AdvisorySource/OSVSource/NVDSource.swift` |
| 8 | `feat(security): cache advisories with TTL and modified invalidation` | offline read with age | `swift test --package-path Packages/CellarCore --filter AdvisoryCacheTests` | **MV-5** | `AdvisoryCache.swift` |
| 9 | `feat(security): gate every egress on recorded consent` | zero egress before consent | `swift test --package-path Packages/CellarCore --filter "ScanConsentTests\|CredentialStoreTests"` | **MV-1, MV-2** | `ScanConsent.swift` + `AdvisoryCredentialStoring.swift` |
| 10 | `feat(security): run scans single-flight on a split stale/poll policy` | one scan, wall-clock staleness | `swift test --package-path Packages/CellarCore --filter "SecurityScanEngineTests\|SecurityRefreshPolicyTests"` | N/A — `TestClock`-provable | `SecurityScanEngine/SecurityRefreshPolicy.swift` |
| 11 | `feat(security): hold scan state behind generation and ordinal guards` | partial never adopted as complete | `swift test --package-path Packages/CellarCore --filter SecurityStoreTests` | N/A | `SecurityStore.swift` |
| 12 | `feat(persistence): add SchemaV2 and dismissals` | first V1→V2 migration | `swift test --package-path Packages/CellarCore --filter "MigrationTests\|DismissalStoreTests\|LocalStoresTests"` | **MV-4** | `SchemaV2/DismissalStore.swift` + plan/container hunks |
| 13 | `test(metadata): scope the no-comparator guard to reachability` | six files, whole-directory scan | `swift test --package-path Packages/CellarCore --filter "SnoozeProjectionTests\|PackageGraphTests"` | N/A — structural | `SnoozeProjectionTests.swift` |
| 14 | `feat(security): classify and inspect brew-managed artifacts` | nothing degrades to "signed" | `swift test --package-path Packages/CellarCore --filter "ArtifactAssessabilityTests\|SignatureInspectorTests\|QuarantineInspectorTests\|IntegrityEngineTests"` | **MV-7, MV-8** | `ArtifactAssessability/CodeSignatureInspecting/QuarantineInspecting/ArtifactIntegrityEngine.swift` |
| 15 | `feat(security): compose queries and artifacts in the app target` | `/Applications` never enumerated | `xcodebuild test … -only-testing:cellarTests/SecurityCompositionTests` | **MV-9** | `cellar/Security/{SecurityQueryBuilder,ArtifactLocator,SecurityRefreshCoordinator}.swift` |
| 16 | `feat(security): show coverage, findings and integrity` | not-covered as prominent as vulnerable | `swift test --package-path Packages/CellarCore --filter SecurityPresentationTests` + `xcodebuild build` | **MV-1, MV-3, MV-10** | `cellar/Security/*` + `AppSection`/`ContentView`/`cellarApp` hunks |
| 17 | `docs(sdd): reconcile the register and open questions` | U2/U3 answers recorded | N/A — docs only | N/A | markdown only |

Phases are **sequential**. Inside a phase, RED strictly precedes its GREEN.

---

## SPLIT BOUNDARIES — two of them, both live until apply begins

- **PR 1 = M4-1, Phases 0–8** (units 1–8) → `m4-security-acquisition`, ≈ **4,300–5,500**.
  Ends at: a complete scan pipeline computable from fixtures, headless, with no store, no UI and no
  egress path wired to a user. Autonomous: nothing outside `Sources/SecurityKit/` +
  `Package.swift` + `Tests/SecurityKitTests/` changes.
- **PR 2 = M4-2, Phases 9–13 and 16** (units 9–13, 16) → `m4-security-cve-surface`, ≈ **4,000–5,300**.
  Ends at: the CVE half is usable — consent, schedule, store, dismissal, section, views.
  `ArtifactIntegrityPanel` is **not** in it; `SecurityView` renders the CVE sections only.
- **PR 3 = M4-3, Phases 14–15, 17–18** (units 14, 15, 17) → `m4-security-integrity`, ≈ **3,300–4,300**.
  Ends at: signature, notarization and quarantine visibility, plus the manual checks and the full gate.

If the split is taken, exactly four things move with it — nothing else:

1. **The spec deltas split too.** PR 1 carries no delta (it ships behind tests only). PR 2 carries
   `vulnerability-scanning` and `local-package-metadata`. PR 3 carries `artifact-integrity`.
2. **`SecurityView` ships twice**: CVE sections in Phase 16, the integrity panel in PR 3.
3. **`cellarApp` composition ships twice**: store/engine/cache in PR 2, `ArtifactLocator` +
   `ArtifactIntegrityEngine` in PR 3.
4. **The Fixtures directory ships in PR 1 for `{OSV,NVD,Versions}`** and grows `{Quarantine,MachO}`
   in PR 3, each with its own `probe-manifest.txt` addendum.

---

## Phase 0: Baseline and delivery precondition

- [x] 0.1 Record the baseline on `0bd1f72`: `swift test --package-path Packages/CellarCore` test/suite
      counts and `swiftlint --quiet` finding count. No commit — this is the number task 18.1 compares
      against.
      **Deviation:** the planned baseline `0bd1f72` is stale — `main` advanced to **`5863f61`**
      (PR #14, `dc55e6c fix(cleanup): parse empty-directory dry-run lines as typed evidence`) between
      `sdd-tasks` and apply. Baseline recorded on `5863f61`, the real branch point of
      `feature/m4-security`. **Measured baseline: 811 tests in 120 suites passing, 1 known issue;
      `swiftlint --quiet` 116 findings (105 warnings + 11 errors — pre-existing, not fixed here:
      4 `type_name`, 2 `line_length`, 2 `large_tuple`, 1 each `shorthand_operator`,
      `identifier_name`, `function_body_length`).** Task 18.1 compares against these numbers.
- [x] 0.2 **Resolve the delivery decision before any code is written** (ruling #7182-1). Either a
      recorded `size:exception` for one ~12,000-line PR, or an explicit choice of chain strategy
      (`stacked-to-main` or `feature-branch-chain`) over the three slices above. Apply MUST NOT start
      until this task is checked with the user's actual answer written into it.
      **User's answer (Engram obs 7456, 2026-08-06): SINGLE PR with an explicit `size:exception`.**
      The user was shown the forecast (~11,600–14,600 lines, 2.3×–2.9× over the 5,000-line session
      budget) and both the tasks forecast's and the orchestrator's recommendation of three chained
      PRs, and chose one PR anyway. `delivery_strategy` resolves to `size:exception` on `single-pr`;
      `chain_strategy` is moot and the split boundaries above are recorded history, not a plan.
      All 19 phases land on `feature/m4-security` as one candidate.

---

# === PR 1 / M4-1 — acquisition and matching ===

## Phase 1: The target, the product, and the structural graph guards

> **RED before the manifest edit.** The graph guard must fail because `SecurityKit` does not exist
> yet, then pass because it exists *with the right edges* — not pass vacuously because the parser
> found nothing (M3-0 task 8.1 lesson).

- [x] 1.1 **RED** `Tests/CatalogTests/PackageGraphTests.swift` — `securityKitDependsOnCatalogAlone`:
      `#expect(graph["SecurityKit"] == ["Catalog"])` and
      `#expect(Self.reachable(from: "SecurityKit", in: graph).isDisjoint(with: ["BrewProcess", "BrewClient", "DiskUsage", "Persistence"]))`.
      — design "Structural guards" (1); `vulnerability-scanning` purpose (brew-free capability).
- [x] 1.2 **RED** same file — `brewClientCannotReachSecurityKit`:
      `#expect(graph["BrewClient"]?.contains("SecurityKit") != true)` **and**
      `#expect(Self.reachable(from: "BrewClient", in: graph).contains("SecurityKit") == false)`. The
      reachability half is what "structurally unreachable" means; the declared half alone would miss a
      transitive edge. — `local-package-metadata` sc *"The security comparator is structurally
      unreachable from snooze"*.
      **Non-RED deviation, recorded in `apply-progress.md` (Deviation 2):** this assertion is a
      prohibition guard over an *absence* that already held before `SecurityKit` existed, so it
      passed on first run and could not be made RED in the ordinary sense.
- [x] 1.3 **RED** same file — `persistenceOwnsBothInwardEdges`:
      `#expect(graph["Persistence"] == ["BrewClient", "SecurityKit"])`, so the second inward edge is an
      asserted fact rather than a side effect of a later commit.
- [x] 1.4 **GREEN** `Packages/CellarCore/Package.swift` — add `.library(name: "SecurityKit", …)`, the
      `.target(name: "SecurityKit", dependencies: ["Catalog"], swiftSettings: [.swiftLanguageMode(.v6)])`,
      the `.testTarget(name: "SecurityKitTests", dependencies: ["SecurityKit", "CellarTestSupport"], resources: [.copy("Fixtures")], …)`,
      and `"SecurityKit"` on `Persistence`'s dependencies. Copy the existing comment discipline: state
      *why* the edge is one-directional, as the `Catalog` and `Persistence` comments already do.
- [x] 1.5 **RED** `Tests/SecurityKitTests/EgressStructureTests.swift` (new) —
      `securityKitSpawnsNothing`: scan every file under `Sources/SecurityKit/` with comments stripped
      for `Process`, `posix_spawn`, `NSTask`, `/usr/bin/`, `spctl`, `codesign`, `xattr`; all absent.
      **Anchor positively first**: assert the scan actually read ≥1 non-empty file and that a known
      present token (`import Foundation`) is found, or the guard passes against an empty read. —
      threat matrix, *Subprocess / process integration* (by prohibition); `artifact-integrity` sc
      *"Inspection spawns nothing and writes nothing"* (the structural half).
- [x] 1.6 **RED** same file — `securityKitWritesNothing`: the same scan finds no `removexattr`,
      `setxattr`, `FileManager.default.removeItem`, `moveItem`, `createFile` or `write(to:` outside the
      one cache file path. — threat matrix, *Filesystem write during classification* (by prohibition).
- [x] 1.7 **GREEN** create `Sources/SecurityKit/SecurityKit.swift` — a single doc-comment file stating
      the target's three prohibitions (no subprocess, no write, two constant hosts), so 1.5–1.6 have a
      real file to read and the prohibitions are documented where they are enforced. **Commit 1.**
      **Two notes.** (a) The scan matches on **identifier boundaries**, not substrings: the threat
      matrix forbids the `xattr` *tool* while the design mandates the `getxattr`/`listxattr` *C
      functions*, so a substring scan would ban the mandated API and be satisfiable only by deleting
      the feature. Triangulated by `theScannerDetectsAViolation` (8 cases) and
      `theScannerDistinguishesTheToolFromTheCFunctions`, or the absences would pass for free.
      (b) `securityKitWritesNothing` is stated **exhaustively** (writers ⊆ {`AdvisoryCache.swift`}),
      not as an allow-list, so it stays valid unchanged through Phase 8.

## Phase 2: Fixture capture — the U1 re-capture and the U2 / U5 probe gates

> **This phase is a gate.** Phases 4, 5 and 6 consume these files as test input. Do not write a
> matcher, comparator or version test before 2.5 is checked.
>
> The bar is `Tests/BrewClientTests/Fixtures/Cleanup/`: byte-exact captures, a `README.md` recording
> endpoint, exact request body, capture date and tool versions, and a `probe-manifest.txt` with the
> SHA-256 of every file.

- [x] 2.1 Re-capture **U1** to the Fixtures standard:
      `Tests/SecurityKitTests/Fixtures/OSV/{querybatch-request.json, querybatch-response.json}` plus
      at least three `vulns-CVE-*.json` hydrations covering a CVSS v3.1 record, a CVSS v4.0 record and
      a record with no score at all. The scratchpad captures from obs 7451
      (`u1-request.json 622dc4d2…`, `u1-response.json 6da8cebf…`) are the source; they are **not**
      the deliverable.
      **Captured**, all HTTP 200 on 2026-08-06. The 7 mapped packages (U1's genuine matches: `bat`,
      `eza`, `ripgrep`, `sd`, `uv`, `protobuf`, `llhttp`) are all installed; at their **real installed
      versions every one is clean** — `querybatch-response.json` is `{"results":[{},…]}`, an
      intentional all-empty capture, and the realistic result U1 predicted. A second
      `querybatch-affected-{request,response}.json` at deliberately older versions of the same real
      packages supplies 19 real advisories as `{id, modified}`, so the matcher has findings to match.
      **Seven hydrations, one per scoring branch** (more than the three required): CVSS v4.0 with and
      without an advertised severity, CVSS v3.1 with and without, no-CVSS-but-advertised (`MODERATE`),
      and **two** no-score-at-all records for `.unrated` triangulation.
      **Naming deviation:** files are `vulns-<OSV-ID>.json`, not `vulns-CVE-*.json`, because the
      hydrated records are OSV IDs (`GHSA-…`, `PYSEC-…`, `RUSTSEC-…`); their CVE aliases are what NVD
      enrichment consumes and are tabulated in the README. Naming them `CVE-*` would have misstated
      what the file contains.
- [x] 2.2 **U2 gate — NVD `cveIds` round-trip.** Capture
      `Fixtures/NVD/{cveids-request.txt, cveids-response.json}` for the identifiers U1 returned, plus
      a rate-limited body (`403`/`429`) and a record carrying **only a CVSS vector string with no
      `baseScore`**. **Record the answer to design Open Question U2 in the README**: whether a
      vector-only record yields a tier or stays `.unrated`. The design default is `.unrated`; if the
      capture contradicts it, say so here and adjust task 3.5, do not silently follow the capture.
      **U2 (a) — plural `cveIds` works.** Seven comma-separated identifiers in one request returned
      HTTP 200, `totalResults: 7`. The design's batched-enrichment shape is confirmed against the real
      API, so task 7.3's `identifiersAreBatchedAtOneHundred` tests real behaviour, not an assumption.
      **U2 (b) — the default stands, the premise does not.** A CVSS metric with a vector and **no
      `baseScore` does not occur**: wherever a `cvssMetricV2/V31/V40` entry exists, its `cvssData`
      carries `baseScore`, and `vectorString` and `baseScore` are always present together across every
      record captured. The real no-score shapes are two, both captured: (i) `metrics: {}` entirely, on
      a CVE at `vulnStatus: "Received"` (`cveids-unrated-response.json`); (ii) a `metrics` entry of a
      **non-CVSS type** — `ssvcV203`, which has no `cvssData` member at all — sitting alongside
      perfectly good v3.1 scores on `CVE-2022-1941` and `CVE-2026-0994`. Shape (ii) is a live decode
      hazard: iterating `metrics` and assuming every entry is a CVSS score mis-tiers a scored record.
      `.unrated` is unchanged as the answer; **only the route to it changed, so task 3.5 is amended
      rather than silently followed** (see 3.5).
      **The rate-limited body is not JSON.** `429` returns 17 bytes of `text/plain`
      (`error code: 1015`, a Cloudflare edge response) with `retry-after: 0` — direct evidence for the
      design's "classify status before any decode attempt" rule. Reproduced by 40 requests at
      concurrency 20 (10 sequential requests all passed, so the limit is concurrency-sensitive rather
      than a simple sliding window). The Cloudflare `__cf_bm` session cookie is `<REDACTED>` in the
      stored headers; every other byte is verbatim, and no key or credential appears anywhere.
- [x] 2.3 **U5 gate — version-string corpus.** Capture the real installed version strings to
      `Fixtures/Versions/installed-versions.txt` with a header recording the machine's formula count
      and the measured split: strict SemVer / SemVer + `_N` revision suffix / neither. This corpus is
      the `arguments:` source for tasks 5.1, 5.3 and 6.1 — a hand-written corpus would test the
      author's imagination instead of Homebrew.
      **Measured over the real 159-formula inventory** (`brew list --formula --versions`, exit 0):
      **strict SemVer 125 (78.6%), strict SemVer + `_N` 9 (5.7%), neither 25 (15.7%)**. 78.6% is the
      number task 5.3 must record — it is what the fix-comparison feature is worth, because fix
      comparison runs over the *installed* string, so the 9 revision rows are covered but not
      comparable (exactly the spec's `1.2.3_1` / `1.2.4` scenario).
      **Two extra corpora captured** (the adversarial half — the inventory says what is *common*,
      Homebrew's own tests say what is *possible*): `homebrew-version-spec-corpus.txt` (149 unique
      strings from Homebrew's `test/version_spec.rb`: `R13B`, `R15B03-1`, `2017-04-17`, `20040914`,
      `8d`, `20c`, `2007f`, `HEAD-abcdef`, `1.2.3-p2`) and `homebrew-pkg-version-spec-corpus.txt`
      (10 strings from `test/pkg_version_spec.rb`, the file that *defines* what `_N` means).
      **Two rows carry more weight than the rest:** `pcre2 10.47_1` and Homebrew's `1.0.1e_1` are a
      `_N` suffix on a **non-SemVer** upstream — the lexical split succeeds and strict SemVer then
      rejects the upstream, which is the version boundary in one line; and `1.0_0` / `2.1.4_0` are
      revision **zero written explicitly**, so `split` must report `0`, never `nil`.
- [x] 2.4 Write `Fixtures/README.md` — endpoint, exact request body, capture date, `brew --version`,
      `curl --version`, macOS build; and `Fixtures/probe-manifest.txt` — SHA-256 of every file above.
      Both written; the README additionally tabulates which scoring branch each hydration exercises,
      records both U2 answers, and marks the all-empty `querybatch-response.json` as an **intentional**
      empty capture (the Cleanup README's own discipline). 21 files digested.
- [x] 2.5 **RED** `Tests/SecurityKitTests/FixtureManifestTests.swift` (new) —
      `everyFixtureMatchesItsRecordedDigest`: recompute SHA-256 for each entry in `probe-manifest.txt`
      and compare; `theManifestNamesEveryFileInTheFixtureTree` (no unlisted file, no listed-but-absent
      file). This is what stops a fixture from being edited to make a test pass. **Commit 2.**
      **RED demonstrated for both halves, since a fixture-integrity test would otherwise pass the
      moment it is written:** corrupting one recorded digest failed `everyFixtureMatchesItsRecordedDigest`
      (and the negative control), and adding one unlisted file failed
      `theManifestNamesEveryFileInTheFixtureTree`; both restored to green. The negative control
      `theDigestCheckDetectsAnEditedFixture` is **permanent**, flipping a byte in a scratch copy so
      the guard can never decay into comparing a recomputation with itself.

## Phase 3: Value vocabulary and tolerant wire decode

- [x] 3.1 **RED** `Tests/SecurityKitTests/OSVWireTests.swift` (new) —
      `aMalformedEnvelopeFailsTheRequest` (truncated or invalid top-level JSON ⇒ throws) and
      `aMalformedRecordIsSkippedAndCounted` (three records in, two out, `skippedRecordCount == 1`).
      This is the `InstalledDecoder` rule stated for a new payload. — `vulnerability-scanning` req
      *"Every result carries provenance, age and cache discipline"*.
      **A third rule was needed and is not in the plan: OSV's `results` array is positional.**
      Entry *i* answers query *i* and nothing inside it names the package it belongs to, so
      dropping a bad entry the way a lossy array drops a bad formula re-attributes every later
      answer to the wrong package. A bad result therefore **keeps its slot** as
      `OSVQueryResult.unreadable`, and `.unreadable != .answered([])` is asserted so the two can
      never be spelled the same way. Three derived fixtures back this
      (`querybatch-truncated-`, `-badrecord-`, `-badresult-response.json`), each one edit away
      from the real capture and documented in the Fixtures README.
- [x] 3.2 **GREEN** create `Sources/SecurityKit/SecurityModels.swift` — `CVEScanOutcome` with the four
      cases `.covered(findings:)`, `.covered(clean:)`, `.notCovered(NotCoveredReason)`,
      `.unavailable(AdvisoryError)`; `NotCoveredReason { unmapped, kindUnsupported, unsupportedVersionScheme }`
      **and nothing else**; `SeverityTier { critical, high, medium, low, none, unrated }`;
      `ResultFreshness { live, cached(fetchedAt: Date) }`; `VulnerabilityFinding`; `AdvisoryError`.
      **No `isClean` accessor exists** — `case .covered(clean:)` is the only way to ask.
      `.covered(clean:)` carries a `CleanCoverage` (`answeredBy`, `queriedVersion`): Swift permits
      the two same-named cases only when both payloads are `Hashable`, and a clean result is a
      positive claim that should not be constructible without naming who was asked about what.
- [x] 3.3 **GREEN** create `Sources/SecurityKit/ScanProvenance.swift` — `scannedAt`,
      `matcherVersion: Int`, `mappingRevision: Int`, per-source `skippedRecordCount`,
      `enrichmentAttempted/Succeeded`, mirroring `CleanupParserProvenance`.
- [x] 3.4 **GREEN** create `Sources/SecurityKit/OSVWire.swift` — `querybatch` (`{id, modified}`) and
      `vulns/{id}` decoders over the Phase 2 fixtures.
- [x] 3.5 **RED** `Tests/SecurityKitTests/NVDWireTests.swift` and `SeverityTierTests.swift` (new) —
      `theTierPrefersCVSSv4ThenV31ThenV30ThenV2` parameterized over the U2 fixtures;
      `anAdvertisedSeverityIsUsedWhenNoScoreExists`;
      `anUnscoredAdvisoryStaysUnratedAndSortsInItsOwnBucket` — never defaulted to medium;
      ~~`aVectorOnlyRecordFollowsTheU2Answer`~~ **(amended by the U2 gate, task 2.2 — a CVSS metric
      with a vector and no `baseScore` does not occur in NVD's schema, so this test would assert
      against a case that cannot arise).** Replaced by the two shapes the capture actually found:
      `aRecordWithNoCvssMetricStaysUnrated` (over `cveids-unrated-response.json`, `metrics: {}` at
      `vulnStatus: "Received"`) and `aNonCvssMetricEntryIsIgnoredRatherThanTiered` (over
      `cveids-response.json`, where `ssvcV203` carries **no `cvssData`** yet sits beside real v3.1
      scores on `CVE-2022-1941` and `CVE-2026-0994` — a decoder that assumes every `metrics` entry is
      a CVSS score mis-tiers a scored record). The design default `.unrated` is **unchanged**; only
      the route to it is. `CVE-2026-0994` is the real precedence case: it carries **both** v4.0 (8.2)
      and v3.1 (7.5), so the tier must come from 8.2. — `vulnerability-scanning` sc *"An unscored
      advisory stays unrated"*.
      **Both replacement assertions written and green.** Two further shapes the capture forced:
      (a) `publishedSeverity` lives **inside** `cvssData` for v3.1/v4.0 and **beside** it for v2,
      both on the same record; (b) 8.2 and 7.5 both land in `high`, so a tier-only preference
      assertion would pass against a decoder that picked either — the *selected score* is asserted
      too, via `SeverityTier.preferredScore(among:)`. CVSS v3.0 has no capture in the corpus
      (NVD had re-scored every one under v3.1), so its rung is asserted directly on the ordering
      function and the gap is recorded rather than left silent.
- [x] 3.6 **GREEN** create `Sources/SecurityKit/NVDWire.swift` — the same envelope/record rule plus the
      tiering function. **Commit 3.**
      Two notes. The record rule is deliberately *not* the same as OSV's: NVD's `vulnerabilities`
      array is not positional, so an unreadable record is dropped rather than kept as a slot, and
      `totalResults` stays at the server's count so the gap is the evidence. Tiering computes the
      band from the numeric score under **its own version's** specification — v2 defines no
      `critical` and no `none` — and `theComputedBandAgreesWithNvdsOwnWord` checks all 15 scored
      entries in the capture against NVD's own published word rather than against memory.

## Phase 4: The curated ecosystem mapping

- [x] 4.1 **RED** `Tests/SecurityKitTests/EcosystemMappingTests.swift` (new) —
      `everyEntryCarriesAnExactEcosystemAndPackageNameAndItsProvenance` (no entry has an empty field,
      no entry is a pattern or prefix) and `theMappingRevisionIsAMonotonicConstant`.
      **"Monotonic constant" was given teeth rather than asserted as `revision >= 1`.** The table
      carries a `revisionFingerprint` recomputed on every run, so editing an entry without bumping
      the revision fails the suite — the cache invalidates on `mappingRevision`, and that guarantee
      is worthless if the constant can go stale. It caught its own placeholder on first run.
      `theFingerprintDetectsEveryKindOfEdit` is the negative control (edited, grown, shrunken,
      plus an unedited control). `provenanceCarriesNoScheme` keeps `sharedUpstream` a
      `host/owner/repo` string rather than a URL, so task 7.6's two-constant-host scan stays a
      simple fact instead of an allow-list.
- [x] 4.2 **RED** same file — `theU1CollisionNamesAreDeliberatelyAbsent`, parameterized over
      `["curl", "cmake", "coreutils", "git", "gcc", "ncurses", "glib"]`: each returns `nil` from the
      table. U1 measured these as identity collisions (obs 7451), and a future contributor adding
      `curl → RubyGems` must fail a test that explains why. — `vulnerability-scanning` sc *"An identity
      collision is never a finding"*.
- [x] 4.3 **RED** same file — `aPackageAbsentFromTheTableIsNotCoveredUnmapped` and
      `theTableActuallyMapsTheGenuineMatches` (`bat`, `eza`, `ripgrep`, `sd`, `uv`) — the positive
      anchor, or 4.2 passes against an empty table.
      `theTableIsSingleDigit` adds the numeric anchor: measured over the real 159-formula corpus,
      coverage lands between 2% and 8%, which is U1's measurement stated as a failing condition.
      `aCaskIsNotCoveredForTheKindReason` covers the sharp case — a **cask** named `bat` must not
      borrow the mapped formula's coverage.
- [x] 4.4 **GREEN** create `Sources/SecurityKit/EcosystemMapping.swift` — a compiled Swift literal
      table with per-entry provenance and a `mappingRevision` constant. Single-digit size is correct:
      U1 measured real coverage at ≈3–5%. **Commit 4.**
      Seven entries, matching the packages the phase-2 `querybatch-request.json` capture was taken
      for, so task 7.1's byte-comparison has a table that produces it. `protobuf` and `llhttp` are
      **cross-language bindings of one upstream**, and that caveat is written into their own
      `provenance` field rather than dropped or hidden. `NotCoveredReason` is decided by
      `EcosystemMapping.lookup(_:)` rather than re-derived in the matcher, because the table is the
      only thing that can say "absent".

## Phase 5: The version boundary — lexical split, strict SemVer, comparator

> **Gate:** consumes the U5 corpus from task 2.3.
>
> **Trap, load-bearing.** `HomebrewRevision.split` must contain **no comparison operator at all**. It
> is a lexical decomposition, not an ordering. A `<`, `>`, `compare(` or `.numeric` anywhere in it
> would be the exact leak `local-package-metadata` forbids, one file away from the snooze rule.

- [x] 5.1 **RED** `Tests/SecurityKitTests/HomebrewRevisionTests.swift` (new) —
      `aTrailingUnderscoreDigitsSuffixIsRemoved` (`1.2.3_1 → ("1.2.3", 1)`),
      `everythingElseIsReturnedUnchanged` parameterized over the U5 corpus (`2024-01-05`, `r5`, `8e`,
      `1.2.3`, `1.2.3_beta`, `1.2_3.4`), and
      `theSplitFileContainsNoComparisonOperator` — a structural scan of
      `Sources/SecurityKit/HomebrewRevision.swift` with comments stripped for `<`, `>`, `compare(`,
      `.numeric`, `precedes`, `isNewer`, `isOlder`, anchored positively on `split(`.
      **The scan normalises `->` away first.** A return arrow is not a comparison, and a raw `>`
      substring scan would ban every function signature and be satisfiable only by deleting the
      function — the same failure mode the `xattr` tool / `getxattr` C function distinction avoids
      in `EgressStructureTests`. `Comparable`, `sorted`, `max(` and `min(` were added to the token
      list, and `theComparisonScannerDetectsAnOrdering` is the negative control. The prohibition
      shaped the implementation: it slices with `prefix(upTo:)` rather than a range operator and
      decides "is this a digit" per character rather than against a bound.
      All 17 captured `_N` rows are parameterized, and
      `theWholeCorpusIsUnchangedWhereItCarriesNoSuffix` walks all 298 suffix-free rows of both
      corpora.
- [x] 5.2 **GREEN** create `Sources/SecurityKit/HomebrewRevision.swift` —
      `split(_: String) -> (upstream: String, revision: Int?)`.
- [x] 5.3 **RED** `Tests/SecurityKitTests/StrictSemVerTests.swift` (new) —
      `onlyMajorMinorPatchParses` parameterized over the U5 corpus: accepts `1.2.3`,
      `1.2.3-rc.1+build`, rejects `1.2`, `1.2.3.4`, `01.2.3` (leading zero), `v1.2.3`, `1.2.3_1`,
      `2024-01-05`, `r5`. Record the measured accept rate over the real corpus in the test's doc
      comment — that number is what the whole fix-comparison feature is worth.
      **78.6% is recorded in the doc comment and asserted row by row.**
      `theCorpusClassificationHolds` walks all 159 real rows against the class each was measured as
      and asserts the three counts (125 / 9 / 25), so the claim fails if the parser drifts either
      way. The nine `revision` rows additionally assert the boundary itself: the installed string
      does **not** parse, and the upstream it splits into does.
      **Correction to a phase-2 capture, recorded not silently followed:** the corpus header lists
      `1.2.3-p2` among shapes that must be rejected. It is wrong — `p2` is an ordinary alphanumeric
      prerelease identifier, so `1.2.3-p2` is valid SemVer 2.0.0, structurally identical to the
      `1.2.3-rc.1+build` this very task requires accepting and to the real `luv 1.52.1-0`. Accepting
      it is also the safe direction: Homebrew reads `-p2` as a patch level *above* `1.2.3` while
      SemVer orders a prerelease *below* it, so an installed `1.2.3-p2` looks older than a fix at
      `1.2.3` — a visible false positive, never a silent false negative. No installed formula has
      the shape. Corrected in `Fixtures/README.md` and pinned by
      `aHyphenatedPatchLevelIsValidSemVer`; the corpus file's own bytes are **left unchanged** so
      its recorded digest still stands.
- [x] 5.4 **GREEN** create `Sources/SecurityKit/StrictSemVer.swift` — `parse(_: String) -> StrictSemVer?`.
- [x] 5.5 **RED** `Tests/SecurityKitTests/FixVersionComparisonTests.swift` (new) — the five-case
      matrix: `.fixedAtOrBefore`, `.stillAffected`, `.noFixPublished` (a declared "no fix" is **not**
      `.fixUnknown`), `.fixUnknown`, `.notComparable(scheme:)`. — `vulnerability-scanning` req *"Fix
      version is compared only when both sides are strict SemVer"*.
      `everyVerdictIsReachableAndDistinct` reaches all five through one `resolve` call each and
      asserts `Set(verdicts).count == 5`, so no two can quietly collapse.
- [x] 5.6 **RED** same file — `theComparatorCannotBeCalledWithStrings`: a structural scan of
      `FixVersionComparison.swift` asserting every public entry point's parameters are typed
      `StrictSemVer`, and that no overload takes `String`. A function that cannot accept two `String`s
      cannot be misapplied to Homebrew version strings — that is the type-level half of the
      `local-package-metadata` guarantee, and the manifest half is task 1.2.
      **Stated more absolutely than planned, and therefore checkably:** the word `String` (and
      `Substring`, `Character`, `rawValue`) appears **nowhere** in the file — not in a signature,
      not in an overload, not in a raw value, not in a convenience initialiser added later. That
      forced the two operand types to be typed rather than textual: `VersionScheme` carries no raw
      value, and `InstalledVersion` is one value rather than an optional plus a scheme, so a caller
      cannot hand over a missing version and a scheme that disagree.
- [x] 5.7 **GREEN** create `Sources/SecurityKit/FixVersionComparison.swift`. **Commit 5.**

## Phase 6: The matcher, the version boundary matrix, and aggregation

> **Design deviation, load-bearing and measured — `CVEScanOutcome` is nested one level.** The design
> writes `.covered(findings:)` and `.covered(clean:)` as two same-named cases. Swift **declares** them
> without complaint and then **refuses to pattern-match them**: every `case .covered(…)` resolves to
> whichever was declared last, and the other becomes
> `error: tuple pattern element label 'findings' must be 'clean'`. Verified against the toolchain, not
> assumed. The pair is therefore nested — `case covered(Coverage)` with
> `Coverage { findings([…]), clean(CleanCoverage) }` — so the four states, their names and the absence
> of any boolean shortcut are all unchanged, and a `switch` stays exhaustive over exactly four
> possibilities. `.covered(clean:)` also needed a `Hashable` payload to be declarable at all, which is
> why `CleanCoverage` exists (task 3.2).

- [x] 6.1 **RED** `Tests/SecurityKitTests/VersionBoundaryTests.swift` (new) — the three-column matrix
      the design names, one test per row:
      (a) `theQueryVersionIsTheLexicalUpstreamNotTheInstalledString` — `1.2.3_1` is queried as `1.2.3`;
      (b) `coverageIsOSVsAnswerNotALocalRangeEvaluation` — the matcher performs no range arithmetic;
      (c) `anUninterpretableVersionIsNotQueriedAndReportsUnsupportedVersionScheme` — `2024-01-05`
      mapped to a SemVer ecosystem produces `.notCovered(.unsupportedVersionScheme)` and **zero**
      queries.
      (b) is proven behaviourally *and* structurally: the real `GHSA-p24j-h477-76q3` (fixes `bat` at
      `0.18.2`) against an installed `9.9.9` still produces a finding — a local range evaluation
      would have dropped it — and `theMatcherEvaluatesNoRange` scans `CVEMatcher.swift` for the
      tokens such an evaluation would need.
      **Interpretability is the mapped ecosystem's rule, not one rule for all.** `protobuf 35.1` has
      two components: not strict SemVer, ordinary PEP 440, and present in the phase-2 capture. Gating
      every ecosystem on SemVer would have silently dropped a package real advisory data covers, so
      `EcosystemVersionScheme` carries a conservative PEP 440 subset for PyPI and SemVer for
      crates.io / npm. `everyCapturedQueryIsStillProduced` holds all seven captured queries against
      the planner so task 7.1's byte-comparison has a table that can produce its request.
- [x] 6.2 **RED** same file — `aRevisionSuffixedInstallIsCoveredAndReportsAnUncomparableFix`: installed
      `1.2.3_1`, OSV fix `1.2.4` ⇒ `covered(findings)` whose finding states *"fix published,
      comparison not possible for this version scheme"* and asserts **no ordering verdict**. This is
      the spec's own scenario and the single most misreadable interaction in the design. —
      `vulnerability-scanning` sc *"A non-SemVer version is not compared"*.
      Run against **real advisory data** rather than the abstract pair: installed `bat 0.18.1_1`
      against the real `GHSA-p24j-h477-76q3`, which declares a fix at `0.18.2`. Covered (queried as
      `0.18.1`), `declaredFixVersion == "0.18.2"`, `fix == .notComparable(scheme: .homebrewRevision)`,
      and both ordering verdicts asserted absent. `theSameAdvisoryAgainstAStrictInstallDoesOrder` is
      the control, or `notComparable` could be the answer to everything.
- [x] 6.3 **RED** `Tests/SecurityKitTests/CVEMatcherTests.swift` (new) —
      `everyOutcomeIsExactlyOneOfTheFourStates` exhaustive over the four cases;
      `aCaskIsNotCoveredKindUnsupported`; `onlyThePrimaryKegIsEverMatched` (a formula with a linked keg
      and two unlinked kegs yields exactly one queried version and no finding naming an unlinked keg).
      — `vulnerability-scanning` sc *"Only the primary keg is in scope"*.
      "Only the primary keg" is enforced **by the shape of the API**: the planner takes one version
      string and there is no overload taking a list of kegs, so a second query is not something a
      caller can produce by accident. Backed structurally — `kegs`, `InstalledKeg`, `linkedKeg` and
      `primaryKeg` appear nowhere in `Sources/SecurityKit/`, so this target cannot enumerate a keg
      even if it wanted to. Choosing the primary keg keeps its existing owner in `BrewClient`.
- [x] 6.4 **RED** same file — `theMatcherPerformsNoNameSimilarityOrKeywordMatching`: feed an advisory
      whose summary text contains the installed formula's name while the package is unmapped; the
      outcome stays `.notCovered(.unmapped)`. — threat matrix, *inference is not discovery*.
      Both halves: `curl` short-circuits to `.notCovered(.unmapped)` with no query at all, and a
      decoy advisory whose prose says "bat" five times while its `affected` entry names
      `some-unrelated-crate` produces `covered(.clean)`. `anAdvisoryInAnotherEcosystemIsNotAFinding`
      adds the ecosystem half — RubyGems `bat` is different software from crates.io `bat`.
- [x] 6.5 **RED** `Tests/SecurityKitTests/CoverageAggregationTests.swift` (new) —
      `fourDistinctCountsSurviveAggregation` over a mixed set, and
      `theCleanCountIncludesOnlyCoveredClean` — `notCovered` and `unavailable` never fold into it. —
      `vulnerability-scanning` sc *"The four states survive aggregation"*, *"Unanswered packages never
      read as clean"*.
      `anAllUnmappedInventoryIsNotClean` runs the realistic 159-package all-unmapped case U1 predicts
      and asserts `hasUnansweredPackages` — the question a badge or empty state must ask before
      claiming anything — with `aFullyAnsweredCleanInventorySaysSo` as the triangulating control.
- [x] 6.6 **GREEN** create `Sources/SecurityKit/CVEMatcher.swift` — a pure `Sendable` struct over
      values, composing OSV advisories, the mapping entry and the dismissal lookup.
      **One extra file, recorded:** `Sources/SecurityKit/AdvisoryQuery.swift` holds `AdvisoryQuery`,
      `AdvisoryQueryPlan`, `EcosystemVersionScheme` and `AdvisoryQueryPlanner`. The version boundary
      needs nothing from `BrewClient` — only a package identity and one version string — so it lives
      where `swift test` can reach it, and the app-side `SecurityQueryBuilder` (task 15) becomes a
      projection with no rules of its own. That is the thin composition point the design's placement
      decision was after.
      **One rule the plan did not specify: choosing among several declared fixes.** A real advisory
      declares one `fixed` event per maintained branch (`PYSEC-2026-899` declares four). The relevant
      one is the earliest at or above the install; past every branch, the latest. It is a selection
      among values the advisory declared, ordered with the comparator this target already owns — no
      bound is interpreted and no membership computed. Written after the implementation rather than
      before it, and therefore **proven non-vacuous by mutation**: replacing it with the naive
      last-declared-fix rule fails six of the seven cases, reporting an up-to-date `3.20.2` install
      as still affected.
- [x] 6.7 **RED** same test file — `aDismissalSuppressesExactlyOneFindingAndChangesNoCoverageState`:
      the package stays `covered(findings)` with the remaining findings; a second finding for the same
      package is untouched; the coverage state is unchanged. — `vulnerability-scanning` req
      *"Dismissal is scoped to the exact finding and installed version"*. **Commit 6.**
      **Dismissal is a flag, never a removal, and that is what makes the rule enforceable.** Deleting
      dismissed findings would let a package whose every finding was dismissed collapse into
      `covered(.clean)` — a coverage state the user never consented to and the spec forbids dismissal
      from changing. `VulnerabilityFinding.isDismissed` keeps the coverage state fixed and leaves
      suppression to the presentation. `DismissalKey` is keyed on `advisoryID` as well as `cveID`
      because many OSV records carry no CVE alias and would otherwise share a `nil` identity.

## Phase 7: Advisory acquisition

- [x] 7.1 **RED** `Tests/SecurityKitTests/OSVSourceTests.swift` (new), over a new
      `Tests/SecurityKitTests/Fakes/RecordingURLProtocol.swift` —
      `discoveryPostsExactlyOneQuerybatchWithTheMappedSubset` (the exact request body, byte-compared
      against the Phase 2 fixture); `theSessionIsEphemeralWithNoURLCache` (config asserted:
      `.ephemeral`, `urlCache == nil`, `.reloadIgnoringLocalCacheData` on **both** config and request);
      `aBodyOverEightMebibytesIsRejectedBeforeDecode`;
      `aNonSuccessStatusIsClassifiedBeforeAnyDecodeAttempt`.
- [x] 7.2 **GREEN** create `Sources/SecurityKit/AdvisorySource.swift` (the `Sendable` protocol with
      `discover`/`enrich`) and `Sources/SecurityKit/OSVSource.swift`. Base URLs are `static let`
      constants; **no host is built from user input**.
- [x] 7.3 **RED** `Tests/SecurityKitTests/NVDSourceTests.swift` (new) —
      `enrichmentIsByCveIdsOnlyAndNeverNamesAnInstalledPackage`: 159 formulae producing 3 identifiers
      issue requests whose URLs contain none of the 159 names;
      `identifiersAreBatchedAtOneHundred` (101 ids ⇒ 2 requests);
      `theApiKeyIsReadFromTheCredentialSeamAndNeverFromDefaults`. —
      `vulnerability-scanning` sc *"Volume follows findings, not inventory"*.
- [x] 7.4 **RED** same file — `aRateLimitedEnrichmentKeepsFindingsUnratedAndNeverMakesAPackageClean`:
      discovery succeeded, enrichment 429 ⇒ findings survive with `.unrated` and a typed unavailable
      enrichment reason; **no** outcome flips to `covered(clean)`. — sc *"A rate-limited enrichment
      does not fabricate severity or health"*.
- [x] 7.5 **GREEN** create `Sources/SecurityKit/NVDSource.swift`.
- [x] 7.6 **RED** `Tests/SecurityKitTests/EgressStructureTests.swift` —
      `onlyTwoConstantHostsAppearInTheTarget`: scan `Sources/SecurityKit/` with comments stripped for
      `https://` literals; exactly the two declared base URLs are present, and no string
      interpolation appears inside a URL literal. — threat matrix, *Network egress*. **Commit 7.**

## Phase 8: The advisory cache

- [x] 8.1 **RED** `Tests/SecurityKitTests/AdvisoryCacheTests.swift` (new), on an injected clock —
      `anEntryOlderThanTwentyFourHoursIsInvalid` and `anEntryInsideTheTtlIsServed`.
- [x] 8.2 **RED** same file — `aMappingRevisionOrMatcherVersionMismatchInvalidatesRegardlessOfTtl`:
      a corrected table or a fixed matcher can never be masked by a fresh-looking entry.
- [x] 8.3 **RED** same file — `anAdvisoryModifiedNewerThanTheEntryForcesReHydrationInsideTheTtl` — the
      second, independent invalidation the spec requires.
- [x] 8.4 **RED** same file — `cachedOutcomesArePublishedAsCachedWithTheirAge` (never `.live`) and
      `aCorruptOrUnreadableFileYieldsNoEntriesAndNoErrorPath` (the `DiskUsageCache` rule: derived data
      in `~/Library/Caches/` degrades to a full scan). — sc *"Findings are readable offline"*.
- [x] 8.5 **RED** same file — `theRevisionOrdinalSurvivesASimulatedRelaunch`: save at ordinal N, reopen
      from disk, a live scan mints N+1; and
      `aSlowCacheLoadLandingAfterAFastLiveScanIsRejectedByTheOrdinalGuard` — fresh results are never
      blanked by a late cache read. This is the `CatalogStore.loadCache()` → `adopt` precedent stated
      as a test.
- [x] 8.6 **GREEN** create `Sources/SecurityKit/AdvisoryCache.swift` — `AdvisoryCaching` +
      `actor AdvisoryCache`, `AdvisoryCacheKey/Entry/File`, TTL `24 * 60 * 60`, both invalidations, the
      persisted `revisionOrdinal`. **Commit 8. → PR 1 ends here.**

---

# === PR 2 / M4-2 — consent, lifecycle, schema, and the CVE surface ===

## Phase 9: Consent and credentials

- [x] 9.1 **RED** `Tests/SecurityKitTests/ScanConsentTests.swift` (new), over a recording fake source —
      `nothingIsTransmittedBeforeConsent`: construct the store and engine, open the surface, load the
      cache, and assert the recording source saw **zero** requests. — sc *"Nothing is transmitted
      before consent"*.
- [x] 9.2 **RED** same file — `turningScanningOffStopsEveryRequestAndEveryScheduledRun`: after
      revocation, advance the `TestClock` past several poll granularities and past `staleAfter`;
      **zero** requests, **zero** scheduled runs; and `theCacheStaysReadableWithItsAgeAfterRevocation`.
      — sc *"Off means fully off"*.
- [x] 9.3 **RED** same file — `aBlockedEgressEmitsBlockedPendingConsentRatherThanParkingSilently`.
- [x] 9.4 **GREEN** create `Sources/SecurityKit/ScanConsent.swift` — a preference value
      (boolean + date), read before every egress path.
- [x] 9.5 **RED** `Tests/SecurityKitTests/CredentialStoreTests.swift` (new), over an in-memory fake —
      `theKeyRoundTripsThroughTheSeamAndNeverThroughUserDefaults`; and a structural scan asserting
      `Sources/SecurityKit/` contains no `UserDefaults`, no `@AppStorage`, and no `print`/`os_log`
      call site that takes the key value. **No test touches the real Keychain.** —
      `vulnerability-scanning` req *"Scanning is opt-in, disclosed, reversible and Keychain-backed"*.
- [x] 9.6 **GREEN** create `Sources/SecurityKit/AdvisoryCredentialStoring.swift` — the protocol plus
      the `kSecClassGenericPassword` implementation (service `…cellar.nvd-api-key`,
      `kSecAttrAccessibleAfterFirstUnlock`). **Commit 9.**

## Phase 10: Scan engine and refresh policy

- [x] 10.1 **RED** `Tests/SecurityKitTests/SecurityScanEngineTests.swift` (new) —
      `overlappingScansCoalesceOntoTheOneInFlightKeyedByToken`;
      `cancellationDrainsThenRestartsRatherThanLeavingAHalfScan`;
      `theEventStreamSupportsExactlyOneObserver`. Mirrors `CatalogSyncEngine`'s shipped guarantees.
- [x] 10.2 **RED** `Tests/SecurityKitTests/SecurityRefreshPolicyTests.swift` (new) —
      `stalenessIsWallClockAgainstFetchedAtWhileTheLoopSleepsOnPollGranularity`: `staleAfter` is
      24 h compared against the cache's `fetchedAt`, `pollGranularity` is `.seconds(15 * 60)`; assert
      a simulated overnight sleep still wakes with a pending re-scan. A single 24 h monotonic sleep
      would not (`CatalogSyncEngine.swift:149`), which is exactly why the split exists.
- [x] 10.3 **RED** same file — `scanIfStaleDoesNothingWhenTheCacheIsFresh` and
      `maximumAttemptsAndBackoffAreHonouredOnRepeatedTransportFailure`.
- [x] 10.4 **GREEN** create `Sources/SecurityKit/SecurityScanEngine.swift` (`actor`, single-flight by
      token, `AsyncStream<SecurityScanEvent>`, `scanIfStale()`, `runRefreshLoop()`) and
      `Sources/SecurityKit/SecurityRefreshPolicy.swift`. Every egress path checks `ScanConsent` first.
      **Commit 10.**

## Phase 11: `SecurityStore`

- [ ] 11.1 **RED** `Tests/SecurityKitTests/SecurityStoreTests.swift` (new) —
      `aSupersededTaskIsKilledByItsGeneration` and
      `aLateArrivingOlderSnapshotIsRejectedByItsOrdinal`. Two guards, two questions — assert both
      independently, or one masks the other.
- [ ] 11.2 **RED** same file — `aDuplicateOrdinalJoinsTheInFlightAdoptionRatherThanReturning`
      (the `CatalogStore.adopt` contract) and `anOlderOrdinalReturnsWithoutBlanking`.
- [ ] 11.3 **RED** same file — `lastGoodSurvivesAFailedScan` and
      `aPartialScanIsAdoptedAsPartialAndNeverAsComplete`. — `vulnerability-scanning` req *"Degradation
      is explicit and never fabricates a clean result"*.
- [ ] 11.4 **RED** same file — `loadCacheRunsBeforeAnyNetworkWorkAndAdoptsAtThePersistedOrdinal`.
- [ ] 11.5 **GREEN** create `Sources/SecurityKit/SecurityStore.swift` — `@MainActor @Observable`,
      `@ObservationIgnored` internals, `private(set)` state, per-`SecurityScope` (`.cveScan`,
      `.integrity`) generations and task map, `lastGood`, plus the `SecurityScanRevision.ordinal`
      guard. **Commit 11.**

## Phase 12: `SchemaV2`, `DismissedCVE`, and the first migration

- [ ] 12.1 **RED** `Tests/PersistenceTests/MigrationTests.swift` —
      `aStoreWrittenUnderV1OpensUnderV2WithEveryRowIntact`: write `PackageMeta`, `Snooze` and
      `HistoryEntry` rows through a V1 container, reopen under the V2 plan, assert all three survive
      byte-identically; and `theThreeV1ModelsAreUnchangedInV2` (a field-level comparison, not a
      count).
- [ ] 12.2 **GREEN** create `Sources/Persistence/SchemaV2.swift` — `[PackageMeta, Snooze, HistoryEntry, DismissedCVE]`
      with the three V1 models byte-identical; `DismissedCVE` holds `cveID`, `kindRaw`, `name`,
      `version`, `dismissedAt`, `note: String = ""` — **primitives only**, no `@Relationship`, no
      `@Transient`, `#Unique<DismissedCVE>([\.cveID, \.kindRaw, \.name, \.version])`.
- [ ] 12.3 **GREEN** `Sources/Persistence/MetadataMigrationPlan.swift` —
      `schemas: [SchemaV1.self, SchemaV2.self]`, `stages: [.lightweight(from: SchemaV1.self, to: SchemaV2.self)]`;
      `Sources/Persistence/PersistenceContainer.swift` — open `Schema(versionedSchema: SchemaV2.self)`.
      The plan was wired from the first commit precisely so this is a two-line change (design D2).
- [ ] 12.4 **RED** `Tests/PersistenceTests/DismissalStoreTests.swift` (new) —
      `aDismissalIsKeyedByTheExactCveKindNameAndVersion`;
      `aVersionChangeReSurfacesTheFindingWithNoUserAction` (dismiss at `1.0.0`, read at `1.1.0` ⇒ not
      suppressed, and the row is **not** deleted); `dismissalsAreEnumerableAndReversible`;
      `aDismissalSuppressesNoOtherFindingForTheSamePackage`. — `vulnerability-scanning` sc *"An upgrade
      re-surfaces a dismissed finding"*.
- [ ] 12.5 **RED** same file — `persistencePublishesAValueSnapshotAndNeverAModelInstance`:
      `DismissalSnapshot`/`DismissalLookup` are `Sendable` values, mirroring `MetadataLookup`; no
      `@Model` type crosses the boundary.
- [ ] 12.6 **GREEN** create `Sources/Persistence/DismissalStore.swift` — **the only file in
      `Sources/Persistence/` that imports `SecurityKit`** (task 13.3 asserts this exhaustively).
- [ ] 12.7 **RED** `Tests/PersistenceTests/LocalStoresTests.swift` —
      `oneContainerStillServesEveryStore`: the shipped W3 invariant must survive the schema bump.
      **Commit 12.**

## Phase 13: The `local-package-metadata` guard evolution

> **Carry-forward from obs 7454(2):** `SnoozeProjectionTests.source(of:)` hardcodes
> `Sources/BrewClient/`. Extending the guard to six files across two targets requires generalizing it
> **first**, or the new assertions read the wrong files and pass vacuously.

- [ ] 13.1 **REFACTOR** `Tests/BrewClientTests/SnoozeProjectionTests.swift` — generalize
      `source(of:)` to take a package-root-relative path (`"Sources/BrewClient/PackageMetadata.swift"`),
      and re-point the two existing call sites. The existing `noVersionComparatorExists` assertions
      stay **byte-identical in meaning**; only the path plumbing changes. Run the suite before adding
      anything: it must still be green.
- [ ] 13.2 **RED** same file — extend `noVersionComparatorExists` to assert, over the **two
      `BrewClient` files** (`PackageMetadata.swift`, `InstalledFilterMode.swift`): the same forbidden
      comparator tokens absent, and the positive anchor `snoozedVersion == candidate` present.
      Unchanged in substance — restated here so the diff shows the guard was not weakened while being
      moved.
- [ ] 13.3 **RED** same file — new `noSecurityComparatorIsReachableFromSnooze`: over **all six**
      enumerated files (`Sources/BrewClient/PackageMetadata.swift`,
      `Sources/BrewClient/InstalledFilterMode.swift`, `Sources/Persistence/MetadataStore.swift`,
      `Sources/Persistence/LocalStores.swift`, `Sources/Persistence/SchemaV1.swift`,
      `Sources/Persistence/SchemaV2.swift`), with comments stripped: no `import SecurityKit` and no
      textual reference to `SecurityKit`, `StrictSemVer`, `FixVersionComparison` or
      `HomebrewRevision`. — `local-package-metadata` sc *"The security comparator is structurally
      unreachable from snooze"*.
- [ ] 13.4 **RED** same file — new `dismissalStoreIsTheOnlyPersistenceFileImportingSecurityKit`: scan
      the **whole** `Sources/Persistence/` directory and assert `DismissalStore.swift` is the sole file
      containing `import SecurityKit`. This is what stops task 13.3's six-file list from being an
      allow-list escape, which the delta forbids: a second import anywhere in `Persistence` fails the
      suite and forces a design conversation.
- [ ] 13.5 **RED** same file — `snoozeBehaviourIsByteIdenticalToItsPreComparatorForm`: the five
      existing behavioural tests (suppression, revival, the accepted false positive, unsnooze,
      still-listed) run unchanged and green. The delta requires behaviour identical and the *guard*
      grown — this task is the "identical" half, stated so a reviewer can see it was checked.
- [ ] 13.6 **No production change is expected in this phase.** If any task 13.2–13.5 goes red against
      shipped code, **stop and record why** — it means an earlier phase leaked, and the fix is in that
      phase, not here. **Commit 13.**

## Phase 16 (shipped in PR 2 for the CVE half): App shell and the security surface

> Numbered 16 to keep the integrity phases contiguous at 14–15; it ships **before** them if the split
> is taken. Its `ArtifactIntegrityPanel` task (16.9) is the one part deferred to PR 3.

- [ ] 16.1 **RED** `Tests/SecurityKitTests/SecurityPresentationTests.swift` (new) —
      `sectionsAreOrderedVulnerableThenNotCoveredThenCleanThenUnavailable` and
      `theNotCoveredSectionRendersWithItsCountEvenAtZeroFindings`. A pure projection in SecurityKit, so
      the rule is provable by `swift test` rather than by reading a view — the project's
      `InstalledPresentation` / `ServicesPresentation` precedent. — `vulnerability-scanning` req
      *"Coverage is typed and never collapses into 'clean'"* (the presentation clause).
- [ ] 16.2 **RED** same file — `noEmptyStateOrBadgeClaimsTheInventoryHasNoVulnerabilitiesWhenAnythingIsNotCovered`:
      exhaustive over the four states, including the all-unmapped inventory U1 says is the realistic
      case. — sc *"Unanswered packages never read as clean"*.
- [ ] 16.3 **GREEN** create `Sources/SecurityKit/SecurityPresentation.swift` — the section projection,
      counts, and empty-state vocabulary.
- [ ] 16.4 `cellar/Shell/AppSection.swift` — add `.security` **between `.cleanup` and `.history`**,
      title "Security", `systemImage: "checkmark.shield"`. Verified safe: no test asserts a case count
      on `AppSection` (`BulkSelection.Action.allCases` is the suite's only exhaustive enum assertion
      and is untouched).
- [ ] 16.5 `cellar/ContentView.swift` and `cellar/cellarApp.swift` — selection column plus composition:
      `SecurityStore`, `SecurityScanEngine`, `AdvisoryCache(fileURL:)` at
      `Caches/Cellar/security-advisories-v1.json` built **beside** `diskCacheURL`
      (`cellarApp.swift:122-124`), the credential store, and the consent preference.
- [ ] 16.6 Create `cellar/Security/SecurityView.swift` — the four sections in order, four counts, the
      freshness label. Identifiers: `security-coverage-{state}`, `security-finding-{cveID}`,
      `security-freshness`, `security-consent`.
- [ ] 16.7 Create `cellar/Security/SecurityFindingDetail.swift` — frames every finding as
      "Reported for `<ecosystem>/<package>` `<version>`", links the OSV and NVD records, shows
      freshness and provenance, offers dismissal (`security-dismiss-{cveID}`), and its upgrade button
      submits `MutationCommand.upgrade(target)` through the existing `OperationCenter`, **stating
      plainly** when Homebrew's `catalogVersion` differs from the advisory's fixed version. No new
      `BrewMutating` family. — sc *"The upgrade offer names Homebrew's version"*.
- [ ] 16.8 Create `cellar/Security/SecurityConsentSheet.swift` — the disclosure names the two hosts and
      exactly what leaves the machine (mapped package names and versions only), and offers revocation.
      Verified by `xcodebuild build` plus manual steps **MV-1, MV-2, MV-3**.
- [ ] 16.9 *(PR 3)* Create `cellar/Security/ArtifactIntegrityPanel.swift` — see Phase 15.
      **Commit 16. → PR 2 ends here.**

---

# === PR 3 / M4-3 — artifact integrity ===

## Phase 14: Inspectors, assessability, and the streamed sweep

- [ ] 14.0 **U3 gate — probe before any RED test below.** On a real brew-installed cask: run
      `SecStaticCodeCreateWithPath` + `SecCodeCopySigningInformation` + `SecStaticCodeCheckValidity`
      against `"notarized"` and `anchor apple generic`, and `SecAssessmentTicketLookup`. Record
      **latency, network dependence, and whether the ticket lookup succeeds unprivileged on macOS 26**
      — this is design Open Question U3. If it does not succeed unprivileged, non-stapled notarization
      is `.couldNotAssess(.assessmentUnavailable)` and task 14.5 asserts that instead; a weaker
      feature, not a different architecture. **Also fixture-check obs 7454(1):** enumerate one cask's
      artifacts and record whether the `.app` bundle lives in the Caskroom or is a symlink to
      `/Applications`. Capture to `Fixtures/{Quarantine,MachO}/` with a README addendum and extend
      `probe-manifest.txt`.
- [ ] 14.1 **RED** `Tests/SecurityKitTests/ArtifactAssessabilityTests.swift` (new), over fixture files —
      `aBundleWithAContentsMacOSExecutableIsAssessable` for `.app`, `.framework`, `.xpc`, `.bundle`;
      `aRegularFileWhoseFirstFourBytesAreMachOMagicIsAssessable` parameterized over `0xfeedface`,
      `0xfeedfacf`, `0xcafebabe`, `0xbebafeca`;
      `aSymlinkIsNeverAssessable`; `aShellScriptAManPageAndAHeaderAreAllOutOfScope` (return `nil`,
      silently). — `artifact-integrity` req *"Scope is brew-managed artifacts only"*; threat matrix,
      *Executable-file classification*.
- [ ] 14.2 **GREEN** create `Sources/SecurityKit/ArtifactAssessability.swift` —
      `classify(_ url: URL) -> AssessableArtifactKind?`, a pure filesystem predicate, plus
      `ArtifactLocation(packageID:url:kind:)`.
- [ ] 14.3 **RED** `Tests/SecurityKitTests/SignatureInspectorTests.swift` (new), over a fake inspector
      matrix — `eachSigningStateIsTypedAndDistinct` (signed / ad-hoc / unsigned / invalid);
      `aSignedArtifactReportsItsIdentifierTeamIdentifierAndAuthorityChain`;
      `anInconclusiveAssessmentIsCouldNotAssessWithAReasonAndIsCountedAsNeither`. —
      `artifact-integrity` sc *"An inconclusive assessment is not a verdict"*, *"A signed artifact
      reports its identity"*.
- [ ] 14.4 **RED** same file — `noOutcomeEverDegradesToSignedOrNotarized`: exhaustive over every
      failure, cancellation and unreachable path from the U3 capture; each is `.couldNotAssess(reason)`.
      Plus `onlineTicketLookupWithoutConsentIsStapledOrCouldNotAssessOnlineLookupRequiresConsent` —
      the integrity half sits behind the same consent gate because ticket lookup can reach the network.
- [ ] 14.5 **GREEN** create `Sources/SecurityKit/CodeSignatureInspecting.swift` — the protocol plus
      `SecurityFrameworkSignatureInspector`, honouring the U3 answer from task 14.0.
- [ ] 14.6 **RED** `Tests/SecurityKitTests/QuarantineInspectorTests.swift` (new), over the U3 fixtures —
      `theAttributeDecodesIntoFlagsTimestampAgentAndUuid` from the `flags;hexTimestamp;agentName;UUID`
      shape; `theRawValueIsPreservedVerbatimAlongsideTheTypedComponents`;
      `anUnrecognisedComponentReportsUnknownAndIsNeverGuessed`;
      `provenancePresenceIsReportedWhenPresent`. — `artifact-integrity` sc *"A quarantined artifact
      explains itself"*, *"An unrecognised attribute component stays unknown"*.
- [ ] 14.7 **GREEN** create `Sources/SecurityKit/QuarantineInspecting.swift` — the protocol plus
      `ExtendedAttributeQuarantineInspector` over `listxattr`/`getxattr`. **Read-only: no `getxattr`
      sibling write call exists in the file** (task 1.6 already forbids it target-wide).
- [ ] 14.8 **RED** `Tests/SecurityKitTests/IntegrityEngineTests.swift` (new) —
      `resultsArriveIncrementallyPerArtifactRatherThanAsOneTerminalBatch`;
      `aPerArtifactFailureBecomesACouldNotAssessEventAndNeverTerminatesTheStream`;
      `cancellationStopsTheRunWithoutPresentingItAsComplete` and completed items remain shown. —
      `artifact-integrity` sc *"A slow lookup does not freeze or poison the run"*.
- [ ] 14.9 **GREEN** create `Sources/SecurityKit/ArtifactIntegrityEngine.swift` — `@concurrent`
      `inspect` streaming `AsyncThrowingStream<ArtifactIntegrityEvent>` with
      `Task.checkCancellation()` per artifact, exactly as `DiskUsageEngine.scan`.
- [ ] 14.10 **RED** `Tests/SecurityKitTests/IntegrityProhibitionTests.swift` (new) —
      `noByteOfAnInspectedArtifactChanges`: a filesystem observer over a temporary fixture tree
      compares content hashes, mtimes and xattr sets before and after a full sweep;
      `noProcessIsLaunchedDuringAFullSweep` through a recording process launcher (**zero** launches);
      `noElevationIsRequested`. — threat matrix, *Subprocess / process integration*, *Filesystem write
      during classification*; `artifact-integrity` sc *"Inspection spawns nothing and writes nothing"*.
- [ ] 14.11 **RED** same file — `noPublicSurfaceOfTheCapabilityAcceptsAWrite`: enumerate every public
      symbol of the integrity half and assert none takes a mutating verb (clear, remove, strip,
      re-sign, staple, assess-change). — `artifact-integrity` req *"Visibility does not become
      remediation"*. **Commit 14.**

## Phase 15: The app-owned composition points

> **Named cost.** These three files sit in the app target because no CellarCore target may import both
> `BrewClient`/`DiskUsage` and `SecurityKit`. Their tests therefore live in `cellarTests` and run under
> `xcodebuild test`, not `swift test`. Where a rule can be hoisted into a pure CellarCore projection,
> hoist it — the app target is the one target M3-1's Phase 18 proved is where defects hide.

- [ ] 15.1 **RED** `cellarTests/SecurityCompositionTests.swift` (new) —
      `theQueryBuilderEmitsOneQueryPerMappedFormulaAndNothingElse`: unmapped formulae, casks and
      uninterpretable versions produce **no** query and instead their corresponding `notCovered`
      outcome, with **zero** egress; `thePrimaryKegIsReadFromInstalledPackageAndNotRederived` (linked
      wins, else newest — `InstalledDecoder.primaryKeg` stays the single owner);
      `theQueryVersionIsTheHomebrewRevisionSplitOfTheInstalledVersion`.
- [ ] 15.2 **GREEN** create `cellar/Security/SecurityQueryBuilder.swift`.
- [ ] 15.3 **RED** same test file — `onlyBrewManagedLocationsAreEnumerated`: a recording filesystem
      enumerator proves `/Applications` and every non-brew location were **never** enumerated;
      `formulaScopeIsThePrimaryKegsBinAndSbinOnly` (no whole-keg walk, no `include/`, no `share/man/`);
      `caskArtifactsResolveThroughBrewRecordedPathsAndNotALiteralCaskroomWalk` — the obs 7454(1)
      carry-forward, driven by the task 14.0 fixture. — `artifact-integrity` sc *"Non-brew applications
      are out of scope"*.
- [ ] 15.4 **RED** same test file — `everyCandidateIsFilteredThroughArtifactAssessability`: a location
      the predicate rejects never reaches the engine.
- [ ] 15.5 **GREEN** create `cellar/Security/ArtifactLocator.swift`.
- [ ] 15.6 **RED** same test file — `aDailyScheduleAndAPostMutationTriggerEachCauseExactlyOneScan` on a
      `TestClock`, and `neitherFiresWhileConsentIsOff`. — `vulnerability-scanning` req *"Scanning is
      opt-in, disclosed, reversible…"* (the cadence clause).
- [ ] 15.7 **GREEN** create `cellar/Security/SecurityRefreshCoordinator.swift` — the
      `DiskUsageRefreshCoordinator` *pattern*, deliberately in the app target rather than beside it in
      `Sources/BrewClient/` (design "Note on placement").
- [ ] 15.8 **GREEN** `cellar/Security/ArtifactIntegrityPanel.swift` (task 16.9) — quarantined artifacts
      shown **together with** their signing and notarization verdict, decoded components plus the raw
      value, `.couldNotAssess` rendered as itself. Identifier `security-integrity-{package}`.
      **No clearing, removing or re-signing affordance exists** — task 14.11 is the capability-surface
      half; this is the UI half. Verified by `xcodebuild build` plus **MV-7, MV-8, MV-10**.
      **Commit 15.**

---

## Phase 17: Manual verification — written now, executed at apply/verify

> **Ruling #7180 c**: these checks exist **before** apply. Do not improvise additions at verify; if a
> check proves impossible, record *why* rather than quietly dropping it (the M2-3 IH6 lesson).
>
> **The observability constraint, stated plainly.** U1 measured ≈3–5% realistic coverage on this
> machine's 159 formulae. So `notCovered` is the state a human will actually see, and **a live check
> that finds zero vulnerable packages is the expected result, not a failure**. The vulnerable-section
> checks are therefore **FIXTURE-DRIVEN**, and each is labelled **LIVE**, **FIXTURE-DRIVEN** or
> **HEADLESS-ONLY**.

- [ ] 17.1 Build with
      `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      and run the ten checks below in order. Record the **actual** observation for each, not just PASS.

      **MV-0 (LIVE, apply-phase, Phase 2/14.0) — The probe captures.** Each of U2, U5 and U3 executed
      against the real endpoint or the real machine, with the answer to its Open Question written into
      `Fixtures/README.md`. *Expect*: `probe-manifest.txt` digests match on re-run (task 2.5).

      **MV-1 (LIVE) — The Security section exists and is honest on first launch.** Launch with no
      consent recorded, select Security. *Expect*: the section renders, the **Not covered** section is
      present with its count, and **no** summary, badge or empty state says the inventory has no
      vulnerabilities. Confirm no network activity in Console/`nettop` for the process.

      **MV-2 (LIVE) — Nothing is transmitted before consent.** With Little Snitch, `nettop`, or
      Console filtered to the process, open Security and wait 60 s. *Expect*: **zero** connections to
      `osv.dev` or `nvd.nist.gov`. Then read the consent sheet. *Expect*: it names both hosts and
      states that mapped package names and versions are what leave the machine. The authoritative
      proof is task 9.1; this is the human-visible half.

      **MV-3 (LIVE) — Consenting produces a real scan whose coverage is honest.** Consent, wait for
      the scan to settle. *Expect*: four counts, and a **Not covered** count in the neighbourhood of
      95% of the inventory (U1 predicts 3–5% covered). Spot-check three not-covered packages: each
      states its typed reason. *Record the four counts verbatim* — this number is the feature's
      honest self-description and belongs in the verify report.

      **MV-4 (LIVE) — The V1 store survives the V2 migration.** Before building the new binary, note
      the existing snooze and history row counts from the running app. Build, launch. *Expect*: the
      identical counts, the same snoozes still suppressing badges, and the same history entries. The
      authoritative proof is task 12.1; this is the real-store half, and it is the first V1→V2
      migration this app has ever performed.

      **MV-5 (LIVE) — Findings are readable offline with their age.** After a successful scan, turn
      Wi-Fi off entirely, quit and relaunch, open Security. *Expect*: the previous results shown,
      each labelled **cached** with an age, and nothing presented as fresh. *Also expect*: no error
      alert — an unreachable network is an ordinary state here.

      **MV-6 (LIVE) — Request volume follows findings, not inventory.** With a proxy or `nettop`
      recording, run a full scan. *Expect*: **one** OSV `querybatch` POST, at most a handful of
      `vulns/{id}` hydrations, and **zero** NVD requests naming any installed package. Count the
      requests and record the number against the inventory size.

      **MV-7 (LIVE) — A cask app reports a real signing identity.** Pick a brew-installed cask,
      open its integrity panel. *Expect*: the signing identifier, team identifier and authority chain
      as reported by `codesign -dv --verbose=4 <path>` in Terminal — **the same values**, obtained
      without Cellar spawning anything. Compare them literally.

      **MV-8 (LIVE) — Inspection changes nothing and asks for nothing.** Before the sweep, record
      `xattr -l` and `stat` for three inspected artifacts. Run the full integrity sweep. *Expect*:
      identical `xattr` output and identical mtimes afterwards; **no** admin password prompt at any
      moment; **no** `codesign`/`spctl`/`xattr` process in Activity Monitor during the sweep.

      **MV-9 (LIVE) — `/Applications` is never swept.** Place a distinctive non-brew `.app` in
      `/Applications`. Run the sweep. *Expect*: it does **not** appear anywhere in the panel. Then
      confirm brew-installed casks **do** appear — the positive anchor, or this check passes against
      an empty list.

      **MV-10 (FIXTURE-DRIVEN — temporary local patch, MUST be reverted, MUST NOT be committed) —
      The vulnerable and unavailable sections render.** Temporarily point the store's source at the
      Phase 2 fixtures so that at least one `covered(findings)`, one `covered(clean)`, one
      `notCovered` and one `unavailable` outcome exist simultaneously. *Expect*: four sections in the
      order Vulnerable → Not covered → Clean → Unavailable, four distinct counts, the unrated finding
      rendered in its own severity bucket, and the `1.2.3_1` finding reading "fix published,
      comparison not possible for this version scheme" with **no** ordering verdict. Screenshot as
      evidence. Then **revert the patch**, rebuild, confirm `git status` is clean. This check exists
      because this machine's real inventory cannot produce these states.

## Phase 18: Full gate, scope guard, and reconciliation

- [ ] 18.1 **Full gate.** (i) `swift test --package-path Packages/CellarCore` — green, count ≥ the 0.1
      baseline plus the new tests; (ii)
      `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      — BUILD SUCCEEDED, **zero** concurrency warnings; (iii) `xcodebuild test` — `cellarTests` and
      `cellarUITests` green; (iv) `swiftlint --quiet` — finding count equal to the 0.1 baseline (zero
      new); (v) file length — `wc -l` on every new file, each under SwiftLint's 400-line
      `file_length` warning. `SecurityStore.swift`, `SecurityScanEngine.swift`, `CVEMatcher.swift` and
      `SecurityView.swift` are the likeliest to breach — **split rather than suppress** (M3-1 split
      four files this way).
- [ ] 18.2 **Scope guard.** `rg '@unchecked Sendable|nonisolated\(unsafe\)'` over `Sources/SecurityKit/`
      and `cellar/Security/` must return **zero** (design "Concurrency"). `rg 'import BrewClient|import BrewProcess|import DiskUsage'`
      over `Sources/SecurityKit/` must return **zero**. `rg 'import SecurityKit' Packages/CellarCore/Sources/Persistence/`
      must return exactly **one** file (task 13.4). `git diff main...HEAD --name-only` must contain no
      taps, services or cleanup source file.
- [ ] 18.3 **Candidate size.** Record `git diff main...HEAD --shortstat` per slice and compare against
      the forecast band. If it lands outside 11,600–14,600 (or outside the per-slice bands), say so and
      say **why** — a forecast never checked against the outcome is how this project under-priced three
      slices in a row. Break the measurement into the same four buckets as the arithmetic table so the
      next forecast can use the deltas.
- [ ] 18.4 **Reconcile the open questions.** Write the U2 answer (vector-only ⇒ tier or `.unrated`) and
      the U3 answer (unprivileged `SecAssessmentTicketLookup`) into `design.md`'s Open Questions,
      checked, with the measured evidence. Register anything still open — notably the **v1.1 local
      advisory index** as the declared coverage fix, and the mapping table's growth path — with its
      reason, rather than deleting the question.
- [ ] 18.5 **Engram.** Save the apply outcome under `sdd/m4-security/apply` with the measured
      candidate size, the four MV-3 coverage counts, and the U2/U3 answers. **Commit 17.**

---

**Counts.** 108 tasks across 19 phases; **63 RED tasks**; 11 pre-written manual checks; 17 work-unit
commits; 3 probe gates (U1 re-capture + U2 + U5 at Phase 2, U3 at 14.0). Split boundaries after
Phase 8 / commit 8 and after Phase 16 / commit 16.
