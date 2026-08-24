# Design: A receipt-backed reduced detail pane (`m10-third-party-detail`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec canonical + Engram mirror, project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

`next_recommended: sdd-tasks`

**Inputs.** `proposal.md` (obs `#7783`), `explore.md` (obs `#7781`; §8 probe `#7782`) and the
maintainer's binding scope and presentation decisions (obs `#7780`). Risks **R1 … R7** are carried from
the proposal by name rather than restated. Approach **A** (explore §4/§6) is confirmed; **B**, **C** and
**D** are recorded as rejected below so nobody re-proposes them.

> **Size note.** This document exceeds the 800-word default by explicit launch-brief instruction (a new
> public type with kind asymmetry, view integration across two files, a concurrency statement, a Strict
> TDD RED map, and a budget/pbxproj confirmation). `openspec/config.yaml` `rules.design` additionally
> requires actor-isolation and Sendable statements. It follows the m9 precedent: tables, not prose.

## Technical Approach

Three pieces, ordered by how much they touch:

1. **A pure value in `BrewClient`** — `InstalledDetailProjection`, built by a total `init` over one
   `InstalledPackage`. It owns the ordered facts, absence, and the formula/cask asymmetry. No SwiftUI,
   no process, no store, no clock; `BrewClientTests` reaches every shape.
2. **The pane, in a new extension file** — `cellar/Browse/PackageDetailView+Receipt.swift` replaces the
   body of `uncatalogedContent(for:)`. The shared `header(id:displayName:versionStory:installed:primaryButton:)`
   is kept, so there stays **one identity row across two panes**. `PackageMetadataSection(entry:metadata:)`
   is reused **unchanged** (proposal :33): it already takes a `PackageEntry`, and `PackageEntry(installed:catalog:id:)`
   accepts `catalog: nil`, so the private note reaches this pane with no new type and no new store.
3. **PD8 activation at presentation** — the Tap fact comes from the receipt; the marker is joined beside
   it by the shipped `TapProjection.grantsIndividually(_:publishedBy:in:)`, never carried as a field.

`rules.design` compliance is structural: all new logic is in `Packages/CellarCore/Sources/BrewClient`;
the app target gains view code only, and **no DI line at all** — `ContentView.swift:533-544` already
wires `catalog`, `installed`, `operations`, `metadata`, `diskUsage` and `trustGrants`, and this change
adds no seventh store. No new external dependency and therefore no new protocol boundary: the pane
introduces no `Process`, `FileManager` or network use. No `#available` branch.

The engineering content is not the fact list. It is **DD-2** (asymmetry made unrepresentable rather than
merely unwritten), **DD-4** (how PD8 attaches without a marker field), **DD-9** (the Swift access-control
consequence of moving the pane into a second file, which is the one thing that can silently turn this
change into duplicated helpers) and **DD-5/DD-6** (the two facts deliberately *not* rendered).

## Architecture Decisions

| # | Decision | Rejected alternative | Rationale |
|---|---|---|---|
| **DD-1** | Keep the proposal's name `InstalledDetailProjection`: a `public struct`, `Sendable`, `Hashable`, with one total `public init(_ package: InstalledPackage)` in a new `InstalledDetailProjection.swift` | `InstalledDetailPresentation` returned by a `TapProjection`-style caseless-enum factory; an extension on `InstalledPackage` | "Projection" is the house word for a pure derivation over a decoded record (`TapProjection`, `InstalledDiskUsageProjection`); "Presentation" names the *value a projection returns* (`TapGrantPresentation`, `TapTrustPresentation`). Here the derivation has exactly one input and one output, so a factory plus a second type would be two names for one thing. An extension on `InstalledPackage` was rejected because the fact copy would then be reachable from every consumer of the model, including the Installed list, where it is not wanted |
| **DD-2** | The kind asymmetry is a **sum type**, not optional fields: `public enum KindState { case formula(FormulaState); case cask(CaskState) }`, where `FormulaState` carries link state, other-keg count and pin, and `CaskState` carries only `autoUpdates: Bool?`. `installStateFacts` is a **computed** derivation over `kindState` | A flat struct with `linkedKeg: String?` + `declaresAutoUpdates: Bool?` and a `switch` at build time; two sibling types with no common parent | This is what "enforced at the type level" means: a cask value has **no place to put** a link state and a formula value has no place to put `auto_updates`, so PD1's uniformity rule applied to the receipt (explore §5.5) cannot be broken by a later edit, only by a deliberate type change. Deriving the facts rather than storing them keeps one source of truth, so the structured value a unit test asserts and the copy the pane renders cannot drift |
| **DD-3** | Absence is `Optional` or omission from an array. **No sentinel, ever**: no `""`, no `"unknown"`, no `"—"`. Every fact value is non-empty by construction, and the absence set is enumerable by a test | Rendering an empty row; a `"Not reported"` value string | **R5**, and PD1's absence discipline promoted to the receipt. `InstalledModels.swift:39-47` exists precisely so `tap` absence is not collapsed to a sentinel; a projection that re-collapses it downstream would undo that at the last hop. Absence living in the value type is what makes it testable without SwiftUI |
| **DD-4** | The projection exposes `public let tapOfOrigin: Fact?` as its **own member**, outside the fact groups. The view attaches the marker there, under the same `if let tap = snapshot.tap` guard that produced it. The projection carries **no** marker, no `isTrusted`, no grant state, and takes no `TrustGrantState` parameter | A `marker: String?` field on the Tap fact; passing `TrustGrantState` into the init; finding the Tap fact by matching the label string `"Tap"` | PD8 :309-314 is explicit — "the marker MUST NOT become a field of the detail projection". A dedicated optional member gives the view a **stable, addressable seam** without label matching (which would break the day the copy changes) and without a field. `tap == nil` ⇒ no fact **and** no marker falls out of one guard rather than two that could disagree (PD8's unknown-tap clause, PT3) |
| **DD-5** | **No "Latest version" fact and no separate outdated fact.** The header's existing `versionStory(installed:)` already renders `installed → offered` when outdated and the bare installed version otherwise | Mirroring the catalog pane's `fact("Latest version", …)` from `catalogVersion`; an "Outdated" install-state row | `InstalledDecoder` falls `catalogVersion` back to the primary keg's version (`:77`, `:109`), so on this branch "offered" can silently *equal* "installed". A row labelled "Latest version" would then assert a published-version fact the receipt never made — the same class of false claim that got Approach C rejected. **Reconciled with II15 (orchestrator decision):** the requirement's install-state list is amended in parallel so the shared identity header owns the version story; a second row restating it would be the duplication one-identity-row-two-panes exists to prevent |
| **DD-6** | **No "Installed on" fact**, and its absence is asserted by test rather than merely omitted | Rendering `installedAt`; fixing the decoder inside m10 | `InstalledDecoder.date(_:)` (`:131-133`) collapses a missing timestamp to the epoch, so the fact would print *1 January 1970* (explore §5.2). Out of scope per the proposal; the pinned absence keeps a future contributor from "completing" the grid and shipping the defect |
| **DD-7** | Store-derived facts stay **view-side**: **Size on disk** (`sizeOnDisk(for:)`) and **Installed as** (`installedAs(for:)`) are reused unchanged and appended into the install-state group by the pane. Both are licensed install-state facts of II15's third group, not view inventions | Passing `Int64?` and `Bool` into the projection init; omitting Size on disk because the receipt does not carry it | Keeps the init a **pure function of one receipt record**, which is the property every unit test depends on. `DiskUsageStore` is a live `@Observable` store whose incremental answer changes between renders; folding it into a `Hashable` value would make that value stale by construction — while leaving the fact out would withhold from this pane a measurement the catalog pane already shows for the same `PackageID` |
| **DD-8** | The header's primary-button slot — today `EmptyView()` (`PackageDetailView.swift:377-379`) — is filled with `MutationMenu(center: operations, entry: PackageEntry(installed: snapshot, catalog: nil, id: snapshot.id))`, **byte-unchanged**. No verb is re-implemented and no `MutationCommand` is constructed by the pane | Re-implementing Upgrade/Uninstall as accent buttons; an `accentButton("Upgrade", …)` mirroring `headerPrimaryButton` | `InstalledRow.swift:61` already renders this exact menu for `catalog: nil` entries, so the verbs, the confirmation rule, the argv validation (`PackageTarget(entry.id)` returns `nil` for an option-shaped name) and the unavailable-runner guidance all arrive already proven (PM7, PM9). **R4** — an upgrade of a third-party package tripping brew's interactive trust prompt — is therefore *inherited unchanged from the row it already ships on*: m10 neither creates nor widens it, and must not "fix" it here |
| **DD-9** | The six helpers the second file needs — `header(id:displayName:versionStory:installed:primaryButton:)`, `versionStory(installed:)`, `fact(_:_:mono:note:)`, `sizeOnDisk(for:)`, `installedAs(for:)` and a **new** `factLink(_:_:)` — drop `private` and become internal. `factLink` is extracted from the catalog pane's inline homepage block (`:569-577`) and used by **both** panes | Putting the receipt pane in `PackageDetailView.swift`; duplicating the helpers in the extension; exposing `@Environment private var theme` | Swift `private` is **file-scoped**: an extension in another file cannot call it, so this is a compile-time consequence of the file split, not a style choice. Duplicating helpers is the drift PT5's one-projection rule exists to prevent, and would put a second copy of the grant-marker rendering in the tree. Extracting `factLink` keeps `theme` private and removes an existing duplication instead of adding one. `favoriteButton` and `statusBadge` stay `private` — only `header`'s callers cross the file boundary, not its callees |
| **DD-10** | The projection is **nonisolated by module default** (CellarCore uses SwiftPM nonisolated defaults per `config.yaml` context) — no annotation, exactly like `InstalledPackage`. `Sendable` and `Hashable` **by composition** (`String`, `Int`, `Bool?`, `URL`, arrays and enums thereof); no `@unchecked`, no actor, no `@MainActor`. The view stays `@MainActor` and builds the value **synchronously inside `body`**: no `Task`, no `.task {}`, no `await` in the render path | Building it in `.task {}` into `@State`; an `@Observable` projection store; caching it on `InstalledStore` | The input is already resident and `Sendable`, and the work is a handful of string interpolations — the same idiom as the shipped `versionStory` and `installedAs`. Async here would introduce a frame where the pane is empty for a value that was never absent, plus a cache to invalidate. Nothing crosses a concurrency domain that did not already cross it: `InstalledInventory` is produced off-main by `InstalledDecoder.decode` (`@concurrent`) and hands `Sendable` values to the main actor today |
| **DD-11** | Extend the shipped `PerPackageTrustSources.views()` with `cellar/Browse/PackageDetailView+Receipt.swift` and update its sorted-name anchor by one element (a 2-line edit), rather than adding a private second scanner in the new test file | A separate source scanner owned by m10's own suite; leaving the new file unscanned | `PerPackageTrustCompositionTests.swift:59-75` loops over `sources` asserting **no** surface composes `"Trusted individually"` locally. A new surface outside that list would silently escape the guard (**R3**). Extending the one list keeps a single enumeration of "surfaces that may mention a grant"; the per-name positive assertions are keyed by file name and are unaffected |
| **DD-12** | The existing scoped copy stays, verbatim including its U+2019 apostrophe — *“This installed package is not in Cellar’s core/cask catalog.”* — as a **footer beneath the facts**, no longer as a `ContentUnavailableView` description | Dropping it now that facts exist; rewording it to mention a third-party tap | Maintainer decision (obs `#7780`). A catalog miss has ≥4 causes (explore §5.3), so the sentence is the one honest statement available and **R2** is a byte-identical-copy test, not a review note |

### Rejected approaches (explore §4)

| Approach | Why rejected |
|---|---|
| **B — widen the detail model with `enum DetailSubject`** | In `Catalog` it makes `Catalog` depend on `BrewClient`, contradicting II7's asserted scenario. In `BrewClient` it forces every catalog-only helper (`facts`, `analytics`, `dependencies`, `dependents`, `PackageInspectionSection`, `ReleaseNotesSection`) to grow a `case receipt` returning nothing — the empty-row shape PD1 forbids — across a shipped, fully specified path |
| **C — synthesize a `CatalogPackage` from the receipt** | **Named rejected in the proposal and restated here.** It falsifies PD6's *"Every snapshot record belongs to a covered tap"* the moment such a value can exist near the store — `PackageSearchIndex` stores `[CatalogPackage]` and vends it through `package(_:)` and `package(at:)`, and 15 files across the tree reference the index, so a synthetic record reaching search is one refactor away; it turns PD1's absence rows into **false claims about the catalog** ("no direct dependencies", "no analytics entry"); and `catalog.tap` is a non-optional `String`, so the withheld-tap case needs exactly the sentinel `InstalledModels.swift:39-47` exists to prevent |
| **D — a standalone `InstalledOnlyDetailView`** | Duplicates or re-exports the shared header, splits the single detail entry point in two, and re-passes five stores through a second construction site. Two panes that must keep the same identity row is the drift PT5's one-projection rule exists to prevent |

## Interfaces / Contracts

```swift
// Packages/CellarCore/Sources/BrewClient/InstalledDetailProjection.swift
public struct InstalledDetailProjection: Sendable, Hashable {
    public struct Fact: Sendable, Hashable {
        public enum Style: Sendable, Hashable { case plain, mono, link(URL) }
        public let label: String
        public let value: String      // never empty — absence is omission (DD-3)
        public let style: Style
    }

    /// Formula-only state. A cask value has no place to put any of it (DD-2).
    public struct FormulaState: Sendable, Hashable {
        /// Linkage alone. The version lives on `primaryKegVersion` for **both**
        /// cases, because II15 requires the primary keg to be named whether or
        /// not brew has linked it — an associated value here would lose it in
        /// the `.unlinked` case, which is exactly the multi-keg truncation the
        /// requirement forbids.
        public enum LinkState: Sendable, Hashable { case linked, unlinked }
        /// Two facts, not a double optional: pinned-without-a-version is a state
        /// brew really reports, and `String??` would encode it unreadably.
        public enum Pin: Sendable, Hashable { case notPinned, pinned(version: String?) }
        public let primaryKegVersion: String   // `primaryKeg.version`; never absent
        public let linkState: LinkState
        public let otherKegCount: Int          // 0 for a single-keg formula
        public let pin: Pin
    }

    /// Cask-only state. `autoUpdates` is the receipt's tri-state, verbatim (II2).
    public struct CaskState: Sendable, Hashable { public let autoUpdates: Bool? }

    public enum KindState: Sendable, Hashable { case formula(FormulaState), cask(CaskState) }

    public let description: String?   // `desc`, absence preserved — rendered as its own block
    public let identity: [Fact]       // Type, Homepage
    public let tapOfOrigin: Fact?     // the PD8 seam; nil ⇒ no fact and no marker (DD-4)
    public let kindState: KindState
    public var installStateFacts: [Fact] { /* derived from kindState (DD-2) */ }

    public init(_ package: InstalledPackage)  // total, pure, no I/O
}
```

### Fact inventory

Copy below is **pinned by the spec**, not left to apply.

| Group (order) | Fact | Source | Rendered when / value |
|---|---|---|---|
| — (block) | Description | `desc` | non-nil |
| 1 Identity | Type | `kind` | always |
| 1 Identity | Homepage (link) | `homepage` | non-nil |
| 2 Origin | **Tap** (+ PD8 marker) | `tap` | non-nil |
| 3 Install state | Installed as | view: `installedAs(for:)` | installed (always here) |
| 3 Install state | Size on disk | view: `sizeOnDisk(for:)` | the scan has answered (DD-7) |
| 3 Install state | Version (formula) | `primaryKegVersion` | always — the primary keg, linked or not |
| 3 Install state | Link state (formula) | `linkedKeg` | always: `Linked` / `Not linked` |
| 3 Install state | Other versions (formula) | `kegs.count` | `> 1`: `N other versions installed`, singular `1 other version installed` |
| 3 Install state | Pinned (formula) | `isPinned`, `pinnedVersion` | `isPinned` |
| 3 Install state | Updates (cask) | `declaresAutoUpdates` | `true` ⇒ `Updates itself` (the shipped string, reused); `false` ⇒ `Updated by Homebrew`; `nil` ⇒ **no fact** |
| footer | Scoped catalog-miss copy | constant | always (DD-12) |

`linkedKeg` is read directly rather than through `formulaLinkState`: that projection returns
`.notApplicable` for casks, a runtime guard `KindState` makes unnecessary, and reading it would pull
`DiskUsage` into a type that needs nothing from it. The primary keg's version is carried on
`FormulaState` rather than inside `LinkState`, so an unlinked multi-keg formula still names it
(II15's "primary keg plus a count of the other kegs").

## Data Flow

    brew info --installed --json=v2        brew trust --json v1
            │  (already shipped)                   │  (already shipped)
            ▼                                      ▼
    InstalledDecoder ──► InstalledInventory   TrustGrantStore.grants
            │  Sendable, off-main                  │
            ▼                                      │
    InstalledStore.inventory.package(id)           │
            │  InstalledPackage (resident)         │
            ▼                                      │
    InstalledDetailProjection(snapshot)  ── pure, @MainActor, synchronous
            │ identity / tapOfOrigin / kindState   │
            ▼                                      ▼
    PackageDetailView+Receipt  ──► if let tap = snapshot.tap ──► TapProjection
        header(...) + facts + MutationMenu             grantsIndividually(id, publishedBy: tap, in:)
        + DiskUsageStore/MetadataStore facts                     │ true ⇒ TapProjection.grantMarker
                                                                 ▼ beside `tapOfOrigin`, never a field

## File Changes

| File | Action | Est. lines | Description |
|---|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/InstalledDetailProjection.swift` | Create | 130–180 | The value, the sum type, the derivation |
| `Packages/CellarCore/Tests/BrewClientTests/InstalledDetailProjectionTests.swift` | Create | 240–360 | RED map below. `BrewClientTests` is the right suite for the PD6 and TM5 rows too: `BrewClient` imports `Catalog`, so a real `PackageSearchIndex` and a `TapRecord` handoff are both constructible there without a new test target |
| `Packages/CellarCore/Tests/BrewClientTests/Fakes/InstalledFixture.swift` | Modify | 20–40 | Multi-keg, tri-state, nil-tap, nil-desc fixtures |
| `cellar/Browse/PackageDetailView+Receipt.swift` | Create | 120–170 | The pane body |
| `cellar/Browse/PackageDetailView.swift` | Modify | 30–50 | `uncatalogedContent` body out; six helpers internal; `factLink` extracted (DD-9) |
| `cellarTests/ReceiptDetailCompositionTests.swift` | Create | 90–140 | Composition/source-text absences |
| `cellarTests/PerPackageTrustCompositionTests.swift` | Modify | 2 | One path + the anchor (DD-11) |
| `openspec/changes/.../specs/` | Create | 180–280 | `installed-inventory` ADDED, PD6 MODIFIED, TM5 MODIFIED |
| `cellar.xcodeproj/project.pbxproj` | **Untouched** | **0** | Confirmed: `path = cellar` (`:46`) and `path = cellarTests` (`:51`) are `PBXFileSystemSynchronizedRootGroup`s, so both new app-target files join their targets with a 0-line diff. `Packages/CellarCore` is SwiftPM and has no pbxproj at all |

**Budget.** ~810–1,220 code and spec lines, plus ~350–550 artifact lines → **~1,160–1,770 against 5,000**.
`400-line budget risk: N/A` (project budget is 5,000); **5,000-line budget risk: Low**. Single PR under the
cached `single-pr` strategy. **R7** stands: `sdd-tasks` forecasts artifacts separately.

## Testing Strategy

Strict TDD: every row is RED before its implementation exists. Verification classes are the spec's:
**`unit`** (`swift test --package-path Packages/CellarCore`) and **`unit-app`** — the established class
for a RED-first assertion over the app target's composition, `openspec/specs/app-updates/spec.md:17`,
run by `xcodebuild test … -only-testing:cellarTests`.

| Class | RED test | Asserts |
|---|---|---|
| `unit` | `aReceiptOnlyPackageIsDetailedFromItsSnapshotAlone` | II15 sc1: group order identity → origin → install state; every value equals the snapshot's; the init takes no catalog value and the type references none |
| `unit-app` | `composingTheReducedDetailReachesNoProcessLayer` | II15 sc2: source scan of the projection file and `PackageDetailView+Receipt.swift` finds no brew-process / `Process` / refresh reference, and the composition takes exactly one `InstalledPackage` with no launcher dependency to inject (a fake-launcher test would assert nothing on a pure init) |
| `unit` | `aMultiKegFormulaShowsItsPrimaryKegAndACountOfTheRest` | 3 kegs ⇒ `primaryKegVersion` is `linkedKeg`'s match and `otherKegCount == 2`; the same holds when the formula is **unlinked** (the version is not lost); no auto-updates fact is representable |
| `unit` | `aCaskAutoUpdatesTriStateStaysThreeAnswers` | `true` ⇒ `Updates itself`, `false` ⇒ `Updated by Homebrew`, `nil` ⇒ **absent** — three distinct outcomes (II2) |
| `unit` | `aWithheldTapProducesNoOriginFact` | `tap == nil` ⇒ `tapOfOrigin == nil`; no `""` anywhere in the value |
| `unit` | `absentDescriptionAndHomepageAreOmittedNotEmptied` | `desc`/`homepage` nil ⇒ `description == nil`, no Homepage fact; **every** emitted `Fact.value` is non-empty (absence enumerated) |
| `unit` | `aFormulaReportsBothLinkStates` / `aPinnedFormulaReportsItsPinWithAndWithoutAVersion` | `Linked` / `Not linked` both render; `.pinned(version: nil)` distinguished from `.notPinned` |
| `unit` | `theGroupsKeepTheirOrderAndNoLabelRepeats` | identity → origin → install state; labels unique |
| `unit` | `aReceiptBackedDetailCreatesNoCatalogRecord` | PD6's added scenario: after composing a reduced detail for a third-party-tap package, the catalog snapshot, `PackageSearchIndex` search and `package(_:)` lookup are unchanged and still answer not-found; no `CatalogPackage` exists for it |
| `unit` | `theHandoffLandsOnAReceiptBackedDetail` | TM5's added scenario: **Show in Installed** resolved by exact `PackageID` composes from the snapshot record alone; catalog snapshot, search and lookup unchanged; no additional brew invocation recorded |
| `unit-app` | `theReceiptPaneResolvesTheMarkerThroughTheOneProjection` | `PackageDetailView+Receipt.swift` contains `TapProjection.grantsIndividually(` and `TapProjection.grantMarker`; contains **no** `"Trusted individually"` literal (also enforced by the extended DD-11 loop) |
| `unit-app` | `theReceiptPaneOffersNoTrustControl` | The file contains no `"Trust` string literal and no `TapCommand` (PT7 asserted as an absence) |
| `unit-app` | `theReceiptPaneOffersTheSameVerbsAsTheRow` | Contains `MutationMenu(center:` and `catalog: nil`; constructs no `MutationCommand` itself (DD-8) |
| `unit-app` | `theScopedCatalogMissCopyIsUnchanged` | The exact sentence, U+2019 included, is present; the phrase `third-party` is absent (**R2**) |
| `unit-app` | `theReceiptPaneRendersNoInstallDate` | No `"Installed on"` and no `installedAt` (DD-6) |

**Existing tests that MUST keep passing, unchanged in meaning:**
`PerPackageTrustCompositionTests` (both tests, with only DD-11's 2-line list edit),
`TapProjectionTests`, `TapShippingProofTests`, `MutationCommandTests`, `InstalledDeriveTests`,
`InstalledFilterCompositionTests`, `SecurityCompositionTests`, `HealthCompositionSupport` consumers,
`BrewfileCompositionTests`, `HomeCompositionTests`. Commands: `swift test --package-path
Packages/CellarCore` for the inner loop, then the full `xcodebuild test … -scheme cellar`.

## Threat Matrix

**N/A — no new routing, shell, subprocess, VCS/PR automation, executable-file classification, or
process-integration boundary.** The pane introduces **no brew invocation** (explore §5.6, confirmed,
and now pinned by the `composingTheReducedDetailReachesNoProcessLayer` RED row),
reads only stores that are already wired and already refreshed, and constructs no argv: every verb goes
through the byte-unchanged `MutationMenu`, whose `PackageTarget(entry.id)` validation and confirmation
rules are already proven by `MutationCommandTests` (PM7, PM9, PM10). The one behavioural exposure —
**R4**, brew's interactive trust prompt on upgrading a third-party package — is inherited unchanged from
`InstalledRow`, where the identical menu ships today, and is therefore not a new boundary for this
change to gate.

## Migration / Rollout

No migration required. Nothing persists: no file format, no stored state, no new process. Reverting the
PR deletes two new source files and two new test files and restores `uncatalogedContent`'s
`ContentUnavailableView`; the six visibility relaxations revert with it. Promoted `openspec/specs/` are
untouched until archive.

## Open Questions

- [x] **Closed.** Exact fact copy is pinned by the spec and reproduced in the fact inventory above:
      `Linked` / `Not linked`; `N other versions installed` (singular `1 other version installed`);
      cask `Updates itself` (true, the shipped string reused) / `Updated by Homebrew` (false) / no fact
      (nil). `sdd-apply` reproduces these strings; it does not choose them.
- [ ] Whether `MutationMenu` sits left of the heart (header slot order) or the heart left of it
      (`InstalledRow` order). Presentation-only; no requirement depends on it.
