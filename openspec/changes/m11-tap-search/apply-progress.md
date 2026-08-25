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

---

# Round 4 — UPDATE pill (2026-08-25)

Maintainer UI feedback, observed in the running app: round 3 gave the tap rows the catalog row's green
**Installed** pill and stopped there. An installed tap package whose own receipt already reports it
outdated — `druk` at `1.21.1` against the offered `1.22.1` — read as merely installed on "Search our
taps" while the same package read as updatable on the catalog surface and in the Installed list. The tap
rows now carry the **same shared orange UPDATE pill**, after the Installed pill. This section is the
delta from `03be818`; rounds 1–3 above are unchanged history. Delivery is unchanged: **single-pr**,
**`size:exception` accepted (maintainer, 2026-08-25)**, RDD disabled.

## Phase 0‴ — baselines, measured at `03be818`

| Runner | Baseline |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,870 tests / 217 suites passed, 1 known issue** |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 258 distinct test ids** (268 raw `Test case … passed` lines) |

One preflight action: `cellar/InfoPlist.xcstrings` carried working-tree churn and was discarded before
any work, per the launch brief. The tree was clean at the first commit.

**The 258 is a correction of this run's own first measurement, and it vindicates verify round 4.** The
first baseline count read **257**, and the discrepancy against verify's 258 at `9894a6a` was chased to a
cause rather than reported as flake: the baseline log was captured through `tee`, and xcodebuild's
concurrent status block interleaved itself **into the middle of a `Test case …` line** —
`app-baseline.log:821` reads `…theBoundedControlGuardSeesAnUnbulkedV` followed by three
`IDETestOperationsObserverDebug` lines and then `erb(): passed`. A line-based `rg` scan cannot match
across that break, so it silently dropped one shipped, branch-untouched `BulkActionBarTests` id. A
whole-file scan finds it. Round 3's "257 → the raw count is 267" figures came from the same line-based
method over a `tee`d log and are therefore **one low on the same footing**; nothing about round 3's
work changes, only how it was counted. Round 4's runs redirect with `> log 2>&1` and two independent
runs produced **identical** 259-id sets.

## Commits

| Unit | Commit | What |
|---|---|---|
| WU14 | `1e47f86` | `docs(sdd): amend m11-tap-search for the shared update pill on tap rows` — PS8 six-facts / offered-version / update-pill clauses, two new scenarios, `specs/README.md` (rev 5), `design.md` (**DD-19** new, round-4 file table, flow lines, RED rows), `tasks.md` Round 4 phase. Delta specs only; `openspec/specs/**` untouched |
| WU15 | `52c4011` | `feat(search): expose the offered version for an outdated installed tap package` — stored `TapSearchHit.nextVersion: String?` + `offeredVersion(for:)`; `InstalledFixture.receipt(outdatedTo:)`; `TapSearchFixture.fourStateTaps` / `fourStateOutdatedInstalled` |
| WU16 | `04122b1` | `feat(taps): mark outdated tap packages with the shared update pill` — `TapSearchView.swift` draws `UpdateTag(nextVersion:)` after `StatusPill.installed`. **`PackageRow.swift` untouched** |
| WU17 | `baff212` | `test(taps): pin the shared update pill on outdated tap rows` — `bothSearchSurfacesDrawTheOneSharedUpdatePill` |
| — | (this record) | `docs(sdd): record the m11-tap-search round 4 apply progress` |

## Key design decision — DD-19

The offered version is read from the **installed receipt the projection already holds**, never from the
tap and never from the catalog, so PD6 and TM5 are untouched and no brew invocation is added. Two
choices carry the round:

1. **Keyed off `TapPackage.installedHandoff`, not off `package.id`.** `TapProjection.installState`
   deliberately answers `.notInstalled` for a receipt whose `tap` names a *different* tap, so a lookup
   by bare identity would hang an UPDATE pill on a row this surface calls not installed. Both installed
   states answer, because both **are** installed. `aReceiptFromAnotherTapOffersNoVersion` pins it.
2. **Stored, not computed** — unlike round 3's `isInstalled`. `Mirror` enumerates stored properties, and
   PS8's facts scenario reads that enumeration: a computed offer would be a fact the type carries and
   the enumeration denies. The scenario, the requirement and the test are amended to say **six** facts.

**`UpdateTag` needed no extraction, which is the round's cheapest fact.** It is already `internal` at
`PackageRow.swift:114`, already drawn by the Installed and Updates lists, and already takes the version
as a **value** — the exact shape DD-18 had to *create* for the installed pill. Round 4 therefore costs
`PackageRow.swift`, `StatusPill.swift` and `BrowseView.swift` a **zero-line diff** each.

## Work unit evidence — round 4

| Unit | Commit | Focused command and exact result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU14** | `1e47f86` | N/A — artifacts only; 4 files, **+248 / −20** | N/A — no behaviour changes | `git revert 1e47f86`; the branch returns to `03be818` |
| **WU15** | `52c4011` | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` → **34 tests / 1 suite passed** (was 32); whole core suite **1,872 / 217 passed, 1 known issue** | N/A — a pure projection over resident values; there is no runtime to exercise | Revert one commit across the projection, two fixtures and the test file. **Independently revertible from WU16 this round** — the member is *added*, never renamed, and `xcodebuild build …` was run at this commit and returned `** BUILD SUCCEEDED **` to prove it, which is what round 3's WU11 could not claim |
| **WU16** | `04122b1` | `xcodebuild build …` → **`** BUILD SUCCEEDED **`**; `git diff --stat 03be818 -- cellar/Browse/PackageRow.swift cellar/Browse/StatusPill.swift` → **empty**; `git diff --stat main -- cellar/Browse/BrowseView.swift` → **empty** | **Deferred to delivery** — launching the app is the one harness this run could not execute headlessly. Everything it would observe is pinned by a runner: the component's identity, its uniqueness, its gate, its position after the Installed pill, and the absence of any update literal in the view are all asserted over the composed sources | `git checkout 03be818 -- cellar/Browse/TapSearchView.swift` — one file |
| **WU17** | `baff212` | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`, 259 distinct ids** | N/A — source-scan suite; the app harness is WU16's | Revert one test commit; no production line is its own |

## TDD cycle evidence — round 4

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 2‴.1–2‴.3 ps4, ps9b | `TapPackageSearchTests.swift` | Unit | ✅ 1,870/1,870 | ✅ **genuine compile failure** — `value of type 'TapSearchHit' has no member 'nextVersion'` at **9 sites**, and no other error | ✅ 34/34, then 1,872/217 | ✅ four states × offered version (outdated ⇒ its own version, withheld+outdated ⇒ its own **distinct** version, installed-and-current ⇒ `nil`, not-installed ⇒ `nil`), plus the whole up-to-date inventory re-run as a second fixture, plus the wrong-tap receipt as its own row | ✅ |
| 2‴.2 fixtures | `InstalledFixture.swift`, `TapSearchFixture.swift` | Unit (arrangement) | ✅ every shipped call site source-identical (defaulted parameter) | ➖ arrangement | ✅ | ✅ two **distinct** offered versions, so a hit reading its neighbour's offer fails | ✅ `outdatedTo:` sets the version and the flag **together**, so an incoherent receipt is unrepresentable |
| 3‴.1 DD-19 (view) | — (production) | — | ✅ build | ➖ proven by WU17's row below, per the round-2 and round-3 precedent | ✅ `** BUILD SUCCEEDED **` | ➖ | ➖ nine lines added, nothing to clean |
| 4‴.1–4‴.2 the shared pill | `TapSearchCompositionTests.swift` | Unit-app | ✅ 258/258 | ✅ **two reversible mutations**, each failing `bothSearchSurfacesDrawTheOneSharedUpdatePill`: (a) `UpdateTag(nextVersion: next)` → a local `Text("UPDATE")`; (b) the chip moved **above** `StatusPill.installed` | ✅ | ✅ component uniqueness asserted by a **tree walk**, both surfaces anchored, both positions asserted by range comparison, the gate asserted, three re-derivation routes forbidden, and the label's home positively anchored | ✅ |

**Both mutations were restored byte-identically and verified**: `shasum -a 256 -c` reported
`cellar/Browse/TapSearchView.swift: OK` after each, and `git status --porcelain` showed only the test
file modified before the WU17 commit.

**Measurement gotcha discovered and recorded.** `-only-testing:cellarTests/TapSearchCompositionTests/bothSearchSurfacesDrawTheOneSharedUpdatePill`
— a **function-level** filter — selects **nothing** for a Swift Testing test and exits
`** TEST SUCCEEDED **`. The first mutation-(a) run reported success for exactly that reason and was not
believed; re-running at **suite** level produced the real `** TEST FAILED **`. A function-level
`-only-testing:` filter must never be used as a RED gate: it cannot distinguish "passed" from "never ran".

## Phase 6‴ — verification and bindings

| Task | Result |
|---|---|
| **6‴.1** core suite | `swift test --package-path Packages/CellarCore` → **1,872 tests / 217 suites passed, 1 known issue** (baseline **1,870**; **+2** — `onlyAnOutdatedInstalledHitOffersAVersion` and `aReceiptFromAnotherTapOffersNoVersion`. The facts row was **renamed**, not added: `aHitCarriesItsFiveFacts…` → `aHitCarriesItsSixFacts…`). Run **five** times: four green at that exact total, one reporting one extra non-reproducing issue whose identity was **not captured** — the same shape round 3 recorded at 6″.1 and round 2 at 0′.4. Not absorbed, and not attributed to any row without evidence |
| **6‴.2** app target, scoped | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`**, **259** distinct test ids (baseline **258**; **+1**). Two independent runs produced byte-identical id sets; `comm` over the two sets against the baseline shows **exactly one id added** — `TapSearchCompositionTests/bothSearchSurfacesDrawTheOneSharedUpdatePill()` — and **none removed**. Raw `Test case … passed` lines: 268 → 269; that number is a reporter artefact, not a count. The full `-scheme cellar` runner is **not** the gate: it is red on `main` from two pre-existing `cellarUITests` Taps failures (`:209`, `:231`) |
| **6‴.3** bindings proof | `git diff --stat main --` over `cellar/Browse/BrowseView.swift`, `cellar.xcodeproj/project.pbxproj`, `openspec/specs/`, `PackageSearchIndex.swift`, `MutationCommand.swift`, `PackageDetailView.swift` and `cellarUITests/` → **empty output**. Round 4 adds two of its own: `git diff --stat 03be818 -- cellar/Browse/PackageRow.swift cellar/Browse/StatusPill.swift` → **empty**. `BrowseView.swift` is byte-identical to `main` for the third round running, and this round the *catalog row itself* is untouched too — the strongest form DD-8 has taken yet |
| **6‴.4** branch total | `git diff --shortstat main...HEAD` → **26 files, +7,314 / −55 = 7,369 authored lines** measured before this section. Round 4's own delta is `git diff --shortstat 03be818...HEAD` → **10 files, +520 / −31 = 551 lines**, split **code+test 280** (6 files, +269 / −11) and **artifacts 271** (4 files, +251 / −20). Measured against the 5,000-line project budget and the maintainer's accepted 4,900–5,200: the branch is **above both**, and the excess is reported rather than trimmed, under the accepted **`size:exception`** |
| **6‴.5** this record | Committed as `docs(sdd): record the m11-tap-search round 4 apply progress`. **Delivery is not a round-4 task**: it stays round 2's open `6′.7`, still deferred by this run's explicit instruction not to push and not to open a pull request |

## Deviations — round 4 (reported, not absorbed)

1. **The "no version" prohibition had to be narrowed, in the spec and in the test.** PS8's five-facts
   paragraph forbade a version outright, and the facts test enforced it with a token scan
   (`labels.contains { $0.lowercased().contains("version") }`) that `nextVersion` trips. Both are
   amended to forbid a **published** version and to enumerate the one version-shaped member by name:
   `#expect(labels.filter { $0.lowercased().contains("version") } == ["nextVersion"])`. That is a
   **stronger** claim than the bare token — it fails on a second version member, which the token scan
   also would, and additionally fails if `nextVersion` is renamed or removed.
2. **The facts test was renamed, so the core suite's id set changed by more than its count.**
   `aHitCarriesItsFiveFactsAndItsCopyAndNothingElse` → `aHitCarriesItsSixFactsAndItsCopyAndNothingElse`,
   with its display name. Keeping the old name would have left the row asserting six facts under a name
   claiming five. The count arithmetic (+2) is unaffected because the rename is one id out and one in.
3. **The Outdated control's *reason* is now false as written, and was rewritten rather than left.** PS8
   said the surface offers no outdated control "because a tap hit carries no version and could never
   answer one". After round 4 a tap hit *can* carry one. The rule is unchanged — there is still no
   control — but its reason is restated honestly: the fact exists only for a hit this Mac has installed
   **and** whose receipt reports it outdated, so an Outdated chip would not filter the listing but
   **replace** it, silently collapsing every published package this Mac does not have. Leaving the old
   sentence would have left a false premise in a promoted requirement.
4. **`UpdateTag` is declared inside `PackageRow.swift`, so round 3's symmetric copy-ownership claim
   cannot be restated for it.** The round-3 pill row asserts "neither presenting surface composes the
   label" over both files, which works because `StatusPill` has a file of its own. Here the catalog
   surface **is** the declaring file, so the assertion is made where it is true — the tap surface
   carries no `"UPDATE"`/`"Update"` literal — and the other half is carried by a **tree walk** proving
   `struct UpdateTag: View` is declared exactly once across `cellar/`, `cellarTests/` and
   `Packages/CellarCore/Sources`. Extracting `UpdateTag` to its own file for symmetry was rejected: it
   would be a diff on a file with no reason to change, and `internal` already makes "the same
   component" representable — which was DD-18's entire problem and is not this round's.
5. **This run's first app-target baseline was wrong, and the error was in the measurement, not the
   suite.** Reported at Phase 0‴ above: 257 was a `tee`-interleaving artefact, the true baseline is
   **258**, verify round 4's 258 at `9894a6a` was right, and round 3's own recorded 257/267 figures
   share the same one-low method. Recorded here because the next reader will otherwise re-derive the
   same wrong number the same way.
6. **A core-suite flake recurred and was not identified.** One of five full runs reported one extra
   non-reproducing issue; the run was piped to `tail -2`, so only the summary line survived and the
   failing row's identity was lost. The remaining four runs were the exact baseline. Reported as an
   unidentified flake of the shape rounds 2 and 3 already recorded, not attributed and not absorbed.

## Task ledger

**Round 4: 22 of 22 complete.** Round 4 has **no** delivery task — the branch's one open delivery box is
still round 2's **`6′.7`**, deferred by this run's explicit instruction not to push and not to open a
pull request. Round 3's ledger is unchanged at 24 of 24, round 2's at 55 of 56, and round 1's 59 boxes
are unchanged history with `6.7` void.

---

# Round 5 — installed verbs (maintainer defect report, 2026-08-25)

**The defect, as reported.** In "Search our taps", the `⋯` menu on an **installed** row offered only
Install and Copy install command. Browse offers Reinstall, Uninstall… (plus Uninstall and Zap… for a
cask, and Upgrade / Pin / Unpin where applicable) for the same package. **Root cause confirmed at
`cellar/Browse/TapSearchView.swift:184`**: the row built `PackageEntry(installed: nil, catalog: nil,
id: hit.mutationTarget)` for *every* hit, so `MutationMenu.swift:32`'s `if entry.isInstalled` branch
could never be taken however installed the package was. No verb was missing; the record was.

## Phase 0⁗ — baselines, measured at `2cba75b`

| Runner | Baseline |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,872 tests / 217 suites passed, 1 known issue** |
| `xcodebuild test … -only-testing:cellarTests` | **259 distinct test ids** |

`cellar/InfoPlist.xcstrings` again carried working-tree churn and was discarded before any work, per the
launch brief. The tree was clean at the first commit and at every commit after it.

The 259 was measured **after** WU19's production change had landed in the working tree, so that run is
also this round's RED proof for the pin: it returned `** TEST FAILED **` with exactly one failing id,
`TapSearchCompositionTests/theTapSearchSurfaceComposesNoTrustGateAndNoBadge()`, whose
`PackageEntry(installed: nil, catalog: nil` literal the change had just falsified. Every other id in the
set passed, which is what makes 259 a usable baseline rather than a broken run.

## Commits

| Unit | Commit | What |
|---|---|---|
| WU18 | `496da52` | `docs(sdd): amend m11-tap-search so installed tap rows carry their installed record` — PS8's rewritten verbs clause and its new mutation-handoff paragraph, the amended facts / offered-version / trust scenarios, one new `unit-app` scenario, `specs/README.md` (rev 6 + an arithmetic correction), `design.md` (**DD-20** new, **DD-9**'s entry clause struck, round-5 file table, flow lines, RED rows), `tasks.md` Round 5 phases. **Delta specs only; `openspec/specs/**` untouched** |
| WU19 | `9910de0` | `feat(taps): hand the mutation menu the installed record for an installed tap package` — stored `TapSearchHit.installed: InstalledPackage?`, `installedReceipt(for:)` keyed on `TapPackage.installedHandoff`, `offeredVersion(of:)` derived from that one resolved receipt, and `PackageEntry(installed: hit.installed, catalog: nil, id:)` on the row |
| WU20 | `951145d` | `test(taps): pin that installed tap rows reach the mutation menu with their record` — the literal pin moved, plus `anInstalledTapRowReachesTheMutationMenuWithItsRecord` |
| — | (this record) | `docs(sdd): record the m11-tap-search round 5 apply progress` |

## Key design decision — DD-20

The hit gains a **stored** `installed: InstalledPackage?`, and the row hands it to the shared
`MutationMenu`. Three choices carry the round:

1. **Resolved by the tap-aware handoff, and resolved exactly once.** `hits(…)` now calls
   `installedReceipt(for:)` — `package.installedHandoff.flatMap { installed.package($0) }` — and both
   the offered version and the handoff read that one result. A bare `PackageID` lookup was rejected
   twice over: it answers for a receipt whose `tap` names a different tap, and it would attach a
   **colliding catalog package's** receipt to a tap row, offering to uninstall a package the row does
   not name. `aCollidingCatalogReceiptIsNeverAttachedToATapRow` pins exactly that, triangulated against
   the same fixture with the receipt naming the publishing tap.
2. **Stored, not computed**, for DD-19's reason: `Mirror` enumerates stored properties and PS8's facts
   scenario reads that enumeration. The member is enumerated there **as a handoff, not a seventh fact** —
   it publishes nothing the tap declares, costs no brew invocation, and the surface presents nothing from
   it, so the six-fact ceiling and TM5's tap-source prohibition are both untouched.
3. **The view resolves nothing.** Letting `TapSearchView` look the receipt up from `installed.inventory`
   was rejected: the `unit` layer could then prove nothing about the keying — the exact thing that was
   broken — and the view would own a rule. It supplies a record and a bare target and decides nothing.

**`MutationMenu.swift` needed no edit at all**, which is the round's cheapest fact: `entry.isInstalled`,
the `isOutdated` gate on Upgrade, the `isPinned` gate on Pin/Unpin, the `FormulaID`/`CaskID` narrowing,
the confirmation rule and every label are already there. Round 5 costs `MutationMenu.swift`,
`PackageRow.swift`, `StatusPill.swift`, `BrowseView.swift` and `project.pbxproj` a **zero-line diff** each.

## Work unit evidence — round 5

| Unit | Commit | Focused command and exact result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU18** | `496da52` | N/A — artifacts only; 4 files, **+229 / −15** | N/A — no behaviour changes | `git revert 496da52`; the branch returns to `2cba75b` |
| **WU19** | `9910de0` | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` → **35 tests / 1 suite passed** (was 34); whole core suite **1,873 / 217 passed, 1 known issue**; `xcodebuild build …` → **`** BUILD SUCCEEDED **`** | **Deferred to delivery** — launching the app is the one harness this run could not execute headlessly. What it would observe is pinned by runners: which branch the shared menu takes is `entry.isInstalled` (asserted over `MutationMenu.swift`), and which record reaches it is asserted over both the projection (`unit`) and the call site (`unit-app`) | Revert one commit across `TapPackageSearch.swift`, `TapSearchView.swift` and the unit test file. The member is **added**, never renamed, so nothing else on the branch stops compiling; `xcodebuild build …` was run at this commit to prove it |
| **WU20** | `951145d` | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`, 260 distinct ids** | N/A — source-scan suite; the app harness is WU19's | Revert one test commit; no production line is its own |

## TDD cycle evidence — round 5

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 2⁗.1–2⁗.3 `TapSearchHit.installed` | `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | `unit` | ✅ 1,872 / 217, 1 known issue at `2cba75b` | ✅ **compile failure**, `TapPackageSearchTests.swift:188:21: error: value of type 'TapSearchHit' has no member 'installed'` (and 11 more sites) | ✅ filtered **35 / 1 suite passed**; whole core suite **1,873 / 217 passed** | ✅ 3 cases — the four-state fixture (installed-outdated, withheld-outdated, installed-current, absent), the up-to-date three-state fixture, and the colliding-receipt row with its own inverted triangulation (catalog's tap ⇒ `nil`, publishing tap ⇒ the receipt) | ✅ `offeredVersion(for:)` → `installedReceipt(for:)` + `static offeredVersion(of:)`; the lookup is performed once and read twice instead of twice |
| 2⁗.4–2⁗.5 the row's entry | `cellarTests/TapSearchCompositionTests.swift` | `unit-app` | ✅ 259 distinct ids at `2cba75b` | ✅ `theTapSearchSurfaceComposesNoTrustGateAndNoBadge()` **failed** on the falsified `PackageEntry(installed: nil, catalog: nil` pin | ✅ pin updated to `installed: hit.installed`; suite **`** TEST SUCCEEDED **`** | ➖ single call site | ✅ the stale "neither an installed nor a catalog record" comment rewritten rather than left contradicting the code |
| 3⁗.1–3⁗.2 the composition guard | `cellarTests/TapSearchCompositionTests.swift` | `unit-app` | ✅ 259 → 260 ids, no shipped id lost | ✅ **reversible mutation** — the entry literal reverted to `installed: nil`; `anInstalledTapRowReachesTheMutationMenuWithItsRecord()` **and** the pin both failed; restored and verified `shasum -a 256 -c` → `cellar/Browse/TapSearchView.swift: OK` | ✅ **`** TEST SUCCEEDED **`, 260 distinct ids** | ➖ single scenario | ➖ none needed |

**Test summary — round 5.** 2 tests written (`aCollidingCatalogReceiptIsNeverAttachedToATapRow` `unit`,
`anInstalledTapRowReachesTheMutationMenuWithItsRecord` `unit-app`), 2 existing tests amended
(`aHitCarriesItsSixFactsAndItsCopyAndNothingElse`, `onlyAnOutdatedInstalledHitOffersAVersion`), 1
existing pin corrected (`theTapSearchSurfaceComposesNoTrustGateAndNoBadge`). Layers: `unit` 1, `unit-app`
1. No approval tests — no refactoring task. Pure functions created: 1 (`static offeredVersion(of:)`).

## Phase 6⁗ — verification and bindings

| Check | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,873 tests / 217 suites passed, 1 known issue** (baseline 1,872 → **+1**, the one new `unit` test) |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 260 distinct test ids** (baseline 259 → **+1**, the one new `unit-app` test; no shipped id lost) |
| `cellar/Browse/BrowseView.swift` vs `main` | **byte-identical** (`git diff --quiet` clean) — fourth round running |
| `cellar/Activity/MutationMenu.swift` vs `main` | **empty diff** — no verb re-implemented, none re-worded |
| `project.pbxproj`, `openspec/specs/`, `PackageSearchIndex.swift`, `MutationCommand.swift`, `PackageDetailView.swift`, `cellarUITests/` vs `main` | **all empty** |
| `PackageRow.swift`, `StatusPill.swift` vs `2cba75b` | **empty** — round 5 changes no mark |
| `git diff --shortstat main...HEAD` | **26 files changed, 7,864 insertions(+), 55 deletions(-)** — reported, not trimmed, under the accepted `size:exception` |
| `git diff --shortstat main...HEAD -- ':!openspec'` | **16 files changed, 3,336 insertions(+), 55 deletions(-)** — the code-only half of the same total |
| `git diff --shortstat 2cba75b..HEAD` | **8 files changed, 452 insertions(+), 37 deletions(-)** — round 5's own cost |
| Working tree | clean at every commit; `cellar/InfoPlist.xcstrings` churn discarded, never committed |

Full `-scheme cellar` was **not** run: it is red on `main` from two pre-existing `cellarUITests` Taps
failures and is not this change's gate. Distinct ids were counted from a `> log 2>&1` redirect over a
whole-file `rg -o "Test case '[^']+'" | sort -u | wc -l`, per the round-4 measurement gotcha.

## Deviations — round 5 (reported, not absorbed)

1. **A stored member was added to a type whose requirement says "exactly six facts", and the spec was
   amended to say why rather than left to be read as violated.** PS8 now carries a **mutation handoff**
   paragraph: the receipt is carried so the shared spine can be handed the record it already takes, it
   publishes nothing the tap declares, and the surface presents nothing from it — so the ceiling stays
   six. The facts scenario and its `Mirror` row **enumerate it by name**, which is what keeps that claim
   testable: a later member that *is* tap-published metadata cannot slip in behind this one.
2. **DD-19 explicitly rejected "a computed `nextVersion` reading a stored `InstalledPackage` on the
   hit". DD-20 is not that, and says so.** `nextVersion` stays **stored** and stays the fact; the receipt
   is carried *additionally*, because `PackageEntry`'s `installed` slot is exactly this record and there
   is no smaller value that satisfies the shared menu. What DD-19 rejected was replacing a stored fact
   with a computed one, which would have made `Mirror` deny it.
3. **My first draft of the new `unit-app` guard forbade `installed.inventory` in the surface and was
   wrong.** `TapSearchView.swift:109` hands that whole inventory *to* the projection — the shipped
   composition, and the opposite of resolving a record locally. The forbidden list was narrowed to a
   genuine lookup (`installed.package(`, `inventory.package(`, `installedHandoff`, `.installed?.`) and
   the reason is recorded in the test itself, so the next reader does not re-add the over-broad token.
   Caught by the runner, at the cost of one red run — which is the process working.
4. **`specs/README.md`'s totals line was already wrong before this round, and was corrected.** It read
   “20 new scenarios (15 `unit`, 5 `unit-app`)” from revision 3 onward while the table above it said
   19 + 1 + 2 = 22. Rounds 3 and 4 amended the table and never re-footed the summary. It now reads
   **23 (16 `unit`, 7 `unit-app`)**, with the correction stated inline as a block quote rather than
   silently applied. No row total moved.
5. **One core-suite flake, identified this time.** The first full `swift test` after GREEN reported
   `Test "Every tap terminal refreshes its declared domains exactly once" recorded an issue with 1
   argument terminal → .cancellationBeforeSpawn at MutationRefreshReceiptTests.swift:214:13:
   Expectation failed: (counts.services → 0) == (terminal.blockerServiceTerminals → 1)`. It is a
   mutation-refresh timing flake with **no path to tap search** — the branch does not touch
   `MutationRefreshReceipt`, `OperationCenter` or any refresh terminal. Re-running that suite alone
   passed 9/9, and two subsequent whole-suite runs passed 1,873/217. Reported and **not** attributed to
   this change; rounds 2, 3 and 4 recorded flakes of the same shape, and this is the first with an
   identity attached, which is the round-4 “redirect, never `tee`” lesson paying off.
6. **`swift test --filter` was used for the RED/GREEN cycle and the whole package for the gate.** The
   filter is at **suite** level (`TapPackageSearchTests`), never function level, per the launch brief.

## Task ledger

**Round 5: 19 of 19 complete.** Round 5 has **no** delivery task — the branch's one open delivery box is
still round 2's **`6′.7`**, deferred by this run's explicit instruction not to push and not to open a
pull request. Round 4's ledger is unchanged at 22 of 22, round 3's at 24 of 24, round 2's at 55 of 56,
and round 1's 59 boxes are unchanged history with `6.7` void.

---

# Round 6 — minimal detail for not-installed tap hits

**Maintainer product decision (binding, 2026-08-25).** The 2026-08-24 rule "a not-installed hit is
non-selectable" is **reversed**. An unambiguous not-installed hit is selectable and opens a minimal
detail composed **exclusively** from the resident tap inventory. Ambiguity is untouched: a colliding
bare token or a duplicate `PackageID` still withholds the route in **either** install state.

**Delivery.** `single-pr` with `size:exception` **accepted** (maintainer, 2026-08-25). Measured totals
are reported below and are **not** trimmed. RDD disabled. Strict TDD active throughout.

## Phase 0⁵ — baselines, measured at `cbd13cb`

| Runner | Baseline |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,873 tests / 217 suites**, 1 known issue **+ 1 flake** |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 260 distinct test ids (corrected by verify round 7; this run first read 259 — one id lost to an interleaved status line)** |
| Working tree | clean after discarding `cellar/InfoPlist.xcstrings` churn |

Two baseline notes, reported rather than absorbed:

1. **The core flake recurred, with the same identity round 5 recorded.** `Every tap terminal refreshes
   its declared domains exactly once … terminal → .cancellationBeforeSpawn at
   MutationRefreshReceiptTests.swift:214:13`. It has no path to tap search — the branch touches no
   refresh terminal — and it did **not** recur in either post-GREEN whole-suite run.
2. **259, where round 5 recorded 260.** Same command, same extraction (`> log 2>&1`, then
   `rg -o "Test case '[^']+'" | sort -u | wc -l`). All 14 shipped `TapSearchCompositionTests` ids were
   present and the run was green, so nothing of this change's is missing. The one-id divergence is
   **unexplained** and is recorded rather than reconciled away; this round's own arithmetic is measured
   against **259**, the number this run actually produced.

## Commits

| Unit | Commit | What |
|---|---|---|
| WU21 | `1c0ced9` | `docs(sdd): amend m11-tap-search for a minimal detail on not-installed tap packages` — PS8's rewritten selectability clause and its inventory-fed detail paragraphs, two amended scenarios and two new ones, PD6's added clause + scenario, TM5's reaffirmation + scenario, `specs/README.md` revision 7, `design.md` (**DD-21**, **DD-22**, round-6 file table and RED rows), `tasks.md` Round 6. **Delta specs only; `openspec/specs/**` untouched** |
| WU21′ | `2c69422` | `docs(sdd): correct the m11 round-6 pane contract to projection-owned copy and no collision note` — two contract corrections found while implementing, recorded before the code that depends on them (deviation 1 below) |
| WU22 | `74560ae` | `feat(search): resolve a not-installed tap package to its one publishing tap for a minimal detail` — `routableID` drops its install-state conjunct; new `TapInventoryDetail` with `resolve(_:in:installed:)` |
| WU23 | `12d1242` | `feat(browse): open a name-only detail for a tap package that is not installed` — `PackageDetailView`'s third branch, its `taps:` parameter, the widened `versionStory`, the new pane file, the `ContentView` call site, the restated inert-row comment, and the pane added to `PerPackageTrustSources.views()` |
| WU24 | `05b7b48` | `test(browse): pin the name-only tap detail and the selection rule` — the selection row renamed and re-reasoned, the new pane-composition row, the shared-detail row narrowed |
| — | (this record) | `docs(sdd): record the m11-tap-search round 6 apply progress` |

## Key design decisions — DD-21 and DD-22

**DD-21 — routability is a fact about identity.** `routable` becomes `collides == false && unique`; the
`isInstalled` conjunct is deleted. Resolution lives in a new pure `TapInventoryDetail.resolve(_:in:installed:)`
that walks `TapProjection.thirdPartyTaps`, keeps the taps `TapProjection.publishes(id, in:)` answers
for, and returns a value **only when exactly one** does. Three choices carry it:

1. **The exactly-one rule is the safety property, and it lives where a test can reach it.** Zero
   publishers have no origin to name; several have no *single* origin, and picking one would put a
   wrong tap on the pane. Letting the view walk `TapStore.inventory` would have made that rule
   unobservable at the `unit` layer — the same objection DD-20 raised against a view-side receipt
   lookup.
2. **It also refuses any identity this Mac holds a receipt for**, keyed on the same
   `installed.package(id)` question the receipt branch asks. That is what keeps `stateCopy` honest: the
   value cannot exist for an installed package, so it can never say “Not installed.” about one. The
   withheld-tap case is why this is keyed on the **receipt** and not on the tap projection's install
   state — Homebrew withholds the tap, the record's `tap` is absent, and the record still decides.
3. **The branch sits third.** Catalog, then receipt, then inventory — asserted by range comparison, not
   argued. An installed tap package therefore still reaches its m10 receipt pane, and this branch
   answers only for a package this Mac does not have, which is exactly the case the receipt branch
   cannot answer.

**DD-22 — the pane composes nothing.** `PackageDetailView+TapInventory.swift` mirrors
`PackageDetailView+Receipt.swift`: it **calls** the shared header, the shared `fact(_:_:)` and the shared
`MutationMenu`, and declares no verb, no argv, no mutation target and — round 6's own addition — **no
sentence**. Both of its strings are the projection's `stateCopy` and `footerCopy`, rendered as values, so
neither appears anywhere in the app target at all.

The one genuinely new thing is the header's **widened `versionStory: String?`**. It was forced, not
preferred: a pane with no version must render **no version line**, and `String` cannot express that.
`versionStory: ""` was rejected outright — it draws an empty `Text` and a dangling separator dot, which
is a placeholder standing in for an absent fact, the thing PD1 keeps off this pane. Both shipped call
sites pass a `String` and are **source-identical**; the compiler proved it. `installed: nil` needed no
change at all: that parameter has been optional since m10, and the header's own status badge already
reads the absence and draws `Not installed`.

## Work unit evidence — round 6

| Unit | Commit | Focused command and exact result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| **WU21** | `1c0ced9` | N/A — artifacts only; 6 files, **+387 / −42** | N/A — no behaviour changes | `git revert 1c0ced9`; the branch returns to `cbd13cb` |
| **WU21′** | `2c69422` | N/A — artifacts only | N/A | `git revert 2c69422`; the contract returns to WU21's wording |
| **WU22** | `74560ae` | `swift test … --filter 'TapPackageSearchTests'` → **35 tests / 1 suite passed**; `--filter 'TapInventoryDetailTests'` → **5 tests / 1 suite passed**; whole core suite **1,878 / 218 passed, 1 known issue** | **Deferred to WU23** — the pane's rendering is the app harness's; what the `unit` layer proves is the resolution rule itself, over four refusal cases and their triangulations | Revert one commit across `TapPackageSearch.swift`, the new `TapInventoryDetail.swift` and two test files. `TapInventoryDetail` is **new**, so nothing else stops compiling; `routableID`'s type is unchanged |
| **WU23** | `12d1242` | `xcodebuild build …` → **`** BUILD SUCCEEDED **`** | **Deferred to delivery** — launching the app is the one harness this run could not execute headlessly. What it would observe is pinned by runners: the branch order by range comparison over `PackageDetailView.swift`, the pane's field set by source scan, and the resolution itself by five `unit` rows | Revert one commit across five app files. The `taps:` parameter is **added**, never renamed; the widened `versionStory` is source-compatible with both shipped call sites |
| **WU24** | `05b7b48` | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`, 261 distinct ids (corrected by verify round 7; first read 260)** | N/A — source-scan suite; the app harness is WU23's | Revert one test commit; no production line is its own |

## TDD cycle evidence — round 6

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 2⁵.1–2⁵.2 `routableID` | `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | `unit` | ✅ 1,873 / 217 at `cbd13cb` | ✅ **assertion** failures, 3 across 2 ids — `aNotInstalledHitIsRoutableWhenItsIdentityIsUnambiguous` at `:912` and `:913`, `anAmbiguousHitIsNotRoutableInEitherInstallState` at `:850` (`unambiguousAbsent.routableID → nil`) | ✅ filtered **35 / 1 suite passed** | ✅ 5 cases in one row — installed-and-colliding, not-installed-and-colliding, duplicate identity, and an unambiguous positive of **each** install state. The last two are the triangulation that matters: without them the three `nil`s would also pass under the retired rule | ➖ none needed — one conjunct deleted |
| 2⁵.3–2⁵.4 `TapInventoryDetail` | `Packages/CellarCore/Tests/BrewClientTests/TapInventoryDetailTests.swift` (new) | `unit` | N/A (new file) | ✅ **compile** failure, `TapInventoryDetailTests.swift:26:10: error: cannot find type 'TapInventoryDetail' in scope` (and 3 more sites) | ✅ filtered **5 / 1 suite passed**; whole core suite **1,878 / 218 passed** | ✅ 5 cases — one publisher, a cask on the same rule, zero/several/official publishers, a held receipt (installed **and** withheld), each with its own inverted triangulation | ✅ the resolution reads `TapProjection.publishes` and `packages(for:)` rather than re-deriving either; `kind` computed off `id` rather than stored beside it |
| 3⁵.1–3⁵.6 the app surface | — | build | ✅ `** BUILD SUCCEEDED **` at `74560ae` | ✅ **compile** failure at the preview call site — `cannot use explicit 'return' statement in the body of result builder 'ViewBuilder'`, the compiler's phrasing for the missing `taps:` argument | ✅ `** BUILD SUCCEEDED **` | ➖ single construction site | ✅ `PackageMetadataSection` removed after review against PS8's closed list (deviation 3) |
| 4⁵.1–4⁵.2 the composition guards | `cellarTests/TapSearchCompositionTests.swift` | `unit-app` | ✅ 260 distinct ids at `cbd13cb` (corrected by verify round 7) | ✅ **two reversible mutations**: (a) `fact("Homepage", published.tapName)` in the pane → `theNameOnlyTapDetailComposesNothingItCannotKnow` **failed**; (b) `let routable = true` in the projection → **4** `unit` ids failed with 6 issues. Both restored and verified `shasum -a 256 -c` → both files `OK` | ✅ **`** TEST SUCCEEDED **`, 260 distinct ids** | ➖ single scenario | ✅ the scan made case-insensitive after mutation (a) exposed the gap (deviation 2) |

**Test summary — round 6.** 6 tests written (5 `unit` in the new `TapInventoryDetailTests`, 1 `unit-app`),
2 existing `unit` tests replaced by reversed equivalents, 2 existing `unit-app` tests renamed/narrowed.
Layers: `unit` 5, `unit-app` 1. No approval tests — no refactoring task. Pure functions created: 1
(`TapInventoryDetail.resolve(_:in:installed:)`).

## Phase 6⁵ — verification and bindings

| Check | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,878 tests / 218 suites passed, 1 known issue** (baseline 1,873 / 217 → **+5 tests, +1 suite**; the flake did not recur in either post-GREEN run) |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 261 distinct test ids** (corrected by verify round 7; baseline 260 → **+1**, the one new `unit-app` test; no shipped id lost) |
| `cellar/Browse/BrowseView.swift` vs `main` | **byte-identical** (`git diff --quiet` clean) — **fifth** round running |
| `project.pbxproj`, `openspec/specs/`, `PackageSearchIndex.swift`, `MutationCommand.swift`, `MutationMenu.swift`, `cellarUITests/` vs `main` | **all empty** |
| `PackageRow.swift`, `StatusPill.swift` vs `cbd13cb` | **empty** — round 6 changes no mark and no pill |
| `cellar/Browse/PackageDetailView.swift` vs `main` | **NO LONGER ZERO-DIFF** — 5 hunks, **+37 / −9**: the `taps: TapStore` property, the third `body` branch, the header's doc comment and `versionStory: String?`, the conditional version line, and `taps: TapStore()` in the `#Preview`. Nothing else in the file moved; the catalog and receipt branches are untouched |
| `git diff --shortstat main...HEAD` | **30 files changed, 9,085 insertions(+), 64 deletions(-)** — reported, not trimmed, under the accepted `size:exception` |
| `git diff --shortstat main...HEAD -- ':!openspec'` | **20 files changed, 4,089 insertions(+), 64 deletions(-)** — the code-only half of the same total |
| `git diff --shortstat cbd13cb..HEAD -- ':!openspec'` | **10 files changed, 787 insertions(+), 43 deletions(-)** — round 6's own code cost |
| Working tree | clean at every commit; `cellar/InfoPlist.xcstrings` churn discarded, never committed |

Full `-scheme cellar` was **not** run: it is red on `main` from two pre-existing `cellarUITests` Taps
failures and is not this change's gate.

**The shortstat above is measured at `05b7b48`, before this record's own commit** — the same point every
earlier round measured at. Including this file, the branch total is **30 files changed, 9,256
insertions(+), 64 deletions(-)**. Both numbers are stated so neither has to be inferred.

## Deviations — round 6 (reported, not absorbed)

1. **The maintainer's projection sketch did not survive contact, and the contract was corrected before
   the code rather than after.** Two things changed, both in commit `2c69422`:
   - **`kind` is computed, not stored.** The brief listed it among the projection's members, but `id`
     already carries it and `id` is itself enumerated by `Mirror`. Storing a second copy would give one
     fact two homes and one chance to disagree — the drift DD-19's "stored, not computed" reasoning does
     **not** apply to, because that reasoning is about facts `Mirror` would otherwise miss.
   - **The collision note is not rendered, and its absence is asserted.** The brief allowed for it "only
     when applicable". It is applicable **never**: a colliding bare token is carried by the catalog, so
     `PackageDetailView`'s **first** branch resolves it and this third one is never reached. Rendering it
     would have been unreachable presentation — worse than none, because it could never be seen to be
     wrong. What the pane's "two copy strings" turned out to be is the install state and the footer.
2. **My first version of the field scan was case-sensitive, and the first mutation walked straight past
   it.** `fact("Homepage", …)` is not caught by a scan for `homepage`. The mutation exposed it, the scan
   now lowercases both sides, and the re-run failed as it should. Caught by the process, at the cost of
   one run — which is the process working.
3. **`PackageMetadataSection` was written into the pane and then removed.** Mirroring the receipt pane
   put the private-note section there by reflex. It is not a tap-published value and would have been
   defensible, but PS8 **enumerates** what this pane presents and closes the list, so adding a section
   to it is a product decision to take deliberately rather than inherit from a neighbouring file. Removed
   before the pane was committed, and the reason recorded in the file. The **favourite heart** is the one
   affordance that does arrive anyway: it belongs to the shared identity header the brief requires the
   pane to reuse.
4. **A shipped `unit-app` guard forbade `TapInventory` in `PackageDetailView.swift` and had to be
   narrowed.** `theTapSurfaceResolvesThroughTheSharedDetail` asserted the shared detail grew no branch
   for the tap surface — a claim round 6 partly overturns. It was **narrowed, not dropped**: the three
   tap-*search* tokens stay forbidden, and the one permitted inventory reference is now pinned positively
   (`TapInventoryDetail.resolve(` present, and the file naming `TapInventory` exactly once) so the
   narrowing cannot quietly widen. Caught by the runner.
5. **A function-level `-only-testing:` filter ran zero tests and reported success.**
   `-only-testing:cellarTests/TapSearchCompositionTests/theNameOnlyTapDetailComposesNothingItCannotKnow`
   matched no Swift Testing id, compiled everything, ran nothing, and exited `0` — which briefly read as
   a mutation surviving. The launch brief's rule ("suite-level filters for RED proofs") is exactly right
   and is why the discrepancy was checked rather than believed. Every RED and GREEN gate in this round is
   suite-level or whole-suite.
6. **The `cellarTests` baseline measured 259 where round 5 recorded 260**, by the same command and the
   same extraction. Reported above and not reconciled away; this round's arithmetic uses the number this
   run measured.
7. **`swift test --filter` was used for the RED/GREEN cycle and the whole package for the gate.** The
   filter is at **suite** level (`TapPackageSearchTests`, `TapInventoryDetailTests`), never function
   level, per the launch brief.

## Task ledger

**Round 6: 25 of 25 complete.** Round 6 has **no** delivery task — the branch's one open delivery box is
still round 2's **`6′.7`**, deferred by this run's explicit instruction not to push and not to open a
pull request. Round 5's ledger is unchanged at 19 of 19, round 4's at 22 of 22, round 3's at 24 of 24,
round 2's at 55 of 56, and round 1's 59 boxes are unchanged history with `6.7` void.

---

# Round 7 — colliding hits open the catalog detail

**Maintainer product decision (binding, 2026-08-25).** The **collision** half of round 6's ambiguity rule
is **reversed**. A hit whose bare token the catalog also carries is **selectable** and opens the
**catalog's own detail**: Homebrew resolves the bare token to the catalog package, which is exactly what
the row's own collision note already says, so the catalog pane is the package the row promises rather
than "a different package than the row chosen". `PackageDetailView` already resolves catalog-first, so
**no new branch** was needed — the hit simply became routable by its `PackageID`. The **only** remaining
inert case is a **duplicate `PackageID` among the emitted hits**, which nothing can disambiguate.

The production change is **one expression**: `TapPackageSearch.swift`'s
`let routable = collides == false && unique` → `let routable = unique`. `unique` keeps being counted over
**emitted tap hits only**, by the `occurrences` fold that already existed — a catalog record is not an
emitted hit. `alsoInCatalog` stays a fact and `collisionNote` stays pinned and required.

**Delivery.** `single-pr` with `size:exception` **accepted** (maintainer, 2026-08-25). Measured totals
are reported below and are **not** trimmed. RDD disabled. Strict TDD active throughout.

## Phase 0⁶ — baselines, measured at `6f18d2d`

| Runner | Baseline |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,878 tests / 218 suites** passed, 1 known issue, **no flake** |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 261 distinct test ids**, 0 failures |
| Working tree | clean after discarding `cellar/InfoPlist.xcstrings` churn |

The `cellarTests` baseline **matches verify round 7's corrected figure of 261 exactly**, and it was
reached by the counting rule the launch brief specifies rather than by a raw line count. The raw log
carried **271** `Test case '…'` occurrences, of which **270** parse cleanly to **260** distinct ids; the
one line that does not parse is corrupted mid-id by an interleaved xcodebuild status line
(`AutomaticUpdateChecksTests/aFreshInsta` + timestamp). Recovering that quoted prefix and testing its
membership against the cleanly parsed set shows it is **absent**, so it counts: **260 + 1 = 261**. The
core flake round 6 recorded (`MutationRefreshReceiptTests.swift:214`) did **not** recur in any run this
round.

## Commits

| Unit | Commit | What |
|---|---|---|
| WU25 | `917de65` | `docs(sdd): amend m11-tap-search so colliding tap hits open the catalog detail` — PS8's rewritten selectability clause, its colliding-route paragraph, the duplicate-only inert paragraph, the narrowed receipt/inventory-branch paragraphs and the corrected unreachable-note paragraph; two amended `unit` scenarios and one amended `unit-app` scenario; PD6's colliding-selection clause + `(Previously: …)` + one new `unit` scenario; `specs/README.md` revision 8; `design.md` (**DD-23**, round-7 preamble, file table, RED rows). **Delta specs only; `openspec/specs/**` untouched** |
| WU26 | `7fafcdb` | `feat(search): route a colliding tap hit to the catalog detail it resolves to` — `let routable = unique`, the comment above it and the two `routableID`/`isInstalled` doc comments restated; two test rows **replaced**, two amended, one new PD6 row |
| WU27 | `e7d203f` | `test(taps): pin that colliding tap rows open the catalog detail` — `TapSearchView`'s inert-row **comment** corrected (no behaviour line changed), the `unit-app` selection-rule scan's recorded reason restated to duplicate-only, the catalog-first ordering annotated as round 7's load-bearing assertion, and the design's mutation honesty note corrected (deviation 1) |
| — | (this record) | `docs(sdd): record the m11-tap-search round 7 apply progress` |

## Key design decision — DD-23

**Routability is uniqueness among the emitted hits, and nothing else.** Round 6 had already removed the
install state from the rule; round 7 removes the collision, leaving one conjunct. Three things make it
the smallest honest change available:

1. **The destination was already correct.** `DD-21` built the whole route — the identity handed over is
   the bare `PackageID`, and `PackageDetailView.body`'s first branch is `catalog.package(id)`, unchanged
   since m1. Both were already asserted. Round 7 stops withholding what they already resolve correctly.
2. **The collision note is not withdrawn.** It answers a **mutation** question — which package an
   install from this row installs — and that answer did not change. What changed is that the row now
   also *opens* that package, so the sentence and the route agree instead of competing.
3. **Uniqueness stays counted over emitted hits alone.** The `occurrences` fold is untouched. A catalog
   record is not a hit this source emits and is not counted against one — which is exactly why deleting
   the `collides` conjunct does not silently re-introduce it through the back door.

Rejected: a fourth branch or a `routesToCatalog` flag on the hit (the destination is the resolution
order's answer, not a fact the projection can know — a second opinion on it is the drift `DD-6`, `DD-7`
and `DD-21` were each written to prevent); withdrawing the collision note; keeping `collides` and
negating it only for the not-installed case (two rules where one will do); routing a colliding hit to
the **tap inventory** pane (it would present the tap's name-only facts for a package Homebrew will not
install from that tap — this round's own mismatch, inverted).

## Work unit evidence — round 7

| Unit | Focused test command and exact result | Runtime harness | Rollback boundary |
|---|---|---|---|
| **WU25** | N/A — artifacts only | N/A — no behaviour change | Revert `917de65`; the branch returns to `6f18d2d` |
| **WU26** | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` → RED **36 tests, 4 failed, 7 issues**, every one an *assertion* failure reading `routableID → nil`; after GREEN → **36 tests passed**. Whole package → **1,879 tests / 218 suites passed**, 1 known issue | **N/A, with reason.** No runtime boundary is added: the destination is the shipped catalog branch, whose rendering the round-6 app harness already exercised. Round 7 introduces no new pane, no new process call and no new store read | Revert `7fafcdb` across `TapPackageSearch.swift` and one test file |
| **WU27** | `xcodebuild test … -only-testing:cellarTests/TapSearchCompositionTests` under mutation → **`** TEST FAILED **`**, `theTapSearchSurfaceSelectsOnRoutabilityAlone()` failed; restored → whole suite `** TEST SUCCEEDED **`, **261 distinct ids**. `xcodebuild build …` → **`** BUILD SUCCEEDED **`** | N/A — source-scan suite | Revert `e7d203f` across one app file (comment only) and one test file; **no behaviour line is its own** |

## TDD cycle evidence — round 7

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 2⁶.1–2⁶.2 the routability rule | `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | Unit | ✅ 1,878 / 1,878 at `6f18d2d` | ✅ **written first**, run before any production edit: 4 tests failed with **7 assertion** failures, each printing `routableID → nil` against the expected `PackageID` — a reversed expectation, never a compile error | ✅ `let routable = unique` → 36/36 in-suite, **1,879** whole package | ✅ 5 fixtures in `onlyADuplicatedIdentityWithholdsTheRoute` — colliding+installed, colliding+absent, the duplicate pair, and an uncollided hit of **each** install state — so uniqueness is isolated against both retired variables; plus the collision/no-collision pair in `aCollidingHitIsShownAndIsRoutable` | ✅ the two `TapSearchHit` doc comments rewritten to the surviving rule; tests re-run green after |
| 2⁶.1 PD6's new row | same file | Unit | ✅ same baseline | ✅ **written first**, failed on `hit.routableID → nil` before the production change | ✅ passes; asserts the catalog's record is byte-identical to the one returned with no tap inventory resident | ✅ triangulated against the tap's *other* packages, which stay ordinary not-founds, and against the index record count and search results | ➖ none needed |
| 3⁶.1–3⁶.2 the app guard | `cellarTests/TapSearchCompositionTests.swift` | `unit-app` | ✅ 261 distinct ids at `6f18d2d` | ✅ **two reversible mutations**, proving different things (deviation 1): (a) `collides == false &&` restored in the projection → the 4 `unit` rows failed and the `unit-app` scan **did not**, which is correct and is why (b) exists; (b) `if let routable = hit.routableID, hit.alsoInCatalog == false` in the view → `theTapSearchSurfaceSelectsOnRoutabilityAlone()` **failed**. Both restored and verified `shasum -a 256 -c` → both files `OK` | ✅ `** TEST SUCCEEDED **`, 261 distinct ids | ➖ single scenario | ➖ none needed |

### Test summary — round 7

- **Tests written**: 1 new (`aCollidingSelectionResolvesToTheCatalogsOwnRecord`), 2 **replaced**
  (`aCollidingHitIsShownAndIsNotRoutable` → `…IsRoutable`;
  `anAmbiguousHitIsNotRoutableInEitherInstallState` → `onlyADuplicatedIdentityWithholdsTheRoute`),
  2 amended in place (`aCollidingCatalogReceiptIsNeverAttachedToATapRow`'s two routability lines only;
  `theTapSearchSurfaceSelectsOnRoutabilityAlone`'s recorded reason).
- **Unchanged and deliberately so**: `twoTapsPublishingOneNameAreBothUnroutable` needed **no edit at
  all** — which is itself the evidence that the rule narrowed rather than vanished.
- **Counts**: CellarCore **1,878 → 1,879** (+1: two replaced by two, plus PD6's new row).
  `cellarTests` **261 → 261** — round 7 adds no `unit-app` test, exactly as `DD-23` predicted, because
  the view needed no edit and the catalog-first assertion it depends on was already pinned.
- **Layers used**: Unit (3 touched, 1 new), `unit-app` (1 amended).
- **Pure functions created**: 0 — the change is a deleted conjunct inside an existing pure projection.

## Phase 6⁶ — verification and bindings

| Gate | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **`Test run with 1879 tests in 218 suites passed`**, 1 known issue (baseline **1,878** → **+1**; no shipped test lost) |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 261 distinct test ids**, 0 failures (baseline **261** → **±0**). Both runs' id sets **union to exactly 261**, each losing a different single id to an interleaved status line (baseline: `AutomaticUpdateChecksTests/aFreshInstallReadsAsOff()`; final: `BrewfileExportCompositionTests/aFailedDumpNeverOpensAPanelAndNeverWrites()`), so the sets are provably identical rather than merely equal in size |
| `xcodebuild build …` | **`** BUILD SUCCEEDED **`** |
| Bindings — zero-diff vs `main` | `git diff --stat main --` printed **nothing** for `cellar/Browse/BrowseView.swift` (**DD-8**, sixth round running), `cellar/Activity/MutationMenu.swift`, `cellar.xcodeproj/project.pbxproj`, `openspec/specs/`, `PackageSearchIndex.swift`, `MutationCommand.swift` and `cellarUITests/` |
| Bindings — `PackageDetailView.swift` | `git diff --stat 6f18d2d -- cellar/Browse/PackageDetailView.swift` printed **nothing**: the file changed in round 6 and is **unchanged this round**. `DD-23` adds no branch, so the shared detail is untouched — the claim is "unchanged since `6f18d2d`", not "byte-identical to `main`" |
| Files changed this round (`6f18d2d...HEAD`) | **9 files, +550 / −141** — of which **4** are docs artifacts. The production diff is `TapPackageSearch.swift` (one expression plus comments) and `TapSearchView.swift` (**comment only**) |
| `git diff --shortstat main...HEAD` | **30 files changed, 9,720 insertions(+), 64 deletions(-)** — **9,784 changed lines**, measured at `e7d203f`, i.e. the commit immediately **before** this record. Reported under the accepted `size:exception` and **not trimmed**. Adding this record itself takes it to **+9,876 / −64 = 9,940**; both figures are given because a progress record cannot measure itself without circularity, and rounds 2–6 all used the same before-the-record convention |
| Working tree | clean; `cellar/InfoPlist.xcstrings` churn discarded and never committed |

## Deviations — round 7 (reported, not absorbed)

1. **The design's mutation honesty note was wrong when first written, and was corrected in WU27.** It
   claimed that restoring `collides == false &&` in the projection "is what proves the `unit-app` scan
   still bites". It is not: that scan reads **app sources only** and is structurally blind to a
   CellarCore edit. Running it confirmed this — the projection mutation failed 4 `unit` rows and left
   the `unit-app` suite green. The round therefore needs **two** mutations, and both were run: the
   projection one for the `unit` rows, and a **view** one (`hit.alsoInCatalog == false` added to the
   selection gate) for the `unit-app` forbidden-token scan, which failed exactly as it should. Corrected
   in `design.md` and in `tasks.md` step `3⁶.3` before the commit that depended on them, rather than
   left as a claim no run supports.
2. **`TapSearchView.swift` was edited, though the brief said it might need no change.** The brief's
   condition — "needs no change **if** it keys `.selectionDisabled` on `routableID == nil`" — held, and
   **no behaviour line changed**. What changed is the inert-row **comment**, which round 6 had restated
   to name the catalog collision as a bar. That sentence is now false, and a comment asserting a retired
   rule beside the code that no longer implements it is exactly the drift these files are scanned for.
3. **Two `routableID == nil` assertions inside `aCollidingCatalogReceiptIsNeverAttachedToATapRow` had to
   move**, though the brief listed that row as "unchanged". Its **subject** is unchanged and was
   verified so: the tap row still carries its own receipt or none, never the catalog's, and every
   assertion about the receipt keying (**DD-20**) is byte-identical. Only the two lines that pinned the
   *retired routability rule* moved, because they were the retired rule stated inside a row about
   something else. Reported rather than silently absorbed.
4. **PS8's "unreachable collision note" paragraph contained a claim that round 7 falsifies**, and was
   rewritten. It justified the name-only pane's absent collision note with **two** reasons — the catalog
   branch resolves first, *and* the colliding row is unroutable. The second is now false. The paragraph
   now says the branch **ordering** is the sole guarantee and notes that it is sufficient because that
   ordering is itself asserted, in `theNameOnlyTapDetailComposesNothingItCannotKnow`.
5. **`specs/README.md`'s "Excluded from these deltas" list still claimed the name-only pane was out of
   scope** — stale since round 6 shipped it. Struck through and annotated rather than deleted, because
   that list is the record of what each slice deliberately left out; deleting the entry would erase the
   fact that the exclusion existed and stopped being true. Flagged as a **round-6 miss corrected in
   round 7**, not as round-7 work.
6. **`swift test --filter` was used at suite level for the RED/GREEN cycle**, never function level, and
   the whole package for the gate — per the launch brief and round 6's own deviation 5.

## Task ledger

**Round 7: 24 of 24 complete.** Round 7 has **no** delivery task — the branch's one open delivery box is
still round 2's **`6′.7`**, deferred by this run's explicit instruction not to push and not to open a
pull request. Round 6's ledger is unchanged at 25 of 25, round 5's at 19 of 19, round 4's at 22 of 22,
round 3's at 24 of 24, round 2's at 55 of 56, and round 1's 59 boxes are unchanged history with `6.7`
void.

## Phase 0⁷ — baselines, measured at `e0e9ce5`

| Runner | Baseline |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,879 tests / 218 suites** passed, 1 known issue |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 261 distinct test ids**, 0 failures |
| Working tree | clean after discarding `cellar/InfoPlist.xcstrings` churn |

The CellarCore baseline is round 7's final figure exactly (**1,879**, up from round 7's own 1,878
starting point). **One transient failure is reported, not hidden**: the *first* baseline run answered
`1879 tests … failed … with 2 issues (including 1 known issue)`, i.e. one real issue beyond the known
one. Only the tail was captured, so the failing row's identity was lost; **two** subsequent full runs
passed cleanly at 1,879 / 1 known issue, and a third was captured to a full log and also passed. It is
recorded here as an **unidentified transient**, which is the honest shape — round 6 recorded a core
flake at `MutationRefreshReceiptTests.swift:214` and it did not recur this round either.

The `cellarTests` baseline of **261** was reached by the counting rule, not by a raw line count: the log
carried **271** `Test case '…'` occurrences, of which **270** parse to **260** distinct ids; the one
corrupted line is `BrewfileCompositionTests/skipsAreGroupedCountedAndName` + an interleaved xcodebuild
status line, and that id is **absent** from the cleanly parsed set, so **260 + 1 = 261**.

## Commits

| Unit | Commit | What |
|---|---|---|
| WU28 | `2bf6081` | `docs(sdd): amend m11-tap-search so tap detail panes show the shared actions section` — PS8's rewritten pane clause with its `(Previously: …)` line and its amended `unit-app` pane-composition scenario; a **new** `specs/installed-inventory/spec.md` carrying MODIFIED **II15**; `specs/README.md` revision 9 (new capability row, corrected “activated, not changed” section, new reversed presentation-decision row); `design.md` (**DD-24**, round-8 preamble, file table, RED rows). **Delta specs only; `openspec/specs/**` untouched** |
| WU29a | `d1781a7` | `refactor(browse): build the detail actions section from a package entry` — `actionsSection(for entry: PackageEntry)`, `internal`; `primaryCommand(for entry:target:)` reading `entry.installed`; the catalog call site becomes `actionsSection(for: entry(for: package))`. **One file** |
| WU29b | `c887078` | `feat(browse): show the shared actions section on tap-backed detail panes` — both panes pass `EmptyView()` as `primaryButton`, drop `MutationMenu`, and call the shared builder as the **last** block of their scroll content |
| WU30 | `92c4262` | `test(browse): pin the shared actions section on tap-backed detail panes` — `ReceiptDetailCompositionTests`'s verb row **replaced**; `TapSearchCompositionTests`'s pane row item 4 amended |
| — | (this record) | `docs(sdd): record the m11-tap-search round 8 apply progress` |

## Key design decision — DD-24

**The signature was simply older than the type.** `actionsSection` never read a catalog *field*: every
input it had was `PackageTarget(package.id)`, `FormulaID(package.id)`, `CaskID(package.id)`,
`entry(for: package)` and `installed.inventory.package(package.id)` — an **identity** and an
**installed record**, which is exactly what `PackageEntry` has carried since the Installed list
shipped. Rebuilding it from the entry is therefore a signature catching up with its own body, not a
generalisation invented for the tap panes, and that is what makes "one component" literally true rather
than aspirational. Three consequences worth recording:

1. **`entry.catalog` is read by nothing inside the section**, so the panes lose nothing by having none
   — and PD6's prohibition on synthesizing a catalog record is satisfied by construction rather than by
   a rule someone has to remember.
2. **Only the declaration is relaxed.** `submit`, `quietButton`, `accentButton`, `dangerButton`,
   `snoozeButton` and `primaryCommand` all stay `private`: they are called from inside the same file,
   so the surface area exposed to the extensions is exactly one function. This is **DD-18**'s precedent
   applied a third time, and the cheapest instance of it yet — no file is created and nothing moves.
3. **The header slot going empty is half the instruction, not a side effect.** One pane offers one
   place to act; leaving the menu *and* adding the section would have been the reported defect stated
   twice.

Rejected: copying the section into each pane (three declarations of one verb set — the drift **DD-18**
exists to end and the drift II15's clause forbids in words); extracting it to a third file as
`StatusPill` was extracted (its body calls six `private` helpers and reads four stored properties, so
extraction means moving or threading all of them — a large diff to reach a shape `internal` already
reaches); a `CatalogPackage?` parameter the panes would always pass `nil` for; a protocol over "things
with an id and an installed record", which `PackageEntry` already is.

## Work unit evidence — round 8

| Unit | Focused test command and exact result | Runtime harness | Rollback boundary |
|---|---|---|---|
| **WU28** | N/A — artifacts only | N/A — no behaviour change | Revert `2bf6081`; the branch returns to `e0e9ce5` |
| **WU29a** | `xcodebuild build …` → **`** BUILD SUCCEEDED **`**; `xcodebuild test … -only-testing:cellarTests` → **260 clean distinct ids**, the **only** two failures being the round-8 RED rows written before the edit; every other app-suite row passed, which is the approval evidence that the refactor preserved behaviour | **N/A, with reason.** No runtime boundary is added: the section, its verbs, its argv and its confirmation rule are the shipped ones, exercised by the catalog pane's own suite on every run | Revert `d1781a7`; one file, and the panes are untouched at that commit |
| **WU29b** | `xcodebuild build …` → **`** BUILD SUCCEEDED **`**; `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`**, both RED rows now green | N/A — same reason | Revert `c887078`; both panes return to the header menu with no other file touched |
| **WU30** | `xcodebuild test … -only-testing:cellarTests/ReceiptDetailCompositionTests -only-testing:cellarTests/TapSearchCompositionTests -only-testing:cellarTests/PerPackageTrustCompositionTests` → **`** TEST SUCCEEDED **`**; under each mutation → **`** TEST FAILED **`** | N/A — source-scan suites | Revert `92c4262`; two test files, **no production line is its own** |

## TDD cycle evidence — round 8

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 3⁷.1 the receipt pane's Actions section | `cellarTests/ReceiptDetailCompositionTests.swift` | `unit-app` | ✅ 261 distinct ids at `e0e9ce5` | ✅ **written first, before any production edit**, and failed as a **genuine** RED rather than a mutation one: the row references `actionsSection(for entry: PackageEntry)`, which did not exist, so `ReceiptDetailSources.actionsSection(in:)`'s `#require` threw. Exactly **one** row in the suite failed; the other six passed | ✅ after `d1781a7` the section exists and after `c887078` the pane calls it → whole suite `** TEST SUCCEEDED **` | ✅ two reversible mutations, proving **different halves** of "one component, one place": (a) `MutationMenu(center: operations, entry: …)` re-added to a pane → the `MutationMenu(` absence assertion failed; (b) `Button("Reinstall") { }` added to a pane → the verb-literal absence assertion failed. Both restored and verified `shasum -a 256 -c` → both panes `OK` | ✅ the verb list extracted to `ReceiptDetailSources.verbLiterals` and the section extracted by brace matching, so `PackageDetailView.swift`'s legitimate trust marker and catalog type are not swept into a claim about the section |
| 3⁷.2 the name-only pane's Actions section | `cellarTests/TapSearchCompositionTests.swift` | `unit-app` | ✅ same baseline | ✅ **written first**; failed on the absent `actionsSection(for: publishedEntry(for: published))` call. Exactly one row in the suite failed | ✅ green after `c887078` | ✅ the same two mutations bite this row too — recorded once, run once, and both rows named in each failure list | ➖ none needed; the row was amended in place and its entry assertion is byte-unchanged |
| 2⁷.2 the entry-shaped section | `cellarTests` (whole suite, as approval tests) | `unit-app` | ✅ 261 distinct ids | ✅ **approval testing**, per the strict-TDD module's refactoring path: the shipped suite describes current behaviour, and it was run before the edit | ✅ after the refactor the whole suite passed **except** the two rows already RED for the feature — no shipped row changed verdict | ➖ N/A — a refactor triangulates nothing new | ✅ the section's body is byte-unchanged apart from `package.id` → `entry.id`; every label, `detail-action-*` identifier, argv and ordering is identical, shown in full in the bindings proof |

### Test summary — round 8

- **Tests written**: 1 **replaced** (`theReceiptPaneOffersTheSameVerbsAsTheRow` →
  `theReceiptPaneOffersTheCatalogPanesActionsSection`), 1 **amended in place**
  (`theNameOnlyTapDetailComposesNothingItCannotKnow`, item 4 only).
- **Counts**: CellarCore **1,879 → 1,879** (±0 — round 8 touches no CellarCore file at all, proven by an
  empty `git diff --stat e0e9ce5 -- Packages/CellarCore`). `cellarTests` **261 → 261**, the difference
  between the two id sets being **exactly** the one rename.
- **Layers used**: `unit-app` (2 touched, 0 net new), Unit (0 — nothing in CellarCore moves).
- **Pure functions created**: 0. **Visibility relaxed**: 1 declaration, `actionsSection`.

## Phase 6⁷ — verification and bindings

| Gate | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **`Test run with 1879 tests in 218 suites passed`**, 1 known issue (baseline **1,879** → **±0**) |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 261 distinct test ids**, 0 failures (baseline **261** → **±0**). Each run loses a different single id to an interleaved status line — baseline `BrewfileCompositionTests/skipsAreGroupedCountedAndNamed()`, final `AutomaticUpdateChecksTests/turningItOffRecordsAStoredFalse()` — and **each missing id is present in the other run's clean set**, so both runs provably enumerate 261. The only genuine set difference is the one rename, in **both** directions: the old id appears only in the baseline, the new one only in the final run |
| `xcodebuild build …` | **`** BUILD SUCCEEDED **`** |
| Bindings — zero-diff vs `main` | `git diff --stat main --` printed **nothing** for `cellar/Browse/BrowseView.swift` (**DD-8**, seventh round running), `cellar/Activity/MutationMenu.swift`, `cellar.xcodeproj/project.pbxproj`, `openspec/specs/`, `PackageSearchIndex.swift`, `MutationCommand.swift` and `cellarUITests/` |
| Bindings — CellarCore | `git diff --stat e0e9ce5 -- Packages/CellarCore` printed **nothing**: round 8 is presentation only, so no projection, fact or copy moves |
| Bindings — `PackageDetailView.swift` | `git diff main --` shown in full: round 6's four hunks (`let taps`, the third branch, the widened `versionStory`, the preview) plus round 8's refactor and the one relaxed `private`. **+55 / −18.** Every verb label, every `detail-action-*` identifier, every command family and the section's internal order are **byte-unchanged** — the diff inside the section is `package.id` → `entry.id` and nothing else |
| Files changed this round (`e0e9ce5..HEAD`) | **10 files, +685 / −53** — of which **5** are docs artifacts (**+487**) and one is the new II15 delta alone (**+252**). The production diff is **three files, +69 / −27** |
| `git diff --shortstat main...HEAD` | **33 files changed, 10,370 insertions(+), 93 deletions(-)** — **10,463 changed lines**, measured at `92c4262`, i.e. the commit immediately **before** this record. Reported under the accepted `size:exception` and **not trimmed**. Adding this record itself takes it to **+10,511 / −93 = 10,604**; both figures are given because a progress record cannot measure itself without circularity, and rounds 2–7 all used the same before-the-record convention |
| Working tree | clean; `cellar/InfoPlist.xcstrings` churn discarded at phase 0⁷ and never committed |

## Deviations — round 8 (reported, not absorbed)

1. **A `MODIFIED II15` delta was required, and the brief's condition for it was met on a reading the
   brief did not spell out.** The brief said to add the delta "if it pins `MutationMenu` or the header
   slot". II15 names **neither** literally. What it does pin is the **source**: "the same mutation verbs
   the installed list row offers … obtained from the same shared mutation surface". Presenting the
   catalog pane's Actions section changes that source, and the verb *sets* are not identical either —
   the section adds snooze and labels the pin verb `Pin version` where the menu says `Pin`, and it shows
   a command **line** where the menu offers `Copy install command`. So the clause was contradicted, not
   merely re-styled, and the delta is mandatory. Recorded because "it does not name `MutationMenu`" was
   a reachable and wrong conclusion.
2. **The RED was genuine, not mutation-based — a change from rounds 3–7.** Both guard rows were written
   and run **before** any production edit and failed on production that did not exist yet. The two
   mutations were still run afterwards, because a genuine RED proves the row bites on *absence* while
   the mutations prove it bites on the two ways the absence could be reintroduced. Both are reported.
3. **`WU29` shipped as two commits, as the brief specified**, and the intermediate commit is green on
   its own terms: at `d1781a7` the panes still hang the menu, the two guard rows were **uncommitted**,
   and the whole app suite passes. The guard rows landed with `92c4262`. Test-first authoring and
   commit order are independent, and the record says which is which rather than implying the tests were
   written last.
4. **`primaryCommand`'s source of truth narrowed, and it is a genuine simplification rather than a
   no-op.** It read `installed.inventory.package(package.id)` directly; it now reads `entry.installed`.
   For the catalog pane the two are the same value by construction — `entry(for:)` builds that member
   from that exact lookup — but the new shape means the panes cannot get a *different* answer from the
   command line than from the buttons above it, which the old shape could not have promised for an
   entry built anywhere else.
5. **One transient CellarCore failure at phase 0⁷ is reported unidentified** (see the baseline table).
   It did not recur across three subsequent full runs, and the final gate is clean at 1,879.
6. **`specs/README.md`'s "activated, not changed" section for `installed-inventory` was stale the
   moment this delta was written**, and was corrected rather than left: II7 and II8 are still
   activation-only, II15 is not.

## Task ledger

**Round 8: 26 of 26 complete.** Round 8 has **no** delivery task — the branch's one open delivery box is
still round 2's **`6′.7`**, deferred by this run's explicit instruction not to push and not to open a
pull request. Round 7's ledger is unchanged at 24 of 24, round 6's at 25 of 25, round 5's at 19 of 19,
round 4's at 22 of 22, round 3's at 24 of 24, round 2's at 55 of 56, and round 1's 59 boxes are
unchanged history with `6.7` void.

# Round 9 — icon tiles on tap rows

**Change**: `m11-tap-search` · **Mode**: Strict TDD · **Round 9** (maintainer UI feedback, final)
**Branch**: `feat/m11-tap-search`, from `2548e40`. **Delivery**: `single-pr` with `size:exception`
**accepted** (maintainer, 2026-08-25) — the measured total is reported below and is **not** trimmed.
RDD disabled. Not pushed; no pull request opened.

**The instruction.** In the “Search our taps” list the rows must show the **same leading icon tile
Browse rows show** — the default formula glyph for formulae, the default colour + initial letter tile
for casks. `PackageRow.swift:34` and `InstalledRow.swift:34` both draw
`PackageIconTile(id: entry.id, assets: assets, iconLoader: iconLoader)`; `TapSearchView`'s row drew no
tile at all.

## Phase 0⁸ — baselines, measured at `2548e40`

| Gate | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **`Test run with 1879 tests in 218 suites passed`**, 1 known issue → baseline **1,879** |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`** → baseline **261 distinct ids** (260 cleanly parsed; one lost to an interleaved `xcodebuild` status line that truncated it to `Test case 'Brewfil…`, recovered by membership from the final run as `BrewfileCompositionTests/missingRowsArriveSelectedAndPresentRowsAreNot()`) |
| Working tree | clean; `cellar/InfoPlist.xcstrings` churn discarded before any edit and never committed |

## Work units — round 9

| Unit | Commit | What landed |
|---|---|---|
| **WU31** | `db5d2f7` `docs(sdd): amend m11-tap-search so tap rows carry the shared icon tile` | PS8's new leading-tile clause and its **new** `unit-app` scenario (the delta's only count movement: 22 → **23** added, 41 → **42** scenarios, `unit-app` 8 → **9**); `specs/README.md` revision **10** with the re-footed arithmetic and the new decision row; `design.md` **DD-25**, the round-9 preamble, file table and RED rows; `tasks.md` round 9 |
| **WU32** | `2e0d5c9` `feat(taps): draw the shared package icon tile on tap search rows` | `TapSearchView` gains `var assets: CaskBrowseAssets?` and `var iconLoader: CaskIconLoader?`; `row(_:)` binds the entry once, nests an `HStack(spacing: 10)` and draws the shared tile first; `MutationMenu` takes the same bound entry; `ContentView`'s one call site passes `caskAssets` / `caskIcons` |
| **WU33** | `e5939d6` `test(taps): pin the shared icon tile on tap search rows` | `bothSearchSurfacesDrawTheOneSharedIconTile` — the guard |

## Phase 2⁸.1 — the component's fallback, verified before it was relied on

The brief asked what `PackageIconTile` renders for a tap cask with **no** catalog record, and said to
fix the fallback minimally if it did not degrade to the letter tile. It was read, not assumed:

1. `PackageIconTile` (`cellar/Casks/CaskIconView.swift:68-95`) branches on `id.kind` **only** — never on
   a catalog record. A `.formula` takes `FormulaIconTile(size:)`, the bundled glyph, unconditionally.
2. A `.cask` with a non-`nil` loader takes `CaskIconView`, passing
   `isKnownToken: assets?.isKnownIconToken(id.name) ?? false` — `false` both for an unloaded catalog and
   for a token the catalog does not list, which is every third-party tap cask.
3. `CaskIconURL.candidateURLs(for:isKnownToken: false)` drops the two CaskFlow rungs and returns the
   App-Fair URL alone; a miss is stamped and answers `nil`.
4. `CaskIconView`'s `nil`-icon branch renders `PackageTile(name: token, …)` — the **coloured initial
   tile**, which is exactly the required default.

**No fix was required, and `cellar/Casks/**` carries a zero-line diff this round.** The letter tile for
a tap cask is the component's designed answer, not a degradation.

## TDD Cycle Evidence — round 9

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 3⁸.1 the shared icon tile on the tap rows | `cellarTests/TapSearchCompositionTests.swift` | `unit-app` | ✅ 261 distinct ids at `2548e40`; the suite's other 15 rows green | ✅ **written first, before any production edit**, and a **genuine** RED rather than a mutation one: `** TEST FAILED **` with **6** recorded issues in exactly one row — the absent call text, the absent `let entry = entry(for: hit)`, the absent `MutationMenu(center: operations, entry: entry)`, both absent property declarations, and the leading-position `#require` throwing. The other **15** rows passed | ✅ after `2e0d5c9` the whole suite is `** TEST SUCCEEDED **`, 16/16 rows | ✅ **one reversible mutation**: the tile replaced by `Image(systemName: "shippingbox")` → **3** recorded issues at once — the call-text equality, the no-local-artwork prohibition and the leading-position `#require`. Restored and verified `shasum -a 256 -c` → `cellar/Browse/TapSearchView.swift: OK` |  ✅ the prohibition loop was **moved above** the first `#require` after the first mutation run proved it unreachable behind a throw (see deviation 2), and the row re-run green before the mutation was repeated |

### Test summary — round 9

- **Tests written**: 1 **new** (`bothSearchSurfacesDrawTheOneSharedIconTile`). None replaced, none deleted.
- **Counts**: CellarCore **1,879 → 1,879** (±0 — round 9 touches no CellarCore file, proven by an empty
  `git diff --stat 2548e40 -- Packages/CellarCore`). `cellarTests` **261 → 262**, the set difference
  being **exactly** the one new id.
- **Layers used**: `unit-app` (1 new), Unit (0 — nothing in CellarCore moves).
- **Pure functions created**: 0. **Visibility relaxed**: 0. **Components edited**: 0 — the tile, its
  loader, its asset store and its URL ladder are all untouched.

## Phase 6⁸ — verification and bindings

| Gate | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **`Test run with 1879 tests in 218 suites passed`**, 1 known issue (baseline **1,879** → **±0**) |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 262 distinct test ids**, 0 failures (baseline **261** → **+1**). 261 ids parsed cleanly; the run lost one to an interleaved status line (`Test case 'BrewfileCompositionTests/aTrustedClaimIsSurfa…`), recovered by membership from the baseline's clean set. Each run's lost id is present in the other run's clean set, so both runs provably enumerate their full totals. `comm` over the two clean sets shows exactly one genuine addition: `TapSearchCompositionTests/bothSearchSurfacesDrawTheOneSharedIconTile()` — the +1 `unit-app` scenario, and nothing else |
| `xcodebuild build …` | **`** BUILD SUCCEEDED **`** |
| Bindings — unchanged since `2548e40` | `git diff --stat 2548e40 --` printed **nothing** for `cellar/Browse/PackageRow.swift`, `cellar/Browse/BrowseView.swift`, `cellar/Activity/MutationMenu.swift`, **the whole of `cellar/Casks/`** (so `PackageIconTile`, `CaskIconView`, `CaskIconLoader` and `CaskBrowseAssets` are provably unedited), `cellar.xcodeproj/project.pbxproj`, `openspec/specs/`, `cellarUITests/` and `Packages/CellarCore/` (which carries `PackageSearchIndex.swift` and `MutationCommand.swift`) |
| Bindings — zero-diff vs `main` | `git diff --stat main --` printed **nothing** for `cellar/Browse/BrowseView.swift` (**DD-8**, eighth round running), `cellar/Activity/MutationMenu.swift`, `cellar/Casks/`, `cellar.xcodeproj/project.pbxproj`, `openspec/specs/`, `Packages/CellarCore/Sources/Catalog/PackageSearchIndex.swift`, `Packages/CellarCore/Sources/BrewClient/MutationCommand.swift` and `cellarUITests/`. **`cellar/Browse/PackageRow.swift` is the one exception, and it is not round 9's** — see deviation 1 |
| `PackageIconTile` fallback diff | **None.** The component required no fix; the round-9 diff under `cellar/Casks/` is zero lines |
| Files changed this round (`2548e40..HEAD`) | **7 files, +396 / −50** — of which 4 are docs artifacts (**+217 / −10**). The production diff is **two files, +75 / −40**, and `TapSearchView.swift` alone is **+73 / −40** raw but **+35 / −2** ignoring whitespace: 38 of those lines are the re-indentation the nested `HStack` forces (deviation 3) |
| `git diff --shortstat main...HEAD` | **33 files changed, 10,930 insertions(+), 93 deletions(-)** — **11,023 changed lines**, measured at `e5939d6`, i.e. the commit immediately **before** this record. Reported under the accepted `size:exception` and **not trimmed**. Adding this record itself takes it to **+11,060 / −93 = 11,153** (measured after the commit, not estimated before it); both figures are given because a progress record cannot measure itself without circularity, and rounds 2–8 all used the same before-the-record convention |
| Working tree | clean; no `cellar/InfoPlist.xcstrings` churn appeared this round and none was committed |

## Deviations — round 9 (reported, not absorbed)

1. **`cellar/Browse/PackageRow.swift` is *not* zero-diff against `main`, and the brief's bindings list
   said it should be.** It carries **+6 / −27** against `main`, entirely from **round 3**'s commit
   `30608ab`, which extracted the row's private `statusPill(_:background:foreground:)` into the shared
   `StatusPill` component so both search surfaces could draw one installed mark. That is the diff **DD-18**
   exists to have produced. Round 9 touches the file not at all: `git diff --stat 2548e40 -- cellar/Browse/PackageRow.swift`
   prints nothing. The honest binding for this round is therefore "**unchanged since `2548e40`**", which
   holds, and the "zero-diff vs `main`" phrasing is recorded here as inapplicable to that one file rather
   than quietly satisfied. Every other file on the list *is* zero-diff against `main`.
2. **The first mutation run proved less than the design claimed, and the test was fixed rather than the
   claim softened.** The design's RED row said the mutation must fail "the call-text equality *and* the
   no-local-image prohibition". The first run recorded only **2** issues, because the prohibition loop sat
   **after** `try #require(surface.code.range(of: call))` — which throws under the mutation and ends the
   row before the loop runs. A prohibition reachable only while the file is already correct proves
   nothing. The loop was moved above the `#require`, the row re-run green, and the mutation repeated:
   **3** issues, the prohibition among them. `design.md` and `tasks.md` were corrected in the commit that
   carries this record, and the sequence is reported rather than presented as having worked first time.
3. **`TapSearchView.swift`'s diff is far larger than the design's `+14 / −4` estimate, and almost all of
   it is whitespace.** Measured **+73 / −40**; `git diff -w` measures **+35 / −2**. The gap is the
   re-indentation forced by nesting the row's text column inside a new `HStack(spacing: 10)`. The nesting
   itself is deliberate: `PackageRow` puts **10** points between the tile and the name while the tap row's
   outer stack uses **6** for the menu, so flattening would have drawn the tile 4 points closer to the
   name than the surface it is copying — a visible mismatch on the one thing this round exists to match.
   The file table now records the measured figure and its whitespace share.
4. **The forbidden-token list had to exclude `systemImage:`, which the design and tasks first named.**
   `TapSearchEmptyState` has passed `systemImage:` to `ContentUnavailableView` since round 2; forbidding
   it would have failed the row on shipped, correct code. The list is `Image(`, `PackageTile(`,
   `FormulaIconTile(`, `CaskIconView(`, `Theme.tile(` — every way this file could draw artwork itself,
   and no way it could not. Corrected in both artifacts, with the reason stated in the test's own comment.
5. **No `.task { await assets?.load() }` was added, unlike `BrowseView`.** Two reasons, both binding:
   PS8's process-layer scenario scans this exact file for `.task`, `await ` and `async ` (**DD-12**), and
   the asset catalog gates only the CaskFlow rungs for tokens it lists — never a third-party tap's cask —
   so the load would change no pixel on this surface. The store is handed through and the component asks;
   every other cask surface already calls the idempotent `load()`.
6. **`WU32` shipped before `WU33` in commit order, and the test was still written first.** The guard row
   was authored and run to a genuine 6-issue RED **before** any production line existed; it was committed
   after the feature so that each commit carries one kind of change. Authoring order and commit order are
   independent, and this record says which is which rather than letting the log imply the tests came last.

## Task ledger

**Round 9: 24 of 24 complete.** Round 9 has **no** delivery task — the branch's one open delivery box is
still round 2's **`6′.7`**, deferred by this run's explicit instruction not to push and not to open a
pull request. Round 8's ledger is unchanged at 26 of 26, round 7's at 24 of 24, round 6's at 25 of 25,
round 5's at 19 of 19, round 4's at 22 of 22, round 3's at 24 of 24, round 2's at 55 of 56, and round 1's
59 boxes are unchanged history with `6.7` void.

## Delivery (task 6′.7 — done)

Pushed `feat/m11-tap-search` and opened https://github.com/juancasanueva/SWIFTUI_cellar/pull/77 against `main` after verify round 11 (PASS WITH WARNINGS, 56/56), under the maintainer-accepted `size:exception`. The PR body discloses the exception, the scoped runners, the pre-existing Taps UI failures, and the four capability deltas.
