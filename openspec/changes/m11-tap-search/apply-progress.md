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
| **WU4** | `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 265 test cases passing** (was 255); `xcodebuild build …` **`** BUILD SUCCEEDED **`** | **Deferred to delivery** — launching the app and typing a tap-published token in Browse is the one harness this run could not execute headlessly. Everything it would observe is pinned by a runner: the section title, its position, the row facts, the install menu and the receipt route are all asserted over the composed sources | Delete `TapSearchSection.swift` and `TapSearchCompositionTests.swift`, restore the flat `List(rows, selection:)`, drop one `ContentView` argument, revert the 4/2 line `PerPackageTrustCompositionTests` edit |

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
| 5.1–5.8 ps13–ps16 | `cellarTests/TapSearchCompositionTests.swift` | Unit-app | ✅ 255/255 | ✅ 7 of the 10 rows failed outright (the surface did not exist); the three that document **shipped** behaviour — `theSearchPromptStillCountsCatalogRecordsOnly`, `catalogRowSelectionIsUnchanged`, `theReceiptDetailIsReachedWithNoNewRoutingBranch` — were proven by **reversible mutation** of `BrowseView.swift` (prompt copy → `records…`, `themedListSelection(isSelected: false)`, `selection: Catalog.PackageID?`), all three failed, restored byte-identical (`sha256 e5d7449a…`) | ✅ | ✅ 10 rows | ✅ |
| 5.9 DD-11a | `cellarTests/PerPackageTrustCompositionTests.swift` | Unit-app | ✅ 2/2 | ✅ both shipped tests failed — `views()` threw on two paths that did not exist | ✅ | ➖ the shipped negative loop is the triangulation | ✅ |
| 5.10–5.12 | — (production) | — | ✅ | — | ✅ 265/265 | — | ✅ |

## Phase 6 — verification and bindings

| Task | Result |
|---|---|
| **6.1** core suite | `swift test --package-path Packages/CellarCore` → **1,864 tests / 217 suites passed, 1 known issue** (baseline 1,838 / 216; **+26**) |
| **6.2** app target, scoped | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`**, **265** passing (baseline 255; **+10**). The full `-scheme cellar` runner is **not** the gate: it is red on `main` from two pre-existing `cellarUITests` Taps failures (`:209`, `:231`). `cellarUITests` has a **zero-line diff** on this branch |
| **6.3** bindings proof | `git diff --stat main -- cellar.xcodeproj/project.pbxproj openspec/specs/ PackageSearchIndex.swift MutationCommand.swift TapCommand.swift TapProjection.swift PackageDetailView.swift scripts/ .github/workflows/` → **empty output**. The catalog index, the argv surface, the tap command surface, the tap projection, the detail pane, the project file and the promoted specs are all untouched |
| **6.4** regression guards | `TapProjectionTests`, `TapShippingProofTests`, `MutationCommandTests`, `MutationCommandTargetTests`, `SearchIndexTests`, `FilterTests`, `InstalledFilterCompositionTests`, `PackageGraphTests` → **107 tests / 9 suites passed**. `PerPackageTrustCompositionTests`, `ReceiptDetailCompositionTests`, `TapCompositionTests` → **`** TEST SUCCEEDED **`** |
| **6.5** spec self-check | Arithmetic confirmed against the main specs: `package-search` 7 req / 19 sc **+1 ADDED / 16 sc** → 8 / 35; `package-detail` 8 / 31, PD6's **3 shipped scenarios byte-identical**, +1 → 8 / 32; `tap-management` 13 / 58, TM5's **10** and TM11's **2** byte-identical, +1 each → 13 / 60. Byte-identity was machine-checked, not eyeballed. All **19** new scenarios have a task above naming them, ps4 included. Verification classes across the three deltas: **28 `unit` + 4 `unit-app`** — no new class (the two PD6 scenarios with no `- Verification:` line are shipped text reproduced byte-identically) |
| **6.6** branch total | `git diff --shortstat main` → **18 files, +4,330 / −14 = 4,344 authored lines**. Split: **code+test 1,935** (forecast 1,509–2,608 ✓ in band) and **artifacts 2,409** (task 0.4 fixed 2,322; `apply-progress.md` adds the rest). **Under the 5,000 governing budget.** `verify-report.md` will add ~250–450, landing the PR at roughly **4,600–4,800** — under the ceiling, with little headroom |
| **6.7** delivery | **Deferred by instruction.** This run was told not to push and not to open a PR. The body's five up-front statements are drafted below so delivery does not re-derive them |

### Drafted PR body — the five statements task 6.7 pins

**PR title**: `feat(browse): find and install packages published by your taps`

1. **The section adds no brew invocation and no store.** It composes the tap inventory already
   resident from the shipped TM1 refresh, and the combined keystroke turn — the catalog query and
   the tap composition together — measures **p95 2.500 ms** against PS6's 8 ms ceiling.
2. **It reads no trust state and presents no badge or control.** An untrusted tap surfaces through
   the shipped typed refusal and its Trust recovery, never through a pre-launch block (PM10).
   Asserted as an absence over both Browse sources, twice.
3. **Nothing enters the catalog.** No snapshot record, no index entry; the catalog is read for
   **membership alone**, to report that a hit's bare token collides.
4. **Ambiguous and not-installed rows are deliberately inert.** The catalog-first resolution would
   otherwise open a different package than the row chosen.
5. **The full `-scheme cellar` runner is red on `main`** for two pre-existing `cellarUITests` Taps
   failures (`:209`, `:231`), tracked separately. The scoped runners are the gate.

## Phase 7 — archive obligations, verified rather than assumed

- **7.1** confirmed: `openspec/specs/package-search/spec.md` and `openspec/specs/package-detail/spec.md`
  carry **no `<!-- PS# -->` / `<!-- PD# -->` markers**, so PS8 and PD6 are matched by heading;
  `tap-management`'s `<!-- TM5 -->` (`:118`) and `<!-- TM11 -->` (`:532`) are the blocks to replace.
  **No `## Verification classes` table exists in any of the three main specs** — only
  `app-updates/spec.md:9` and `release-distribution/spec.md:9` carry one — so none is promoted.
- **7.2** confirmed: the change carries **exactly three delta specs**. No `package-mutation`, no
  `installed-inventory`, no `package-trust` delta. `<!-- TM12 -->` (`:560`, the trust presentation)
  is untouched. The TM10→TM11 / TM11→TM12 marker drift is recorded at `specs/README.md:98-106`.
- **7.3** confirmed: the deferrals are recorded in `tasks.md` and unchanged by this apply.
- **7.4** **recorded with a correction — see deviation 6 below.**

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
5. **The DD-11a edit is 4 insertions / 2 deletions, not "exactly 3 lines".** Two of those are the
   two new paths; the other two are the sorted-name anchor and the trailing comma Swift array
   syntax forces onto the previous element. There is no smaller edit that adds two elements to that
   literal. Scope is unchanged.
6. **`tasks.md` task 7.4 asks for a PRD.md milestone that does not exist.** `PRD.md` §7 enumerates
   **M1–M6 only**; there is no M11, and neither `m9-per-package-trust` nor `m10-third-party-detail`
   recorded a milestone at archive (`rg -i milestone` over both archives returns nothing).
   `m11-tap-search` is a **post-M6 slice**, not a PRD milestone: its nearest PRD anchors are M1's
   "catalog sync + local search" and M3's "taps manager". Reported rather than absorbed —
   `sdd-archive` should record "no PRD milestone closed; post-M6 slice" instead of "M11".
   The second half of 7.4 stands as written: the two pre-existing `cellarUITests` Taps failures
   (`:209`, `:231`) remain open and are **not** m11's to close.
7. **Task 7.1's citation `openspec/specs/installed-inventory/spec.md:1122-1184` points at that
   spec's amendment-provenance log, not at a verification-class table.** The operative claim is
   nonetheless true and was checked directly: no `## Verification classes` table exists in
   `package-search`, `package-detail` or `tap-management`, so none promotes. Citation noise only.
8. **`MutationMenu.swift` lives at `cellar/Activity/MutationMenu.swift`**, not under
   `cellar/Browse/`. The design and tasks cite it by file name and line only, and lines `:32-40` are
   exactly where they say. Not a moved anchor.
9. **The section renders only when it has hits.** `isSectionVisible` gates `tapHits`, and the view
   composes `TapSearchSection` only for a non-empty result. A visible-but-empty header would
   announce a section that cannot fill — the reading `InstalledListView.swift:111-113` already
   rejects for the catalog's own sections. The spec's absence rules are unchanged and unrelaxed.

## Task ledger

**58 of 59 complete.** The one open task is **6.7 (open the PR)**, deferred by this run's explicit
instruction not to push and not to open a pull request. Its content is drafted above.
