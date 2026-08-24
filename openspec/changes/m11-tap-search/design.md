# Design: Tap package search and install from Browse (`m11-tap-search`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec canonical + Engram mirror `sdd/m11-tap-search/design`, project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

`next_recommended: sdd-tasks` (after `sdd-spec` lands `specs/`).

**Inputs.** `proposal.md` (obs `#7796`), `explore.md` (§1 architecture, §3 install spine, §5 approaches,
§6 open questions) and the maintainer's binding scope and presentation decisions (obs `#7795`). Risks
**R1 … R7** are carried from the proposal by name rather than restated. Approach **A** (explore §5) is
confirmed; **B**, **C** and **D** are recorded as rejected below so nobody re-proposes them.

> **Size note.** This document exceeds the 800-word default by explicit launch-brief instruction (a new
> public type, a two-identity selection problem, view integration across three files, a concurrency and
> PS6 statement, a Strict TDD RED map, and a budget/pbxproj confirmation). `openspec/config.yaml`
> `rules.design` additionally requires actor-isolation and Sendable statements. It follows the m9/m10
> precedent: tables, not prose.

## Technical Approach

Three pieces, ordered by how much they touch:

1. **A pure value in `BrewClient`** — `TapPackageSearch`, a `Sendable` struct over `TapInventory` +
   `InstalledInventory`, returning an ordered `[TapSearchHit]`. It owns matching, the rank ladder, the
   total order, collision detection, the section-visibility rule **and every user-visible string on the
   surface** (PS8 — the view composes no copy). No SwiftUI, no `Process`, no store, no clock;
   `BrewClientTests` reaches every shape, including the pinned copy.
2. **A sectioned Browse list** — `BrowseView.swift:59-78`'s flat `List(rows, selection:)` becomes
   `List(selection:) { ForEach(rows) … ; TapSearchSection(…) }`, with the tap rows in a new file
   `cellar/Browse/TapSearchSection.swift`. Catalog rows keep `PackageID` selection; tap rows are
   selectable only when their identity is unambiguous (**DD-4**).
3. **One argument at the composition root** — `ContentView.swift:307-315` gains `taps: taps`. The store
   is already held and already wired (it is passed to the neighbouring call at `:296`), so there is no
   new store, no new DI line and no new refresh.

`rules.design` compliance is structural: all new logic is in `Packages/CellarCore/Sources/BrewClient`;
the app target gains view code only. No new external dependency and therefore no new protocol boundary —
the section introduces no `Process`, `FileManager` or network use, and **no new brew invocation**: the tap
inventory is already resident in `TapStore.inventory` from the shipped TM1 refresh. No `#available`
branch is needed (**DD-13**).

The engineering content is not the row layout. It is **DD-4** (how one `List` carries two identity
spaces without the R1 duplicate-tag defect), **DD-3** (a rank ladder that answers the same keystroke by
the same rules as the list beside it), **DD-6** (four absence rules made one pure, testable function
instead of four view `if`s) and **DD-10** (why no visibility relaxation is needed here, unlike m10).

## Architecture Decisions

| # | Decision | Rejected alternative | Rationale |
|---|---|---|---|
| **DD-1** | `TapPackageSearch` is a `public struct: Sendable` holding `inventory: TapInventory` and `installed: InstalledInventory`, with a method `hits(query:kinds:hideInstalled:isInCatalog:)`. The catalog-membership predicate is a **parameter**, never a stored property | A `Hashable` value storing the predicate; a `Set<PackageID>` member; a caseless-enum factory; taking `CatalogStore` | This is `InstalledBrowse` byte-for-byte in shape: `public struct InstalledBrowse: Sendable` (`InstalledFilterMode.swift:62-65`) stores the inventory and takes `catalogLookup: (PackageID) -> CatalogPackage?` as a parameter of `rows(…)` (`:99-107`). **Correction to the launch brief:** a stored closure makes `Hashable` unrepresentable, so `Hashable` is carried by `TapSearchHit`, not by the search type. A `Set<PackageID>` was rejected because `CatalogStore` vends no such set — `BrowseView.swift:118` already passes `{ catalog.package($0) }`, and `PackageSearchIndex.package(_:)` (`:158-160`) is one `[PackageID: Int]` lookup, so the predicate costs O(1) per hit. Keeping it a closure is also what keeps `Catalog` out of the type's stored state, preserving II7's one-directional edge (`Package.swift:62-66`) |
| **DD-2** | Row identity is its own type: `TapSearchHit.RowID { tapName, kind, name }`, `Hashable`, used as `Identifiable.id`. `PackageID` survives **only** as `mutationTarget` — the bare token PM10 puts in argv | `"\(tapName)/\(kind)/\(name)"` as a `String` id; reusing `PackageID` as the row id | **R1.** `TapPackage.id` is `PackageID(kind:, name: bareToken)` (`TapProjection.swift:140`, `:153`) — the *same* identity space the catalog uses, so two rows can share one `PackageID`. A structured id cannot be accidentally compared against, passed to, or matched with a `PackageID`; a `String` id can be pattern-matched and re-parsed. Two taps publishing the same bare name and kind are distinct rows, and `tapName` is what distinguishes them |
| **DD-3** | The ladder is `TapMatchRank: Int, Comparable, Sendable, CaseIterable { exactToken, namePrefix, nameSubstring }` over `PackageText.normalize`, and it matches against **both** the normalised bare token **and** the normalised `publishedName` (the qualified `owner/repo/name` brew publishes). Both forms are token-aware: `exactToken` is the whole normalised string **or** one whole space-delimited token; `namePrefix` is a whole-string prefix **or** a token prefix. A hit that matches **only** via `publishedName` is capped at `nameSubstring` and never ranks higher | `localizedCaseInsensitiveContains`, as `TapProjection.filter(_:query:kind:)` uses (`:176-186`); matching the bare token alone; reusing `PackageSearchIndex`'s byte scans; a full four-class ladder | Explore §6.5: two lists on one screen answering the same keystroke by different rules is a defect waiting to be filed. `PackageText` lives in `Catalog`, which `BrewClient` already imports (`TapProjection.swift:1`), so PS2's single normalisation is **reused, not re-derived**; the classes are the index's first three (`PackageSearchIndex.swift:277-279`), whose `equals`/`hasToken`/`hasPrefix`/`hasTokenPrefix`/`contains` are `private` and so are re-expressed over `PackageText.normalizedString` and its space-delimited tokens. Token-awareness is load-bearing, not decorative: `normalize("gentle-ai")` yields `gentle ai` (`PackageText.swift:28-41` makes `-` a separator), so `ai` must token-match. Matching `publishedName` too is what lets a user who remembers **the tap** rather than the package (`gentleman`) find it at all — the qualified form normalises to `gentleman programming tap gentle ai`. The cap exists because a tap-name match is a weaker statement about the *package* than any match on its own token, and letting it reach `exactToken` would put every package of a matching tap above a genuine name hit. `descriptionSubstring` is **unrepresentable**: a not-installed tap package has no description (explore §2.3, TM5) |
| **DD-4** | A tap row is selectable **iff** `routableID != nil`, a stored `PackageID?` the projection sets. It is `nil` when the hit is not installed, when `alsoInCatalog`, or when another emitted hit carries the same `PackageID`. Selectable rows get `.tag(id)` + `.themedListSelection(isSelected:)`; the rest get `.selectionDisabled()` and **no tag**. `List(selection: $selection)` stays `PackageID?` and `ContentView`/`PackageDetailView` are untouched | A `BrowseSelection` enum wrapping both id types; tagging every installed tap row; relying on SwiftUI ignoring a type-mismatched tag | **R1, R4.** A `BrowseSelection` enum would change `ContentView.swift`'s `@State private var selection: PackageID?` — shared with the Installed, Home and Favorites surfaces — and `PackageDetailView`'s three-way resolution, contradicting the proposal's *"no routing change"*. Keeping `PackageID?` means a colliding tap row must never be tagged: `PackageDetailView` resolves catalog-first, so a tagged colliding row would open the **catalog** package's pane (explore §6.1.2), and duplicate tags in one `List` select together (§6.1.1). Uniqueness among tap hits is checked too, because two taps can publish the same bare name with neither in the catalog — `alsoInCatalog` alone would leave that case tagged twice. **The nil rule lives in the projection, so it is asserted in `BrewClientTests` without SwiftUI**; the view only reads it. The spec is adding this exception explicitly, so the rule is a requirement rather than a view convention |
| **DD-5** | Deterministic order is `(rank asc, name asc, formula before cask, tapName asc)`. Tap hits are never interleaved into PS3's order | Mirroring `PackageSearchIndex.precedes` (`:235-253`); a two-key order | PS3's tiebreak is 365-day install count descending, and a tap package has none (explore §2.3), so the count key is dropped rather than faked with a sentinel. The fourth key is what makes the order **total**: without `tapName`, two taps publishing the same name and kind compare equal and can swap between refreshes — the exact property PS3 buys from `(name, kind)` uniqueness, which tap hits do not have. Source order is `TapProjection(inventory:).thirdPartyTaps` (`:93`), so `homebrew/core` and `homebrew/cask` are excluded by the shipped `officialNames` rule (`:82`) and the catalog is never duplicated into its own section |
| **DD-6** | Section visibility is one pure static function on the projection type — `isSectionVisible(query:outdatedOnly:tapState:)` — returning `false` for a query that normalises to empty, for `outdatedOnly`, and for `.brewAbsent` / `.failed`. The view calls it and renders nothing else | Four `if` conditions in `BrowseView.body`; an error banner for `.brewAbsent`; making `outdatedOnly` an input to `hits(…)` so the Outdated chip filters hits instead of hiding the section | Explore §6.3, §6.8 and obs `#7795` give four separate absence rules. Left in the view they are untestable in the `swift test` inner loop and become the "view accident" §6.3 warns against. Emptiness is judged on the **normalised** query so a whitespace-only query behaves like an empty one — the same guard `PackageSearchIndex.search` applies at `:181`. `TapLoadState` is in the same module (`TapStore.swift:5-11`), so nothing new crosses a target boundary. Absence, never an error: catalog search works with brew absent by design (II7), and a banner would make brew's absence change the catalog result. `outdatedOnly` reaches this function but **not** `hits(…)`: a tap hit carries no version, so filtering by outdatedness would silently emit zero hits and read as "your taps have nothing", which is a different and false claim from "this chip does not apply here" |
| **DD-7** | A colliding hit is **shown**, non-selectable, with a neutral note, and **the projection supplies the note as a string**: `public let collisionNote: String?`, non-nil exactly when `alsoInCatalog`, carrying the pinned sentence `Also in the catalog. Homebrew installs the catalog package.` The view renders it and composes nothing (**PS8**). The argv stays bare | Suppressing the hit; an "Ambiguous" badge; a bare `alsoInCatalog: Bool` with the sentence written in the view; qualifying the argv to disambiguate | Qualifying is **forbidden**: PM10 `:647-652` bans a `/`-qualified token on any path, because Homebrew treats naming a qualified package as the grant (explore §3.1). Suppression would hide a genuine Homebrew ambiguity the user is entitled to see. PS8 requires the copy to be **supplied by the projection and never composed by the view**, so a `Bool` alone is insufficient: it would put the sentence in the app target where no `unit` test can reach it and where a second surface could word it differently. `alsoInCatalog` is retained beside the note because `routableID`'s rule reads it (**DD-4**) and a test asserting "shown, not suppressed" should not have to parse prose. The sentence is **pinned by the spec**: capital `A`, two sentences, terminal periods; `sdd-apply` reproduces it and does not word it. The maintainer's recorded fragment (obs `#7795`) was the lowercase shorthand *"also in the catalog; Homebrew installs the catalog package"*; the spec's pinned sentence supersedes that shorthand |
| **DD-8** | The catalog rows move into a bare `ForEach` with **no** `Section` header; only the tap results get `Section("From your taps")`, rendered **below** them. The row builder, `.tag(entry.id)` and `.themedListSelection` move byte-unchanged | Wrapping the catalog rows in `Section("Catalog")`; two peer sections; a `Divider()` row | **R4.** `List(rows, selection:)` → `List(selection:) { ForEach(rows) … }` has identical identity semantics — `PackageEntry` is `Identifiable` and the tag is explicit (`BrowseView.swift:70`) — so the only behavioural delta is the added section. A "Catalog" header is a visual change nobody asked for and would push every existing row down. Below the catalog rows is the maintainer's accepted recommendation (obs `#7795`). Section title pinned by the proposal (`:26`, `:142`) and by the spec |
| **DD-9** | The row carries name, `KindTag(kind:)`, tap of origin, `hit.stateCopy`, `hit.collisionNote`, and `MutationMenu(center:entry:)` built from `PackageEntry(installed: nil, catalog: nil, id: hit.mutationTarget)`. `stateCopy: String` is **supplied by the projection** (PS8) — `Installed.` / `Installed. Homebrew withholds its tap while this tap is untrusted.` / `Not installed.` — **not** read from `TapPackage.statusExplanation`. **No "Untrusted" badge, no trust read** | Re-implementing an Install button; `TapDetailView`'s `kindBadge`; reusing `TapPackage.statusExplanation`; rendering the trust badge | **Verified:** for `installed == nil` the entry's `isInstalled` is `false` (`InstalledFilterMode.swift:54`) and `MutationMenu` renders exactly `action("Install", .install(target))` plus **Copy install command** (`MutationMenu.swift:32-40`) — the affordance m11 needs, already proven, with `PackageTarget(entry.id)` validation (`:27`, PM9) and the unavailable-runner guidance (`:50-51`, PM7). `displayName` falls back to `id.name` (`InstalledFilterMode.swift:46`), so a `catalog: nil` entry renders its own name. `KindTag` is internal in `cellar/Browse/PackageRow.swift:152` and already used by both shipped rows (`PackageRow.swift:41`, `InstalledRow.swift:41`); `TapDetailView.kindBadge` is `private` (`:208`) and unreachable. **`statusExplanation` is refused with evidence:** it returns `nil` for `.installed` (`TapProjection.swift:52-58`), because TM5's state 1 mandates **Show in Installed** and no copy at all (`openspec/specs/tap-management/spec.md:131-132`), whereas PS8 requires all three Browse states to carry copy. Reusing it would make the row silent for an installed hit and would force the view to compose the missing `Installed.` itself — exactly what PS8 forbids. Its two non-nil strings are reproduced byte-identically in `stateCopy`, so the two surfaces still agree. The badge is refused because TM12 would otherwise need a MODIFIED for a third consumer of `TapProjection.trust(for:)` (explore §6.2), and because PM10 `:659-670` forbids the gate a badge invites |
| **DD-10** | **No `private` is relaxed anywhere.** `TapSearchSection.swift` references only internal symbols; `EmptyResults` (`BrowseView.swift:126`, file-scoped `private`) stays private and stays in `BrowseView`, whose overlay condition becomes `rows.isEmpty && tapHits.isEmpty` | Moving `EmptyResults` into the new file; passing tap hits into `EmptyResults`; a shared `Browse+Rows.swift` | Checked explicitly because m10's **DD-9** had to drop `private` from six helpers for exactly this reason — Swift `private` is file-scoped. Here the new file needs `KindTag` (`PackageRow.swift:152`, internal), `MutationMenu` (internal), `themedListSelection` (`ThemedListSelection.swift:34-40`, internal `extension View`), `ActionPillStyle`/`FilterChip` (internal) and `Theme` (internal) — all reachable. `hideInstalled`/`outdatedOnly` are `@State private var` in `BrowseView` (`:34-35`) and cross as `let` parameters, not as relaxed members. **R5** is answered by the overlay condition alone: no new empty-state copy is invented |
| **DD-11** | The Browse tap surface's freedom from trust is asserted **twice**: (a) extend the shipped `PerPackageTrustSources.views()` (`PerPackageTrustCompositionTests.swift:186-201`) with `cellar/Browse/BrowseView.swift` and `cellar/Browse/TapSearchSection.swift`, updating the sorted-name anchor at `:31-32`; (b) a new `cellarTests/TapSearchCompositionTests.swift` scanning the same two files for `TrustGrantStore`, `TrustGrantState`, `TapProjection.trust(`, `TapCommand`, `"Untrusted"` and `"Trust` — all absent | Only (b); only (a); a scanner private to the new suite | **R3.** (a) is m10's **DD-11** rationale applied unchanged: a surface outside the one enumeration silently escapes the shipped grant-copy guard, whose negative loop at `:60-75` covers every listed source and whose positive assertions are keyed by file name and therefore unaffected. (b) is m11's own, stronger claim — PM10 `:737-743` establishes the idiom of asserting a trust gate as an **absence over a whole surface** rather than leaving it to review. The `#filePath`-anchored reader is the shipped idiom in both targets (`PerPackageTrustCompositionTests.swift:181`, `MutationCommandTargetTests.swift:169-179`) and needs no working-directory assumption. The same new suite carries PS8's copy-location scan (copy present in `TapPackageSearch.swift`, absent from `TapSearchSection.swift`) and the no-new-routing-branch scan, because all three are source-text claims spanning a package file and an app file — which only the app target can read together |
| **DD-12** | `TapPackageSearch`, `TapSearchHit`, `TapMatchRank` are **nonisolated by module default** — no annotation, exactly like `InstalledPackage` — and `Sendable`/`Hashable` **by composition**; no `@unchecked`, no actor, no `@MainActor`. The view stays `@MainActor` and builds the value **synchronously inside `body`**: no `Task`, no `.task {}`, no `await` in the render path | Building it in `.task {}` into `@State`; an `@Observable` search store; caching it on `TapStore` | `Package.swift` declares no `.defaultIsolation(MainActor.self)` for any CellarCore target (`:5-7`, `:62-66`), so the package is nonisolated under Swift 6 mode; the app target is `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`project.pbxproj:451`, `:488`), so the views need no annotation either. Both inputs are already resident and already `Sendable` — `TapStore` is `@MainActor @Observable` holding a `Sendable` inventory (`TapStore.swift:13-17`) — and the work is a linear scan, the same idiom as the shipped `browse`/`rows` computed properties (`BrowseView.swift:86-88`, `:107-122`). Async here would introduce a frame where the section is empty for a value that was never absent, plus a cache to invalidate |
| **DD-13** | **No `#available` branch.** `Section` and `.selectionDisabled(_:)` are used unguarded | An availability guard around `selectionDisabled` | The deployment target is macOS 26.0 in every configuration (`project.pbxproj:355`, `:413`, `:503`, `:524`) and `Package.swift:7` declares `.macOS("26.0")`. Both APIs predate it, so a guard would be dead code and would violate the project's no-`#available` rule |

### Rejected approaches (explore §5)

| Approach | Why rejected |
|---|---|
| **B — merged ranked list** | PS3's total order is defined over catalog records and broken by install count descending; a tap package has none, so interleaving either restates PS3 or contradicts it. `MatchRank` is dropped at `CatalogStore.rerank()` (`:315-318`) and would have to be re-plumbed through `results` and `PackageEntry` into every consumer (~10 files). It is also the highest PD6 leak risk: indistinguishable from catalog search results, which is precisely the reading PD6 forbids |
| **C — ingest tap names into `PackageSearchIndex`** | **Named rejected in the proposal (`:52-54`) and restated here.** It falsifies PD6's *"MUST be absent from the snapshot"* and its covered-tap scenario, contradicts TM5's *"MUST NOT enter the catalog snapshot, catalog search"*, and structurally requires `Catalog` to depend on `BrewProcess` (tap data originates in `brew tap-info`), which II7's package-graph scenario asserts against and `Package.swift:37-43` encodes as an absent dependency. It would also break catalog search working with brew absent |
| **D — a "Taps" scope control on the search field** | Does not solve the reported problem. The complaint is *"I searched and found nothing"*; a scope the user must know to switch to reproduces exactly that |

## Interfaces / Contracts

```swift
// Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift
import Catalog

/// The three classes a name-only record can match, strongest first.
/// `PackageSearchIndex`'s first three (`:277-279`); the fourth needs a
/// description, which a not-installed tap package does not have (DD-3).
public enum TapMatchRank: Int, Comparable, Sendable, CaseIterable {
    case exactToken = 0, namePrefix, nameSubstring
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct TapSearchHit: Sendable, Hashable, Identifiable {
    /// Row identity — deliberately NOT a `PackageID` (DD-2, R1).
    public struct RowID: Sendable, Hashable {
        public let tapName: String
        public let kind: PackageKind
        public let name: String
    }
    public let id: RowID
    /// The bare token argv names. PM10: never `/`-qualified.
    public let mutationTarget: PackageID
    /// The qualified name brew publishes, for display only. Never argv.
    public let publishedName: String
    public let displayName: String
    public let tapName: String
    public let state: TapPackageInstallState
    /// PS8: the copy is supplied here, never composed by the view (DD-9).
    /// `Installed.`
    /// `Installed. Homebrew withholds its tap while this tap is untrusted.`
    /// `Not installed.`
    /// NOT `TapPackage.statusExplanation`, which is `nil` for `.installed`.
    public let stateCopy: String
    /// A catalog record carries this bare token, so Homebrew resolves the
    /// install there. Surfaced, never suppressed (DD-7).
    public let alsoInCatalog: Bool
    /// PS8: non-nil exactly when `alsoInCatalog`. Pinned sentence —
    /// `Also in the catalog. Homebrew installs the catalog package.`
    public let collisionNote: String?
    public let rank: TapMatchRank
    /// The identity this row may hand to `List(selection:)`, or `nil` when it
    /// must not be selectable: not installed, `alsoInCatalog`, or another
    /// emitted hit shares this `PackageID` (DD-4).
    public let routableID: PackageID?
}

public struct TapPackageSearch: Sendable {
    public let inventory: TapInventory
    public let installed: InstalledInventory

    public init(inventory: TapInventory, installed: InstalledInventory)

    /// Ordered by `(rank, name, kind, tapName)` — total (DD-5).
    /// `isInCatalog` is a parameter, never stored (DD-1).
    public func hits(
        query: String,
        kinds: Set<PackageKind>,
        hideInstalled: Bool,
        isInCatalog: (PackageID) -> Bool
    ) -> [TapSearchHit]

    /// The four absence rules, in one pure place (DD-6).
    public static func isSectionVisible(
        query: String,
        outdatedOnly: Bool,
        tapState: TapLoadState
    ) -> Bool
}
```

Reuse, not re-derivation: hits are built from `TapProjection.packages(for:installed:)`
(`TapProjection.swift:134-162`), which already applies `bareToken(_:publishedBy:)` (`:208-211`), keeps the
qualified `publishedName` **DD-3** matches against, and resolves the three-valued
`TapPackageInstallState` (`:25-30`). `hideInstalled` drops hits whose `state != .notInstalled`, matching
what `BrowseView.swift:120-121` already does to catalog rows.

**Every user-visible string on this surface originates here.** `stateCopy`, `collisionNote` and the
section title are the projection's or the spec's; `TapSearchSection.swift` contains no copy literal of its
own, and **DD-11**'s scan asserts that as an absence rather than leaving it to review (PS8).

## Data Flow

    brew tap-info --installed --json          brew info --installed --json=v2
        │ (already shipped, TM1)                   │ (already shipped)
        ▼                                          ▼
    TapStore.inventory ─────────────┐   InstalledStore.inventory
        │ TapLoadState              │          │
        ▼                           ▼          ▼
    isSectionVisible(query:outdatedOnly:tapState:)   TapPackageSearch(inventory:installed:)
        │ false ⇒ nothing renders                    │  .hits(query:kinds:hideInstalled:
        │                                            │        isInCatalog: { catalog.package($0) != nil })
        ▼                                            ▼
    BrowseView (@MainActor, synchronous, per keystroke)
        List(selection: $selection)
          ├─ ForEach(rows)  ── PackageRow + MutationMenu ── .tag(entry.id)      [unchanged]
          └─ Section("From your taps") ── TapSearchSection
                 └─ TapSearchRow: name · KindTag · tapName · hit.stateCopy
                                  · hit.collisionNote · MutationMenu(entry: PackageEntry(
                                        installed: nil, catalog: nil, id: hit.mutationTarget))
                    routableID != nil ⇒ .tag(id)  ⇒ PackageDetailView ⇒ m10 receipt pane
                    routableID == nil ⇒ .selectionDisabled()

`PackageSearchIndex` appears nowhere on this path. That is the PD6/TM5 argument, and it is structural
rather than asserted: the section's only inputs are the tap inventory, the installed inventory and a
membership predicate.

## File Changes

| File | Action | Est. lines | Description |
|---|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift` | Create | 150–210 | The hit, the ladder, the order, the collision rule, the visibility rule, **and the four pinned copy strings** (PS8) |
| `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | Create | 340–480 | RED map below, including the PS8 combined-turn latency harness (~40–60 of these lines). `BrewClientTests` is the right suite for the PD6/TM5 rows too: `BrewClient` depends on `Catalog` (`Package.swift:62-66`), so a real `PackageSearchIndex` is constructible there without a new target — m10's design made this exact argument |
| `cellar/Browse/TapSearchSection.swift` | Create | 110–160 | The `Section`, the row, the selection rule's view half |
| `cellar/Browse/BrowseView.swift` | Modify | 40–70 | `let taps: TapStore`; `List(selection:)` + `ForEach`; the section; overlay condition. Prompt string **unchanged** |
| `cellar/ContentView.swift` | Modify | 1 | `taps: taps` at `:307-315` |
| `cellarTests/TapSearchCompositionTests.swift` | Create | 150–210 | Composition + source-text absences (DD-11b) + the PS8 copy-location scan + the no-new-routing-branch scan |
| `cellarTests/PerPackageTrustCompositionTests.swift` | Modify | 3 | Two paths + the sorted anchor (DD-11a) |
| `openspec/changes/m11-tap-search/specs/` | Create | 180–280 | `package-search` ADDED (incl. **PS8**), PD6/TM5/**TM11** MODIFIED — owned by `sdd-spec` |
| `cellar.xcodeproj/project.pbxproj` | **Untouched** | **0** | `path = cellar` (`:46`) and `path = cellarTests` (`:51`) are `PBXFileSystemSynchronizedRootGroup`s, so both new app-target files join their targets with a 0-line diff. `Packages/CellarCore` is SwiftPM and has no pbxproj at all. A non-zero diff is a defect, not a rollback step |

**Budget.** ~970–1,420 code and spec lines, plus ~400–600 artifact lines → **~1,370–2,020 against 5,000**.
`400-line budget risk: N/A` (project budget is 5,000); **5,000-line budget risk: Low**. Single PR under the
cached `single-pr` strategy. **R7** stands: `sdd-tasks` forecasts artifacts separately and emits the guard
lines explicitly.

## Testing Strategy

Strict TDD: every row is RED before its implementation exists. Verification classes are the spec's two:
**`unit`** (`swift test --package-path Packages/CellarCore`) and **`unit-app`** — the established class for
a RED-first assertion over the app target's composition (`openspec/specs/app-updates/spec.md:17`), run by
`xcodebuild test … -only-testing:cellarTests`.

> **Reconciliation obligation.** `specs/` is being authored in parallel and does not exist on disk at the
> time of writing. The rows below are keyed to the requirement clauses the proposal (`:60-78`) and obs
> `#7795` fix. Before `sdd-tasks` closes, every scenario in the delivered `specs/` MUST have a row here,
> matched **scenario by scenario**; a scenario with no RED row is a gate failure, not a rounding error.
> All quoted copy is **pinned by the spec** — `sdd-apply` reproduces it and does not choose it.
>
> **Requirement ordinals.** This document uses the **promoted main spec's** markers:
> `<!-- TM11 -->` (`openspec/specs/tap-management/spec.md:532`) is the adjacent-capabilities requirement
> this change MODIFIES, and `<!-- TM12 -->` (`:560`) is the trust-presentation requirement it leaves
> untouched. `explore.md` and `proposal.md` call these **TM10** and **TM11** respectively, using the
> pre-promotion ordinals; the requirements are the same, only the numbering moved.

| Class | RED test | Asserts (requirement clause) |
|---|---|---|
| `unit` | `aTapPackageIsFoundByANonEmptyQuery` | PS-new: a name published only by a third-party tap produces a hit carrying `displayName`, `kind`, `tapName`, `state` and `mutationTarget`; the hit exposes no description, version, homepage, licence, dependency, install count, deprecation flag or size (the absent field set is enumerated, not assumed) |
| `unit` | `theLadderConvergesWithTheCatalogIndexOnOneFixture` | PS-new / PS2: for a shared name set, `TapMatchRank` classifies exactly as `PackageSearchIndex.search` does for its first three classes — exact, whole-token, prefix, token-prefix and substring (DD-3) |
| `unit` | `aHyphenatedNameMatchesByTokenAtEveryRung` | DD-3, keyed to the maintainer's own package: for `gentle-ai` (normalising to `gentle ai`), query `ai` ⇒ `.exactToken` (whole token), `gent` ⇒ `.namePrefix` (token prefix), `tle` ⇒ `.nameSubstring`; all three are hits, and the three ranks are distinct |
| `unit` | `aTapNameQueryMatchesThroughThePublishedName` | DD-3: query `gentleman` matches `gentleman-programming/tap/gentle-ai` via the normalised `publishedName` while matching the bare token not at all; the hit is emitted and its rank is capped at `.nameSubstring`, so it sorts below any hit matching on its own token |
| `unit` | `theOrderIsTotalAndReproducible` | PS-new / PS3-analogue: `(rank, name, kind, tapName)`; two taps publishing the same name and kind keep a stable relative order across repeated calls and across shuffled inventory input (DD-5) |
| `unit` | `officialTapsNeverEnterTheSection` | PS-new: a `homebrew/core` or `homebrew/cask` record in the inventory produces **no** hit (DD-5, `TapProjection.officialNames`) |
| `unit` | `theKindFilterIsHonoured` | PS-new / PS4: `kinds: [.formula]` emits no cask hit and vice versa; the declared `SearchFilters` set is **not** extended |
| `unit` | `hideInstalledSubtractsFromTheSection` | obs `#7795`: `hideInstalled` drops `installed` **and** `installedTapWithheld` hits and keeps `notInstalled` ones |
| `unit` | `theSectionIsAbsentForAnEmptyOrWhitespaceQuery` | PS-new / explore §6.3: `isSectionVisible` is `false` for `""` and for `"   "` (normalised emptiness), `true` for a real query |
| `unit` | `theOutdatedChipHidesTheSection` | obs `#7795`: `outdatedOnly` ⇒ `isSectionVisible == false`, whatever the query |
| `unit` | `absentOrFailedTapStateHidesTheSectionWithoutAnError` | PS-new / explore §6.8: `.brewAbsent` and `.failed` ⇒ `false`; `.idle`, `.loading`, `.loaded` ⇒ visibility decided by the query alone; no error value is produced |
| `unit` | `aCollidingHitIsShownAndIsNotRoutable` | **R1**, DD-7: a bare token also present in the catalog ⇒ hit emitted, `alsoInCatalog == true`, `routableID == nil`; the hit is **not** suppressed |
| `unit` | `twoTapsPublishingOneNameAreBothUnroutable` | DD-4: neither in the catalog, both installed ⇒ two hits, distinct `RowID`s, both `routableID == nil` |
| `unit` | `anInstalledUnambiguousHitIsRoutable` | DD-4: installed, not in the catalog, unique ⇒ `routableID == mutationTarget`; `installedTapWithheld` routes too, because the handoff selects by exact `PackageID` and that identity is exact regardless of what brew withholds (`openspec/specs/tap-management/spec.md:133-138`, mirroring `TapPackage.installedHandoff`) |
| `unit` | `aNotInstalledHitIsNeverRoutable` | obs `#7795` / explore §6.4(a): `state == .notInstalled` ⇒ `routableID == nil` on every path |
| `unit` | `everyMutationTargetIsBare` | PM10 `:647-652` cited, not restated: no emitted `mutationTarget.name` contains `/`, for a formula or a cask, including a deeply qualified `publishedName` |
| `unit` | `theThreeInstallStatesCarryTheirExactCopy` | **PS8**, DD-9: `stateCopy` is byte-exactly `Installed.` / `Installed. Homebrew withholds its tap while this tap is untrusted.` / `Not installed.` for the three `TapPackageInstallState` values; never empty, never `nil`-equivalent. Guards the `statusExplanation` trap — the `.installed` case must **not** be silent |
| `unit` | `theCollisionNoteIsPresentExactlyWhenItIsTrue` | **PS8**, DD-7: `collisionNote == "Also in the catalog. Homebrew installs the catalog package."` byte-exactly when `alsoInCatalog`, and `nil` otherwise; the two fields never disagree |
| `unit` | `theProjectionTakesNoLauncherAndNoCatalogStore` | PS-new: the type's whole input surface is two inventories, a query, a kind set, a `Bool` and a predicate — no `BrewProcess` type, no `CatalogStore`, no `Process`, no clock is constructible into it (kept as a `unit` row: it is a parameter-surface claim, not a source-text one) |
| `unit` | `aTapPackageFoundHereAddsNoTapManagementAction` | **TM11**'s preserved scenario: composing and rendering a tap search hit adds nothing to the tap-management action set — the enumerated actions stay refresh, filter, Installed handoff, canonical add, plain untap, eligible force untap, trust and untrust, byte-identical; this surface offers install through `package-mutation` and detail through `package-search`, neither of which is a tap-management action |
| `unit` | `theCombinedKeystrokeTurnStaysUnderTheCeiling` | **PS8** latency: the shipped PS6 catalog fixture **plus** a synthetic tap inventory of ~500 packages spread across several taps; ≥100 distinct queries; each turn runs the catalog query **and** the tap composition together, as `BrowseView` does. p95 < 8 ms for the **combined** turn. Explicitly **not** a re-run of the shipped PS6 measurement — that one never touches the tap inventory and so cannot show a regression caused by this change (**R6**) |
| `unit` | `aComposedTapSearchLeavesTheIndexUnchanged` | **PD6's added scenario**: a real `PackageSearchIndex` built from a snapshot answers `search(name)` and `package(id)` identically before and after a tap search over a name absent from the snapshot; no `CatalogPackage` exists for the tap hit |
| `unit` | `theTapInventoryFeedsASurfaceOutsideTapManagement` | **TM5's added clause**: the section is composed from the inventory alone — no tap-source read, no catalog record created, no additional brew invocation recorded (asserted over a recording launcher that is never called) |
| `unit-app` | `browseComposesTheTapSectionFromTheResidentStore` | Composition: `BrowseView` holds `let taps: TapStore` and `ContentView` passes `taps:`; the section is built from `TapPackageSearch(` with `isInCatalog:` supplied by `catalog.package(` |
| `unit-app` | `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge` | **R3**, DD-11b: `BrowseView.swift` and `TapSearchSection.swift` contain no `TrustGrantStore`, `TrustGrantState`, `TapProjection.trust(`, `TapCommand`, `"Untrusted"` or `"Trust` |
| `unit-app` | `theGrantCopyGuardCoversTheNewSurface` | DD-11a: `PerPackageTrustSources.views()` returns the extended sorted-name list including `BrowseView.swift` and `TapSearchSection.swift`; the existing negative loop (`:60-75`) passes for both |
| `unit-app` | `theTapRowOffersInstallThroughTheSharedMenu` | DD-9: `TapSearchSection.swift` contains `MutationMenu(center:` and `PackageEntry(installed: nil, catalog: nil`; it constructs **no** `MutationCommand` and no `PackageTarget` itself |
| `unit-app` | `theSurfaceCopyLivesInTheProjectionNotTheView` | **PS8**, DD-7, DD-9: source scan — `TapPackageSearch.swift` **contains** `Installed.`, `Installed. Homebrew withholds its tap while this tap is untrusted.`, `Not installed.` and `Also in the catalog. Homebrew installs the catalog package.`; `TapSearchSection.swift` contains **none** of the four. The pinned section title is present in the view (it is `Section` copy, not hit copy) and is byte-exact |
| `unit-app` | `theReceiptDetailIsReachedWithNoNewRoutingBranch` | PS-new / II15: source scan — `TapSearchSection.swift` tags a routable tap row with `hit.routableID` (a `PackageID`) and nothing else, so an installed tap hit lands on the shipped `PackageDetailView` fallthrough; `PackageDetailView.swift` gains **no** new resolution branch, no tap import and no `TapSearchHit` reference (**DD-4**'s "no routing change") |
| `unit-app` | `neitherTapSearchFileReachesTheProcessLayer` | PS-new: source scan over **both** `TapPackageSearch.swift` and `TapSearchSection.swift` — no `BrewProcess` import, no `Process`, no launcher, no `refresh(` call. Reclassified from `unit` because it is a source-text claim over one package file and one app file, which only the app target can scan together |
| `unit-app` | `notInstalledTapRowsAreNotSelectable` | DD-4: the file contains `.selectionDisabled(` and tags only through `hit.routableID`; no unconditional `.tag(hit.mutationTarget)` appears |
| `unit-app` | `theSearchPromptStillCountsCatalogRecordsOnly` | obs `#7795`: `BrowseView.swift`'s prompt literal is unchanged and references neither `taps` nor the tap hit count |
| `unit-app` | `theEmptyStateYieldsToTapHits` | **R5**, DD-10: the overlay is guarded by both row sources; `EmptyResults` remains `private` and gains no tap parameter |
| `unit-app` | `catalogRowSelectionIsUnchanged` | **R4**: the catalog `ForEach` still tags `entry.id` and still applies `themedListSelection`; no `Section` header is composed for it |

**Existing tests that MUST keep passing, unchanged in meaning:** `PerPackageTrustCompositionTests` (both
tests, with only DD-11a's 3-line list and anchor edit), `TapProjectionTests`, `TapShippingProofTests`,
`MutationCommandTests`, `MutationCommandTargetTests`, `SearchIndexTests`, `FilterTests`,
`InstalledFilterCompositionTests`, `ReceiptDetailCompositionTests`, `PackageGraphTests`. Commands:
`swift test --package-path Packages/CellarCore` for the inner loop, then the full
`xcodebuild test … -scheme cellar`. **The latency claim is measured, not assumed** — but by the *new*
`theCombinedKeystrokeTurnStaysUnderTheCeiling` row, which exercises the catalog query and the tap
composition on one turn. Re-running the shipped PS6 measurement alone would prove nothing here: it never
touches the tap inventory, so it cannot observe the regression this change could cause (**R6**).

## Threat Matrix

**N/A — no new routing, shell, subprocess, VCS/PR automation, executable-file classification, or
process-integration boundary.** The section introduces **no brew invocation** (the tap inventory is
already resident from the shipped TM1 refresh; pinned by the
`theTapInventoryFeedsASurfaceOutsideTapManagement` RED row), reads only stores that are already wired and
already refreshed, and constructs no argv: install goes through the byte-unchanged `MutationMenu`, whose
`PackageTarget(entry.id)` validation and confirmation rules are already proven (PM7, PM9, PM10). The one
behavioural exposure — Homebrew refusing to load a package from an untrusted tap — is **inherited
unchanged** from the shipped spine: it is the measured non-interactive refusal
(`MutationOutcome.refusedUntrustedTap`, `MutationOutcome.swift:71` — the typed outcome; the `Signature`
that classifies it is `private`) plus `UntrustedTapRecovery`'s Trust affordance, already
end-to-end against Homebrew 6.0.18 (explore §3.3). It is therefore not a new boundary for this change to
gate — and PM10 `:659-670` forbids gating it.

## Migration / Rollout

No migration required. Nothing persists: no file format, no stored state, no new process, no new brew
invocation. Reverting the PR deletes `TapPackageSearch.swift`, `TapSearchSection.swift` and two test
files, restores `BrowseView`'s flat `List(rows, selection:)` and drops one argument at
`ContentView.swift:307-315`; no visibility relaxation has to be undone (**DD-10**). The four deltas revert
with the change folder; promoted `openspec/specs/` are untouched until archive.

## Open Questions

- [x] **Closed** (obs `#7795`, binding): section below the catalog rows; neutral collision note, no nudge;
      "Hide installed" subtracts from the section; the Outdated chip hides it; the prompt stays
      catalog-only.
- [x] **Closed** (explore §6.2, DD-9): tap name only, no "Untrusted" badge — **TM12** untouched
      (`openspec/specs/tap-management/spec.md:560`; explore calls it TM11).
- [x] **Closed** (explore §6.4(a), DD-4): not-installed tap rows are non-selectable; a name-only detail
      pane is a scoped follow-up, out of scope here.
- [x] **Closed by the parallel spec amendment (PS8).** Copy is owned by the projection, not the view, and
      every string is pinned: `Installed.`, `Installed. Homebrew withholds its tap while this tap is
      untrusted.`, `Not installed.`, `Also in the catalog. Homebrew installs the catalog package.` The
      maintainer's lowercase shorthand in obs `#7795` is superseded by the pinned sentence (**DD-7**).
      `sdd-apply` reproduces these strings; it does not choose them.
- [ ] **Still open for `sdd-tasks`, not blocking this design.** `specs/` is being authored in parallel.
      `sdd-tasks` MUST reconcile the RED map against the delivered scenarios **scenario by scenario**
      before closing, and MUST confirm the delivered `package-search` ADDED block numbers this
      requirement **PS8** and the `tap-management` MODIFIED block targets **TM11**.
