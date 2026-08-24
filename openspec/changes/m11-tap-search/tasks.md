# Tasks: Tap package search and install from Browse (`m11-tap-search`)

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m11-tap-search/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `chain_strategy=pending`, `review_budget_lines=5000`, `strict_tdd=true`.
RDD disabled.

Inputs: the four spec deltas **rev 2, gate-passed**
(`specs/{package-search,package-detail,tap-management}/spec.md` + `specs/README.md` — **19 new
scenarios**: 16 / 1 / 2, of which **15 `unit`** and **4 `unit-app`**), `design.md` (**DD-1…DD-13**,
whose Testing Strategy table is the RED map), `proposal.md`, `explore.md`. Engram mirrors: spec
`#7798`, design `#7797`, proposal `#7796`, decisions `#7795`.

Size note: this artifact exceeds the generic 530-word phase budget, on the house precedent at
`openspec/changes/archive/2026-08-23-m7-tap-trust/tasks.md:16`,
`2026-08-24-m9-per-package-trust/tasks.md:15` and `2026-08-24-m10-third-party-detail/tasks.md:13`.
Nothing is padded.

## Scenario map (IDs used by every task below)

**`package-search` PS8 ADDED — 16 scenarios, all new (12 `unit`, 4 `unit-app`).**
**ps1** a tap package the catalog does not carry is found by a non-empty query (`unit`) ·
**ps2** the ladder is token-aware over the shared normalisation (`unit`) ·
**ps3** the composed order is total and reproducible (`unit`) ·
**ps4** a hit carries its five facts and its copy, and nothing else (`unit`) ·
**ps5** the kind filter restricts the composed source (`unit`) ·
**ps6** an empty query composes no tap source (`unit`) ·
**ps7** an unavailable tap inventory is an absence, not an error (`unit`) ·
**ps8** a catalog collision is reported on the hit and never suppressed (`unit`) ·
**ps9** the three install states stay distinct and carry their exact copy (`unit`) ·
**ps10** an installed hit with an ambiguous identity is not routable (`unit`) ·
**ps11** installed-state controls compose above the tap source (`unit`) ·
**ps12** the keystroke latency ceiling is not regressed (`unit`) ·
**ps13** the tap section is titled, positioned last, and inert when not installed (`unit-app`) ·
**ps14** an installed tap hit opens the receipt-backed detail (`unit-app`) ·
**ps15** the tap search surface composes no trust gate and no local copy (`unit-app`) ·
**ps16** composing the tap source reaches no process layer (`unit-app`).

**`package-detail` PD6 MODIFIED — +1.** **PD6 sc4** “A composed tap section leaves catalog search
unchanged” (`unit`, `specs/package-detail/spec.md:93`). PD6's three shipped scenarios are
**byte-identical regression guards, never RED**.

**`tap-management` TM5 MODIFIED — +1.** **TM5 sc11** “The inventory feeds an outside search surface
without entering the catalog” (`unit`, `specs/tap-management/spec.md:190`). TM5's ten shipped
scenarios are **byte-identical regression guards, never RED**.

**`tap-management` TM11 MODIFIED — +1.** **TM11 sc3** “A tap package found on another surface adds no
action here” (`unit`, `specs/tap-management/spec.md:242`). TM11's two shipped scenarios — including the
enumerated-actions one — are **byte-identical regression guards, never RED**.

**`package-mutation` (PM10), `installed-inventory` (II7/II8/II15), `tap-management` TM12 — no delta.**
**Activated**, not amended, and asserted here (ps8, ps13–ps16), never restated.

**New RED work: 19 scenarios** (15 `unit` + 4 `unit-app`). **15 shipped scenarios are regression
guards.** **No `manual-evidence` scenario exists in this change** — every claim, latency included, is
answered by a runner, so `sdd-verify` MUST NOT wait for a manual harness.

**RED-map reconciliation (the design's open obligation, discharged here).** Every delivered scenario
was matched against `design.md`'s Testing Strategy table, scenario by scenario. **One gap: ps4** (the
five-facts enumeration) has **no row** in that table — task 2.5 supplies it. Two design rows —
`theLadderConvergesWithTheCatalogIndexOnOneFixture` and `aTapNameQueryMatchesThroughThePublishedName` —
assert requirement prose that no delivered scenario isolates; both are kept (tasks 2.2, 2.3) as extra
coverage, not dropped. The delivered blocks do number the added requirement **PS8** and do target
**TM5 + TM11** (the main spec's markers), as the design asked `sdd-tasks` to confirm.

## Pinned copy — apply reproduces these bytes, it does not choose them

| Fact | Exact copy | Where it lives |
|---|---|---|
| Section title | `From your taps` | the **view** (`TapSearchSection.swift`) — the surface's own |
| Catalog collision note | `Also in the catalog. Homebrew installs the catalog package.` | the **projection** only |
| Install state — installed | `Installed.` | the **projection** only — **new copy**, not a shipped string |
| Install state — tap withheld | `Installed. Homebrew withholds its tap while this tap is untrusted.` | the **projection** only — TM5's exact shipped string |
| Install state — not installed | `Not installed.` | the **projection** only — TM5's exact shipped string |

The four projection strings MUST NOT appear in `TapSearchSection.swift`; the title MUST appear there
byte-exact (ps13, ps15). `TapPackage.statusExplanation` is **refused with evidence** (DD-9): it returns
`nil` for `.installed` (`TapProjection.swift:52-58`), which would leave an installed row silent.

## Review Workload Forecast

| Field | Value |
|---|---|
| Bottom-up **code + tests** | **794–1,134** (core code 150–210 · core tests 340–480 · app view 110–160 · `BrowseView.swift` 40–70 · `ContentView.swift` 1 · app tests 150–210 · DD-11a edit 3) |
| House correction | **1.9–2.3×**, applied to the code+test bucket **only** (794–1,134 → **1,509–2,608**) |
| **SDD artifacts, forecast separately, NO code-derived correction** (m7 learning E / m9 R8 / m10) | **counted, not estimated**: the deltas are already on disk at **839** lines (328 + 121 + 270 + 120), `design.md` **307**, `proposal.md` **154**, `explore.md` **572** — **1,872 total**; this file adds **~300**; `verify-report.md` adds **~250–450** at verify time |
| Estimated changed lines (PR total) | **~2,259–5,230** authored — the band's width is the artifact bucket (task 0.4 collapses it) |
| Governing budget | **5,000** (`config.yaml:8` and the session preflight agree) |
| Risk vs governing budget | **Medium** — 45 % at the low end; the ceiling is straddled **only** in the one corner where the 1,872 artifact lines are new to the branch **and** the code bucket runs to the top of its band (5,230, a 4.6 % overrun). Task 0.4 resolves that corner **before any code lands** |
| Chained PRs recommended | **No** — one PR, four work units, delivered as work-unit commits |
| Suggested split | **Single PR** (`single-pr`, honoured as cached). If task 6.6 measures >5,000, that is information for the next forecast, not a mid-flight re-plan |
| Delivery strategy | single-pr |
| Chain strategy | pending — **no chain decision is required**; `pending` is the guard's literal value for "no chain in play" (house precedent: m6-cask-tap, m7-tap-trust, m8-bundle-rename, m10-third-party-detail) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

`400-line budget risk` is the literal guard value against the 400 **default**, which does not govern
this repository. The governing 5,000-line judgement is the **Medium** row above, so `sdd-apply` starts
without a `size:exception` and without a chain decision.

**Branch**: `feat/m11-tap-search`
(`^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)/[a-z0-9._-]+$` ✓).
**PR title**: `feat(browse): find and install packages published by your taps`.

### Suggested Work Units (`work-unit-commits`; conventional commits, **no `Co-Authored-By`, no AI attribution**)

RED and GREEN may be separate commits inside a unit (house precedent); tests never leave the unit whose
behaviour they verify.

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|---|
| **WU1** | The **four** deltas land **first** — PD6, TM5 and TM11 are narrowed before any line of code (**R2**) | PR 1 | N/A — artifacts only, no code | N/A — no behaviour changes | Revert the single artifact commit; the tree returns to `main` |
| **WU2** | `TapPackageSearch` + `TapSearchHit` in `BrewClient`, with **17 `unit` RED rows** — ps1–ps11, PD6 sc4, TM5 sc11, TM11 sc3 | PR 1 | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | N/A — a pure, total projection over two resident inventories; there is no runtime to exercise and **no launcher to inject** (that absence is itself asserted) | Delete the new source + test files and the fixture additions; nothing references them yet |
| **WU3** | The combined-turn latency measurement — ps12, over the shipped PS6 fixture **plus** a ~500-package tap inventory | PR 1 | `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'` | N/A — the measurement **is** the harness; p95 < 8 ms on the same turn | Delete the one test case and its fixture builder; no production line is theirs |
| **WU4** | `BrowseView` sectioning + `TapSearchSection.swift` + the `ContentView` argument + `TapSearchCompositionTests` + the DD-11a 3-line edit — ps13–ps16 | PR 1 | `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` | **Launch the app**, type a tap-published token in Browse, confirm the section title, position, row facts, install menu and the receipt detail on an installed unambiguous hit | Delete the new view + test files, restore the flat `List`, drop one `ContentView` argument, revert the DD-11a anchor |

**Parallel vs sequential.**

- **Sequential, hard dependencies**: **WU1 → everything** (**R2** — read narrowly PD6/TM5/TM11 bind
  only their own surfaces; read broadly they ban this change outright, and the m9 archive already cites
  PD6 as a blanket ban in three places. No code may land before the narrowing). **WU2 → WU3** (the
  latency test measures the type WU2 creates). **WU2 → WU4** (the section renders `[TapSearchHit]`, and
  every pinned string it must *not* contain has to exist in the projection first).
- **Parallelisable in principle**: **WU3 ∥ WU4** once WU2 is green — disjoint files
  (`Packages/CellarCore/Tests/…` vs `cellar/` + `cellarTests/`) and disjoint runners. **One writer,
  executed sequentially** — no parallel worktrees, no parallel branches.
- **Inside every unit**: RED before GREEN, `strict_tdd: true`. Never negotiable.
- **Rollback order** is the reverse — WU4 → WU3 → WU2 → WU1.
- **Bottleneck**: **WU4** — the only unit needing the app runner, the only one touching the shipped
  `PerPackageTrustCompositionTests`, and the only one whose assertions are absences in *two* files at
  once. It is the unit most likely to need a second session. **Secondary risk: WU3** — a p95 that
  misses is a design signal, not a task to retry with a looser ceiling (task 4.4).

## Phase 0: Preflight (sequential; no behaviour changes)

- [x] 0.1 Measure and record the green baseline; do not re-derive it later and do not assume the m10
      numbers still hold. Run `swift test --package-path Packages/CellarCore` and
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
      Count **distinct** passing test ids; `Executed 0 tests` is meaningless for Swift Testing bundles.
- [x] 0.2 Confirm every anchor the design pins is still where it says — a moved anchor is a deviation to
      **report, not absorb**: `TapProjection.swift` :25-30 (`TapPackageInstallState`) · :32-40
      (`TapPackage`, incl. `publishedName`/`displayName`) · :52-58 (`statusExplanation`, `nil` for
      `.installed`) · :82 (official-tap exclusion) · :93 (`thirdPartyTaps`) · :134-162 (`packages(for:installed:)`)
      · :208-211 (`bareToken`) · `PackageText.swift` :16-45 (`normalize` — separator on every
      non-alphanumeric run) · `BrowseView.swift` :59-78 (the flat `List(rows, selection:)`), :74-78
      (the `rows.isEmpty` overlay), :126 (`private struct EmptyResults`) · `ContentView.swift` :307-315
      (the `BrowseView(…)` call site) · `MutationMenu.swift` :32-40 (Install + Copy install command when
      `isInstalled == false`) · `InstalledFilterMode.swift` :54 (`installed == nil ⇒ isInstalled == false`),
      :62-65 and :99-107 (the `InstalledBrowse` closure-parameter precedent DD-1 mirrors) ·
      `PerPackageTrustCompositionTests.swift` :31-32 (the sorted-name anchor) and :186-201
      (`PerPackageTrustSources.views()`).
- [x] 0.3 `git checkout -b feat/m11-tap-search main`.
- [x] 0.4 **Collapse the forecast band.** `git log --oneline -- openspec/changes/m11-tap-search` and
      `git status --short openspec/changes/m11-tap-search`: record whether the **1,872** artifact lines
      already sit on `main` (⇒ only `tasks.md` + `verify-report.md` land in this PR, ~2,259–3,358 total)
      or are new to this branch (⇒ ~4,131–5,230, the corner that straddles the 5,000 ceiling). Record
      the answer; do not re-estimate it at task 6.6.

## Phase 1: WU1 — the four deltas land first (R2)

- [x] 1.1 Commit the SDD artifacts, **PD6's, TM5's and TM11's MODIFIED blocks included**, before any
      Swift file changes: `docs(sdd): record the m11-tap-search proposal, spec deltas, design and tasks`.
      **Acceptance**: `specs/package-detail/spec.md` binds PD6's prohibition to what the **catalog
      projection itself returns** and permits the **membership-only** catalog read;
      `specs/tap-management/spec.md` narrows TM5's catalog half and scopes TM11's exclusion list to tap
      management's **own** surface — so a section composed above the index neither satisfies nor
      violates any of the three.
- [x] 1.2 Confirm the delta arithmetic before moving on: `package-search` **1 ADDED / 16 scenarios** →
      8 req / 35 sc; `package-detail` **1 MODIFIED, 4 scenarios replacing 3** → 8 req / 32 sc;
      `tap-management` **2 MODIFIED, 11 replacing 10 and 3 replacing 2** → 13 req / 60 sc. A mismatch is
      a spec defect to report, not to patch here.
- [x] 1.3 Record the **marker drift** in the apply context (`specs/README.md:98-106`): `explore.md` and
      `proposal.md` call these requirements TM10/TM11; the file's markers are `<!-- TM11 -->` (`:532`)
      and `<!-- TM12 -->` (`:560`). The deltas use the **file's** markers. “TM11 untouched — no
      Untrusted badge” in the decision record means the main spec's **TM12**, and it stays untouched.

## Phase 2: WU2 — the projection, RED (ps1–ps11, PD6 sc4, TM5 sc11, TM11 sc3)

Runner: `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'`

- [x] 2.1 **Test support (not a behaviour).** Add the fixture shapes the RED rows need to
      `Packages/CellarCore/Tests/BrewClientTests/Fakes/` (extend the shipped tap/installed fixtures;
      shipped signatures stay source-compatible): a third-party tap publishing `widget`, `widget-cli`,
      `superwidget`; a tap publishing `gentle-ai`; **two** taps each publishing formula **and** cask
      `widget` (the total-order fixture); **two different taps publishing the same bare token, both
      installed** (the duplicate-`PackageID` ambiguity cause); a tap whose token the catalog also
      carries (`wget`); an **official** tap; the three install states (same-tap installed record ·
      withheld tap under an `untrusted` publishing tap · no installed record); and `.brewAbsent` /
      `.failed` tap states.
- [x] 2.2 **RED.** New file `Packages/CellarCore/Tests/BrewClientTests/TapPackageSearchTests.swift` ·
      `aTapPackageIsFoundByANonEmptyQuery`: query `widget` over `acme/tools` returns `widget`,
      `widget-cli`, `superwidget` in exactly that order — exact, then prefix, then substring — each
      reporting tap of origin `acme/tools` and its published qualified name. **RED because**
      `TapPackageSearch` does not exist. Add `theLadderConvergesWithTheCatalogIndexOnOneFixture` (the
      same fixture ranks identically under `PackageSearchIndex`'s classes) and
      `officialTapsNeverEnterTheSection` (**DD-5**, source is `TapProjection.thirdPartyTaps`). *(ps1)*
- [x] 2.3 **RED.** `aHyphenatedNameMatchesByTokenAtEveryRung`: `gentle-ai` normalises to `gentle ai`, so
      `ai` ⇒ `exactToken` (**not** substring), `gent` ⇒ `namePrefix`, `tle` ⇒ `nameSubstring` — three
      **distinct** ranks. Add `aTapNameQueryMatchesThroughThePublishedName`: `gentleman` matches only via
      the normalised `publishedName` and is **capped at `nameSubstring`** (**DD-3**), so a tap-name match
      never outranks a genuine bare-token hit. *(ps2)*
- [x] 2.4 **RED.** `theOrderIsTotalAndReproducible`: two taps × two kinds, all in one class, composed
      twice ⇒ `acme` formula, `bravo` formula, `acme` cask, `bravo` cask **both times** — bare token asc,
      then formula before cask, then tap name asc. No install count is read or faked (**DD-5**). *(ps3)*
- [x] 2.5 **RED — the row the design's table omits (reconciliation gap).**
      `aHitCarriesItsFiveFactsAndItsCopyAndNothingElse`: enumerating every member of `TapSearchHit` for a
      cask hit yields exactly kind, bare token, published name, tap of origin, install state, `stateCopy`,
      and `collisionNote` **only when colliding** — plus the projection-internal `id`, `mutationTarget`,
      `alsoInCatalog`, `rank`, `routableID`. **No** description, version, homepage, license, dependency
      list, install count, deprecation flag, disabled flag or size is **representable**, and no emitted
      value is `""`, `-`, `unknown` or any other placeholder standing for absence. *(ps4)*
- [x] 2.6 **RED.** `theKindFilterIsHonoured`: one formula and one cask both named `widget`, query
      restricted to `cask` ⇒ exactly one hit, kind `cask`; and `SearchFilters` gains **no** member for
      this source (PS4 — asserted against the shipped declared-filter set). *(ps5)*
- [x] 2.7 **RED.** `theSectionIsAbsentForAnEmptyOrWhitespaceQuery`: `""` and `"   "` ⇒ zero hits, nothing
      thrown, over a tap publishing forty packages. *(ps6)*
- [x] 2.8 **RED.** `absentOrFailedTapStateHidesTheSectionWithoutAnError`: `.brewAbsent` and, separately,
      a failed refresh ⇒ zero hits, **no error raised, no error state reported**, and the catalog results
      for the same query are byte-identical to the no-tap-inventory run. Exercised through
      `TapPackageSearch.isSectionVisible(query:outdatedOnly:tapState:)` (**DD-6**). *(ps7)*
- [x] 2.9 **RED.** `aCollidingHitIsShownAndIsNotRoutable`: catalog carries formula `wget`, `acme/tools`
      publishes `acme/tools/wget` ⇒ the hit is **present**, `alsoInCatalog == true`, `routableID == nil`,
      its `RowID` differs from the catalog row's identity, and `mutationTarget` is the **bare**
      `PackageID(kind: .formula, name: "wget")`. Add `everyMutationTargetIsBare` (no `/` in any emitted
      target, PM10) and `theCollisionNoteIsPresentExactlyWhenItIsTrue` — `collisionNote` is non-nil
      **exactly when** `alsoInCatalog`, carrying byte-for-byte
      `Also in the catalog. Homebrew installs the catalog package.` *(ps8)*
- [x] 2.10 **RED.** `theThreeInstallStatesCarryTheirExactCopy`: the three states stay **distinct values**,
      never collapsed into two, and `stateCopy` is byte-exactly `Installed.`,
      `Installed. Homebrew withholds its tap while this tap is untrusted.` and `Not installed.`
      respectively. **RED because** `TapPackage.statusExplanation` returns `nil` for `.installed`
      (`TapProjection.swift:52-58`) — this row is the guard on that trap (**DD-9**). *(ps9)*
- [x] 2.11 **RED.** `anAmbiguousInstalledHitIsNotRoutable` — **both causes**: (a) an installed hit whose
      bare token the catalog also carries for the same kind; (b) two installed hits from **different**
      taps carrying the same `PackageID` (`twoTapsPublishingOneNameAreBothUnroutable`). Each reports
      `routableID == nil`, stays **presented** and stays **installable** with the bare target. Add
      `anInstalledUnambiguousHitIsRoutable` (`routableID == mutationTarget`, the exact `PackageID`
      handoff, `openspec/specs/tap-management/spec.md:133-138`) and `aNotInstalledHitIsNeverRoutable`.
      *(ps10, DD-4)*
- [x] 2.12 **RED.** `hideInstalledSubtractsFromTheSection` and `theOutdatedChipHidesTheSection`: with one
      installed and one not-installed match, `hideInstalled: true` ⇒ only the not-installed hit;
      `outdatedOnly` ⇒ **no tap hit at all**, via `isSectionVisible`, **not** by filtering `hits(…)`
      (**DD-6**: a version-less hit filtered by outdatedness would emit zero hits and read as the false
      claim “your taps have nothing”). *(ps11)*
- [x] 2.13 **RED.** `theProjectionTakesNoLauncherAndNoCatalogStore`: the parameter surface of
      `init(inventory:installed:)` and `hits(query:kinds:hideInstalled:isInCatalog:)` admits **no**
      process launcher, **no** `CatalogStore` and **no** refresh handle — the catalog enters **only** as
      the `isInCatalog` membership predicate, which is a **parameter, never stored** (**DD-1**, mirroring
      `InstalledFilterMode.swift:62-65`). *(supports ps16 at the `unit` layer)*
- [x] 2.14 **RED.** `aComposedTapSearchLeavesTheIndexUnchanged`: with a **real** `PackageSearchIndex` over
      a snapshot that does not carry the tap package, composing hits leaves the snapshot, `search` and
      `package(_:)` **identical** to the no-tap-inventory run and still answering not-found, and **no
      `CatalogPackage` exists** for that id anywhere. *(PD6 sc4)*
- [x] 2.15 **RED.** `theTapInventoryFeedsASurfaceOutsideTapManagement`: the same resident inventory feeds
      the composed source with **zero** brew invocations recorded by a fake launcher, **no** refresh
      started or awaited, and **no** tap formula/cask source read. *(TM5 sc11)*
- [x] 2.16 **RED.** `aTapPackageFoundHereAddsNoTapManagementAction`: the enumerated tap-management action
      set is **unchanged** by this source — finding a tap package on the query surface adds no action to
      the Taps surface, and the projection constructs no `TapCommand`. *(TM11 sc3)*
- [x] 2.17 **Prove RED.** Run the focused command; 2.2–2.16 MUST fail, each for its stated reason. A
      green test here is a defect in the test.

## Phase 3: WU2 — the projection, GREEN

- [x] 3.1 **GREEN.** New file `Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift` —
      `public enum TapMatchRank: Int, Comparable, Sendable, CaseIterable { exactToken, namePrefix, nameSubstring }`
      and `public struct TapSearchHit: Sendable, Hashable, Identifiable` with
      `id: RowID { tapName, kind, name }`, `mutationTarget: PackageID`, `publishedName`, `displayName`,
      `tapName`, `state: TapPackageInstallState`, `stateCopy: String`, `alsoInCatalog: Bool`,
      `collisionNote: String?`, `rank: TapMatchRank`, `routableID: PackageID?` (**DD-1, DD-2**).
- [x] 3.2 **GREEN.** `public struct TapPackageSearch: Sendable` holding `inventory` + `installed`, with
      `init(inventory:installed:)`, `func hits(query:kinds:hideInstalled:isInCatalog:) -> [TapSearchHit]`
      and `static func isSectionVisible(query:outdatedOnly:tapState:) -> Bool`. Built from
      `TapProjection.thirdPartyTaps` (`:93`) and `TapProjection.packages(for:installed:)` (`:134-162`),
      reusing `bareToken` (`:208-211`) and `TapPackageInstallState` (`:25-30`). The `isInCatalog`
      predicate is a **parameter, never a stored closure** — a stored closure makes `Hashable`
      unrepresentable (**DD-1**).
- [x] 3.3 **GREEN, matching.** Rank over `PackageText.normalize` applied to **both** the bare token and
      the `publishedName`. `exactToken` = the normalised query equals the whole normalised string **or**
      one whole space-delimited token; `namePrefix` = whole-string **or** token prefix; otherwise
      `nameSubstring`. A hit matching **only** via `publishedName` is **capped at `nameSubstring`**
      (**DD-3**). Strongest class only; **no fourth class** — there is no description to scan.
- [x] 3.4 **GREEN, order and routing.** Sort by `(rank asc, normalised bare token asc, formula before
      cask, tapName asc)` — total. `routableID` is non-nil **iff** the hit is installed **and**
      `alsoInCatalog == false` **and** no other emitted hit shares its `PackageID` (**DD-4**).
- [x] 3.5 **GREEN, binding constraints** (each already asserted above, restated so no shortcut is taken):
      **every** user-visible string on this surface originates in this file; `TapPackage.statusExplanation`
      is **not** reused (**DD-9**); **nonisolated by module default**, no annotation, no `@unchecked`, no
      actor (**DD-12**); no `Process`, no `FileManager`, no store, no clock, no SwiftUI import, no
      `#available` (**DD-13**); nothing is pushed into `PackageSearchIndex` and `SearchFilters` gains no
      member.
- [x] 3.6 Focused command green **and** every shipped `SearchIndexTests` / `FilterTests` /
      `TapProjectionTests` case still green; commit WU2
      (`feat(search): compose tap-published packages above the catalog index`).

## Phase 4: WU3 — the combined-turn latency ceiling (ps12)

Runner: `swift test --package-path Packages/CellarCore --filter 'TapPackageSearchTests'`

- [ ] 4.1 **Fixture (not a behaviour).** Build a resident tap inventory of realistic size — **several
      taps publishing ≈500 packages in total**, mixed formulae and casks, deterministic — alongside the
      **shipped PS6 catalog fixture**, reused as-is rather than re-created.
- [ ] 4.2 **RED.** `theCombinedKeystrokeTurnStaysUnderTheCeiling`: **≥100** representative as-you-type
      queries of varying length run the **catalog query and the tap composition on the same turn**;
      the **p95** of that combined duration is **below 8 ms**. **RED because** `hits(…)` does not exist
      at authoring time. *(ps12)*
- [ ] 4.3 **Explicitly not a re-run of shipped PS6**, which never touches the tap inventory: this row
      measures the combined turn and must not replace, relax or re-baseline PS6's own scenario.
- [ ] 4.4 **The ceiling is not negotiable.** If p95 misses, the fix is the projection (allocation per
      keystroke, repeated normalisation, an O(n·m) scan) — **never** a larger ceiling, a smaller
      inventory, fewer queries or a p90. A miss that survives optimisation is a **design deviation to
      report**, not to absorb.
- [ ] 4.5 Focused command green; commit WU3
      (`test(search): pin the combined catalog and tap keystroke turn under 8 ms`).

## Phase 5: WU4 — the Browse surface (ps13–ps16)

Runner: `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`

> `cellar/` and `cellarTests/` are `PBXFileSystemSynchronizedRootGroup`s (`project.pbxproj` :46, :51),
> so both new files join their targets with a **0-line `project.pbxproj` diff**.

- [ ] 5.1 **RED.** New file `cellarTests/TapSearchCompositionTests.swift` ·
      `browseComposesTheTapSectionFromTheResidentStore`: `BrowseView.swift` contains a `taps` store
      property and builds `TapPackageSearch(` from it; `ContentView.swift` passes `taps: taps` at the
      `BrowseView(…)` call site (`:307-315`). **RED because** neither exists yet. *(ps13)*
- [ ] 5.2 **RED.** `theTapSectionIsTitledAndPositionedLast`: `TapSearchSection.swift` contains the
      section title **byte-exact** — `From your taps` — and `BrowseView.swift` places that section
      **after** the catalog `ForEach` inside a single `List(selection:)`. *(ps13)*
- [ ] 5.3 **RED.** `notInstalledTapRowsAreNotSelectable`: rows are tagged with `hit.routableID`, so a
      `nil` routable id yields no selectable tag; the not-installed and ambiguous cases are the same
      code path. *(ps13, ps14, DD-4)*
- [ ] 5.4 **RED.** `theSurfaceCopyLivesInTheProjectionNotTheView`: the four pinned strings —
      `Also in the catalog. Homebrew installs the catalog package.`, `Installed.`,
      `Installed. Homebrew withholds its tap while this tap is untrusted.`, `Not installed.` — are
      present in `TapPackageSearch.swift` and **absent** from `TapSearchSection.swift`, which renders
      `hit.stateCopy` and `hit.collisionNote` instead. *(ps15, PS8's copy-ownership clause)*
- [ ] 5.5 **RED.** `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge`: scanning **both**
      `TapSearchSection.swift` and the `BrowseView.swift` tap surface finds no `TrustGrantStore`, no
      `TrustGrantState`, no `TapProjection.trust(`, no `TapCommand`, no `"Untrusted"` and no `"Trust`
      literal; the install affordance is offered for **every** hit whatever the origin tap's trust
      state, through `MutationMenu` over
      `PackageEntry(installed: nil, catalog: nil, id: hit.mutationTarget)` — which renders exactly
      Install + Copy install command (`MutationMenu.swift:32-40`, via
      `InstalledFilterMode.swift:54`). *(ps15, PM10, TM12 gains no consumer)*
- [ ] 5.6 **RED.** `theReceiptDetailIsReachedWithNoNewRoutingBranch`: `PackageDetailView.swift` has a
      **zero-line diff** — no new branch, no tap import, no `TapSearchHit` reference — and selection
      stays `PackageID?`, so an unambiguous installed hit lands on the m10 receipt-backed detail through
      the **existing** resolution order. *(ps14, DD-4)*
- [ ] 5.7 **RED.** `neitherTapSearchFileReachesTheProcessLayer`: scanning **both** new/modified Browse
      files finds no brew-process reference, no `Process`, and no store refresh triggered by presenting
      the section; the composition takes only already-resident values, with no launcher dependency to
      inject. *(ps16)*
- [ ] 5.8 **RED.** `theSearchPromptStillCountsCatalogRecordsOnly`: `PaneSearchField`'s prompt still reads
      `Search \(catalog.packageCount.formatted()) packages…` — unchanged, tap hits uncounted
      (`BrowseView.swift:45-48`). And `theEmptyStateYieldsToTapHits`: the overlay condition becomes
      `rows.isEmpty && tapHits.isEmpty`, so a query matching only tap packages shows the section rather
      than `EmptyResults` (`:74-78`). *(ps13, PS8's prompt clause, R5)*
- [ ] 5.9 **RED — DD-11a, the one edit to a shipped guard.** `cellarTests/PerPackageTrustCompositionTests.swift`:
      add `"cellar/Browse/BrowseView.swift"` and `"cellar/Browse/TapSearchSection.swift"` to
      `PerPackageTrustSources.views()` (`:186-201`) and extend the sorted-name anchor (`:31-32`) to
      `["BrowseView.swift", "PackageDetailView+Receipt.swift", "PackageDetailView.swift", "TapDetailView.swift", "TapSearchSection.swift", "TapsListView.swift"]`
      — ASCII order: `B` first, `+` (U+002B) before `.` (U+002E), `TapD` < `TapS` < `Taps`. **Exactly 3
      lines.** Both new files then inherit the shipped `for source in sources` guards (`:60-75`): no
      `"Trusted individually"`, no `trusted individually`, no locally derived section case. Do **not**
      add a private second scanner in the new test file. *(ps15, R3)*
- [ ] 5.10 **Prove RED** (5.1–5.9 all fail, each for its stated reason), then **GREEN**: new file
      `cellar/Browse/TapSearchSection.swift` — the row is name, `KindTag(kind:)`, tap of origin,
      `hit.stateCopy`, `hit.collisionNote`, and `MutationMenu` over the bare-target `PackageEntry`
      (**DD-9**). No copy literal of its own beyond the section title.
- [ ] 5.11 **GREEN.** `cellar/Browse/BrowseView.swift` — the flat `List(rows, selection: $selection)`
      (`:59-78`) becomes `List(selection: $selection) { ForEach(rows) { … }; TapSearchSection(…) }`. The
      catalog rows move into a **bare `ForEach` with no header** (**DD-8**); the row builder, `.tag(entry.id)`
      and `.themedListSelection` move **byte-unchanged**. `tapHits` is built **synchronously in `body`** —
      no `Task`, no `.task {}`, no `await` (**DD-12**) — gated by `TapPackageSearch.isSectionVisible(…)`.
      **No `private` is relaxed anywhere** (**DD-10**, unlike m10's DD-9): `EmptyResults` stays private.
- [ ] 5.12 **GREEN.** `cellar/ContentView.swift:307-315` — add **one** argument, `taps: taps`. Nothing
      else in that file changes; the store is already wired.
- [ ] 5.13 Runner green — the Phase 0 baseline **plus** the new composition cases, and
      `PerPackageTrustCompositionTests` **both** tests still green with only the 3-line edit. Commit WU4
      (`feat(browse): show packages published by your taps below the catalog results`).

## Phase 6: Verification and bindings

- [ ] 6.1 Full core suite: `swift test --package-path Packages/CellarCore` → the Phase 0 baseline **plus**
      every new case, **0 failures**. Assert counts, never a bare success line.
- [ ] 6.2 App target — **use the SCOPED runner**:
      `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`
      → baseline plus the new composition cases, 0 failures. **The full `-scheme cellar` runner is known
      red on `main` @ 5a0860b** from two **pre-existing** `cellarUITests` Taps failures
      (`cellarUITests.swift:209`, `:231`), tracked for a separate PR — it is **not** the gate for this
      change, and a red full-scheme run caused by those two cases is **not** a regression of m11.
      `cellarUITests` gains **no** new test and has a zero-line diff on this branch.
- [ ] 6.3 **Bindings proof.**
      `git diff --stat main -- cellar.xcodeproj/project.pbxproj openspec/specs/ Packages/CellarCore/Sources/Catalog/PackageSearchIndex.swift Packages/CellarCore/Sources/BrewClient/MutationCommand.swift Packages/CellarCore/Sources/BrewClient/TapCommand.swift Packages/CellarCore/Sources/BrewClient/TapProjection.swift cellar/Browse/PackageDetailView.swift scripts/ .github/workflows/`
      → **empty output**. A non-zero `project.pbxproj` diff means the file-system-synchronized group
      assumption broke; a non-zero `openspec/specs/` diff means someone promoted a delta early (that is
      `sdd-archive`'s job); a non-zero `PackageSearchIndex.swift` diff means the source was pushed
      **into** the index (Approach C, which PD6 now forbids outright); a non-zero `MutationCommand.swift`
      diff means a new argv family was invented (PM10). Any of them is reported before merge, never
      absorbed.
- [ ] 6.4 **Regression guards that must never have moved**: `PerPackageTrustCompositionTests` (both
      tests, 3-line edit only), `TapProjectionTests`, `TapShippingProofTests`, `MutationCommandTests`,
      `MutationCommandTargetTests`, `SearchIndexTests`, `FilterTests`, `InstalledFilterCompositionTests`,
      `ReceiptDetailCompositionTests`, `PackageGraphTests`.
- [ ] 6.5 **Spec-delta self-check before verify**: re-count the four deltas against task 1.2's numbers;
      confirm PD6's three, TM5's ten and TM11's two shipped scenarios are **byte-identical** to
      `openspec/specs/{package-detail,tap-management}/spec.md` (`git diff --no-index` on the extracted
      blocks); confirm every one of the **19** new scenarios has a task above naming it — **including
      ps4, whose RED row this artifact added** — and that **no** delta introduces a new verification
      class.
- [ ] 6.6 `git diff --stat main` for the whole branch — record the authored total **split into the
      code+test bucket and the artifact bucket**, and compare each against its own forecast (1,509–2,608
      and the band task 0.4 fixed). If the total exceeds 5,000, record it as information for the next
      forecast, not as a mid-flight re-plan.
- [ ] 6.7 **Delivery — one PR** (`single-pr`, forecast Medium against 5,000; no `size:exception`, no
      chain). The body states up front: (a) the section **adds no brew invocation and no store** — it
      composes an inventory already resident, and PS6's 8 ms ceiling is measured on the combined turn;
      (b) it **reads no trust state and presents no badge or control** — an untrusted tap surfaces
      through the shipped typed refusal and its Trust recovery, never a pre-launch block (PM10);
      (c) **nothing enters the catalog** — no snapshot record, no index entry, one membership-only read;
      (d) **ambiguous and not-installed rows are deliberately inert** — the catalog-first resolution
      would otherwise open a different package than the row chosen; and (e) the **full-scheme** runner is
      red on `main` for two pre-existing UI reasons, so the scoped runners are the gate (task 6.2).

## Phase 7: Archive obligations (recorded now so they are not re-derived at `sdd-archive`)

- [ ] 7.1 Promote the ADDED block as **PS8**, appended after `package-search`'s current last requirement
      (→ 8 req / 35 sc; PS1–PS7 byte-identical). Promote PD6, TM5 and TM11 as **whole-block
      replacements** (→ 8 req / 32 sc and 13 req / 60 sc). **Promote no verification-class table** —
      none of the three main specs carries one (precedent at
      `openspec/specs/installed-inventory/spec.md:1122-1184`); only the inline `- Verification:` lines
      promote. `package-search` and `package-detail` carry **no `<!-- PS# -->` / `<!-- PD# -->` markers**;
      match those blocks by heading.
- [ ] 7.2 Record in provenance: **no `package-mutation` delta** — PM10 was **activated, not amended**,
      and its argv enumeration gains no family; **no `installed-inventory` delta** — II7/II8/II15
      activated; **no `package-trust` delta** — nothing on this surface reads a grant; **TM12 untouched**
      — no Untrusted badge in Browse. Record the **TM10→TM11 / TM11→TM12 marker drift** once more, since
      `explore.md` and `proposal.md` still carry the pre-promotion ordinals.
- [ ] 7.3 Record the deferrals, so a future contributor does not “complete the grid”: a **name-only
      detail pane for a not-installed tap hit** is a clearly scoped follow-up, blocked today by TM5's
      unconditional tap-source-read ban; **a merged ranked list** stays rejected (PS3's order is broken
      by 365-day install count, which a tap package does not have); **index ingestion** (Approach C) is
      now explicitly forbidden by PD6's modified text; **`SearchFilters` gains no member** for this
      source, by construction.
- [ ] 7.4 Record which **PRD.md milestone** this closes (**M11**), and note that the two pre-existing
      `cellarUITests` Taps failures (`:209`, `:231`) remain open and are **not** m11's to close.
