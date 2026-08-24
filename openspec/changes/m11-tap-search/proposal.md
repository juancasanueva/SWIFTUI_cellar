# Proposal: `m11-tap-search` — find and install tap packages from Browse

Anchors PRD.md **M1 "Core & Catalog"** (§7 :202) — the Browse promise of **§3.1** (:52, "instant,
as-you-type local search") — applied to the tap inventory **§3.7** (:108, "show packages per tap")
delivered in M3. Post-M6 refinement slice. Inputs: `explore.md` (obs `#7794`), maintainer scope
decisions (obs `#7795`, binding).

## Intent

Searching `gentle-ai` in Browse finds nothing, although the maintainer's own tap
(`gentleman-programming/tap`) is installed and publishes it. `PackageSearchIndex` is built from the
`CatalogSnapshot` alone — `homebrew/core` + `homebrew/cask` — so every third-party tap package is
invisible to the one surface users search. The only path today is Taps → tap detail → its filter
field, i.e. the user must already know which tap publishes the package they are looking for. The
data is already resident in `TapStore.inventory` and the install argv is already correct and bare,
so the missing piece is an entry point, not a mechanism.

## Scope

### In Scope
- `TapPackageSearch` (name provisional) in `Packages/CellarCore/Sources/BrewClient/`: a
  `nonisolated`, `Sendable` projection over `TapInventory` + `InstalledInventory` + query +
  `SearchFilters.kinds`, composed **above** the index (II8's discipline), reusing
  `PackageText.normalize` with an exact/prefix/substring ladder and `TapProjection`'s existing
  `packages(for:installed:)` / `bareToken`. Zero brew invocations.
- A distinct **"From your taps"** section in `BrewClient`-fed `BrowseView`, rendered **only for a
  non-empty query**, and **absent** (never an error) when `TapStore.state` is `brewAbsent`/`failed`.
- A tap row carrying **name, kind, tap of origin, install state and `MutationMenu`** — the tap name
  as a plain fact, **no "Untrusted" badge** (TM12, the trust-presentation requirement, untouched; explore used the older ordinal TM11).
- A tap hit whose bare name collides with a catalog record is **shown**, never suppressed, with an
  explicit note that it is also in the catalog and that **Homebrew resolves the install to the
  catalog package**. The argv stays bare (PM10); Cellar surfaces the ambiguity rather than hiding it.
- **Install offered unconditionally** on the existing spine with the existing bare-token argv and
  **no trust gate** — PM10 `:659-670` forbids one, Homebrew 6 refuses non-interactively with a
  signature Cellar already classifies, and `UntrustedTapRecovery` already supplies the Trust
  affordance.
- Not-installed tap rows are **non-selectable**; installed tap hits route to the m10 receipt pane
  through the existing `PackageDetailView` fallthrough with no routing change.
- `EmptyResults` reconciled so a catalog miss with tap hits is not a contradictory empty state;
  the search-field prompt keeps counting catalog records only (unchanged).
- Deltas: `package-search` **ADDED**; **PD6 MODIFIED**; **TM5 MODIFIED**; **TM11 MODIFIED**.

### Out of Scope (explicit non-goals)
- Any **tap-source read** (TM5 forbids it) — so no description, version, homepage, license,
  dependencies, install count, deprecation flag or size for a not-installed tap hit.
- **Merged ranking** — tap hits never interleave into PS3's total order (Approach B).
- Any **trust gate, pre-block, badge or trust-state read** before launch (PM10); no `Untrusted`
  badge in Browse.
- Any **new brew invocation**; any change to the snapshot, `index.search`, `index.package`, or the
  declared `SearchFilters` set.
- A **name-only detail pane** for a not-installed tap hit — a clearly scoped follow-up.
- **Approach C** (ingesting tap names into `PackageSearchIndex`) — **rejected**: it falsifies PD6's
  *"MUST be absent from the snapshot"* and its covered-tap scenario, contradicts TM5, and would make
  `Catalog` depend on `BrewProcess`, which II7's package-graph scenario asserts against.

## Capabilities

### New Capabilities
- None. (`package-search` gains a requirement; it is an existing spec.)

### Modified Capabilities
- `package-search`: **ADDED** — packages published by installed third-party taps are searchable as a
  distinct, composed source: above the index, never in it; fed only by the resident tap inventory;
  a hit is a name, a kind and a tap of origin and nothing else; install on the shared spine with a
  bare token and no trust gate; PS6's ceiling not regressed.
- `package-detail`: **PD6 MODIFIED** — extends m10's boundary paragraph by one clause naming a
  *search-surface* section fed exclusively by the tap inventory, on m10's exact terms. Existing
  scenarios byte-identical; a new scenario asserts `index.search`/`index.package` unchanged.
- `tap-management`: **TM5 MODIFIED** — narrows the "catalog search" half the way m10 narrowed the
  detail half, and states affirmatively that the tap inventory may feed a surface owned elsewhere.
  All 8 scenarios preserved.
- `tap-management`: **TM11 MODIFIED** — narrows *"package installation from tap inventory,
  third-party catalog ingestion or search"* to this capability's **own action set**, naming
  `package-search` and `package-mutation` as the owners. Enumerated-action scenario byte-identical.
- `package-mutation`: **none (provisional)** — PM10 already mandates the bare token and forbids the
  gate; cite it rather than restate it. Touch only if `sdd-spec` finds a genuine gap.
- `installed-inventory`: **none** — II7/II8/II15 already license composition-above-the-index and the
  receipt pane.

## Approach

Approach **A** from `explore.md` §5. The projection lands as a value type in `BrewClient` — the
target that owns `TapInventory` — beside the shipped `InstalledBrowse` and `TapProjection` idiom, so
it is unit-testable in `BrewClientTests` with no SwiftUI and no `Process`, and the dependency
direction (`BrewClient` → `Catalog`, never the reverse) stays as II7 asserts. The index is untouched
**by construction**, so PS1–PS7 hold without argument and PD6/TM5 compliance is provable by a test
that queries `index.search`/`index.package` and finds nothing. `ContentView` already holds `taps` —
one argument at the `BrowseView` call site, no new store wiring. Install reuses the existing spine
unchanged: `TapPackage.id` already *is* the bare token `MutationCommand.install` emits.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `BrewClient/TapPackageSearch.swift` | **New** | Pure ranked projection + hit type over the tap inventory |
| `cellar/Browse/BrowseView.swift` | Modified | `let taps: TapStore`; sectioned `List`; prompt + `EmptyResults` copy |
| `cellar/Browse/TapSearchSection.swift` | **New** | Name, kind, tap of origin, collision note, `MutationMenu` |
| `cellar/ContentView.swift` | Modified | One argument: `taps` passed into `BrowseView` |
| `Tests/BrewClientTests/` | **New** | Ranking ladder, kind filter, collision, empty query, absent-tap-state |
| `cellarTests/` | **New**/Modified | Composition + source-text absence assertion (no trust gate in Browse) |
| `cellar.xcodeproj/project.pbxproj` | **Untouched — binding 0-line diff** | `cellar/Browse/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup` roots |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| R1 `PackageID` collision: duplicate row identity, catalog-first detail routing, brew resolving Install to the catalog package | **High** | Distinct **row** identity (`tapName/kind/name`) with `PackageID` kept only as the mutation target; explicit catalog note on the row; argv stays bare (PM10); collision asserted by test |
| R2 PD6/TM5/TM11 read as a blanket ban on tap search | **High** | Land all three MODIFIED deltas in the first work unit, before any surface code |
| R3 A trust gate creeps into the Browse tap surface | Med | Source-text absence assertion in `cellarTests/`, mirroring the shipped PM10 scanner |
| R4 Sectioned `List` regresses catalog row identity/selection | Med | Tap rows non-selectable; catalog selection plumbing asserted behaviourally unchanged |
| R5 Empty-state copy contradicts itself (catalog miss + tap hits) | Med | `EmptyResults` reasons recomputed over both sources; asserted |
| R6 PS6's shared keystroke budget regressed | Low | Linear scan over tens-to-hundreds of names vs 1.02 ms measured p95 / 8 ms ceiling; the new requirement asserts non-regression |
| R7 Artifact overshoot (m7 overshot 5–7×) | Med | `sdd-tasks` forecasts artifacts separately and splits work units if 5,000 is threatened |

## Rollback Plan

`rules.proposal` mandates one for anything touching the Xcode project file or target membership.
**Neither is touched.** `cellar/Browse/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup`
roots (the same fact m5-discover slice 1, m6-cask-tap and m10 relied on), so `TapSearchSection.swift` and
any new test file join their targets with a **0-line pbxproj diff**. A non-zero `project.pbxproj`
diff is a defect, not a rollback step: restore with
`git checkout HEAD -- cellar.xcodeproj/project.pbxproj` and re-verify membership before proceeding.

Otherwise: revert the PR. Nothing persists — no file format, no migration, no stored state, no new
process, no new brew invocation. Deleting `TapPackageSearch.swift` and `TapSearchSection.swift` and
restoring `BrowseView`'s flat `List(rows, selection:)` returns the app exactly to today. The four
deltas revert with the change folder; promoted `openspec/specs/` are untouched until archive.

## Dependencies

None new. The tap inventory is already resident from the shipped `brew tap-info --installed --json`
refresh (TM1). The refusal path (`MutationOutcome.refusedUntrustedTap`, `UntrustedTapRecovery`,
PM10's typed copy) is already shipped and measured against Homebrew 6.0.18.

## Size Forecast

~**1,100–1,600** changed lines against the **5,000** budget under the cached `single-pr` strategy —
**budget risk: Low**. TM5's ~90-line whole-block MODIFIED is the largest unavoidable single cost.

## Success Criteria

- [ ] Typing `gentle-ai` in Browse shows it under **"From your taps"** with an **Install** action.
- [ ] Installing from an untrusted tap yields the **already-shipped typed refusal** plus the Trust
      recovery — not a pre-launch block, and not a qualified argv.
- [ ] A tap hit colliding with a catalog record is shown with the explicit catalog note; neither row
      is suppressed and no argv is qualified.
- [ ] The tap section is absent for an empty query, and absent (never an error) when `TapStore` is
      `brewAbsent`/`failed`.
- [ ] An installed tap hit opens the m10 receipt pane; a not-installed tap row is non-selectable.
- [ ] `index.search` and `index.package` return byte-identical results before and after; no new brew
      invocation; PS6's p95 ceiling not regressed.
- [ ] The Browse tap surface composes no trust gate and no "Untrusted" badge (both asserted as
      absences).
- [ ] `cellar.xcodeproj/project.pbxproj` diff is 0 lines.
