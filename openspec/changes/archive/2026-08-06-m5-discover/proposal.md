# Proposal: M5 Discover (`m5-discover`)

Anchors PRD.md **M5** (§7); feature §3.1 (Discover tab, as amended). Slice **2 of 5** per the
recorded M5 decision round (Engram obs 7477). Exploration: `openspec/changes/m5-pro-parity/explore.md`
(obs 7476). Slice 1 archived at `163edd5`.

## Intent and Users

Cellar answers "find the package whose name I already know". A user who does **not** know what to
install has no entry point: Browse is a search field over ~16k records, and an empty query returns
nothing worth looking at. Discover serves the user *before* they have a query — what other people
actually install, a short hand-picked list, and what has shown up since they last looked. Two of the
three inputs are already downloaded on every sync and thrown away unprojected. This slice is also the
lowest-risk place to establish the new-sidebar-section pattern that slice 5 reuses for Health.

## Product Rules (user-approved, binding)

- **Zero new egress.** Rankings come from the analytics join the sync already performs; the curated
  list ships inside the app. No new endpoint, no per-package fetch, no consent surface.
- **Absent is not zero.** A package the analytics endpoint never listed is *unranked*, not
  rank-last. `installCount` is `Int?` for exactly this reason (package-detail PD5).
- **Formulae and casks rank separately, 50 deep each.** The two endpoints measure different
  quantities — `install-on-request` vs `cask-install`, already modelled as `InstallCount.metric` —
  so a single merged ladder would sort incomparable numbers and misrepresent both. Deprecated and
  disabled packages are ineligible for either ladder.
- **"New to you" means exactly that.** Newness is derived locally by diffing against what Cellar has
  seen before. It is not a publication date and MUST NOT be labelled as one. A package stays listed
  for **30 days** after Cellar first sees it. Empty on first run is a **designed state with its own
  copy**, not an error, a spinner or a hidden section.
- **A curated entry missing from the catalog is skipped and counted**, never rendered as a dead row
  (`skippedRecordCount` idiom).
- **Discover never opens empty.** Rankings and the curated list are always present; only the "new to
  you" section carries an empty state.

## Scope

**In:** top-50 most-installed projections per kind (formulae, casks) in the `Catalog` target; a
durable known-package roster persisted beside the snapshot, plus the dated 30-day arrivals log the
diff feeds and prunes; a curated list of ~20–30 entries in 3–5 categories, shipped as a resource with
a tolerant decoder and counted skips; a new `.discover` case in `cellar/Shell/AppSection.swift`
between `.home` and `.browse`, with its views and `ContentView`/`cellarApp` wiring.

**Out (non-goals):** any new network call, endpoint or credential; changes to Browse search, filters
or ranking; editorial content beyond a v1 seed list; slices 3–5 (release notes, Brewfile, health +
bulk polish); **any new field on `CatalogPackage`**; any change to `CatalogSnapshot`'s shape or
schema version.

## Capabilities

- **New `package-discovery`** — ranked projections and their absent/tie rules, curated-list decoding
  with counted skips, arrival diffing, and the first-run empty contract.
- **MODIFIED `catalog-sync`** — sync gains a durable known-package roster written next to the
  snapshot, with its own read/discard rule, its 30-day arrivals retention, and an explicit guarantee
  that it never enters `CatalogSnapshot`.
- **Unchanged:** the other 15 shipped capabilities.

## Approach

**The revision ordinal cannot carry newness.** `CatalogSnapshotRevision` is documented as
*process-local and never persisted* (`CatalogModels.swift`, catalog-sync design D2) — ordinals
restart at 1 on every launch, so a diff keyed on them would report the entire catalog as new on the
second launch. The M5 decision round's "diff via revision ordinals" is therefore not implementable as
stated. Newness needs a **durable roster** of the package IDs Cellar has already seen; the ordinal
keeps its existing job (deciding which materialization wins in `adopt`) and gains none.

**That roster must not touch `CatalogPackage`.** Slice 1's `CatalogFootprintTests` pins the encoded
snapshot at 1.56× against a 1.6× bound — 2.4% headroom — and a single persisted per-record field
(a first-seen ordinal or date) would cross it across ~16k records. So the roster ships as its **own
file** owned by `CatalogFileStore`, beside `catalog-state.json`, under the same exact
schema-version gate (missing, corrupt or mismatched all mean "seen nothing", the CS6 idiom).
`CatalogSnapshot` is untouched, `currentSchemaVersion` stays **2**, and `CatalogFootprintTests` is
re-run unchanged rather than re-based. The roster gets its own small size bound so it cannot grow
unpoliced.

**The roster and the arrivals log are two different things** (D2). The roster is the full seen-set,
names only, no dates — it answers "have I seen this before". The arrivals log is small and dated: the
IDs the last diff found new, pruned at 30 days. Only the arrivals log carries timestamps, so dating
costs a few hundred entries rather than ~16k.

Rankings are pure sorts over the snapshot already in memory — no store, no acquisition, no actor
change. The curated list ships inside the app bundle as required by D1, carried as a resource on the
`Catalog` target rather than a loose file under `cellar/`: both land in the built `.app`, but only
the former keeps the decoder and its skip accounting testable under `swift test`, which the project's
"all logic in CellarCore" rule requires. It decodes off the main actor (`@concurrent static func`
over `Data`, attribute before the modifier). The app target gains presentation only.

| Area | Impact |
|---|---|
| `Sources/Catalog/` — new ranked-projection + curated-list + roster/diff files | New |
| `Sources/Catalog/CatalogFileStore.swift`, `CatalogSyncEngine.swift` | Modified — roster read/write at persist time |
| `Packages/CellarCore/Package.swift` | Modified — `resources:` on the `Catalog` target |
| `cellar/Shell/AppSection.swift`, `cellar/ContentView.swift`, `cellar/cellarApp.swift` | Modified — `.discover` case, exhaustive switch, wiring |
| `cellar/Discover/` | New — section views |
| `Tests/CatalogTests/` | New cases + roster size bound; footprint suite re-run unchanged |

## Risks

| Risk | L | Mitigation |
|---|---|---|
| Roster field lands on `CatalogPackage` and breaks the 1.56×/1.6× bound | Med | Spec-level prohibition; separate file; footprint suite re-run unchanged as a gate |
| Roster file grows unbounded or bloats every sync write | Med | Names-per-kind encoding, own size bound as a test, retention window on the arrivals log |
| "New to you" reads as "new on Homebrew" | High | Copy reviewed at spec level; the honest phrasing is the requirement, not a UI note |
| SwiftPM resource bundle does not reach the built `.app` | Med | Load the curated list through the shipped accessor in a test, plus an app-target check |
| Ranking flattens unranked packages to 0 | Med | `Int?` preserved end to end; explicit scenario for absent counts |
| Curated list rots as tokens are renamed or removed | Low | Tolerant skip + count, surfaced honestly; content is release-updatable by design |

## Rollback Plan

Additive and revertible by `git revert` of the slice PR. **No new CellarCore target, product or
dependency edge**; the only `Package.swift` change is `resources:` on the existing `Catalog` target,
which reverts by deleting that line and the resource directory. New app files live under
`cellar/Discover/`, a `PBXFileSystemSynchronizedRootGroup` root — slice 1 confirmed for
`cellar/Browse/` that this needs **no pbxproj edit**, so there is no target-membership, build-setting
or scheme change to unwind. `CatalogSnapshot` and `currentSchemaVersion` are untouched, so no cache
is invalidated in either direction. A reverted build simply never reads the roster file; the orphaned
file is inert and is re-created if the slice is re-applied.

## Delivery

Session budget **5,000** lines, `single-pr`, strict TDD. Forecast **700–1,200** authored source+tests,
**1,800–2,800** including lifecycle artifacts. No size exception is requested; the review workload
guard resolves after `sdd-tasks`.

## Success Criteria

- [ ] A user with no query sees something worth installing: separate formula and cask rankings plus a
      curated list.
- [ ] No new network request is issued by opening Discover — asserted, not assumed.
- [ ] Unranked packages are absent from rankings rather than ranked last.
- [ ] "New to you" is empty and honestly explained on first run, correct on the second sync, and a
      package leaves the list 30 days after it arrived.
- [ ] `CatalogFootprintTests` passes **unchanged**, and `CatalogPackage` gained no field.
- [ ] A curated entry pointing at a removed token is skipped, counted and never rendered.
- [ ] D1–D5 are each traceable to a spec requirement before design closes.

## Resolved Decisions (user-approved, binding)

Answered in the proposal question round. These are decisions, not assumptions; specs derive from them
and MUST NOT re-open them. Each names what was rejected, so a later phase cannot reintroduce a
rejected alternative as a fresh idea.

- **D1 — Curated list: maintainer-authored, ~20–30 entries, 3–5 named categories, short blurbs.**
  An entry is a token plus a category plus a blurb, never a bare token. Blurbs are written in
  Cellar's voice and say *why you might want this*; the package's own `desc` is not a blurb. The list
  ships inside the app bundle and is updated by shipping a release. **Rejected:** fetching or
  refreshing curated content over the network, which would break the zero-egress rule. Authoring
  content beyond a v1 seed list stays out of scope.
- **D2 — "New to you" is a rolling 30-day dated arrivals log.** A package appears when a sync first
  observes it and stays listed for 30 days from that moment, so the section survives the daily sync
  instead of emptying every 24 h. The 30 days are measured from *first observation by this machine*,
  never from a publication date the catalog does not carry. **Rejected:** the strictly
  since-last-sync variant — simpler, but empty almost all the time, which ships a section the user
  never sees populated.
- **D3 — Top 50 per ladder, two ladders, deprecated and disabled excluded.** Formulae and casks stay
  separate because `install-on-request` and `cask-install` are different measurements. **Rejected:**
  a single merged most-installed ladder (it sorts incomparable numbers), an unbounded or
  full-catalog ranking, and including deprecated or disabled packages — recommending an abandoned
  package is worse than showing a shorter list.
- **D4 — `.discover` sits between `.home` and `.browse`.** Home is untouched by this slice.
  **Rejected:** making Discover the landing section, and folding Home into it. PRD §5 lists Discover
  first, but Home's future belongs to slice 5 once the Health dashboard exists; deciding it here
  would change the app's landing surface twice.
- **D5 — Section-level empty state only; Discover never opens empty.** Rankings and the curated list
  are always present, because both are available from the first successful sync. When the arrivals
  log is empty, the "new to you" section explains that newness is measured from this sync onward.
  **Rejected:** a tab-level empty screen, hiding the section entirely, and a spinner — the first-run
  state is a designed, explained state, not a pending one.
