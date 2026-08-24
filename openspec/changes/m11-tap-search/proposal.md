# Proposal: `m11-tap-search` — a "Search our taps" section beside Search catalog

Anchors PRD.md **M1 "Core & Catalog"** (§7 :202) — the search promise of **§3.1** (:52, "instant,
as-you-type local search") — applied to the tap inventory **§3.7** (:108, "show packages per tap")
delivered in M3. Post-M6 refinement slice. Inputs: `explore.md` (obs `#7794`), maintainer scope
decisions (obs `#7795`; **scope change 2026-08-25, binding**).

## Revision history

- **r1** (2026-08-24) — a composed "From your taps" **section inside Browse**, below the catalog
  rows, rendered only for a non-empty query. Implemented in apply round 1.
- **r2** (2026-08-25, this revision) — **maintainer scope change**. Browse returns to **exactly**
  what it is on `main`; the tap surface moves to its **own sidebar section, "Search our taps"**, a
  visually exact copy of the Browse view showing tap packages only, whose **empty query lists every
  third-party tap package** the way Browse lists the whole catalog. Round 1's projection, deltas and
  invariants carry over unchanged; its **view half is replaced**.

## Intent

Searching `gentle-ai` finds nothing, although the maintainer's own tap
(`gentleman-programming/tap`) is installed and publishes it. `PackageSearchIndex` is built from the
`CatalogSnapshot` alone — `homebrew/core` + `homebrew/cask` — so every third-party tap package is
invisible to search. The only path today is Taps → tap detail → its filter field, i.e. the user must
already know which tap publishes the package they want. The data is already resident in
`TapStore.inventory` and the install argv is already correct and bare, so the missing piece is an
entry point, not a mechanism.

r2 sharpens *which* entry point. Catalog search and tap search answer different questions over
different data with different fields available, and mixing them into one list forced the catalog
surface to absorb a second source's empty states, ranking and copy. Two sibling sections in
**Overview** — *Search catalog* and *Search our taps* — say that plainly, and leave the catalog
surface untouched.

## Scope

### In Scope
- `TapPackageSearch` — **carried over from round 1, unchanged**: a `nonisolated`, `Sendable`
  projection in `Packages/CellarCore/Sources/BrewClient/` over `TapInventory` +
  `InstalledInventory`, composed above the index (II8's discipline), reusing `PackageText.normalize`
  with the exact/prefix/substring ladder. Zero brew invocations; measured **p95 2.500 ms** against
  PS6's 8 ms ceiling.
- A **new `AppSection` case** placed immediately after `.browse`, sidebar title **"Search our
  taps"**, in the **Overview** group beside Home and Search catalog, with an SF Symbol consistent
  with `.browse`'s `magnifyingglass`.
- **`cellar/Browse/TapSearchView.swift`** — a visually exact copy of the Browse view: search field,
  filter bar, list, and detail pane, showing third-party tap packages **only**.
- Its filter bar carries **kind chips + Hide installed**, and **no Outdated chip** — a tap hit
  carries no version, so an outdated verdict is unavailable and an inert control would be a lie.
- An **empty query lists every package from all third-party taps**, labelled by tap of origin,
  mirroring Browse listing the whole catalog. (This **reverses** round 1's empty-query absence rule.)
- Tap rows: **name, kind, tap of origin, projection-supplied install-state copy, collision note when
  the bare token is also in the catalog, and `MutationMenu`** — Install offered unconditionally on
  the existing bare-token spine, **no trust gate** (PM10).
- **Installed rows select** and open the m10 receipt pane; **ambiguous and not-installed rows are
  non-selectable**. The `routableID` rule is carried over from round 1 **unchanged**.
- When `TapStore.state` is `brewAbsent` or `failed`, the section shows an **honest empty state in
  its own view** — never an error banner, and never a change to catalog behaviour.
- **`BrowseView.swift` ends this change with a zero diff against `main`.**
- Deltas: `package-search` **ADDED (PS8)**; **PD6 MODIFIED**; **TM5 MODIFIED**; **TM11 MODIFIED**.

### Out of Scope (explicit non-goals)
- Any **tap-source read** (TM5 forbids it) — so no description, version, homepage, license,
  dependencies, install count, deprecation flag or size for a not-installed tap hit.
- Any **change to Browse** — no section, no new source, no copy change, no filter change. Zero diff.
- **Merged ranking** — tap hits never enter or interleave with PS3's order (Approach B).
- Any **trust gate, pre-block, badge or trust-state read** before launch (PM10); no `Untrusted`
  badge (TM12, the trust presentation, stays untouched).
- An **Outdated filter** for tap packages, and any outdated verdict over them.
- Any **new brew invocation**; any change to the snapshot, `index.search`, `index.package`, or the
  declared `SearchFilters` set.
- A **name-only detail pane** for a not-installed tap hit — still a follow-up.
- **Approach C** (ingesting tap names into `PackageSearchIndex`) — **rejected**: it falsifies PD6's
  *"MUST be absent from the snapshot"* and its covered-tap scenario, contradicts TM5, and would make
  `Catalog` depend on `BrewProcess`, which II7's package-graph scenario asserts against.

## Capabilities

### New Capabilities
- None. (`package-search` gains a requirement; it is an existing spec.)

### Modified Capabilities
- `package-search`: **ADDED — PS8**. Packages published by installed third-party taps are searchable
  as a distinct, composed source: above the index, never in it; fed only by the resident tap
  inventory; a hit is a name, a kind and a tap of origin and nothing else; install on the shared
  spine with a bare token and no trust gate; PS6's ceiling not regressed. **r2 revises PS8's
  presentation rules**: the surface is its own sidebar section rather than a Browse section; the
  empty query enumerates rather than withholds; there is no outdated-only absence rule because
  there is no Outdated control.
- `package-detail`: **PD6 MODIFIED** — extends m10's boundary paragraph by one clause naming a
  *search-surface* fed exclusively by the tap inventory, on m10's exact terms. Three shipped
  scenarios byte-identical; one added.
- `tap-management`: **TM5 MODIFIED** — narrows the "catalog search" half the way m10 narrowed the
  detail half, and states affirmatively that the tap inventory may feed a surface owned elsewhere.
  All 10 shipped scenarios byte-identical.
- `tap-management`: **TM11 MODIFIED** — narrows *"package installation from tap inventory,
  third-party catalog ingestion or search"* to this capability's **own action set**, naming
  `package-search` and `package-mutation` as the owners. Both shipped scenarios byte-identical.
  (`explore.md` calls this requirement **TM10** by narrative count; the main spec marks it
  `<!-- TM11 -->` at `:532`. The drift is recorded once at `specs/README.md:98-106`.)
- `package-mutation`: **none** — PM10 already mandates the bare token and forbids the gate;
  activated, not changed (`specs/README.md:73`).
- `installed-inventory`: **none** — II7/II8/II15 already license composition-above-the-index and the
  receipt pane (`specs/README.md:90`).

## Approach

Approach **A** from `explore.md` §5, with r2's surface placement. The projection stays a value type
in `BrewClient` — the target that owns `TapInventory` — beside the shipped `InstalledBrowse` and
`TapProjection` idiom, unit-tested in `BrewClientTests` with no SwiftUI and no `Process`, with the
dependency direction (`BrewClient` → `Catalog`, never the reverse) as II7 asserts. The catalog index
is untouched **by construction**, so PS1–PS7 hold without argument and PD6/TM5 compliance is proven
by a test that queries `index.search`/`index.package` and finds nothing.

The view half becomes a sibling of `BrowseView` rather than a mutation of it. `TapSearchView` owns
its own query, kind filter and hide-installed state; `ContentView` constructs it and routes its
detail column into the existing `PackageDetailView`, whose m10 receipt fallthrough already resolves
an installed tap package with **no new routing branch**. `AppSection` gains one case and one
`sidebarGroups` entry; `listPaneWidths` is already keyed by `AppSection`, so the new section earns
its own remembered pane width for free.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `BrewClient/TapPackageSearch.swift` | **Carried over** | Round 1's projection and hit type, unchanged apart from r2's empty-query and outdated rules |
| `cellar/Shell/AppSection.swift` | Modified | One case after `.browse`; `title`, `sidebarTitle` ("Search our taps"), `systemImage`, and the **Overview** `sidebarGroups` entry |
| `cellar/Browse/TapSearchView.swift` | **New** | The section's whole surface: search field, filter bar (kind chips + Hide installed), list, empty states |
| `cellar/Browse/TapSearchSection.swift` | **Deleted** | Round 1's in-Browse section; its row body moves into `TapSearchView` |
| `cellar/Browse/BrowseView.swift` | **Reverted — binding 0-line diff vs `main`** | `taps` parameter, `tapHits`, the sectioned `List` and the two-source empty overlay all come out |
| `cellar/ContentView.swift` | Modified | Constructs `TapSearchView`; adds the section's list and detail cases; passes `taps`, `installed`, `operations` |
| `Tests/BrewClientTests/` | **Carried over** | 26 projection rows, incl. the release-build latency measurement; empty-query rows revised |
| `cellarTests/` | Modified | `TapSearchCompositionTests` retargeted from the Browse section to the new section; `AppSectionPlacementTests` gains the placement claim; the Browse-side rows are retired with the surface they asserted |
| `cellar.xcodeproj/project.pbxproj` | **Untouched — binding 0-line diff** | `cellar/Browse/`, `cellar/Shell/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup` roots |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| R1 `PackageID` collision: catalog-first resolution would open or install a different package than the row chosen | **High** | Carried over unchanged: a distinct row identity, `routableID` `nil` for ambiguous rows (inert), the projection-supplied collision note, and a bare argv (PM10). Already asserted by round 1's ps8/ps10 rows |
| R2 PD6/TM5/TM11 read as a blanket ban on tap search | **High** | All three MODIFIED deltas already drafted and landed in WU1; r2 changes their presentation clauses only |
| R3 A trust gate creeps into the tap surface | Med | Source-text absence assertion mirroring the shipped PM10 scanner, **retargeted** to `TapSearchView` — a scan still pointed at `TapSearchSection` would pass vacuously |
| R4 **Sidebar/section wiring**: a new `AppSection` case must be added to `sidebarGroups`, the list switch, the detail switch and the toolbar, each an exhaustive switch across `ShellToolbar` and `ContentView` | **Med-High** | `AppSectionPlacementTests` pins the group and order; the compiler catches every exhaustive switch; placement asserted rather than eyeballed |
| R5 Empty-query enumeration is unbounded by query and now the default view of the section | Med | The projection already composes the whole tap inventory in the measured turn; re-measure the **empty-query** turn explicitly rather than reusing round 1's query-shaped p95 |
| R6 Detail selection shared with Browse's `selection` cross-contaminates two sections | Med | `sdd-design` decides: a dedicated `@State` for the new section, following the shipped `serviceSelection` / `tapSelection` precedent, rather than reusing `selection` |
| R7 A stale Browse assertion survives the revert and passes vacuously | Med | Task 6.3's binding proof gains `BrowseView.swift` to its zero-diff `git diff --stat main` list |
| R8 **The 5,000-line budget is now genuinely tight** | **High** | Round 1 already landed ~4,400; see the forecast below. `sdd-tasks` must re-measure before apply and raise a `size:exception` or a slice **before** work starts, not after |

## Rollback Plan

`rules.proposal` mandates one for anything touching the Xcode project file or target membership.
**Neither is touched.** `cellar/Browse/`, `cellar/Shell/` and `cellarTests/` are
`PBXFileSystemSynchronizedRootGroup` roots (the fact m5-discover slice 1, m6-cask-tap and m10 relied
on), so `TapSearchView.swift` joins its target — and `TapSearchSection.swift` leaves it — with a
**0-line pbxproj diff**. A non-zero `project.pbxproj` diff is a defect, not a rollback step: restore
with `git checkout HEAD -- cellar.xcodeproj/project.pbxproj` and re-verify membership.

**Within the branch (r1 → r2):** the view half is one revertible boundary. Restore
`BrowseView.swift` from `main` (`git checkout main -- cellar/Browse/BrowseView.swift`), delete
`TapSearchSection.swift`, add `TapSearchView.swift`, and retarget the composition tests. The
projection, its 26 tests and the three spec deltas are untouched by this step, so a failure in the
view half never costs the verified core.

**Whole change:** revert the PR. Nothing persists — no file format, no migration, no stored state,
no new process, no new brew invocation. Removing the `AppSection` case, `TapSearchView.swift`,
`TapPackageSearch.swift` and the tests returns the app exactly to `main`. The three deltas revert
with the change folder; promoted `openspec/specs/` are untouched until archive.

## Dependencies

None new. The tap inventory is already resident from the shipped `brew tap-info --installed --json`
refresh (TM1). The refusal path (`MutationOutcome.Signature.untrustedTap`, `UntrustedTapRecovery`,
PM10's typed copy) is already shipped and measured against Homebrew 6.0.18.

## Size Forecast

**Apply round 1 already landed 4,404 lines on `feat/m11-tap-search`** (task 6.6 measured
**4,344** authored lines — 18 files, +4,330 / −14 — at the time it ran; later artifact edits account
for the rest). Round 2 **replaces the view half**: `BrowseView.swift` returns to a zero diff
(≈ −45 authored), `TapSearchSection.swift` is deleted (−92), `TapSearchView.swift` is added
(≈ +200), `AppSection.swift` (+8) and `ContentView.swift` (≈ +35) gain the wiring, and the
composition tests are retargeted (≈ +60 net). Net **≈ +150 to +200**, landing the branch near
**4,550–4,650** before this revision's own artifact edits and before `verify-report.md`
(forecast ≈ 250–450).

**Projected total ≈ 4,900–5,200 against the 5,000 budget — budget risk: HIGH.** This is a decision
`sdd-tasks` must take before apply round 2 starts: either an accepted `size:exception`, or a slice
that delivers the section separately from the round-1 revert. It must not be discovered at
verification.

## Success Criteria

- [ ] The sidebar's **Overview** group shows **Home · Search catalog · Search our taps**, in that
      order.
- [ ] Typing `gentle-ai` in **Search our taps** finds it, with an **Install** action.
- [ ] Opening the section with an **empty query** lists every third-party tap package, each labelled
      by its tap of origin.
- [ ] The section's filter bar offers kind chips and Hide installed, and **no Outdated chip**.
- [ ] Installing from an untrusted tap yields the **already-shipped typed refusal** plus the Trust
      recovery — not a pre-launch block, and not a qualified argv.
- [ ] A hit colliding with a catalog record shows the collision note and is **inert**; a
      not-installed row is inert; an installed row opens the m10 receipt pane.
- [ ] With `TapStore` `brewAbsent`/`failed`, the section shows an empty state in its own view — no
      error banner, and catalog behaviour unchanged.
- [ ] **`git diff main -- cellar/Browse/BrowseView.swift` is empty.**
- [ ] `index.search` and `index.package` are behaviourally byte-identical; no new brew invocation;
      the keystroke turn stays under PS6's 8 ms ceiling, re-measured for the empty query.
- [ ] The tap surface composes no trust gate and no "Untrusted" badge (both asserted as absences,
      against `TapSearchView`).
- [ ] `cellar.xcodeproj/project.pbxproj` diff is 0 lines.
