# Tasks: A receipt-backed reduced detail pane (`m10-third-party-detail`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m10-third-party-detail/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `chain_strategy=pending`, `review_budget_lines=5000`, `strict_tdd=true`.
RDD disabled.

Inputs: the three spec deltas **rev 2, gate-passed** (`specs/{installed-inventory,package-detail,tap-management}/spec.md`
+ `specs/README.md` — **14 new scenarios**: 12 / 1 / 1, of which **9 `unit`** and **5 `unit-app`**),
`design.md` (**DD-1…DD-12**, whose Testing Strategy table is the RED map), `proposal.md`,
`explore.md` (§8 probe). Engram mirrors: spec `#7785`, design `#7784`, proposal `#7783`.

Size note: this artifact exceeds the generic 530-word phase budget, on the house precedent at
`openspec/changes/archive/2026-08-23-m7-tap-trust/tasks.md:16` and `2026-08-24-m9-per-package-trust/tasks.md:15`.
Nothing is padded.

## Scenario map (IDs used by every task below)

**`installed-inventory` II15 — 12 scenarios, all new (7 `unit`, 5 `unit-app`).**
**sc1** detailed from the receipt alone, group order, no catalog value (`unit`) ·
**sc2** composing reaches no process layer (`unit-app`) ·
**sc3** facts do not cross between formula and cask (`unit`) ·
**sc4** cask auto-updates has three distinguishable outcomes (`unit`) ·
**sc5** linked multi-keg formula: `Linked`, primary keg version, `2 other versions installed` (`unit`) ·
**sc6** unlinked formulae still name their primary keg; `1 other version installed` singular; single keg ⇒ no fact (`unit`) ·
**sc7** withheld tap ⇒ no origin fact, no marker (`unit`) ·
**sc8** absent description/homepage absent, never empty (`unit`) ·
**sc9** no install-date fact (`unit-app`) ·
**sc10** marker beside the origin fact, never composed locally (`unit-app`) ·
**sc11** the installed row's verbs, no trust control (`unit-app`) ·
**sc12** footer copy exact, nothing implying a third-party tap (`unit-app`).

**`package-detail` PD6 MODIFIED — +1.** **PD6 sc3** “A receipt-backed detail creates no catalog record”
(`unit`, `specs/package-detail/spec.md:64`). PD6's two shipped scenarios are **byte-identical regression
guards, never RED**.

**`tap-management` TM5 MODIFIED — +1.** **TM5 sc10** “The handoff lands on a receipt-backed detail, not
on a catalog record” (`unit`, `specs/tap-management/spec.md:143`). TM5's nine shipped scenarios are
**byte-identical regression guards, never RED**.

**`package-trust` — no delta.** PD8, PT3, PT5, PT6, PT7 are **activated** by this surface and asserted
here (sc7, sc10, sc11), not amended.

**New RED work: 14 scenarios** (9 `unit` + 5 `unit-app`). **11 shipped scenarios are regression guards.**
**No `manual-evidence` scenario exists in this change** — the §8 probe already cleared the only
measurement it needed, so `sdd-verify` MUST NOT wait for a manual harness.

## Pinned copy — apply reproduces these bytes, it does not choose them

| Fact | Exact copy | Condition |
|---|---|---|
| Formula link state | `Linked` / `Not linked` | both states, always |
| Formula other kegs | `N other versions installed`; `1 other version installed` singular | `kegs.count > 1`; **no fact** for a single keg |
| Cask auto-updates | `Updates itself` (shipped, `PackageDetailView.swift:579`) / `Updated by Homebrew` | declared `true` / declared `false`; **no fact** when undeclared |
| Grant marker | `Trusted individually` | granted by exact identity; **from the `package-trust` projection only** |
| Footer | `This installed package is not in Cellar’s core/cask catalog.` | always — **U+2019**, byte-identical to `PackageDetailView.swift:384` |

No “latest”, “current” or “published” version fact exists on this surface (**DD-5**); no install-date
fact exists (**DD-6**).

## Review Workload Forecast

| Field | Value |
|---|---|
| Bottom-up **code + tests** | **632–942** (core code 130–180 · core tests 240–360 · fixtures 20–40 · app view 120–170 · `PackageDetailView.swift` 30–50 · app tests 90–140 · DD-11 edit 2) |
| House correction | **1.9–2.3×**, applied to the code+test bucket **only** (632–942 → **1,201–2,167**) |
| **SDD artifacts, forecast separately, NO code-derived correction** (m7 learning E / m9 R8) | **counted, not estimated**: the deltas are already on disk at **610** lines (258 + 90 + 177 + 85), `design.md` **234**, `proposal.md` **126**, `explore.md` **286**, this file **~270**; `verify-report.md` adds **~250–450** at verify time |
| Estimated changed lines (PR total) | **~1,710–4,130** authored — the band's width is the artifact bucket (task 0.4 collapses it) |
| Governing budget | **5,000** (`config.yaml:8` and the session preflight agree) |
| Risk vs governing budget | **Low** — 34 % at the low end, **83 %** at the high end. The ceiling is not straddled at either end |
| Chained PRs recommended | **No** — one PR, five work units, delivered as work-unit commits |
| Suggested split | **Single PR** (`single-pr`, honoured as cached). If task 8.6 measures >5,000, that is information for the next forecast, not a mid-flight re-plan |
| Delivery strategy | single-pr |
| Chain strategy | pending — **no chain decision is required**; `pending` is the guard's literal value for "no chain in play" (house precedent: m6-cask-tap, m7-tap-trust, m8-bundle-rename) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

`400-line budget risk` is the literal guard value against the 400 **default**, which does not govern this
repository. The governing 5,000-line judgement is the **Low** row above, so `sdd-apply` starts without a
`size:exception` and without a chain decision.

**Branch**: `feat/m10-third-party-detail`
(`^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)/[a-z0-9._-]+$` ✓).
**PR title**: `feat(installed): detail a package the catalog does not carry from its receipt`.

### Suggested Work Units (`work-unit-commits`; conventional commits, **no `Co-Authored-By`, no AI attribution**)

RED and GREEN may be separate commits inside a unit (house precedent); tests never leave the unit whose
behaviour they verify.

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| **WU1** | The three deltas land **first** — PD6 and TM5 are narrowed before any line of code (**R1**) | PR 1 | N/A — artifacts only, no code | N/A — no behaviour changes | Revert the single artifact commit; the tree returns to `main` |
| **WU2** | **DD-9 visibility relaxation + `factLink` extraction** in `PackageDetailView.swift` — a **pure refactor, no new behaviour** | PR 1 | `xcodebuild test … -only-testing:cellarTests` (nothing may change) | `xcodebuild build …` must compile | Revert one commit; six `private` keywords return and `factLink` re-inlines |
| **WU3** | `InstalledDetailProjection.swift` + its `unit` suite + fixtures — II15 sc1, sc3–sc8 | PR 1 | `swift test --package-path Packages/CellarCore --filter 'InstalledDetailProjectionTests'` | N/A — a pure, total `init` over one resident record; there is no runtime to exercise | Delete the new source + test files and the fixture additions; nothing references them yet |
| **WU4** | PD6 sc3 and TM5 sc10 in `BrewClientTests` — the catalog stays untouched | PR 1 | `swift test --package-path Packages/CellarCore --filter 'InstalledDetailProjectionTests'` | N/A — `BrewClient` imports `Catalog`, so a real `PackageSearchIndex` is constructible in-suite | Delete the two test cases; no production line is theirs |
| **WU5** | `PackageDetailView+Receipt.swift` + `ReceiptDetailCompositionTests.swift` + the DD-11 2-line edit — II15 sc2, sc9–sc12 | PR 1 | `xcodebuild test … -only-testing:cellarTests` | **Launch the app**, open an installed package the catalog does not carry, confirm facts, marker, verbs and footer | Delete the new view + test files and revert the DD-11 anchor; `uncatalogedContent`'s `ContentUnavailableView` returns with WU2 |

**Parallel vs sequential.**

- **Sequential, hard dependencies**: **WU1 → everything** (R1 — the m9 archive reads PD6 as a blanket ban
  in three places; no code may land before the narrowing). **WU2 → WU5** (**DD-9**: Swift `private` is
  file-scoped, so the extension cannot compile until the six helpers are internal — this is the one
  ordering mistake that silently becomes duplicated helpers). **WU3 → WU5** (the pane renders the value).
- **Parallelisable in principle**: **WU2 ∥ WU3** (disjoint files: `PackageDetailView.swift` vs
  `Packages/CellarCore/…`), **WU4 ∥ WU3's GREEN** once the projection type exists. **One writer,
  executed sequentially** — no parallel worktrees, no parallel branches.
- **Inside every unit**: RED before GREEN, `strict_tdd: true`. Never negotiable.
- **Rollback order** is the reverse — WU5 → WU4 → WU3 → WU2 → WU1.
- **Bottleneck**: **WU5** — it is the only unit whose tests need two runners, the only one touching the
  shipped `PerPackageTrustCompositionTests`, and it depends on both WU2 and WU3. It is the unit most
  likely to need a second session.

## Phase 0: Preflight (sequential; no behaviour changes)

- [x] 0.1 Measure and record the green baseline; do not re-derive it later and do not assume the m9
      numbers still hold. Run `swift test --package-path Packages/CellarCore` and
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
      Count **distinct** passing test ids; `Executed 0 tests` is meaningless for Swift Testing bundles.
- [x] 0.2 Confirm every anchor the design pins is still where it says — a moved anchor is a deviation to
      **report, not absorb**: `PackageDetailView.swift` :370-390 (`uncatalogedContent`, incl. the
      `EmptyView()` slot at :377-379 and the footer sentence at :384) · :396-402 (`header(id:…)`) ·
      :463 (`versionStory(installed:)`) · :569-577 (the inline homepage block `factLink` is extracted
      from) · :578-579 (`Updates itself`) · :586-591 (`fact(_:_:mono:note:)`) · :629 (`sizeOnDisk`) ·
      :640 (`installedAs`) · `PerPackageTrustCompositionTests.swift` :31-32 (the sorted-name anchor) and
      :186-190 (`PerPackageTrustSources.views()`) · `InstalledModels.swift` :29-97 (`InstalledPackage`
      members: `desc`, `homepage`, `tap`, `kegs`, `primaryKeg`, `linkedKeg`, `isPinned`, `pinnedVersion`,
      `declaresAutoUpdates`) · `InstalledFixture.swift` :79-103 (`package(…)`).
- [x] 0.3 `git checkout -b feat/m10-third-party-detail main`.
- [x] 0.4 **Collapse the forecast band.** `git log --oneline -- openspec/changes/m10-third-party-detail`
      and `git status --short openspec/changes/m10-third-party-detail`: record whether the 1,256 artifact
      lines already sit on `main` (⇒ only `tasks.md` + `verify-report.md` land in this PR, ~1,710 total)
      or are new to this branch (⇒ ~4,130). Record the answer; do not re-estimate it at task 8.6.

## Phase 1: WU1 — the deltas land first (R1)

- [x] 1.1 Commit the SDD artifacts, **PD6's and TM5's MODIFIED blocks included**, before any Swift file
      changes: `docs(sdd): record the m10-third-party-detail proposal, spec deltas, design and tasks`.
      **Acceptance**: `specs/package-detail/spec.md` binds PD6's prohibition to the **catalog
      projection**, and `specs/tap-management/spec.md` binds TM5's to a **catalog record + tap-source
      read**, so a receipt-only rendering neither satisfies nor violates either.
- [x] 1.2 Confirm the delta arithmetic before moving on: `installed-inventory` **1 ADDED / 12 scenarios**
      → 15 req / 79 sc; `package-detail` **1 MODIFIED, 3 scenarios replacing 2** → 8 req / 31 sc;
      `tap-management` **1 MODIFIED, 10 scenarios replacing 9** → 13 req / 58 sc. A mismatch is a spec
      defect to report, not to patch here.
- [x] 1.3 Record the **m9 provenance correction** in the apply context (`specs/README.md:62-75`): the
      “no third-party detail fallback” clause is **TM5**'s, not TM1's, despite three m9 citations. TM1's
      genuine constraint — **no additional brew invocation to complete a detail** — is honoured and
      asserted by II15 sc2 and TM5 sc10.

## Phase 2: WU2 — DD-9 visibility and the `factLink` extraction (pure refactor; no RED)

Runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`

> **No RED task here by design.** This unit adds **no behaviour**: `strict_tdd` sequences RED before
> GREEN for behavioural tasks, and a visibility relaxation is neither. Its guard is that **every existing
> test stays green and the catalog pane renders byte-identically**.

- [x] 2.1 In `cellar/Browse/PackageDetailView.swift`, drop `private` from exactly these five helpers,
      making them **internal**: `header(id:displayName:versionStory:installed:primaryButton:)`,
      `versionStory(installed:)`, `fact(_:_:mono:note:)`, `sizeOnDisk(for:)`, `installedAs(for:)`.
      **`favoriteButton`, `statusBadge`, `factLabel`, `headerPrimaryButton`, `facts(for:)` and
      `header(for:)` stay `private`** — only `header`'s callers cross the file boundary, not its callees.
- [x] 2.2 Extract a **new internal** `factLink(_ label: String, _ url: URL)` from the inline homepage
      block at `:569-577` and call it from `facts(for:)` in place of that block. `@Environment private
      var theme` stays **private** — `factLink` is what keeps it so.
- [x] 2.3 **Binding, asserted not assumed.** `git diff main -- cellar/Browse/PackageDetailView.swift`
      shows **only** six visibility keywords removed, the `factLink` extraction, and the homepage block
      replaced by its call. **No copy string changes.** The catalog pane's rendered facts are unchanged.
- [x] 2.4 **Forbidden, stated so no later task does it**: do **not** duplicate any of the six helpers in
      the WU5 extension file. A second copy is the PT5 drift the one-projection rule exists to prevent,
      and would place a second grant-marker renderer in the tree (**DD-9**).
- [x] 2.5 Runner green at the Phase 0 baseline, `xcodebuild build …` compiles; commit WU2
      (`refactor(browse): share the detail header helpers across both panes`).

## Phase 3: WU3 — the projection (II15 sc1, sc3–sc8)

Runner: `swift test --package-path Packages/CellarCore --filter 'InstalledDetailProjectionTests'`

- [x] 3.1 **Test support (not a behaviour).** Extend
      `Packages/CellarCore/Tests/BrewClientTests/Fakes/InstalledFixture.swift` with the shapes the RED
      rows need: multi-keg (3 kegs, one linked), **unlinked** multi-keg (2 kegs, `linkedKeg: nil`),
      single-keg unlinked, `declaresAutoUpdates` `true` / `false` / `nil`, `tap: nil`, `desc: nil` +
      `homepage: nil`, and `isPinned` with `pinnedVersion` present **and** absent. Shipped fixture
      signatures stay source-compatible for their existing callers.
- [x] 3.2 **RED.** New file `Packages/CellarCore/Tests/BrewClientTests/InstalledDetailProjectionTests.swift` ·
      `aReceiptOnlyPackageIsDetailedFromItsSnapshotAlone`: a formula from `acme/tools` with desc,
      homepage and one keg ⇒ facts appear in group order **identity → origin → install state**, every
      value equals the snapshot's, and the type references no catalog value. **RED because**
      `InstalledDetailProjection` does not exist. *(II15 sc1)*
- [x] 3.3 **RED.** `theGroupsKeepTheirOrderAndNoLabelRepeats`: the three groups keep their order across
      both kinds and no label appears twice. *(II15 sc1)*
- [x] 3.4 **RED.** `factsDoNotCrossBetweenFormulaAndCask`: enumerating every fact of a formula and of a
      cask, the formula exposes **no** auto-updates declaration and the cask exposes **no** keg count, no
      primary-keg version, no linked-keg state and no link state — unrepresentable via `KindState`
      (**DD-2**), not merely unwritten. *(II15 sc3)*
- [x] 3.5 **RED.** `aCaskAutoUpdatesTriStateStaysThreeAnswers`: `true` ⇒ exactly `Updates itself`,
      `false` ⇒ exactly `Updated by Homebrew`, `nil` ⇒ **no fact at all**; the three outcomes are
      pairwise distinguishable, so “not declared” is never “declared false”. *(II15 sc4, II2)*
- [x] 3.6 **RED.** `aMultiKegFormulaShowsItsPrimaryKegAndACountOfTheRest`: 3 kegs, one linked ⇒ exactly
      `Linked`, the primary keg's version named, and exactly `2 other versions installed`; nothing
      truncates or drops the other kegs. *(II15 sc5)*
- [x] 3.7 **RED.** `anUnlinkedFormulaStillNamesItsPrimaryKeg`: 2 kegs with **no** linked keg ⇒ exactly
      `Not linked`, the primary keg's version **still named**, and exactly `1 other version installed`
      **in the singular**; a second unlinked single-keg formula exposes **no** other-versions fact.
      **RED because** carrying the version inside `LinkState` would lose it when unlinked. *(II15 sc6)*
- [x] 3.8 **RED.** `aFormulaReportsBothLinkStates` and
      `aPinnedFormulaReportsItsPinWithAndWithoutAVersion`: both link states render; `.pinned(version:
      nil)` is distinguishable from `.pinned(version: "1.2.3")` and from `.notPinned`. *(II15 sc6,
      install-state group)*
- [x] 3.9 **RED.** `aWithheldTapProducesNoOriginFact`: `tap == nil` ⇒ `tapOfOrigin == nil`, no origin
      fact, no placeholder, no explanatory note — and, per PT3, no marker is derivable downstream.
      *(II15 sc7, PD8, PT3)*
- [x] 3.10 **RED.** `absentDescriptionAndHomepageAreOmittedNotEmptied`: `desc`/`homepage` nil ⇒
      `description == nil` and no Homepage fact; **every** emitted `Fact.value` across every fixture is
      non-empty and is never `""`, `unknown` or a dash. The absence set is enumerated, not sampled.
      *(II15 sc8, DD-3)*
- [x] 3.11 **Prove RED.** Run the focused command; 3.2–3.10 MUST fail, each for its stated reason. A
      green test here is a defect in the test.
- [x] 3.12 **GREEN.** New file `Packages/CellarCore/Sources/BrewClient/InstalledDetailProjection.swift` —
      `public struct InstalledDetailProjection: Sendable, Hashable` with `Fact` (`label`, non-empty
      `value`, `Style.plain|.mono|.link(URL)`), `FormulaState` (`primaryKegVersion`, `LinkState`,
      `otherKegCount`, `Pin`), `CaskState(autoUpdates: Bool?)`, `enum KindState`, `description: String?`,
      `identity: [Fact]`, `tapOfOrigin: Fact?`, and a **computed** `installStateFacts` derived from
      `kindState`. One total `public init(_ package: InstalledPackage)`.
- [x] 3.13 **GREEN, binding constraints** (each already asserted above, restated so no shortcut is
      taken): **no** `Latest version`/`Outdated` fact (**DD-5**); **no** install-date fact (**DD-6**);
      **no** display name and **no** version story (the shared header owns both); read `linkedKeg`
      **directly**, never `formulaLinkState` (its `.notApplicable` is a runtime guard `KindState` makes
      unnecessary and it would pull `DiskUsage` in); **nonisolated by module default**, no annotation,
      no `@unchecked`, no actor (**DD-10**); no `Process`, `FileManager`, store, clock or SwiftUI import.
- [x] 3.14 Focused command green; commit WU3
      (`feat(installed): derive a reduced detail from one installed receipt`).

## Phase 4: WU4 — the catalog stays untouched (PD6 sc3, TM5 sc10)

Runner: `swift test --package-path Packages/CellarCore --filter 'InstalledDetailProjectionTests'`

- [x] 4.1 **RED.** `InstalledDetailProjectionTests · aReceiptBackedDetailCreatesNoCatalogRecord`: with a
      real `PackageSearchIndex` over a snapshot that does not carry the package, composing a reduced
      detail leaves the catalog snapshot, `search` and `package(_:)` **unchanged and still answering
      not-found**, and **no `CatalogPackage` exists** for that id anywhere. **RED because** the
      projection does not exist yet at authoring time; it stays meaningful afterwards as the ban on
      Approach C. *(PD6 sc3)*
- [x] 4.2 **RED.** `InstalledDetailProjectionTests · theHandoffLandsOnAReceiptBackedDetail`: **Show in
      Installed** resolved by **exact `PackageID`** composes from the snapshot record alone; the catalog
      snapshot, search and lookup are unchanged; **no additional brew invocation is recorded** (a fake
      launcher records zero) and **no tap-source read** occurs. *(TM5 sc10, TM1's genuine constraint)*
- [x] 4.3 **Prove RED**, then **GREEN** — GREEN here requires **no production line**: both scenarios are
      absences that the WU3 shape already satisfies. If either needs a production change, that is a
      design deviation to report, not to absorb.
- [x] 4.4 Focused command green **and** every shipped `CatalogTests` / `InstalledDeriveTests` case still
      green; commit WU4 (`test(installed): pin that a receipt-backed detail never touches the catalog`).

## Phase 5: WU5 — the pane and the composition guards (II15 sc2, sc9–sc12)

Runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`

> `cellar/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup`s (`project.pbxproj` :46, :51),
> so both new files join their targets with a **0-line `project.pbxproj` diff**.

- [x] 5.1 **RED.** New file `cellarTests/ReceiptDetailCompositionTests.swift` ·
      `composingTheReducedDetailReachesNoProcessLayer`: scanning `InstalledDetailProjection.swift` **and**
      `PackageDetailView+Receipt.swift` finds no brew-process reference, no `Process`, and no store
      refresh triggered by presenting the detail; the composition takes **exactly one**
      `InstalledPackage`, with no launcher dependency to inject. **RED because** the view file does not
      exist. *(II15 sc2)*
- [x] 5.2 **RED.** `ReceiptDetailCompositionTests · theReceiptPaneResolvesTheMarkerThroughTheOneProjection`:
      the pane contains `TapProjection.grantsIndividually(` and `TapProjection.grantMarker`, and contains
      **no** `"Trusted individually"` literal of its own. *(II15 sc10, PD8, PT5)*
- [x] 5.3 **RED.** `ReceiptDetailCompositionTests · theReceiptPaneOffersNoTrustControl`: the pane contains
      no `"Trust` string literal and no `TapCommand`; nothing on it grants, revokes or alters a tap trust
      or a per-package grant, and no copy states or implies untrusted, unverified, unsigned or
      unnotarized. *(II15 sc11, PT6, PT7 asserted as an absence)*
- [x] 5.4 **RED.** `ReceiptDetailCompositionTests · theReceiptPaneOffersTheSameVerbsAsTheRow`: the pane
      contains `MutationMenu(center:` with `catalog: nil` and constructs **no** `MutationCommand` of its
      own — the verbs arrive from the same shared surface `InstalledRow.swift:61` uses. *(II15 sc11,
      DD-8)*
- [x] 5.5 **RED.** `ReceiptDetailCompositionTests · theScopedCatalogMissCopyIsUnchanged`: the exact
      sentence `This installed package is not in Cellar’s core/cask catalog.` is present **with its
      U+2019 apostrophe**, compared byte-for-byte against `PackageDetailView.swift:384`; the phrase
      `third-party` is **absent** from the pane. *(II15 sc12, R2, DD-12)*
- [x] 5.6 **RED.** `ReceiptDetailCompositionTests · theReceiptPaneRendersNoInstallDate`: neither the pane
      nor the projection contains `"Installed on"` or `installedAt`, and no exposed value derives from the
      Unix epoch. *(II15 sc9, DD-6)*
- [x] 5.7 **RED — DD-11, the one edit to a shipped guard.** `cellarTests/PerPackageTrustCompositionTests.swift`:
      add `"cellar/Browse/PackageDetailView+Receipt.swift"` to `PerPackageTrustSources.views()` (:186-190)
      and extend the sorted-name anchor (:31-32) to
      `["PackageDetailView+Receipt.swift", "PackageDetailView.swift", "TapDetailView.swift", "TapsListView.swift"]`
      — `+` (U+002B) sorts **before** `.` (U+002E), so the new name comes **first**. **Exactly 2 lines.**
      Do **not** add a private second scanner in the new test file. *(R3)*
- [x] 5.8 **Prove RED** (5.1–5.7 all fail, each for its stated reason), then **GREEN**: new file
      `cellar/Browse/PackageDetailView+Receipt.swift` — an extension on `PackageDetailView` replacing the
      body of `uncatalogedContent(for:)`. It calls the **WU2 internal** helpers; it duplicates none.
- [x] 5.9 **GREEN, composition** (order is the spec's, copy is the pinned table's): the shared
      `header(id:displayName:versionStory:installed:primaryButton:)` with its `EmptyView()` slot filled by
      `MutationMenu(center: operations, entry: PackageEntry(installed: snapshot, catalog: nil, id: snapshot.id))`
      · the description block · `identity` facts (`factLink` for Homepage) · `tapOfOrigin` with the marker
      joined **beside** it under the same `if let tap = snapshot.tap` guard, via
      `TapProjection.grantsIndividually(_:publishedBy:in:)` · `installStateFacts` **plus** the view-side
      `installedAs(for:)` and `sizeOnDisk(for:)` (**DD-7**) · `PackageMetadataSection(entry:metadata:)`
      **unchanged** · the footer copy. Built **synchronously in `body`**: no `Task`, no `.task {}`, no
      `await` (**DD-10**). **No new DI line** — `ContentView.swift:533-544` already wires all six stores.
- [x] 5.10 **GREEN.** `PackageDetailView.swift` — remove the `ContentUnavailableView` body of
      `uncatalogedContent(for:)` now that the extension supplies it. Nothing else in that file changes
      beyond WU2's refactor.
- [x] 5.11 Runner green — the Phase 0 baseline **plus** the six new cases, and
      `PerPackageTrustCompositionTests` **both** tests still green with only the 2-line edit. Commit WU5
      (`feat(browse): show a receipt-backed detail for packages the catalog does not carry`).

## Phase 6: Verification and bindings

- [x] 6.1 Full core suite: `swift test --package-path Packages/CellarCore` → the Phase 0 baseline **plus**
      every new case, **0 failures**. Assert counts, never a bare success line.
- [x] 6.2 Full app target:
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      → baseline plus the new composition cases, 0 failures. `cellarUITests` gains **no** new test — this
      change adds no new UI-test-flagged store.
- [x] 6.3 **Bindings proof.**
      `git diff --stat main -- cellar.xcodeproj/project.pbxproj scripts/ .github/workflows/ Packages/CellarCore/Sources/BrewClient/MutationCommand.swift Packages/CellarCore/Sources/BrewClient/TapCommand.swift Packages/CellarCore/Sources/BrewClient/InstalledDecoder.swift Packages/CellarCore/Sources/BrewClient/InstalledModels.swift`
      → **empty output**. A non-zero `project.pbxproj` diff means the file-system-synchronized group
      assumption broke; a non-zero `InstalledDecoder.swift` diff means someone “fixed” the epoch defect
      DD-6 defers. Either is reported before merge, never absorbed.
- [x] 6.4 **Regression guards that must never have moved**: `PerPackageTrustCompositionTests` (both
      tests, 2-line edit only), `TapProjectionTests`, `TapShippingProofTests`, `MutationCommandTests`,
      `InstalledDeriveTests`, `InstalledFilterCompositionTests`, `SecurityCompositionTests`,
      `HealthCompositionSupport` consumers, `BrewfileCompositionTests`, `HomeCompositionTests`.
- [x] 6.5 **Spec-delta self-check before verify**: re-count the three deltas against task 1.2's numbers;
      confirm PD6's two and TM5's nine shipped scenarios are **byte-identical** to
      `openspec/specs/{package-detail,tap-management}/spec.md`
      (`git diff --no-index` on the extracted blocks); confirm every one of the **14** new scenarios has
      a task above naming it, and that **no** delta introduces a new verification class.
- [x] 6.6 `git diff --stat main` for the whole branch — record the authored total **split into the
      code+test bucket and the artifact bucket**, and compare each against its own forecast (1,201–2,167
      and the band task 0.4 fixed). A large miss is information for the next forecast, not a failure.
- [ ] 6.7 **Delivery — one PR** (`single-pr`, forecast Low against 5,000; no `size:exception`, no chain).
      The body states up front: (a) the pane **adds no brew invocation and no store** — it composes data
      already resident; (b) it **grants and revokes nothing** — the marker is display-only, from the one
      `package-trust` projection; (c) it makes **no claim about a third-party tap** — the footer stays a
      statement about Cellar's catalog; and (d) **R4** (brew's interactive trust prompt on upgrading a
      third-party package) is **inherited unchanged** from `InstalledRow`, neither created nor widened
      here.

## Phase 7: Archive obligations (recorded now so they are not re-derived at `sdd-archive`)

- [x] 7.1 Promote the ADDED block as **II15**, appended after `installed-inventory`'s current last
      requirement (→ 15 req / 79 sc; II1–II14 byte-identical). Promote PD6 and TM5 as **whole-block
      replacements** (→ 8 req / 31 sc and 13 req / 58 sc). **Promote no verification-class table** —
      none of the three main specs carries one (precedent recorded at
      `openspec/specs/installed-inventory/spec.md:948`); only the inline `- Verification:` lines promote.
- [x] 7.2 Record in provenance: **no `package-trust` delta** — PD8/PT3/PT5/PT6/PT7 were **activated, not
      amended**; and the **TM1→TM5 provenance correction** (m9 cited TM1 in ≥3 places for a clause that
      is TM5's).
- [x] 7.3 Record the deferrals, so a future contributor does not “complete the grid”: the **install-date
      fact** is blocked on an `InstalledDecoder` epoch-collapse fix (a follow-up delta against
      `installed-inventory`, **not** a rendering choice); **no “latest version” fact** may be added while
      `catalogVersion` falls back to the installed keg's version (**DD-5**); receipt-backed **release
      notes** stay in `release-notes` D4 territory; **Approach C** (synthesizing a `CatalogPackage`)
      is now explicitly forbidden by PD6's modified text.
- [x] 7.4 Record the presentation question the design left open — whether `MutationMenu` sits left of the
      heart or the heart left of it — as **closed by whatever apply shipped**, with the choice named. No
      requirement depends on it.
