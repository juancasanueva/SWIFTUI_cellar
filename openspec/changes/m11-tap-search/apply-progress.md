# Apply progress: `m11-tap-search`

Mode: **Strict TDD** (`openspec/config.yaml` `testing.strict_tdd: true`). Store: **hybrid**
(this file is canonical; Engram topic `sdd/m11-tap-search/apply-progress` mirrors it).
Branch: `feat/m11-tap-search` from `main` @ `edda9a5`.

**Two rounds.** Round 1 landed at `dbc5233` and is kept below as history. Round 2 — the 2026-08-25
maintainer scope change — is the governing record and starts at
[Round 2 — scope change](#round-2--scope-change-2026-08-25). Delivery for round 2 is **single-pr with
`size:exception` accepted by the maintainer (2026-08-25)**; round 1's "no `size:exception` in use" is
superseded.

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
  artifact bucket measures **2,322 lines**. This is the corner the forecast named.

## Work unit evidence — round 1

| Unit | Focused command | Exact result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU1** | N/A — artifacts only | `9fe6013`, 8 files, +2,322 | N/A — no behaviour changes | `git revert 9fe6013`; the tree returns to `main` |
| **WU2** | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | **24 tests / 1 suite passed**; full core suite **1,862 / 217 passed, 1 known issue** (was 1,838) | N/A — a pure projection over two resident inventories; there is no launcher to inject, and that absence is itself asserted | Delete `TapPackageSearch.swift`, `TapPackageSearchTests.swift`, `Fakes/TapSearchFixture.swift` |
| **WU3** | `swift test -c release --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | **26 tests / 1 suite passed**; combined-turn **p95 2.500 ms** (median 2.340 ms, max 2.776 ms) against the 8 ms ceiling | N/A — the measurement **is** the harness | Delete the two latency rows and `Fakes/TapSearchLatencyFixture.swift` |
| **WU4** | `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 265 test cases passing** (was 255); `xcodebuild build …` **`** BUILD SUCCEEDED **`** | **Deferred to delivery** — launching the app was the one harness that run could not execute headlessly | Delete `TapSearchSection.swift` and `TapSearchCompositionTests.swift`, restore the flat `List(rows, selection:)`, drop one `ContentView` argument, revert the `PerPackageTrustCompositionTests` edit |

## TDD cycle evidence — round 1

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 2.1 | `Fakes/TapSearchFixture.swift` | — (support) | N/A (new) | ➖ not a behaviour | ➖ | ➖ | ➖ |
| 2.2 ps1 | `TapPackageSearchTests.swift` | Unit | ✅ 1,838/1,838 | ✅ `cannot find 'TapPackageSearch' in scope` | ✅ | ✅ 3 rows | ✅ |
| 2.3 ps2 | same | Unit | ✅ | ✅ same | ✅ | ✅ 2 rows, 3 distinct ranks + the published-name cap | ✅ |
| 2.4 ps3 | same | Unit | ✅ | ✅ same | ✅ | ✅ composed twice + shuffled input | ✅ |
| 2.5 ps4 | same | Unit | ✅ | ✅ `cannot find 'TapSearchHit' in scope` | ✅ | ✅ `Mirror` enumeration + 12-name absence set | ✅ |
| 2.6 ps5 | same | Unit | ✅ | ✅ same | ✅ | ✅ cask-only **and** formula-only | ✅ |
| 2.7 ps6 | same | Unit | ✅ | ✅ same | ✅ | ✅ `""`, `"   "`, `"\t\n"` | ✅ |
| 2.8 ps7 | same | Unit | ✅ | ✅ same | ✅ | ✅ `.brewAbsent` **and** `.failed` | ✅ |
| 2.9 ps8 | same | Unit | ✅ | ✅ same | ✅ | ✅ 3 rows | ✅ |
| 2.10 ps9 | same | Unit | ✅ | ✅ same | ✅ | ✅ three states, three distinct copies | ✅ |
| 2.11 ps10 | same | Unit | ✅ | ✅ same | ✅ | ✅ 4 rows | ✅ |
| 2.12 ps11 | same | Unit | ✅ | ✅ same | ✅ | ✅ hide-installed **and** outdated-only | ✅ |
| 2.13 ps16 (unit half) | same | Unit | ✅ | ✅ same | ✅ | ✅ 10 identifiers + 5 substrings | ✅ |
| 2.14 PD6 sc4 | same | Unit | ✅ | ✅ same | ✅ | ✅ search, lookup, record count, snapshot | ✅ |
| 2.15 TM5 sc11 | same | Unit | ✅ | ✅ same | ✅ | ➖ single claim (zero launches) | ✅ |
| 2.16 TM11 sc3 | same | Unit | ✅ | ✅ same | ✅ | ✅ 5 verbs | ✅ |
| 4.2 ps12 | same | Unit | ✅ 1,862/1,862 | ✅ **reversible mutation** — 400× re-normalisation drove p95 to **80.1 ms**; restored byte-identical | ✅ p95 **2.500 ms** | ✅ | ✅ |
| 5.1–5.8 ps13–ps16 | `cellarTests/TapSearchCompositionTests.swift` | Unit-app | ✅ 255/255 | ✅ 7 of 10 rows failed outright; 3 proven by reversible mutation of `BrowseView.swift`, restored byte-identical | ✅ | ✅ 10 rows | ✅ |
| 5.9 DD-11a | `cellarTests/PerPackageTrustCompositionTests.swift` | Unit-app | ✅ 2/2 | ✅ both shipped tests failed — `views()` threw on two missing paths | ✅ | ➖ | ✅ |

## Phase 6 — verification and bindings (round 1, at `dbc5233`)

`swift test` **1,864 / 217 passed, 1 known issue** (+26); `xcodebuild … -only-testing:cellarTests`
**265 passing** (+10); bindings proof empty; branch total **4,344 authored**. Superseded by Phase 6′.

## Phase 7 — archive obligations (round 1)

Superseded wholesale by Phase 7′. Task 7.4's "M11" claim is **wrong** and is corrected at 7′.4.

---

# Round 2 — scope change (2026-08-25)

Tap results left Browse entirely and took their own sidebar surface, `Search our taps`.
This section describes the delta from `dbc5233`.

## Phase 0′ — preflight

- **0′.1 branch re-measured at `dbc5233`** (working tree carried the amended artifacts):
  **18 files, +5,032 / −14**. Split: **code+test 1,935** (1,921 + 14) and **artifacts 3,111**.
- **0′.2 anchors**: every round-2 anchor is where the design says. `TapPackageSearch.swift` `:125`
  (`guard needle.isEmpty == false else { return [] }`), `:120-125` (`hits(…)`), `:183`
  (`isSectionVisible`) · `TapProjection.swift` `:188-196` (`state(loadState:inventory:)`, cases
  `.idle/.loading(hasLastGood:)/.content(isThirdPartyEmpty:)/.unavailable/.error(_,hasLastGood:)`) ·
  `TapProjectionTests.swift` `:130` (`presentationStatesRemainDistinct`, `hasLastGood` included) ·
  `PackageSearchIndex.swift` `:218-227` (`defaultOrder`, the empty-query precedent) ·
  `AppSection.swift` `:28` (`case browse`), `:104-130` (`title`), `:134-139` (`sidebarTitle`, **with**
  its `default:` arm), `:141-167` (`systemImage`), `:173-180` (`sidebarGroups`), `:148-150` (the
  recorded missing-symbol precedent) · `ContentView.swift` `:68`, `:95-99`, `:153-159`, `:196-198`
  (`countLabel`, inline in the `ShellTitleBar` call rather than a named member — see deviation 5),
  `:303-315`, `:530-546`, `:594-599`, `:603-606`, `:624-636` · `SidebarView.swift` `:175-205` ·
  `CatalogFilterBar.swift` `:10-16`, `:77-95` · `AppSectionPlacementTests.swift` `:34`, `:52-60`,
  `:150-156`, `:195-200` · `TapSearchCompositionTests.swift` `:287-291` ·
  `PerPackageTrustCompositionTests.swift` `:31-32`, `:186-201`. **No anchor moved.**
- **0′.3 SF Symbol**: `sparkle.magnifyingglass`, forwarded by the orchestrator from Engram topic
  `sdd/m11-tap-search/state` and **re-verified against this SDK** by this run —
  `NSImage(systemSymbolName:accessibilityDescription:)` returns non-`nil` for it, and `nil` for the
  control `clock.badge.plus` (the name `AppSection.swift:148-150` already records as absent), so the
  check is real rather than vacuous. The check is now a permanent assertion in
  `theTapSearchSurfaceIsWiredAtEveryAppSectionSite`.
- **0′.4 green baseline on the branch at `dbc5233`**:

| Runner | Baseline at `dbc5233` |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,864 tests / 217 suites passed, 1 known issue** |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 267 passing test-case results / 256 distinct ids** |

  One flake observed and not absorbed: the first core run reported 2 issues, the second reported
  the baseline 1. The extra was `OperationCenterCancelTests.swift:183` ("no process was launched for
  call 0 within 0.05 seconds"), a **shipped, timing-sensitive** row already wrapped in a known-issue
  guard. It is not m11's and did not recur.

## Phase 1′ — WU5, the amended artifacts

- **1′.1** committed first, before any Swift change: `3335347`, 7 files, **+1,077 / −449**.
- **1′.2 delta arithmetic, re-counted against r3**: `package-search` 7 req / 19 sc **+1 ADDED / 17 sc**
  → **8 / 36**; `package-detail` 8 / 31, **1 MODIFIED, 4 replacing 3** → **8 / 32**;
  `tap-management` 13 / 58, **2 MODIFIED, 11 replacing 10 and 3 replacing 2** → **13 / 60**.
  **20 new scenarios.** The r3 prose amendments moved nothing the round-1 tests assert: PD6's,
  TM5's and TM11's suites are green with **no edit** (6′.4).
- **1′.3 recorded**: `design.md` does **not** quote the two empty-state strings. The spec is
  authoritative for them (`specs/package-search/spec.md:236-237`, `specs/README.md:53-54`), and this
  run reproduced those bytes rather than paraphrasing the design.

## Work unit evidence — round 2

| Unit | Commit | Focused command and exact result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU5** | `3335347` | N/A — artifacts only; 7 files, +1,077 / −449 | N/A — no behaviour changes | `git revert 3335347`; the branch returns to `dbc5233` |
| **WU6** | `656e2d5` | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` → **31 tests / 1 suite passed**; `TapProjectionTests\|SearchIndexTests\|FilterTests\|TapShippingProofTests` → **62 tests / 5 suites passed** | N/A — a pure projection over resident values; there is no runtime to exercise | Revert one commit in `TapPackageSearch.swift` + its test file and fixture. **Not independently revertible from WU7** — see deviation 1 |
| **WU7** | `70f7148` | `xcodebuild build …` → **`** BUILD SUCCEEDED **`**; the test target's remaining failures are exactly the round-1 rows WU8 replaces | **Deferred to delivery** — launching the app and typing in the new surface is the one harness this run could not execute headlessly. Everything it would observe is pinned by a runner: the sidebar entry, its group and position, the empty-query listing, the row facts, the install menu and the receipt route are all asserted over the composed sources | `git checkout dbc5233 -- cellar/` restores the round-1 surface wholesale |
| **WU8** | `d13fd75` | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`, 267 passing / 257 distinct** | N/A — source-scan suite; the app harness is WU7's | Revert one test commit; no production line is its own |
| **WU9** | `b99ffe3` | `swift test -c release --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` → **32 tests / 1 suite passed**; tap turn **p95 1.501 ms** (median 1.344, max 1.856), catalog re-run **p95 1.068 ms** (median 0.987, max 1.096), both against 8 ms | N/A — the measurement **is** the harness | Revert the two latency rows; the ≈500-package fixture is shared with round 1 |

## TDD cycle evidence — round 2

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 2′.1 ps6 | `TapPackageSearchTests.swift` | Unit | ✅ 1,864/1,864 | ✅ **genuine** — `(found.map(\.displayName) → []) == [40 names]`, because `:125` still returned `[]` | ✅ | ✅ `""`, `"   "`, `"\t\n"`, official-tap exclusion, kind filter (15), hide-installed (39), and a 6-of-40 real query | ✅ |
| 2′.2 ps6 | same | Unit | ✅ | ✅ **genuine** — `(listed.count → 0) == 4` | ✅ | ✅ listing vs a query that classes all four alike, ranks asserted equal so the match is not a rank artefact | ✅ |
| 2′.5 ps11 | same | Unit | ✅ | ✅ **genuine** — `contains("outdatedOnly") → true` and `contains("isSectionVisible") → true` | ✅ | ✅ parameter labels enumerated off the declaration, plus two absences | ✅ |
| 2′.3 ps7 | same | Unit | ✅ | ✅ **compile failure** — `cannot find type 'TapSearchPresentation' in scope`, `type 'TapPackageSearch' has no member 'presentation'` | ✅ | ✅ five states pairwise-distinct, plus official-only and publishes-nothing inventories | ✅ |
| 2′.4 ps7 | same | Unit | ✅ | ✅ same compile failure | ✅ | ✅ `.loading` and `.failed` × last-good present/absent, anchored on `TapProjection.state(…)` itself | ✅ |
| 2′.6 ps7 | same | Unit | ✅ | ✅ same compile failure | ✅ | ✅ two pinned sentences asserted distinct, three states asserted to pin none | ✅ |
| 2′.7 DD-17 | same | Unit | ✅ | ✅ same compile failure | ✅ | ✅ equals the empty-query hit count, official taps excluded, 0 and 3 at the ends | ✅ |
| 2′.8 | same | — (deletion) | ✅ | ➖ `theOutdatedChipHidesTheSection` deleted, not left green | ➖ | ➖ | ✅ |
| 4′.2 ps17 | `TapSearchCompositionTests.swift` | Unit-app | ✅ 267/267 | ✅ **reversible mutation** — `let tapHits = 0` in `BrowseView.rows` | ✅ | ✅ 7 forbidden identifiers + 4 positive anchors + the call-site check | ✅ |
| 4′.3 ps17 | same | Unit-app | ✅ | ✅ **reversible mutation** — `git checkout HEAD~1 -- cellar/Browse/TapSearchSection.swift` | ✅ | ✅ tree walk over 3 roots, both `TapSearchSection` and `From your taps` | ✅ |
| 4′.4 ps13 | same | Unit-app | ✅ | ✅ **reversible mutation** — `sidebarTitle` → `"Search taps"`, `systemImage` → `"magnifyingglass"` | ✅ | ✅ rawValue, order, both titles **separately**, symbol identity **and** SDK existence, group literal, three `Set` literals, width, count label | ✅ |
| 4′.5 ps13 | `AppSectionPlacementTests.swift`, `BrewfileCompositionTests.swift` | Unit-app | ✅ 267/267 | ✅ **genuine** — both suites failed at WU7 on `order.count == 21` and the rawValue anchor | ✅ | ✅ Overview group literal added; sidebar coverage and the 3-switch count untouched | ✅ |
| 4′.6 ps13/ps14 | `TapSearchCompositionTests.swift` | Unit-app | ✅ | ✅ **reversible mutation** — prompt switched to `catalog.packageCount`; `TapInventory` member added to `PackageDetailView` | ✅ | ✅ six shared components anchored on Browse and on `PackageRow`; the shared detail arm asserted by its exact case list | ✅ |
| 4′.7 ps11 | same | Unit-app | ✅ | ✅ **reversible mutation** — `showsOutdatedChip: true` | ✅ | ✅ three literals absent, both defaults present, Browse's call site asserted argument-free **and** still calling | ✅ |
| 4′.8 ps14–ps16 | same | Unit-app | ✅ | ✅ **genuine** for the copy row (retargeted scan failed at WU7); **reversible mutation** for the rest — `private let launcher = 0` / `private let trustGrants = 0` | ✅ | ✅ six pinned strings, eight trust identifiers plus a whole-file `trust` sweep, eleven process identifiers | ✅ |
| 4′.9 | same | — (deletions) | ✅ | ➖ five round-1 rows deleted after failing at WU7, not left green | ➖ | ➖ | ✅ |
| 5′.1 ps12 | `TapPackageSearchTests.swift` | Unit | ✅ 1,870/1,870 | ✅ **reversible mutation** — 400× re-normalisation per package drove tap p95 to **67.8 ms** | ✅ p95 **1.501 ms** | ✅ paired with the max assertion so the empty query cannot slip past a p95 | ✅ |
| 5′.2 ps12 | same | Unit | ✅ | ✅ **reversible mutation** — 60 forced `defaultOrder` sorts inside `PackageSearchIndex.search` drove catalog p95 to **71.5 ms** | ✅ p95 **1.068 ms** | ✅ fixture size and shape re-asserted by the shipped row | ✅ |

**Every mutation was restored byte-identically and verified**: `shasum -a 256 -c` reported `OK` for
`BrowseView.swift`, `AppSection.swift`, `TapSearchView.swift`, `PackageDetailView.swift`,
`TapPackageSearch.swift` and `PackageSearchIndex.swift`, and `git status --porcelain cellar/` and
`git diff main -- …PackageSearchIndex.swift` both printed nothing.

## Phase 6′ — verification and bindings

| Task | Result |
|---|---|
| **6′.1** core suite | `swift test --package-path Packages/CellarCore` → **1,870 tests / 217 suites passed, 1 known issue** (baseline 1,864; **+6** = 8 added − 2 deleted) |
| **6′.2** app target, scoped | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`**, **267** passing results / **257** distinct ids (baseline 267 / 256; **+1** = 6 added − 5 deleted). The full `-scheme cellar` runner is **not** the gate: it is red on `main` from two pre-existing `cellarUITests` Taps failures (`:209`, `:231`). `cellarUITests` has a **zero-line diff** on this branch, verified |
| **6′.3** bindings proof | `git diff --stat main -- cellar/Browse/BrowseView.swift cellar.xcodeproj/project.pbxproj openspec/specs/ PackageSearchIndex.swift MutationCommand.swift TapCommand.swift TapProjection.swift PackageDetailView.swift scripts/ .github/workflows/` → **empty output**. `BrowseView.swift` is byte-identical to `main`, and so are the index, the argv surface, the tap command surface, the tap projection, the detail pane, the project file and the promoted specs |
| **6′.4** regression guards | `TapProjectionTests`, `TapShippingProofTests`, `MutationCommandTests`, `MutationCommandTargetTests`, `SearchIndexTests`, `FilterTests`, `InstalledFilterCompositionTests`, `PackageGraphTests` → **107 tests / 9 suites passed**. `PerPackageTrustCompositionTests` (2/2), `AppSectionPlacementTests` (7/7) and `ReceiptDetailCompositionTests` (5/5) all pass with **only** their listed edits |
| **6′.5** spec self-check | Arithmetic as 1′.2. Byte-identity **machine-checked**, not eyeballed: PD6's **3**, TM5's **10** and TM11's **2** shipped scenarios are byte-identical to `openspec/specs/**`. The three apparent mismatches the first pass reported were regex artefacts only — a trailing blank line and the *following* requirement's `<!-- TM6 -->` / `<!-- TM12 -->` marker swept into the preceding block; the scenario text itself matches. All **20** new scenarios have a task naming them, including **ps11's `unit` half** (task 2′.5). Verification classes across the three deltas: **28 `unit` + 5 `unit-app`** — no new class |
| **6′.6** branch total | `git diff --shortstat main` → **22 files, +5,728 / −26 = 5,754 authored lines**. Split: **code+test 2,643** (forecast ~2,057–2,107 — **over by ~536**, see deviation 8) and **artifacts 3,111** before this file's rewrite (forecast 3,361–3,561, which included `verify-report.md`). Measured against the maintainer's accepted **4,900–5,200** and this forecast's **5,418–5,668**: the branch is **above both**, and the excess is reported rather than trimmed, under the accepted **`size:exception`** |
| **6′.7** delivery | **Deferred by instruction.** This run was told not to push and not to open a pull request. The body's six statements are drafted below so delivery does not re-derive them |

### Drafted PR body — the six statements task 6′.7 pins

**PR title**: `feat(taps): search and install packages published by your taps`

1. **Browse is byte-identical to `main`.** The catalog surface is out of scope, asserted twice — by
   `git diff --stat main -- cellar/Browse/BrowseView.swift` (empty) and by
   `browseIsUntouchedByThisChange`, which is what protects the property after the merge.
2. **The surface adds no brew invocation and no store.** It composes the tap inventory already
   resident from the shipped TM1 refresh, and each surface holds **its own** 8 ms turn:
   tap **p95 1.501 ms** (worst case included — an empty query lists every package), catalog re-run
   **p95 1.068 ms**.
3. **It reads no trust state and presents no badge or control.** An untrusted tap surfaces through
   the shipped typed refusal and its Trust recovery, never a pre-launch block (PM10). Asserted as an
   absence over both the projection and the view, plus a whole-file `trust` sweep.
4. **Nothing enters the catalog.** No snapshot record, no index entry; the catalog is read for
   **membership alone**, to report that a hit's bare token collides.
5. **Ambiguous and not-installed rows are deliberately inert.** The catalog-first resolution would
   otherwise open a different package than the row chosen.
6. **The PR is over the 5,000-line budget on artifact lines**, under a `size:exception` the
   maintainer accepted on 2026-08-25; and the full `-scheme cellar` runner is red on `main` for two
   pre-existing `cellarUITests` Taps failures (`:209`, `:231`), so the scoped runners are the gate.

## Phase 7′ — archive obligations (round 2), verified rather than assumed

- **7′.1** confirmed: `openspec/specs/package-search/spec.md` and `openspec/specs/package-detail/spec.md`
  carry **no `<!-- PS# -->` / `<!-- PD# -->` markers**, so PS8 (**17** scenarios → 8 req / **36** sc)
  and PD6 are matched by heading; `tap-management`'s `<!-- TM5 -->` and `<!-- TM11 -->` are the blocks
  to replace (→ 13 req / 60 sc). **No `## Verification classes` table exists in any of the three main
  specs**, so none promotes; only the inline `- Verification:` lines do.
- **7′.2** confirmed: exactly three delta specs. **No `package-mutation` delta** (PM10 activated; its
  argv enumeration gains no family), **no `installed-inventory` delta** (II7/II8/II15 activated),
  **no `package-trust` delta**. `<!-- TM12 -->` is untouched. The **TM10→TM11 / TM11→TM12 marker
  drift** is recorded again: `explore.md` still carries the pre-promotion ordinals.
- **7′.3** recorded, so no future reader resurrects them from the round-1 history: the string
  **`From your taps` is WITHDRAWN** and now appears nowhere in `cellar/`, `cellarTests/` or
  `Packages/CellarCore/Sources` — asserted by a tree walk, not by a list. The **void** rev-2
  decisions are: the section's placement inside Browse, the Outdated chip hiding a section, and
  `isSectionVisible` (deleted).
- **7′.4** **PRD milestone: none closed.** `PRD.md` §7 ends at **M6**; the m7–m11 labels are session
  shorthand. Round 1's task 7.4 claimed "M11" and is wrong. The two pre-existing `cellarUITests` Taps
  failures (`:209`, `:231`) remain open and are **not** m11's to close.
- **7′.5** deferrals recorded: a **name-only detail pane** for a not-installed hit stays blocked by
  TM5's tap-source-read ban; the **merged ranked list** stays rejected; **index ingestion** is
  forbidden by PD6's text; `SearchFilters` gains **no** member; and the tap surface knowingly holds a
  `SearchFilters` whose two exclusion predicates are dead — DD-15's accepted cost.

## Deviations — round 2 (reported, not absorbed)

1. **The `sidebarTitle` `default:` arm had to go, and that is the shipped guard working.**
   `AppSectionPlacementTests`'s detector treats any switch with **two or more** `AppSection` case
   labels as one of the shell's section switches, and requires it to cover `.health` with **no
   `default:`**. `sidebarTitle` escaped that only because it had **one** case. Adding
   `case .tapSearch` brings it into scope, so it is now **exhaustive** — one grouped arm led by
   `.health` (the same idiom `ContentView.shellTitleBarAccessories` already uses for the same
   scanner). DD-14 site 2 called this site "test only"; it is now **compiler-forced**, which is
   strictly stronger and removes the silent-fallback trap the design warned about.
2. **`countLabel` is an `if`-chain, not a `switch`, for the same reason.** A two-label
   `switch section` would be detected as a fourth shell section switch and would break
   `everyAppSectionSwitchCoversHealthWithoutADefault`'s `count == 3`. Recorded in the code.
3. **A tenth `AppSection` wiring site exists that DD-14 and task 4′.5 both missed.**
   `cellarTests/BrewfileCompositionTests.swift:617-630` carries a **second** full rawValue anchor and
   a `count == 21`. It failed at WU7 and was amended, not weakened, exactly like the placement
   suite's. The design's nine-site table is short by one **test** anchor.
4. **`TapSearchView` takes `@Binding var selection: PackageID?`, not a local `@State`.** Tasks 3′.9
   and 4′.6 ask for "`@State private var selection: PackageID?` of its own", but the *same* tasks
   (3′.5) and ps14 require `ContentView`'s **shared** `PackageDetailView` arm to resolve `.tapSearch`
   — and that arm reads the shell's `selection`. A locally-owned `@State` would leave the detail pane
   permanently empty and make ps14 false. The binding is what makes the receipt-backed detail
   reachable with **no new routing branch**, which is the property both DD-4 and ps14 actually
   protect. `theTapSurfaceResolvesThroughTheSharedDetail` pins it.
5. **`ContentView.countLabel` did not exist as a named member.** The design cites `:204-206`; the
   shipped code had the expression **inline** in the `ShellTitleBar(` call. It was extracted to a
   named `countLabel` so the tap surface's own count has somewhere to live. Not a moved anchor — the
   expression was exactly where the design said, just unnamed.
6. **`Search our taps` appears in `AppSection.swift` only, not also in the view.** Task 4′.8 asks for
   it in both. The shell renders the pinned bar's title from `section.sidebarTitle` for every member
   of `shellTitleBarSections`, so the sidebar entry and the surface title are **one string in one
   place** — putting a second literal in the view is precisely what PS8's copy-ownership clause
   forbids. `theSurfaceTitleIsTheSidebarEntry` asserts the mechanism instead, and asserts the view
   carries no such literal.
7. **`theGrantCopyGuardCoversTheNewSurface` (task 4′.8) is not a test that exists.** The guard it
   names is the shipped `PerPackageTrustCompositionTests.rowHeaderAndRowsReadOneProjection`'s
   `for source in sources` loop, which the `PerPackageTrustSources.views()` retarget (4′.1) now points
   at `TapSearchView.swift`. Both shipped tests pass with only that edit.
8. **The code+test bucket is ~536 lines over its forecast (2,643 vs ~2,057–2,107).** The round-2
   forecast derived it from round 1's 1,907 plus a +150–200 net delta; the measured round-1 base was
   **1,935**, and the round-2 net came to **+708**. The excess is test code: the composition suite
   grew from 376 to 524 lines (the AppSection wiring row, the zero-diff row, the tree walk) and the
   projection suite from 719 to 1,012 (five presentation rows plus the split latency rows). No
   production file exceeded its estimate. Information for the next forecast, not a re-plan.
9. **The WU6 commit leaves the app target non-compiling until WU7.** WU6 deletes `isSectionVisible`
   and WU7 removes its only caller (`BrowseView.swift:139`), so WU6's stated rollback boundary — "no
   app file depends on it yet" — is false for round 2. The tasks' own rollback order
   (WU9 → WU8 → WU7 → WU6 → WU5) already requires reverse-order rollback, so nothing is unsafe; the
   boundary text is what is wrong. `swift test` for `CellarCore` is green at WU6.
10. **`theCatalogKeystrokeTurnIsUnchanged` re-runs PS6's method over the reproduced fixture, not over
    `LatencyFixture` itself.** One SwiftPM test target cannot import another (round-1 deviation 1
    stands unchanged), so the row uses `TapSearchLatencyFixture.catalogSnapshot()`, whose size and
    shape the shipped `theCatalogFixtureIsTheOnePS6MeasuresOver` re-asserts against PS6's own
    invariants. Same method, same ceiling, no tap inventory in the turn.
11. **`.error(_, hasLastGood: true)` maps to content, not to `.failed`.** Task 2′.3 says "a failed
    refresh ⇒ `.failed(error)`" and task 2′.4 pins the `hasLastGood` rule only for `.loading`.
    Applying it uniformly is the more faithful reading of the spec — "where the tap inventory is
    **unavailable**" — because a failed refresh over a resident inventory still has rows on screen,
    and "No packages from your taps." would be false while they are visible. The `.failed` mapping is
    asserted over an empty inventory, exactly as `TapProjectionTests` asserts its own.
12. **Round 2 has 56 task checkboxes, not the 57 the launch brief named.** The 57th is round-1's
    `6.7`, which the file itself marks **VOID** and leaves unchecked on purpose. **55 of 56** round-2
    tasks are complete; the one open box is **6′.7 (open the PR)**, deferred by this run's explicit
    instruction not to push and not to open a pull request.

## Task ledger

**Round 2: 55 of 56 complete.** Open: **6′.7**, delivery, deferred by instruction; its content is
drafted above. Round 1's 59 boxes are unchanged history, with `6.7` void.

---

# Round 3 — INSTALLED badge (2026-08-25)

Maintainer UI feedback, observed in the running app: a tap row carried a third text line reading
`Installed.` or `Not installed.`, where a catalog row carries the green **Installed** pill and shows
nothing at all when the package is not installed. The tap rows now mirror the catalog rows. This section
is the delta from `8f233b1`; rounds 1 and 2 above are unchanged history. Delivery is unchanged:
**single-pr**, **`size:exception` accepted (maintainer, 2026-08-25)**, RDD disabled.

## Phase 0″ — baselines, measured at `8f233b1`

| Runner | Baseline |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,870 tests / 217 suites passed, 1 known issue** |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 256 distinct test ids** |

One preflight action: `cellar/InfoPlist.xcstrings` carried working-tree churn and was discarded before
any work, per the launch brief. The tree was clean at the first commit.

## Work unit evidence — round 3

| Unit | Commit | Focused command and exact result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU10** | `8f33b1f` | N/A — artifacts only; 4 files, **+230 / −31** | N/A — no behaviour changes | `git revert 8f33b1f`; the branch returns to `8f233b1` |
| **WU11** | `9714cfc` | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` → **32 tests / 1 suite passed**; whole core suite **1,870 / 217 passed, 1 known issue** | N/A — a pure projection over resident values; there is no runtime to exercise | Revert one commit in `TapPackageSearch.swift` + its test file. **Not independently revertible from WU12** — see deviation 1 |
| **WU12** | `30608ab` | `xcodebuild build …` → **`** BUILD SUCCEEDED **`**; `git diff --stat main -- cellar/Browse/BrowseView.swift cellar.xcodeproj/project.pbxproj` → **empty** | **Deferred to delivery** — launching the app is the one harness this run could not execute headlessly. Everything it would observe is pinned by a runner: the pill's component, its gate, its position after the kind chip, the absent state line and the surviving withheld note are all asserted over the composed sources | `git checkout 8f233b1 -- cellar/Browse/` restores all three files and drops the new one |
| **WU13** | `88898d0` | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`, 257 distinct ids** | N/A — source-scan suite; the app harness is WU12's | Revert one test commit; no production line is its own |

## TDD cycle evidence — round 3

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 2″.1/2″.2 ps4, ps9 | `TapPackageSearchTests.swift` | Unit | ✅ 1,870/1,870 | ✅ **genuine compile failure** — `value of type 'TapSearchHit' has no member 'isInstalled'` and `… has no member 'stateNote'`, at 8 sites | ✅ 32/32, then 1,870/217 | ✅ three states × `isInstalled` × `stateNote`, plus both withdrawn strings enumerated as absences and the surviving note asserted as the **only** one emitted | ✅ |
| 3″.1–3″.3 DD-18 | — (production) | — | ✅ build | ➖ proven by WU13's rows below, per the round-2 precedent | ✅ `** BUILD SUCCEEDED **` | ➖ | ✅ the private method is **deleted**, not left beside its replacement |
| 4″.1 ps15 (copy) | `TapSearchCompositionTests.swift` | Unit-app | ✅ 256/256 | ✅ **reversible mutation** — the tap row's `StatusPill.installed` replaced by `Text("Installed.")`; `theSurfaceCopyLivesInTheProjectionNotTheView` **and** `bothSearchSurfacesDrawTheOneSharedPill` both failed | ✅ | ✅ withdrawn strings scanned as **complete literals** over both files, plus the four surviving pinned sentences | ✅ |
| 4″.1 ps15 (pill, catalog half) | same | Unit-app | ✅ | ✅ **reversible mutation** — `git show HEAD~1:cellar/Browse/PackageRow.swift` restored the private `statusPill`; `bothSearchSurfacesDrawTheOneSharedPill` failed | ✅ | ✅ label declared once, both surfaces anchored, the predecessor asserted gone, `BrowseView` asserted free of both spellings | ✅ |
| 4″.1 ps15 (position + projection) | same | Unit-app | ✅ | ✅ **reversible mutation** — the pill moved **above** `KindTag` in the tap row, and `private static let notInstalledCopy = "Not installed."` revived in the projection; both rows failed | ✅ | ✅ order asserted on **both** surfaces by range comparison, not by one | ✅ |
| 4″.2 DD-4 | same | Unit-app | ✅ | ➖ amendment, not a new claim — see deviation 2 | ✅ | ✅ `occurrences` added to the forbidden list; the two reads asserted **separately** | ✅ |

**Every mutation was restored byte-identically and verified**: `shasum -a 256 -c` reported `OK` for
`TapSearchView.swift`, `PackageRow.swift`, `StatusPill.swift` and `TapPackageSearch.swift` after each of
the three mutation runs, and `git status --porcelain` showed only the test file modified before the WU13
commit.

## Phase 6″ — verification and bindings

| Task | Result |
|---|---|
| **6″.1** core suite | `swift test --package-path Packages/CellarCore` → **1,870 tests / 217 suites passed, 1 known issue** — unchanged, because round 3 **renames and restates** one row rather than adding or deleting any. One non-reproducing extra issue in one of four runs; the other three were the baseline. Its identity was not captured, and it did not recur — the same shape of flake round 2 recorded at 0′.4 and attributed to the shipped, timing-sensitive `OperationCenterCancelTests` row. Not absorbed, and not claimed to be that row without evidence |
| **6″.2** app target, scoped | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`**, **257** distinct test ids (baseline **256**; **+1** — `bothSearchSurfacesDrawTheOneSharedPill`, confirmed present and passing in the log). The raw `Test case … passed` line count reads **267** in both runs because roughly ten ids are reported twice under parallel execution; that number is an artefact of the reporter, not a count, and the distinct-id count is the honest one. Round 2's record of "267 / 257" used the same coarse line count for the first figure. The full `-scheme cellar` runner is **not** the gate: it is red on `main` from two pre-existing `cellarUITests` Taps failures (`:209`, `:231`) |
| **6″.3** bindings proof | `git diff --stat main --` over `cellar/Browse/BrowseView.swift`, `cellar.xcodeproj/project.pbxproj`, `openspec/specs/`, `PackageSearchIndex.swift`, `MutationCommand.swift`, `PackageDetailView.swift` and `cellarUITests/` → **empty output**. `BrowseView.swift` is still byte-identical to `main` **after** the pill extraction, which is the load-bearing claim of DD-18, and `cellarUITests.swift:226`'s shipped `app.staticTexts["Not installed."]` assertion is untouched because it reads the **tap-detail** rows TM5 governs, not this surface |
| **6″.4** branch total | `git diff --shortstat main...HEAD` → **25 files, +6,748 / −53 = 6,801 authored lines** measured before this file's round-3 section, and **25 files, +6,838 / −53 = 6,891** with it. Round 3's own delta is `git diff --shortstat 8f233b1...HEAD` → **10 files, +527 / −103 = 630 lines** before this section and **11 files, +617 / −103 = 720** with it, split **code+test 400** and **artifacts 320**. Measured against the 5,000-line project budget and the maintainer's accepted 4,900–5,200: the branch is **above both**, and the excess is reported rather than trimmed, under the accepted **`size:exception`** |
| **6″.5** this record | Committed as `docs(sdd): record the m11-tap-search round 3 apply progress`. **Delivery is not a round-3 task**: it stays round 2's open `6′.7`, still deferred by this run's explicit instruction not to push and not to open a pull request. Round 2's drafted PR body stands, with two corrections — statement 6's line count is superseded by 6″.4's measurement, and one statement should be added: the two search surfaces now draw **one** installed pill component, asserted structurally |

## Deviations — round 3 (reported, not absorbed)

1. **WU11 leaves the app target non-compiling until WU12**, exactly as round-2 deviation 9 recorded for
   WU6/WU7. `stateCopy` is renamed, and `TapSearchView.swift` renders it. The rollback order
   (WU13 → WU12 → WU11 → WU10) already requires reverse-order rollback, so nothing is unsafe; the unit's
   "independently revertible" framing is what would be wrong, and the table above says so instead.
   `swift test` for `CellarCore` is green at WU11.
2. **`hit.isInstalled` was removed from `notInstalledTapRowsAreNotSelectable`'s forbidden list.** This is
   a guard being narrowed, so it is reported rather than buried. The guard's subject is **routability**,
   and the row now legitimately reads installed-ness to draw the pill. A `Bool` about installation cannot
   express routability, which additionally requires the hit to be uncollided and unique — and those two
   facts stay forbidden (`alsoInCatalog`, `hit.state ==`, `== .notInstalled`, plus `occurrences`, newly
   added). Two positive assertions were added in compensation: the pill's gate and the selection's gate
   are asserted **separately**, so a future edit that gated selection on installed-ness fails.
3. **`StatusPill.swift` does not join `PerPackageTrustSources.views()`.** Task 4″.3 asked for the
   decision to be made and recorded. That scanner guards surfaces that present **per-package trust**
   copy; the pill presents install state and names no trust concept. Adding it would make the suite's
   sorted anchor assert something the file has no relationship to. Nothing was retargeted.
4. **`TapPackage.statusExplanation` is now the shape DD-9 originally wanted, and is still not reused.**
   DD-9 refused it in round 1 because it is `nil` for `.installed` and would have left an installed row
   silent. After round 3 that is exactly right — but it answers `"Not installed."` for the third state,
   which this surface withdrew, and it is a projection over `TapPackage`, not over a hit. `TapPackageSearch`
   keeps its own `note(for:)`. Recorded so a later reader does not "simplify" the two into one.
5. **The round-2 record's app-target figure "267 passing / 257 distinct" mixed two metrics.** The 267 is
   a `Test case … passed` line count; it exceeds the distinct-id count because three parameterized
   tests print one line per case, not because ids are reported twice. Measured by verify round 4 from
   the retained logs: **257** distinct ids at round 3 (`f98d9fa`) and **258** at round 4 (`9894a6a`),
   exactly one id added and none removed (`comm` over the id sets). This paragraph originally stated
   256 → 257 and a duplicate-reporting cause; both were wrong and are corrected here (verify W4).

## Task ledger

**Round 3: 24 of 24 complete.** Round 3 has **no** delivery task — the branch's one open delivery box is
still round 2's **`6′.7`**, deferred by this run's explicit instruction not to push and not to open a
pull request. Round 2's ledger is otherwise unchanged at 55 of 56. Round 1's 59 boxes are unchanged
history, with `6.7` void.
