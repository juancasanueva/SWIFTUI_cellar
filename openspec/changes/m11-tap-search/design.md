# Design: Tap package search and install (`m11-tap-search`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec canonical + Engram mirror `sdd/m11-tap-search/design`, project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

`next_recommended: sdd-tasks`.

**Revision 3 — maintainer scope change (2026-08-25), binding.** Round 1 already landed on branch
`feat/m11-tap-search` (`dbc5233`). **This document describes the delta from that branch, not from
`main`.** The scope change is not a refinement of the shipped section — it moves the whole surface:

| | Revision 2 (landed) | Revision 3 (this) |
|---|---|---|
| Where tap results appear | a `Section` inside `BrowseView`'s list | **its own sidebar section**, "Search our taps" |
| `BrowseView.swift` | modified (sectioned list, `let taps`, overlay) | **reverted to a ZERO diff vs `main`** |
| Empty query | section hidden | **lists every tap package**, deterministic order |
| Outdated chip | hides the section | **not present on the new surface** |
| Absence rule | `isSectionVisible` (a `Bool`) | **a presentation state machine** with empty-state copy |

**Inputs.** proposal obs `#7796`, `explore.md`, maintainer decisions obs `#7795` and the 2026-08-25 scope
change. Risks **R1 … R7** carry from the proposal by name. Approach **A** stands; **B**, **C**, **D**
remain rejected. Verification classes are the spec's two: **`unit`** and **`unit-app`**.

> **Size note.** Exceeds the 800-word default by explicit launch-brief instruction (a new `AppSection`
> case with nine wiring sites, a full surface, a revert plan, a concurrency statement and a Strict TDD RED
> map). `openspec/config.yaml` `rules.design` additionally requires actor-isolation and Sendable
> statements. Tables, not prose — the m9/m10 precedent.
>
> **Requirement ordinals.** This document uses the **promoted main spec's** markers: `<!-- TM11 -->`
> (`openspec/specs/tap-management/spec.md:532`, adjacent capabilities, MODIFIED) and `<!-- TM12 -->`
> (`:560`, trust presentation, untouched). `explore.md`/`proposal.md` call these TM10 and TM11 using the
> pre-promotion ordinals; same requirements, renumbered.

## Technical Approach

Three pieces, ordered by how much they touch:

1. **Amend the landed projection** (`TapPackageSearch.swift`). Two behavioural changes and one addition:
   an empty query now lists **every** tap package instead of returning `[]` (`:125`); `isSectionVisible`
   is **replaced** by a presentation state machine that folds the shipped
   `TapProjection.state(loadState:inventory:)` (`TapProjection.swift:188-196`) with the hit count; and a
   `packageCount` for the shell's title-bar count label. Everything else — matching, ladder, order,
   collision rule, copy — is **unchanged and already green** on the branch.
2. **A new surface**, `cellar/Browse/TapSearchView.swift`, replacing the deleted `TapSearchSection.swift`.
   A visually exact sibling of `BrowseView`: same `PaneSearchField`, the same filter bar (reused, **DD-15**),
   the same `List(selection:)`/row/`MutationMenu` composition, the same `PackageDetailView` detail wiring.
   Reached through a new `AppSection.tapSearch` case wired at **nine** sites (**DD-14**).
3. **Revert the Browse integration entirely.** `BrowseView.swift` returns to a byte-identical copy of
   `main`; `ContentView`'s `BrowseView(…)` call drops its `taps:` argument; `TapSearchSection.swift` is
   deleted (**Removal plan**, below).

`rules.design` compliance is unchanged and structural: all logic stays in
`Packages/CellarCore/Sources/BrewClient`; the app target gains view and wiring code only. No new external
dependency, no new protocol boundary, **no new brew invocation**, no `#available`.

## Architecture Decisions

Decisions **DD-1 … DD-5**, **DD-7**, **DD-9**, **DD-12** and **DD-13** are unchanged from revision 2 and
already shipped on the branch; they are summarised for continuity, not re-argued. **DD-6**, **DD-8**,
**DD-10** and **DD-11** are rewritten. **DD-14 … DD-17** are new.

### Carried unchanged (shipped on `dbc5233`)

| # | Decision | Where it lives now |
|---|---|---|
| **DD-1** | `TapPackageSearch` is `public struct: Sendable`; `isInCatalog` is a **parameter**, never stored — mirroring `InstalledBrowse` (`InstalledFilterMode.swift:62-65`, `:99-107`). `Hashable` is carried by the hit, not the search type | `TapPackageSearch.swift:88-123` |
| **DD-2** | Row identity is `TapSearchHit.RowID { tapName, kind, name }`; `PackageID` survives only as `mutationTarget` (**R1**) | `:32-47` |
| **DD-3** | Ladder `{ exactToken, namePrefix, nameSubstring }` over `PackageText.normalize`, matching **both** the bare token and the qualified `publishedName`, with a `publishedName`-only match capped at `nameSubstring` | `:214-228` |
| **DD-4** | Selectable **iff** `routableID != nil` — nil when not installed, when `alsoInCatalog`, or when another emitted hit shares the `PackageID`. Selection stays `PackageID?` | `:64-67`, `:152-172` |
| **DD-5** | Order `(rank asc, normalised token asc, formula before cask, tapName asc)` — total. Official taps excluded via `TapProjection.thirdPartyTaps` | `:245-252`, `:128` |
| **DD-7** | The projection supplies `collisionNote: String?` — `Also in the catalog. Homebrew installs the catalog package.` — never the view (**PS8**) | `:107-108`, `:169` |
| **DD-9** | The row renders `hit.stateCopy` and `hit.collisionNote`, and builds `MutationMenu` from `PackageEntry(installed: nil, catalog: nil, id:)`. **`TapPackage.statusExplanation` refused**: it is `nil` for `.installed` (`TapProjection.swift:52-58`) because TM5 state 1 mandates no copy (`openspec/specs/tap-management/spec.md:131-132`), which would leave an installed row silent. No "Untrusted" badge — **TM12** untouched | `:103-108`, `:230-236` |
| **DD-12** | Projection types nonisolated by module default (`Package.swift` declares no `.defaultIsolation`), `Sendable`/`Hashable` by composition. Views `@MainActor` implicitly (`project.pbxproj:451`, `:488`). Built **synchronously in `body`** — no `Task`, no `.task {}`, no `await` | — |
| **DD-13** | No `#available` — macOS 26.0 everywhere (`project.pbxproj:355,413,503,524`; `Package.swift:7`) | — |

### Rewritten and new

| # | Decision | Rejected alternative | Rationale |
|---|---|---|---|
| **DD-6 (rewritten)** | `isSectionVisible(query:outdatedOnly:tapState:)` is **deleted** and replaced by `presentation(tapState:inventory:query:hitCount:) -> TapSearchPresentation`, an `Equatable` enum: `.loading`, `.unavailable(InstalledAbsence)`, `.failed(TapInventoryError)`, `.noTaps`, `.noMatch(query: String)`, `.content`. It is built by **switching over the shipped `TapProjection.state(loadState:inventory:)`** and folding only the hit count on top | Keeping a `Bool` and writing four `if`s in the view; a parallel state machine that re-reads `TapLoadState` directly; reusing `TapPresentationState` unchanged | A `Bool` answered the old question ("render the section at all?"). The new surface is **always reachable from the sidebar**, so it can never hide — it must instead *say why it is empty*, and there are four distinct reasons. `TapProjection.state(…)` (`TapProjection.swift:188-196`) already distinguishes three of them and is already proven by `TapProjectionTests.presentationStatesRemainDistinct` (`:130-135`), including the `hasLastGood` rule that keeps stale content visible during a refresh. Re-deriving that from `TapLoadState` would be a second opinion on a question one projection already answers — the drift PT5's one-projection rule exists to prevent. Only `.noMatch` is genuinely new, because only it depends on the hit count. `outdatedOnly` is **dropped entirely**: the chip does not exist on this surface (**DD-15**) |
| **DD-8 (rewritten)** | Tap results get **their own sidebar section and their own view**, `cellar/Browse/TapSearchView.swift`. `BrowseView.swift` reverts to a **byte-identical copy of `main`** — asserted, not reviewed | Keeping the landed `Section` inside `BrowseView`; a segmented scope control on Browse's search field; a sheet | Maintainer scope change (2026-08-25), binding. The engineering consequence is strictly favourable: **R4 disappears** — catalog row identity, selection and the empty-state overlay cannot regress if the file does not change — and **R5 disappears** with it, because there is no longer a shared empty state to reconcile. `EmptyResults` stays `private` untouched (**DD-10**). The cost is one more `AppSection` case and its nine wiring sites (**DD-14**), which the compiler and the shipped placement suite both enforce |
| **DD-10 (rewritten)** | **The new file duplicates a small private `TapSearchEmptyState` rather than sharing `BrowseView`'s `EmptyResults`.** No visibility anywhere is relaxed | Relaxing `EmptyResults` to internal and reusing it; extracting a shared internal `BrowseEmptyState` into a third file | **Forced, not chosen.** `EmptyResults` is `private struct` at `BrowseView.swift:173`, and Swift `private` is file-scoped — so *any* reuse requires editing `BrowseView.swift`, which **DD-8** requires to have a zero diff. Extracting it to a third file would also edit `BrowseView.swift` (the declaration would leave it). The duplication is small and, more importantly, the two are **not the same view**: `EmptyResults` answers three catalog reasons (`Loading catalog` / `No packages yet` / `.search(text:)`), while this surface answers four different ones (**DD-6**) and shares only the last. A shared type would need a union of seven cases so that each surface could ignore three — a worse abstraction than two honest ones. The new file's states render from `TapSearchPresentation`, so the *rule* is still tested once, in `BrewClientTests` |
| **DD-11 (rewritten)** | The scanner lists swap `cellar/Browse/TapSearchSection.swift` → `cellar/Browse/TapSearchView.swift` in **both** places: `TapSearchSources.paths` (`TapSearchCompositionTests.swift:287-291`) and `PerPackageTrustSources.views()` (`PerPackageTrustCompositionTests.swift:186-201`) with its sorted anchor (`:31-32`). `BrowseView.swift` **leaves** the trust-scanner list and **stays** in the tap-search scanner list — now as the subject of a zero-diff assertion | Dropping `BrowseView.swift` from both lists; leaving the deleted path in place | A path that no longer exists makes every absence in that suite throw rather than pass, so the swap is mandatory, not cosmetic. `BrowseView.swift` leaves the *trust* list because it is reverting to a file that never mentioned trust, and its presence would assert nothing about this change. It stays in the *tap-search* list because the strongest claim this revision makes is about that file: **it must not reference the tap surface at all** |
| **DD-14 (new)** | `case tapSearch` is added to `AppSection` **immediately after `.browse`** (`AppSection.swift:28`), and wired at **nine** sites, enumerated below. Its `rawValue` is `"tapSearch"` | A free-floating `NavigationLink`; folding the surface into `.taps`; placing it in the "Manage" group beside Taps | The enum exists so the selection is "a value the shell can hold, restore and switch over exhaustively" (`AppSection.swift:8-11`). Placement after `.browse` in the **Overview** group is what makes the two search surfaces siblings — the maintainer's "Search our taps" reads as the counterpart to "Search catalog". Putting it under Manage would file a *search* surface under *tap administration*, which is the TM11 boundary this change spent three deltas narrowing |
| **DD-15 (new)** | **Reuse `CatalogFilterBar`** with two new **defaulted** parameters — `showsOutdatedChip: Bool = true` and `showsCatalogPredicates: Bool = true` — so the tap surface renders kind chips plus a **Hide installed** toggle and nothing else. `BrowseView`'s call site stays **byte-identical** because both parameters default | A sibling `TapFilterBar` duplicating the chips; reusing the bar unchanged and letting three controls sit inert; hoisting the chips into a third shared view | Maintainer preference is reuse, and the defaults are what make it compatible with **DD-8**'s zero-diff requirement — a non-defaulted parameter would force a `BrowseView.swift` edit and fail the whole constraint. The two flags are not cosmetic: `Outdated` is unanswerable (a tap hit carries no version, **DD-6**) and `Hide deprecated`/`Hide disabled` are `SearchFilters` predicates the *published index* answers (`CatalogFilterBar.swift:10-16`) which the tap inventory does not publish. Rendering them would break the shipped "no enabled control is inert" rule (design D8d). **Honest cost:** the tap surface holds a `SearchFilters` whose two exclusion flags are dead, and passes `.constant(false)` for `outdatedOnly` — accepted because the alternative duplicates the `KindSelection` three-way picker (`CatalogFilterBar.swift:77-95`), whose whole purpose is making "neither kind selected" unrepresentable |
| **DD-16 (new)** | An **empty query lists every tap package**. The `guard needle.isEmpty == false else { return [] }` at `TapPackageSearch.swift:125` is removed; an empty needle assigns **every** package `.exactToken`, so the ladder is uniform and the order falls entirely to **DD-5**'s remaining three keys | Returning `[]` (the landed behaviour); a separate `allPackages()` entry point; sorting the default listing by tap name first | Mirrors `PackageSearchIndex.defaultOrder(filters:limit:)`, which does exactly this — it assigns `.exactToken` to every record in the default listing (`PackageSearchIndex.swift:218-227`) — so the two surfaces answer an empty query by the same rule. A second entry point would duplicate the kind and `hideInstalled` filters and give a later reader two orders to keep in step. Grouping by tap was rejected because **DD-5**'s order is already total and reproducible, and the tap of origin is on every row anyway |
| **DD-17 (new)** | The surface's own copy — the search-field prompt, the section title and the four empty states — is **pinned by the spec**. The **count** behind the prompt and the shell title bar comes from a new pure `TapPackageSearch.packageCount(inventory:)`, not from a view-side sum | A view-side `inventory.taps.reduce(0)`; no count at all; reusing `TapProjection.packageSummary(for:)` | PS8's copy-ownership clause already requires the *hit's* sentences to come from the projection (**DD-7**, **DD-9**); a count rendered beside them is the same kind of claim and belongs in the same place, where a `unit` test can reach it. `packageSummary(for:)` (`TapProjection.swift:166`) is per-tap and formats a different sentence ("5 formulae · 1 cask"), so reusing it would mean reformatting its output. `sdd-apply` reproduces the pinned strings; it does not choose them |

### `AppSection.tapSearch` — the nine wiring sites (DD-14)

Every one verified this round. Sites 6–9 are **compile-time forced**; the rest are silent if missed,
which is why each carries a RED row.

| # | Site | File / line | What it needs | Forced by |
|---|---|---|---|---|
| 1 | `title` | `AppSection.swift:104-130` | `"Search taps"` — pinned by spec | compiler (exhaustive) |
| 2 | `sidebarTitle` | `:134-139` | `"Search our taps"` — pinned by spec. **Has a `default:` arm**, so a missing case is silent and falls back to `title` | test only |
| 3 | `systemImage` | `:141-167` | a symbol distinct from `.browse`'s `magnifyingglass` — **must be verified against this SDK** (**R8**) | compiler |
| 4 | `sidebarGroups` | `:173-180` | `("Overview", [.home, .browse, .tapSearch])` | test only |
| 5 | `ContentView.listSections` | `ContentView.swift:156-159` | add — it is a list-plus-detail surface | test only |
| 6 | content switch | `:306` | `case .tapSearch: TapSearchView(…)` | compiler |
| 7 | detail switch | `:530-546` | join the `PackageDetailView` arm beside `.browse, .installed, .favorites, .updates` — **no new branch** (**DD-4**) | compiler |
| 8 | `shellTitleBarAccessories` | `:624-636` | join the `nil` arm — "exhaustive with no `default:` … a new section must decide, visibly, at compile time" (`:621-623`) | compiler |
| 9 | `SidebarView.badge(for:)` | `SidebarView.swift:175-205` | join the no-badge arm — likewise exhaustive with no default (`:199-201`) | compiler |

Two `Set` literals are **not** switches but are asserted as full coverage by the shipped placement suite,
so they are mandatory all the same:

- `pinnedHeaderSections` (`ContentView.swift:594-599`) — `AppSectionPlacementTests.swift:195-200` loops
  **every** `AppSection.allCases` and requires membership. Omitting it fails a shipped test.
- `shellTitleBarSections` (`:603-606`) — the surface has no collection controls of its own, so it takes
  the shell's plain `ShellTitleBar`, exactly as `.browse` does.

Two further touches, neither forced:

- `defaultListPaneWidth(for:)` (`:97-99`) is `section == .browse ? 400 : 342`. The tap rows carry a kind
  chip and a trailing menu like Browse's, so `.tapSearch` joins the 400 branch.
- `countLabel` (`:204-206`) is `section == .browse ? "\(catalog.packageCount.formatted()) packages" : nil`.
  `.tapSearch` gets the same shape over `TapPackageSearch.packageCount(inventory:)` (**DD-17**).

**Persistence check (asked explicitly).** `section` is `@State private var section: AppSection = .home`
(`ContentView.swift:68`) — **not** `@AppStorage`, `@SceneStorage` or otherwise restored, so a new case
needs no migration and cannot break restoration. The raw value *is* persisted indirectly: it keys the
per-section list-pane width in `UserDefaults` as `"shell.listPaneWidth.\(section.rawValue)"`
(`:106`, `:122`). That is **purely additive** — `"shell.listPaneWidth.tapSearch"` is a new key, no
existing key changes meaning, and the legacy `shell.listPaneWidth` seed (`:101`, `:108-110`) still
applies. No migration required.

## Interfaces / Contracts — the round-2 delta

```swift
// Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift  (MODIFIED)

/// Why the surface shows what it shows. Folded from the shipped
/// `TapProjection.state(loadState:inventory:)`, which already distinguishes the
/// first four; only `.noMatch` depends on the hit count (DD-6).
public enum TapSearchPresentation: Sendable, Equatable {
    case loading
    case unavailable(InstalledAbsence)
    case failed(TapInventoryError)
    case noTaps
    case noMatch(query: String)
    case content
}

extension TapPackageSearch {
    public static func presentation(
        tapState: TapLoadState,
        inventory: TapInventory,
        query: String,
        hitCount: Int
    ) -> TapSearchPresentation

    /// The number behind the prompt and the shell's count label (DD-17).
    /// Third-party taps only — the same set `hits(…)` draws from.
    public static func packageCount(inventory: TapInventory) -> Int
}

// REMOVED: isSectionVisible(query:outdatedOnly:tapState:)  — DD-6
// CHANGED: hits(...) no longer returns [] for an empty needle — DD-16
```

```swift
// cellar/Browse/CatalogFilterBar.swift  (MODIFIED — both defaulted, so
// BrowseView's call site is byte-identical; DD-15)
struct CatalogFilterBar: View {
    @Binding var filters: SearchFilters
    @Binding var hideInstalled: Bool
    @Binding var outdatedOnly: Bool
    let isInstalledFilterEnabled: Bool
    var showsOutdatedChip = true          // NEW
    var showsCatalogPredicates = true     // NEW — Hide deprecated / Hide disabled
}
```

## Data Flow

    brew tap-info --installed --json          brew info --installed --json=v2
        │ (already shipped, TM1)                   │ (already shipped)
        ▼                                          ▼
    TapStore.inventory + .state ─────┐   InstalledStore.inventory
        │                            │          │
        │   TapProjection.state(loadState:inventory:)   ← shipped, reused (DD-6)
        │                            ▼          ▼
        └──────────────► TapPackageSearch(inventory:installed:)
                             .hits(query:kinds:hideInstalled:isInCatalog:)
                             │  empty query ⇒ every package, .exactToken (DD-16)
                             ▼
                 TapPackageSearch.presentation(…, hitCount:)
                             │
                             ▼
    Sidebar "Search our taps" ⇒ AppSection.tapSearch ⇒ TapSearchView (@MainActor, synchronous)
        PaneSearchField · CatalogFilterBar(showsOutdatedChip: false,
                                           showsCatalogPredicates: false)
        List(selection: $selection)
          └─ ForEach(hits) ── name · KindTag · tapName · hit.stateCopy
                              · hit.collisionNote · MutationMenu(PackageEntry(
                                    installed: nil, catalog: nil, id: hit.mutationTarget))
             routableID != nil ⇒ .tag(id) ⇒ ContentView detail arm ⇒ PackageDetailView
             routableID == nil ⇒ .selectionDisabled()
        .overlay ── TapSearchEmptyState(presentation)   ← private sibling, not shared (DD-10)

    BrowseView ──────────────► unchanged. Byte-identical to `main`. (DD-8)

`PackageSearchIndex` appears nowhere on this path, and neither does `BrowseView`. PD6/TM5 compliance is
structural, and now **doubly** so: the catalog surface no longer even references the tap projection.

## File Changes — round-2 delta on top of `dbc5233`

| File | Action | Est. delta | Description |
|---|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift` | Modify | +70 / −25 | **DD-16** empty-query listing; **DD-6** `presentation(…)` replaces `isSectionVisible`; **DD-17** `packageCount` |
| `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | Modify | +130 / −45 | Drop the `isSectionVisible` and outdated rows; add empty-query, presentation and count rows; restate the latency row |
| `cellar/Browse/TapSearchView.swift` | **Create** | 210–270 | The whole surface: search field, filter bar, list, rows, empty states, preview |
| `cellar/Browse/TapSearchSection.swift` | **Delete** | −93 | Superseded by `TapSearchView.swift` |
| `cellar/Browse/BrowseView.swift` | **Revert** | −45 (to zero diff vs `main`) | **DD-8**. Asserted byte-identical, not reviewed |
| `cellar/Shell/AppSection.swift` | Modify | +14 | **DD-14** sites 1–4 |
| `cellar/ContentView.swift` | Modify | +14 / −1 | **DD-14** sites 5–8, both `Set`s, width, count label; **drops** `taps: taps` from the `BrowseView(` call |
| `cellar/Shell/SidebarView.swift` | Modify | +1 | **DD-14** site 9 |
| `cellar/Browse/CatalogFilterBar.swift` | Modify | +12 | **DD-15** two defaulted parameters |
| `cellarTests/AppSectionPlacementTests.swift` | Modify | +5 / −3 | `order.count == 21` → `22` (`:34`); `"tapSearch"` after `"browse"` in the rawValue anchor (`:52-60`); Overview group |
| `cellarTests/TapSearchCompositionTests.swift` | Modify | +150 / −125 | Path swap (`:287-291`); replace the five Browse-integration tests with their `TapSearchView` equivalents plus the zero-diff assertion |
| `cellarTests/PerPackageTrustCompositionTests.swift` | Modify | 3 | **DD-11** path swap + sorted anchor (`:31-32`, `:186-201`) |
| `openspec/changes/m11-tap-search/specs/` | Modify | +120 / −80 | PS8's surface clauses; new empty-state and empty-query copy — owned by `sdd-spec` |
| `cellar.xcodeproj/project.pbxproj` | **Untouched** | **0** | `path = cellar` (`:46`) and `path = cellarTests` (`:51`) are `PBXFileSystemSynchronizedRootGroup`s. A deletion is likewise a 0-line diff |

**Budget.** Round-2 delta ≈ **700–950** changed lines, plus ~250–400 artifact lines. Cumulative branch
total ≈ **2,050–2,600 against 5,000**. `400-line budget risk: N/A` (project budget is 5,000);
**5,000-line budget risk: Low**. Single PR under the cached `single-pr` strategy.

## Removal plan (explicit, per the scope change)

1. `git rm cellar/Browse/TapSearchSection.swift` — no other file may reference it afterwards; the two
   scanner lists are updated in the same commit (**DD-11**), or their reads throw.
2. `git checkout main -- cellar/Browse/BrowseView.swift` — restores the file wholesale rather than
   hand-unpicking `let taps`, the sectioned `List`, the `tapHits` property and the overlay condition. A
   hand-revert is how a stray blank line survives and turns a zero-diff claim into a review argument.
3. `ContentView.swift` — remove `taps: taps` from the `BrowseView(` call (site added in round 1). The
   store stays wired; it is now consumed by `TapSearchView` instead.
4. **Verify** with `git diff main -- cellar/Browse/BrowseView.swift`, expecting **empty output**, and by
   the `browseIsUntouchedByThisChange` RED row below. Both, because the test is what protects the property
   after the PR merges.

pbxproj remains untouched: a file-system-synchronized group needs no edit to add or remove a file.

## Testing Strategy

Strict TDD: every row is RED before its implementation exists. **`unit`** =
`swift test --package-path Packages/CellarCore`; **`unit-app`** = `xcodebuild test …
-only-testing:cellarTests` (`openspec/specs/app-updates/spec.md:17`).

> **Reconciliation obligation.** `specs/` is being amended in parallel to this same scope change. Before
> `sdd-tasks` closes, every delivered scenario MUST have a row here, matched **scenario by scenario**. All
> quoted copy is **pinned by the spec** — `sdd-apply` reproduces it and does not choose it.

**Dropped from revision 2** (the behaviour no longer exists): `theSectionIsAbsentForAnEmptyOrWhitespaceQuery`,
`theOutdatedChipHidesTheSection`, `theTapSectionIsTitledAndPositionedLast`, `theEmptyStateYieldsToTapHits`,
`catalogRowSelectionIsUnchanged`, `theSearchPromptStillCountsCatalogRecordsOnly` (Browse form),
`browseComposesTheTapSectionFromTheResidentStore`.

**Unchanged and still green** (assert the projection core, untouched by this revision):
`aTapPackageIsFoundByANonEmptyQuery`, `theLadderConvergesWithTheCatalogIndexOnOneFixture`,
`aHyphenatedNameMatchesByTokenAtEveryRung`, `aTapNameQueryMatchesThroughThePublishedName`,
`theOrderIsTotalAndReproducible`, `officialTapsNeverEnterTheSection`, `theKindFilterIsHonoured`,
`hideInstalledSubtractsFromTheSection`, `aCollidingHitIsShownAndIsNotRoutable`,
`twoTapsPublishingOneNameAreBothUnroutable`, `anInstalledUnambiguousHitIsRoutable`,
`aNotInstalledHitIsNeverRoutable`, `everyMutationTargetIsBare`, `theThreeInstallStatesCarryTheirExactCopy`,
`theCollisionNoteIsPresentExactlyWhenItIsTrue`, `theProjectionTakesNoLauncherAndNoCatalogStore`,
`aComposedTapSearchLeavesTheIndexUnchanged`, `theTapInventoryFeedsASurfaceOutsideTapManagement`,
`aTapPackageFoundHereAddsNoTapManagementAction`, `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge`
(now scanning `TapSearchView.swift`), `theReceiptDetailIsReachedWithNoNewRoutingBranch`,
`neitherTapSearchFileReachesTheProcessLayer`, `theSurfaceCopyLivesInTheProjectionNotTheView`,
`notInstalledTapRowsAreNotSelectable`, `theGrantCopyGuardCoversTheNewSurface`.

**New and rewritten rows:**

| Class | RED test | Asserts |
|---|---|---|
| `unit` | `anEmptyQueryListsEveryTapPackage` | **DD-16**: an empty query, and a whitespace-only query, both emit **every** third-party tap package — count equals `packageCount(inventory:)` — each at `.exactToken`, in **DD-5**'s order; official taps still excluded; `kinds` and `hideInstalled` still applied |
| `unit` | `theDefaultListingOrderMatchesTheSearchOrder` | **DD-16**: the empty-query listing and a query matching everything produce the same sequence, so one order governs both |
| `unit` | `thePresentationDistinguishesEveryEmptyReason` | **DD-6**: `.brewAbsent` ⇒ `.unavailable(absence)`; `.failed(error)` ⇒ `.failed(error)`; `.loaded` with no third-party tap ⇒ `.noTaps`; loaded with taps and `hitCount == 0` and a non-empty query ⇒ `.noMatch(query:)`; `hitCount > 0` ⇒ `.content`. Five distinct values, never an error value for an absence |
| `unit` | `thePresentationKeepsStaleContentWhileRefreshing` | **DD-6**: `.loading` with a non-empty resident inventory does **not** collapse to `.loading` and hide rows — the `hasLastGood` rule is inherited from `TapProjection.state(…)`, not re-derived |
| `unit` | `theEmptyStateCopyIsExact` | **DD-17**: each `TapSearchPresentation` case maps to its pinned sentence, byte-for-byte; none is empty |
| `unit` | `thePackageCountCountsThirdPartyTapsOnly` | **DD-17**: `packageCount(inventory:)` equals the number of hits for an empty query with default filters, and excludes `homebrew/core`/`homebrew/cask` |
| `unit` | `theTapSurfaceKeystrokeTurnStaysUnderTheCeiling` | PS8 latency, **restated**: this surface's own keystroke turn — a ~500-package inventory across several taps, ≥100 queries, `hits(…)` plus `presentation(…)` per turn — p95 < 8 ms. It is **no longer a combined turn**: Browse no longer composes tap hits, so nothing is added to the catalog's budget. Paired with the row below |
| `unit` | `theCatalogKeystrokeTurnIsUnchanged` | **R6** in its new form: the shipped PS6 catalog measurement is re-run and must be **unchanged**, because `BrowseView` and `PackageSearchIndex` are untouched. This is the honest PS6 claim now — the earlier combined-turn framing described an integration that no longer exists |
| `unit-app` | `browseIsUntouchedByThisChange` | **DD-8**, the load-bearing assertion: `BrowseView.swift` contains **none** of `TapPackageSearch`, `TapSearchHit`, `TapSearchSection`, `TapSearchView`, `TapStore`, `taps`, `tapHits`; it still declares `List(rows, selection: $selection)` and the single-source overlay `if rows.isEmpty {`; and `ContentView`'s `BrowseView(` call site contains no `taps:` |
| `unit-app` | `theTapSearchSectionFileIsGone` | Removal plan step 1: no source in `cellar/` references `TapSearchSection`, and the scanner path lists name `TapSearchView.swift` instead (**DD-11**) |
| `unit-app` | `theTapSearchSectionIsWiredAtEveryAppSectionSite` | **DD-14**, one row per site: `AppSection.tapSearch` exists with rawValue `"tapSearch"`, sits immediately after `.browse` in `allCases`, carries its pinned `title`/`sidebarTitle`/`systemImage`, appears in `sidebarGroups[0]` after `.browse`, and is a member of `listSections`, `pinnedHeaderSections` and `shellTitleBarSections`. The three exhaustive switches are covered by the compiler and by the extended placement suite |
| `unit-app` | `theShippedPlacementSuiteStillPassesWithTwentyTwoSections` | `AppSectionPlacementTests` amended, not weakened: `allCases.count == 22`, the rawValue anchor gains `"tapSearch"` after `"browse"`, sidebar coverage still exact, and `ContentView.swift`'s AppSection-switch count is still **3** — this change adds cases to existing switches, never a fourth switch (`:150-156`) |
| `unit-app` | `theTapSurfaceMirrorsBrowsesComposition` | Scope change's "visually exact copy": `TapSearchView.swift` composes `PaneSearchField(`, `CatalogFilterBar(`, `List(selection:`, `KindTag(`, `MutationMenu(center:` and `.themedListSelection(` — the same six the Browse list uses |
| `unit-app` | `theTapFilterBarOffersNoInertControl` | **DD-15**: the call passes `showsOutdatedChip: false` and `showsCatalogPredicates: false`; the file contains no `"Outdated"`, `"Hide deprecated"` or `"Hide disabled"` literal; and `CatalogFilterBar`'s new parameters both default to `true`, so the Browse call site needs no argument |
| `unit-app` | `theTapSurfaceOwnsItsSelectionLocally` | Scope change: `TapSearchView` declares `@State private var selection: PackageID?` — its own, not a binding threaded from the shell — and `ContentView`'s detail arm resolves `.tapSearch` through the **shared** `PackageDetailView` with no new branch (**DD-4**) |

**Existing tests that MUST keep passing:** `TapProjectionTests`, `TapShippingProofTests`,
`MutationCommandTests`, `MutationCommandTargetTests`, `SearchIndexTests`, `FilterTests`,
`InstalledFilterCompositionTests`, `ReceiptDetailCompositionTests`, `PackageGraphTests`, and — with only
their listed edits — `AppSectionPlacementTests` and `PerPackageTrustCompositionTests`.

## Threat Matrix

**N/A — no new routing, shell, subprocess, VCS/PR automation, executable-file classification, or
process-integration boundary.** Unchanged from revision 2 and, if anything, narrower: the surface composes
no argv, spawns no process and adds no brew invocation, and the catalog surface is now entirely out of
scope. Install goes through the byte-unchanged `MutationMenu`, whose `PackageTarget(entry.id)` validation
and confirmation rules are already proven (PM7, PM9, PM10). The untrusted-tap refusal is inherited from
the shipped spine — `MutationOutcome.refusedUntrustedTap` (`MutationOutcome.swift:71`; the classifying
`Signature` is `private`) plus `UntrustedTapRecovery`, measured against Homebrew 6.0.18 — and PM10
`:659-670` forbids gating it. The new `AppSection` case is sidebar navigation, not routing in the
threat-matrix sense: it spawns nothing and parses nothing.

## Migration / Rollout

No migration. Nothing persists that changes meaning: the one new `UserDefaults` key
(`shell.listPaneWidth.tapSearch`) is additive, and `section` is not restored across launches
(`ContentView.swift:68`). Reverting the PR deletes `TapPackageSearch.swift`, `TapSearchView.swift` and
two test files, removes one `AppSection` case and its nine wiring sites, and drops `CatalogFilterBar`'s
two defaulted parameters. `BrowseView.swift` needs no revert at all — it is already identical to `main`,
which is the clearest benefit of the scope change.

## Open Questions

- [x] **Closed** (obs `#7795`, superseded in part by the 2026-08-25 scope change): collision note,
      hide-installed, prompt scope. The section-placement and Outdated-chip decisions are **void** — there
      is no section and no Outdated chip.
- [x] **Closed** (**DD-9**, **TM12** untouched): tap name only, no "Untrusted" badge.
- [x] **Closed** (**DD-4**): not-installed and ambiguous rows are non-selectable; routable rows reach the
      shared `PackageDetailView` with no new branch.
- [x] **Closed** (**DD-10**): the empty state is duplicated, not shared — forced by `EmptyResults` being
      file-scoped `private` in a file that must not change.
- [x] **Closed** (**DD-15**): `CatalogFilterBar` is reused with two defaulted flags.
- [ ] **R8 — for `sdd-apply`, verify before committing.** `AppSection.systemImage` for `.tapSearch` must be
      a symbol that **exists in this SDK**. `AppSection.swift:148-150` already records one case where a
      plausible name (`clock.badge.plus`) did not exist and a substitute was needed. Candidates, in order:
      `sparkle.magnifyingglass`, then `magnifyingglass.circle`. Verify in SF Symbols before use; do not
      ship an unverified name.
- [ ] **Still open for `sdd-tasks`, not blocking.** Reconcile the RED map against the amended `specs/`
      scenario by scenario, and confirm the delivered blocks still number this requirement **PS8** and
      target **TM11**.
