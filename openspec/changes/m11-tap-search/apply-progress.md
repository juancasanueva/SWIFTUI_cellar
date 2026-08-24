# Apply progress: `m11-tap-search`

Mode: **Strict TDD** (`openspec/config.yaml` `testing.strict_tdd: true`). Store: **hybrid**
(this file is canonical; Engram topic `sdd/m11-tap-search/apply-progress` mirrors it).
Delivery: **single-pr**, chain `pending`, no `size:exception` in use.
Branch: `feat/m11-tap-search` from `main` @ `edda9a5`.

## Phase 0 — baselines and preflight (tasks 0.1–0.4)

| Runner | Baseline on `main` |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,838 tests / 216 suites, passed, 1 known issue** |
| `xcodebuild test … -only-testing:cellarTests` | **255 test cases passed, `** TEST SUCCEEDED **`** |

- **0.2 anchors**: every anchor the design pins is present. `TapProjection.swift` `:25`
  (`TapPackageInstallState`), `:32` (`TapPackage`, `publishedName` `:34` / `displayName` `:35`),
  `:52` (`statusExplanation`, `nil` for `.installed`), `:93` (`thirdPartyTaps`, official exclusion
  via `officialNames` `:82`), `:134` (`packages(for:installed:)`), `:208` (`bareToken`);
  `PackageText.swift` `:16` (`normalize`); `BrowseView.swift` `:47` (prompt), `:59`
  (`List(rows, selection:)`), `:75` (`rows.isEmpty` overlay), `:126` (`private struct EmptyResults`);
  `ContentView.swift` `:307` (`BrowseView(`); `MutationMenu.swift` `:32`/`:35`/`:38`;
  `InstalledFilterMode.swift` `:54`, `:62`, `:104`; `PerPackageTrustCompositionTests.swift` `:31`,
  `:186`. **No anchor moved.**
  One path note, not a move: `MutationMenu.swift` lives at `cellar/Activity/MutationMenu.swift`,
  not under `cellar/Browse/`.
- **0.4 forecast band, collapsed**: `git log --oneline -- openspec/changes/m11-tap-search` is
  **empty** and the folder was **untracked**, so the artifacts are **new to this branch**. The
  artifact bucket measures **2,322 lines** (not the forecast's 1,872 + ~300): `explore.md` 572,
  `tasks.md` 451, `specs/package-search` 328, `specs/tap-management` 270, `design.md` 307,
  `proposal.md` 154, `specs/README.md` 120, `specs/package-detail` 121. This is the corner the
  forecast named; it is recorded here and re-measured at task 6.6, never re-estimated.

## Work unit evidence

| Unit | Focused command | Exact result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU1** | N/A — artifacts only | `9fe6013`, 8 files, +2,322 | N/A — no behaviour changes | `git revert 9fe6013`; the tree returns to `main` |
| **WU2** | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | **24 tests / 1 suite passed**; full core suite **1,862 / 217 passed, 1 known issue** (was 1,838) | N/A — a pure projection over two resident inventories; there is no launcher to inject, and that absence is itself asserted | Delete `TapPackageSearch.swift`, `TapPackageSearchTests.swift`, `Fakes/TapSearchFixture.swift`; nothing else references them |
| **WU3** | `swift test -c release --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | **26 tests / 1 suite passed**; combined-turn **p95 2.500 ms** (median 2.340 ms, max 2.776 ms) against the 8 ms ceiling | N/A — the measurement **is** the harness | Delete the two latency rows and `Fakes/TapSearchLatencyFixture.swift`; no production line is theirs |

## TDD cycle evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 2.1 | `Fakes/TapSearchFixture.swift` | — (support) | N/A (new) | ➖ not a behaviour | ➖ | ➖ | ➖ |
| 2.2 ps1 | `TapPackageSearchTests.swift` | Unit | ✅ 1,838/1,838 | ✅ `cannot find 'TapPackageSearch' in scope` | ✅ | ✅ 3 rows (found · index convergence · official excluded) | ✅ |
| 2.3 ps2 | same | Unit | ✅ | ✅ same | ✅ | ✅ 2 rows, 3 distinct ranks + the published-name cap | ✅ |
| 2.4 ps3 | same | Unit | ✅ | ✅ same | ✅ | ✅ composed twice + shuffled input | ✅ |
| 2.5 ps4 | same | Unit | ✅ | ✅ `cannot find 'TapSearchHit' in scope` | ✅ | ✅ `Mirror` enumeration + 12-name absence set + placeholder scan | ✅ |
| 2.6 ps5 | same | Unit | ✅ | ✅ same | ✅ | ✅ cask-only **and** formula-only + `SearchFilters` member set | ✅ |
| 2.7 ps6 | same | Unit | ✅ | ✅ same | ✅ | ✅ `""`, `"   "`, `"\t\n"` + a real query over the same 40 packages | ✅ |
| 2.8 ps7 | same | Unit | ✅ | ✅ same | ✅ | ✅ `.brewAbsent` **and** `.failed` vs the three visible states | ✅ |
| 2.9 ps8 | same | Unit | ✅ | ✅ same | ✅ | ✅ 3 rows; collision vs no-collision on one fixture | ✅ |
| 2.10 ps9 | same | Unit | ✅ | ✅ same | ✅ | ✅ three states, three distinct copies, none empty | ✅ |
| 2.11 ps10 | same | Unit | ✅ | ✅ same | ✅ | ✅ 4 rows: catalog cause, duplicate cause, routable, not-installed | ✅ |
| 2.12 ps11 | same | Unit | ✅ | ✅ same | ✅ | ✅ hide-installed **and** outdated-only, with hits proven unchanged | ✅ |
| 2.13 ps16 (unit half) | same | Unit | ✅ | ✅ same | ✅ | ✅ 10 identifiers + 5 substrings + the positive signature anchors | ✅ |
| 2.14 PD6 sc4 | same | Unit | ✅ | ✅ same | ✅ | ✅ search, lookup, record count and snapshot membership | ✅ |
| 2.15 TM5 sc11 | same | Unit | ✅ | ✅ same | ✅ | ➖ single claim (zero launches) | ✅ |
| 2.16 TM11 sc3 | same | Unit | ✅ | ✅ same | ✅ | ✅ 5 verbs, each anchored in `TapCommand.swift` then denied here | ✅ |
| 4.2 ps12 | same | Unit | ✅ 1,862/1,862 | ✅ **reversible mutation** — a 400× re-normalisation per package in `hits(_:)` drove p95 to **80.1 ms**; restored byte-identical (`sha256 1e5b6a2a…`, empty `git diff --stat`) | ✅ p95 **2.500 ms** | ✅ paired with the fixture-shape row | ✅ |

## Deviations recorded so far

1. **The PS6 catalog fixture is reproduced, not imported** (task 4.1 says "reused as-is"). One
   SwiftPM test target cannot import another, and `LatencyFixture` lives in `CatalogTests`; moving
   it into `CellarTestSupport` would give that deliberately dependency-free target an edge on
   `Catalog` (`Package.swift:19-27`). The generator, its seed and its shape rules are reproduced
   verbatim in `Fakes/TapSearchLatencyFixture.swift`, and
   `theCatalogFixtureIsTheOnePS6MeasuresOver` re-asserts the shipped size and shape invariants
   (15,500 records, mean name 8–13, mean description 30–42, an empty description present, both
   kinds) so the copy is proven rather than trusted.
2. **The latency row is gated on a release build**, exactly as the shipped PS6 row is
   (`SearchLatencyTests.swift:35`): a `-Onone` byte scan is 5–20× slower, so a debug measurement
   would assert against a number nobody experiences. The ceiling itself is untouched.
3. **`ps1`'s "exact, then prefix, then substring" is the ladder's ordering rule, not a per-fixture
   class label.** Under the requirement's own token-aware definition, `widget-cli` matches query
   `widget` as a **whole token** and is therefore `exactToken`, not `namePrefix`. The scenario's
   stated **order** — `widget`, `widget-cli`, `superwidget` — is delivered exactly, and
   `theLadderConvergesWithTheCatalogIndexOnOneFixture` pins the classification against
   `PackageSearchIndex`, which classifies the same three names identically. No spec text is
   contradicted: the requirement says exact means "the whole normalised string **or** a whole
   normalised token of it".
4. **`TapSearchHit.hash(into:)` is hand-written.** `TapPackageInstallState` is `Equatable` and not
   `Hashable`, and making it `Hashable` would put a diff in `TapProjection.swift`, which task 6.3
   requires to be empty. Hashing on `RowID` alone is faithful — it is unique among the hits one
   composition emits — and `==` still synthesises over every member.
