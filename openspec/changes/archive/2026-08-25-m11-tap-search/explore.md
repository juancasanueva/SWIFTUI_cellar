# Exploration: m11 — tap package search and install from Browse

**Change**: `m11-tap-search` · **Project**: `swiftui_cellar` · **Base**: `main` @ v1.3.0 (clean)
**Artifact store**: hybrid (Engram topic `sdd/m11-tap-search/explore`, obs #7794 + this file, which is canonical)
**Phase**: explore only — no proposal, spec, design, tasks or code.

**The problem.** Browse/Search cannot find a package published by a tapped third-party tap (measured
in the running v1.3.0 app: `gentle-ai` from `gentleman-programming/tap`). `PackageSearchIndex` is
built only from the `CatalogSnapshot` (`homebrew/core` + `homebrew/cask`), by design. Today the only
path is Taps → `TapDetailView` → its filter field. The requirement is that Search/Browse **find**
those packages and **install** them from there.

---

## 1. Current search architecture

### 1.1 The index and its result type

`Packages/CellarCore/Sources/Catalog/PackageSearchIndex.swift`

- `SearchHit` (`:37`) — `{ id: PackageID, rank: MatchRank }`. Nothing else.
- `PackageSearchIndex` (`:55`) — struct-of-arrays over one `CatalogSnapshot`: `names`,
  `descriptions`, `installCounts`, `kinds`, `flags`, `packages`, `positions`.
- `search(_:filters:limit:)` (`:175-215`) — normalises the needle once, buckets every record by
  `MatchRank`, then sorts each bucket lazily by `precedes` (`:235-253`) and takes `limit`.
- `package(_ id:)` (`:158-160`) — the catalog detail lookup. Its own doc comment already names the
  boundary: *"the catalog covers two taps and everything else is simply not in it (package-detail
  PD1, PD6)"*.
- The index is a **closed value built from a snapshot**. There is no ingestion seam: `build(from:)`
  takes a `CatalogSnapshot` and nothing else. Widening it is Approach C below (rejected).

### 1.2 The store and the rerank

`Packages/CellarCore/Sources/Catalog/CatalogStore.swift`

- `rerank()` (`:315-318`) is the whole query path:
  `index.search(query, filters:, limit: resultLimit)` → `results = hits.compactMap { index.package($0.id) }`.
  Synchronous, main actor, no debounce — licensed by the measured p95 of 1.02 ms against PS6's 8 ms
  ceiling (design D4).
- `results` is `[CatalogPackage]`. **The rank is dropped at this hop**: nothing downstream of
  `rerank()` sees `MatchRank`. Any merged-ranking approach has to re-plumb it.

### 1.3 The view

`cellar/Browse/BrowseView.swift`

- `PaneSearchField(text: $catalog.query, prompt: "Search \(catalog.packageCount.formatted()) packages…")`
  (`:45-48`) — the prompt counts catalog records only.
- `CatalogFilterBar` (`:49-54`) — kind chips, Outdated chip, and a menu with Hide deprecated / Hide
  disabled / Hide installed.
- `List(rows, selection: $selection)` (`:59-72`) — **one flat list, no sections**, each row a
  `PackageRow` + `MutationMenu`, tagged by `entry.id` (a `PackageID`).
- `rows` (`:107-122`) — `InstalledBrowse.rows(mode:query:filters:catalogResults:catalogLookup:)`,
  then the `hideInstalled` subtraction.
- `EmptyResults` (`:126-143`) — three distinct reasons (not ready / empty query / no match).

### 1.4 Where a second result source can join — the shipped precedent

`Packages/CellarCore/Sources/BrewClient/InstalledFilterMode.swift`

- `PackageEntry` (`:34-55`) — `{ id, displayName, version, installed: InstalledPackage?, catalog:
  CatalogPackage? }`. **Both sides are optional**, and its own comment says so: *"A package from a
  third-party tap has no catalog record."* `desc` falls back, `displayName` falls back to `id.name`.
- `InstalledBrowse.rows(...)` (`:99-133`) composes installed state **above** the index and is
  required to: installed-inventory II8 — *"Installed-state filters are composed, never pushed into
  the search index"* (`openspec/specs/installed-inventory/spec.md:256-276`).

**This is the join seam and the architectural template.** A second result source belongs exactly
where `InstalledBrowse` already lives: a pure projection in `BrewClient`, composed above the index,
consumed by `BrowseView`. Not inside `Catalog`.

### 1.5 Detail routing today

`cellar/Browse/PackageDetailView.swift:48-70` resolves a `PackageID` in strict order:

1. `catalog.package(id)` → the full catalog pane;
2. `installed.inventory.package(id)` → `uncatalogedContent` — the m10 receipt pane (II15);
3. otherwise → `ContentUnavailableView("Package details unavailable")`.

`cellar/ContentView.swift` already holds `taps: TapStore` (`:42`) and `trustGrants: TrustGrantStore`
(`:46`) and owns `@State private var selection: PackageID?` (`:73`). **No new store wiring is
needed at the composition root** — only passing `taps` down into `BrowseView`.

---

## 2. What is already resident about tap packages

### 2.1 The data

- `TapStore` (`Packages/CellarCore/Sources/BrewClient/TapStore.swift:13`) — `@MainActor @Observable`,
  holds `inventory: TapInventory` and `state: TapLoadState`. Single-flight `refresh(using:)` with
  invalidation-marked in-flight joining (`:55-93`).
- `TapRecord` (`TapWire.swift:18`) carries `formulaNames` and `caskTokens`, **both fully qualified**
  (`acme/tools/widget`), plus the tap's own `trust`.
- `TapProjection.packages(for:installed:)` (`TapProjection.swift:134-162`) → `[TapPackage]`, one per
  published name: `id: PackageID(kind:, name: bareToken)`, `publishedName` (qualified),
  `displayName`, `state`.
- `TapPackageInstallState` (`:25-30`) — `installed(PackageID)` / `installedTapWithheld(PackageID)` /
  `notInstalled`. Three values, not two (TM5).
- `TapProjection.filter(_:query:kind:)` (`:176-186`) — the existing tap-detail filter:
  `localizedCaseInsensitiveContains` over `displayName`, **no ranking, no normalisation**.
- `TapProjection.bareToken(_:publishedBy:)` (`:208-211`) — the one normalisation, removing only the
  selected tap's own `owner/repo/` prefix.
- `TapProjection.publishes(_:in:)` (`:219-222`) — already public, already used by
  `UntrustedTapRecovery`.

### 2.2 Refresh cadence — no new invocation

- One `brew tap-info --installed --json` per tap refresh (TM1). Driven by launch/activation refresh
  and by `InvalidationScope.taps`.
- `TapCommand.invalidates` (`TapCommand.swift:150-156`): `addTap`/`removeTap` → `.taps`;
  `trustTap`/`untrustTap` → `[.taps, .installedInventory]`; `forceRemoveTap` → `+ .diskUsage`.
- **Searching the tap inventory costs zero brew invocations** — it is already in memory in
  `TapStore.inventory`, and matching it is a pure function. This satisfies the TM1-by-analogy
  constraint m10 established (*no additional brew invocation to complete a surface*).

### 2.3 What is NOT available for a not-installed tap package — confirmed

`TapRecord` carries **names and tokens only**. There is no description, version, homepage, license,
dependency list, install count, deprecation flag or size for a tap package that is not installed.
Obtaining any of them requires reading the tap's formula/cask **source**, which:

- TM5 forbids outright — *"MUST NOT perform a tap-source read to complete a package detail"*
  (`openspec/specs/tap-management/spec.md:149-150`);
- the m10 explore §2.3 already enumerated as the exact PD1 field set that exists only in the catalog
  dump, and ruled out for the same reason;
- would be a trust-sensitive operation (loading third-party Ruby), i.e. precisely what the whole
  m7/m9 trust surface exists to keep behind an explicit grant.

**Conclusion: a tap search hit is a name, a kind, and a tap of origin. Nothing more.** For an
*installed* tap package the m10 receipt pane already supplies the rest.

---

## 3. Install from a tap package

### 3.1 The argv is already correct, and must stay bare

`MutationCommand.arguments` (`MutationCommand.swift:259-280`) → `install` +
`vector(naming:)` (`:329-335`), which emits exactly `[--formula|--cask, id.name]` — **the bare
name**.

`PackageTarget.init?` (`:44-47`) gates on `MutationName.isSafe` (`:130-133`), which rejects empty,
whitespace and leading-`-` names but **permits `/`** — deliberately, because `TapName.init?`
(`TapCommand.swift:10-17`) is expressed over the same gate and a tap name *is* `owner/repo`.

The invariant is therefore **not** in the validator. It is PM10, `package-mutation/spec.md:647-652`:

> **The prohibition.** No argv this capability or any command on the shared mutation spine spawns MUST
> contain a `/`-qualified package token — on any path, including the recovery offered after this refusal
> and any retry. Homebrew treats *naming* a qualified package to its trust machinery **as the grant**, so
> a requalified retry would convert a refusal into silent execution of code the user never consented to
> run […] The shipped name-safety gate permits `/`, so this MUST be asserted as an **absence over the
> whole mutation surface** by a test, never left to review.

Scenario `:713-719` enumerates every argv element every spine family can produce and asserts none is
qualified.

**Consequence for m11: a tap hit installs by its bare token, and `TapPackage.id` already *is* that
bare token.** `MutationCommand.install(PackageTarget(tapPackage.id)!)` needs no new command family,
no new argv shape, and adds nothing to the qualified-token enumeration. This is the single largest
reason m11 is cheap.

### 3.2 The proposed trust gate is FORBIDDEN — correcting the brief

The launch brief proposed: *"trusted tap → Install; untrusted → no Install, route to Trust"*. That
is prohibited by the very requirement that owns this area. PM10, `package-mutation/spec.md:659-670`:

> The refusal MUST NOT be converted into a pre-launch gate. This capability MUST NOT block a mutation
> because the package's tap is untrusted: with the tap withheld the inventory cannot prove the origin
> tap, and a per-package grant can make brew allow exactly what a tap-state gate would refuse. Only brew
> sees both grant kinds, so only brew decides.
>
> **The same prohibition MUST HOLD for per-package grant state.** This capability MUST NOT block,
> disable, hide, delay or pre-qualify a mutation, an affordance or a request because a package has, or
> lacks, an individual grant — and MUST NOT read the per-package trust report, store or projection to
> decide anything before launch.

With two scenarios (`:721-735`) — *"An untrusted tap never pre-blocks a mutation"*, *"A per-package
grant state never pre-blocks a mutation"* — and a **shipped source-scanning assertion** (`:737-743`)
that fails the build if a trust type name appears anywhere in the mutation command surface.

So the `unreported` branch the brief left open ("unreported → ?") has the same answer as the other
two: **offer Install unconditionally; brew decides.**

### 3.3 There is no interactive prompt to avoid — the refusal path is already shipped

Homebrew 6 does **not** prompt; it refuses non-interactively. The measured signature
(`package-mutation/spec.md:628-630`, Homebrew 6.0.18, Engram `#7721`):

> ``Error: Refusing to load cask <qualified> from untrusted tap <tap>. Run `brew trust --cask <qualified>` or `brew trust <tap>` to trust it.``

And the whole recovery is already built:

- `MutationOutcome.Signature.untrustedTap = "untrusted tap"` (`MutationOutcome.swift:146-164`) —
  one structural phrase, stderr only, nothing extracted.
- `UntrustedTapRecovery.trustableTap(forRefused:in:)` (`UntrustedTapRecovery.swift:20-35`) — derives
  the single candidate tap from **Cellar's own** tap-info snapshot (`trust == .untrusted`,
  non-official, `TapProjection.publishes`), and returns `nil` when the candidate is ambiguous.
- Typed copy, pinned by PM10 `:709`: *"Homebrew refused to load this package because its tap is not
  trusted. Trust the tap in Taps, then try again."*

`BrewEnvironment.pinned` (`BrewEnvironment.swift:47-51`) carries only `HOMEBREW_NO_AUTO_UPDATE`,
`HOMEBREW_NO_COLOR`, `HOMEBREW_NO_EMOJI` — nothing trust-related, and nothing to add. `PATH`/`HOME`
are the only inherited keys.

**Net: install-from-search on an untrusted tap already has a correct, tested end-to-end story.** m11
adds an entry point, not a mechanism.

---

## 4. Spec homework

### 4.1 `package-search` — every requirement, and whether it binds

`openspec/specs/package-search/spec.md` (7 requirements / 19 scenarios). Every one is a statement
about **the index**, not about the Browse surface:

| # | Requirement | Binds a tap section? |
|---|---|---|
| PS1 | Index identity is `(kind, name)` (`:8-25`) | Only if tap hits enter the index. They must not. **But see §6.1 — the collision it implies is real.** |
| PS2 | Matching runs over pre-normalised ASCII-folded text (`:27-45`) | No — but a tap section that matches with `localizedCaseInsensitiveContains` would behave *differently* from the catalog list beside it. Worth aligning to `PackageText.normalize` for consistency, not for compliance. |
| PS3 | Deterministic ranking order (`:47-78`) | No, **provided the tap hits are a separate ordered section**. Merging them into one ranked list restates PS3, because PS3's tiebreak is 365-day install count and a tap package has none. |
| PS4 | Filters answerable from the catalog alone (`:80-109`) | No. Its scenario *"No filter references installed state"* enumerates the **declared filter set** (`SearchFilters`), which m11 must not extend. A view-level tap section is not a filter — same standing as the shipped `hideInstalled` toggle, which II8 already licenses. |
| PS5 | Empty and non-matching queries are ordinary results (`:111-127`) | No, but the tap section needs its own empty-query answer (see §6.3). |
| PS6 | Measured as-you-type latency ceiling, p95 < 8 ms (`:129-145`) | Not literally (it is measured over the index). But the composed section runs **on the same main-actor keystroke turn** as `rerank()`, so a linear scan over the tap inventory is added to that budget. Tap inventories are tens-to-hundreds of names, not 15,500 — but the new requirement should state the ceiling is not regressed. |
| PS7 | Index construction never runs on the main actor (`:147-178`) | No — no index is built. |

**Delta: `package-search` ADDED — one requirement.** Working shape: *"Packages published by installed
third-party taps are searchable as a distinct, composed source"*. It must state: composed above the
index, never pushed into it (II8's exact discipline); fed exclusively by the already-resident tap
inventory with no brew invocation; a hit carries name, kind and tap of origin and **nothing else**;
presented distinctly from catalog results and never interleaved into PS3's order; and it must offer
install on the shared spine with a bare token, with **no trust-state gate** (citing PM10).

### 4.2 PD6 — verbatim (post-m10)

`openspec/specs/package-detail/spec.md:232-249`:

> ### Requirement: Third-party tap packages are outside catalog scope
>
> The catalog covers the `homebrew/core` and `homebrew/cask` taps only. A package published by any
> other tap MUST be absent from the snapshot, **MUST NOT appear in search results**, and a detail lookup
> for it MUST return the ordinary not-found result. Its absence MUST NOT be reported as a sync
> failure, a decode failure, or an error state.
>
> Every clause above binds the **catalog projection** this capability owns — the snapshot, catalog
> search, and the catalog detail lookup. A rendering fed **exclusively by the installed receipt** is not a
> catalog detail lookup: it creates no catalog record, adds nothing to the snapshot or to search, consults
> no catalog value, and spawns no additional brew invocation, so it neither satisfies nor violates this
> requirement. […]

**Reading.** m10 already drew the boundary sentence for *detail*. The second paragraph's own words —
*"Every clause above binds the catalog projection … the snapshot, catalog search, and the catalog
detail lookup"* — mean a Browse section fed exclusively by the tap inventory is not "catalog search"
and does not literally violate the clause. **But** the bare phrase *"MUST NOT appear in search
results"* is broad enough to read as a blanket ban, and m10's own explore recorded the cost of
shipping against an unamended one: *"a documented contradiction"*.

**Delta: MODIFIED PD6** — extend the m10 boundary paragraph by one clause naming a *search-surface*
section fed exclusively by the tap inventory, on exactly the terms m10 used for the receipt pane (no
catalog record, nothing added to the snapshot or the index, no catalog value consulted, no extra brew
invocation). Both existing scenarios and the new m10 scenario survive byte-identical; a third
scenario asserts the composed section still leaves `index.search` and `index.package` unchanged.
PD6 is a ~20-line block — a whole-block MODIFIED is cheap.

### 4.3 TM5 — verbatim clause (post-m10)

`openspec/specs/tap-management/spec.md:147-153`:

> Tap packages MUST NOT enter the catalog snapshot, catalog search, or catalog detail; PD6 remains
> unchanged. Selecting a tap package MUST NOT create a **catalog** record for it and MUST NOT perform a
> tap-source read to complete a package detail — that is the whole of this prohibition. It does not
> reach a detail composed **exclusively from the installed receipt** […]

**Reading.** Same shape as PD6. m10 narrowed the *detail* half and left the *catalog search* half
intact. m11 needs the parallel narrowing for search, plus the affirmative statement that the tap
inventory is a legitimate source for a surface **outside** this capability.

**Delta: MODIFIED TM5** — ~90-line block, must be reproduced whole with all 8 scenarios preserved.
This is the largest single line cost of the change and it is unavoidable.

### 4.4 TM10 — the obstacle the brief did not anticipate

`openspec/specs/tap-management/spec.md:533-550`:

> ### Requirement: Tap management does not expand into adjacent product capabilities
>
> The capability MUST NOT offer Brewfile import/export, **package installation from tap inventory,
> third-party catalog ingestion or search**, official-source cloning, tap security scanning, arbitrary Git
> management, cleanup, disk usage, or service behavior. […]
>
> #### Scenario: Enumerated tap actions stay within scope
> - THEN they are refresh, filter, Installed handoff, canonical add, plain untap, eligible force untap, trust, and untrust

This names m11's two deliverables almost word for word. Two readings:

1. **Narrow (correct)** — it constrains what the **tap-management surface** offers. m11 adds no
   action to the Taps surface; the enumerated-action scenario survives byte-identical because it
   enumerates *that surface*. The Browse section is owned by `package-search`, and the install is a
   `package-mutation` command on the shared spine.
2. **Broad** — "third-party catalog ingestion or search" is a capability-level ban wherever the tap
   inventory is the source.

Shipping under reading 1 without amending TM10 leaves exactly the documented contradiction m10 was
careful to avoid. **Delta: MODIFIED TM10** — a ~25-line block, cheap, narrowing the exclusion to the
tap-management surface's own action set and naming who owns the two capabilities instead. The
existing scenario text is preserved verbatim, which is the strongest evidence the narrow reading is
the intended one.

### 4.5 TM11 — a constraint on how much the tap section may say

`openspec/specs/tap-management/spec.md:586-595`: *"Exactly one projection MUST supply the trust
presentation consumed by both the tap list row and the tap detail header, so the two cannot drift.
An `untrusted` tap MUST carry the exact badge text "Untrusted" and MUST offer the **Trust** control."*

If the Browse tap section renders an "Untrusted" badge it becomes a third consumer of
`TapProjection.trust(for:)` and TM11 has to be MODIFIED to name it. If the section renders only the
**tap name** — a plain fact, no verdict — TM11 is untouched. §6.2 treats this as an open question.

### 4.6 `package-mutation` — likely NO delta

PM10 already (a) mandates the bare-token argv m11 uses, (b) forbids the trust gate, (c) supplies the
typed refusal and the Trust recovery. `MutationMenu` builds from a `PackageEntry` and needs no
change. Adding a MODIFIED here risks restating a requirement that already says the right thing.
**Recommend: state the no-gate rule in the new `package-search` requirement by citation, and touch
`package-mutation` only if `sdd-spec` finds a genuine gap.**

### 4.7 Recommended delta set

| Spec | Op | Approx. block size | Why |
|---|---|---|---|
| `package-search` | **ADDED** — 1 requirement | new, ~45 lines | The capability that owns the query surface; II8 is the precedent |
| `package-detail` | **MODIFIED PD6** | ~20 lines | Search carve-out, parallel to m10's detail carve-out |
| `tap-management` | **MODIFIED TM5** | ~90 lines | Narrows "catalog search"; states the inventory may feed an outside surface |
| `tap-management` | **MODIFIED TM10** | ~25 lines | Narrows "package installation from tap inventory / third-party search" to this capability's own surface |
| `package-mutation` | none (provisional) | — | PM10 already mandates the bare token and forbids the gate |
| `installed-inventory` | none | — | II7/II8/II15 already license composition-above-the-index and the receipt pane |

---

## 5. Approaches

### A. Composed "From your taps" section in Browse, fed by a pure `TapPackageSearch` projection

A new `nonisolated` value type in `Packages/CellarCore/Sources/BrewClient/` (working name
`TapPackageSearch`), beside `TapProjection` and `InstalledBrowse`. Input: `TapInventory` +
`InstalledInventory` + query + `SearchFilters.kinds`. Output: an ordered `[TapSearchHit]` carrying
`{ tapName, package: TapPackage }`. `BrowseView` gains `let taps: TapStore` and renders a second
`Section` below the catalog rows; each tap row shows name, kind chip, tap of origin, install state,
and a `MutationMenu`. Trust stays on Taps.

- **Pros.** The index is untouched by construction — PS1–PS7 hold without argument, and PD6/TM5
  compliance is provable by a test that queries `index.search`/`index.package` and finds nothing.
  Dependency direction is already correct: `BrewClient` imports `Catalog` (`TapProjection.swift:1`),
  never the reverse, so II7's package-graph scenario is safe. Mirrors the shipped `InstalledBrowse`
  and `TapProjection` idiom exactly, satisfying `rules.design` ("keep all logic in
  `Packages/CellarCore`"). Pure and `Sendable`, so the whole thing is asserted in the `swift test`
  inner loop with no SwiftUI and no `Process`. A separate section is the honest UX for hits that
  have no description and no version — they are visibly a different kind of result, not a
  degraded catalog row. Install is free: `PackageTarget(tapPackage.id)` → existing spine.
- **Cons.** `BrowseView` moves from `List(rows, selection:)` to a sectioned `List(selection:)`, which
  changes row identity plumbing (§6.1). Two empty states to reconcile. The search-field prompt
  ("Search N packages…") counts catalog records only. One more public type in `BrewClient`.
- **Effort: Medium-Low.**

### B. Merged `SearchProjection` in CellarCore — one ranked list with a source label

A projection that merges catalog hits and tap hits into a single ordered result list, each carrying
a source discriminator, consumed by an extended `PackageEntry`.

- **Pros.** One list; `gentle-ai` appears at the top where the user is already looking; no scrolling
  past 200 catalog rows; one empty state.
- **Cons.** PS3's total order is defined over catalog records and broken by install count descending;
  a tap package has no install count, so interleaving either restates PS3 or contradicts it — and
  PS3's *"the order is total and reproducible"* claim is currently guaranteed by `(name, kind)`
  uniqueness, which merged sources destroy (§6.1). `MatchRank` is dropped at `CatalogStore.rerank()`
  and would have to be re-plumbed through `results` and `PackageEntry`, touching every consumer of
  both (`InstalledBrowse`, `PackageRow`, `MutationMenu`, `InstalledListView`, the Favorites and
  Updates lists). A merged list is also the **highest PD6 leak risk**: it is indistinguishable from
  catalog search results, which is precisely the reading PD6 forbids.
- **Effort: High.** Blast radius across ~10 files plus a ranking requirement that has to be written
  from scratch.

### C. Index tap names into `PackageSearchIndex`

- **Reject.** Directly violates PD6 (*"MUST be absent from the snapshot"*) and TM5 (*"MUST NOT enter
  the catalog snapshot, catalog search"*), and breaks PD6's shipped scenario *"Every snapshot record
  belongs to a covered tap"*. Worse structurally: tap data originates in `brew tap-info`, so
  `Catalog` would need `BrewClient`/`BrewProcess`, which II7's scenario *"The catalog target does not
  depend on the brew-process target"* asserts against. Non-starter, and it would break catalog search
  working with brew absent.
- **Effort: n/a.**

### D. A "Taps" scope control on the search field

A segmented scope (Catalog / Taps) rather than a section.

- **Pros.** Zero identity collision, zero ranking question, smallest view diff.
- **Cons.** Does not solve the reported problem. The maintainer's complaint is *"I searched and found
  nothing"* — a scope the user must know to switch to reproduces exactly that.
- **Effort: Low.** Listed for completeness; not recommended.

| Approach | Index untouched | Spec cost | Blast radius | Solves the report | Effort |
|---|---|---|---|---|---|
| **A** section + projection | yes, by construction | 1 ADDED + 3 MODIFIED | `BrowseView` + 1 new type | yes | **Med-Low** |
| B merged ranked list | argued, not structural | + a new ranking requirement | ~10 files | yes | High |
| C index ingestion | no — violates PD6/TM5/II7 | rewrite PD6 + TM5 | package graph | yes | n/a — reject |
| D scope control | yes | ~same as A | small | no | Low |

---

## 6. Detail routing, and the open questions

### 6.1 HIGH — `PackageID` collision between a tap package and a catalog package

`TapPackage.id` is `PackageID(kind:, name: bareToken)` — the *same* identity space the catalog uses.
If any installed tap publishes a bare name the catalog also carries (`acme/tools/wget` vs
`homebrew/core/wget`), the composed list holds **two rows with the same `PackageID`**. Three
consequences:

1. `List(selection: $selection)` keys on `PackageID`; SwiftUI duplicate-id behaviour in a `List`/
   `ForEach` is undefined-ish and at best selects both rows together.
2. `PackageDetailView` resolves catalog-first (`:50`), so selecting the tap row opens the **catalog**
   package's pane.
3. `MutationCommand.install` emits the bare name, and brew's own resolution prefers core — so the
   Install button on the tap row would install the catalog package. PM10 forbids qualifying the argv
   to disambiguate.

Mitigations to decide in `sdd-design`: give the tap **row** its own identity
(`"\(tapName)/\(kind)/\(name)"`) while keeping `PackageID` as the mutation target; and decide whether
a tap hit whose bare name collides with a catalog record is suppressed, badged, or shown with an
explicit note. (3) is a genuine Homebrew ambiguity, not a Cellar defect — the honest answer is
probably to surface the collision rather than pretend it away. **This must be settled before spec.**

### 6.2 MEDIUM — how much the tap row may say about trust

Options: (a) tap name only, no trust presentation — TM11 untouched, and PM10's no-gate rule is
trivially satisfied; (b) render the "Untrusted" badge from `TapProjection.trust(for:)` so the user
understands a likely refusal in advance — requires MODIFIED TM11 to name a third consumer, and
must be written carefully so it stays *informational* and never becomes the gate PM10 forbids.
Recommend (a) for this slice.

### 6.3 MEDIUM — the empty query

PS5 makes an empty catalog query return the whole filtered catalog in default order. `TapProjection.filter`
does the same for an empty query. If the tap section also renders every tap package on an empty
query, Browse opens with a "From your taps" section permanently pinned below 200 catalog rows.
Recommend: **the tap section renders only when the query is non-empty**, stated as a requirement so
it is not a view accident.

### 6.4 MEDIUM — detail routing for a **not-installed** tap hit

- **Installed** (`state == .installed` or `.installedTapWithheld`) → routes to the m10 receipt pane
  today, with no new code: `installed.inventory.package(id)` resolves. `TapPackage.installedHandoff`
  already exists for exactly this handoff.
- **Not installed** → falls through to `ContentUnavailableView("Package details unavailable")`,
  which is wrong-looking for a row the user just found. There is nothing honest to put in a pane:
  II15 covers installed receipts only, PD1/PD6 forbid a catalog record, TM5 forbids the tap-source
  read that would supply description/version. Options:
  (a) make not-installed tap rows non-selectable and put everything (name, kind, tap, Install) on the
      row — smallest, fully honest;
  (b) a minimal pane stating only name, kind, tap of origin, "Not installed." (TM5's exact copy) and
      the Install action;
  (c) route to `TapDetailView` for the owning tap.
  Recommend **(a)** for slice 1 with (b) as a clearly-scoped follow-up. (c) is a section switch and
  loses the search context.

### 6.5 LOW-MEDIUM — matching semantics drift

`TapProjection.filter` uses `localizedCaseInsensitiveContains`; the catalog uses
`PackageText.normalize` + four ranked match classes. Two lists on one screen answering the same
keystroke by different rules is a defect waiting to be filed. Recommend the new projection reuse
`PackageText.normalize` and a reduced rank ladder (exact / prefix / substring — there is no
description to scan). Note `PackageText` lives in `Catalog`, which `BrewClient` already imports.

### 6.6 LOW — `PS6`'s latency budget is shared

The composed section runs on the same synchronous main-actor keystroke turn as `rerank()`. A linear
scan over a few hundred tap names is negligible against 1.02 ms measured p95 / 8 ms ceiling, but the
new requirement should assert the ceiling is not regressed rather than assume it.

### 6.7 LOW — surface copy

`PaneSearchField`'s prompt counts `catalog.packageCount` only, and `EmptyResults` (`BrowseView.swift:126-143`)
reports "no match" without knowing about tap hits. Both need updating so an empty catalog result with
a non-empty tap result does not render a contradictory empty state.

### 6.8 LOW — brew absent / taps unavailable

`TapStore.state` can be `.brewAbsent` or `.failed`. Catalog search works with brew absent by design
(II7). The tap section must then simply be absent — never an error banner in Browse, and never a
reason the catalog results change.

---

## 7. Recommendation

**Approach A**, sliced as one PR.

1. `TapPackageSearch` — a pure, `nonisolated`, `Sendable` projection in
   `Packages/CellarCore/Sources/BrewClient/`, over `TapInventory` + `InstalledInventory`, reusing
   `PackageText.normalize`, `TapProjection.packages(for:installed:)` and `TapProjection.bareToken`.
   Fully unit-testable in `BrewClientTests`.
2. `BrowseView` gains `let taps: TapStore`, a sectioned `List`, a distinct tap-row identity, and a
   tap row that carries name, kind, tap of origin, install state and `MutationMenu`.
   `ContentView` already holds `taps` — one argument at the call site.
3. Install is the **existing** spine with the **existing** bare-token argv and **no trust gate**;
   an untrusted tap surfaces through the **already-shipped** typed refusal plus
   `UntrustedTapRecovery`'s Trust affordance.
4. App-target composition tests in `cellarTests/` (the `TapCompositionTests` /
   `PerPackageTrustCompositionTests` / `ReceiptDetailCompositionTests` pattern), including a
   source-text absence assertion that the Browse tap surface composes no trust gate — mirroring the
   shipped PM10 scanner.

**Why not B**: it buys a nicer result ordering at the price of rewriting PS3, re-plumbing `MatchRank`
through every `PackageEntry` consumer, and creating the exact merged-results appearance PD6 forbids.
The section boundary is not a UX compromise here — it is what makes the tap hits' missing description
and version honest instead of looking like broken catalog rows.

### Rough size against the 5,000-line review budget

| Area | Est. changed lines |
|---|---|
| Spec deltas (ADDED + PD6 + TM5 + TM10, blocks reproduced whole) | ~280 |
| `TapPackageSearch` + hit type | ~140 |
| `BrewClientTests` for the projection | ~260 |
| `BrowseView` sectioning + tap row view | ~180 |
| `cellarTests` composition/absence assertions | ~110 |
| Proposal / design / tasks / verify-report / provenance | ~350 |
| **Total** | **~1,300** |

Comfortably inside 5,000. `delivery_strategy: single-pr` is appropriate; no chaining needed.
**400-line budget risk: High** by the shared default, but the session's cached
`review_budget_lines: 5000` governs — `sdd-tasks` must still emit the guard lines explicitly.

---

## 8. Ready for proposal

**Yes**, with three answers wanted from the maintainer before `sdd-spec`:

1. **§6.1** — when a tap's bare package name collides with a catalog record, does the tap hit get
   suppressed, badged, or shown plainly? (The Install argv cannot disambiguate: PM10.)
2. **§6.2** — does the Browse tap row show the "Untrusted" badge (costs a MODIFIED TM11) or only the
   tap name (costs nothing)?
3. **§6.4** — for a **not-installed** tap hit: non-selectable row (recommended), or a minimal
   name-only detail pane?

**Corrections to the launch brief, recorded here so they do not propagate:**

- There is **no <=1-slash argv invariant in `MutationName.isSafe`** — the validator permits `/`
  deliberately (so `TapName` stays constructible). The invariant is PM10's *absence assertion over
  the whole argv surface*: no `/`-qualified package token, anywhere, ever.
- The proposed **trust gate is prohibited**, not merely optional: PM10 `:659-670` plus two scenarios
  plus a shipped source-scanning assertion. Install is offered unconditionally; brew decides; the
  typed refusal and `UntrustedTapRecovery` handle the rest. This applies to the `unreported` state
  too.
- **Homebrew 6 does not present an interactive trust prompt.** It refuses non-interactively with a
  measured stderr signature Cellar already classifies. There is nothing to suppress in
  `BrewEnvironment`.
- **TM10** (`tap-management/spec.md:533-550`) explicitly excludes *"package installation from tap
  inventory, third-party catalog ingestion or search"*. The brief did not list it; it is the largest
  spec obstacle and needs a MODIFIED alongside PD6 and TM5.

---

## 9. Persistence note (phase-level)

The OpenSpec half of the hybrid store was written by the orchestrator from Engram obs #7794: the
`sdd-explore` agent has no file-writing tool in this session. Content is byte-equivalent apart from
this note and the header line naming the canonical file.
