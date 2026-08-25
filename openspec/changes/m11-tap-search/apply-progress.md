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
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 259 distinct test ids** |
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
| **WU24** | `05b7b48` | `xcodebuild test … -only-testing:cellarTests` → **`** TEST SUCCEEDED **`, 260 distinct ids** | N/A — source-scan suite; the app harness is WU23's | Revert one test commit; no production line is its own |

## TDD cycle evidence — round 6

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 2⁵.1–2⁵.2 `routableID` | `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | `unit` | ✅ 1,873 / 217 at `cbd13cb` | ✅ **assertion** failures, 3 across 2 ids — `aNotInstalledHitIsRoutableWhenItsIdentityIsUnambiguous` at `:912` and `:913`, `anAmbiguousHitIsNotRoutableInEitherInstallState` at `:850` (`unambiguousAbsent.routableID → nil`) | ✅ filtered **35 / 1 suite passed** | ✅ 5 cases in one row — installed-and-colliding, not-installed-and-colliding, duplicate identity, and an unambiguous positive of **each** install state. The last two are the triangulation that matters: without them the three `nil`s would also pass under the retired rule | ➖ none needed — one conjunct deleted |
| 2⁵.3–2⁵.4 `TapInventoryDetail` | `Packages/CellarCore/Tests/BrewClientTests/TapInventoryDetailTests.swift` (new) | `unit` | N/A (new file) | ✅ **compile** failure, `TapInventoryDetailTests.swift:26:10: error: cannot find type 'TapInventoryDetail' in scope` (and 3 more sites) | ✅ filtered **5 / 1 suite passed**; whole core suite **1,878 / 218 passed** | ✅ 5 cases — one publisher, a cask on the same rule, zero/several/official publishers, a held receipt (installed **and** withheld), each with its own inverted triangulation | ✅ the resolution reads `TapProjection.publishes` and `packages(for:)` rather than re-deriving either; `kind` computed off `id` rather than stored beside it |
| 3⁵.1–3⁵.6 the app surface | — | build | ✅ `** BUILD SUCCEEDED **` at `74560ae` | ✅ **compile** failure at the preview call site — `cannot use explicit 'return' statement in the body of result builder 'ViewBuilder'`, the compiler's phrasing for the missing `taps:` argument | ✅ `** BUILD SUCCEEDED **` | ➖ single construction site | ✅ `PackageMetadataSection` removed after review against PS8's closed list (deviation 3) |
| 4⁵.1–4⁵.2 the composition guards | `cellarTests/TapSearchCompositionTests.swift` | `unit-app` | ✅ 259 distinct ids at `cbd13cb` | ✅ **two reversible mutations**: (a) `fact("Homepage", published.tapName)` in the pane → `theNameOnlyTapDetailComposesNothingItCannotKnow` **failed**; (b) `let routable = true` in the projection → **4** `unit` ids failed with 6 issues. Both restored and verified `shasum -a 256 -c` → both files `OK` | ✅ **`** TEST SUCCEEDED **`, 260 distinct ids** | ➖ single scenario | ✅ the scan made case-insensitive after mutation (a) exposed the gap (deviation 2) |

**Test summary — round 6.** 6 tests written (5 `unit` in the new `TapInventoryDetailTests`, 1 `unit-app`),
2 existing `unit` tests replaced by reversed equivalents, 2 existing `unit-app` tests renamed/narrowed.
Layers: `unit` 5, `unit-app` 1. No approval tests — no refactoring task. Pure functions created: 1
(`TapInventoryDetail.resolve(_:in:installed:)`).

## Phase 6⁵ — verification and bindings

| Check | Result |
|---|---|
| `swift test --package-path Packages/CellarCore` | **1,878 tests / 218 suites passed, 1 known issue** (baseline 1,873 / 217 → **+5 tests, +1 suite**; the flake did not recur in either post-GREEN run) |
| `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`, 260 distinct test ids** (baseline 259 → **+1**, the one new `unit-app` test; no shipped id lost) |
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
