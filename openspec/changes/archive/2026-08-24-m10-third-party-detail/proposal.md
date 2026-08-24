# Proposal: `m10-third-party-detail` — a receipt-backed reduced detail pane

Anchors PRD.md **M1 "Core & Catalog"** (§7 :202) — the package-detail promise of **§3.1** (:53, "tap of
origin") — applied to the installed-only records **§3.2** (:59) delivered in M2. Post-M6 refinement slice.
Inputs: `explore.md` (obs `#7781`; §8 probe `#7782`), maintainer scope decisions (obs `#7780`, binding).

## Intent

`Home-Cellar` — installed from the maintainer's own tap — opens to
`ContentUnavailableView("No further details")`. So does every tap-only, unpublished or locally-built
package. The receipt Cellar **already decoded** holds the version story, kegs, link state, pin state,
auto-updates flag, homepage and tap of origin. `installed-inventory` **II7** already promises such a
package is listed with "everything the snapshot knows about it"; the detail surface is the one place
that promise is unkept. Separately, m9 shipped **PD8**'s `Trusted individually` marker, but this branch
renders no tap-of-origin fact for it to sit beside — so a per-package grant is invisible exactly where
it would explain why the package works at all.

## Scope

### In Scope
- `InstalledDetailProjection` (name provisional) in `Packages/CellarCore/Sources/BrewClient/`: a
  `nonisolated`, `Sendable` value over `InstalledPackage` exposing ordered facts with **absence
  preserved** and no formula/cask cross-contamination (kegs/`linkedKeg` formula-only;
  `declaresAutoUpdates` cask-only, tri-state per II2).
- Render it from the **existing** `uncatalogedContent` branch, moved into new
  `cellar/Browse/PackageDetailView+Receipt.swift`. The shared `header(id:displayName:…)` is unchanged —
  one identity row, two panes.
- A **Tap fact** from `InstalledPackage.tap`, with the PD8 marker beside it via the existing
  `TapProjection.grantsIndividually(_:publishedBy:in:)`. Tap `nil` ⇒ no fact **and** no marker.
- The **same verbs as the installed row**, by reusing `MutationMenu(center:entry:)` **unchanged**
  (`cellar/Installed/InstalledRow.swift:61` already renders it for `catalog: nil` entries). No verb is
  re-implemented.
- Reuse `PackageMetadataSection`, `sizeOnDisk(for:)` and `installedAs(for:)` unchanged.
- Deltas: `installed-inventory` **ADDED**; **PD6 MODIFIED** (one boundary sentence; both scenarios
  byte-identical); **TM5 MODIFIED** (narrowed). Provenance corrects m9's **TM1→TM5** mis-citation.

### Out of Scope (explicit non-goals)
- An **"Installed on"** fact. `InstalledDecoder.date(_:)` collapses a missing timestamp to the epoch and
  would print *1 Jan 1970*; that decoder fix is a follow-up, not m10.
- Receipt-backed **release notes** (`release-notes` D4 territory: entry point + egress consent).
- **Any new brew invocation**; any change to catalog search, snapshot or sync.
- Any **trust control** on the pane (PT7); any negative per-package copy (PT6).
- Any copy claiming **"third-party tap"** — a catalog miss has ≥4 causes. Today's scoped copy stays.
- **Approach C** (synthesizing a `CatalogPackage`) — **rejected**: it falsifies PD6's covered-tap
  scenario, makes PD1's absence rows into false catalog claims, and needs a sentinel tap.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `installed-inventory`: **ADDED** — the installed receipt supplies a reduced detail for a package the
  catalog does not carry (II7's promise, finally at the detail surface).
- `package-detail`: **PD6 MODIFIED** — the catalog exclusion binds the *catalog projection*; a rendering
  fed exclusively by the installed receipt is not a catalog detail. Search absence reproduced verbatim.
- `tap-management`: **TM5 MODIFIED** — "selection MUST NOT create a third-party detail fallback" narrowed
  to its meaning: no catalog record is fabricated and no tap-source read completes a package detail.

## Approach

Approach **A** from `explore.md` §6. Logic lands as a value type in `BrewClient` — the target that owns
`InstalledPackage` — so it is unit-testable in `BrewClientTests` with no SwiftUI and no process, and
`Catalog` never gains a dependency on the brew-process layer (II7's asserted scenario). The app target
only renders it. No routing change, no new store wiring, no new process spawn: `InstalledStore`,
`TrustGrantStore`, `DiskUsageStore` and `MetadataStore` are already wired at
`cellar/ContentView.swift:533-544`. This mirrors the shipped `TapProjection` / `ReleaseNotesPresentation`
idiom.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `BrewClient/InstalledDetailProjection.swift` | **New** | Ordered facts over `InstalledPackage`, absence preserved |
| `cellar/Browse/PackageDetailView+Receipt.swift` | **New** | The pane body; extension keeps the 875-line view reviewable |
| `cellar/Browse/PackageDetailView.swift:369-390` | Modified | `uncatalogedContent` body moves out; `primaryButton` gains `MutationMenu` |
| `Tests/BrewClientTests/` | **New** | Projection unit coverage, formula/cask asymmetry, absence enumeration |
| `cellarTests/` | Modified/New | PD8 marker present; **no** trust control; no locally composed marker copy |
| `cellar.xcodeproj/project.pbxproj` | **Untouched — binding 0-line diff** | `cellar/Browse/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup` roots |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| R1 PD6/TM5 read as a blanket ban; m9 archive says so in 3 places | **High** | Land both MODIFIED deltas in the first work unit; record the TM1→TM5 correction |
| R2 The pane's copy drifts into "this is from a third-party tap" | Med | Non-goal above; existing scoped copy asserted byte-identical by test |
| R3 A marker composed locally instead of via `TapProjection` | Med | `PerPackageTrustCompositionTests.swift:59-75` already fails the build for that |
| R4 Upgrading a third-party package trips brew's interactive trust prompt non-interactively | Med | Verbs are the *unchanged* shared `MutationMenu`; behaviour is identical to the installed row it already ships on |
| R5 An absent field renders as `""` / "unknown" (PD1 by imitation) | Med | Absence lives in the value type where a test can enumerate it |
| R6 `PackageDetailView.swift` grows past reviewability | Low | New file, not in-place growth |
| R7 Artifact overshoot (m7 overshot 5–7×) | Med | Forecast artifacts separately in `sdd-tasks`; split work units if 5,000 is threatened |

## Rollback Plan

`rules.proposal` mandates one for anything touching the Xcode project file or target membership.
**Neither is touched.** `cellar/Browse/` is a `PBXFileSystemSynchronizedRootGroup` root (confirmed in
`cellar.xcodeproj/project.pbxproj`; the same fact m5-discover slice 1 and m6-cask-tap relied on), so
`PackageDetailView+Receipt.swift` and any new test file join their targets **with a 0-line pbxproj
diff**. If a non-zero `project.pbxproj` diff appears, that is a defect, not a rollback step: restore with
`git checkout HEAD -- cellar.xcodeproj/project.pbxproj` and re-verify membership before proceeding.

Otherwise: revert the PR. Nothing persists — no file format, no migration, no stored state, no new
process. Deleting `InstalledDetailProjection.swift` and `PackageDetailView+Receipt.swift` and restoring
`uncatalogedContent`'s `ContentUnavailableView` returns the app exactly to today. The three deltas revert
with the change folder; promoted `openspec/specs/` are untouched until archive.

## Dependencies

None new. Homebrew's existing `brew info --installed --json=v2` and `brew trust --json v1` reads, both
already shipped. Probe (`explore.md` §8) confirmed brew reports a non-null `tap` for individually
granted, installed packages, so PD8 activates from the receipt alone.

## Size Forecast

~**1,060–1,640** changed lines against the **5,000** budget under the cached `single-pr` strategy —
**budget risk: Low**. The excluded `installedAt` fix would have added ~150–250.

## Success Criteria

- [ ] Opening `Home-Cellar` (or any tap-only package) shows its facts, not "No further details".
- [ ] The pane offers the same verbs as its installed row, from the same unchanged `MutationMenu`.
- [ ] A package with a per-package grant shows `Trusted individually` beside its Tap fact.
- [ ] A package whose receipt withholds `tap` shows **no** Tap fact and **no** marker.
- [ ] The pane offers no trust control and composes no marker copy locally (both asserted as absences).
- [ ] No new brew invocation; catalog search and snapshot are byte-identical in behaviour.
- [ ] `cellar.xcodeproj/project.pbxproj` diff is 0 lines.
