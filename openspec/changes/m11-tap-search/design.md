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

**Round 3 (2026-08-25 maintainer UI feedback).** **DD-9** is rewritten and **DD-7** amended: the row's
install state is presented by the shared `Installed` pill rather than by a sentence, and only the
withheld state keeps a projection-supplied note. **DD-18** is new and carries the extraction that makes
"the same pill" literally true. Nothing else moves — **DD-8**'s zero-diff on `BrowseView.swift` is
unaffected, because the pill is declared in `PackageRow.swift`.

**Round 4 (2026-08-25 maintainer UI feedback).** **DD-19** is new: the hit gains a stored
`nextVersion: String?`, derived from the installed receipt the projection already holds, and the tap row
draws the shipped shared `UpdateTag` after the installed pill. Nothing else moves — **DD-8** is again
unaffected, and this time `PackageRow.swift` needs no edit at all, because `UpdateTag` is already an
internal component both surfaces can reach.

**Round 6 (2026-08-25 maintainer product decision).** **DD-21** and **DD-22** are new and together
supersede **DD-4**'s install-state conjunct: `routableID` becomes routable **iff** unambiguous, and an
unambiguous not-installed hit lands on a new, name-only pane fed by the resident tap inventory. **DD-8**
is unaffected for the fifth round running; **DD-18**, **DD-19** and **DD-20**'s components are untouched.
What does move is a property no earlier round had to give up: `PackageDetailView.swift`'s zero diff. It
gains the third branch and one stored parameter, and the bindings proof narrows from "byte-identical" to
"these two hunks and nothing else".

**Round 5 (2026-08-25 maintainer UI feedback).** **DD-20** is new and supersedes **DD-9**'s entry clause:
the hit gains a stored `installed: InstalledPackage?`, resolved by the **same** `installedHandoff` lookup
**DD-19** already performs, and the row hands it to the shared `MutationMenu` so an installed tap package
offers the verbs the Installed and catalog surfaces already offer it. Nothing else moves — **DD-8** is
unaffected for the fourth round running, and `MutationMenu.swift` needs no edit at all, because every verb
and its applicability rule are already declared there.

### Carried unchanged (shipped on `dbc5233`)

| # | Decision | Where it lives now |
|---|---|---|
| **DD-1** | `TapPackageSearch` is `public struct: Sendable`; `isInCatalog` is a **parameter**, never stored — mirroring `InstalledBrowse` (`InstalledFilterMode.swift:62-65`, `:99-107`). `Hashable` is carried by the hit, not the search type | `TapPackageSearch.swift:88-123` |
| **DD-2** | Row identity is `TapSearchHit.RowID { tapName, kind, name }`; `PackageID` survives only as `mutationTarget` (**R1**) | `:32-47` |
| **DD-3** | Ladder `{ exactToken, namePrefix, nameSubstring }` over `PackageText.normalize`, matching **both** the bare token and the qualified `publishedName`, with a `publishedName`-only match capped at `nameSubstring` | `:214-228` |
| **DD-4** | Selectable **iff** `routableID != nil` — nil when not installed, when `alsoInCatalog`, or when another emitted hit shares the `PackageID`. Selection stays `PackageID?` | `:64-67`, `:152-172` |
| **DD-5** | Order `(rank asc, normalised token asc, formula before cask, tapName asc)` — total. Official taps excluded via `TapProjection.thirdPartyTaps` | `:245-252`, `:128` |
| **DD-7** (amended r3) | The projection supplies `collisionNote: String?` — `Also in the catalog. Homebrew installs the catalog package.` — never the view (**PS8**). **Round 3**: `stateNote: String?` joins it on exactly the same terms, non-`nil` for the withheld state alone. The two are now the *only* projection-supplied row sentences | `:107-108`, `:169` |
| **DD-9** (rewritten r3, entry clause superseded r5 by **DD-20**) | The row renders `KindTag`, then `StatusPill.installed` when `hit.isInstalled`, then `hit.stateNote` and `hit.collisionNote` when either is non-`nil`; it builds `MutationMenu` from ~~`PackageEntry(installed: nil, catalog: nil, id:)`~~ → **`PackageEntry(installed: hit.installed, catalog: nil, id:)`** (**DD-20**; `catalog: nil` is unchanged and still load-bearing, per PD6). **`TapPackage.statusExplanation` is now the right shape after all** — `nil` for `.installed`, TM5's sentence for the withheld state — but it is still not reused directly: it answers `"Not installed."` for the third state, which this surface withdrew, and it is a projection of a *different* row type. `TapPackageSearch` keeps its own `note(for:)`. No "Untrusted" badge — **TM12** untouched | `:103-108`, `:230-236` |
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
| **DD-18 (new, r3)** | `PackageRow`'s `private func statusPill(_:background:foreground:)` is **extracted to an internal `StatusPill` view** in a new file `cellar/Browse/StatusPill.swift`, with a `static var installed` carrying the pinned `Installed` label and the success colours. `PackageRow` and `TapSearchView` both draw it; neither declares the label | A second pill literal in `TapSearchView`; relaxing `statusPill` to internal and calling it across files (impossible — Swift `private` is file-scoped, and a method on `PackageRow` is not reachable anyway); moving the pill into `KindTag`'s file as a free function; projection-supplied pill copy | PS8's round-3 clause asks for the **same** pill, not an identical-looking one, and `private` file scope makes "same" unrepresentable without extraction. `BrowseView.swift` is untouched by the move (`statusPill` lives in `PackageRow.swift`, which is not under the zero-diff constraint), so **DD-8 survives intact** — this is the extraction DD-10 could not do for `EmptyResults`, available here only because the declaration is in a file that may change. `project.pbxproj` needs no edit: `path = cellar` is a `PBXFileSystemSynchronizedRootGroup` (`:46`), the same reason `TapSearchView.swift` needed none. The label is *not* projection-supplied: it is a presentation constant of the shared component, and putting it in `TapPackageSearch` would give the catalog surface a reason to import the tap projection |
| **DD-19 (new, r4)** | `TapSearchHit` gains a **stored** `nextVersion: String?`, computed in `hits(…)` as `match.package.installedHandoff.flatMap { installed.package($0) }.flatMap { $0.isOutdated ? $0.catalogVersion : nil }`. `TapSearchView`'s row draws the **shipped** `UpdateTag(nextVersion:)` immediately after `StatusPill.installed`, gated on `hit.nextVersion != nil`. `PackageRow.swift` is **not edited** | A computed `nextVersion` reading a stored `InstalledPackage` on the hit (drags a whole receipt, and its `Hashable`, into a value that carries facts); a `Bool` `isOutdated` plus a separate version lookup in the view; extracting `UpdateTag` to its own file for symmetry with `StatusPill`; reading the tap's published version (does not exist — TM5 forbids the source read) | **The receipt is the only honest source.** `InstalledInventory` is already a stored property of `TapPackageSearch`, and `InstalledPackage.isOutdated` is II4's shipped rule including the self-updating-cask exclusion — so the surface cannot disagree with the Installed list without one of them being rewritten. The lookup is keyed off **`TapPackage.installedHandoff`**, not off the raw `PackageID`: `TapProjection.installState` deliberately returns `.notInstalled` for a receipt whose `tap` names a *different* tap (`TapProjection.swift:239-247`), so keying off the id alone would hang an UPDATE pill on a row this surface calls not-installed. **Stored, not computed**, unlike `isInstalled`: a computed property is invisible to `Mirror`, and PS8's facts scenario reads that enumeration — an offered version that never appears there would be a fact the enumeration denies exists. The scenario and its test are amended to list it, and the requirement now says **six** facts. **`UpdateTag` needs no extraction**: it is already `internal` at `PackageRow.swift:114`, already drawn by the Installed and Updates lists, and already takes the version as a **value** — the shape DD-18 had to *create* for the installed pill exists here for free, so round 4 costs `PackageRow.swift` a zero-line diff. Leaving it in `PackageRow.swift` rather than moving it beside `StatusPill.swift` is deliberate: a move is a diff on a file with no reason to change, and `internal` already makes "the same component" representable, which was DD-18's whole problem |
| **DD-17 (new)** | The surface's own copy — the search-field prompt, the section title and the four empty states — is **pinned by the spec**. The **count** behind the prompt and the shell title bar comes from a new pure `TapPackageSearch.packageCount(inventory:)`, not from a view-side sum | A view-side `inventory.taps.reduce(0)`; no count at all; reusing `TapProjection.packageSummary(for:)` | PS8's copy-ownership clause already requires the *hit's* sentences to come from the projection (**DD-7**, **DD-9**); a count rendered beside them is the same kind of claim and belongs in the same place, where a `unit` test can reach it. `packageSummary(for:)` (`TapProjection.swift:166`) is per-tap and formats a different sentence ("5 formulae · 1 cask"), so reusing it would mean reformatting its output. `sdd-apply` reproduces the pinned strings; it does not choose them |
| **DD-20** (new, r5) | `TapSearchHit` gains a **stored** `installed: InstalledPackage?`, resolved in `hits(…)` by the **same** `TapPackage.installedHandoff` → `InstalledInventory.package(_:)` lookup **DD-19** already performs, and `nextVersion` is derived from that one resolved receipt rather than resolving it a second time. `TapSearchView`'s row builds `PackageEntry(installed: hit.installed, catalog: nil, id: hit.mutationTarget)`, so `MutationMenu`'s shipped `entry.isInstalled` branch is taken for an installed hit. `MutationMenu.swift` is **not edited** | The view resolving the receipt itself from `installed.inventory` (the `unit` layer could then prove nothing about the keying, and the view would own a rule); exposing `installedHandoff: PackageID?` on the hit and letting the view do the lookup (same objection, plus a stored member that is *also* not a fact); a bare `PackageID` lookup in the view or the projection; giving `MutationMenu` a second initialiser that takes a hit; making `nextVersion` computed off the new member | **The keying is the whole defect.** A bare `PackageID` lookup answers `.notInstalled`'s receipt for a withheld-tap row and, worse, attaches a *colliding catalog package's* receipt to a tap row — offering Uninstall for a package the row does not name. `installedHandoff` is already the exact-identity handoff TM5 defines for both installed states, and **DD-19** already proved it under test, so round 5 reuses the resolved value rather than adding a second lookup with a second chance to disagree. **Stored, not computed**, for the same reason **DD-19** stored `nextVersion`: `Mirror` enumerates stored properties and PS8's facts scenario reads that enumeration. It is enumerated there as a **handoff, not a seventh fact** — it carries nothing the tap publishes, and the surface presents nothing from it. `nextVersion` **stays stored** and keeps its own `Mirror` row; it is now derived from the resolved receipt so the two can never disagree about which receipt answered. **DD-19**'s rejected alternative — "a computed `nextVersion` reading a stored `InstalledPackage`" — is not what this is: `nextVersion` remains stored and remains the fact; the receipt is carried *additionally*, because the shared mutation spine takes a `PackageEntry` whose `installed` slot is exactly this record and there is no smaller value that satisfies it. `InstalledPackage` is already `Sendable, Hashable`, and the hit's hand-written `hash(into:)` combines `id` alone, so neither conformance moves. `MutationMenu` needs no edit at all: `entry.isInstalled`, `isOutdated`, `isPinned`, `FormulaID`/`CaskID` narrowing and the confirmation rule are all already there, which is why round 5 re-implements no verb |
| **DD-21** (new, r6) | `routableID` becomes `collides == false && unique` — the `isInstalled` conjunct is **deleted**, so routability is a fact about **identity** alone in both install states. Resolution moves into a new pure `TapInventoryDetail` in `BrewClient`: `resolve(_ id: PackageID, in inventory: TapInventory) -> TapInventoryDetail?`, which walks `TapProjection(inventory:).thirdPartyTaps`, keeps the taps where `TapProjection.publishes(id, in: tap)` answers true, and returns a value **only when exactly one** does
**and this machine holds no receipt for the identity** — the same `installed.package(id)` question the
receipt branch asks, so the two can never both answer. `kind` is **computed** off `id` rather than
stored: unlike **DD-19**'s `nextVersion`, it is not invisible to `Mirror` — `id` is enumerated and
carries it — and a second stored copy of a fact `id` already holds is the drift these rules forbid. `PackageDetailView.body` gains a **third** branch after the catalog and receipt branches, resolving against `taps.inventory`; zero or several publishers fall through to the shipped `ContentUnavailableView` | Letting the view walk `TapStore.inventory` itself (the `unit` layer could then prove nothing about the exactly-one rule, and the view would own it); a `TapProjection.publisher(of:in:) -> TapRecord?` returning the record (the pane would then re-derive the display name and the copy from it, which is the drift the projection exists to prevent); resolving against `TapPackageSearch.hits(query:…)` (a *search* answering a *detail* question, and it needs a query, a kind set and a catalog predicate the pane has none of); putting the branch **before** the receipt branch (an installed tap package would lose its receipt pane) | The exactly-one rule is the whole safety property, and it is the one a test must be able to reach without rendering anything. `TapProjection.publishes(_:in:)` already exists and already owns "does this tap publish this exact `(kind, name)`", so the resolution composes it rather than restating it — the same reuse **DD-6** made of `TapProjection.state(…)`. The branch's **position** is load-bearing and asserted: catalog first (unchanged), then the receipt (m10, unchanged), then the inventory. A package this machine has installed therefore always reaches its receipt pane, and this branch answers only for one it does not — which is exactly the case the receipt branch cannot answer |
| **DD-22** (new, r6) | The pane is `cellar/Browse/PackageDetailView+TapInventory.swift`, an extension mirroring `PackageDetailView+Receipt.swift`: it **calls** the shared `header(id:displayName:versionStory:installed:primaryButton:)`, the shared `fact(_:_:)`, and hands the shared `MutationMenu` a `PackageEntry(installed: nil, catalog: nil, id:)`. Both of its sentences are the projection's `stateCopy` and `footerCopy`, rendered as values. `versionStory` is widened from `String` to `String?` and the version line plus its separator dot render only when it is non-`nil`; both shipped call sites pass a `String` and are **source-identical**. The pane's footer — `Cellar knows this package by name only until it is installed.` — is a `private var` in this file, exactly as `receiptFooter` is in the receipt file | Passing `versionStory: ""` (renders an empty `Text` and a dangling separator dot — a placeholder for an absent fact, which PS8 forbids by name); a second header written for this pane (the drift **DD-18** was created to prevent, in the one place the helper is already `internal`); leaving the footer in the pane the way `receiptFooter` is left in the receipt pane (that footer is byte-shared with a sentence `PackageDetailView.swift` already ships, which is what earned it its place; this one is new copy with no such tie, and PS8's copy-ownership clause puts every new sentence of this change in the projection); carrying a `collisionNote` (**unreachable**: a colliding token is carried by the catalog, so the catalog branch resolves it before this one — presentation that can never be seen to be wrong is worse than none) | The receipt pane is the precedent for **everything** here, which is why the round costs so little: the header helper, the fact helper, the entry shape and the footer idiom all already exist and are already `internal` for exactly this reason. The one genuinely new thing is the widened `versionStory`, and that is forced: a pane with no version must render **no version line**, and `String` cannot express that. Widening it is smaller and more honest than a second header, and the compiler proves both shipped call sites unaffected. `installed: nil` needed no change at all — the parameter has been optional since m10 |

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
          └─ ForEach(hits) ── name · KindTag · StatusPill.installed (hit.isInstalled)
                              · UpdateTag(nextVersion:) (hit.nextVersion != nil)
                              · tapName · hit.stateNote · hit.collisionNote
                              · MutationMenu(PackageEntry(
                                    installed: hit.installed, catalog: nil,
                                    id: hit.mutationTarget))                    (DD-20)
             routableID != nil ⇒ .tag(id) ⇒ ContentView detail arm ⇒ PackageDetailView
             routableID == nil ⇒ .selectionDisabled()
        .overlay ── TapSearchEmptyState(presentation)   ← private sibling, not shared (DD-10)

    StatusPill ──────────────► one component, two surfaces: PackageRow and the row above (DD-18)
    UpdateTag ───────────────► one shipped component, already internal, already drawn by the
                               Installed and Updates lists; the row above joins them (DD-19)
    InstalledInventory ──────► the offered version's only source: receipt.isOutdated ⇒
                               receipt.catalogVersion. No brew invocation, no catalog read (DD-19)
                               …and the same resolved receipt is the hit's `installed` handoff,
                               keyed by TapPackage.installedHandoff — never a bare PackageID (DD-20)
    MutationMenu ────────────► one component, three surfaces: it already branches on
                               entry.isInstalled and already declares every verb (DD-20)

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

### File Changes — round-3 delta (maintainer UI feedback)

| File | Action | Est. delta | Description |
|---|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift` | Modify | +8 / −12 | `stateCopy: String` → `stateNote: String?`; computed `isInstalled`; the two withdrawn constants deleted (**DD-7**, **DD-9**) |
| `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | Modify | +20 / −12 | The install-state row restated; the `Mirror` label list and two spot assertions updated |
| `cellar/Browse/StatusPill.swift` | **Create** | ~45 | **DD-18**, the shared pill and its `installed` constant |
| `cellar/Browse/PackageRow.swift` | Modify | +6 / −22 | **DD-18**: the private method leaves; three call sites become `StatusPill` |
| `cellar/Browse/TapSearchView.swift` | Modify | +14 / −10 | **DD-9**: the pill in the title line; the state sentence removed; the note line conditional |
| `cellarTests/TapSearchCompositionTests.swift` | Modify | +40 / −12 | The withdrawn strings asserted absent; the shared pill asserted on both surfaces |
| `cellar/Browse/BrowseView.swift` | **Untouched** | **0** | **DD-8** holds: the pill lives in `PackageRow.swift` |
| `cellar.xcodeproj/project.pbxproj` | **Untouched** | **0** | Synchronized root group — a new file needs no reference |

**Budget.** Round-2 delta ≈ **700–950** changed lines, plus ~250–400 artifact lines. Cumulative branch
total ≈ **2,050–2,600 against 5,000**. `400-line budget risk: N/A` (project budget is 5,000);
**5,000-line budget risk: Low**. Single PR under the cached `single-pr` strategy.

### File Changes — round-4 delta (maintainer UI feedback, the update pill)

| File | Action | Est. delta | Description |
|---|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift` | Modify | +18 / −4 | **DD-19**: stored `nextVersion: String?` and its derivation from the installed receipt |
| `Packages/CellarCore/Tests/BrewClientTests/Fakes/InstalledFixture.swift` | Modify | +12 / −2 | An `outdatedTo:` parameter on `receipt(…)`, defaulted, so every shipped call site is source-identical |
| `Packages/CellarCore/Tests/BrewClientTests/Fakes/TapSearchFixture.swift` | Modify | +12 / −0 | An outdated four-state inventory beside the shipped three-state one |
| `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | Modify | +45 / −6 | The new offered-version row; the `Mirror` label list and the facts row renamed to six |
| `cellar/Browse/TapSearchView.swift` | Modify | +9 / −0 | **DD-19**: `UpdateTag(nextVersion:)` after `StatusPill.installed` |
| `cellarTests/TapSearchCompositionTests.swift` | Modify | +45 / −0 | The shared update pill asserted on both surfaces, positioned, and its copy asserted absent from the tap view |
| `cellar/Browse/PackageRow.swift` | **Untouched** | **0** | **DD-19**: `UpdateTag` is already internal and already takes the version as a value |
| `cellar/Browse/StatusPill.swift` | **Untouched** | **0** | Round 3's component; the update mark is a different, already-shipped one |
| `cellar/Browse/BrowseView.swift` | **Untouched** | **0** | **DD-8** holds for the third round running |
| `cellar.xcodeproj/project.pbxproj` | **Untouched** | **0** | No file is created this round at all |

### File Changes — round-5 delta (maintainer UI feedback, the mutation verbs)

| File | Action | Est. delta | Description |
|---|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift` | Modify | +22 / −12 | **DD-20**: stored `installed: InstalledPackage?`; the handoff lookup is performed once and `nextVersion` derived from its result |
| `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | Modify | +55 / −4 | The mutation-handoff assertions on the offered-version row; `installed` added to the `Mirror` label list; a colliding-receipt row |
| `cellar/Browse/TapSearchView.swift` | Modify | +7 / −5 | **DD-20**: `PackageEntry(installed: hit.installed, catalog: nil, id: hit.mutationTarget)` and its comment |
| `cellarTests/TapSearchCompositionTests.swift` | Modify | +40 / −2 | The literal pin moves to `installed: hit.installed`; a new row for the shared menu's installed branch and the still-absent local verbs |
| `cellar/Activity/MutationMenu.swift` | **Untouched** | **0** | **DD-20**: every verb, its applicability and its argv are already there |
| `cellar/Browse/PackageRow.swift`, `cellar/Browse/StatusPill.swift` | **Untouched** | **0** | Rounds 3 and 4's components; round 5 changes no mark |
| `cellar/Browse/BrowseView.swift` | **Untouched** | **0** | **DD-8** holds for the fourth round running |
| `cellar.xcodeproj/project.pbxproj` | **Untouched** | **0** | No file is created this round either |

### File Changes — round-6 delta (maintainer product decision, the name-only detail)

| File | Action | Est. delta | Description |
|---|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift` | Modify | +6 / −6 | **DD-21**: `routableID` drops the install-state conjunct — routable **iff** unambiguous |
| `Packages/CellarCore/Sources/BrewClient/TapInventoryDetail.swift` | **Create** | ~70 | **DD-21**: the pure resolution `resolve(_:in:)` and the four names it publishes, plus the two copy strings |
| `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` | Modify | +30 / −10 | The routability rows restated for both install states |
| `Packages/CellarCore/Tests/BrewClientTests/TapInventoryDetailTests.swift` | **Create** | ~110 | The resolution rows: exactly one publisher, zero, several; the enumerated facts; the withheld-installed exclusion |
| `cellar/Browse/PackageDetailView.swift` | Modify | +8 / −1 | **DD-21**: the third `body` branch after the receipt branch, and the `taps: TapStore` parameter. The file's zero-diff run **ends here**, and the bindings proof says so |
| `cellar/Browse/PackageDetailView+TapInventory.swift` | **Create** | ~95 | **DD-22**: the pane, mirroring `PackageDetailView+Receipt.swift`'s structure and reusing the shared header. Composes **no** sentence of its own |
| `cellar/ContentView.swift` | Modify | +1 | `taps: taps` at the one `PackageDetailView(` construction site |
| `cellar/Browse/TapSearchView.swift` | Modify | +4 / −5 | The inert-row comment restated: ambiguity, not install state |
| `cellarTests/TapSearchCompositionTests.swift` | Modify | +75 / −10 | The selection row renamed and restated; the new pane-composition row |
| `cellarTests/PerPackageTrustCompositionTests.swift` | Modify | +2 / −1 | The new pane joins `views()` and its sorted anchor — it is a detail surface, so the no-local-marker guard must cover it |
| `cellar/Activity/MutationMenu.swift`, `cellar/Browse/PackageRow.swift`, `cellar/Browse/StatusPill.swift` | **Untouched** | **0** | The pane hands the shipped menu an entry; no mark and no verb moves |
| `cellar/Browse/BrowseView.swift` | **Untouched** | **0** | **DD-8** holds for the fifth round running |
| `cellar.xcodeproj/project.pbxproj` | **Untouched** | **0** | Synchronized root group — the two new files need no reference |

**`PackageDetailView.swift` stops being a zero-diff file.** Rounds 1–5 asserted it byte-identical to
`main`; round 6 cannot, because the third branch and the `taps:` parameter both live in it. The claim is
therefore **narrowed rather than dropped**: the diff is limited to those two hunks, shown in full in the
bindings proof, and the file keeps every other property the earlier rounds asserted — no verb, no argv,
no mutation target of its own, and the catalog and receipt branches unchanged.

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
`aNotInstalledHitIsNeverRoutable`, `everyMutationTargetIsBare`, `theThreeInstallStatesCarryTheirExactCopy`
(**round 3: renamed to `onlyTheWithheldStateCarriesANote` and restated — see the round-3 rows below**),
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

**Round-3 rows (maintainer UI feedback):**

| Class | RED test | Asserts |
|---|---|---|
| `unit` | `onlyTheWithheldStateCarriesANote` (replaces `theThreeInstallStatesCarryTheirExactCopy`) | **DD-9**: the three `TapPackageInstallState` values stay distinct; `isInstalled` is `true` for both installed states and `false` for the third; `stateNote` is non-`nil` **only** for the withheld state and is byte-exactly TM5's sentence; and neither withdrawn string is produced for any hit |
| `unit` | `aHitCarriesItsFiveFactsAndItsCopyAndNothingElse` (amended) | The `Mirror` label set becomes `stateNote` rather than `stateCopy`, and a not-installed hit's note is `nil` — an absence, not `""` |
| `unit-app` | `theSurfaceCopyLivesInTheProjectionNotTheView` (amended) | **DD-18**: `"Installed."` and `"Not installed."` appear as complete literals in **neither** the projection nor the surface; the surface carries no `"Installed"` literal at all; it renders `StatusPill.installed`, `hit.stateNote` and `hit.collisionNote`; and `PackageRow.swift` draws the **same** `StatusPill.installed`, whose label is declared once, in `StatusPill.swift` |
| `unit-app` | `notInstalledTapRowsAreNotSelectable` (amended) | Unchanged in substance: routability is still read from `hit.routableID` alone. `hit.isInstalled` leaves the forbidden list because the pill legitimately reads it and a `Bool` about installation **cannot** express routability, which additionally needs non-collision and uniqueness — the two facts the row is still forbidden to consult (`alsoInCatalog`, `hit.state ==`, `== .notInstalled`) |

**Round-4 rows (maintainer UI feedback, the update pill):**

| Class | RED test | Asserts |
|---|---|---|
| `unit` | `onlyAnOutdatedInstalledHitOffersAVersion` (new) | **DD-19**: over a four-state fixture — installed-and-outdated, installed-and-current, not-installed, withheld-and-outdated — `nextVersion` is exactly the receipt's offered version for the first and the fourth, `nil` for the second and the third, and never equal to the version that hit has installed. An absence, never `""` |
| `unit` | `aHitCarriesItsSixFactsAndItsCopyAndNothingElse` (renamed from `…ItsFiveFacts…`, amended) | The `Mirror` label set **gains `nextVersion`**, and a not-installed hit's is `nil`. The rename is the honest one: `nextVersion` is stored, so the enumeration this row reads would otherwise deny a fact the type carries |
| `unit-app` | `bothSearchSurfacesDrawTheOneSharedUpdatePill` (new) | **DD-19**: both `TapSearchView.swift` and `PackageRow.swift` reference `UpdateTag(nextVersion:`; `struct UpdateTag: View` is declared **once** across the app sources; the tap row draws it **after** `StatusPill.installed` (range comparison, as the round-3 pill row does) and gates it on `hit.nextVersion` alone; and `TapSearchView.swift` contains no `"UPDATE"` or `"Update"` literal, so the pill's copy is the component's |

**Round-4 honesty note.** `UpdateTag` is declared **inside `PackageRow.swift`**, not in a file of its
own like `StatusPill`. The round-3 row could assert "neither presenting surface composes the label"
symmetrically over both files; this one cannot, because for `PackageRow.swift` the presenting surface
*and* the declaration are the same file. The claim is therefore asserted where it is true and provable —
the declaration is unique across the app sources, and the tap surface carries no update literal — rather
than restated in a shape one of the two files cannot satisfy.

**Round-5 rows (maintainer UI feedback, the mutation verbs):**

| Class | RED test | Asserts |
|---|---|---|
| `unit` | `onlyAnOutdatedInstalledHitOffersAVersion` (amended) | **DD-20**: over the same four-state fixture, `installed` is the hit's **own** receipt for installed-and-outdated, installed-and-current and withheld-and-outdated — matching `id`, matching `catalogVersion` — and `nil` for the not-installed one. Both installed states answer, so the withheld row is not silently excluded from the verbs the way an exact-tap-only lookup would exclude it |
| `unit` | `aCollidingCatalogReceiptIsNeverAttachedToATapRow` (new) | **DD-20**, the keying claim: a tap publishing a bare token the catalog also carries, whose only resident receipt names the **catalog's** tap, yields a hit with `installed == nil` — so the catalog package's receipt can never reach the tap row's menu. Triangulated against the same fixture with the receipt naming the **publishing** tap, where the record is present and is that receipt |
| `unit` | `aHitCarriesItsSixFactsAndItsCopyAndNothingElse` (amended) | The `Mirror` label set **gains `installed`**, and a not-installed hit's is `nil`. It is enumerated as a **handoff**: the six-fact ceiling and the absence set (`desc`, `homepage`, `license`, …) are re-asserted unchanged around it |
| `unit-app` | `anInstalledTapRowReachesTheMutationMenuWithItsRecord` (new) | **DD-20**: `TapSearchView.swift` builds `PackageEntry(installed: hit.installed, catalog: nil` with `id: hit.mutationTarget`; it never writes `installed: nil` into that entry and never passes a catalog record; `MutationMenu.swift` still branches on `entry.isInstalled` and still declares Reinstall, Uninstall…, Uninstall and Zap…, Upgrade and Pin/Unpin exactly once each; and the tap view still declares none of `MutationCommand`, `PackageTarget(`, `submit(`, `FormulaID`, `CaskID` or any of those verb literals |
| `unit-app` | `theTapSearchSurfaceComposesNoTrustGateAndNoBadge` (amended) | The entry literal it pins becomes `PackageEntry(installed: hit.installed, catalog: nil`. `catalog: nil` **stays pinned** — PD6: no catalog record reaches this row, in either install state. The trust half is untouched |

**Round-5 honesty note.** The new stored member is **not** a seventh fact and PS8 says so explicitly. The
`Mirror` row that enumerates it is what keeps that claim honest: the enumeration lists `installed` by name
and re-asserts the absence set around it, so a later member that *is* tap-published metadata cannot slip in
behind this one. What makes the addition legitimate is that the shared mutation spine's own input type
already has this exact slot — the row is supplying a value `PackageEntry` declares, not inventing one.

**Round-6 rows (maintainer product decision, the name-only detail):**

| Class | RED test | Asserts |
|---|---|---|
| `unit` | `anAmbiguousHitIsNotRoutableInEitherInstallState` (renames and absorbs `anAmbiguousInstalledHitIsNotRoutable`) | **DD-21**: over four fixtures — an installed colliding hit, a **not-installed** colliding hit, two taps sharing one `PackageID`, and an unambiguous hit of each install state — `routableID` is `nil` for the first three and the exact `PackageID` for the last two. The install state is read alongside and is *not* what decides, which is the claim the round turns on |
| `unit` | `aNotInstalledHitIsRoutableWhenItsIdentityIsUnambiguous` (replaces `aNotInstalledHitIsNeverRoutable`) | **DD-21**: the shipped three-package not-installed fixture now reports `routableID == mutationTarget` for all three, and each is still presented and still installable — the assertion the old row made, with the inverted expectation the decision reversed |
| `unit` | `oneTapPublishingTheIdentityResolvesToItsFourNames` (new) | **DD-21**: `TapInventoryDetail.resolve(_:in:)` answers a value for an identity exactly one third-party tap publishes; its `Mirror` label set is exactly `{id, displayName, tapName, stateCopy, footerCopy}` and contains no `desc`, `version`, `homepage`, `license`, `dependencies`, `installCount`, `deprecated`, `disabled`, `size` or `collision`; `stateCopy` is byte-exactly TM5's `Not installed.` and `footerCopy` byte-exactly the pinned footer; `kind` answers off `id` |
| `unit` | `anUnpublishedOrDoublyPublishedIdentityResolvesToNothing` (new) | **DD-21**, the exactly-one rule: an identity no third-party tap publishes answers `nil`, an identity **two** third-party taps publish answers `nil`, an identity only an **official** tap publishes answers `nil`, and an identity one tap publishes but this machine **has a receipt for** answers `nil` — including the withheld-tap receipt, whose `tap` is absent — triangulated against the same inventory with the receipt removed, where a value comes back, so the `nil`s are the rule working rather than an empty inventory answering |
| `unit-app` | `theTapSearchSurfaceSelectsOnRoutabilityAlone` (renames `notInstalledTapRowsAreNotSelectable`) | Unchanged in substance and in subject: selection is still gated on `hit.routableID` alone, and the four re-derivation tokens (`alsoInCatalog`, `hit.state ==`, `== .notInstalled`, `occurrences`) stay forbidden. What changes is the row's *name* and its recorded reason — the inert case is now ambiguity, never the install state |
| `unit-app` | `theNameOnlyTapDetailComposesNothingItCannotKnow` (new) | **DD-22**: `PackageDetailView+TapInventory.swift` contains none of `desc`, `homepage`, `license`, `dependencies`, `analytics`, `Size on disk`, `versionStory(`, `catalogVersion`, `installedAs(`, `sizeOnDisk(`; no trust token (`TrustGrant`, `grantsIndividually`, `grantMarker`, `Untrusted`, `Trust`); it draws `MutationMenu(center:` with `PackageEntry(installed: nil, catalog: nil`; and the footer literal appears **exactly once** across the app sources. `PackageDetailView.swift`'s `body` orders `catalog.package(id)`, then `installed.inventory.package(id)`, then the inventory branch (range comparison), and `ContentView.swift`'s one `PackageDetailView(` call site passes `taps: taps` |

**Round-6 honesty note.** Two shipped `unit` rows are **inverted**, not extended:
`aNotInstalledHitIsNeverRoutable` asserted exactly what the maintainer reversed, so it is replaced rather
than amended around. That is the honest shape for a reversed decision — leaving the old row in place with
a narrowed fixture would let both the old rule and the new one appear satisfied. The `unit-app` selection
row is the opposite case: its subject never changed, so it is **renamed and re-commented** and its
assertions stand.

**Existing tests that MUST keep passing:** `TapProjectionTests`, `TapShippingProofTests`,
`MutationCommandTests`, `MutationCommandTargetTests`, `SearchIndexTests`, `FilterTests`,
`InstalledFilterCompositionTests`, `ReceiptDetailCompositionTests`, `PackageGraphTests`, and — with only
their listed edits — `AppSectionPlacementTests` and `PerPackageTrustCompositionTests`. Round 6 adds
`ReceiptDetailCompositionTests` to the list of suites whose **subject** it touches without amending them:
the receipt pane and its branch are unchanged, and that suite passing unedited is the proof.

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
- [x] **Closed** (**DD-4**), then **half reopened and re-closed** (**DD-21**, **DD-22**, round 6):
      **ambiguous** rows are non-selectable in either install state; an unambiguous row is routable
      whether or not it is installed. Routable rows still reach the shared `PackageDetailView`, which now
      carries a **third** branch — catalog, then receipt, then resident tap inventory — so an installed hit
      still lands on the m10 receipt pane and a not-installed one lands on the name-only pane.
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
