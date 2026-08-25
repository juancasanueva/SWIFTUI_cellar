```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:b99f9e5effe908044d7fc1003f031edc9505e5208a20dec8b7eca2d444734102
verdict: fail
blockers: 0
critical_findings: 0
requirements: 4/4
scenarios: 34/35
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:98eeedbff91d553010d932673a6dfc54274fce4f00e291624401e1efb8030bdb
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:2d754715c46c6095dc874e605cb01f672ff417a51949b28cb8f65b90af43088c
```

## Verification Report — round 2 (the `Search our taps` surface)

**Change**: `m11-tap-search`
**Version**: spec deltas **r3** — PS8 ADDED, PD6 MODIFIED, TM5 + TM11 MODIFIED
**Mode**: Strict TDD (`openspec/config.yaml` `testing.strict_tdd: true`), coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `36f1b8d`, **12 commits** off `main` @ `edda9a5`, working tree clean
before and after this run
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled: no review lifecycle, no receipt, delivery under ordinary repository policy.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception` (2026-08-25). The measured
**5,889** changed lines against the 5,000 budget is recorded, **not** raised as a finding.
**Independence**: fresh context. Every number below was measured in this session. Nothing is taken
from `apply-progress.md` on its word; where this report agrees with it, it agrees because the
measurement was repeated.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total (both rounds) | 115 |
| Complete | 113 |
| Incomplete | **2** — `6.7` (round 1, marked **VOID** in the file, deliberately unchecked) and `6′.7` (open the PR) |

Counted directly from `tasks.md`: 113 `- [x]`, 2 `- [ ]` at `:430` and `:886`. Round 1 is 58 of 59
with `6.7` void; **round 2 is 55 of 56**, the single open box being `6′.7`, a delivery task this
run's launch brief forbade. This matches apply's deviation 12 exactly, including its correction of
the "57 checkboxes" figure in the round-2 launch brief.

---

### Build & Tests Execution

Four runners were executed. The first three are the maintainer's declared runners (m10's W1 decision,
binding); the fourth is required because the declared `unit` runner does not execute the latency
scenario (see **W4**).

**Build**: ✅ Passed

```text
xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
→ ** BUILD SUCCEEDED **   exit 0
```

**Tests**: ✅ all green, 0 failures

| # | Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|---|
| 1 | `swift test --package-path Packages/CellarCore` | **1,870 tests / 217 suites passed, 1 known issue** | 0 | `ea50cabc…41e7` |
| 2 | `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`** — 267 passing results / **257** distinct ids, 0 failed | 0 | `98eeedbf…0bdb` |
| 3 | `xcodebuild build … -scheme cellar` | **`** BUILD SUCCEEDED **`** | 0 | `2d754715…088c` |
| 4 | `swift test -c release --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | **32 tests / 1 suite passed** — both latency rows ran and passed | 0 | `c5d6f0d3…d4cf` |

Every figure apply claimed reproduced exactly: core **1,870/217** (its 6′.1), cellarTests **267/257**
(its 6′.2), build clean, release filter **32**. The one known issue in runner 1 is the shipped,
known-issue-guarded row; the timing flake the brief warned about
(`OperationCenterCancelTests.swift:183`) **did not occur** in either of this session's two core runs,
so no re-run was needed.

**Latency (release configuration, runner 4).** Both rows passed:

- `theTapSurfaceKeystrokeTurnStaysUnderTheCeiling` — passed in 1.971 s. Its binding assertions are
  `p95 < 8 ms` **and** `max < 8 ms`, and it proves its own worst case before measuring: the empty
  query is the first of ≥101 queries and the test asserts it reaches
  `TapSearchLatencyFixture.tapPackageCount` hits, so a p95 cannot step over the turn DD-16 makes the
  most expensive. 5 warm-up passes, 10 measured passes, `blackHole` `@inline(never)`.
- `theCatalogKeystrokeTurnIsUnchanged` — passed in 1.425 s, PS6's method over the reproduced fixture,
  with **no tap inventory in the turn**.

The exact p95/median/max are emitted only inside the failure message, so apply's **tap p95 1.501 ms /
max 1.856 ms** and **catalog p95 1.068 ms** could not be re-read numerically from a green run. What is
independently confirmed is the clause that binds: both turns hold **under the 8 ms ceiling**, and the
maximum does too. `theCatalogFixtureIsTheOnePS6MeasuresOver` re-asserts the fixture's size and shape
against PS6's own invariants (record count, mean name length 8–13, mean description length 30–42, both
kinds present, an empty description present), so "the same fixture" is proven rather than assumed.

**Coverage**: ➖ Not available — no coverage tool is configured for this project; threshold is 0.
**Linter / type checker**: ➖ No separate linter. The Swift 6 compiler is the type checker and both
targets build clean.

---

### Non-vacuity spot checks — six reversible mutations

Every check below was applied to the shipped source, run, and restored. **All six restored
byte-identically** (`shasum -a 256` compared against the pre-mutation digest) and
`git status --porcelain` printed **nothing** at the end. No mutation was left in the tree.

| # | Mutation | Expected | Observed | Restored |
|---|---|---|---|---|
| M1 | `routable = isInstalled && collides == false && unique` → `routable = isInstalled` | routability stops honouring collision and duplicate `PackageID` | ❌ 2 failures — `anAmbiguousInstalledHitIsNotRoutable` (`:601`), `twoTapsPublishingOneNameAreBothUnroutable` (`:619`) | ✅ |
| M2 | `if needle.isEmpty { return .exactToken }` → `return nil` | an empty query lists nothing | ❌ 3 tests / 8 issues — `anEmptyQueryListsEveryTapPackage`, `theDefaultListingOrderMatchesTheSearchOrder`, `thePackageCountCountsThirdPartyTapsOnly` | ✅ |
| M3 | drop `hasToken(…)` from the exact rung | `ai` no longer matches `gentle-ai` exactly | ❌ 4 tests / 6 issues — `aHyphenatedNameMatchesByTokenAtEveryRung` reported `.namePrefix` where `.exactToken` is required | ✅ |
| M4 | uncap the `publishedName`-only match | a tap-name match outranks substring | ❌ `aTapNameQueryMatchesThroughThePublishedName`, 4 issues — order flipped and both ranks became `.exactToken` | ✅ |
| M5 | `presentation.emptyStateCopy ?? ""` → the literal `"Your taps publish nothing yet."` in the view | the copy-ownership scan rejects it | ❌ `theSurfaceCopyLivesInTheProjectionNotTheView` failed | ✅ |
| M6 | add `private let tapHits = 0` to `BrowseView` | the untouched-Browse scan rejects it | ❌ `browseIsUntouchedByThisChange` failed | ✅ |

Every assertion this change rests on is therefore load-bearing. No spot check passed vacuously.

---

### Spec Compliance Matrix

35 scenarios live in the three r3 deltas (4 requirement blocks): PS8 **17**, PD6 **4** (3 reproduced
byte-identical + 1 new), TM5 **11** (10 + 1), TM11 **3** (2 + 1) — **20 new**. Counted from the files,
not from the artifact prose: `rg -c '^### Requirement:'` → 4, `rg -c '^#### Scenario:'` → 35.

#### PS8 — packages published by installed third-party taps (17 scenarios)

| Scenario | Test | Result |
|---|---|---|
| Found by a non-empty query | `TapPackageSearchTests > aTapPackageIsFoundByANonEmptyQuery` | ✅ COMPLIANT |
| The ladder is token-aware | `> aHyphenatedNameMatchesByTokenAtEveryRung`, `> theLadderConvergesWithTheCatalogIndexOnOneFixture`, `> aTapNameQueryMatchesThroughThePublishedName` | ✅ COMPLIANT |
| The composed order is total and reproducible | `> theOrderIsTotalAndReproducible` | ✅ COMPLIANT |
| Five facts and its copy, nothing else | `> aHitCarriesItsFiveFactsAndItsCopyAndNothingElse` | ✅ COMPLIANT |
| The kind filter restricts the source | `> theKindFilterIsHonoured` | ✅ COMPLIANT |
| An empty query lists everything | `> anEmptyQueryListsEveryTapPackage`, `> theDefaultListingOrderMatchesTheSearchOrder` | ✅ COMPLIANT |
| Unavailable / empty is an ordinary empty state | `> anUnavailableInventoryIsAnEmptyStateNotAnError`, `> thePresentationDistinguishesEveryEmptyReason`, `> theEmptyStateCopyIsExact`, `> thePresentationKeepsStaleContentWhileRefreshing` | ✅ COMPLIANT |
| A collision is reported and never suppressed | `> aCollidingHitIsShownAndIsNotRoutable`, `> theCollisionNoteIsPresentExactlyWhenItIsTrue` | ✅ COMPLIANT |
| Three install states with exact copy | `> theThreeInstallStatesCarryTheirExactCopy` | ✅ COMPLIANT |
| An ambiguous installed hit is not routable | `> anAmbiguousInstalledHitIsNotRoutable`, `> twoTapsPublishingOneNameAreBothUnroutable` | ✅ COMPLIANT |
| Hide-installed composes; no outdated control | `> hideInstalledSubtractsFromTheSection`, `> theTapSourceAdmitsNoOutdatedPredicate`, `TapSearchCompositionTests > theTapFilterBarOffersNoInertControl` | ✅ COMPLIANT |
| The surface holds the ceiling on its own turn | `> theTapSurfaceKeystrokeTurnStaysUnderTheCeiling`, `> theCatalogKeystrokeTurnIsUnchanged`, `> theCatalogFixtureIsTheOnePS6MeasuresOver` | ✅ COMPLIANT (release runner only — **W3**) |
| Its own titled entry; not-installed rows inert | `TapSearchCompositionTests > theTapSearchSurfaceIsWiredAtEveryAppSectionSite`, `> theSurfaceTitleIsTheSidebarEntry`, `> notInstalledTapRowsAreNotSelectable` | ✅ COMPLIANT |
| An installed hit opens the receipt-backed detail | `> theTapSurfaceResolvesThroughTheSharedDetail` | ✅ COMPLIANT |
| No trust gate and no local copy | `> theBrowseTapSurfaceComposesNoTrustGateAndNoBadge`, `> theSurfaceCopyLivesInTheProjectionNotTheView` | ⚠️ **PARTIAL** — **W1** |
| Composing reaches no process layer | `> neitherTapSearchFileReachesTheProcessLayer`, `TapPackageSearchTests > theProjectionTakesNoLauncherAndNoCatalogStore` | ✅ COMPLIANT |
| The catalog query surface is untouched | `> browseIsUntouchedByThisChange` + `git diff --stat main...HEAD` (BrowseView.swift absent from the changed-file set) | ✅ COMPLIANT (durability — **S3**) |

#### PD6 (4), TM5 (11), TM11 (3)

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| PD6 | A composed tap surface leaves catalog search unchanged (new) | `TapPackageSearchTests > aComposedTapSearchLeavesTheIndexUnchanged` | ✅ COMPLIANT |
| PD6 | 3 reproduced scenarios | shipped `package-detail` suites, unmodified and green | ✅ COMPLIANT |
| TM5 | The inventory feeds an outside search surface (new) | `> theTapInventoryFeedsASurfaceOutsideTapManagement` | ✅ COMPLIANT |
| TM5 | 10 reproduced scenarios | `TapProjectionTests` + `TapShippingProofTests`, unmodified and green (107 tests / 9 suites in the regression sweep) | ✅ COMPLIANT |
| TM11 | A tap package found elsewhere adds no action (new) | `> aTapPackageFoundHereAddsNoTapManagementAction` + shipped `TapShippingProofTests` action enumeration | ✅ COMPLIANT (see **S1**) |
| TM11 | 2 reproduced scenarios | `TapShippingProofTests` (`:95`, `:317`), unmodified and green | ✅ COMPLIANT |

**Compliance summary**: **34/35 compliant, 1 partial, 0 untested, 0 failing.**

---

### Correctness (static evidence, verified this session)

| Requirement clause | Status | Evidence |
|---|---|---|
| Copy pinned byte-exact | ✅ | All seven strings verified in `TapPackageSearch.swift`: `Installed.` (`:145`), `Installed. Homebrew withholds its tap while this tap is untrusted.` (`:146-147`), `Not installed.` (`:148`), `Also in the catalog. Homebrew installs the catalog package.` (`:149-150`), `No packages from your taps.` (`:118`), `Your taps publish nothing yet.` (`:119`); `Search our taps` in `AppSection.sidebarTitle`. |
| Copy is projection-owned, absent from the view | ✅ | `theSurfaceCopyLivesInTheProjectionNotTheView` asserts all six sentences present in the projection **and** absent from `TapSearchView.swift`. Proven non-vacuous by **M5**. |
| `Search our taps` as sidebar entry **and** pane title | ✅ | `SidebarView.swift:97` renders `item.sidebarTitle`; `ContentView.swift:203` renders `ShellTitleBar(title: section.sidebarTitle)` and `.tapSearch ∈ shellTitleBarSections`. One string, one place. `AppSection.title` and `.sidebarTitle` are asserted **separately** (`TapSearchCompositionTests:104-106`), and the `default:` arm's removal is confirmed in the diff. |
| `AppSection.title == "Search taps"` is never rendered | ✅ | Its only consumer is `ShellToolbarItems` (`ShellToolbar.swift:29`), gated by `showsPageChrome: !pinnedHeaderSections.contains(section)` (`ContentView.swift:234`); `.tapSearch` **is** in `pinnedHeaderSections`, so that string is unreachable. See **S2**. |
| No trust type, badge or control on the surface | ✅ | Asserted over `TapSearchView.swift` (8 identifiers + a whole-file lowercase `trust` sweep). Independently confirmed for the **projection** by direct inspection: 0 occurrences of all eight identifiers; its only `trust` byte-sequence is inside the pinned TM5 sentence. |
| No new routing branch in `PackageDetailView` | ✅ | `PackageDetailView.swift` has a **zero-line diff**; the detail arm reads `case .browse, .tapSearch, .installed, .favorites, .updates:` — one arm, four forbidden identifiers asserted absent from the detail file. |
| Process-layer scan over both files | ✅ | `neitherTapSearchFileReachesTheProcessLayer`: 7 process identifiers + 5 work-starting forms (`refresh`, `.task`, `Task {`, `await `, `async `) absent from both, comments stripped. |
| `BrowseView.swift` zero-line diff, no reference | ✅ | Absent from `git diff --stat main...HEAD`; `browseIsUntouchedByThisChange` asserts 7 forbidden identifiers absent, 5 positive anchors present, and `ContentView`'s `BrowseView(` call carries no `taps:`. Proven non-vacuous by **M6**. |
| `From your taps` withdrawn | ✅ | Present in exactly one file — `TapSearchCompositionTests.swift`, the suite that asserts its absence, which excludes itself from its own tree walk. Absent from all of `cellar/`, `Packages/CellarCore/Sources/`. |
| No new brew invocation | ✅ | Neither file names `Process`, `BrewProcess`, `ProcessSpec`, `brewPath` or `/bin/`; `theTapInventoryFeedsASurfaceOutsideTapManagement` asserts `RecordingProcessLauncher.launchCount == 0` with a non-empty hit set. |
| `Catalog` does not import `BrewClient` (II7) | ✅ | `Package.swift:63-64` — `BrewClient` depends on `Catalog`; no `import BrewClient` anywhere under `Sources/Catalog/`. |
| Pure, `nonisolated`, `Sendable` projection | ✅ | `Package.swift` declares no `defaultIsolation`; `TapPackageSearch: Sendable`; `isInCatalog` is a parameter, never stored (`#expect(file.code.contains("let isInCatalog") == false)`). |
| Install unconditional, bare token | ✅ | `TapSearchView.row(_:)` renders `MutationMenu(center:entry:)` for **every** hit with `PackageEntry(installed: nil, catalog: nil, id: hit.mutationTarget)` — no condition, no `PackageTarget(`, no `MutationCommand`. `everyMutationTargetIsBare` covers the argv side. |
| PM10 scanner passes | ✅ | `MutationCommandTests`, `MutationCommandTargetTests` green in the 107-test regression sweep and in the full core run. |
| `PerPackageTrustSources.views()` retargeted, no private scanner | ✅ | +1 path (`cellar/Browse/TapSearchView.swift`) and the sorted anchor updated — a 5-line diff, no new scanner. Both shipped tests pass (`rowHeaderAndRowsReadOneProjection`, `theMarkerIsAdditiveOnThePackageRow`). |

---

### Invariants — zero-diff proof

`git diff --stat main...HEAD` lists 22 files. **None** of the following appears in it, so every one
carries a zero-line diff, verified independently of `apply-progress.md`:

`cellar.xcodeproj/project.pbxproj` · `openspec/specs/**` · `PackageSearchIndex.swift` ·
`MutationCommand.swift` · `TapCommand.swift` · `TapProjection.swift` · `PackageDetailView.swift` ·
`cellar/Browse/BrowseView.swift` · `cellarUITests/**`

---

### Coherence (Design DD-1 … DD-17)

| Decision | Followed? | Notes |
|---|---|---|
| DD-1 `Sendable` struct, `isInCatalog` a parameter | ✅ | Asserted structurally and by the type's shape. |
| DD-2 `RowID` row identity, `PackageID` only as `mutationTarget` | ✅ | `TapSearchHit.RowID { tapName, kind, name }`; `id` and `mutationTarget` are separate members. |
| DD-3 three-rung ladder over both names, published-name cap | ✅ | Non-vacuous by **M3** and **M4**. |
| DD-4 selectable iff `routableID != nil` | ✅ | View reads `routableID` and re-derives nothing; `.tag(` appears exactly once. Non-vacuous by **M1**. |
| DD-5 total order, official taps excluded | ✅ | `precedes` has all four keys; official exclusion asserted for both query and empty-query paths. |
| DD-6 `presentation(…)` replaces `isSectionVisible` | ✅ | `isSectionVisible` exists nowhere but in the assertion of its own absence. Five states, pairwise-distinct. |
| DD-7 / DD-9 projection supplies the copy; no badge | ✅ | Non-vacuous by **M5**. |
| DD-8 own surface, Browse byte-identical | ✅ | Non-vacuous by **M6** plus the git zero-diff. |
| DD-10 `EmptyResults` duplicated, not shared | ✅ | `private struct EmptyResults` still at `BrowseView.swift:126`; `private struct TapSearchEmptyState` is a separate type in `TapSearchView.swift:178`. No visibility relaxed. |
| DD-11 both scanner lists retargeted | ✅ | `TapSearchSources.paths` names `TapSearchView.swift`; `PerPackageTrustSources.views()` gains it with the sorted anchor updated. |
| DD-12 built synchronously in `body`, no `Task`/`await` | ✅ | Asserted as an absence over the whole file. |
| DD-13 no `#available` | ✅ | None in either file. |
| DD-14 `.tapSearch` after `.browse`, Overview, `sparkle.magnifyingglass`, wired everywhere | ✅ | **Ten** sites, not nine — see **S4**. Symbol existence is asserted against the live SDK via `NSImage(systemSymbolName:)`, not merely by string equality. `AppSectionPlacementTests` `order.count == 22` ✓ and its suite passes 7/7. |
| DD-15 `CatalogFilterBar` reused, both flags default `true` | ✅ | Defaults confirmed in the diff; Browse's call site carries neither argument and is byte-identical. |
| DD-16 empty query lists everything | ✅ | Non-vacuous by **M2**. Mirrors `PackageSearchIndex.defaultOrder`. |
| DD-17 `packageCount` in the projection | ✅ | `ContentView.countLabel` and the view's prompt both read `TapPackageSearch.packageCount(inventory:)`; the count is asserted **equal to the empty-query hit count**, so listing and label cannot drift. One inaccuracy in DD-17's own prose — see **S5**. |

**Visual mirror of Browse**: `PaneSearchField(`, `CatalogFilterBar(`, `List(`, `KindTag(`,
`MutationMenu(center:`, `.themedListSelection(` — all six present in `TapSearchView.swift` and
anchored against Browse itself, so "the same six" is proven rather than asserted.
`.selectionDisabled()` guards non-routable rows; the detail is the shared `PackageDetailView` arm.

**`.error(_, hasLastGood: true)` maps to content, not to the unavailable copy** — **licensed by the
spec.** PS8 conditions the empty state on the inventory being *unavailable* ("brew absent, or its
refresh failed"). With last-good rows resident the inventory is available-but-stale, and rendering
"No packages from your taps." over visible rows would be a false statement. The `.failed` mapping is
asserted over an **empty** inventory — exactly the case PS8's scenario describes
(`presentation(.failed(.malformedJSON), [], …) == .failed(.malformedJSON)`), and the stale-content
rule is inherited from `TapProjection.state(…)` rather than re-derived, which is what PT5's
one-projection rule requires. **Accepted.**

---

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | Two full cycle tables in `apply-progress.md` — 19 round-1 rows, 17 round-2 rows |
| All tasks have tests | ✅ | Every behavioural task names a test file; the two `➖ (deletion)` rows are deletions by design |
| RED confirmed (tests exist) | ✅ | All **21** round-2 test names in the TDD table exist on disk under the names claimed |
| GREEN confirmed (tests pass) | ✅ | 1,870 core + 267 cellarTests + 32 release-filter, all passing this session |
| Triangulation adequate | ✅ | Every row triangulated except three explicitly-marked `➖` (two deletions, one single-claim) |
| Safety net for modified files | ✅ | Baselines recorded and re-verified: 1,864 → 1,870 core (+6 = 8 added − 2 deleted), 267 → 267 results / 256 → 257 distinct ids (+1 = 6 added − 5 deleted) |
| RED where behaviour pre-existed | ✅ | Nine round-2 rows are proven by **reversible mutation** rather than by a compile error, each restored byte-identically with `shasum -a 256 -c` reported `OK` |
| Withdrawn behaviour deleted, not left green | ✅ | All seven round-1 tests for retired behaviour are gone from the tree; `isSectionVisible` survives only inside the assertion of its own absence |

**TDD Compliance**: 8/8 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (`unit`) | 32 in `TapPackageSearchTests` (30 debug + 2 release-gated) | 1 + 2 fixtures | Swift Testing |
| Unit-app (`unit-app`) | 10 in `TapSearchCompositionTests`, plus edits to 3 shipped suites | 4 | Swift Testing + `#filePath` source scan |
| Integration | 0 | 0 | not applicable to this change |
| E2E (`cellarUITests`) | 0 — zero-line diff | 0 | XCUITest (out of scope) |

### Changed File Coverage

➖ Coverage analysis skipped — no coverage tool is configured. Threshold is 0.

### Assertion Quality

| File | Line | Assertion | Issue | Severity |
|---|---|---|---|---|
| `TapPackageSearchTests.swift` | 987-990 | `#expect([...8 string literals].count == 8)` | Tautology over a literal — exercises no production code | SUGGESTION (**S1**) |

Every other pattern audited came back clean. Specifically: no `#expect(true)`; every `for` loop over a
scanned collection runs behind a positive anchor (`swiftFiles.count > 50`, `sources.count == paths.count`,
`assertAnchored`, or a literal collection), so there are **no ghost loops**; every `.isEmpty` assertion is
either a companion to a non-empty one in the same test or is itself the positive anchor for a following
absence; the one type-only assertion (`NSImage(systemSymbolName:) != nil`) is paired with a value
assertion on the symbol name and with a control the file itself records as non-existent; there are no
mocks in either new file, so the mock/assertion ratio is 0.

**Assertion quality**: 0 CRITICAL, 0 WARNING, 1 SUGGESTION.

---

### Deviations — the twelve apply recorded, judged

| # | Deviation | Judgment |
|---|---|---|
| 1 | `sidebarTitle`'s `default:` arm removed under test pressure | **ACCEPT.** Strictly stronger: the arm is now compiler-forced instead of "test only", removing the silent-fallback trap DD-14 itself warned about. The shipped placement suite passes 7/7 with `.health` covered and no `default:`. |
| 2 | `countLabel` is an `if`-chain, not a `switch` | **ACCEPT.** A two-label `switch` would be counted as a fourth shell section switch and break the shipped `count == 3` invariant. Recorded in the code. |
| 3 | A **tenth** wiring site exists (`BrewfileCompositionTests.swift:617-630`) | **ACCEPT**, with **S4**. It failed at WU7 and was amended, not weakened. The design's nine-site table is short by one test anchor and should be corrected at archive. |
| 4 | `@Binding var selection` instead of the tasks' `@State` | **ACCEPT — the tasks were wrong.** `ContentView`'s shared `PackageDetailView` arm reads the shell's `selection`; a locally-owned `@State` would leave the detail pane permanently empty and make PS8 sc14 false. The binding is what delivers "no new routing branch". Pinned by `theTapSurfaceResolvesThroughTheSharedDetail`. |
| 5 | `ContentView.countLabel` extracted to a named member | **ACCEPT.** The expression was exactly where the design said, only unnamed. No anchor moved. |
| 6 | `Search our taps` lives in `AppSection.swift` only | **ACCEPT — and it is the correct reading.** The shell renders the pinned bar from `section.sidebarTitle`, so one string serves both places; a second literal in the view is what PS8's copy-ownership clause forbids. The test asserts the mechanism and the view's silence. |
| 7 | `theGrantCopyGuardCoversTheNewSurface` never existed | **ACCEPT.** The task named a test that does not exist; the guard it meant is the shipped `rowHeaderAndRowsReadOneProjection` loop, now pointed at `TapSearchView.swift` by the `PerPackageTrustSources.views()` retarget. Both shipped tests pass with only that edit. |
| 8 | code+test bucket ~536 lines over forecast | **ACCEPT.** Informational, entirely test code, under the accepted `size:exception`. Useful input for the next forecast. |
| 9 | WU6 leaves the app target non-compiling until WU7 | **ACCEPT as reported**, with **S6**. Honestly self-reported rather than hidden; the rollback order is reverse, so nothing is unsafe. The cost is that one intermediate commit does not build the app target. |
| 10 | The catalog latency row reproduces PS6's fixture rather than importing it | **ACCEPT.** One SwiftPM test target cannot import another — a real constraint, not a shortcut — and `theCatalogFixtureIsTheOnePS6MeasuresOver` re-asserts PS6's own size and shape invariants over the copy. Same method, same ceiling, no tap inventory in the turn. |
| 11 | `.error(_, hasLastGood: true)` maps to content | **ACCEPT — licensed by the spec.** Reasoning in the Coherence section above. |
| 12 | 56 round-2 checkboxes, not 57 | **ACCEPT.** Verified by counting: 113 `[x]` + 2 `[ ]`; round 1 is 59 boxes with `6.7` void, round 2 is 56 with `6′.7` open. |

**Twelve accepted, zero rejected.** Every one was reported by apply rather than absorbed, which is the
behaviour the process asks for.

---

### Commit hygiene and branch size

- **12 commits**, all Conventional Commits (`docs(sdd):`, `feat(taps):`, `feat(search):`,
  `test(search):`, `test(taps):`), each with a substantive body.
- **No AI attribution anywhere**: `git log main..HEAD --format='%B'` matches none of
  `co-authored`, `generated with`, `claude`.
- Ordering follows the TDD narrative: the two `test(...)` commits that pin new behaviour land
  before/around their `feat(...)`, and artifacts (`3335347`) landed **before** any round-2 Swift change.
- `git diff --shortstat main...HEAD` → **22 files changed, 5,863 insertions(+), 26 deletions(−)** =
  **5,889 authored lines** against the 5,000 budget, under the **maintainer-accepted `size:exception`
  (2026-08-25)**. Recorded, not a finding. Note that `apply-progress.md` states 5,754, measured before
  its own final rewrite — see **S7**.
- Working tree clean at start and at end; no `cellar/InfoPlist.xcstrings` churn was produced.

---

### Out-of-scope tracked items (not findings against this change)

- The full `-scheme cellar` runner is **red on `main`** from two pre-existing `cellarUITests` Taps
  failures (`cellarUITests.swift:209`, `:231`), tracked for a separate PR by maintainer decision.
  `cellarUITests/**` carries a **zero-line diff** on this branch, verified. The scoped runners are the
  gate for m11.
- `PRD.md` §7 ends at **M6**; no PRD milestone closes with this change. Round 1's task `7.4` claimed
  "M11" and apply already corrected it at `7′.4`.

---

### Issues Found

**CRITICAL**: None.

**WARNING** (4):

- **W1 — PS8 sc15's trust scan does not cover the projection.** The scenario's GIVEN names *"the source
  of the projection … and the source of the surface"* and its WHEN scans *both* for a trust type name, a
  trust badge and a trust control. `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge` scans
  `BrowseView.swift` and `TapSearchView.swift` — a round-1 source set, from when the surface lived
  inside Browse. `TapPackageSearch.swift` is never scanned for trust. The substance holds: I confirmed
  by direct inspection that all eight forbidden identifiers occur **zero** times in the projection, and
  its only `trust` byte-sequence is inside the pinned TM5 sentence `"…while this tap is untrusted."` —
  which is almost certainly why the whole-file lowercase sweep could not be pointed at it. Scoring the
  scenario **PARTIAL**, because nothing would catch a future `TrustGrantStore` reference added to the
  projection.
  **Remediation**: in `TapSearchCompositionTests.swift:321`, change
  `let scanned = [try TapSearchSources.browse(), try TapSearchSources.surface()]` to
  `[try TapSearchSources.projection(), try TapSearchSources.surface()]`, and scope the whole-file
  lowercase `trust` sweep (`:336-339`) to the surface alone, with a comment naming the pinned TM5
  sentence as the reason. Browse's trust-freedom is already covered by `browseIsUntouchedByThisChange`
  and by its zero-line diff.

- **W2 — one task is open: `6′.7`, "Delivery — one PR".** 55 of 56 round-2 tasks are complete. `6′.7`
  was deferred by this run's explicit instruction not to push and not to open a pull request; its six
  PR-body statements are drafted in `apply-progress.md`. This is a delivery task, not implementation,
  and it is the same shape m10 closed with.
  **Remediation**: open the PR with the drafted body, then tick `6′.7`. Nothing in the code changes.

- **W3 — the latency scenario is not exercised by the spec's declared `unit` runner.** Both latency
  rows carry `.enabled(if: TapSearchBuildConfiguration.isRelease)`, so under
  `swift test --package-path Packages/CellarCore` they are reported **skipped**, not run — I confirmed
  both skip lines in the debug log. The scenario is genuinely covered, but only by
  `swift test -c release …`, which this session ran (32 tests, both rows green). This mirrors the
  shipped PS6 precedent exactly (`CatalogTests/SearchLatencyTests.swift:35` uses the same idiom), so it
  is house convention rather than an m11 novelty — but PS8's verification-class table names the debug
  runner as the runner for all 12 `unit` scenarios, and it does not execute two of them.
  **Remediation**: at archive, add the release invocation beside the `unit` runner in the promoted
  scenario's provenance, or note in `specs/README.md` that latency scenarios are gated to release in
  this repository, as PS6 already is. No code change.

- **W4 — the exact latency figures could not be independently reproduced.** `p95`, median and max are
  interpolated into the `#expect` failure message only, so a green run prints none of them. Apply's
  **tap p95 1.501 ms / max 1.856 ms** and **catalog p95 1.068 ms** are therefore uncorroborated numbers;
  what this run independently confirms is the binding clause — both turns, including the empty-query
  worst case, are under **8 ms**.
  **Remediation**: none required for this change. If the figures are to be quoted in the PR body, either
  record them with an `Attachment` or accept them as apply's measurement and say so.

**SUGGESTION** (7):

- **S1 — a tautological assertion.** `TapPackageSearchTests.swift:987-990` asserts
  `[...8 string literals].count == 8`, which exercises no production code. TM11 sc3's substance rests on
  the source scan below it plus the shipped `TapShippingProofTests` enumeration (`:95`, `:317`, backed by
  a real enum with `case installedHandoff = "Installed handoff"`), both green. Read the shipped
  enumeration instead of restating it, or delete the line and keep the comment.
- **S2 — `AppSection.tapSearch.title == "Search taps"` is dead code.** Its only consumer is
  `ShellToolbarItems`, which is suppressed for every member of `pinnedHeaderSections`, and `.tapSearch`
  is one. The value is required only by the exhaustive `switch`. Harmless and consistent with `.browse`
  ("Search" vs "Search catalog"), but DD-14 site 1 describes it as *"pinned by spec"* and the spec pins
  nothing for `title` — correct that line at archive so a later reader does not treat it as a contract.
- **S3 — the zero-diff half of PS8 sc17 has no shipped enforcement.** `browseIsUntouchedByThisChange`
  enforces the no-reference half and five structural anchors every run; the *"zero-line difference"*
  clause is proven by `git diff`, which I re-verified this session but which no test can assert without
  git access. Consider a CI step (`git diff --quiet <base> -- cellar/Browse/BrowseView.swift`) if the
  property is meant to survive indefinitely.
- **S4 — correct the design's wiring table to ten sites.** `BrewfileCompositionTests.swift:617-630`
  carries a second full `rawValue` anchor and its own `count == 22`. Record it at archive so the next
  `AppSection` addition does not rediscover it by a failing test.
- **S5 — DD-17's prose overstates what the spec pins.** It says *"the four empty states"* are pinned;
  the spec pins **two** (`No packages from your taps.`, `Your taps publish nothing yet.`), reuses the
  catalog no-match state, and pins nothing for `.loading`. Consequently `"Reading your taps"`
  (`TapSearchView.swift:184`) is the one user-visible sentence on this surface that is composed in the
  view and covered by no copy assertion. Permitted by PS8 — which gives the surface its own title and
  empty-state copy — but worth pinning if the copy-ownership discipline is meant to be total.
- **S6 — one intermediate commit does not build the app target.** `656e2d5` (WU6) deletes
  `isSectionVisible` while `70f7148` (WU7) removes its only caller, so a `git bisect` landing on WU6
  cannot build `-scheme cellar` (`swift test` for CellarCore is green there). Apply reported this itself
  and corrected its own rollback-boundary text. No action needed for a single-PR merge; worth a squash
  or a fixup if the branch is ever bisected.
- **S7 — two branch-size figures are in circulation.** `apply-progress.md` 6′.6 records **5,754**
  authored lines, measured before that file's own final rewrite; the branch at `36f1b8d` measures
  **5,889**. Both are over budget under the accepted exception. Quote the final figure in the PR body so
  a reviewer does not have to reconcile them.

---

### Verdict

**FAIL — on evidence completeness only. 0 blockers, 0 CRITICAL, 4 WARNING, 7 SUGGESTION.**

This is not a judgment on the change, which is in excellent shape. Exactly one fact denies a passing
verdict, and it is the same shape that denied one to `m10-third-party-detail` round 1:

- **W1** — PS8 sc15's THEN reads *"**neither** contains a trust type name, a trust badge or a trust
  control"*, where "neither" names the projection and the surface. It is asserted for the surface and
  **not for the projection**: `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge` still scans the
  round-1 pair (`BrowseView.swift`, `TapSearchView.swift`), spending both slots on a file that is
  byte-identical to `main` and already covered by its own dedicated test. The scenario is therefore
  **PARTIAL**, and `scenarios: 34/35`.

The clause is **true** — I verified by direct inspection that all eight forbidden trust identifiers
occur zero times in `TapPackageSearch.swift`, and `theProjectionTakesNoLauncherAndNoCatalogStore` pins
the projection's entire public input surface, so no trust value can be injected into it. Nothing is
broken and nothing needs redesigning. What is missing is the assertion that would keep it true.

Everything else passes. All four runners are green with exit code 0 and reproduce apply's counts
exactly. The other 34 scenarios trace to named tests that passed at runtime. Six reversible mutations
proved the load-bearing assertions non-vacuous, each restored byte-identically to a clean tree. Every
zero-diff invariant holds — `BrowseView.swift`, `project.pbxproj`, `openspec/specs/**`, the index, the
argv surface, the tap command surface, the tap projection, the detail pane and `cellarUITests/**`. All
twelve recorded deviations are accepted, and the two that mattered most — the `@Binding` selection and
the `.error(hasLastGood:)` mapping — are better readings of the spec than the tasks they departed from.

**The remedy is a two-line test edit**, given verbatim in W1: swap `TapSearchSources.browse()` for
`TapSearchSources.projection()` at `TapSearchCompositionTests.swift:321`, and scope the whole-file
lowercase `trust` sweep to the surface alone, because the projection legitimately carries the substring
inside TM5's pinned sentence `"…while this tap is untrusted."`. Re-run
`xcodebuild test … -only-testing:cellarTests` and re-verify. No production line changes.
